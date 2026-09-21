# The exchange — tie trunks and the network

An exchange is one 8 × 8 fabric of 64 ports: 48 lines, an operator, and **an MF8 group of eight
tie trunks on block 1** — further groups at the busy centre of a network (`protocol.md`
§5). A network is such exchanges joined by those trunks — a handful on a chain,
a score around a hub, sixty-four codes in all — in which a line on another
exchange is dialled directly with `1` and its four-digit number. This document is how: nobody routes, nobody sends; the call is
**flooded, heard, and dropped in by its owner**. A standalone exchange carries
none of it.

> **Status: analysis.** Decided: **all pulse; the flood carries the caller's own dial
> pulses, live; no sender.** The monitor's two rules are measured
> (`monitor.md`). The timing in §3.1 and §4 is `exch.py flood` — arithmetic
> from measured constants, **not a simulation of the gates** — and §5's link
> loads are Erlang arithmetic. **`exch.py net` runs a network of eight exchanges
> call by call** in milliseconds — the flood, the monitors, the claim, the
> resolvers, the registers and the channels — and §5.1 is its run. It models the
> timing and the pools, not the gates.

---

## 1. Tie trunks

A port's latch points only at one of the 64 ports of its own exchange, so a call
to another exchange crosses a **tie trunk: a pair of ports, one in each exchange,
back to back**, with no channel card behind either.

```
 exchange 22                                                exchange 23
 line 47 ── listens to ─▶ T                            T′ ◀─ listens to ── line 25
 T ─────── listens to ─▶ line 47                       T′ ── listens to ─▶ line 25

            T's C_RX, A_RX ──────────────────────────▶ T′'s C_TX, A_TX
            T's C_TX, A_TX ◀────────────────────────── T′'s C_RX, A_RX
```

What T hears from its fabric, T′ says into its own, and the reverse — `C` and `A`
both. To line 25, port T′ *is* the caller: its slot carries their voice and its A
is their hook, so 25 rings by the hotline rule and the release rule runs through
the pair untouched. To each fabric a trunk port is a port like any other: class
trunk, a `BUSY` bit, its own release detectors. It holds no digits and decides
nothing.

| | |
|---|---|
| Ports | **10–17** first: one MF8 link on block 1, eight channels. The exchange unit occupies the block and takes its highway (`mf8-unit.md` §5). Slot *n* is channel C*n* of the line after conversion, not a bit position on the wire (`protocol.md` §5). **Further groups in blocks 2+** (20–27, …) at the cost of those lines. **Block 0 is never an MF8 trunk group** — 01–03 are tones, 04–07 the operator bank; 06–07 may take single-channel trunks (`network.md` §1.1). On a standalone exchange, 1 is a highway digit and there is no trunk block |
| Directions | an exchange faces **up to four directions, N, S, E and W, and a direction is not a class.** Every trunk port is class trunk, and **says so, and which way its link goes, in its word** (`extensions.md` §2.2). An MF8 unit on a tie trunk sends one word to its eight channels, from one 74HC165, and ties their `/ANS` lines low so that none rings (a subscriber terminal sets each channel apart, `terminal.md` §3). A single-channel card sends its own (§1.1). One group or two in a direction — eight channels, or sixteen, or nine with a single-channel card beside an MF8 one — makes no difference to anything but the words: the hunt is for a free trunk facing that way, in fixed order. A trunk card sends its word only while its link is up, so a trunk whose link is down reads unequipped and is never hunted |
| The link | an MF8 pair each way — or, between exchanges in one rack, copper: a tie card at each end crosses the ports over and gives them their class and words; same clock, bit-exact, one frame more delay (`protocol.md` §4). Or any other carrier that does what §1.1 asks |
| The far end | another exchange's trunk block makes the link a tie trunk. A stock MF8 shelf of channel cards makes the same link, from the same unit, eight lines of this exchange (`terminal.md`) |
| Transmit | payload in the exchange's clock (`TX_CLK` / `TX_OCT` on C). The line mux is the unit's own 4.096 MHz, tap Q1, `HB` 2.048 MHz — not `SLOT`, not fabric `HB` (`mf8-unit.md` §5.5) |
| Receive | each link is its own clock domain. The crossing of `mf8-backplane.md` §2 moves here: two '174s for the eight `C`, the §14 RC and Schmitt gate for `A` |
| Trunk down | `MUTE` clears the A hold, every M falls, calls release themselves. **`MUTE_BLK` forces the block's `BUSY` highway to 1**, or a dead trunk hunts as free. The unit also stops sending its words, which keeps a dead trunk from being hunted on any carrier (§1.1); `BUSY` is what keeps callers off a subscriber terminal's dead lines (`terminal.md` §2) |
| Guard | `marker.md` §5.2's settle term already holds a released trunk busy for ~0.6 s |
| Glare | the two ends of a link hunt it in opposite order: the word's `g` bit, set at one end, has the marker take the last free trunk facing that way and not the first. Residual glare joins two callers to each other |

Two directions make an exchange a node in **a chain or a ring**; a pair of
exchanges may point both directions at each other. Doubling a direction is for
the middle of a chain, where everyone's traffic crosses (§5). **Three or four
directions make an exchange a hub**: a star, or a tree of chains and stars
(§3.2).

### 1.1 Trunks that are not MF8

A trunk is any port of class trunk that sends a direction word. The exchange
cares about what is behind it in a handful of ways only — and **not about how long
it is**, which is the one most carriers fail on and this one does not (§5.1 of
`monitor.md`):

