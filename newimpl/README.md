# `newimpl` — the exchange in Verilog, rebuilt around the folded A plane

`verilog/` is the exchange of the `exchange/` and `common/` documents as they
stood. This is a clean start around one change: **`HA[0..7]` — eight
totem-pole A highways at 512 kbps, commutated by `SLOT` at each block — are
replaced by scanner-addressed open-collector conductors at 64 kbps: `/HA`
carries M, `/HB` carries `BUSY`, and `/HW` carries the card option word.**

Everything else follows from that.

> **`PB` is gone.** With `BUSY` on its own scanned wire and the option word on
> a wire a reader selects in the port's own bit-time, nothing in the exchange
> is block-steered any more, and `/BLK` survives only to gate a block's
> writes.

> **Status: measured in simulation — 22 benches, 770 checks under Verilator,
> and 71 faults, each shown to turn its bench red by a named check but the two
> held by design (`make faults`, §4).** Icarus is
> retired from the test sequence (§4). Its last full run, on the RTL of commit
> `63bafbb`, passed the eleven benches below `net` with the same counts. It was
> stopped in `net` after an hour, and `chain` never ran. No gate delays, so
> this cannot see `fabric.md` §2.2's hazard or confirm §7's nanoseconds. Nothing has been drawn and nothing has been on a bench. The
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
| polarity | **idle HIGH.** One 4.7 kΩ pull-up each at the clock card, one drain a block each (the port drains are ORed on the block, `exchange/block-stack.md`) |

The second conductor is what removes the phase bit. One bit-time carries M
*and* `BUSY` **of the same port**, so a reader never holds half a sample across
a frame edge and cannot pair one port's hook with its neighbour's `BUSY` — the
failure the interleaved single wire would produce if `FILL` and `SCAN[0]` were
ever inverted against each other.

It also doubles the margin that decided the fold. `dialling.md` §3.1's measured
worst case, an 18 ms break at 20 pps, was nine samples against a four-sample
`HIT` window at 2 ms; it is **eighteen against eight** at 1 ms.

### The card option word: `/HW`

`/HW` is a third wired-OR conductor and the same part, but it is **not**
scanned. **A reader names the port on a fourth, `/WS`, the select**, on what
was one of the bus's two spares (pin 47, `bus.md` §2.1). It pulls `/WS` in that port's own
bit-time; every block samples `/WS` with `/HA` and `/HB`, the one whose number
is `SCAN[5:3]` latches `SCAN[2:0]`, and that one card drives `/HW`, a bit a
frame, until the next select. The reader takes the eight frames that follow:
**a read is nine frames, 140 µs, and touches no other wire.** Nothing
continuous depends on it, so the scanner never waits for it and a word in
flight cannot disturb a supervision sample. That is the whole reason the word
is not on the scan: the scan only *names* the card, and its whole word
follows.

> **`/WS` replaced the pointing word** (Joel, 2026-09-25). A reader used to
> name its port with a control word whose `DST` was the port, `WR` suppressed:
> sixteen `SCLK`s at 128 kHz, 125 µs, as long as the octet it pointed at, with
> cable B held across the whole read because another master's word shifted in
> during it would have moved the pointer. Now cable B carries **writes only**;
> a write passing during a read changes nothing on `/HW` (`tb_word`); the
> unit's `WAIT` need only outlast a write; and the unit's hunt is a 9 ms sweep
> where it was 17. The price is that a read starts only at its port's turn, up
> to a pass to wait.
>
> **Nobody owns `/WS`, and nothing can collide on it.** A select names
> whichever port's turn it is, so two readers pulling it in one bit-time name
> the same port and both take its word. The one rule is not to select during
> somebody's eight frames, and every reader can see those on `/WS`
> (`word_rx.v`). And since any card can see which port was named, **every read
> is public**: a card could take another's reads as its own. None does yet.

> **`/HW` fails SAFE, read the way the pin is defined.** A card pulls its word
> pin low for a one (`card-word.md` §2), so a selected port that is empty, on
> an unfitted block, held off by its power-up RC or a trunk whose link is down
> leaves `/HW` high for every frame and reads **all zeros** — the word table's
> *none / OOS*. Only a reader that took the wire's level as the bit would read
> that absence as all ones, a plain line. An earlier version of this note said
> the bus fails open; it had the bit the wrong way up. `word_rx` reads it
> low-true and `tb_word` checks both readings.
>
> **What a card can deliver at 64 kHz is the primary octet.** A card's '165
> reloads on `TX_OCT`, every eight frames, and the socket has no strobe that
> marks sixteen; the trunk card (`trunks.md` §2) shifts on `TX_CLK`, so
> frame 7 carries bit 0 and frame *f* bit *f*+1, and any eight consecutive
> frames hold the octet. A select comes at its port's turn, so the frame a
> read starts on is fixed by the port's slot, and `word_rx`'s '259 is wired
> rotated so that every slot reads in place. Class, glare and direction are
> all in the octet. The secondary byte at 64 kHz is §6's open item.

