# The exchange — the trunk monitor

A flood has no route: a call is offered to every exchange it can reach, and the
one that owns it takes it (`network.md` §3). The **monitor** is the thing at
each exchange that listens to the offer and decides. It is the only part of the
network that reads a digit it was not sent, so it is the part that must never be
wrong.

> **Status: proposed; its rules measured in simulation.** `exch.py monitor` runs
> the caller's pulses down a chain of seven through the trunk's measured A path,
> with monitors that attach early, late and not at all, and counts the calls
> claimed by the wrong exchange; `exch.log` is the run. The first rule written
> for the monitor — "count only after 128 ms of steady make" — failed that test,
> and §3 has the two rules that replace it. **The model runs `1 e b h s`**: a
> monitor compares both `e` and `b`. The circuit of §6 is a sketch from the
> register's; nothing has been on a bench.

---

## 1. What it is for

A line on another exchange is dialled `1 e b h s`: the network's key, the
exchange's two-digit code, then the line (`network.md` §2). The key opens the
flood (`network.md` §3): the origin seizes a trunk in each of its directions,
every exchange the seizure reaches patches it onward, and the caller's own next
two digits — **`e` and `b`** — go down all of it at once as dial pulses on A.
Each exchange must now answer one question: *is that my code?*

| it could be | why it is not |
|---|---|
| a register from the subscribers' pool | every call that leaves its exchange, anywhere in the network, wants a monitor at **every** exchange for a second or two; and a register that is busy means slow dial tone, while a monitor that is busy means a call this exchange owned is never claimed. The two loads should not share a pool |
| the marker | the marker acts in milliseconds and holds nothing; a digit takes up to a second to arrive |

So the monitor is its own small circuit, **on a block that holds trunks**, reading
its trunk ports' M lines directly — it never touches the fabric.

---

## 2. What it does

```
 idle      the trunk's M is low
 seized    M rises, AND THE MONITOR SAW IT RISE, AND THE PORT WAS NOT BUSY  → count this seizure
           (M is already high when a monitor comes free → this seizure is never counted)
           (the port was busy at the last visit → this is a CLAIM coming back, not a seizure: §3.3)
 counting  a break of 8 ms or more is a pulse; 128 ms of make ends the digit   — register.md §2's windows
           decide    the first digit is this exchange's e       → read one digit more
           the second is this exchange's b            → CLAIM: ask the network unit
           either is 8 or 9                           → reserved (network.md §2: e and b are 0–7,
                                                        and a 0 is ten pulses): let go
           either is anything else                    → let go, at once
 done      nothing more is read until the trunk releases (M low for 256 ms)
```

**It reads two digits and no more.** On a claim the **network unit** re-points
the trunk into the local fabric with the latch's `CLAIM` bit set, clears the
onward patch, **and asks the marker for a free register on the trunk's port
number** — the trunk is now a line like any other, so the register reads `h s`,
or 0, or 9, from its hook as it would from a phone's (`common-control.md`
§2.3). The caller's next digit is at least 370 ms away (their pause
less the 128 ms already spent), against a hunt of 8 ms. No register free: the
unit points the trunk at the cannot-complete tone — *claimed, cannot complete*
— and the caller hears it at once.

An incoming call therefore costs the register pool one register for two digits,
and only at the exchange that owns it. Every other exchange spends a monitor for
one digit, if its `e` is not the one dialled, or for two.

---

## 3. The three rules

A monitor that counts a partial digit claims a call for the wrong exchange, and
the caller gets a wrong number with no sign that anything failed. Two things can
make a count partial, and each needs its own rule. A third rule is not about
partial counts at all: it is about telling a seizure from a claim, and an
exchange with outgoing trunks of its own cannot do without it (§3.3).

**1. A monitor counts only a seizure whose rise it saw.** A monitor that attaches
late — because it was busy — may attach in the *pause between two digits*. It
then sees all the steady make anyone could ask for, and counts a later digit
as the first: `b` as `e`, and `h` as `b`. The rule first written, "count only after 128 ms of make", guards
against attaching in mid-digit and does nothing about this. Seeing the rise is
the only proof that nothing has gone by. A pooled monitor is therefore given a
seizure within one scan of its rise — 1 ms, in which no pulse can fit — or not at
all. (`exch.py monitor` allowed 6 ms, the scan of six channels on the 1 kHz tick.
The scanner now steps all eight slots, because a trunk's channels sit where they
are on the wire (`protocol.md` §5), and on the tick that would take 8 ms,
which is as long as the shortest break that counts. So it steps on the 8 kHz
octet mark, as the marker's scanner does. The measured rows do not depend on the
figure: a monitor given the seizure counts from the rise.)

**2. The origin abandons a call whose next break comes within *the guard* of its
seizure. The guard is a jumper, and 128 ms is one setting of it (§3.5).** The flood takes time to spread: 7 ms a hop, 12 at a slow marker. A
caller whose next digit begins before the last exchange is patched in has their
first pulse or two swallowed at the far end, where the monitor — which *did* see
its rise — counts a digit short. Only the origin can know: it sees both its own
seizure and the caller's next break. One tap on a counter: if the break comes
inside the guard, release the trunks and give cannot-complete. 128 ms covers ten
hops at the slow figure, 256 ms twenty-one and 512 ms forty-two, and which tap an
exchange is jumpered for is the one number in the protocol that says how big the
network is (§3.5).

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

