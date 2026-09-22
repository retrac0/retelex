# verilog — the exchange in Verilog

A register-transfer model of the exchange of [`exchange/`](../exchange/): the
8 × 8 fabric, the ports that supervise themselves, and the clock card, in
synthesisable Verilog. It is built the way the 74HC design is built — a '151 is
a `mux8`, a '273 is the port's `addr` register, the block has no address and no
comparator — so that the RTL and the documents can be read against each other.

> **Status: a network that dials.** The fabric, the mainboard and its serial
> control bus, the supervision, an MF8 trunk, and the common control — marker,
> registers, seekers and resolvers — run and are checked. The testbenches build
> networks out of whole exchanges: two on a link, three in a chain, **five round
> a hub**, **four in a ring**. Every shape `network.md` §3 describes now
> runs — the flood, the transit, the fan-out of §3.2, the jumper of §3.3 — and
> the monitor pool has been put against `monitor.md` §4's sizing table with
> traffic rather than argument. **`make traffic` builds a network of up to ten
> whole exchanges out of three shape numbers and offers it demand that is not
> smooth** — bursts, a flash crowd, peak against off peak — and `exch.py traffic`
> runs the same network on the same clock, so the two are read against each other
> (`traffic.md`). Nothing has been on an FPGA.

**The hierarchy is the layout.** Each module is a thing you could point at in a
rack, and the module boundaries are the connectors.

```
 exch_top          ONE exchange -- the logic of mvp.md 1, and nothing that plugs in
   clock_card      HCLK, SLOT, SLOTQ a quarter cell later, TX_CLK, TX_OCT, RX_OCT,
                   LINE_HB, FILL, the ring cadence, TICK          (mainboard.md 2.1)
   mainboard       the ribbon's sixteen highway conductors, the eight BLK conductors,
                   and the SHUNT field that gives each block position its number
                                                             (mainboard.md 1, 6)
   block  x8       four commutators, the write and strobe decoders, the ringback
                   '157s, and eight ports                    (fabric.md 3.1)
     port x8       the crosspoint: '273, three '151s, a '74 pair   (fabric.md 3.2)
                   the supervision: two detectors and the gates    (fabric.md 3.5)
   mux8            a 74HC151.  The whole fabric is this part used three ways
   ctl_write       the serialiser for cable B: one 16-bit word on one wire
                                                             (mainboard.md 2.3)

 marker            scanner, probe, hunt in fixed order from 00, the number
                   parsing of 2.  Flood, forwarder and resolvers are net_unit
                                                             (marker.md,
                                                              common-control.md)
 net_unit          origin flood, transit forward, resolvers, CLAIM writes
                                                             (network.md 3,
                                                              common-control.md)
 mini_marker       a marker: one pulse_reg inside, two-digit local calls,
                   M and BUSY only, no card word; flood_go / CLAIM hooks
                   for a network unit                        (mini-marker.md)
 pulse_reg         a register, one of a POOL: no port, no class, reads its
                   caller's hook off HA through its own probe; four-digit store
                   plus a 6-bit SRC held-party field for operator transfer
                   (register.md 6.1)
                   caller's hook off the M highway through its own probe, and
                   holds its own four-digit store              (register.md 4)
 monitor           the seeker, a POOL on each trunk block: the only part of the
                   network that reads a digit it was not sent (monitor.md)
   pulse_rx        register.md 2's three windows off one timer, shared by both

 line_card         a card that plugs into a channel slot -- OUTSIDE exch_top, because
                   that is where it is                       (mf8-backplane.md 8)
 pulse_gen         hex buttons as pins: 10 pps on A_TX, no handset
                                                             (pulse-gen.md)
 su1               Autovon pad → pulses, mute, ring; handset cousin of pulse_gen
                                                             (su-1.md)
 mf8_trunk_card    six channels of a block made into a tie trunk (mf8-unit.md 1)
   mf8_encoder     differential Manchester: a transition a line bit, two for a 0
                                                             (mf8-spec.md 9.2)
   mf8_decoder     the classifier: times gaps, no PLL, nothing to lose
                                                             (mf8-spec.md 9.4)
   mf8_framer      F = 0xFFFE, the guard at states 0 and 8, 32 to lock,
                   two +2/-1 counters to track               (mf8-spec.md 3, 4)
```

`exch_top`'s edge is the 64 channel-slot pin groups and the two cables. Cards
are instantiated beside it, never inside it, which is why a port has no idea
what it is and why an MF8 trunk card can tap `hc[h]`/`ha[h]` from outside.

## Running it

**Two simulators run the same testbenches.** Icarus is the reference; Verilator
is about two orders of magnitude faster and is what to use while working. The
network testbench is 3 s of model time: minutes under Icarus, 22 s under
Verilator. Anything that passes under one must pass under the other.

```
make fabric   every source to every listener, bit-exact, one frame
make mvp      mvp.md: absent parts read as idle, and the hotline
make two      two exchanges, own crystals 100 ppm apart, both making calls
make trunk    two exchanges tied by one MF8 link, calls patched across it
make net      the same two exchanges, calls DIALLED: local, and the pulse flood
make chain    three exchanges, 22 = 23 = 24, and a call that transits 23
make monitor  the seeker's pool and the three terms of its seizure rule
make pool     two callers at once: two registers, two cells, one scanner
make hub      five exchanges: four directions, a fan-out, and the resolvers
make hub-fwd  hub scenario 4 alone: two seizures inside one forwarder sweep
make ring     four exchanges in a ring, and the jumper that breaks it
make erlang   the monitor pool against monitor.md 4's sizing table
make stress   a FULL exchange -- 48 lines -- under random traffic
make regs     marker.md 6's axis: NREG = 1, 2, 3 at a fixed 48-line load
make traffic  a NETWORK under demand that is not smooth: bursts, herds, peak
make sclk     mainboard.md 7: a spurious SCLK edge mid-shift, and that it heals
make priority  extensions.md 2.4.1: a priority lift waits out non-priority under overload
make word     the card word: class, answers-to, call nail, tied nail, plain FF, zero
make groups   groups.md §2: answers-to hunt, digit 0 → pilot 04, cover
make pulse_gen pulse-gen.md: hex buttons, 10 pps, a call with no handset
make su1      su-1.md: Autovon pad, mute, ring trip, a local call
make mini     mini-marker.md: two lines, one register, no card word; 1 is a highway
make iv       the whole suite again under Icarus, as the reference
make chain-delay  the chain with 20 ms of CARRIER on every link
make ring-open    the same ring with the jumper OUT: the flood circles
make erlang-long  the traffic run with enough calls to measure, not just check
make stress-pair      the stress run over two exchanges, 100 ppm apart
make stress-overload  48 callers thrashing a TWO-register exchange
make trunk-ppm    the link with the two crystals 100 ppm apart
make traffic-net      EIGHT exchanges, off peak and then peak, measured
make traffic-models   the same eight, one run an arrival process and holding law
make traffic-deep     TEN exchanges: the same two hubs, spokes two deep
make lint     verilator, the whole exchange fitted
make synth    yosys: what the 64-port exchange costs in cells
```

