# The exchange — internal protocol and fabric

What passes between a card and the switch, and how the switch is built so that
it grows eight ports at a time in 74HC with no memory part anywhere. The marker
that sets it is `exch-marker.md`; the cards that are its features are
`exch-features.md`; trunks and the network are `exch-network.md`.

> **Status: proposed, measured in simulation.** `exch.py tandem` and
> `exch.py fabric` are the runs (`exch.log`). The fabric is modelled cell by cell
> as the gates would act; its timing margins are the ones `mf8-backplane.md` §5
> computed from data-sheet figures, and none has been scoped. Package counts are
> estimates. Nothing has been on a bench.

---

## 1. The protocol is the slot interface

A port is what an MF8 channel slot already is (`mf8-backplane.md` §3):

| | each way | |
|---|---|---|
| `C` | 64 kbps, one bit a frame | the channel: CVSD, a DS0, anything |
| `A` | one level | signalling. `A_TX` is the M lead — off-hook, ringing present, `DTR`. `A_RX` is the E lead — ring, close the loop, `DSR` |
| clocks | `TX_CLK` 64 kHz, `TX_OCT` 8 kHz | **one clock domain for the whole exchange** |

**Every MF8 card is an exchange card, unchanged.** The exchange adds three pins
the backplane had reserved (§5). Voice band exists only on cards that face
analog things.

---

## 2. Why bits and not voice band — measured

The classical answer is four-wire audio plus E&M between every card and the
switch. It is universal, and it was measured before being set aside
(`exch.py tandem`: 7 talkers × 12 s, each stage encode → decode → 3.4 kHz
reconstruction, the next card's 300–3400 Hz filter, level trimmed back to
nominal):

| codecs in the chain | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| segSNR, codec noise alone, dB | 23.40 | 21.38 | 19.09 | 18.00 | 17.09 |
| loss | — | **−2.02** | −4.31 | −5.40 | −6.31 |
| segSNR against the source, dB | 22.50 | 16.40 | 13.81 | 12.69 | 11.78 |

Each tandem costs about 2 dB of codec noise for the first two and about 1 dB
after. The first row scores against the source passed through the same filters
with no codec in the chain, so it is the codec's noise alone; the last row adds the
band-edge droop of the cascaded filters, which is real in kind and overstated in
size — the model's filters are zero-phase Butterworths, steeper than a card's.

What that does to calls, in codecs in the chain:

| call | voice-band fabric | bit fabric |
|---|---|---|
| CVSD phone to CVSD phone, one exchange | 2 | **1** |
| … across one MF8 trunk | 3 | **1** |
| … through a transit exchange | 4 | **1** |
| CVSD phone to analog phone, one exchange | 1 | 1 |
| analog phone to analog phone, one exchange | **0** | 1 |
| … across one trunk / through a transit | 1 / 2 | 1 / 1 |
| 64 kbps data | cannot | passes |

Voice band wins one row: two analog phones on one exchange never meet a codec.
Everywhere else it costs the digital phone — the project's centrepiece — a
tandem on a *local* call, puts the §12.1 engine on every digital line and six of
them behind every trunk card, and cannot switch data at all. With bits switched,
the only per-hop cost is the clock-crossing slip `mf8-backplane.md` §7 measured
at −25 dB for 5 ms.

What voice band gets right is kept another way:

| | here |
|---|---|
| anything connects to anything | **voice on the fabric is MF8's 64 kbps CVSD.** A card facing anything else transcodes on the card: the FXS card does; a DNVT card is two codecs back to back |
| E&M as the universal port signalling | kept exactly: `A` |
| tones, ringing, conference, DTMF are easy | they are **lines** (`exch-features.md`) |

---

## 3. The fabric: an 8-slot highway per block

No memory part means the connection memory is flip-flops, so it lives at the
port, and the fabric grows a block at a time without touching what is installed.

```
 block h:  C_TX[0..7] ─▶ 74HC151 ─▶ HC[h]  512 kbps NRZ, this block its only driver ─────┐
           A_TX[0..7] ─▶ 74HC151 ─▶ HA[h]                                                │  to every block
           BUSY, TYPE0-2 ─▶ 4 × '151 ─▶ HB[h], HT0-2[h]   to the marker only             │
                     ▲ slot counter, '393, reset by SYNC                                 ▼
 port p:   latch 74HC273 [ highway(3) | slot(3) | BUSY | CLAIM ] ◀── marker: PORT, SRC, WR
           HC[0..7] ─▶ '151 (highway) ─▶ D ─[ FF, clocked at mid-cell when slot strobe ]─[ FF, frame edge ]─▶ C_RX[p]
           S[0..7]  ─▶ '151 (slot) ───────────▲                                      same pair for A ─▶ A_RX[p]
```

- **The unit is one highway: eight ports × 64 kbps = 512 kbps**, commutated by a
  '393 and a '151 — the trunk transmitter of `mf8-spec.md` §10 without the line
  code or the framer. A cell is 1.95 µs; every margin is one
  `mf8-backplane.md` §5 has already worked.
- **One driver per wire.** Up to eight highways run to every block as parallel
  wires. No bus turnaround, no contention, nothing faster than the MF8 line
  itself. An absent block's wire is pulled to `FILL` and its `A` wire to 0, as an
  empty MF8 slot is (§12.3).