| | what the carrier must do |
|---|---|
| **A** | carry a level each way, and dial pulses with it: a monitor or a register must still see every break of 8 ms or more (`register.md` §2). The A path may **shorten** a break — MF8's own costs 0.5 ms a hop, and the line card's hook detector 6.1 ms once, so a 60 ms break is 50 ms after seven hops (§4) — and must not lengthen a make past the 128 ms that ends a digit, or a break past the 256 ms that is a hang-up |
| **A's delay** | **anything.** A constant one-way delay costs the flood's guard *nothing*, because the seizure and the caller's pulses are the same wire and arrive equally late: measured to 160 ms a hop and 1.17 s across seven, 0 false claims (`monitor.md` §5.1). What the guard counts is the marker's own 3–10 ms a hop, and **delay the carrier loses between the seizure and the next digit**, which costs a millisecond of guard for a millisecond of wander |
| **A's wander** | **under 12 ms a hop** on the guard's 128 ms tap, or strap the next one: 256 ms buys 30 ms a hop and 512 ms buys 67, and 512 is the last tap a telephone to ES 201 187 will never be abandoned by (`monitor.md` §3.5, measured §5.1) |
| **C** | carry 64 kbps each way bit for bit, crossed into the exchange's clock on the card as MF8's trunk card does. Or carry voice band, with a codec pair on the card: a tandem of about 2 dB, and no data (`protocol.md` §2) |
| **Round trip, signalling** | **under 0.9 s** over the whole path, whatever the hop count: the origin gives up 2 s after `b` and the claim has to cross the network and come back inside that (§4). Nothing a terrestrial carrier does comes near it |
| **Round trip, ECHO** | **20–30 ms, and this is the one that binds.** `channel-cards.md` §3.3 says echo needs no treatment because the round trip is "under 0.1 ms plus 5 µs per km", and there is **no canceller and no suppressor** anywhere in the design. That holds for a CVSD subscriber at both ends, which is four-wire and has no hybrid to echo off (`subscriber-line.md`); it does **not** hold the moment either end is an **analog FXS or FXO card**, whose 600 Ω hybrid returns 10–15 dB. **One 15 ms hop is already 30 ms of round trip.** A carrier of tens of milliseconds is for a network of CVSD sets, or it needs a canceller the design does not have |
| **One way, conversation** | with no hybrid at either end the limit is G.114's, **150 ms one way** for transparency and 400 ms to be usable at all. Three 40 ms hops are transparent; ten are not |
| **Glare** | the window in which both ends may seize one channel unseen is the carrier's delay plus the marker's own, so a 40 ms carrier makes glare about six times as likely as a pair does. The word's `g` bit still needs seven of eight channels busy before it can happen at all (§1) |
| **Link down** | stop sending its word, so that its port reads unequipped and is never hunted, and let A fall, so that a call in progress releases |
| **The word** | class trunk, its direction and its glare bit (`extensions.md` §2.2), and `/ANS` tied low |

So a direction may be carried by an MF8 unit's eight channels, the usual case; by
a copper tie card between exchanges in one room (`baseband.md`); by a
single-channel card, one trunk over a pair or two, for example two CVSD line
interfaces back to back (`subscriber-line.md`), not designed; or by a
voice-band card on a leased circuit or a radio — the E&M card of
`mf8-spec.md` §12.1 on four-wire, or **`pots-trunk.md` on a dry two-wire pair
with A as a dual tone each way**. Any mix of them may face one way.

**One channel carries little.** At 1 % blocking one channel carries 0.01 E, two
carry 0.15 E and eight 3.13 E, and every call in the network floods every link for
1.2–1.7 s (§4). A direction of one channel suits a few lines at the far end of a
network, or tops up a direction. It is not a route for an exchange's traffic.

---

## 2. Numbers

**A line is dialled `h s` from its own exchange, and `1 e b h s` from anywhere.**
Nothing is strapped for it: an exchange with no network card gives
cannot-complete for `1`, and otherwise parses the same digits.

```
 local         4 7           line 47 of this exchange.  No trunk is touched
 network       1 2 3 4 7     exchange 23's line 47: the same digits from anywhere, 23 included
               1 2 3 0       exchange 23's operator            1 2 3 9   its outside line
 reserved      1 8 …, 1 9 …             out of the network (§6)
```

- **`1` is the network's key, and it is the digit the flood consumes** (§3). It
  says only "this call leaves", which the origin alone needs to know, so nothing
  is lost with it. It is one pulse: the shortest digit there is.
- **`e b` is the exchange's code, both digits 0–7**: 00–77, octal as a line's
  number is, sixty-four of them. It is never an address, only compared with
  jumpers, which say **who an exchange is and never where anything is**. Both
  digits go down the flood live, and a monitor claims a call only when both are
  its own.
- **By convention 00–17 are the backbone's**: tandems and hubs, the exchanges that
  are mostly trunks. Ordinary exchanges take 20–77. A network's codes then read
  as an exchange's ports do, where 00–07 are services, 10–17 the first trunk
  group when networked, and 20–77 are
  lines (`protocol.md` §5), and a planner sees which codes are which. Nothing
  enforces it: all sixty-four are assignable.
- **8 and 9 stay special in both places of the code.** `1` followed by either, or
  `1 e` followed by either, is reserved, and cannot-complete today. After the key
  a 0 or a 1 is only a digit: the operator and the key are first keys.
- **A local call never floods**, and its number is the same whether the exchange
  stands alone or not. Joining a network changes nobody's number.
- **Give the codes of fewest pulses to the busiest exchanges.** A flood lasts until
  `e` and `b` have both been dialled, so each pulse of an exchange's code adds
  0.1 s to the flood of every call made to it (§4). A 1 is one pulse and a 0 is
  ten: 11 is the cheapest code, 2.0 s of flood, and 00 the dearest, 3.8 s. The
  convention suits this. A tandem has a dozen lines and is seldom called, so the
  0 series costs little there.
- **An exchange's own code works from inside it**, at the cost of a flood: the
  origin's register sees its own `e b`, releases the trunks and carries on
  locally.

---

