# The exchange — extensions: test lines, what a card says about its port, nailed-up connections and hotlines, traffic counters

Additions to the exchange. Each is a card, or a few jumpers on one. None
changes the fabric, and none needs a memory part. Test lines are features that
are lines, in the manner of `features.md`. **Whatever sits behind a port
says everything about it** (§2): one pin says whether it rings, and one serial
word says its class, its options, a trunk's direction, what it answers to, a
call nail, or a tied nail.
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
if it is a trunk, what it answers to, a call nail, or a tied nail. The block keeps no
per-port settings, so **move a card and all of it moves with the card.**

> **In the word** (`groups.md`): type `01` is *a plain line that answers to
> `h s`*, and a call that cannot be completed at the number dialled hunts for a
> port that answers to it. That replaces the run of adjacent `o` ports and class
> *operator*. Type `10` is a *call nail to `h s`*. Pin `a14` stays spare; the old
> secondary **pin** is retired (tagged secondary on `a12` remains).

### 2.1 The pins

The MF8 backplane reserved three pins of the channel slot's row *a* and connects
none of them (`mf8-backplane.md` §8). The exchange uses two:

| pin | on the MF8 shelf | in the exchange | at the port | on the card |
|---|---|---|---|---|
| a12 | not connected | **card word** (§2.2) | ~680 Ω pull-up: open reads "no word" | tied to ground on a plain line card; otherwise open-drain, **2N7002** |
| a13 | not connected | **`/ANS`** (§2.3) | a pull-up: open reads "rings" | tied to ground on a card that never rings |
| a14 | spare | spare | | |

MF8 reserved a12–a14 under the old names `TYPE0` / `TYPE1` / `RAI`; the live
names are **card word** and **`/ANS`** (`terms.md`). A card only ever pulls the
two pins to ground, and the MF8 shelf leaves them unconnected, so a card built
for the exchange works unchanged in an MF8 shelf.
Row *c* keeps all seven of its grounds.

- **A card** says it for its one port.
- **A trunk card** says it for each of its six channels: a word line and an
  `/ANS` line a channel (`network.md` §1, `terminal.md` §3). An MF8
  trunk card on a tie trunk sends one word to all six from two 74HC165
  daisy-chained, since its
  link goes one way, and ties all six `/ANS` lines low. A trunk card is six
  cards' worth of ports in one. **A single-channel trunk card is one port's
  worth**, and sits in any slot (`network.md` §1.1).
- **An empty slot** says nothing: unequipped, and nothing points at it.

### 2.2 The card word

One **16-bit** card word a port, shifted at **128 kHz** (`LOOP_HB` / a2 — the same rate
as `SCLK`), loaded every **`CLK_8K`**. The scanner still rests **one `CLK_8K`
period** (125 µs) per port, so sixteen bit-times fit the visit with no scan
slowdown (`marker.md` §3–4, `clocks.md` §1). The pin is low for a 1.
(`CLK_8K` is the exchange name for socket `TX_OCT` / a3 — an 8 kHz edge, not
an 8-bit word.) Bit-time *n* is `WORD[n]` (LSB first on the wire).

**Why this fits.** The probe's word and `BUSY` muxes are addressed by the
marker's named port (`DST[2:0]` in the serial control word), not by `SLOT`
(`fabric.md` §1). For the whole visit `PB` holds that card's pin steady, so the
marker may clock sixteen bits at 128 kHz. Highways stay on `SLOT`; only the
probe is scanner-addressed.

**Primary (0–7) is enough for a one-chip card.** The second `'165` is optional;
when unfitted, strap the daisy-chain so bits 8–15 read all ones (`FF`). Tie
trunks always fit both chips (one shared word for all six channels).

