# Line repeater

One board. Both directions on it. Any number of them in a row.

Every number below was measured by `repeater.py`, which cascades spans through
the same chain `validate.py` uses — CVSD, frame, differential Manchester, cable,
noise, monostable receiver, framer — at the hardware master clock, 8.192 MHz.
`sd` is the per-span noise standard deviation referred to the launched peak, the
same quantity as spec §6.2, so a figure here and a figure there mean the same
impairment. The single-span design limit is **sd = 0.4** and a single span is
error-free to 0.6; the harness reproduces both.

Measured at the 256 kbps line rate on the previous framing header. The repeater
never sees the frame, so the S4 header of spec §3 changes nothing here; the
other line rates of spec §2 change the transformer and the crosstalk budget
(below), not the circuit.

---

## 1. The decision

**Slice and re-drive. No clock, no crystal, no framer, no retiming — no decision
of any kind on the board.**

The repeater is the receive front end of the RX card bolted straight to the
output stage of the TX card, with nothing in between. It introduces no circuit
block that has not already been designed and measured elsewhere in this system.

### 1.1 The candidates

| | what it does | clock on the board |
|---|---|---|
| **amplify** | linear gain, no slicer | none |
| **regenerate** | comparator → driver. Amplitude restored, edge position not | none |
| **retime** | regenerate, then re-place the mid-cell edge from a one-shot | none (RC only) |
| *reclock* | *decode to bits, re-encode from a local oscillator* | *crystal* |

The fourth was never a candidate; §1.6 says why. The other three were built in
the simulation and run on identical waveforms.

### 1.2 Amplification loses to regeneration by a factor of two, not by orders of magnitude

This one did not come out the way the textbook says, so it is worth being
precise about.

**Bandwidth is not what kills an amplified chain.** With no noise at all, 33
cascaded cable sections — an effective bandwidth far below the symbol rate —
still decode bit-exact, because the crossings move almost not at all:

| spans | short mean | short sd | long mean |
|---|---|---|---|
| 1 | 0.5000 | 0.0003 | 1.0000 |
| 2 | 0.5000 | 0.0005 | 1.0000 |
| 9 | 0.5000 | 0.0007 | 1.0000 |
| 33 | 0.4913 | 0.0140 | 1.0223 |

That is spec §5's "no threshold to set" earning its keep: a DC-free signal
through a symmetric lowpass loses amplitude long before it loses the position of
its zero crossings, and amplitude is not what the receiver decides on.

**Noise is what kills it, and it accumulates as √spans.** Largest per-span sd at
which an amplified chain is error-free, against a single-span edge of 0.6:

| spans | amplify: error-free to sd | `0.6/√spans` | regenerate: error-free to sd | ratio |
|---|---|---|---|---|
| 1 | 0.60 | 0.60 | 0.60 | 1.0 |
| 2 | 0.40 | 0.42 | 0.55 | 1.4 |
| 3 | 0.35 | 0.35 | 0.50 | 1.4 |
| 5 | 0.25 | 0.27 | 0.35 | 1.4 |
| 9 | 0.20 | 0.20 | 0.225 | 1.1 |
| 17 | 0.10 | 0.15 | 0.15–0.20 | 1.5–2 |
| 33 | <0.10 | 0.10 | 0.15 | >1.5 |

The amplifier tracks `0.6/√spans` to within a grid step everywhere. And the
regenerator — which strips the noise off the waveform completely at every stage —
is only about **1.4× better in per-span noise, i.e. 3 dB**, or a factor of two in
span count at fixed noise. It is not more, because §1.4's jitter exponent is 0.41
against the amplifier's 0.50, and those are nearly the same law.

(Single seed, 0.5 s per point, so the edge cells wobble by a grid step: 17 spans
regenerated gives 4e-03 at sd 0.175 and exactly zero at 0.20. Read the column,
not the cell.)

**A slicer does not remove the effect of noise; it freezes it.** Amplitude noise
that has already displaced an edge is captured by the comparator and re-emitted
as a clean edge in the wrong place, and no later stage can recover it. What the
regenerator wins is the difference between 0.50 and 0.41 — about a factor of two
in span count at a given per-span noise, worth having, but not the unbounded
advantage the phrase "regeneration prevents accumulation" suggests.

The case for regenerating is therefore mostly **not** this table. It is that the
amplifier in that table is *ideal* — perfect gain, set from a noiseless
reference, at every one of 32 unattended sites — while the regenerator has no
gain to set, no equaliser to match, no level to hold, and no AGC to drift. It
restores amplitude, ISI (§1.3), DC balance and polarity (§5.3) exactly, it is one
package (§2.2), and it happens to be twice as good as well.

### 1.3 Deterministic distortion does not accumulate

