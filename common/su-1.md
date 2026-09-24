# SU-1 — mk1 CVSD subscriber unit

A freestanding **native CVSD phone** on the two-pair line of
`subscriber-line.md`. It holds the codec, a 4P4C handset jack, and a 4×4 pad
in the Autovon / DTMF layout that generates **dial pulses**. It is not an
exchange channel card and not the POTS adapter of `subscriber-adapter.md`.
The exchange still sees an ordinary line through the CVSD subscriber line
card (`channel-cards.md` §2).

> **Status: proposed.** The line law, detectors and codec are measured in
> simulation (`subscriber-line.md`, `mf8-spec.md` §12.1). The dialer timebase
> and pulse map match `pulse-gen.md` (measured under `make pulse_gen` /
> `make su1`). Nothing has been on a bench. Outline and stack pitch are
> locked for PCB provisioning; schematic and copper are not drawn.

```
  handset ── 4P4C ──► SU-A (audio / codec)
                         ║ S   64 k clocks, both bit streams
  mic jack ─────────► SU-D (line PHY, PSU, speaker, talk UI, hook)
  speaker  ◄───────── SU-D
  line out ◄───────── SU-D
                         ║ K   ribbon, nothing above 1 kHz
  16 keys ──────────► SU-K (dial: encode + pulse sequencer)

                    SU-D
                         ║
                    two pairs + 48 V phantom
                         ║
                    CVSD line card ──► exchange
```

---

## 1. What it is

| | |
|---|---|
| **Line** | two pairs, 64 kbps differential Manchester, 128 kBaud — `subscriber-line.md` §1 |
| **Power** | 48 V phantom on the centre taps; local rails +5 / ±12 derived on SU-D |
| **Codec** | type-A enc + dec + recon in the set (`mf8-spec.md` §12.1) — not on the line card |
| **Handset** | standard **4P4C** (RJ9 / RJ22) jack on SU-A for a **600 Ω** modular handset (§3.1) |
| **Speaker** | loudspeaker on the **base (SU-D)** — ringer and conference listen (§3.2) |
| **Mic jack** | input jack on the base; jumper selects it in speaker mode (§3.2) |
| **Line out** | fixed-level jack on the base from decoder recon (§3.2) |
| **Dial** | sixteen keys, Autovon labels, **pulse only**, on their own board **SU-K** — same 1–16 map as `pulse-gen.md` §4 (§4, §6.5) |
| **Audio face** | **HANDSET / SPEAKER** toggle; **LIVE / PTT** toggle; **PTT** button; volumes **handset / loudspeaker / ring** (§3.2) |
| **Clocking** | **no local crystal** — loop-timed from the recovered downstream (§5) |
| **Line LED** | ~1 Hz blink from recovered RX clock — dark if no carrier (§5) |

The shelf CVSD codec **R** riser (`cvsd-codec.md`) is a different host and
header. SU-A reuses the same engine parts with a phone-specific **S** header
(§6.1). The same **S** accepts **SDU-1** (`sdu-1.md`) as a data-only riser, or
both engines on one dual-mode riser with a panel switch (§7). SU-D still owns
the line code and `1100`.

---

## 2. Interface law

Unchanged from `subscriber-line.md` §§1–5. Summarised for the unit:

| direction | state | on the line |
|---|---|---|
| phone → exchange | off-hook, talking | CVSD |
| | on-hook, or a dial break | `1100` repeating |
| exchange → phone | off-hook | trunk C bit |
| | on-hook, idle | `1010` |
| | on-hook, ringing | all zeros, ring cadence |

Phone logic (`subscriber-line.md` §4):

```
TX   = ON-HOOK or dial break  ?  1100  :  BIT_ENC from the S riser
encoder input = dial off-normal || mic gated off ? silence : microphone
ring = RING · ON-HOOK                                 → base speaker (ringer)
decoder input = RING ? 1010 : Q ;  handset ear muted while ON-HOOK
speaker talk = SPEAKER · OFF-HOOK · decoder audio
```

