# Dialling: what the register is given, and its windows measured

How a dial's pulses reach the register through the CVSD line card's hook
detector, why the register's three windows sit where they do, and how they
held against 3 200 dialled digits. The rule this supports is
`register.md` §1.

> **Analysis, measured in simulation:** `sim/subline.py register` (dial, `1100`, line, receiver, hook detector, register, tick by tick) and `subline.py dial` (the pulses the register is given).
> **Changed since, not re-run:** the built register samples M off `/HA` at 1 kHz, where this model saw the detector continuously; `pulse_rx.v` counts a break once it has lasted HIT, not at its end, and its tick is `SCAN5`'s fall, not §2's `TX_OCT` ÷ 8 (the same 1 kHz); `tb_dial` dials the nominal corners (28 ms breaks at 20 pps), not the measured 18 ms.
> **Unchanged:** HIT 8, ID 128, CLR 256 ms. The mute of §1.1 and the correction of §1.3 are proposals, not in `newimpl`.

---

## 1. What the register is given

The line card reduces the phone's upstream to one level, `ON_HOOK`
(`common/channel-cards.md` §2.2): `1100` → `Q ⊕ Q[n−2]` → 4 ms RC → comparator 0.85 / 0.70.
From there on, a dial pulse is a loop break like any other, and nothing in the
register knows the line is digital. What the register does inherit is the
detector's timing. The RC climbs from the make's density to 0.85, then falls
from 1.0 to 0.70, and the two do not take the same time.

Digit 0, ten breaks, at seven dial settings from 7 pps 56/44 to 20 pps 60/40,
each clean, at noise sd 0.8, and at 100 and 1000 impulses/s (`subline.py dial`):

| the makes carry | pulses counted | break as seen, against sent | |
|---|---|---|---|
| **`1010`: the dial mutes the transmitter** | **10 / 10 in all 28 cells** | **6.1 ms short on every pulse**; −6.9 to −4.9 ms at 1000 impulses/s | every break starts the RC from 0: 7.6 ms to climb to 0.85, 1.4 ms to fall to 0.70 |
| speech: it does not | 10 / 10 in all 28 cells | 0.1 to 7.5 ms short | the RC starts from wherever the talker left it |

Makes are lengthened by what breaks lose. Every count was right, so the
register itself would not care (§3). The distortion still decides two things:
what the phone should do while dialling (§1.1), and whether pulses can be passed
on as pulses (§1.3).

### 1.1 The dialling technique: mute the transmitter while the dial is off normal

A rotary dial carries an off-normal contact that closes while the dial is wound
away from rest. Analog sets use it to quiet themselves while dialling.
**Specify it here as the encoder's mute:** while the dial is off normal, the
encoder input is held at silence. The makes between breaks then carry the
codec's own idle `1010`, whose `Q ⊕ Q[n−2]` is 0, and the shortening becomes
one number set by the RC and the thresholds alone:

```
τ · ( ln 1/(1 − 0.85) − ln 1/0.70 )  =  4 ms × 1.540  =  6.16 ms
```

Without the mute it depends on what the microphone hears, anywhere from 0.1 to
7.5 ms. The phone logic of `common/subscriber-line.md` §4 gains one line and a gate.

### 1.2 Why not move the thresholds

The obvious fix is thresholds placed symmetrically, so that assert and release
take equal time. They cannot move. The release threshold must sit above
everything off-hook traffic produces, which is 0.60 under 1000 impulses/s
(`common/subscriber-line.md` §3.1). Otherwise a talking phone would never read
off-hook, and the assert threshold has to sit higher still. Talk-state safety
is what puts both thresholds high, and the asymmetry comes with them. The
correction belongs after the comparator, where it cannot touch the measured
safety.

### 1.3 When it matters: pulses repeated, not registered

To the register, the distortion does not matter: every window in §2 has tens
of milliseconds to spare. It matters where pulses are passed on as pulses. On
an extended line (`common/channel-cards.md` §1), the phone's breaks cross the trunk on the
A bit and an FXO card opens a CO loop with them. The phone leg takes 6.1 ms off
every break and the A path takes 0.5 ms more (`common/channel-cards.md` §5). A 60/40 dial
reaches the CO as 53/47, outside both ranges ES 201 187 allows a phone to send
(56–64 % and 63–72 %). Whether a given CO still counts it depends on that
CO's pulse receiver, not on a spec.

**The correction is to hold `ON_HOOK` 6.16 ms after each release**: ½ 74HC123
triggered on the falling edge, ORed back in, on the line card ahead of `A_TX`.
With the transmitter muted, this brings every break back to within −0.7 to
+1.3 ms of what was sent, in every condition measured, and within ±0.4 ms
below 1000 impulses/s. With speech under the dial the error is −1.4 to
+6.1 ms, which is one more reason to mute. The only other effect is 6 ms of
extra delay on the off-hook edge. The detector's thresholds and its
false-event record are untouched. A ±10 % monostable adds ±0.6 ms.

---

## 2. The windows

A pulse register makes three decisions, all from one timer.

