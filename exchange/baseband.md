# The exchange — the baseband trunk card, and the block's card side

`network.md` §1.1 says a trunk is any port of class trunk that sends a
direction word, and lists among the carriers "a single-channel card, one trunk
over a pair or two". `protocol.md` §5 adds that such a card "may sit in any
slot and face any way". Neither says what is on the card or what it plugs into.

This document is both. **The baseband trunk is a tie trunk with nothing in
between**: `C` and A out, `C` and A in, four conductors, no line code, no framer,
no codec. It is the cheapest card in the exchange, and working out where it
plugs in turns out to be the larger half of the question — because the block's
card side, the thing every card plugs into, has never been written down.

The short answers, before the detail:

- **The card is interchangeable with a subscriber line card at the socket.** Same
  pins, one port, any slot. It uses no −48 V, no `RING` and no ±12 V.
- **The block's card side is not a bus.** Electrically it is a star: per-slot
  lines point to point, and only the clocks and the rails are common. Physically
  that star rides a **block ribbon** ending at the **block header**; the
  **slots** along it *are* the channel sockets (`fabric.md` §5.1). It is the
  MF8 channel slot of
  `mf8-backplane.md` §8, with the block standing where the MF8 trunk card stands.
- **A port circuit is fitted only with its card.** Shared block logic
  (commutators, highway drivers) is on the board behind the block header; the
  crosspoint and supervision come with the card at the slot.
- **What does not swap is the monitor.** A trunk on a block needs a monitor pool
  on that block, and a monitor is not a card.

> **Status: proposed. Nothing here is newly measured.** §3.2's same-clock case is
> `exch.py fabric` 8, already reported by `protocol.md` §4 as "a copper tie
> between two exchanges"; every other figure is cited from where it was measured.
> §3.2's octet phase across a tie **was measured on 2026-09-25** by a scratch
> bench of two exchanges on one clock (§3.2).
> §3.5's pin usage is an assignment, not a measurement — it is what the documents
> already imply, written out, against the socket `common-cards.md` §1 now holds. §6 is why
> an MF8 unit mates the **block header**, not `HC[h]` — reasoning against `verilog`,
> not a run. No circuit has been drawn.

---

## 1. What it is

```
   exchange 22, port 43                                       exchange 23, port 05
   port's C_RX  ─────▶ C out ═══════════════════════════▶ C in ─────▶ port's C_TX
   port's A_RX  ─────▶ A out ═══════════════════════════▶ A in ─────▶ port's A_TX
   port's C_TX ◀───── C in ◀═══════════════════════════ C out ◀─────  port's C_RX
   port's A_TX ◀───── A in ◀═══════════════════════════ A out ◀─────  port's A_RX
```

That is the whole of it, and it is `network.md` §1's tie trunk drawn with
the carrier deleted. What the near port hears from its fabric goes down the
wire; what comes back is what that port's card says. The card holds no digits,
counts nothing and decides nothing.

**There is no clock recovery here, and none is wanted.** The received `C` is one
bit a frame, changed at the far end's frame edge and held for the whole 15.6 µs
of it. Sampling that with the local frame clock is exactly the crossing
`mf8-backplane.md` §2 puts on an MF8 trunk card — two '174s there, half a '74
here — with the line code, the framer and the '259 all deleted because a
single-channel link has no frame to find. **The link is slow enough to be its own
eye.**

---

## 2. The block's card side

`protocol.md` §1 says "a port is what an MF8 channel slot already is";
`fabric.md` §5.1 is the packaging. This section is the electrical star and the
channel-socket pinout — whether a baseband trunk can sit where a line card sits.

### 2.1 It is a star on a block ribbon, not a bus

| | signals | how many |
|---|---|---|
| **point to point, slot *n* only** | `C_TX[n]`, `A_TX[n]`, `C_RX[n]`, `A_RX[n]`, the card word, `/ANS` (`a14` spare) | **6 a slot, 48 a block** |
| **common to all eight** | `TX_CLK`, `LOOP_HB`, `TX_OCT`, `RX_CLK`, `RX_OCT`, `FILL`, `MUTE` | 7 |
| **rails** | `+5 V`, `GND`, `±12 V`, `−48 V` and its return, `RING` and its return | |

