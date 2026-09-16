# Line transmitter card

One card per direction per end. Identical at both ends — there is no master or
slave strap, because the two directions are independent systems (spec §1).

The counter arithmetic collapses almost completely. Both identities below were
verified against the simulated frame before this document was written.

---

## 1. Block diagram

```
  2.56 MHz ──÷4──→ 640 kHz ──÷2──→ 320 kHz ──÷10──→ 32 kHz
   osc              half-bit        line bit         frame clock
                       │               │                │
                       │               ↓                └──→ to all channel cards
                       │        74HC161 mod-10              (CVSD encode clock)
                       │         frame counter Q3:Q0
                       │               │
                       │        ┌──────┴───────┐
                       │        │              │
                       │   74HC151 mux     Q3 selects
                       │   addr = Q2:Q0    S/T
                       │   A1,C1,A2,C2,        │
                       │   A3,C3,A4,C4         │
                       │        └──────┬───────┘
                       │               │ line bit
                       ↓               ↓
                  ┌─────────────────────────┐
                  │  T = NAND(/H, data)     │   biphase encoder
                  │  JK with J=K=T          │   one gate + one flip-flop
                  └───────────┬─────────────┘
                              ↓
                   75176 driver → series R → slew RC
                              ↓
                   1:1 transformer, centre-tapped
                              ↓
                   protection → line pair
```

---

## 2. Frame generation — the two identities

Frame counter counts 0–9 at the 320 kHz line bit rate. Payload sits at counts
0–7, framing at 8–9.

### 2.1 Mux address needs no arithmetic

`74HC151` address = `Q2:Q0` directly. Inputs in frame order:

| input | I0 | I1 | I2 | I3 | I4 | I5 | I6 | I7 |
|---|---|---|---|---|---|---|---|---|
| signal | A1 | C1 | A2 | C2 | A3 | C3 | A4 | C4 |

Putting the framing bits at counts 8–9 rather than at the start is what makes
this work — the address is the counter's low three bits with no offset.

### 2.2 S and T fall out of the counter

```
line bit = Q3 ? Q0 : mux_out
```

At count 8 (`1000`) Q3=1 and Q0=0, giving S=0. At count 9 (`1001`) Q3=1 and
Q0=1, giving T=1. The framing bits need no source of their own — they are the
counter bit. One 2-to-1 mux (quarter of a 74HC157, or three gates).

### 2.3 Mod-10 clear

```
sync clear = Q3 · Q0
```

`Q3·Q0` is true only at count 9 within 0–9, so one 2-input gate to the 74HC161's
synchronous clear closes the count. Verified exhaustively over 0–9.

**The same two terms do three jobs** — framing bit value, mux select, and
counter modulus. That is the whole frame generator.

---

## 3. Differential Manchester encoder — one gate, one flip-flop

Let `H` be the half-cell phase (the 320 kHz signal): `H=0` during the first half
of a cell, `H=1` during the second.

```
T = H OR NOT(data) = NAND(/H, data)
JK flip-flop wired J = K = T, clocked at 640 kHz
```

| H before edge | data | T | behaviour |
|---|---|---|---|
| 1 | 0 | 1 | entering a new cell — boundary transition, always |
| 1 | 1 | 1 | entering a new cell — boundary transition, always |
| 0 | 0 | 1 | mid-cell — transition, encoding a 0 |
| 0 | 1 | 0 | mid-cell — hold, encoding a 1 |

A JK with J=K toggles when T=1 and holds when T=0, which is exactly a T
flip-flop. Take `/H` from the divider flip-flop's `/Q` output and the gate is a
single NAND.

**Timing note.** `H` and the line flip-flop are both clocked from 640 kHz. Same-
edge synchronous clocking is correct here — the JK samples `H`'s value from
before the edge — but it depends on the divider's clock-to-Q exceeding the JK's
hold time. That is satisfied comfortably by 74HC, whose hold time is typically
zero or negative. Check it against the specific parts rather than assuming; a
hold violation here works on a warm bench and fails at temperature.

