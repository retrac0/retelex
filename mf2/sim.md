# MF2 simulation checklist

What to build and run before `mf2/spec.md` graduates from sketch. Patterned on
`mf8/mf8-spec.md` §16 and `mf8/line-codes.md`: **bit-level framer first**, then
**AMI structural**, then **waveform plant**, then **interop**. Codec law and
card audio reuse MF8's numbers unless a test below fails.

> **Nothing in this list has been run for N = 2 yet.** Commands name intended
> entry points (`sim/mf2.py`, `sim/mf2_line.py`); fork from `mf8.py` /
> `mf8_line.py` / `linecodes.py` with `FLEN=4`, `NCH=2`, `LINE=256e3`, AMI
> default, SF=8, S at bit 2, guard at states 0 and 4.

Fixed geometry under test (do not vary unless a row says so):

```
frame:  [ F ][ C1 ][ S ][ C2 ]     64 kHz → 256 kbps
SF:     8 frames, F = 11111110,  guard S @ 0,4 = 0,1
line:   AMI, DPLL RX (option C), 256 kBaud
```

Logs: write `sim/mf2_*.log` (and `.csv` where sweeps exist) beside the script.

---

## 0. Pass bar (whole checklist)

| gate | pass when |
|---|---|
| **G1 Framer** | Wrong SF phases admitted = 0 on the F word + guard (MF8 §3.3 class). Acquisition holds 32 good frames on clean line for all payload classes in §1. |
| **G2 Seats** | Two arbitrary data cards: either **0 holds** with the product rule enforced in the model, or a measured alternate (XOR/alternating-C) reduces holds to chance acquisitions the guard counter releases (MF8 seats class). One data + voice: residual documented, release time measured. |
| **G3 AMI timing** | Zero-run bound structural; DPLL bit-count exact at ≥1000 ppm offset on worst payload; clockless RC path **not** required to pass. |
| **G4 Plant** | At 256 kbps AMI: Gaussian / attenuation / impulse columns filled; ranking vs DM at the **same bit rate** recorded. No claim that MF8's 512k numbers apply. |
| **G5 Interop** | MF2↔MF8 mis-jumper → no false lock, MUTE/LOF deterministic. Gateway remap seats that are three apart never used. |

Ship the sketch to “measured” only when G1–G5 are green or explicitly waived in `mf2/spec.md` §15.

---

## 1. Tooling to stand up

| work | source | change |
|---|---|---|
| `sim/mf2.py` | **exists** (build, framer, smoke) | Full word/guard/seats battery still to port from `mf8.py` |
| `sim/mf2_line.py` | **exists** | Calls `mf8_line.rx_ami(line=256e3)`; DM @ 256k is reference only |
| AMI PHY | `mf8_line.rx_ami` / `fast.ami_*` | Single implementation; hardware sketch `mf2/ami.md` |
| AMI helpers | `sim/linecodes.py` | zero-run, DPLL coast, polarity — retarget logs to 256k / N=2 frame |

Do not parametrize N=2 inside `mf8.py` in a way that breaks MF8's logged baselines; keep a separate module or a clearly gated `FAMILY=mf2` path.

---

## 2. Bit-level framer (`sim/mf2.py`)

Same targets as `mf8.py`. Run order matters: **word → sfphase → guard → sbit → locks → seats → errors**.

### 2.1 `word` — why `11111110` on N = 2

| measure | intent |
|---|---|
| Longest consecutive frame match of candidate F words on CVSD speech, silence, const 0/1, random | Same table shape as `mf8.py word` |
| Period-8 vs period-4 candidates | Period-4 must not be chosen (cannot pin 8-state SF / octet) |

**Pass:** `11111110` remains best or tied among period-8 words; no period-4 word admitted.

### 2.2 `sfphase` — wrong superframe phases

| measure | intent |
|---|---|
| All hook states × all SF skews: phases that satisfy F (+ guard if enabled) | MF8 closed this at 0 wrong phases |

**Pass:** **0** wrong SF phases admitted with F+guard.

### 2.3 `guard` — states 0,4 = `0,1`

| measure | intent |
|---|---|
| Four guard layouts (include 0,4 and at least one same-parity alternative) | Decode cost + residual speech |
| F word in every lane; one data card worst seat; voice 4-running residual | Same columns as `mf8.py guard` |

