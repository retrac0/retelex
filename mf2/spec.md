# Two-channel TDM digital voice carrier over AMI

Two 64 kbps channels with a sub-commutated signalling channel in a 4-bit frame.
This is over one twisted pair each way. It is implemented with discrete 74HC
logic. It is the **N = 2** member of the family in `mf8/frame-rate.md` §1
(F + S + N is a power of two; N ∈ {2, 6, 14}).

A channel slot is a DS0: 64 kbps and octet-aligned, so it takes a CVSD voice
card, a synchronous data card, or a G.711 PCM stream — same card faces as MF8,
with the slot rules of §5.

> **Status: sketch.** Geometry, AMI, and the 8-frame superframe are **decided**.
> F-word / guard / seats / AMI plant numbers for this frame are **not measured**.
> Until §15 is closed, treat every quantitative claim copied from MF8 as a
> starting hypothesis. The live trunk remains MF8 (`mf8/mf8-spec.md`).

Parent documents: `mf8/mf8-spec.md` (framer, cards, failure behaviour),
`mf8/line-codes.md` (AMI vs differential Manchester), `mf8/frame-rate.md`
(family rates), `exchange/mf8-unit.md` (split trunk vs fuse).

AMI encoder/decoder: [`ami.md`](ami.md) — **ngspice 74HC+line PHY** in
[`../spice/mf2-ami/`](../spice/mf2-ami/) (`make -C spice/mf2-ami all`).
Simulation checklist: [`sim.md`](sim.md). Line plant (Python):
`sim/mf2_line.py` → `mf8_line.rx_ami`.

---

## 1. What this is, and what it is not

| | MF8 | **MF2 (this spec)** |
|---|---|---|
| Frame | 8 bits, N = 6 | **4 bits, N = 2** |
| Line | 512 kbps | **256 kbps** |
| Line code | differential Manchester | **AMI** |
| Baud | 1.024 MBaud | **256 kBaud** |
| Reach (√f vs 256 kbps ref) | 0.71× | **1.00×** (~1.41× MF8 span) |
| Superframe | 8 frames, 8 kHz | **8 frames, 8 kHz** (octet counter kept) |
| Channels | six | **two** |
| RX timing | clockless monostable | **crystal + DPLL** |
| Fabric fit | fused on highway seats 1–3, 5–7 | **split block adapter** (§10); gateway into MF8 (§11) |

**Not taken:** 4-frame superframe (loses octet / `RX_OCT`); polar NRZ; CMI;
3B4B expansion of a 3-bit logical frame; raw nesting of MF2 bits inside an MF8
frame; clockless AMI.

**Decided against nesting:** an MF2 span terminates to C/A and is re-inserted
into safe MF8 seats. Bit-for-bit embedding fights line rate, F/S words, and
superframe phase (`exchange/mf8-unit.md`).

---

## 2. Frame and superframe

**Frame — 4 bits, 15.625 µs, 64 kHz:**

```
 bit:   0     1      2     3
      [ F ][ C1 ][ S ][ C2 ]
      00    01    10    11     <- mux address
```

S sits at bit 2, **half a frame from F**. For frame length L = 4 the unique
opposite spacing is s = 2 (`2s ≡ 0 (mod L)`), the same geometric rule as
`mf8-spec.md` §3.4. Do **not** put S beside F: that revives the one-data-card
false-lock hole.

**Superframe — 8 frames, 125 µs, 8 kHz:**

| state | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|---|
| **F** | 1 | 1 | 1 | 1 | 1 | 1 | 1 | **0** |
| **S** | **0** | A1 | — | — | **1** | A2 | — | — |

`An` is channel *n*'s signalling bit. States 0 and 4 are the guard (§3.2).
States 2, 3, 6, 7 are spare on S (RAI / SS0 / complement-pair candidates —
`mf8-spec.md` §3.5); freeze them only after the false-lock battery.

