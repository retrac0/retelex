# The exchange — local eight-channel highway trunk

A **short-range** tie between two exchanges: one block at each end, eight
trunk channels, the wire a bidirectional copy of a highway-shaped `C` and `A`
stream. No line code, no F and S, no crystal of its own. It is the copper peer
of an MF8 trunk group for runs inside a room or between adjacent racks — eight
payload seats where fused MF8 gives six.

> **Status: proposed.** Nothing measured on a bench. It is a **block adapter**
> on the **block header** (`fabric.md` §5.2); the clocking rule is stated here;
> package counts are a sketch. No RTL and no `exch.py` model yet.

---

## 1. What it is

```
 exchange 22, block h                         exchange 23, block k
 eight port circuits                         eight port circuits
      │                                           │
 block header ◀── local-trunk unit ══ C_hw, A_hw, ══ unit ──▶ block header
                 HCLK, TX_CLK each way
```

Each end occupies a whole block **1–7**, stuffed as a **block adapter**
(`fabric.md` §5.2): the unit mates the block header; the block-ribbon slots are
not populated; eight port circuits sit behind the header. Every port is class
trunk, one shared direction word, `/ANS` tied low. The marker, the flood and
the monitors treat the group as they treat any other trunk block.

**The wire is highway-shaped, not a tap of `HC[h]`.** Eight cells a frame at
512 kbps, `C` and `A` on separate conductors, ordered by `SLOT`. Transmit is a
mux of the eight ports' `C_RX` / `A_RX` on the *local* `SLOT`. Receive is demuxed
on the *far* end's clocks into holds, then crossed into the local domain as
`C_TX` / `A_TX`. The block's own `'151` then makes `HC[h]` / `HA[h]` as for any
stuffing. Feeding the transmitter from `HC[h]` would loop the link
(`baseband.md` §6); this unit never does that.

```
  local C_RX[0..7], A_RX[0..7]  ─▶  '151 on local SLOT  ─▶  TX C_hw, A_hw
       + local HCLK, TX_CLK                              ─▶  wire

  wire RX C_hw, A_hw            ─▶  demux on far HCLK / far TX_CLK  ─▶  holds
       + far HCLK, far TX_CLK   ─▶  '174 cross on local TX_CLK      ─▶  C_TX, A_TX
                                                                    ─▶  block commutator ─▶ HC[h], HA[h]
```

---

## 2. Against the other copper and MF8

| | this unit | baseband trunk (`baseband.md`) | fused MF8 (`mf8-unit.md` §1) |
|---|---|---|---|
| channels | **eight** | one | six (F, S steal 0 and 4) |
| face | **block adapter** on the block header | one **slot** on the block ribbon | **block adapter** on the block header (six of eight appearances) |
| wire | highway-shaped `C`+`A` + clocks | one `C` + one A (± clock) | MF8 pair, line code, framer |
| map | `h0–h7` all trunks | any single slot | `h1–h3`, `h5–h7` |
| reach | short: room / adjacent racks | short; RS-422 between racks | MF8 reach |
| clocks | TX local; **RX master-timed by far `HCLK`** (§4) | sample at local `TX_CLK`; optional far `TX_CLK` conductor | recover from the line |

A direction may mix carriers (`network.md` §1.1). This unit is for when eight
channels of copper are cheaper than an MF8 group and a single baseband card is
not enough.

---

## 3. The face — block header

Exactly `fabric.md` §5.2. Live MF8 uses the same header (`mf8-unit.md` §1);
this document is the eight-channel copper rear on that contract.

| | |
|---|---|
| **appearances** | eight: `C_TX` / `A_TX` out, `C_RX` / `A_RX` in, word, `/ANS` |
| **commons** | `TX_CLK`, `TX_OCT`, `FILL` in; **`MUTE_BLK` out** |
| **rear** | the highway-shaped link (§5), not on the header, not on H |

**Word.** Two 74HC165 daisy-chained to all eight: class trunk, direction N/E/S/W, glare `g`
(`extensions.md` §2.2). Gated by link-up (§6). Power-up RC as usual.

**`/ANS`.** Tied low on the board. Trunks do not ring.

**`MUTE_BLK`.** Asserted while link down. The block ORs it into `BUSY` when the
header is stuffed for this unit. Monitors still read this block's M — the unit's
`A_TX`.

**Eight port circuits** behind the header: latch, selects, capture, supervision.
Claim OR on A as for any trunk block (`fabric.md` §3.1).

---

## 4. Clock domains

Each exchange keeps its own crystal. Nothing on this link slaves a clock card.

| path | timed by | what |
|---|---|---|
| **Transmit** | **local** `SLOT`, `HCLK`, `TX_CLK` | mux of `C_RX` / `A_RX`; drive `C_hw`, `A_hw`, and copy local `HCLK` and `TX_CLK` onto the wire |
| **Receive demux** | **far** `HCLK` and far `TX_CLK` | the far exchange is master of this direction. Slot counter on the unit resets from far `TX_CLK`, steps on far `HCLK`. Sample `C_hw` / `A_hw` into eight holds |
| **Present to the block** | **local** `TX_CLK` | two `'174`s (or equivalent) cross the eight C bits into T; A through RC + Schmitt as MF8 (§14). Then ordinary `C_TX` / `A_TX` into the commutator |

