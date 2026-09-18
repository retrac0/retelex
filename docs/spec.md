# Digital voice carrier — system specification

A family of 1-, 3- and 7-channel carriers over twisted pair, at 16, 32 or
64 kbps per channel, built in discrete 74HC logic. Each channel slot takes a
CVSD voice card, a synchronous data card, or nothing. The mode is selected by
two jumper fields and the channel mix by which cards are fitted.

Every number in this document was measured in the simulation in this repository
unless it is marked as analysis. Where a figure comes from a specific
experiment, the script is named. §13 lists what has not been measured.

---

## 1. Architecture

**Two independent one-way systems.** Two pairs, one per direction. Each
direction is timed end to end by the transmitting end's oscillator: the far
end's channel cards are clocked by the clock recovered from that same
oscillator. No data ever crosses between directions, so there is **no rate
mismatch anywhere and slips are structurally impossible**. There is no master/
slave strap and no loop timing.

```
End A                                  End B
[TX card] ──────── pair 1 ──────────> [RX card]
[RX card] <─────── pair 2 ─────────── [TX card]
```

- Identical TX cards at both ends, identical RX cards at both ends.
- Each direction can be brought up and faulted independently.
- Crystal tolerance between ends is irrelevant. A ±100 ppm offset appears only
  as a 0.17-cent pitch shift in recovered audio.
- **The two directions may run different line rates** (§2.2). They must carry
  the same channel count and the same card types slot for slot.

**Per end:** one TX card, one RX card, a backplane with **seven** channel slots,
and one to seven channel cards.

---

## 2. Modes

### 2.1 The nine modes

The frame clock *is* the per-channel clock (§4), so

```
line rate = per-channel rate × frame length        frame length = 2 + 2N
```

| mode | frame | line rate | baud | capacity | CVSD segSNR, mean (worst talker) | noise margin, same cable | reach | monostable |
|---|---|---|---|---|---|---|---|---|
| N=1 @ 16k | 4 | 64 kbps | 128 k | 16 kbps | 10.8 dB (9.0) | **+6.0 dB** | 2.00× ¹ | 11 719 ns |
| N=1 @ 32k | 4 | 128 kbps | 256 k | 32 kbps | 17.4 dB (14.9) | +2.9 dB | 1.41× | 5 859 ns |
| N=1 @ 64k | 4 | 256 kbps | 512 k | 64 kbps | 23.3 dB (19.7) | 0 | 1.00× | 2 930 ns |
| N=3 @ 16k | 8 | 128 kbps | 256 k | 48 kbps | 10.8 dB (9.0) | +2.9 dB | 1.41× | 5 859 ns |
| **N=3 @ 32k** | **8** | **256 kbps** | **512 k** | **96 kbps** | **17.4 dB (14.9)** | **0 (reference)** | **1.00×** | **2 930 ns** |
| N=3 @ 64k | 8 | 512 kbps | 1.024 M | 192 kbps | 23.3 dB (19.7) | −1.9 dB | 0.71× | 1 465 ns |
| N=7 @ 16k | 16 | 256 kbps | 512 k | 112 kbps | 10.8 dB (9.0) | 0 | 1.00× | 2 930 ns |
| N=7 @ 32k | 16 | 512 kbps | 1.024 M | 224 kbps | 17.4 dB (14.9) | −1.9 dB | 0.71× | 1 465 ns |
| N=7 @ 64k | 16 | 1024 kbps | 2.048 M | 448 kbps | 23.3 dB (19.7) | **−8.0 dB** ² | 0.50× | 732 ns |

- **segSNR** is CVSD alone on seven independent talkers, 30 s each (`seven.py`,
  `family.md` §3). The carrier adds nothing measurable: −0.09 to −0.16 dB
  through the full chain at the rates tested (`strap.py` §19, §29). Specify
  against the worst talker.
- **Noise margin, same cable** is the tolerable noise relative to the reference
  mode on one physical cable (1 MHz, 3 dB) with one noise floor (`strap.py` §31).
  With the cable scaled to each mode's symbol rate every mode is identical,
  error-free to sd 0.6 (`strap.py` §30), so no mode is intrinsically worse. The difference
  is entirely how much noise bandwidth a mode collects: +3 dB per halving of
  line rate.
- **Reach** is √f analysis scaled from §12's single unmeasured anchor. The
  ratios are sound; the absolutes are not.
- **Monostable** is 0.75 of a line cell (§6).

¹ The √f law is leaving the skin-effect region at the 64 kbps line rate; 2.00×
is an upper bound.
² At 2.048 Mbaud the 1 MHz cable is below the symbol rate, so this mode pays for
cable bandwidth as well as noise bandwidth — a cliff, not the −4.8 dB trend. It
is the only mode where bandwidth rather than attenuation binds.

