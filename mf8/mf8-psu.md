# MF8 PSU — two end boards, talk battery and ring

The MF8 shelf's power: what comes in, what the cards need, how −48 V talk
battery and 20 Hz ringing are made from a common low-voltage wall supply, and
why that splits across **two 100 × 100 mm boards** at the end of the stack.

The channel cards, rails on the socket, and per-slot fusing remain
`common-cards.md` §3 and `mf8-backplane.md` §8. This document is the supply
that feeds them once the shelf is a spacer-stack of 100 × 100 cards rather than
a Eurocard subrack with a monolithic PSU slot.

> **Status: proposed.** Nothing drawn, nothing on a bench. Currents are from the
> card specs (`channel-cards.md` §3.4, `common-cards.md` §3); converter topology
> is an assignment. Ring amplitude here is **~80 Vrms** at 20 Hz — the same role
> as `mf8-backplane.md` §8's "~90 Vrms", rounded to a buildable inverter target.

---

## 1. Input

| | |
|---|---|
| Nominal | **15–18 V DC**, unregulated — a common brick / wall-wart class |
| On the noisy board | reverse protection, bulk capacitance, UVLO into the converters |
| Not on this shelf | mains primary; −48 V plant battery; a central ring plant |

One input feeds every converter. Logic, analog, talk battery and ring are all
derived locally.

---

## 2. Rails the shelf presents

| Rail | Role | Who needs it |
|---|---|---|
| **`+5 V`** | 74HC, trunk digital, FXS logic half | every card |
| **`+12 V`**, **`−12 V`** | codec / op-amps (LM13700, TL07x, …) | FXS / FXO / E&M |
| **`−48 V`**, **`−48 RET`** | talk battery (FXS feed); CVSD phantom if those cards are fitted | FXS; CVSD line cards |
| **`RING`**, **`RING RET`** | 20 Hz, **~80 Vrms**, into FXS ring relays only | FXS layers, strapped |
| **`GND`** | logic return | every card |

`RING` is **not** drawn from the −48 V rail. An FXS card disconnects battery
feed while it rings and connects the ring bus instead (`channel-cards.md`
§3.4). Ringer current belongs on the ring inverter; talk-battery current is
loop feed only.

**Per-slot:** −48 V through a 100 mA PTC as `mf8-backplane.md` §8 already has
it. Feed bridges on the cards still current-limit 25–45 mA off-hook.

---

## 3. Two converter paths from the bulk input

Both start from the same 15–18 V bulk.

### 3.1 Talk battery — regulated −48 V

| | |
|---|---|
| Output | **regulated −48 V** (usable window about −42 to −56 V under load) |
| Load (six FXS) | ~0.3 A if all off-hook at 45 mA; design headroom **~0.5–1 A** |
| Power at 1 A | 48 W out → ~55–65 W in → several amps from 15 V |
| Care about | stay in the battery window; **low audio-band ripple** (hum into the hybrid); current limit / foldback |
| Do not need | ±1 % setpoint accuracy |

Topology: inverting buck-boost or flyback from the bulk rail — an assignment.
Switching residue is filtered hard before the stack; this is talk battery, not a
logic rail.

A **−24 V** stuffing option remains sensible for short premise loops only; the
socket and silkscreen in `common-cards.md` still name **−48 V**, so −24 is a
PSU population, not a silent rename.

### 3.2 Ring — ~80 Vrms at 20 Hz

| | |
|---|---|
| Output | **`RING` / `RING RET`**, ~80 Vrms, 20 Hz |
| Path | boost / flyback to HV, then a **20 Hz inverter** (H-bridge or chopper) — a ring generator, not a DC buck-boost alone |
| Cadence | gated: free-running 80 V into an idle bus is unnecessary. Enable from shelf cadence or from “any FXS relay demanding ring” |
| Load | REN × open-circuit voltage — tens of mA per ringer, not an amp from −48 V |

Noise from this stage is why it does not share a board with the codec rails.

---

## 4. Two boards

**100 × 100 mm**, same outline as the channel and trunk cards. Split by noise,
not by voltage count alone.

### 4.1 Noisy board — intake and AC

- 15–18 V entry, protection, bulk storage  
- **Ring inverter** (§3.2)  
- The big **−48 V** power stage (§3.1) — a tens-of-watts chopper; keep it here  
- Pass header toward the quiet board: bulk and/or semi-regulated feeds, returns, ring enable / cadence  