On a voice-only set, `BIT_ENC` is the CVSD encoder. Dual-mode (§7) steers
`BIT_ENC` / `BIT_DEC` between CVSD and the data path (insert-1, or RAW64 when
nailed — `sdu-1.md` §3.6); the `1100` mux stays on SU-D.

**Mute while off-normal** is mandatory so makes carry `1010` and the register
sees a fixed shortening (`subscriber-line.md` §5, `register.md` §1.1).

---

## 3. Face and connectors

| face | |
|---|---|
| **Pad** | 4×4 momentary keys on **SU-K**, Autovon / DTMF layout (§4) |
| **Hook** | cradle or switchhook wired to **SU-D**; open = on-hook. Read by SU-K over **K** (§6.5) |
| **Handset** | standard **4P4C** on SU-A for a **600 Ω** modular handset (§3.1) |
| **Speaker** | loudspeaker on **SU-D** (base) — ringer + conference listen (§3.2) |
| **Mic jack** | input jack on **SU-D**; board jumper enables it in **SPEAKER** mode (§3.2) |
| **Line out** | output jack on **SU-D** — fixed line level from recon (§3.2) |
| **HANDSET / SPEAKER** | maintained toggle — where receive audio goes (§3.2) |
| **LIVE / PTT** | maintained toggle — mic always open vs push-to-talk (§3.2) |
| **PTT** | momentary button — opens mic when **PTT** mode is selected |
| **Volumes** | three face pots: **handset**, **loudspeaker**, **ring** (§3.1–§3.2) |
| **Line** | two pairs (RJ45 or terminal block on SU-D) |
| **Line LED** | ~1 Hz from recovered RX clock (§5) — dark when the line is dead |
| **Mode** | on a dual-mode set only: panel **VOICE / DATA** (§7) |

No exchange channel socket. No DTMF generator on the pad in mk1: every key
is a pulse count. In-band DTMF remains possible later through the codec if a
tone source is added; the network flood still needs pulse on A
(`network.md` §3).

### 3.1 Handset — 4P4C, 600 Ω

A stock modular telephone handset on a **4P4C** cord (also called RJ9 / RJ22).
The jack is on the SU-A face (or the voice half of a dual-mode riser).

**Pinout** — jack viewed from the front, contacts up, latch down (same silk as
most desk-set handset jacks):

| pin | handset | SU-A |
|---|---|---|
| 1 | earpiece | receiver drive, **600 Ω** |
| 2 | microphone | mic input (with bias if the capsule needs it) |
| 3 | microphone | mic return |
| 4 | earpiece | receiver return |

Pins 1–4 and 2–3 are the two pairs of a standard handset cord. A straight or
handset-reversed cord both work if the pairs stay pairs.

| | |
|---|---|
| **Ear** | output amp after the reconstruction LPF. Face pot **handset** sets gain — min to comfortable loud; stop before clipping the capsule (`cvsd-codec.md` FS class). Muted on-hook and when **SPEAKER** is selected |
| **Mic** | handset capsule into the mic source mux (§3.2); bias / pad as needed. Fixed encode level (no face mic pot) |
| **Sidetone** | local pad on SU-A, after the **handset** pot (tracks ear level); handset path only |
| **Hook** | cradle switch on SU-D, **not** in the handset cord; `HOOK` goes up to SU-K on **K** |

```
  BIT_DEC ──► CVSD DEC ──► RECON ─┬─►[ handset ]──► ear amp ──► 4P4C ear
                                  │         │
                                  │         └── sidetone ──► (handset path)
                                  └── AUDIO_RX on S ──► SU-D loudspeaker + line out (§3.2)
```

Ringing is **not** injected into the 4P4C and is **not** through the **handset** pot.

### 3.2 Base speaker, mic jack, line out, and talk controls

The **loudspeaker** lives on **SU-D** (the base). It is both the **ringer** and
the **conference / hands-free** listen path. Ring level and talk level are
**separate** pots. **Line out** is a fixed-level tap of the same recon for
recording / monitor — not through any face pot.

