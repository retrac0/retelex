# The exchange — extensions: test lines, what a card says about its port, nailed-up connections and hotlines, traffic counters

Additions to the exchange. Each is a card, or a few jumpers on one. None
changes the fabric, and none needs a memory part. Test lines are features that
are lines, in the manner of `features.md`. **Whatever sits behind a port
says everything about it** (§2): one pin says whether it rings, and one serial
word says its class, its options, a trunk's direction and what it is nailed to.
A hotline to another exchange is a card that dials. The traffic counters count
what the marker already does.

> **Status: proposed.** None of it is in the `calls` model, no circuit has been
> drawn, and nothing has been on a bench. Every figure here comes from another
> document's run, as cited. The word and the hotline card's dialler are
> sketched by function. The sources below use the *source* class that
> `fabric.md` §3.5 proposes. Under the marker as it stands, class 5 or 6
> does the same (`features.md` §6).

---

## 1. Test lines

Three cards a tester can dial. Each is reached like any line: `h s` on its own
exchange, and `1 e b h s` from anywhere in the network, so **every exchange and
every trunk can be tested from any phone**. Fitting them in the same three slots
at every exchange, say 75–77, lets a tester remember them. That is a suggestion,
not a rule.

| | the card | class | what it tests |
|---|---|---|---|
| **Milliwatt** | 1004 Hz at the codec's 0 dBm0 reference, into one encoder half, as a tone card (`features.md` §2). `A_TX` tied low | source | the listener's decoder, and its analog path, for level |
| **Quiet termination** | a card carrying only its word (§2.2). Its `C_TX` is pulled to `FILL` as an empty slot's is, and its `A_TX` to 0 | source | the listener's idle noise: `FILL` decodes at −48.3 dB re nominal speech (`protocol.md` §4) |
| **Loopback** | one 74HC74 clocked on `TX_CLK`: `C_TX` ← `C_RX`, `A_TX` ← `A_RX` | line | a caller hears their own voice; a data card gets its own bits back |

**Why a milliwatt means more here than in a voice-band exchange.** Bits are
switched, so the tone reaches every listener bit for bit, however many
exchanges and trunks it crosses. What is read at a phone is that phone's card,
its decoder and its analog path, and nothing between. On a path that crosses
MF8 a slip is a −29 dB tick lasting about a millisecond (`mf8-backplane.md` §7).
It is not a level error.
The tone is 1004 Hz, as in PCM practice, so that it is not a submultiple of the
bit rate. It can also be a looping ROM image, as the announcement card plays
one (`features.md` §3): 251 cycles of 1004 Hz are exactly 16 000 bits,
0.25 s, 2 000 bytes. That image's seam has not been measured.

**The loopback re-times, as every card does.** A card holds `C_TX` for the whole
frame and samples `C_RX` at the frame edge (`fabric.md` §3.4). A bare wire
from `C_RX` to `C_TX` would change mid-frame and give a delay that depends on the
slot order. The flip-flop gives two frames, 31.25 µs, whatever the slots: one
frame there and one frame back.

- **For a voice caller** it is an echo test of the whole path. The voice comes
  back as sidetone.
- **For a data card** it is a bit-error test. Inside one exchange, or over copper
  ties, the loop is bit-exact.
- **Across MF8** every crossing slips at the offset between the two exchanges'
  clocks, which is one slip a crossing every 781 ms at 20 ppm. A tester counting
  slips through a loopback at another exchange is therefore measuring that
  offset: the count a second, divided by two crossings and by 64 000, is the
  offset between the two crystals.

The loopback copies `A_RX` to `A_TX`, as a conference bridge leg does, so it answers
when rung and releases when its caller does. As a line, it waits for the first
burst of the ring cadence, up to 4 s. §2.3 removes the wait. The two sources are
never rung and never answer: a caller hears them at once, any number may listen,
and the caller leaves by hanging up.

---

## 2. What a card says about its port

