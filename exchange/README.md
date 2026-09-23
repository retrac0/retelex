# exch — an exchange at MF8's level of technology

A telephone exchange in 74HC and a few tuned analog circuits, that grows eight
ports at a time, takes every MF8 channel card unchanged, and is tied by MF8 both
to other exchanges and to subscriber terminals. No processor, no memory part in
the exchange logic. **An exchange is one 8 × 8 fabric — eight highways by eight
slots, 64 ports**: standalone, fifty-six dialable lines (10–77) with block 0
holding tones at 01–03 and a four-line bank at 04–07 (operator and kin);
networked, forty-eight lines (20–77) and the first MF8 trunk group on block 1
(11–13, 15–17 — six channels; 10 and 14 free), with further groups in blocks 2+
at the cost of those lines.
A network
is such exchanges in a chain, a ring, a star or a tree (an exchange faces up to
four directions): a handful on a chain, a score around a tandem hub. A line is dialled `h s` from its own
exchange and `1 e b h s` from anywhere when networked (standalone, 1 is a
highway digit): the key, the exchange's code (00–77,
sixty-four of them, with 00–17 kept for the backbone by convention) and the
line. 8 and 9 stay special in the code.

```
 card ── C, A each way ── port ──▶ 8-slot highway, 512 kbps, one per block ──▶ every block
                          port ◀── [ latch: highway | slot ] ◀── marker: hunt a class, write two latches
```

- **The internal protocol is the MF8 slot interface**: a 64 kbps bit stream and one
  signalling level each way. Bits are switched, never decoded: one codec pair end
  to end, over any number of exchanges.
- **The connection memory is a latch at each port**, so the fabric grows linearly
  and adding a block touches nothing installed.
- **Dialled digits are the address**: octal as dialled, ports 00–77.
- **Features are lines.** Operator, outside line, tones, announcements, a radio
  anyone may dial, a conference bridge are cards with a class mark; the marker's one special skill is
  hunting a class in fixed order. Nothing anywhere says where anything is.
- **Nobody is in charge of a call.** The marker writes two latches and leaves;
  ringing, ringback, answer and release are done by the ports.

## Documents

