# Bringing the network unit to `newimpl` — a survey

What `old/verilog/rtl/net_unit.v` needs, what this tree has, what is missing,
what must be decided before the first line is copied, and in what order. The
audit of 2026-09-24 found most of this; this is the porting view of it, with
the file and line for each claim.

---

## 1. What is being ported

`net_unit.v` (418 lines) is the pulse flood off the marker — `network.md` §3,
`common-control.md` §2.2–2.3: origin seize, transit forward, hub resolvers,
own-code, the origin guard, and the `CLAIM` writes. The marker consumes key
`1`, restarts the register and raises `flood_go`; the unit owns the call from
there. Around it in the old tree, and part of the same port:

| file | lines | what it is |
|---|---|---|
| `rtl/net_unit.v` | 418 | the unit |
| `rtl/marker.v` | 878 | the class marker, with the unit's marker-side interface at `:79-92` and the burst drain at `:483-490` |
| `rtl/mini_core.v` | 321 | the mini-marker with `HAS_NET` / `TRUNK_MASK` hooks — the minimal+network build's marker |
| `rtl/monitor.v` | 197 | the seeker pool on a trunk block; claims go to the unit |
| `rtl/mf8_trunk_card.v` | 154 | six sockets of a block made into a tie trunk |
| `tb/net_site.v`, `mini_net_site.v`, `trunk_site.v`, `bitpath.v`, `line_delay.v` | — | the plant every network bench builds on |
| `tb/tb_net tb_chain tb_hub tb_ring tb_pool tb_priority tb_word tb_groups tb_stress tb_traffic tb_erlang` | — | the network suite. **`hub` and `ring` are red at HEAD** |

---

## 2. The unit's interface, wire by wire, against this tree

`net_unit.v:24-71`. "Same" means the signal exists here under a different
name; "gap" means it does not exist.

| the unit wants | from | in `newimpl` | verdict |
|---|---|---|---|
| `clk`, `rst_n`, `tick_1k` | clock card | `exch.tick_1k` | same |
| `visit`, `p_valid` | the marker's scan-steered probe | `probe.fresh` | same, **one signal for two**: there is no `pv` because no visit is ever disturbed. The five sites that gate on `visit && p_valid` (`:221 :235 :271 :304 :400`) become `p_fresh` |
| `p_port`, `p_m`, `p_busy` | the probe | `probe.port_q`, `.m`, `.busy` | same |
| **`p_word`** (16 bits, with every sample) | the probe, off block-steered `PB` | **nothing.** The word is `/HW`, marker-addressed: a pointing word, then 16 frames at 64 kHz, 250 µs a port | **gap — the one that changes the design.** §3.3 |
| `flood_go`, `flood_caller` | the marker: this register consumed key `1` | `mini_marker` has no key handling, no `HAS_NET`, no flood | gap — the marker side, §4 |
| `reg_gone`, `reg_brk`, `reg_ndig`, `reg_digits` | the register pool, `NREG` deep | `pulse_reg` has all four as levels (`gone`, `brk`, `ndig`, `digits`) but it lives *inside* `mini_marker` and they are not on its boundary; `NREG = 1` | gap — §5 |
| `restart`, `go_local`, `done`, `nogo` | to the marker | `mini_marker` has `r_restart` internally and no inputs for the other three | gap — the marker side, §4 |
| `mon_claim`, `mon_port`, `mon_ack` | a monitor pool | no monitor | gap — §6 |
| `att_req`, `att_port` | to the marker: give a register this trunk as a line, `CLAIM` on | no path | gap — the marker side, §4 |
| `nw`, `wdst`, `wsrc`, `wbsy`, `wclm`, `wev` (124 conductors) | into the marker's queue, drained next cycle | cable B has **one master** (`top_min.v:80`); `ctl_write`'s `g`, `strobe`, `clm` are tied off (`mini_marker.v:127-128`); the queue is 13 bits (`:131`) | **gap — the structural one.** §3.1 |
| `any_claimed`, `dirs_held`, `fan_legs`, `res_used` | bench diagnostics | — | carry as-is |

Parameters (`net_unit.v:11-22`), judged by *straps and stuffing, never
features*:

| parameter | verdict |
|---|---|
| `NREG`, `NRES` | how many registers, how many resolvers are fitted — stuffing. Keep |
| `OWN_E`, `OWN_B` | the exchange's own code — a strap. Keep |
| `STRAP_N[3:0]` | the ring jumper, one a direction (`network.md` §3.3) — a strap. Keep |
| `T_GUARD`, `T_CLAIM` | RC constants — stuffing. Keep, and add **`T_KEY = 5000`** (§7) |
| `TRUNK_MASK`, `TRUNK_DIR` | the jumpered mask a marker with no word uses — straps. Keep; they become the *primary* class source (§3.3) |
| `NOGO` | **dead.** Its only occurrence is its declaration (`:16`); the refusal is written by the marker (`marker.v:772`). Delete, and say so in `common-control.md` §2.3 |

---

## 3. Four interfaces to settle before the first line is copied

These are `README.md` §7's four, made concrete for the unit.

### 3.1 Cable B needs an arbiter, and the unit is its third master

`common-control.md` §2.2 says it in so many words: the unit *"is another
master of cable B for the writes it owns (seize, forward, CLAIM, drop), the
way the console is. Until that third master is drawn, the RTL marker drains a
burst of writes the unit queued"*. The burst is `net_unit.v:57-62` — `nw`,
`wdst[47:0]`, `wsrc[47:0]`, `wbsy`, `wclm`, `wev` — and the drain is
`marker.v:483-490`. The whole unit port list at `NREG = 2, NRES = 1` is 245
conductors. That is not a ribbon between two cards; it is one module drawn
across two.

**The shape to write it into.** One `ctl_queue.v`, instantiated by every
master: depth a parameter, entry `{G, CLM, BSY, SRC, DST}` (15 bits,
`marker.v:275`'s word — `mini_marker`'s is 13, `:131`), the blocking-tail
`push` with its waiver and the comment that explains it (`mini_marker.v:143-153`
— the part that must not be re-typed), the drain (`:171-177`), and its own
`ctl_write`. `push_ev`'s policy comes in as a parameter — events are the only
way `EV_GLARE` (`net_unit.v:310`) and `EV_NOTRUNK` (`:339`) leave the unit,
and the drop-when-nearly-full rule (`marker.v:322`) is why an event never
delays a call. Each master drives `sdata/sclk/wr` behind its own `oe` and
yields *between words*, as the console did (`marker.v:571-575`); with two
requesters the no-grant scheme breaks, so the request line gets a fixed rank
— console over unit over marker — one conductor each on the 16-way, which has
the two spares (`README.md` §1). The wire-OR lives **above `exch`**, which
takes one `sdata/sclk/wr` triple and needs no change.

