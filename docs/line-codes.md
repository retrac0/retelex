# Line codes for this carrier — differential Manchester against the field

> **Working record, and one question left open.** `spec.md` §5 chose differential
> Manchester and kept AMI on file "for a span limited by bandwidth rather than
> attenuation". This document tests that choice against everything the plant can
> do, and finds a **second** reason to keep AMI on file: under impulse noise the
> two codes rank the opposite way round, and by a wide margin. Every other
> objection to AMI — zero runs, clock recovery, polarity, slips — turns out to be
> answerable. The decision now rests on a single number nobody here has: the
> impulse rate on the target loops.
>
> Everything was measured by `mfcmp.py` on the same chain `s4_simple.py` and
> `framing_review.py` run; `mfcmp.log` is the run. This began as part of
> `mf-vs-16bit.md` and outgrew it. `frame-rate.md` is the other half.

Both codes are carried on the same frames throughout: the 8-bit superframe frame
(`mfspec.md`, and now `mf8-spec.md`) and the 16-bit 7-channel frame (`spec.md`),
at 512 kbps on one twisted pair.

---

## 1. The candidate set, decided by one column

Nine codes on the mfspec frame, structural properties measured (`mfcmp.py
codes`). Intervals and disparity in **bit periods**: min interval sets the
maximum fundamental and therefore bandwidth and reach; max interval sets what
clock recovery has to coast; disparity swing is the DC wander a transformer must
pass. Random payload, constant-0 worst case in brackets where it differs:

| code | levels | min int | max int | disparity swing |
|---|---|---|---|---|
| Manchester (biphase-L) | 2 | 0.50 | 1.00 | **1.0** |
| **differential Manchester** | **2** | **0.50** | **1.00** | **1.0** |
| **AMI** | **3** | **1.00** | 13 (15) | **1.0** |
| CMI | 2 | 0.50 | 1.50 | **1.5** |
| Miller | 2 | **1.00** | **2.00** | 96 (502) |
| NRZI | 2 | **1.00** | 14 (16) | 186 (30) |
| polar NRZ | 2 | 1.00 | 14 (15) | 3168 (26999) |
| unipolar RZ | 2 | 0.50 | 13.5 (15.5) | 7210 (1250) |
| unipolar NRZ | 2 | 1.00 | 14 (15) | 14420 (2500) |

**The disparity column decides the candidate set** before noise performance is
discussed at all. The pair is transformer coupled (`spec.md` §5) and a
transformer cannot pass unbounded DC wander:

- bounded, order one bit period — Manchester, **differential Manchester**, **AMI**, CMI → viable
- data-dependent, 5–500 bits — Miller, NRZI → out
- hundreds to tens of thousands — unipolar NRZ/RZ, polar NRZ → out

### 1.1 What that rules out, and what it nearly did not

**Miller (delay modulation) was the promising one.** It halves the bandwidth like
AMI *and* bounds its max interval at 2.0 bits, which would make clock recovery
nearly as cheap as differential Manchester — the best of both, on paper.
Measured, it swings **96 bit periods of disparity on random payload and 502 on
constant 0.** That is the classic Miller DC problem, and it is why Miller-squared
exists; the patch costs encoder state and is heuristic.

**NRZI** halves the bandwidth, is polarity-blind, and has its run length bounded
at 16 by the same framing bit that bounds AMI's (§2.1). It fails the same way:
186 bit periods. Both would need a DC-management layer — scrambling or block
coding — and `framing-review.md` §8 records why scrambling is unattractive here
(lockup on all-zero idle onsets, ~2⁻⁷).

**CMI is the near-miss.** Two levels, DC-free, disparity 1.5, max interval 1.5
bits. It matches differential Manchester on every axis and beats it on none —
same 0.5-bit min interval, so the same bandwidth and the same reach.

**Manchester (biphase-L)** is structurally identical to differential Manchester
in the table. It differs in one respect the table cannot show: it carries data in
the *direction* of the mid-cell transition, so inverting the pair swaps ones and
zeros. It is not polarity-blind, and §5 measures that the differential form is —
for free. That is the entire reason to prefer the differential form, and it is
sufficient.

