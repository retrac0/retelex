# SU-1 PCB

KiCad provisioning for the mk1 CVSD subscriber unit in `common/su-1.md`.
Two boards in a spacer stack; no schematic or copper yet.

| Project | Role | Copies |
|---|---|---|
| [`su_d/`](su_d/) | Line PHY, PSU, dial, clock recovery, line LED, **speaker**, mic jack, line out, talk UI — **100 × 100 mm** base | 1 per set |
| [`su_a/`](su_a/) | Type-A enc + dec + recon, 4P4C, handset ear VOL, mic mux — **100 × 100 mm** riser | 1 if voice-only |
| (later) `sdu_1/` | Data-only riser on the same **S** — `common/sdu-1.md` | 1 if data-only |
| (later) `su_ad/` | Dual-mode riser: both engines + **VOICE / DATA** switch — `su-1.md` §7 | 1 if dual-mode |

Voice-only, data-only, and dual-mode are **alternative** S populations — never
two risers stacked.

## Locked for this design pass

| | |
|---|---|
| Outline | **100 × 100 mm** each, 1.6 mm |
| Stack pitch | **0.4″ (10.16 mm)** — spacers datum; headers float |
| Mezzanine | **S** 2×12 0.1″ keyed — pin map = `su-1.md` §6.1 (`AUDIO_*`, `SPK`, `MIC_EN`) |
| Dial | Autovon 4×4 → 1–16 pulses, 10 pps 60/40 (`su-1.md` §4) |
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
detectors; `1100` / `1010` pattern gens; dialer (~11 HC + 16 keys + hook);
clock recovery (+ optional DPLL); ÷ for `TICK` and ~1 Hz LED; **loudspeaker
+ amp + loudspeaker pot + ring pot**; local ring tone; **mic jack + MICJ**;
**line out**; HANDSET/SPEAKER, LIVE/PTT, PTT; 48 V→+5/±12 DC-DC; line
connector; S.

**SU-A:** LM311 + LM13700 + 3× TL072 + 3× '74 + '86 + '32 + 2× 2N3906;
recon LPF; **handset ear amp + handset pot**; **4P4C** (600 Ω); mic mux / gate /
sidetone; S mate. **No piezo** — base speaker rings.

## Status

- **Spec:** `common/su-1.md` (proposed).
- **Schematic / PCB:** not drawn yet — create `su_d/` and `su_a/` when laying out.
- **Header P/N:** not chosen (need ~10.16 mm engagement, keyed 2×12).
- **Handset 4P4C P/N:** standard RJ9 jack; cord / capsule are off-the-shelf 600 Ω.
- **Speaker / mic jack / line out P/N:** not chosen.
- **Line pair connector P/N:** not chosen.
- **Spice reference (codec):** `spice/cvsd-enc/`, `spice/cvsd-dec/`.

## Next

1. Draw SU-D schematic from `su-1.md` §6.2 (PHY, dialer, speaker, mic jack, line out, PSU, S).
2. Draw SU-A schematic from §6.3 / `cvsd-codec.md` §4–5 (engine, 4P4C, mux, S).
3. Pick stackable header + spacers; fix hole pattern shared by both boards.
4. Place zones; pour GND; route; DRC.
5. Bench SU-A alone on an S carrier before first stack-up with a live line.