**Pass:** F-in-every-lane and one-data worst seat at **0/512** class; residual speech rate recorded (expect order 1 in hundreds–thousands).

### 2.4 `sbit` — S at bit 2, not beside F

| measure | intent |
|---|---|
| Every byte × every seat × beside-F vs opposite-F layouts | Beside-F must show one-data-card holes |

**Pass:** Opposite-F (S@2) has no one-data-card deterministic hole; beside-F fails as on MF8.

### 2.5 `locks` — payload classes

| measure | intent |
|---|---|
| False locks over speech, silence, const, random, data-ish octets | With F+guard+acquisition |

**Pass:** No deterministic hold except the known residual classes documented under seats.

### 2.6 `seats` — the critical MF2 row

| measure | intent |
|---|---|
| Both seats data, every byte pair, all skews | **Expected red without product rule** |
| One data + one voice; two voice | Residual / clean |
| Guard-counter release time when speech supplies guard | Second counter mandatory |
| Optional: XOR or alternating-C on payload | Only if trying to lift the two-data ban |

**Pass for ship-with-ban:** document two-data holds (count/512); enforce ≤1 data card in spec.  
**Pass for lift-ban:** alternate framing → 0 deterministic holds; chance rate + release measured.

### 2.7 `errors` — BER, acquisition, slips

| measure | intent |
|---|---|
| Injected BER vs LOF rate, reacquire time | AMI path: prefer **bit errors** over bit-count slips |
| Forced slip recovery | Framer reacquire ≤ MF8-class |

**Pass:** At BER levels MF8 §4.2 cared about, LOF behaviour characterized; injected **bit-count slips** are a separate stress (PHY should not produce them under AMI+DPLL — see §3–4).

### 2.8 Octet / `RX_OCT`

| measure | intent |
|---|---|
| Recovered state-7 strobe at 8 kHz on clean lock | DS0 claim |
| Wrong SF phase never asserted as locked | Ties to `sfphase` |

**Pass:** Octet phase pinned whenever framer is locked.

---

## 3. AMI structural (`linecodes` / `mf2.py` helpers)

### 3.1 Zero-run bound

| measure | intent |
|---|---|
| Longest AMI zero run over all hook states × payload classes | Structural bound from F=`11111110` on 4-bit frame |
| Compare to MF8's 15 | Expect shorter (~7–8 analysis) |

**Pass:** Bound stated as structural max; B8ZS/HDB3 still unnecessary.

### 3.2 DPLL (option C) at 256 kbps

| measure | intent |
|---|---|
| Crystal offset sweep (200 ppm … ≥1000 ppm, include 5000 ppm if cheap) | Bit count emitted − sent = 0 on worst payload |
| Coast across max zero run | No slip |
| Optional: tank / clockless RC (option A/B) | Expect fail or no margin — record, do not adopt |

**Pass:** Option C green; A/B not required.

### 3.3 Polarity / tip-ring swap

| measure | intent |
|---|---|
| Invert pair; lock and BER | Full-wave AMI front end must stay blind |

**Pass:** Both polarities lock; no systematic 1↔0 swap on payload.

### 3.4 Bipolar violations

| measure | intent |
|---|---|
| Count violations under clean vs impulse | Optional MUTE/erasure input |

**Pass:** Not a ship gate; numbers feed §13 optional erasure design.

---

## 4. Waveform plant (`sim/mf2_line.py`)

Same measurement rules as `mf8_line.py`: score audio inside contiguous locked runs; isolation uses one lag per channel.

Default code **AMI**. Always keep a **DM @ 256 kbps** column for ranking, not as a product option.

### 4.1 `clean`

| measure | intent |
|---|---|
| Per-channel segSNR, isolation, LOF=0 | Carrier adds nothing on clean line |

**Pass:** segSNR within noise of codec-only; isolation ~0 on cross terms.

### 4.2 `noise` — Gaussian

| measure | intent |
|---|---|
| sd sweep: breaks/s, muted %, segSNR | AMI amplitude decision vs DM timing decision |

**Pass:** Table filled; expect DM stronger on Gaussian (MF8 pattern) — document, do not switch codes.

### 4.3 `plant` — attenuation

| measure | intent |
|---|---|
| Amplitude / hysteresis relative to § spec (≤10% target, 20% single-span limit) | 256k reference span |