**Ruled out by the build constraint rather than by measurement:** 2B1Q, MLT-3 and
duobinary need equalisation or echo cancellation and are not discrete-TTL
propositions; 4B/5B needs a lookup table and a 25% rate increase, which also
breaks the power-of-two frame; HDB3 and B8ZS solve a zero-run problem the frame
has already solved (§2.1). `framing-review.md` §8 notes TRI-TAC ran this same
codec over *conditioned diphase*, a biphase variant — the closest field
precedent, and it lands where this design already is.

**So the viable set is {differential Manchester, AMI}**, and the rest of this
document is those two.

---

## 2. AMI's three standard objections, and what happens to them

### 2.1 Zero runs — the frame already solved it

Worst run of zeros on the line, over all 64 hook states (`mfcmp.py clock`):

| payload | longest zero run |
|---|---|
| **all constant 0** | **15** |
| random data | 13 |
| octet `10110010` | 9 |
| CVSD speech | 8 |
| CVSD silence / all constant 1 | 2 |

**The framing bit alternates, so a mark lands every 2 frames = 16 line bits
whatever the payload does.** 15 is structural, not statistical. B8ZS substitutes
at 8 zeros and HDB3 at 4, so neither is needed — the framing bit does their job
for free. `mf8-spec.md`'s `11111110` word keeps the same bound, since F is 0 only
one frame in eight.

### 2.2 Clock recovery — a tank is hard, the crystal is easy

Differential Manchester has a transition every cell, so `spec.md` §6.1's receiver
has **no clock on the timing path at all**. AMI sends nothing for a zero and must
flywheel. The reason it is harder is the **dynamic range** of the measurement,
not the presence of timing:

| | intervals to distinguish | ratio | tolerance needed |
|---|---|---|---|
| differential Manchester | 0.5 or 1.0 cell | 2:1 | ±13% measured sufficient |
| AMI | gaps of 1 … 16 bit periods | **16:1** | **< 3.1%** |

A gap of *k* mis-rounds once tol·*k* > 0.5, so resolving 16 needs better than
3.1%. Three architectures, measured:

**A — no clock at all.** Time mark-to-mark gaps with an RC and round to whole bit
periods, the way the monostable rounds a half-cell against a full cell:

| RC tolerance | random BER | constant-0 BER | constant-0 bit count |
|---|---|---|---|
| **2.0%** | **0** | **0** | −15 (end effect) |
| **3.0%** | 6.5e−02 | 1.5e−01 | **−765** |
| 5.0% | 4.8e−01 | 1.4e−01 | −3014 |

Error-free to 2%, broken at 3% — the 3.1% predicted. `spec.md` §6.2 says a 1%
resistor with a 2% C0G capacitor gives **±3%**, so a clockless AMI receiver lands
exactly *on* its failure point with no margin, where the same components give
differential Manchester four times the margin it needs. And the failure mode
settles it: a mis-rounded gap emits the wrong *number* of zeros, so **the
failures are slips** — handing back the one property that makes AMI worth
considering (§4.1). Not a real option.

**B — an analog tank** flywheeled off the line. Rectify, drive a resonator,
square it up. BER on the worst payload, sampling phase trimmed once at nominal:

| Q | amplitude left after 15 idle cycles | 0.25% detune | 0.5% | 1% |
|---|---|---|---|---|
| 50 | 0.39 | 4.7e−02 | 4.7e−02 | 4.7e−02 |
| **100** | 0.62 | **ok** | 3.1e−02 | 4.7e−02 |
| **200** | 0.79 | **ok** | 3.1e−02 | 4.7e−02 |

Two effects pull opposite ways, and the one that fails is not the obvious one:

```
coasting decay over 15 idle cycles = exp(-pi*15/Q)    -> wants Q HIGH
static phase shift when detuned    = atan(2*Q*df/f)   -> wants Q LOW
```