| control | board | |
|---|---|---|
| **HANDSET / SPEAKER** | SU-D | **HANDSET:** decoder → handset ear (SU-A); loudspeaker silent except when ringing on-hook. **SPEAKER:** decoder → loudspeaker amp; handset ear muted |
| **handset** | SU-A | earpiece volume (§3.1) |
| **loudspeaker** | SU-D | conference / hands-free listen gain (recon → speaker amp). Does **not** set ring loudness |
| **ring** | SU-D | local ring-tone level into the speaker amp when `RING · ON-HOOK` |
| **Mic jack** | SU-D | input jack; **board jumper `MICJ`**: when set, **SPEAKER** mode takes mic from this jack; when clear, **SPEAKER** mode still uses the handset mic. **HANDSET** mode always uses the handset mic. Fixed mic gain after the source mux |
| **Line out** | SU-D | unbalanced jack; fixed line level from `AUDIO_RX` (pre–**loudspeaker** / **handset** pots). Always fed when recon is live — independent of **HANDSET / SPEAKER**. No local ring tone on this jack |
| **LIVE / PTT** | SU-D | **LIVE:** mic gated on whenever off-hook (and not dial-muted). **PTT:** mic gated off unless the **PTT** button is held |
| **PTT** | SU-D | momentary; active only in **PTT** mode |

```
                    ┌─ HANDSET mic ─────────────────────┐
  mic sources ─────┤                                    ├──► gate ──► ENC
                    └─ jack (if MICJ · SPEAKER) ─────────┘     │
                                                              │ LIVE: on when off-hook
                                                              │ PTT:  on when PTT held
                                                              │ always off when dial off-normal

  RECON (AUDIO_RX) ──┬──►[ loudspeaker ]──►┐
                     │                      ├──► speaker amp ──► loudspeaker
                     │   RING · ON-HOOK ──► ring tone ──►[ ring ]──┘
                     └──► fixed pad ──► line-out jack
```

| | |
|---|---|
| **Ringer** | `RING · ON-HOOK` gates a **local** ring tone into the speaker amp through the **ring** pot — not the CVSD stream of zeros, and not the **loudspeaker** pot. No separate piezo required |
| **Conference listen** | off-hook + **SPEAKER**: far-end audio from recon through the **loudspeaker** pot. Acoustic path is open; operator discipline (and PTT) limit howl-round |
| **Line out** | same recon as conference listen, fixed pad to consumer line level (~−10 dBV class). Independent of **HANDSET / SPEAKER** and of the face pots; local ring tone stays off this jack |
| **Gate** | mic gate is silence into the encoder (same node as dial off-normal mute). `MUTE` on S still covers dial; `MIC_EN` on S carries LIVE/PTT state to SU-A if the gate lives there |

S carries talk audio both ways for this feature: **`AUDIO_RX`** (recon → speaker and line out) and **`AUDIO_TX`** (selected mic toward the encoder when the jack feeds SU-A, or mic already on SU-A). Digital **`SPK`** and **`MIC_EN`** ride former spare/test pins (§6.1).

---

## 4. Keypad and dialer — SU-K

All of this section is **one board, SU-K** (§6.5): keys, debounce, encode and
sequencer together, with only `BREAK` and `OFF_NORM` leaving it on the **K**
ribbon.

Autovon physical layout; pulse counts identical to the hex map of
`pulse-gen.md` §4 (FO/F/I/P = A–D = 13–16):

```
        KEY1  KEY2  KEY3  KEYFO         pulses  1  2  3 13
        KEY4  KEY5  KEY6  KEYF                  4  5  6 14
        KEY7  KEY8  KEY9  KEYI                  7  8  9 15
        KEY*  KEY0  KEY#  KEYP                 11 10 12 16
```

1–9 are 1–9 pulses; 0 is ten. `*` is 11, `#` is 12, FO/F/I/P are 13–16.
The numbering plan does not use them yet: a first digit past 10 is
cannot-complete (`marker.md` §2). They exist so a register can count them
and so Autovon precedence can be given a dial-plan meaning later — **not in
mk1**.

