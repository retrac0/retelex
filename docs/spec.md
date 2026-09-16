# Digital voice carrier — system specification

4-channel CVSD voice carrier over twisted pair, built in discrete 74HC logic.

Every number in this document was measured in the simulation in this repository
rather than assumed. Where a figure comes from a specific experiment, the
module is named.

---

## 1. Architecture

**Two independent one-way systems.** Two pairs, one per direction. Each
direction is timed end to end by the transmitting end's oscillator: the far
end's CVSD decoders are clocked by the clock recovered from that same
oscillator. No data ever crosses between directions, so there is **no rate
mismatch anywhere and slips are structurally impossible**. There is no master/
slave strap and no loop timing.

```
End A                                  End B
[TX card] ──────── pair 1 ──────────> [RX card]
[RX card] <─────── pair 2 ─────────── [TX card]
```

Consequences worth stating plainly:

- Two board designs, not one. Identical TX cards at both ends, identical RX
  cards at both ends.
- Each direction can be brought up and faulted independently.
- Crystal tolerance between ends is irrelevant. A ±100 ppm offset appears only
  as a 0.17-cent pitch shift in the recovered audio, which is inaudible.

**Per end:** one TX card, one RX card, up to four channel cards, one backplane.

---

## 2. Frame

```
count:  0     1     2     3     4     5     6     7     8     9
      [ A1 ][ C1 ][ A2 ][ C2 ][ A3 ][ C3 ][ A4 ][ C4 ][ S ][ T ]
                                                        0     1

  An  channel n signalling bit          Cn  channel n CVSD bit
  S   start bit, always 0               T   stop bit, always 1
```

Ten bits. Payload occupies counts 0–7, framing counts 8–9.

### 2.1 The interleaving rule — a constraint, not a preference

**Signalling and voice bits must alternate. No two adjacent interior bit
positions may both be static.**

Start/stop framing works by checking that one position is always 0 and another
always 1. At a wrong alignment of *k* bits the receiver reads frame bit *k* as
its start and bit *k−1* as its stop, so **every candidate alignment tests one
adjacent pair of interior bits**. The alternation guarantees each such pair
contains a CVSD bit, which is effectively random, so every wrong alignment is
rejected within a few frames.

Group the signalling bits together instead — `[C1..C4][A1..A4][S][T]` — and the
pair `(An, An+1)` is two static bits. A channel on-hook next to one off-hook is
an ordinary operating state, and it holds that false alignment **indefinitely**.
This was measured, not argued: the grouped ordering false-locked on every
non-zero start-up skew, and the decoded output was digital silence because the
false alignment feeds the constant S and T bits to the codecs.

### 2.2 Scaling

The frame generalises to `2 + 2N` bits for N channels. The alternation rule is
satisfied automatically at any N.

| N | frame | line rate | symbol rate | oscillator |
|---|---|---|---|---|
| 1 | 4 | 128 kbps | 256 kbaud | 1.024 MHz |
| 2 | 6 | 192 kbps | 384 kbaud | 1.536 MHz |
| 3 | 8 | 256 kbps | 512 kbaud | 2.048 MHz |
| **4** | **10** | **320 kbps** | **640 kbaud** | **2.56 MHz** |

Build the frame for the maximum channel count and leave unequipped slots idle;
idle slots need pull resistors, not logic. Populating a slot is the only
configuration step.

---

## 3. Rates and clocking

```
2.56 MHz  ──÷4──>  640 kHz   half-bit clock (biphase transitions)
          ──÷2──>  320 kHz   line bit clock
          ──÷10──>  32 kHz   frame clock  ==  CVSD clock, all channels
```

- CVSD rate **32 kbps per channel**. The frame clock *is* the codec clock, so
  channel bit spacing is exactly one frame period with zero jitter and no
  buffering anywhere.
- Only the oscillator and the first divider run above 640 kHz.

**Oscillator accuracy is not critical.** The receiver classifies intervals
against an RC and tolerates a ±13% window at high noise (§5.2), so the
transmitter never needs crystal accuracy — a ceramic resonator at ±0.5% is
ample. Specify a crystal anyway for unit-to-unit repeatability. 2.56 MHz needs
a sourcing check; 5.12 and 10.24 MHz are clean fallbacks (÷8, ÷16).

---

## 4. Line code — differential Manchester

- Transition at **every** cell boundary. This is the clock.
- Additional transition at mid-cell **iff** the data bit is 0.

Properties that matter:

| property | consequence |
|---|---|
| Two-level, always ±V, never zero | Full amplitude every symbol; threshold sits midway, so noise margin is the full V |
| Decision is same-vs-different half-cells | **No threshold to set and no AGC.** Cable loss and driver amplitude are irrelevant |
| Polarity-blind | Tip and ring may be swapped with no effect. Verified bit-identical |
| DC-free, disparity bounded at ±1 cell | Transformer coupling works with no coding effort |
| Guaranteed transition every bit | Clock recovery never starves regardless of data |

AMI was evaluated and rejected. It halves the symbol rate, which is real, but
it needs a three-level driver and a slicer threshold that tracks received
amplitude — measured to fail at 0.6× gain error, where biphase has no threshold
at all. Keep AMI on file as the reach extension if a future span becomes
bandwidth-limited rather than attenuation-limited.

---

## 5. Receiver

### 5.1 Monostable interval classifier

No PLL, no oversampling, no clock on the receive timing path.

Inter-transition intervals are either `T/2` or `T`:

- a **1** bit (no mid-cell transition) produces one **full-cell** interval
- a **0** bit produces **two half-cell** intervals

One retriggerable monostable set to ~0.75 cell classifies each interval; a
state flip-flop tracks boundary versus mid-cell. **The state self-heals**: any
full-cell interval forces it back to the boundary state, and roughly half of
all bits are 1, so a disturbed state recovers within a couple of bits. There is
no lock to lose.

### 5.2 Timing tolerance

| condition | usable threshold window | margin about 0.75 |
|---|---|---|
| clean | 0.52 – 0.98 | ±31% |
| moderate noise | 0.60 – 0.90 | ±20% |
| high noise | 0.65 – 0.85 | **±13%** |

The ±13% figure must absorb RC tolerance, tempco, and the far end's oscillator
error combined. The oscillator contributes ~0.01% and is negligible. Use C0G/
NP0 for the timing capacitor; the resistor then dominates and 1% parts leave
large margin.

### 5.3 Measured performance versus alternatives

At 4 channels, all three receiver architectures were measured on identical
waveforms:

| receiver | board clock | performance |
|---|---|---|
| oversampling DPLL | 10.24 MHz | reference |
| analog PLL (4046) | 1.28 MHz | equal to reference |
| **monostable** | **none** | within 3× of reference at the noise edge, identical elsewhere |

Under synthetic impulse noise the monostable was *better* than the analog PLL,
because its errors are confined to the impulse while a PLL smears the
disturbance over its loop time constant. Note this was AWGN plus synthetic
impulses; real plant behaviour is a bench measurement.

---

## 6. Framer

```
good frame  :=  (bit at count 8 == 0)  AND  (bit at count 9 == 1)

acquisition :  64 consecutive good frames to declare lock
on bad frame:  slip ONE line bit, restart the count
loss of frame: saturating up/down error counter,
               +2 on a bad frame, −1 on a good frame, trip at 12
```

### 6.1 Why loss of frame is not "N consecutive bad frames"

This is the most important detail in the framer and the easiest to get wrong.

Acquisition and loss-of-frame have **opposite statistical requirements**, and
using the same "consecutive" logic for both is a defect. The interleaving rule
(§2.1) guarantees every wrong alignment is gated by a CVSD bit, so a misaligned
frame fails only ~50% of the time. That is ideal for acquisition, which needs
64 *consecutive good*. It is useless for loss of frame, which would need N
*consecutive bad* — and a 50%-failing misalignment essentially never produces
16 of those.

Measured detection time after a bit slip, by slip size:

| policy | 1 | 2 | 3 | 4 | 5 | 6 | 7 | false reframes @1e-2 / 3e-2 |
|---|---|---|---|---|---|---|---|---|
| 16 consecutive bad | 0.44 | **558** | 0.44 | **285** | 0.44 | **4000** | 0.44 | 0 / 0 |
| **+2/−1 trip 12** | 0.12 | **0.84** | 0.12 | **0.59** | 0.12 | **0.19** | 0.12 | **0 / 0** |

(milliseconds). With the consecutive policy a 6-bit slip **never recovers**.

Even-numbered slips are the dangerous ones: they rotate the channel slots *and*
land the S/T check on an `(A, C)` pair. Crosstalk after a 2-bit slip: **558 ms
with the consecutive policy, 0.84 ms with the up/down counter**, with the
cross-correlation to the neighbouring channel's audio falling from 0.254 to
0.042 (the noise floor).

### 6.2 Hardware form

