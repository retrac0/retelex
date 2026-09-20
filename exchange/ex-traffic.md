# The exchange — traffic: bursts, herds, peak against off peak, and how near sixty-four

`exch-network.md` §5 works out what a link carries with Erlang B, and `Topology.md`
takes that over the shapes a network may have. Both assume **smooth demand**: calls
that arrive from nowhere at a fixed rate, spread evenly over the other exchanges.
Real demand is neither. This document is what happens when it is not — and it is
the first thing in `exchange/` that is run **twice, in two simulators that do not share
a line of code**, so that the figures are the design's and not the model's.

> **Status: measured, in two simulators.** `verilog`'s `make traffic-net` is eight
> whole exchanges in RTL — the fabric, the markers, the registers, the monitors, the
> resolvers, the MF8 links — under traffic with no scenario in it. `exch.py traffic`
> is the same network, the same clock and the same demand in the millisecond model
> of `exch.py net`. They are read against each other in §3, and where they agree the
> Python model is used for what the RTL cannot reach: `exch.py big` is the search
> over shapes up to the sixty-four codes (§8). Nothing has been on an FPGA and no
> network has been built.

---

---

## 1. Two simulators, one clock

| | `exch.py traffic` | `make traffic-net` |
|---|---|---|
| what it models | milliseconds: the flood, the monitors, the claim, the resolvers, the registers, the channels | **gates**: `exch_top` × 8, marker, `pulse_reg` pool, `monitor` pool, `mf8_trunk_card`, the serial control bus |
| a caller | a line: it hangs up, waits, and lifts again | a line: the same state machine, in Verilog |
| what it costs | a 10 s phase in **under a second** | a 10 s phase in **an hour**, one thread |
| what it cannot do | glitch, race, or run out of anything the model does not have | grow: **ten exchanges is what was run**, and each one is 64 ports that come out as one C function, which g++ takes a quarter of an hour over |
| what it is for | every shape, up to the sixty-four codes | whether the gates agree

**The two are only comparable because the dial is scaled and the marker is not.**
`verilog`'s system testbenches run the dial and the register's three windows at eight
times life — `HIT`/`ID`/`CLR` = 1/16/32 ms against `register.md` §2's 8/128/256, and
a pulse of 20 ms against 100 — so that a call costs a second and a half of
simulation instead of twelve. What is **not** scaled is everything the marker's
scanner sets: the 8 ms scan, the 7 ms hop, a marker action, the A path. Those are
the same milliseconds in both.

That is deliberate and it is not neutral: **in a call's own terms the scanner is
eight times slower here than in the real exchange.** Dial tone, the hunt and the
hop all cost eight times as much of a call as they will. Everything in this document
is therefore *hard* on the common control and *fair* on the links, which carry what
they carry whatever the clock. `exch.py`'s `Tempo` holds the two tables — `LIFE` and
`FAST` — and `net` and `topo` still run `LIFE`, so nothing in `exch-network.md` §5.1
or `Topology.md` has moved.

**The network is the reference shape of `exch-network.md` §5.1**, scaled to what
eight exchanges of RTL can be: two hubs on one link, three leaves on each, **six
channels on every link**, twelve lines an exchange, ninety-six lines in all. Codes
are `21` and `22` for the hubs and `23`–`27`, `31` for the leaves — `e` from 2 and
`b` from 1, so that no exchange's code costs the ten pulses a `0` costs. Three
registers, three monitor cells a trunk block, three resolvers. 30 % of calls leave
home.

**The offered load is a measurement, not a setting.** Neither model is told how many
calls a second to make: both are told how long a line waits between them, and what
comes out depends on how long a call takes and on how often a line is tied up
answering one. So every table below carries the calls a second each run *managed*
to offer, and the first check on any of them is arithmetic — ninety-six lines that
wait six seconds between calls and spend about a second on each cannot offer
seventeen calls a second, and one early run of the RTL bench that said they could
was a bench fault and not a finding (`verilog/README.md`).

**Every phase is measured after a warm-up.** A phase begins with every line on hook,
which is not a state the network is ever in otherwise: the first idle's worth of
calls all arrive together and nothing has been answered yet. Six seconds of traffic
are run and then forgotten, in both simulators, and what is reported is the network
in its stride.

---

## 2. What demand is offered

A line that has hung up waits an *idle* and lifts again. What that wait is drawn
from is the whole of the traffic model.