```
bit-time      01  234  567  89  101112  131415
field         tt  aaa  bbb  TT  ppp     ppp

CONSTANTS
plain         11  111  111  11  111     111
none/OOS      00  000  000  00  000     000

PORT FORMS  (secondary idle = FF)
tied nail     00  hhh  sss  11  111     111
answers-to    01  hhh  sss  11  111     111
call nail     10  hhh  sss  11  111     111   local only

CLASS FORMS  type=11, class ccc in 2–4, options ppp in 5–7
unequip       11  000  ---  ..  ...     ...   (not sent)
line          11  001  Pb0  11  111     111   idle sec
operator      11  010  0b0  11  111     111
source        11  011  000  11  111     111
outside       11  100  000  11  111     111
trunk         11  101  000  10  ddg     000   sec required
data          11  110  0b0  11  111     111
restricted    11  111  zb0  11  111     111   ¬z → local floor

SECONDARY EXTENSIONS  (tag ≠ 11; only listed pairs)
class+cover   11  ccc  ppp  01  hhh     sss   not trunk
ans+alias     01  hhh  sss  01  hhh     sss   second local answers-to
ans field A   01  hhh  sss  00  000     000   reserved layout; ignored (§2.2.1)
ans field B   01  hhh  sss  10  LUK     000   hunt-condition flags (§2.2.1)
              01  hhh  sss  10  111     111   field B, no feature
net nail      10  hhh  sss  00  eee     bbb   RESERVED/OOS

any other tag×primary / MBZ=1 / tag11∧payload≠111111  →  OOS

LEGEND
  tt          type (0–1): 00 tied nail · 01 answers-to · 10 call nail · 11 class
  aaa / bbb   primary (2–7): port hhhsss, or class ccc + options ppp
  TT          secondary tag (8–9) — one tag a word (field A XOR field B)
  ppp ppp     secondary payload (10–15); meaning from (type × TT)
  hhh sss     local port (hundreds / units, octal)
  eee bbb     remote exchange (network nail; reserved)
  ccc         class code (see CLASS FORMS)
  ppp         primary options, or payload octal triplets
  P           priority (line)
  b           busy-out / busy-inbound
  z           0-only (restricted); clear → local-only floor
  ddg         trunk direction (dd=N/E/S/W) + glare; ttt MBZ 0
  LUK         field B: local-only / unequipped-owner / busy-owner (§2.2.1)
  0           must-be-zero (MBZ); a 1 → OOS
  FF          secondary 11 111 111 — no extension / unfitted chip
  --- / ..    unused / not sent
```

| bit-times | meaning |
|---|---|
| **0–1** | type: `00` tied nail · `01` answers-to · `10` call nail · `11` class |
| **2–7** | local `h h h s s s`, or class `c c c` + options `p p p` |
| **8–9** | **secondary tag** |
| **10–15** | **secondary payload** (meaning from the tag) |

#### Primary options `p p p` (bit-times 5–7)

| class `c c c` | | options (5–7) |
|---|---|---|
| 000 | unequipped | — |
| 001 | line | `P b **0**` — priority, busy-out; bit 7 **MBZ 0** |
| 010 | operator | `0 b 0` |
| 011 | source | `000` MBZ |
| 100 | outside line | `000` MBZ |
| 101 | tie trunk | `000` MBZ — direction and glare only in the secondary |
| 110 | data line | `0 b 0` |
| 111 | restricted | `z b **0**` — bit 7 **must be 0**; if ¬z, floor as local-only (§2.4) |

Shared frames: bit 6 is busy-out / busy-inbound on every class that uses `b`; bit 5 is
priority on a line and `z` on restricted. **Must-be-zero bits are decoder-enforced:**
a 1 where MBZ is required → out of service, not a soft ignore.

#### Secondary tag (8–9) and payload (10–15)

Unfitted / unused secondary → **`FF`** (tag `11`, payload all ones). Tag `11` with
any other payload → OOS. Never treat bare ones in 10–15 as exchange/port `77`.

**One tag a word.** Fields A and B are alternate encodings of bits 8–9, not two
payloads on one card. A word carries A **or** B **or** alias/cover **or** `FF` —
never A and B together. Do not pack `e b h s` across two tags; the only 12-bit
remote form is primary `h s` plus one 6-bit payload, and that is the **network
nail** (call nail + tag `00` + `eee bbb`), not answers-to.

Decode keys on the **(primary type × tag)** pair, not the tag alone.

| tag 8–9 | valid with | payload 10–15 | |
|---|---|---|---|
| `11` | any primary | must be `111111` | no extension |
| `00` | call nail `10` only | `e e e b b b` | **reserved / OOS until a dialler exists** — then dest = `1` + that + primary `h s`. Must not fall back to local |
| `00` | **answers-to `01`** | must be `000000` | **field A** — layout reserved as `eee bbb`; marker ignores; any non-zero → OOS (§2.2.1) |
| `01` | class, not trunk | `h h h s s s` | secondary answers-to / cover beside class+options |
| `01` | **answers-to `01`** | `h h h s s s` | **second local answers-to** (dual membership) |
| `10` | trunk class `101` | `d d g 0 0 0` | direction N/E/S/W, glare; `ttt` **MBZ 0**. Trunks always fit this chip |
| `10` | **answers-to `01`** | `L U K 0 0 0` or `111111` | **field B** hunt-condition flags, or no feature (§2.2.1) |
| other pairings | | | **OOS** (fail closed) |

