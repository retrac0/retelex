# The 7-channel variant — 16-bit frame

> **Superseded in part by `spec.md` (2026-09-16).** The N = 7 measurements stand.
> The crystal (16.384 MHz → 4.096 MHz strappable), the framing header (static
> `(0,1)` → S = 0, T = `1110`) and the acquisition count (64 → 32) have changed;
> see spec §3, §4 and §7.

An exploration, not a committed design. The question is whether `N = 7` is a
real member of the family or only an arithmetic one, and what it costs.

Every number here was measured by `n7.py` on the same chain `validate.py` runs,
against the 3-channel build as the control. Where a figure is analysis rather
than simulation it says so.

---

## 1. Summary

**It works, and it costs almost nothing in logic.** The 16-bit frame is not a
new design — it is the same design with one more counter tap. Every structural
property the 3-channel build relies on survives unchanged, and the audio is
transparent to within 0.14 dB.

**What it costs is reach: ~1.2 km against ~1.7 km, and that is the whole
trade.** Doubling the line rate doubles the fundamental, and on 24 AWG in the
skin-effect region attenuation goes as √f.

| | N = 3 (committed) | N = 7 |
|---|---|---|
| Frame | 8 bits | 16 bits |
| Line rate | 256 kbps | **512 kbps** |
| Symbol rate | 512 kbaud | **1.024 Mbaud** |
| Oscillator | 8.192 MHz | **16.384 MHz** |
| Crystal-to-frame | ÷256 = 2⁸ | **÷512 = 2⁹** |
| Cell / half-cell | 3.91 µs / 1.95 µs | **1.95 µs / 977 ns** |
| TX packages | ~6 | **7–8** |
| RX signalling demux | 1 × 74HC259 (5 spare) | **1 × 74HC259 (1 spare)** |
| Channels per pair | 3 | **7** |
| Estimated reach | order 1.7 km | **order 1.2 km** |

Channels per pair go up 2.33×; reach goes down to 71%. Whether that is a good
trade is a plant question, not a design question.

---

## 2. What does not change

This is the important half of the result. The following were re-measured at
N = 7 and are **identical to the 3-channel build**, not merely acceptable:

**The interleaving rule generalises exactly.**

```
count: 0    1    2    3    4    5    6    7    8    9   10   11   12   13   14   15
      [A1][ C1][A2][ C2][A3][ C3][A4][ C4][A5][ C5][A6][ C6][A7][ C7][ S ][ T ]
                                                                        0    1
```

Sixteen bits, payload at counts 0–13, framing at 14–15. That frame has 15 wrong
alignments and zero adjacent-static pairs, the same as the 8-bit frame's 7. The
reason is structural, not luck: the receiver's S and T check positions are
adjacent, so at any offset one of them lands on an *odd* frame index — and odd
indices are always CVSD bits. Every wrong alignment is therefore gated by a
random bit, at any N.

Enumerated exhaustively for N = 7: 13 of the 15 wrong alignments are gated by a
CVSD bit, and the remaining two — offsets of 1 and 15, where the check straddles
the S/T pair itself — fail *deterministically* on every frame rather than half
of them, which is better still. No alignment is ungated.

- Lock to the true phase at all 16 skews, bit-exact channel recovery: **yes**.
- Grouped-ordering control false-locks on **13 of 16** skews, so the test has
  teeth at N = 7 exactly as it does at N = 3.

**Acquisition time does not change.** 1.97–2.56 ms at N = 7 against
1.97–2.50 ms at N = 3. The frame has twice as many wrong phases to search, but
the line runs twice as fast, and the two cancel. Acquisition costs ~2–2.6 ms
whatever the channel count — worth knowing, because the naive expectation is
that it doubles. It takes twice as many bit slips to get there (0–15 rather
than 0–7), but each slip is half as long.

**The loss-of-frame policy still covers every slip size.** All 15 of them:

| policy | worst detection, N = 3 | worst detection, N = 7 |
|---|---|---|
| **+2/−1 trip 12** | **0.81 ms** | **0.94 ms** |
| 16 consecutive bad | never recovered | never recovered |

("Never recovered" is the 3000 ms clip length — the link was still misaligned
when the measurement ran out, at both channel counts.)

Zero false reframes at 1e-3, 1e-2 and 3e-2 BER. The consecutive policy fails on
every even slip at N = 7 just as it does at N = 3 — there are simply seven ways
to get it wrong now instead of three. Crosstalk after a 2-bit slip: **0.53 ms
and correlation 0.051 with the up/down counter, 1500 ms and 0.471 with the
consecutive policy.**

**Signalling is unchanged.** Zero spurious assertions on an idle channel at
every BER to 6e-2, with the other six channels off-hook. Longest run of
erroneous A bits at 6e-2 is 0.125 ms against the ~1.7 ms the RC needs.

**The receiver's timing window is unchanged in relative terms:** 0.60–0.85 of a
cell, **±13% about 0.75**, measured at the same sd = 0.4 design limit. In
absolute terms the monostable becomes **1465 ns ±195 ns** instead of
2930 ns ±391 ns. Still an ordinary 74HC123 RC, and the ±3% achievable with a 1%
resistor and a 2% C0G capacitor still clears it with the same room to spare.

**Noise margin is unchanged in relative terms**, when the cable bandwidth is
scaled with the symbol rate. The absolute figure was first measured as
error-free to sd = 0.6 on 3 s of the original material; the 30 s seven-talker
run (§4.3) is error-free to **sd = 0.5** and fails at 0.6. Thirty seconds gives
the link six times as many chances to hit a bad patch, so **sd = 0.5 is the
figure to specify against** and the earlier 0.6 was undersampled, not wrong. **Squelch still holds:** the
framer never locks on a noise-only line at any sd tested, and the sd = 0.05
pathology that makes squelch mandatory is present and identical (mean run of 1s
= 1343 bits, recovered bit rate 0.02× nominal).

---

## 3. The counter identities survive

This was the thing most likely to break, and it does not. The transmitter's two
identities (`line-transmitter.md` §2) are not special to a 3-bit counter — they
hold for **any power-of-two frame**:

```
payload mux address = frame counter taps, directly, no offset
S/T select          = AND of every counter bit above the LSB
line bit when selected = the counter LSB    -> S=0 at count 14, T=1 at count 15
```

A literal hardware model — free-running binary counter, mux addressed by taps,
S/T decoded from the top — was checked bit-for-bit against `link.build()` at
N = 1, 3 and 7. **All three match exactly.** The generalisation is why the
family exists at all: the framing bits being last is what makes the address
offset zero, at every N.

### 3.1 Clock chain

Still one 74HC4040, still every tap binary:

| tap | divide | signal |
|---|---|---|
| Q4 | ÷16 | **1.024 MHz** half-bit clock |
| Q5 | ÷32 | **512 kHz** line bit clock — this is `H` |
| Q6…Q9 | ÷64…÷512 | mod-16 frame counter, Q6 = LSB |
| Q9 | ÷512 | 32 kHz frame clock → channel cards |

Q9 of 12 available. No decoded modulus, no sync-clear gate, mod-16 wraps
naturally on four binary stages — exactly the argument made for mod-8.

**Ripple caveat, slightly worse.** One more stage of ripple (Q1→Q9, ~110 ns)
into a settling budget that has halved to ~1 µs. Still 11% of a half-cell and
still benign, but it has gone from "ignore it" to "scope it during bring-up."

### 3.2 Package count

| function | N = 3 | N = 7 |
|---|---|---|
| All timing | 74HC4040 | 74HC4040 |
| Payload mux | 74HC151 (6 of 8 used) | **2 × 74HC151**, output selected by Q9 |
| S/T select | `Q8·Q7`, 2-input | **`Q9·Q8·Q7`, 3-input** |
| Everything else | unchanged | unchanged |

