# The exchange — MF8 unit (six-channel live on the block header; eight-channel not taken)

**Exchange face (adopted).** Live MF8 is a **block adapter** on the **block
header** (`fabric.md` §5.2) — the same star collect as local-trunk. It drives
appearances **1–3 and 5–7**; **0 and 4** are unequipped / `FILL` on the fabric.
F and S exist only on the line. Transmit samples `C_RX` / `A_RX` off the
header; receive drives `C_TX` / `A_TX`. Not a tap of `HC[h]` / `HA[h]`
(`baseband.md` §6, `mf8_trunk_card.v`).

**Frame (adopted).** The **8-bit six-channel** frame of `mf8-spec.md` /
`mf8.py` — F and S opposite, 512 kbps / 1.024 MBaud. Inside the unit the line
mux may still share the fabric's `SLOT` count for payload seats; that is
frame-shape fusion, not a highway tap.

**Eight-channel payload split (not taken).** This file also records the
measured path to eight payload channels on a line of its own (10-bit and
16-bit headers, PHY timers, full eight appearances live). That path is set
aside. The 8 × 8 fabric, the port map of `protocol.md` §5, and
`mf8_trunk_card.v` follow six channels.

> **Status.** Exchange face and six-channel frame: **adopted** as above.
> Eight-channel split: **not taken** — keep §§3–4 and the eight-appearance
> sketch in §5 as the record of what was set aside. §5's header contract is
> live for six channels (six of eight appearances driven).

---

## 1. What is fused today (frame shape, not the highway)

An MF8 *line* frame and a highway cell are the same shape:

```
 bit / slot:  0     1      2      3      4     5      6      7
 MF8 line:  [ F ][ C1 ][ C2 ][ C3 ][ S ][ C4 ][ C5 ][ C6 ]
 highway:     00    01     02     03     04    05     06     07     (block 0)
              10    11     12     13     14    15     16     17     (block 1)
```

One 3-bit address is the channel's C bit, its A bit's superframe state, its
input on the unit's mux and `'259`, and its port (`protocol.md` §5). The
block commutator builds `HC[h]` from the eight `C_TX` on the **block header**.
The unit's *line* transmitter inserts F at bit 0 and S at bit 4 and muxes
payload from appearances 1–3 and 5–7. Transmit in `mf8_trunk_card.v` is one
mux on `SLOT`:

```
tx_bit = (slot == 0) ? F : (slot == 4) ? S : C[slot]
```

with `C[slot]` taken from `port_c_rx` — the header appearances — not from
`HC[h]`. That is the whole of the frame-shape fusion, and it is why six
channels over MF8 cost nothing extra for the *address*. It is also the whole
of the map mess:

| | what the identity forces |
|---|---|
| **Channel count** | six, not eight. F and S occupy two of eight bits, and they are load-bearing (`mf8-spec.md` §3) |
| **Map** | a group is slots 1–3 and 5–7 of one block. Slots 0 and 4 are leftovers on the fabric (unequipped). Block 0 is forbidden, because 00–07 are tones and the operator bank |
| **Face** | **block adapter** on the **block header** (`fabric.md` §5.2). Six appearances live; `MUTE_BLK` on the commons. The 2 × 32 trunk/gateway shell (`common-cards.md` §7.2) is the *shelf's* part, not this |
| **Data cards** | keyed to seats 1–3 on an MF8 shelf, because two data cards three apart can hold a wrong alignment (`mf8-spec.md` §5, `channel-cards.md` §4.3) |
| **Terminals** | six remote lines, numbered `h1–h3` and `h5–h7` (`terminal.md`) |

The family is N = 2, 6, 14 because F + S + N must be a power of two
(`frame-rate.md` §1). Eight is not in it.

---

## 2. A — split — or B — fuse

**A. Split.** The highway stays eight slots of 512 kbps NRZ, `C` and `A` on
separate wires, `SLOT` the cell number, one `'151` a commutator. MF8 is a
carrier with its own bit counter, its own mux, its own F and S, its own line
code. The exchange unit takes eight `C`/`A` pairs from eight channel sockets
and muxes them onto the line. The two streams meet only as eight bits a frame
at the socket, which is what a line card already is (`protocol.md` §1).

**B. Fuse eight payload.** Finish what an older `fabric.md` §1.1 began: the
highway *is* the MF8 frame, eight slots, eight payload channels, F and S gone
from the bitstream or moved into a wider cell. Slot number is still wire
position. That path needs a 10- or 16-slot highway or a new F/S story — **not
taken**, and not a reason to tap `HC[h]`.

| | A, split (eight payload) | B, fuse eight payload |
|---|---|---|
| **What it costs in parts** | the trunk card already has a frame mux, a signalling mux and a framer (`mf8-spec.md` §§10–11). Split, those stay and stop sharing `SLOT` as the line address. A decade (or 4-bit) counter and a wider mux replace the free `SLOT` address. A handful of packages, on one card | at six channels the *address* is free (`SLOT`); at eight, either a new header with no dedicated F and S, or a 10- or 16-slot highway |
| **What it costs the fabric** | nothing. 8 × 8, `HCLK`, the latch, the cable, octal `h s` | a 10-slot wire is not octal and not a `'151`. A 16-slot wire is `big-exchange.md`, a new family, every port already fitted |
| **What it costs the F word** | a new frame to measure, with F and S still seats. §4 | F and S out of an 8-bit 512 kbps stream. `mf8-spec.md` §3.2 is why F alone is not enough, and why the guard is a second lane. That work would be redone from scratch, against data cards that can carry any byte |
| **The board** | **block adapter** on the **block header** — already the live six-channel face; eight appearances live | same header would still be required; tapping `HC`/`HA` is refused (`baseband.md` §6) |
| **The map** | a group is eight ports of one block. They can sit in any block 1–7 (§6) | wire position is still slot. "Anywhere" is still a whole block, and only if F and S no longer steal 0 and 4 |
| **Clocks** | the unit owns its line-rate crystal and `LINE_HB`. 4.096 MHz stays off the cable, which `mainboard.md` §8 already wanted. Fabric `LINE_HB` remains for `SLOTQ` | at 512 kbps the line bit can share `HCLK`. At 1.024 Mbps `LINE_HB` is 2.048 MHz on the cable, which §8 was written to avoid |

**Decided.** Exchange face: **block adapter** for live six-channel (§1). Eight
payload channels: **not taken** — A would be required; B cannot meet it on this
fabric. Fusion of *frame shape* with `SLOT` remains the six-channel line mux
(§1); it is not a path to eight.

The rest of this document is the A sketch (eight appearances) and the
measurements that closed the eight-channel frame choices.

---

## 3. Why eight payload bits cannot live on `SLOT`

The highway has eight seats and must keep them: a port is `h s`, `s` is three
bits into a `'151`, a cell is 1.95 µs, the wire is 512 kbps. That is
`fabric.md` §1.1's "why eight by eight", and it is not reopened.

MF8 at eight payload channels still needs F and S. F pins bit alignment and
superframe phase in one word; S is a second, independent condition so a data
card carrying that word cannot hold a false lock (`mf8-spec.md` §3.1–3.2).
Those two bits are not optional and they are not payload.

