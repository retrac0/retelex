# Line codes for this carrier — differential Manchester against the field

> **Working record, and one question left open.** `mf8-spec.md` §9 chose differential
> Manchester and kept AMI on file "for a span limited by bandwidth rather than
> attenuation". This document tests that choice against everything the plant can
> do, and finds a **second** reason to keep AMI on file: under impulse noise the
> two codes rank the opposite way round, and by a wide margin. Every other
> objection to AMI — zero runs, clock recovery, polarity, slips — turns out to be
> answerable. The decision now rests on a single number nobody here has: the
> impulse rate on the target loops.
>
> Everything was measured by `linecodes.py` on the same chain `mf8.py` and
> `linecodes.py` run; `linecodes.log` is the run. This began as part of
> `mf8-spec.md` and outgrew it. `frame-rate.md` is the other half.

Both codes are carried on the MF8 frame throughout (`mf8-spec.md`), at 512 kbps
on one twisted pair.

---

## 1. The candidate set, decided by one column

Nine codes on the MF8 frame, structural properties measured (`linecodes.py
codes`). Intervals and disparity in **bit periods**: min interval sets the
maximum fundamental and therefore bandwidth and reach; max interval sets what
clock recovery has to coast; disparity swing is the DC wander a transformer must
pass. Random payload, constant-0 worst case in brackets where it differs:

| code | levels | min int | max int | disparity swing |
|---|---|---|---|---|
| Manchester (biphase-L) | 2 | 0.50 | 1.00 | **1.0** |
| **differential Manchester** | **2** | **0.50** | **1.00** | **1.0** |
| **AMI** | **3** | **1.00** | 15 | **1.0** |
| CMI | 2 | 0.50 | 1.50 | **1.5** |
| Miller | 2 | **1.00** | **2.00** | 89 (3) |
| NRZI | 2 | **1.00** | 16 | 210 (28) |
| polar NRZ | 2 | 1.00 | 18 (15) | 854 (23001) |
| unipolar RZ | 2 | 0.50 | 15.5 | 8210 (2250) |
| unipolar NRZ | 2 | 1.00 | 18 (15) | 16420 (4500) |

**The disparity column decides the candidate set** before noise performance is
discussed at all. The pair is transformer coupled (`mf8-spec.md` §9) and a
transformer cannot pass unbounded DC wander:

- bounded, order one bit period — Manchester, **differential Manchester**, **AMI**, CMI → viable
- data-dependent, 5–500 bits — Miller, NRZI → out
- hundreds to tens of thousands — unipolar NRZ/RZ, polar NRZ → out

### 1.1 What that rules out, and what it nearly did not

**Miller (delay modulation) was the promising one.** It halves the bandwidth like
AMI *and* bounds its max interval at 2.0 bits, which would make clock recovery
nearly as cheap as differential Manchester — the best of both, on paper.
Measured, it swings **89 bit periods of disparity on random payload**, and its
excursion is payload-dependent rather than bounded. That is the classic Miller DC problem, and it is why Miller-squared
exists; the patch costs encoder state and is heuristic.

**NRZI** halves the bandwidth, is polarity-blind, and has its run length bounded
at 16 by the same framing bit that bounds AMI's (§2.1). It fails the same way:
210 bit periods on random payload. Both would need a DC-management layer — scrambling or block
coding — and scrambling is unattractive here — a self-synchronising scrambler locks up on
all-zero idle onsets, measured at ~2⁻⁷.

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
has already solved (§2.1). TRI-TAC ran this same codec over *conditioned diphase*, a biphase variant —
the closest field precedent, and it lands where this design already is.

**So the viable set is {differential Manchester, AMI}**, and the rest of this
document is those two.

---

## 2. AMI's three standard objections, and what happens to them

### 2.1 Zero runs — the frame already solved it

Worst run of zeros on the line, over all 64 hook states (`linecodes.py`):

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

Differential Manchester has a transition every cell, so `mf8-spec.md` §9.4's receiver
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

Error-free to 2%, broken at 3% — the 3.1% predicted. `mf8-spec.md` §9.4 says a 1%
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
`mf8-spec.md` §9.1 already specifies divides every family rate exactly — 4× / 8× /
16× / 32× / 64× for 1024 / 512 / 256 / 128 / 64 kbps. Sampling at 8× and running
an ordinary DPLL on the mark edges, on the worst payload:

| crystal offset | drift across the clip | bits emitted − sent | BER |
|---|---|---|---|
| 200 ppm | 9.6 bits | **0** | 0 |
| 1000 ppm | 48 bits | **0** | 0 |
| **5000 ppm** | **240 bits** | **0** | 0 |

