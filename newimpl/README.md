# `newimpl` — the exchange in Verilog, rebuilt around the folded A plane

`verilog/` is the exchange of the `exchange/` and `common/` documents as they
stood. This is a clean start around one change: **`HA[0..7]` — eight
totem-pole A highways at 512 kbps, commutated by `SLOT` at each block — are
replaced by scanner-addressed open-collector conductors at 64 kbps: `/HA`
carries M, `/HB` carries `BUSY`, and `/HW` carries the card option word.**

Everything else follows from that.

> **`PB` is gone.** With `BUSY` on its own scanned wire and the option word on
> a marker-addressed one, nothing in the exchange is block-steered any more,
> and `/BLK` survives only to select which card answers on `/HW`.

> **Status: measured in simulation, both simulators, 103 checks.** No gate
> delays, so this cannot see `fabric.md` §3.2's hazard or confirm §4's
> nanoseconds. Nothing has been drawn and nothing has been on a bench. The
> 4.7 kΩ pull-up on `/HA` is the one new electrical number and it has not been
> analysed — see *What is not settled*.

---

## 1. The change, entire

| | |
|---|---|
| bit rate | **64 kHz** — one bit a 64 kHz frame, the `TX_CLK` period |
| a pass | **64 bit-times**: in bit-time *p*, port *p* drives **both** wires = **1 ms** |
| per-port refresh | **1 kHz** |
| capacity | **full.** Nothing else rides either wire |
| address | `SCAN[5:0]` — plain 0..63, the port number and nothing else |
| polarity | **idle HIGH.** One 4.7 kΩ pull-up each at the clock card, 64 open drains each |

The second conductor is what removes the phase bit. One bit-time carries M
*and* `BUSY` **of the same port**, so a reader never holds half a sample across
a frame edge and cannot pair one port's hook with its neighbour's `BUSY` — the
failure the interleaved single wire would produce if `FILL` and `SCAN[0]` were
ever inverted against each other.

It also doubles the margin that decided the fold. `register.md` §3.1's measured
worst case, an 18 ms break at 20 pps, was nine samples against a four-sample
`HIT` window at 2 ms; it is **eighteen against eight** at 1 ms.

### The card option word: `/HW`

`/HW` is a third wired-OR conductor and the same part, but it is **not**
scanned. The marker points at a port by leaving a word in the blocks' shift
registers whose `DST` names it, and that one card drives `/HW` at 64 kHz, a bit
a frame — **250 µs for a whole sixteen-bit word.** Nothing continuous depends
on it, so the scanner never waits for it and a word in flight cannot disturb a
supervision sample. That is the whole reason the word is not on the scan.

> `/HW` idles HIGH like the other two, so a pointed port that is empty or on an
> unfitted block reads all ones — and `extensions.md` §2.2 calls all ones
> *unconditional*. **The marker must treat a silent sixteen frames as
> unequipped, not as `FF`.** This is `option-word-rev2.md` §2's fails-open bug,
> still live in the old tree, and the pull-up makes it reachable here.

`HC[0..7]` at 512 kbps are untouched — eight slots a frame, 64 kbps a port,
`SLOT[2:0]` on every commutator. Voice is unaffected; only supervision slows.

### Why it is worth doing

Today the marker's probe reads `BUSY` and the card word off the block-steered
`PB[1:0]`, and steering `/BLK` costs a full 125 µs visit. So a disturbed visit
must be *repeated*; `ADVANCE` exists only so a listener can de-duplicate; and
`rtl.md` records a livelock and a premature hunt termination that came out of
it. Give M and `BUSY` a scanned wire each and nothing continuous needs `/BLK` —

**the scanner has no enable input at all.** `SCAN[5:0]` is six stages of the
clock card's own divider, brought out on six pins. There is no `pv`, no
`p_valid`, no `probe_dirty`, no re-point and no repeated visit, because there
is nothing in the path that could ask for one. A port the marker cannot take
comes round again 1 ms later.