| | |
|---|---|
| **smooth** | exponential about the mean. Poisson arrivals, the textbook case and the one Erlang B assumes |
| **bursty** | the same mean in **bursts**. The network goes hot and cold together — 1 s hot in every 6, and hot the rate is eight times what it is cold. The office at a shift change of `exch-network.md` §5.1 |
| **herd** | smooth, with a **flash crowd** on top: now and then a third of every line in the network lifts inside 300 ms, and **they all dial the same exchange**. A number read out on the radio. This is the one that is not only *when* the calls come but *where they go* |

and the conversation is exponential, constant, or a two-class mix of nine short
calls to one ten times as long — the same mean, and a standard deviation of 0, 1.00
and 1.55 times it.

**A burst does not offer the same calls, and that is not the model being wrong.**
The cold rate is set so that the mean over the cycle is the smooth one, which is
exact for arrivals out of nowhere. But **a line that is off hook cannot lift**, and
at eight times the rate the hot idle is shorter than a call, so the lines themselves
are the limit: the bursty runs offer about 60 % of the calls the smooth ones do.
`exch.py net`, whose callers arrive from nowhere, cannot show this at all. It is the
whole difference between a caller and a line, and it is why every table below carries
the calls a second each run *managed* to offer beside what it did with them.

---

## 3. The two simulators against each other

The eight-exchange network of §1, two phases of 10 s after 6 s of warm-up, the same
demand in both. `make traffic-net` is the gates; `exch.py traffic` §1 is the model.

| | | calls/s offered | talked | hub link | the 3 spoke links | registers | monitors | resolvers | dial tone |
|---|---|---|---|---|---|---|---|---|---|
| **off peak** | model | 16.7 | 118 | 3.11 E | 2.12 / 2.17 / 2.23 | 0.77 E | 0.46 E | 0.97 E | 16 ms |
| | **gates** | 20.9 | 114 | 2.48 E | 2.33 / 2.47 / 2.81 | 1.50 E | 0.30 E | 0.85 E | 33 ms |
| **peak** | model | 29.8 | 162 | 4.55 E | 3.26 / 3.53 / 3.73 | 1.33 E | 0.69 E | 1.38 E | 47 ms |
| | **gates** | 33.1 | 121 | 3.10 E | 2.77 / 3.17 / 3.66 | 2.05 E | 0.33 E | 1.24 E | 69 ms |

**The one number that settles it is erlangs for each call a second offered**, because
that is the only thing the two models measure the same way — a channel-millisecond
is a channel-millisecond, and dividing by the offered rate takes out everything else:

| | every link taken together | for each call a second offered |
|---|---|---|
| off peak, model | 15.88 E | **0.951** |
| off peak, gates | 20.04 E | **0.959** |
| peak, model | 24.83 E | **0.833** |
| peak, gates | 26.41 E | **0.798** |

**Eight tenths of a per cent apart off peak and four per cent at peak.** The
millisecond model of `exch.py net` puts the right number of channel-seconds on the
network's trunks for the traffic it is given, and the gates agree. Everything in
§§5–8 rests on that.

### 3.1 And four places they do not agree

**The gates offer a fifth more attempts for the same completed calls** — 209 against
167 off peak, for 114 talked against 118. The RTL's caller rings a real port and
waits for a real answer; the model draws a called-busy probability and connects. So
the two fail differently, and the *mix* of failures is the part of this comparison
that is not being claimed. What is claimed is that each attempt lays the same
channel-seconds on the trunks, which is the table above.

**The registers disagree by a factor of two, and the model is the one that is
wrong.** `exch-monitor.md` §2 gives a register to a **claim** as well as to a caller
— *this call is ours: give it a register and the trunk's port* — so in the gates the
*terminating* exchange holds one for every network call, and `exch.py net` has never
modelled that. It is the largest single gap this comparison found in the model, and
it shows in the next line too: dial tone is twice as late in the gates, 33 ms against
16 off peak and 69 against 47 at peak, which is the same registers being busier.

**Which link is busiest is not settled by a ten-second run, and cannot be.** The
model makes the hub-to-hub link the busiest, the gates make it one of hub 22's
spokes. Both are right about the level — 2.3 to 3.5 E off peak, 2.8 to 4.8 at peak —
and neither has the samples to order them, because **the flood is most of what is on
a link and the flood is on every link equally**: 7.1 network calls a second holding
every link for about a third of a second is 2.3 E before a single conversation is
carried. What is left to tell the links apart is a dozen calls each.

**The monitor pools carry two thirds in the gates of what the model gives them**,
0.30 E against 0.46 off peak. Both are far under the three cells fitted, and both
say the same thing about sizing; the difference is that a cell in the RTL is freed
at the acknowledgement and the model holds it to the digit.

### 3.2 What the gates found that the model cannot