This was the surprise, and it is why the cheap option wins.

With no noise at all, cascade a regenerator 32 times and the interval
distribution at the far end is **identical to one span**:

| spans | short mean | short sd | short max | long mean | long sd | long min |
|---|---|---|---|---|---|---|
| 1 | 0.5000 | 0.0002 | 0.594 | 1.0000 | 0.0000 | 1.000 |
| 2 | 0.5000 | 0.0003 | 0.625 | 1.0000 | 0.0000 | 1.000 |
| 3 | 0.5000 | 0.0003 | 0.625 | 1.0000 | 0.0000 | 1.000 |
| 5 | 0.5000 | 0.0003 | 0.625 | 1.0000 | 0.0000 | 1.000 |
| 9 | 0.5000 | 0.0003 | 0.625 | 1.0000 | 0.0000 | 1.000 |
| 17 | 0.5000 | 0.0003 | 0.625 | 1.0000 | 0.0000 | 1.000 |
| 33 | 0.5000 | 0.0003 | 0.625 | 1.0000 | 0.0000 | 1.000 |

(In cells: a half-cell interval is 0.5, a full cell 1.0, and the terminal
classifies against 0.75.) The chain decodes bit-exact at every N.

Cable ISI displaces each edge by an amount that depends only on the recent edge
pattern. A regenerator re-squares the waveform, so the *next* span applies the
same displacement to the same pattern — the map has a fixed point, the chain
lands on it after the first span, and stays there. **Pulse-width distortion does
not grow with the number of repeaters**, so the entire class of worry that
motivates retiming does not apply here.

Checked at 32, 64 and 128 samples per cell to make sure this was not the
simulation grid flattering the result. All three agree.

### 1.4 What accumulates is jitter, and it grows as N^0.41

Each span's noise displaces edges, the slicer makes that displacement permanent,
and the next span adds its own. Intervals at the far terminal, sd = 0.4/span:

| spans | short mean | short sd | short max | long mean | long sd | long min |
|---|---|---|---|---|---|---|
| 1 | 0.5000 | **0.0248** | 0.594 | 1.0000 | 0.0251 | 0.875 |
| 2 | 0.5000 | 0.0349 | 0.656 | 1.0001 | 0.0354 | 0.875 |
| 3 | 0.5000 | 0.0424 | 0.688 | 1.0001 | 0.0433 | 0.812 |
| 5 | 0.5000 | 0.0539 | **0.719** | 0.9999 | 0.0556 | **0.750** |
| 9 | 0.5002 | 0.0695 | 0.719 | 0.9986 | 0.0744 | 0.750 |
| 17 | 0.5000 | 0.0878 | 0.719 | 0.9931 | 0.1030 | 0.750 |
| 33 | 0.4983 | **0.1037** | 0.719 | 0.9829 | 0.1389 | 0.750 |

At sd = 0.3 the same sweep runs 0.0194 → 0.0877 over the same range.

Three things to read off it:

- **The growth exponent is 0.41, not 0.5.** Fitting σ ∝ spans^a gives 0.409 at
  sd = 0.4 and 0.431 at sd = 0.3. Independent noise alone would give 0.5; the ISI
  fixed point of §1.3 is attracting, so it pulls displaced edges partway back and
  the accumulation comes out slightly sub-root-N. Do not plan on this. It is why
  the measured chain outlives the arithmetic.
- **Read the max/min columns, not the sd.** The decision needs each interval to
  stay on its own side of 0.75, i.e. within ±0.25 cell. By 5 spans the worst
  short interval seen in half a second is 0.719 and the worst long interval is
  0.750 — the tail has already reached the threshold while the BER is still
  exactly zero.
- **Jitter is the only thing the repeater count buys you.** Everything else —
  amplitude, ISI, DC balance, polarity — is restored at every stage.

### 1.5 Retiming buys nothing measurable, and costs three packages

Same waveforms, with a retiming stage in every repeater (interval classifier,
one flip-flop, a half-cell one-shot):

| per-span sd | repeater | N=4 | N=8 | N=16 | N=32 |
|---|---|---|---|---|---|
| 0.2 | regenerate | 0 | 0 | 0 | 1.9e-01 (18) |
| 0.2 | retime | 0 | 0 | 0 | 2.5e-01 (24) |
| 0.3 | regenerate | 0 | 2.0e-02 (4) | 3.4e-01 (29) | 4.5e-01 (29) |
| 0.3 | retime | 0 | 1.7e-02 (3) | 3.2e-01 (27) | 4.6e-01 (28) |
| 0.4 | regenerate | 1.6e-03 (1) | 2.0e-01 (22) | 4.4e-01 (28) | no lock |
| 0.4 | retime | 1.6e-03 (1) | 2.3e-01 (20) | 4.5e-01 (29) | no lock |

