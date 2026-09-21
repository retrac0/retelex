# The exchange — subscriber terminals: six lines over an MF8 link

A trunk block (`network.md` §1) is an MF8 trunk card on six port circuits.
It does not know what is at the far end of its link. If the far end is another
exchange's trunk block, the link is a tie trunk. If it is a stock MF8 shelf of
channel cards, the link is **six lines of this exchange at another site**: a
subscriber terminal. The exchange end is the same trunk card either way, with
its channels saying line and not trunk. The terminal is MF8 as it stands, and no card in it
knows that an exchange is at the other end.

Which one a site gets depends on what it needs. One phone at a distance is a
subscriber line: two pairs to a CVSD phone (`subscriber-line.md`). Up to six at
one site is a terminal on one MF8 link, and the lines can be anything a channel
card serves: CVSD phones, analog phones, a data terminal, an outside line.

> **Status: proposed.** Nothing here is newly measured. Every part is one the
> design already has, and every figure is cited from where it was measured. No
> remote line is in the `calls` model, no circuit has been drawn, and nothing
> has been on a bench.

---

## 1. Why it works

```
 exchange, block h                                           subscriber terminal: a stock MF8 shelf
 ports h1–h3, h5–h7 ── trunk card ═══ MF8, a pair each way ═══ trunk card ── slots C1–C6: channel cards
 ports h0, h4: local slots, cards as usual                                   CVSD line, FXS, data, FXO
```

**The exchange's port is an MF8 slot.** Its protocol is the slot interface: `C`
and one signalling level each way (`protocol.md` §1). An MF8 station card
(the CVSD subscriber line card, the FXS card or the data card) puts off-hook on
`A_TX` and reads ring from `A_RX`, whatever faces it (`channel-cards.md` §1). A port
gives it exactly that: `A_RX` is E, chopped by the ring cadence while the phone
is on-hook (`fabric.md` §3.5). A card at a terminal differs from the same
card in a local slot by one thing only: the link, which carries `C` bit for bit
and A through an RC.

| | a card in a local slot | the same card at a terminal |
|---|---|---|
| its voice | `C_TX` into the block's commutator | across the link, then through the trunk card's '174 into the commutator |
| hook, dial pulses | M on the block's A commutator | M across the link's A: 1.5 ms later on a rise, 2.0 ms on a fall. Breaks arrive 0.5 ms short, and 10 of 10 pulses arrive at every line error rate to 6e−2 (`channel-cards.md` §5) |
| ringing | its port's `A_RX`, in cadence | the same `A_RX`, sent as forward A: it rings in the same cadence |
| ringback | the caller hears `RBT` from the called port's highway cell | the same, at the exchange |
| answer, release | M rises; M or E falls for 256 ms | the same, 1.5 or 2 ms later |
| codecs in a call | one pair, end to end | the same. Bits cross the link and are never decoded |

---

## 2. At the exchange

A terminal's link lands on a block as a tie trunk's does, and the block is
fitted the same way. What differs:

| | tie trunk | subscriber terminal |
|---|---|---|
| block | 0 or 1, and optionally 2 and 3 | any of 2–7, one link a block |
| ports | slots 1–3 and 5–7, where the channels are on the wire (`protocol.md` §5) | the same slots, which are lines *h*1–*h*3 and *h*5–*h*7, dialled like any other line. Slots 0 and 4 stay local: lines *h*0 and *h*4 |
| what a channel says | trunk and its direction, one word for all six, and `/ANS` tied low (`extensions.md` §2) | line: its word line tied to ground, as a plain line card's pin is, and `/ANS` open, so the port rings its phone and gives ringback. It can be set a channel at a time (§3) |
| trunk card | transmits in the exchange's clock (a strap). Its receive side crosses into that clock by two '174s for `C` and the RC and Schmitt gate for A | the same card, the same straps |
| monitors, network card | two monitors a block, and the network card hunts the class and patches it | **not fitted.** Class 1 is not the network card's. A monitor on the block would take a subscriber lifting the handset for a seizure and count their digits |
| `CLAIM` gate | backward A on a claimed trunk | never written, and harmless (`fabric.md` §3.1) |
| link down | `MUTE` clears the A '259: every M falls and calls release. `MUTE` forces the block's `BUSY` to 1 and stops the card's words, so a dead trunk is not hunted | the same. The six lines read on-hook, calls in progress release, and a caller dialling one of them gets cannot-complete instead of ringing a phone that cannot ring |

**Numbers.** A terminal's lines are lines of the exchange: `h s` from inside it,
`1 e b h s` from anywhere in a network. Nothing tells a caller that a line is remote.
The terminal's shelf numbers its slots C1–C6 (`mf8-backplane.md` §3), so C4–C6
are lines *h*5–*h*7. Label the terminal's slots with their line numbers.

**Capacity.** A terminal is not a trunk group. Each line has a channel of its own
for good, so nothing is hunted across the link and nothing blocks. Blocks 2–7
give up to six terminals and 36 lines, and the twelve slots at *h*0 and *h*4 stay
local. A busy exchange at the centre of a network with trunk groups in
blocks 2 and 3 has four blocks left for terminals. **Not block 0**: its channel
slots are tones and the 04–07 bank. On a standalone exchange, block 1 can also
take a terminal (1 is a highway digit then); on a networked one, block 1 is the
first trunk group.

**Cost at the exchange.** The six port circuits are the ones six local cards
would need, and so are the block's shared parts. Added: the trunk card, whose
transmitter is ≈ 6 packages and receiver ≈ 10 (`mf8-spec.md` §10, §11), and the
crossing's two '174s. The six channel cards move to the terminal, together with
a ring generator for the shelf's `RING` bus if any of them is an FXS card.