**The three axes trade, and any two can be chosen.** Doubling the channels at
constant reach costs about 5.9 dB per channel, and so does doubling the reach at
constant channels. Modes sharing a line rate share the pair, driver, transformer,
slicer, monostable and noise margin, and differ only in how the line is divided.

### 2.2 The two straps

| strap | positions | set by | changes |
|---|---|---|---|
| **Rate** | 1024 / 512 / 256 / 128 / 64 kbps line | line conditions | TX half-bit clock tap and edge-rate capacitor; the far end's RX rate plug (input filter, classifier, dead time, carrier detect) |
| **Channel** | N = 1 / 3 / 7 | local needs | frame counter mask; frame clock stage; S/T select width; payload mux width at N = 7 |

The nine modes are the nine valid settings of fifteen. The other six give a
per-channel rate below 16 kbps or above 64 kbps. They frame and lock correctly,
but the codec is outside its characterised range. They are not hazardous.

- Moving between modes of the same line rate is two jumpers per card.
  Moving between line rates changes the rate jumper on the transmitter and the
  rate plug on the far end's receiver.
- **Channel cards take no strap.** The CVSD card's components set slew, not step
  size (`channel-card.md` §2.3). Leaving its trim at the 32 kbps value costs
  0.35 dB at 16 kbps and 0.28 dB at 64 kbps (`strap.py` §9).
- **Repeaters take no strap.** They never see the frame, and the active path is
  rate-blind; the line transformer is specified for the lowest rate (§12).
- **The rate strap may differ between directions**; each direction is timed by
  its own transmitter. The channel strap must match at the two ends.

### 2.3 What cannot be built

- **N = 2, 4, 5, 6.** `2 + 2N` must be a power of two for the counter identities
  of §4. A 6-bit frame needs a decoded modulus, a sync-clear gate and an offset
  mux address. Fit three slots of an N = 3 build instead.
- **N = 15.** A 32-bit frame: at 32 kbps a 1024 kbps line with a 488 ns
  half-cell, and two 74HC259s per bit type. More capacity wants a different line
  code.
- **Ground start.** It needs two independent static conditions per channel per
  end, and §3.2 forbids a second static bit beside the first.

---

## 3. Frame

### 3.1 Layout

```
count:   0      1      2      3    …   2N−2   2N−1    2N    2N+1
       [ A1 ][ C1 ][ A2 ][ C2 ] … [ AN ][ CN ][  S  ][  T  ]

  An   channel n signalling bit (voice card) or strapped 1 (data card)
  Cn   channel n CVSD bit or data bit
  S    0 in every frame
  T    1, 1, 1, 0 repeating over four frames
```

The only multiframe in the system is T's four-frame pattern, and nothing tracks
its phase — not the channel cards, not the backplane, and not the receiver,
whose check (§7) is phase-free.

### 3.2 The interleaving rule

**A and C bits alternate. No two adjacent payload positions may both be
static.**

At a wrong alignment the receiver checks an adjacent pair of payload bits
instead of S and T, and the alternation guarantees each such pair contains a C
bit. A voice C bit is CVSD, which is random in level. Group the A bits together
instead, and one channel on-hook beside one off-hook holds a false alignment
indefinitely. This was measured on every non-zero start-up skew at N = 3 and on
13 of 16 at N = 7.

### 3.3 Why S is static and T carries a pattern

Framing is always a pattern that payload must not be able to imitate forever.
Six headers were built and measured against every payload class the system
can produce (`framing-review.md`, `t_pattern.py`, `cvsd_tones.py`):

| header | imitated by | outcome |
|---|---|---|
| static `(S,T) = (0,1)` — the previous standard | a **constant** data slot beside the opposite static A bit; any **empty slot** pulled low before an off-hook channel | permanent false locks; a narrow-frame transmitter locks a wide receiver |
| alternating `10` / `01` | **CVSD silence**, which is exactly `1010…` | 7/8 and 15/16 skews false-locked on an idle link, permanently |
| static 4-bit word `1100`, N = 6 | two adjacent data slots | loses a channel at every power of two; mis-strap still locks |
| S = 0, T = `0101` (one flip-flop) | CVSD silence, a comparator offset with no input, any tone at −40 dB — and the empty-slot fill | up to 14/16 false locks at N = 7; slips never detected |
| S = 0, T = `1100` (two flip-flops, no gate) | CVSD near fs/4: at 16 kbps a steady tone of 3 kHz or more on an on-hook channel matches it on 75–99% of frames | no false locks, but a slip during such a tone is never detected |
| **S = 0, T = `1110` over four frames** | only a data bit that reproduces `1110`, placed after a bit that can stay 0 | eliminated by the slot rules of §3.4 |