**Trunk channels left held.** Every traffic run ends with every line on hook and a
second of quiet, and nothing may be `BUSY`. Two or three ports are, at eight
exchanges and at ten, and the bench names them and the last latch write each one got:

```
  JAM: 3 ports still BUSY with every line on hook
       21 port 12 (a trunk channel), last written 1751.8 ms ago: src 3 bsy 1 clm 0
       21 port 32 (a trunk channel), last written 1751.7 ms ago: src 3 bsy 1 clm 0
       21 port 42 (a trunk channel), last written 1751.7 ms ago: src 3 bsy 1 clm 0
```

Ports 12, 32 and 42 are blocks 1, 3 and 4; port 03 is block 0. **That is a hub's
fan-out** (`exch-network.md` §3.2) — a seizure came in on one direction and was
patched out into the other three — and when the call died without a claim, the
incoming trunk released and the three legs did not. A port releases on the **fall**
of one of its two detectors, and all three were written after the source's A had
already gone, so there is no edge left for either detector to fall on.

**It is `exch-rtl.md`'s hazard at a trunk instead of at a line**, and the
ten-exchange run finds it at chain transits too, one channel at each of three
exchanges. `make stress` checks for the same shape directly and reports it at HEAD
on a line written to dial tone. **Nothing in a millisecond model can find this**: it
is a write that lands after the edge it needed, and the model has no edges.

---

## 4. Ten exchanges, and spokes two deep

The same two hubs, but two spokes each and every spoke two exchanges deep: ten
exchanges, 120 lines, **a transit on every spoke**, and nine links instead of seven.
`make traffic-deep`, 8 s a phase after 6 s of warm-up.

```
          24 = 23 = 21 = 22 = 27 = 31
                    |    |
          26 = 25 ──┘    └── 32 = 33
```

| | | calls/s | talked | hub to hub | next the hub | the far link | registers | resolvers | dial tone |
|---|---|---|---|---|---|---|---|---|---|
| **off peak** | model | 21.8 | 129 | 3.73 E | 3.07 / 3.94 | 2.73 E | 0.77 E | 1.18 E | 17 ms |
| | **gates** | 26.0 | 110 | 3.97 E | 3.69 / 4.26 | 4.10 E | 1.58 E | 1.34 E | 39 ms |
| **peak** | model | 39.1 | 167 | 5.01 E | 4.04 / 4.38 | 3.89 E | 1.35 E | 1.69 E | 29 ms |
| | **gates** | 39.2 | 144 | 3.76 E | 3.59 / 4.11 | 3.78 E | 2.04 E | 1.26 E | 71 ms |

| | every link taken together | for each call a second offered |
|---|---|---|
| off peak, model | 26.80 E | **1.232** |
| off peak, gates | 35.59 E | **1.369** |
| peak, model | 36.45 E | **0.932** |
| peak, gates | 34.59 E | **0.882** |

Eleven per cent apart off peak and five at peak — looser than §3's eight tenths, and
for a reason the run makes obvious.

**This network is full.** Every one of its nine links sits between 3.4 and 4.4 E of
six in the gates, and every one reached a high-water mark of six. **At peak it
carries less than it does off peak** — 34.59 E against 35.59 — with fifty per cent
more calls offered. Past that point the two models are no longer measuring the same
thing: one refuses a seizure where the other refuses a slightly different one, and
the difference compounds.

**And the finding that is not in §8.2's arithmetic: depth costs almost nothing
here.** `exch.py big` §8.2 says the link next the tandem carries the whole spoke
past it and is the one that fills. In the gates the link next the hub carries 4.26 E
and the link beyond it 4.10 — **within four per cent of each other.** The reason is
the flood: 7.75 network calls a second holding every link in the network for about a
third of a second is **2.7 E on all nine links before a single conversation is
carried**, out of the 3.4 to 4.3 they carry. What tells a near link from a far one is
the conversation, and there is barely an erlang of it to tell them apart with.

**So §8.2's bottleneck is a property of its load and not of the shape.** At the loads
§8 works — 3 calls an hour a line on twelve-channel links — the flood is 0.3 to 0.7 E
of twelve and the traffic is the rest, so the near link really is the one that fills.
Here the flood is nearly half of six and there is nothing left for a shape to make a
bottleneck out of. **The flood's share of a link is what decides
whether a network has a bottleneck or is simply uniformly busy**, and that share
goes with the lines in the whole network against the width of one link.

**The transits leak too.** The ten-exchange run ends its off-peak phase with one
trunk channel held at each of three exchanges — 21, 23 and 25, a hub and two
transits — each written to listen to a trunk whose A had already gone (§3.2). The
hub's fan-out is not a special case; **a chain transit's two-latch patch has the same
hole.**

