# The exchange — internal protocol and fabric

What passes between a card and the switch, and how the switch is built so that
it grows eight ports at a time in 74HC with no memory part anywhere. 

An exchange is one 8 × 8 fabric — eight highways by eight slots — and 64 ports.

More lines are more exchanges (`network.md`), not a bigger one. 


> **Status: proposed, measured in simulation.** `exch.py tandem` and
> `exch.py fabric` are the runs (`exch.log`). The fabric is modelled cell by cell
> as the gates would act; its timing margins are the ones `mf8-backplane.md` §5
> computed from data-sheet figures, and none has been scoped. Package counts are
> estimates. Nothing has been on a bench.

---

## 1. The protocol is the slot interface

A port has the same structure as an MF8 channel (`mf8-backplane.md` §3):

| | each way | |
|---|---|---|
| `C` | 64 kbps, one bit a frame | the channel: CVSD, a DS0, anything |
| `A` | one level | signalling. `A_TX` is the M lead — off-hook, ringing present, `DTR`. `A_RX` is the E lead — ring, close the loop, `DSR` |
| clocks | `TX_CLK` 64 kHz, `TX_OCT` 8 kHz | **one clock domain for the whole exchange** |

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
| tones, ringing, conference, DTMF are easy | they are **lines** (`features.md`, `conference.md`) |

---

## 3. The fabric: an 8-slot highway per block

No memory part means the connection memory is flip-flops, so it lives at the
port, and the fabric grows a block at a time without requiring modification
of the previously installed parts of the exchange.

```
 block h:  C_TX[0..7] ─▶ 74HC151 ─▶ HC[h]  512 kbps NRZ, this block its only driver ─────┐
           A_TX[0..7] ─▶ 74HC151 ─▶ HA[h]                                                │  to every block
           BUSY, the word ─▶ 2 × '151 ─▶ PB[1:0]          to the marker only             │
                     ▲ slot counter, '393, reset by SYNC                                 ▼
 port p:   latch 74HC273 [ highway(3) | slot(3) | BUSY | CLAIM ] ◀── marker: one 16-bit word, then WR
           HC[0..7] ─▶ '151 (highway) ─▶ D ─[ FF, clocked at mid-cell when slot strobe ]─[ FF, frame edge ]─▶ C_RX[p]
           S[0..7]  ─▶ '151 (slot) ───────────▲                                      same pair for A ─▶ A_RX[p]
```

- The unit is one highway: eight ports × 64 kbps = 512 kbps, commutated by a
  '393 and a '151 — the trunk transmitter of `mf8-spec.md` §10 without the line
  code or the framer and slightly reordered.  A cell is 1.95 µs so there is generous margin.
  
- **One driver per wire.** Up to eight highways run to every block as parallel
  wires. No bus turnaround, no contention, nothing faster than the MF8 line
  itself. An absent block's wire is pulled to `FILL` and its `A` wire to 0, as an
  empty MF8 slot is (§12.3).
- **Per port, space then time.** One '151 picks the highway, a second picks one
  of eight shared slot strobes, a flip-flop captures at mid-cell. Cards sample
  `C_RX` at the frame edge, which is half a cell from any capture, so a bit is
  one frame late whatever the two slots. (The re-timing flip-flop drawn above
  turned out not to be needed: `fabric.md` §3.4.)
- **Any number of ports may listen to one port.** That costs nothing, and it is
  what makes a tone a line.
- **It is an 8 × 8 fabric with one-way crosspoints**: eight highways in space by
  eight slots in time, and the 64 squares are the 64 ports. Every port can listen
  to any square, so to any of 64 sources, and its latch holds the one it has —
  one of 4 096 pairings, never an array of them. One stage, so
  there is exactly one path between two ports and it is always free: the marker
  never hunts inside the fabric. A conversation is two crosspoints.
- **The latch never grows.** A port only ever listens inside its own exchange; the
  digits in front of `h s` name an exchange, not an address (`network.md`).