What this deletes: `marker.v`'s `wq_ovf` / `EV_WQOVF` machinery (`:310 :143
:581-584`), which exists only because two units share one queue.

### 3.2 The sample record: `p_fresh`, and the pass boundary

Five sites become `p_fresh` (§2). The hunt bracket changes shape: the old unit
watches for port 63 twice (`net_unit.v:222-230`, `hunt_arm → hunt_run →
hunt_done`); this tree has the boundary as a conductor, `pass_stb`, and
`pass_stb` **is** `tick_1k`. Three flags collapse to one `hunting`.

**The one-tick trap.** `pass_stb` fires at the frame edge with `scan == 0`;
`probe` publishes the turn that just ended at the same edge, so **port 63's
`fresh` and `pass_stb` coincide**. Write the close after the accumulate in
the same block (nonblocking, so the accumulate reads the old state), or close
on `p_fresh && p_port == 63` and never look at `pass_stb` in the hunt at all.
Get it backwards and port 63 — a trunk at 77 — is never a candidate, silently.

What ports **unchanged**: `hunt_busy` / `hunt_owner` (`:119-120 :329-336`).
That is "one scanner, `NREG` callers", and the fold did not give the exchange
a second scanner.

### 3.3 The card word is not a field of the sample any more

The old unit decodes class, direction and glare out of `p_word` on *every*
visit for *every* port during a hunt pass (`net_unit.v:79-96`). Here the word
is `/HW`: the marker points, one card answers, 250 µs. A pass-wide survey by
pointing is 64 × 250 µs = 16 ms of cable B to cover a 1 ms pass. That is not
a porting detail; it is the interface decision.

Two paths exist, and the unit already has both:

- **The strap path, primary.** `TRUNK_MASK` / `TRUNK_DIR` (`net_unit.v:20-22`)
  — *"Mini-marker has no word: these ports are trunks, 2 bits of direction
  each"* — and `is_trunk` / `p_dir` already fall back to them (`:92-94`).
  `common-control.md` §2.4: *"A one-direction bring-up hunts by a jumpered
  port mask, not by the word."* This is the MINIMAL+network build, and it
  needs no `/HW` at all.
- **The word path, MAXIMAL.** The marker owns the point-read on `/HW` — it
  is the only cable-B master that can point — and hands the unit a *result*
  for one named port (`class`, `dir`, `g`, `word_valid`), not a field on every
  sample. `word_valid` is a separate validity from `p_fresh`: the word is
  still `/BLK`-selected and only meaningful in a quiet octet after a pointing
  word. One `visit` for both is the bug `probe_dirty` was.

**The trap on `/HW`.** It idles high, so a pointed socket with **no card**
reads all ones — and all ones is `p_plain` (`net_unit.v:80`), which the unit
classes as `C_LINE`. An empty socket reads as a *line*. The old tree had the
same failure in the opposite direction (`option-word-rev2.md` §2's `FF`
secondary reading *unconditional*, live at `marker.v:185`). Whatever owns the
`/HW` read must treat *no drain on any of sixteen frames* as unequipped, and
pair every read with the `BUSY` it already has off `/HB`. This is the first
lamp to add to the debugger once the word path exists.

### 3.4 The queue carries `G`, `CLM` and the event

`ctl_write.v` already has `strobe`, `g` and `clm` and `tb_ctl` exercises all
three; the only instantiation ties them off (`mini_marker.v:127-128`). The
unit needs all three: `CLM` on every claim write (`net_unit.v:310 :394`), `G`
clear for the two event words, and `strobe` clear for the pointing word §3.3
needs. `common-control.md` §2.2: *"`CLAIM` sticks until release … The marker
keeps the bit on every later write to that port"* — so `mini_marker` cannot
stay as it is even in the minimal+network build.

---

## 4. The marker side

`common-control.md` §2.2 is the contract. `mini_marker.v` meets none of the
network half of it, and `mini_core.v` (the old minimal marker with the hooks)
is the source for what it must grow:

| the unit needs the marker to | old source | `mini_marker` today |
|---|---|---|
| consume key `1` at once, restart, drop dial tone, raise `flood_go` (with a `HAS_NET` jumper; without it `1` is highway 1) | `marker.v:655-660`, `mini_core.v` | dials `1` as highway 1, always |
| **never treat a trunk's M as a call request** — *"Leave this as `M · /BUSY` and a flood seizes a register at every hop"* | `is_trunk` from the word or the mask | `S_IDLE` seizes on `p_m && !p_busy` for any port (`mini_marker.v:197`) |
| take `restart` / `local` / `done` / `nogo` from the unit in `S_COLLECT` | `marker.v:688-697` | no inputs |
| take `att_req` + port: give a register the trunk as a line, `CLAIM` on | `marker.v:757-772` | no path |
| keep `CLAIM` on every later write to a claimed port | `marker.v` | `clm` tied to 0 |
| accept `/HUNT_INH` with nothing driving it | specified `common-control.md` §2.4, **implemented nowhere** | absent — a defect about to be copied |

Two ways to get there. (a) Grow `mini_marker` by exactly this list, with a
`HAS_NET` jumper and `TRUNK_MASK` — the minimal+network build `mini_net_site`
ran. (b) Write the class marker (`marker.v`'s port) and leave `mini_marker`
minimal. (a) is smaller and is the bring-up path; (b) is `README.md` §7's
first item anyway. Either way the tap changes: `mini_marker` re-points its
one probe onto `called` during `S_PROBE` (`:75-76`), so a unit watching the
tap loses the sweep exactly when the marker is busiest. **Give the unit its
own `probe`** — one '688 and half a '74 — as `pulse_reg` already does, and
stop widening the tap.

---

## 5. The register: a pool the unit can tap

The unit taps `digits`, `N`, `brk`, `gone` and pulses `restart`
(`common-control.md` §2.1). Those are `pulse_reg`'s ports already, but the
register is instantiated inside `mini_marker` and none of them cross its
boundary. Two options: bring the ribbon out through `mini_marker` (adds
4 + `NREG` × 20 conductors to its port list), or instantiate the register(s)
**beside** the marker at the site — which is what the maximal build does
(`pulse_reg.v:11-13`: *"in the maximal build the same module is a pool member
on its own card"*) and what `common-control.md` §2.1 draws. Beside is right.

While it is open: the ribbon is missing `attach_src` / `src`, the held-party
field `register.md` §6.1 defers and `marker.v:49 :53` consumes for operator
transfer. Add them tied off now; retrofitting them into a pool later touches
every member.

The old timer bug is already fixed here (`pulse_reg.v:111`), and the unit's
`reg_gone` release at `net_unit.v:318` will now fire at 10 s from the *last
digit*, which is what `marker.md` §6 meant.

---

## 6. The monitor

`monitor.v` wants, per trunk block: `m[7:0]` direct, `busy[7:0]`, `oct_stb`,
`chan_mask`, and the claim handshake (`monitor.v:47-58`). This tree has the
inputs: `a_tx[63:0]` at the sockets is M direct, `port_busy[63:0]` is
exported *for a monitor* (`exch.v:72-73`), `oct_stb` is on cable A. So the
plumbing exists. Three things do not port:

- **The seizure rule's third term is timed against a visit that no longer
  exists.** `monitor.v:31-38` argues from *"this scanner covers eight slots
  while the marker's covers sixty-four ports: the marker reaches an incoming
  seizure first about one time in eight"*. The marker now reaches every port
  once a millisecond, and BUSY comes off `/HB` at the same instant as M. Which
  "last visit" the rule means — the monitor's 8 kHz octet or the plane's 1 ms
  pass — has to be re-derived, not re-typed.
- **`monitor.md` §2's `done` row is wrong** (`:52`: freed when the trunk
  releases) against §3.4, §4, §6 and the code (`monitor.v:135-141`: freed by
  the ack). Fix the document *before* porting from a reading of it.
- **It has no card-word input** though `monitor.md` §4 and §6 specify and
  bill one; `chan_mask` is a strap in no document. Under §3.3 the strap is
  the primary path anyway — write it into `monitor.md` and stop billing the
  '164.

---

## 7. Defects in the source that must not come with it

| defect | where | what to write instead |
|---|---|---|
| **`network.md` §4's 5 s no-`b` rule is in no RTL.** `N_NET` (`net_unit.v:354-371`) waits on digit counts alone; the trunks go only at `reg_gone` (`:318`), i.e. the register's own timeout — the outcome the rule exists to prevent. `sim/exch.py:2105` has `FLOOD_TIMEOUT = 5000.0` | `net_unit.v` | a third parameter `T_KEY = 5000`, armed on entry to `N_NET`; at expiry with `!f2[r]`: `drop_trunk(r); nogo[r] <= 1; nst[r] <= N_IDLE`. It **cannot reuse `tmr[r]`**: `:348` zeroes it on entry but the guard owns it and stops it when `guarding` clears. `common-control.md:105` lists four `nogo` causes and needs a fifth |
| `NOGO` is dead | `net_unit.v:16` | delete; the marker writes the refusal |
| the second dialled digit gets no service-digit test in `marker.v` (`:685`) — `net_unit.v:359-361` and `monitor.v:165` *do* test it | the marker, not the unit | settle `protocol.md:190` against `nano-marker.md:80` before the marker is rewritten; the unit is already right |
| `mf8_decoder`'s carrier timeout is 3 cells where seven places say 2 | `old/verilog/rtl/mf8_decoder.v:26` | already fixed: `dm_rx.v` is 2 cells. The trunk card instantiates `dm_rx #(.CELL(8))` |
| `mf8_trunk_card` has no `/ANS` output, so it cannot tie the six low as `extensions.md` §2.1 requires; the old tree carried the fact in a hand-maintained `PORT_RINGS` literal — the deaf-hub bug `old/verilog/README.md:372` records | `mf8_trunk_card.v` | `/ANS` is a pin here (`port.v:137`). The card drives `ans_n = 0` on its six channel sockets |
| `MUTE_BLK` is generated and left open at all three instantiations | `mf8_trunk_card.v:91`, `net_site.v:209` | `port.v:59` already takes `mute_blk`; wire it, and the word path with it (a muted trunk must read unequipped, not be offered by `TRUNK_MASK`) |
| the `FF`-secondary reads unconditional | `marker.v:185 :207` | §3.3's `/HW` rule: silence is unequipped, and pair the read with `/HB` |

