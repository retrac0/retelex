# The exchange — trunks

The cards that link one exchange to another: what every trunk card must do, the
baseband tie card, the local eight-channel trunk, and the MF8 group's face on a
block. What the network does with a trunk is `network.md`; what a carrier must
carry is `network.md` §2.

> **Built:** `newimpl/rtl/baseband_card.v` (benches `tb_tie`, `tb_word`, `tb_net`, `tb_chain`, `tb_max`); `newimpl/rtl/local_trunk.v` (`tb_ltu`, `tb_lnet`, `tb_lfull`, `tb_lchain`). Nothing drawn.
> **Not built:** the MF8 six-channel adapter (§4).
> **Proposed:** `proposed/pots-trunk.md` (a two-wire voice-band tie), `proposed/terminal.md` (an MF8 shelf as remote lines).

## 1. A trunk is a card

A trunk is a port whose card says it is one. **Nothing else in the exchange holds
that fact**: no jumper on the marker or the network unit says a port is a trunk
or which way it faces; whoever needs to know reads the card's word (`network.md`
§3). A trunk port holds no digits and decides nothing. What every trunk card
does:

| | |
|---|---|
| **the word** | class trunk (family 01, member 0), the glare bit and the direction, all in the primary octet (`card-word.md` §2), from jumpers on the card. The direction is the direction of the link the card is wired to, so a strap anywhere else could disagree with the cable |
| **`/ANS`** | tied low on the board: a trunk answers at once and never rings. One that rang would give its caller ringback the instant it was seized, and chop forward A in the cadence (`fabric.md` §5) |
| **gating** | the word and M (`A_TX`) are enabled only while the link is up **and** the card's power-up RC (≈ 100 ms) has settled. Otherwise the port reads NONE, all zeros, so it is never a caller and never hunted, and its A is 0, so a call in progress releases. M is gated as well as the word because a seizure passed on while the word still read NONE would be taken for nobody's. A block adapter fails its whole group at once (`fabric.md` §6.2) |
| **one glare bit a direction** | every trunk facing one way carries the same glare bit, and the two ends of a link carry opposite ones (`network.md` §5). The bit belongs to the direction, not to the card: a card of one channel needs none on its own, and takes its neighbours' beside them |

**A trunk is never dialled** — its port is cannot-complete as a number
(`numbering.md` §4) — and its M is never a caller: the network unit holds it
(`network.md` §3.3). A card carries no jumper but its word: the ring strap is the
unit's, one a direction (`network.md` §7). Where trunks sit in the port map is
`numbering.md` §2.

**What a group carries**, at 1 % blocking: one channel 0.01 E, two 0.15 E, six
1.91 E, eight 3.13 E, twelve 5.88 E, sixteen 8.88 E; and every call that leaves
holds a channel on every link for 2.0–3.8 s (`network.md` §4.3). A direction of
one channel suits a few lines at the edge of a network, a bypass across a ring,
or topping a group up; a group is the route for an exchange's traffic.

| card | channels | where it sits | |
|---|---|---|---|
| baseband tie (§2) | 1 | any channel socket, like a line card | built |
| local eight-channel trunk (§3) | 8 | a block adapter, one block's eight ports | built |
| MF8 group (§4) | 6 | a block adapter, six of a block's eight ports | not built |
| two-wire voice-band tie | 1 | any channel socket | `proposed/pots-trunk.md` |
| E&M voice band on four wires | 1 | any channel socket | `mf8/mf8-spec.md` §12.1; not designed for the exchange |
| two CVSD line interfaces back to back | 1 | any channel socket | not designed |

Any mix may face one way. What a block adapter owes the block, and why it never
taps the highway, is `fabric.md` §6.2.

## 2. The baseband tie card

**A tie trunk with nothing in between**: `C` and A out, `C` and A in, and a fifth
conductor each way carrying `TX_CLK`. No line code, no framer, no codec. It sits
in any channel socket, draws `+5 V` only, and is the cheapest card in the
exchange. The received `C` is one bit a frame, changed at the far end's frame
edge and held for its 15.6 µs, so sampling it once a frame needs no clock
recovery: **the link is slow enough to be its own eye.**