- **Per port, space then time.** One '151 picks the highway, a second picks one
  of eight shared slot strobes, a flip-flop captures at mid-cell. A second
  flip-flop re-times at the frame edge, so a card sees `C_RX` change on one edge
  only, whatever slot its source sits in; cards sample it on the opposite phase,
  half a frame from any change.
- **Any number of ports may listen to one port.** That costs nothing, and it is
  what makes a tone a line.
- **The latch never grows.** A port only ever listens inside its own group of
  64; larger numbers are routing, not addresses (`exch-network.md`).

**16 or 32 ports is mechanical, not architectural**: two or four highways on one
backplane. Sixteen ports, four switch cards and a supply are 21 slots — one
84 HP subrack at 4 HP.

**Cost, estimated.** Per port: the '273, two '151 for `C` (highway, strobe) and
one more highway '151 for `A`, a '74 pair, and the supervision of
`exch-marker.md` §5 — about 5 packages. Per block: counter, six commutating
'151s, drivers, write decode — about 10. **≈ 50 packages a block of eight**, on
two Eurocards, beside ≈ 80 for the eight line cards it serves. The
selector-per-line sketched in `register.md` §6 is 2 packages a port at eight
lines and 10 at sixty-four: it does not grow.

---

## 4. Measured: the highway, cell by cell

`exch.py fabric` steps the gates above one cell at a time — commutator, highway
select, slot strobe, capture, re-time — with random data on every fitted port.

| | result |
|---|---|
| every source slot to every listening slot, `C` and `A` | 4 096 pairs, **0 errors, delay exactly 1 frame** for all of them |
| 1 to 8 blocks fitted, random maps, 85 % of slots filled | 2.1 M bits a row, **0 errors**; a port listening to an empty slot or an absent block receives `FILL` and `A` = 0 |
| fan-out, 63 ports on one source | identical streams, 0 errors |
| a cleared latch | listens to port 00, which is never fitted: `FILL`, `A` = 0, decoding at −48.3 dB re nominal speech |
| octets, a source sending bytes on `TX_OCT` | 255 of 255 right when the listener frames on **`RX_OCT` = `TX_OCT` + 1 frame**; 253 of 255 wrong if it does not |
| an MF8 frame as a block's highway (`mf8.build` / `mf8.framer`) | bit-exact on the right ports; after a slipped line bit the framer re-frames once and **no channel lands on the wrong port**; 45 bits are wrong across the six, all in the 15 frames before the framer let go |
| `A` through the S bit | 0 errors |
| a tie between two groups' highways | 0 errors at exactly 2 frames, one per fabric |

Because the delay is one frame for every pair, the octet phase survives any
connection: a DS0 stays a DS0 through the switch, and data passes bit-exact.

**The marker may write a latch at any instant.** 4 000 writes at random cells:

| what the listener receives | |
|---|---|
| the new source from the write's own frame on | 2 289 |
| the old source for that frame, then the new | 1 045 |
| one bit held over, then the new — neither slot was strobed in the write's frame | 666 |
| anything else | **0** |

The worst a re-point can do is repeat one bit, which is the slip
`mf8-backplane.md` §7 measured. The marker needs no synchronisation to the frame.

---

## 5. Numbering is the address

**Octal as dialled: the keys 0–7 are the digits, and a line's two digits `h s`
are its port address** — highway, slot — three bits each, straight into the two
'151s. A digit's value is the low three bits of the register's pulse count
(`register.md` §4), forced to 000 when bit 3 is set: three AND gates, so that 0
— ten pulses, `1010` — is octal 0. 8 and 9 are caught as service digits before
they are ever an address.

```
 first key   0  operator      1  long distance (reserved)      2–7  a number
             8  spare         9  outside line
 ports       00–77.  00 is never fitted: it is the silence a cleared latch listens to.
             00–17 are never subscriber-dialled, because 0 and 1 mean something in that
             position: they hold tones, registers and the first trunk block.
             Subscribers are 20–77: 48 lines a group.
```

How a number is parsed, and the four-digit form a networked exchange uses, are
`exch-marker.md` §2 and `exch-network.md` §3.

**Three reserved pins become the class mark.** `TYPE0`, `TYPE1` and the unused
`RAI` pin of `mf8-backplane.md` §8 carry a 3-bit class set by a jumper on the
card; an empty slot reads 000. The block commutates them onto three more
highways that only the marker reads. Nothing in the fabric uses them.

---

## 6. Not measured

- **Every timing margin.** They are `mf8-backplane.md` §5's, computed, at the
  same cell width. Scope the capture strobe against the highway at the far end
  of the longest inter-shelf run.
- **The highways between shelves**: single-ended 74HC at 512 kbps over a ribbon
  is assumed; RS-422 if shelves are racks apart.
- **Package counts.** Estimates from a block diagram, not a parts list.
- **Tandem loss with real filters.** The "against the source" row overstates the
  droop. The codec-only row is the one to quote.
- **The re-timing phase** — `RX_CLK` as the opposite phase of `TX_CLK` — against
  the line card's two-stage synchronizer, which is now redundant but still there.