Wall-wart and plant-facing energy land here first.

### 4.2 Quiet board — regulated distribution

- **`+5 V`**  
- **`±12 V`** — post-filtered or linear after a switcher so the codecs stay clean  
- **−48 V** finish: LC filter and distribute, or a second quiet stage if the noisy board only delivers a rough intermediate  
- Soft feed into the channel stack; star point for returns  

`±12` is the rail that must stay quiet. −48 V after filtering is “quiet enough
for feed”; it is never as clean as a linear analog supply, and does not need to
be.

### 4.3 Pass header (noisy ⇄ quiet)

Short, keyed, board-to-board — not the channel stack header. Carries bulk DC,
`−48` (raw or finished), `RING` pair if the inverter is on noisy and the quiet
board only distributes, enables, and **separate returns**. No channel clocks,
no `C`/`A`.

---

## 5. Where it sits in the stack

Mechanical form is the spacer-stack of 100 × 100 cards (channel layers through
a pinheader, trunk split across Trunk-D / Trunk-A with its own pass header).
Power is two more boards at the end:

```
  FXS ×6  ══ C ══  Trunk-D ══ pass ══ Trunk-A ══  Quiet PSU ══ pass ══ Noisy PSU ── 15–18 V in
                                                      │                │
                                                   +5, ±12,          intake,
                                                   −48 out           −48 stage,
                                                   into stack        RING inverter
```

Order can swap Quiet/Noisy if the wall entry must be the outermost board; the
rule is only that **ring and intake stay on the noisy card** and **`±12` /
`+5` distribution stay on the quiet one**.

`RING` is strapped only to layers that hold FXS cards, as
`mf8-backplane.md` §8 already requires.

---

## 6. Populations — what to leave off

| Shelf content | Fit |
|---|---|
| FXS (this document's baseline) | full: +5, ±12, −48, ring |
| FXO only | +5, ±12; no −48, no ring (battery from the CO) |
| CVSD line cards only | +5, −48 (phantom); no ±12, no ring |
| Trunk + gateway bring-up, no channels | +5 (and whatever Trunk-A's line interface needs) |

A board outline that always has the footprints, with converters unpopulated, is
fine: an FXS shelf must be able to arrive later (`common-cards.md` §3).

---

## 7. Grounding

| Return | Joins |
|---|---|
| `GND` | logic, +5, ±12 reference |
| `−48 RET` | talk battery / phantom return — **separate** from logic through the stack |
| `RING RET` | ring return — **separate** again |

Join the three only at the **PSU star** (quiet board or the pass between the
two). Do not daisy-chain plant returns through channel cards into logic ground.

---

## 8. What this changes in other documents

| document | |
|---|---|
| `mf8-backplane.md` §8 | PSU slot becomes these two end boards; ring amplitude may be cited as ~80 Vrms here while the backplane's "~90" remains the classical figure — same bus, build target in this file |
| `common-cards.md` §3 | rails unchanged; supply that makes them is this document |
| `channel-cards.md` §3.4 | FXS still expects a shelf `RING` bus and −48 feed; no card change |
| trunk split (Trunk-D / Trunk-A) | not power; classifier on A, pass header of its own — beside this stack story, not inside it |

---

## 9. Not measured, and open

- **Every converter.** No schematic, no magnetics, no efficiency or ripple number.  
- **Ring open-circuit voltage and REN capacity** — ~80 Vrms is a target; confirm against the phones you actually hang on FXS.  
- **Whether −48's power stage is entirely on the noisy board** or split as rough + quiet post-reg — §4 allows either; pick at layout.  
- **Cadence source** that gates the ring inverter (shelf `/RING_CAD` equivalent vs diode-OR of relay demands).  
- **Thermal on 100 × 100** at ~50 W talk-battery class — may force a taller stack pitch, heatsink, or derating below 1 A.  
- **Safety / creepage** for −48 and ~80 Vrms beside a 15–18 V inlet on the noisy board — still required; deriving HV from LV does not retire it.  
- **Hot-plug** of PSU boards or channel layers with feeds live — not considered.  
- **Exchange blocks** — out of scope; they keep per-subrack PSUs and never put −48 or `RING` on Cable A (`mainboard.md` §2.4).