**A pass is exactly the `TICK` period.** 64 ports × 64 master ticks is 4096, so
the pass boundary and `TICK` are one edge and one conductor — `SCAN[5:0]` are
the six stages that already sit between `TX_CLK` (÷64) and `TICK` (÷4096), and
the divider grows nothing to make the scanner. (At 128 bit-times it did: the
seventh stage was a ÷8192 one binary order *past* `TICK`, which a single '4040
cannot supply. The second conductor removed a divider stage as well as a wire.)

| | `verilog/` | here |
|---|---|---|
| highway conductors | 16 | **10** — 8 × `HC`, `/HA`, `/HB` (+ `/HW`, MAXIMAL) |
| usable seats | 63 | **63** |
| a block's commutators | 4 × '151 | **0** |
| the marker's probe | 2 × '151, '74, 2 × '164 | a comparator and two flip-flops |
| cable B | 26-way, 12 signals | **16-way**, 6 + 2 spare |
| scan pass | 8 ms nominal, **9 ms measured**, 72 visits to 64 ports | **1 ms**, 64 ports, always |
| seizure latency | ~9 ms | **≤ 1 ms + a bit-time** |
| per-port supervision refresh | 64 kHz | **1 kHz** — the cost |

> The `verilog/` column is **not a sound baseline**: its `ctl_write` truncates
> `DIV` to three bits, so cable B runs at 512 kHz rather than the documented
> 128 kHz, and the 9 ms / 72-visit measurement was taken against a serialiser
> four times too fast. The fold still wins; the margin is unknown until that is
> fixed and re-measured.

An earlier attempt at the same fold is the retired `exchange/fabric-rev2.md`
(commit `4aec724`): A interleaved into a **sacrificed slot 4 of the C
highway**. It cost a seat a block — 55 usable against 63 — and moved the
operator off 04. A separate wire costs one conductor and keeps all 63.

---

## 2. The clock chain

One 4.096 MHz crystal, one divider, everything a tap of it. In RTL that is one
clock domain at 4.096 MHz with strobes.

| ÷ | rate | name | who wants it |
|---|---|---|---|
| 4 | 1.024 MHz | `LINE_HB` | the '175 that makes `SLOTQ`; MF8 trunk encoders |
| 8 | 512 kHz | `HCLK`, `SLOT[2:0]` | every C commutator, every strobe decoder |
| 32 | 128 kHz | `LOOP_HB` = `/SLOT[1]`; `SCLK` | the CVSD encoder; the control bus |
| 64 | 64 kHz | `TX_CLK` = `/SLOT[2]` | socket a1; **one bit-time on all three wires** |
| 128 | 32 kHz | `FILL`, **and `SCAN[0]`** | the idle `1010`; the port field's low bit |
| | 32 kHz→1 kHz | **`SCAN[5:1]`** | the rest of the port field, 0..63 |
| 512 | 8 kHz | `CLK_8K`, `RX_OCT` | socket a3/a8 |
| 4096 | 1 kHz | `TICK`, **and `pass_stb`** | **the ports' RC detectors**, the registers, the marker; the pass boundary, replacing `START` |

`SCAN[5:0]` are **exactly** the six stages between `TX_CLK` and `TICK`, so the
scanner costs no divider stage at all, and `pass_stb` is not a further tap — it
**is** `TICK`, because 64 bit-times of 64 master ticks is 4096. `tb_clock`
asserts that the two are the same edge.

`FILL` and `SCAN[0]` are **the same divider stage**. `SCAN[0]` is now the port
number's low bit rather than an A/`BUSY` phase, but it is the same ÷128 at
32 kHz: invert one of them "locally" and the scan is off by a port and every
reader takes its neighbour's hook. `tb_clock` asserts it every master tick.

The ÷32 / 128 kHz row that used to sit here is gone. `LOOP_HB` and `SCLK` are
in `clocks.md` §1 and on socket a2, but **`clock_card` does not bring either
out in this build** — `ctl_write` counts its own bit-time from the master
clock. That is a departure from `clocks.md` §1's placement and is listed in §5.

---

## 3. The hierarchy is the layout

