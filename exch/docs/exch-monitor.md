# The exchange — the trunk monitor

A flood has no route: a call is offered to every exchange it can reach, and the
one that owns it takes it (`exch-network.md` §3). The **monitor** is the thing at
each exchange that listens to the offer and decides. It is the only part of the
network that reads a digit it was not sent, so it is the part that must never be
wrong.

> **Status: proposed; its rules measured in simulation.** `exch.py monitor` runs
> the caller's pulses down a chain of seven through the trunk's measured A path,
> with monitors that attach early, late and not at all, and counts the calls
> claimed by the wrong exchange; `exch.log` is the run. The first rule written
> for the monitor — "count only after 128 ms of steady make" — failed that test,
> and §3 has the two rules that replace it. **The model runs the earlier
> numbering**, in which the first digit was the key and a monitor compared one
> digit. Under `1 e b h s` a monitor compares two, `e` and then `b`; the second is
> not yet in the model (§5). The circuit of §6 is a sketch from the register's;
> nothing has been on a bench.

---

## 1. What it is for

A line on another exchange is dialled `1 e b h s`: the network's key, the
exchange's two-digit code, then the line (`exch-network.md` §2). The key opens the
flood (`exch-network.md` §3): the origin seizes a trunk in each of its directions,
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
 seized    M rises, AND THE MONITOR SAW IT RISE      → count this seizure
           (M is already high when a monitor comes free → this seizure is never counted)
 counting  a break of 8 ms or more is a pulse; 128 ms of make ends the digit   — register.md §2's windows
 decide    the first digit is this exchange's e       → read one digit more
           the second is this exchange's b            → CLAIM: ask the marker
           either is 8 or 9                           → reserved (exch-network.md §2: e and b are 0–7,
                                                        and a 0 is ten pulses): let go
           either is anything else                    → let go, at once
 done      nothing more is read until the trunk releases (M low for 256 ms)
```

**It reads two digits and no more.** On a claim the marker re-points the trunk
into the local fabric with the latch's `CLAIM` bit set, clears the onward patch,
**and gives a free register the trunk's port number** — the trunk is now a line
like any other, so the register reads `h s`, or 0, or 9, from its hook as it
would from a phone's. The caller's next digit is at least 370 ms away (their pause
less the 128 ms already spent), against a hunt of 8 ms. No register free: the
marker points the trunk at the cannot-complete tone — *claimed, cannot complete*
— and the caller hears it at once.

An incoming call therefore costs the register pool one register for two digits,
and only at the exchange that owns it. Every other exchange spends a monitor for
one digit, if its `e` is not the one dialled, or for two.

---

## 3. The two rules

A monitor that counts a partial digit claims a call for the wrong exchange, and
the caller gets a wrong number with no sign that anything failed. Two things can
make a count partial, and each needs its own rule.

**1. A monitor counts only a seizure whose rise it saw.** A monitor that attaches
late — because it was busy — may attach in the *pause between two digits*. It
then sees all the steady make anyone could ask for, and counts a later digit
as the first: `b` as `e`, and `h` as `b`. The rule first written, "count only after 128 ms of make", guards
against attaching in mid-digit and does nothing about this. Seeing the rise is
the only proof that nothing has gone by. A pooled monitor is therefore given a
seizure within one scan of its rise — 1 ms, in which no pulse can fit — or not at
all. (`exch.py monitor` allowed 6 ms, the scan of six channels on the 1 kHz tick.
The scanner now steps all eight slots, because a trunk's channels sit where they
are on the wire (`exch-protocol.md` §5), and on the tick that would take 8 ms,
which is as long as the shortest break that counts. So it steps on the 8 kHz
octet mark, as the marker's scanner does. The measured rows do not depend on the
figure: a monitor given the seizure counts from the rise.)

**2. The origin abandons a call whose next break comes within 128 ms of its
seizure.** The flood takes time to spread: 7 ms a hop, 12 at a slow marker. A
caller whose next digit begins before the last exchange is patched in has their
first pulse or two swallowed at the far end, where the monitor — which *did* see
its rise — counts a digit short. Only the origin can know: it sees both its own
seizure and the caller's next break. One tap on a counter: if the break comes
inside the guard, release the trunks and give cannot-complete. 128 ms covers ten
hops at the slow figure.

Together they make the budget `exch-network.md` §4 uses: the digit recognised
(128 ms), the seizure (2), the guard (128) — **the flood is ready 258 ms after
the caller's last pulse, whatever the hop count**, against the 500–800 ms a dial
takes between digits.

---

## 4. Where it sits, and how many

On each block that holds trunks, watching that block's trunk ports. A pool, not
one a channel:

```
 scanner   a 3-bit counter on the 8 kHz octet mark steps the block's eight slots, one a visit,
           reads the slot's word over the visit, and attends only a slot whose word says trunk.  A block may hold an MF8 card beside idle,
           the operator or the tones, or a single-channel trunk among lines (exch-network.md §1.1),
           and a subscriber lifting is never read as a seizure.  For channel k:
           M[k] high, and low at the last visit  → a fresh seizure, at most 1 ms old
             a monitor is free → it latches k and starts counting
             none is free      → the seizure goes unwatched here, for good
           (the last-visit bit is what makes rule 1 true by construction)
           A nailed channel (ex-extensions.md §3.3) sends a nail and not a class, so it is never
           attended, and never read as dialling