**16 or 32 ports is mechanical, not architectural**: two or four highways on one
backplane. Sixteen ports, four switch cards and a supply are 21 slots — one
84 HP subrack at 4 HP.

**Cost.** `fabric.md` is the parts list: 5 packages a port for the crosspoint
and about 3¼ for its supervision, 13 shared by a block — **≈ 80 packages a block
of eight**, beside ≈ 80 for the eight line cards it serves. (An earlier figure of
50 here left out most of the supervision.) The
selector-per-line sketched in `register.md` §6 is 2 packages a port at eight
lines and 10 at sixty-four: it does not grow.

### 3.1 Past 64 ports: more exchanges, not a bigger one

**Decided: the exchange stays 8 × 8 — 64 ports**, and a larger system is several
of them joined by tie trunks and the flood (`network.md`). Four ways of
making one fabric bigger were worked through and set aside as too complex for
what they bought:

| | what it was | why not |
|---|---|---|
| banks joined by junctors, a rack marker, a shared service highway | several 64-port fabrics in one rack as one exchange | a fifth of all ports become junctors at 100 lines and a third at 1000; registers cannot be pooled; tie wiring, a tandem stage, a marker that hunts paths |
| 64-slot highways at 4.096 Mbps | a rack of 512 ports behind one '151 | a 244 ns cell is outside comfortable 74HC |
| allocated talk slots, 16 to a highway at 1.024 Mbps | a port holds a slot only while it is in a call, so a listener need only reach the slots in use | a second rate; ≈ 8 packages a port against 5 |
| the same in MF8's own frame at 512 kbps, highways pooled in fours | one rate, sixteen banks in one stage | ≈ 11 packages a port: four to six packages a line more than anything else here |

---

## 4. Measured: the highway, cell by cell

`exch.py fabric` steps the gates above one cell at a time — commutator, highway
select, slot strobe, capture, re-time — with random data on every fitted port.

| | result |
|---|---|
| every source slot to every listening slot, `C` and `A` | 4 096 pairs, **0 errors, delay exactly 1 frame** for all of them |
| 1 to 8 blocks fitted, random maps, 85 % of slots filled | 2.1 M bits a row, **0 errors**; a port listening to an empty slot or an absent block receives `FILL` and `A` = 0 |
| fan-out, 63 ports on one source | identical streams, 0 errors |
| a cleared latch | listens to port 00, which is never fitted (§5): `FILL`, `A` = 0, decoding at −48.3 dB re nominal speech |
| octets, a source sending bytes on `TX_OCT` | 255 of 255 right when the listener frames on **`RX_OCT` = `TX_OCT` + 1 frame**; 253 of 255 wrong if it does not |
| an MF8 frame as a block's highway, its channels on slots 1–3 and 5–7 as §5 has them (`mf8.build` / `mf8.framer`) | bit-exact on the right ports; after a slipped line bit the framer re-frames once and **no channel lands on the wrong port**; 45 bits are wrong across the six, all in the 15 frames before the framer let go |
| `A` through the S bit | 0 errors |
| a copper tie between two exchanges | 0 errors at exactly 2 frames, one per fabric |

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
 first key   0  operator
             1  standalone: a local number, 1 s
                networked: the flood, 1 e b h s          (network card fitted, or the strap that says so)
             2–7  a local number, h s
             8  spare: cannot-complete      9  outside line

 00          idle: never fitted; the silence a cleared latch listens to
 01          dial tone
 02          busy tone
 03          cannot-complete tone
 04–07       four ordinary line slots (full port circuits).  Nominal use:
             04  the operator
             05  night announcement / backup operator
             06–07  more operators, or single-channel trunks
             — still undialable as 0 s, because 0 is the operator key; reached by
               hunt, warm restricted line, console, or (if trunks) direction hunt

 standalone  10–77  fifty-six lines (1 is a highway digit; no trunk block)
 networked   11–13, 15–17  first MF8 trunk group (block 1); 10 and 14 free
             20–77  forty-eight lines
             21–23 25–27 / 31–33 35–37 / …  further MF8 groups in blocks 2+, at
               the cost of those lines (`network.md` §1)
 h1–h3 h5–h7 in any trunk or line block 1–7: a subscriber terminal, six lines
             over an MF8 link (`terminal.md`).  Not block 0: its channel
             slots are the tones and the 04–07 bank
