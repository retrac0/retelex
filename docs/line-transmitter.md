# Line transmitter card

One card per direction per end. Identical at both ends — there is no master or
slave strap, because the two directions are independent systems (spec §1).

Covers all nine modes of spec §2 with two jumper fields. The frame generator
identities below were verified against the simulated frame before this document
was written; the S4 framing term and the T generator are checked in spec §4.3.

---

## 1. Block diagram

```
 4.096 MHz ─→ 74HC4040 prescaler ─ Q1..Q5 ─→ RATE jumper ─→ HB, half-bit clock
                                                               │
                         74HC393 half A: ÷2 ─→ H, line bit clock (half-cell phase)
                                                               │
                         74HC393 half B: frame counter b0..b3, clocked by H
                               │                        │
                 CHANNEL jumper: FC = b1 / b2 / b3    mask jumpers: b2, b3 → 0
                 (N = 1 / 3 / 7)                      above the frame width
                               │                        │
                 74HC74: m0, m1 counting FC           74HC151 (×2 at N = 7)
                 T = NAND(m0, m1)   toggle = m0       addr = b0..b3 masked
                               │                      inputs A1,C1 … A7,C7
                               │                        │
                 select = b1 · (b2 or strap) · (b3 or strap)   (74HC11)
                 framing data = b0 · T                          (74HC11)
                 line bit = select ? framing data : mux out     (74HC157)
                                         │
                            biphase encoder: EN = NAND(/H, line bit)
                            JK flip-flop, J = K = EN, clocked by HB
                                         │
                75176 driver → series R → slew RC (rate-strapped C)
                                         │
                1:1 transformer, centre-tapped, ≥ 33 mH → protection → pair
```

FC (frame clock) goes to every channel slot as the transmit clock. The frame
toggle m0 feeds the empty-slot fill (§4).

---

## 2. Clock chain

| rate jumper | line rate | HB (half-bit) | H (line bit) |
|---|---|---|---|
| Q1 | 1024 kbps | 2.048 MHz | 1.024 MHz |
| Q2 | 512 kbps | 1.024 MHz | 512 kHz |
| **Q3** | **256 kbps** | **512 kHz** | **256 kHz** |
| Q4 | 128 kbps | 256 kHz | 128 kHz |
| Q5 | 64 kbps | 128 kHz | 64 kHz |

| channel jumper | frame | FC = per-channel clock, at 256 kbps |
|---|---|---|
| b1 | 4 bits, N = 1 | 64 kHz |
| **b2** | **8 bits, N = 3** | **32 kHz** |
| b3 | 16 bits, N = 7 | 16 kHz |

**Why two counters, not one.** A fixed-mode build can take everything as taps on
one 74HC4040: half-bit, line bit, frame counter and frame clock. But the rate
jumper moves the half-bit tap, and on one ripple chain the frame counter would
move with it, so the mux address would need a 4 × 5 matrix of jumpers. Clocking
the frame counter from H puts its bits on fixed pins at every strap. That costs
one 74HC393, and it is the whole price of the rate strap.

**Why 4.096 MHz.** It is the lowest crystal that reaches the 2.048 MHz half-bit
clock of the fastest mode, with the one divide a Pierce oscillator's duty cycle
needs. Nothing on the card needs a faster clock (spec §4.1).

**Accuracy is nearly irrelevant.** The far-end receiver tolerates ±13% of a cell
and the oscillator contributes ~0.01%. Specify a crystal for repeatability.

**Ripple.** The skews that matter are within the frame counter, which is what
the select term and the mux address decode across. They are two or three stages
of a 74HC393, some tens of nanoseconds, against a settling budget of half a cell
before the mid-cell sampling edge. That is 488 ns at 1024 kbps and 7.8 µs at
64 kbps. Scope it at bring-up in the 1024 kbps modes.

---

## 3. Frame generation

Frame counter b0..b3 counts 0 … 2N+1 at the line bit rate. Payload sits at
counts 0 … 2N−1, framing at 2N and 2N+1.

### 3.1 Mux address needs no arithmetic

The 74HC151 address is the counter bits directly, with the bits above the frame
width forced to 0 by the mask jumpers. Inputs are in frame order: A1, C1, A2,
C2, …. At N = 7 two '151s hold counts 0–7 and 8–15, selected by b3 through a
spare 74HC157 section. Unused inputs are never selected at framing counts,
because the override below wins there.

Framing bits at the end of the frame are what make the offset zero. The
requirement is only that S and T be adjacent (spec §3.2). Framing-first works
equally, with a NOR select instead of an AND.

### 3.2 S and T fall out of the counters

```
select        = AND of every counter bit above b0   → true at counts 2N and 2N+1
framing data  = b0 · T                               → 0 at 2N (S), T at 2N+1
T             = NAND(m0, m1)                         → 1, 1, 1, 0 over four frames
line bit      = select ? framing data : mux out
```

m0 and m1 are a 2-bit ripple counter on FC, so they change at the frame
boundary and are stable through the frame. They have long settled by the time
the framing counts arrive. `T = NAND(m0, m1)` was checked against `1,1,1,0` over
64 frames.

The select term is one 3-input AND with the unused inputs strapped high:

| N | select |
|---|---|
| 1 | b1 (b2, b3 inputs strapped high) |
| 3 | b1 · b2 (b3 input strapped high) |
| 7 | b1 · b2 · b3 |