So the line frame is longer than the highway frame. The trunk transmitter
cannot be the block commutator. `tx_bit = C[slot]` has nowhere to put F and S.
That is the one-line form of §2.

A 9th or 10th highway cell, or a 16-slot highway, would make the streams the
same length again. The first is not octal and not a `'151`. The second is a
16 × 16 exchange talking to this one over MF8, which `big-exchange.md` §8
already names as the 14-channel family, not a conversion of 8 × 8.

---

## 4. Three frames that carry eight

64 kHz frame rate, 64 kbps a channel, octet-aligned DS0 — the spec point
`frame-rate.md` §5 chose. Reach is the √f law scaled to 256 kbps = 1.00×, as
that document's table.

| | line | baud | reach | mux | superframe | what it keeps | what it spends |
|---|---|---|---|---|---|---|---|
| **today, N = 6** | 512 kbps | 1.024 M | 0.71× | `'151` on `SLOT` | 8 frames, 8 kHz | F, S opposite, PCM = superframe, S-mirror of C | two seats, six channels |
| 10-bit, SF = 10 (`mf8_10.py`) | 640 kbps | 1.280 M | 0.63× | count 0–9 | 10 frames | F and S as seats, eight C | decade SF; separate octet counter; S full |
| **10-bit × 16-SF (`mf8_10_16.py`) — reopened** | **640 kbps** | **1.280 M** | **0.63×** | count 0–9 + 4-bit SF | **16 frames**, 4 kHz | 0xFFFE, guard 0,8, PCM = q[2:0], six slow S states | decade frame counter; new 2.56 MHz crystal; four adversarial pairs |
| **16-bit, 8 C + 6 overhead (`mf8_16.py`)** | **1024 kbps** | **2.048 M** | 0.50× | 4-bit `'150` | **16 frames**, 4 kHz | in-family crystal; F at 0, S at 8; P, RAI, K seats; one adversarial pair | twice today's line; PHY window half of 512k |
| 9-bit, 8C + header | 576 kbps | 1.152 M | 0.67× | 8 + 1 | 16 frames to hold F and 8 × A | closest to 512 kbps | no S-opposite-F geometry; header is one lane |

### 4.1 Lean: ten bits

```
 bit:   0     1     2     3     4     5     6     7     8     9
      [ F ][ C0 ][ C1 ][ C2 ][ C3 ][ S ][ C4 ][ C5 ][ C6 ][ C7 ]
```

S at bit 5, half of ten. `mf8_10.py skew` lists the ten alignments: skew 5
is the F word on itself; every other wrong skew reads two payload lanes five
wire-bits apart — (C0,C4), (C1,C5), (C2,C6), (C3,C7) and the swaps.

**The superframe is ten frames, not eight**, if S still carries two guard pads
and eight A bits. Eight frames of S are eight bits: that is the eight A bits
and nothing left for the pads. F alone is not sufficient (`mf8-spec.md`
§3.2).

**F is `1111111110`, 0x3FE, one zero at state 9.** `mf8_10.py word`: longest
run a payload lane matches it is 15 (CVSD speech), 3 (silence), 9 (constant
1), 17 (random), 15 (octet 0xFE) — all under the 32 acquisition needs. Period-2
words `1010101010` / `0101010101` are matched indefinitely by CVSD silence,
as `1010` was. The generator is the decade counter's wrap: F is 0 only at
state 9. Wrong superframe phase: a rotation mismatches at 2 of 10, longest
good run 8, **0 admissible wrong phases** over all 256 hook states
(`mf8_10.py sfphase`).

| state | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
|---|---|---|---|---|---|---|---|---|---|---|
| **F** | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | **0** |
| **S** | **0** | A0 | A1 | A2 | A3 | A4 | **1** | A5 | A6 | A7 |

**The 0,5 analogue of today's 0,4 pads does not work.** 5 is odd, so 0 and 5
have different parity: a period-2 lane (CVSD silence, FILL) *is* `0,5 = 0,1`.
`mf8_10.py guard`: one data card carrying the F word, idle elsewhere, holds
256 / 2560 start-ups. Same-parity pads are clean:

| guard | F word, every lane | one data card, worst | idle every | speech, 4 superframes |
|---|---|---|---|---|
| **0,5 = 0,1 — the analogue** | 0 / 2560 | **256 / 2560** | 0 / 2560 | 1 in 711 |
| 0,6 = 0,1 | **0 / 2560** | **0 / 2560** | 0 / 2560 | 1 in 914 |
| 0,4 = 0,1 | 0 / 2560 | 0 / 2560 | 0 / 2560 | 1 in 640 |
| 0,2 = 0,1 | 0 / 2560 | 0 / 2560 | 0 / 2560 | 1 in 376 |
| 0,5 = the F word there | 2054 / 2560 | 6 / 2560 | 6 / 2560 | 1 in 582 |

**The guard is 0,6 = 0,1.** Same parity, different values, different from the
F word at those states (0x3FE is 1 at both 0 and 6). Half a superframe is 5
and is odd, so there is no same-parity pair opposite F in time; 6 is the
farthest even seat from 0 that is not 0. Header-on-itself (skew 5) still
fails: G0 is 0, the word starts with 1.

**PCM is a separate counter.** The superframe is 10 frames, 6.4 kHz. An octet
is still 8 bits, 8 kHz at this frame rate. A 3-bit octet counter, clocked by
the frame, is one half of a `'393` that today's superframe counter was giving
away. A PCM card still transfers at octet state 7; it no longer shares that
count with the signalling `'259`. The S-mirror is gone: C seats are bits 1–4
and 6–9, A bits sit at states 1–5 and 7–9, and the two maps are wired.

**The `'259` is no longer addressed by `SLOT`.** A `'259` takes a 3-bit
address. Ten seats do not fit. The receiver writes eight C flip-flops (two
`'174`s, which the exchange trunk card already uses for the clock crossing)
enabled on the eight C seats, and eight A bits into a second `'259` or a
second `'174` from the superframe map. That is the package cost of losing the
free address.

**Data cards, measured (`mf8_10.py seats`).** With guard 0,6:

- One data card, any seat, every 8-bit octet and every 10-bit word: **0 holds**.
- Two PCM cards (8-bit octets), the F word in one and every octet in the other:
  **no pair holds.** An octet cannot carry a 10-bit F word.
- Two period-10 lanes, F word against every 10-bit word: holds only on
  **(1,5) (2,6) (3,7) (4,8)** — five apart on the wire, 131 584 (word, hook)
  combinations each. Adjacent pairs are safe. Random content in all eight:
  0 / 2560.
- Residual: F word in seat 1, voice in seat 5. Speech satisfies 0,6 four
  superframes running once in 410. Forced at 24 such points, the frame
  counter never releases; the guard counter releases in 50–220 frames
  (mean 1.81 ms). Same shape as `mf8-spec.md` §5.

**The rule.** Two data cards that can carry a period-10 pattern may not sit
five slots apart on the wire. Key the connector to seats 1–4 (or 5–8): four
data cards, no two five apart. Ordinary PCM octets are safe in every seat
and every pair, because they cannot mimic 0x3FE. That is stricter than
today's "three of six" on the adversarial card, and looser on a DS0.