**Timebase:** **10 pps, 60/40**, seize wait 500–800 ms before the first digit,
700 ms interdigit, ~20 ms debounce, one-key lockout while a train is out,
**one-deep queue**. Same structure as `pulse-gen.md` §2.1 / §3, but `TICK`
comes from the **recovered downstream** clock divided on SU-D (§5) and arrives
on **K** pin 3 — not a local crystal and not shelf `TX_OCT`. No RC/DIP
adjustable source on the set.

The dial contact is the pulse sequencer: breaks assert the on-hook pattern
(`1100` on the line; on the simplified RTL interface, `m` drops as
`phone.v` / `pulse_gen` do).

---

## 5. Clocking and line LED — loop-timed, no crystal

The set has **no local oscillator**. The exchange transmits continuously on
the downstream pair (`subscriber-line.md` §1). Differential Manchester always
carries transitions (`mf8-spec.md` §9), so the §9.4 receiver recovers a bit
strobe whenever the line is up — idle `1010`, ringing zeros, or speech.

```
 downstream pair ──► §9.4 RX ──► recovered bit / half-bit clock
                                      │
                    ┌─────────────────┼─────────────────┐
                    ▼                 ▼                 ▼
              RX_CLK (64 k)     TX_CLK (= RX)      ÷ → ~1 Hz LED
              to decoder        upstream TX         face “line live”
              and S             dialer TICK
                                encoder
```

| | |
|---|---|
| **TX timing** | upstream encoder and `1100` / payload TX run on the **recovered** clock (hard lock or a small DPLL — `line-codes.md` §2.2 C). Slip-free toward the exchange |
| **S clocks** | `TX_CLK` and `RX_CLK` on S are both derived from that recovery (may be the same net on mk1) |
| **Dialer** | 1 kHz `TICK` = recovered 64 kHz ÷ 64, out to SU-K on **K** (§6.5) |
| **Line LED** | recovered clock ÷ ~64 000 → **≈ 1 Hz** blink. Watches **RX only**, never the upstream |
| **Dark LED** | no carrier, cut pair, or unpowered set — same “no downstream ⇒ no clock” fact that rejected carrier-off signalling (`subscriber-line.md` §6) |
| **Not** | a wall-clock 1.000 Hz; tracks the exchange crystal (±ppm), which is invisible at 1 Hz |

Short LOF / reacquire may stutter the LED for a moment. That is acceptable.

This closes the phone-side half of `subscriber-line.md` §7’s clocking open:
**SU-1 is loop-timed.** A free-run crystal population is not taken.

---

## 6. Three boards

All three are **100 × 100 mm**, 1.6 mm. SU-D and SU-A stack at **0.4″
(10.16 mm)** — same spacer family as `cvsd-codec.md` / `pcb/hookbusy/`. **SU-K**
is not in that stack: it carries the pad and mounts to the panel on a ribbon
(§6.5).

| board | role | mounting |
|---|---|---|
| **SU-D** | line PHY, phantom PSU, hook, clock recovery, line LED, **loudspeaker + loudspeaker VOL + ring VOL**, **mic jack**, **line out**, **HANDSET/SPEAKER**, **LIVE/PTT**, **PTT**, local ring tone, headers **S** and **K** | base of the stack |
| **SU-A** | type-A enc + dec + recon, **4P4C 600 Ω** handset, **handset VOL**, sidetone, mic mux / gate | riser on **S** |
| **SU-K** | 16 Autovon keys, debounce, encode, pulse sequencer, seize and interdigit timing | panel, on **K** |

> **SU-D is over a board even after SU-K left, and the count above is not
> settled.** Costed at ~22 packages plus both transformers, four conductors of
> gas tube / PTC / TVS, two switchers, the speaker amp and the face, SU-D is
> ~9 500 mm² of courtyard with the face panel-mounted — 95 % of a bare
> 100 × 100 before a track is laid, against the 33 % fill the only placed boards
> in this tree reach (`pcb/hookbusy/`). `mf8-trunk.md` §1 already refuses a
> *lighter* load than this on one 100 × 100 — "two line transformers with
> creepage beside the classifier" — and `stu-1.md` §3 puts STU-1's switchers
> "at the other end of the stack from a comparator whose hysteresis is fixed at
> ~50 mV", which is exactly the comparator SU-D seats them next to. Splitting
> SU-D again — a line board, a logic board, and an energy board carrying the
> loudspeaker channel, as `stu-1.md`'s ST-D / ST-L / ST-P do — is **open**
> (§9). The outline is not the problem; SU-D's contents are.