## 3. Flood, monitor, claim — the **pulse flood**

The protocol of this section is the **pulse flood**: the caller's own dial pulses,
flooded live down every trunk, heard by every exchange, and claimed by the one
they name.

**The origin opens a flood on the key `1`, the caller's own pulses go down
it, every exchange hears them, and the owner drops the call in.** A transit needs
no matrix and no route table, because it never has to know where a call is going
in order to pass it on.

```
 origin    the FIRST digit is in, and it is 1.  (0 and 9 are local hunts, and 2–7 begins a local
           number: none of them touches a trunk.)
           Seize one free trunk in EVERY direction the exchange has, all listening to the CALLER:
           their remaining digits go down the flood as they dial them.  The network card holds the
           trunks seized for this register (§3.2), which goes on counting:
           our own e b → release the trunks, carry on locally.  An e or a b of 8 or 9 →
           reserved: release the trunks, cannot-complete.  Else, when a trunk has claimed, release the
           others; when the last digit is in, point the caller at the one that claimed and free
           the register.  No claim 2 s after the last digit → cannot-complete.
           b not in 5 s after the key → release the trunks, cannot-complete: a caller who stops,
           or a key that was never dialled at all (§4)
 seizure   at every exchange it reaches: M rises on a trunk → the marker hunts a free trunk in
           every OTHER direction the exchange has — any channel to any channel — and a monitor
           listens.  One found: patch it, two latches, and forget.  Two or three: fan out (§3.2).
           A seizure is never forwarded INTO a strapped link, nor forwarded ONWARD from one:
           that is how a ring is kept from circling (§3.3)
 e, b      the first two digits a monitor hears are e and b (1 was the trigger, and said nothing a
           monitor needs).  e not ours → the monitor lets go at once.  e ours → it reads on.
           b ours → CLAIM: re-point the incoming trunk into the local fabric with the latch's
           CLAIM bit set, clear the onward patch or every leg of a fan-out, fetch a register,
           and read on — h s, or 0, or 9: the trunk is now simply a line HERE.
           b not ours → the monitor lets go.
           A monitor counts only a seizure whose rise it saw, and the origin abandons a call
           whose next break comes within 128 ms of its seizure  (monitor.md §3)
 claim     a trunk port with CLAIM set sends backward A = 1, steadily, until release.  An origin
           or a hub that seized several keeps the one whose M rises and releases the others
 release   A falls through every patch at once; each port clears itself (marker.md §5)
```

**The claim is a level, not a wink.** Release is on a *fall* of M or E. A wink is
a rise and a fall, and every patch it crossed would clear itself 256 ms later. A
level that rises at claim and falls at release is one rise and one fall, which is
what the rule already expects; no port changes. It costs the difference between
*claimed* and *answered* on backward A across the network: a CO line extended to
another exchange is answered at claim, and a data card's `DSR` rises at claim.
Local calls keep true answer supervision.

**Geography is nowhere.** The origin learns the way from the claim, not from
jumpers saying which group each code lies behind.

**A transit with no free onward trunk** cannot forward, and the origin would wait
out its 2 s. It hears `b` like everyone else, so it may **claim the call in order
to refuse it** — trunk to its own cannot-complete tone, `CLAIM` set — and the
caller gets the tone at once.

### 3.1 Worked: line 44 of exchange 22 dials 1 2 4 5 5 on the chain 22 ═ 23 ═ 24 ═ 25

A dial at 10 pps, 0.8 s between digits; milliseconds from lifting the handset.
The times are arithmetic on the constants `exch.py flood` uses (a digit recognised
128 ms after its last pulse, a marker action 2, a hop of the flood 7, the A path
1.5 up and 2 down a hop, a release 256). The model's own run is `flood` 1.

```
      0   22   44 lifts
     10   22   register attached; dial tone
   1000   22   44 dials 1: its one pulse ends at 1060
   1190   22   the first digit is in, and is 1: seize a trunk toward 23, listening to the caller
   1197   23   M rises on the trunk: patched to a free trunk toward 24; monitor on
   1204   24   M rises: patched to a free trunk toward 25; monitor on
   1211   25   M rises: nowhere to forward; monitor on
   1318   22   the origin's guard ends: a break before this would have abandoned the call
   1860   22   44 dials 2 — 542 ms after the guard; last pulse ends at 2020
   2150        "2" is every monitor's e on this chain: all three read on
   2820   22   44 dials 4: last pulse ends at 3180
   3310   23   "4" is not my b: monitor lets go; the patch stays
   3313   24   "4" is my b: CLAIM — trunk → local fabric; the patch toward 25 cleared; backward A = 1
   3313   25   "4" is not my b: monitor lets go
   3316   22   backward A rises on the trunk
   3571   25   its port has released itself: link 24–25 is free again
   3980   22   44 dials 5, then 5: the last pulse ends at 5700
   5830   22   its own register has the last digit: caller 44 ↔ trunk; register freed
   5833   24   has 5 5: trunk ↔ line 55; 55 rings; ringback goes back in band
   5833   22   44 hears 24's ringback            post-dial delay 133 ms
```

**What is held, and for how long.** From the key to the claim — 2.1 s here, the
time it takes to dial `e` and `b` — the call holds a trunk on all three links and
a monitor at 23, 24 and 25. **From the claim on it holds one trunk on 22–23 and
one on 23–24 and nothing else**: link 24–25 was released by the owner clearing
its onward patch, 25 holds nothing, and 23 holds two patched ports — no register,
no marker, nothing but two latches. The channels differ from link to link because
each exchange chose its own (§7). An exchange whose `e` is not the one dialled
frees its monitor a digit sooner, at 2150 here. Its patch stays until the claim.

**A local call holds nothing.** 44 dialling `4 7` never touches a trunk, and no
other exchange hears of it.