Nothing on a slot is shared with another slot, nothing is bidirectional, nothing
is addressed and nothing contends. **No card on it knows where it is.** That is
`mf8-backplane.md` §3's "no slot-ID pins" and `mainboard.md` §1's "the cable
is common, the board is position-wired, and the card knows nothing", carried down
one more level — and it is the third time the same bargain is struck in this
design.

**Physically the star is a block ribbon** off the **block header** on the
shared board (`fabric.md` §5.1). The same connector family as §2.2's channel
socket; **slots** along the block ribbon *are* the channel sockets. Commons are
continuous; each slot takes that seat's six private lines. It is not a
multi-drop bus for the per-slot signals, and it is not eight sockets standing
on a flat mainboard of eighty packages.

The fastest thing on it is `LOOP_HB` at 128 kHz, against 1.024 MHz on the
mainboard. Electrically it is nothing: a short block ribbon, `mf8-backplane.md`
§8's rates, no termination.

So: **not a secondary bus.** The block's card side is the MF8 channel slot with
the block standing in the MF8 trunk card's seat. A block presents the same
channel socket as an MF8 shelf without a line — which is the reason
`terminal.md` works at all, and the reason a card built for one works unchanged
in the other. An MF8 *trunk*
group is a **block adapter** on the **block header** (`mf8-unit.md` §1); it does
not tap the highway. The **local eight-channel highway trunk** is another
**block adapter** on that header (`local-trunk.md`, `fabric.md` §5.2): eight
seats of copper in highway shape, where this card is one seat on a **slot** of the
block ribbon.

### 2.2 The channel socket

**The pinout has left this document.** `common-cards.md` §1 is now the single
table for the channel socket in an MF8 shelf and in an exchange block: what stood
here, with the direction of every pin, the drive rule, and a column for each
card in the set.
It is not repeated. Three readings this section made first, and that table
carries:

- a2 `LOOP_HB` is **derived at the block** — §2.3, and now `clocks.md` §4
- a7 `RX_CLK` **is** `TX_CLK` in an exchange (`fabric.md` §3.4)
- a11 `MUTE` is **tied to "locked"** at every socket, because a block has no link

Pin `a14` is spare. A secondary word on it (`groups.md`) is retired; this
card leaves it open.

The pull-ups on a12, a13 and a14 are at the port, not on the card
(`fabric.md` §3.5). **What this card does with each pin is §3.5.**

### 2.3 Four things the socket needs that no document supplies

- **`LOOP_HB`, 128 kHz, is not on cable A** — **closed, `clocks.md` §4** — and the
  CVSD subscriber line card cannot encode without it (`channel-cards.md` §2: differential Manchester at
  128 kBaud, `H` = `TX_CLK`, clocked by `LOOP_HB`). It needs no conductor.
  `SLOT[2:0]` counts the eight cells of a frame at 512 kHz, so **`/SLOT1` is a
  128 kHz square wave rising at the frame edge and at the half-frame, and
  `/SLOT2` is `TX_CLK`** — the half-bit clock is already on the cable, one bit
  down the same '163. One inverter a block, ⅙ of a '04, and its skew against
  `TX_CLK` is conductor to conductor within one ribbon, under 0.1 ns/m
  (`mainboard.md` §5.2). **Reasoning, not measured**: the phase wants
  scoping against `channel-cards.md` §2's encoder at bring-up.
- **`MUTE` has no driver in an exchange.** On an MF8 shelf the trunk card asserts
  it when the link is not locked (`mf8-spec.md` §13); a block has no link and no
  trunk card, so a11 is tied to "locked" at every socket. A card that reads it,
  such as the data card forcing `RXD` to 1, then simply never sees it.
- **`/HUNT_INH` is specified but lands nowhere.** `marker.md` §4 has it
  "pulled up on the backplane: a card may reject the port the probe is on and the
  hunt walks on", and `network.md` §3.2 has the network unit driving it at a
  port whose word faces the wrong way. It is not in `mainboard.md` §2.3's
  seven control signals and not in any pin list. A card that drives it needs a
  pin **and** a path back to the marker, which is a third
  `PB` line — the probe bus carries `BUSY` and the word and nothing else today.
  Nothing in `verilog` drives it. **a14 is spare** (the secondary word is
  retired), so `/HUNT_INH` could use it if built from a channel slot
  (`common-cards.md` §1). It is a loose end this document can only name.