**One extra package on the transmitter, possibly two.** The two '151s hold
counts 0–7 and 8–15; Q9 selects between them through a second section of the
74HC157 that is already on the card for the S/T override, since that part is a
quad. No 16-to-1 device is needed and none should be used — the 74HC150 is a
24-pin obsolete part.

The second package is the question mark. The select term widens from `Q8·Q7` to
`Q9·Q8·Q7`, and whether that fits depends on what is left in the 74HC00 that
also forms the biphase NAND. Building a 3-input AND from 2-input NAND gates
costs four of the four available, which leaves nothing for the encoder. Swap the
'00 for a 74HC10 (triple 3-input NAND) plus an inverter, or add a 74HC11 and
keep the '00 — either way, budget **7–8 packages against the 3-channel build's
~6**, and settle it on the schematic rather than here.

### 3.3 N = 7 is the size that fits the parts

The 74HC259 addressable latch is 8 outputs. At N = 3 five of them are wasted; at
N = 7 exactly one is spare, and the 3-bit latch address is the same three
counter taps. **The receive demux package count is identical at N = 3 and
N = 7** — the 3-channel build is paying for an 8-channel part and using three
of it.

---

## 4. Audio

Absolute segmental SNR is set by the source clip, not the carrier, so the
measurement that means something is what the 512 kbps line **adds** to the
codec running on its own:

| ch | codec alone | over the 7-channel link | delta |
|---|---|---|---|
| 1 | 18.81 dB | 18.82 dB | +0.01 |
| 2 | 19.77 dB | 20.01 dB | +0.24 |
| 3 | 17.95 dB | 17.82 dB | −0.13 |
| 4 | 18.82 dB | 18.68 dB | −0.14 |
| 5 | 17.13 dB | 17.25 dB | +0.13 |
| 6 | 18.82 dB | 18.79 dB | −0.03 |
| 7 | 10.78 dB | 10.72 dB | −0.05 |

**Worst degradation attributable to the carrier: −0.14 dB.** The ±0.2 dB
scatter is segmental-SNR measurement noise, not channel-position effect.

Channel 7's 10.7 dB is **not** a 7-channel effect — that extract has a crest
factor of 17 and codes at 10.78 dB with no link in the path at all. It is a
level problem in the test clip, and it is left in the table deliberately,
because it is the one row that shows the carrier is transparent even to a
source the codec is already struggling with.

Degradation with line errors matches the 3-channel table row for row:

| line BER | segSNR | loss-of-frame events |
|---|---|---|
| 0 | 18.85 dB | 0 |
| 1e-4 | 18.44 dB | 0 |
| 1e-3 | 13.65 dB | 0 |
| 1e-2 | 4.50 dB | 0 |

### 4.1 Isolation — superseded, and how it was wrong

**This section originally reported off-diagonal ≤ 0.111 against a source floor
of ≤ 0.110. Both numbers were inflated about 4× by the estimator, and the test
material has since been replaced. The corrected measurement is in §4.2.**

Two separate problems, worth recording because both are easy to repeat:

**The test material.** Only four speech extracts existed, so channels 5–7
reused the speakers of 1–3 at a different offset. The sources themselves
correlated, so the raw off-diagonal could not be read against zero.

**The estimator.** The matrix was built by calling `audio.align()` separately
for every (i, j) pair. On the diagonal that finds the channel's real delay. Off
the diagonal it *maximises* correlation over ~8192 candidate lags before
measuring it, and two unrelated speech signals cannot come out at zero under
that treatment. A channel has one delay, so the lag must be found once per
recovered channel and then applied across the whole row.

Measured on a run whose BER was identically zero — where carrier crosstalk is
zero by construction, so everything reported is estimator plus source floor:

| estimator | off-diagonal max | source floor | excess |
|---|---|---|---|
| re-aligned per pair | 0.0721 | 0.0700 | 0.0021 |
| **single lag per channel** | **0.0175** | **0.0143** | **0.0032** |