**Whatever sits behind a port says everything the exchange needs to know about
it, in two places.** One pin, `/ANS`, says the one thing the port's own gates
need at every instant: whether the port rings. One serial word says the rest,
and only the marker reads it: what the port is, its options, which way it goes
if it is a trunk, and what it is nailed to if it is nailed. The block keeps no
per-port settings, so **move a card and all of it moves with the card.**

> **Proposed, not applied here** (`groups.md`): the word's unused quarter,
> bit 0 and bit 7 both set, becomes *a plain line that answers to `h s`*, and a
> call that cannot be completed at the number dialled hunts for a port that
> answers to it. That replaces §2.4's run of adjacent `o` ports and class
> *operator*. Pin `a14` stays spare; a secondary word is retired.

### 2.1 The pins

The MF8 backplane reserved three pins of the channel slot's row *a* and connects
none of them (`mf8-backplane.md` §8). The exchange uses two:

| pin | on the MF8 shelf | in the exchange | at the port | on the card |
|---|---|---|---|---|
| a12 | `TYPE0`: reserved | **the word** (§2.2) | a pull-up: open reads "no word" | tied to ground on a plain line card; otherwise an open-drain output, ¼ 74HC03 |
| a13 | `TYPE1`: reserved | **`/ANS`** (§2.3) | a pull-up: open reads "rings" | tied to ground on a card that never rings |
| a14 | `RAI`: reserved | spare | | |

A card only ever pulls the two pins to ground, and the MF8 shelf leaves them
unconnected, so a card built for the exchange works unchanged in an MF8 shelf.
Row *c* keeps all seven of its grounds.

- **A card** says it for its one port.
- **A trunk card** says it for each of its six channels: a word line and an
  `/ANS` line a channel (`network.md` §1, `terminal.md` §3). An MF8
  trunk card on a tie trunk sends one word to all six from one 74HC165, since its
  link goes one way, and ties all six `/ANS` lines low. A trunk card is six
  cards' worth of ports in one. **A single-channel trunk card is one port's
  worth**, and sits in any slot (`network.md` §1.1).
- **An empty slot** says nothing: unequipped, and nothing points at it.

### 2.2 The word

One 8-bit word a port, one bit a frame, every octet. The scanner rests on each
port for one octet, 125 µs, so the marker has the whole word at the end of every
visit (`marker.md` §4). The pin is low for a 1.

```
 frame of the octet    0    1  2  3    4  5  6  7
 what the port is      0    c  c  c    p  p  p  p     its class, and four options that depend on the class
 a nail                1    h  h  h    s  s  s  0     the port this one is nailed to (§3.1)
 a plain line          1    1  1  1    1  1  1  1     the pin tied to ground: class line, no options
 nothing               0    0  0  0    0  0  0  0     an empty slot; a card out of service; a trunk whose link is down
```

| class `c c c` | | options `p p p p` (frames 4–7) |
|---|---|---|
| 000 | unequipped | |
| 001 | line | `o w b ·` — overflow, warm, busy-out, spare (§2.4) |
| 010 | operator | `o · · ·` — overflow in the same bit as a line |
| 011 | source: a radio, a clock, a test tone (`features.md` §6) | |
| 100 | outside line | |
| 101 | tie trunk | `d d g n`: its direction, N 00, E 01, S 10, W 11; the glare bit; and `n`, which keeps a flood from being forwarded into this link or out of it, so that a ring does not circle (`network.md` §1, §3.3) |
| 110 | data line | `o · · ·` — overflow in the same bit as a line |
| 111 | restricted | `z w b L` — 0-only, reserved (warm), busy-inbound, local-only (§2.4). Was *conference leg* |

**Bit order is shared where the marker's test is the same.** Frame 4 is overflow
on every class that hunts (`line`, `operator`, `data`). Frame 5 is warm on a
line, and **reserved** on restricted (same place, for warm later). Frame 6 is
busy-out / busy-inbound — one terminating not-free test. Restricted's dialling
bits take the two slots that do not overlap: `z` in frame 4, `L` in frame 7.
A trunk's `d d g n` does not share meaning with these and keeps its own map.

