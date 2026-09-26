# Subscriber terminal: six lines over an MF8 link

An MF8 block adapter (`trunks.md` §4) does not know what is at the far end of
its link. If it is a stock MF8 shelf of channel cards, the link is six lines
of this exchange at another site: a subscriber terminal. It works because
**the exchange's port is an MF8 slot**, `C` and one signalling level each way,
all a station card uses (`fabric.md` §5). The link carries `C` bit for bit and
A 1.5–2 ms late with a break 0.5 ms short (`common/channel-cards.md` §5), so
no card at the terminal knows an exchange is at the other end. One phone at a
distance is a subscriber line instead (`common/subscriber-line.md`).

> **Proposed.** Nothing drawn, nothing on a bench, no remote line in any model
> (only a frame through a block, the A path and one slip are measured). Every
> part is one the design already has; the MF8 adapter is not yet written.

## 1. At the exchange

| | tie trunk | terminal |
|---|---|---|
| channels | h1–h3, h5–h7 of the adapter's block (`numbering.md` §2) | the same six, which are lines, dialled `h s` here and `1 e b h s` from the network |
| each channel's word | trunk, glare and direction, one '165 for all six; `/ANS` low | what the card at that channel's far end is (§2) |
| the unit | takes a seizure on a flood-trunk word (`network.md` §3) | never involved: a channel that says line is the marker's caller |
| link down | A falls and calls release; the words read NONE; `MUTE_BLK` holds the ports `BUSY` (`trunks.md` §1, `fabric.md` §5) | the same, so a call to a terminal line gets cannot-complete |

Each line keeps its channel, so nothing is hunted across the link and nothing
blocks. **Blocks 2–7**, one link a block: up to six terminals, 36 lines; block 1
only on a standalone exchange. The link's spare S bit carries only the remote
alarm (`mf8/mf8-spec.md` §3.5).

## 2. What a channel says

The adapter gives each channel a word pin and an `/ANS` pin, read like a card's
(`fabric.md` §4). A jumper a channel takes the word to the plain-line constant,
the shared '165 or a '165 of its own; a second sets `/ANS`. Every word passes
the link's lock gate, and only the primary octet is read (`card-word.md` §7).

| at the terminal | channel's word; `/ANS` | the port |
|---|---|---|
| CVSD line card, FXS card | plain line; open | rings in cadence, gives ringback |
| data card | line with option D (`card-word.md` §4); low for `DSR` at once | never meets a voice port |
| FXO card | outside line; low | 9 hunts it; a CO ringing in goes to 04 (`features.md` §4) |
| a second operator phone | answers-to 04 (`card-word.md` §5); open | takes 0's calls while 04 is busy |
| a phone on a private line | tied nail to a port here, which nails back (`card-word.md` §6.2); open | a ringdown holding only its own channel |

**Label both ends, and keep the word and `/ANS` in step**: a channel jumpered
line with an FXO card behind it takes every CO ring for a phone lifting.

## 3. Clocking

Shelf and exchange each run on a crystal, and a channel slips a bit at their
offset where they meet (`network.md` §8): toward the phone only on a CVSD line
card, which samples `C_RX` on its own `TX_CLK` (`mf8/mf8-backplane.md` §2), and
from the phone at the adapter's crossing. Voice does not hear it; synchronous
data and G.711 cannot cross a free-running terminal.

**Loop timing removes the slips**: the terminal's trunk card transmits on the
clock it recovers from the link. The no-slaving rule (`network.md` §8) is about
exchanges, and MF8's reason against slaving, that a slave's phones lose their
clock with the trunk (`mf8/mf8-backplane.md` §2), fails at a terminal, whose
phones reach nothing without the link. It needs a PLL locked to the receiver's
transition strobes, since that receiver has no clock (`mf8/mf8-spec.md` §9.4).

## 4. Bringing it up

The link alone, two trunk cards back to back. Then a loopback test line in a
terminal slot (`features.md` §7): hear yourself, and let a data card count slips
through it for the crystals' offset (a second's count over two crossings and
64 000). Then one phone, both release orders, and a link broken mid-call,
which releases both ports and gives the terminal's lines cannot-complete.

## 5. Open

- **Loop timing, the live question.** The PLL is not designed, nor whether a
  channel's '259 write, locked, can sit on the exchange's frame edge and flip
  between frames with its jitter. Until then: voice and async data only.
- **The alarm needs a converted far end.** x = 1 fails a fixed-guard receiver
  (`proposed/ss0.md` §2), so a stock shelf neither sends the alarm nor locks
  while it is sent; whether the adapter should work to one is `trunks.md` §5.
- **The adapter's face**: whether h0 and h4 of a terminal's block take local
  cards is `trunks.md` §5's. The per-channel jumpers are not drawn.