Together they make the budget `network.md` §4 uses: the digit recognised
(128 ms), the seizure (2), and the guard — **the flood is ready 130 ms plus the
tap after the caller's last pulse, whatever the hop count.** That is 258 ms at
128, 386 at 256 and 642 at 512, against the 720 ms a telephone to ES 201 187
gives at its fastest (`register.md` §2).

### 3.3 A claim coming back is not a seizure

**Measured in RTL, `verilog`.** The two rules above are enough at the end of a
chain and not enough anywhere else. When a far exchange claims, backward A
rises — and at a transit, or at any origin that seized a trunk, that is **M
rising on this exchange's own outgoing trunk**, which satisfies both rules
exactly. The monitor latches it, counts a level that never pulses, and is held
for the whole of that call.

It does not misroute anything: no digit ever completes, so nothing is claimed.
It costs a monitor. But §4 sizes the pool on a monitor being held for one digit
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

### 3.4 A claim is a request, not a pulse

**Measured in RTL, `verilog`.** Every monitor counts on the same 1 kHz tick, so
two calls whose last pulse ended in the same millisecond decide **together** —
within one pool, and between the pools of two trunk blocks. A claim offered as
a pulse is then lost: the cell goes to *done*, the marker never hears, the trunk
sits busy pointed at idle, and the caller times out to cannot-complete. That is
a call this exchange owned and never took, which is the loss §4 exists to bound.

A claim must therefore be **held until the network unit acknowledges it**, and
the unit must take one at a time. The marker sees only the attach that follows.
It is also what §3.3 of `network.md`
already assumes: a ring delivers a call to its owner twice, and relies on the
second claim being processed and finding the line busy.

### 3.5 Setting the guard

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
| and *not* | the earliest a claim can come back. The marker reads M rising on a trunk it seized inside the guard as glare and not as a claim (`counters.md` §9), so the guard must stay clear of a real one — and it does at every tap, because a caller the guard has not already abandoned has a pause of at least the tap plus 130 ms and must dial two digits before anyone can claim: **twice the tap and 378 ms more** |

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
| `HIT` 8 ms, `ID` 128 ms, `CLR` 256 ms | a register's and a monitor's own windows, local to one exchange, set by the dial's envelope (`register.md` §2) |
| the origin's 2 s wait for a claim | the claim crosses forward and back at about 1.5 ms a hop: **600 hops** of room on a pair, 22 behind a 40 ms carrier |
| the 5 s rule (`network.md` §4) | sized on a slow dial reaching the code `77` in 3.8 s; distance is not in it |
| the release detectors, the trunk's 0.6 s settle, the register's 10 s | all local to one exchange |
| the A path | shortens a break 0.5 ms a hop against a 45 ms margin: **91 hops** |

**In parts:** the sequence counts on the 1 kHz tick already, and 128, 256 and
512 ms are three adjacent stages of that counter. A three-way jumper field beside
the code jumpers and one '151, or three links and none.

---

## 4. Where it sits, and how many

On each block that holds trunks, watching that block's trunk ports. A pool, not
one a channel:

```
 scanner   a 3-bit counter on the 8 kHz octet mark steps the block's eight slots, one a visit,
           reads the slot's word over the visit, and attends only a slot whose word says trunk.  A block may hold an MF8 card beside idle,
           the operator or the tones, or a single-channel trunk among lines (network.md §1.1),
           and a subscriber lifting is never read as a seizure.  For channel k:
           M[k] high, and low at the last visit  → a fresh seizure, at most 1 ms old
             a monitor is free → it latches k and starts counting
             none is free      → the seizure goes unwatched here, for good
           (the last-visit bit is what makes rule 1 true by construction)
           A nailed channel (extensions.md §3.3) sends a nail and not a class, so it is never
           attended, and never read as dialling
```

A seizure nobody watched is still patched onward — the marker does that, not the
monitor — so **an exchange with no free monitor still passes the call; it just
cannot be the one that owns it.**

Every call dialled with `1`, anywhere in the network, wants a monitor on each
block its flood reaches. A monitor whose `e` is the one dialled holds until `b` is
in: 2.7 s on average from the seizure. One whose `e` is not lets go after the
first digit: 1.5 s (`network.md` §4). A local call wants none. Erlang B for
the worst-placed block, one at the end of a chain, which every flood reaches; 48
lines an exchange, 3 calls a line an hour, 30 % of them leaving:

| exchanges | one `e` for all: erlang | all busy with 2 | 3 | 4 | codes spread over eight `e`: erlang | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|---|---|---|---|
| 4 | 0.13 | **0.8 %** | 0.0 % | | | | | | |
| 8 | 0.26 | 2.6 % | **0.2 %** | | 0.16 | 1.1 % | **0.1 %** | | |
| 12 | | | | | 0.24 | 2.2 % | **0.2 %** | 0.0 % | |
| 20 | | | | | 0.39 | 5.3 % | **0.7 %** | 0.1 % | |
| 36 | | | | | 0.71 | 13 % | 3.0 % | **0.5 %** | 0.1 % |
| 47 | | | | | 0.93 | 18 % | 5.3 % | 1.2 % | **0.2 %** |

**Measured against a network, `exch.py net`** (`network.md` §5.1): eight
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

---

## 5. Measured: which rules stop a wrong number

**The model runs `1 e b h s`.** A monitor compares both digits (`network.md` §3,
`monitor.md` §2): first `e`, and if that matches this exchange it reads `b` and
claims only on a full match; if `e` is not ours it lets the onward patch go after
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

`network.md` §1.1 allows a carrier "about 2 ms of A path a hop", which a
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

**And in the gates.** `verilog`'s `make chain-delay` is three exchanges with 20 ms
of carrier on every link — 160 ms in the world, because that bench dials eight
times fast and its guard is 16 ms and not 128. The flood is up **40 ms after the
seizure against a 16 ms guard**, two and a half times over it, and every check
passes: the seizure is forwarded, both monitors catch it, 24 claims, 23 lets go
because 4 is not its `b`, the line rings, answers and releases. Nothing in the
marker or the monitor is aware of the delay line at all.

**The guard has four taps of headroom and they are free**, and §3.5 is what each
one is worth. What §5.1 adds to it is the budget: the tap must cover the
marker's own hop *and this wander*, and nothing of the carrier's length.

**None of which is the reason to keep a carrier short.** The guard does not care,
and the origin's 2 s wait for a claim allows nearly a second of round trip. What
does care is **echo**: `channel-cards.md` §3.3 has no canceller and no suppressor in
the design at all, on the grounds that the round trip is "under 0.1 ms plus 5 µs
per km" and echo is objectionable above 20–30 ms. That is still true for a CVSD
subscriber at each end, which is four-wire; it stops being true the moment either
end is an analog FXS or FXO card, and **one 15 ms hop is 30 ms of round trip.**

**Which tap to jumper, what it buys and what it costs, is §3.5.** The guard is the
only timer in the protocol that is a function of the hop count, and a carrier's
length is not in it; its wander is.

---

## 6. The circuit, sketched

It is `register.md` §4's register with the store, the digit index and the line
select taken away, and a compare added.

| per monitor | parts |
|---|---|
| which channel it holds, and busy | 74HC175 |
| that channel's M | 74HC151 |
| synchroniser and edge | 74HC74, ¼ 74HC86 |
| timer on the 1 kHz tick, cleared on every edge: Q3 = 8 ms, Q7 = 128 ms | 74HC393 |
| pulse count, stepped on a rise when the break reached 8 ms | 74HC163 |
| the count against the exchange's `e` jumpers, then its `b` jumpers, all four bits | 74HC85, 74HC157 |
| which digit; done; claim request | 74HC74, ½ 74HC74 |

| shared by the block | parts |
|---|---|
| scanner | ½ 74HC393 |
| M at the scanner's channel; M at its last visit | 74HC151; 74HC259 and a 74HC151 |
| the scanned slot's word, trunk or not: the block's word commutator held on `DST[2:0]`, sixteen bits at 128 kHz | 2 × 74HC164 and a gate, ≈ 2½ |
| free-monitor pick, gating | 74HC00, 74HC08 |

**≈ 8½ packages a monitor, ≈ 6½ shared: ≈ 24 for a block with two, ≈ 32 with three.** The same
count-then-clear ordering as the register applies (`circuit-review.md` §3): the
edge enables the count and clears the timer a tick later.

**To the network unit:** `CLAIM_REQ` and the channel (3 bits). **From it:** an
acknowledge that frees the monitor. **Jumpers:** `e` and `b`, four bits each,
the unit's own-code jumpers bussed to the monitors. Each is the digit's
pulse count as the counter holds it, so a 0 is jumpered `1010`, ten pulses, and
the compare is all four bits. 8 and 9 are never jumpered, so neither can match.

---

## 7. Not measured

- **The circuit.** A sketch; the orderings are the register's and have not been
  drawn for this.
- **The scanner's 1 ms** against a real seizure's rise through the A path's
  Schmitt gate; the model gives a pooled monitor the rise or nothing.
- **A slow marker.** The guard assumes no exchange takes more than about 12 ms to
  patch a seizure onward. A marker held up longer than that is a partial count at
  every exchange beyond it, and nothing here detects it. It is now the whole of
  what the guard's tap is sized on (§3.5), and the 12 ms is still an assumption
  about parts and not a measurement — `verilog` measures 3–10 ms, and is not 74HC.
- **Copper ties.** Between exchanges in one rack a trunk is a crossover with no
  A-path RC, so pulses arrive undistorted and a hop is a frame; the model used
  the MF8 figures throughout, which are the worse.
- **How fast people really dial**, which is what the no-claim column is made of.
