# The exchange — trunks and the network

How exchanges are joined by MF8, how a line on another exchange is dialled
directly, and what that costs. A standalone exchange carries none of this:
everything here is on trunk blocks and one optional network card.

> **Status: analysis.** Decided: **all pulse, no DTMF; the flood carries the caller's
> own dial pulses, live; no sender inside a district.** A call floods as soon as
> its first digit is in. The timing in §3.1, §4 and §4.1 is `exch.py flood` —
> arithmetic from measured constants (the register's windows, the trunk's A path),
> **not a simulation of the gates**. **§4.1 — how `1` is handled with no sender —
> is a proposal**: it fixes what an area code may begin with, which had been left
> TBD. A register-sender and serial characters on A were worked out and set aside
> (§8). §5 quotes a scratch simulation. The flood, the monitors, the claim and
> every sequence of §3 are **unmodelled**: `exch.py net` does not exist yet.

---

## 1. One block, three populations

| population | fitted | ports |
|---|---|---|
| **line** | eight channel cards | 8 |
| **trunk** | one MF8 trunk card; class 4 set once for the block | 6, on slots **1, 2, 3, 5, 6, 7** — the '151 map of `mf8-spec.md` §10. The highway is the MF8 frame with F and S handed back; slots 0 and 4 stay channel slots |
| **tie** | a crossover to a co-located group's tie block: the NRZ highway itself, same clock | 8 junctors, class 4, bit-exact at 2 frames (`exch-protocol.md` §4) |

| a trunk block | |
|---|---|
| Transmit | in the exchange's clock. The trunk card needs a strap to take 4.096 MHz and frame sync from the clock card instead of owning the crystal |
| Receive | each link is its own clock domain. The crossing of `mf8-backplane.md` §2 moves here: two '174s for the six `C`, the §14 RC and Schmitt gate for `A` |
| Trunk down | `MUTE` clears the A '259, every M falls, calls release themselves. **`MUTE` must also force the block's `BUSY` highway to 1**, or a dead trunk hunts as free |
| Guard | `exch-marker.md` §5.2's settle term already holds a released junctor busy for ~0.6 s |
| Glare | the two ends of a link hunt it in opposite order (a strap); residual glare joins two callers to each other |

A group past 64 ports is another exchange to the numbering plan, reached over a
tie block exactly as a remote one is reached over MF8.

---

## 2. Numbers

**One jumper: a standalone exchange dials `h s`; a networked one dials `e e h s`
for every number, its own included** — the small-town conversion.

```
 standalone    4 7           line 47
 networked     3 2 4 7       exchange 32's line 47 — the same digits from anywhere, 32 included
               3 2 0         exchange 32's operator          3 2 9   its outside line
 long distance 1 8 3 3 2 4 7 another district or area — §4.1, proposed
```

- **Exchange codes are 20–77**, octal as dialled: 48 codes. A code is never an
  address; it is compared with jumpers on the network card, which say **who the
  exchange is and never where anything is**.
- **Read `e e` as district and exchange** from the start: neighbours share a first
  digit. It costs nothing now and is what §6 needs later.
- The length is uniform across a network, because a monitor must know what the
  first digit it hears stands for.
- Against a one-digit code: one more key a call, one or two packages, the '670
  exactly full — and 48 codes instead of 6. **The argument for two digits is
  growth at a site**: every further group of 64 takes a code.

---

## 3. Flood, monitor, claim

Nobody routes, and nobody sends. **The origin opens a flood on the first digit,
the caller's own pulses go down it, every exchange hears them, and the owner
drops the call in.** A transit needs no matrix and no route table, because it never has to know where a call is going
in order to pass it on.