**Busy** is the owner's to say: 24 points the trunk at its cannot-complete tone and
the caller hears it through the same path. **Release** from either end is A
falling through every patch at once; each port clears itself 256 ms later, and
55, if still off-hook, gets 24's dial tone.

**From the middle**, a line of 23 dialling `1 2 5 5 5` seizes a trunk toward 22
*and* one toward 24. 22 hears a `b` of 5 and lets go; 25 claims; backward A rises
on the trunk toward 24; the origin keeps it and releases the other.

| the network card | |
|---|---|
| Holds | the own-code jumpers, `e` and `b`, three bits each; the forward-on-seizure sequence; the seize and await-claim sequence and its guard, with the **three-way strap that sets the guard's tap** (`monitor.md` §3.5) beside the code jumpers; **the trunks an origin seized**, a '574 a direction in a bank a register; the direction states and the claim comparator; at a hub, **the fan-out resolvers** (§3.2) |
| Where the rest of it is | nowhere. **Everything the network needs is on this card.** The fabric, the ports, the registers, the marker and the release rule are the standalone exchange's, unchanged, so an exchange joins a network by plugging cards in (§3.2, `mvp.md` §5) |
| Not fitted | `1` gives cannot-complete, and the trunk ports are empty: the standalone exchange |

### 3.2 Hubs: three or four directions

A transit on a chain forwards into its one other direction: two latches, and it
holds nothing. A hub forwards into two or three. Any number of trunks may listen
to the incoming one, so the caller's pulses go down every leg at once. But the
incoming trunk can listen to only one port, and which leg will claim is not known
until the claim comes back. Latches cannot be read back, so the hub remembers the
call until then, in a **resolver**:

```
 seizure            one scan finds a free trunk in each other direction.  Each leg listens to the incoming
                    trunk.  The incoming trunk listens to idle, BUSY set, so backward A stays 0: no claim
                    yet.  A resolver takes the incoming trunk's address and the legs'
 a leg's M rises    that branch has claimed.  The incoming trunk listens to that leg, and backward A rises
                    toward the origin.  The other legs are pointed at idle: each releases itself 256 ms later,
                    and its link with it.  The resolver is free, and the call is a patch of two latches, as
                    on a chain
 ours               the hub's monitor claims, as any owner does, and every leg is pointed at idle
 no claim           a local call elsewhere, a wrong number, a caller who hangs up: forward A falls, the
                    incoming trunk releases itself, and every leg with it.  The resolver frees itself when
                    the incoming trunk reads BUSY = 0, which dial pulses never cause
 no resolver free   patch into the first direction found, as a chain would: the call reaches that branch
                    only
```

| | |
|---|---|
| **A resolver** | the incoming trunk's address and three legs', in 4 × 74HC574, and a flip-flop: **≈ 4½ packages** |
| **Seeing the claim** | the scanner visits every port every 8 ms. At each visit a counter runs the stored leg addresses, the resolvers' and the seizure banks', past one shared 74HC688 while the probe reads M off the control bus, well inside the 125 µs visit: **≈ 3 packages**, shared, on the card |
| **The origin** | the trunks it seized are held on the network card, one 74HC574 a direction the exchange has, in a bank a register: two '574 a bank at an exchange on a chain. The register counts the digits and says when to let go; the card holds the addresses and writes the latches. This replaces the card's two '174, which held only one pending network call at a time. **The bank is on the card and not in the register**, so joining a network does not reach into a register already fitted |
| **How many** | every call dialled with `1` anywhere in the network passes the hub, for 2.2–3.2 s, the time `e` and `b` take. With 30 % of calls leaving, eight exchanges of 48 lines put 0.26 E on the hub's resolvers: two are all busy 2.6 % of the time, three 0.2 %. Twenty put 0.64 E: three 2.3 %, four 0.4 %. **Three at a hub, four at the centre of a score of exchanges** |
| **The marker** | **nothing.** It hunts a class as it always did and knows nothing of directions: the card watches the same probe and pulls `/HUNT_INH` at a port whose word faces the wrong way, so the hunt walks on (`marker.md` §4). The direction states — the origin's scan, a transit latching the incoming trunk's direction and hunting the others, the resolver's states — are **≈ 4 packages**, on the card |
| **Timing** | a hub adds up to three writes to the flood's hop, about 4 ms, and up to one scan and a write to the claim's way back, 10 ms. The origin's guard covers ten hops at a slow marker's 12 ms on its 128 ms tap, twenty-one on its 256 ms one, and a hub counts as a hop and a third (`monitor.md` §3.5). **On the 128 ms tap no exchange should be more than about eight hops from another**: a hub with four chains of four is eight across |
| **Loops** | a tree of chains and stars needs no strap. A ring anywhere, through a hub or not, is broken by strapping one of its links (§3.3) |
| **Monitors** | two a trunk block, as everywhere: a flood reaches a hub on one block |

**What it costs, and where it sits.** Every networked exchange pays ≈ 4 for the
direction states, ≈ 3 for the shared comparator and a '574 a direction in each
register's bank — **and all of it is on the network card**. A hub adds its
resolvers: ≈ 14 for three. Nothing is added to the fabric, the ports, the
registers, the marker or the release rule, and after the claim a call through a
hub is two latches like any other.

**What the standalone exchange must carry for that to be true**, and carries
anyway (`mvp.md` §5):

- **the probe on the control bus.** The scanned port's M and its word go out
  beside `PORT`, `SRC`, `BUSY` and `WR`, on the '244s the marker already has. A
  card that wants to watch the scan can.
- **one pulled-up input, `/HUNT_INH`.** A hunt takes it; nothing drives it when
  no card is fitted, which reads as *accept*, and the hunt is the plain
  first-free-of-a-class it always was. It is the only way anything may steer a
  hunt, and it keeps the marker from ever learning what a direction is.