```

A seizure nobody watched is still patched onward — the marker does that, not the
monitor — so **an exchange with no free monitor still passes the call; it just
cannot be the one that owns it.**

Every call dialled with `1`, anywhere in the network, wants a monitor on each
block its flood reaches. A monitor whose `e` is the one dialled holds until `b` is
in: 2.7 s on average from the seizure. One whose `e` is not lets go after the
first digit: 1.5 s (`exch-network.md` §4). A local call wants none. Erlang B for
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

**Measured against a network, `exch.py net`** (`exch-network.md` §5.1): eight
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

**The model runs the earlier numbering**: a trigger digit, one digit compared,
one digit more. Under `1 e b h s` the digit compared first is `e`, and `b` is
compared after it. Both hazards below act on the first digit a monitor hears,
whichever it is. A second compared digit adds no new way of attaching late,
because the monitor is attached by then. It is not in the model, and is to be
run.

A chain of seven exchanges with `b` = 1–7; a dial at 10 pps ± 10 %, 60/40; the
trigger digit, `b` (1–7, or ten pulses for an exchange that is not there), one
digit more. The origin seizes 130 ms after the trigger's last pulse; each
exchange patches onward 3–10 ms after its M rises; A crosses every hop through
the trunk's A path as `exch.py aline` measured it; a claim cuts the onward patch.
1 500 calls a row. **False = an exchange other than the one dialled claimed the
call.**

| a monitor counts | origin guard | pause between digits | right | no claim | **false** |
|---|---|---|---|---|---|
| from whenever it attaches, after 128 ms of make | none | 140–900 ms | 49.5 % | 44.1 % | **97** |
| the same | none | 450–900 ms | 68.2 % | 29.9 % | **29** |
| the same | 128 ms | 140–900 ms | 49.9 % | 47.7 % | **36** |
| the same | 128 ms | 450–900 ms | 70.4 % | 28.9 % | **11** |
| only a seizure whose rise it saw | none | 140–900 ms | 81.9 % | 17.9 % | **4** |
| the same | none | 450–900 ms | 81.5 % | 18.5 % | 0 |
| **only a seizure whose rise it saw** | **128 ms** | 140–900 ms | 70.8 % | 29.2 % | **0** |
| the same, line BER 1e−2 on every hop | 128 ms | 140–900 ms | 71.4 % | 28.6 % | **0** |
| the same | 128 ms | 450–900 ms | 83.7 % | 16.3 % | **0** |
| the same, line BER 1e−2 on every hop | 128 ms | 450–900 ms | 82.6 % | 17.4 % | **0** |

- **The old rule gives wrong numbers even to a careful caller**: 29 in 1 500 at
  human pauses, from monitors attaching between digits.
- **Rule 1 alone is safe for a human and not for a fast one**: the four false
  claims are all callers whose next digit began before the flood was complete.
- **Both rules: none**, at any pause a pulse register can read at all, clean or
  at a line error rate of 1e−2.
- *No claim* is the safe failure — the origin times out and returns
  cannot-complete. In the rows that need the rise seen, one monitor in five was
  made busy on purpose, and that is most of it; with the guard, callers pausing
  under 258 ms are abandoned as well.
- 140 ms is the floor for **any** pulse register: below it two digits run
  together (`register.md` §3.2), flood or no flood.

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
| the scanned slot's word, trunk or not: the block's word commutator sampled in that slot's cell, one bit a frame | 74HC164 and a gate, ≈ 1½ |
| free-monitor pick, gating | 74HC00, 74HC08 |

**≈ 8½ packages a monitor, ≈ 6½ shared: ≈ 24 for a block with two, ≈ 32 with three.** The same
count-then-clear ordering as the register applies (`circuit-review.md` §3): the
edge enables the count and clears the timer a tick later.

**To the network card:** `CLAIM_REQ` and the channel (3 bits). **From it:** an
acknowledge that frees the monitor. **Jumpers:** `e` and `b`, four bits each,
the network card's own-code jumpers bussed to the monitors. Each is the digit's
pulse count as the counter holds it, so a 0 is jumpered `1010`, ten pulses, and
the compare is all four bits. 8 and 9 are never jumpered, so neither can match.

---

## 7. Not measured

- **The second compared digit.** `exch.py monitor` compares one digit. Two, with
  the let-go after a first digit that is not ours, are to be run.
- **The circuit.** A sketch; the orderings are the register's and have not been
  drawn for this.
- **The scanner's 1 ms** against a real seizure's rise through the A path's
  Schmitt gate; the model gives a pooled monitor the rise or nothing.
- **A slow marker.** The guard assumes no exchange takes more than about 12 ms to
  patch a seizure onward. A marker held up longer than that is a partial count at
  every exchange beyond it, and nothing here detects it.
- **Copper ties.** Between exchanges in one rack a trunk is a crossover with no
  A-path RC, so pulses arrive undistorted and a hop is a frame; the model used
  the MF8 figures throughout, which are the worse.
- **How fast people really dial**, which is what the no-claim column is made of.