| | Icarus | Verilator |
|---|---|---|
| `fabric`, 29 ms of model time | seconds | **0.28 s** |
| `trunk`, 70 ms | ~5 s | **0.72 s** |
| `net`, 3 s | minutes | **22 s** |
| `hub`, 5 s over five exchanges | many minutes | **2 min** |
| `erlang`, 4 100 s of offered traffic | 2 min, at a tenth the calls | **23 s** |
| `erlang-long`, 49 000 s | — | **6 min** |
| `stress`, 5.4 s over a 56-port exchange | — | **3 min** |
| `stress-pair`, the same over two | — | **12 min** |
| `traffic`, 3 exchanges, 22 s of model time | — | **7 min** |
| `traffic-models`, one of the five, 8 exchanges, 12 s | — | **32 min** |
| `traffic-net`, 8 exchanges, 34 s | — | **58 min** |
| `traffic-deep`, 10 exchanges, 30 s | — | **75 min** |

**`erlang` is not a system test and does not pay for one.** It drives a block's
eight M and `BUSY` lines directly, and it drops the 4.096 MHz master clock: a
monitor sees only the 8 kHz octet mark and the 1 kHz tick, so the bench keeps
their 8:1 ratio and spends 8 clocks on a millisecond instead of 4096. Every
count the monitor makes is the count it makes in the exchange — the windows are
the real 8, 128 and 256 ms — and **an hour of offered traffic costs 23 seconds**,
fourteen hours of it six minutes. Under Icarus the Makefile cuts it to a tenth
of the calls: there it checks that the two simulators agree, not the figures.

## What is decided here, and why

**One clock: the clock card's own 4.096 MHz crystal** (`mf8-spec.md` §9.1).
Eight master ticks to a 512 kHz cell, eight cells to a frame, eight frames to an
octet. Everything the 74HC design does with separate clock wires comes out here
as strobes on that one domain, so the model is synchronous throughout and
`SLOTQ` still sits a quarter of a cell behind `SLOT`, where `fabric.md`
§3.2 puts it. **This does not reproduce the §3.2 hazard** — a race between a
'138's address and its enable has no meaning in RTL, where nothing glitches by
construction. `SLOTQ` is here because the hardware has it, not because the model
needs it.

**Capture at mid-cell, sampled at the frame edge.** A port's '74 pair clocks at
tick 4 of the selected cell, and a card reads `C_RX` at the frame edge and
nowhere else. That gives the one frame of delay for every pair of ports that
`exch.py fabric` measured, whatever the two slots — which is what keeps octets
aligned (`fabric.md` §3.4).

**No tri-state.** The highways have one driver a wire, so they are plain signals.
The probe bus `PB` *is* tri-state in 74HC, and here it is a mux with the same
observable behaviour: pulled low when no block is selected, so an absent block
reads as eight unequipped slots (`mainboard.md` §6).

**Growing the exchange is changing a parameter.** `BLOCK_FITTED` and
`PORT_FITTED` default to the MVP of `mvp.md` §1 — block 2 alone, port
circuits at 20 and 21, `RBT` tied to `FILL`. An unfitted block's highway is
pulled to `FILL` and its `A` to ground; an unpopulated slot the same. Nothing
that is fitted changes when more is.

**The subscriber interface is four wires.** A card's subscriber side is `tx`
and `rx` (CVSD each way) and `m` and `e` (the hook out, supervision back) --
the names `fabric.md` §3.5 uses throughout, and the same four leads as
`mf8-spec.md` §12.1's E&M card. The transformers, the 48 V phantom and the
128 kBaud line code of `subscriber-line.md` change no bit that reaches the
exchange, so they are left out. `e` already carries the ring cadence: the
port's own gates did that, not the card.

**More than one exchange.** Nothing in the RTL is global and every module takes
its clock as a port, so an exchange is a thing you instantiate. `make two` runs
a pair on crystals 100 ppm apart -- the plesiochronous case `mf8-backplane.md`
§2 assumes of any two ends of a link.

**The control bus is one word on one wire.** `mainboard.md` §2.3: the
marker's whole output is sixteen bits — a guard, `DST`, and the port's '273
verbatim — broadcast to every block, and the block that answers `WR` is the one
its shunt column names. One consequence the RTL made plain: **`/BLK` steers the
probe as well as the write.** The block that drives `PB` is the block the shift
register names, so the marker cannot probe a block without first shifting a word
naming it. `ctl_write` takes a `strobe` input for that — low, it shifts the word
and never pulses `WR` — which is safe only because nothing reads a block's shift
register outputs until `WR`.

### What a pool demands of a marker

Five races, and four of them exist only because there is more than one of
something. Every one had the same shape, and the rule is worth stating on its
own: **an event on a wire is a race; a level that is valid when read is not.**