Coasting drift at 0.5% detune is only 0.075 bit (27°) — not the problem. What
fails is the resonator's *static* phase shift, growing as `2Q·δ`, and the
measured edge sits exactly at `δ ≈ 1/(2Q)`. So a tank wants **Q ≈ 100 and tuning
inside ~0.25% simultaneously**; a 1% inductor with a 1% capacitor gives about 1%,
so an LC tank does not reach it. That is a ceramic resonator or a crystal, one
per line rate, on the receiver's rate plug.

**C — an oversampling DPLL off the local 4.096 MHz crystal.** The oscillator
`spec.md` §4.1 already specifies divides every family rate exactly — 4× / 8× /
16× / 32× / 64× for 1024 / 512 / 256 / 128 / 64 kbps. Sampling at 8× and running
an ordinary DPLL on the mark edges, on the worst payload:

| crystal offset | drift across the clip | bits emitted − sent | BER |
|---|---|---|---|
| 200 ppm | 9.6 bits | **0** | 0 |
| 1000 ppm | 48 bits | **0** | 0 |
| **5000 ppm** | **240 bits** | **0** | 0 |

**Does a local crystal reintroduce slips?** No, and that is the question that
matters, because `spec.md` §1 rests on *"no rate mismatch anywhere and slips are
structurally impossible."* The crystal is a **sampling** reference; the DPLL
recovers bit phase from the line, so the bit clock stays locked to the far
transmitter. The bit count is exact at every offset, including 5000 ppm where the
two clocks drift 240 bits apart. **The DPLL absorbs drift as phase, not as
bits.** Only a free-running local clock used as the *data* clock would slip.

**It is also not a loss of rate-blindness**, which is the obvious objection and
is wrong: the receiver already carries a per-rate plug (`spec.md` §2.2,
`line-receiver.md` §8) for the input filter, classifier, dead time and carrier
detect. On that axis option C is an *improvement* — the per-rate change becomes a
counter tap, exact and digital, instead of matched RC values. Repeaters are
unaffected; they slice and re-drive and never see the frame.

**What AMI's clock costs is the receiver's clocklessness, and nothing else.**
`spec.md` §6.3 already prices that trade: the oversampling DPLL is the *reference*
receiver there, and the clockless monostable was chosen over it at a cost of 3×
at the noise edge.

### 2.3 Polarity — it is already neutral, for free

A tip/ring swap inverts everything arriving differentially, signal and coupled
noise together, so the test is inverting the **complete received waveform**:

| condition | differential Manchester | AMI |
|---|---|---|
| clean | **identical** | **identical** |
| noise sd 0.4 / 0.6 | **identical** | **identical** |
| impulse 100/s | **identical** | **identical** |
| attenuated 0.25× | **identical** | **identical** |

Bit-identical in every condition for both codes, *including while the link is
making errors* — the errors themselves are the same errors. End to end through
the 16-bit frame and the `spec.md` §7 framer, both polarities lock, recover the
lanes in the right order, and take 0 loss-of-frame events.

The two get there differently. Differential Manchester decides *same-vs-different
half cells*, and inversion flips both. AMI decides `|x| > thresh × peak` — **the
sign never enters** (`phy.ami_decode`; `c_ami_decode` uses `fabs`). The part
worth noticing is that AMI's blindness is not bolted on: **a full-wave front end
is mandatory for AMI anyway**, because marks arrive as both `+` and `−` pulses
and a half-wave receiver would miss every other one. Polarity neutrality falls
out of the receiver you must build regardless.

The alternation rule is symmetric too — inverting `+,−,+,−` gives `−,+,−,+`,
still valid, and a bipolar violation stays a violation under either polarity, so
even BPV error detection survives a swap.

---

## 3. Gaussian noise and attenuation — differential Manchester wins

One 1.8 MHz cable, 512 kbps, noise sd referred to the signal **peak** — one
rail-limited driver, one cable, one noise floor, which is `spec.md` §2.1's "same
cable" condition. Differential Manchester runs at 1.024 MBaud with a 1.024 MHz
receive filter and the 0.75-cell monostable; AMI at 512 kBaud with a 512 kHz
receive filter, which is where its noise-bandwidth advantage comes from.