### Why the dial is its own board

1. **The pad sets its own outline.** A 4×4 pad at a usable ~15 mm pitch spans
   45 mm between outer key centres and wants about **60 × 60 mm** of board once
   margins and a bezel are allowed. On SU-D that was over a third of the base's
   area, claimed in the one place the base can least spare it — the face, where
   the speaker, three pots, three switches and two jacks already are. As its own
   board the pad *is* the layout and the sequencer fills the strip behind it.
2. **The pad is panel furniture; the stack is not.** Keys have to line up with a
   bezel at whatever height and rake the case wants. Spacers are the datum for
   SU-D / SU-A (`pcb/su-1/README.md`); the panel is the datum for the keys.
   Tying the two together over-constrains both.
3. **It matches the tree.** `stu-1.md` §12 gives this same circuit its own
   board, ST-K, in a five-board set. SU-1 and STU-1 now cut the dialler out at
   the same seam, so the two sets share the block instead of each adapting
   `pulse-gen.md` §5 separately.

Breaking SU-K out costs **no stack height**: SU-D + SU-A is still
10.16 + 1.6 ≈ **11.8 mm**. It does **not** even out the set. The split is
roughly **22 / 12 / 10** packages — SU-D still carries half the design and all
of the magnetics, protection, switchers and face furniture, so the mean is not
the distribution.

PCB stub: `pcb/su-1/README.md`. Schematic and copper are not drawn.

### 6.1 Mezzanine header **S**

Keyed **2×12** 0.1″ stackable (mate on SU-D top / SU-A bottom). Names from
SU-A's view. Same rails and bit/clock idea as shelf **R**, plus phone
controls that R deliberately omits.

| pin | name | dir | |
|---|---|---|---|
| 1 | `GND` | — | |
| 2 | `GND` | — | |
| 3 | `+5 V` | in | from SU-D |
| 4 | `+12 V` | in | |
| 5 | `−12 V` | in | |
| 6 | `GND` | — | |
| 7 | `TX_CLK` | in | 64 kHz encoder sample |
| 8 | `RX_CLK` | in | 64 kHz decoder sample — separate net |
| 9 | `BIT_ENC` | out | encoder → SU-D line TX mux |
| 10 | `BIT_DEC` | in | to decoder (after SU-D `RING→1010` gate) |
| 11 | `AUDIO_TX` | in | mic from SU-D jack path (when `MICJ` · SPEAKER); else unused |
| 12 | `AUDIO_RX` | out | recon (pre–handset-volume) → SU-D speaker amp and line out |
| 13 | `GND` | — | audio return |
| 14 | `MUTE` | in | dial off-normal — encoder silence |
| 15 | `RING` | in | ringer on SU-D; forces decoder `1010` on SU-D before `BIT_DEC` |
| 16 | `/OE` | in | optional; pull-down to run |
| 17 | `SPK` | in | 1 = **SPEAKER** mode (mute handset ear; enable talk into speaker) |
| 18 | `MIC_EN` | in | 1 = mic gate open (LIVE, or PTT held) |
| 19 | `Y_E` | out | test |
| 20 | `Y_D` | out | test |
| 21 | `GND` | — | |
| 22 | `GND` | — | |
| 23 | `GND` | — | spare / key |
| 24 | `GND` | — | |

`AUDIO_RX` / `AUDIO_TX` are analog about ground. `SPK` / `MIC_EN` / `MUTE` /
`RING` are 0 / +5 V HC. Handset ear and sidetone stay on SU-A; the base
speaker, mic jack, and line out live on SU-D.

