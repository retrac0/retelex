# The exchange — local eight-channel highway trunk

A **short-range** tie between two exchanges: one block at each end, eight
trunk channels, the wire a bidirectional copy of a highway-shaped `C` and `A`
stream. No line code, no F and S, no crystal of its own. It is the copper peer
of an MF8 trunk group for runs inside a room or between adjacent racks — eight
payload seats where fused MF8 gives six.

> **Status: RTL and a bench (2026-09-25); no board, no `exch.py` model.** It is a
> **block adapter** on the **block header** (`fabric.md` §5.2).
> `newimpl/rtl/local_trunk.v` is the unit and `newimpl/tb/tb_ltu.v` its bench:
> two exchanges on two crystals, sixteen channels patched by hand. Measured
> there: the word on every channel, `MUTE_BLK` busying the group on a cut, eight
> patterns each way in order with no channel carrying another's, A per channel
> end to end, and slips at 1000 ppm that keep every channel on its own port. A
> bare pair of units beside them, driven with a random bit a frame on `C` and on
> A, shows A slipping in all sixteen directions: one bit each time, A and `C`
> together, and no A bit on another channel.
>
> `newimpl/tb/tb_lnet.v` dials across it, B's crystal 100 ppm fast: a flood
> seizes the lowest channel and B claims; two calls ride two channels at once;
> from the glare end the key hunts from the top, so the two ends start at
> opposite channels; a pulled cable busies the group and a key finds no trunk.
> `tb_lfull.v` fills all eight channels, refuses a ninth call from either end,
> and provokes glare on the last free one: both origins count it and the two
> callers are joined, as `network.md` §1 has it. `tb_lchain.v` transits a
> middle exchange across two groups, two calls at once.
> Not measured: the eye on a real cable, a cut during a dialled call.
> Package counts are a sketch.

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
| **commons** | `TX_CLK`, `TX_OCT`, `FILL` in; **`MUTE_BLK` out**; **`HCLK` in, on the commons' spare** |
| **rear** | the highway-shaped link (§5), not on the header, not on H |

**Word.** One 74HC165 to all eight: class trunk, direction N/E/S/W and glare `g`, all three in the primary octet
(`extensions.md` §2.2). Gated by link-up (§6). Power-up RC as usual.

**`/ANS`.** Tied low on the board. Trunks do not ring.

**`HCLK` on the spare.** A 512 kbps mux needs the cell clock, and `fabric.md`
§5.2's commons carry only the 64 kHz `TX_CLK`. `mainboard.md` §5 already has the
MF8 unit taking `HCLK` through the block. `SLOT` is not needed: the unit counts
cells itself (§4).

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
| **Transmit** | **local** `HCLK`, `TX_CLK` | a cell counter rebuilds `SLOT`; two '151s mux `C_RX` / `A_RX`; a '74 drives `C_hw`, `A_hw` at `HCLK`'s rise; local `HCLK` and `TX_CLK` go onto the wire |
| **Receive demux** | **far** `HCLK` and far `TX_CLK` | the far exchange is master of this direction. The same cell counter on the far clocks; two '259s take `C_hw` / `A_hw` at the far `HCLK`'s fall |
| **Present to the block** | **local** `TX_CLK` | two '273s cross the sixteen bits into T at the local frame edge. Then ordinary `C_TX` / `A_TX` into the commutator |

**Every edge on the wire is clocked half a cell from the edge that samples
it.** A port's `C_RX` and `A_RX` change at the mid-cell capture, `HCLK`'s fall;
the unit samples them at `HCLK`'s rise and changes the wire there; the far end
samples at the far `HCLK`'s fall. No transmit latch is needed: the ports hold
each bit for a frame already.

**Cell 0 is found at mid-cell, not at `TX_CLK`'s rise.** `TX_CLK` rises on the
same clock-card edge as `HCLK`, so a counter cleared by that rise and stepped by
`HCLK` races itself. Sampled at `HCLK`'s fall, `TX_CLK` is high in cells 0–3 and
low in 4–7, so its first high sample is cell 0. A quarter '74 remembers the
last sample. Fault F31 removes the realignment and every channel's bits land on
another's port.

**A has no RC here.** It arrives as a clocked bit in its own cell, sampled
mid-cell and crossed at the frame edge like `C`: there is no raw wire to
filter. Measured in `tb_ltu`: each edge of A crosses in under 0.1 ms, and a
40 ms make keeps its length to 0.05 ms.

**Why carry `HCLK`, not only `TX_CLK`.** The highway eye is one cell (~1.95 µs).
Sampling a free-running 512 kbps stream with a local cell clock is the wrong
margin for short copper. The receiver must track the far transmitter's cell
clock. Far `HCLK` *is* that clock. Far `TX_CLK` is only the frame mark that
keeps the eight seats aligned (`SLOT` itself is not on the wire).

**Slip.** The two crystals wander. The crossing into local T is the same class
of slip `mf8-backplane.md` §7 measured on an MF8 trunk — audible as nothing on
voice, and out for bit-exact synchronous data across the link
(`network.md` §8). Octet phase inside each exchange is untouched. Measured in
`tb_ltu` with the crystals 1000 ppm apart for 150 ms: every channel slipped, the
worst direction kept 96.8 % of its 32-bit windows whole, and **no bit ever
landed on another channel**.

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
1.91 E. Glare still wants the word's `g` bit, now frame 5 of the primary.

---

## 8. Parts (sketch)

Not drawn.

| function | part | |
|---|---|---|
| TX cell counter | '163, and a quarter '74 remembering `TX_CLK` | 1¼ |
| TX mux `C`, `A` | 2 × 74HC151 on the counter | 2 |
| TX output | half a '74 at `HCLK`'s rise | ½ |
| TX drivers | ¼–½ '244, or 26LS31 | 1 |
| RX receivers | Schmitt / 26LS32 | 1 |
| RX cell counter | '163 and a quarter '74, on the far clocks | 1¼ |
| RX demux holds | 2 × '259 | 2 |
| Local crossing | 2 × '273 on local `TX_CLK` | 2 |
| Gating: `FILL` on `C`, A off, while link down | '157 × 2, '08 × 2 | 4 |
| Card word, `/ANS`, `MUTE_BLK`, link-down | one '165, eight 2N7002s, ½ '123 | ≈ 2 |
| | **≈ 17** | beside the eight port circuits the block already has |

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
- An `exch.py` battery. The RTL exists (`newimpl/rtl/local_trunk.v`), with a
  hand-patched bench (`tb_ltu`) and a dialled one (`tb_lnet`).
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