`HC[0..7]` at 512 kbps are untouched — eight slots a frame, 64 kbps a port,
`SLOT[2:0]` on every commutator. Voice is unaffected; only supervision slows.

### Why it is worth doing

Today the marker's probe reads `BUSY` and the card word off the block-steered
`PB[1:0]`, and steering `/BLK` costs a full 125 µs visit. So a disturbed visit
must be *repeated*; `ADVANCE` exists only so a listener can de-duplicate; and
the retired `rtl.md` recorded a livelock and a premature hunt termination that
came out of it (`exchange/decisions.md`). Give M and `BUSY` a scanned wire each and nothing continuous needs `/BLK` —

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
| highway conductors | 16 | **10** — 8 × `HC`, `/HA`, `/HB` (+ `/HW` and `/WS`, MAXIMAL) |
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
| 4 | 1.024 MHz | — | the '175 that makes `SLOTQ`, inside the clock card. **Not on the bus**: `LINE_HB` is dropped (`bus.md` §3) |
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

**Since 2026-09-25 only `SCAN` and `SLOT` are on the bus** (`bus.md`
§3). `FILL` *is* `SCAN[0]` and `TICK` *is* `SCAN[5]`, the same divider
stages, so neither has a pin. `TX_CLK`, `TX_OCT` and `RX_OCT` are one package
on each block (`rtl/frame_decode.v`). That removes the trap this section used
to warn of: with `FILL` and `SCAN[0]` on two pins, inverting one "locally" put
the scan a port out and every reader took its neighbour's hook. There is one
wire now, and nothing to invert against it.

The ÷32 / 128 kHz row that used to sit here is gone. `LOOP_HB` is `/SLOT1`,
made on each block for socket a2 (`clocks.md` §1, §4), and **`clock_card`
brings out no 128 kHz of its own** — `ctl_write` counts `SCLK` from the master
clock, which no bus line carries; `bus.md` §7 has that open.

---

## 3. The hierarchy is the layout