- **The trunk socket is a different socket.** An MF8 trunk card is six ports in
  one (`extensions.md` §2.1) and needs 6 × `C_RX`, 6 × `A_RX` in and
  6 × `C_TX`, 6 × `A_TX`, 6 words, 6 `/ANS` out, plus `HCLK`, `LINE_HB` and
  `SLOT[2:0]` for its own frame mux and line encoder — none of which a channel
  socket carries. That is `mf8-backplane.md` §8's gateway slot, a 2 × 32, used
  the other way about. **The baseband card wants none of it**: one port, one bit
  a frame, `TX_CLK` and nothing faster. It fits the plain channel socket, and
  that is the whole of its case for interchangeability.

---

## 3. The card

### 3.1 The four conductors

| | | |
|---|---|---|
| `C` out | the port's `C_RX`, straight from its capture flip-flop | 64 kb/s NRZ, changing at the local frame edge |
| A out | the port's `A_RX`, which is E in the ring cadence while the port rings — and a trunk never rings, so it is E as it stands (`extensions.md` §2.3) | a level |
| `C` in | into the port's `C_TX`, through one flip-flop clocked at the local frame edge | |
| A in | into the port's `A_TX`, through an RC and a Schmitt gate | a level |

**A has a wire of its own, and that is the best thing about this card.** Every
other carrier in the design squeezes A into something: MF8 into the S bit, the
subscriber loop into held bit pairs in the `C` lane — which is why a data-class
loop has to give up its hook rule entirely (`subscriber-line.md`, and the data
class of `extensions.md` §2.2). Here it is a wire. `network.md` §1.1
allows about 2 ms of A path a hop and every break of 8 ms or more must survive;
MF8 spends 1.5–2.0 ms of delay and shortens a break by 0.5 ms a hop
(`channel-cards.md` §5). **A baseband hop spends the RC and nothing else.** Set the
RC short — tens of microseconds, against MF8's 2 ms — and dial pulses cross it
undistorted, which is what `monitor.md` §7 already says of a copper tie:
"a crossover with no A-path RC, so pulses arrive undistorted and a hop is a
frame".

### 3.2 Clocking: the jumper that decides what the link will carry

| jumper | what it is | what crosses |
|---|---|---|
| **two clocks — the network's case** | each exchange on its own ±20 ppm crystal, up to 40 between neighbours (`network.md` §8) | one slip every 390 ms at 40 ppm, 780 at 20 — the same event MF8 has, and `mf8-backplane.md` §7 measured it at 34.6 dB below the clean decode against the codec's own 25.3. Voice fine. Async oversampled to 9 600 fine. **Synchronous data no** |
| **one clock** | both exchanges on one clock card: two exchanges in one rack, and nothing else. Slaving a clock card to a trunk is set aside (`network.md` §9) | **bit-exact at a fixed delay**, two frames, one per fabric. Synchronous bit-oriented data (HDLC) passes. Measured: `exch.py fabric` 8, 0 errors. **G.711 does not**, because the octet phase is not the listener's (below) |

The card is the same either way; the jumper chooses whether the incoming flip-flop
is clocked by the local frame edge or by the far end's.

