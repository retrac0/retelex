# Line receiver card

One card per direction per end, identical at both ends. It recovers bits from
the line with no clock of its own, finds the frame (spec §7), and delivers A and
C bits with a receive frame clock to the seven channel slots.

Status: the receive chain — input filter, slicer, interval classifier, framer —
is the one the simulation measures, and §4–§7 give its measured tolerances
(`rx_review.py`, `s4_simple.py spec`, spec §6). The circuit around it — parts,
timing between flip-flops, the rate plug, package count — is a design proposal
and has not been built.

---

## 1. Block diagram

```
 pair ─ protection ─ 1:1 transformer (≥ 33 mH, centre tap) ─ termination
                                                                │
                                        [preamp / equaliser footprint]
                                                                │
                            input low-pass, two RC sections ── RATE PLUG
                                                                │
                            comparator, ~50 mV hysteresis (75176 receiver half)
                                                │                     │
                                    transition detector        carrier detect
                                                │              (retriggerable,
                        dead-time timer ── RATE PLUG            2 cells) ── RATE PLUG
                        (ignore < 0.2 cell)                           │
                                                │                     │
                        classifier timer ── RATE PLUG                 │
                        (long gap > 0.75 cell), mid-cell flip-flop    │
                                                │                     │
                                   recovered bit + bit strobe         │
                                                │                     │
                                 slip gate ─→ frame counter b0..b3    │
                                                │   (CHANNEL strap:   │
                                                │    mask, frame clock)
                    ┌───────────────────────────┼─────────────┐       │
                    │                           │             │       │
          framer (spec §7)                 74HC259 A     74HC259 C    │
          T history, one-zero decode,      addr b1..b3   addr b1..b3  │
          acquisition count, LOF counter,  when b0 = 0   when b0 = 1  │
          lock ─────────── not locked ──┐       │             │       │
                                        └── OR ─┴─ no carrier ┘       │
                                            │         │             │
                                          MUTE    A1..A7        C1..C7    RX frame clock
                                            └─────────────→ channel slots ←───────┘
```

---

## 2. Line interface

The same parts as the transmitter's output side (`line-transmitter.md` §6), and
the same front end as the repeater's receive half (`repeater.md` §2):

| item | specification |
|---|---|
| Protection | gas tube to ground on both conductors, series PTC or fuse, TVS clamping **above the eventual 48 V feed** |
| Transformer | 1:1, **≥ 33 mH**, centre-tapped on the line side — the same part as the transmitter |
| Centre tap | brought out to the unpopulated simplex-feed footprint |
| Termination | the pair's characteristic impedance, 100–135 Ω, on the line side of the comparator. A receiver must never look like a bridged tap |
| Preamp / equaliser | footprint, unpopulated on short spans; populate when the span loss leaves less than about 0.5 V at the comparator |

**Deliver about a volt to the comparator.** The comparator's hysteresis is fixed
in millivolts (about 50 mV for a 75176-class receiver), so what matters is its
ratio to the received amplitude:

| hysteresis ÷ received amplitude | 0 | 0.02 | 0.05 | 0.10 | 0.20 | 0.30 |
|---|---|---|---|---|---|---|
| sd 0.4 | ok | ok | ok | ok | ok | ok |
| sd 0.5 | ok | ok | ok | ok | ok | ok |
| sd 0.6 | ok | ok | ok | ok | ok | 4e-01 |

(`rx_review.py` §2, single span, 256 kbps.) A single span tolerates 20%. A
repeatered route does not: `repeater.md` §2.4 measures an order of magnitude
lost by nine spans at 20%. **Specify ≤ 10%**, which is 0.5 V at the comparator
for 50 mV of hysteresis, and aim for a volt.

---

## 3. Input filter

A low-pass ahead of the comparator sets how much line noise reaches the slicer.
It is what gives lower line rates their noise advantage (spec §2.1, +3 dB per
halving), and **it must move with the rate**.

Error-free noise level against the filter corner, one fixed cable and noise
floor, 256 kbps (`rx_review.py` §3–4):

| corner ÷ symbol rate | 0.5 | 0.75 | 1.0 | 1.5 | 2 | 4 | 8 |
|---|---|---|---|---|---|---|---|
| 2nd-order Butterworth, error-free to sd | 0.6 | **0.7** | 0.6 | 0.5 | 0.4 | 0.3 | < 0.3 |
| two first-order RC sections, error-free to sd | 0.5 | 0.6 | **0.6** | **0.6** | 0.5 | 0.3 | < 0.3 |