**Does a local crystal reintroduce slips?** No, and that is the question that
matters, because `mf8-spec.md` §2 rests on *"no rate mismatch anywhere and slips are
structurally impossible."* The crystal is a **sampling** reference; the DPLL
recovers bit phase from the line, so the bit clock stays locked to the far
transmitter. The bit count is exact at every offset, including 5000 ppm where the
two clocks drift 240 bits apart. **The DPLL absorbs drift as phase, not as
bits.** Only a free-running local clock used as the *data* clock would slip.

**It is also not a loss of rate-blindness**, which is the obvious objection and
is wrong: the receiver already carries a per-rate plug (`mf8-spec.md` §9.7,
`mf8-spec.md` §9.4) for the input filter, classifier, dead time and carrier
detect. On that axis option C is an *improvement* — the per-rate change becomes a
counter tap, exact and digital, instead of matched RC values. Repeaters are
unaffected; they slice and re-drive and never see the frame.

**What AMI's clock costs is the receiver's clocklessness, and nothing else.**
`mf8-spec.md` §9.4 already prices that trade: the oversampling DPLL is the *reference*
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
the MF8 frame and its framer, both polarities lock, recover the
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
rail-limited driver, one cable, one noise floor, which is `frame-rate.md` §1's "same
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
and a 0.6× error costs about a factor of ten. This corroborates `mf8-spec.md` §9's
rejection of AMI and adds the mechanism: **AMI's loss is the amplitude decision,
not the bandwidth.** The AMI figures are generous, because the decoder estimates
its own peak from the data — free AGC a real receiver would have to build.

**Attenuation, and the cliff is the hysteresis spec.** Signal scaled; the sd 0.10
noise floor and the 0.05 comparator hysteresis both held fixed, so loss costs
real margin. (`mf8-spec.md` §9 notes the cable lowpass models dispersion, not loss,
which is why attenuation has to be applied separately.)

| atten | hysteresis, % of received | differential Manchester | AMI |
|---|---|---|---|
| 1.0 | 5% | 0 LOF | 0 LOF |
| 0.5 | **10% — `mf8-spec.md` §9.4 limit** | 0 LOF | 0 LOF |
| 0.25 | **20% — single-span max** | 0 LOF | 0 LOF |
| 0.12 | **42% — out of spec** | 237 LOF, 69.53% down | 22 LOF, 15.23% down |
| 0.06 | 83% | 100% down | 100% down |

**The measured cliff sits exactly where the hysteresis leaves its specified
range.** Error-free at 0.25, where hysteresis is 20% of received amplitude and
`mf8-spec.md` §9.4 allows 20% on a single span; collapsed at 0.12, where it is 42%
and the comparator stops responding to real transitions. So the attenuation limit
is **the comparator, not the noise floor** — the fix is smaller hysteresis or an
AGC stage, not more launch amplitude.

---

## 4. Impulse noise — the ranking reverses

`phy.plant_noise`: damped rings at 0.5–3× the transmitted peak, 15–80 kHz,
20–200 µs decay, Poisson arrivals, both polarities (§4.2). The full curve is §4.5;
the short version, from `impulse_sweep.py`:

| impulses/s | DM breaks/s | DM muted | AMI breaks/s | AMI muted |
|---|---|---|---|---|
| 1 | 0.78 | 0.06% | **0.13** | **0.01%** |
| 10 | 7.8 | 0.59% | **1.3** | **0.11%** |
| 100 | 68 | 5.3% | **13** | **1.1%** |
| 500 | 259 | 22.9% | **88** | **9.4%** |
| 800 | 341 | 33.3% | 173 | 29.6% |
| 900 | 359 | **36.4%** | — | **100% — never locks** |

**Through the whole working range AMI takes about a sixth of the breaks**, because
differential Manchester's impulse failures are bit-count slips and AMI's are
ordinary bit errors (§4.1). Past ~850/s that reverses: AMI collapses outright
while differential Manchester is still delivering two thirds of the time.

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

What an outage *is* matters more than how much time it takes. Every break is
short — **0.76 ms** for differential Manchester and 0.80 ms for AMI at low rate,
barely more at 500/s — so neither code spends much time muted until the rate is
very high. What climbs with impulse rate is the **number** of breaks, and each is
a click plus a CVSD decoder that has to recover (its syllabic filter is 6 ms, so
at tens of breaks a second it never settles).

`mf8_render.py` puts all six talkers through the chain for 15 s and writes what
the link delivers, muted where the framer is not locked. Per-channel segSNR is
scored only where the link was up; muting is counted separately, because the two
fail independently. The 15 s results are §4.6; from the 4 s verification pass:

| impulse/s | code | breaks | muted | ch1 segSNR |
|---|---|---|---|---|
| 10 | diff. Manchester | 34 | 0.68% | 22.4 dB |
| 10 | AMI | 3 | 0.07% | 23.5 dB |
| 100 | diff. Manchester | 280 | 8.0% | **6.4 dB** |
| 100 | AMI | 40 | 0.8% | **8.7 dB** |

At 10/s both codes are listenable and the difference is clicks — about eight a
second for differential Manchester against one. At 100/s both are badly degraded,
differential Manchester by constant decoder restarts and AMI by bit errors, and
AMI still wins on both columns.

**A correction.** An earlier render reported differential Manchester as 72% muted
at 100 impulses/s. It had discarded every locked run shorter than 31 ms, because
its alignment needed that many bits, and at 100/s most runs are shorter — so
locked time was counted as silence. The framer is up about 95% of that time; the
render now aligns runs down to 1 ms and agrees with it. An earlier version of this
section likewise scored only the longest unbroken stretch, which is what made
differential Manchester look like it had "no regime where it is merely noisy".
It does: at 10/s it is clicky but sound.

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
`linecodes.py`). Bits lost at 200/s, amplitude 1.5: 1622–1755 at 0.05, 1665–1820
at 0.25, 3789–4135 at 0.45. Flat, then worse. **Dead time rejects edges that
arrive too early; a stuck comparator removes edges**, so there is nothing for it
to reject.

**AMI's decision threshold does nothing either** — 0 breaks and 4.4–5.7e−03 raw
BER flat across 0.3 to 0.7. So neither code has a *tuning* answer to impulse
noise. The only measured answer is structural: AMI does not slip.

---

### 4.5 The falloff curve, measured precisely

`impulse_sweep.py`: 23 impulse rates from 0.3/s to 1000/s, both codes, several
independent 10 s runs per point — enough for ~200 impulses at the low rates, where
each one counts. Link layer only, on the chunked physical layer `mf8_render.py`
verified bit-identical against an unchunked reference. Full table and per-point
standard errors in `impulse_sweep.log` and `impulse_sweep.csv`.

**Thresholds**, interpolated on the measured points — no model. Per-point standard
errors are 5–10% relative, so these are good to two significant figures:

| link reaches | diff. Manchester | AMI | AMI ÷ DM |
|---|---|---|---|
| 1 break/s | 1.3 impulses/s | 7.3 | 5.6× |
| 10 breaks/s | 13 | 77 | 5.9× |
| 50 breaks/s | 71 | 320 | 4.5× |
| 0.1% muted | 1.7 | 9.4 | 5.4× |
| 1% muted | 18 | 95 | 5.3× |
| 5% muted | 95 | 340 | 3.6× |
| 10% muted | 200 | 515 | 2.6× |

**The two curves are different shapes, not one curve displaced**, so there is no
single "AMI is N× better":

- **Differential Manchester degrades smoothly.** Each impulse above the comparator
  threshold causes a slip — 0.77 per impulse at low rate — each slip costs
  ~0.76 ms, and outages add. An independent-outage model built from those two
  low-rate numbers, `muted = 1 − exp(−r / 1724)`, tracks the measurement to within
  10–15% all the way to 1000/s. Breaks per impulse falls slowly at high rate (0.68
  at 100/s, 0.37 at 1000/s) as one outage starts absorbing several impulses.
- **AMI holds, then collapses.** Breaks per impulse stays near 0.13 — a sixth of
  differential Manchester — and muting grows gently: 1% at 95/s, 9.4% at 500/s,
  29.6% at 800/s. At **900/s it never locks.** Its outages lengthen as it nears the
  edge (0.8 ms per break at low rate, 1.7 ms at 800/s), which is the warning. The
  same independent-outage model fits it badly and should not be used for it.

The likely mechanism for the collapse is F-bit errors reaching the `+2/−1`
counter's one-in-three trip point, beyond which no 32-frame acquisition succeeds.
That is a hypothesis consistent with the shape, not a measurement. What is
measured is where it happens: **between 800 and 900 impulses/s**, which is also
where the ranking reverses — at 800/s AMI is still muted less (29.6% against
33.3%), at 900/s it is muted completely.

**What this replaces.** Earlier versions of this document placed differential
Manchester's "cliff between 1 and 10 events/s" from four points and 1 s clips.
That was the right decade for where *breaks* start to become frequent — the link
reaches 1 break/s at 1.3 impulses/s and 10 breaks/s at 13 — but it was never a
cliff. Differential Manchester does not fall off anything; it accumulates clicks
in proportion to the impulse rate. The only cliff on this page is AMI's, and it
sits two orders of magnitude further out.