The mux output has half a cell (1.56 µs) to settle before the mid-cell edge
samples it, so there is no settling concern on the data path. At the boundary
edge `T=1` regardless of data, so data does not matter there at all.

---

## 4. Oscillator

| | |
|---|---|
| nominal | 2.56 MHz |
| divider | ÷4 → 640 kHz, ÷2 → 320 kHz, ÷10 → 32 kHz |
| fastest node | oscillator and first divider only |

**Accuracy is nearly irrelevant.** The far end's monostable receiver classifies
intervals against an RC with a ±13% window at high noise (spec §5.2), and the
oscillator contributes ~0.01% of that. A ceramic resonator at ±0.5% would work.
Specify a crystal anyway, for unit-to-unit repeatability rather than accuracy.

**Verify 2.56 MHz availability before committing the divider chain.** It must be
`2.56 × 2ⁿ` to reach 640 kHz on binary dividers; 5.12 MHz (÷8) and 10.24 MHz
(÷16) are the clean fallbacks and cost only one more divider stage. Since only
the oscillator runs at that rate, taking 10.24 MHz is not a board-wide penalty.

The 32 kHz frame clock is distributed to all four channel card slots as the
CVSD encode clock. It is the only clock the channel cards receive from this
card.

---

## 5. Output stage

**Driver:** 75176 differential transceiver, driver half. Single package, and
the receiver half is unused here.

**Series matching:** the pair is 100–135 Ω. Two series resistors of roughly
50 Ω limit drive current to ~25 mA from a 5 V differential swing and present a
sensible source impedance. Trim against the actual cable.

**Slew limiting:** series R with shunt C to give roughly 150 ns edges. At
640 kbaud (1.56 µs half-cell) that is well inside the eye while meaningfully
reducing radiated emissions. Do not skip this — a raw 75176 edge into outside
plant is unnecessarily noisy.

**Transformer:** 1:1, **centre-tapped on the line side**.

Running disparity in differential Manchester is bounded at ±1 bit cell =
3.125 µs. For under 5% droop over that interval, `L/R > 62 µs`; at 100 Ω that is
`L > 6.2 mH`. Specify ~10 mH primary inductance and the DC balance takes care of
itself with no coding effort.

**Centre tap:** brought out to an unpopulated footprint for the simplex feed.
DC injected there is common-mode while the signal is differential, and the feed
current splits equally between the two winding halves so the ampere-turns
cancel — the transformer sees no net DC flux. This is why the centre tap must
be specified now even though line power is not populated: retrofitting it means
a new transformer.

**Protection:** gas tube to ground on both conductors, series PTC or fuse, TVS
clamp. **The TVS must clamp above the eventual 48 V feed voltage**, not above
signal level — specify it for the powered case now, so the protection does not
have to be redesigned when the feed is populated.

---

## 6. Package count

| function | part |
|---|---|
| Oscillator | 74HC04 + 2.56 MHz crystal |
| ÷4 and ÷2 dividers | 74HC74 |
| Mod-10 frame counter | 74HC161 |
| Payload mux | 74HC151 |
| S/T select | 74HC157 (¼) |
| Biphase T flip-flop | 74HC73 or 74HC76 |
| Gates (clear term, NAND) | 74HC00 |
| Line driver | 75176 |

**~8 packages**, plus one transformer and the protection network. Everything
except the oscillator and first divider runs at 640 kHz or below.

---

## 7. Bring-up order

1. **Clock chain alone.** Scope 640 / 320 / 32 kHz and confirm the divider
   ratios before anything else is populated.
2. **Frame counter and mux, no encoder.** Watch the raw line bit stream on a
   logic analyser: it should show the 10-bit frame with 0 then 1 at counts 8
   and 9. This is directly comparable to `link.build` output from the simulator.
3. **Biphase encoder.** Check that every cell boundary has a transition and
   that mid-cell transitions track the data. Confirm DC balance on a scope with
   AC coupling — the trace should show no baseline wander.
4. **Into the transformer and a short cable**, then into the receiver.

Steps 1–3 need no receiver and no far end.