### 6.2 Parts on SU-D (rough)

| block | parts |
|---|---|
| Line magnetics | 2× 1:1 ≥ 33 mH, centre taps out (`mf8-spec.md` §9.3) |
| Upstream TX | §9.2 encoder + 75176 half + matching — the phone transmits **upstream** (§2) |
| Downstream RX | §9.4 classifier at the 64 kbps plug — the phone receives **downstream** (§5) |
| Detectors | LM339 ring (zeros) only — `subscriber-line.md` §3 gives the phone **X = Q**, not the exchange's `Q ⊕ Q[n−2]`, and the hook here is the cradle switch, so there is no density hook detector on the set |
| Pattern gens | `1100` (bit clock ÷ 4); idle / mute `1010` |
| Hook | cradle switch, pull-up and ~20 ms RC; `HOOK` out on **K**. The dialler itself is SU-K (§6.5) |
| Clocks | §9.4 recovered strobe → 64 kHz / 128 kHz / 1 kHz `TICK` (out on **K**); optional DPLL |
| Line LED | recovered ÷ ~64k → ~1 Hz driver |
| Speaker | loudspeaker + amp; **loudspeaker** pot (talk); **ring** pot + local ring-tone oscillator gated by `RING` |
| Mic jack | input jack; `MICJ` jumper; fixed gain onto `AUDIO_TX` |
| Line out | jack + fixed pad from `AUDIO_RX` (no face pot; no ring tone) |
| Talk UI | **HANDSET/SPEAKER**, **LIVE/PTT**, **PTT** → `SPK` / `MIC_EN` on S |
| Power | 48 V phantom → +5, ±12 DC-DC; protection gas tube / PTC / TVS |
| Connector | line pairs + **S** + **K** |

### 6.3 Parts on SU-A (rough)

| block | parts |
|---|---|
| Codec | type A as `cvsd-codec.md` §4–5 — LM311, LM13700, 3× TL072, 3× '74, '86, '32, 2× 2N3906 |
| Recon | 3.4 kHz LPF → `AUDIO_RX` and handset path |
| Handset | **4P4C** jack, **600 Ω**; **handset** pot + ear amp; sidetone after that pot |
| Mic mux / gate | handset mic vs `AUDIO_TX`; open only if `MIC_EN`; also silenced by dial `MUTE` |
| Header | **S** mate |

No piezo on SU-A — the base speaker is the ringer.

### 6.4 Populations on S

| population | riser | face |
|---|---|---|
| **Voice only** | SU-A | handset, no DTE |
| **Data only** | SDU-1 (`sdu-1.md`) | DTE, no handset |
| **Dual mode** | one board with both engines (§7) | handset + DTE + **VOICE / DATA** switch |

One mating on S. Dual mode does not stack SU-A and SDU-1 as two layers.
**K is not part of this** — every population dials the same way.

### 6.5 SU-K — the dial, and header **K**

SU-K is `pulse-gen.md` §5's sequencer with the adjustable sources left off. §4
already rules them out — `TICK` is the recovered downstream, never a crystal and
never a pot — so the `SRC` mux and the '14 astable go with them.

| block | parts |
|---|---|
| Keys | 16 momentary, Autovon layout, ~15 mm pitch, pull-ups |
| Debounce | ~20 ms, ½ 74HC74 + RC |
| Encode 16 → 1..16 | 2× 74HC148 |
| Pulse count | ½ 74HC193 + one FF — five bits, so **P** still loads 16 |
| 60/40 break former | 74HC4017, ¼ 74HC4002 |
| Interdigit pause, one-deep queue | 74HC393 |
| Seize delay 500–800 ms | ½ 74HC123 |
| Lockout, off-normal | ¼ 74HC86, ½ 74HC74 |

**≈ 9–10 packages** — `pulse-gen.md` §5's eleven less the `SRC` mux and the RC
astable. Treat that as arithmetic; nothing is routed.

