# Frame rate — what the 8-bit superframe carrier should run at

> **The question looks like a hard trade and mostly is not.** In this frame the
> frame rate *is* the per-channel rate and the line rate is 8× it, so one knob
> appears to set audio quality, capacity and reach at once. It is less
> constrained than that, because frame *length* is a second knob that trades
> against it at constant reach. **64 kbps channels are available at any reach** —
> two of them at 1.00× reference, six at 0.71×. What distance costs is channel
> count, not rate.
>
> Measured by `linecodes.py`; `linecodes.log` is the run. `line-codes.md` is the
> line-code half of the same question, and `mf8-spec.md` the design that adopts
> the conclusion.

---

## 1. The family

F + S + N channels must be a power of two, so **N = 2, 6, 14**.

| frame | N | per-ch | line | baud | capacity | reach | superframe |
|---|---|---|---|---|---|---|---|
| 4 b | 2 | 16k | 64k | 0.128 M | 32k | **2.00×** | 4 fr |
| 4 b | 2 | 32k | 128k | 0.256 M | 64k | 1.41× | 4 fr |
| 4 b | 2 | **64k** | 256k | 0.512 M | 128k | **1.00×** | 4 fr |
| 8 b | 6 | 16k | 128k | 0.256 M | 96k | 1.41× | 8 fr |
| 8 b | 6 | 32k | 256k | 0.512 M | 192k | **1.00×** | 8 fr |
| **8 b** | **6** | **64k** | **512k** | **1.024 M** | **384k** | 0.71× | **8 fr** |
| 16 b | 14 | 16k | 256k | 0.512 M | 224k | **1.00×** | 16 fr |
| 16 b | 14 | 32k | 512k | 1.024 M | 448k | 0.71× | 16 fr |
| 16 b | 14 | 64k | 1024k | 2.048 M | 896k | 0.50× | 16 fr |

The exchange uses the **8-bit / six-channel** row at 64 kbps on a 512 kbps
line (`mf8-spec.md` §2). Eight- and ten-bit frames were measured and not
taken (`mf8-unit.md`). Octet alignment is the 8-state superframe counter.

Reach is the √f law scaled to a 256 kbps reference — the ratios
are sound, the kilometres are not measured.

**Read it by column, not by row.** "64 kHz or 32 kHz" is the wrong question,
because the line rate is what sets reach and the frame length decides how that
line is divided:

| at 256 kbps — 1.00× reach, order 1.7 km | at 512 kbps — 0.71×, order 1.2 km |
|---|---|
| 4-bit @ 64 kHz → **2 ch × 64 kbps** (DS0) | 8-bit @ 64 kHz → **6 ch × 64 kbps** (DS0) |
| 8-bit @ 32 kHz → 6 ch × 32 kbps | 16-bit @ 32 kHz → 14 ch × 32 kbps |
| 16-bit @ 16 kHz → 14 ch × 16 kbps | |

---

## 2. What the per-channel rate costs the audio

CVSD alone, 2 s clip, one talker:

| per-channel | segSNR | vs 64 kbps |
|---|---|---|
| 16k | 11.17 dB | **−14.01 dB** |
| 32k | 18.06 dB | −7.12 dB |
| 64k | 25.18 dB | — |

Absolute values are clip-dependent. Three talkers at nominal level on
`mf8-spec.md` §12.1's law give 10.3 / 17.1 / 23.1 dB (`cvsd_law.py rates`), and
those are the ones to specify against; seven-talker measurements on the previous
law gave 10.8 / 17.4 / 23.3, worst talker 9.0 / 14.9 / 19.7. Either way the
shape is the same: **32 kbps is the quality knee, 16 kbps is a real sacrifice,
64 kbps is comfortable.**

---

## 3. Reach is not free either

Attenuation goes as √f, so a fixed physical span costs each rate a different
loss. Referenced to 12 dB at 256 kbps:

| line | loss | amplitude | hysteresis as % of received |
|---|---|---|---|
| 128k | 8.5 dB | 0.376 | 13% |
| 256k | 12.0 dB | 0.251 | **20% — the single-span limit** |
| 512k | 17.0 dB | 0.142 | **35% — outside spec** |

On this span the 512 kbps mode is already outside the hysteresis specification,
which is exactly where `line-codes.md` §3 measured the attenuation cliff. That is
the reach argument stated in volts rather than kilometres, and it is the real
case *for* a lower rate.

### 3.1 But impulse noise runs the other way

Same span, 100 impulses/s fixed in absolute terms, 0.25 s × 4 seeds. Reported in
**time, not frames**: a re-acquisition costs a fixed number of *frames*, which is
four times longer in wall-clock at a 16 kHz frame rate than at 64 kHz, so a
frame-counted outage would flatter the low rates.