**One column is not a comparison.** The resolvers are counted over every exchange
that can forward in the gates — six of them here, the two hubs and the four transits
— and over the two hubs alone in the model, because `exch.py net` still follows
`exch-network.md` §3.2's *a chain transit holds nothing* and `verilog` found that it
does not (`exch-rtl.md`). The two numbers are near each other by arithmetic accident.

---

## 5. Peak against off peak

The same network, the idle between a line's calls cut step by step, 240 s a point
in the millisecond model. The link quoted is the busiest — the hub-to-hub link,
which carries both halves' traffic on the same six channels as a leaf's — and
"Erlang B" is worked **on the erlangs the run itself carried**, so the two columns
are the same traffic and differ only in how the loss is arrived at.

| idle between a line's calls | calls/s offered | busiest link | refused | Erlang B | registers | a caller waited |
|---|---|---|---|---|---|---|
| 12 000 ms | 4.2 | 1.05 E | **0.00 %** | 0.06 % | 0.20 E | 0.0 % |
| 8 000 | 6.3 | 1.58 E | **0.21 %** | 0.44 % | 0.30 E | 12.6 % |
| 6 000 | 8.3 | 2.08 E | **2.18 %** | 1.43 % | 0.40 E | 15.2 % |
| 4 000 | 12.1 | 2.91 E | **4.55 %** | 4.75 % | 0.59 E | 38.0 % |
| 3 000 (*off peak*) | 15.8 | 3.29 E | **9.07 %** | 6.92 % | 0.74 E | 54.8 % |
| 2 000 | 22.7 | 4.11 E | **19.07 %** | 12.53 % | 1.06 E | 72.8 % |
| 1 500 (*peak*) | 29.2 | 4.46 E | **26.81 %** | 15.13 % | 1.33 E | 80.3 % |
| 1 000 | 40.3 | 4.96 E | **37.87 %** | 18.87 % | 1.79 E | 89.2 % |
| 700 | 51.9 | 5.23 E | **43.40 %** | 20.88 % | 2.22 E | 93.7 % |

**Erlang B is right to about 1 % and optimistic past it — by a factor of two at
20 % blocking and a factor of two and a half at 40 %.** That is not a defect in
Erlang B; it is that the traffic offered to a link here is not smooth, and for two
reasons that are both the pulse flood's:

- **A flood is a seizure on every link of the network at the same instant.** A
  call that leaves does not offer one arrival to one link; it offers one to each,
  simultaneously and for the same 2–4 s. Whatever congests one link congests the
  rest of the network in step with it.
- **A saturated register pool releases callers in clumps.** At peak four callers in
  five wait a scan for a register, and the marker hands them out on its 8 ms
  scanner — so the calls that do get away leave the exchange bunched on the scan
  rather than spread over the second.

**The knee is at about 3 E on six channels**, which is where `exch-network.md` §5's
sizing already puts it: below it every link is quiet and the arithmetic is sound for
choosing trunks; above it the loss doubles for every step and the arithmetic
understates by more at every step. **Halving the idle between a line's calls from
3 000 ms to 1 500 takes the busiest link from 9 % to 27 %** — three times the loss
for 1.8 times the calls.

**And what fails is not what a caller notices first.** At every load in the table
the register pool is worse off than the trunks: at 6 000 ms one caller in seven is
already waiting a scan for dial tone while the busiest link refuses 2 % of seizures,
and at 3 000 more than half of them are. Three registers to twelve lines is
`exch-marker.md` §6's pool offered thirty times what §6 sizes it for, so that is
arithmetic working, not a surprise — but it is the order in which a network gives
way: **dial tone first, trunks second.**

---

## 6. What each kind of demand moves

The three arrival processes of §2, each run off peak and at peak, at the same
nominal mean. Read the erlangs and the loss together: what matters is that the
first two carry the same hour in a different order, and the third does not.

| arrivals | phase | calls/s offered | busiest link | E a call/s | refused | registers | a caller waited | dial tone mean / 95 % / worst |
|---|---|---|---|---|---|---|---|---|
| smooth | off peak | 8.4 | 1.97 E | 0.236 | **0.68 %** | 0.39 E | 25.1 % | 8.7 / 9.8 / 582 ms |
| smooth | peak | 28.8 | 4.57 E | 0.159 | **26.44 %** | 1.32 E | 78.8 % | 35.5 / 207.4 / 953 ms |
| bursty | off peak | 4.7 | 1.10 E | 0.236 | **0.00 %** | 0.22 E | 8.5 % | 6.8 / 9.7 / 182 ms |
| bursty | peak | 17.5 | 3.45 E | 0.197 | **13.77 %** | 0.82 E | 71.1 % | 25.7 / 146.8 / 1 024 ms |
| herd | off peak | 10.4 | 2.03 E | 0.195 | **41.59 %** | 0.49 E | 42.7 % | 11.9 / 10.0 / 594 ms |
| herd | peak | 30.1 | 4.70 E | 0.156 | **36.85 %** | 1.39 E | 82.4 % | 43.8 / 258.9 / 1 199 ms |