| conductor | |
|---|---|
| `C` out | the port's `C_RX`, 64 kb/s NRZ, changing at the local frame edge |
| A out | the port's `A_RX`: E, and `CLAIM` ORed in (`fabric.md` §5), so a claim crosses on it |
| clock out | `TX_CLK`, a continuous 64 kHz square wave |
| `C` in | re-timed into `C_TX` by half a '74, on the edge the clock jumper picks |
| A in | into `A_TX` through an RC of tens of microseconds and a quarter '14: this is M at the port |
| clock in | the link-down detector, and the far bit clock on one clock card |

**A has a wire of its own**, and that is the best thing about the card. The RC is
tens of microseconds against MF8's 2 ms, so dial pulses cross undistorted: where
distance allows, a chain that must carry pulses many hops is better on baseband
ties than on MF8.

**The clock jumper** picks the edge that re-times incoming `C`:

| | | what crosses |
|---|---|---|
| **two clocks** — the network's case | the local frame edge | a slip every 390–780 ms between neighbours, as on MF8 (`network.md` §8). Voice and oversampled async; **not** synchronous data |
| **one clock** — two exchanges on one clock card | the far clock, on the fifth conductor | **bit-exact**, two frames late, one a fabric (`exch.py fabric` 8, 0 errors): HDLC passes. G.711 does not |

**The octet phase does not survive a tie, even on one clock.** Each end frames on
its own `SCAN[2:0]`, which power-up sets independently; measured on two exchanges
on one master clock, B's scan φ frames behind A's, the errors are 1 − φ frames
A→B and 1 + φ B→A. They always sum to 2 mod 8, so no alignment of the counters
makes both directions right (2026-09-25, a scratch bench).

**Link down is the one thing four wires cannot tell.** An idle link and a cut
cable both read A = 0, and with failsafe receivers so does `C`:

| | | |
|---|---|---|
| edge detection on `C` | an idle far port sends `FILL`; no edge for *n* frames would be a cut | **no**: HDLC idles at all ones, and a live data call would read as a cut cable |
| **a fifth conductor each way, carrying `TX_CLK`** | half a '123 retriggered by it; silence is a cut, and a pulled cable stops it | **yes**: the smallest fail-safe thing, and it is the far bit clock as well. The RTL takes three frames of silence as a cut |
| a line code on `C` | differential Manchester at 128 kBaud, as the subscriber loop: DC-free, so transformer-coupled, with carrier detect from the decoder | for **between buildings**: ≈ 2–3 packages more and `LOOP_HB`. Not the baseline |

**The link-down detector is the enable on the word**, and on M (§1). Four wires
without the clock are still a usable link inside one room, but a cut cable then
leaves the trunk in the hunt: one failed call per attempt while it is broken.
That is a choice to make knowingly.

**Levels.** In one rack on one ground: 74HC with 33 Ω at the driver, six
conductors and a ground. Between racks on separate grounds: V.11 / RS-422, one
26LS31 and one 26LS32 for the six signals, three pairs each way.

**The card.** Which socket pins it uses is `common/common-cards.md` §1 and the
header of `baseband_card.v`: eight of the fourteen signal pins and `+5 V`. The
word is one '165 from jumpers into a 2N7002 (`card-word.md` §3). Parts: half a
'74 for `C`, a quarter '14 and an RC for A, half a '123 for link down, the '165
and a FET for the word, `/ANS` tied low: about 2¼ packages, and two more for
RS-422. A sketch; the RTL models the A-lead RC as two flip-flops on the frame
edge.

## 3. The local eight-channel trunk

**A short-range tie between two exchanges, one block at each end**, for a room or
adjacent racks: eight channels where an MF8 group gives six. The wire is a
highway-shaped copy of `C` and A — eight cells a frame at 512 kbps, on conductors
of their own — with the sender's `HCLK` and `TX_CLK` beside them, so the receiver
is timed by the far end. No line code, no F and S, no crystal. It is a **block
adapter**: it drives one block's eight port appearances (`C_TX`, `A_TX`, word and
`/ANS` out; `C_RX`, `A_RX` in) and takes the adapter commons, J6
(`block-stack.md` §6): `TX_CLK`, `TX_OCT`, `FILL` and `HCLK` in; `MUTE_BLK`
out. How the eight appearances reach the port cards is open
(`block-stack.md` §9).