```
 exch              ONE exchange: the clock card, the mainboard, eight blocks
   clock_card      the crystal, the divider, SLOT, SLOTQ, SCAN, the ring cadence
   frame_decode    each block's one package: TX_CLK, TX_OCT, RX_OCT, FILL and TICK off SLOT2 and SCAN
   mainboard       the bus: eight HC_OUT onto eight highways, the wired-ORs
                     into /HA, /HB and /HW.  No jumper, no shunt field, no /BLK
   block  x8       ITS OWN NUMBER -- two header jumpers, NUMBER and HC ROUTE,
                     and no '148 (block-stack.md §2.3); a '688 that makes /BLK
                     from NUMBER; the C commutator, the ringback '157s (one on
                     each port card), the write decoder, the word's two '164,
                     and the plane OR onto one drain a plane
     port x8       '273, two '151, two '688, a '74 pair, TWO open drains, a
                     2 x 3 slot jumper, and the supervision

 mini_marker       MINIMAL: the handoff, the sequencer, one register; and, tied
                   off in top_min, the NETWORK half -- key 1, YIELD, a word read
                   before a caller or a connect, and the CLAIM REGISTER's
                   sequencer (K_): a claim attached to a second register at
                   once, h s, the called port, the connect and its watch, run
                   between this card's own states
   probe           the scanner-addressed listener -- ONE '688 and half a '74
   pulse_reg       register.md §2's collector, with a probe of its own on its caller
     pulse_rx      three windows off one timer: HIT 8, ID 128, CLR 256 ms
   ctl_queue       a master's side of cable B: its queue (a model part), its
                   serialiser, and when it may start.  Writes only
     ctl_write     the cable B serialiser: one 16-bit word on one wire at 128 kHz
   word_rx         NETWORK: the card word reader.  A select on /WS in the port's
                   own bit-time, then /HW into the primary octet: a '259 wired
                   rotated by one

 net_unit          NETWORK: the pulse flood.  Its own probe and cable-B master;
                   a classifier that reads a seizing port's word, a bit a port
                   (eight '164) saying which it has dealt with, and a watch on
                   each hold through the ports' arming time; the monitors, each
                   its own probe and pulse_rx; the origin bank for the one
                   register, connecting at the claim; the forwarder and
                   resolvers, with ages on cells and resolvers; one 9 ms
                   sweep with a hunt hold-off a direction; its own word_rx
 pulse_reg         NETWORK: the claim register, a second register card on the
                   ribbon that only claims are given (top_net)

 marker            MAXIMAL: the class marker.  The mini marker's sequencer, and
                   every decision it makes taken on the port's word as well as
                   its M and BUSY: callers by class, a dialled number connected,
                   listened to or hunted for, busy tone for a busy line.  A
                   WALK — a read every 4 ms, 63 ports in about 250 ms — is the
                   only way in: it takes callers, call nails and CO lines at
                   their read and finds tied nails to make, and it closes PWAIT
                   at 77 (marker.md §4.3).  Nothing is read out of turn,
                   so there is no per-port memory.  The dialled port and a hunt
                   are read on demand.  The mini marker's network half and its
                   WATCH, unchanged
   probe           on SCAN, never re-pointed
   word_rx         its own; the sequencer's reads and the walk's share it
     word_dec      what the primary octet says: the constants, the class, the
                   options, the three port forms.  Gates and a '138
   ctl_queue       as the mini marker's
 pulse_reg         MAXIMAL: the register as a pool card BESIDE the marker, on
                   register.md §3's ribbon.  One is fitted

 debugger          MINIMAL+MAXIMAL: a listener on the tap with no authority.
                   Eleven sticky lamps grouped by which board to pull; its own
                   copy of the scanner and of the last control word

 dm_rx             the differential-Manchester receiver of mf8-spec.md 9.4 at
                   any rate plug: the same four packages at both ends of every
                   line in the family
 cvsd_line_card    a CVSD subscriber line card on the channel socket: two line
                   interfaces, the hook detector, the slot logic.  THE PHONE
                   HOLDS THE CODEC.  THE SOCKET IS THE CARD ABSTRACTION: a port
                   list, fourteen pins in socket order, the same on every card
 baseband_card     NETWORK: the baseband tie trunk (trunks.md §2), in any
                   channel socket.  ITS WORD SAYS IT IS A TRUNK AND WHICH WAY IT
                   FACES; its fifth conductor's link-down detector gates the word
 local_trunk       NETWORK: the local eight-channel highway trunk (trunks.md §3),
                   a block adapter on one block's header: C, A, HCLK and TX_CLK
                   each way, the receiver timed by the far HCLK.  PLESIOCHRONOUS:
                   the eight bits cross at the local frame edge, and slip there

 top_min           MINIMAL: exch + mini_marker
 top_net           NETWORK: THE SAME exch, the same mini marker, and a network
                   unit beside it -- a pulse-flood exchange with the small marker
 top_max           MAXIMAL: THE SAME exch, the class marker and one register card
                   beside it, and the network unit as stuffing: UNIT_FITTED
                   leaves it out, and /NET and /UREQ read their pull-ups
```

`top_net` and `top_max` instantiate the same `exch`, unchanged, so "the network
and maximal builds are the same fabric" is true by construction rather than by
care. What is MAXIMAL in the minimal build is **two wires** — `/HW` and its
select, `/WS` — brought out, and used in `top_net` only.