Off peak here is a line lifting every 6 s, not phase 1's 3: nothing ties §§6–7 to the
RTL's operating point, and a light hour is where a herd shows.

**The finding is where, not when.** A herd off peak carries 2.03 E where smooth
carries 1.97 — three per cent more of the same hour — and **refuses 42 % of its
seizures where smooth refuses 0.68 %.** Sixty times the loss for three per cent
more traffic. The reason is not that the calls come together; it is that they
all go to *one exchange*, so one link in the network is asked for six channels it
does not have while the other six are idle. **A flood spreads a call over every
link; it cannot spread a destination.**

The same herd at peak is 36.9 % against smooth's 26.4 % — 40 % worse, not sixty
times. **Off peak is where a herd shows**, because at peak the link is congested
already and a flash crowd has nothing left to take.

**Bursts fall on the registers and not on the links**, which is `exch-network.md`
§5.1's finding, reached by a different road. Here the bursty runs carry *less* —
the lines cannot deliver an eight-fold rate (§2) — and at equal traffic per call
(the "E a call/s" column: 0.236 against 0.236 off peak) the link sees exactly the
same thing. What the burst moves is dial tone, and it moves it *down*, because
there are fewer calls to make it late.

**And the gates say the same.** `make traffic-models` runs the same three arrival
processes on eight whole exchanges in RTL, 8 s at peak apiece — too few calls for a
loss figure, but the link's erlangs are a time average and those agree:

| at peak | calls/s offered, gates / model | busiest link, gates / model | dial tone mean, gates / model |
|---|---|---|---|
| smooth | 29.9 / 28.8 | 4.49 / 4.57 E | 55 / 36 ms |
| bursty | **19.4 / 17.5** | 3.62 / 3.45 E | 31 / 26 ms |
| herd | 38.0 / 30.1 | 4.65 / 4.70 E | **141 / 44 ms** |

**The burst's shortfall is in the gates too** — a fifth fewer calls offered there, a
third fewer here — which is the strongest thing in this document, because it is a
consequence nobody put into either model. And the RTL has the marker's own count of
what a herd does to a link: its *all trunks this way busy* event goes from **3–17 a
direction under smooth traffic to 21–42 under a herd**, on the same network at the
same hour.

**The pools built for the flood are never the constraint.** Over these runs a hub's
resolvers reach 1.0–1.5 E of three and turn away 8–18 % of the fan-outs that want
one; a block's monitors reach 0.5–0.7 E and turn away 2.6–4.2 %. Both are at
roughly **thirty times** the design's offered load (`exch-network.md` §5.1's line
makes 3 calls an hour; here it makes one every second and a half of a clock that is
itself eight times fast), and three of each still hold.

---

## 7. The holding-time law

Erlang B is insensitive to the holding-time law: it depends on the offered erlangs
and nothing else about the distribution. Nothing in this exchange has read Erlang,
so it is worth asking the gates. The same arrivals at peak, 240 s, three laws of
the same mean and a standard deviation of 0, 1.00 and 1.55 times it:

| conversation | sd/mean | calls/s offered | busiest link | refused | Erlang B on it | every link |
|---|---|---|---|---|---|---|
| exponential | 1.00 | 28.8 | 4.55 E | **27.93 %** | 15.81 % | 25.13 E |
| constant | 0.00 | 28.9 | 4.62 E | **27.05 %** | 16.32 % | 25.47 E |
| two-class, nine short to one long | 1.55 | 28.6 | 4.58 E | **27.73 %** | 16.01 % | 25.70 E |

**In the gates it is not measured, and should not be read as if it were.** The same
two laws in RTL give 3.29 E and 3.98 E against the exponential's 4.49, which looks
like a large effect and is not one: eight seconds of model time is seventy network
calls, and seventy samples of an exponential holding time do not have a stable mean.
**The RTL is where the mechanism is checked and the model is where the statistics
are**, and this is the clearest case of it in the document.

