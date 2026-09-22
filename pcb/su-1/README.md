# SU-1 PCB

KiCad provisioning for the mk1 CVSD subscriber unit in `common/su-1.md`.
Two boards in a spacer stack; no schematic or copper yet.

| Project | Role | Copies |
|---|---|---|
| [`su_d/`](su_d/) | Line PHY, phantom PSU, dial/hook digital, keypad, crystal — **100 × 100 mm** base | 1 per set |
| [`su_a/`](su_a/) | Type-A enc + dec + recon, 4P4C, sidetone, ringer — **100 × 100 mm** riser | 1 per set |
| (later) `sdu_1/` | Data riser on the same **S** — see `common/sdu-1.md`; not provisioned here yet | 0 or 1 (not with SU-A) |

## Locked for this design pass

| | |
|---|---|
| Outline | **100 × 100 mm** each, 1.6 mm |
| Stack pitch | **0.4″ (10.16 mm)** — spacers datum; headers float |
| Mezzanine | **S** 2×12 0.1″ keyed — pin map = `su-1.md` §5.1 |
| Dial | Autovon 4×4 → 1–16 pulses, 10 pps 60/40 (`su-1.md` §4) |
| Handset | 4P4C on SU-A |
| Line | two pairs + phantom centre taps on SU-D |
| Codec | type A — same engine as `cvsd-codec.md` §4–5; **not** shelf header R |
| Rails on S | +5, ±12, GND; plus `MUTE`, `RING` |

### Parts by board

**SU-D:** 2× line transformers (§9.3); §9.2 TX + §9.4 RX; LM339 hook/ring
detectors; `1100` / `1010` pattern gens; dialer (~11 HC packages + 16 keys +
hook); local crystal and dividers; 48 V→+5/±12 DC-DC; line connector; S.

**SU-A:** LM311 + LM13700 + 3× TL072 + 3× '74 + '86 + '32 + 2× 2N3906;
recon LPF; 4P4C; mic bias / ear / sidetone; ringer driver; S mate.

## Status

- **Spec:** `common/su-1.md` (proposed).
- **Schematic / PCB:** not drawn yet — create `su_d/` and `su_a/` when laying out.
- **Header P/N:** not chosen (need ~10.16 mm engagement, keyed 2×12).
- **Line 4P4C / pair connector P/N:** not chosen.
- **Spice reference (codec):** `spice/cvsd-enc/`, `spice/cvsd-dec/`.

## Next

1. Draw SU-D schematic from `su-1.md` §5.2 (PHY, detectors, dialer, PSU, S).
2. Draw SU-A schematic from §5.3 / `cvsd-codec.md` §4–5 (engine, 4P4C, ringer, S).
3. Pick stackable header + spacers; fix hole pattern shared by both boards.
4. Place zones; pour GND; route; DRC.
5. Bench SU-A alone on an S carrier before first stack-up with a live line.