##### 2.2.1 Answers-to secondary: field A, field B, dual membership

| | form | marker |
|---|---|---|
| **Idle** | secondary `FF` | answers to primary `h s` only |
| **Dual membership** | tag `01`, payload second `h s` | hunt matches **either** primary or payload. One phone in two local groups (e.g. covers two desks). Prefer this over burning field A |
| **Field A** | tag `00`, payload **`000000` only** | accepted; **no action**. Layout staked as `eee bbb` so tag `00` means the same bit shape as a network nail; action stays on call-nail when a sender exists. Non-zero payload → OOS (fail closed). Not a remote dest, not cover, not overflow |
| **Field B** | tag `10`, payload `L U K 000` or `111111` | qualifies when this member may be taken (§ below). `111111` = no feature (unconditional). `U`∧`K` both set → OOS. Any other pattern → OOS |

**Field B flags** (bit-times 10–15 = `L U K 0 0 0`):

| bit | | the marker, on an answers-to hunt |
|---|---|---|
| `L` | **local callers only** | skip this member when the caller is a claimed trunk (`ctx_clm`) — desk overflow for internal calls, not network |
| `U` | **unequipped owner only** | take only when the dialled/pilot port failed the probe as unequipped / OOS / empty — night service (announcement when 04 is switched out), not when it is merely busy |
| `K` | **busy owner only** | take only when that port failed as busy / busy-out / already held — cover while the owner is in a call |
| `000` | **MBZ** | must be 0 |

Unconditional members (`FF`, dual without B, field B `111111`, or `LUK` all clear) stay eligible for every hunt reason. `L` may combine with `U` or `K`. Class options (`P`, `b`, `z`) stay on **class+cover** (tag `01` beside class) — not in field B.

**What these bits do not buy.** Remote cover, roaming, multi-exchange hunt, overflow to `1 e b h s`, call waiting, transfer, camp-on, distinctive ring, hunt rank, or a conference LEG mark: the marker leaves after two latch writes, latches name one local port, and the flood has no sender (`groups.md` §2.6, §3.4). Hop-by-hop nails and dialling-card hotlines remain the network paths.

The no-forward strap stays on the network unit, one jumper a compass direction
(`network.md` §3.3) — not in the word (six channels share one word).

#### Whole-word constants and decode order

| word | meaning |
|---|---|
| all ones | plain line (grounded pin) |
| all zeros | no word / OOS / link down |
| primary OK + secondary `FF` | no extension |
| bad primary/tag/MBZ | OOS — no hunt, nail, or seizure side-effect |

Decode: (1) all ones → plain line; (2) all zeros → none; (3) primary; (4) if
secondary ≠ `FF`, accept only a listed tag×primary pair with MBZ payload bits
clear; else OOS.

**Incremental fit:** (1) primary-only cards, secondary strapped `FF`; (2) tag
`01` class+cover, and answers-to + tag `01` dual membership; (3) trunks tag
`10` + `ddg000`; (4) tag `00` network nails only with a sender; (5) answers-to
field A (zeros only) and field B (`LUK000` / `111111`) — members that stayed on
`FF` are untouched.

Three 6-bit port forms plus class-and-options do not fit beside four option bits
in the primary, so class has **three**. Tied nail to 00 collides with all zeros
(unequipped) — and 00 is never a line. Answers-to 77, call nail to 77 and **tied
nail to 77** are free as primary destinations.

- **A plain line card carries no part and no jumper for this.** Its word pin is
  tied to ground, which reads all ones, and that means a line with no options.
  Plain lines are most of an exchange. Only a card with something more to say
  carries the word's parts.