Why this header survives:

- CVSD silence alternates, and `1110` does not. A window of four silent bits
  has two zeros and fails.
- A constant fails the window outright.
- **A steady tone cannot imitate it.** `1110` has three ones to one zero, and a
  zero-mean tone cannot produce that duty cycle; `1100` is balanced, and a tone
  near a quarter of the frame rate produces it. On every tone and offset tested
  at every rate the `1110` check passed at most 35% of frames.
- **A mis-strap cannot imitate it.** A receiver strapped for a wider frame
  samples a narrower frame's T only every other narrow frame. `1110 1110`
  decimated by two is `1111` or `1010`, and neither has exactly one zero in four.
  The frame-length divisibility that defeats every static header defeats the
  mis-strap here. A period-7 pattern does not have this property: decimated,
  it becomes a shift of itself.

### 3.4 Slot rules

Three rules make every combination of cards safe against false lock, whatever
the data:

1. **Data rides on C only.**
2. **A data card straps its A bit to 1.**
3. **An empty slot presents A = 0 and C = the frame toggle** (`1010`, §8.3).

A wrong alignment can hold S4 only if its first bit can stay 0 on every frame
and its second can follow `1110` indefinitely. Only a data bit can do the
second. Under rule 1 a data bit is preceded by its own card's A bit, which rule
2 makes 1, and followed by the next slot's A bit, which never carries data.

Enumerated over every combination of voice card, data card and empty slot
(`seatmix.py`; the pulled-low, pulled-high and toggle fills each give the same
result):

| N | combinations | unsafe |
|---|---|---|
| 1 | 4 | 0 |
| 3 | 64 | 0 |
| 7 | 16 384 | 0 |

Simulated at N = 7 (`seatmix_sim.py`) against constant 0, constant 1, `1110`,
`0111`, `1010` and random data at both hook states: empty chassis, one data card
in seat 1, one in seat 7, seven data cards, and mixed layouts all measured
**0 false locks**. Negative controls lock as predicted: data cards with A
strapped **low**, 14/16; a single-slot 64 kbps card with data on A, 2/16.

---

## 4. Rates and clocking

### 4.1 Oscillator

**4.096 MHz**, a standard E1-family value. It is the lowest crystal that reaches
all nine modes. N = 7 @ 64k needs a 2.048 MHz half-bit clock, and the half-bit
clock must be at least one divide below the crystal, because a raw Pierce
output is not 50% duty.

Nothing on the board needs a faster clock. The fastest node with a job is the
half-bit clock, and the half-bit clock *is* the baud rate. The receiver has no
clock at all. The previous 8.192 MHz (and 16.384 MHz for 512 kbps) specification
was inherited from a 640 kHz half-bit clock that only 10.24 MHz reached. At
4.096 MHz, clock-chain current is a half and a quarter of those, and a 74HC
speed-margin question at 16 MHz does not arise. Ripple skew is not an argument
for a faster crystal. The skews that matter are below the half-bit clock and
identical at every crystal (`draft-protocols.md` §5.8).

**Accuracy is not critical.** The receiver tolerates ±13% of a cell (§6.2) and
the oscillator contributes ~0.01%. The crystal is specified for unit-to-unit
repeatability.

### 4.2 Chain

```
4.096 MHz ─→ 74HC4040 prescaler  Q1 2.048M │ Q2 1.024M │ Q3 512k │ Q4 256k │ Q5 128k
                                        └──────── RATE jumper ─────────┘
                                                      │
                                               half-bit clock ─→ biphase flip-flop
                                                      │
                                           ÷2 (74HC393 A) ─→ H, line bit clock
                                                      │
                               4-stage frame counter (74HC393 B), bits b0..b3
                                   │                        │
                    CHANNEL jumper: frame clock          mask above the frame
                    = b1 (N=1), b2 (N=3), b3 (N=7)       width → mux address,
                                   │                     S/T select, RX '259
                          2-bit multiframe counter m0, m1
                          T = NAND(m0, m1)  →  1,1,1,0
                          frame toggle = m0 →  empty-slot fill (§8.3)
```