Raw line BER, no framer, so the protocol cannot amplify anything:

| code | sd 0.0 | sd 0.4 | sd 0.5 | sd 0.6 | sd 0.7 |
|---|---|---|---|---|---|
| **differential Manchester** | ok | **ok** | **ok** | **ok** | 9.4e−05 |
| AMI, exact amplitude | ok | 4.7e−05 | 3.0e−04 | 3.0e−03 | 1.1e−02 |
| AMI, 0.8× amplitude | ok | ok | 6.3e−05 | 6.3e−04 | 2.7e−03 |
| AMI, 0.6× amplitude | ok | 3.4e−04 | 2.1e−03 | 6.1e−03 | 1.3e−02 |

**Error-free to sd 0.6 against AMI's 0.4, despite AMI collecting half the noise
bandwidth.** Differential Manchester decides on transition *timing* against a
0.75-cell monostable, so noise must displace an edge by a quarter cell to cause
an error; AMI decides on *amplitude* against a threshold at half the received
peak, and at equal peak line voltage that is the smaller margin. The threshold is
also not where you would put it — 0.8× the estimated peak beats the nominal 0.5×,
and a 0.6× error costs about a factor of ten. This corroborates `spec.md` §5's
rejection of AMI and adds the mechanism: **AMI's loss is the amplitude decision,
not the bandwidth.** The AMI figures are generous, because the decoder estimates
its own peak from the data — free AGC a real receiver would have to build.

**Attenuation, and the cliff is the hysteresis spec.** Signal scaled; the sd 0.10
noise floor and the 0.05 comparator hysteresis both held fixed, so loss costs
real margin. (`spec.md` §5.1 notes the cable lowpass models dispersion, not loss,
which is why attenuation has to be applied separately.)

| atten | hysteresis, % of received | differential Manchester | AMI |
|---|---|---|---|
| 1.0 | 5% | 0 LOF | 0 LOF |
| 0.5 | **10% — `spec.md` §6.1 limit** | 0 LOF | 0 LOF |
| 0.25 | **20% — single-span max** | 0 LOF | 0 LOF |
| 0.12 | **42% — out of spec** | 237 LOF, 69.53% down | 22 LOF, 15.23% down |
| 0.06 | 83% | 100% down | 100% down |

**The measured cliff sits exactly where the hysteresis leaves its specified
range.** Error-free at 0.25, where hysteresis is 20% of received amplitude and
`spec.md` §6.1 allows 20% on a single span; collapsed at 0.12, where it is 42%
and the comparator stops responding to real transitions. So the attenuation limit
is **the comparator, not the noise floor** — the fix is smaller hysteresis or an
AGC stage, not more launch amplitude.

---

## 4. Impulse noise — the ranking reverses

`phy.plant_noise`: damped rings at 0.5–3× the signal peak as `repeater.py` uses,
15–80 kHz, 20–200 µs decay, Poisson arrivals. Each impairment swept alone.

| events/s | code | mfspec framer: unlk / down | 16-bit framer: LOF / down |
|---|---|---|---|
| 0 | either | 0 / 0.1% | 0 / 0.4% |
| 10 | diff. Manchester | 8 / 1.47% | 7 / 1.24% |
| 10 | **AMI** | 10 / 1.72% | **0 / 0.40%** |
| 100 | diff. Manchester | 72 / 13.29% | 62 / 7.94% |
| 100 | **AMI** | 79 / 13.40% | **0 / 0.40%** |
| 1000 | diff. Manchester | 283 / 64.48% | 262 / 52.09% |
| 1000 | AMI | 262 / 74.87% | 92 / 65.10% |

**With the 16-bit framer, AMI takes 0 loss-of-frame events and 0.40% downtime at
100 events/s where differential Manchester takes 62 and 7.94%.**

### 4.1 The mechanism is bit count, measured directly

Bits emitted minus bits sent, 4 seeds, 128 000 line bits:

| impulse/s | differential Manchester | AMI |
|---|---|---|
| 0 | −1, −1, −1, −1 (a constant end effect) | 0, 0, 0, 0 |
| **10** | **−15, −90, −86, −1** | **0, 0, 0, 0** |
| **100** | **−243, −406, −485, −200** | **0, 0, 0, 0** |
| 1000 | −3309, −3364, −3662, −2966 | 0, 0, −1, 0 |

The monostable decides on transition *timing* and has **no independent time
reference**, so a transient that adds or swallows an edge changes the bit count —
and every lost bit is a slip that re-phases the frame and forces a
reacquisition. AMI is clocked: it emits exactly one bit per recovered clock
period whatever the line does, so the count cannot drift and the `+1/−1` counter
only ever sees ordinary bit errors, which is what it is for.

### 4.2 Susceptibility is a sharp threshold at the signal amplitude

The rings are 15–80 kHz against a 512 kHz symbol rate, so each acts as a slowly
varying **offset** on the timescale of a bit. With the signal at ±1 and
comparator hysteresis *h*, an offset of magnitude *A* sticks the comparator when
**A > 1 − h**: the polarity the ring is currently displacing stops crossing, and
every transition while that holds is lost.

Each event is a *damped sinusoid with a randomly signed amplitude*, so it swings
**both polarities** many times rather than stepping one way — a 40 kHz ring
reverses every 6.4 bit periods, and one measured ring spanned −1.659 to +1.880
with 23 zero crossings. The blanking therefore alternates which polarity it kills
as the ring rings, which is why the damage runs for the ring's whole length
(20–200 µs = 10–100 bit periods) rather than for a single half-cycle. Over
0.5 s at 200 events/s the noise is symmetric: min −3.165, max +2.859, mean
−1.3e−04, 1.93% of samples below −0.1 against 1.91% above +0.1.

Bits lost at 200 events/s:

| impulse amplitude, × signal peak | differential Manchester | AMI: bits lost | AMI: raw BER |
|---|---|---|---|
| 0.50 | 1, 2, 1, 1 | **0, 0, 0, 0** | 2.8e−05 |
| 0.80 | 9, 16, 13, 2 | **0, 0, 0, 0** | 2.7e−03 |
| 0.95 | 31, 39, 50, 25 | **0, 0, 0, 0** | 4.4e−03 |
| **1.10** | **250, 278, 301, 206** | **0, 0, 0, 0** | 6.0e−03 |
| 1.50 | **1665, 1820, 1966, 1423** | **0, 0, 0, 0** | 9.8e−03 |
| 3.00 | 6413, 7050, 7657, 5694 | **0, 0, 0, 0** | 1.8e−02 |

Two things at once, and the second overturns the easy reading of §4:

- Differential Manchester's threshold lands where predicted, just below 1.0× the
  received signal. Below it an impulse costs essentially nothing; above it, the
  whole ring.
- **AMI starts erring at half that amplitude**, because it decides `|x| > 0.5 ×
  peak` and an offset of 0.5 either fakes a mark on a zero slot or cancels a real
  one. At 0.8× peak AMI makes ~1400 wrong bits where differential Manchester
  makes about a dozen.

**So AMI is the more susceptible code in raw terms. Its advantage is not
immunity — it converts a few catastrophic slips into many benign bit errors**,
and the `+1/−1` counter is measured good to 3e−02, above every BER in that
column.

Hysteresis moves the threshold the **wrong** way (`A > 1 − h`) — at amplitude
0.9, bits lost go 13–23 at h = 0.02 to 77–85 at h = 0.20 — so the
impulse-optimal comparator is a *tight* one, the opposite of what Gaussian noise
wants.

**A prediction that did not survive:** `ami_decode` sets its threshold from the
99th percentile of `|x|`, so impulses should inflate it and push real marks
under. Pinning the threshold to the nominal peak changes nothing (4.4e−03 against
4.7e−03 at 0.95). The AGC is not the mechanism.

### 4.3 What it costs the audio

