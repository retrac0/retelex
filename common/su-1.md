# SU-1 — the CVSD subscriber set

SU-1 is the native telephone for the two-pair CVSD line of `subscriber-line.md`
— codec, handset, loudspeaker and a sixteen-key pulse dial — seen by the
exchange as an ordinary CVSD line card (`channel-cards.md` §2). The line law,
the detectors and dialling on the line are `subscriber-line.md`'s.

> **Proposed.** Nothing drawn, nothing on a bench.
> Model: `newimpl/tb/subscriber.v`, the line behaviour only (bench `line`: no
> dial, face or LED); the retired full model is `old/verilog/rtl/su1.v`.
> Measured in: `subscriber-line.md` §3, §5.

## 1. What it is

Three boards, each 100 × 100 mm:

| board | holds | joined by |
|---|---|---|
| **SU-D** | line interface, phantom supply, hook, clock recovery, line LED, loudspeaker, every face control but the handset's | the two pairs |
| **SU-A** | type-A encoder, decoder and reconstruction (`cvsd-codec.md`), handset jack, ear amplifier, sidetone, mic mux and gate | header **S** on SU-D, 0.4″ stack (§6) |
| **SU-K** | keys, debounce, encode, pulse sequencer | ribbon **K** from SU-D, placed by the bezel (§4) |

## 2. The line logic

The set is `subscriber-line.md` §4's phone end. SU-D holds the `1100` mux ahead
of the §9.2 encoder, the ring detector in the phone's sense (¼ LM339,
`subscriber-line.md` §3), the `1010` forced onto `BIT_DEC` while `RING`, and the
hook: the cradle switch and a ~20 ms RC, with no density hook detector. SU-A
silences its encoder while the dial is off normal (`OFF_NORM`, **mandatory**,
`subscriber-line.md` §5) or the mic gate is shut. The line interface is
`mf8/mf8-spec.md` §9 at the §9.7 64 kbps plug: a §9.3 transformer and protection
per pair, the phantom on the line-side centre taps.

## 3. The face

| control | board | what it does |
|---|---|---|
| 4P4C jack, **handset** pot | SU-A | 600 Ω modular handset; ear muted on-hook and in SPEAKER; sidetone after the pot |
| cradle | SU-D | open = on-hook; `HOOK` to SU-K on K |
| **HANDSET / SPEAKER** | SU-D | where received audio goes; `SPK` on S |
| **LIVE / PTT**, **PTT** key | SU-D | mic open while off-hook, or only while PTT is held; `MIC_EN` on S |
| loudspeaker, **loudspeaker** pot | SU-D | the ringer, and hands-free listen in SPEAKER; the pot sets listen level only |
| **ring** pot | SU-D | level of the local ring tone that `RING · ON-HOOK` gates into the speaker amp |
| mic jack, jumper `MICJ` | SU-D | with `MICJ` fitted SPEAKER takes the mic from the jack; HANDSET always uses the handset mic |
| line out | SU-D | fixed ~−10 dBV from `AUDIO_RX`, ahead of every pot and either mode; never the ring tone |
| line LED, two pairs | SU-D | §5; RJ45 or a terminal block |
| **VOICE / DATA** | riser | dual-mode sets only (§7) |

Handset jack from the front, contacts up: 1 earpiece, 2–3 microphone, 4 earpiece
return. Mic level into the encoder is fixed.

```
 handset mic ─────────────┐
 jack (MICJ · SPEAKER) ───┴─ mux ── gate: MIC_EN · /OFF_NORM ── encoder
 decoder ── recon ─┬─ [handset] ── ear amp ── 4P4C
                   └─ AUDIO_RX ─┬─ [loudspeaker] ─────┬─ amp ── loudspeaker
                                │ ring tone ── [ring] ┘
                                └─ fixed pad ── line out
```

## 4. The dial — SU-K and header K

A 4×4 Autovon pad, **pulses only**: 1–9 send 1–9, 0 ten, `*` 11, `#` 12 and the
fourth column FO / F / I / P 13–16. 10 pps 60/40, a deaf seize wait of
500–800 ms before the first digit, 700 ms between digits, ~20 ms debounce,
one-key lockout while a train is out, a one-deep queue. SU-K is
`exchange/proposed/pulse-gen.md` §5's sequencer without the ÷8, the `SRC` mux or
the RC astable, about ten packages by arithmetic; its one timebase is `TICK`.
What the exchange does with keys past ten pulses is `numbering.md` §3; its
register counts to 15 (`newimpl/rtl/pulse_rx.v`), so I and P read alike there.

| pin | signal | | pin | signal | |
|---|---|---|---|---|---|
| 1 | `GND` | | 2 | `+5 V` | the only rail on K |
| 3 | `TICK` | 1 kHz (§5) | 4 | `GND` | |
| 5 | `HOOK` | 1 = off-hook | 6 | `BREAK` | out: 1 in a break, to the `1100` mux |
| 7 | `OFF_NORM` | out: a train out or queued | 8 | `GND` | |
| 9 | `KEY_ANY` | out, test | 10 | `GND` | |

K is a keyed 2×5 ribbon. **The hook stays on SU-D**, so a set with K unplugged
still goes on-hook; SU-D pulls `BREAK` and `OFF_NORM` low, and the set then
simply cannot dial.