**The octet phase does not survive a tie, even on one clock** (measured
2026-09-25, two exchanges on one master clock, B's scan released 0–7 frames after
A's). Inside one exchange every pair is one frame late, so a listener framing on
`RX_OCT` (`TX_OCT` a frame late) is right. Across a tie a byte is two frames late
— one per fabric — while each end frames on its own `SCAN[2:0]`, which power-up
sets independently. The errors, A→B and B→A, measured **1 − φ and 1 + φ frames**
for B running φ frames behind A: they always sum to 2 mod 8, so no alignment of the
two counters makes both directions right. Carrying G.711 across would need the
octet marked on the link and re-framed on arrival: a spare pair and ≈ 3–4
packages a card. Set aside with the network's clocking (`network.md` §8, §9).

### 3.3 Link down, which is the one thing four wires cannot do

`network.md` §1.1 requires a carrier to "stop sending its word, so that its
port reads unequipped and is never hunted". The card generates the word locally,
so it must be told the far end is alive, and **four conductors cannot tell it.**
An idle link and a cut cable look the same: A = 0 either way, and with failsafe
receivers so does `C`.

Three ways out, and the middle one is the recommendation:

| | what | costs | verdict |
|---|---|---|---|
| **edge detection on `C`** | an idle far port has a cleared latch listening to port 00 and so carries `FILL`, `1010` at 32 kHz (`fabric.md` §3.3); "no edge for *n* frames" would be link down | ½ package | **no.** It is right for an idle link and for voice, and wrong for the one case that matters: a data call. HDLC idles at all ones, and a constant pattern across a live link would read as a cut cable and drop the call |
| **a fifth conductor each way, carrying `TX_CLK`** | a continuous 64 kHz square wave; absent for *n* frames is link down. Fail-safe: a pulled cable stops it | one conductor, one driver, one receiver, a retriggerable detector ≈ ½ package | **yes.** It is the smallest thing that is fail-safe, and it does two more jobs: it is the far end's bit clock for §3.2's incoming flip-flop, and it is the `RX_CLK` the clock card's existing jumper wants, which turns the pair synchronous and buys §3.2's top row |
| **a line code on `C`** | differential Manchester at 128 kBaud, the subscriber loop's own engine (`subscriber-line.md`) — DC-free, so the pair can be transformer-coupled, and carrier detect falls out of the decoder's violation term | ≈ 2–3 packages more, and `LOOP_HB` | the version for **between buildings**, where the isolation is worth more than the packages. Not the baseline |

**Four wires is still a usable link** where the run is short and inside one room:
what a cut cable then costs is that the trunk stays in the hunt, a caller is
switched to silence and hangs up — one call per attempt while it is broken,
against `network.md` §1.1's promise that a dead trunk is never hunted. That
is a choice to make knowingly, not a thing to discover.

### 3.4 Levels

Single-ended 74HC between two racks on separate grounds is the weak point, not
the bit rate. Two populations, as the data card has two (`channel-cards.md` §4.2):

- **In one rack, one ground:** 74HC with 33 Ω at the driver, as
  `mf8-backplane.md` §8 uses on 25 cm. Four conductors and a ground, or six with
  §3.3's clock.
- **Between racks:** V.11 / RS-422, 26LS31 and 26LS32 as the data card uses them.
  Six signals — `C`, A, clock each way — fit exactly one 26LS31 and one 26LS32,
  two packages, on three pairs each way.

### 3.5 The card's pins

Two connectors: the channel socket of `common-cards.md` §1, and its rear connector
there, §7.3, for the line. **The card uses eight of the fourteen signal pins and one
rail**, which is the lightest load on the socket of anything in the set.

| pin | | | what this card does with it |
|---|---|---|---|
| a1 | `TX_CLK` | in | **three jobs.** It re-times incoming `C` through the ½ '74 in the local-clock jumper of §3.2; it shifts the word's '165; and it is the waveform driven down §3.3's clock conductor, where that conductor is fitted |
| a2 | `LOOP_HB` | — | nothing on this card encodes a line |
| a3 | `TX_OCT` | in | loads the word's '165, so the sixteen bits repeat every `CLK_8K` |
| a4 | `FILL` | — | the port already idles to `FILL` through its own commutator input (`fabric.md` §3.3), and an idle far end sends it down the line. The card generates no idle pattern |
| a5 | `C_TX[n]` | **out** | incoming `C` off the line, re-timed: one bit a frame into the block's `C` commutator |
| a6 | `A_TX[n]` | **out** | incoming A off the line, through the RC and ¼ '14. This is M at the port |
| a7 | `RX_CLK` | — | see below: the card would like to *drive* this and cannot |
| a8 | `RX_OCT` | — | |
| a9 | `C_RX[n]` | in | straight out on the line, 64 kb/s NRZ, changing at the local frame edge |
| a10 | `A_RX[n]` | in | straight out on the line. E as it stands, since `/ANS` is low and a trunk never rings (§4) |
| a11 | `MUTE` | — | tied to "locked" at every socket in a block, and real only in an MF8 shelf. This card's link-down detector is its own, on a12 |
| a12 | card word | **out**, o.d. | class trunk, primary `11 01 0` with `g d d` in frames 5–7, secondary `FF`, from one '165 (`extensions.md` §2.2). Held off at power-up by the RC, **and gated by §3.3's link-down detector**, so a cut cable reads unequipped and the trunk leaves the hunt |
| a13 | `/ANS` | **out** | tied low on the board. No part |
| a14 | spare | — | open |
| a16, c2, c4, c6, c8, c11, c14, c16 | `GND` | in | |
| c1, c3 | `+5 V` | in | **the only rail.** No `±12 V`, no `−48 V`, no `RING`, nothing above 5 V anywhere on the card |

**The rear connector: six pins, or four.** `C`, A and §3.3's clock, each way.
In the 74HC population of §3.4 that is six conductors and a ground; in the
RS-422 population it is three pairs each way, twelve conductors, one 26LS31 and
one 26LS32. Four pins is §3.3's bottom row — the link with no clock conductor,
which is a usable link inside one room and is not fail-safe.

**a12 is where this card differs from every other card in the set.** The others
declare something fixed — a class, or a constant from a grounded pin — and
declare it for as long as they are seated. This one's word is conditional on a
wire outside the card, and that is the whole of `extensions.md` §2.2's "a
trunk card also gates that input with *link up*, so a dead link sends nothing and
is never hunted", on one channel instead of six. **The link-down detector is not
a feature of the line interface; it is the enable on the word.**

**a7, and why it no longer matters.** Slaving a clock card to this card's
recovered clock would need a wire from the rear connector to the clock card,
since a7 `RX_CLK` is an **input**, common to all eight slots. The network is
plesiochronous (`network.md` §8, decided 2026-09-25), so no such wire is wanted:
this card carries voice and async between exchanges on separate clocks, and
bit-exact data only between two exchanges on one clock card, where the clock is
already shared. The clock card's slaving footprint stays reserved and undesigned.

### 3.6 Parts

| | |
|---|---|
| line interface, RS-422 population | 26LS31 + 26LS32 = **2** |
| incoming `C`, re-timed | ½ 74HC74 |
| incoming A: RC, diode, Schmitt | ¼ 74HC14 |
| link-down detector (§3.3) | ½ 74HC123 |
| the word: one '165 from jumpers (class trunk, glare and direction in its options), into a 2N7002, held off at power-up by an RC (`extensions.md` §2.2) | ≈ 1 + FET |
| `/ANS` | tied low on the board: no part |
| | **≈ 3½** — 74HC population, **≈ 2** |

The data card is four packages without its word and `channel-cards.md` §4.4
calls it "the cheapest card in the shelf". This **beats** it, and in the 74HC
population beats it twice over — a trunk's direction and glare ride in the
primary octet, so one `'165` says everything.

---

## 4. Is it interchangeable with a subscriber line card?

**At the socket, yes.** Same 2 × 16, same six per-slot signals, one port, any
slot in any block. It draws `+5 V` only: no −48 V, no `RING`, no ±12 V, no ring
generator, nothing above 5 V anywhere on it.

What it says about itself is set on the card, as `extensions.md` §2 requires,
so **moving the card moves all of it**:

| | a plain line card | the baseband trunk card |
|---|---|---|
| the word (a12) | pin tied to ground: all ones, class line, no options | class trunk with glare and direction in its options, from one '165 |
| `/ANS` (a13) | open: the port rings in cadence and gives ringback | tied low: a trunk that rang would give its caller ringback the instant it was seized, and chop forward A in the cadence (`extensions.md` §2.3) |
| the port circuit | unchanged | unchanged — the same 5 packages of crosspoint and 3¼ of supervision |
| the block | unchanged | unchanged |

**What does not swap is on the block, not the card:**

- **A monitor pool.** `monitor.md` §4 puts monitors on each block that holds
  trunks, and its scanner already attends only slots whose word says trunk — so
  "a single-channel trunk among lines" is explicitly allowed, and a subscriber
  lifting a handset on the next slot is never read as a seizure. But a block with
  no monitor can never *own* a call arriving on that trunk. It still passes the
  flood on; it just cannot be the exchange the call is for. **Fitting this card
  in a block of lines silently changes what that block needs.**
- **A dialable number.** MF8 trunk groups live at 10–17 and further in
  blocks 2+, never dialled on a networked exchange because 1 is the flood key
  (`protocol.md` §5). A single-channel card in a line slot has a number a
  subscriber can dial. What the marker does when a dialled port's class is trunk
  is not written down in `marker.md` and is not in the `calls` model. It
  should be cannot-complete. **Unsettled, and a reason to prefer an undialable
  seat — 06–07 in the operator bank are free of that.**
- **The NO-FORWARD jumper is per link, and this card is exactly one link** — so
  the jumper of `network.md` §3.3, which must be set at both ends of
  one link, is one jumper on one card here, where on an MF8 card it is one
  jumper a direction on the network unit and does not sit in the shared word. A bypass link across a ring is the natural use of
  a single-channel trunk, and it is also where the jumper belongs.

---

## 5. What one channel is worth

`network.md` §1.1: one channel carries **0.01 E at 1 % blocking**, against
0.15 for two, 1.91 for six (MF8), and **3.13 for eight** on a local highway
trunk (`local-trunk.md`). Every network call floods every link for 1.2–1.7 s.
So:

- **It is not a route for an exchange's traffic.** It suits a few lines at the far
  end of a network, a bypass across a ring, or topping a six-channel direction up
  to seven — or, for a full short-range group, use `local-trunk.md` instead.
- **Glare is not a problem, for the reason that makes it useless for traffic.**
  The `g` bit tells one end to hunt the *last* free trunk facing a way
  (`network.md` §1); with one channel there is no last, so on a group of one
  it does nothing and should be left clear. Both ends seizing within the ~10 ms
  glare window, at 0.01 E, is of the order of once in decades — arithmetic from
  the offered load, not a run. Beside an MF8 card in the same direction the card
  must carry **the same `g` as its neighbour**, because the bit belongs to the
  direction and not to the card.
- **Its A path is the best in the design** (§3.1), so a chain that must carry dial
  pulses many hops is better off with baseband ties than MF8 ones wherever the
  distance allows.

---

## 6. Why an MF8 unit must not tap `HC[h]`

An older `mainboard.md` §2.4 said of an MF8 trunk card: "It taps its *own
block's* `HC[h]` and `HA[h]`, which are already its transmitter's multiplexed
frame."

**They are not.** `HC[h]` is the commutation of the block's eight `C_TX` —
what the trunk unit has just taken *off* the line — so a transmitter fed from it
would loop the link back on itself. A transmitter needs the six ports' `C_RX`,
which are private to each port and appear on no highway; `HA[h]` is wrong the
same way, carrying the far end's M where the transmitter needs each port's
`A_RX`. `network.md` §1's own drawing has it right, and so does
[mf8_trunk_card.v](../verilog/rtl/mf8_trunk_card.v), which takes `port_c_rx`
and `port_a_rx` in and drives `port_c_tx` and `port_a_tx` out.

That is why the exchange face is the **block header** (`fabric.md` §5.2,
`mf8-unit.md` §1): card-side appearances, not H. The likeness in `fabric.md`
§1.1 — commutator and frame mux are the same *kind* of part — is not an
identity with the pair.

The rest of `mainboard.md` §2.4 stands: the unit takes `HCLK`, `LINE_HB`,
`SLOT` and `TX_OCT` from the block, and the cable still has ten taps however
many trunks are fitted.

---

## 7. Not measured

- **§2 and §3.5.** The socket is `common-cards.md` §1's and is an assignment
  there; what this card does with each pin is read off §3's own description and
  not off a board. No connector, no bench. `LOOP_HB` as `/SLOT1` is arithmetic off
  the cell count and still wants a scope against `channel-cards.md` §2's encoder
  (`clocks.md` §7), even though the derivation itself is now settled.
- **`MUTE`'s polarity** at the socket, from `mf8-spec.md` §13, and whether any
  card in an exchange should ever see it asserted.
- **`/HUNT_INH`** (§2.3): specified in three documents, present in none of the
  signal lists, driven by nothing in `verilog`. Either it gets a pin, a third `PB`
  line and a card that uses it, or it goes.
- **The card.** Nothing drawn. The link-down detector's constant is unchosen; the
  A-lead RC is named as "tens of microseconds" and not worked. §3.5 makes the
  detector the enable on the word's 2N7002 gate, which is one FET and has not
  been drawn either.
- **A dialled port whose class is trunk** (§4). Not in `marker.md`, not in
  the `calls` model.
- **Glare on a group of one** (§5): arithmetic from the offered load, not a run
  of `exch.py net`, which has no single-channel trunk in it.
- **§6** is reasoning against `verilog` and `network.md` §1, not a run. What
  it corrects has never been built either way.
- **The two-clock case's sampling margin.** §1 argues that a bit held for a whole
  frame and sampled once a frame is its own eye, and that the crossing is
  `mf8-backplane.md` §2's; the metastability window at the moment the two frame
  edges coincide is not worked, and the slip rate is MF8's carried across.
