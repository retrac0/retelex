# MF8 trunk — two 100 × 100 boards and the pass between them

The trunk function of `mf8-spec.md` §§9–11 on **two boards**: **Trunk-D**
(digital — clocks, muxes, framer, stack drivers) and **Trunk-A** (analog — line
magnetics, encoder/driver, comparator, **§9.4 classifier**). They share a short
keyed **pass header**. Channel cards and the PSU sit on the spacer-stack of
`mf8-psu.md` §5; this document is only the trunk split.

> **Status: proposed.** Package counts are from `mf8-spec.md` §10–11 and
> `mf8-backplane.md` §8; the pass pinout is an assignment. Nothing laid out.
> **Gateway / Pico slot: deferred** — not placed in the stack yet.
> **Channel through-header C wiring: deferred** — pin *roles* remain
> `common-cards.md` §1; layer geometry is not written here.

---

## 1. Why two boards

One 100 × 100 cannot hold the framer, both demuxes, the clock `244`, *and* two
line transformers with creepage beside the classifier. Splitting at the
classifier keeps plant energy and interval timing on A, and every multi-drop
stack driver on D.

| Board | Owns | ≈ packages |
|---|---|---|
| **Trunk-D** | Crystal / `4040` / `393`, frame and signalling muxes, F gen, framer **without** the classifier, C and A holds, `MUTE` / `LOCK` / `CD`, eight C/A pairs; on an exchange, collect T + commons C | **≈ 16–20** |
| **Trunk-A** | TX encoder + `75176` + transformer + protection; RX transformer, filter, comparator, **§9.4 classifier**, carrier detect | **≈ 6–8** + **2** transformers |

Rear plant (trunk pair) leaves **Trunk-A** only (`common-cards.md` §7.3). Optional
`LOCK` / `CD` lamps face the operator from either board; electrically they are
Trunk-D outputs.

---

## 2. The pass header (Trunk-D ⇄ Trunk-A)

Board-to-board, short, keyed — **not** the channel stack header C, **not** the
PSU pass. Directions below are **signal flow**.

### 2.1 D → A (transmit path into the line)

| signal | rate | what |
|---|---|---|
| `TX_BIT` | 512 kb/s | frame-mux serial bit, before the biphase encoder — F, S, and the six C bits in turn (`mf8-spec.md` §10) |
| `HB` | 1.024 MHz | half-bit clock; clocks the encoder on A (`mf8-spec.md` §9.1–9.2) |
| `+5 V` | | logic for A |
| `GND` | | |

`TX_BIT` changes on the bit boundary in T; the encoder on A decides mid-cell on
`HB`. No need to pass `TX_CLK` if `HB` and `TX_BIT` are enough for §9.2.

### 2.2 A → D (receive path into the framer)

| signal | rate | what |
|---|---|---|
| `RX_BIT` | ~512 kb/s | recovered data bit from the classifier |
| `RX_STB` | ~512 kHz | accepted-transition strobe that writes the bit (classifier “emit”) |
| `/CD` | level | carrier detect, low = no carrier — forced LOF into the framer (`mf8-spec.md` §9.6) |
| `GND` | | return with the above |

The framer, both `259`s, `RX_CLK` / `RX_OCT` / `MUTE` / `LOCK` / `CD` for the
**stack** are generated on **D** from `RX_BIT`, `RX_STB`, and `/CD`. Nothing
analog crosses the pass.

### 2.3 Suggested 2 × 5 (or 2 × 6 with spare)

Odd pins signal, even ground — same idiom as the exchange ribbons:

| pin | | pin | |
|---|---|---|---|
| 1 | `TX_BIT` | 2 | `GND` |
| 3 | `HB` | 4 | `GND` |
| 5 | `RX_BIT` | 6 | `GND` |
| 7 | `RX_STB` | 8 | `GND` |
| 9 | `/CD` | 10 | `GND` |
| 11 | `+5 V` | 12 | spare (key / future) |

Key the shell so A and D cannot mate reversed. Stub length: keep the boards
adjacent in the stack (`mf8-psu.md` §5).

---

## 3. What each board presents elsewhere

| Interface | Board | |
|---|---|---|
| Channel stack header **C** | **Trunk-D** | Clocks, `MUTE`, six `C_TX`/`A_TX` in, six `C_RX`/`A_RX` out — roles of `common-cards.md` §1 / `mf8-backplane.md` §3. **How C is fanned through six layers: deferred.** |
| Trunk pair rear | **Trunk-A** | Four conductors (pair each way) |
| Trunk pass | both | §2 |
| PSU rails into the stack | Quiet PSU → C nets | not via this pass (`mf8-psu.md`) |

---

## 4. Decisions locked here

- **Classifier on Trunk-A** — clean digital `RX_BIT` / `RX_STB` / `/CD` toward D.  
- **Encoder and `75176` on Trunk-A** — `TX_BIT` + `HB` toward A.  
- **100 × 100** outline, same family as channel and PSU cards.  
- **Gateway slot: deferred** — Pico / mirrored 2 × 32 not placed in this stack yet.

---

## 5. Open

- Exact stack order of D vs A relative to the six FXS layers (ASCII in
  `mf8-psu.md` §5 puts D then A; either order works if C lands only on D).  
- Whether `H` (line bit clock) is derived on A from `HB` or also passed.  
- Rate-plug parts for the classifier — on A with the timers.  
- Bench: scope `TX_BIT`→line and `RX_STB`→`259` write against `mf8-spec.md` §5
  margins with the pass in between.
