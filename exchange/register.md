# The register — reading the dial into a simple exchange

The MF8 shelf of `mf8-backplane.md` extends lines. It does not switch them. An
exchange needs three more things: a **register** that reads the number a caller
dials, a **switch** that decides who hears whom, and a **marker** that sets the
switch from the register. This document covers the register: how the dial
pulses of `subscriber-line.md` §5 become digits in a store, built in 74HC, and
how one register serves every line. It sketches the switch and the marker only
as far as the register's interface to them (§6).

> **Status: proposed, measured in simulation.** `subline.py register` runs the
> whole chain tick by tick: dial, `1100`, line, receiver, hook detector,
> register. `subline.py dial` measures the pulses the register is given. The
> circuit is a proposal from data-sheet behaviour. Nothing has been on a bench.

---

## 1. What the register is given

The line card reduces the phone's upstream to one level, `ON_HOOK`
(`channel-cards.md` §2.2): `1100` → `Q ⊕ Q[n−2]` → 4 ms RC → comparator 0.85 / 0.70.
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
7.5 ms. The phone logic of `subscriber-line.md` §4 gains one line and a gate.

### 1.2 Why not move the thresholds

The obvious fix is thresholds placed symmetrically, so that assert and release
take equal time. They cannot move. The release threshold must sit above
everything off-hook traffic produces, which is 0.60 under 1000 impulses/s
(`subscriber-line.md` §3.1). Otherwise a talking phone would never read
off-hook, and the assert threshold has to sit higher still. Talk-state safety
is what puts both thresholds high, and the asymmetry comes with them. The
correction belongs after the comparator, where it cannot touch the measured
safety.

### 1.3 When it matters: pulses repeated, not registered

To the register, the distortion does not matter: every window in §2 has tens
of milliseconds to spare. It matters where pulses are passed on as pulses. On
an extended line (`channel-cards.md` §1), the phone's breaks cross the trunk on the
A bit and an FXO card opens a CO loop with them. The phone leg takes 6.1 ms off
every break and the A path takes 0.5 ms more (`channel-cards.md` §5). A 60/40 dial
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
(`subscriber-line.md` §3), so the register sees an ordinary break that grows
past 256 ms. 266 ms is the detector's 7.6 ms, CLR, the synchronizer and the
late restart. No spurious digit appears, because the break never ends and so
is never counted.

---

## 4. The circuit

```
 TX_OCT 8 kHz ─[ ½ 74HC393, ÷8 ]─ TICK, 1 kHz ─────────────────────── clocks everything below

 A_TX[1..8] ─[ 74HC151, W output ]─ H ─[ D1 ]─[ D2 ]─[ D3 ]─[ D4 ]           74HC175, on TICK
              ▲ LINE, 3 bits from the finder     │      │      ▲
                                        BRK = D2 ┘      │      │
                                    EDGE = D2 ⊕ D3 ─────┴──────┘   D4 = EDGE a tick later = RST

 74HC4040   on TICK, reset by RST         Q4 ─▶ HIT ┐
                                          Q8 ─▶ ID  ├─ D flip-flops, D = 1, clocked by the tap, cleared by RST
                                          Q9 ─▶ CLR ┘
 74HC163 + FF   pulse count, on TICK  enable  EDGE · /BRK · HIT · /CLR          a break has just ended, and was a pulse
                                      clear   STB, synchronous                  five bits, so 16 pulses is 16, not a wrap
 STB      = ID · /ID' · /BRK · (count ≠ 0)                                       ID' is ID a tick later
 74HC670 + nibble  the store, four digits   write the count at N, while STB, in the tick's second half
                                      four bits of each digit in the '670; the four MSBs in one nibble of a second '670
                                      (pulse-gen.md 4: D is 16 pulses)
 N          digit index               ½ 74HC393, advanced by STB's end
 RELEASE  = CLR · BRK                 the caller hung up, or the pair is cut
```

**Count, then clear.** The counter must read HIT on the tick after the edge,
but the edge is also what clears HIT. If the edge cleared the latches directly,
the counter would find HIT already gone. So the edge enables the count, and
`RST` (the edge one tick later, from the '175's fourth stage) clears the timer
and its latches. The timer restarts a tick late, and every width it measures
is one tick short. This is `circuit-review.md` §3's sample-then-retrigger, one
level up, and `subline.py` models it. The store has the same issue at the
digit strobe. The '670 is written during the second half of the strobe's tick,
so the write completes before the edge that clears the '163.