| rate jumper | line rate | half-bit | H | monostable |
|---|---|---|---|---|
| Q1 | 1024 kbps | 2.048 MHz | 1.024 MHz | 732 ns |
| Q2 | 512 kbps | 1.024 MHz | 512 kHz | 1 465 ns |
| **Q3** | **256 kbps** | **512 kHz** | **256 kHz** | **2 930 ns** |
| Q4 | 128 kbps | 256 kHz | 128 kHz | 5 859 ns |
| Q5 | 64 kbps | 128 kHz | 64 kHz | 11 719 ns |

The frame counter is re-clocked by H rather than taken as taps on the prescaler.
The rate jumper moves the half-bit tap, so on a single ripple chain the frame
counter would move with it. Re-clocked, its bits sit on fixed pins at every
strap. That is the whole cost of strappability: one 74HC393.

The per-channel clock is exactly one frame period, with zero jitter and no
buffering anywhere.

### 4.3 The transmitter identities

The framing bits are at the end of the frame, so

```
payload mux address  = frame counter bits, masked, no offset
S/T select           = AND of every counter bit above b0     (3-input AND, unused inputs strapped high)
framing data         = b0 AND T                              → S = 0 at count 2N, T at count 2N+1
line bit             = select ? framing data : mux output
```

A gate-level model of the transmitter reproduces the frame bit for bit at
N = 1, 3 and 7 (`strap.py` §3, verified against the earlier `b0`-only framing
data; the T term adds one AND gate). `T = NAND(m0, m1)` from a 2-bit ripple
counter on the frame clock was checked against `1,1,1,0` over 64 frames.

---

## 5. Line code — differential Manchester

- Transition at **every** cell boundary. This is the clock.
- An additional transition at mid-cell **iff** the data bit is 0.

| property | consequence |
|---|---|
| Two-level, always ±V, never zero | Full amplitude every symbol |
| Decision is same-vs-different half-cells | **No threshold to set and no AGC.** Cable loss and driver amplitude are irrelevant |
| Polarity-blind | Tip and ring may be swapped. Verified bit-identical |
| DC-free, disparity bounded at ±1 cell | Transformer coupling works with no coding effort |
| Guaranteed transition every bit | Clock recovery never starves regardless of data |

AMI was evaluated and rejected. It halves the symbol rate, but needs a
three-level driver and a slicer threshold that tracks received amplitude, which
was measured to fail at 0.6× gain error. Keep it on file for a span limited by
bandwidth rather than attenuation.

---

## 6. Receiver

The receiver card is specified in `line-receiver.md`. This section records the
measured properties it rests on.

### 6.1 Interval classifier

No PLL, no oversampling, no clock on the receive timing path. Intervals between
transitions are either half a cell or a full cell. A retriggerable timer set to
0.75 cell classifies each gap, a state flip-flop pairs the half-cell gaps of a 0
bit, and transitions within 0.2 cell of the last accepted one are ignored.
**The state self-heals**: any full-cell gap forces it back to the boundary state.

Ahead of the classifier sit a low-pass at the symbol rate and a comparator with
hysteresis. Measured tolerances, `rx_review.py`:

| parameter | specify | usable range |
|---|---|---|
| Input filter | two RC sections at the symbol rate | 0.75–1.5× the symbol rate; **8× loses all margin**, so it moves with the rate |
| Comparator hysteresis | ≤ 10% of received amplitude (≈ 1 V at a 50 mV comparator) | 20% on a single span; 10% on repeatered routes (`repeater.md` §2.4) |
| Dead time | 0.2 cell, non-retriggerable | 0.05–0.30 cell to sd 0.5 |
| Classifier threshold | 0.75 cell | ±13% at the sd 0.4 design limit (§6.2) |
| Carrier-detect timeout | 2 cells | never trips on signal, even at sd 0.9 |

The filter, the two timers and the carrier timeout move together on a per-rate
plug (`line-receiver.md` §8). The receiver chain with the §7 framer is bit-exact,
with no loss of frame, clean and at sd 0.4, at 64, 256 and 1024 kbps.

### 6.2 Timing tolerance

| condition | usable threshold window | margin about 0.75 |
|---|---|---|
| clean | 0.55 – 0.95 | ±27% |
| moderate (sd 0.3) | 0.60 – 0.90 | ±20% |
| **design limit (sd 0.4)** | 0.60 – 0.85 | **±13%** |
| edge of lock (sd 0.5) | 0.65 – 0.80 | ±7% |

Measured at 256 kbps. The relative window is unchanged at 128, 512 and
1024 kbps (N = 1 @ 32k: 0.60–0.90; N = 3 @ 64k, N = 7 @ 32k, N = 7 @ 64k:
0.60–0.85). **Specify against ±13%.** A 1% resistor and 2% C0G capacitor give
±3%.

The absolute window at 1024 kbps is ±98 ns, where layout stray capacitance and
ripple skew stop being negligible; scope it at bring-up in that mode.

