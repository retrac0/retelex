# Analysis — the monitor's rules, and what they were measured against

The rules that keep a monitor from claiming a wrong number, why each is needed,
how the origin's guard is set, and the runs that measured them. The rules as
built are `network.md` §3.4 and §6; this is how they were found. Moved from the
retired `monitor.md` §3–§5.

> **Analysis, measured in `exch.py monitor` (`sim/exch.log`) on the model of its day, and in the retired `old/verilog` tree** (§2, §3, and §5.1's `make chain-delay`). **Not re-run for the unit as built**, whose benches run the dial 8× fast and the sweep at real speed, so check the mechanism and not the reach.
> **Changed: the hop.** The runs and §4 take a hop as the marker's 3–10 ms, "7 ms a hop, 12 at a slow marker", and a hub as a hop and a third; the unit's hop is a 9 ms sweep, ≈ 12 ms typical and ≈ 22–30 ms slow (`network.md` §6); at a hub only the extra legs' writes add to it, so §4's tap table (ten hops at 128 ms) holds only for the typical hop. The origin's seizure comes ≈ 11 ms after the digit, so "130 ms plus the tap" is ≈ 139 ms plus the tap. `network.md` §2 now allows a carrier *any* constant delay; §5.1 was run against "about 2 ms of A path a hop".
> **Changed: the monitor.** One pool of cells on the network unit, each its own probe and `pulse_rx`, attached when the unit reads a seizing port's word — not a scanner on each trunk block stepping on the octet mark (`network.md` §3.4). Rule 1's "within one scan of its rise, 1 ms" is now 2–3.5 ms, up to 20 ms behind a busy classifier, and the guard covers it; §2's third term is `BUSY` read live in M's own bit-time plus a bit a port, not "`BUSY` at the last visit"; §6 sized monitors a block, not one pool (`network.md` §10).
> **Changed: the claim and the guard.** A cell's claim is held until the unit writes `CLAIM` and freed at that write, with no acknowledgement (§3). The guard is a two-bit strap, not a three-way jumper and a '151 (§4).

---

## 1. The first two rules

A monitor that counts a partial digit claims a call for the wrong exchange, and
the caller gets a wrong number with no sign that anything failed. Two things can
make a count partial, and each needs its own rule. A third rule is not about
partial counts at all: it is about telling a seizure from a claim, and an
exchange with outgoing trunks of its own cannot do without it (§2).

**1. A monitor counts only a seizure whose rise it saw.** A monitor that attaches
late — because it was busy — may attach in the *pause between two digits*. It
then sees all the steady make anyone could ask for, and counts a later digit
as the first: `b` as `e`, and `h` as `b`. The rule first written, "count only after 128 ms of make", guards
against attaching in mid-digit and does nothing about this. Seeing the rise is
the only proof that nothing has gone by. A pooled monitor is therefore given a
seizure within one scan of its rise — 1 ms, in which no pulse can fit — or not at
all. (`exch.py monitor` allowed 6 ms, the scan of six channels on the 1 kHz tick.
The scanner now steps all eight slots, because a trunk's channels sit where they
are on the wire (`trunks.md` §4), and on the tick that would take 8 ms,
which is as long as the shortest break that counts. So it steps on the 8 kHz
octet mark, as the marker's scanner does. The measured rows do not depend on the
figure: a monitor given the seizure counts from the rise.)

**2. The origin abandons a call whose next break comes within *the guard* of its
seizure. The guard is a jumper, and 128 ms is one setting of it (§4).** The flood takes time to spread: 7 ms a hop, 12 at a slow marker. A
caller whose next digit begins before the last exchange is patched in has their
first pulse or two swallowed at the far end, where the monitor — which *did* see
its rise — counts a digit short. Only the origin can know: it sees both its own
seizure and the caller's next break. One tap on a counter: if the break comes
inside the guard, release the trunks and give cannot-complete. 128 ms covers ten
hops at the slow figure, 256 ms twenty-one and 512 ms forty-two, and which tap an
exchange is jumpered for is the one number in the protocol that says how big the
network is (§4).

**What the guard is counting is the marker, not the carrier.** A trunk on a
leased circuit, a radio or anything with a buffer is tens of milliseconds long,
and it costs the guard **nothing** — because the seizure that opens the flood and
the pulses that follow it are *the same wire*. An exchange seven hops out behind a
80 ms carrier is patched in 600 ms later in absolute time, and the first break of
`e` reaches it 600 ms later too; it still sees the rise first. The two delays
cancel exactly (§5.1). What does not cancel is the part of each hop where the
signal **restarts**: the marker's 3–10 ms of reading M and writing the onward
latch, which is what the flood's 7 ms a hop is mostly made of. Add to it any delay
the carrier *loses* between the seizure and the next digit — a buffer draining, a
link re-timing — because that moves the pulses forward against a rise that has
already gone by, and it costs a millisecond of guard for a millisecond of wander.

Together they make the budget `network.md` §6 uses: the digit recognised
(128 ms), the seizure (2), and the guard — **the flood is ready 130 ms plus the
tap after the caller's last pulse, whatever the hop count.** That is 258 ms at
128, 386 at 256 and 642 at 512, against the 720 ms a telephone to ES 201 187
gives at its fastest (`register.md` §1).

## 2. A claim coming back is not a seizure

**Measured in RTL, `old/verilog`.** The two rules above are enough at the end of a
chain and not enough anywhere else. When a far exchange claims, backward A
rises — and at a transit, or at any origin that seized a trunk, that is **M
rising on this exchange's own outgoing trunk**, which satisfies both rules
exactly. The monitor latches it, counts a level that never pulses, and is held
for the whole of that call.

It does not misroute anything: no digit ever completes, so nothing is claimed.
It costs a monitor. But §6 sizes the pool on a monitor being held for one digit
or two, and a transit holds one for **every call it passes**, which is the whole
traffic of the network. A middle-of-chain exchange runs out.

**The third term is `BUSY`, and it must be `BUSY` *at the last visit*.** The two
cases differ in order, not in state: this exchange writes `BUSY` when it seizes
or patches a trunk, and the far end's answer raises M long afterwards, so a
claim's rise always finds `BUSY` already set at the previous visit and a real
seizure's never does. Reading `BUSY` live instead loses about one seizure in
eight, because the monitor's scanner covers eight slots while the marker's
covers sixty-four ports and the marker reaches a port first that often. `BUSY`
is a line on the block, beside the M lines the monitor already reads, so this
costs one more '151 input and no new connection.

## 3. A claim is a request, not a pulse

**Measured in RTL, `old/verilog`.** Every monitor counts on the same 1 kHz tick, so
two calls whose last pulse ended in the same millisecond decide **together** —
within one pool, and between the pools of two trunk blocks. A claim offered as
a pulse is then lost: the cell goes to *done*, the marker never hears, the trunk
sits busy pointed at idle, and the caller times out to cannot-complete. That is
a call this exchange owned and never took, which is the loss §6 exists to bound.

A claim must therefore be **held until the network unit acknowledges it**, and
the unit must take one at a time. The marker sees only the attach that follows.
It is also what `network.md` §7
already assumes: a ring delivers a call to its owner twice, and relies on the
second claim being processed and finding the line busy.

## 4. Setting the guard

**The guard is a jumper, and it is the only number in the protocol that says how
big the network is.** An exchange's other jumpers say *who it is* — `e` and `b`,
its own code, and nothing anywhere says where anything is. This one says how far
the flood has to travel, it is the same value at every exchange in one network,
and it is set by whoever plans the network and not by the exchange.

It is one tap on the counter the seize-and-await-claim sequence already runs on,
so the choice costs no parts. What each tap is worth (`exch.py big` §7):

| tap | covers, at a slow marker's 12 ms a hop | the longest chain whose flood fits it | the largest network the shape rules allow, 30 % of calls leaving |
|---|---|---|---|
| **128 ms** | 10 hops | 11 exchanges | 63 exchanges, 756 lines, 12 a piece |
| **256 ms** | 21 hops | 22 exchanges | **64 exchanges, 1 428 lines, 22 a piece** |
| 512 ms | 42 hops | 43 exchanges | the same 64 and 1 428 |

**256 ms fills the sixty-four codes and nearly doubles the lines. 512 buys
nothing more in size**, because past 256 what stops the search is the traffic on
the centre and the four directions an exchange has, and neither of those is a
timer. What 512 buys instead is room for a carrier that wanders (§5.1).

**What the guard has to cover** is every hop's *marker* — 12 ms at a slow one,
4 ms more at a hub, a hub counting as a hop and a third — plus any delay a
carrier loses between the seizure and the next digit, a millisecond for a
millisecond. **Not** a carrier's own transmission delay, which cancels (§5.1).

**What bounds it:**

| | |
|---|---|
| above | the caller's own pause less the 130 ms the digit and the seizure take. A telephone to ES 201 187 gives at least 720 ms, so **590 ms**, and 512 is the last tap under it |
| below | nothing. 128 ms is right for a network of pairs and a short chain, and there is no reason to go under it |
| and *not* | the earliest a claim can come back. M rising on a trunk the origin seized inside the guard is glare — the far end seized the same channel — and the unit takes it **as the claim**, counts it and joins the two callers (`network.md` §5, `proposed/counters.md`), so the guard must stay clear of a real claim — and it does at every tap, because a caller the guard has not already abandoned has a pause of at least the tap plus 130 ms and must dial two digits before anyone can claim: **twice the tap and 378 ms more** |

**What a longer tap costs is the fast caller.** 128 ms gives cannot-complete to
anyone dialling with under 258 ms between digits, 256 ms to anyone under 386, and
512 ms to anyone under 642. All three are inside what a conforming telephone
does and none is inside what a worn dial, a non-conforming instrument or an
operator's practised hand might. **That is the trade rule 2 exists to make** — a
failed call in place of a chance of a wrong number — and a longer tap makes it
more often. A local call, `h s`, never floods and is never touched by it.

**Everything else stays where it is.** The guard is the only timer in the
protocol that is a function of the hop count:

| | why it does not move with it |
|---|---|
| `HIT` 8 ms, `ID` 128 ms, `CLR` 256 ms | a register's and a monitor's own windows, local to one exchange, set by the dial's envelope (`register.md` §1) |
| the origin's 2 s wait for a claim | the claim crosses forward and back at about 1.5 ms a hop: **600 hops** of room on a pair, 22 behind a 40 ms carrier |
| the 5 s rule (`network.md` §4.1) | sized on a slow dial reaching the code `00` in 3.8 s; distance is not in it |
| the release detectors, the trunk's 0.6 s settle, the register's 10 s | all local to one exchange |
| the A path | shortens a break 0.5 ms a hop against a 45 ms margin: **91 hops** |

**In parts:** the sequence counts on the 1 kHz tick already, and 128, 256 and
512 ms are three adjacent stages of that counter. A three-way jumper field beside
the code jumpers and one '151, or three links and none.

## 5. Measured: which rules stop a wrong number

**The model runs `1 e b h s`.** A monitor compares both digits (`network.md`
§3.4): first `e`, and if that matches this exchange it reads `b` and claims only
on a full match; if `e` is not ours it lets the onward patch go after
`e`. Both hazards below act on the first digit a monitor hears. A second compared
digit does not add a new way of attaching late — the monitor is attached by then —
but it rejects a partial count that landed on the wrong `e` before `b` is read.

A chain of seven exchanges with codes 11–17; a dial at 10 pps ± 10 %, 60/40; the
key `1`, then `e` and `b` (1–7, or ten pulses for a code that is not there), one
digit more. The origin seizes 130 ms after the key's last pulse; each
exchange patches onward 3–10 ms after its M rises; A crosses every hop through
the trunk's A path as `exch.py aline` measured it; a claim cuts the onward patch.
1 500 calls a row. **False = an exchange other than the one dialled claimed the
call.**

| a monitor counts | origin guard | pause between digits | right | no claim | **false** |
|---|---|---|---|---|---|
| from whenever it attaches, after 128 ms of make | none | 140–900 ms | 92.9 % | 6.3 % | **12** |
| the same | none | 450–900 ms | 96.5 % | 3.5 % | **1** |
| the same | 128 ms | 140–900 ms | 94.5 % | 5.0 % | **7** |
| the same | 128 ms | 450–900 ms | 96.1 % | 3.4 % | **7** |
| only a seizure whose rise it saw | none | 140–900 ms | 98.0 % | 1.8 % | **3** |
| the same | none | 450–900 ms | 97.7 % | 2.3 % | 0 |
| **only a seizure whose rise it saw** | **128 ms** | 140–900 ms | 96.1 % | 3.9 % | **0** |
| the same, line BER 1e−2 on every hop | 128 ms | 140–900 ms | 96.7 % | 3.3 % | **0** |
| the same | 128 ms | 450–900 ms | 97.9 % | 2.1 % | **0** |
| the same, line BER 1e−2 on every hop | 128 ms | 450–900 ms | 98.1 % | 1.9 % | **0** |

- **The old rule still gives wrong numbers**, but far fewer than under one-digit
  compare (12 in 1 500 at fast pauses against 97): a partial count must now match
  both `e` and `b`.
- **Rule 1 alone is safe for a human and not for a fast one**: the three false
  claims are all callers whose next digit began before the flood was complete.
- **Both rules: none**, at any pause a pulse register can read at all, clean or
  at a line error rate of 1e−2.

### 5.1 A carrier that is not a pair

The network spec of the day allowed a carrier "about 2 ms of A path a hop" (now
`network.md` §2, which allows any constant delay), which a
copper pair and an MF8 link are inside and a leased circuit, a radio, a mux or a
jitter buffer are not. The same model with a **constant one-way delay** added to
every hop, both rules on, a pause of 140–900 ms and the 128 ms guard throughout;
1 000 calls a row:

| carrier a hop | the flood is up at | right | no claim | **false** |
|---|---|---|---|---|
| 0 ms | 46 ms | 96.6 % | 3.4 % | **0** |
| 10 ms | 116 ms | 97.5 % | 2.5 % | **0** |
| 20 ms | 186 ms | 96.8 % | 3.2 % | **0** |
| 40 ms | 326 ms | 97.2 % | 2.8 % | **0** |
| 80 ms | 606 ms | 96.7 % | 3.3 % | **0** |
| **160 ms** | **1 166 ms** | 96.2 % | 3.8 % | **0** |

**Delay costs the guard nothing, at any depth.** The flood taking 1.17 s to cross
seven hops changes no outcome, because every break the caller makes is 1.12 s late
at the far end as well. A hop's contribution to the guard is the part where the
signal *restarts* — the marker's own 3–10 ms — and not the part where it travels.

**Delay that the carrier loses between the seizure and the next digit does cost
it, one for one.** A buffer draining or a link re-timing moves the pulses forward
against a rise that has gone by. The same model with that wander added per hop, on
top of the marker:

| wander a hop | the flood is up at | false, guard 128 ms | matched tap | false | abandoned, a dial of 140–900 | abandoned, 720–900 |
|---|---|---|---|---|---|---|
| 0 ms | 46 ms | **0** | 128 ms | 0 | 14 % | **0 %** |
| 5 ms | 80 ms | **0** | 128 ms | 0 | 15 % | **0 %** |
| 10 ms | 116 ms | **0** | 128 ms | 0 | 14 % | **0 %** |
| 20 ms | 186 ms | **0** | 256 ms | 0 | 31 % | **0 %** |
| 40 ms | 326 ms | **7** | 512 ms | 0 | 65 % | **0 %** |

**And in the gates.** `old/verilog`'s `make chain-delay` is three exchanges with 20 ms
of carrier on every link — 160 ms in the world, because that bench dials eight
times fast and its guard is 16 ms and not 128. The flood is up **40 ms after the
seizure against a 16 ms guard**, two and a half times over it, and every check
passes: the seizure is forwarded, both monitors catch it, 24 claims, 23 lets go
because 4 is not its `b`, the line rings, answers and releases. Nothing in the
marker or the monitor is aware of the delay line at all.

**The guard has four taps of headroom and they are free**, and §4 is what each
one is worth. What §5.1 adds to it is the budget: the tap must cover the
marker's own hop *and this wander*, and nothing of the carrier's length.

**None of which is the reason to keep a carrier short.** The guard does not care,
and the origin's 2 s wait for a claim allows nearly a second of round trip. What
does care is **echo**: `common/channel-cards.md` §3.1 has no canceller and no suppressor in
the design at all, on the grounds that the round trip is "under 0.1 ms plus 5 µs
per km" and echo is objectionable above 20–30 ms. That is still true for a CVSD
subscriber at each end, which is four-wire; it stops being true the moment either
end is an analog FXS or FXO card, and **one 15 ms hop is 30 ms of round trip.**

**Which tap to jumper, what it buys and what it costs, is §4.** The guard is the
only timer in the protocol that is a function of the hop count, and a carrier's
length is not in it; its wander is.

## 6. How many, sized a block

Every call dialled with `1`, anywhere in the network, wants a monitor on each
block its flood reaches. A monitor whose `e` is the one dialled holds until `b` is
in: 2.7 s on average from the seizure (`network.md` §4.3). One whose `e` is not
lets go after the first digit: 1.5 s, by this model's arithmetic. A local call
wants none. Erlang B for the worst-placed block, one at the end of a chain,
which every flood reaches; 48 lines an exchange, 3 calls a line an hour, 30 % of
them leaving:

| exchanges | one `e` for all: erlang | all busy with 2 | 3 | 4 | codes spread over eight `e`: erlang | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|---|---|---|---|
| 4 | 0.13 | **0.8 %** | 0.0 % | | | | | | |
| 8 | 0.26 | 2.6 % | **0.2 %** | | 0.16 | 1.1 % | **0.1 %** | | |
| 12 | | | | | 0.24 | 2.2 % | **0.2 %** | 0.0 % | |
| 20 | | | | | 0.39 | 5.3 % | **0.7 %** | 0.1 % | |
| 36 | | | | | 0.71 | 13 % | 3.0 % | **0.5 %** | 0.1 % |
| 47 | | | | | 0.93 | 18 % | 5.3 % | 1.2 % | **0.2 %** |

**Measured against a network, `exch.py net`** (`analysis/topology.md` §11.1): eight
exchanges, 348 lines, 30 % of calls leaving, smooth and in bursts. A leaf's trunk
block holds its monitors 0.09 E and turns away 0.0 % of the calls that want one
with three fitted; at 50 % leaving, 0.14 E and 0.0 %. Bursts do not move it: a
monitor is held by a call that is already dialling, and bursts fall on the
registers instead.

**These figures are the loss to callers.** A call is lost when every monitor on
its owner's block is busy as the seizure arrives. (This section used to divide
the figure by the number of exchanges. That was wrong: an exchange misses only
its own calls, but it misses them at this rate.) **Two monitors a block to four
exchanges, three to twenty, four to thirty-six, five beyond.** More than eight
exchanges cannot share an `e`, and spreading the codes over several frees most
monitors a digit sooner.
At a hub a flood arrives on one of several blocks, and each block's monitors see
only their share.