**Insensitivity holds.** Nine tenths of a per cent between a constant conversation and one
with half again the spread of an exponential, on a link refusing better than a
quarter of what it is offered — which is inside the run-to-run spread. The level is
not Erlang B's, for §5's reasons, but **whatever sets that level, it is not the
holding-time law**: a network that is sized on mean holding time alone is sized
correctly, and the design need not know what a call's length distribution is.

---

## 8. How near sixty-four exchanges

`exch-network.md` §5's arithmetic, run over shapes instead of over one shape:
`exch.py big`. The rules are `Topology.md` §1 — four directions an exchange, eight
trunk groups, the flood sees a tree, sixty-four codes, and the whole flood inside
the origin's guard at its smallest tap, 128 ms, at a slow marker (12 ms a hop and
4 more at a hub; §8.5 runs the other taps). A
line makes 3 calls an hour of 48 s, 30 % of them leaving, and every call that leaves
floods **every link in the network** for 2.73 s on average over the sixty-four codes.

### 8.1 A tandem chain is short and cannot grow

A tandem has eight trunk groups and four directions. **In the middle of a chain two
directions and four of the groups are gone before a single spoke is hung on it**, so
a middle tandem carries two spokes of twelve channels and nothing more; an end of
the chain carries three.

| | exchanges | lines | worst link | blocked | hops | spread |
|---|---|---|---|---|---|---|
| 2 tandems, 3 spokes each | 8 | 312 | 2.32 E on 12 | 0.00 % | 3 | 44 ms |
| 3 tandems, 3 and 2 spokes | 11 | 420 | 2.82 E on 12 | 0.00 % | 4 | 60 ms |
| 4 tandems | 14 | 528 | 3.72 E on 12 | 0.04 % | 5 | 76 ms |
| 5 tandems | 17 | 636 | 4.31 E on 12 | 0.11 % | 6 | 92 ms |

Five tandems and seventeen exchanges, with every link comfortable and the guard
barely touched. **It is the shape that runs out of room, not the traffic**: a chain
of tandems spends its directions on the chain.

### 8.2 Long spokes are cheap in trunks and dear in hops

A spoke that is a chain of exchanges costs nothing at the tandem — it is one
direction whatever its length — but **the link next the tandem carries the whole
spoke's traffic past it**, and every exchange added puts two hops on the diameter.

| 2 tandems, 3 spokes each | exchanges | lines | worst link | blocked | hops | spread |
|---|---|---|---|---|---|---|
| spokes 2 deep | 14 | 528 | 3.72 E on 12 | 0.04 % | 5 | 68 ms |
| 3 deep | 20 | 744 | 5.15 E on 12 | 0.42 % | 7 | 92 ms |
| 4 deep | 26 | 960 | 6.59 E on 12 | 1.96 % | 9 | 116 ms |
| 5 deep | 32 | 1 176 | 8.03 E on 12 | 5.22 % | 11 | **140 ms** |

**Long spokes run out twice at once**, and at about the same place: the link next
the tandem passes 1 % at four deep, and the guard runs out at five. A spoke of four
is the most a twelve-channel link will carry, and that is twenty-six exchanges.

That the link next the tandem is the one that fills is true **here, where the flood
is 0.3 to 0.7 E of twelve**. §4 runs a deep network in the gates at a load where the
flood is half of six, and there the near link and the far one are within four per
cent of each other: when the flood is most of what is on a link, every link in the
network carries the same thing and the shape stops mattering.

### 8.3 What a fully connected core of hubs is worth

**The flood must see a tree.** Of the *k*(*k*−1)/2 links between *k* fully connected
tandems, only the *k*−1 of a spanning chain may carry it; every other one is
**strapped**, and `exch-network.md` §3.3's strapped link carries calls between its
own two ends only. Read in pairs — the same eight trunk groups at each tandem, spent
on a chain of wide links or on a mesh of narrow ones:

| | exchanges | lines | worst link | blocked | worst pair |
|---|---|---|---|---|---|
| 3 tandems chained, 12 ch, 2 spokes | 9 | 348 | 2.30 E on 12 | **0.00 %** | 0.00 % |
| the same, fully connected, 6 ch | 9 | 360 | 2.29 E on **6** | **2.05 %** | 4.05 % |
| 4 tandems chained, 12 ch, 1 spoke | 8 | 312 | 2.32 E on 12 | **0.00 %** | 0.00 % |
| the same, fully connected, 6 ch | 8 | 312 | 2.00 E on **6** | **1.21 %** | 2.06 % |