- **An unswitched filter throws the low rates away.** A filter set for
  1024 kbps and left there puts the 128 kbps line rate at 8× its symbol rate.
  That leaves no margin at all, where a switched filter gives sd 0.6–0.7.
- **Two RC sections are enough.** They reach within one grid step of the
  Butterworth optimum, and they hold it from 0.75× to 1.5× the symbol rate, so
  component tolerance doesn't matter here.

**Specify: two first-order RC sections, corner at the symbol rate.** Buffer them,
or make the second section's R at least ten times the first so it barely loads
it. Corners by rate are in §8.

---

## 4. Bit recovery — the interval classifier

No PLL, no oversampling, no clock. The receiver times the gap between
transitions against two thresholds. This is exactly the behaviour of
`fast.mono_decode`, which every measurement in the repository uses:

```
on each transition from the comparator:
    if less than DEAD since the last ACCEPTED transition:  ignore it
    otherwise accept it:
        if more than 0.75 cell since the previous accepted transition:  emit 1, clear MID
        else if MID is set:                                              emit 0, clear MID
        else:                                                            set MID
```

A 1 bit has no mid-cell transition, so its gap is a full cell. A 0 bit produces
two half-cell gaps, and the MID flip-flop pairs them. **The state self-heals**:
any full-cell gap clears MID, so a disturbed state recovers within a couple of
bits, and there is no lock to lose.

### 4.1 Classifier threshold — 0.75 cell, ±13%

| condition | usable threshold | margin about 0.75 |
|---|---|---|
| clean | 0.55 – 0.95 | ±27% |
| sd 0.3 | 0.60 – 0.90 | ±20% |
| **sd 0.4, design limit** | 0.60 – 0.85 | **±13%** |
| sd 0.5 | 0.65 – 0.80 | ±7% |

(Spec §6.2. The same relative window was measured at 128, 512 and 1024 kbps.)
The timer's R, its C, and the timer IC's own pulse-width constant together must
stay inside ±13% over supply and temperature. A 1% resistor and a 2% C0G
capacitor give ±3%. **Check the chosen timer IC's pulse-width tolerance against
the remaining ±10%** before committing, and measure the window edges on the bench
(§11, step 2).

### 4.2 Dead time — 0.2 cell, loose

| dead time, fraction of a cell | 0.05 | 0.10 | 0.15 | 0.20 | 0.25 | 0.30 | 0.35 | 0.40 | 0.45 |
|---|---|---|---|---|---|---|---|---|---|
| clean | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| sd 0.4 | ok | ok | ok | ok | ok | ok | ok | 4e-01 | 1e+00 |
| sd 0.5 | ok | ok | ok | ok | ok | ok | 3e-02 | 4e-01 | 1e+00 |

(`rx_review.py` §1.) Anything from 0.05 to 0.30 cell works to sd 0.5.
**Specify 0.2 cell**, which sits centrally with ±50% either way; the 0.25 used in
every other measurement is inside the window. The dead time only swallows
comparator chatter, so ordinary tolerances are fine. It must be
**non-retriggerable**: an ignored transition does not restart it.

### 4.3 Parts and timing

| function | proposal |
|---|---|
| Transition detector | 74HC86: comparator output XOR a short RC-delayed copy, one pulse per transition |
| Dead-time timer | ½ 74HC221 (non-retriggerable); accepted transition = pulse AND NOT dead-time running |
| Classifier timer | ½ 74HC123 (retriggerable), triggered by each accepted transition |
| LONG sample and MID state | 74HC74: LONG captures "classifier timer expired" on the accepted transition; MID per the rule above |
| Bit strobe | accepted transition gated by `LONG + MID` (before MID updates); recovered bit = LONG |

**Sample, then retrigger.** At each accepted transition the classifier timer's
state must be captured before the same transition retriggers it. The timer's
trigger-to-output delay, tens of nanoseconds, gives the flip-flop its hold
margin. Confirm it against the specific parts, as `line-transmitter.md` §5 does
for the encoder.

---

## 5. Framing and demultiplexing

### 5.1 Frame counter