- **The word's parts**: two 74HC165 (daisy-chained) loaded from jumpers on
  `CLK_8K` (`TX_OCT` / a3) and shifted on **`LOOP_HB` (a2, 128 kHz)**, into a
  **2N7002** (gate from the serial output, held off at power-up by an RC of about
  100 ms): **≈ 2 packages + FET**. Primary chip alone + strap to ones on the
  chain input is a complete simple card; the second chip is the optional
  extension. A line card has the footprint. The port's pull-up is **~680 Ω**.
  `LOOP_HB` is already on the socket for the CVSD encoder; a word card that is
  not a CVSD line still takes a2 for the shift clock.
- **Held off at power-up.** The FET gate stays low through the RC until the
  '165s are loading properly. Without
  this a random word is a tied nail, a call nail or an answers-to about three times in
  four. A trunk card also gates that enable with "link up", so a dead link sends
  nothing and is never hunted. A trunk whose secondary is missing or not tag `10`
  is unequipped (not hunted).
- **A tied-nail port sends no class.** It is never hunted, dialled or a call
  request (§3.1), so the marker never needs one. Whether it rings is `/ANS`.
  The dest of a one-sided tied nail keeps whatever word it already had.
- **Out of service** is no word at all: a switch in the FET gate, or the
  ground link opened on a plain card. The port reads unequipped. A call to it
  gets cannot-complete and its lifting is ignored. On a trunk card, a switch a
  channel takes one channel out of the hunt.
- **The tone cards at 01–03 need no word.** The marker reaches them by
  address and never reads their class (`fabric.md` §3.5).
- **The block**: a fourth '151 commutates the eight word pins onto the probe bus
  beside `BUSY`, **addressed by `DST[2:0]` of the serial control word** (the port
  the marker named), not by `SLOT`. **The marker**: two 74HC164 take the word in
  at 128 kHz over the visit, a 74HC30 finds all ones, and a few gates read type
  from bit-times 0–1 and the secondary tag from 8–9.
- **What is given up.** A word pin shorted to ground reads as a free line.
  Probing a dialled port out of turn still costs up to one `CLK_8K` period
  (125 µs) to collect sixteen bits, waiting for the visit to fill.

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
same frame on every class that uses them (§2.2). There are **three**, in frames
5–7: class took frames 2–4, and the fourth option bit was spent on the two type
bits that name a 6-bit port.

#### Line (`001`)

| frame | bit | | the marker |
|---|---|---|---|
| 5 | `P` | **priority** | under register overload, a `P` line is given the next free register before a non-`P` line that is already waiting (§2.4.1) |
| 6 | `b` | **busy-out** (DND as busy) | on a **terminating** call, the port is **not free** — same path as `BUSY` set: the caller hears **busy** tone. **Lifting still gets a register and dial tone**; outbound is unchanged. Against out of service (§2.2): OOS is unequipped both ways (lift ignored). Against a latch make-busy (`console.md` §4): this mark is in the word and survives hang-up. Same bit and test as restricted *busy-inbound* |
| 7 | `0` | **MBZ** | must read 0; a 1 → OOS (§2.2). Reserved for a future primary feature |

**Why busy, not cannot-complete.** Cannot-complete (fast busy / reorder) means the
number cannot be completed — empty slot, wrong digit, restricted dialling.
Busy-out means “this phone is not taking calls,” which is what a busy line
already says. Distinctive DND tone would be a second source and a second marker
steer; not worth it.

**Overflow `o` is retired** (`groups.md`). A hunt group is a port that *answers
to* the number people dial, not a run of adjacent ports.

**Warm is not an option.** A courtesy / lift / help phone is a **call nail**
(§2.2): on lift, connect as if dialled `h s`, with no register. Call nail to 04
is the operator, and holds nothing while idle. Against a tied nail (§3.1): a
tied nail rings one fixed phone and holds two latches for good.

#### Restricted (`111`)

Class *restricted* is a lobby or public phone: the same free test and ringing as
a line. The class itself is unsafe to miss — a jumper the user cannot clear — so
dialling limits live in the options, not in clearing the class. Conference
bridge legs remain class *line* with `/ANS` low (`conference.md` §6).

| frame | bit | | the marker |
|---|---|---|---|
| 5 | `z` | **0-only** | only digit **0** completes (pilot 04, then answers-to). Any other first key → cannot-complete |
| 6 | `b` | **busy-inbound** | same terminating not-free / busy path as a line's busy-out. Lift and outbound unchanged |
| 7 | `0` | **MBZ** | must read 0; a 1 → OOS (would otherwise collide with all-ones plain line when secondary is `FF`) |

