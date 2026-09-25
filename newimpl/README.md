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

> **Status: measured in simulation — 13 benches, 306 checks under Verilator,
> and 25 faults each shown to turn its bench red (`make faults`).** Icarus is
> retired from the test sequence (§4). Its last full run, on the RTL of commit
> `63bafbb`, passed the eleven benches below `net` with the same counts. It was
> stopped in `net` after an hour, and `chain` never ran. No gate delays, so
> this cannot see `fabric.md` §3.2's hazard or confirm §4's nanoseconds. Nothing has been drawn and nothing has been on a bench. The
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

> **`/HW` fails SAFE, read the way the pin is defined.** A card pulls its word
> pin low for a one (`extensions.md` §2.2), so a pointed port that is empty, on
> an unfitted block, held off by its power-up RC or a trunk whose link is down
> leaves `/HW` high for every frame and reads **all zeros** — the word table's
> *none / OOS*. Only a reader that took the wire's level as the bit would read
> that absence as all ones, a plain line. An earlier version of this note said
> the bus fails open; it had the bit the wrong way up. `word_rx` reads it
> low-true and `tb_word` checks both readings.
>
> **What a card can deliver at 64 kHz is the primary octet.** A card's '165
> reloads on `TX_OCT`, every eight frames, and the socket has no strobe that
> marks sixteen; the trunk card (`baseband.md` §3.5) shifts on `TX_CLK`, so
> frame 7 carries bit 0 and frame *f* bit *f*+1, and any eight consecutive
> frames hold the octet. Class, glare and direction are all in it. The
> secondary byte at 64 kHz is §6's open item.

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
| 4 | 1.024 MHz | — | the '175 that makes `SLOTQ`, inside the clock card. **Not on the bus**: `LINE_HB` is dropped (§5) |
| 8 | 512 kHz | `HCLK`, `SLOT[2:0]` | every C commutator, every strobe decoder |
| 32 | 128 kHz | `LOOP_HB` = `/SLOT[1]`; `SCLK` | the CVSD encoder; the control bus |
| 64 | 64 kHz | `SLOT[2]`; `TX_CLK` = `/SLOT[2]`, made on each block | socket a1; **one bit-time on all three wires** |
| 128 | 32 kHz | **`SCAN[0]`, which is `FILL`** | the port field's low bit; the idle `1010` |
| | 32 kHz→1 kHz | **`SCAN[5:1]`** | the rest of the port field, 0..63 |
| 512 | 8 kHz | `TX_OCT` (`CLK_8K`), `RX_OCT`: `SCAN[2:0]` decoded on each block | socket a3/a8 |
| 4096 | 1 kHz | **`SCAN[5]`, which is `TICK`**; its fall is `pass_stb` | the registers, the marker, the unit; the pass boundary, replacing `START` |

`SCAN[5:0]` are **exactly** the six stages between `TX_CLK` and `TICK`, so the
scanner costs no divider stage at all, and `pass_stb` is not a further tap — it
**is** `TICK`, because 64 bit-times of 64 master ticks is 4096. `tb_clock`
asserts that the two are the same edge.

**Since 2026-09-25 only `SCAN` and `SLOT` are on the bus** (`mainboard.md`
§3.5). `FILL` *is* `SCAN[0]` and `TICK` *is* `SCAN[5]`, the same divider
stages, so neither has a pin. `TX_CLK`, `TX_OCT` and `RX_OCT` are one package
on each block (`rtl/frame_decode.v`). That removes the trap this section used
to warn of: with `FILL` and `SCAN[0]` on two pins, inverting one "locally" put
the scan a port out and every reader took its neighbour's hook. There is one
wire now, and nothing to invert against it.

The ÷32 / 128 kHz row that used to sit here is gone. `LOOP_HB` and `SCLK` are
in `clocks.md` §1 and on socket a2, but **`clock_card` does not bring either
out in this build** — `ctl_write` counts its own bit-time from the master
clock. That is a departure from `clocks.md` §1's placement and is listed in §5.

---

## 3. The hierarchy is the layout