- **A plain line card carries no part and no jumper for this.** Its word pin is
  tied to ground, which reads all ones, and that means a line with no options.
  Plain lines are most of an exchange. Only a card with something more to say
  carries the word's parts.
- **The word's parts**: a 74HC165 loaded from jumpers on `TX_OCT` and shifted on
  `TX_CLK`, into ¼ 74HC03: **≈ 1¼ packages**. A line card has the footprint, and
  it is fitted when the card is to be an operator's position, restricted (class
  111), in a hunt group, a warm line, busy-out / busy-inbound, or nailed.
- **Held off at power-up.** The '03's second input is an RC of about 100 ms. A
  card just plugged in sends nothing until its '165 is loading properly. Without
  this a random byte reads as a nail one time in four. A trunk card also gates
  that input with "link up", so a dead link sends nothing and is never hunted.
- **A nailed port sends no class.** It is never hunted, dialled or a call
  request (§3.1), so the marker never needs one. Whether it rings is `/ANS`.
- **Out of service** is no word at all: a switch in the '03's enable, or the
  ground link opened on a plain card. The port reads unequipped. A call to it
  gets cannot-complete and its lifting is ignored. On a trunk card, a switch a
  channel takes one channel out of the hunt.
- **The tone cards at 01–03 need no word.** The marker reaches them by
  address and never reads their class (`fabric.md` §3.5).
- **The block**: a fourth '151 commutates the eight word pins onto the probe bus
  beside `BUSY` (`fabric.md` §2, §3.1). **The marker**: a 74HC164 takes the
  word in, a 74HC30 finds all ones, and a few gates sort the rest: bit 0 = 0 is
  a class and its options; bit 0 = 1 with bit 7 = 0 is a nail; all ones is a
  plain line; anything else is no word.
- **What is given up.** A word pin shorted to ground reads as a free line, where
  a shorted class pin would have read as some other class. And a class takes a
  whole visit to read: no cost in the scan, and up to 250 µs when the marker
  probes a dialled port out of turn, waiting for the octet edge.

### 2.3 Ringing, and lines that answer at once

A port that rings gives its card E only in the ring cadence, and sends the
caller ringback meanwhile (`fabric.md` §3.5):

```
 ON   = /ANS is open  ·  /M  ·  /fM       an on-hook port that rings, and did not hang up a moment ago
 A_RX = E · /( ON · /RING_CAD )           E in the cadence while ON; otherwise E as it stands
 RB   = ON · E                            ringback in place of the card's voice while it is being rung
```

**`/ANS` is the whole of it.** The class does not enter into it, because ringing
is how a port is supervised and not what it is. A phone's card leaves the pin
open. Every card that must not be rung in cadence ties it low:

| card | why |
|---|---|
| tie trunk, outside line, conference bridge leg | a trunk that rang would give its caller ringback the instant it was seized, and chop forward A in the cadence. These cards tie it low on the board |
| the loopback test line (§1), a paging amplifier, a relay port | to answer, or act, at once and not 0–4 s later at the first ring burst |
| the announcement at the end of the operator hunt | class operator, so that 0 finds it, and still it must answer at once |
| a data card, if its `DSR` should follow `DTR` without the cadence | `DSR` at once |

With the pin low, `A_RX` is E, steady from the frame after the latch is written,
and the caller hears the card, or silence until it answers.

**Never on a phone's card.** An on-hook phone given a steady E rings
continuously, not in cadence, and its caller hears no ringback. **The class and
the pin must agree** on a card that is not a line. A purpose-built card has both
on the board. Only a subscriber terminal's channels set them by jumper
(`terminal.md` §3).

### 2.4 Options of a line, and class *restricted*

The option bits are read only by the marker. None needs a part anywhere but the
card's word and a term in a test the marker already makes. Shared bits keep the
same frame on every class that uses them (§2.2).

#### Line (`001`), and overflow wherever it sits