| | |
|---|---|
| a claim as a one-cycle pulse | held request, acknowledged one at a time |
| a digit as a strobe | the register's own store, read as levels |
| the store after a restart or an attach | a hold-off, because the write takes a cycle to land; and an idle store is an EMPTY store |
| one register offered to two callers in one cycle, since a stage only changes at the clock edge | a blocking mask of what has been given out *this* cycle |
| one caller given two registers | skip a port some call already has as its caller |
| two calls starting a hunt at once, with one scanner | the hunt has an owner, and a call waits in `M_WANT` for it |

**And one that is not in the documents at all.** Two registers can finish
dialling the *same* number inside one 8 ms scan. They probe the called port at
the same visit, both see `BUSY` clear, and **both write its latch** -- one
caller silently patched to a line that is ringing for someone else. It cannot
happen with a single register, which is why `marker.md` §3 does not mention
it; any marker serving more than one call at a time needs the arbitration, in
74HC as much as here. It is ordinary glare and takes the ordinary answer: the
first takes the line, the second gets busy.

`make pool` has both of A's lines dial exchange 23 in lockstep, pulse for
pulse, which exercises all of it at once -- and in its second half has them
dial the *same* number, checking from outside that exactly one caller is
talking to B's line and exactly one hears B's cannot-complete tone across the
trunk.

### What a transit demands of a monitor

Three findings from building the chain, all in the same place, and together they
say that **`monitor.md` §4's seizure rule is not sufficient once an exchange
has outgoing trunks of its own**. An end of a chain never shows any of it; a
transit shows it on every call.

**A returning claim looks like a seizure.** When the far exchange claims,
backward A rises — and at a transit that is M rising on its *outgoing* trunk,
which satisfies "M high, and low at the last visit" exactly. A monitor is then
held for the whole call, counting a level that never pulses. §4's Erlang tables
size the pool on a monitor being held for one or two digits, so a chain would
exhaust it.

**Gating on `BUSY` live loses one seizure in eight.** Both scanners step on the
8 kHz octet mark, but the monitor covers eight slots and the marker sixty-four
ports, so the marker reaches a port first about one time in eight — and a live
`BUSY` test throws those seizures away.

**The discriminator is order, not state.** `BUSY` *as of the last visit*, on the
same cadence as M. This exchange writes `BUSY` when it seizes or patches a
trunk, and the far end's answer raises M long after, so a claim's rise always
finds `BUSY` already set at the previous visit; an arriving seizure's rise never
does. Immune to the scan race rather than subject to it.

And one of timing: **a hop cost about three scans** until the forwarder was made
to sweep from where the seizure was seen rather than from port 63. Two now, of
which one is the marker's own detection latency — inherent to a scanned marker,
and worth holding against `network.md` §3.1's 7 ms hop.

**The pool is the thing §4 is really about.** Its sizing table -- two a block to
four exchanges, three to twenty, four to thirty-six -- is the loss to callers
whose calls this exchange owns, and none of it exists with a single cell. The
monitor is now a pool: one scanner over the block's eight slots, a cell each
with its own timer, and a seizure that finds none free going **unwatched here,
for good**. The exchange still passes the call on; it just cannot be the one
that owns it.

`make monitor` drives the eight M and `BUSY` lines directly, because the
interesting cases cannot be reached from a system test: two seizures on one
block would need two callers dialling at once, and one register serves one
caller. §4's Erlang argument is measured the same way and for the same reason:
`make erlang` offers a block's eight lines the traffic of a whole network, and
*The pool against `monitor.md` §4* below is what came back.

### What a hub demands of a marker

`make hub` is five exchanges: a hub with four directions — W, E, N and S, on
blocks 0, 1, 3 and 4 — and a leaf on each. A transit on a chain forwards into
its one other direction and forgets the call. A hub forwards into three, and
**the incoming trunk can listen to only one of them**: it goes on listening to
idle with `BUSY` set, so backward A stays 0 and nothing has claimed, while every
leg listens to *it* and the caller's pulses go down all three at once. Latches
cannot be read back, so the hub remembers the call in a **resolver** until a
leg's M rises.

| measured, `make hub` | |
|---|---|
| a flood through the hub | **4 trunk channels** while it is out — the one in, and one on each of three legs — for the 2.2 s `e` and `b` take |
| after the claim | **2**, and the resolver back in the pool: the other two legs are pointed at idle, and their links go with them |
| the hub as the owner | **1**. Its own monitor claims, as any owner does, and every leg is pointed at idle |
| speech through it | 0 wrong in 384 bits each way at **7 frames over two hops** — what a chain's two hops cost, because after the claim a hub is two latches like anything else |
| the one resolver busy | a second flood **takes one leg, not three**: 6 channels at the hub, not 8. `make hub` has that caller want an exchange behind the leg taken, and the call completes; had they wanted one of the other two it would have been lost, which is what §3.2 says to expect |

**A transit must hold the pair until the call resolves — on a chain as much as
at a hub.** §3.2 says a chain transit "forwards into its one other direction:
two latches, and it holds nothing", and §3.1's own timeline needs more than
that: when 24 claims, "the patch toward 25 [is] cleared", and 25's port releases
itself 256 ms later. **A marker that forwarded and forgot cannot clear it** — it
no longer knows which port it wrote, and latches cannot be read back — so the
onward link, and every link beyond it, stays seized for the whole conversation.
The answer is the resolver it already has: a one-leg forward takes one too, and
is patched straight through so backward A comes back as it always did. `make
ring` measures it, on an exchange that forwards a call and then turns out to own
it: 24's two blocks hold **one** channel after it claims, not two.

The cost lands on every exchange that is not a leaf, not only on hubs: ≈ 4½
packages a resolver, and §3.2's own erlang figures say two or three of them.

### What a carrier's delay demands of the guard: nothing

`network.md` §1.1 allows a trunk's carrier "about 2 ms of A path a hop", and
the origin's 128 ms guard (`monitor.md` §3, rule 2) is sized on the flood
crossing the network inside it. A leased circuit, a radio, a mux or a jitter
buffer is tens of milliseconds a hop, which looks like it must eat that guard.