| line | amplitude | breaks/s | ms per break | time down |
|---|---|---|---|---|
| 128k | 0.376 | **41** | 13.3 ms | **54.7%** |
| 256k | 0.251 | 74 | 5.0 ms | 36.8% |
| 512k | 0.142 | **87** | **2.5 ms** | **21.3%** |

**The two effects pull opposite ways, which is not the intuition.** A lower rate
breaks *less often* — its signal is larger against a fixed impulse amplitude, so
fewer rings clear the `1 − h` threshold (`line-codes.md` §4.2), and each ring
spans fewer bits. But each break costs *more time*, because re-acquisition is
counted in frames and frames are longer. On these numbers the second effect wins.

So reach does not buy impulse robustness for free: **it buys fewer, longer
outages.** For voice that is the worse trade — a listener notices one 13 ms mute
more than five 2.5 ms ones.

(0.25 s × 4 seeds at one impulse rate on one assumed span loss. The **ordering**
is the result; the magnitudes are thin and should not be quoted as rates.)

---

## 4. The PCM argument is stronger than a rate coincidence

A 64 kbps slot is a DS0 rate, so a data card at a 64 kHz frame rate is a G.711
pipe. But rate alone is not enough — PCM needs **octet alignment** to know where
a sample starts, and a framer that establishes bit alignment and slot identity
establishes nothing coarser.

This frame fixes that for nothing, because **the superframe counter is already
the octet counter.** It has 8 phases, a channel takes one bit per frame, so
superframe state *k* is bit *k* of that channel's octet. The same three bits that
address the signalling demultiplexer do the byte framing:

```
superframe state   0   1   2   3   4   5   6   7
signalling S      A1  A2  A3   1  A4   0  A5  A6    -> the '259 address
channel n octet   b0  b1  b2  b3  b4  b5  b6  b7    -> the byte boundary
```

(S slot allocation as `mf8-spec.md` §2 specifies it.)

And at a 64 kHz frame rate the superframe rate is 64/8 = **8 kHz, the PCM sample
rate exactly**, so one superframe carries one sample. A PCM card becomes a shift
register clocked by the frame clock and transferred at state 7 — one 74HC164 and
a latch per channel.

No other combination lands on 8 kHz:

| N | superframe | bits/ch per superframe | at 64 kHz frame rate |
|---|---|---|---|
| 2 | 4 frames | 4 | 16 kHz superframe — half an octet |
| **6** | **8 frames** | **8** | **8 kHz — one PCM sample** |
| 14 | 16 frames | 16 | 4 kHz — two octets |

**The catch is serious, and it is why the F word matters.** `mfspec.md`'s
superframe phase was admitted wrong for 56 of 64 hook states, which there
misroutes signalling. If octet alignment rides the same phase, a wrong phase
**rotates every PCM sample** — garbage audio on a link that is otherwise
bit-perfect. Carrying PCM on the superframe promotes that from a signalling bug
to a payload bug.

`mf8-spec.md` §3.3 closes it: the framing word itself pins the phase, and the
enumeration over all 64 hook states measures **0 admissible wrong superframe
phases**. Octet alignment is only safe to rely on with that fix in place.

---

## 5. Recommendation

**64 kHz — six channels at 64 kbps on a 512 kbps line — if the plant reaches.**
It is the only mode one-for-one with a DS0, and the octet alignment that makes it
one is free. 32 kHz is the fallback and costs 5.5–5.9 dB per channel plus the DS0
property; 16 kHz gives up about 9 dB and should be treated as a reach-limited
special case, not a default.

The reach objection is weaker than it looks (§3 is a real constraint, but §3.1
runs the other way), so **the question to settle first is not the frame rate.**
It is whether the span is inside 0.71× reference reach, and what the impulse rate
on it is. Both are plant measurements.

**If the span is long, prefer fewer channels at 64 kbps over more channels at
32 kbps.** The 4-bit frame gives 2 DS0s at full reference reach, which keeps the
DS0 property that a rate drop throws away. That option exists only because frame
length is a separate knob, and it is the main reason §1 says to read the table by
column.

---

## 6. Reproducing

```
python3 sim/linecodes.py framerate
```

Caveats:

- §1's reach column is the √f law scaled from §1's single unmeasured
  anchor. The ratios are sound and the kilometres are not.
- §2's segSNR is one talker on a 2 s clip, so the absolutes differ from
  §1's seven-talker figures — use those to specify against.
- §3.1 is 0.25 s × 4 seeds at one impulse rate on one assumed span loss. The
  ordering is the finding; the magnitudes are thin.
- The 4-bit and 16-bit frame lengths are arithmetic here. Only N = 6 has a
  validated F word (`mf8-spec.md`); the others need their own framing word and
  guard positions, and the mis-jumper case between them is unmeasured.