| frame | bit | | the marker |
|---|---|---|---|
| 4 | `o` | **overflow**: a hunt group | a dialled port that is not free, and whose `o` is set, passes the call to the next port, and so on until a port is free or a port that is not free has `o` clear: then cannot-complete. **A hunt group is a run of adjacent ports with `o` set on all but the last, and its number is its first port's.** A sales desk, a pool of data ports, a conference bridge (`conference.md` §6). Slot order is priority, and an announcement card can sit last. Two groups may sit side by side. A member has no number of its own that does not overflow. Same bit on class *operator* and *data line* |
| 5 | `w` | **warm line**: a courtesy phone, a lift's phone, a help point | its lifting is routed as if it had dialled 0, with no register, as a CO line ringing in is (`marker.md` §3). It can still be dialled by its number. Against a nail (§3.1): a nail rings one fixed phone and holds two latches for good; a warm line rings whichever operator's position is free, and holds nothing while idle |
| 6 | `b` | **busy-out** (DND as busy) | on a **terminating** call, the port is **not free** — same path as `BUSY` set: the caller hears **busy** tone, and an `o` hunt walks on. **Lifting still gets a register and dial tone**; outbound is unchanged. Against out of service (§2.2): OOS is unequipped both ways (lift ignored). Against a latch make-busy (`console.md` §4): this mark is in the word and survives hang-up. Same bit and test as restricted *busy-inbound* |
| 7 | `·` | **spare** | one bit free on class line |

**Why busy, not cannot-complete.** Cannot-complete (fast busy / reorder) means the
number cannot be completed — empty slot, wrong digit, restricted dialling.
Busy-out means “this phone is not taking calls,” which is what a busy line
already says, and it is what a hunt group needs so a member can leave the group
without ending the run. Distinctive DND tone would be a second source and a
second marker steer; not worth it.

#### Restricted (`111`)

Class *restricted* is a lobby phone or a public phone: the same free test and
ringing as a line. The class itself is unsafe to miss — a jumper the user cannot
clear — so dialling limits live in the options, not in clearing the class.
Conference bridge legs remain class *line* with `/ANS` low (`conference.md`
§6).

| frame | bit | | the marker |
|---|---|---|---|
| 4 | `z` | **0-only** | only digit **0** completes (hunt operator). Any other first key → cannot-complete. Wins over `L` if both are set |
| 5 | `w` | **reserved** | same frame as a line's warm bit; held for warm (lift → 0) later. Clear for now |
| 6 | `b` | **busy-inbound** | same terminating not-free / busy path as a line's busy-out. Lift and outbound unchanged |
| 7 | `L` | **local-only** | **9** and (networked) **1** → cannot-complete; no flood. Own-exchange lines and operator only |

**Floor.** If `z` and `L` are both clear, the marker still treats the caller as
**local-only** — a bare restricted card never opens a flood. Campus-only and
CO-ok / no-flood profiles are not used.

A data line (class 110) is a line the marker will not connect to a voice port,
and the reverse: the mismatch `channel-cards.md` §1 warns is "loud, locked, not
squelched". The check is made where both classes can be read, which is inside
one exchange. A call from another exchange arrives on a trunk.

---

## 3. Nailed-up connections and hotlines

A connection that stays when both ends hang up: a ringdown hotline between two
phones, a private wire, a permanent data circuit. Two ports facing each other
are already a hotline (`channel-cards.md` §1), where either lifting rings the other
and both lifted is a call. What the exchange lacks is a way to keep the pair
after release, because the release clears both latches. A nailed-up
connection is `mvp.md` §6's bring-up step 3 made permanent, and brought up
by the scanner from jumpers on the two cards.

### 3.1 The nail word

Each card that may be nailed holds its partner's port number in jumpers, and
sends it as its word (§2.2) in place of its class:

```
 frame of the octet    0     1–3    4–6    7
 a nail                1     h      s      0
```