**The mesh carries exactly the same traffic on half the channels.** Its extra links
are straps, and the only calls a strapped tandem-to-tandem link can take are the
twelve lines at one end calling the twelve at the other — which at a tandem is
almost nothing. **Capacity between hubs is bought in channels on the tree, not in
links off it.** A mesh of five needs four directions and has none left for a spoke;
a mesh of six needs five and cannot be built at all.

**The exception is the one that shows why.** With *nothing behind them*, meshed
exchanges are not hubs — they *are* the traffic, every pair has a direct link, and
no call is ever forwarded:

| | exchanges | lines | worst link | blocked | hops |
|---|---|---|---|---|---|
| 5 tandems chained, 12 ch, no spokes | 5 | 204 | 1.59 E on 12 | 0.00 % | 4 |
| 5 **fully connected**, 6 ch, no spokes | 5 | 180 | **0.31 E on 6** | 0.00 % | **1** |

A five-exchange mesh is a fifth of the load of the chain and one hop across, and the
flood never leaves the link it was born on. **Five is where it stops**: a sixth
exchange wants a fifth direction, and hanging anything off one of the five turns
every mesh link back into a strap that nothing behind it may cross.

### 8.4 What reaches sixty-four codes is smaller exchanges

Both the traffic on a link and the flood on it are proportional to the **lines in
the network** and not to the exchanges in it. The same sixty-two-exchange tree, read
at different line counts:

| 2 tandems, 3 × 3 × 2 | exchanges | lines | flood a link | worst link | blocked |
|---|---|---|---|---|---|
| 48 lines an exchange | 62 | 2 472 | 1.67 E | 16.75 E on 12 | 36.55 % |
| 36 | 62 | 2 040 | 1.38 E | 13.82 E on 12 | 26.81 % |
| 24 | 62 | 1 392 | 0.94 E | 9.43 E on 12 | 9.84 % |
| 18 | 62 | 1 068 | 0.72 E | 7.24 E on 12 | 3.21 % |
| **12** | 62 | 744 | 0.50 E | 5.04 E on 12 | **0.36 %** |
| 8 | 62 | 496 | 0.34 E | 3.36 E on 12 | 0.02 % |

**Sixty-two exchanges is not a numbering problem and it is not a hop problem.** The
shape is seven hops and 108 ms, inside the guard on its smallest tap; the codes are
there. What decides
it is how many lines are behind them, and at about a thousand lines in the network
the twelve-channel link at the centre passes 1 %.

### 8.5 The largest, searched

Backbones of one to five tandems, trees of up to three levels under each, channel
counts that never grow outward, and a line cap — about a hundred thousand shapes,
kept only if no link passes 1 % and the whole flood fits inside the guard. The
largest of them, by exchanges:

| calls leaving home | exchanges | lines | an exchange | flood a link | worst link | blocked | worst pair | hops | spread | monitors | resolvers |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 20 % | **63** | 1 428 | 24 | 0.65 E | 5.82 E on 12 | 0.94 % | 2.05 % | 8 | 124 ms | 4 | 4 |
| 30 % | **63** | 756 | 12 | 0.51 E | 1.35 E on 6 | 0.22 % | 0.86 % | 8 | 124 ms | 4 | 4 |
| 50 % | **63** | 504 | 8 | 0.57 E | 5.12 E on 12 | 0.41 % | 1.59 % | 8 | 124 ms | 4 | 4 |

**All three are the same shape: three tandems in a chain, two sub-hubs on each,
three under every sub-hub and two leaves under every one of those.** Sixty-three
exchanges of the sixty-four codes, eight hops across and 124 ms of flood against
the origin's 128 ms guard — *four milliseconds of margin*, which is what actually
stops it. **The guard is a strap and the next tap up ends that**: at 256 ms the
same search finds all 64 codes and 1 428 lines, and what stops it then is the
traffic on the centre and the four directions an exchange has, neither of which is
a timer (`exch-monitor.md` §3.5, `exch.py big` §7). At 128 ms the traffic is
handled by giving up lines: 24 an exchange where a fifth
of calls leave, 12 where a third do, 8 where half do.

| what stops each family | |
|---|---|
| a tandem chain with spokes | **directions**: a middle tandem has two left and two trunk groups (§8.1) |
| long spokes | **the link next the tandem at four deep, and the guard at five** (§8.2) |
| a fully connected core | **nothing to carry**: every link off the tree is a strap (§8.3) |
| a branching tree of full exchanges | **traffic**: about a thousand lines on a twelve-channel centre (§8.4) |
| the best of them | **the guard, at 124 ms of 128** |