**It does not, and `make chain-delay` is why.** `line_delay` puts 20 ms of
constant one-way delay on every link of the three-exchange chain — 160 ms in the
world, because this bench dials eight times fast and its guard is 16 ms, not 128.
C's monitor is then patched in **40 ms after the origin seized, two and a half
times the guard**, and all thirteen checks pass: the seizure is forwarded, both
monitors catch it, 24 claims and 23 lets go, the line rings, answers and releases.

The reason is that **the seizure and the caller's pulses are the same wire**. A
trunk's forward A *is* the caller's hook; the flood's seizure is that signal going
high and the dial pulses are breaks in it. Delay the wire and both move together,
so a monitor 40 ms out in absolute time still sees the rise before the first break
reaches it. What the guard is counting is only the part of a hop where the signal
**restarts** — the marker reading M and writing the onward latch — which is what
the flood's 7 ms a hop is mostly made of. `monitor.md` §5.1 has it measured
to 160 ms a hop and 1.17 s across seven, at 0 false claims in 1 000 calls, and has
the thing that *does* cost the guard: delay the carrier **loses** between the
seizure and the next digit.

`make chain` runs the same bench at `DLY=0` and its speech checks with it; the
bit-path comparison is skipped when there is a carrier, because it aligns over a
few frames and a carrier is thousands of them.

**The guard is a parameter here and a jumper there.** `marker`'s `T_GUARD` is
128 ms, which `monitor.md` §3.5 now makes one setting of three — 128, 256 and
512 ms, three adjacent stages of the counter the sequence already runs on — and
the one number in the protocol that says how big the network is. The system
testbenches pass 16, which is that 128 at their eight-times-life scaling.

### What a ring demands of the jumper

`make ring` is 22 ═ 23 ═ 24 ═ 25 ═ 22 with the 25 ═ 22 link jumpered at both
ends. The no-forward jumper is one plug a compass direction on the network unit, not a bit
of the trunk port's word, and both halves of its
rule were already in the RTL with nothing to close a loop on.

| measured | |
|---|---|
| a call two hops either way | every exchange sees it **once**: 6 channels, one on each of four links, and one turn only. 4 once the call is up |
| an origin on a jumpered link | may still seize it, and the far end may still claim — the flood simply is not forwarded off it |
| a call to the far end of the jumper | arrives **twice**, and both copies claim, as §3.3 says. No caller hears the second |
| the jumper out, `make ring-open` | ONE call, **high-water 40 of the ring's 48 trunk channels**, and 8 still held once it is up against the jumpered ring's 4. All of it releases when the caller hangs up |

**Which copy of a doubled call the origin keeps is decided by its scanner, not
by which claimed first.** §3.3 reasons that "the direct copy is a hop away and
the long one many, so the direct copy always claims first". It may well; **the
origin cannot tell**. It learns of a claim from its own scanner, which reaches a
given port once in 8 ms, and one hop against three is microseconds, so both fall
inside one visit. Under the settled map the jumpered link is block 3 and the
long way is block 1; `make ring` keeps the jumper (two ports on one link), which
is what §3.3 wants. Nothing is misrouted and no caller hears anything wrong —
a scanned marker cannot do better without a latch a trunk.

**A trunk card must tie its `/ANS`.** A port whose card leaves `/ANS` open
rings, and `fabric.md` §3.5's `A_RX` gate then chops that port's own
forward A into the ring cadence. A trunk port that does it sends the cadence
down the link instead of the caller's dial pulses — breaks that are not breaks
at this model's scaled cadence, and a hang-up every few seconds at the real one.
It never showed while trunks sat on blocks 0 and 1; the hub's third and fourth
directions are at ports 24–47, where the model's port map had left ringing on,
and nothing beyond the hub could read a digit.

### What the serial bus demands of a marker

Three things the RTL found in making `mainboard.md` §2.3 work, none of
them in the document yet. They are the marker's, not this model's: a 74HC
marker on this bus needs all three.

**Steering the probe costs a visit, and the cost lands on slot 0.** The word
takes 125 µs at 128 kHz; the visit it governs takes its first `PB` sample about
1 µs in, so **a re-point can never complete before the visit it is for**. The
first visit of every block therefore reads the *previous* block's `BUSY` and
word — and in the port map that is `00`, `10`, and the first line of every
block of lines. Port 20 is slot 0 of block 2, so the MVP's own caller is the
first thing this breaks. The marker needs a validity interlock, and a scanner
that can **hold** for one visit and repeat the disturbed one rather than lose
it. That is about one visit a block: a 64-port scan goes from 8 ms to 9 ms.

**Once the scanner can stall, anything keyed on "a visit happened" is wrong.**
It must be keyed on the scanner actually *advancing*. Two things that were
correct on the parallel bus are not on this one: "a block turns over", which
keyed on the octet mark and slot 7 — a stalled scanner sits *at* slot 7, so
every repeated visit queued another re-point and every re-point stalled it
again, a livelock; and the hunt's sweep, which terminates at port 63 — a
repeated visit of port 63 ended the sweep the instant it began, so no free
trunk was ever found.

**§7's `SCLK` hazard is slightly better than written.** A stray shift corrupts
the next write, which is one call, as the document has it. It also mis-points
the probe — but the marker re-points at the next block boundary regardless, so
that half self-heals within a millisecond.

**A trunk is a pair of ports back to back, and nothing else.** What a trunk
port hears from its own fabric goes out on the line; what comes in off the line
is what that port's card says (`network.md` §1). The card decides nothing
and holds no digits. A call across it is the hotline rule of `fabric.md`
§3.5 running through the pair untouched: the far line rings because its port
sees E, and the caller hears ringback because the far port substitutes `RBT`
into its own highway cell — both of which `make trunk` watches happen across
two exchanges.