**Lean, after measurement.** Ten bits, 0x3FE, S at bit 5, guard **0,6 = 0,1**.
The 0,5 analogue is dead. That is the cheapest eight-payload line that
still has a two-lane header. It is not where alarm, parity, or a
condition bit lives: S is full (eight A bits and two pads), and stealing
a pad is the complement pair `ss0.md` already priced at a 1-in-28
residual.

**The header type is enough to lock.** It is the same two-lane check
`mf8-spec.md` §3 already adopted: F pins both alignments, S is a second
condition the F word fails, opposite F in the frame so a wrong skew
reads the F word on itself or two payload lanes a fixed distance apart.
PCM octets cannot carry a 10-bit F word, which is stronger than today.
The residual is the same shape §5 accepted, closed by the same slot
rule and the same guard counter. A CRC, a second F bit, or confirm-64
would spend parts or lock time on a failure this battery does not have.

**640 kbps / 1.280 MBaud is in range.** It sits between the 512 kbps spec
point and the 1024 kbps family row of `mf8-spec.md` §9.7, a quarter faster
than today's line, not a new band. Reach on the √f law of `frame-rate.md` §1
is 0.63× against 0.71× at 512 kbps. The rate plug is one more row:

| line | baud | filter | 0.75 cell | dead 0.2 cell | CD timeout |
|---|---|---|---|---|---|
| 640 kbps | 1.280 MBaud | 1.28 MHz | 1 172 ns | 312 ns | 3.12 µs |

`LINE_HB` is 1.280 MHz on the unit's own crystal, not on the fabric cable.
4.096 MHz does not divide 1.280 (3.2), so that crystal is a new part
(2.560 MHz, or 12.80 MHz with a plug).

**S has no spare under SF = 10.** Eight A bits and two pads fill ten states.
§4.1 left a 16-state superframe on this line as an unmeasured aside. That
row is now §4.1½.

### 4.1½ Ten bits, sixteen-state superframe — measured

The frame of §4.1 with the superframe of §4.2. S still at bit 5. F word
**0xFFFE**, guard **0,8 = 0,1**. Battery: `mf8_10_16.py` (`sim/mf8_10_16.log`).

```
 bit:   0     1     2     3     4     5     6     7     8     9
      [ F ][ C0 ][ C1 ][ C2 ][ C3 ][ S ][ C4 ][ C5 ][ C6 ][ C7 ]

 superframe state   0 | 1–7 | 8 | 9 | 10–15
 F                  1 |  1  | 1 | 1 | 1, except 0 at 15
 S                  0 | A0–A6 | 1 | A7 | spare (R / K / SS0 at 4 kHz)
```

**What the SF = 10 row charged, and what this recovers.** PCM is q[2:0]
again — free. Guard decode is the same `NOR(q2,q1,q0)` expecting `q3` as
§4.2. Six S states at 4 kHz cover R and four K-like levels without 64 kbps
seats (those levels are ms of debounce, not payload). S is not full.

**What it still spends.** Frame count is 0–9 (decade or load-at-9).
4.096 MHz does not divide 1.280 MHz — a **2.560 MHz** (or 12.80 MHz) crystal
on the unit, and a rate-plug row (`mf8_baud.py`: 1.172 µs / 312 ns / 19%
slew of half-cell). Four payload pairs five apart on the wire
(C0,C4)…(C3,C7). Two F-word lanes there still fail the guard (0xFFFE is 1,1
at 0 and 8); the residual is F word against voice, same shape as §4.2.
No per-frame P seat.

**Measured.** 0xFFFE: longest payload run 16 (speech), under 32. Wrong SF
phase: 0 admissible over 256 hooks. Guard 0,8 = 0,1: 0 / 2560 on F word,
one data card, idle; F+F five apart 0 / 2304; voice residual 1 in 337,
guard releases in 90–306 frames (mean 2.83 ms). Guard 0,5 = 0,1 still
dead (2304 / 2560 one-data). Tracking at 1e−2 BER lost 0.05 % of frames;
slips of 1–9 bits relocked in 5–25 frames.

**Against §4.2 on the plant.** `mf8_baud.py`: at atten 0.25 with sd 0.10,
640 kbps stays ~6e−5 raw BER; 1024 kbps rises to ~4e−2 on the same fixed
1.8 MHz cable model. Timer window ±10% after the classifier: 117 ns vs
73 ns. Reach ordering 0.63× vs 0.50× is the one to settle on a bench.

**Open.** Sixteen bits if the unit must stay on the 4.096 MHz family and
wants one adversarial pair plus full-rate P/R/K seats. Ten × 16-SF if the
extra crystal and decade counter buy the 0.13× reach and 80% payload
efficiency. §4.1 (SF = 10) is the measured strawman; do not reopen it as
the lean.

### 4.2 Sixteen bits: eight channels, and the slack is used

`frame-rate.md` lists N = 14 at 64 kbps on a 1024 kbps line because
F + S + N is a power of two. F at 0, S at 8, fourteen other seats, a
4-bit `'150`, superframe 16 frames. Tying six of those seats to `FILL`
was how this document first wrote "eight of fourteen": slack, wasted.
**Use it.** The exchange unit still presents eight cards. The six seats
are not ports. They terminate on Trunk-D.

```
 bit:  0    1  2  3  4  5  6  7     8    9   10  11  12 13 14 15
     [ F ][ C0 C1 C2 C3 C4 C5 C6 ][ S ][ C7][ P ][ R ][ K0 K1 K2 K3 ]
```

Eight C, F and S opposite (the family geometry), six overhead. P is
parity of the other fifteen bits, even, one XOR tree. R is the remote
alarm: this end holds it 1 while `MUTE`, the far end takes 32 ms of 1 as
the alarm — the rule `mf8-spec.md` §3.5 already decided for x, on a seat
of its own, so it does not steal a guard pad. K0–K3 are condition
levels, both ways, the same shape as A: a bit a frame, an RC and a
Schmitt. Battery at a terminal, AIS, a door, a spare. They are not
switched. They do not appear on the block header.

S still carries the eight A bits and the two pads. Superframe states
10–15 of S are a second, slower spare (6 × 4 kHz) if SS0 wants a
channel that is not a 64 kbps seat.

**F is `1111111111111110`, 0xFFFE, one zero at state 15.** The 4-bit
counter's wrap is the generator, the analogue of 0xFE and 0x3FE.
`mf8_16.py word`: longest run a payload lane matches it is 16 (CVSD
speech), 3 (silence), 15 (constant 1), 18 (random), 15 (octet 0xFE) —
all under 32. Period-2 words are matched indefinitely by CVSD silence,
as they were. Wrong superframe phase: a rotation mismatches at 2 of 16,
longest good run 14, **0 admissible wrong phases** over all 256 hook
states (`mf8_16.py sfphase`).

| state | 0 | 1–7 | 8 | 9 | 10–15 |
|---|---|---|---|---|---|
| **F** | 1 | 1 | 1 | 1 | 1, except **0** at 15 |
| **S** | **0** | A0–A6 | **1** | A7 | spare (SS0, or unused) |