**The count is the MT8870's code.** A binary '163 reaches `1010` on the tenth
pulse, and `1010` is what an MT8870-class DTMF receiver presents for 0. Digits
1–9 are `0001`–`1001` on both. Pulse and tone digits therefore share one store
with no translation (§7). A decade '160 would read 0 as `0000`, which is the
MT8870's D. Sixteen pulses — keypad D of `pulse-gen.md` — need the fifth bit:
the store holds `10000`, which no MT8870 produces, and the marker's `isvc`
treats it as service, as it does 11–15.

| block | parts |
|---|---|
| tick ÷ 8, digit index | 74HC393 |
| line select | 74HC151 |
| synchronizer, edge, `RST` | 74HC175, ¼ 74HC86 |
| timer | 74HC4040 |
| HIT, ID, CLR, ID' | 2 × 74HC74 |
| pulse count | 74HC163 + 1 FF (five bits: 1–16) |
| store | 74HC670 + one nibble of a second '670 |
| held party `SRC` (§6.1) | ½ 74HC174 (six bits), or spare in a second '670 |
| count ≠ 0, strobe and enable gating | 74HC4002, 74HC08 |

**≈ 11½ packages, one register for the exchange** (§5). With the held field,
≈ 12.

---

## 5. One register for every line

A register works for a few seconds per call and is idle the rest of the time.

- **One per line.** Drop the '151 and put the rest on each line card: ten
  packages a line, idle more than 99 % of the time.
- **One shared, found by a finder.** This is the design proposed here. While
  the register is free, a 3-bit counter on the tick steps `LINE` through the
  lines. It stops on one that is off-hook and not already in a call (a `BUSY`
  bit per line, kept by the marker), and the switch gives that line dial tone.
  The hunt reaches any of eight lines within 8 ms. The register's synchronizer
  and counter are held clear while it hunts.
- **Scanned.** Exchanges with hundreds of lines kept each line's timer and
  count in memory and ran one sequencer past them all. The trunk card's
  signalling mux already scans six hook states at 8 kHz. At eight lines this
  is not worth it.
- **Direct control.** Strowger's selectors stepped once per pulse and needed no
  register. Here the analogue would be a per-line address counter stepped by
  that line's own pulses. It gives one digit in one direction, and nothing to
  ring the called phone or check that it is free. Those are the jobs a register
  exists to hand to a marker.

**How many.** As an assumption, say each of eight lines makes three calls in
the busiest hour and the register holds each for 10 s: dial tone, four digits,
pauses. That is 0.067 erlang. With **one register**, a caller finds it busy
1 time in 15 and waits about 11 s for dial tone. With **two**, it is 1 time in
465. One is enough for eight lines, and two is the choice if waiting for dial tone
is not acceptable. This is arithmetic on assumed calling rates, not a measurement.

---

## 6. What the register hands on

| to the marker | |
|---|---|
| `LINE` / `port` | the caller, six bits (was three on the eight-line sketch) |
| `SRC` | **held party**, six bits: `00` = none; non-zero only on an operator transfer attach (§6.1) |
| `D1`…`D4` | the store's read port, addressed by the marker |
| `N` | digits so far |
| `DONE` | `N` has reached the numbering plan's length. With eight lines or fewer, that is one digit |
| `RELEASE` / `gone` | CLR, or a partial-dial timeout: the caller gave up |

| from the marker | |
|---|---|
| `FREE` / `release` | clears the store, `N`, and `SRC`, and restarts the finder |
| `attach` + `attach_port` + `attach_src` | seize the register for this caller; `attach_src` is the held party or `00` |
| `restart` | begin the store again, caller unchanged. The network unit pulses this too (`common-control.md` §2.1): key `1`, then own `e b` |

**Parts for `SRC`.** Six bits loaded at attach and cleared when the register is
freed: half a 74HC174, or six bits of a second '670 if one is already on the
card for digits. **+6 bits a register**, 12–18 for a pool of two or three —
not two dial digits. `00` means empty because port 00 is never a talking party
(`protocol.md` §5).

### 6.1 Operator transfer: `SRC` is the held party — deferred