**Floor.** If `z` is clear, the marker treats the caller as **local-only** — a bare
restricted card never opens a flood (**9** and networked **1** → cannot-complete).
Campus-only and CO-ok profiles are not used. Option `L` is **retired**; the floor
replaces it. A help point that may only reach the operator is **call nail to 04**:
it never gets a register, so `z` is not needed on that path.

`z b` both set with bit 7 clear is offered. `z b 1` is OOS, not a plain line.

A data line (class 110) is a line the marker will not connect to a voice port,
and the reverse: the mismatch `channel-cards.md` §1 warns is "loud, locked, not
squelched". The check is made where both classes can be read, which is inside
one exchange. A call from another exchange arrives on a trunk.

#### 2.4.1 Priority under register overload

One flip-flop, `PWAIT`. A scan that finds a `P` line wanting a register and not
getting one sets it at port 77. While it is set, a non-`P` line does not take a
free register even if one is idle; a `P` line still does. A scan that finds no
`P` line still waiting clears it, and the next non-`P` waiter is served. A
single line lifting into an idle exchange is never delayed: `PWAIT` is clear
until a priority lift has been refused. `make priority`.

---

## 3. Nailed-up connections and hotlines

A connection that stays when both ends hang up: a ringdown hotline between two
phones, a private wire, a permanent data circuit. Two ports facing each other
are already a hotline (`channel-cards.md` §1), where either lifting rings the other
and both lifted is a call. What the exchange lacks is a way to keep the pair
after release, because the release clears both latches. A nailed-up
connection is `mvp.md` §6's bring-up step 3 made permanent, and brought up
by the scanner from jumpers on the two cards.

### 3.1 The tied-nail word

One card holds the dest port in jumpers and sends it as its word (§2.2) in place
of its class. Type `00`, dest in frames 2–7; all zeros is excepted (an empty
slot, so **tied nail to 00 is the missing code** — and 00 is never a line).

| | |
|---|---|
| **The card** | the word's parts (§2.2), with the dest in the jumpers. A plain line card to be nailed has them fitted, and its ground link opened |
| **The marker** | type `00` and not all zeros. An empty slot reads all zeros and a plain line all ones, and neither is a tied nail |
| **The rule** | checked at each port before any other: **a tied nail and `BUSY` clear → write this port to the dest and the dest to this port, both with `BUSY` set.** One visit, two writes. A port that sends a tied nail is never free, never hunted, never connected by a dialled number, and its lifting is never a call request or a seizure |
| **The dest** | keeps whatever word it already had — a class, an answers-to, a call nail. While the tied nail holds it is `BUSY`. Do **not** nail a source: the second write would `BUSY` the radio, and a source is never written (`features.md` §6). A radio or a clock is class *source*; listeners dial it |
| **Release** | nothing stops it. When the pair's call ends, the release detectors clear both latches as on any call (`marker.md` §5), and within one scan, 8 ms, the scanner writes both back. The dest is free in that gap. The port circuit is unchanged |
| **After `/RESET`, or a card plugged in** | the first scan writes every nail, within 8 ms. The nailing cards are the only record, and nothing else is needed |
| **One end is enough** | for two phones, or a phone onto a line. A trunk on a hop-by-hop path still sends a nail of its own (§3.3), so it is never a trunk to the flood or the monitor |
| **The console** | can still point two latches at each other by hand, as bring-up step 3 does — one key, two crossed words in one tenure (`console.md` §1, §6). **It rings nothing**: with both phones on hook the pair is held by nothing, so an operator rings each end from a source first and pairs them once both have answered. It is a call, and it clears when it is released; nothing remembers it, which is the whole difference from a nail |
| **Counters** | a nail's writes are not calls (§4) |

The tied-nail word replaces a nail card that wrote nails from a diode matrix: a '161,
a '138 and up to 88 diodes for four connections at most. There is no limit on
the number of nails, and changing a local pair is one card's jumpers.

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

A tied-nail word names a port of its own exchange, because a latch can name nothing
else (`protocol.md` §3). A channel held end to end across exchanges is
nailed at every exchange on the way, each exchange nailing its own pair:

```
 exchange 22      phone A ↔ trunk channel toward 23            A's card names the channel, or the channel names A
 exchange 23      channel from 22 ↔ channel toward 24          one of the two channels names the other
 exchange 24      channel from 23 ↔ phone B                    B's card names the channel, or the channel names B
```