---

## 8. The trunk card on the socket

`mf8_trunk_card.v` is not a card in one socket; it is a **block adapter**
that occupies six (`:44-51`: `port_c_rx[7:0]` … `port_word[7:0]`, channels at
slots 1–3 and 5–7). The socket abstraction (`STYLE.md` §1, `cvsd_line_card.v`)
is one card, one port list. The adapter form is that list **eight times**,
as `[7:0]` vectors — plus the block-header commons it is the only card to
drive: `mute_blk`, and the clocks it takes from cable A rather than the
socket (`slot`, `tick`, `frame_stb`, `tx_oct`). Write it as
`mf8_block_adapter.v` with the socket list vectorised, and let a site place
it on a block rather than a slot. Its receiver is `dm_rx` at `CELL = 8`; its
framer and encoder port from `mf8_framer.v` / `mf8_encoder.v` unchanged.

---

## 9. The benches

None of the eleven port as they stand: every one instantiates `exch_top` by
the old port map through one of seven site wrappers, and the wrappers
re-type a fifty-line plant each. What is needed first is **one `site`**
for this tree — the `tb/plant.v` of the audit — wrapping `exch`, a
`CARD[p*8+s]` type code with a generate that instantiates the right card
model per socket (`cvsd_line_card` for a phone, a block adapter for a trunk
block), the marker, the register pool beside it, the unit, and the monitors.
`bitpath.v` and `line_delay.v` (the trunk between two sites) port unchanged.