Indistinguishable. Where the two differ they differ in both directions, which is
the signature of measurement noise rather than of an effect. Retiming costs about
three extra packages per direction — six per board, against the two the whole
regenerator needs — and returns nothing.

**The reason is structural: a regenerator makes no timing decision, and a
retimer makes one per span.** The regenerated chain carries interval *lengths*
forward, and the only circuit that ever judges half-cell against full-cell is the
terminal's monostable: one decision, at the one place with the full margin. Put a
classifier in every repeater and there are N+1 decisions, each with its own RC
tolerance, and each irreversible — a misjudged interval is re-emitted downstream
as a clean, confident, wrong interval that no later stage can question.

Retiming is the right answer when pulse-width distortion accumulates. §1.3
measured that here it does not.

(If it is ever populated anyway, the one-shot's RC wants to be on the short side:
at 5 spans and sd 0.4, −16% to +8% of a half cell all give 1.6–2.1e-03, while
+16% gives 9.0e-02. Asymmetric, because a one-shot that is too long can outrun a
jittered short cell.)

### 1.6 Why the repeater must not have a crystal

Decoding to bits and re-encoding from a local oscillator is the textbook
regenerative repeater. Here it would destroy the property the system is built on.

Each direction is timed end to end by the transmitting terminal's oscillator, so
there is no rate mismatch anywhere and slips are structurally impossible
(spec §1). A repeater with its own oscillator is a **timing boundary**: incoming
rate is the far terminal's crystal, outgoing rate is the repeater's, and the
difference has to go somewhere — an elastic store, stuffing, and a slip whenever
the store runs dry. Every repeater added would be another slip source, and
spec §7.4 measures what a slip costs: even-numbered slips rotate the channel
slots and cross-connect the audio until the framer catches them.

It is also the only version of the repeater that would need to know the line
rate, the frame length and the channel count. The chosen repeater knows none of
those, which is why it can be staged arbitrarily and why spec §4's remark that
the line rate can be moved to suit the crystal stays true with repeaters in the
route.

### 1.7 How many can be staged

Largest per-span noise the chain survives, measured on a 0.5 s stream (128 k
line bits), against the prediction of the jitter law below:

| repeaters | spans | error-free to sd | ≤1e-4 (spec §11's full-quality target) | law: 0.6·spans^−0.41 |
|---|---|---|---|---|
| 0 | 1 | 0.60 | 0.65 | 0.60 |
| 1 | 2 | 0.55 | 0.55 | 0.45 |
| 2 | 3 | 0.50 | 0.50 | 0.38 |
| **4** | **5** | **0.35** | 0.35 | 0.31 |
| **8** | **9** | **0.225** | **0.25** | 0.25 |
| 16 | 17 | 0.15–0.20 | 0.20 | 0.19 |
| 32 | 33 | 0.15 | 0.15 | 0.15 |

The `@1e-4`, `@1e-3` and `@1e-2` thresholds fall within one grid step of each
other at every N: the degradation is a cliff, not a slope, which is the same
behaviour spec §5 records for biphase generally. There is no "slightly degraded"
region to lean on — either the route is clean or it is reframing.

The same limit in the terminal receiver's own currency — the usable monostable
threshold window of spec §6.2, which has to absorb RC tolerance, tempco and
everything else:

| repeaters | spans | window at sd 0.3 | window at sd 0.4 |
|---|---|---|---|
| 0 | 1 | ±20% | ±13% |
| 1 | 2 | ±13% | ±13% |
| 2 | 3 | ±7% | ±7% |
| 4 | 5 | ±7% | ±7% |
| 8 | 9 | ±7% | none |
| 16 | 17 | none | none |

The N = 0 row reproduces spec §6.2 exactly at both noise levels (±20% at sd 0.3,
±13% at sd 0.4), so the degradation below it can be read at face value.

The terminal's RC is specified at ±3% worst case from a 1% resistor and a 2%
C0G capacitor, so ±7% is still twice what the components need — but it is half
of what the spec asks for, and §1.4 shows the interval tail is already touching
0.75 there. The staging rules:

- **Up to 2 repeaters (3 spans) with spans engineered to the existing single-span
  design limit, sd = 0.4.** Nothing in the terminal changes.
- **Up to 8 repeaters (9 spans) if the spans are held to sd ≤ 0.25**, i.e. about
  4 dB better SNR per span than a single-span link needs.
- **Beyond that, re-engineer the spans rather than adding repeaters.** Shorter
  spans, a front-end equaliser (§2.5) or a quieter route all buy more than
  another regenerator does: the noise a route tolerates falls as `spans^−0.41`,
  so margin per span is cheaper than stages.

**The design law is one line.** The terminal's jitter budget is fixed at ±0.25
cell; accumulated jitter is `sd × spans^0.41` (§1.4); so the per-span noise a
route can tolerate falls as `spans^−0.41`. The table above shows that prediction
landing on the measurement from nine spans upward, and running conservative
below that. Halving the per-span noise buys about five times the span count —
which is the whole case for regeneration, and also the whole warning about it.

---

## 2. The board

### 2.1 Block diagram

Two identical unidirectional regenerators, back to back, sharing nothing but
power and the card:

```
 WEST                                                                    EAST

 pair 1 ─ protect ─ xfmr ─ term ─→ [preamp/eq] ─→ comparator ─→ slew ─→ driver ─ Rs ─ xfmr ─ protect ─ pair 1
                      │                              │                               │
                 (centre tap)                  carrier detect                   (centre tap)
                      │                         (74HC123) ──→ driver enable + LED
                      │                                                              │
                      └──────────────── DC feed path, both pairs ────────────────────┘
                      │                                                              │
 pair 2 ─ protect ─ xfmr ─ Rs ─ driver ←─ slew ←─ comparator ←─ [preamp/eq] ←─ term ─ xfmr ─ protect ─ pair 2
```

Direction A→B enters West and leaves East; direction B→A enters East and leaves
West. Nothing crosses between them. Beyond the two comparators and the
carrier-detect monostable there is no logic on the card at all — no gate, no
flip-flop, no counter, no oscillator, and nothing that knows what a frame is.

### 2.2 One package per direction

The comparator is a differential line receiver and the output stage is a
differential line driver, and those are one part: a **75179-type driver/receiver
pair**, which brings the driver outputs and the receiver inputs out on separate
pins.

The 75176 used on the TX and RX cards will **not** do this job alone: it is a
half-duplex transceiver, so its driver and receiver share the same A/B bus pins,
and at a repeater they face different pairs. Three ways out, in order of
increasing sense:

| | packages for both directions | note |
|---|---|---|
| 2 × 75176 per direction | 4 | keeps the whole system on one transceiver part number, half of each wasted |
| 75179-type pair | 2 | the natural fit |
| 26LS32 quad receiver + 26LS31 quad driver | 2 | lowest count, two spare channels |

Confirm threshold, hysteresis and pinout against the specific part before layout:
§2.4 shows the hysteresis figure matters and the sensitivity figure sets span
length.

### 2.3 Why one board serves both directions, with no strap

Because the two directions are independent one-way systems (spec §1), the two
halves of this board have nothing to agree about — no master/slave choice, no
shared timing, no framing to align, no data path between them. The board is
symmetric, so either connector can face either terminal.

And there is nothing to configure per unit:

- **No line rate.** No oscillator and no bit-rate-dependent *active* element on
  the card. Change the rate strap at the terminals and every repeater on the route
  is still correct, untouched. The line transformers are rate-dependent: specify
  the same ≥ 33 mH part as the terminal (spec §12), which covers 64 kbps upward.
- **No channel count.** The card never sees the frame.
- **No polarity.** Differential Manchester decides same-versus-different
  half-cells, so tip and ring may be swapped at any repeater on any span.
  Measured in §5.3.
- **No position in the route.** Repeater 1 and repeater 8 are the same board with
  the same settings.

The only per-site choice is how much gain the front end needs, and that is a
populate-or-not decision on the equaliser footprint (§2.5).

### 2.4 Comparator hysteresis: keep the ratio small

Line BER at sd 0.25 per span against the comparator's hysteresis, as a fraction
of the received amplitude:

| hysteresis | 3 spans | 5 spans | 9 spans | 17 spans |
|---|---|---|---|---|
| 0.02 | 0 | 0 | 0 | 1.9e-02 |
| **0.05** | 0 | 0 | 8.3e-06 | 6.0e-02 |
| 0.10 | 0 | 0 | 0 | 3.4e-01 |
| 0.20 | 0 | 0 | 5.5e-04 | 3.6e-01 |
| 0.30 | 0 | 0 | 2.9e-03 | 4.9e-02 |

Short chains do not care at all. Long ones do, and the 0.30 row's apparent
recovery at 17 spans is single-seed noise on a route that has already failed —
read the trend, not the individual cells. **Anything up to 10% is free; 20% and
beyond costs an order of magnitude by nine spans.**

Hysteresis is pulse-width distortion. It delays every crossing by `h/slope`, and
because the slope differs between a fully settled edge and one starting from a
half-settled level, the two delays do not cancel across an interval. Short chains
do not care; long chains do, because the loss comes out of the same ±0.25-cell
budget that §1.4 is already eating.

**The rule is on the ratio, not the millivolts.** A line receiver's hysteresis is
fixed in millivolts — around 50 mV for a 75176-class part — so the ratio is set
by how much signal reaches it. 10% wants 0.5 V at the comparator and 5% wants
1 V, so **specify a volt at the comparator input**, and treat that, not the
datasheet sensitivity, as what the front end has to deliver.

The terminal's monostable already rejects anything shorter than a quarter cell
(spec §6.1), so the usual argument for generous hysteresis — glitch immunity — is
covered downstream. Take the noise immunity in amplitude, not in hysteresis.

### 2.5 Span loss and the equaliser footprint

Two separate limits, routinely confused:

**Sensitivity**, from the parts, not the simulator. A 75176-class receiver
switches at ±200 mV. A 5 V driver through 2 × 50 Ω into a 100 Ω line launches
roughly 2 V differential once the driver's own loaded drop is allowed for, so a
bare line receiver runs out somewhere around 20 dB of span loss on paper — and
nearer 6 dB in practice, because §2.4 wants a volt at the comparator, not
200 mV.

**Noise.** Measured, with the comparator's hysteresis fixed at 5% of the
*launched* level so that span loss eats hysteresis margin the way it really does,
and a small noise floor (sd 0.05) at the far end of every span:

| gain | span loss | 2 spans | 9 spans |
|---|---|---|---|
| 1.00 | 0 dB | 0 | 0 |
| 0.50 | 6 dB | 0 | 0 |
| 0.25 | 12 dB | 0 | 5.5e-04 |
| 0.15 | 16.5 dB | 0 | 1.1e-01 |
| 0.10 | 20 dB | 7.9e-02 | no lock |
| 0.07 | 23 dB | no lock | no lock |

There is no "loss limit" in the line code itself — spec §5 removed the threshold
and the AGC — so loss costs only received SNR and hysteresis ratio, both of which
are already measured. The 12 dB row is the check: it leaves the comparator seeing
sd 0.2 of noise and 20% of hysteresis, and it returns 5.5e-04 at nine spans,
which is the same number §2.4's table gives for h = 0.20 at nine spans. The two
limits are the same limit, and the rule is one line: **deliver about a volt to
the comparator and the span is as long as the noise allows.**

**So put a preamp and equaliser footprint on the card, ahead of the comparator.**
A stage of gain, optionally with a first-order zero to lift the top of the band,
converts the sensitivity limit back into a noise limit; unpopulated, the card
still works on short spans. It needs no AGC and no level setting, because there
is no threshold to track — only enough gain not to be hysteresis-limited, and no
more, since gain lifts the crosstalk of §3.3 along with the signal.

Spec §10's bandwidth sweep found the single-span limit to be attenuation rather
than dispersion. That is the good case, and it is the case a preamp fixes.

### 2.6 Output stage

Identical to the TX card (line-transmitter §5), for the same reasons:

- two series resistors of ~50 Ω, trimmed against the actual cable
- slew limiting to ~150 ns edges — at 1.95 µs per half-cell that is well inside
  the eye and materially quieter on radiated emissions
- 1:1 transformer, centre-tapped on the line side, ≥10 mH primary so the ±1 cell
  of running disparity droops under 5%
- gas tube on both conductors, series PTC or fuse, TVS clamping **above the
  eventual feed voltage** (§4), not above signal level

A repeater has four line ports where a terminal has one, so it carries four of
these networks. That, not the active parts, is most of the board.

Both receive sides need the line terminated in its characteristic impedance. A
repeater must never look like a bridged tap.

---

## 3. Carrier detect, squelch and finding the bad span

### 3.1 The terminal's squelch survives regeneration

A repeater re-squares whatever it is given, so a dead span with induction on it
arrives at the *next* span at full amplitude rather than as a whisper. Since
spec §10.1 identifies quiet noise on a dead pair as the dangerous case, this had
to be checked rather than assumed. Noise-only input, regenerated N times:

| repeaters | line noise | bits recovered | fraction 1s | mean interval (cells) | terminal framer |
|---|---|---|---|---|---|
| 1 | sd 0.05 | 3146 | 0.998 | 23.7 | never locks |
| 1 | sd 0.2 | 63837 | 0.559 | 0.62 | never locks |
| 1 | sd 1.0 | 74860 | 0.363 | 0.45 | never locks |
| 4 | sd 0.05 | 3146 | 0.999 | 23.7 | never locks |
| 4 | sd 0.2 | 62929 | 0.570 | 0.67 | never locks |
| 4 | sd 1.0 | 71141 | 0.432 | 0.54 | never locks |

The quiet-noise case behaves exactly as spec §10.1 describes — sparse transitions,
enormous intervals, a solid run of 1s — and regenerating it four times changes
nothing. **The not-locked mute of spec §10.2 remains a valid squelch with
repeaters in the route.** No new failure mode, and nothing to add at the
terminal.

### 3.2 Squelch at the repeater is for maintenance, not for safety

The terminal is already safe, so the reason to put carrier detect on the repeater
is different: **without it, a route with eight repeaters gives you no way to find
which span is broken.** A regenerator downstream of a fault emits a
healthy-looking full-amplitude signal, so every repeater after the break looks
alive.

One retriggerable monostable per direction — a 74HC123 covers both — watching the
comparator output:

- retriggered by every transition; the line code guarantees one every cell
  (3.9 µs), so a ~100 µs timeout is 25 cells of silence and cannot false trip
- on timeout, pull the outgoing driver's enable low, so the next span goes quiet
  instead of carrying regenerated hash
- and light an LED

The fault rule is then the one that has always worked on repeatered routes:
**walk the line until the lights go out; the fault is in the span before the
first dark repeater.** One package per board buys that.

**Loopback** is worth laying out and not populating: a relay per direction
connecting the regenerated output of one direction into the input of the other,
so a terminal can test the route as far as that repeater. Commanding it by
reversing the polarity of the DC feed (§4) needs no extra pair and no signalling
channel. For the first build a pair of jumpers does the same job with a site
visit.

### 3.3 Near-end crosstalk is the impairment that is worse at a repeater

At a terminal the local transmitter and the local receiver both sit at the end of
their spans. At a repeater the outgoing driver of one direction sits at **full
launch level** a few centimetres from the incoming receiver of the other, which
is a whole span down. Measured, with an independent biphase aggressor
capacitively coupled into the receiver input, quoted as rms relative to the
wanted signal's launched peak:

| NEXT/signal | rejection | 1 span | 2 spans | 5 spans | 9 spans |
|---|---|---|---|---|---|
| 0.00 | — | 0 | 0 | 0 | 0 |
| 0.10 | 20 dB | 0 | 0 | 0 | 5.1e-03 |
| 0.20 | 14 dB | 0 | 0 | 2.1e-02 | 3.7e-01 |
| 0.30 | 10 dB | 0 | 0 | 3.9e-01 | 4.6e-01 |
| 0.40 | 8 dB | 0 | 4.1e-03 | 4.5e-01 | no lock |
| 0.50 | 6 dB | 0 | 3.8e-01 | no lock | no lock |

(with sd 0.2 per span; with no other noise the chain survives one step further at
every N.) **Budget 20 dB of rejection at the receiver input, more on a long
route** — and that is 20 dB *relative to the wanted signal*, so the requirement on
the plant is `20 dB + span loss` of coupling loss between the two directions'
pairs at 512 kHz. On a 16 dB span that is 36 dB. At the 512 kbps and 1024 kbps
line rates, NEXT loss falls about 4.5 dB per octave, so budget roughly 24.5 dB
and 29 dB plus span loss — textbook scaling, not simulated (spec §12).

Which is the real reason the two directions belong in separate binder groups, or
separate cables. On the card it means keeping the drivers away from the receiver
inputs, guarding those inputs, and not putting more gain in front of the
comparator than §2.5 needs — gain lifts the crosstalk too.

---

## 4. Power

Repeaters sit where there is no mains. The card is laid out for a simplex feed
from the terminals for exactly the reason spec §12 gives for the TX card's centre
tap: **retrofitting it means new transformers.**

### 4.1 Budget

Driving 5 V across 2 × 50 Ω of series resistance into a 100 Ω line is of order
20 mA per direction, and biphase always switches, so that is continuous rather
than average. With ordinary 75176/75179-class parts at ~30 mA quiescent the board
draws roughly **110 mA at 5 V, 550 mW** — more than a conventional 60 mA feed
loop can deliver, so the first thing to fix is the parts, not the feed:

| | per board |
|---|---|
| 75176/75179-class, 50 Ω series | ~110 mA, 550 mW |
| low-power pin-compatible driver/receiver, 220 Ω series | ~25 mA, 125 mW |

But raising the series resistors to ~220 Ω drops the launched level to about
0.9 V, and §2.4 wants a volt at the far end of the span, not at the near end. So
on a line-powered route **the preamp of §2.5 stops being optional** — the power
saved in the driver is spent again in the front end, at much lower current.
Feed power against span length is a real trade, and one to make deliberately
rather than by picking a resistor.

### 4.2 Feed arrangement

Constant-current loop, out on one pair's simplex and back on the other's, through
every repeater in series — the arrangement spec §12 already provisions at the
terminals. DC injected at a centre tap is common-mode against a differential
signal, and the feed current splits equally between the winding halves so the
ampere-turns cancel and the transformer sees no net DC flux.

At 60 mA, with each repeater shunt-regulating ~5 V out of the loop and 1.5 km
spans of 24 AWG at spec §12's ~26 Ω/kft two-pair loop resistance:

```
  per repeater      5 V
  per span          60 mA x 128 ohm  =  7.7 V
  8 repeaters       8 x 5  +  9 x 7.7  =  109 V
```

within reach of a single-ended feed, and comfortable if both terminals feed half
the route. Three consequences:

- **Each repeater must pass the full loop current** whatever it consumes, so the
  local supply is a shunt regulator, not a series one.
- **Take the power off both pairs' simplex paths through a bridge.** Then feed
  polarity and card orientation are both irrelevant and §2.3's "no strap"
  property survives contact with the power feed.
- **The loop current is the continuity test.** A feed still in regulation proves
  every repeater is in circuit; a feed sitting at its compliance voltage says the
  route is open, before anyone walks it.

**Safety:** a mid-route card floats at up to ~100 V with respect to earth. The
TVS clamps on all four line ports must sit above the feed voltage rather than
above signal level (line-transmitter §5), the enclosure must be bonded, and the
card must be treated as live whenever the feed is up.

For the first build, power the repeaters locally and leave the feed path
unpopulated — the same staging spec §12 chose for the terminals.

---

## 5. Staging

### 5.1 What the repeater has to know

Nothing. No oscillator, no framer, no channel count, no line-rate dependency, no
threshold, no polarity convention. That is what makes "stage an arbitrary number
of them" true rather than aspirational, and it follows directly from §1: the
moment a repeater reclocks, frames, or sets a threshold, it acquires a
configuration, and a configuration is a thing that can be wrong at one site out
of eight.

### 5.2 Transparency, measured

Real speech through the whole chain, at sd 0.2 per span — comfortably inside
§1.7's budget for this length:

| repeaters | spans | line BER | LOF events | segmental SNR |
|---|---|---|---|---|
| 0 | 1 | 0 | 0 | 18.67 dB |
| 1 | 2 | 0 | 0 | 18.67 dB |
| 2 | 3 | 0 | 0 | 18.67 dB |
| 4 | 5 | 0 | 0 | 18.67 dB |
| 8 | 9 | 0 | 0 | 18.67 dB |

At sd 0.3, which §1.7 says is one step too much for nine spans:

| repeaters | spans | line BER | LOF events | segmental SNR |
|---|---|---|---|---|
| 0 | 1 | 0 | 0 | 18.67 dB |
| 1 | 2 | 0 | 0 | 18.67 dB |
| 2 | 3 | 0 | 0 | 18.67 dB |
| 4 | 5 | 0 | 0 | 18.67 dB |
| 8 | 9 | 9.8e-03 | 9 | **1.03 dB** |

A clean regenerated chain delivers *the same bits*, so it delivers the same
audio, to two decimal places. Compare spec §11's 19.06 dB single-span figure from
`validate.py` on a longer clip. **A repeater is not an audio impairment; it is a
bit-error source, and until it makes errors it does not exist.** When it does
start making them, §1.7's cliff means the audio goes from unchanged to reframing
with almost nothing in between.

### 5.3 Polarity at a repeater

Tip and ring swapped on any combination of spans, 4 repeaters, sd 0.3:

| spans reversed | line BER | framer locks | LOF events |
|---|---|---|---|
| none | 0 | yes | 0 |
| span 1 | 0 | yes | 0 |
| span 2 | 0 | yes | 0 |
| spans 1 and 3 | 0 | yes | 0 |

Bit-exact in every case. Installers cannot get this wrong, which on a route with
eight splice points is worth more than it sounds.

### 5.4 Plant impulse noise

Switching transients, relay operation, induction — damped ringing of 0.5 to 3×
the signal peak, Poisson arrivals, **an independent burst train on every span**,
which is what a long route actually buys you. Line BER with loss-of-frame events
in brackets, sd 0.1 of Gaussian noise underneath:

| events/s/span | 1 span | 2 | 3 | 5 | 9 |
|---|---|---|---|---|---|
| 0 | 0 (0) | 0 (0) | 0 (0) | 0 (0) | 0 (0) |
| 5 | 0 (0) | 4.8e-02 (1) | 4.9e-02 (2) | 1.7e-01 (4) | 2.0e-01 (11) |
| 20 | 1.3e-01 (7) | 1.5e-01 (12) | 1.6e-01 (15) | 2.4e-01 (22) | 2.7e-01 (37) |
| 50 | 1.8e-01 (10) | 2.3e-01 (25) | 2.4e-01 (29) | 2.9e-01 (47) | 3.4e-01 (69) |

**Loss-of-frame events grow in proportion to the number of spans, and an
amplifying chain measures the same** (12 versus 11 events at nine spans and
5/s). This is the one impairment regeneration does nothing about, and the reason
is the same as §1.2's: an impulse does its damage where it lands, the slicer
turns that damage into clean wrong bits, and the errors from each span simply
add.

So a repeatered route multiplies exposure to plant transients in proportion to
its length. That is an argument about the route — where it runs, what shares its
binder, how well it is bonded — not about the repeater, and no repeater design
changes it. Spec §5.3's finding still holds underneath: the monostable confines
impulse damage to the impulse, where a PLL would smear it over its loop time
constant, and a chain of regenerators inherits that because it has no loop
either.

### 5.5 Adding one to a live route

Cutting the pair to insert a repeater is a loss of signal: the terminal squelches
within about 0.2 ms (spec §10.2) and re-acquires after 32 good frames (spec §7.2)
once the span is restored. Nothing else in the system notices, nothing is
re-strapped, and the other direction is unaffected if only one pair is opened.

Latency added per repeater is comparator and filter delay — well under one bit
cell, against cable propagation of microseconds per kilometre. Not worth
counting. (Another small advantage of not retiming: a retiming stage cannot
re-emit a cell until it has seen the whole cell, so it costs a full cell of delay
per repeater by construction.)

---

## 6. Package count

| function | parts |
|---|---|
| Regenerator, A→B | 75179-type driver/receiver pair (or 2 × 75176) |
| Regenerator, B→A | same |
| Front-end gain / equaliser, per direction | one op-amp section each — populate per span |
| Carrier detect, output squelch, LED, both directions | 74HC123 |
| Shunt regulator for the simplex feed | TL431 + pass device — unpopulated in the first build |
| Line transformers | 4 × 1:1, centre-tapped |
| Protection | 4 × gas tube / PTC / TVS |

**About three active packages**, and two of those are the regenerator itself. The
card is overwhelmingly line interface: four transformers and four protection
networks against three ICs.

There is no crystal, no counter and no flip-flop on the card, and the only
timing element is a monostable whose entire job is to notice silence. That is
worth restating, because it is §1's whole argument expressed as a BOM.

---

## 7. Bring-up

1. **One repeater on the bench, short cables.** Terminal TX → repeater → terminal
   RX must be bit-identical to the direct connection. Anything else is a wiring
   error, not a margin problem.
2. **Scope the comparator output and measure the interval histogram**, not the
   amplitude. Half-cell against full-cell against a 0.75-cell threshold is what
   the terminal actually decides, and the spread of that histogram is the only
   quantity that accumulates (§1.4). A time-interval analyser, or a scope with
   interval histogram, gives numbers directly comparable to §1.4's table.
3. **Add cable until the comparator sees about a volt**, and call that the span
   (§2.4). Do not extend to where it stops working — that point is a cliff, and
   the operating point must sit well back from it.
4. **Two repeaters, then four,** re-measuring the histogram at each step. Expect
   the spread to grow as spans^0.41 and the BER to stay at exactly zero. **BER is
   a useless bring-up instrument here**, because §1.7 shows it is zero right up
   until the route falls over. The histogram is the early warning; the BER is the
   funeral.
5. **Break a span deliberately.** The downstream repeater's carrier detect must
   drop within ~100 µs, its driver must squelch, and the terminal must mute rather
   than pass hash (spec §10.2). Restore it and confirm re-acquisition.
6. **Measure crosstalk between the two directions** at the repeater housing with
   both directions live, against §3.3's 20 dB. This is the measurement most
   likely to disagree with the simulation, and the most expensive to discover
   late.
7. **Only then the DC feed**, with TVS ratings checked against the feed voltage
   first, and the card treated as live.

---

## 8. Not settled

- **Span length.** Spec §10's caution applies with more force here: the reach
  figure is an estimate, and on a repeatered route the error multiplies. Measure
  one span on the real cable before deciding how many repeaters a route needs.
- **Crosstalk in the real plant.** §3.3's aggressor is synthetic. The binder-group
  arrangement is a plant decision that must be made before the route is built and
  is far harder to fix afterwards than anything on this card.
- **The low-power transceiver.** §4.1's budget assumes a part that has not been
  chosen; its hysteresis in millivolts feeds straight back into §2.4.
- **Equaliser shape.** Whether a first-order zero is worth populating depends on
  measured loss against frequency, which needs the cable rather than the
  simulator.
- **Impulse behaviour on a long chain.** §5.4 covers the rates modelled by
  `phy.plant_noise`; real plant transients are a bench measurement, as spec §6.3
  already says for the single-span case.