**A block does not know its own number.** `block`'s `H` parameter is carried so
an instance names itself in a waveform and is read by nothing. Which highway a
block drives is the `mainboard`'s `SHUNT` parameter -- three bits a position,
the three shunts in one silkscreened column of `mainboard.md` §1. A
position whose shunts are left out drives nothing and its column is pulled to
`FILL`; two positions shunted onto one column read as `x`, which is what two
'244s on one conductor are. Layout, not logic.

## The link, measured

`make trunk` — two exchanges, one MF8 pair each way, the console patching
latches at both ends:

| | |
|---|---|
| both framers acquire | **38 frames** after reset — `mf8-spec.md` §4.1 measures 37–86 |
| re-acquire after the link is cut and restored | 33–55 frames |
| speech, each way, each channel | **0 wrong in 400 bits**, at a delay of 3–4 frames |
| two calls at once on channels 1 and 2 | same delay on both: no crosstalk |
| the link cut with two calls up | squelch, both framers unlock, **every call releases itself** |

**Crystal offset.** At 0 and 100 ppm the speech paths are bit-exact; at 100 ppm
a slip is one bit in 10 000 frames and the 400-frame window sees none, as
`mf8-backplane.md` §7 predicts. Driven far past the specification — 5 000 and
20 000 ppm, 50× and 200× the ±100 ppm the design assumes — the framer still
locks in 38 frames and the calls still run; what appears is **ten isolated
wrong bits in 400**, clustered at the slips, and not a broken link. That is the
failure mode the design was built for: a slip costs a bit, not a call.

## A full exchange under load, and what it turned up

Everything else in this suite drives a scenario someone thought of. `make
stress` fits every block — **48 lines**, the two tones and six trunk channels,
which is the whole 64-port exchange — and lets forty-eight callers loose on it
with no scenario at all. `make stress-pair` does the same on two exchanges tied
by one MF8 link **100 ppm apart**, with a quarter of the calls crossing it, and
`make stress-overload` gives the same forty-eight callers a TWO-register
exchange, where almost nothing completes and the only question is whether
anything jams.

**The callers do not behave.** One in ten hangs up in the middle of dialling;
one in ten dials into block 1, which is the network key followed by nothing; one
in ten dials its own number; one in twenty lifts and never dials; one in five
flashes the hook in the middle of a call; one in ten lifts again before its own
port has finished releasing; and a third of them dial the same four numbers, to
make glare likely rather than merely possible. They do wait for dial tone,
because a register pool means dial tone is late and a caller who dials into a
register nobody gave them is testing nothing.

**Two invariants do the work, and neither needs to know what the call was.**

- **Every line says who it is listening to.** Each one transmits its own name —
  eight ones, then a zero, its exchange and its port — so the bench can read
  off the whole connection graph, frame by frame, and hold it to three rules:
  *i hears j implies j hears i*; *no two lines hear the same line*, which is two
  callers patched to one line; and *no port hears itself*. A patch is allowed
  forty milliseconds to settle before any of it counts.
- **Nothing may be held when nobody is calling.** The traffic runs in rounds: a
  burst, then every line on hook and a gap longer than any release detector. At
  the end of the gap no port may be BUSY, no register busy, no trunk channel
  seized. A leak shows as a number that ratchets up round on round. During a
  round, a port that has been BUSY for 300 ms *and* on hook for 300 ms *and*
  with its E dead for 300 ms is reported where it stands, with the last latch
  write the marker sent it.

  **All three of those, or the check is worthless.** Written with only the last
  two it fires the instant a port is written to ring: the line has been on hook
  and its E dead since long before the write, and the cadence takes a few
  milliseconds to appear. That version reported seven jams in one round and
  every one of them was a call being set up correctly.

**What it found, and the answer is a bus.** The marker tells a register which
port to listen to on `reg_port` — one set of lines to the whole pool, the way a
74HC marker's port lines are one bus. Two things hand out a register: a
monitor's **claim** ("this call is ours: give it a register and the trunk's
port") and a **line lifting** ("give it a register and its own port"). A mask
already stopped them being handed the *same* register. But both wrote
`reg_port`, and the second writer won, so **both registers latched the line's
port number**. The claimed trunk's register would then count the line's dialling
and the marker would connect the far caller to whatever that line asked for — a
wrong number across the network, which is the one thing `monitor.md` §3
exists to stop.

The rule is **one attach a cycle**: a caller who lifts in the same cycle as a
claim waits a scan, and they are waiting for dial tone anyway. An arriving trunk
*seizure* is not deferred, because it needs no register. The marker counts the
deferrals, so the cost of the rule is measured and not assumed.

It is a load-dependent race and not a one-in-a-million one: a claim is a level
held until the marker takes it, and the marker holds it off while its write
queue is within five of full. Under load that moves the cycle on which the claim
is taken off the tick that decided it and onto an arbitrary one — including a
visit with a line waiting for dial tone.

**And a clean result: overload does not jam it.** `make stress-overload` gives
the same forty-eight callers a **two**-register exchange — the pool
`marker.md` §6 sizes for 0.16 E, offered something nearer ten. In two
rounds, 199 callers lifted, **141 of them waited out dial tone and gave up**,
and four calls got through. Nothing was left held, no line was heard by two
callers, no port was stuck, and the write queue never overran. The exchange
degrades exactly the way §6 says a pool degrades — *a caller who finds no
register free is not refused, dial tone is late* — and it does not lock up.

## A network under demand that is not smooth

`make stress` asks whether a full exchange jams. `make traffic` asks a different
question of a whole *network*: **when does it block, and does the shape of the
demand change the answer.** There is no scenario in it. The inputs are a topology,
an arrival process and a holding-time law; what comes out is erlangs and loss, link
by link and pool by pool, in the gates.

**The topology is arithmetic**, so the same testbench is three exchanges or ten: a
chain of `NHUB` hubs, `SPOKE` spokes on each, each spoke a chain of `SLEN`. `NHUB=1
SPOKE=4` is a star; `NHUB=2 SPOKE=3` is `network.md` §5.1's reference shape;
`NHUB=2 SPOKE=2 SLEN=2` is a backbone with spokes two deep and a transit on every
one of them. A `net_site` is instantiated for each, its direction slots packed from
0, and the link between any two is `assign lin[i] = lout[peer]` — no wires by hand.

