# SU-1 PCB

KiCad provisioning for the mk1 CVSD subscriber unit in `common/su-1.md`.
Three boards — a two-board spacer stack plus a panel-mounted dial; no schematic
or copper yet.

| Project | Role | Copies |
|---|---|---|
| [`su_d/`](su_d/) | Line PHY, PSU, hook, clock recovery, line LED, **speaker**, mic jack, line out, talk UI — **100 × 100 mm** base | 1 per set |
| [`su_a/`](su_a/) | Type-A enc + dec + recon, 4P4C, handset ear VOL, mic mux — **100 × 100 mm** riser | 1 if voice-only |
| [`su_k/`](su_k/) | 16 Autovon keys + pulse sequencer — **100 × 100 mm**, panel-mounted on ribbon **K** (`su-1.md` §6.5) | 1 per set |
| (later) `sdu_1/` | Data-only riser on the same **S** — `common/sdu-1.md` | 1 if data-only |
| (later) `su_ad/` | Dual-mode riser: both engines + **VOICE / DATA** switch — `su-1.md` §7 | 1 if dual-mode |

Voice-only, data-only, and dual-mode are **alternative** S populations — never
two risers stacked. **SU-K is fitted in all three**: every population dials the
same way.

## Locked for this design pass

| | |
|---|---|
| Outline | **100 × 100 mm** each, 1.6 mm |
| Stack pitch | **0.4″ (10.16 mm)** SU-D↔SU-A — spacers datum; headers float. SU-K is **off-stack**, datum is the bezel |
| Mezzanine | **S** 2×12 0.1″ keyed — pin map = `su-1.md` §6.1 (`AUDIO_*`, `SPK`, `MIC_EN`) |
| Dial ribbon | **K** 2×5 0.1″ keyed IDC — pin map = `su-1.md` §6.5. Nothing on it above **1 kHz** |
| Dial | Autovon 4×4 → 1–16 pulses, 10 pps 60/40 (`su-1.md` §4), **on SU-K**; keys ~15 mm pitch, 60 × 60 mm field |
| Clock | **no crystal** — loop-timed from §9.4 RX (`su-1.md` §5) |
| Line LED | ~1 Hz from recovered RX clock; dark if no carrier |
| Handset | **4P4C** (RJ9), **600 Ω** — `su-1.md` §3.1 |
| Speaker | on **SU-D**; ringer + conference listen — `su-1.md` §3.2 |
| Mic jack | on **SU-D**; `MICJ` jumper for SPEAKER mode |
| Line out | on **SU-D**; fixed pad from `AUDIO_RX` (no pot; no ring tone) |
| Talk UI | HANDSET/SPEAKER, LIVE/PTT, PTT |
| Volumes | **three** face pots: **handset**, **loudspeaker**, **ring** |
| Line | two pairs + phantom centre taps on SU-D |
| Codec | type A — same engine as `cvsd-codec.md` §4–5; **not** shelf header R |
| Rails on S | +5, ±12, GND; `MUTE`, `RING`, `SPK`, `MIC_EN` |

### Parts by board

**SU-D:** 2× line transformers (§9.3); §9.2 TX + §9.4 RX; LM339 hook/ring
detectors; `1100` / `1010` pattern gens; hook switch + debounce; clock recovery
(+ optional DPLL); ÷ for `TICK` and ~1 Hz LED; **loudspeaker + amp +
loudspeaker pot + ring pot**; local ring tone; **mic jack + MICJ**; **line
out**; HANDSET/SPEAKER, LIVE/PTT, PTT; 48 V→+5/±12 DC-DC; line connector;
S and K.

**SU-A:** LM311 + LM13700 + 3× TL072 + 3× '74 + '86 + '32 + 2× 2N3906;
recon LPF; **handset ear amp + handset pot**; **4P4C** (600 Ω); mic mux / gate /
sidetone; S mate. **No piezo** — base speaker rings.

**SU-K:** 16 keys at ~15 mm pitch + pull-ups; 2× '148 encode; ½ '193 + FF count;
'4017 + ¼ '4002 break former; '393 pause; ½ '123 seize delay; ¼ '86 + '74
lockout / debounce; K mate. **≈ 9–10 packages** — `exchange/pulse-gen.md` §5
less the `SRC` mux and the RC astable (`su-1.md` §6.5).

## Status

- **Spec:** `common/su-1.md` (proposed).
- **Schematic / PCB:** not drawn yet — create `su_d/` and `su_a/` when laying out.
- **Header P/N:** not chosen (need ~10.16 mm engagement, keyed 2×12 for S; 2×5
  shrouded keyed IDC for K).
- **Key P/N and pitch:** ~15 mm assumed for the 60 × 60 field; not chosen.
- **Handset 4P4C P/N:** standard RJ9 jack; cord / capsule are off-the-shelf 600 Ω.
- **Speaker / mic jack / line out P/N:** not chosen.
- **Line pair connector P/N:** not chosen.
- **Spice reference (codec):** `spice/cvsd-enc/`, `spice/cvsd-dec/`.

## Next

1. Draw SU-D schematic from `su-1.md` §6.2 (PHY, speaker, mic jack, line out, PSU, hook, S, K).
2. Draw SU-A schematic from §6.3 / `cvsd-codec.md` §4–5 (engine, 4P4C, mux, S).
3. Draw SU-K schematic from §6.5 / `exchange/pulse-gen.md` §5 (keys, encode, sequencer, K).
4. Pick stackable header + spacers; fix hole pattern shared by SU-D and SU-A.
5. Place zones; pour GND; route; DRC.
6. Bench SU-A alone on an S carrier before first stack-up with a live line.
7. Bench SU-K alone on K: `TICK` in at 1 kHz, a break train on a counter —
   **60 ms of every 100** — and all sixteen keys through the two '148s
   (`stu-1.md` §13 step 5 is the same check on ST-K).