**SU-K is one of the tighter boards, not a loose one.** Ten DIPs with their
passives and decoupling are ~2 800 mm² of courtyard. The strip behind a 60 × 60
pad on a 100 × 100 board is 100 × 40 = 4 000 mm², which is **70 % courtyard
fill** — against the 33 % the only placed boards in this tree actually reach
(`pcb/hookbusy/`, both unrouted). Wrapping the logic into the L around the pad
gives 6 400 mm² and 44 %, still above that. Either the pad and the sequencer
share the board at a fill nothing here has demonstrated, or the pad is a key
board and the sequencer stays on SU-D. **Not settled** (§9).

At a real telephone pitch the problem is worse, not better: Bell / E.161 desk
sets are ~19 mm centres, which makes the field ~75 × 75 = 5 600 mm² and leaves
the sequencer nowhere on a 100 × 100. `stu-1.md` §12's ST-K uses **16 SMD keys**,
which is the other way out.

Header **K** is a keyed **2×5 0.1″** ribbon, not a mezzanine: SU-K's position is
fixed by the bezel, not by the spacers.

| pin | name | dir | |
|---|---|---|---|
| 1 | `GND` | — | |
| 2 | `+5 V` | in | from SU-D. SU-K is all HC — no ±12 crosses K |
| 3 | `TICK` | in | 1 kHz, recovered 64 kHz ÷ 64 on SU-D (§5) |
| 4 | `GND` | — | |
| 5 | `HOOK` | in | 1 = off-hook; cradle switch stays on SU-D (§3.1) |
| 6 | `BREAK` | out | 1 during a dial break → SU-D's `1100` mux |
| 7 | `OFF_NORM` | out | 1 while a train is out or queued → `MUTE` on **S** |
| 8 | `GND` | — | |
| 9 | `KEY_ANY` | out | spare / test: any key down |
| 10 | `GND` | — | |

**Nothing on K runs faster than 1 kHz.** `TICK` is the quickest signal on it and
the breaks are 60 ms of every 100, so the ribbon can be dressed anywhere in the
case without a thought for the ~50 mV hysteresis of the §9.4 comparator or for
the codec's analog cluster. That is the opposite of **S**, where 64 kHz clocks
and both bit streams cross the gap, and it is why the dialler is the block that
can safely leave the stack while the receiver chain cannot (`stu-1.md` §3).

**The hook stays on SU-D** even though it is a manual control like the keys.
SU-D needs `HOOK` for the `1100` mux whatever the dialler is doing, and a phone
that cannot go on-hook when the ribbon is unplugged is worse than one that
cannot dial.

**S is unchanged.** SU-K asserts `OFF_NORM`; SU-D passes it to SU-A as `MUTE` on
S pin 14 exactly as before. The riser, `sdu-1.md` and the dual-mode population
(§6.4) see no difference at all.

---

## 7. Dual mode — panel switch

A dual-mode set keeps **both** the type-A CVSD path and the SDU-1 data path on
one riser. A panel switch **VOICE / DATA** selects which engine drives
`BIT_ENC` and which listens to `BIT_DEC`. SU-D is unchanged: seize, dial
breaks (`1100`), ring, and phantom do not depend on the switch. On **DATA**,
rate is insert-1 32 kb/s by default, or RAW64 when both ends are nailed
(`sdu-1.md` §3.6).

```
                 ┌─ VOICE ─► CVSD enc ──┐
  mic / TXD ────┤                      ├──► BIT_ENC → SU-D TX mux
                 └─ DATA ──► SDU-1 ─────┘

  BIT_DEC ← SU-D ┬─ VOICE ─► CVSD dec → ear
                 └─ DATA ──► SDU-1 → RXD
```

| | |
|---|---|
| **Switch** | maintained, two positions; silk **VOICE** / **DATA**. No centre off required |
| **What it steers** | `BIT_ENC` / `BIT_DEC` only. Hook, pad, speaker UI, `MUTE` / `RING` / `SPK` / `MIC_EN`, clocks stay on the voice path logic |
| **When to throw** | before or during a call; there is no in-band mode digit and no far-end handshake |
| **Wrong setting** | the far end hears **noise** (or data hunt / DTE mark). Same class of failure as voice↔shelf-data today (`channel-cards.md` §1, `features.md` §8) |
| **Exchange** | sees a plain CVSD line card either way. Mode is not in the word and not on A. A line's *data* bit `D` remains optional hygiene so the marker can refuse known-bad setups; the switch does not need it to work |