**Everything about the demand is a plusarg.** Eight exchanges take a quarter of an
hour to verilate and compile — the exchange's combinational cone comes out as one
C function an exchange and g++ is superlinear in it, which is what `--output-split`
in the Makefile is for — and an hour to run. So the network is
compiled once and `+model=`, `+holdm=`, `+secs=`, `+op=`, `+pk=`, `+warm=`,
`+leave=`, `+seed=` decide the rest when the binary starts.

| the arrival process | |
|---|---|
| `+model=0` **smooth** | a line's idle is exponential about the mean: Poisson arrivals, and what Erlang B assumes |
| `+model=1` **bursty** | the same mean in bursts — the network goes hot and cold together, 1 s hot in 6 at eight times the rate |
| `+model=2` **herd** | a flash crowd: a third of every line in the network lifts inside 300 ms and **they all dial the same exchange** |
| `+holdm=0,1,2` | the conversation exponential, constant, or a two-class mix of nine short calls to one ten times as long |

**One crystal, not eight.** Staggering the clocks costs the simulator an evaluation
point for every exchange — the three-exchange run is 1.8× slower with them — and
buys nothing a traffic run reads. The plesiochronous case is `make trunk-ppm` and
`make stress-pair`; `-GSTAGGER=1` at build time is there if it is ever wanted here.

**Every phase is measured after a warm-up of twice the longer idle**, because a
phase begins with every line on hook, which is not a state the network is ever in
otherwise: a line that has not lifted yet is a first lift still to come, whatever
rate the run was asked for. Warm for less than an idle and the whole phase is that
transient — thirty-six lines at 6 s between calls and about a second a call is
5.1 calls a second, and a run warmed for 2 s offered **8.5**, every one of the extra
being a line lifting for the first time. `exch.py traffic` warms the
same way, which is what makes the two runs the same experiment.

### A delay is a 32-bit expression

The first long run of this bench was wrong and said so nowhere. `#(SECS * 1000 *
NS)` is arithmetic on `integer`s — `NS` is 1 000 000 and `SECS` twenty — and
2 × 10¹⁰ does not fit in 32 bits. **A twenty-second phase silently became 2.8
seconds**, a six-second warm-up 1.7, and every erlang in the run was a real
measurement over a window nobody chose. Nothing warns: the multiply wraps at
elaboration, the delay is honoured, and the only sign is `$finish at 11s` at the
foot of a run that should have been fifty-three.

It is caught by comparing the calls a second against the calls: 104 lifts at
26.6 a second is a 3.9 s phase, whatever the header says. The fix is to wait a
millisecond at a time — `for (w = 0; w < ms; w = w + 1) #(NS)`, where the
constant is 10⁶ and cannot wrap — and twenty thousand context switches over a
twenty-second run cost nothing beside 4 096 clocks a millisecond. It had not
appeared before because **nothing else in `verilog` waits longer than two seconds
in one `#`**: `tb_stress`'s round is `#(BURST * NS)` at 1 800 ms, which is
1.8 × 10⁹ and inside a signed 32-bit integer — but only just. Anything past
2 147 ms in that expression wraps the same way.

### A line is rung by a cadence, and reading it as a level doubles the traffic

The second thing this bench got wrong, and the one that matters if anyone writes
another. A caller in `S_RUNG` decided whether to answer by reading `e` — and `e`
while a line is being rung is `exch_top`'s ring cadence, which at this bench's
`RING_ON`/`RING_OFF` is a few milliseconds high and twice that low. **Read at one
instant it is low two thirds of the time**, so two callers in three decided the
ringing had stopped.

That alone would only have lost calls. What made it a measurement error is where
they went: back to `S_IDLE` with the timer *already expired*, so they lifted again
the same millisecond. **Every line rung and not answered became an extra call
offered**, and eight exchanges asked for 8 calls a second offered 17. The load is
not a number the bench is told; it is a number the bench has to produce, and
nothing checks it but arithmetic — 96 lines at 6 s between calls and about a second
a call cannot offer 17 a second, and that is the whole of how it was caught.

The cure is a few cadence periods of memory (`rseen`, 40 ms) instead of a level,
read both in `S_IDLE` to notice the ringing and in `S_RUNG` to answer it — and a
line that finds the ringing really has stopped now **waits an idle** like any other.
`tb_stress` reads the level the same way; there it costs answered calls and nothing
else, because its callers are a scenario rather than a load.

### What the runs say

**Eight exchanges at peak**, one run for each arrival process and each
holding-time law: 96 lines, a line lifting every 1.5 s, 8 s measured after 3 s of
warm-up. `make traffic-models`.

| | calls/s offered | talked | busiest link | registers | dial tone, mean / worst | waited a scan |
|---|---|---|---|---|---|---|
| smooth | 29.9 | 101 | 4.49 E of 6 | 1.91 E | 55 ms / 600 ms | 53 % |
| **bursty** | **19.4** | 84 | 3.62 E | 1.45 E | 31 ms / 352 ms | 26 % |
| **herd** | 38.0 | 101 | 4.65 E | 2.31 E | **141 ms / 1 197 ms** | **73 %** |
| constant conversation | 30.2 | 104 | 3.29 E | 1.63 E | 52 ms / 829 ms | 39 % |
| two-class conversation | 31.8 | 117 | 3.98 E | 2.18 E | 91 ms / 1 062 ms | 58 % |

**And the two networks at off peak and at peak**, `make traffic-net` (eight
exchanges) and `make traffic-deep` (ten, with a transit on every spoke): 10 s and
8 s a phase after 6 s of warm-up, a line lifting every 3 s off peak and every 1.5 s
at peak.