A busy operator-class port cannot get a second register by lifting
(`operator.md` §3, `console.md` §7). **Transfer for now is console keys only**
(`console.md` §7, measured). Phone flash — a break the length of dial digit
`1` while the call is up, re-attaching a register with `SRC` = the held party —
is **deferred** (`operator.md` §5). `1` at dial tone stays the network key /
highway digit either way.

The field and the marker's consult / CLR pair path are in RTL as hooks: when
`attach_src` is non-zero, connect keeps the register (`M_CONSULT`), hang-up
pairs held ↔ called, and abandon restores the operator to the held party.
Transfer consult is **local only** in that first cut — a network key with
`SRC` set is refused. **Flash detect and filling `attach_src` are not wired**;
every attach today loads `SRC` = 00. Latches cannot be read back; a card-local
write-shadow was the preferred future shape (`operator.md` §5), not designed
here.

**Also useful once flash is revisited**

| | |
|---|---|
| **Consultation return** | second flash or nodig before connect: back to `SRC` (same abandon path) |
| **Attended vs blind** | hang up after connect = attended transfer; (later) release without talk = blind |
| **Trunk as held** | `SRC` may be a trunk port — abandon/transfer must not leave it hung; same writes |
| **Restricted / audit** | counters can see that a connect had a non-zero `SRC` (operator-handled call) |
| **Not call waiting** | switching between two live parties still needs more than one held field |

**A sketch of the switch, not a design.** Every line's upstream is already a
bit stream on `TX_CLK` inside the line card (`mf8-backplane.md` §2), and every
downstream is already chosen on `TX_CLK` by the card's rule (`channel-cards.md`
§2.3). Replace that rule's `C_RX` input with an 8:1 selector over the other
lines' upstreams, addressed by a 3-bit latch the marker writes, and the shelf
becomes a non-blocking switch for eight 64 kbps lines: one '151 and one '175
per line. Tones (dial, ringback, busy) are further inputs to the selector. It
needs its own document.

**Trunk calls.** Suppose one digit, say 9, routes to the trunk. There are two
ways to pass on the digits that follow:

- **Cut through.** The register releases and the caller's remaining pulses
  cross on the A bit. This is §1.3's case, and it wants the 6.16 ms correction.
- **Register-sender.** The register keeps the remaining digits and sends them
  itself as fresh 10 pps 60/40 pulses from the same tick. No distortion
  survives, and a 20 pps phone can dial through a 10 pps CO. The cost is a
  second counter and a longer store.

---

## 7. DTMF into the same store

An MT8870's StD strobe writes its code into the '670 through the same port,
ORed with the pulse strobe. It is the same store and the same code (§4). The
receiver needs audio. The served line's upstream bits are selected by the same
`LINE` (a second '151, on the lines' upstreams), decoded by the decoder half of
`mf8-spec.md` §12.1's engine, and passed through its 3.4 kHz reconstruction
filter. `subscriber-line.md` §5 measured DTMF through that codec: usable from
25 dB below nominal speech to 6 dB above. **One DTMF receiver per register,
not per line.** That is `subscriber-line.md` §5's "a DTMF receiver belongs at
the exchange" made concrete.

---

## 8. Not measured

- **The circuit.** It is a proposal from data-sheet behaviour, including the two
  count-then-clear orderings of §4. Scope `EDGE`, `RST` and the '670's write
  against `TICK` at bring-up.
- **A real dial.** Contact bounce at make and break should be invisible to a
  4 ms RC, by reasoning. The model's dial is ideal apart from ±2 % jitter per
  pulse. The off-normal mute of §1.1 has not been tried on a phone.
- **The correction of §1.3 against a real CO**, and a real CO's pulse receiver
  against the uncorrected 53 %.
- **DTMF into an MT8870** after the CVSD decoder. §7 rests on
  `subscriber-line.md` §5's SINAD and twist figures, not on a receiver.
- **The finder, the marker and the switch.** They are sketched only.
- **The partial-dial and permanent-signal timeouts.** They need a second
  counter measuring seconds; they are not modelled.
- **Rare events.** 3 200 digits with none wrong bounds the error rate below
  about 1 in 1 000 per digit at 95 % confidence, the rule of three. It does not
  show that the rate is zero. The margins of §3.1 are the stronger evidence.