The original conclusion — no measurable crosstalk — survives, because the floor
was computed with the same inflated estimator and the *excess* was always
small. Only the absolute numbers were wrong.

### 4.2 Isolation, measured properly

Seven independent LibriSpeech talkers (`talkers.py`), 30 s each, single-lag
estimator (`seven.py`):

| | value |
|---|---|
| source-correlation floor | **0.0088** (was 0.110 with the 4-file set) |
| off-diagonal, through the link, sd ≤ 0.5 | **0.018** |
| excess over the source floor | **0.009** |
| diagonal (wanted signal) | ≥ 0.95 |

The off-diagonal is **identical at sd = 0.0, 0.2, 0.4 and 0.5** — as it must be,
because the BER is identically zero at all four and the recovered bits are the
same bits. It rises only once the link starts making errors (0.021 at sd = 0.6,
0.028 at sd = 0.7), which is slot rotation after a slip, not steady-state
leakage.

The stronger statement is structural rather than statistical: **at every noise
level where the link is error-free the recovered bits are bit-identical to the
transmitted bits, so carrier crosstalk is exactly zero, not merely small.** The
only way channels can leak into each other is a slot rotation after an
undetected bit slip, which is what §2's loss-of-frame measurement covers. An
isolation matrix measured on an error-free link can only ever report its own
noise floor.

### 4.3 Noise resistance, seven talkers, 30 s

Three 10 s segments, OS = 32, cable fc 1.8 MHz, all seven channels in parallel
through the full chain (`seven.py sweep`):

| noise sd | peak SNR | worst BER | mean BER | segSNR min | segSNR mean | LOF | isolation |
|---|---|---|---|---|---|---|---|
| 0.0 | — | 0 | 0 | 11.72 | 15.94 | 0 | 0.018 |
| 0.2 | 14.0 dB | 0 | 0 | 11.72 | 15.94 | 0 | 0.018 |
| 0.4 | 8.0 dB | 0 | 0 | 11.72 | 15.94 | 0 | 0.018 |
| **0.5** | **6.0 dB** | **0** | **0** | **11.72** | **15.94** | **0** | **0.018** |
| 0.6 | 4.4 dB | 6.2e-1 | 3.2e-1 | 0.80 | 4.17 | 6 | 0.021 |
| 0.7 | 3.1 dB | 5.2e-1 | 4.6e-1 | −0.83 | −0.36 | 122 | 0.028 |

**The edge is a cliff, not a slope.** Between sd = 0.5 and 0.6 the link goes
from bit-exact to a 32% mean BER. There is no usable operating point in
between, which matches the README's "biphase is perfect until it isn't" — and
it is the argument for the squelch of §8: a link at sd = 0.6 is not a degraded
link, it is a broken one that must be muted rather than passed through.

Per-channel segSNR on a clean line:

| ch1 | ch2 | ch3 | ch4 | ch5 | ch6 | ch7 |
|---|---|---|---|---|---|---|
| 18.85 | 11.92 | 19.29 | 15.46 | 11.97 | 17.67 | 16.46 |

The 7.4 dB spread is **entirely the talkers**, not the slots: it tracks crest
factor, and the same spread appears with the codec running alone and no link in
the path. The figures are identical at every sd from 0.0 to 0.5, which is the
same error-free statement made a second way.

---

## 5. What it actually costs

### 5.1 Cable bandwidth — exactly 2×, no penalty

Both builds are error-free from **0.12 × symbol rate**: 60 kHz at N = 3,
125 kHz at N = 7. The requirement scales linearly with rate and nothing extra
appears at the higher rate.

Note how low both numbers are, and do not over-read them. Differential
Manchester with a monostable receiver decides on zero-crossing *timing*, not
amplitude, so a bandwidth-limited-but-loud signal still decodes. **The
first-order lowpass in the model is not a cable** — it captures dispersion and
not attenuation. This is consistent with the spec's existing finding that the
limit is attenuation rather than dispersion, which is the good case, but it
means the bandwidth sweep cannot be used to predict reach.