Then in this order, because each is the plant for the next:

1. `tb_net` — two sites on one link, the origin flood (`network.md` §3.1).
2. `tb_chain` — three, the transit forward.
3. `tb_pool`, `tb_priority`, `tb_word` — the register pool and the word path.
4. `tb_hub`, `tb_ring` — **both red at HEAD**; the 5 s timer (§7) is the
   first thing to check when they come up.
5. `tb_stress`, `tb_traffic`, `tb_erlang` — the load suite, against
   `sim/exch.py traffic` as before.

`old/verilog/README.md`'s network results (the 9 ms pass, the 72 visits, the
hub's 40-of-48 high-water) were measured against a serialiser running four
times too fast (`ctl_write.v:52`) and against a `ring-open` target that never
took the jumper out (`Makefile:212`). Take none of them as a baseline;
re-measure.

---

## 10. Order of work

1. **Documents that must be right before porting from them**: `monitor.md`
   §2's `done` row; `rtl.md` §3's "still unbuilt" list (the unit, the
   resolvers and the ring *are* built); `common-control.md` §2.3's `nogo`
   causes; and `exchange/folded-a.md`, without which the unit is ported
   against a specification of the tree being deleted.
2. **`ctl_queue.v`** and the cable-B arbiter above `exch`; `mini_marker`'s
   queue to 15 bits; `g`/`strobe`/`clm` live.
3. **Decide §3.3**: strap-primary for the bring-up; the marker-owned `/HW`
   read with `word_valid` for MAXIMAL. Add the empty-socket lamp to the
   debugger when the word path exists.
4. **The register beside the marker**, with `attach_src`/`src` tied off.
5. **The `site`**, the socket-vectorised block adapter, `dm_rx` at `CELL = 8`.
6. **`net_unit.v`**: five `p_fresh` substitutions, the pass boundary with
   §3.2's ordering, `T_KEY`, `NOGO` gone, its own `probe`, its own queue.
7. **The marker side** (§4), as `mini_marker` + `HAS_NET` first.
8. **The monitor**, after its visit rule is re-derived.
9. **`tb_net`, `tb_chain`**; then the rest of §9.