A 4-bit counter (½ 74HC393) clocked by the bit strobe through the **slip gate**:
on a bad frame while not locked, one strobe is withheld, and the frame boundary
moves by one line bit. The channel strap masks the counter bits above the frame
width and selects the frame clock stage, exactly as on the transmitter
(`line-transmitter.md` §3).

**Latch, then advance.** Each strobe first latches the recovered bit at the
current count (into the demux, or into S or T), then advances the counter.

### 5.2 Framer

Spec §7 in full; the reference model is `s4_simple.framer_single`.

| function | parts |
|---|---|
| S and T capture at counts 2N and 2N+1 | select = AND of counter bits above b0, as on the transmitter |
| T history, four bits | 74HC175 |
| "Exactly one zero in four" | 74HC151 as a 4-input function |
| Acquisition count to 32; T check enabled at count ≥ 3 | 74HC393, both halves |
| Loss-of-frame counter, +1/−1, floor 0, trip 16 | 74HC193 |
| Lock and slip-pending | 74HC74 |

### 5.3 Demultiplexer — two 74HC259s, no enable gating

The counter's low bit says which bit type is arriving, and the bits above it say
which channel:

| latch | enabled when | address |
|---|---|---|
| A demux | b0 = 0 | b1..b3 (masked) = channel index |
| C demux | b0 = 1 | b1..b3 (masked) = channel index |

The framing bits arrive at counts 2N and 2N+1, channel index N, which is a spare
output of each latch at every channel strap (output 1 at N = 1, 3 at N = 3, 7 at
N = 7). **No enable gating is needed**: S and T land in unused outputs instead of
overwriting a channel.

### 5.4 Receive frame clock

The channel-strap-selected counter stage, b1, b2 or b3. Its falling edge comes at
the counter wrap, after every channel's C bit for the frame has been latched, so a
channel card sampling on that edge receives its bit at exactly one frame period's
spacing. That zero-jitter decoder clock is what the CVSD engine needs (spec §4.2).
During acquisition the slip gate stretches frame periods, but the channels are
muted then.

---

## 6. Mute

```
MUTE = NOT locked  OR  no carrier
```

| on MUTE | effect |
|---|---|
| to every slot | voice cards mute their audio; data cards force RXD = 1 |
| 74HC259 A demux, clear | every received A bit reads 0: voice cards see on-hook, idle |
| 74HC259 C demux | **not** cleared |

**Drive the mute from the not-locked level, not the loss-of-frame edge**
(spec §10.2): a broken line leaves the framer searching indefinitely. The §7
framer never locks on a noise-only line (0/8 skews at sd 0.05, 0.2 and 1.0).

**Why the C demux is not cleared.** A cleared latch presents a constant 0 to
every CVSD decoder, which slams its integrator to the rail and winds its
syllabic filter up (spec §10.1). Muted, that is inaudible, but it leaves the
decoder further from rest at the moment the link relocks. Leaving the C latch
running avoids that. The size of the relock click either way is not measured;
listen for it at bring-up.

---

## 7. Carrier detect — the backstop

A retriggerable timer (the other half of the 74HC123), retriggered by every
comparator transition, timeout **2 cells**. Timed out means no carrier.

Fraction of time with no transition for longer than T, 256 kbps
(`rx_review.py` §5):

| input | T = 1.5 cells | 2 cells | 4 cells | 8 cells |
|---|---|---|---|---|
| signal, clean | 0 | 0 | 0 | 0 |
| signal, sd 0.6 | 0 | 0 | 0 | 0 |
| signal, sd 0.9 (beyond decoding) | 0 | 0 | 0 | 0 |
| **noise only, sd 0.05 — the dangerous case** | 0.94 | **0.92** | 0.85 | 0.72 |
| noise only, sd 0.2 | 0.04 | 0.02 | 0 | 0 |
| noise only, sd 1.0 | 0.003 | 0 | 0 | 0 |

A valid line has a transition every cell by construction and never trips it. The
quiet-noise case that makes squelch mandatory (spec §10.1) reads as no carrier
92% of the time. Louder noise mostly does not, and doesn't need to: the framer
never locks on it, so the not-locked mute already holds.

**Feed no-carrier into the framer as a forced loss of frame**, rather than only
into the MUTE OR. Every timeout then drops lock, and the mute is held until 32
good frames. Without that, a detector flickering on and off at 92% would chatter
the mute. Light an LED from it as well; it is the terminal's half of
`repeater.md` §3.2's "walk the line until the lights go out".