| decision | must be yes for | must be no for | window |
|---|---|---|---|
| is this break a pulse? | the shortest dial break: 46.7 ms at 12 pps 56 %, 28 ms at 20 pps | a hit the detector passed | **break ≥ 8 ms** |
| does this make end the digit? | the shortest pause between digits: ≥ 720 ms from a phone to ES 201 187 | the longest make inside a digit: 62.9 ms at 7 pps 56 % | **make ≥ 128 ms** |
| is this break the caller hanging up? | anything held on-hook | the longest dial break: 102.9 ms at 7 pps 72 % | **break ≥ 256 ms** |

**The envelope.** ES 201 187 asks a phone for 10 ± 1 pps, a break of 56–64 %
or 63–72 % of the period depending on the network, at least 720 ms between
digits, and at least 500 ms before the first. Exchanges have always accepted
more: 7 to 12 pps in the GPO standard, 8 to 11 in the Bell System. The register
is designed for **7–12 pps and 56–72 % break**. It also takes 20 pps, which a
register, unlike a direct-control selector, always could.

**Why these values.** They are three taps of one ripple counter on a 1 kHz
tick: 8, 128 and 256 ms are a 74HC4040's Q4, Q8 and Q9, and the tick is
`TX_OCT` ÷ 8 exactly. Each sits well inside its gap:

- **ID at 128 ms** is twice the longest in-digit make and under a fifth of the
  shortest pause a phone may send. It sits low in that gap because it is also
  the post-dialling delay: the last digit is not known until 128 ms after the
  last break.
- **CLR at 256 ms** is 2.5 times the longest dial break.
- **HIT at 8 ms**, with the detector's 6.1 ms and the timer's one tick, means
  a break must last about 15 ms to count. That is half the shortest break at
  20 pps.

**A flash is a digit.** To any pulse register, a hook flash the length of a
dial break is a digit 1. That is why timed-break recall needs a DTMF phone.
With CLR at 256 ms, a longer flash reads as a hang-up. A simple exchange that
offers no recall loses nothing.

---

## 3. Measured

### 3.1 End to end

Random four-digit strings, 50 per cell. Each string draws its own dial: a
rate in the range shown, a break ratio of 56–72 %, ±2 % jitter on each pulse,
a pause of 250–1000 ms before each digit (a third of ES 201 187's minimum and
up), a random tick phase, and one of the seven talkers. Widths are as the
register's own timer measured them, in ms.

| dial | makes | line | digits | wrong | break counted | make in a digit | pause |
|---|---|---|---|---|---|---|---|
| 7–12 pps | idle | clean, sd 0.8, 100 and 1000 impulses/s | 800 | **0** | 40 – 93 | 28 – 67 | ≥ 256 |
| 7–12 pps | speech | same | 800 | **0** | 40 – 99 | 26 – 67 | ≥ 255 |
| 20 pps | idle | same | 800 | **0** | 18 – 35 | 17 – 30 | ≥ 256 |
| 20 pps | speech | same | 800 | **0** | 18 – 38 | 13 – 29 | ≥ 255 |

**3 200 digits, none wrong.** The windows against what the timer saw:

| window | the nearest traffic came | margin |
|---|---|---|
| HIT, 8 ms | shortest break counted: 18 ms at 20 pps, 40 ms at 7–12 | 2.3× |
| ID, 128 ms, from below | longest make inside a digit: 67 ms | 61 ms |
| ID, 128 ms, from above | shortest pause: 255 ms, for 250 ms sent | 127 ms |
| CLR, 256 ms | longest break: 99 ms | 157 ms |

### 3.2 Where each window gives way

Clean line, idle makes, one run per row. The register fails exactly where the
windows and the 6.1 ms say it will, and nowhere else:

| stress | holds at | gives way at | how |
|---|---|---|---|
| pause between two digits (2, then 3, at 10 pps) | 125 ms sent, 130 timed | 120 ms sent | read as one digit, 5 |
| a slow dial's make (digit 3, 56 % break) | 3.6 pps: 122 ms make, 128 timed | 3.4 pps: 129 ms make | split: 1, 1, 1 |
| one long break (digit 2) | 260 ms | 280 ms | CLEAR |
| one short break (digit 3) | 16 ms | 8–14 ms: seen, but short of HIT | read 2 |
| | | 6 ms: not seen by the detector at all | read 1, 1: the two makes merged into a pause |

Every boundary is a window shifted by §1's 6.1 ms and the timer's one tick,
and nothing else. To fail, a dial would have to run below about 3.5 pps to
split a digit, a phone would have to pause less than about 123 ms to merge
two, and a single break would have to last more than about 263 ms to clear.

### 3.3 Clearing

4 and 2 dialled at 10 pps 60/40, then the event 500 ms later:

| event | digits read | CLEAR after |
|---|---|---|
| phone hung up | 4, 2 | 266 ms |
| pair cut, quiet | 4, 2 | 266 ms |
| pair cut, noise sd 0.3 | 4, 2 | 266 ms |
| pair cut, 100 impulses/s | 4, 2 | 266 ms |
| hung up on the fourth pulse of a 5 | none: the partial digit is never strobed | 266 ms |

**A cut pair clears exactly like a hang-up.** The detector's violation and
carrier terms force G to 1 on a dead pair within 2 cells, as `1100` does
(`common/subscriber-line.md` §3), so the register sees an ordinary break that grows
past 256 ms. 266 ms is the detector's 7.6 ms, CLR, the synchronizer and the
late restart. No spurious digit appears, because the break never ends and so
is never counted.