**So the answer to "how near sixty-four" is: one short of it on the guard's
smallest tap, and all of it on the next one.** What runs out at 63 is the 128 ms
guard — and behind that,
`exch-monitor.md` §3's 12 ms hop at a slow marker, which is the one constant in this
whole document that is an *assumption about parts* rather than a measurement.
The guard is a three-way strap (`exch-monitor.md` §3.5), and at its 256 ms tap the
same search finds **all 64 codes and 1 428 lines**; what stops it there is the
traffic on the centre and the four directions an exchange has, and neither of
those is a timer.

### 8.6 And run call by call

The three, with `net`'s engine — the flood, the monitors, the claim, the resolvers
and the registers, call by call in milliseconds — at `exchange/`'s busy hour of 3 calls
a line and then at **twice** it, which is a network built for one community and
given two. Five monitor cells a block, five resolvers a hub, six hours each:

| | calls a line an hour | calls an hour | worst link | refused | no trunk | no claim | pools | lost / 1 000 |
|---|---|---|---|---|---|---|---|---|
| 20 % leaving, 24 lines | 3 | 4 333 | 5.63 E on 12 | 0.70 % | 0.8 | 5.9 | 0.0 | **6.7** |
| | **6** | 8 615 | 8.83 E on 12 | 11.57 % | 2.1 | 111.8 | 6.1 | **120.0** |
| 30 % leaving, 12 lines | 3 | 2 293 | 1.38 E on 6 | 0.42 % | 0.0 | 3.9 | 0.0 | **3.9** |
| | **6** | 4 580 | 7.33 E on 12 | 4.04 % | 0.5 | 63.2 | 1.4 | **65.1** |
| 50 % leaving, 8 lines | 3 | 1 524 | 1.51 E on 6 | 0.48 % | 0.0 | 6.3 | 0.0 | **6.8** |
| | **6** | 3 054 | 8.09 E on 12 | 7.40 % | 0.2 | 99.2 | 0.4 | **99.8** |

**At the busy hour the arithmetic holds**: 0.70 % refused on the busiest link where
0.94 % was predicted, 0.42 % where 0.22 % was, 0.48 % where 0.41 % was, and six or
seven network calls lost in a thousand in all three.

**At twice the busy hour it does not degrade, it collapses — by a factor of
seventeen, not of two.** And the column it collapses in is `no claim`, not
`no trunk`: the caller's own exchange finds a trunk, the flood goes out, and it
**does not reach the exchange it names**, because one link somewhere along the way
had six channels busy. The call is not refused; it is dialled in full and then times
out into cannot-complete.

**That is the pulse flood's own failure mode and it belongs in a sizing rule.** A
routed network loses a call when the *route* is busy; a flooded one loses a call
when *any link between the caller and the owner* is busy, and it finds out 2 s
later. A link at 4 % is a network at 6.5 %. **Size the links for the busy hour with
margin, because the second hour is not twice as bad.**


---

## 9. Not measured

- **The RTL runs are 10 s a phase**, or 8 for the ten-exchange one, which at these
  loads is a few hundred seizures on the busiest link. That measures a 5 % loss and
  does not measure a 0.5 % one, which is why §3 is read on **erlangs** — a
  channel-millisecond is a channel-millisecond in both models — and not on loss.
  The Python runs in §§5–7 are 240 s for the same reason.
- **One seed each**, and the two models cannot share one: the RTL bench has its own
  LCG so that Icarus and Verilator measure the same traffic, and `exch.py` has
  numpy's. Agreement here is statistical, never call for call.
- **Nothing here is plesiochronous.** `tb_traffic` runs the whole network on one
  crystal, because staggering the clocks costs the simulator an evaluation point for
  every exchange and buys nothing a traffic run reads. The two-crystal case is
  `make trunk-ppm` and `make stress-pair`.
- **The traffic is uniform over the other exchanges**, except in a herd. A real
  community is not, and the shapes of §8 are worked on the assumption that it is.
- **`exch.py big` is arithmetic**, Erlang B on a tree, except for §8's last table.
  §5 says what that arithmetic is worth: good to about 1 % and optimistic past it.
- **The model still does not give a register to a claim** (§3.1), which the gates do
  and `exch-monitor.md` §2 requires. Every register figure in `exch.py` — here, in
  `net`, in `topo`, and therefore in `exch-network.md` §5.1's table — is **low at a
  terminating exchange** by about the share of its calls that arrive over a trunk.
  Nothing else in those documents moves; the links and the pools built for the flood
  do not see it.
- **Both network runs FAIL their own jam check** on the held trunk channels of §3.2,
  and so does `make traffic`. That is the check working. What is *not* measured is
  how often it happens in a run long enough to count, or whether a marker that
  refused to write a port whose source is already down would cost anything.