```
 exch              ONE exchange: the clock card, the mainboard, eight blocks
   clock_card      the crystal, the divider, SLOT, SLOTQ, SCAN, FILL, cadence, TICK
   mainboard       a ribbon: eight HC_OUT onto eight highways, the wired-ORs
                     into /HA, /HB and /HW.  No jumper, no shunt field, no /BLK
   block  x8       ITS OWN NUMBER -- one header jumper, a '148 to read it, a
                     '688 that makes /BLK from it; the C commutator, the
                     ringback '157s, the write decoder, the word's two '164
     port x8       '273, a '151, a '688, a '74 pair, TWO open drains, a 2 x 3
                     slot jumper, and the supervision

 mini_marker       MINIMAL: the handoff, the sequencer, one register, one serialiser
   probe           the scanner-addressed listener -- ONE '688 and half a '74
   pulse_reg       register.md 4's collector, with a probe of its own on its caller
     pulse_rx      three windows off one timer: HIT 8, ID 128, CLR 256 ms
   ctl_write       the cable B serialiser: one 16-bit word on one wire at 128 kHz

 debugger          MINIMAL+MAXIMAL: a listener on the tap with no authority.
                   Twelve sticky lamps grouped by which board to pull; its own
                   copy of the scanner and of the last control word

 dm_rx             the differential-Manchester receiver of mf8-spec.md 9.4 at
                   any rate plug: the same four packages at both ends of every
                   line in the family
 cvsd_line_card    a CVSD subscriber line card on the channel socket: two line
                   interfaces, the hook detector, the slot logic.  THE PHONE
                   HOLDS THE CODEC.  THE SOCKET IS THE CARD ABSTRACTION: a port
                   list, fourteen pins in socket order, the same on every card

 top_min           MINIMAL: exch + mini_marker
 top_max           MAXIMAL: THE SAME exch, with the class marker, a register pool,
                   a network unit and monitors beside it            (not written yet)
```

`top_max` instantiates the same `exch`, unchanged, so "the maximal build is
the same fabric" is true by construction rather than by care. What is MAXIMAL
in the minimal build is **one wire** — `/HW` — brought out and unused.