### 6.3 Versus alternatives

| receiver | board clock | performance |
|---|---|---|
| oversampling DPLL | 10.24 MHz | reference |
| analog PLL (4046) | 1.28 MHz | equal to reference |
| **monostable** | **none** | within 3× of reference at the noise edge, identical elsewhere |

---

## 7. Framer

One check, used for both acquisition and tracking, and one counter. The receiver
keeps no multiframe phase and loads nothing at lock. The reference model is
`s4_simple.framer_single`, validated by `python3 s4_simple.py spec`.

### 7.1 The check

```
good frame  :=  S == 0
                AND ( fewer than three frames seen since the last slip
                      OR  the last four T at this alignment contain exactly one 0 )
```

**Exactly one zero, not at most one.** A wrong alignment whose T position is a
constant 1 has no zeros at all. An empty slot pulled low before a data card
idling at all ones gave **3/8 false locks** with an "at most one" check, and 0
with "exactly one" at N = 1, 3 and 7.

**The first three frames after a slip are scored on S alone.** Until four T
samples exist there is no window to test. The acquisition counter (§7.2) already
counts frames since the slip, so the T test is enabled when that count reaches
3, and no extra state is needed.

The check is phase-free: `1110`, `1101`, `1011` and `0111` all pass. It fails on
every case a wrong alignment can present:

| T position at a wrong alignment | check fails |
|---|---|
| static bit, any value | every frame |
| `1010` — CVSD silence, the empty-slot fill | every frame |
| random CVSD | ~75% of frames |
| steady tone or comparator offset, any rate (`cvsd_tones.py`) | ≥ 65% of frames |

### 7.2 Acquisition

```
on a bad frame :  slip ONE line bit, clear the T history and the count
lock           :  32 consecutive good frames
```

**32, not 64.** A wrong alignment is gated at no better than 50% per frame, so a
transient false lock has probability 2^-32 per attempt, and §7.3 clears it
within a few tens of frames regardless. Permanent false locks are not affected
by the count; §3.4 removes those.

| N | acquisition, clean | @ 1e-2 BER | @ 3e-2 BER | false locks, speech / idle / empty / data mixes |
|---|---|---|---|---|
| 1 | 31–36 frames | 79 frames | 171 frames | 0 / 0 / 0 / 0 of 4 |
| 3 | 31–40 frames | 52 frames | 72 frames | 0 / 0 / 0 / 0 of 8 |
| 7 | 31–49 frames | 60 frames | 122 frames | 0 / 0 / 0 / 0 of 16 |

(First lock, mean of three error seeds.) In time, 32 frames is 2.0 ms at a
16 kHz frame rate, 1.0 ms at 32 kHz and 0.5 ms at 64 kHz. The previous
64-frame count took 33 ms to acquire at 3e-2 BER (N = 3 @ 32k), against 2.3 ms
here.

### 7.3 Loss of frame — one counter

```
tracking :  the §7.1 check, every frame
counter  :  +1 on a bad frame, −1 on a good frame, floor 0; trip at 16
on trip  :  not locked; slip one line bit; acquire again
```

**Why `+1/−1` trip 16.** The counter trips when more than half the frames fail.

- At the true alignment one line error on T spoils the four windows that
  contain it. Together with errors on S, the bad-frame rate is about 5 × BER:
  15% at 3e-2, far below half.
- At a wrong alignment the check fails on at least 65% of frames in every case
  in the §7.1 table, so the counter always climbs.

A `+2/−1` counter trips at a third, which four-frame error spreading reaches:
52–53 false reframes at 1e-2 BER, measured.

| receiver | frames misaligned after a slip: idle voice / empty + data / speech | 16 kbps, steady tone on an on-hook channel | false reframes @ 1e-3 / 1e-2 / 3e-2 / 5e-2 |
|---|---|---|---|
| predictive T check, +2/−1 trip 12 | 21 / **never** / 23 | — | 0 / 0 / 0 / 0–1 |
| window check, +2/−1 trip 12 ¹ | — | — | 0–2 / **52–53** / 42–63 |
| predictive + window counters (previous revision) | 18 / 16 / 18 | 22–35 | 0 / 0 / 0–1 / 8–9 |
| **window check, +1/−1 trip 16 — this spec** | **18 / 17 / 19** | **29–44** | **0 / 0 / 0–1 / 8** |

(N = 3 and N = 7, worst over every slip size. Tones 1004, 2600, 3000, 3400 and
3800 Hz. ¹ Measured with a 64-frame acquisition count.)