A trunk that is a dest and keeps its class is still a trunk to the monitor and
the flood in the 8 ms after release. **Nail the trunk end too** — each names the
other, two one-sided nails — so neither looks like a trunk.

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
| **Dialling** | breaks on its own `A_TX` while the phone stays off-hook: 10 pps, 60/40, 0.7 s between digits, all from `CLK_8K`. These are the windows the register, the flood and the monitors were measured at: the flood is ready 258 ms after the first digit, and the monitors' rules held at 10 pps ± 10 % (`network.md` §4, `monitor.md` §5). The phone hanging up stops it |
| **Then** | an ordinary call. The flood opens on `1`, the owner claims on `e b`, the far phone rings, and ringback comes in band. Answer across the network is seen at claim (`network.md` §3) |
| **Time** | 0.8–3.2 s of pulses and 2.8 s of pauses for five digits: **about 4–6 s from dial tone to the far port being rung**, then the cadence's own 0–4 s to the first ring |
| **Both ways** | a dialling card at each end, each naming the other. Both lifting at once find each other busy and get cannot-complete |
| **Held while idle** | nothing: no channel, no latch, no register |
| **Parts** | the 10 ms step from `CLK_8K` ('4040 and a gate); the 100 ms pulse and its 60 % break ('4017 and a NOR); the pulse count ('193, loaded through 2 × '153 from the jumpers of `e b h s`; the key `1` is wired, as the count the digit pointer's first state loads, and a jumper skips it for a local number); the digit pointer and the pause ('393); the idle-pattern detector and control ('86, '74): **≈ 8 packages**, fitted only on a hotline card |

A phone that dials a stored number when it is lifted does the same with no card
at all. The number may also be `h s` of the card's own exchange: a hotline that
holds nothing while idle. A **call nail** (§2.2) does that dest with no dialler:
on lift, connect as if dialled `h s`. A **tied nail** rings faster and holds two
latches.

A tester who wants to **drive a register and the flood without a handset** is
the same live A with the number keyed rather than jumpered: `pulse-gen.md`.

### 3.5 Which to use

| | tied nail (§3.1) | nailed hop by hop (§3.3) | a card that dials (§3.4) |
|---|---|---|---|
| reaches | its own exchange | another exchange, by a fixed path | anywhere in the network |
| named by | the dest port, on one card | a dest at each exchange; a trunk dest sends a nail too | the number, on one card |
| the far end rings | at the lift | at the lift | 4–6 s after dial tone |
| the far end lifting rings the near end | yes | yes | only with a dialling card there too |
| answer seen | yes | yes | at claim |
| holds while idle | two latches | a channel on every link crossed | nothing |
| parts | ≈ 2 + FET a card | ≈ 2 + FET a card or channel, at every exchange on the path | ≈ 8 a card |

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
| the card word and `/ANS` | nothing on a plain line card; ≈ 2 + FET on any other; two ~680 Ω pull-ups a port; ≈ 3 at the marker | the cards, the block, the marker |
| lines that answer at once | `/ANS` tied low on the card | the card |
| restricted lines, hunt groups, call nail, busy-out | class *restricted* with `z b 0` (local floor if ¬z); line `P b 0`; call nail a 6-bit form; shared frame 6 for `b`; secondary tagged per §2.2 (dual membership, field A zeros-only, field B `LUK`) | the cards, the marker |
| nailed-up connections | one card's word, two writes | the nailing card |
| nailed hop by hop | a nail on each trunk that must not look like a trunk | trunk cards |
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
- **The word as gates**: the 2×'165 load against `CLK_8K`, the probe's capture
  in the scanned port's cell, the all-ones detector, the power-up hold-off, and
  a plain card's ground link against a fault that reads the same.
- **`/ANS` alone forming `ON`**, drawn.
- **The line options in the marker**: restricted `z` (0-only) with local-only
  floor if ¬z; priority `P` on frame 5; call nail on type `10`; busy `b` on
  shared frame 6; secondary tag/payload per §2.2 including dual membership
  (answers-to + tag `01`), field A zeros-only, and field B `LUK`. `make word`,
  `make priority`, `make groups`.
- **The nail rule**: one-sided two-write, its place ahead of the call-request
  rule, and the 8 ms after a release in which the dest is idle. `make word`.
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