**A third top, deliberately.** The rewrite's plan had two, with the unit only
in `top_max`. Joel chose, 2026-09-25, to bring the unit up beside the mini
marker first (`exchange/README.md` §2: "a flood never needs a smarter
marker"). The mini marker's network half is in `top_min` too, tied to "no unit
fitted": `/NET` and `/UREQ` at their pull-ups, every strobe low. It then reads
no word, never yields, and takes key 1 as highway 1 — the path it took before
it had a network half, and `tb_mini` checks it.

**The four interfaces above `exch` that the network needed are in.** Cable B
has two masters, each a `ctl_queue`, the unit ranked above the marker on a
request line; `g` and `clm` are live and the queue is fifteen bits; each card
that reads a word has a `word_rx` of its own, which names its port on `/WS`
and needs no cable B at all; and the unit fits its own probe instead of
widening the marker's tap. (`strobe` was live too, for the pointing word; it
went with it.)

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
make faults-check   every fault's anchors applied in place, nothing run
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
| `ctl` | the hotline set up by hand; the guard bit; an event word that pulses `WR` and writes nothing; **`CLM` reaches the card as `A_RX`**; **the serialiser's rate measured** — every `SCLK` period 32 ticks, sixteen edges a word, 17 bit-times a written word; `/RESET` |
| `ha` | the bit-time map **on both wires at once** — `/HA` is port *p*'s M and `/HB` is port *p*'s `BUSY` in bit-time *p*; the capture 36 master ticks (8.79 µs) into the frame; all 64 ports in order; a bare exchange never pulls either down; **E follows M within one pass**; and the 16 ms detector arming, sampled either side of the window |
| `probe` | 64 ports a pass following the scan, one a pass when held, and **the per-port clear** |
| `dial` | a rotary dial through the 1 kHz sampler, at the corners of `dialling.md` §2's **nominal** envelope, down to an ideal 28 ms break at 20 pps; and the no-digit timeout from seizure, from the last digit, and **on a line that pulses and never ends a digit** — which held the exchange's only register until it hung up while the timer paused for a digit in progress |
| `mini` | `marker.md` §2's call, 20 to 21: seize within a pass, dial tone, `2 1`, the ringback substitution, ringing in cadence, answer, two-way voice, self-release; then `numbering.md` §4's wrong numbers, **`2 8` refused on the second key**, and **key 1 as highway 1 with no unit fitted**; and **a caller who hangs up at the connect** — as the digit lands, and 10 ms after the write, inside the called port's `T_ARM` — the called port written free by the marker's watch, one still up at 60 ms left to the ports, and a line chattering from the write on freed at the no-digit timeout |
| `debug` | the debugger card: a quiet exchange and a clean write light **nothing**; eleven faults injected one at a time, each lighting its own lamp, and the two `STUCK` faults their `P00` lamp with it; and **`bus.md` §6.2's SCLK hazard** — one extra edge lights the lamp *and* loses the write, and the next clean word lands |
| `line` | the CVSD line card with a phone on its two pairs: `1100` reads on-hook and speech off-hook, through the 4 ms RC; **a 60 ms dial break arrives 54 ms long** — the 6 ms `subscriber-line.md` §5 measures, reproduced; `A_RX` rings an on-hook phone and only an on-hook phone; a cut pair reads on-hook, not off; `MUTE` puts `1010` on an off-hook line; bits cross both ways in order |
| `word` | a card's word off `/HW`, named by a select on `/WS`: a trunk reads its class, glare and direction; **eight trunks, one a slot, each read their own word** — every octet phase, since a port's slot fixes where its read starts; a plain line all ones; an empty socket, an unfitted block, a card in its power-up RC and a cut link **all zeros**; one select a read, in the port's own bit-time, and the word **512 ticks after it**; **no read moves `SCLK` or makes a `WR`**; two readers selecting one port in one bit-time both take its word; a reader whose port comes round inside another's eight frames takes it a pass later; **a write passing on cable B during a read changes nothing on `/HW`**; and two faults on the wire go red in the same run — `/HW` a frame late, and read at its wire level |
| `tie` | two exchanges on two crystals and a baseband tie trunk, patched by hand: each end reads its own card's word; 32 bits cross each way in order; the hook crosses as M; `/ANS` is low; a cut cable drops both link detectors, reads NONE at both ends and drops A |
| `ltu` | two exchanges on two crystals and a local eight-channel trunk, patched by hand: all sixteen channels read their unit's word; **a cut with no call busies all sixteen ports through `MUTE_BLK`**, reads NONE and sends `FILL`; eight hotlines carry eight patterns each way, in order, **no channel ever carrying another's**; A crosses channel by channel end to end, and a 40 ms make keeps its length to 0.05 ms; a cut in a call drops every A; and **1000 ppm apart every channel slips and still carries only its own bits**; beside them a bare pair of units, their headers driven with a random bit a frame on C and on A: **A slips in all sixteen directions, each slip one bit doubled or dropped, A and C together, and no A bit on another channel** |
| `lnet` | two exchanges whose only link is a local eight-channel trunk, **calls dialled across it**, B's crystal 100 ppm fast: the key seizes the lowest channel, B claims, B21 rings, voice both ways; **two calls on two channels at once**, the busy channel passed by; from B the glare end **hunts from the top**, B17, and the call lands on A17; the cable pulled busies all sixteen channels and a key finds no trunk |
| `lfull` | the same two exchanges with the local trunk **filled**: five local calls at A touch no channel; **eight calls across at once**, each key taking the lowest free channel and each channel carrying only its own pair; a ninth call from either end finds none, cannot-complete and `EV_NOTRUNK`; one channel freed, and B's key, hunting from the top, passes seven busy ones to take it; and **glare on the last free channel** — each origin counts it and takes the other's M as its claim, `EV_GLARE` names the channel on both cables B, neither end also takes its own seized channel as an incoming call, and the two callers are joined to each other with nobody rung |
| `net` | two exchanges on one link, **calls that are dialled**, in seventeen scenarios: a local call floods nothing; `1 2 3 2 1` seizes the lowest trunk facing E, B holds it and does **not** take its M as a call, B's monitor claims at `b`, B gives the trunk its **claim register**, A connects at the claim, 21 rings, voice both ways, release through every patch; own code; nobody (the 2 s from `b`); 8 and 9 in the code; the 5 s rule; a break inside the guard; **B20 holding B's line register, and A20's claim taken all the same by the claim register**; **the claim register busy with A20's call, and A22's claim refused after the CLAIM word, heard at once**; a dialled trunk refused; no trunk and `EV_NOTRUNK` on cable B; a caller who stops after `b`, connected at the claim and given cannot-complete by B's no-digit timer through the path; **the called party hanging up first, with no phantom seizure after**; **a hold on a seizure that died before the port could arm, cleared**; two lines waiting for the register while A floods, each read once; a one-key number after the code, `1 2 3 0`; a 0.9 ms blip on the link, read and held and then **written away** because B's port could never arm; `1 2 2 1`, the second key refused; **two calls up through A at once, the second flood reading the busy A11 and passing it by for A12**; **B's marker mid-word when B's unit wants cable B, and the unit waiting the word out** — the coincidence the key's writes used to make in every flood, before reads left the bus; no clash on either cable B, ever; and **no trunk ever given dial tone** |
| `chain` | three exchanges and a transit: A to C through B, B's monitor lets go at `b`, B's resolver frees itself at the claim, B never holds a register; C to A; and a call **from the middle**, flooded both ways, that drops the losing direction and connects **at the claim**; the leaves A and C strapped on their absent directions, and **never sweeping for nothing**; and **two floods crossing at B**, A's seizure arriving in the middle of B's own sweep |
| `lchain` | `chain`'s three exchanges with every link a local trunk, B 100 ppm fast and C 100 ppm slow: A to C **through B, across both of B's units**, B's monitor letting go at `b` and its resolver at the claim; **two transits through B at once**, each on its own channels; three local calls at B beside them, the transits untouched; C to A from the glare end, B forwarding from the top of its own glare group; and a call from the middle, flooded both ways, the west channel let go at the claim; the strapped leaves never sweep for nothing |
| `max` | the class marker on one exchange, no unit: every port's card says what it is, and the marker reads it before it acts. A private line — a tied nail on each card, naming the other — made by the walk at power-up, and a **one-way nail** from a paging amplifier onto the radio, which is never written; the private line used, and **one end left off-hook is no caller: both ends are nailed again and it rings the other**, then made again when both are down; dial tone within a round of the walk; **21 busy, and 22's call goes to 26, which answers to 21**; both busy, **busy tone**; busy-out is busy tone, and still gets dial tone; self, an empty slot, a card out of service, 8 and 2 8 are cannot-complete; a source is listened to, never written or rung; 0 rings the operator, then the second position, then busy tone; 9 takes two outside lines in order and refuses a third; restricted z lets only 0 through and the floor refuses 9; a data line neither calls nor is called, and off-hook is read once a round by the walk and by nothing else; a call nail rings 20 with no dial tone, and hears busy tone when 20 is busy; a CO line ringing in is routed as 0; **PWAIT** set by a round that finds the P line 36 waiting, the register given to 36 and not to 35 beside it, and to 35 once PWAIT has cleared; and a caller gone at the connect leaves the called port free |
| `fl_link` | the flood study's fixes on two exchanges (A 2 1, B 2 3; two baseband trunks and a local trunk; every port's `T_REL` short, 26 against `CLR` 32, the RC case): **a link outage is a release, never a pulse** — in `b`'s pause, ending mid-dial, one way only, and on the local trunk, whose held channel keeps no other channel poisoned; **no cannot-complete lands on a port that released itself** at the no-digit, 5 s and claim-wait boundaries, nor on a claimed trunk; a break between the key and the seizure write abandons the call; **crossing calls both complete**; a claim during a chattering line's watch taken at once and finished after it; the far caller gone at the claim, nothing held |
| `fl_chain` | the flood study's races on a chain with a local-trunk hop: **a dial break inside a hold watch two hops down** at six offsets, never a claim of a number nobody dialled; a forward called off in `F_WRITE` when its seizure died; **a resolver whose incoming link was cut lets go** and the mended link carries calls; **a stuck A conductor frees its cell and resolver** after 2–3 × `T_KEY`, parked `BUSY` |
| `fl_fwd` | the flood study's wrong numbers at **real timers**, the neighbours played by the bench: a 1 ms glitch on a held trunk is no claim; A standing before `b` is cannot-complete; a late flood's first break inside the watch; **glare dropping a trunk and a forward re-seizing it 60 ms later — the hunt hold-off keeps it off the channel**; a far port whose RC runs short; a re-seizure 200 ms after a hang-up, the cell gone at `ID` |
| `fl_load` | **random traffic** on two 48-line exchanges and a local trunk (the flood study's harness): every call classified by what its two ends heard — **no wrong number, joined pair or phantom ring**; every caller gets dial tone; and after the drain every port, both registers, the claim sequencer, the origin, classifier, forwarder, hold-off, monitors, resolvers and queues idle |

**The checks can fail, and `make faults` shows it.** `faults.py` puts 71 old
bugs and missing rules back, one at a time, into a copy of the tree, and runs
the bench meant to catch each: the unit released on `gone` alone, a sweep on an
even stride, the 5 s rule gone, the claim wait from the last digit, the second
digit folded, the register armed on a stale sample, no guard, no wait before
the unit drives, a word not gated by its link, key 1 a flood with no unit, the
old serialiser rate, `CLM` tied off, no unhold, the origin reading the shared
sweep, no per-port memory, a second key allowed, `/HW` steered by `DST` again, every block answering a select, a reader
selecting inside another read's eight frames, the sweep taking a trunk that was
busy at its select, the classifier holding a channel its own origin had just
seized, the no-digit timer paused by a digit in progress, the marker
letting go of a connect before the called port could, and fourteen of the
class marker's — busy tone turned back into cannot-complete, no answers-to
hunt, a hunt taking a busy port, the walk taking a caller that was busy at its
select, the restricted floor and z ignored, a data line taken for voice, no
PWAIT, PWAIT never clearing, no watch, a nail that writes its dest too, the type
bits read the old way, a source not listened to, no walk — and twenty for the
pulse-flood study's fixes: the connect back at the last digit, a claim waiting
for the line register or never refused, a leaf sweeping, a link outage counted
as a pulse (both trunk cards, one way, a channel group), a cannot-complete
written on a released port, a break before the seizure lost, no hunt
hold-off, no long break, no C_LOW, a claim on one sample or before `b`, cells
that never age, a forward that ignores its cancel, a leg never seen free, and
random traffic with a claim attached late. **Every one turns its bench red** on
the final tree — except two, green by design: the refusal landing after
`CLAIM`, whose rule is held twice (a second fault removing both holds is red),
and the unit's release on the no-digit timeout, a backstop that connecting at
the claim leaves no bench able to reach (`faults.py`'s header). A trunk's M is
held once where it matters: the unit's hold does not cover `tb_net` scenario
2's release tail, where only the marker's read of the trunk's word stops it,
and the bench checks that no trunk is ever given dial tone. **Only a named
check makes a verdict RED**: a bench that hangs is TIMEOUT, a copy that does
not build is BROKEN, a stale anchor is NOT-APPLIED, and `make faults` fails
unless every verdict is the contract's.

A review of the network RTL by four independent readers, each finding checked
by a skeptic trying to refute it, found five real defects before this tree
settled — the origin reading a sweep result a forward had just cleared; two
waiting lines starving the sweep; a hold on a seizure that died before the port
armed, left BUSY for good; a phantom flood when the called party hung up first;
and a second key after the call's own code. Each is fixed, each has its
scenario, and each has its fault in `faults.py`. `lfull`'s glare scenario
found a sixth: a far seizure reaching a channel in the pass or two before this
end's own seizure showed BUSY was held by the classifier as an incoming call,
over the origin's write, so one caller heard the other and the other heard
cannot-complete. The classifier now leaves alone every port the unit has
seized for itself (F35).

**What these do not cover**, so the count is not read as more than it is:

- `dial` drives the *nominal* corner, 28 ms. `dialling.md` §3.1 **measured**
  breaks as short as 18 ms at 20 pps once the line card's 6.1 ms and jitter are
  in. 18 ms is 18 samples against an 8-sample `HIT` window, so it holds — but
  nothing here drives it.
- `mini`'s seizure-latency check is **one sample** at 1 ms resolution against a
  2 ms bound. `ha`'s eight-phase sweep is what measures the worst phase.
- `mini` does **not** cover a called party already in a call (`marker.md`
  §3: M or `BUSY` up is 03) — the only case that reaches the `p_m || p_busy`
  branch rather than `called == caller`. That branch has never run.
- A claim arriving while the mini marker watches a connect **waits** rather
  than being refused (`att_refuse`). No bench provokes that coincidence.
- There are **no gate delays**, so `fabric.md` §2.2's hazard and §7's
  nanoseconds are outside what any of this can see.
- `net` and `chain` run the register, the port detectors and the protocol's
  timers **8× fast** through their straps. The word reads and the sweep are
  cable timing and do not scale, so the guard covers less than one hop there:
  its mechanism is tested, not its reach. No relayed pulse is measured at real
  speed.
- **Glare** is provoked only on the local trunk's last free channel
  (`lfull` 5): not on a baseband tie, not at a transit, and never with more
  than one channel free, which the word's `g` bit is there to prevent.
  No hub (a fan-out of two or more legs), no ring and its jumper, no two
  floods at once on one exchange (`net` 16 has two calls up at once, but its
  second flood starts after the first is connected), and no MF8.
- The network benches' phones are the socket's pins driven by hand, as
  `mini`'s are, not `cvsd_line_card`.
- The local trunk: `ltu` patches by hand, `lnet` and `lfull` dial across it
  and `lchain` transits two, but nothing sees the 512 kbps eye on a real
  cable, and no cut falls during a dialled call.
- The class marker runs in `max` with **no network unit**: a claim or a flood
  through it, and the walk's reads beside the unit's on `/WS`, are in no
  bench. One register and the primary octet: no covers, dual numbers or L/U/K
  conditions, no pool, no console. One private line and one one-way nail,
  and PWAIT against one P line and one plain line.

---

## 5. The documents

The specification was rewritten on 2026-09-26 to describe this tree
(`exchange/README.md`): the table of departures that stood here is gone
because the documents now say what the code does. Where a question is still
open, its owner's Open section says so, and `exchange/README.md` §5 lists the
ones that need a decision. What the old documents said and why it was
retired is `exchange/decisions.md`.

---

## 6. What is not settled

- **The 4.7 kΩ pull-up.** Each bus plane carries one drain a block, eight in
  all; a block ORs its eight ports' drains under 1 k on the header, ≈ 230 pF
  and a 0.23 µs rise by arithmetic (`exchange/block-stack.md` §3). The
  ≈ 300 pF and τ ≈ 1.4 µs this item used to give assumed 64 drains on the bus.
  Against 8.79 µs of settling it is still the **one place the fabric is near a
  limit**, and it is why the wire runs at 64 kHz and not 512 kHz. Nothing has
  analysed it; `exchange/bus.md` §7 owns the open item.
- **One conductor, one failure domain.** A single stuck open drain kills all 64
  ports' signalling where an A driver fault used to cost eight. Pulling a
  block's FIT jumper lifts its one drain off each plane, and the debugger's
  `HA_STUCK`/`HB_STUCK` lamps name the fault; a failed drain on the bus side or
  a short on the bus itself is still everyone's (`exchange/fabric.md` §8).
- **Relayed dial pulses.** Each exchange a pulse crosses re-samples it at 1 kHz
  where the old plane re-sampled at 64 kHz. `/HB` halves what this costs — the
  quantisation is 1 ms, not 2 — but nothing here measures a relayed pulse yet.
- **The word's secondary byte at 64 kHz.** A card reloads on `TX_OCT`, every
  eight frames, and the socket carries nothing that marks sixteen, so what a
  reader gets at a bit a frame is the primary octet. That is enough for a trunk
  and for everything this build reads. The class marker wants the secondary —
  covers, conditions, dual numbers — and needs a load strobe on the socket, or
  the card to shift the word at 128 kHz, or a second octet by another means
  (`card-word.md` §8). (The fails-open worry this item used to be was
  a misreading of the bit's polarity: §1.)
- **The hunt costs the guard.** A sweep is 9 ms whatever the exchange holds,
  and a transit's hop is mostly one sweep, about 12 ms by arithmetic.
  `monitor-rules.md` §4 budgeted a hop at 7 ms, 12 at a slow marker;
  `network.md` §6 now takes ≈ 12 ms typical, at which the 128 ms tap covers
  about ten hops, the 256 ms about twenty and the 512 ms about forty. Half that
  or less where a transit's own caller is sweeping as the seizure arrives,
  because the forward waits for that sweep, and the guard must cover the slow
  case: running past it is a wrong number, not a failed call (`network.md`
  §6). With the pointing word the sweep was
  17 ms and the 128 ms tap covered six. `topology.md`'s limits on long chains
  move with it and have not been re-run. It is the price of the card saying
  what it is, which Joel accepted.
- **One forwarder, one origin bank.** A seizure that arrives while the
  forwarder is sweeping is held and watched but not passed on (`n_nofwd` counts
  it). The unit has one origin bank because the mini marker has one register;
  a register pool wants one bank a register.
- **The queue is a model part, and the unit's writes want a sequencer.** In
  74HC a card's sequencer holds until its word is away, and there is no queue
  (`bus.md` §5). The unit decides up to five writes in one tick — a
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
  one each 18 ms. A seizure seen while the reader is busy — every frame of a
  sweep, which selects every nine — is kept and read ahead of the sweep's next
  step; left to wait, it waited out the whole sweep, and `faults.py` F19's
  crossing race stopped being reachable.
- **Cable B's second master, on paper.** `/UREQ` has its pin (`bus.md`
  §2.1), but the unit's `WAIT` of 640 ticks is derived from the marker's
  longest transaction — a written word, 545 ticks, and two to hand the '244
  back — by hand, not measured against it. `b_clash` is counted in every
  network bench and has never lit.
- **`/WS` spent a spare.** The bus had two, each with an owner in waiting — a
  second request line for a console ranked above the unit, and the input by
  which a trunk slaved the clock card to its far end. The slaving is retired
  (`exchange/decisions.md`), and the one spare left, pin 48, is kept for the
  console (`bus.md` §2.1, §5). `/WS` is also one more open drain sampled at the
  capture instant, on the same unanalysed 4.7 kΩ pull-up as `/HA`, `/HB` and
  `/HW`. And no lamp watches it: a select made inside another read's eight
  frames is what a faulty reader would do, and the debugger would not see it.
- **`SCLK` is not a tap here.** `ctl_write` counts its own bit-time off the
  4.096 MHz master, so the one rate in the design that is not a divider tap is
  hidden inside a module whose header calls itself two '165s. On a board each
  master (the marker and the network unit) takes it from `SLOT1`, 128 kHz on
  the bus, or counts its own; undecided (`exchange/bus.md` §7).
- **The MF8 block adapter is not written.** The adopted six-channel frame
  transmits in the fabric's clock (`trunks.md` §4), which wants a 1.024 MHz
  half-bit clock and `SLOT[2:0]` at the adapter. `LINE_HB` is no longer on the
  bus (`bus.md` §3), and the adapter commons, J6, carry `TX_CLK`, `TX_OCT`,
  `FILL`, `MUTE_BLK` and `HCLK` at 512 kHz, out of which 1.024 MHz cannot be
  divided; the options are `trunks.md` §5's. The baseband tie card came first
  instead.
- **74HC or 74LS.** Every document says 74HC at 5 V and `fabric.md` §7's whole
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
2. **The MF8 block adapter**, once its 1.024 MHz is settled (§6).
3. **The rest of the maximal build.** The class marker is in — `marker.v`,
   `top_max`, `tb_max` — with one register card and the word's primary
   octet. Left: the network benches run on `top_max` (a claim and a flood
   through the class marker have run nowhere); a register pool with a bank a
   register on the unit; the card word's secondary (§6); `console.v`. The
   fabric needs no change for any of it.
4. **`exchange/folded-a.md`**, the fold's own specification. This README and
   `PORT.md` stand in for it.
5. **A router, sketched and not built.** A tandem with no subscribers is `exch`,
   a network unit and trunk cards, and no marker at all: the unit has its own
   probe, its own cable-B master and reads the cards itself, and ports release
   themselves. It owns no code, so it never claims — it cannot refuse a call it
   cannot pass on, and cannot parent a PBX leaf. A stub marker with the claim
   path alone would give it a code. The unit already runs with no marker
   fitted; what a router wants first is more than one forwarder.
