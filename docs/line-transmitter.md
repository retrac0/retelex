# Line transmitter card

One card per direction per end. Identical at both ends — there is no master or
slave strap, because the two directions are independent systems (spec §1).

The counter arithmetic collapses almost completely. Both identities below were
verified against the simulated frame before this document was written.

---

## 1. Block diagram

```
  8.192 MHz ──────── ONE 74HC4040, taps only ─────────────────┐
     Q4 = 512 kHz half-bit   Q5 = 256 kHz line bit (H)        │
     Q6:Q8 = mod-8 frame counter    Q8 = 32 kHz frame clock ──┴→ channel cards
                       │               │                          (CVSD encode clock)
                       │               │
                       │        frame counter Q8:Q6
                       │               │
                       │        ┌──────┴───────┐
                       │        │              │
                       │   74HC151 mux     Q8·Q7 selects
                       │   addr = Q8:Q6    S/T
                       │   A1,C1,A2,C2,        │
                       │   A3,C3 (I6,I7 n/c)   │
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

Frame counter counts 0–7 at the 256 kHz line bit rate. Payload sits at counts
0–5, framing at 6–7.

**There is no frame counter package.** Because crystal-to-frame is ÷256 = 2⁸,
the counter is simply three taps on the same 74HC4040 that divides the crystal.
It free-runs; there is no modulus to decode and no sync-clear gate.

### 2.1 Mux address needs no arithmetic

`74HC151` address = the frame counter taps `Q8:Q6` directly. Inputs in frame
order:

| input | I0 | I1 | I2 | I3 | I4 | I5 | I6 | I7 |
|---|---|---|---|---|---|---|---|---|
| signal | A1 | C1 | A2 | C2 | A3 | C3 | — | — |

Putting the framing bits at the end rather than the start is what makes this
work — the address is the counter bits with no offset. I6 and I7 are never
selected for payload (counts 6 and 7 are the framing positions, where the 2-to-1
below overrides), so tie them off.

### 2.2 S and T fall out of the counter

```
line bit = (Q8·Q7) ? Q6 : mux_out
```

At count 6 (`110`) the select is true and Q6=0, giving S=0. At count 7 (`111`)
Q6=1, giving T=1. The framing bits need no source of their own — they are the
counter bit. One 2-to-1 mux (quarter of a 74HC157) and one AND for the select.

### 2.3 No modulus to close

Mod-8 wraps naturally on three binary stages, so unlike a 10-bit frame there is
**no sync-clear decode at all**. The `Q8·Q7` select term is reused by the
receiver's framing check, so it is generated once and used twice.

That is the whole frame generator: three taps, one mux, one AND, one 2-to-1.

---

## 3. Differential Manchester encoder — one gate, one flip-flop

Let `H` be the half-cell phase (the 320 kHz signal): `H=0` during the first half
of a cell, `H=1` during the second.

```
T = H OR NOT(data) = NAND(/H, data)
JK flip-flop wired J = K = T, clocked at 512 kHz
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

**Timing note.** `H` and the line flip-flop are both clocked from 512 kHz. Same-
edge synchronous clocking is correct here — the JK samples `H`'s value from
before the edge — but it depends on the divider's clock-to-Q exceeding the JK's
hold time. That is satisfied comfortably by 74HC, whose hold time is typically
zero or negative. Check it against the specific parts rather than assuming; a
hold violation here works on a warm bench and fails at temperature.

The mux output has half a cell (1.95 µs) to settle before the mid-cell edge
samples it, so there is no settling concern on the data path. At the boundary
edge `T=1` regardless of data, so data does not matter there at all.

---

## 4. Oscillator

| | |
|---|---|
| nominal | **8.192 MHz** |
| divider | ÷16 → 512 kHz, ÷2 → 256 kHz, ÷8 → 32 kHz — **÷256 total, all binary** |
| fastest node | oscillator and the first divider stages; every tap ≤ 512 kHz |

**Accuracy is nearly irrelevant.** The far end's monostable receiver classifies
intervals against an RC with a ±13% window at high noise (spec §5.2), and the
oscillator contributes ~0.01% of that. A ceramic resonator at ±0.5% would work.
Specify a crystal anyway, for unit-to-unit repeatability rather than accuracy.

**The whole chain is one 74HC4040.** Crystal-to-frame is ÷256 = 2⁸, so a single
12-stage ripple counter provides every timing signal on the card:

| tap | divide | signal |
|---|---|---|
| Q4 | ÷16 | 512 kHz half-bit clock |
| Q5 | ÷32 | 256 kHz line bit clock — this is `H` |
| Q6, Q7, Q8 | ÷64…÷256 | mod-8 frame counter, Q6 = LSB |
| Q8 | ÷256 | 32 kHz frame clock → channel cards |

That replaces a ÷16 divider, a ÷2, a frame counter and a clear gate — roughly
three packages.

**Ripple caveat.** The '4040's stages do not change together: Q1→Q8 skew is
~100 ns and decoding `Q8·Q7` can glitch briefly. Benign here, because every
consumer has ~2 µs of settling before the mid-cell sampling edge, and 100 ns on
the 31.25 µs frame clock is 0.3% — far inside what CVSD tolerates. Worth knowing
before you scope it and see the spikes. If it bothers you, a synchronous
74HC161 chain costs two more packages and removes it.

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
512 kbaud (1.95 µs half-cell) that is well inside the eye while meaningfully
reducing radiated emissions. Do not skip this — a raw 75176 edge into outside
plant is unnecessarily noisy.

**Transformer:** 1:1, **centre-tapped on the line side**.

Running disparity in differential Manchester is bounded at ±1 bit cell =
3.906 µs. For under 5% droop over that interval, `L/R > 78 µs`; at 100 Ω that is
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
| Oscillator | 74HC04 + 8.192 MHz crystal |
| **All timing: ÷16, ÷2, frame counter, frame clock** | **74HC4040** |
| Payload mux | 74HC151 |
| S/T select | 74HC157 (¼) |
| Biphase T flip-flop | 74HC73 or 74HC76 |
| Gates (S/T select, NAND) | 74HC00 |
| Line driver | 75176 |

**~6 packages**, plus one transformer and the protection network. Every tap runs
at 512 kHz or below.

---

## 7. Bring-up order

1. **Clock chain alone.** Scope 8.192 MHz and the Q4 / Q5 / Q8 taps (512 / 256 /
   32 kHz) before anything else is populated.
2. **Frame counter and mux, no encoder.** Watch the raw line bit stream on a
   logic analyser: it should show the 10-bit frame with 0 then 1 at counts 8
   and 9. This is directly comparable to `link.build` output from the simulator.
3. **Biphase encoder.** Check that every cell boundary has a transition and
   that mid-cell transitions track the data. Confirm DC balance on a scope with
   AC coupling — the trace should show no baseline wander.
4. **Into the transformer and a short cable**, then into the receiver.

Steps 1–3 need no receiver and no far end.