| | |
|---|---|
| [mvp.md](mvp.md) | **the minimum that makes calls**: two lines, one block, one register, no tones — what is fitted (≈ 70 packages of exchange logic), what an absent part reads as, a call and its release as the model ran them, wrong numbers, how each feature is added, bring-up |
| [common-control.md](common-control.md) | **proposed**: marker, register, network unit and monitor as replaceable units; the ribbons of levels between them; the solo exchange and a basic pulse flood on the same tap |
| [protocol.md](protocol.md) | the internal protocol, why it is bits and not voice band (measured), the highway fabric cell by cell (measured), numbering |
| [fabric.md](fabric.md) | **how the fabric is built**: the bus, the circuit of a block and of a port by part, the one timing hazard and its cure, no re-timing flip-flop, a cleared latch that means idle (00), supervision in gates, worst-case timing, package counts, **physical form** (shared board, **block header**, **block ribbon** with **slots**, port circuit with the card), **block adapter** (non-breakout mate of the same star), bring-up |
| [big-exchange.md](big-exchange.md) | **analysis**: a bigger fabric in 74HC is possible — 128 ports costs a third octal digit, and there is nothing honest to do with it; the exchange stays **8 × 8**, 64 ports, 512 kHz, one highway one MF8 group after conversion (`exch.py timing` 6) |
| [mainboard.md](mainboard.md) | **the mainboard**: the fifty-five signals in full, the two ribbons that carry them and their pinouts, why three signals a block cannot come down a ribbon and how a shunt gives them, what the cable costs the fabric's margins (18 ns of 743, measured), what an absent block or a missing shunt reads as, and the one signal on the bus whose glitch can lose a call |
| [marker.md](marker.md) | class marks, reading a number, the hunt, supervision and release — with the two faults the model found in the rule as first written — registers as a pool, dialling on the A line. The flood is the network unit (`common-control.md`) |
| [mini-marker.md](mini-marker.md) | **a marker**: one register inside, two-digit local calls, no card word — stays a marker if a network unit is added; **LEAF** / PBX leaf (`leaf-uplink.md`, `make mini-leaf`) |
| [nano-marker.md](nano-marker.md) | **proposed**: the mini-marker squeezed onto one board, 25 packages — a **three-bit** pulse count (8, 9 and 0 all read 0), a six-bit digit store that *is* the called number, no write queue, and one hunt serving two keys: an operator on `0`, an uplink group on `1`. Both skip open slots by asking whether the card word exists, without reading it, so a group may have gaps. Gives up `8` and `9` as keys of their own; its callers keep all ten on the far exchange (`make nano`) |
| [leaf-uplink.md](leaf-uplink.md) | **proposed**: PBX leaf off a central — network dials `1 e b g s` then leaf extension; leaf dials `1` for uplink dial tone |
| [features.md](features.md) | the features that are lines: registers, analog tones, ROM announcements and their seams, operator and console, the FXO card's one change, sources anyone may listen to (a radio, a clock), data |
| [conference.md](conference.md) | **proposed, switch measured**: meet-me conference block — attaches to the mainboard buses, private party bus, two×4 or one×8 bit-switched bridges, no codec |
| [register.md](register.md) | the register: dial pulses into a digit store in 74HC, pulse correction, measured end to end |
| [operator.md](operator.md) | **proposed**: the operator's **phone** — position at 04 (default), ordinary 0, night/second seat; transfer is console-only for now; phone flash deferred |
| [console.md](console.md) | **proposed**: the operator's console — forced release, service observing, connecting two lines, dialling a port and supervising both ends (and transfer) |
| [network.md](network.md) | **analysis**: tie trunks in up to four directions and on any carrier, `1 e b h s`, flood–monitor–claim with a worked call and its timing, the caller's own dial pulses as the network's signalling, how many exchanges an eight-channel link will carry, clocking, what was set aside (a register-sender; serial characters on A, measured) |
| [topology.md](topology.md) | **analysis, checked call by call**: the shapes a network may take — chains, stars, a tandem with chains, trees, a split centre — what each carries and where each stops; the upper limits of the protocol (36 exchanges, four neighbours, ten hops, about 1 300 lines); rings and loops, which work with one link jumpered and fail without |
| [terminal.md](terminal.md) | **proposed**: subscriber terminals — a trunk block with its class set to line, a stock MF8 shelf of channel cards at the far end, six lines at another site; why the cards need no change, the class a channel at a time, clocking and the case for loop-timing a terminal |
| [mf8-unit.md](mf8-unit.md) | **adopted** exchange face: six-channel MF8 as a **block adapter** on the **block header**; **not taken**: eight-channel payload split / 10- and 16-bit frames (`mf8-spec.md` remains live frame) |
| [local-trunk.md](local-trunk.md) | **proposed**: local eight-channel highway trunk — short-range copper, a **block adapter** on the **block header**, bidirectional highway-shaped `C`/`A` with `HCLK`/`TX_CLK` carried so RX is master-timed by the far exchange |
| [rtl.md](rtl.md) | **measured**: what building the exchange in Verilog found — ten things these documents did not say, or said in a way that does not survive a second register or a second monitor; the one rule the half of them are instances of (an event on a wire is a race, a level valid when read is not); and what `verilog` does not settle |
| [baseband.md](baseband.md) | **proposed**: the baseband trunk card — a tie trunk with nothing in between, four conductors and ≈ 4½ packages; and **the block's card side**, a star on a **block ribbon** ending at the **block header** (**slots** *are* the channel sockets): the channel socket pin by pin, the four things it needs that no document supplied, why the card swaps with a line card and what on the block does not swap with it |
| [pots-trunk.md](pots-trunk.md) | **proposed**: one trunk over a dry two-wire POTS pair — voice-band codec and hybrid, A as a jumper-selected dual tone each way with notches out of the speech path |
| [monitor.md](monitor.md) | the trunk monitor: the one part that reads a digit it was not sent — what it does, the two rules that keep it from ever claiming a wrong number (measured), where it sits and how many, the circuit sketched |
| [extensions.md](extensions.md) | **proposed**: test lines (milliwatt, quiet termination, loopback); **what a card says about its port**: one pin for whether it rings, and one serial word for its class (including *restricted*), its options, a call nail, or a tied nail; nailed-up connections as a one-sided two-write, ringdown, nailing hop by hop, and hotlines to another exchange by a card that dials; traffic counters |
| [pulse-gen.md](pulse-gen.md) | **proposed, measured in simulation**: hook/pulse generator card — hex buttons as pins, no handset, crystal 10 pps and an RC/DIP timebase, \*#A–D as 11–16 pulses (`make pulse_gen`) |
| [groups.md](groups.md) | **measured**: one hunt in place of two — a port **answers to a number** in the primary word, so a hunt group, a second operator's position, cover, and a meet-me bridge are jumpers on plain cards; class *conference*, the secondary word / fifth `'151`, and the adjacent `o` run are **retired**; digit 0 → pilot 04 (`make groups`, `exch.py calls`) |
| [observers.md](observers.md) | **proposed**: four cards that only listen — the **hook lamp field**, 64 lamps off the A highways for 8 packages and no gates, and the **busy lamp field**, which needs the marker's own word to know which row it is looking at because there is no `BUSY` highway on the cable; what each of the four states means, how a class shows itself, how the two fields diagnose a block's shunt column, a flood you can watch; the **port watch** and its stale lamp, and a **last-word display** that freezes on a jumpered match |
| [hookbusy.md](hookbusy.md) | the hook/busy display — interface card on the cables, sixteen lamp cards on four stack buses |
| [counters.md](counters.md) | the traffic counter card on the control bus |
| [traffic.md](traffic.md) | **measured, in two simulators**: demand that is not smooth — bursts, a flash crowd, peak against off peak — run in the millisecond model and in `verilog`'s eight-exchange RTL, and the two read against each other; that Erlang B holds to about 1 % on a link and understates past it, because a flood is a seizure on every link at once; that the holding-time law does not matter and where the calls GO does; and how near the sixty-four codes a tandem-chain backbone goes (63 exchanges), what a fully connected core of hubs is worth (nothing the flood can use) and what long spokes cost |
| [ss0.md](ss0.md) | **proposed, not adopted**: SS0, the number as one message a link on the MF8 frame's spare S bit, forward only, with A keeping everything else — the message, the parts, a worked call, and the live flood against it |

## Tool

```
python3 sim/exch.py            everything                    (sim/exch.log is the run)
python3 sim/exch.py tandem     N codecs in tandem
python3 sim/exch.py fabric     the highway, cell by cell
python3 sim/exch.py calls      one exchange, a millisecond at a time
python3 sim/exch.py announce   a message as a ROM of CVSD bits
python3 sim/exch.py aline      serial characters on A over 1–7 trunk hops
python3 sim/exch.py flood      the timing of a flooded call under 1 e b h s (arithmetic, not a simulation)
python3 sim/exch.py monitor    which rules keep a flood from ever claiming a wrong number, and what a slow carrier costs them
python3 sim/exch.py timing     the fabric's circuit in nanoseconds, worst case over the 74HC spread; then other cell widths (`big-exchange.md` §2)
python3 sim/exch.py mainboard  what a ribbon between the blocks costs those margins: skew, the line, the edges
python3 sim/exch.py confer     conference.md: speech detector, floor, switch
python3 sim/exch.py ss0        SS0 against the live flood: post-dial delay, trunks held for nothing, line errors (arithmetic)
python3 sim/exch.py net        eight exchanges call by call: the flood, the monitors, the claim, the registers, bursty demand
python3 sim/exch.py topo       chains, stars, trees and rings: what each carries and how large, by arithmetic and call by call
python3 sim/exch.py traffic    demand that is not smooth: bursts, herds, peak against off peak, and the RTL run beside it
python3 sim/exch.py big        how near sixty-four exchanges the flood goes: tandem chains, meshed hubs, long spokes
python3 sim/mf8.py             8-bit / 6-channel MF8 (canonical)
# not taken: mf8_10.py, mf8_10_16.py, mf8_16.py, mf8_baud.py
```

It imports `audio`, `cvsd` and `mf8` from the repository root and reads the
`talker*.wav` files there (not committed; see the root README). `announce` writes
its image, and `confer` what a conference sounds like, to `sim/out/`, which is
not committed.

## What is settled and what is not

Settled, in simulation: the fabric is transparent and its delay is one frame for
every pair of ports; a re-point costs at most one repeated bit; one exchange
sets up, supervises and releases every call in the scenario battery with every
latch idle at the end — once a port reads busy while a release detector is still
timing out, and once ringing is gated by the filtered hook. Both of those came
out of the model, not out of the design.

**Decided: the exchange stays 8 × 8 — 64 ports — and more lines are more
exchanges.** Four
ways of making one fabric bigger were worked through and set aside as too
complex for what they bought (`protocol.md` §3.1). The same highway method
with more slots or more wires still costs a third octal digit
(`big-exchange.md`). A chain of four or five
48-line exchanges is comfortable on six-channel links while most calls stay
home, and twenty work around a tandem hub of four twelve-channel directions
(`network.md` §5). What limits a network is its flood, which every call that
leaves lays on every link for 2.7 s.

Decided and not yet modelled as a whole: **the network, the *pulse flood*.** All pulse, no DTMF: a
call dialled with the key `1` opens a flood, and the caller's own dial pulses, the
exchange's code `e b` and the line, go down it live. Every exchange's monitor
hears them and the owner drops the call in. A local call, `h s`, never touches a
trunk. The flood lives on the **network unit**, not in the marker
(`common-control.md`). No
sender, no matrix, no route table. The monitor's two rules are measured — no
wrong number in 1 500 calls at any pause a register can read — and the rest is
timed by arithmetic on measured constants. **`net` is the second pass, and it
runs**: eight exchanges call by call, two hubs of four directions with three
leaves each, against smooth and bursty demand (`network.md` §5.1). It
confirms §5's arithmetic to two decimal places, and finds that bursts leave the
links alone and fall on the registers. **`topo` runs the other shapes**
(`topology.md`): the protocol holds 36 exchanges and about 1 300 lines, and a ring
works only with one of its links jumpered. **`exch.py monitor` and `flood` run
`1 e b h s`**: a monitor compares both `e` and `b` (and lets go after `e` when
it is not ours). `1 8` and `1 9`, out of the network, are reserved.

**Checked against the gates, and three things it changed** (`traffic.md`).
`verilog`'s `make traffic-net` runs the same eight exchanges in RTL under the same
demand on the same clock, and `traffic` runs it here; where they agree, `big`
carries the shapes out to the sixty-four codes. What came of it: **Erlang B is
right to about 1 % on a link and optimistic past it**, because a flood is a
seizure on every link of the network at one instant and a saturated register pool
lets callers out in clumps; **a flash crowd is worse than a burst and worst off
peak**, because a burst is only *when* the calls come and a crowd is *where they
go* — 42 % of seizures refused against 0.68 % for the same erlangs; and **the
holding-time law does not matter**, which is Erlang's insensitivity holding call
by call. The flood's own failure mode is `no claim` and not `no trunk`: a call
blocked on any link between the caller and the owner is dialled in full and then
times out, so **twice the busy hour costs seventeen times the calls**.

**How large, with the line count free** (`traffic.md` §8). Both the traffic on
a link and the flood on it go with the *lines* in the network and not the
exchanges, so the way to fill the numbering plan is exchanges that are not full:
**63 of the 64 codes**, on three tandems in a chain with a tree under each, eight
hops and 124 ms of the origin's 128 ms guard — and what stops it is the guard,
not the codes. **The guard is one tap on a counter**, and the next one up (256 ms)
fills all sixty-four codes with 1 428 lines; past that what stops the search is
the traffic on the centre and the four directions an exchange has, neither of
which is a timer (`monitor.md` §3.5). A **fully connected core of hubs buys nothing**: the flood must
see a tree, so every link off it is a jumper, and a jumper carries its own two ends
only.

Decided: **the port map** (`protocol.md` §5). 00 is idle, and a cleared
latch listens to it. 01–03 are dial, busy and cannot-complete. 04–07 are a
four-line bank (operator, night/backup, then more positions or single-channel
trunks). MF8 trunk groups start at block 1 when networked; standalone frees
digit 1 so 10–77 are fifty-six lines. The `calls` model uses this map; registers
are a pool and take no port.

Decided, and written up as a proposal: **MF8 serves subscriber terminals as well
as trunks**, depending on need (`terminal.md`). A trunk block with its class
set to line, and a stock MF8 shelf at the far end, give six lines at another
site. Voice needs nothing new. Synchronous data needs a loop-timed terminal,
whose PLL is not designed.

Proposed, with the switch and its detector measured: **sources**, which anyone
may dial and any number may hear, and a **conference bridge with no codec**
(`conference.md`), which passes one talker's bits to everyone else and chooses
the talker by counting runs of three in each caller's bits. Sources are a new
class (`fabric.md` §3.5); conference legs are ordinary lines. Neither is in
the marker or the `calls` model yet as classes.

Proposed: **the mainboard is a ribbon for what every block shares and a
board for the three signals that are not shared** (`mainboard.md`). Block *h* drives
highway *h* and answers to `BLK[h]`, which is the whole of a block's identity and
the one thing an identical tap on a common ribbon cannot give it; three shunts in
one labelled column give it back for no parts, where working it out in logic
would cost six packages a block. Two metres of cable costs 18 ns of a 743 ns
set-up budget, because the clock travels down it with the data and the flight
cancels the skew. Of the fifty-five signals, **fifty-four cannot lose a call**:
the worst a glitch does is one wrong CVSD bit, which is what a plesiochronous
slip already does to every line in the system every 156 ms. `/RESET` is the exception, and it
is filtered at every block.

Proposed: **whatever sits behind a port says everything about it**
(`extensions.md` §2). One pin, `/ANS`, tells the port's gates whether it
rings. One serial word, which the marker's scanner reads at every visit, carries
the class and its options: a trunk's direction, a hunt group, a call nail, or
a tied nail; class *restricted* is its own code (`z b 0`: 0-only,
busy-inbound; local-only by floor). A plain line card
says all of it with no part, its word pin tied to ground. The earlier class on
three pins is gone, and with it three commutators a block. Every circuit is
still to draw. Nothing has been on a bench.

Proposed: **a port answers to a number** (`groups.md`). A call that cannot be
completed at the number dialled is offered to the first free port that says it
answers to that number, which makes a hunt group, a second operator's position,
cover and a bank of call-in lines out of jumpers on the members' cards, in any
slots, and replaces both the run of adjacent `o` ports and class *operator*. The
word's last unused form says it on a plain phone's card — **2×`'165`**, with the
second byte spare unless a secondary number needs it (`groups.md` §3–4). A conference bridge becomes a group the same way (class *conference* and
the secondary word / fifth `'151` retired). Nothing is measured.