```

A group is named by its block. Which way it faces, N, S, E or W, is in its
ports' words, set by jumpers on its trunk card (`network.md` §1). Any group
may face any way, and two groups facing the same way are one direction of twelve
channels. **MF8 trunk groups sit in blocks 1–7, never in block 0** — block 0 holds
the three tones and the four-line bank. A single-channel trunk card may sit in
any slot of those blocks, including 06–07 (`network.md` §1.1). A tandem at
the centre of a star can still give blocks 1–7 to trunks; the twelve spare seats
at slots 0 and 4 of those blocks remain ordinary ports (`network.md` §5).

**Ports 00–07 are never dialled**, because 0 is the operator key. **Ports 10–17
are never dialled on a networked exchange**, because 1 opens the flood; on a
standalone exchange they are ordinary lines. Registers and monitors take no
ports: a pulse register reads its caller's hook from the M highway through a
probe (`marker.md` §4), and a monitor reads a trunk's A on the trunk block
(`monitor.md`).

**A link's channels sit where they are on the wire.** MF8 sends channel C*n*'s
bit at frame position 1–3 or 5–7, with F at 0 and S at 4, and its A bit at the
superframe state of the same number (`mf8-spec.md` §2). A trunk port takes that
number as its slot. So one 3-bit address picks a channel's C bit in the frame,
its A bit in the superframe, its input on the trunk card's frame mux and '259,
and its port, and the trunk card is wired straight across. Slots 0 and 4, which
are F and S on the wire, are ports of their own: on a trunk block in 1–7 they
are two more ports (empty, a line, a single-channel trunk, a test tone); on
block 0 they are idle (00) and the first of the 04–07 bank (04).

**A cleared latch listens to 00, and 00 is never fitted.** A port that releases
clears its '273 to zeros, which is highway 0, slot 0: `FILL` and A = 0, the
silence of an empty slot. Nothing that talks may sit there. If the operator
were at 00, every idle phone would ring whenever the operator lifted, because
on-hook with E high is the ring condition. A phone off-hook with a cleared
latch, one waiting for a register for example, would also hear the operator's
calls. So the operator's home is 04, first of the four-line bank. The latch
holds port numbers as they are: the slot select is wired in order, and `SRC`
carries the number as dialled.

How a number is parsed, and the form `1 e b h s` — the network's key, the
exchange's code, then the line — that reaches a line on any exchange, are
`marker.md` §2 and `network.md` §2–3.

**Two reserved pins say what a port is.** `mf8-backplane.md` §8 reserved
`TYPE0`, `TYPE1` and `RAI` in the channel slot and connects none of them. The
exchange uses the first two (`extensions.md` §2):

- **The word, on a12**: eight bits, one a frame, every octet. It carries the
  port's class and its options (a trunk's direction, a hunt group,
  restricted warm / `z` / `L` / `b`), or the port it is nailed to. Class
  *restricted* is a class of its own. The block commutates it onto one wire that
  only the marker reads, and the marker's scanner reads the whole word at each
  visit. **A plain line card ties the pin to ground**, which reads all ones and
  means a line with no options: no part and no jumper. An empty slot reads all
  zeros, unequipped.
- **`/ANS`, on a13**: the one thing the port's own gates need to know, which is
  whether the port rings. A phone's card leaves it open. A trunk, an outside
  line, a conference bridge leg and any card that answers at once tie it low.

A card only ever pulls the two pins to ground, so it works unchanged in an MF8
shelf. **Whatever sits behind a port says everything the exchange needs to know
about it**: a card for its port, a trunk card for each of its six channels.
Nothing in the fabric uses the word.

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