**The guard is 0,8 = 0,1.** Half a superframe, both even, different
values, and 0xFFFE is 1 at both, so a lane carrying the F word fails
it. `mf8_16.py guard`: 0 / 4096 on the F word in every lane, on one
data card, and on idle. Voice satisfies four superframes running once
in 666. Putting the pads where the F word already is (0,8 = 1,1) is
the hole `mf8-spec.md` §3.2 killed: 512 / 4096.

**PCM is q[2:0] of the same 4-bit counter.** Superframe 16 frames is
4 kHz, two octets a superframe — the catch `frame-rate.md` §4 named,
when octet alignment rode a phase the F word did not pin. F pins it.
State 7 is the first octet's last bit; state 15 is the second's. A PCM
card transfers when the low three bits are 111, as it does today, twice
a superframe. The 10-bit frame had to add a counter for this. The
16-bit frame gives it back. `TX_OCT` on the header commons is still the exchange's 8 kHz
and still loads the word's 2×`'165`.

**Eight C plus F and S opposite cannot avoid one payload pair at
distance 8.** `mf8_16.py skew`: skew 8 is the F word on itself; skew 1
and 9 read (C0, C7); every other wrong skew reads a C and an overhead
seat. Overhead is generated on D, not by a data card, so those six
alignments cannot be held by payload. The remaining pair is C0 and C7,
bits 1 and 9, slots 0 and 7 of the unit.

**Data cards, measured (`mf8_16.py seats`).** Guard 0,8:

- One PCM card, any seat, every octet: **0 holds**.
- Two PCM cards, F word in one and every octet in the other: **no pair
  holds.** An octet cannot carry a 16-bit F word.
- F word in every payload seat, F word in C0 and C7 together, eight
  random cards, eight cards carrying 0xFE: **0 / 4096.** The F word is
  1,1 at the guard states, so two F-word lanes eight apart fail the
  guard.
- Residual: F word in C0, voice in C7. Speech satisfies 0,8 four
  superframes running once in 337. Forced at 24 such points, the frame
  counter never releases; the guard counter releases in 90–306 frames
  (mean 2.83 ms). Same shape as `mf8-spec.md` §5 and as the 10-bit
  residual.

**The rule.** PCM octets are safe in every seat and every pair. Two
period-16 lanes that can carry the F word and a guard-satisfying
pattern may not sit in C0 and C7 together. Key the connector to C0–C6,
or to C1–C7: seven data cards, not the two end slots at once. Overhead
seats are not keyed; they are not cards.

**Parity does not replace S.** It is a third check, or a lamp, or a
contribution to `MUTE` after a run of failures. A data card controls
one bit of the XOR and can always make one frame's parity good; S is
the independent lane the F word fails. This battery did not put P in
the framer. R does not replace S either: it is a level, and a quiet
link holds it 0.

**2.048 MBaud is in range.** It is the family top row of `mf8-spec.md`
§9.7, already specified: filter 2.0 MHz, 0.75 cell 732 ns, dead 0.2
cell 195 ns, CD timeout 1.95 µs. Reach on the √f law of
`frame-rate.md` §1 is 0.50× against 0.71× at 512 kbps and 0.63× at
640. Impulse outages are shorter in wall-clock at the faster frame
(§3.1 there). `LINE_HB` is 2.048 MHz on the unit's own 4.096 MHz crystal,
tap Q1 — the oscillator §9.1 picked so this rate would divide. It does
not ride the fabric cable (`mainboard.md` §8). Twice today's baud, not
a new band.

**Parts, against the 10-bit decade.** Frame and superframe are two
halves of a `'393`, as today. One `'150` addresses F, eight C, S and
the six overhead. The octet counter is free. The `'259` for A is
enabled on the eight C seats; K0–K3 and R are a `'174`. XOR for P is a
gate or two. Trunk-D is closer to today's 14–16 plus eight-not-six
than to the 20–24 the decade cost.

**What the slack is for**, both ways, the pair being bidirectional:

| seat | rate | between exchanges | terminal → exchange |
|---|---|---|---|
| **R** | 64 kbps, a level | far end not locked | the same: the shelf is down |
| **P** | 64 kbps | line quality, or a mute input | the same |
| **K0–K3** | 64 kbps, levels | AIS, plant, spare, spare | battery, door, plant, spare |
| **S states 10–15** | 4 kHz each | SS0, if built (`ss0.md`) | unused; a terminal does not flood |

A 10-bit line can carry R only by stealing a guard pad (x, 8 kbps, the
1-in-28 residual). It cannot carry P a frame. It cannot carry four
condition levels without giving up payload. That is the case for
sixteen bits, and it is not a case about lock. The 10-bit header
already locks. It is the measured lean, and this document does not
take it.

Tracking at 1e−2 BER lost 0.04 % of frames and no off-phase lock; a
slip of 1–15 bits relocked in 5–26 frames (`mf8_16.py errors`).

**Reopened here.** Sixteen bits remains the working tree (RTL, map, spec
geometry) until a choice is frozen. The case for sixteen is crystal
commonality, one adversarial pair, and full-rate P/R/K seats — not lock
(§4.1½ already locks) and not "family N = 14." The case for ten × 16-SF
is reach, timer window, and payload efficiency. `mf8_10.py` (SF = 10)
stays as the measured decade-SF row, not the lean to take.

### 4.3 Set aside: nine bits

One extra bit a frame, 576 kbps, closest to today's line. That bit must carry
the F word and the eight A bits over a longer superframe, and there is no
second lane for the guard to sit opposite F. A wrong alignment then reads one
payload lane as the whole header. `mf8-spec.md` §3.4 killed S-beside-F for
that reason. A 9-bit stuffed header is that layout with the neighbour deleted.
Not measured; not the lean.

### 4.4 What 512 kbps eight-payload would have to invent

For completeness, B's remaining escape: keep the 8-bit 512 kbps frame, all
eight bits payload, frame by something that is not a seat. Line-code
violations want a different decoder than §9.4's transition timer. A unique
word in the payload is what data cards can hold. Stealing A bits periodically
is a signalling bug. A second pair is not "over MF8". None of those is a
small change to the spec. They are a different carrier.

---

## 5. The exchange unit — an MF8 block adapter

**Live six-channel** mates this face and drives six of eight appearances (§1).
The eight-channel sketch below is the same header with all eight live — **not
taken** as a frame, but the pin contract is what six-channel already uses.

One MF8 pair each way on the rear, and on the fabric side a **block adapter** —
eight ordinary slot appearances plus `MUTE_BLK`, on the reusable **block header**
(`fabric.md` §5.2). MF8 occupies a block because a trunk group is one
failure domain, one monitor and one hunt unit. It does not *define* that header;
"MF8 is a block" is packaging, not the contract.

The short answers, before the pins:

- **Electrically it is eight cards**, within `common-cards.md` §1.2, plus the
  one block-scoped pin the contract adds (`MUTE_BLK`). Same six per-slot
  signals, same word, same `/ANS`. The commutator is unchanged; the block
  gains an OR gate and a jumper when the header is stuffed for an adapter.
- **Mechanically it mates the block header**, not eight slots on the block ribbon.
  The contract refuses the eight-slot board (`fabric.md` §5.2). One board (two:
  Trunk-D and Trunk-A), one block, nothing else on those slots.
- **It does not tap `HC`/`HA`.** `baseband.md` §6 already said that tap
  would loop the link. Verilog never did it. Split makes the face match
  the signals.