| | |
|---|---|
| **The card** | the word's parts (§2.2), with the partner's port in the jumpers. A plain line card to be nailed has them fitted, and its ground link opened |
| **The marker** | **a nail** is bit 0 = 1 and bit 7 = 0. An empty slot reads all zeros and a plain line all ones, and neither is a nail |
| **The rule** | checked at each port before any other: **a nail and `BUSY` clear → write this port's latch to the nail's port, with `BUSY` set.** A port with a nail is never free. It is never hunted, never connected by a dialled number, and its lifting is never a call request or a seizure |
| **Release** | nothing stops it. When a nailed pair's call ends, the release detectors clear both latches as on any call (`marker.md` §5), and within one scan, 8 ms, the scanner writes both back. The port circuit is unchanged |
| **After `/RESET`, or a card plugged in** | the first scan writes every nail, within 8 ms. The cards are the only record of the nails, and nothing else is needed |
| **Both ends** | each card names the other, and each port is written from its own card. A card naming a port whose card does not name it back is a one-way nail. That is right for a listener on a source, a speaker on a radio say (`features.md` §6). For a phone it is dead: it lifts and nothing rings |
| **The console** | can still point two latches at each other by hand, as bring-up step 3 does — one key, two crossed words in one tenure (`console.md` §1, §6). **It rings nothing**: with both phones on hook the pair is held by nothing, so an operator rings each end from a source first and pairs them once both have answered. It is a call, and it clears when it is released; nothing remembers it, which is the whole difference from a nail |
| **Counters** | a nail's writes are not calls (§4) |

The nail word replaces a nail card that wrote nails from a diode matrix: a '161,
a '138 and up to 88 diodes for four connections at most. There is no limit on
the number of nails, and changing one is two cards' jumpers.

### 3.2 Ringdown

A nailed pair of phones is a ringdown hotline. Nothing in it is new: it is the
hotline rule of `channel-cards.md` §1 under the exchange's supervision
(`fabric.md` §3.5):

```
 A lifts          A's M reaches B's port as E.  B is on-hook, so B's port rings it in the cadence and sends RBT
                  to A in place of B's voice.  The first burst comes 0–4 s after the lift: RING_CAD is shared
                  and free-running
 B answers        B's M rises: ringing and RBT stop.  A's E is B's M, and they talk
 both hang up     the release detectors clear both latches 256 ms after the first; the scanner re-nails both
                  within 8 ms
 one stays off-hook   it rings the other, and hears ringback, until the other answers or it hangs up:
                  either phone off-hook rings the other
```

**A data circuit** is two data cards nailed together, with `/ANS` on both so
that `DSR` follows `DTR` without the cadence. It is bit-exact inside one
exchange and over copper ties. Across MF8 it is async oversampled data only
(`network.md` §8), except to a loop-timed subscriber terminal
(`terminal.md` §4).

### 3.3 Across the network: nailed hop by hop

A nail word names a port of its own exchange, because a latch can name nothing
else (`protocol.md` §3). A channel held end to end across exchanges is
nailed at every exchange on the way, each exchange nailing its own pair:

```
 exchange 22      phone A ↔ trunk channel toward 23            A's card and the channel's word name each other
 exchange 23      channel from 22 ↔ channel toward 24          the two channels' words, on two trunk cards
 exchange 24      channel from 23 ↔ phone B                    the channel's word and B's card
```

- **Ringdown works both ways, as in §3.2.** Forward A is A's hook and backward A
  is B's. No claim is involved, so each end sees the other answer. Trunk ports
  never ring and never send ringback, because their classes do not; ringback
  comes in band from B's port.
- **The flood never touches a nailed channel.** It sends a nail and not a class,
  so it is never hunted, its M rising is never a seizure, and no monitor attends
  it (`monitor.md` §4).
- **The cost is a channel on every link crossed, for good.** A direction's six
  channels become five, and its capacity at 1 % blocking falls from 1.91 E to
  1.36 E (`exch.py ss0` 4). And the path is in jumpers at every exchange: a
  fixed route, which the network otherwise never has. Use it where a channel
  must be held end to end, such as a permanent data circuit.
- **Through a subscriber terminal it costs nothing extra.** Each terminal line
  has its own channel (`terminal.md` §2).