Channel 1 through the full chain, 1.0 s clip, with the `spec.md` §7 framer on the
16-bit frame — a properly built receiver, so this isolates the line code. segSNR
is scored on the **longest unbroken locked stretch** against the codec over the
*same window*, because a slip shifts the time base and scoring the whole clip
against one alignment reports a collapse that is mostly bookkeeping:

| impulse/s | diff. Manchester | AMI |
|---|---|---|
| 1 | +0.00 dB, 0 breaks, 999 ms clean | +0.00 dB, 0 breaks, 999 ms clean |
| **10** | −2.35 dB, **5 breaks/s**, 475 ms | **−1.28 dB, 0 breaks, 999 ms** |
| **100** | *too short to score*, **65 breaks/s**, 71 ms | **−7.86 dB, 0 breaks, 999 ms** |
| 1000 | never locks | never locks |

**At 100 events/s AMI holds frame for the entire second without a single
reframe**, delivering continuously degraded audio, where differential Manchester
is chopped into 71 ms fragments by 65 breaks a second. For voice that is the
difference between a noisy channel and an unusable one — same impairment, same
receiver, same framer.

The cliff for differential Manchester spans about one decade of impulse rate and
costs both continuity *and* fidelity: at 10/s, five mutes a second **and** 2.35 dB
of degradation inside the stretches that never broke. There is no regime where it
is merely noisy.

The ranking inverts again at the extreme — at 1000 events/s AMI never achieves
lock while differential Manchester locks intermittently — so the trend is not
monotonic and should not be extrapolated past 100/s. Neither is a working link
there.

### 4.4 Mitigations — nothing tunes this away

**The transformer helps differential Manchester and does not help AMI.** The line
is transformer coupled and the model has none, so the figures above are
pessimistic. The lowest signal fundamental is 256 kHz, so a corner well above the
rings is available:

| high-pass corner | diff. Manchester, breaks/s at 100/s | AMI |
|---|---|---|
| none | 65 | 0 breaks, 0.10% down |
| 60 kHz | 34 | 0 breaks, 0.10% down |
| **120 kHz** | **26** | 0 breaks, **11.89% down** |
| 200 kHz | 30 | — |

AC coupling at ~120 kHz cuts differential Manchester's break rate **2.5×** and is
free — the component is already in the design, so the corner is worth specifying
deliberately rather than letting leakage inductance choose it. For AMI the same
filter makes things *worse*: differential Manchester's spectrum starts at
256 kHz, while AMI's is null at DC and peaks at 256 kHz with substantial content
below, so the filter removes AMI's own signal and distorts the pulse amplitudes
its decision depends on.

**Dead time does nothing**, and it is the obvious knob (0.05–0.30 cell usable per
`rx_review.py`). Bits lost at 200/s, amplitude 1.5: 1622–1755 at 0.05, 1665–1820
at 0.25, 3789–4135 at 0.45. Flat, then worse. **Dead time rejects edges that
arrive too early; a stuck comparator removes edges**, so there is nothing for it
to reject.

**AMI's decision threshold does nothing either** — 0 breaks and 4.4–5.7e−03 raw
BER flat across 0.3 to 0.7. So neither code has a *tuning* answer to impulse
noise. The only measured answer is structural: AMI does not slip.

---

## 5. The trade-off table

Measured columns marked with the section. Only differential Manchester and AMI
have been through the full chain; §1's other rows are structural plus analysis.