| | calls/s | talked | busiest link | registers | resolvers | dial tone | every link |
|---|---|---|---|---|---|---|---|
| eight, off peak | 20.9 | 114 | 3.46 E of 6 | 1.50 E | 0.85 E | 33 ms | 20.04 E |
| eight, peak | 33.1 | 121 | 4.76 E | 2.05 E | 1.24 E | 69 ms | 26.41 E |
| ten, off peak | 26.0 | 110 | 4.26 E | 1.58 E | 1.34 E | 39 ms | 35.59 E |
| ten, peak | 39.2 | 144 | 4.39 E | 2.04 E | 1.26 E | 71 ms | 34.59 E |

**The ten-exchange network is full**: every one of its nine links is between 3.4 and
4.4 E of six and every one reached six, and **at peak it carries less than off
peak** — 34.59 E against 35.59 — with half again the calls offered. `traffic.md`
§4 reads it beside the model, where the two agree on erlangs for each call a second
offered to **eight tenths of a per cent** at eight exchanges and five per cent at
ten.

Read beside `exch.py traffic` 2, which runs the same three arrival processes for
240 s instead of 8, the two agree on what matters and the RTL adds nothing the
model missed:

| at peak | calls/s, gates / model | busiest link, gates / model |
|---|---|---|
| smooth | 29.9 / 28.8 | 4.49 / 4.57 E |
| bursty | 19.4 / 17.5 | 3.62 / 3.45 E |
| herd | 38.0 / 30.1 | 4.65 / 4.70 E |

**A burst really does offer fewer calls, in the gates as in the model** — a fifth
fewer here and a third fewer there — because a line that is off hook cannot lift
and at eight times the rate the hot idle is shorter than a call. **A herd is the
one that moves the link**: it raises the marker's own *all trunks this way busy*
event from 3–17 a direction to **21–42**, and dial tone from 55 ms to 141.

### And a leak: a fan-out leg with no edge left to release it

**Every traffic run that offers the network a flood it cannot resolve leaves
trunk channels held.** The bench's own jam check catches it — every line on hook,
a second of quiet, and nothing may be `BUSY` — and it names the port and the last
latch write the marker sent it:

```
  JAM: 2 ports still BUSY with every line on hook
       22 port 11 (a trunk channel), last written 1795.3 ms ago: src 42 bsy 1 clm 0
       22 port 31 (a trunk channel), last written 1795.3 ms ago: src 42 bsy 1 clm 0
```

Ports 11 and 31 are blocks 1 and 3; port 42 is block 4. **That is a hub's fan-out**
(`network.md` §3.2): a seizure arrived on the fourth direction and was patched
out into two others, and when the call died without a claim the incoming trunk
released and *the legs did not*. A port releases on the **fall** of one of its two
detectors, and both of these were written after the source's A had already gone —
so neither detector has an edge left to fall on, and the port is held until
something writes it again.

**It is the hazard `rtl.md` already has, at a trunk instead of at a line.**
`make stress` checks for it directly (`no port was written BUSY with no edge left
to release it`) and reports it at HEAD on a line written to dial tone; this finds
the same shape on a hub's fan-out legs and on a chain transit's patch. `make
traffic` and `make traffic-net` therefore **report one to three held ports and
FAIL today**, and that is the check doing its job, not the bench being wrong —
everything else in both runs passes.

The smooth and the two holding-law runs pass; the bursty and herd runs do not.
What they have that the others have not is **floods that never resolve**: a herd
sends a third of the network at one exchange, most of those floods find no free
channel somewhere, and the origin times out 2 s later with the fan-out still
pointed at it.

**The two holding-time laws are NOT a result here.** Their means are equal and
`exch.py traffic` 3 shows the link carrying 4.55, 4.62 and 4.58 E over 240 s —
Erlang's insensitivity holding to half a per cent. Eight seconds is seventy
network calls, and seventy samples of an exponential holding time do not have a
stable mean; the 3.29 against 4.49 above is that and not physics. **The RTL is
where the mechanism is checked and the model is where the statistics are.**

## The pool against `monitor.md` §4, measured

§4 sizes the monitor pool with Erlang B on a load it argues from three numbers:
every call dialled with `1` anywhere in the network wants a monitor on each
block its flood reaches; a monitor whose `e` is the one dialled holds until `b`
is in, 2.7 s from the seizure; one whose `e` is not lets go after the first
digit, 1.5 s. `NMON` is a parameter, so `make erlang` offers the pool traffic
and counts the loss instead of arguing it, and it runs **four pools on one
stimulus** — two cells, three, four and five — so one run measures a whole
column of the table. A seizure is counted lost when every cell is busy *as it
arrives*, which is §4's own definition of the figure.

**First, what a monitor is actually held for.** The RTL's own windows, a dial at
10 pps 60/40 and 800 ms between digits. A hold is the caller's pauses plus the
pulses of the digits the monitor reads, so these three are one draw each and not
an average — the averages over real traffic are in the rows further down:

| from the seizure | measured | §4 assumes |
|---|---|---|
| `e` = 3, not ours: it lets go at once | **1.19 s** | 1.5 s |
| `e` = 2 ours, `b` = 5 not: it reads one more | **2.39 s** | 2.7 s |
| `e` = 2, `b` = 3, both ours: it **claims** | **2.19 s** | 2.7 s |

**And `done` must free the cell, or §4's load is out by a factor of six.** §2's
state list ends with *done — nothing more is read until the trunk releases (M
low for 256 ms)*, and the RTL did exactly that: a cell that had claimed stayed
held until its trunk went down. But the trunk of a claimed call is up for the
whole conversation. A leaf of eight exchanges takes about 43 incoming calls an
hour; at two minutes each that is **1.4 E of its own on top of the 0.26 E of
floods**, and a pool of three then turns away 17 % of them where the table says
0.2 %. Nothing else in the design notices, because M stays high for the call and
`seen` stays set, so the slot is never attended again either way — which is
exactly why the cell can be freed at the acknowledgement, and now is. *It reads
two digits and no more*, as §2 says in the line under that list.