### 3.4 Ringdown to another exchange: a card that dials

A nail cannot be named by an exchange's code and a line. A path the flood sets up lives
only while forward A is high, and every patch clears itself on the fall
(`network.md` §3). No transit keeps anything that would tell it a patch was
meant to stay. And backward A across the network is the claim, not the far
phone's hook, so the far phone could not ring the near one over such a path.

So a hotline to another exchange holds no path. **It dials, every time its phone
is lifted.** The card is a station card, FXS or CVSD line card, with a dialler
fitted and the number in jumpers. To the exchange it is a caller like any other,
whose pulses the flood carries live: no change to the exchange, and no sender.

| | |
|---|---|
| **The number** | `1 e b h s`, or `h s` for a line of the card's own exchange. Four jumpers a digit hold its pulse count, ten for 0 |
| **Waiting for the register** | the card must not dial before a register is attached, or the register counts from the middle. The marker points a caller at dial tone when it hands it a register (`marker.md` §3), so the card waits for `C_RX` to leave the idle pattern: `C_RX` against `FILL`, one XOR and a counter. With no dial-tone card fitted, a hotline cannot dial |
| **Dialling** | breaks on its own `A_TX` while the phone stays off-hook: 10 pps, 60/40, 0.7 s between digits, all from `TX_OCT`. These are the windows the register, the flood and the monitors were measured at: the flood is ready 258 ms after the first digit, and the monitors' rules held at 10 pps ± 10 % (`network.md` §4, `monitor.md` §5). The phone hanging up stops it |
| **Then** | an ordinary call. The flood opens on `1`, the owner claims on `e b`, the far phone rings, and ringback comes in band. Answer across the network is seen at claim (`network.md` §3) |
| **Time** | 0.8–3.2 s of pulses and 2.8 s of pauses for five digits: **about 4–6 s from dial tone to the far port being rung**, then the cadence's own 0–4 s to the first ring |
| **Both ways** | a dialling card at each end, each naming the other. Both lifting at once find each other busy and get cannot-complete |
| **Held while idle** | nothing: no channel, no latch, no register |
| **Parts** | the 10 ms step from `TX_OCT` ('4040 and a gate); the 100 ms pulse and its 60 % break ('4017 and a NOR); the pulse count ('193, loaded through 2 × '153 from the jumpers of `e b h s`; the key `1` is wired, as the count the digit pointer's first state loads, and a jumper skips it for a local number); the digit pointer and the pause ('393); the idle-pattern detector and control ('86, '74): **≈ 8 packages**, fitted only on a hotline card |

A phone that dials a stored number when it is lifted does the same with no card
at all. The number may also be `h s` of the card's own exchange: a hotline that
holds nothing while idle, where a nail rings faster and holds two latches.

### 3.5 Which to use

| | nail (§3.1) | nailed hop by hop (§3.3) | a card that dials (§3.4) |
|---|---|---|---|
| reaches | its own exchange | another exchange, by a fixed path | anywhere in the network |
| named by | the partner's port, on each card | a port at each exchange, on each card and trunk card | the number, on one card |
| the far end rings | at the lift | at the lift | 4–6 s after dial tone |
| the far end lifting rings the near end | yes | yes | only with a dialling card there too |
| answer seen | yes | yes | at claim |
| holds while idle | two latches | a channel on every link crossed | nothing |
| parts | ≈ 1¼ a card | ≈ 1¼ a card or channel, at every exchange on the path | ≈ 8 a card |

The first ring burst waits for the shared cadence in every column: up to 4 s
more.

---

## 4. Traffic counters

The register table of `marker.md` §6 and the link loads of
`network.md` §5 assume a calling rate. Counters check those tables on a
working exchange, and say when to add a register or double a direction.
Exchanges have always kept two kinds.

**Peg counts: how often.** Each is a pulse from a state the marker's sequencer
already reaches:

| counter | pulses when | answers |
|---|---|---|
| calls connected | the second latch write of a call. A nail's writes are not counted | the calling rate |
| cannot-complete given | a caller's latch is written to cannot-complete | wrong numbers, busy lines, empty slots |
| waited for a register | a call request found no register free | whether §6's register count holds |
| all trunks busy, one a direction | a hunt for a free trunk facing that way found none | a link's blocking, against `network.md` §5 |

**Usage: how much, in erlangs, by switch count.** On each rising edge of
`RING_CAD`, once every 6 s and at no extra cost, one full pass of the scanner is
enabled, 8 ms long. During it, a counter counts the ports of one class that read
`BUSY` on the probe. The count × 6 s ÷ the period is the class's traffic: **one
erlang for an hour is 600 counts.** It is kept for the trunks facing each direction
(the class and the direction, both in the word) and for all lines. A nailed
channel sends no class, so it is not counted: it has left its group. Sampling every 6 s sees a 100 s call about 16
times. The Bell System sampled every 100 s, which is where its unit, the CCS or
hundred call-seconds, comes from.

| | parts |
|---|---|
| a counter | a 74HC4040, 12 bits, driving 12 LEDs. At 48 lines and 0.08 E a line, all lines count 2 304 an hour, so read and reset at the end of the busy hour or cascade two |
| the usage gate | a flip-flop set on the `RING_CAD` edge and cleared at the scanner's wrap, ANDed with the class decode and `BUSY` on the probe |
| | **≈ 1 package a counter, ≈ 2–3 shared**: the eight counters above are about ten packages on one card beside the marker. A reset key on the console |

---

## 5. Together

| | parts | where |
|---|---|---|
| test lines | a tone card; a card with only its word; a 74HC74 | line slots |
| the word and `/ANS` | nothing on a plain line card; ≈ 1¼ on any other; two pull-ups a port; ≈ 3 at the marker | the cards, the block, the marker |
| lines that answer at once | `/ANS` tied low on the card | the card |
| restricted lines, hunt groups, warm lines, busy-out | class *restricted* with `z w b L`; line `o w b ·`; shared frames for `o`/`w`/`b` | the cards, the marker |
| nailed-up connections | the card's word | the cards |
| nailed hop by hop | a word of its own on each trunk card channel that may be nailed | trunk cards |
| hotlines to another exchange | ≈ 8 on each hotline card | the card |
| traffic counters | ≈ 10 | a counter card beside the marker |

A standalone exchange can take all of it except §3.3 and §3.4, which are for a
network.

---

## 6. Not measured

- **All of it in the `calls` model.** The loopback and the answer-at-once port
  behave like the conference bridge leg the model already has (`A_TX` = `A_RX`,
  no special class, and `/ANS` low so that it does not ring). A nailed pair is
  bring-up step 3, which the model does not run as a scenario, and the scanner's
  nail rule is not in it.
- **The milliwatt's level** through the encoder half, and its ROM image's seam.
- **The word as gates**: the '165's load against `TX_OCT`, the probe's capture
  in the scanned port's cell, the all-ones detector, the power-up hold-off, and
  a plain card's ground link against a fault that reads the same.
- **`/ANS` alone forming `ON`**, drawn.
- **The line options in the marker**: restricted `z` / `L` (0-only; local-only,
  with local floor if both clear), overflow hunt on shared frame 4, a warm
  line's lift against the call-request rule, and busy `b` on shared frame 6
  (terminating not-free / busy; outbound still a call request). Restricted
  frame 5 reserved for warm.
- **The nail rule**: its place ahead of the call-request rule, and the 8 ms after
  a release in which a nailed port is idle.
- **A nail now needs the scanner after every release.** With the marker stopped,
  a nailed pair works until its first release and not after. If a nail must
  survive that, the release can be held off as well: a '259 a block, latching
  each port's word bit 0 into its release gate. Not adopted.
- **The dialling card**: its idle-pattern detector against a real dial tone, the
  dialler's timing against the register and the monitors, and a caller lifting
  while every register is busy.
- **The usage gate** against the marker's own use of the probe during a hunt, and
  whether one pass every 6 s reads the tables closely enough at real holding
  times.