## 5. Clocking and the line LED

The §9.4 receiver's strobe, one pulse a received bit, runs while the downstream
carries idle, ringing or speech. It is `RX_CLK` on S (64 kHz); ÷ 64 it is `TICK`
on K; ÷ 65 536 it blinks the line LED at 0.98 Hz, dark with no carrier, a cut
pair or no power. The LED watches the downstream only. **The set is
loop-timed** (`subscriber-line.md` §1): `TX_CLK` on S and the §9.2 encoder's
128 kHz half-bit follow the downstream, so the upstream never slips against the
line card's synchronizer (`channel-cards.md` §2.3). The circuit that makes them
from the strobe is open (`subscriber-line.md` §7).

## 6. Header S and the populations

Keyed 2×12, 0.1″, stacking at 0.4″ (10.16 mm; that pitch is open,
`cvsd-codec.md` §6). Directions from the riser. Logic
is 0 / +5 V HC; `AUDIO_*` are analog about ground.

| pin | signal | | pin | signal | |
|---|---|---|---|---|---|
| 1 | `GND` | | 2 | `GND` | |
| 3 | `+5 V` | in | 4 | `+12 V` | in |
| 5 | `−12 V` | in | 6 | `GND` | |
| 7 | `TX_CLK` | in, 64 kHz, encoder | 8 | `RX_CLK` | in, 64 kHz, decoder |
| 9 | `BIT_ENC` | out, to the `1100` mux | 10 | `BIT_DEC` | in, after the `RING` gate |
| 11 | `AUDIO_TX` | in, jack mic | 12 | `AUDIO_RX` | out, recon ahead of the handset pot |
| 13 | `GND` | audio return | 14 | `OFF_NORM` | in, encoder silent |
| 15 | `RING` | in | 16 | `/OE` | in, optional; pull down to run |
| 17 | `SPK` | in, 1 = SPEAKER | 18 | `MIC_EN` | in, 1 = mic gate open |
| 19 | `Y_E` | out, test | 20 | `Y_D` | out, test |
| 21, 23 | `GND` | 23 is the key | 22, 24 | `GND` | |

S takes one riser, never two stacked: SU-A (voice), SDU-1 (data, `sdu-1.md`) or
the dual-mode riser (§7). SU-K is fitted on every set that dials, and may be
left off a headless or nailed data set. Parts and build: `pcb/su-1/README.md`.

## 7. Dual mode

One riser carries SU-A's engine and SDU-1's; a maintained **VOICE / DATA**
switch and a '157 pick which drives `BIT_ENC` and which hears `BIT_DEC`. Hook,
dial, ring, face and clocks do not depend on it. It may be thrown before or
during a call. There is no handshake: a mismatch is noise at the far end, as
voice into a data port is (`channel-cards.md` §1). DATA is insert-1, or RAW64 on
a nail (`sdu-1.md` §3). The riser needs ±12 V for its codec half.

## 8. Against the exchange

Lift, wait, dial, as with a rotary phone on the same card (`numbering.md` §1);
the mode switch is in neither the word nor A. **A set that makes or takes
switched calls, voice or data, needs its line's word to leave `D` clear**
(`card-word.md` §4, §8); the line card as built sends the plain-line constant
(`channel-cards.md` §2.5).

## 9. Open

- **SU-D does not fit one board.** ~22 packages, two transformers, protection on
  four conductors, two switchers, the speaker amp and the face are ~95 %
  courtyard on 100 × 100, the switchers beside the ~50 mV receiver comparator.
  Split it (line / logic / energy, as `stu-1.md` §3) or find room; an isolated
  DC-DC brick is taller than the 4.5 mm under a 0.4″ neighbour, so it cannot sit
  mid-stack. Blocks the SU-D schematic.
- **SU-K's fill and key pitch.** Ten DIPs behind a 60 × 60 pad at ~15 mm pitch
  is ~70 % courtyard; desk sets use ~19 mm, which leaves none. Options: SMD keys
  (STU-1's ST-K), or a key board with the sequencer on SU-D.
- **No power budget.** SU-D adds a speaker amp and a ring oscillator to
  `subscriber-adapter.md` §4's load, which closes at 3 km and is marginal at 5.
- **The deaf seize wait** clears the class marker's walk (≈ 250 ms, `marker.md`
  §4.2) but not a busy register (every build has one, `register.md` §4): a
  queued key is then dialled before a register listens. Options: a longer
  wait, or `exchange/proposed/pulse-gen.md`'s dial-tone wait (the downstream leaves `1010`) on
  SU-K.
- **SU-K's 100 ms step.** A '4017 on a 1 kHz tick cycles in 10 ms, not 100;
  `exchange/proposed/pulse-gen.md` §2.1 puts a ½ '390 ÷10 ahead of it, and SU-K on `TICK` needs
  the same, which `pcb/su-1/README.md` does not list.
- **The loop-timing circuit** (§5): `subscriber-line.md` §7.
- **Not measured:** howl-round in SPEAKER + LIVE, ring-tone timbre, key bounce
  and cradle chatter against the debounce, VOICE / DATA switch bounce into
  `BIT_ENC`, phantom-supply noise into the codec. **Not in mk1:** DTMF from the
  pad; meanings for FO / F / I / P.