---

## 8. Rate plug

Five components move with the line rate. Put them on a **plug-in header, one plug
per rate**, so a rate change swaps all five at once and none can be left behind:

| line rate | symbol rate | filter corner (both sections) | classifier, 0.75 cell | dead time, 0.2 cell | carrier timeout, 2 cells |
|---|---|---|---|---|---|
| 1024 kbps | 2.048 Mbaud | 2.0 MHz | 732 ns | 195 ns | 1.95 µs |
| 512 kbps | 1.024 Mbaud | 1.0 MHz | 1 465 ns | 391 ns | 3.9 µs |
| **256 kbps** | **512 kbaud** | **512 kHz** | **2 930 ns** | **781 ns** | **7.8 µs** |
| 128 kbps | 256 kbaud | 256 kHz | 5 859 ns | 1 563 ns | 15.6 µs |
| 64 kbps | 128 kbaud | 128 kHz | 11 719 ns | 3 125 ns | 31.3 µs |

**The receiver's rate must match the far end's transmitter**, not this end's.
The two directions are independent and may run different rates (spec §2.2), so
the rate plug is set per direction. The channel strap is different: it must
match this end's transmitter and the far end, and comes from the end's shared
strap block (spec §8.5).

A plug is not the only way. The same selection can be made from a rate code on the
backplane through analog multiplexers (74HC4051, whose ~100 Ω on-resistance is
small against the timing resistors). That costs three to five packages and puts a
switch in series with the filter capacitors, and it buys remote control of the
rate. For a jumper-set system the plug is simpler and cannot be half-changed.

---

## 9. Package count

| function | parts |
|---|---|
| Comparator | 75176 (receiver half) |
| Transition detector, gates | 74HC86, 74HC00 |
| Classifier and carrier-detect timers | 74HC123 |
| Dead-time timer | 74HC221 (½) |
| LONG, MID, lock, slip-pending | 74HC74 × 2 |
| Frame counter | 74HC393 (½) |
| A and C demux | 74HC259 × 2 |
| T history, one-zero decode | 74HC175, 74HC151 |
| Acquisition count, loss-of-frame counter | 74HC393, 74HC193 |
| S/T select, mute OR | 74HC11, 74HC32 |
| Input filter buffer, preamp footprint | op-amp (optional) |

**About 15 packages**, plus the line interface, the rate plug and the channel strap
field. An estimate for the schematic to settle.

---

## 10. What is and is not measured

| item | status |
|---|---|
| Filter corner, filter shape, hysteresis, dead time, carrier-detect timeout | measured, `rx_review.py` |
| Classifier threshold window at four line rates | measured, spec §6.2 |
| Framer, acquisition, loss of frame, mute on noise | measured, `s4_simple.py spec` |
| Chain end to end with the §7 framer: bit-exact, no loss of frame, clean and at sd 0.4, at 64, 256 and 1024 kbps | measured, `rx_review.py` §6 |
| Timer IC tolerance, flip-flop hold margins, filter component values | not measured; datasheet and bench |
| Relock transient with the C demux running | not measured |
| Carrier detect as a forced loss of frame | design, not simulated |

---

## 11. Bring-up order

1. **Front end.** Transmitter looped over a short cable. Scope the comparator
   output: a transition at every cell boundary, clean edges, no chatter. Measure
   the amplitude at the comparator input and confirm the hysteresis ratio is
   under 10%.
2. **Classifier.** Logic analyser on the bit strobe and recovered bit, against
   the transmitter's raw line bit stream: bit-exact after the first few bits.
   Then swap the classifier resistor for a pot and find where errors start in
   each direction. The edges should sit near 0.55 and 0.95 of a cell clean. This
   is the real check of §4.1's timer tolerance.
3. **Framer.** Watch the lock indicator through repeated cold starts, then pull
   and restore the cable: the mute must drop within a few frames and hold until
   relock. Confirm the carrier-detect LED lights with the cable pulled.
4. **Demux.** One card at a time. With the far end's slot empty, the C output of
   that slot alternates frame to frame (the `1010` fill) and its A output reads 0.
5. **Noise.** Inject noise at the input until errors appear; the link should hold
   lock long after audio degrades (spec §11.1).
6. **Every rate plug**, repeating steps 2 and 5, with the far end's transmitter
   strapped to match.