The predictive check on its own was blind to a wrong alignment whose T position
is static or `1010`: its predicted `1110` still matched three frames in four.
That is why the previous revision carried two counters and a phase counter. The
window check fails that case on every frame, so neither is needed.

**End to end** (`s4_simple.py spec`), at N = 1, 3 and 7:

- 0 false locks across speech, idle voice on- and off-hook, the empty chassis,
  data cards with constant, `1110`, `1100`, `1010` and random data, and mixed
  voice / empty / data layouts.
- 0 loss-of-frame events and 0 frames emitted off the true phase on clean lines.
- Negative controls lock as predicted: data cards with A strapped low, 2/4, 6/8
  and 14/16.
- A narrower-frame transmitter mutes a wider receiver on speech, idle, and data
  cards.
- The receiver never locks on a noise-only line.

### 7.4 Why loss of frame is not "N consecutive bad frames"

Acquisition and loss of frame have opposite statistical requirements. A
misaligned frame fails only part of the time. That is ideal for acquisition,
which needs a run of *good* frames, and useless for a rule that needs a run of
*bad* frames, which a partly failing misalignment rarely produces. Measured on
the previous header, with a "16 consecutive bad" rule, a 6-bit slip never
recovered and a 2-bit slip left channels crossed for 558 ms. The up/down counter
detected every slip size within 0.84 ms. The mechanism does not depend on the
header.

### 7.5 Hardware form

| function | parts |
|---|---|
| T history, four bits | 74HC175 or 74HC164 |
| "Exactly one zero in four" | 74HC151 as a 4-input function: three T bits on the address, the fourth and its complement on the data inputs |
| S = 0, T-check enable, good-frame gate | gates |
| Acquisition count to 32; T-check enable at count ≥ 3 | 74HC393, both halves cascaded; enable = `Q0·Q1 + Q2 + Q3 + Q4 + Q5` |
| Loss-of-frame counter, +1/−1, floor 0, trip 16 | 74HC193: up on bad, down on good, borrow inhibits below 0, carry out = trip |
| Lock state | ½ 74HC74 |
| Frame counter and '259 address mask | shared with the RX demux |

**About five packages**, against eight for the two-counter framer of the previous
revision. The check must be exactly §7.1: "at most one zero", or testing T
before three frames have passed, is a different receiver.

---

## 8. Channel cards and slots

### 8.1 CVSD voice card

E&M four-wire, semi-analog CVSD, `channel-card.md`. Runs at 16, 32 or 64 kbps
with no change: its components set slew, and the one trim is within 0.35 dB of
optimum across the range. A = E&M signalling (§9), C = CVSD.

### 8.2 Data card

Synchronous, bit-transparent, `data-card.md`. One bit per frame on C, **A
strapped to 1**, so a 16, 32 or 64 kbps pipe. The carrier supplies the transmit
and receive clocks. The pipe is not octet-aligned and is **not scrambled** —
§3.4 makes any data content safe, including all zeros, all ones and periodic
patterns. Two adjacent data cards bond into one pipe at twice the rate (C*j*
even bits, C*j*+1 odd bits), with no alignment state.

A single card carrying data on both A and C is **not** permitted (§3.4
negative control).

### 8.3 Empty slot

**A = 0 (on-hook), C = the frame toggle** (`m0`, alternating `1010`),
fed to each slot's mux inputs through 4.7 kΩ so that a fitted card overrides it.
Buffer the toggle bus, which carries seven resistive loads.

Framing is safe with a static fill too (§3.4 enumerates both). The reason for the
toggle is what the far end hears when it has a voice card in a slot that is
empty at this end, as it will whenever cards are added one end at a time:

| empty-slot C bit | far-end CVSD output, re normal speech |
|---|---|
| pulled low or high (constant) | **+20 dB rms, +47.7 dB peak** — the integrator slams rail to rail |
| **frame toggle `1010`** | **−59 dB rms**, −21 dB peak — CVSD idle, silence |

A far-end data card facing an empty slot receives `1010`, which is harmless
idle.

### 8.4 Card types must match slot for slot

**Slot *j* must hold the same card type at both ends, or be empty at one end.**
A voice card facing a data card decodes data as CVSD. That is loud noise, and
squelch cannot mute it, because the link is correctly locked. The output clamp
(§10.2) bounds the level. Label every slot at both ends.

### 8.5 Backplane

Seven slots, each:

| signal | direction |
|---|---|
| TX frame clock | from TX card |
| C bit out, A bit out | to TX card mux (with the §8.3 fill resistors) |
| RX frame clock | from RX card |
| C bit in, A bit in | from RX card demux |
| Mute / not-locked | from RX card |

