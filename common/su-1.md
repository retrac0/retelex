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
                         ║ S  (board-to-board)
  Autovon pad ─────────► SU-D (line / dial / power)
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
| **Handset** | 4P4C jack on SU-A (mic, ear, common, spare or sidetone return) |
| **Dial** | sixteen keys, Autovon labels, **pulse only** — same 1–16 map as `pulse-gen.md` §4 |
| **Clocking (mk1)** | free-run crystal on SU-D. Loop-timing from the downstream is open (`subscriber-line.md` §7) |

The shelf CVSD codec **R** riser (`cvsd-codec.md`) is a different host and
header. SU-A reuses the same engine parts with a phone-specific **S** header
(§5). The same **S** accepts **SDU-1** (`sdu-1.md`) instead of SU-A: a 32 kb/s
data riser; SU-D still owns the line code and `1100`.

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
TX   = ON-HOOK or dial break  ?  1100  :  CVSD encoder
encoder input = dial off-normal ? silence : microphone
ring = RING · ON-HOOK                                 → sounder
decoder input = RING ? 1010 : Q ;  audio muted while ON-HOOK
```

**Mute while off-normal** is mandatory so makes carry `1010` and the register
sees a fixed shortening (`subscriber-line.md` §5, `register.md` §1.1).

---

## 3. Face and connectors

| face | |
|---|---|
| **Pad** | 4×4 momentary keys, Autovon / DTMF layout (§4) |
| **Hook** | cradle or switchhook; open = on-hook |
| **Handset** | 4P4C on SU-A |
| **Line** | two pairs (RJ45 or terminal block on SU-D) — tip/ring of each pair; no third pair |
| **Sounder** | piezo / transducer on SU-A, driven by `RING` |

No exchange channel socket. No DTMF generator on the pad in mk1: every key
is a pulse count. In-band DTMF remains possible later through the codec if a
tone source is added; the network flood still needs pulse on A
(`network.md` §3).

---

## 4. Keypad and dialer

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

**Timebase (mk1):** crystal path only — **10 pps, 60/40**, seize wait
500–800 ms before the first digit, 700 ms interdigit, ~20 ms debounce,
one-key lockout while a train is out, **one-deep queue**. Same structure
as `pulse-gen.md` §2.1 / §3, but `TICK` comes from the **on-board** crystal
divided, not shelf `TX_OCT`. No RC/DIP adjustable source on the set.

The dial contact is the pulse sequencer: breaks assert the on-hook pattern
(`1100` on the line; on the simplified RTL interface, `m` drops as
`phone.v` / `pulse_gen` do).

---

## 5. Two boards

Stack of two **100 × 100 mm** boards, **0.4″ (10.16 mm)** pitch — same
spacer family as `cvsd-codec.md` / `pcb/hookbusy/`. SU-D is the base (line
face); SU-A is the riser (handset face).

| board | role |
|---|---|
| **SU-D** | line PHY, phantom PSU, dial / hook digital, keypad, local crystal, header **S** |
| **SU-A** | type-A enc + dec + recon, 4P4C, sidetone pad, ringer driver |

PCB stub: `pcb/su-1/README.md`. Schematic and copper are not drawn.

### 5.1 Mezzanine header **S**

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
| 11 | `AUDIO_TX` | — | reserved / sense (mic path is local on SU-A) |
| 12 | `AUDIO_RX` | — | reserved / sense (ear path is local on SU-A) |
| 13 | `GND` | — | audio return |
| 14 | `MUTE` | in | encoder silence while dial off-normal |
| 15 | `RING` | in | sounder arm; also forces decoder `1010` on SU-D before `BIT_DEC` |
| 16 | `/OE` | in | optional; pull-down to run |
| 17 | `SYL_E` | out | test |
| 18 | `SYL_D` | out | test |
| 19 | `Y_E` | out | test |
| 20 | `Y_D` | out | test |
| 21 | `GND` | — | |
| 22 | `GND` | — | |
| 23 | `GND` | — | spare / key |
| 24 | `GND` | — | |

Mic and ear stay on SU-A; they do not cross S as primary audio. `MUTE` and
`RING` do.

### 5.2 Parts on SU-D (rough)

| block | parts |
|---|---|
| Line magnetics | 2× 1:1 ≥ 33 mH, centre taps out (`mf8-spec.md` §9.3) |
| Downstream TX | §9.2 encoder + 75176 half + matching |
| Upstream RX | §9.4 classifier at the 64 kbps plug |
| Detectors | LM339 RC hook (`1100`) and ring (zeros) — `subscriber-line.md` §3 |
| Pattern gens | `1100` (bit clock ÷ 4); idle / mute `1010` |
| Dial / hook | `pulse-gen.md` §5 circuit adapted (~11 HC packages), Autovon keys, hook switch |
| Clocks | local crystal → 64 kHz / 128 kHz / 1 kHz `TICK` |
| Power | 48 V phantom → +5, ±12 DC-DC; protection gas tube / PTC / TVS |
| Connector | line pairs + **S** |

### 5.3 Parts on SU-A (rough)

| block | parts |
|---|---|
| Codec | type A as `cvsd-codec.md` §4–5 — LM311, LM13700, 3× TL072, 3× '74, '86, '32, 2× 2N3906 |
| Recon | 3.4 kHz LPF on decoder |
| Handset | 4P4C; mic bias; ear drive; sidetone pad |
| Ringer | driver from `RING` to piezo / transducer |
| Header | **S** mate |

---

## 6. Against the exchange

Lift, wait, dial `h s`: a register on the line card's port counts the breaks
on A (derived from the `1100` detector). Dial `1 e b h s` and the same pulses
ride the flood (`network.md` §3). Nothing in the exchange is different from a
rotary phone on a CVSD line card. The tester cousin with no handset is
`pulse-gen.md`; SU-1 is the set with the codec and the ear.

RTL: `verilog/rtl/su1.v` — phone digital on the simplified four-wire
subscriber interface (`line_card.v`). Full differential-Manchester PHY stays
out of that model, as on the line card. `make su1` runs the Autovon map, mute,
ring trip, and a local call.

---

## 7. Not measured / deferred

- **PCB.** Outline and S pin map locked; schematic and copper not drawn.
- **Phantom PSU** efficiency, rail noise into the codec, and feed imbalance
  (`subscriber-line.md` §7).
- **Free-run slip** vs loop-timed upstream — open, same as the line doc.
- **Real key bounce** and cradle chatter against the debounce.
- **Autovon precedence** dial-plan meanings for FO/F/I/P.
- **DTMF from the pad** — not fitted in mk1.
- **Glare** and switching transients — as `subscriber-line.md` §7.