- **the diode for key `1`**, which sends it to a class-4 hunt. With no trunk
  port fitted that hunt finds nothing and the caller gets cannot-complete
  (§2, `mvp.md` §4).

**How big the card is.** The jumpers and the two sequences, ≈ 4 for the
direction states, ≈ 3 for the comparator, and a '574 a direction in each
register's bank — six at an exchange on a chain with three registers — is
twenty-odd packages: **one card, on the control bus beside the marker**, not in
a line slot. A hub has four directions to seize into but a dozen lines and one
register, and adds ≈ 14 of resolvers: thirty-odd, **two cards**. That is the
price of keeping it all off the marker and the registers, and it is paid only
where it is used.

### 3.3 Rings: the strap belongs to a link, not to an exchange

A flood must not go round in circles. Left alone, a seizure sent round a ring
comes back to the exchange that made it, which forwards it again, and the call
eats a channel of every link at each turn until the links are full.

**The strap is the `n` bit of a trunk port's word** (`extensions.md` §2.2),
set on every channel of one link, at both ends. It says:

```
 a strapped link   a seizure is never forwarded INTO it, and a seizure that arrives ON it is never
                   forwarded onward.  An origin may still seize it, and the far end may still claim:
                   the link carries calls between its own two ends, and no others
```

**The links without the bit must form a tree**: one strapped link breaks a ring,
and a mesh needs one in every independent cycle. Both ends should be strapped.
One end alone breaks the cycle just as well, because a seizure that arrives on a
strapped port is not forwarded either way, but then the unstrapped end floods
into a link that goes nowhere, and wastes a channel on every call.

**What it costs at the two ends.** A call from one end of the strapped link to
the other reaches it twice: once on the link, once the long way round. Both
monitors match, so the far exchange claims twice. The direct copy is a hop away
and the long one many, so the direct copy always claims first, the caller gets
it, and the origin releases the long way as soon as it does. The second claim
finds the called line busy — it is ringing for the first — and points its trunk
at cannot-complete for the few hundred milliseconds before the release reaches
it. No caller hears it. Everywhere else in the ring, every exchange sees the
call once.

**Why not strap an exchange.** An exchange strapped to forward nothing, which is
what this document said before, breaks a ring only for calls that do not begin
there. Its own calls go out both ways, meet at the far side and come back to it,
so every other exchange in the ring sees the same call twice, on two trunks, and
if one of them owns the call it claims on both. The first claim wins and the
second gives cannot-complete, which is a race no caller should be in.

**A ring is also a spare.** Move the strap to a link that has failed and the ring
is a chain again, with every exchange still reachable. That is a jumper, or a
switch on the trunk card, at each end of two links.

---

---

## 4. What the network speaks: the caller's own dial pulses

**All pulse, live.** The trunks listen to the caller; the caller's hook is their forward A;
a monitor reads two digits of it. One signalling system, all 74HC, nothing sent
twice.

| | |
|---|---|
| What is consumed | the first digit only, and it is the trigger: `1`, which says only that the call leaves, so no monitor needs it |
| A monitor | its own small circuit on the trunk block, **not a register from the pool**: `monitor.md`. It reads `e` and `b`, claims or lets go, and on a claim the marker fetches a register for `h s` |
| What keeps it from ever claiming a wrong number | **a monitor counts only a seizure whose rise it saw; the origin abandons a call whose next break comes within 128 ms of its seizure.** Measured under `1 e b h s` with both digits compared: 0 false claims in 1 500 calls with both rules, 3 to 12 without (`monitor.md` §5). Both hazards act on the first digit heard |
| Pulses as they arrive | a CVSD line card's hook detector shortens a break by 6.1 ms (`register.md` §1); the trunk's A path by 0.5 ms a hop (`channel-cards.md` §5); a copper tie not at all. A 60 ms break is 50 ms after seven hops, against an 8 ms window |
| Against the release rule | the longest dial break, 103 ms, against the shortest release, 204 ms: `exch.py calls` 15b |
| Post-dial delay | **133 ms after the last pulse**, whatever the hop count |
| A key and nothing after it | **the origin releases its trunks 5 s after the key** if `b` has not arrived. The register keeps its own 10 s for the caller (`marker.md` §6). Without the rule an accidental key, or a caller who stops to think, would hold a channel on every link for the register's whole 10 s. A slow dial reaching the code 77 needs 3.8 s, so 5 s leaves margin |
| An accidental key | one break of 8 ms or more, then 128 ms of unbroken make, on a line with a register attached. Nothing digital makes one: a CVSD line's hook detector gave **0 false events** against noise to sd 0.8 and impulses to 1000/s (`subscriber-line.md` §5), and A across MF8 gave **0 spurious transitions in 60 s to a line error rate of 1e−1** (`channel-cards.md` §5). What is left is the subscriber's own instrument — a hook flash, a worn dial contact — as in any exchange. Contact bounce is caught by the origin's guard, which abandons on a break within 128 ms of the seizure. **It would take about 13 an hour across the network to add 0.01 E to a link** |
| Also | a data card places a network call by pulsing `DTR` |

**What must hold: the flood is up before the caller's next digit.** The digit
recognised (128 ms), the seizure (2), the origin's guard: **ready 130 ms plus the
guard's tap after the caller's last pulse, whatever the hop count** (`exch.py
flood` 5) — 258 ms on the 128 ms tap and 386 on the 256 ms one, against the 720 ms
a telephone to ES 201 187 gives at its fastest (`register.md` §2). The flood
itself takes 7 ms a hop — 49 ms across seven, 84 at a slow marker — well inside
the guard, and **which tap to strap is what decides how many hops there may be**
(`monitor.md` §3.5).