### 3.3 No modulus to close

The frame counter wraps naturally at every power-of-two frame, and the
multiframe counter at four. There is no sync-clear decode anywhere on the card.

---

## 4. Empty-slot fill

Each slot's two mux inputs have default resistors that a fitted card overrides:

| input | fill | resistor |
|---|---|---|
| A | 0 (on-hook) | 4.7 kΩ to ground |
| C | frame toggle m0 (`1010`) | 4.7 kΩ to the toggle bus |

**Buffer the toggle bus.** Seven 4.7 kΩ loads in parallel is 670 Ω; use a spare
74HC04 or a 74HC244 section rather than m0 directly.

**Settling:** 4.7 kΩ into ~10 pF is ~50 ns. The earliest a C input is sampled
after the toggle changes is one line bit into the frame — 977 ns at 1024 kbps.
A card output driving against 4.7 kΩ draws about 1 mA.

Why the toggle and not a plain pull-down: a far-end voice card facing an empty
slot hears a constant C bit as a rail-to-rail slam, +47.7 dB peak re speech. A
`1010` C bit is CVSD idle, −59 dB. Framing is safe either way (spec §8.3).

---

## 5. Differential Manchester encoder — one gate, one flip-flop

Let `H` be the half-cell phase: 0 in the first half of a line cell, 1 in the
second. The toggle enable is called EN here, to keep it apart from the framing
bit T.

```
EN = H OR NOT(line bit) = NAND(/H, line bit)
JK flip-flop wired J = K = EN, clocked by HB
```

| H before edge | line bit | EN | behaviour |
|---|---|---|---|
| 1 | 0 | 1 | entering a new cell — boundary transition, always |
| 1 | 1 | 1 | entering a new cell — boundary transition, always |
| 0 | 0 | 1 | mid-cell — transition, encoding a 0 |
| 0 | 1 | 0 | mid-cell — hold, encoding a 1 |

**Timing note.** H and the output flip-flop are both clocked from HB. Same-edge
synchronous clocking is correct, since the JK samples H's value from before the
edge, but it depends on the divider's clock-to-Q exceeding the JK's hold time.
74HC satisfies that comfortably; check it against the specific parts. A hold
violation works on a warm bench and fails at temperature.

---

## 6. Output stage

**Driver:** 75176 differential transceiver, driver half.

**Series matching:** two ~50 Ω series resistors into the 100–135 Ω pair, ~25 mA
from a 5 V swing. Trim against the actual cable.

**Slew limiting, switched by the rate jumper:**

| line rate | edge | fraction of half-cell |
|---|---|---|
| 64 – 512 kbps | 150 ns | 1.9% – 15.4% |
| 1024 kbps | **75 ns** | 15.4% (150 ns would be 31%) |

One series R with a shunt C, and a second C switched in for the lower rates. Do
not skip slew limiting: a raw 75176 edge into outside plant is unnecessarily
noisy.

**Transformer:** 1:1, **centre-tapped on the line side, ≥ 33 mH.** Running
disparity is bounded at ±1 cell, and under 5% droop needs `L/R > 20 × cell`.
The longest cell is 15.6 µs at the 64 kbps line rate, which gives 31 mH at
100 Ω (arithmetic, not simulated). The 10 mH of the previous specification only
covers 256 kbps and above.

**Centre tap:** brought out to an unpopulated footprint for the simplex feed.
DC injected there is common-mode, and the feed current splits so the
ampere-turns cancel. Specify the centre tap now: retrofitting it means a new
transformer.

**Protection:** gas tube to ground on both conductors, series PTC or fuse, TVS.
**The TVS must clamp above the eventual 48 V feed voltage**, not above signal
level.

---

## 7. Package count

| function | part |
|---|---|
| Oscillator, toggle-bus buffer | 74HC04 + 4.096 MHz crystal |
| Prescaler | 74HC4040 |
| H divider and frame counter | 74HC393 |
| Multiframe counter m0, m1 | 74HC74 |
| Payload mux | 74HC151 (a second at N = 7) |
| Framing override, N = 7 mux select | 74HC157 |
| S/T select, framing data | 74HC11 |
| T gate, biphase EN gate | 74HC00 |
| Biphase flip-flop | 74HC73 or 74HC76 |
| Line driver | 75176 |

**~10 packages** (11 with the second '151), plus the transformer, protection
network and jumper fields. A single-mode build can drop the 74HC393 and take
taps on the 4040, for ~9.

---

## 8. Bring-up order

1. **Clock chain alone.** Scope 4.096 MHz, HB and H at the chosen rate jumper,
   and FC at the chosen channel jumper.
2. **Frame counter, multiframe counter and mux, no encoder.** On a logic
   analyser the raw line bit stream should show S = 0 at count 2N in every
   frame, and T at count 2N+1 running `1,1,1,0` across frames. Fit one card
   and confirm its A and C land in their slot; confirm an empty slot shows
   A = 0 and C alternating frame to frame. Compare against `framing_review.gbuild`.
3. **Biphase encoder.** Every cell boundary has a transition, and mid-cell
   transitions track the data. Confirm DC balance on an AC-coupled scope.
4. **Into the transformer and a short cable**, then into the receiver. Repeat
   step 3 at the 64 kbps and 1024 kbps rate settings: droop at the first, edge
   rate at the second.

Steps 1–3 need no receiver and no far end.