| path | timed by | what |
|---|---|---|
| **transmit** | local `HCLK`, `TX_CLK` | a cell counter rebuilds `SLOT`; two '151s mux the eight `C_RX` and `A_RX`; a '74 drives `C_hw`, `A_hw` at `HCLK`'s rise; the local `HCLK` and `TX_CLK` go on the wire |
| **receive** | far `HCLK`, `TX_CLK` | the same counter on the far clocks; two '259s take `C_hw`, `A_hw` at the far `HCLK`'s fall. The far exchange is master of this direction |
| **crossing** | local `TX_CLK` | two '273s take the sixteen bits into the local frame at its edge, as `C_TX` and `A_TX` |

**Every edge on the wire is clocked half a cell from the edge that samples it.**
A port's `C_RX` and `A_RX` change at the mid-cell capture, `HCLK`'s fall; the
unit samples them at `HCLK`'s rise and changes the wire there; the far end
samples at its `HCLK`'s fall. No transmit latch: the ports hold each bit for a
frame.

**Cell 0 is found at mid-cell.** `TX_CLK` rises on the same clock-card edge as
`HCLK`, so a counter cleared by that rise races itself. Sampled at `HCLK`'s fall,
`TX_CLK` is high in cells 0–3 and low in 4–7, so its first high sample is cell 0,
and a quarter '74 remembers the last sample. Without it every channel's bits land
on another's port (`faults.py` F31).

**A has no RC here.** It arrives as a clocked bit in its own cell and crosses
like `C`: `tb_ltu` has each edge of A across in under 0.1 ms, and a 40 ms make
keeping its length to 0.05 ms. **`HCLK` is carried** because the cell eye is
1.95 µs: the receiver must track the far transmitter's cell clock, and far
`TX_CLK` is only the frame mark.

**It slips at the crossing**, one bit dropped or doubled a channel, A and `C`
together (`network.md` §8). In `tb_ltu`, at 1000 ppm, every channel slips and
still carries only its own bits, and no A bit lands on another channel.

**The wire**, each way: `C_hw` and `A_hw` at 512 kbps NRZ, `HCLK` at 512 kHz,
`TX_CLK` at 64 kHz as the frame mark. Single-ended 74HC on twisted pair, 33 Ω at
the driver, on a common ground in one rack or adjacent racks; between racks on
separate grounds, the same four as RS-422, four pairs each way. No transformers:
isolation and longer plant are MF8's. An idle channel's far latch listens to 00,
so it carries `FILL` and A = 0.