```
 exch              ONE exchange: the clock card, the mainboard, eight blocks
   clock_card      the crystal, the divider, SLOT, SLOTQ, SCAN, the ring cadence
   frame_decode    each block's one package: TX_CLK, TX_OCT, RX_OCT, FILL and TICK off SLOT2 and SCAN
   mainboard       a ribbon: eight HC_OUT onto eight highways, the wired-ORs
                     into /HA, /HB and /HW.  No jumper, no shunt field, no /BLK
   block  x8       ITS OWN NUMBER -- one header jumper, a '148 to read it, a
                     '688 that makes /BLK from it; the C commutator, the
                     ringback '157s, the write decoder, the word's two '164
     port x8       '273, a '151, a '688, a '74 pair, TWO open drains, a 2 x 3
                     slot jumper, and the supervision

 mini_marker       MINIMAL: the handoff, the sequencer, one register; and, tied
                   off in top_min, the NETWORK half -- key 1, YIELD, the claim
                   attach, sticky CLAIM, a word read before a caller or a connect
   probe           the scanner-addressed listener -- ONE '688 and half a '74
   pulse_reg       register.md 4's collector, with a probe of its own on its caller
     pulse_rx      three windows off one timer: HIT 8, ID 128, CLR 256 ms
   ctl_queue       a master's side of cable B: its queue (a model part), its
                   serialiser, its word reader, and when it may start
     ctl_write     the cable B serialiser: one 16-bit word on one wire at 128 kHz
     word_rx       /HW into the primary octet: a '259 wired rotated by one

 net_unit          NETWORK: the pulse flood.  Its own probe and cable-B master;
                   a classifier that reads a seizing port's word, a bit a port
                   (eight '164) saying which it has dealt with, and a watch on
                   each hold through the ports' arming time; the monitors, each
                   its own probe and pulse_rx; the origin bank for the one
                   register; the forwarder and resolvers; one 17 ms sweep

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
 baseband_card     NETWORK: the baseband tie trunk (baseband.md 3), in any
                   channel socket.  ITS WORD SAYS IT IS A TRUNK AND WHICH WAY IT
                   FACES; its fifth conductor's link-down detector gates the word

 top_min           MINIMAL: exch + mini_marker
 top_net           NETWORK: THE SAME exch, the same mini marker, and a network
                   unit beside it -- a pulse-flood exchange with the small marker
 top_max           MAXIMAL: THE SAME exch, with the class marker, a register pool,
                   a network unit and monitors beside it            (not written yet)
```

`top_net` and `top_max` instantiate the same `exch`, unchanged, so "the network
and maximal builds are the same fabric" is true by construction rather than by
care. What is MAXIMAL in the minimal build is **one wire** — `/HW` — brought
out, and read in `top_net` only.