> **That claim is true of the fabric and false of the tap.** `exch`, `mainboard`,
> `block`, `port` and `clock_card` need nothing. But `probe`, `ctl_write`,
> `pulse_reg` and `mini_marker` are listed in this hierarchy as well, and four
> interfaces above `exch` must still change before `net_unit` and the class
> marker can be written: cable B has **no arbitration** (`top_min` hardwires one
> master, and the old tree's 124-conductor reach from `net_unit` into the
> marker's queue is not portable); `ctl_write`'s `g`, `strobe` and `clm` are
> tied off at the only instantiation and the queue is 13 bits where the word is
> 15; and `/HW` needs a validity of its own, separate from `probe`'s `fresh`,
> because the word is still `/BLK`-selected while M and `BUSY` are not.
> `probe_fresh` is now on the tap; the rest is §7's work.

### Style

The house style is written up in [`STYLE.md`](STYLE.md); these are its
headlines.

- Verilog-2001, plus the SystemVerilog that **both** simulators accept —
  `logic`, `typedef`, `always_comb`, `for (int)`, `generate`, packed 2-D
  *signals*. Not packed-array or struct *parameters*: Icarus 13 rejects them,
  so parameters stay flat vectors with part-selects. No chip library, nothing
  instantiated that is not a board.
- **A '151 is an `assign` under a comment that says so.** One region a package.
- `// MINIMAL` / `// MAXIMAL` / `// MINIMAL+MAXIMAL` mark which build needs
  which region.
- Parameters model **straps and stuffing** (`FITTED`, `BLOCK`, `POS`,
  `SHUNT`) and never features. The one exception is `` `PW `` in `exch.vh`,
  and the five sites that would widen with it each say so.
- Every module lints clean under `verilator -Wall` with one waiver, in
  `mini_marker`, for a blocking assignment that is deliberate. `make lint`
  now **fails** when a module does not lint: the old loop put the compiler on
  the left of an `&&` and returned only the last iteration's status, so ten of
  the eleven modules could not fail it.

---

## 4. Running it

```
make            every bench under Verilator
make iv         every bench under Icarus
make lint       every module on its own, -Wall
make clean
```

Verilator is what to use while working; Icarus is the reference. **Anything
that passes under one must pass under the other** — one real bug has already
been caught that way (a function called from a continuous assign, which Icarus
did not re-evaluate when a signal read *inside* the function changed).

| bench | proves |
|---|---|
| `clock` | the taps it brings out, their rate and phase; `SLOTQ` a quarter cell late; **`FILL == SCAN[0]`**; **`pass_stb` and `TICK` are the same edge**; a pass is 4096 master ticks; and that **`SCAN` steps on every frame edge with no exception** |
| `fabric` | every source slot to every listening slot — **4 096 ordered pairs, bit-exact, one frame**; fan-out; and that an exchange with no port circuits pulls none of the three wires down |
| `ctl` | the hotline set up by hand; the guard bit; an event word that pulses `WR` and writes nothing; a pointing word that never pulses `WR`; `/RESET` |
| `ha` | the bit-time map **on both wires at once** — `/HA` is port *p*'s M and `/HB` is port *p*'s `BUSY` in bit-time *p*; the capture 36 master ticks (8.79 µs) into the frame; all 64 ports in order; a bare exchange never pulls either down; **E follows M within one pass**; and the 16 ms detector arming, sampled either side of the window |
| `probe` | 64 ports a pass following the scan, one a pass when held, and **the per-port clear** |
| `dial` | a rotary dial through the 1 kHz sampler, at the corners of `register.md` §3.1's **nominal** envelope, down to an ideal 28 ms break at 20 pps |
| `mini` | `mvp.md` §3's call each way: seize within a pass, dial tone, `2 1`, the ringback substitution, ringing in cadence, answer, two-way voice, self-release; then `mini-marker.md` §5's wrong numbers |
| `debug` | the debugger card: a quiet exchange and a clean write light **nothing**; twelve faults injected one at a time, each lighting its own lamp and no other; and **`mainboard.md` §7's SCLK hazard** — one extra edge lights the lamp *and* loses the write, and the next clean word lands |
| `line` | the CVSD line card with a phone on its two pairs: `1100` reads on-hook and speech off-hook, through the 4 ms RC; **a 60 ms dial break arrives 54 ms long** — the 6 ms `subscriber-line.md` §5 measures, reproduced; `A_RX` rings an on-hook phone and only an on-hook phone; a cut pair reads on-hook, not off; `MUTE` puts `1010` on an off-hook line; bits cross both ways in order |

**What these do not cover**, so the count is not read as more than it is:

- `dial` drives the *nominal* corner, 28 ms. `register.md` §3.1 **measured**
  breaks as short as 18 ms at 20 pps once the line card's 6.1 ms and jitter are
  in. 18 ms is 18 samples against an 8-sample `HIT` window, so it holds — but
  nothing here drives it.
- `mini`'s seizure-latency check is **one sample** at 1 ms resolution against a
  2 ms bound. `ha`'s eight-phase sweep is what measures the worst phase.
- `mini` does **not** cover `mini-marker.md` §5's "called party already in a
  call" row — the only row that reaches the `p_m || p_busy` branch rather than
  `called == caller`. That branch has never run.
- There are **no gate delays**, so `fabric.md` §3.2's hazard and §4's
  nanoseconds are outside what any of this can see.

---

## 5. Where the documents now disagree

Each of these is a place the code departs from a written section, deliberately.
The code comments name the section; the documents have not been brought up yet.

| document | what changed |
|---|---|
| `fabric.md` §1.1, §2, §3.1, §3.2 | `HA[0..7]` are gone; the block has **no** commutator but the C one; the port's A select is a comparator; `PB[1:0]` and both its '151s go |
| `mainboard.md` §2.2 | **the polarity.** "`HA` is pulled to ground: on-hook" becomes `/HA`, `/HB` and `/HW` pulled **up** — an open-collector wire cannot be pulled to its active state. §2.2's table also still lists eight `HA` wires |
| `mainboard.md` §2.1 | the `CLK_8K` row's "the scanner steps on it; a visit is 125 µs" — the scanner steps on the 64 kHz frame edge and a turn is 15.63 µs. The group count "15, of which the clock card drives 14" grows by `SCAN[5:0]` |
| `mainboard.md` §2.3.3, §2.3.4 | `SCAN[2:0]`, `ADVANCE` and `START` come off cable B; `SCAN[5:0]` goes on cable A, from the clock card. §2.3.3's conclusion — that a word-steered probe would saturate the bus — no longer applies to M or `BUSY`, but **does** now apply to `/HW`, which is word-steered by design |
| `mainboard.md` §3.2 | cable B reverts to a 16-way. `common/terms.md` §, which still says 16-way, becomes the **correct** document and §3.2 the stale one |
| `mainboard.md` §1, §2.3, §4 | **there is no shunt field.** The jumper is on the block header, a '148 reads it as the block's number, and the block makes `/BLK` itself with one '688 on `DST[5:3]`. §2.3's "the decoder moved to the block's end and nothing learned its own name" is superseded: the block knows its name. `blk_dec` and the `/BLK` return — 8 conductors a block connector, 64 on the mainboard — are gone, and the mainboard is the ribbon §1 always said it was |
| `port-card.md` | the port card carries a 2 × 3 **slot jumper**, and takes the highway half of its number off the block ribbon. It must be set to the socket the card sits in, which is still where its `C_TX` enters the commutator |
| `mainboard.md` §6 | the absent-part table's two "`HA` to ground" rows. Absence now reads idle because nothing pulls down, not because something pulls low |
| `mainboard.md` §9 | both open items are answered: what re-drives the scanned port's M, and crosstalk on sixteen switching highways — there are ten conductors now, which is a better cure than `fabric.md` §6's |
| `fabric.md` §6 | the economy form is **superseded**. It bought eight wires by spending edge margin; this buys six and spends none |
| `clocks.md` §1 | `SCAN[5:0]` joins the table as six stages that were always there, and `pass_stb` is `TICK` rather than a further tap. The ÷32 `LOOP_HB`/`SCLK` row has **no signal on the clock card in this build** |
| `protocol.md` §3, `mvp.md` §2 | "an absent block's `A` wire to 0" / "`HA` = 0" — the same polarity inversion, in two more places |
| `mini-marker.md` §1, §2, §4 | the probe reads `BUSY` off `/HB`, not off `PB`; the pass is 1 ms, not 8 ms |
| `common-control.md` §2.1 | the register ribbon loses `attach_src`/`SRC` and gains `counting`/`hook` in the minimal build |
| `common-control.md` §2.2 | the tap's `visit` is `probe_fresh`; the card word is **not** a field of the scanned sample any more, so a listener needs a second validity for it |
| `register.md` §2 | `counting` is cleared one gate later than the '163's STB, because `pulse_reg` samples `cnt` in the strobe cycle |
| `port-card.md` | the trailing `bbb bss sss` is a nine-bit address from the withdrawn `beafaf1` branch; and `:13`'s "64 A status bits multiplexed at 64 kHz" is the A half only, with no `BUSY`, no `SCAN` pin and a 1 ms pass |

**Not** a departure, though it looks like one: `fabric.md` §3.3's "port 00 reads
`FILL` and A = 0" survives the polarity flip, because the port re-inverts on
capture (`port.v`'s `e_cap <= ~ha_n`).

---

## 6. What is not settled

- **The 4.7 kΩ pull-up.** 64 taps and 2 m of ribbon is ≈300 pF, so τ ≈ 1.4 µs
  against 8.79 µs of settling — six time constants. At 10 kΩ or 500 pF the
  margin is gone. This is the **one place the fabric is near a limit**, and it
  is why the wire runs at 64 kHz and not 512 kHz. `exch.py mainboard` should be
  re-run for this conductor.
- **One conductor, one failure domain.** A single stuck open drain kills all 64
  ports' signalling where an A driver fault used to cost eight, and there is no
  way to lift a block off a wired-OR. `/HA` low for a whole pass is a fault and
  is worth a lamp.
- **Relayed dial pulses.** Each exchange a pulse crosses re-samples it at 1 kHz
  where the old plane re-sampled at 64 kHz. `/HB` halves what this costs — the
  quantisation is 1 ms, not 2 — but nothing here measures a relayed pulse yet.
- **`/HW` fails open.** The word bus idles high, and all ones is what
  `extensions.md` §2.2 calls *unconditional*. A pointed card that is absent,
  unseated or still in its power-up RC therefore reads as eligible for every
  hunt. This is `option-word-rev2.md` §2's bug — **a document in no index, cited
  by nothing, and still live in `verilog/rtl/marker.v`** — and the class marker
  must pair every word read with the `BUSY` it already has off `/HB`.
- **`SCLK` is not a tap here.** `ctl_write` counts its own bit-time off the
  4.096 MHz master, so the one rate in the design that is not a divider tap is
  hidden inside a module whose header calls itself two '165s. On a board that
  wants either a 4.096 MHz conductor on cable B or a ÷32 counter on the marker
  card, and `clocks.md` §3 forbids the second.
- **`channel-cards.md` §2.2's violation timer.** It reads "gap > 1.25 cells …
  ½ 74HC123, 14.6 µs at 128 kBaud". At 64 kbps 1.25 cells is 19.5 µs; 14.6 µs
  is 15/16 of a cell and would fire on every `1` bit. `dm_rx` implements 1.25
  cells, which is what `subscriber-line.md` §3.1 measured with. One of the two
  numbers is wrong, and it is the microseconds.
- **74HC or 74LS.** Every document says 74HC at 5 V and `fabric.md` §4's whole
  timing analysis is 74HC at 4.5 V; `pcb/portcard/` instantiates 74LS151 and
  74LS153. The comments here say HC.
- **`exch.py mainboard` cannot settle the pull-up.** §6 above nominates it, but
  that model has no open drain in it — it is a totem-pole ribbon whose stated
  conclusion is that the cure for the edges is to *slow* them, which is the
  open-collector failure mode. There is no SPICE rig for the fabric either.
  The three pull-ups are **unanalysed**, not merely un-re-run.

## 7. Next

The maximal build: `marker.v` (the class marker and the card word off `/HW`),
`net_unit.v`, `monitor.v`, `console.v`, and `top_max.v`. The **fabric** needs
no change for any of them — `exch`, `mainboard`, `block`, `port` and
`clock_card` are done. Four things above `exch` do:

1. **Cable B needs an arbiter.** `top_min` hardwires one master. The console
   worked in the old tree on request-with-no-grant, which extends to exactly
   one requester; `net_unit` was not a master at all but a 124-conductor burst
   the marker drained, which `common-control.md` §2.2 calls a placeholder and
   §2.3 files under *not measured*. Give every master its own `ctl_write` and a
   ranked request line — the 16-way has the two spares for it — and wire-OR
   above `exch`, which needs no change to take it.
2. **`ctl_write`'s `g`, `strobe` and `clm` are tied off**, and `mini_marker`'s
   queue is 13 bits where the word is 15. Event words, pointing words and
   sticky CLAIM all have no path. `common-control.md` §2.1 requires CLAIM of the
   mini-marker itself once a unit is fitted, so this is not deferrable.
3. **`/HW` needs its own validity.** M and `BUSY` are scanned and covered by
   `probe_fresh`; the word is `/BLK`-selected and only meaningful in a quiet
   octet after a pointing word. One `visit` for both is the bug `probe_dirty`
   was.
4. **The tap should be decomposed, not widened.** `mini_marker` re-points the
   shared probe onto `called` during `S_PROBE`, so a watcher loses the sweep
   exactly when the marker is busiest. A probe is one '688 and half a '74 —
   every listener should fit its own, as `pulse_reg` already does.

Before `net_unit` is ported, two defects in its source must not come with it:
`network.md` §4's **5 s no-`b` timer is in no RTL** (the trunks go at the
register's own timeout instead, which is the outcome the rule exists to
prevent), and the answers-to hunt **writes at the end of the pass**, which
`groups.md` §2.2 says not to do and which races the same-visit connect.