### 5.2 Reach — analysis, not simulation

In the skin-effect region attenuation goes as √f, so doubling the fundamental
from 128 kHz to 256 kHz costs √2 in dB/km and therefore 1/√2 in distance for
the same loss budget:

> **~1.2 km against the 3-channel build's order 1.7 km — 71%.**

Both figures need a bench measurement on real plant before anyone relies on
them. The ratio is more trustworthy than either absolute.

### 5.3 The output stage gets tighter

150 ns edges were specified for the 3-channel build, which is 7.7% of its
1.95 µs half-cell. At N = 7 the half-cell is 977 ns and the same edge is
**15.4%** of it. Still inside the eye, but the EMI-versus-eye trade that was
comfortable is now a real choice: keep 150 ns and accept a visibly softer eye,
or tighten to ~75 ns and give back some of the radiated-emissions benefit.

Transformer droop scales the right way, at least — running disparity is bounded
at ±1 cell, and the cell has halved to 1.95 µs, so the 10 mH specified for the
3-channel build is now twice the margin it needs to be.

---

## 6. Where this leaves the family

| N | frame | line rate | symbol rate | oscillator | half-cell | '259s per bit type |
|---|---|---|---|---|---|---|
| 1 | 4 | 128 kbps | 256 kbaud | 4.096 MHz | 3906 ns | 1 |
| **3** | **8** | **256 kbps** | **512 kbaud** | **8.192 MHz** | **1953 ns** | **1** |
| **7** | **16** | **512 kbps** | **1.024 Mbaud** | **16.384 MHz** | **977 ns** | **1** |
| 15 | 32 | 1024 kbps | 2.048 Mbaud | 32.768 MHz | 488 ns | 2 |

**N = 7 is the top of the family in practice.** N = 15 is not a logic-speed
limit — 74HC is good to 25–50 MHz at 5 V and the divider chain stays binary —
but 2.048 Mbaud into outside plant with a 488 ns half-cell is a different
transmission problem, the '259 stops holding the signalling bits in one
package, and reach would fall to about 0.85 km. If a 15-channel system is ever
wanted, it wants a different line code, not a longer frame.

---

## 7. Recommendation

**Build N = 3 as specified; treat N = 7 as a drop-in rate option, not a
redesign.**

Nothing in the 3-channel design forecloses it. Concretely, doing these three
things now costs nothing and keeps the door open:

1. **Footprint the second 74HC151 on the TX card**, route Q9 to a spare '157
   section, and form the S/T select from a 3-input gate wired as 2-input at
   N = 3 rather than from the '00. Unpopulated parts cost a footprint.
2. **Lay out the backplane for seven channel slots**, not three. The frame
   generalises for free; the backplane does not.
3. **Use a 74HC123 RC for the monostable that can be re-valued**, not a trimmed
   one-off. The threshold stays at 0.75 cell; only the absolute value halves.

The one decision that must be made now rather than later is the **backplane
slot count**, because everything else is a component change on an existing card
and that is not.

---

## 8. Reproducing

```
python3 n7.py all        # everything below, ~4 min
python3 n7.py link       # frame, acquisition, loss of frame, signalling
python3 n7.py phy        # cable bandwidth, noise margin, monostable window
python3 n7.py audio      # segSNR, isolation, crosstalk, squelch
python3 n7.py hw         # counter identities, clock chain, package count
```

Caveats that affect how the numbers should be read:

- Link-layer sections use 6 s clips; PHY and audio sections use 3 s, because
  the N = 7 waveform at OS = 32 is 16.384 MHz — the real master clock — and
  memory binds before anything else does.
- Seven sources come from four files (§4.1). Absolute isolation needs seven
  independent talkers.
- The cable is a first-order lowpass. It models dispersion, not attenuation,
  so §5.1 is not a reach measurement and §5.2 is analysis.