Plus the frame-toggle bus and the **channel strap**, distributed to the TX and RX
cards from one jumper field per end, so the two cards at an end cannot disagree
about N.

The **rate** is not shared. A receiver must match the *far* end's transmitter,
not its own end's, and the two directions may run different rates (§2.2). So the
transmitter's rate jumper and the receiver's rate plug (`line-receiver.md` §8)
are set per direction.

---

## 9. Signalling

**One bit per channel per direction** on voice cards; A = 1 means active. E&M is
a two-lead interface with one lead driven and one sensed, so one bit each way
carries seizure, answer, disconnect, dial pulses and wink or delay start, all of
which are encoded in timing. Loop start fits; ground start does not (§2.3).

Received A bit → RC, τ = 2 ms → 74HC14 Schmitt: one resistor, one capacitor and
one gate per channel, serving as both error filter and debounce. Measured with
channel 1 idle:

| line BER | erroneous A bits | longest raw run | **spurious assertions** |
|---|---|---|---|
| 1e-3 | 236 | 0.031 ms | **0** |
| 1e-2 | 2581 | 0.062 ms | **0** |
| 3e-2 | 7568 | 0.125 ms | **0** |
| 6e-2 | 14650 | 0.125 ms | **0** |

Dial pulses (10 pps, 40/60 ms): **78 of 78 recovered at every BER to 3e-2**,
0.16% ratio error. Measured at 32 kbps. τ = 2 ms is independent of mode. At a
16 kHz frame rate the same error run is twice as long in time, about 0.25 ms at
6e-2 — still seven times short of the ~1.7 ms needed to assert (analysis).

A data card's A bit is 1 and the far-end data card ignores it.

---

## 10. Failure behaviour

| event | response |
|---|---|
| Not locked | Mute all channel outputs; force received A bits to idle (74HC259 clear); data cards present RXD = 1 |
| Loss of signal / no transitions | Squelch — **required**, §10.1 |
| Mis-strapped channel count, far end narrower | **Does not lock** (§10.3) |
| Empty slot at one end | Far end hears silence (§8.3) |
| Card type mismatch | Loud, locked, not squelched; clamp bounds it (§8.4) |

### 10.1 Why squelch is mandatory

Output level of a CVSD card, relative to normal speech, when the framer is
bypassed (`squelch.py`):

| line condition | framer locks | rms | **peak** |
|---|---|---|---|
| truly dead | no | silent | silent |
| **noise only, sd 0.05** | no | **+24.1 dB** | **+47.7 dB** |
| noise only, sd 1.0 | no | +20.8 dB | +41.0 dB |
| signal + noise sd 0.9 | yes | +4.2 dB | +21.6 dB |

A dead pair with a little induced noise makes sparse transitions. The
monostable then emits long runs of 1s, which the syllabic compander reads as a
loud signal.

### 10.2 Implementation

- **Mute on the not-locked *level*, not the loss-of-frame edge.** On a cable
  break the framer searches indefinitely and would emit hash after a
  momentary edge-triggered mute. The §7 framer **never locks on a noise-only
  line**: 0/8 skews at sd 0.05, 0.2 and 1.0 (`s4_simple.py spec`).
- **Backstop: a carrier-detect monostable** on transition rate, independent of
  the framer.
- **Clamp the audio output** with two diodes. It bounds the two locked failures
  squelch cannot catch: a degraded but locked link, and a card type mismatch.

### 10.3 Mis-strap

Every frame length divides every longer one. Under the previous static header a
transmitter strapped for fewer channels than the receiver locked the receiver
permanently, with slots pinned at the rail (+47.7 dB peak). Under S4 the
receiver never locks. That was measured for N = 1 into N = 3, N = 1 into N = 7
and N = 3 into N = 7, on speech, on an idle link, and with data cards sending
`1110` (`framing_review.py`, `seatmix_sim.py`, `s4_simple.py spec`). A wider transmitter into a
narrower receiver never locked under either header. The shared channel-strap
field per end (§8.5) prevents a disagreement within an end.

---

## 11. Performance

### 11.1 Audio

CVSD, seven independent talkers, 30 s each:

| rate | mean segSNR | worst talker |
|---|---|---|
| 16 kbps | 10.80 dB | 9.02 dB |
| 32 kbps | 17.40 dB | 14.91 dB |
| 64 kbps | 23.28 dB | 19.69 dB |

About 6 dB per doubling, with no knee. Per-talker spread tracks crest factor and
exceeds anything the carrier contributes.

Degradation with line errors, N = 3 @ 32k:

| line BER | segSNR | loss-of-frame events |
|---|---|---|
| 0 | 18.8 dB | 0 |
| 1e-4 | 18.3 dB | 0 |
| 1e-3 | 13.9 dB | 0 |
| 1e-2 | 4.5 dB | 0 |

At a fixed line rate a lower per-channel rate degrades more gently but never
better in absolute terms. At 1e-2: 5.93 dB at 64k, 4.63 at 32k, 4.01 at 16k
(`strap.py` §17). **Design target: 1e-4 for full quality, 1e-3 as the usable
floor.**

End to end at N = 3 @ 32k (`validate.py`): **19.06 dB** through the full
chain, channel isolation diagonal ≥ 0.981, off-diagonal ≤ 0.029.

### 11.2 Data

Bit-exact through the framer at every start-up skew, including bonded pairs.
Line errors pass through one for one; the carrier adds no error multiplication.

---

## 12. Reach, line interface and power

**Reach anchor: order 1.7 km on 24 AWG at 256 kbps. Measure it before relying on
it.** Every reach figure in this document is a ratio from that anchor. The
bandwidth sweep says the limit at 256 kbps is attenuation, not dispersion, which
is the good case. Differential Manchester puts its fundamental between half the
line rate (all ones) and the line rate (all zeros), so the ratios hold whichever
is taken.

**Line transformer: 33 mH minimum**, centre-tapped on the line side. Running
disparity is bounded at ±1 cell; under 5% droop needs `L/R > 20 × cell`, which
at the 64 kbps line rate (15.6 µs cell) and 100 Ω is 31 mH. This is arithmetic,
not simulation. The same part serves every rate and the repeater.

**Edge rate by rate strap:** 150 ns at 512 kbps and below (15.4% of the half-cell
at 512 kbps), **75 ns at 1024 kbps**, where 150 ns would be 31%. It is one
capacitor switched by the rate jumper.

**Near-end crosstalk** is budgeted at 20 dB rejection at 512 kHz
(`repeater.md` §3.3). NEXT loss falls about 4.5 dB per octave, so 1.024 Mbaud
needs about 24.5 dB and 2.048 Mbaud about 29 dB, plus span loss. That is
textbook scaling and has not been simulated. Keep the two directions in
separate binder groups, and measure NEXT before using the 1024 kbps modes.

**Beyond one span, repeat** (`repeater.md`). One board slices and re-drives both
directions and has no oscillator, framer or strap. Deterministic distortion does
not accumulate; jitter grows as `spans^0.41`. A repeatered route needs a tighter
per-span noise budget: three spans at sd 0.4, nine at sd 0.25.

**Line power is provisioned, not populated**: centre-tapped transformers with
the feed path and protection laid out, with the TVS clamping above the eventual
feed voltage. Ringing generation, not the transmission terminal, will strain the
budget; it is deferred with the FXS card.

---

## 13. Validation status

| claim | measured by | status |
|---|---|---|
| Framing, S4 header, all nine modes' frame widths | `framing_review.py` | measured, bit level |
| Slot rules, every card combination | `seatmix.py` (enumeration), `seatmix_sim.py` | measured |
| **Framer as specified in §7**: false locks, slip detection, reframes, tones, mis-strap, noise-only line | `s4_simple.py spec` | measured |
| Framer policies considered and rejected | `s4_lof.py`, `s4_simple.py` | measured |
| Receiver front end: filter corner and shape, hysteresis, dead time, carrier detect; chain end to end at three line rates | `rx_review.py` | measured |
| Receiver circuit: timer IC tolerance, flip-flop timing, rate plug, relock transient | `line-receiver.md` | design, not built |
| T patterns `0101`, `1100`, `1110`; CVSD tones and offsets | `t_pattern.py`, `cvsd_tones.py` | measured |
| PHY: noise margin, monostable window, bandwidth, all line rates | `strap.py` §10–12, §19, §29–31 | measured |
| Audio per rate, seven talkers | `seven.py` | measured |
| End-to-end chain | `validate.py` | measured **on the previous static header** at N = 3 @ 32k, 8.192 MHz; framing-independent results carry over, but `validate.py` should be moved to S4 |
| Mis-strap under S4 | `framing_review.py`, `seatmix_sim.py` | measured |
| Data card circuit | — | not designed |
| Transformer droop, edge rates, NEXT at ≥ 1 Mbaud | — | analysis only |
| Reach, any rate | — | unmeasured anchor; bench measurement required |

Superseded by this document where they conflict: `seven-channel.md` (crystal and
header), `family.md` (crystal swaps as the rate mechanism), `draft-protocols.md`
and `framing-review.md`, which are the working records that produced it.