**And whatever the carrier.** Of that 7 ms a hop, only the marker's own 3–10 ms is
in the guard's budget: a link's *transmission* delay is not, because the seizure
and the caller's pulses travel it together and arrive together. A trunk on a
leased circuit or a radio 80 ms long puts the flood up 600 ms after the seizure in
absolute time and changes nothing, measured to 0 false claims in 1 000 calls
(`monitor.md` §5.1). What the guard does have to cover, besides the marker,
is delay the carrier **loses** between the seizure and the next digit, and the
guard is one tap on a counter with four taps of room above it. A dial leaves 242 ms of margin at 0.5 s between digits and 542 at
0.8 s. A caller who beats it is abandoned to cannot-complete: a failed call,
**never a wrong number**.

**What it costs: every call that leaves floods the whole network**, from the key
until `e` and `b` have both been dialled. One trunk on every link, and a resolver
at every hub, are held for that long: **2.0 s for the code 11 up to 3.8 s for 00,
0.1 s a pulse, 2.7 s on average over the sixty-four** (`exch.py flood` 5; `code_hold`
in the model). A monitor whose `e` is not the one dialled is free after the first
digit, 1.5 s on average. **A local call costs nothing**: under the earlier plan,
in which every number began with a shared `e`, every call flooded, local ones
too.

---

## 5. How many exchanges a link will carry

A direction of eight channels carries 3.13 erlang at 1 % blocking; **of sixteen, 8.88 —
more than twice the calls for twice the trunks.** The tables below were run on
six-channel groups (1.91 E / 5.88 E at twelve) and are the shape, not the new
capacity. In a chain the middle link carries
everyone's traffic across it, and the flood adds its own. 48 lines an
exchange at 0.08 E a line and 3 calls a line an hour, calls spread evenly over
the other exchanges, and every call that leaves flooding every link for 2.7 s
(§4); erlangs on the busiest link (traffic + flood) and calls blocked there:

| exchanges | | 20 % of calls leave | 30 % | 50 % |
|---|---|---|---|---|
| 2 | one link | 0.77 + 0.04 E, 0.0 % | 1.15 + 0.06, 0.1 % | 1.92 + 0.11, 1.3 % |
| 3 | chain | 0.77 + 0.06, 0.0 % | 1.15 + 0.10, 0.2 % | 1.92 + 0.16, 1.4 % |
| 3 | triangle | 0.38 + 0.06, 0.0 % | 0.58 + 0.10, 0.0 % | 0.96 + 0.16, 0.1 % |
| 4 | chain | 1.02 + 0.09, 0.1 % | 1.54 + 0.13, 0.6 % | 2.56 + 0.21, 4.0 % |
| 5 | chain | 1.15 + 0.11, 0.2 % | 1.73 + 0.16, 1.0 % | 2.88 + 0.27, 6.1 % |
| 6 | chain | 1.38 + 0.13, 0.4 % | 2.07 + 0.19, 2.0 % | 3.46 + 0.32, 10.1 % |

The same busiest link, six channels against twelve (traffic and flood together):

| exchanges in a chain | 30 % of calls leave | 50 % |
|---|---|---|
| 4 | 1.66 E: 0.6 % → 0.00 % | 2.77 E: 4.0 % → 0.00 % |
| 5 | 1.89 E: 1.0 % → 0.00 % | 3.15 E: 6.1 % → 0.01 % |
| 6 | 2.27 E: 2.0 % → 0.00 % | 3.78 E: 10.1 % → 0.04 % |

**Doubling the trunks at the centre is what lets a chain of six carry busy
traffic**, and it costs the central exchanges twelve lines each (36, not 48).
A doubled centre needs its edges doubled too: in a longer chain the links just
outside a doubled core carry nearly as much as the core, and become the
bottleneck.

**A star does the same with less.** Five exchanges of 48 lines, `b` from 2:

| | busiest link, 30 % of calls leave | 50 % | MF8 links | trunk ports | line slots given up | links a call crosses |
|---|---|---|---|---|---|---|
| chain | 1.0 % | 6.1 % | 4 | 48 | 0 | 2.0 |
| chain, the middle two links doubled | 0.19 % | 1.72 % | 6 | 72 | 24 | 2.0 |
| star: a hub and four spokes (§3.2) | 0.19 % | 1.72 % | 4 | 48 | 12 | 1.6 |

A spoke's link carries one exchange's traffic, as a chain's end link does, so the
star blocks exactly as the doubled chain does, with a third fewer trunks, two MF8
links fewer and half the lines given up, all of them at the hub. It also fits a
plant that radiates from a centre.

### 5.1 Measured: eight exchanges, call by call

`exch.py net` runs two hubs of four directions with three leaves each — 12
channels between the hubs, 6 to every leaf, 30 lines at a hub and 48 at a leaf,
348 in all — for twelve hours. A line makes 3 calls an hour and holds one 48 s;
30 % leave home. **Bursty** is the same calls arriving together: 30 s at eight
times the rate, every 5 minutes, an office at a shift change.

| | calls an hour | leaf link, 6 ch | hub link, 12 ch | flood held a leg | dial tone, mean / 99 % / worst | lift to ringback, local / network |
|---|---|---|---|---|---|---|
| smooth, 30 % leaving | 1 053 | 1.25 E, 0.13 % | 2.57 E, 0.00 % | 1.98 s | 6 ms / 10 ms / 1.1 s | 2.33 s / 4.82 s |
| bursty, 30 % | 1 047 | 1.26 E, 0.25 % | 2.46 E, 0.00 % | 1.98 s | 15 ms / 10 ms / 5.6 s | 2.34 s / 4.82 s |
| bursty, 50 % | 1 047 | 1.87 E, 2.12 % | 3.78 E, 0.12 % | 1.99 s | 19 ms / 249 ms / 4.2 s | 2.35 s / 4.82 s |
| bursty, 30 %, two registers | 1 047 | 1.24 E, 0.59 % | 2.45 E, 0.00 % | 1.98 s | 79 ms / 2.1 s / 7.4 s | 2.39 s / 4.89 s |
| bursty, 30 %, one register | 1 047 | 1.34 E, 0.26 % | 2.61 E, 0.00 % | 1.98 s | 1.0 s / 13.2 s / 35.9 s | 3.25 s / 5.71 s |