Coordination is operational: both ends on VOICE, or both on DATA, or accept
garbage until they match. Flipping mid-call is allowed and ugly.

Mk1 dual-mode parts: SU-A engine + SDU-1 encode/decode/DTE on one 100 × 100
riser, plus a 74HC157 (or equivalent) on the switch, 4P4C and the DTE
connector both stuffed. Power budget is the sum; ±12 still required for the
codec half.

---

## 8. Against the exchange

Lift, wait, dial `h s`: a register on the line card's port counts the breaks
on A (derived from the `1100` detector). Dial `1 e b h s` and the same pulses
ride the flood (`network.md` §3). Nothing in the exchange is different from a
rotary phone on a CVSD line card. The tester cousin with no handset is
`pulse-gen.md`; SU-1 is the set with the codec and the ear. Dual-mode DATA
is still that line: opaque C bits once off-hook (`sdu-1.md` §9).

RTL: `verilog/rtl/su1.v` — phone digital on the simplified four-wire
subscriber interface (`line_card.v`). Full differential-Manchester PHY stays
out of that model, as on the line card. `make su1` runs the Autovon map, mute,
ring trip, and a local call.

---

## 9. Not measured / deferred

- **PCB.** Outlines and the **S** and **K** pin maps locked; schematic and
  copper not drawn.
- **SU-K mounting.** Panel on a ribbon is chosen (§6.5); bezel, key pitch, and
  the ribbon's length and dress are not drawn. Whether the pad would rather be
  the top of the spacer stack is not settled.
- **Key pitch.** ~15 mm is assumed everywhere (§6, §6.5, `pcb/su-1/README.md`,
  `stu-1.md` §9) and has never been checked against a hand. Real desk sets run
  ~19 mm. The 60 × 60 field, and with it SU-K's fit, descends entirely from
  this number.
- **Component height in the 0.4″ gap.** `hookbusy.md` §4 is the tree's only
  Z-axis figure — `10.16 − 1.6 board − 4 mm DIP = 4.5 mm` — and it was derived
  for all-logic lamp cards. SU-1 is the first board in this family to put
  magnetics and a switcher *in* the stack: a ≥ 33 mH can and a through-hole
  isolated DC-DC brick are both taller than that gap, so neither can sit on a
  middle layer. Stack **order** is constrained even though stack height is not.
- **SU-D does not fit.** Its ~22 packages plus both transformers, four
  conductors of gas tube / PTC / TVS, two switchers, the amp and the face are
  ~9 500 mm² of courtyard with the face panel-mounted — 95 % of a bare
  100 × 100, before a track. `mf8-trunk.md` §1 refuses a smaller load than this
  on one board, and `stu-1.md` §3 puts the switchers at the far end of the
  stack from the ~50 mV comparator that SU-D sits them beside. **Splitting SU-D
  is open** — see the note at the head of §6.
- **Dual-mode riser layout** and the VOICE/DATA switch bounce into `BIT_ENC`.
- **Speaker / handset acoustic howl** in SPEAKER + LIVE; PTT discipline assumed.
- **Local ring tone** into the speaker amp — timbre; level is the **ring** pot (independent of **loudspeaker**).
- **Phantom PSU** efficiency, rail noise into the codec, and feed imbalance
  (`subscriber-line.md` §7).
- **DPLL vs hard lock** of upstream TX to the recovered strobe — decided
  loop-timed (§5); circuit not drawn or measured.
- **Line LED** divide exactness and blink through LOF / ring bursts.
- **Real key bounce** and cradle chatter against the debounce.
- **Autovon precedence** dial-plan meanings for FO/F/I/P.
- **DTMF from the pad** — not fitted in mk1.
- **Glare** and switching transients — as `subscriber-line.md` §7.
