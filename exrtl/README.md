# exrtl — the exchange in Verilog

A register-transfer model of the exchange of [`exch/docs`](../exch/docs): the
64 × 64 crossbar, the ports that supervise themselves, and the clock card, in
synthesisable Verilog. It is built the way the 74HC design is built — a '151 is
a `mux8`, a '273 is the port's `addr` register, the block has no address and no
comparator — so that the RTL and the documents can be read against each other.

> **Status: a network that dials.** The fabric, the mainboard and its serial
> control bus, the supervision, an MF8 trunk, and the common control — marker,
> registers, seekers and resolvers — run and are checked. The testbenches build
> networks out of whole exchanges: two on a link, three in a chain, **five round
> a hub**, **four in a ring**. Every shape `exch-network.md` §3 describes now
> runs — the flood, the transit, the fan-out of §3.2, the strap of §3.3 — and
> the monitor pool has been put against `exch-monitor.md` §4's sizing table with
> traffic rather than argument. Nothing has been on an FPGA.

**The hierarchy is the layout.** Each module is a thing you could point at in a
rack, and the module boundaries are the connectors.

```
 exch_top          ONE exchange -- the logic of mvp-ex.md 1, and nothing that plugs in
   clock_card      HCLK, SLOT, SLOTQ a quarter cell later, TX_CLK, TX_OCT, RX_OCT,
                   HB, FILL, the ring cadence, TICK          (exch-mainboard.md 2.1)
   mainboard       the ribbon's sixteen highway conductors, the eight BLK conductors,
                   and the SHUNT field that gives each block position its number
                                                             (exch-mainboard.md 1, 6)
   block  x8       four commutators, the write and strobe decoders, the ringback
                   '157s, and eight ports                    (exch-fabric.md 3.1)
     port x8       the crosspoint: '273, three '151s, a '74 pair   (exch-fabric.md 3.2)
                   the supervision: two detectors and the gates    (exch-fabric.md 3.5)
   mux8            a 74HC151.  The whole fabric is this part used three ways
   ctl_write       the serialiser for cable B: one 16-bit word on one wire
                                                             (exch-mainboard.md 2.3)

 marker            scanner, probe, hunt in fixed order from 00, the number
                   parsing of 2, the flood at both ends, and the fan-out and
                   RESOLVERS of a hub                         (exch-marker.md,
                                                              exch-network.md 3)
 pulse_reg         a register, one of a POOL: no port, no class, reads its
                   caller's hook off the M highway through its own probe, and
                   holds its own four-digit store              (register.md 4)
 monitor           the seeker, a POOL on each trunk block: the only part of the
                   network that reads a digit it was not sent (exch-monitor.md)
   pulse_rx        register.md 2's three windows off one timer, shared by both

 line_card         a card that plugs into a channel slot -- OUTSIDE exch_top, because
                   that is where it is                       (mf8-backplane.md 8)
 mf8_trunk_card    six channels of a block made into a tie trunk (exch-network.md 1)
   mf8_encoder     differential Manchester: a transition a cell, two for a 0
                                                             (mf8-spec.md 9.2)
   mf8_decoder     the classifier: times gaps, no PLL, nothing to lose
                                                             (mf8-spec.md 9.4)
   mf8_framer      F = 11111110, the guard at states 0 and 4, 32 to lock,
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
make mvp      mvp-ex.md: absent parts read as idle, and the hotline
make two      two exchanges, own crystals 100 ppm apart, both making calls
make trunk    two exchanges tied by one MF8 link, calls patched across it
make net      the same two exchanges, calls DIALLED: local, and the pulse flood
make chain    three exchanges, 22 = 23 = 24, and a call that transits 23
make monitor  the seeker's pool and the three terms of its seizure rule
make pool     two callers at once: two registers, two cells, one scanner
make hub      five exchanges: four directions, a fan-out, and the resolvers
make ring     four exchanges in a ring, and the strap that breaks it
make erlang   the monitor pool against exch-monitor.md 4's sizing table
make stress   a FULL exchange -- 48 lines -- under random traffic
make iv       the whole suite again under Icarus, as the reference
make ring-open    the same ring with the strap OUT: the flood circles
make erlang-long  the traffic run with enough calls to measure, not just check
make stress-pair      the stress run over two exchanges, 100 ppm apart
make stress-overload  48 callers thrashing a TWO-register exchange
make trunk-ppm    the link with the two crystals 100 ppm apart
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
`SLOTQ` still sits a quarter of a cell behind `SLOT`, where `exch-fabric.md`
§3.2 puts it. **This does not reproduce the §3.2 hazard** — a race between a
'138's address and its enable has no meaning in RTL, where nothing glitches by
construction. `SLOTQ` is here because the hardware has it, not because the model
needs it.

**Capture at mid-cell, sampled at the frame edge.** A port's '74 pair clocks at
tick 4 of the selected cell, and a card reads `C_RX` at the frame edge and
nowhere else. That gives the one frame of delay for every pair of ports that
`exch.py fabric` measured, whatever the two slots — which is what keeps octets
aligned (`exch-fabric.md` §3.4).

**No tri-state.** The highways have one driver a wire, so they are plain signals.
The probe bus `PB` *is* tri-state in 74HC, and here it is a mux with the same
observable behaviour: pulled low when no block is selected, so an absent block
reads as eight unequipped slots (`exch-mainboard.md` §6).

**Growing the exchange is changing a parameter.** `BLOCK_FITTED` and
`PORT_FITTED` default to the MVP of `mvp-ex.md` §1 — block 2 alone, port
circuits at 20 and 21, `RBT` strapped to `FILL`. An unfitted block's highway is
pulled to `FILL` and its `A` to ground; an unpopulated slot the same. Nothing
that is fitted changes when more is.

**The subscriber interface is four wires.** A card's subscriber side is `tx`
and `rx` (CVSD each way) and `m` and `e` (the hook out, supervision back) --
the names `exch-fabric.md` §3.5 uses throughout, and the same four leads as
`mf8-spec.md` §12.1's E&M card. The transformers, the 48 V phantom and the
128 kBaud line code of `subscriber-line.md` change no bit that reaches the
exchange, so they are left out. `e` already carries the ring cadence: the
port's own gates did that, not the card.

**More than one exchange.** Nothing in the RTL is global and every module takes
its clock as a port, so an exchange is a thing you instantiate. `make two` runs
a pair on crystals 100 ppm apart -- the plesiochronous case `mf8-backplane.md`
§2 assumes of any two ends of a link.

**The control bus is one word on one wire.** `exch-mainboard.md` §2.3: the
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
happen with a single register, which is why `exch-marker.md` §3 does not mention
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
say that **`exch-monitor.md` §4's seizure rule is not sufficient once an exchange
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
and worth holding against `exch-network.md` §3.1's 7 ms hop.

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
*The pool against `exch-monitor.md` §4* below is what came back.

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

### What a ring demands of the strap

`make ring` is 22 ═ 23 ═ 24 ═ 25 ═ 22 with the 25 ═ 22 link strapped at both
ends. The strap is the `n` bit of the trunk port's word, and both halves of its
rule were already in the RTL with nothing to close a loop on.

| measured | |
|---|---|
| a call two hops either way | every exchange sees it **once**: 8 channels, one on each of four links, and one turn only. 4 once the call is up |
| an origin on a strapped link | may still seize it, and the far end may still claim — the flood simply is not forwarded off it |
| a call to the far end of the strap | arrives **twice**, and both copies claim, as §3.3 says. No caller hears the second |
| the strap out, `make ring-open` | ONE call, **high-water 40 of the ring's 48 trunk channels**, and 8 still held once it is up against the strapped ring's 4. All of it releases when the caller hangs up |

**Which copy of a doubled call the origin keeps is decided by its scanner, not
by which claimed first.** §3.3 reasons that "the direct copy is a hop away and
the long one many, so the direct copy always claims first". It may well; **the
origin cannot tell**. It learns of a claim from its own scanner, which reaches a
given port once in 8 ms, and one hop against three is microseconds, so both fall
inside one visit and the **lower-numbered port wins**. Here the strapped link is
block 1 and the long way round block 0, so the call is set up the long way:
`make ring` counts six ports held in the ring where two would have done, and
three links carry the conversation instead of one. Nothing is misrouted and no
caller hears anything wrong — it costs channels, and a scanned marker cannot do
better without a latch a trunk.

**A trunk card must tie its `/ANS`.** A port whose card leaves `/ANS` open
rings, and `exch-fabric.md` §3.5's `A_RX` gate then chops that port's own
forward A into the ring cadence. A trunk port that does it sends the cadence
down the link instead of the caller's dial pulses — breaks that are not breaks
at this model's scaled cadence, and a hang-up every few seconds at the real one.
It never showed while trunks sat on blocks 0 and 1; the hub's third and fourth
directions are at ports 24–47, where the model's port map had left ringing on,
and nothing beyond the hub could read a digit.

### What the serial bus demands of a marker

Three things the RTL found in making `exch-mainboard.md` §2.3 work, none of
them in the document yet. They are the marker's, not this model's: a 74HC
marker on this bus needs all three.

**Steering the probe costs a visit, and the cost lands on slot 0.** The word
takes 31 µs at 512 kHz; the visit it governs takes its first `PB` sample about
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
is what that port's card says (`exch-network.md` §1). The card decides nothing
and holds no digits. A call across it is the hotline rule of `exch-fabric.md`
§3.5 running through the pair untouched: the far line rings because its port
sees E, and the caller hears ringback because the far port substitutes `RBT`
into its own highway cell — both of which `make trunk` watches happen across
two exchanges.

**A block does not know its own number.** `block`'s `H` parameter is carried so
an instance names itself in a waveform and is read by nothing. Which highway a
block drives is the `mainboard`'s `SHUNT` parameter -- three bits a position,
the three shunts in one silkscreened column of `exch-mainboard.md` §1. A
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
wrong number across the network, which is the one thing `exch-monitor.md` §3
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
`exch-marker.md` §6 sizes for 0.16 E, offered something nearer ten. In two
rounds, 199 callers lifted, **141 of them waited out dial tone and gave up**,
and four calls got through. Nothing was left held, no line was heard by two
callers, no port was stuck, and the write queue never overran. The exchange
degrades exactly the way §6 says a pool degrades — *a caller who finds no
register free is not refused, dial tone is late* — and it does not lock up.

## The pool against `exch-monitor.md` §4, measured

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

**`A out = E + CLAIM`** (`exch-fabric.md` §3.1) is the A the port hands its
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

- **The word's encoding.** `exch-protocol.md` §5 says a plain line card ties its
  word pin to ground and "reads all ones and means a line with no options",
  while `exch-fabric.md` §3.5's table gives *line* as class 001. Both cannot be
  right. The fabric uses the word for nothing, so the commutator is wired and
  the encoding left alone until the marker is built.
- **Detector tolerance.** `exch.py calls` draws each port's detectors ±20 % about
  256 ms, which is why `mvp-ex.md` §3 has 21 release at 6.266 s and 20 at 6.284.
  Here they are exact, so both ports release in the same frame.

## Next

1. **A testbench for the `SCLK` hazard** (`exch-mainboard.md` §7): a spurious
   shift puts the next write in the wrong port with the wrong source. It costs
   one call and does not persist, and it is worth watching it not persist.
2. **Two seizures inside one sweep.** An exchange has one forwarder and a
   forward is one scan, 8–9 ms; a seizure arriving while it is running is held
   `BUSY` and never forwarded at all, and the origin waits out its 2 s and gives
   cannot-complete. At the 0.26 E of §4 that is about one flood in a thousand —
   but that is arithmetic on the model, not a measurement, and no document
   mentions the case. `tb_hub` staggers its two floods to keep clear of it.
3. **The register pool against `exch-marker.md` §6**, which is a *delay* table
   and not a loss one: a caller who finds no register free is not refused, dial
   tone is late. `tb_erlang`'s generator would want a queue and a wait time
   where it now wants a blocked count.
4. **SS0** (`ex-ss0.md`) against the flood, on these same networks.
5. Nothing has been on an FPGA.