- **`MUTE` cannot live on a11.** a11 is a common input, tied to "locked"
  in an exchange (`baseband.md` §2.3). Link-down is this adapter's, and
  `MUTE_BLK` on the header commons is the busy force the contract exists to carry.

```
  block h, eight port circuits                    MF8 unit (D + A)
  hdr appearances: C_RX/A_RX[0..7]  ──▶  hold, TX mux, F, S  ── pass ── encoder  ══ line out
  hdr appearances: C_TX/A_TX[0..7]  ◀──  '174, RX demux, framer  ◀── classifier  ◀══ line in
  hdr appearances: word, /ANS[0..7] ◀──  2×'165 / jumpers, /ANS tied or per slot
  hdr commons: TX_CLK, TX_OCT, FILL ──▶  payload domain, the word, idle
  hdr commons: MUTE_BLK             ◀──  not locked  →  block ORs into BUSY
```

### 5.1 This adapter on the block header

The **block header**, dual footprint, `MUTE_BLK`, and what any block adapter
owes the block are `fabric.md` §5.2. This section is only what the MF8 unit
puts on that header and on its own rear.

| | shell | what this unit does |
|---|---|---|
| **appearances** | type B, 64-way — the header collect | eight tie-trunk appearances: shared word, `/ANS` tied low (or per slot on a terminal). Column map and per-pin behaviour §5.3 |
| **commons** | 2 × 5 — the header commons | listens to `TX_CLK` / `TX_OCT` / `FILL`; drives `MUTE_BLK` from link lock (§5.4) |
| **pass** | `mf8-trunk.md` §2 | D ⇄ A. Unchanged: `TX_BIT`, `LINE_HB`, `RX_BIT`, `RX_STB`, `/CD` |
| **rear** | `common-cards.md` §7.3 | the pair each way, off Trunk-A only. Not on the header, not on H |

A block stuffed as this group does not populate the block-ribbon slots. The eight
port circuits still sit behind the header (`fabric.md` §5.2). Mixing a line card with
this unit on the same block is not a configuration — both because the
contract forbids it and because a group is eight channels on one link.

**The 2 × 32 trunk/gateway shell is not this board.** That is the MF8
*shelf's* trunk slot (`common-cards.md` §7.2), where channel cards face a
stack header. This unit faces a block through the **block header**. Same pin *roles* on
each appearance as a channel card; eight of them collected, not one wide
connector with `SLOT` and `LINE_HB` on it.

### 5.2 Why the highway was the wrong face

`mainboard.md` §2.4 put an MF8 trunk card on `HC[h]`/`HA[h]` because
`fabric.md` §1.1 said the highway *is* the frame. `baseband.md` §6
corrected that and `mf8_trunk_card.v` never did it: `HC[h]` is the
commutation of this block's `C_TX`, which is what just came *off* the
line. A transmitter fed from it loops the link. What the transmitter
needs is the eight ports' `C_RX` / `A_RX`, which are private to each
port and appear on no highway.

So the unit mates the **block header** (`fabric.md` §5.2), not
a highway tap. The block still has its commutator: eight `C_TX` into the
`'151` on `SLOT` is how this block's highway is made, whether those pins
come from line cards or from this adapter. Split, that `'151` is only a
commutator. It is not the line mux, and F and S are not seats on it. That
retires `mainboard.md` §2.4's "a trunk card is not on the bus either": it
was never on the bus in the way that sentence meant, and it is not on H
now.

### 5.2½ The conversion — 16-bit line, 8-slot highway

The unit plugs into a block and **takes that block's highway**: stuffing
the header here means `HC[h]` / `HA[h]` *are* this group's eight channels, after
the block's own `'151` has commutated them. The MF8 pair on the rear is
not that highway. The conversion is this unit.

Two serial streams share a 64 kHz frame and nothing else:

```
 highway cell (SLOT)   0        1        2        3        4        5        6        7
                      512 kbps NRZ, C and A on two wires, no line code

 MF8 bit               0  1     2  3     4  5     6  7     8  9    10 11    12 13    14 15
 content               F  C0    C1 C2    C3 C4    C5 C6    S  C7    P  R     K0 K1    K2 K3
                      1024 kbps, differential Manchester
```

Two line bits sit in the time of one highway cell, because 1024 kbps is
twice 512. That is a convenience of the shared 4.096 MHz divide, not an
identity: the line mux is a 4-bit count on the unit's `LINE_HB`, not `SLOT`.
F, S, P, R and K never appear as ports. Slot *n* of the block is
channel C*n* of the line, packed: C0–C6 at bits 1–7, C7 at bit 9 (S is
opposite F, so one payload pair is eight apart).

**Transmit.** Sample `C_RX[n]` / `A_RX[n]` in `TX_CLK` into a hold —
eight parallel bits at 64 kHz, the same a line card already is. Mux
them onto the 16-bit frame in the line domain. A is one bit a channel a
superframe, 4 kHz; the hold is still a level.

**Receive.** Demux the sixteen bits; write eight C flip-flops and eight
A bits; re-sample C on the local frame edge (the two `'174`s). Drive
`C_TX[n]` / `A_TX[n]`. The block's commutator then makes `HC[h]` as it
does for any stuffing. A listener on another block who has this group
in a latch sees eight ordinary 64 kbps squares.

The fabric does not know there is an MF8 line. The line does not know
there is a `'151`. They meet as eight `C`/`A` pairs on the block header.

### 5.3 Appearances — what this adapter does with each

Direction is the *card's* view, as `common-cards.md` §1: `out` is the
adapter driving the block. The column map is the block header's
(`fabric.md` §5.2); this table is what the MF8 unit does with each pin.
Slot *n* is line channel C*n*: bits 1–7 of the frame at *n* = 0..6, bit 9
at *n* = 7 (S sits at bit 8; there is no hole in the sockets). Straight
across, after the conversion of §5.2½.

| appearances | | | what this unit does with it |
|---|---|---|---|
| a, col *n*+1 | `C_TX[n]` | **out** | incoming C off the line, through the two `'174`s of §5.5 into the block's C commutator. `FILL` while not locked |
| a, col *n*+9 | `A_TX[n]` | **out** | incoming A, through the RC and Schmitt of `mf8-spec.md` §14. Held 0 while not locked, so every M falls |
| a, col *n*+17 | `C_RX[n]` | in | the port's captured C, what this channel sends. Sampled in `TX_CLK` into the TX hold, then muxed in the line domain |
| a, col *n*+25 | `A_RX[n]` | in | the port's `A_RX`: E, and a trunk never rings, so E as it stands (`extensions.md` §2.3). The S-lane mux's input *n* |
| c, col *n*+1 | word `[n]` | **out**, o.d. | §5.6. Held off at power-up by the RC of `extensions.md` §2.2, **and gated by lock**, so a cut pair reads unequipped |
| c, col *n*+9 | `/ANS[n]` | **out** | tied low on a tie trunk. Open, or tied, a channel at a time on a terminal (`terminal.md` §3) |
| c, 17–24 | `GND` | in | |
| c, 25–32 | `+5 V` / `GND` | in | **the only rail.** No `±12 V`, no `−48 V`, no `RING`. Same as the baseband trunk card |