### 4.6 Rendered audio

`mf8_render.py`, 15 s, six independent talkers, the full duration as the link
delivers it. "muted" is time with no audio placed; segSNR is scored only where
the link was up. Clean is 26.1 / 21.1 dB on channels 1 and 4 in both codes.

| condition | DM breaks/s | DM muted | DM ch1 / ch4 | AMI breaks/s | AMI muted | AMI ch1 / ch4 |
|---|---|---|---|---|---|---|
| impulse 10/s | 9.3 | 0.71% | 18.2 / 16.0 dB | **2.0** | **0.17%** | **22.4 / 18.7 dB** |
| impulse 100/s | 71 | 8.9% | 5.3 / 4.9 dB | **13** | **1.1%** | **8.4 / 8.7 dB** |
| Gaussian sd 0.60 | 0.13 | 0.02% | **25.9 / 21.0 dB** | 5.2 | 0.54% | 3.3 / 2.8 dB |
| Gaussian sd 0.70 | 4.9 | 0.42% | **23.0 / 19.2 dB** | 28 | 5.3% | −1.7 / −1.8 dB |
| attenuation 0.12 | 441 | 86% | 2.5 / 2.4 dB | 54 | 62% | −1.5 / −1.5 dB |

The render agrees with the sweep where they overlap — at 100/s AMI is 1.10%
muted with 12.9 breaks/s against the sweep's 1.05% and 12.8. Differential
Manchester reads 8.9% muted against the sweep's 5.3% because runs shorter than
1 ms are not placed; that remainder is time the framer counts as up but that is
too short to carry audio.

Listen to `dm_imp10_ch1.wav` against `ami_imp10_ch1.wav` for the realistic case:
both sound like speech, and the difference is the ticking. At 100/s both are
poor, and AMI is still the better of the two on every column. Under Gaussian
noise the table flips entirely, which is §3 heard rather than measured.

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

**Keep differential Manchester**, which is `mf8-spec.md` §9's choice, and the reason
to cite is the **amplitude decision** — sd 0.6 against 0.4, plus the attenuation
behaviour — not the clock. Clocking splits: two wins (no clock hardware, and the
timing decision that produces the Gaussian margin) against one measured loss
(bit-count slips under impulse).

**Re-examine it if the plant is impulse-dominated.** §4 is not a small
correction: through the working range AMI takes about a sixth of the breaks
(§4.5), and §4.4 says no amount of receiver tuning closes that gap. If AMI is ever
taken off the file, §2 is the answer sheet — the zero run is bounded at 15 by the
frame, the clock comes off the 4.096 MHz crystal already on the board with 12×
margin, and polarity is free.

**The decision turns on one number nobody here has: the impulse rate on the
target loops.** The curve is now measured, so that number converts directly into
a break rate for each code: 1 break/s at 1.3 impulses/s for differential
Manchester and 7.3 for AMI, 10 breaks/s at 13 and 77 (§4.5). How many clicks a
second a voice circuit can carry is a judgement; how many a given loop will
produce no longer is. That is a counter on a real pair, and it is worth more than
any further simulation. It is
the same class of gap `frame-rate.md` §1 has on reach.

---

## 7. Reproducing

```
python3 linecodes.py codes      nine line codes on the frame, side by side
python3 linecodes.py clock      zero-run bound; AMI clock recovery, tank vs DPLL
python3 linecodes.py rxclock    does an AMI receiver need a local clock?
python3 linecodes.py polarity   tip/ring swap, both codes
python3 linecodes.py plant      Gaussian, impulse and attenuation, swept independently
python3 linecodes.py impulse    impulse threshold and mitigations
python3 impulse_sweep.py        the impulse falloff curve, 23 rates, both codes
python3 mf8_line.py             six talkers through the whole chain, both codes
python3 mf8_render.py           15 s of every channel to out/, for listening
```

How to read the numbers:

- §1 is measured for the structural columns; a code ruled out on disparity was
  not simulated, which is the point — it cannot cross the transformer whatever
  its noise performance.
- §§3–4 use 16 000-frame (0.25 s) clips × 4 seeds, and §4.3's audio is one 1.0 s
  clip, one talker, one seed per cell. §4.5 supersedes it for impulse noise:
  23 rates, 30–120 s per point, per-point standard errors. Read
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
  `linecodes.py`'s and `linecodes.py`'s values, so the rows are comparable with
  `mf8-spec.md` §9.3. Impulses are not scaled by attenuation, which is conservative.
