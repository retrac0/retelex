# SU-1 PCB

Build notes for the three boards of `common/su-1.md`, which owns the function,
the face and the S and K pin maps. Nothing is drawn; create `su_d/`, `su_a/` and
`su_k/` when each is laid out, and later `sdu_1/` (`common/sdu-1.md`) and the
dual-mode riser.

All boards 100 × 100 mm, 1.6 mm, two layers. SU-A stacks on SU-D at 0.4″
(10.16 mm); the spacers are the datum and the headers float. SU-K is off the
stack on ribbon K, and its datum is the bezel.

| board | parts |
|---|---|
| **SU-D** | 2× Murata 78615/9C (`mf8/mf8-spec.md` §9.3); 75176; the §9.2 encoder; the §9.4 receiver and violation term; LM339 ring detector (`common/subscriber-line.md` §3); `1100` / `1010` pattern gens; cradle switch and RC; the loop-timing circuit (open, `common/subscriber-line.md` §7), clock dividers and LED driver; speaker amp and ring-tone oscillator; 48 V → +5, ±12 V DC-DC; gas tubes, PTCs, TVS; line connector; S, K |
| **SU-A** | LM311, LM13700, 3× TL072, 3× '74, '86, '32, 2× 2N3906 (`common/cvsd-codec.md` §4); recon LPF; ear amp; 4P4C (RJ9) jack; mic mux, gate, sidetone; S mate |
| **SU-K** | 16 keys and pull-ups; 2× '148; ½ '193 and a flip-flop; '4017 and ¼ '4002; '393; ½ '123 seize delay; ¼ '86 and a '74 for lockout and debounce; K mate |

Not chosen: the S header (keyed 2×12 stacking, ~10.16 mm engagement), K (2×5
shrouded keyed IDC), the keys (~15 mm pitch assumed), the ear amp, loudspeaker,
jacks and line connector. The handset and cord are stock 600 Ω. Codec spice
reference: `spice/cvsd-enc/`, `spice/cvsd-dec/`.

1. SU-D schematic from `su-1.md` §2–§6, once SU-D's split (`su-1.md` §9) and
   the loop-timing circuit are settled.
2. SU-A schematic from `su-1.md` §3, §6 and `cvsd-codec.md`.
3. SU-K schematic from `su-1.md` §4 and `exchange/proposed/pulse-gen.md` §5.
4. Pick the stacking header and spacers; one hole pattern for SU-D and SU-A.
5. Place, pour ground, route, DRC.
6. Bench SU-A alone on an S carrier before the first stack-up on a live line.
7. Bench SU-K alone on K: `TICK` at 1 kHz in, a break train on a counter (60 ms
   of every 100), all sixteen keys through the two '148s.