The unit drives four pins a slot, and only four — the same four
`common-cards.md` §1.2 allows a card. Commons are not on the appearances
shell. a2 `LOOP_HB`, a7 `RX_CLK`, a8 `RX_OCT`, a11 `MUTE` are ribbon-slot
pins the unit never sees: the first is for a CVSD line card (`clocks.md` §4),
the next two are `TX_CLK` / late `TX_OCT` in an exchange, and MUTE-as-input
is tied locked because a block had no link. This unit *is* the link, and its
mute is generated here, not read here.

**a12 is still where a trunk differs from a line**, as
`baseband.md` §3.5 had it for one channel: the word is conditional on a
wire outside the card. Eight times, one enable.

### 5.4 Commons — this adapter's use of the header commons

Odd pins signal, even ground — the ribbon idiom, same as the pass. Pin
roles are the block header's (`fabric.md` §5.2); values here are this unit's:

| pin | | pin | |
|---|---|---|---|
| 1 | `TX_CLK` in — 64 kHz from the clock card, via the block. Loads the TX hold; shifts the word's 2×`'165` | 2 | `GND` |
| 3 | `TX_OCT` in — 8 kHz (`CLK_8K`). Loads the 2×`'165`, so the sixteen bits repeat every visit | 4 | `GND` |
| 5 | `FILL` in — 32 kHz `1010`. What `C_TX[n]` becomes while not locked | 6 | `GND` |
| 7 | `MUTE_BLK` **out** — asserted with `MUTE` (not locked, or no carrier) | 8 | `GND` |
| 9 | spare: recovered-clock lead if a loop-timed slave is ever designed. Open until then | 10 | `GND` |

The block ORs `MUTE_BLK` into its `BUSY` commutator — all eight inputs, or the `'151`'s output, one gate, jumpered in when the header is stuffed for an adapter (`fabric.md` §5.2). Pulled down on the block so an unfitted commons shell does not busy a ribbon stuffing.

`LOCK` and `CD` lamps face the operator from Trunk-D, as `mf8-trunk.md`
already had them. They are not on the header. The panel may take
them off the board; they clock nothing.

**Why `MUTE_BLK` is on the header commons, not a11 or a14**, is the contract's (`fabric.md`
§5.2). This unit asserts it with `MUTE` (not locked, or no carrier). The
block's part, one gate, is the only change on the fabric side of the header. A
ribbon stuffing leaves it off.

### 5.5 Clocks: the payload is the exchange's, the line is the unit's

`network.md` §1 said a trunk card in an exchange takes 4.096 MHz from
the clock card instead of owning the crystal. That was the fused rate:
`LINE_HB` 1.024 MHz is on cable A, `HCLK` *is* the line bit, `SLOT` *is* the
mux address (`mainboard.md` §8). Split, those taps are the fabric's.
The line is 1024 kbps / 2.048 MBaud, and `LINE_HB` is this unit's.

**The unit owns the line oscillator: 4.096 MHz, tap Q1, `LINE_HB` 2.048 MHz.**
That is `mf8-spec.md` §9.1's crystal, doing the job it was picked for.
It does not ride H or the block header. The clock card's 4.096 MHz stays on the
clock card for the fabric, as `mainboard.md` §8 wanted. A 10-bit line
would have needed 2.560 MHz; this unit does not.

Two domains on the unit, the same two `mf8-backplane.md` §2 named:

| domain | clock | what |
|---|---|---|
| **payload** (backplane T) | `TX_CLK` / `TX_OCT` from C | the TX hold, the word's 2×`'165`, the `'174` that presents `C_TX` to the block. The eight bits a frame this unit owes the commutator, and the eight it takes from the ports |
| **line** (backplane R on receive; its own on transmit) | the unit's `LINE_HB`, 2.048 MHz | the 4-bit frame counter, the `'150`, F, the encoder on A, the framer. Receive is recovered: `RX_BIT` / `RX_STB` from the classifier, no clock on that path (`mf8-spec.md` §9.4) |

**Transmit is still in the exchange's frame**, in the only sense that
survives the split: C and A change at `TX_CLK` and are held for the
15.6 µs of it. The line mux reads the hold. It does not run from
`SLOT`. The line counter is not locked to the fabric; a PLL that would make
it so is the part `terminal.md` §4 already declined to design. The
offset is the two crystals', ±20 ppm, a slip every 390–780 ms, the same
`mf8-backplane.md` §7 measured. Voice does not hear it. Synchronous
data across a trunk is already out (`network.md` §8).

Receive crosses into payload with two `'174`s on the eight C bits —
eight bits, two packages, the same shape as today's six. A is a level:
the §14 RC and Schmitt, then `A_TX`. `RX_CLK` as a pin is not wanted;
the block would not take it (`baseband.md` §3.5's "a7 is an input").

Channel-socket `LOOP_HB` stays `/SLOT[1]` for a CVSD line card on a
*different* block. This unit does not encode a subscriber line and does
not use it.

### 5.6 The word, `/ANS`, and link-down

A tie trunk sends one word to all eight from two 74HC165 daisy-chained and ties every
`/ANS` low (`network.md` §1, `extensions.md` §2.1). Direction N/E/S/W
and the glare bit are the jumpers on that 2×`'165`. The no-forward jumper
stays on the network unit, one jumper a direction (`network.md` §3.3),
not on this unit.

A subscriber terminal is the same board with the jumpers of
`terminal.md` §3: a channel takes the shared 2×`'165`, a 2×`'165` of its
own, or a ground (plain line); `/ANS` is tied or open to match the card
at the far end. The far end still cannot send its own word — MF8 carries
C and A — so both ends are labelled, as that section already required.
Eight channels, not six; no leftover seats, so no local card in slot 0
or 4 of this block.

**Link-down is the enable on the words**, as `baseband.md` §3.5 made the
detector the enable on the word FET. Not locked, or no carrier: the eight
open-drain word pins float, the ports read unequipped, class hunt walks
on; `A_TX` is held 0, every M falls, calls release; `C_TX` is `FILL`;
`MUTE_BLK` forces the block's `BUSY` so a terminal's dead lines are busy
to a caller and not a phone that cannot ring (`terminal.md` §2). Stopping
the words is what `network.md` §1 asked for on any carrier; the `BUSY`
force is what it asked for on a terminal. Both, from one lock flip-flop.

Held off at power-up by the same ~100 ms RC, so a unit just seated is
unequipped until the 2×`'165` is loading (`extensions.md` §2.2).

R, the remote alarm (`mf8-spec.md` §3.5), is generated here: held 1
while `MUTE`, bit 11 of the frame. S keeps both pads. It is not a pin
on the block header. A channel card never sees it. K0–K3 are levels on D: lamps on
the unit, or a scan, not fabric ports.

### 5.7 Trunk-D / Trunk-A

`mf8-trunk.md` still splits digital from analog, and the pass still
does not care how many C bits the mux assembled. What changes is D's
other face.

| | today, on an MF8 shelf | this unit |
|---|---|---|
| **Trunk-D** | stack header C: clocks, `MUTE`, six C/A toward six channel layers | **block header**: eight C/A toward the block, `MUTE_BLK` instead of shelf `MUTE`, no stack `'244`, no empty-slot pulls (the block already pulls an unfitted `C_TX` to `FILL`) |
| **Trunk-A** | pair, encoder, classifier, magnetics | the same. Rate-plug timers on A at the 1024 kbps row `mf8-spec.md` §9.7 already has |
| **outline** | 100 × 100, spacer-stack | not required to be 100 × 100. It has to mate the block header on a block and present A at the rear. Two boards, pass between them, same split |

D no longer drives `RX_CLK` / `RX_OCT` / `MUTE` onto a shelf. Those nets
are the exchange's, on cable A, and the header commons bring D only what it listens to.
The framer still makes lock from `RX_BIT`, `RX_STB` and `/CD`.

### 5.8 What the block still has to be

The unit is a block adapter: eight cards electrically, within the contract
(`fabric.md` §5.2). Everything that was never a card, and the eight port
circuits a card would have brought to a ribbon slot, stay on the block
behind the header.

- **Eight port circuits**, behind the header: the latch, the three `'151`s, the
  capture `'74`, the supervision of `fabric.md` §3.5. Fitted with the group,
  not along the ribbon. `/ANS` tied low means a trunk port does not ring, as
  that section already required.
- **The commutators**, including the word and `BUSY`, on the shared board.
  The `'151` on `SLOT` is how the highway is made. F and S are not inputs to it.
- **A monitor pool** (`monitor.md` §1, `baseband.md` §4). A group is
  still one block, so a monitor still reads that block's M — which is
  this unit's `A_TX`. Fitting the unit in a block of lines is what
  stuffing the header for it *means*; a block with no monitor can pass a flood
  and cannot own a call. `MUTE`/`BUSY` is still one force, which is why
  §6.2 does not scatter.
- **The `MUTE_BLK` OR** of §5.4, jumpered in. A ribbon stuffing leaves it
  off.
- **Nothing on H.** The unit is not a tap. The cable still has ten taps
  however many groups are fitted (`mainboard.md` §2.4, the part that
  stands).

### 5.9 Parts

Sketch, against `mf8-spec.md` §§10–11 and `mf8-trunk.md` §1. Not drawn.
The classifier, the encoder, the 75176 and the two transformers stay on
A, ≈ 6–8 + 2 as they were. On D, sixteen bits pays the six overhead FFs
and keeps the family counter; the 10-bit decade is §4.1's cost, not
this board's:

| function | part | |
|---|---|---|
| Line oscillator and `LINE_HB` tap | **4.096 MHz + `'4040`, Q1** | 1 |
| Frame + superframe | 1 × `'393`, as today | 1 |
| Octet counter | **free: q[2:0]** | |
| Mux | 1 × `'150` | 1 |
| F | wrap of the 4-bit counter (0 at 15) | ⅓ |
| TX hold, eight C | `'174` × 2 | 2 |
| Framer without the classifier | ≈ 6, guard 0,8 | ≈ 6 |
| RX C, two `'174`s | 2 × 74HC174 | 2 |
| RX A + overhead | `'259` on the eight C seats; `'174` for R and K | ≈ 2 |
| P | XOR tree | a gate or two |
| A: RC, Schmitt, eight times; K and R if they debounce like A | 2 × `'14`, plus RC | 2 |
| Card word, `/ANS`, `MUTE_BLK` | ≈ 3¼ + ½ | ≈ 3¾ |
| | **≈ 16–20 on D** | today's 14–16 plus eight-not-six and the overhead FFs |

A handful, on one card, as §2 said. The fabric does not pay it.

### 5.10 What it is not interchangeable with

| | this unit | a channel card on P | the shelf trunk | the baseband trunk |
|---|---|---|---|---|
| face | **block header** / **block adapter** (`fabric.md` §5.2) | one **slot** on the block ribbon | 2 × 32 stack header (`common-cards.md` §7.2) | one **slot** on the block ribbon |
| ports | eight, one link | one | six (eight after adoption), one link | one |
| line | MF8, on A | the subscriber pair, on R | MF8, on A | four conductors, on R |
| `+5 V` only | yes | no, except the data card and this family's trunks | no: it drives a shelf that wants ±12 and −48 | yes |
| sits beside a line on the same block | no: it is the non-breakout mate of that star | yes | no | yes (`network.md` §1.1) |

The far end of the link is either another of these units (a tie) or a
stock MF8 shelf of channel cards (a terminal). That shelf's trunk is
still Trunk-D/A on the spacer-stack, eight layers after adoption, and
is a different board with a different face. The exchange unit does not
plug into an MF8 shelf. A channel card does not plug into T.

### 5.11 Bring-up

1. **The link alone.** Two units, T unterminated or looped through a
   jig that ties `C_RX` to `C_TX`. Lock both ways; `MUTE_BLK` falls;
   `LOCK` lamps. Scope `TX_BIT` against the line, and `RX_STB` against
   the `'174` write, with the pass in between (`mf8-trunk.md` §5).
2. **One block, this unit stuffed, no far end.** Eight ports
   unequipped: words off, `A_TX` low, `MUTE_BLK` high, `BUSY` forced.
   The lamp field's row is dark on hook and lit on busy
   (`observers.md` §1).
3. **Far end a second exchange, one channel seized from the console.**
   Claim, speech, both release orders. Then pull the pair: both ends
   release, the group leaves the hunt, a caller to a terminal line gets
   cannot-complete.
4. **A terminal.** Far end a shelf of eight channel cards. Lift, dial
   tone from 01, a local call, then break the link during it
   (`terminal.md` §5).

Step 1 does not need the fabric. Step 2 is `fabric.md` §7 step 2 with
this stuffing instead of empty P.

---

## 6. The map, once the board exists

### 6.1 A group is `h0–h7` of any block 1–7

Slots 0 and 4 are payload. There are no leftover seats on a trunk block.

```
 first key   0  operator
             1  standalone: a local number, 1 s
                networked: the flood, 1 e b h s
             2–7  a local number, h s

 00          idle
 01–03       dial / busy / cannot-complete
 04–07       four-line bank (operator, night, …)

 standalone  10–77  fifty-six lines; no trunk board
 networked   10–17  first MF8 group (block 1), eight channels
             20–77  forty-eight lines
             20–27 / 30–37 / …  further groups in blocks 2–7
```

**Block 0 is still never an MF8 group.** 01–03 are tones, 04–07 the bank.
Single-channel trunks may still sit in 06–07 (`network.md` §1.1).

**Digit 1 is still the flood** on a networked exchange, so 10–17 are still
undialable as lines. Putting the first group there wastes no line numbers.
On a standalone exchange, block 1 is lines, as now.

**A terminal is eight lines**, numbered `h0–h7` of its block, dialled like
any other. Label the far shelf's slots with those numbers. Blocks 2–7 give
up to six terminals and 48 remote lines; block 1 as well on a standalone
exchange. Not block 0.

**The lamp field is the numbering** (`observers.md` §1). Row 1 becomes eight
trunks, not six with two holes.

### 6.2 Scatter is out of scope

Eight MF8 channels at arbitrary ports — 06, 23, 51, … — would be eight
flying C/A tails and a map the hardware does not have. Monitors sit on a
trunk *block* and read that block's M. `MUTE_BLK` forces a *block's*
`BUSY`. A dead link that had to busy-out eight scattered ports is eight
forces, not one. Direction hunt would still find them (the word is on
the card), and that is not enough. That is why the block header
collects a whole star (`fabric.md` §5.2): assignment anywhere in this
document means **any block 1–7**, by stuffing the header for this adapter there —
not because MF8 somehow *is* a block, but because an eight-channel group
is one failure domain.

---

## 7. What a group of eight does to a network

Trunk groups still cost lines. The first group still sits in block 1, whose
slots are not lines. Each group after that takes **eight** line slots, not
six, and leaves no 0/4 leftovers:

| trunk groups | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|
| lines in 20–77 | 48 | 40 | 32 | 24 | 16 | 8 | 0 |
| trunk channels | 8 | 16 | 24 | 32 | 40 | 48 | 56 |

Seven groups, not eight: block 0 stays. A tandem on this fabric is **56
channels of trunk** and the 04–07 bank. Today's tandem (`topology.md` §1)
is 48 channels and six lines, counting eight six-channel groups; the "never
block 0" rule and that count have never quite agreed. This table follows
the rule.

At 1 % blocking (`erlang_cap` in `exch.py`, the same 1 % `topology.md`
quotes):

| channels | 8 | 16 | 24 | 32 | 48 | 56 |
|---|---|---|---|---|---|---|
| erlangs | 3.13 | 8.88 | 15.30 | 22.05 | 36.11 | 43.31 |

Today six carry 1.91 E and twelve 5.88 E. One eight-channel group is worth
more than one six-channel group and less than two of them; two eight-channel
groups facing one way (16) carry 8.88 E where two six-channel groups (12)
carry 5.88 E. Glare still wants the word's `g` bit, now on eight channels
instead of six.

The flood is unchanged: a call dialled with `1` still seizes one channel in
every direction for 2.7 s. More channels a link do not shorten it. They
raise what a hub can carry, which is what `big-exchange.md` §8 said a
wider group was for.

Baseband and POTS-trunk cards are untouched. They remain one port, any slot,
including 06–07.

---

## 8. What adoption changed

Done in the live tree. The list is the edits, not a surprise.

| | |
|---|---|
| [mf8-spec.md](../mf8/mf8-spec.md) | 16-bit frame, F = 0xFFFE, guard 0,8, eight C + P, R, K0–K3, §5 seating C0/C7, §10–11 `'150` / 4-bit counter, title |
| [frame-rate.md](../mf8/frame-rate.md) | N = 14 with eight switched and six overhead, octet = q[2:0] |
| [mf8-backplane.md](../mf8/mf8-backplane.md) | eight channel slots on the shelf, not six |
| [mf8-trunk.md](../mf8/mf8-trunk.md) | eight C/A pairs on Trunk-D; the exchange face is the **block header**, not stack header C; `TX_BIT` at 1024 kbps |
| [protocol.md](protocol.md) §5 | the map of §6.1; delete "a link's channels sit where they are on the wire" as an identity |
| [fabric.md](fabric.md) §1.1, §5.2 | delete "a trunk block's highway is an MF8 frame with F and S given back"; the commutator is only a commutator; **block header** is the star collect (eight slot appearances + `MUTE_BLK`); `MUTE_BLK` OR when a **block adapter** mates it |
| [network.md](network.md) | 10–17 first group of eight; further groups 20–27, …; one word to eight channels; `MUTE_BLK` is the `BUSY` force that section named |
| [topology.md](topology.md) | §1's table and the tandem line; Erlang rows for 8 / 16 / 24 / 32 |
| [terminal.md](terminal.md) | eight remote lines, `h0–h7`; K bits from the shelf |
| [mainboard.md](mainboard.md) §2.4 | the unit is on the **block header**, not a highway tap; line `LINE_HB` 2.048 MHz is not on the cable |
| [block-stack.md](block-stack.md) | the block header's map is the star collect on 8 × 8 (`fabric.md` §5.2); a block adapter omits the block-ribbon breakout |
| [observers.md](observers.md) | the silkscreen: row 1 is eight trunks |
| [common-cards.md](common-cards.md) | exchange-side 2 × 32 not used for this unit; shelf trunk slot still a stack header, eight wide; C is not P |
| [channel-cards.md](channel-cards.md) §4.3 | data-card keying: not C0 and C7 together |
| [clocks.md](../common/clocks.md) | trunk `LINE_HB` is the unit's 2.048 MHz; fabric `LINE_HB` remains 1.024 MHz for `SLOTQ` |
| [README.md](README.md) | 48 lines and eight trunks on block 1 when networked; six-channel figures in the opening |
| [ss0.md](ss0.md) | S states 10–15; R is not x |
| `mf8.py`, `mf8_trunk_card.v`, `exch.py`, the trunk benches | the F word is `mf8_16.py`; the unit converts 16-bit MF8 to eight highway slots. `mf8.py` and `mf8_10.py` stay as predecessor / lean measurement |

The marker, the latch, the flood, the monitor's two rules, and class hunt do
not change. A trunk is still a port of class trunk that sends a direction
word.

---

## 9. Open

- **Whether P joins the framer** or only lamps / `MUTE` after a run of
  failures. Not in `mf8_16.py`.
- **What K0–K3 are**, beyond "levels, not switched": a battery bit at
  a terminal is the obvious one; the other three are plant.
- **Shelf mechanical**: eight 100 × 100 channel layers on the spacer-stack
  (`mf8-psu.md` §5 is drawn for six). That is the far-end shelf, not §5.
- **§8**, adopted: the live map, the RTL unit and the conversion of §5.2½.

**Closed by `mf8_16.py`:** the F word is 0xFFFE; the guard is 0,8 = 0,1;
0 wrong superframe phases; PCM octets hold in no pair; the only payload
pair at the F-lane spacing is C0 and C7, and two F-word lanes there
still fail the guard; the voice residual on that pair releases in
2.83 ms mean; tracking at 1e−2 BER lost 0.04 % of frames; a slip of
1–15 bits relocked in 5–26 frames. **Closed by `mf8_10.py`, and not
taken:** the 10-bit lean, 0x3FE, guard 0,6. **Closed here:** sixteen
bits is the path; 1024 kbps / 2.048 MBaud is in range; the six extra
**Closed by `mf8_16.py`:** the F word is 0xFFFE; the guard is 0,8 = 0,1;
0 wrong superframe phases; PCM octets hold in no pair; the only payload
pair at the F-lane spacing is C0 and C7; the voice residual releases in
2.83 ms mean. **Closed by `mf8_10.py`:** the SF = 10 lean, 0x3FE, guard
0,6 — not the best available 10-bit design. **Closed by `mf8_10_16.py`:**
10-bit × 16-SF locks with 0xFFFE and guard 0,8; recovers free PCM and six
slow S states; four five-apart pairs. **Closed by `mf8_baud.py`:** plug
arithmetic and relative eye at 512 / 640 / 1024 kbps. **Open:** which
eight-channel frame to freeze. **Closed in §5:** the unit is an MF8
**block adapter** on the **block header** (`fabric.md` §5.2), not eight ribbon slots and not H;
`MUTE_BLK` is the `BUSY` force.

What is not open, if this is adopted: whether the highway and the MF8 line
are the same wire. They are not.