**Link down and power-up.** Far `HCLK` silent for three frames (half a '123), or
the first ≈ 100 ms after power-up, and the group fails as a block adapter does
(`fabric.md` §6.2). `tb_ltu`: a cut with no call busies all sixteen ports, reads
NONE and sends `FILL`.

**The group.** One '165 from jumpers, fanned to eight 2N7002s: one word for all
eight channels, which share one link and so one direction. `/ANS` tied low. It
takes a whole block 1–7; the first group goes in block 1, whose ports 10–17 a
networked exchange never dials (`numbering.md` §2). About 17 packages beside the
eight port circuits: two counters and their quarter '74s, two '151s, half a '74,
drivers and receivers, two '259s, two '273s, the gating ('157 × 2, '08 × 2), and
the word, `MUTE_BLK` and the detector. A sketch.

**Benches.** `tb_ltu`: two exchanges on two crystals, sixteen channels patched by
hand. `tb_lnet`: calls dialled across it, B 100 ppm fast, the glare end hunting
from the top, the cable pulled. `tb_lfull`: all eight channels busy, a ninth call
refused at either end, glare on the last one. `tb_lchain`: a transit across two
groups, two calls at once. **Bring-up**: two units with their appearances looped
on a jig (far `HCLK` both ways, `MUTE_BLK` falls; scope `C_hw` against far
`HCLK`); one block stuffed with no far end (eight ports NONE and busy); then a
second exchange, and the cable pulled in a call.

## 4. The MF8 six-channel face

An MF8 group is a **block adapter**, one link of six channels on one block's
header, its line the MF8 pair of `mf8/mf8-spec.md`: the 8-bit frame, 512 kbps,
1.024 MBaud, F and S opposite. It drives appearances **1–3 and 5–7**. **Seats 0
and 4 are unequipped**: nothing drives them, they read NONE, and no card sits
there beside the adapter; whether they may keep cards of their own is open (§5).
**Not built**: `newimpl` has no MF8 adapter; the retired
`old/verilog/rtl/mf8_trunk_card.v` modelled one.

```
 bit / slot:  0     1      2      3      4     5      6      7
 MF8 line:  [ F ][ C1 ][ C2 ][ C3 ][ S ][ C4 ][ C5 ][ C6 ]
 a block:     h0    h1     h2     h3     h4    h5     h6     h7
```

**The frame shape is fused with the cell count; the highway is not.** One 3-bit
address is a channel's `C` bit on the line, its A bit's superframe state, its
input on the adapter's mux and '259, and its port's slot. The transmitter inserts
F at bit 0 and S at bit 4 and takes the payload from appearances 1–3 and 5–7,
`tx_bit = slot 0 ? F : slot 4 ? S : C_RX[slot]`, with A from each `A_RX` into the
S lane. F and S exist only on the line. Measured in `exch.py fabric`: an MF8
frame on a block, channels on 1–3 and 5–7, is bit-exact on the right ports; after
a slipped line bit the framer re-frames once and no channel lands on a wrong port
(45 bits wrong across the six, all in the 15 frames before it let go); A through
the S bit, 0 errors. The address costs nothing extra; there are six channels and
not eight because F and S are load-bearing (`mf8/mf8-spec.md` §3; eight channels
a line were measured and not taken, `analysis/eight-channel-mf8.md`).

**Receive** crosses the six `C` into the local frame on two '174s, and A through
the RC and Schmitt gate of `mf8/mf8-spec.md` §14; the line code and its receiver
are `mf8/mf8-spec.md` §9's. **Transmit is in this exchange's clock**: the card
owns no crystal, and wants the 1.024 MHz half-bit clock and the cell count at the
adapter (§5).

**Lock is the enable on the words**, as §1: not locked, or no carrier, and the
group fails as a block adapter does (`fabric.md` §6.2). The remote alarm, x
(`mf8/mf8-spec.md` §3.5), is made on the adapter while it is not locked; it is
not a pin of the header. **One word** from one '165 serves all six channels,
`/ANS` tied low. An MF8 shelf of channel cards at the far end makes the same link
six lines of this exchange, each channel's word and `/ANS` set to match the card
at the far end (`proposed/terminal.md`); that shelf must speak the remote alarm
too (§5).

## 5. Open

- **The MF8 adapter's 1.024 MHz.** The six-channel frame transmits in the
  fabric's clock and wants a 1.024 MHz half-bit clock and `SLOT` at the adapter,
  but the adapter commons carry `HCLK` at 512 kHz and neither `SLOT` nor `SLOTQ`
  (`block-stack.md` §6), and 1.024 MHz cannot be divided out of 512 kHz.
  Options: an edge doubler on `HCLK` with the cell count rebuilt as the local
  trunk does; `SLOTQ` or `SLOT` on a J6 pin; the 1.024 MHz tap itself brought
  out on J6; or a crystal on the adapter with its own clock-domain crossing.
  Blocks the MF8 adapter.
- **An eight-channel adapter's face** in the block stack, eight J4 ribbons or a
  face of its own, is `block-stack.md` §9's open item; the RTL wires eight
  socket-shaped appearances and is agnostic. Blocks both adapters as boards.
- **MF8 seats 0 and 4.** Under an adapter nothing drives them and they read
  none (§4). With the appearances on J4 ribbons (`block-stack.md` §5) they could
  instead keep cards of their own — a line, or a single-channel trunk — beside
  the adapter. Decide which; the port map (`numbering.md` §2) follows §4.
- **A terminal's far end.** The adapter holds x at 1 while it is not locked and
  takes x at 1 for 32 ms as the far end's alarm; a stock MF8 shelf does neither,
  so `proposed/terminal.md` needs a converted far end. Whether the adapter should
  also work to an unconverted shelf, and what it does with a far end that never
  sends x, is open.
- **Board constants.** The link-down time of both built cards (the RTL takes
  three frames of silence), and the baseband card's A-lead RC, are unchosen on a
  board; the baseband card's sampling margin where the two frame edges coincide,
  on two clocks, is not worked.
- **Not measured**: the local trunk's 512 kbps eye on a real cable, a cut during
  a dialled call on either card, glare on a baseband tie (at 0.01 E a channel,
  arithmetic puts it at once in decades).