The hubs are 11 and 12, backbone codes, and the leaves 21–23 and 31–33 (§2). The
model dials each call's own code, so these floods are short ones: the codes are
cheap.

- **§5's arithmetic holds.** Worked with these codes' own floods it predicts
  1.28 E and 0.17 % on a leaf link at 30 % leaving, and 2.58 E on the hub link;
  the run gives 1.25 E and 0.13 %, and 2.57 E. The flood is held 2.0 s a leg
  against 2.2 s by arithmetic, the difference being this model's pauses,
  0.5–0.9 s against 0.8 s.
- **Bursts do not move the erlangs.** The same calls arrive, in a different
  order. What they move is what a caller waits for: dial tone's mean more than
  doubles and its worst case goes from 1.1 s to 5.6 s, while every link and pool
  reads the same.
- **Bursts fall on the registers, and nowhere else.** Three at a 48-line leaf
  carry them: 1.2 % of callers wait a scan for one. Two, and 6.8 % wait, with
  one caller in a hundred waiting 2 s. One, and a third of all callers wait,
  1 in 100 for 13 s. **Fit three.**
- **The pools built for the flood are barely touched**: a hub's resolvers reach
  0.14 E and turn away 0.1 % of the calls that want one; a leaf's monitors 0.09 E
  and 0.0 %. Three of each is generous, two would do at this size.
- **At 50 % leaving the leaf links are the constraint**, 2.12 % blocked against
  0.12 % on the doubled hub link. Twelve channels to each leaf, or fewer calls
  leaving home.
- **What a caller hears**, whatever the load: 2.3 s from lifting to ringback on a
  local call, 4.8 s on a network call to these codes, of which most is dialling
  five digits at 10 pps. The claim itself is 133 ms, as §4 has it.

---

**A hub with four directions of sixteen channels is a tandem switch.** It gives
blocks 1–7 to trunk groups: seven groups, and the 04–07 bank (`protocol.md` §5,
`mf8-unit.md` §7). Each direction is a
chain of *k* exchanges of 48 lines. With 30 % of calls leaving, erlangs on each
link of a branch from the hub outward, and calls blocked there on eight channels
and on sixteen:

| *k* | exchanges | flood a link | hub to 1st | 1st to 2nd | 2nd to 3rd | 3rd to 4th | 4th to 5th |
|---|---|---|---|---|---|---|---|
| 1 | 4 | 0.13 E | 1.28 E: 0.2 % / 0.00 % | | | | |
| 2 | 8 | 0.26 | 2.23: 1.9 % / 0.00 % | 1.41: 0.3 % / 0.00 % | | | |
| 3 | 12 | 0.39 | 3.21: 6.4 % / 0.01 % | 2.48: 2.7 % / 0.00 % | 1.54: 0.4 % / 0.00 % | | |
| 4 | 16 | 0.51 | 4.20: 13 % / 0.09 % | 3.51: 8.3 % / 0.02 % | 2.66: 3.5 % / 0.00 % | 1.67: 0.6 % / 0.00 % | |
| 5 | 20 | 0.64 | 5.19: 21 % / 0.45 % | 4.52: 16 % / 0.17 % | 3.73: 9.8 % / 0.04 % | 2.82: 4.3 % / 0.00 % | 1.79: 0.8 % / 0.00 % |

**Twenty full exchanges work around one hub** with twelve channels on every link
but the outermost, where six will do. The hub wants four resolvers (§3.2) and
each exchange's trunk blocks three monitors (`monitor.md` §4).