The superframe counter is the octet counter: at 64 kHz frame rate the
superframe rate is **8 kHz**, so each channel is a DS0 with `RX_OCT` at
state 7, as on MF8 (`mf8-spec.md` §6, `common/clocks.md`).

Signalling: one A bit per channel per superframe → **8 kbps per channel**,
same order as MF8 (not the 16 kbps of a lean 4-frame SF).

Line rate: 4 × 64 kHz = **256 kbps**. AMI symbol rate = **256 kBaud**.

---

## 3. The F word and guard

### 3.1 F — the word `11111110`

Same word as MF8. One check pins bit alignment and superframe phase. Generator
from the 3-bit superframe counter:

```
F = NAND(q2, q1, q0)        one 3-input gate
```

> **Unmeasured on N = 2.** `frame-rate.md` §6 and `mf8-spec.md` §8: only N = 6
> has a validated F word. Re-run `word` / `sfphase` on a 4-bit model before
> claiming MF8-class rejection of CVSD silence and constant lanes.

### 3.2 The guard — S at states 0 and 4 = `0,1`

Same rule as MF8 §3.2: two same-parity states, values different from each
other and from F at those states, so a period-2 idle lane and a lane carrying
the F word both fail.

```
guard enabled  =  NOR(q1, q0)     states 0 and 4
guard expected =  q2
```

### 3.3 Where S sits

`[F][C1][S][C2]`. At skew 2 the receiver reads F and S swapped onto each
other (F word on itself) and fails the guard the same way MF8 does. Skews 1
and 3 read **(C1, C2)** — the only payload pair. That is the seating problem
in §5.

---

## 4. Framer

Carry MF8's structure until measured otherwise:

| item | intent (from MF8) |
|---|---|
| Acquisition | 32 consecutive good frames |
| Tracking | +2/−1, floor 0, trip 12 |
| Counters | **separate** F and guard counters (mandatory; speech can satisfy the guard sparsely) |
| No carrier | forced loss of frame + MUTE (`mf8-spec.md` §9.6, §13) |

Hunt space is four bit alignments × eight SF phases. Smaller than MF8's, but
not a reason to drop the second counter.

> **Unmeasured:** acquisition time, false-lock counts, slip recovery under AMI
> bit errors (AMI should not bit-count-slip the way DM does —
> `line-codes.md` §4).

---

## 5. Slot rules

MF8 forbids data cards at seats three apart because that spacing is F-to-S
(`mf8-spec.md` §5). On MF2 the F-to-S spacing **is the only two channel seats**.

**Product rule (until alternate framing is measured):**

| fit | allowed? |
|---|---|
| two voice cards (CVSD / FXS / E&M) | yes |
| one voice + one data | residual chance-acquisition only — keep the guard counter |
| **two data cards** | **no** |
| bonded 128 kbps (two data seats) | **no** — same forbidden pair |

Keying and silkscreen must not reuse MF8's "seats 1–3" story; the rule is
carrier-specific.

**Open:** XOR / alternating-bit on C lanes (`mf8-spec.md` §3.5 idea) so two
data cards become chance acquisitions the guard counter releases. Measure with
a `seats` sweep before lifting the product rule.

---

## 6. Octet alignment

Kept. SF = 8 at 64 kHz frame rate ⇒ 8 kHz `RX_OCT`. PCM and synchronous data
cards use the same octet story as MF8 §6.

A 4-frame superframe was rejected: it yields a 16 kHz SF ("half an octet") and
a period-4 F word cannot pin an 8-state octet phase (`frame-rate.md` §4).

---

## 7. Rates and reach

Family row taken (`frame-rate.md` §1):

| | per-ch | line | AMI baud | capacity | reach vs 256k ref | vs MF8 span |
|---|---|---|---|---|---|---|
| **this spec** | **64k** | **256k** | **256 k** | **128k** | **1.00×** | **~1.41×** |

Lower per-channel rows (32k / 16k) buy more √f reach but need rate adaptation
to the 64 kbps highway seat and lengthen impulse outages (`frame-rate.md`
§3.1). **Not in this sketch.** Rate plug may still expose them later as a
family jumper; default is 64 kbps / 256 kbps only.