| | differential Manchester | AMI |
|---|---|---|
| Levels / driver | 2, two-state | **3, needs a three-level driver** |
| Symbol rate at 512 kbps | 1.024 MBaud | **512 kBaud** |
| Max fundamental | 512 kHz | **256 kHz** |
| DC / transformer | **bounded ±1 cell** ✓ | **bounded ±1 cell** ✓ §1 |
| Zero-run limit needed | none | **15, met by the frame** ✓ §2.1 |
| Receiver clock | **none at all** ✓ §2.2 | crystal + DPLL §2.2 |
| Polarity-blind | **yes** ✓ §2.3 | **yes, free** ✓ §2.3 |
| Decision rule | **timing**, 0.75-cell monostable | amplitude vs ½ peak |
| Gaussian margin | **sd 0.6** ✓ §3 | sd 0.4 §3 |
| Attenuation | cliff at the hysteresis limit §3 | threshold-limited §3 |
| Error onset under impulse | 0.95 × signal peak §4.2 | **0.5 ×** (worse) §4.2 |
| Kind of impulse error | **bit-count slip** → reframe ✗ | bit error → absorbed ✓ §4.1 |
| **Impulse, 100 events/s** | **chopped, 71 ms fragments** ✗ | **continuous, −7.9 dB** ✓ §4.3 |
| Encoder cost | ½ '74 + gate | alternation flip-flop + 3-level driver |

**Differential Manchester wins the Gaussian and attenuation rows and needs no
clock. AMI wins the impulse row outright and halves the bandwidth.** Everything
else is a tie or a detail.

---

## 6. Where this leaves it

**Keep differential Manchester**, which is `spec.md` §5's choice, and the reason
to cite is the **amplitude decision** — sd 0.6 against 0.4, plus the attenuation
behaviour — not the clock. Clocking splits: two wins (no clock hardware, and the
timing decision that produces the Gaussian margin) against one measured loss
(bit-count slips under impulse).

**Re-examine it if the plant is impulse-dominated.** §4 is not a small
correction: at 100 events/s it is the difference between a usable channel and a
broken one, and §4.4 says no amount of receiver tuning closes it. If AMI is ever
taken off the file, §2 is the answer sheet — the zero run is bounded at 15 by the
frame, the clock comes off the 4.096 MHz crystal already on the board with 12×
margin, and polarity is free.

**The decision turns on one number nobody here has: the impulse rate on the
target loops**, with the cliff located between 1 and 10 events/s. That is a
counter on a real pair, and it is worth more than any further simulation. It is
the same class of gap `spec.md` §12 has on reach.

---

## 7. Reproducing

```
python3 mfcmp.py codes        nine line codes on the frame, side by side
python3 mfcmp.py line         over the line with noise, both codes
python3 mfcmp.py plant        impulse and attenuation, swept independently
python3 mfcmp.py impulse      impulse threshold, audio cost, mitigations
python3 mfcmp.py impulse_ami  the same test again with AMI
python3 mfcmp.py polarity     tip/ring swap, both codes
python3 mfcmp.py clock        zero-run bound; AMI clock recovery, tank vs DPLL
python3 mfcmp.py rxclock      does an AMI receiver need a local clock?
```

How to read the numbers:

- §1 is measured for the structural columns; a code ruled out on disparity was
  not simulated, which is the point — it cannot cross the transformer whatever
  its noise performance.
- §§3–4 use 16 000-frame (0.25 s) clips × 4 seeds, and §4.3's audio is one 1.0 s
  clip, one talker, one seed per cell. Enough to place the impulse cliff between
  1 and 10 events/s; not enough to quote outage *rates* at the noise edge. Read
  the 1000+ events/s and sd 0.6–0.7 cells as indicative.
- Noise sd is referred to the signal peak, modelling a rail-limited driver.
  Referred to mean power instead, AMI would look better by its peak-to-rms ratio,
  which at 9.4% mark density is large.
- The AMI decoder estimates its own peak from the data — free AGC a real receiver
  would have to build — so §3's AMI column is optimistic.
- §2.2's tank models the flywheel, not a full PLL with a loop filter. A proper
  PLL would widen the detuning tolerance at the cost of its own acquisition
  behaviour, which has not been simulated. **This is the gap to close before the
  tank is ruled out on tuning grounds alone.**
- §4.4's transformer is a first-order high pass standing in for the real
  component's response. It shows the mechanism, not the part.
- §5's impulse amplitude (0.5–3× peak) and the fixed 0.05 hysteresis are
  `repeater.py`'s and `rx_review.py`'s values, so the rows are comparable with
  `repeater.md`. Impulses are not scaled by attenuation, which is conservative.