**A third top, deliberately.** The rewrite's plan had two, with the unit only
in `top_max`. Joel chose, 2026-09-25, to bring the unit up beside the mini
marker first (`common-control.md` §1: "a flood never needs a smarter
marker"). The mini marker's network half is in `top_min` too, tied to "no unit
fitted": `/NET` and `/UREQ` at their pull-ups, every strobe low. It then reads
no word, never yields, and takes key 1 as highway 1 — the path it took before
it had a network half, and `tb_mini` checks it.

**The four interfaces above `exch` that the network needed are in.** Cable B
has two masters, each a `ctl_queue`, the unit ranked above the marker on a
request line; `g`, `strobe` and `clm` are live and the queue is fifteen bits;
`/HW` has a reader of its own with its own validity; and the unit fits its own
probe instead of widening the marker's tap.

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
  which region, and `// NETWORK` what only `top_net` stuffs.
- Parameters model **straps and stuffing** (`FITTED`, `BLOCK`, `POS`,
  `SHUNT`) and never features. The one exception is `` `PW `` in `exch.vh`,
  and the five sites that would widen with it each say so.
- Every module lints clean under `verilator -Wall` with **no** waiver: the one
  there was, in `mini_marker`'s queue, went with the queue into `ctl_queue`,
  which needs none. `make lint`
  now **fails** when a module does not lint: the old loop put the compiler on
  the left of an `&&` and returned only the last iteration's status, so ten of
  the eleven modules could not fail it.

---

## 4. Running it

```
make                every bench under Verilator
make lint           every module on its own, -Wall
make faults         every rule's check shown able to fail: faults.py
make iv-<bench>     one bench under Icarus, by hand; not in the sequence
make clean
```

**The test sequence is `make`, `make lint` and `make faults`**, all
Verilator. Icarus was the reference and is **retired from it** (Joel,
2026-09-25). It is too slow for the network benches: `tb_net` ran over an hour
under it without finishing. The RTL stays in the language both accept
(`STYLE.md` §5), so `make iv-<bench>` still runs a bench under Icarus. That is
worth doing by hand after a change that leans on evaluation order. Icarus once
caught a real bug that Verilator passed: a function called from a continuous
assign, which Icarus did not re-evaluate when a signal read *inside* the
function changed.

| bench | proves |
|---|---|
| `clock` | the taps it brings out, and the block decode (`frame_decode`) made from them, their rate and phase; `SLOTQ` a quarter cell late; **`FILL == SCAN[0]`**; **`pass_stb` and `TICK` are the same edge**; a pass is 4096 master ticks; and that **`SCAN` steps on every frame edge with no exception** |
| `fabric` | every source slot to every listening slot — **4 096 ordered pairs, bit-exact, one frame**; fan-out; and that an exchange with no port circuits pulls none of the three wires down |
| `ctl` | the hotline set up by hand; the guard bit; an event word that pulses `WR` and writes nothing; a pointing word that never pulses `WR`; **`CLM` reaches the card as `A_RX`**; **the serialiser's rate measured** — every `SCLK` period 32 ticks, sixteen edges a word, 17 bit-times a written word; `/RESET` |
| `ha` | the bit-time map **on both wires at once** — `/HA` is port *p*'s M and `/HB` is port *p*'s `BUSY` in bit-time *p*; the capture 36 master ticks (8.79 µs) into the frame; all 64 ports in order; a bare exchange never pulls either down; **E follows M within one pass**; and the 16 ms detector arming, sampled either side of the window |
| `probe` | 64 ports a pass following the scan, one a pass when held, and **the per-port clear** |
| `dial` | a rotary dial through the 1 kHz sampler, at the corners of `register.md` §3.1's **nominal** envelope, down to an ideal 28 ms break at 20 pps |
| `mini` | `mvp.md` §3's call, 20 to 21: seize within a pass, dial tone, `2 1`, the ringback substitution, ringing in cadence, answer, two-way voice, self-release; then `mini-marker.md` §5's wrong numbers, **`2 8` refused on the second key**, and **key 1 as highway 1 with no unit fitted** |
| `debug` | the debugger card: a quiet exchange and a clean write light **nothing**; eleven faults injected one at a time, each lighting its own lamp, and the two `STUCK` faults their `P00` lamp with it; and **`mainboard.md` §7's SCLK hazard** — one extra edge lights the lamp *and* loses the write, and the next clean word lands |
| `line` | the CVSD line card with a phone on its two pairs: `1100` reads on-hook and speech off-hook, through the 4 ms RC; **a 60 ms dial break arrives 54 ms long** — the 6 ms `subscriber-line.md` §5 measures, reproduced; `A_RX` rings an on-hook phone and only an on-hook phone; a cut pair reads on-hook, not off; `MUTE` puts `1010` on an off-hook line; bits cross both ways in order |
| `word` | a card's word off `/HW`: a trunk reads its class, glare and direction; a plain line all ones; an empty socket, an unfitted block, a card in its power-up RC and a cut link **all zeros**; the same octet at all eight phases; a read writes nothing and holds cable B 998 ticks; and two faults on the wire go red in the same run — `/HW` a frame late, and read at its wire level |
| `tie` | two exchanges on two crystals and a baseband tie trunk, patched by hand: each end reads its own card's word; 32 bits cross each way in order; the hook crosses as M; `/ANS` is low; a cut cable drops both link detectors, reads NONE at both ends and drops A |
| `net` | two exchanges on one link, **calls that are dialled**, in fifteen scenarios: a local call floods nothing; `1 2 3 2 1` seizes the lowest trunk facing E, B holds it and does **not** take its M as a call, B's monitor claims at `b`, B gives the trunk its register, 21 rings, voice both ways, release through every patch; own code; nobody (the 2 s from `b`); 8 and 9 in the code; the 5 s rule; a break inside the guard; **B's register busy — the refusal lands after the CLAIM word**; a dialled trunk refused; no trunk and `EV_NOTRUNK` on cable B; a caller who stops after `b`, freed by `nodig`; **the called party hanging up first, with no phantom seizure after**; **a hold on a seizure that died before the port could arm, cleared**; two lines waiting for the register while A floods, each read once; a one-key number after the code, `1 2 3 0`, connected at three digits; a 0.9 ms blip on the link, read and held and then **written away** because B's port could never arm; `1 2 2 1`, the second key refused; and no clash on either cable B, ever |
| `chain` | three exchanges and a transit: A to C through B, B's monitor lets go at `b`, B's resolver frees itself at the claim, B never holds a register; C to A; and a call **from the middle**, flooded both ways, that drops the losing direction **at the claim**; and **two floods crossing at B**, A's seizure arriving in the middle of B's own sweep |

**The checks can fail, and `make faults` shows it.** `faults.py` puts 25 old
bugs and missing rules back, one at a time, into a copy of the tree, and runs
the bench meant to catch each: the unit released on `gone` alone, a sweep on
an even stride, the 5 s rule gone, the claim wait from the last digit, the
second digit folded, the register armed on a stale sample, no guard, no wait
before the unit drives, a word not gated by its link, key 1 a flood with no
unit, the old serialiser rate, `CLM` tied off, no unhold, the origin reading
the shared sweep, no per-port memory, a second key allowed, a one-key number
waiting for four, and more. **Every one turns its bench red** on the final
tree — except two whose rule is held twice, which stay green by design and
each have a second fault removing both holds, which is red: the refusal
landing after `CLAIM` (the unit's handshake, and its rank on cable B), and a
trunk's M never taken as a call (the marker's own read, and the unit's hold
within a pass).

A review of the network RTL by four independent readers, each finding checked
by a skeptic trying to refute it, found five real defects before this tree
settled — the origin reading a sweep result a forward had just cleared; two
waiting lines starving the sweep; a hold on a seizure that died before the port
armed, left BUSY for good; a phantom flood when the called party hung up first;
and a second key after the call's own code. Each is fixed, each has its
scenario, and each has its fault in `faults.py`.

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
- `net` and `chain` run the register, the port detectors and the protocol's
  timers **8× fast** through their straps. The word reads and the sweep are
  cable timing and do not scale, so the guard covers less than one hop there:
  its mechanism is tested, not its reach. No relayed pulse is measured at real
  speed.
- **No glare** is provoked, so `EV_GLARE` and the glare count are unexercised.
  No hub (a fan-out of two or more legs), no ring and its jumper, no two calls
  through one exchange at once, and no MF8.
- The network benches' phones are the socket's pins driven by hand, as
  `mini`'s are, not `cvsd_line_card`.

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
| `mainboard.md` §2.1, §3.1; `clocks.md` §1; `mf8-spec.md` §9.1 | **`LINE_HB` is dropped from the bus** (Joel, 2026-09-25). Nothing in newimpl read it. The '175 that makes `SLOTQ` keeps its 1.024 MHz tap inside the clock card, so the fastest signals on the bus are now `HCLK`, `SLOT` and `SLOTQ`, at 512 kHz. An MF8 adapter makes its own 1.024 MHz half-bit clock |
| `mainboard.md` §3.1–§3.3 | **one bus, not two cables** (Joel, 2026-09-25): 31 signals on one 2 × 25 header, `mainboard.md` §3.4, which also says how it is cabled. Where this tree still says "cable A" or "cable B", read it as a signal group |
| `mainboard.md` §2.1; `clocks.md` §1; `common-cards.md` §1.1 | **`TX_CLK`, `TX_OCT`, `RX_OCT`, `FILL` and `TICK` left the bus** (Joel, 2026-09-25): each is another bus signal or one gate from one, and each block makes them for its sockets (`rtl/frame_decode.v`, `mainboard.md` §3.5). `FILL` *is* `SCAN0` and `TICK` *is* `SCAN5`; the marker and the unit take the 1 ms edge off `SCAN`; the debugger takes its pass off its own mirror and loses `FILL_SCAN0` |
| `protocol.md` §3, `mvp.md` §2 | "an absent block's `A` wire to 0" / "`HA` = 0" — the same polarity inversion, in two more places |
| `common-control.md` §2.1 | the register ribbon loses `attach_src`/`SRC` and gains `counting`/`hook` in the minimal build |
| `common-control.md` §2.2 | the tap's `visit` is `probe_fresh`; the card word is **not** a field of the scanned sample any more, so a listener needs a second validity for it |
| `register.md` §2 | `counting` is cleared one gate later than the '163's STB, because `pulse_reg` samples `cnt` in the strobe cycle |
| `port-card.md` | the trailing `bbb bss sss` is a nine-bit address from the withdrawn `beafaf1` branch; and `:13`'s "64 A status bits multiplexed at 64 kHz" is the A half only, with no `BUSY`, no `SCAN` pin and a 1 ms pass |
| the rewrite's plan, D6 | **three tops, not two.** `top_net` fits the network unit beside the mini marker; `top_max` is still to come. Joel's decision, 2026-09-25 |
| `mainboard.md` §2.3; `common-control.md` §2.2 | **cable B has a second master.** The unit has its own serialiser and a request line, `/UREQ`, on one of the 16-way's two spares; the marker yields between transactions; there is no grant, and the unit waits 1152 ticks — longer than the marker's longest transaction, a word read — before it drives. `common-control.md` §2.2's drain of the unit's writes through the marker's serialiser is gone |
| `common-control.md` §1, §2.3, §4; `monitor.md` §1, §3.3, §4, §6; `fabric.md` §5.2 | **the monitors are on the network unit**, not on the trunk block: each cell is a probe on `/HA` and `/HB` and a `pulse_rx`, one pool an exchange, attached when the unit reads a seizing port's word. BUSY is read in M's own bit-time, so the third term is live, not "at the last visit". No block wiring, no `chan_mask`, no `BLOCK` strap; `e` and `b` are the unit's own jumpers. `monitor.md` §4's per-block sizing must be re-derived for one pool |
| `common-control.md` §2.2, §2.4, §5; `network.md` §3.2 | **no trunk jumpers anywhere.** A trunk card says it is a trunk, which way it faces and its glare in its own word, and the marker and the unit each read it off `/HW` when they need it (Joel, 2026-09-25). `TRUNK_MASK`, `TRUNK_DIR` and `HAS_NET` are gone; "a one-direction bring-up hunts by a jumpered port mask" no longer holds |
| `common-control.md` §2.2 | **`/NET`**: the unit grounds it and the marker reads it, in place of "a jumper, or the card present". Unit-to-marker controls are one-tick `_stb` lines; `att` is a level held until the marker attaches or refuses, raised only once the `CLAIM` word has gone out |
| `network.md` §3, §3.2; `topology.md` | **a hunt is a 17 ms sweep.** Reading words costs a quarter of a pass each, so the unit visits every port once on a stride of 17 and keeps, a direction, the lowest free trunk — or the highest where the word sets glare — then confirms each is still free before writing it. At a transit that is most of a hop: the 128 ms guard covers about six hops where the documents' 12 ms a hop gave ten |
| `extensions.md` §2.2, `baseband.md` §3.5 | **the word's timing.** §2.2 shifts a card's '165 at 128 kHz on `LOOP_HB`; `/HW` is read at 64 kHz. The trunk card shifts on `TX_CLK` and loads in the first half of frame 7 (`TX_OCT · TX_CLK`, a quarter '08), so the load is released a half-frame before the edge that shifts; `baseband.md` §3.5's load on `TX_OCT` alone released it at that very edge |
| `register.md` §4 | `pulse_reg` arms its collector at the first sample its probe takes **of the caller**. The probe holds the last port's hook for up to a pass after it is re-pointed, and a HIT strapped as low as 1 ms counted that stale zero as a pulse |
| `baseband.md` §3.1 | the A path's RC is modelled as two flip-flops on the frame edge, a frame or two where the card has tens of microseconds |
| `baseband.md` §3.5 | the power-up RC holds off the card's **M** as well as its word. A card that passed a seizure on while its word still read NONE would be read as nobody's, and the marker now takes a NONE word as no caller |
| `network.md` §3 | "when the last digit is in" is `h s`, **or a one-key number** — 0 or 9 after the code (§3's "h s, or 0, or 9"): the origin connects at three digits when the third is one |
| `common-control.md` §2.2 | after the unit turns a call local (own code), **a 1 is refused**, not taken as a second key; the old marker re-flooded |

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
- **The word's secondary byte at 64 kHz.** A card reloads on `TX_OCT`, every
  eight frames, and the socket carries nothing that marks sixteen, so what a
  reader gets at a bit a frame is the primary octet. That is enough for a trunk
  and for everything this build reads. The class marker wants the secondary —
  covers, conditions, dual numbers — and needs a load strobe on the socket, or
  the card to read the word at 128 kHz as `extensions.md` §2.2 has it, or a
  second octet by another means. (The fails-open worry this item used to be was
  a misreading of the bit's polarity: §1.)
- **The hunt costs the guard.** A sweep is 17 ms whatever the exchange holds,
  and a transit's hop is mostly one sweep. `network.md` §4 and `monitor.md`
  §3.5 budget a hop at 7 ms, 12 at a slow marker; at 17 the 128 ms tap covers
  about six hops and the 256 ms tap about thirteen. `topology.md`'s limits on
  long chains move with it and have not been re-run. It is the price of the
  card saying what it is, which Joel accepted.
- **One forwarder, one origin bank.** A seizure that arrives while the
  forwarder is sweeping is held and watched but not passed on (`n_nofwd` counts
  it). The unit has one origin bank because the mini marker has one register;
  a register pool wants one bank a register.
- **The queue is a model part, and the unit's writes want a sequencer.** In
  74HC a card's sequencer holds until its word is away, and there is no queue
  (`counters.md` §9). The unit decides up to five writes in one tick — a
  `CLAIM` and four leg drops — and hands them to `ctl_queue` at once, and its
  other machines carry on while they go out. On a board that is a stepping
  sequencer, a word at a time, with the resolver and monitor watches running on
  their own. The bus time is the same; the unit's structure is not, and it has
  not been drawn. The marker never has more than a few words waiting, and a
  per-word stall there changes nothing. A 16-deep FIFO a master would be the
  other way, and is a memory part.
- **The classifier holds each seizure for the ports' arming time.** It watches
  a hold for `T_ARM` — 16 ms — and writes it away if M falls inside that time,
  because a port whose M detector never rose has no edge to release on. It
  takes no other seizure meanwhile; one that rises then is read at a later pass
  (its bit a port is still clear), so a burst of seizures is classified about
  one each 18 ms.
- **Cable B's second master, on paper.** `/UREQ` is one of the 16-way's two
  spares, but no pin table for newimpl's 16-way has been written, and the
  unit's `WAIT` of 1152 ticks is derived from the marker's longest transaction
  by hand, not measured against it. `b_clash` is counted in every network bench
  and has never lit.
- **`SCLK` is not a tap here.** `ctl_write` counts its own bit-time off the
  4.096 MHz master, so the one rate in the design that is not a divider tap is
  hidden inside a module whose header calls itself two '165s. On a board that
  wants either a 4.096 MHz conductor on cable B or a ÷32 counter on the marker
  card, and `clocks.md` §3 forbids the second. **There are two such cards now**,
  the marker and the network unit.
- **The MF8 block adapter is not written.** The adopted six-channel frame
  transmits in the fabric's clock (`network.md` §1), which wants a 1.024 MHz
  half-bit clock and `SLOT[2:0]` at the adapter. `LINE_HB` is no longer on the
  bus (§5), so the adapter makes its 1.024 MHz itself, from `HCLK`; the block header's commons carry `TX_CLK`,
  `TX_OCT`, `FILL`, `MUTE_BLK` and one spare. The baseband tie card came first
  instead, and the header's pins are open.
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

The network unit is in, beside the mini marker (`top_net`), with the 5 s rule
it never had and the other trunks dropped at the claim. What is left:

1. **A hub and a ring.** The resolvers and the ring jumper are built and have
   run only with one leg. `tb_hub` and `tb_ring` were red in the old tree when
   it retired; they are the next benches, and the first place a fan-out of two
   or more legs is exercised.
2. **The MF8 block adapter**, once the block header's commons are settled (§6).
3. **The maximal build**: `marker.v` (the class marker, and the card word's
   secondary, §6), a register pool with a bank a register on the unit,
   `console.v`, and `top_max.v`. The fabric needs no change for any of it.
4. **`exchange/folded-a.md`**, the fold's own specification. This README and
   `PORT.md` stand in for it.
5. **A router, sketched and not built.** A tandem with no subscribers is `exch`,
   a network unit and trunk cards, and no marker at all: the unit has its own
   probe, its own cable-B master and reads the cards itself, and ports release
   themselves. It owns no code, so it never claims — it cannot refuse a call it
   cannot pass on, and cannot parent a PBX leaf. A stub marker with the claim
   path alone would give it a code. The unit already runs with no marker
   fitted; what a router wants first is more than one forwarder.