---

## 3. What a channel says, a channel at a time

A tie trunk's six channels all send one word, trunk and its direction
(`network.md` §1). A terminal's channels need not be alike:

| at the terminal | its channel says | what the port does |
|---|---|---|
| CVSD subscriber line card, FXS card | a plain line: word line to ground, `/ANS` open | rings in cadence, gives ringback |
| data card | data line; `/ANS` low if `DSR` should follow `DTR` without the cadence | never connected to a voice port of this exchange |
| FXO card, exchange build (`features.md` §5) | outside line, `/ANS` low | 9 hunts it: an outside line at the terminal's site. A CO ringing in is routed as 0 |
| a phone on any station card | operator | a second position, hunted after 04 |
| a loopback test line (`extensions.md` §1) | line, `/ANS` low | a test of the link from any phone (§5) |
| a hotline card that dials (`extensions.md` §3.4) | a plain line | dials its number whenever its phone is lifted |
| a phone nailed to a port at the exchange (`extensions.md` §3.1) | a nail | a ringdown hotline to the exchange's site, holding nothing more than the terminal's own channel |

**The trunk card says, for each channel, what a card would say for its port**
(`extensions.md` §2.1): a word line and an `/ANS` line a channel. It is six
cards' worth of ports in one. The block already commutates each port's word
separately (`fabric.md` §3.1). On the trunk card a strap a channel takes the
word line to ground (a plain line), to the card's shared 74HC165 (one word,
jumpered), or to a '165 of the channel's own. A second strap sets `/ANS`. A tie
trunk straps all six to the shared word and ties every `/ANS` low. A terminal
straps each to what the card at the far end of that channel is: the cards at the
terminal cannot send their own, because MF8 carries only `C` and A. **Label both
ends, and keep the word and `/ANS` in step**: a channel strapped as a line with
an FXO card behind it would read every CO ring as a phone lifting, and send dial
tone down the CO line.

---

## 4. Clocking

A stock terminal runs from its own crystal (`mf8-backplane.md` §2), and the
exchange runs from its own. Wherever the two clocks meet, a channel slips one
bit at the offset between them. That is every 781 ms at 20 ppm, and every 390 ms
at 40 ppm, the worst case for two ±20 ppm crystals. Measured at 20 ppm: 34.8 dB
against the clean decode, with a transient that peaks 29 dB below speech and
settles in 1.3 ms (`mf8-backplane.md` §7). Where the clocks meet depends on the
card:

| card at the terminal | toward the phone | from the phone |
|---|---|---|
| CVSD subscriber line card | slips: the card samples `C_RX` on its own `TX_CLK` (`mf8-backplane.md` §2) | slips at the exchange's '174 |
| FXS card | none: its decoder runs on `RX_CLK` (`channel-cards.md` §3.2) | slips at the exchange's '174 |
| data card | none: the DTE takes `RX_CLK` (`channel-cards.md` §4) | slips at the exchange's '174 |

**For voice this is enough.** A slip is inaudible (`mf8-backplane.md` §7). A call
from a terminal across tie trunks adds the trunks' crossings to the terminal's,
as `network.md` §8 counts them. **For synchronous data and G.711 it is
not.** A slip is a lost or doubled bit, so both are ruled out across a
free-running terminal, as they are across MF8 trunks. Async oversampled data
passes.

**Loop-timing the terminal removes the slips.** The terminal's trunk card takes
its transmit clock from the clock it recovers from the link, so the whole shelf
runs in the exchange's clock. The upstream then arrives at the exchange at the
exchange's own rate, and the '174 never slips. `mf8-backplane.md` §2 chose
plesiochronous timing for MF8 because a slave exchange's phones would lose their
clock whenever the trunk failed. **That reason does not hold at a terminal.**
Without the link its phones can reach nothing, not even each other, since every
call is switched at the exchange. So a terminal is the natural slave, and loop
timing should be its default once the part exists. The part is a PLL on the
terminal's trunk card, locked to the receiver's transition strobes, because the
§9.4 receiver times intervals and has no clock to give (`mf8-backplane.md` §2).
It is not designed. Until it is, a terminal carries voice and async data, and
synchronous data stays inside the exchange.

---

## 5. Bringing it up

1. **The link alone**: two trunk cards back to back, as a point-to-point MF8
   link. Lock both ends, and `MUTE` releases.
2. **A loopback test line** (`extensions.md` §1) in a terminal slot, jumpered
   line at the exchange. Dial it and hear yourself. A data card counting slips
   through it reads the offset between the two crystals: the count a second,
   divided by two crossings and by 64 000.
3. **One phone.** Lift it and get dial tone from 01. Dial a local line, ring,
   answer, and release in both orders. Then break the link during a call: both
   ports release, and a call to the terminal's lines gets cannot-complete until
   the link locks again.

---

## 6. Not measured

- **Any of it as a whole.** No remote line is in the `calls` model. What exists:
  `exch.py fabric` 7 passed an MF8 frame through a block bit for bit, in one
  clock and with no crossing; `channel-cards.md` §5 measured the A path; and
  `mf8-backplane.md` §7 measured one slip.
- **The exchange's receive crossing, and the trunk card's clock strap**: as for
  tie trunks (`network.md` §10).
- **The per-channel word and `/ANS` straps** of §3, drawn.
- **The loop-timed terminal**: the PLL itself. Also whether, with the terminal
  locked to the exchange, a channel's '259 write can sit on the exchange's frame
  edge and flip between two frames with the PLL's jitter.