**Pass:** Behaviour at 0.25 and cliff region recorded; preamp recommendation for `mf2/spec.md` §7.

### 4.4 `plant` / `impulse_sweep` — impulse

| measure | intent |
|---|---|
| Breaks/s, ms/break, muted %, segSNR vs impulses/s | AMI should avoid DM slip storms |
| Collapse point if any | MF8 AMI collapsed ~800–900/s at 512k — re-find at 256k |

**Pass:** Impulse curve for AMI @ 256k; DM @ 256k reference; no use of MF8 512k thresholds as MF2 limits.

### 4.5 Render (optional)

| measure | intent |
|---|---|
| `mf2_render`-class WAVs at 10/s and 100/s impulse | Listen for ticks vs chop |

**Pass:** Optional; attach paths in the log header.

---

## 5. Interoperability and abuse

### 5.1 Mis-jumper MF2 ↔ MF8

| case | expect |
|---|---|
| MF2 AMI RX on MF8 DM 512k line | no lock / carrier fail / MUTE |
| MF2 RX on MF8 256k family row if exposed (32k/ch MF8) | no false lock on interleaved C pairs |
| MF8 DM RX on MF2 AMI 256k | no lock |

**Pass:** Deterministic mute; zero acquisition on alien alphabet in the exhaustive short-clip sense used elsewhere.

### 5.2 Rate mis-jumper within MF2 plug

| case | expect |
|---|---|
| 256k PHY vs 128k/64k if plugs exist | no false lock |

**Pass:** Same as family mis-jumper note in `mf8-spec.md` §15.

### 5.3 Gateway seat remap (logical test)

| measure | intent |
|---|---|
| Enumerate MF8 seat pairs for two C/A | Reject pairs three apart: (1,4)(2,5)(3,6) |
| Preferred pairs e.g. (1,2)(2,3)(5,6)(6,7) | Allowed |

**Pass:** Checklist in code or a 20-line unit test; no waveform needed.

---

## 6. Signalling and cards (light)

| test | intent | pass |
|---|---|---|
| A1/A2 round-trip at 8 kHz through framer | Hook path | Bit-exact on clean line |
| Dial-pulse style A toggles through debounce model | If reusing channel-cards §5 RC | Edges survive; re-tune note if not |
| `RX_OCT` to data-card PCM framing | Octet claim | Aligns with state 7 |

Full CVSD law / tolerance sweeps: **reuse** `cvsd_law.py` / `tolerance.py` at 64 kbps; no MF2-specific gate unless clean-line segSNR regresses.

---

## 7. Suggested run order and time

| step | command (intended) | ~time | gate |
|---|---|---|---|
| 1 | `python3 sim/mf2.py word sfphase guard sbit` | short | G1 |
| 2 | `python3 sim/mf2.py locks seats errors` | medium | G1, G2 |
| 3 | `python3 sim/mf2.py` (or helper) `zeros dpll polarity` | short | G3 |
| 4 | `python3 sim/mf2_line.py clean` | medium | G4 |
| 5 | `python3 sim/mf2_line.py noise plant` | long | G4 |
| 6 | impulse sweep @ 256k AMI (+ DM ref) | long | G4 |
| 7 | misjumper + gateway seat test | short | G5 |

Bit-level failures block line work: do not tune AMI plant against a broken framer.

---

## 8. Caveats (read numbers like MF8)

- `mf2.py` is bit level: no waveform. Plant conclusions need `mf2_line.py`.
- Impulse model is the same damped bipolar ring as `mf8-spec.md` §16; at 256 kbps the ring crosses fewer bit periods per event — do not compare breaks/s to MF8 without noting rate.
- Exhaustive hook sweeps use short clips (MF8: 3000 frames): ample for 32-frame acquisition, weak for rare events.
- Two talkers only; isolation matrix is 2×2.
- Scoring locked-run windows and single-lag isolation rules from `mf8_line.py` apply unchanged.
- Analysis that “zero run ≈ 7” or “AMI impulse ranking holds” is **hypothesis** until the matching row above is green.

---

## 9. Closing the spec

When a gate passes, flip the matching row in `mf2/spec.md` §15 from **not measured** to a one-line result (value + log name). When G1–G5 pass, remove the sketch banner’s “not measured” clause for geometry/AMI plant and point §16 here as the reproduction index.