Attenuation on the 256 kbps reference span sits at the ~20% hysteresis
"single-span limit" in `frame-rate.md` §3 — expect the preamp footprint
populated more often than on a short MF8 hop.

---

## 8. Line code — AMI

Hardware and sim reference: [`ami.md`](ami.md). The noisy-line model is
`mf8_line.rx_ami` at 256 kbps (`sim/mf2_line.py`); do not fork the decode rule.

### 8.1 Choice

**AMI**, not differential Manchester.

| reason | note |
|---|---|
| Reach / bandwidth | one symbol per bit → 256 kBaud vs DM's 512 kBaud at the same bit rate |
| Magnetics | disparity bounded ±1 mark; transformer OK (`line-codes.md` §1) |
| Zero runs | framing bit bounds marks; HDB3/B8ZS not required (§8.2) |
| Impulse | bit errors, not bit-count slips (`line-codes.md` §4) — fits a long span |
| Cost | three-level driver + **RX crystal DPLL** (family 4.096 MHz already present) |

Differential Manchester remains the MF8 trunk code. CMI and polar NRZ are out
(CMI: no baud win; polar: unbounded disparity on transformers).

### 8.2 Zero runs

On MF8 the structural bound is 15 zeros (`line-codes.md` §2.1). On a 4-bit
frame with `11111110`, expect a **shorter** worst mark gap (analysis ~7–8 bit
periods — **measure**). That eases DPLL coasting vs MF8; it does not justify a
clockless AMI receiver (MF8 option A failed at ±3% parts).

### 8.3 Encoder

Standard AMI: `0` → 0 V; `1` → alternate +A / −A. One flip-flop for mark
polarity + three-level line driver (or push-pull with disable for spaces).
Parts sketch TBD from MF8 §9.3's driver family, adapted for ternary.

### 8.4 Decoder — clocked

**Option C from `line-codes.md` §2.2:** oversampling DPLL off the local
4.096 MHz crystal. The crystal is a **sampling** reference; bit phase locks to
mark edges. Bit count stays with the far end (no free-running data clock).

Do **not** use a free-running local oscillator as the data bit clock through
dropouts — that reintroduces slips. No-carrier still forces LOF + MUTE.

Classifier / peak / threshold: amplitude decision vs ~½ peak (AMI). Re-run
Gaussian and attenuation columns at 256 kbps; MF8's 512 kbps numbers do not
scale blindly.

### 8.5 Polarity

AMI remains tip/ring swap tolerant if the front end is full-wave for mark
detection (`line-codes.md` §2.3). Confirm on the MF2 encoder/decoder.

### 8.6 Oscillator and rate plug

Same 4.096 MHz family crystal as MF8 §9.1. At 256 kbps: 16× oversample is
native. Rate-plug RC for filter, carrier timeout, DPLL loop constants —
populate for the 256 kbps row (`mf8-spec.md` §9.7 table, Q3 class).

---

## 9. Transmitter and receiver (block level)

### 9.1 Transmit path

```
C1,C2,A1,A2  →  frame mux (F,S insert)  →  AMI encoder  →  line driver / Xfmr
                      ↑
              SF counter (shared)
```

Mux is a 4:1 on a 2-bit address from the bit counter — not the exchange
`'151` on `SLOT` (that commutator is eight seats at 512 kbps).

### 9.2 Receive path

```
Xfmr → filter → slicer → AMI decode + DPLL → framer → C1,C2,A1,A2, RX_OCT, MUTE
```

Package budget: order of MF8's framer (~6 IC) plus AMI three-level I/O and
DPLL — roughly **comparable total packages to an MF8 trunk for two channels
instead of six** (analysis; count when schematics exist).

---

## 10. Block fit — two channel cards

Two ordinary channel sockets do **not** share per-slot C/A or a line PHY
(`common/common-cards.md`, `mf8/mf8-backplane.md`). MF2 needs one of:

1. **Block adapter** on the **block header** (`exchange/fabric.md` §5.2)
   owning the framer, AMI PHY, and mute — non-breakout mate of the star; or
2. Master + ribbon between a paired card set, or
3. Double-width card.

**Decided intent: (1)** — split architecture in the sense of
`exchange/mf8-unit.md` §2.A (unit owns line crystal and frame; fabric stays
8 × 8). Fusion of MF2 onto highway F/S seats is impossible at 256 kbps vs
512 kbps HCLK.

Clocks: bit clock 256 kHz may be divided from `HCLK` locally if not pinned
(`common/clocks.md`).

---

## 11. MF8 gateway (embedding)

**Terminate and re-insert.** Extract two C/A pairs; place them in MF8 payload
seats that are **not** three apart (e.g. (1,2) or (2,3), never (2,5)).
Independent clocks ⇒ retiming / slip policy as in `mf8-unit.md` §5.5.

Mis-jumper MF2 ↔ MF8 (same plug row, wrong alphabet) must mute deterministically
— **unmeasured** (`mf8-spec.md` §15).

---

## 12. Channel cards

Reuse MF8 card faces (`common/channel-cards.md`, `mf8-spec.md` §12): CVSD
subscriber, FXS/FXO, data, E&M. Slot interface unchanged: `C`, `A`, word,
`/ANS`, mute, `RX_OCT`.

Differences: seating/keying per §5; A-path RC was measured at MF8's 8 kHz —
re-check if spare S states change edge density; data-card bonding across the
two MF2 seats is forbidden.

---

## 13. Failure behaviour

Intent: same as MF8 §13 — mute on unlock, carrier detect into LOF, squelch on
voice cards, no audio on false lock. AMI-specific: bipolar violations may
feed a per-frame erasure / idle toward CVSD (optional cheap integrity; not a
substitute for the framer).

---

## 14. Signalling

S superframe: guard at 0,4; A1 at 1; A2 at 5 (mirror of C bit indices 1 and
3 — adjust if the mux address map wants Aₙ at the state equal to Cₙ's frame
bit; with only two channels the natural mirror is states 1 and 3).

> **Sketch picks 1 and 5 above for "same half as MF8's A block"; freeze the
> mirror map when the mux is drawn so the '151/'259 address story stays one
> map.**

Spare S states: leave reserved until RAI/SS0 is designed. Do not spend a
guard seat on signalling.

---

## 15. What is and is not measured

| item | status |
|---|---|
| Family rate row 4b / 64k / 256k | arithmetic (`frame-rate.md`) |
| Opposite-S geometry for L = 4 | analysis (mod-L rule) |
| F word / guard / skew / seats on N = 2 | **not measured** |
| Two-data-card false lock | **analysis — treat as critical** |
| AMI zero-run bound on this frame | **not measured** |
| AMI DPLL at 256 kbps (offset, coast) | **not measured** (MF8 was 512k) |
| Gaussian / attenuation / impulse at 256k AMI | **not measured** |
| Mis-jumper MF2 ↔ MF8 | **not measured** |
| Block-adapter / block-header pinout / package count | **not drawn** |
| A-filter with final S map | **not measured** |

---

## 16. Reproducing

The simulation checklist is [`sim.md`](sim.md): gates G1–G5, bit-level
framer targets, AMI structural tests, waveform plant, mis-jumper, and run
order. Intended entry points `sim/mf2.py` and `sim/mf2_line.py` (fork
`mf8.py` / `mf8_line.py`); nothing there has been run for N = 2 yet.

Flip §15 rows to measured results as each gate in `sim.md` goes green.

---

## 17. Open decisions (narrow)

1. Exact S-state map for A1/A2 (1&3 vs 1&5) and which spares are RAI/SS0.
2. Whether XOR/alternating-C lifts the two-data ban after measurement.
3. Preamp always-on vs jumper for short MF2 hops.
4. Filename / doc home: this file is `mf2/spec.md`; link from `README.md` when
   the sketch graduates past "decided geometry."