```
 origin    the FIRST digit is in, and it is the home district's — or it is 1 (§4.1).  0 and 9 are
           local hunts; any other first digit is cannot-complete.  Seize one free class-4 port
           in EACH trunk block, all listening to the CALLER: his remaining digits go down the
           flood as he dials them.  The origin's register goes on counting: its own exchange
           digit → release the junctors, carry on locally.  Else, when the last digit is in and
           a junctor has claimed: point the caller at it, release the rest, free the register.
           No claim 2 s after the last digit → class 6
 seizure   at every exchange it reaches: M rises on a class-4 port → the marker patches it to a
           free class-4 port in every OTHER trunk block — any channel to any channel — and a
           monitor listens.  A block strapped NO-FORWARD is skipped: that is how a ring or a mesh
           is made a tree
 e         the first digit a monitor hears is the exchange digit (the district's was the trigger,
           and every exchange flooded shares it).  Ours → CLAIM: re-point the incoming junctor
           into the local fabric with the latch's CLAIM bit set, clear the onward patches, and
           read on — h s, or 0, or 9: the junctor is now simply a line HERE.
           Not ours → the monitor lets go.  A monitor that did not see 128 ms of steady make
           before the first break never claims
 claim     a trunk port with CLAIM set sends backward A = 1, steadily, until release.  Wherever
           the call fanned out — an origin with two links, a transit with three — the first
           onward junctor whose M rises is the way: point the backward path at it, release the rest
 release   A falls through every patch at once; each port clears itself (exch-marker.md 5)
```

**The claim is a level, not a wink.** Release is on a *fall* of M or E. A wink is
a rise and a fall, and every patch it crossed would clear itself 256 ms later. A
level that rises at claim and falls at release is one rise and one fall, which is
what the rule already expects; no port changes. It costs the difference between
*claimed* and *answered* on backward A across the network: a CO line extended to
another exchange is answered at claim, and a data card's `DSR` rises at claim.
Local calls keep true answer supervision.

**Geography is nowhere.** A fan-out point learns the way from the claim, not from
jumpers saying which arm each code lies on.

### 3.1 Worked: 2144 dials 2355 on the chain 21 ═ 22 ═ 23 ═ 24

A dial at 10 pps, 0.8 s between digits (`exch.py flood` 6; milliseconds from
lifting the handset):

```
      0   21   44 lifts
     10   21   register attached; dial tone
   1000   21   44 dials 2: its last pulse ends at 1160
   1290   21   the first digit is in, and is the district's: seize a junctor toward 22,
               listening to the caller
   1297   22   M rises on the junctor: patched to a free channel toward 23; monitor on
   1304   23   M rises: patched to a free channel toward 24; monitor on
   1311   24   M rises: nowhere to forward; monitor on
   1439   24   the last monitor has seen its 128 ms of make: the flood is ready
   1960   21   44 dials 3 — 521 ms after the flood was ready; last pulse ends at 2220
   2350   22   "3" is not mine: monitor lets go; the patch stays
   2353   23   "3" is mine: CLAIM — junctor → local fabric; the patch toward 24 cleared; backward A = 1
   2353   24   "3" is not mine: monitor lets go
   2356   21   backward A rises on the junctor
   2611   24   its port has released itself: link 23–24 is free again
   3020   21   44 dials 5, then 5: the last pulse ends at 4740
   4870   21   its own register has the last digit: caller 44 ↔ junctor; register freed
   4873   23   has 5 5: junctor ↔ line 55; 55 rings; ringback goes back in band
   4873   21   44 hears 23's ringback            post-dial delay 133 ms
```

**What is held, and for how long.** From the first digit to the claim — 1.06 s
here, the time it takes a human to dial the next digit — the call holds a channel on all three links
and a monitor at 22, 23 and 24. **From the claim on
it holds 21–22 channel 3 and 22–23 channel 1 and nothing else**: link 23–24 was
released by the owner clearing its onward patch, 24 holds nothing, and 22 holds
two patched ports — no register, no marker, no state beyond two latches. The
channel numbers differ from link to link because each node chose its own (§5).

**Busy** is the owner's to say: 23 points the junctor at its class 6 and the
caller hears 23's tone through the same path. **Release** from either end is A
falling through every patch at once; each port clears itself 256 ms later, and
55, if still off-hook, gets 23's dial tone.