**`traffic.md` takes the demand further** — bursts, a flash crowd, peak against
off peak, and the whole of this section's network run a second time **in the gates**
(`verilog`'s `make traffic-net`, eight whole exchanges in RTL) and read against the
model here. Two things it changes: **Erlang B holds to about 1 % on a link and
understates past it**, because a flood puts a seizure on every link of the network
at the same instant; and **a caller is a line**, which cannot lift while it is off
hook, so a burst does not offer the calls the arithmetic says it does.

**`topology.md` takes this further**: chains, stars, trees and a split centre,
the largest of each, and rings. **What sets the limit is the flood, not the
numbering.** The flood's share — the
second figure above — is every call that leaves, anywhere, held on every link for
2.7 s. Thirty-six full exchanges would put 1.2 E of it on every link: more than
half of what six channels carry, and a fifth of twelve. **The sixty-four codes are
more than full exchanges can use**: the largest network `topology.md` finds is 47
exchanges and 1 700 lines, with a fifth of calls leaving. Past that the way on
is SS0 (`ss0.md`), whose message floods for a third of a second, or a second
network reached through `1 8` or `1 9` (§6). A pair can put both groups between
them (twelve channels, no blocking to speak of). **Closing a chain into a ring**
puts a link between its two ends and takes their traffic off every link between
(§3.3): at five exchanges and 30 % leaving the busiest link falls from 1.89 E to
1.60 E, 1.0 % blocking to 0.5 %, and the new link carries 0.45 E. At 50 % it is
3.15 E to 2.67 E, 6.1 % to 3.5 %. The gain is that one pair's traffic and no
more, because the flood, and so the call, goes one way round: the strapped link
carries only calls between its own two ends.

---

## 6. Out of the network: `1 8`, `1 9` — reserved

`1` followed by 8 or 9 is reserved, and returns cannot-complete today. No `e`
can be either, so a monitor knows such a call by the first digit it hears and
lets go, and only a gateway exchange would claim it. One way to do that
with no sender was worked through under the earlier plan and is kept here, not
adopted: each digit is claimed by one level in turn, with the same 258 ms and the
same guard (`exch.py flood` 7). The alternatives are a pulse delay (≈ 2 packages:
no digit is ever consumed) or a register-sender (§9).

---

## 7. Why a transit chooses its own channel

The first version of the flood hard-wired channel *k* through every exchange, so
a call needed the same *k* free on every link while its origin chose *k* seeing
only its own. A scratch simulation — a chain of 8, 6 channels a link, uniform
traffic, 150 000 calls a cell, % blocked for all calls / calls of 4+ hops:

| offered, whole chain | a channel chosen at each hop | **the same *k*, chosen blind** | the same *k*, all-knowing |
|---|---|---|---|
| 0.5 E | 0.00 / 0.00 | **2.10 / 4.29** | 0.00 / 0.00 |
| 1 E | 0.00 / 0.00 | **4.14 / 8.21** | 0.00 / 0.01 |
| 2 E | 0.11 / 0.18 | **8.34 / 16.4** | 0.13 / 0.21 |
| 4 E | 2.21 / 3.60 | **16.1 / 31.0** | 2.61 / 4.62 |

The damage is the blind choice, not continuity. Since seizure comes before the
number, a transit can patch to any free onward trunk with its ordinary fabric,
and blocking becomes the first column. Not in `exch.log`; `net` reproduces it.

---

## 8. Clocking

Plesiochronous, ±20 ppm crystals. Slips add per hop: one crossing measured
34.6 dB at 20 ppm, 33.2 at 100 and 20.7 at 1000 against the clean decode, the
codec itself 25.3 (`mf8-backplane.md` §7, under the codec law of that date).
±20 ppm is up to 40 between neighbours, so seven crossings are at most
280 ppm-equivalent: between the measured rows, expected above the codec, and for
`net` to score. **Voice and async oversampled data cross MF8; synchronous data
and G.711 pass inside an exchange and over copper ties, not across MF8.** The
clock card keeps a strap and a footprint to slave to a trunk's `RX_CLK` later.

---

## 9. Considered and set aside

- **A register-sender** — the origin repeats the number into the flood at 20 pps,
  keeping pace with the caller (`exch.py flood` 1–4): post-dial delay 0.49 s
  against 0.13 s live. ≈ 6–7 packages, all 74HC: two '4017 for the 50 ms period,
  a '193 counted down a pulse at a time, a '393 for the pause and the digit
  pointer, a '74, an '86, a '00. It would let the origin know a call is local
  before seizing anything (0.03 E of flood a link instead of 0.19), free the
  numbering plan, and serve keypad phones. Set aside because for a handful of
  dial-phone exchanges nothing needs repeating.
- **Serial characters on A** — measured (`exch.py aline`): start, data, stop, at
  16 ms a bit, cross seven hops with 0 errors in 4 000 at a line error rate of
  1e−2, a four-digit number in 0.32 s. Each hop shortens a space by 0.5 ms and
  delays it 2 ms. Set aside as a second signalling system that needs the sender.
- **An in-band DTMF sender** — the original plan; replaced by pulses.
- **Hop-by-hop dialling**, **route jumpers** saying which exchanges lie behind
  which direction, **hubs that finish a call with a sender and a matrix**, **a wink for the claim** — each replaced by something in
  §3 that needs no knowledge of where anything is.
- **`e` as the key** — every number dialled `e b h s`, its own exchange's
  included, with `e` shared by every exchange and consumed to open the flood. It
  allowed six exchanges, and every call flooded, local ones too: 0.35 E a link at
  six exchanges, against 0.19 E now. Replaced by the key `1`, local numbers of two
  digits and a monitor that reads two digits.
- **Making one exchange bigger than 64 ports** — `protocol.md` §3.1.

---

## 10. Not measured

- **Everything in §3 as gates.** Fan-out resolution at a middle origin, the
  strapped link of §3.3 and the double claim at its ends, own code dialled from
  inside, `1 e b 9`, glare, a trunk down
  in mid-call, and the flood's real load against calling rate.
- **The gates of §3.** `net` models the timing, the pools and the channels, not
  the circuits: a monitor is a thing that is taken and given back, not a pulse
  counter, and a resolver is a count. The fan-out's writes, the hub's re-point
  and the two-digit compare are still to be drawn.
- **§4's timing.** Arithmetic on measured constants; the monitor's rules are
  simulated under `1 e b h s` with both digits compared (`exch.py monitor`,
  `flood`). §3.1's timeline and §4–§5's flood figures are worked from those
  constants.
- **An accidental `1`.** One pulse is the easiest digit to make by fumbling the
  hook. It costs a flood and a cannot-complete, never a wrong number, since a
  claim needs two more digits to match. How often it happens is a counter on a
  working exchange.
- **§5's loads.** Erlang arithmetic with even calling; a real community is not
  even.
- **How fast people really dial.** The margins rest on 0.5–0.8 s between digits;
  `register.md` §3 tested its register down to 0.25 s, which the guard would
  abandon.
- **Seven slips in a row**, at 20, 40 and 100 ppm.
- **The trunk card's external-clock strap**, and the block's clock crossing.
- **The hub** (§3.2): the resolver, the shared comparator's run through the
  stored legs, a claim that races a release, and a star's timing, all as gates.
  `net` models a two-hub tree (§5.1), and `topo` a chain, a star, two trees and
  rings with and without a strap (`topology.md`).
- **Trunks that are not MF8** (§1.1): the baseband copper card is `baseband.md`;
  the two-wire voice-band card with in-band dual-tone A is `pots-trunk.md`.
  Neither has been on a bench; `pots-trunk.md` §9 lists what it still owes.