`+2/−1 trip 12` is equivalent to `+1 up per bad frame, −1 per two good frames,
trip at 6`: a 74HC193 up/down counter, one toggle flip-flop dividing the
good-frame clock, trip decoded on `Q2·Q1`, borrow output inhibiting underflow.

---

## 7. Signalling

**One bit per channel per direction.** A = 1 means active.

For E&M this is an exact fit and not an approximation: E&M is a two-lead
interface with one lead driven outward (M) and one sensed (E), so one bit each
way carries seizure, answer, disconnect, dial pulses, and wink/delay-start
protocols — all of which are encoded in *timing* rather than in bit
combinations.

Loop start also fits (ring control one way, loop closure the other). **Ground
start does not** — it needs two independent conditions per end, and the frame
cannot carry a second static bit per channel without violating §2.1. If ground
start is ever required the framer must change, not just the frame.

### 7.1 Integration

Received A bit → RC, τ = 2 ms → 74HC14 Schmitt. One resistor, one capacitor,
one gate per channel. This is both the error filter and the contact debounce.

Measured, with channel 1 idle throughout:

| line BER | erroneous A bits received | longest raw run | **spurious assertions after RC** |
|---|---|---|---|
| 1e-3 | 236 | 0.031 ms | **0** |
| 1e-2 | 2581 | 0.062 ms | **0** |
| 3e-2 | 7568 | 0.125 ms | **0** |
| 6e-2 | 14650 | 0.125 ms | **0** |

Zero false assertions at any tested error rate. The margin is structural: the
longest run of erroneous bits at 6% BER is 0.125 ms against the ~1.7 ms of
sustained assertion needed to cross the Schmitt threshold.

Dial pulse fidelity (10 pps, 40/60 ms): **78 of 78 pulses recovered at every
BER up to 3e-2**, make time 60.10 ms against 60 ms nominal, 0.16% ratio error,
standard deviation ≤0.09 ms. Essentially independent of line quality.

Signalling is the most robust part of the system by a wide margin, and the
cheapest.

---

## 8. Failure behaviour

| event | response |
|---|---|
| Loss of frame | Mute all channel audio outputs; force all received A bits to idle; the 74HC259 clear pin does this in one wire |
| Loss of signal / no transitions | Squelch. **Required, not optional** — both line codes fail as a cliff rather than a slope, so an unmuted receiver below threshold emits full-scale hash rather than quiet noise |
| Unequipped slot | Idle pattern in, A bit pulled to idle |

---

## 9. Verified audio performance

Segmental SNR, real speech, clean line:

| CVSD rate | speech | band-limited music |
|---|---|---|
| 16 kbps | 10.8 dB | 8.1 dB |
| **32 kbps** | **17.9 dB** | 10.8 dB |
| 64 kbps | 24.0 dB | 16.1 dB |

Roughly 6–7 dB per doubling, with no knee — every doubling costs the same in
line rate and buys the same in quality.

Degradation with line errors (32 kbps, 4 channels):

| line BER | segSNR | loss-of-frame events |
|---|---|---|
| 0 | 18.8 dB | 0 |
| 1e-4 | 18.3 dB | 0 |
| 1e-3 | 13.9 dB | 0 |
| 1e-2 | 4.5 dB | 0 |

**The framer outlives the audio.** Zero loss-of-frame events at every rate the
link can acquire at. Design target: **1e-4 for full quality, 1e-3 as the usable
floor.** Acquisition, not tracking, sets the ceiling — a cold start needs 64
consecutive clean frames, so acquisition becomes unreliable above a few percent
BER while tracking continues far beyond.

Channel isolation on a clean line, three distinct talkers: diagonal correlation
0.981 / 0.989 / 0.993, off-diagonal ≤0.030.

---

## 10. Reach and power

Fundamental 320 kHz. Expect order 1.5 km on 24 AWG before attenuation binds;
**measure it rather than trust that figure.** The bandwidth sweep suggests the
limit is attenuation, not dispersion, which is the good case — attenuation is
fixable with gain.

Line power over the pair is **provisioned, not populated**: centre-tapped line
transformers with the DC feed path and protection laid out, both ends locally
powered for the first build. DC injected at the centre taps is common-mode
while the signal is differential, and the feed current splits equally between
the two winding halves so the ampere-turns cancel and the transformer sees no
net DC flux. Two-pair loop resistance on 24 AWG is ~26 Ω/kft.

When populated: ringing generation is the item that will strain the budget, not
the transmission terminal. The E&M card does not generate ringing, so this is
deferred until the FXS card exists.