**Why carry `HCLK`, not only `TX_CLK`.** The highway eye is one cell (~1.95 µs).
Sampling a free-running 512 kbps stream with a local cell clock is the wrong
margin for short copper. The receiver must track the far transmitter's cell
clock. Far `HCLK` *is* that clock. Far `TX_CLK` is only the frame mark that
keeps the eight seats aligned (`SLOT` itself is not on the wire).

**Slip.** The two crystals wander. The crossing into local T is the same class
of slip `mf8-backplane.md` §7 measured on an MF8 trunk — audible as nothing on
voice, and out for bit-exact synchronous data across the link
(`network.md` §8). Octet phase inside each exchange is untouched.

**What is not done.** The local clock card is not slaved to the link. The block's
commutator and every other port stay on the local `HCLK` / `SLOT`. Only this
unit's receive demux is far-mastered.

---

## 5. The wire

Each way, short range:

| signal | rate | role |
|---|---|---|
| `C_hw` | 512 kbps NRZ | eight C bits, cell 0…7 |
| `A_hw` | 512 kbps NRZ | eight A bits, same cells |
| `HCLK` | 512 kHz | RX master clock at the far end |
| `TX_CLK` | 64 kHz | frame mark; resets the far RX slot counter |

Eight signal conductors + returns. **Baseline: single-ended 74HC on twisted
pair**, 33 Ω at the driver, common ground — one rack or a short run between
adjacent racks on the same ground (`baseband.md` §3.4's in-rack row).
**Between racks on separate grounds:** the same four signals as RS-422 / V.11
(26LS31 / 26LS32), four pairs each way.

No line code. No transformers in the baseline. Isolation and longer plant are
MF8's job.

**Idle.** An idle trunk port's far latch listens to 00, so the far `C` cell is
`FILL` and A is 0 when that channel is free and on-hook — the same pattern a
listener already expects.

---

## 6. Link-down

Far `HCLK` absent for *n* frames (retriggerable, same idea as
`baseband.md` §3.3's clock-loss detector):

- float the eight word pins → unequipped, leave the hunt
- hold every `A_TX` at 0 → M falls, calls release
- present `FILL` on every `C_TX`
- assert `MUTE_BLK`

*n* is a few frames — long enough to ride a glitch, short enough that a pulled
cable leaves the hunt before the next seizure. Exact constant unchosen until
the board is scoped.

---

## 7. The map

```
 networked   block h (1–7) stuffed as this unit:  h0–h7  eight trunk channels
             further groups: more blocks, eight lines lost each
 standalone  no trunk block; 1 is a highway digit
```

**Block 0 is never this group** — tones and the operator bank. Single-channel
baseband trunks may still sit in 06–07 (`network.md` §1.1).

**Digit 1** on a networked exchange is still the flood, so 10–17 remain
undialable as lines. Putting the first local-trunk group in block 1 wastes no
line numbers and gives eight channels where an MF8 group on that block gives
six.

At 1 % blocking, eight channels carry **3.13 E** (`erlang_cap`); six carry
1.91 E. Glare still wants the word's `g` bit.

---

## 8. Parts (sketch)

Not drawn.

| function | part | |
|---|---|---|
| TX mux `C`, `A` | 2 × 74HC151 on local `SLOT` | 2 |
| TX drivers | ¼–½ '244, or 26LS31 | 1 |
| RX receivers | Schmitt / 26LS32 | 1 |
| RX slot counter | ½ '393 or '163, reset by far `TX_CLK`, clock far `HCLK` | 1 |
| RX demux holds | 2 × '174 (C); A levels or a second '174 | 2–3 |
| Local crossing | 2 × '174 on local `TX_CLK` | 2 |
| A path | RC + Schmitt, eight ways (or shared after demux) | ≈ 1–2 |
| Card word, `/ANS`, `MUTE_BLK`, link-down | ≈ 3¼ + ½ | ≈ 4 |
| | **≈ 14–18** | beside the eight port circuits the block already has |

No 4.096 MHz, no classifier, no magnetics in the baseline.

---

## 9. Bring-up

1. **Link alone.** Two units, header appearances unterminated or looped (`C_RX`
   tied to `C_TX` on a jig). Far `HCLK` present both ways; `MUTE_BLK` falls;
   scope `C_hw` against far `HCLK`, and the `'174` write against local `TX_CLK`.
2. **One block stuffed, no far end.** Eight ports unequipped; `MUTE_BLK` high;
   lamp field dark on hook / lit on busy (`observers.md`).
3. **Far end a second exchange.** Seize one channel from the console; speech;
   both release orders. Pull the cable: both ends release, group leaves the
   hunt.
4. **Flood.** One networked call across the group; monitor sees dial pulses on
   A (`monitor.md`).

Step 1 does not need the fabric. Step 2 is `fabric.md` §7 with a block adapter
on the header.

---

## 10. Not measured / open

- The link-down retrigger constant (*n* frames).
- In-rack eye at 512 kbps on the chosen pair length; whether the RS-422
  population is wanted for the first boards.
- Whether A should be a level held for the cell (as drawn) or a slower
  conductor of its own — level-in-cell matches the highway and costs no extra
  pair.
- RTL and an `exch.py` battery.
- Slaving a whole exchange to the link: **declined** (§4).

---

## 11. Index

| | |
|---|---|
| block header / block adapter | `fabric.md` §5.2 |
| one-channel copper | `baseband.md` |
| six-channel MF8 | `mf8-unit.md` §1, `network.md` §1 |
| carrier rules | `network.md` §1.1 |
| clocks in the exchange | `clocks.md` |