**Then the loss.** `make erlang-long`, three thousand seizures at each of three
of §4's rows, offered to all four pools at once. The dial is 10 pps 60/40 with
500–1100 ms between digits, `e` and `b` drawn 0–7 with a dialled 0 as ten
pulses, and the arrivals Poisson:

| offered, measured | cells | Erlang B | measured | |
|---|---|---|---|---|
| **0.230 E** — eight exchanges, one `e` for all | 2 | 2.10 % | **2.03 %** | 61 of 3000 |
| | 3 | 0.16 % | **0.13 %** | 4 |
| | 4 | 0.01 % | 0.00 % | 0 |
| **0.360 E** — twenty, codes over eight `e` | 2 | 4.55 % | **4.77 %** | 143 of 3000 |
| | 3 | 0.54 % | **0.47 %** | 14 |
| | 4 | 0.05 % | 0.00 % | 0 |
| **0.849 E** — forty-seven | 2 | 16.32 % | **16.29 %** | 487 of 2989 |
| | 3 | 4.42 % | **4.38 %** | 131 |
| | 4 | 0.93 % | **0.94 %** | 28 |
| | 5 | 0.16 % | **0.10 %** | 3 |

**The loss is Erlang B's, and §4's recommendation stands**: three a block to
twenty exchanges and five beyond, with a little margin to spare.

**What §4 has slightly wrong is the load, and in the safe direction.** Its rows
read 0.26, 0.39 and 0.93 E; the model offers 0.230, 0.360 and 0.849, because a
monitor is held 2.38 s and not 2.7 where `e` matches and 1.40 s and not 1.5
where it does not. The first has a cause worth keeping: **with one `e` for the
whole network, that one digit is what every caller dials**, and here it is `e` =
2 — two pulses, 200 ms, against the 475 ms of an average digit. Share `e` = 0
and it is ten pulses, and the load goes the other way. §4 is 8–12 % high as
written, which costs nothing but a little pool.

One artefact to read past: a block has six trunk channels, and Erlang B assumes
arrivals that do not care what is already up. At the top row **11 of 3000
arrivals found no free channel** and were never offered to the pool at all.
They are counted, reported and left out of both sides.


## What it costs

`make synth`, all eight blocks and all 64 ports fitted, after `techmap`:

| | |
|---|---|
| cells | 19 454 |
| flip-flops | 2 856 |
| of which, the two release detectors | **1 920** — 30 of every port's 44 |

That last row is the honest difference between this and the hardware. In 74HC
the two detectors are a diode, two resistors, a capacitor and a Schmitt gate
each: **an RC, not a counter.** The RTL has to count frames to get 16 ms and
256 ms, and two 15-bit counters a port is two thirds of the whole design's
flip-flops. Anyone putting this on an FPGA pays that; anyone building it in
74HC does not.

## Two things the RTL settled

**`A out = E + CLAIM`** (`fabric.md` §3.1) is the A the port hands its
**card**, not its highway contribution. Three things agree: "2 × 74HC32" is
eight OR gates for eight ports; backward A goes up the link, which is fed from
`A_RX`; and the highway must go on carrying the far caller's dial pulses so that
a register at the claiming exchange can read `h s` off them. Put it on the
highway instead and the claim jams the register the claim itself summoned.

**A claimed trunk keeps `CLAIM` for the whole call it brought in.** The marker's
later writes to that port — dial tone off, the connect — must carry it, or
backward A drops and every patch behind it releases itself 256 ms later. Found
by `make net`: the call reached the far exchange, rang nothing, and the origin's
trunk let go.

## Open, and deliberately not guessed

- **Detector tolerance.** `exch.py calls` draws each port's detectors ±20 % about
  256 ms, which is why `mvp.md` §3 has 21 release at 6.266 s and 20 at 6.284.
  Here they are exact, so both ports release in the same frame.

**Closed: the word's encoding** (`common-cards.md` §2). All ones is the
constant *plain line*, from a grounded pin — `line_card.v`'s default `WORD`.
Class 001 is an explicit word for a line that has options to say. The marker
treats both as `C_LINE` (all-ones via the 74HC30 of `extensions.md` §2.2).

## Next

1. **The fan-out leak above.** A hub's legs, and a chain transit's patch, can be
   written after the call they were for has gone, and then have no edge left to
   release on. It is `rtl.md`'s hazard and the answer is the same one: either
   the marker must not write a port whose source is already down, or a port must
   release on a level and not only on an edge. `make traffic` reports it.
2. **SS0** (`ss0.md`) against the flood, on these same networks.
3. **Sixteen exchanges or more**, which `tb_traffic` will build from its three
   shape parameters and Verilator will not compile in a working day. What the
   suite has instead is `exch.py traffic`, which is the same network and the same
   demand in milliseconds and agrees with the gates at eight and at ten
   (`traffic.md` §§3–4), and `exch.py big`, which carries that out to the
   sixty-four codes.
4. Nothing has been on an FPGA.

**Measured (was Next 1–3):**

| | target | what it showed |
|---|---|---|
| **`SCLK` hazard** | `make sclk` | A spurious edge mid-shift mangles one write; the next clean word re-aligns; an idle-time edge costs nothing (`mainboard.md` §7) |
| **Two seizures / one sweep** | `make hub` §4, or `make hub-fwd` | Two lines at A dial `1` a hop apart: five channels at the hub (fan-out of four + one unforwarded inbound); the second origin hears cannot-complete; the first flood still completes |
| **`NREG` vs dial-tone wait** | `make regs` | Same 48-line thrash, idle 400–1200 ms. Gave up waiting for dial tone: **120 / 100 / 73** at `NREG` = 1 / 2 / 3; callers who got dial tone: 44 / 77 / 117; completed calls: 9 / 12 / 18. The pool size moves who gets through, as `marker.md` §6 says |
| **Answers-to hunt** | `make groups` | Digit 0 probes pilot 04, then the first free port that answers to 04. A busy number falls through to a member whose word answers to it. The adjacent `o` run is not in the marker |