**From the middle**, 2244 dialling 2455 seizes a channel toward 21 *and* one
toward 23. 21 hears 24, lets go; 24 claims; backward A rises on the arm toward
23; the origin keeps that arm and releases the other.

**A refinement, not yet in §3:** a transit that finds no free onward channel
cannot forward, and the origin would wait out its 2 s. It hears the code like
everyone else, so it can **claim the call in order to refuse it** — junctor to
its own class 6, `CLAIM` set — and the caller gets a busy tone at once.

| the network card | |
|---|---|
| Holds | the 2 / 4-digit jumper; the own-code jumpers, one comparator used twice through a '157; the forward-on-seizure sequence; the seize and await-claim sequence; **a pending-claim store — the junctor seized in each trunk block, 2 × '174** — used only where a call fans out |
| Not fitted | two-digit dialling, no class 4: the standalone exchange |
| **The cost is the flood** | every call floods, local ones included, from its first digit until the exchange digit is heard — about a second on **every link** and at **every exchange's** monitors (§4). It cannot be seized later: the second digit is the one the monitors need. Fine for a handful of exchanges; past 20–30, §6 |

---

## 4. What the network speaks: the caller's own dial pulses

**Decided: all pulse, no DTMF, live.** The junctors listen to the caller; his hook
is their forward A; every monitor is the pulse register of `register.md` §4
reading its own `A_RX`. One signalling system, all 74HC, nothing sent twice.

| | |
|---|---|
| What is consumed | the first digit only, and it is the trigger: the home district's digit, shared by every exchange the flood can reach, so no monitor needs it |
| A monitor | a register from the pool (class 7), or a pulse counter and the digit compare on the trunk block. **It claims only if it saw 128 ms of steady make before the first break**, so a monitor that attaches late can never count half a digit |
| Pulses as they arrive | a CVSD line card's hook detector shortens a break by 6.1 ms (`register.md` §1); the trunk's A path by 0.5 ms a hop (`mf8-cards.md` §5). A 60 ms break is 50 ms after seven hops, against an 8 ms window. The 6.16 ms correction of `register.md` §1.3 is optional |
| Against the release rule | the longest dial break, 103 ms, against the shortest release, 204 ms: `exch.py calls` 15b |
| Post-dial delay | **133 ms after the last pulse**, whatever the hop count |
| Also | a data card places a network call by pulsing `DTR` |

**What must hold: the flood is ready before the caller's next digit.** The digit
recognised (128 ms), the seizure, the flood, the monitors' 128 ms of make
(`exch.py flood` 5):

| hops | ready after the caller's last pulse | margin at 500 ms between digits | at 800 ms |
|---|---|---|---|
| 1 | 265 ms | 235 ms | 535 ms |
| 3 | 279 ms | 221 ms | 521 ms |
| 7 | 307 ms | 193 ms | 493 ms |

A caller who beats it gets a failed call, **never a wrong number**: the monitor
that was not ready refuses to claim, nobody claims, and the origin returns
class 6.

**What it costs: every call floods**, because the first digit cannot say whether
a call is local. The origin learns that from the second, carries on locally and
releases the junctors. A local call, 2144 to 2155 (`exch.py flood` 3, 4): every
link and a monitor at every exchange held 1.1 s for nothing; with 4 exchanges ×
48 lines × 3 calls an hour, **0.19 erlang of pure signalling on each 6-channel
link and at each monitor pool**. Fine for a handful of exchanges. It is also why
monitors should be a pulse counter on the trunk block and not registers from the
subscribers' pool.

### 4.1 Long distance: `1`, without a sender — proposed

**`1` is handled exactly as the district digit is: it is the trigger, it carries
nothing the network needs, and consuming it costs nothing.** What makes that
work is that the digits which follow say what kind of call it is, to a monitor
with no memory and nothing sent to it:

- **An exchange digit is 0–7: one to seven pulses, or ten.** Eight and nine
  pulses are never an exchange digit. **So an area code begins with 8 or 9**, and
  a monitor that hears 8 or 9 first knows a toll call; every ordinary exchange
  lets go, and the district's toll gateway — a monitor with a strap — claims.
  (It is the trick NANP used, the other way round. The compare is on the
  counter's four bits, not the octal value, since 8, 9 and ten all read octal 0.)
- **Each digit is acted on by exactly one level, which patches the call into the
  next flood before the following digit.** That is the same forward-and-claim as
  §3, with the same margin — 265 to 307 ms needed, 500 to 800 available — once
  per level (`exch.py flood` 7, `1 8 3 2 3 5 5`, 0.8 s between digits):

| digit | its last pulse | acted on by | next flood ready | next digit begins | margin |
|---|---|---|---|---|---|
| 1 | 1060 | the origin: not my district — seize | 1339 | 1860 | 521 ms |
| 8 | 2620 | the district's toll gateway: claim, patch into toll plane 8 | 2892 | 3420 | 528 ms |
| 3 | 3680 | area 83's gateway: claim, patch into its area | 3952 | 4480 | 528 ms |
| 2 | 4640 | district 2's gateway: claim, patch into its district | 4919 | 5440 | 521 ms |
| 3 | 5700 | exchange 23: claim | 5958 | 6500 | 542 ms |
| 5 5 | 8220 | exchange 23's register: line 55 | | | rings 133 ms later |

  At 0.5 s between digits every margin is still 221 ms or more.
- **A gateway is a monitor with a strap and a second trunk block**, nothing else:
  no store, no sender, no matrix. It holds two patched ports for the call.

**What it fixes, now:** area codes are `8x` and `9x` (16 if the second digit stays
octal) — they are compared, never addresses, so nothing in the fabric cares;
**anything outside the home district is dialled `1` + the whole number**, the home
area's code included, and a bare first digit 2–7 that is not the home district is
cannot-complete; the origin's register expects three more digits after the
district's and six after 1.

| if that is too much to fix | what it costs | what it buys |
|---|---|---|
| **A pulse delay** — the junctors listen to the caller's A through a shift register on the register card: 128 bits at 250 Hz, one CD4517-class part and half a '393, 0.5 s. A gateway needs 1.5 s, two parts | ≈ 2 packages, 0.5 s a level | **no digit is ever consumed**: every monitor hears the number exactly as dialled, area codes can be plain octal, a bare other-district digit works, and the race with the caller's finger is gone |
| **A register-sender** at the origin and at every gateway | ≈ 6–7 packages each (§8), a second '670 for seven digits, 0.5 s a level | the same, machine-paced, plus any dialling speed |

### 4.2 The ledger: what doing without a sender costs

Three different things were ruled out along the way, and they are not the same
decision:

| ruled out | why | still right? |
|---|---|---|
| memory parts in the exchange logic | the level of technology | yes — and a register-sender never needed one: it is '670s and counters |
| translators, route matrices, any knowledge of where things are | flood and claim makes them unnecessary | **yes. This is the design's best idea, and it does not depend on the sender either way**: a sender can speak into a flood as well as a caller can |
| storing and re-sending at every hop | 12–21 s across a chain, and a sender in every transit | yes — a transit stays two patched ports |
| **a sender at the origin** | ≈ 6–7 packages a register | **only for one district of dial phones** |

What the last one has cost, as it came out question by question:

| without a sender | with one at the origin (and at a gateway) |
|---|---|
| **every call floods**, local ones included, because the junctors must be up before the second digit: 0.19 E of pure signalling on each link of the four-exchange example | the origin knows a call is local before it seizes anything: 0.03 E |
| the flood must beat the caller's finger: 265–307 ms against his pause. `register.md` §3 accepted pauses of 250 ms | machine-paced: a guard the sender always keeps |
| **the numbering plan serves the signalling**: every exchange in a flood shares a first digit; area codes must begin 8 or 9; anything outside the district is `1` + the whole number; a bare other-district digit cannot be dialled | the number is heard whole, so it can be anything: plain octal area codes, any district dialled directly |
| every level of a long-distance call is another race with the finger | one re-origination a level, 0.5 s each |
| a monitor at every exchange is held at human speed, ~1 s a call | ~0.4 s, and only for calls that leave the exchange |
| **no keypad phone can ever place a network call**: a converter is a sender | any phone: the register converts |
| nothing | ≈ 7 packages × 2–3 registers an exchange, a second '670; post-dial delay 0.49 s instead of 0.13 s |

This is the pressure that took the telephone network from direct control to
register-senders, at the same points: numbering tied to trunking, common
equipment held at the speed of a finger, one kind of telephone. Small offices
lived with it for decades, and a single district of dial phones can too — there
the left column costs nothing that is wanted. **Past that, the sender is the
cheaper of the two.** The two do not mix inside one flood, because a monitor must
know whether the first digit it hears is the exchange digit or the first of the
whole number: that is one jumper on the monitor's compare, and it is worth
reserving now.

---

## 5. Why a transit chooses its own channel

The first version of the flood hard-wired channel *k* through every node, so a
call needed the same *k* free on every link while its origin chose *k* seeing
only its own. A scratch simulation — a chain of 8, 6 channels a link, uniform
traffic, 150 000 calls a cell, % blocked for all calls / calls of 4+ hops:

| offered, whole chain | a channel chosen at each hop | **the same *k*, chosen blind** | the same *k*, all-knowing |
|---|---|---|---|
| 0.5 E | 0.00 / 0.00 | **2.10 / 4.29** | 0.00 / 0.00 |
| 1 E | 0.00 / 0.00 | **4.14 / 8.21** | 0.00 / 0.01 |
| 2 E | 0.11 / 0.18 | **8.34 / 16.4** | 0.13 / 0.21 |
| 4 E | 2.21 / 3.60 | **16.1 / 31.0** | 2.61 / 4.62 |

The damage is the blind choice, not continuity. Since seizure comes before the
number, a transit can patch to any free onward channel with its ordinary fabric,
and blocking becomes the first column. Not in `exch.log`; `net` reproduces it.

---

## 6. Past the flood: districts, and areas

Flooding fails by load, not by logic: every call reaches every exchange in the
domain. Past 20–30 exchanges a domain is split, and **§4.1 is how domains are
joined** — a gateway is a monitor with a strap, and each level of the number is
claimed by the level that owns it. Nothing in an exchange changes when its
district gains a gateway.

---

## 7. Clocking

Plesiochronous, ±20 ppm crystals. Slips add per hop: one crossing measured
34.6 dB at 20 ppm, 33.2 at 100 and 20.7 at 1000 against the clean decode, the
codec itself 25.3 (`mf8-backplane.md` §7, under the codec law of that date).
±20 ppm is up to 40 between neighbours, so seven crossings are at most
280 ppm-equivalent: between the measured rows, expected above the codec, and for
`net` to score. **Voice and async oversampled data cross MF8; synchronous data
and G.711 pass inside an exchange and over ties, not across MF8.** The clock card
keeps a strap and a footprint to slave to a trunk's `RX_CLK` later.

---

## 8. Considered and set aside

**Serial characters on A — measured, and set aside as a second signalling
system.** Seized is mark; a character is a start bit, data bits, a stop bit.
**Measured** (`exch.py aline`): A as the trunk carries it — sampled once a
superframe, line errors on the S bit, `mf8-spec.md` §14's 2 ms RC and Schmitt
gate at every hop. Each hop shortens a space by **0.5 ms** and delays it by
**2 ms** (a 16 ms space arrives as 15.5, 14.5 and 12.5 ms after 1, 3 and 7
hops). Character errors in 4 000, three data bits, characters back to back:

| bit | four digits | 1 hop: clean / 1e−2 / 6e−2 | 3 hops | 7 hops |
|---|---|---|---|---|
| 2 ms | 40 ms | 1675 / 1683 / 2091 | — | — |
| 4 ms | 80 ms | **0 / 0** / 39 | 2291 / … | — |
| 8 ms | 160 ms | 0 / 0 / 0 | **0 / 0** / 5 | 0 / 2230 / 3127 |
| **16 ms** | **320 ms** | 0 / 0 / 0 | 0 / 0 / 0 | **0 / 0** / 8 |
| 32 ms | 640 ms | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 |

**16 ms a bit — sixteen ticks of the 1 kHz tick — crosses a chain of eight clean
at a line error rate of 1e−2**, where the trunk's framer is already in trouble.
A whole four-digit number takes the time of three dial pulses. With four data
bits at 16 ms: 0 / 0 / 0 over 7 hops, 384 ms.

| | 3 data bits | 4 data bits |
|---|---|---|
| Carries | octal: `e e`, `h`, `s` — and 0 in the *h* place, the operator | the register's own code: 0–9, `*`, `#` |
| Does not carry | **9**: another exchange's outside line would have to go as the otherwise meaningless *h* = 1, a translation at both ends | — |
| Character | 5 bits, 80 ms | 6 bits, 96 ms |
| Sender | the three AND gates of `exch-protocol.md` §5 first | **the store's word goes on the wire as it is** |
| Longest space, against the 204 ms release | 64 ms | 80 ms |

It is faster than pulses (0.32 s a number against about 2 s of sending) and its
monitor is smaller, but it is a second system to build and to debug, and it needs the
sender that live dialling does without. If the flood's load ever matters more than its simplicity, this
is the measured way to shorten it.

- **A pulse register-sender** — the origin repeats the number into the flood at
  20 pps, keeping pace with the caller (`exch.py flood` 1–4): post-dial delay
  0.49 s against 0.13 s live. Circuit: two '4017 from the 1 kHz tick for the
  50 ms period and its 30 / 20 split; a '193 loaded from the '670 and counted down
  a pulse at a time; half a '393 for 200 ms between digits, which is also the
  guard; the other half as the digit pointer; a '74 for run and phase; an '86 to
  compare the read pointer with the write pointer, so a digit goes as soon as it
  is in; a '00. **≈ 6–7 packages, all 74HC, no trim** — about two thirds of the
  register it sits beside. Set aside because inside a district nothing needs
  repeating (§4), and across districts §4.1 does without it.
- **An in-band DTMF sender** — the original plan: a tone generator and an encoder
  half in every register-sender, and every monitor a DTMF register. Replaced by
  the caller's own pulses: all digital, and indifferent to what `C` carries.
- **Hop-by-hop dialling** — a route code and a dial tone at every exchange: no
  network card, but numbers depend on where they are dialled from and a middle
  exchange needs the caller to name a link.
- **Direction jumpers** — eight a site, which arm each code lies on. Replaced by
  the claim level.
- **Hubs that finish** a call with a sender and a matrix code → link. Not needed
  once a fan-out resolves on the claim. If the flood ever costs too much this is
  the way back, **and as a line**: a dialler card, two ports back to back in bits,
  that takes a whole number and dials out of its second port like a subscriber.
- **Hard-wired pass-through** of channel *k*: §5.
- **64-slot 4.096 Mbps super-highways**: non-blocking to 512 ports, 74AC-class,
  and no fourth digit.

---

## 9. Not measured

- **Everything in §3.** Claims and fan-out resolution, a late monitor, a ring's
  NO-FORWARD strap, own code dialled from inside, `e e 9`, glare, a trunk down in
  mid-call, and the flood's real load on links and monitors against calling rate.
- **§4's and §4.1's timing as gates.** It is arithmetic on measured constants: the
  monitors' 128 ms rule, the claim and a gateway's patch are not simulated.
- **How fast people really dial.** The margins rest on 0.5–0.8 s between digits;
  `register.md` §3 tested its register down to 0.25 s, which would beat the flood.
- **The serial receiver as gates**; §8 is the waveform and an ideal mid-bit
  sampler on the 8 kHz mark.
- **Seven slips in a row**, at 20, 40 and 100 ppm.
- **The trunk card's external-clock strap**, and the block's clock crossing.
