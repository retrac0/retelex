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
> port that answers to it. That **retires** the run of adjacent `o` ports and
> class *operator*, whose code is now the word's spare. Type `10` is a *call
> nail to `h s`*. Pin `a14` stays spare; the old secondary **pin** is retired
> (tagged secondary on `a12` remains).
>
> **A trunk says all of itself in the primary octet** — class, glare, direction
> — so it is a one-`'165` card and its secondary is `FF` (§2.2). A **data line**
> is a line with option `D`, not a class; the freed code is the *tone trunk*,
> the offers-tone seat of `leaf-uplink.md` §3.

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
  trunk card on a tie trunk sends one word to all six from a single
  74HC165, since its link goes one way, and ties all six `/ANS` lines low. A trunk card is six
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

**Why this fits.** The probe's word and `BUSY` muxes are addressed by
**`SCAN[2:0]`** — the scanner's own low three bits, carried on cable B
(`mainboard.md` §2.3.3) — not by `SLOT` (`fabric.md` §1). For the whole visit
`PB` holds that card's pin steady, so the marker may clock sixteen bits at
128 kHz. Highways stay on `SLOT`; only the probe is scanner-addressed. It could
not have been a field in the word: a sixteen-bit word at 128 kHz is 125 µs and
so is a visit, so steering by word would saturate the bus and leave no room for
a write. Under `/CON` the console does steer by word, because an operator aims
the probe by hand a few times a minute.

**One chip is enough for most cards, and the word is sixteen bits either way.** The
primary — bit-times 0–7 — carries a whole class with its options, or a whole 6-bit
port. The second `'165` is optional; where it is unfitted the daisy-chain is strapped
so bits 8–15 read all ones. **That strap is not an absence: it is the value `FF`**, and
the marker reads sixteen bits from every card there is. So the tables below print every
form in full, top byte and all, and a card with nothing more to say is one whose top
byte is `FF` — not one whose word is short. **A tie trunk is such a card**: its
direction and glare are primary options.

**Everything below is printed in wire order, and every field goes LSB first, as the
word does.** Bit-time 0 is leftmost, so what the page shows is the order the `'165`
shifts out and the order a reader of the first few bits sees. A two-digit number
therefore appears **second digit first, each digit's low bit first**: a port is
`s s s h h h`. The RTL reads the same six bits together as `WORD[7:2]`, which is `h s`
as a number — the same bits, named the other way round. Earlier drafts printed the
numeric fields reversed and the flag fields this way; jumpers cut from those tables
have the two digits swapped.

```
bit-time      01  234  567  89  101112  131415
class form    tt  aam  ppp  TT  qqq     qqq
port form     tt  sss  hhh  TT  qqq     qqq

CONSTANTS
plain line    11  111  111  11  111     111     a grounded pin, and no part fitted
none / OOS    00  000  000  00  000     000     no card, held off, or link down

PORT FORMS
tied nail     00  sss  hhh  11  111     111     dest h s; to 00 is the missing code
answers-to    01  sss  hhh  11  111     111     the number this port answers to
call nail     10  sss  hhh  11  111     111     on lift, connect as if dialled h s

CLASS FORMS  tt = 11; family aa at 2–3, member m at 4, options at 5–7
unequipped    11  00 0  ---  --  ---     ---    never sent
reserved      11  00 1  ···  ··  ···     ···    the spare code → OOS whatever follows
source        11  10 0  000  11  111     111
outside line  11  10 1  000  11  111     111
trunk         11  01 0  gdd  11  111     111    flood seat: glare, then direction
tone trunk    11  01 1  000  11  111     111    offers-tone seat (leaf-uplink.md)
line          11  11 0  PbD  11  111     111    priority, busy-out, data
restricted    11  11 1  zb0  11  111     111    frame 7 MBZ — it holds the carve-out

SECONDARY    a top byte other than FF, where a card has more to say.
             These pairings and no others; every one not listed → OOS
cover         11  aam  ppp  01  sss     hhh     a class, not the trunk family
dual member   01  sss  hhh  01  sss     hhh     answers to either number
conditions    01  sss  hhh  10  LUK     000     or 111111 for none (§2.2.1)
network nail  10  SSS  HHH  00  bbb     eee     on lift, dial 1 e b h s  RESERVED
netwide fwd   01  SSS  HHH  00  bbb     eee     calls here go to 1 e b h s  RESERVED
class flags   11  aam  ppp  10  ···     ···     the last unspent space  RESERVED

LEGEND
  tt          type (0–1), as PORT FORMS and CLASS FORMS above
  aa m        class family (2–3) and member (4)
  ppp         primary options (5–7); which bits they are comes from the class
  TT          secondary tag (8–9): 11 nothing · 01 a local port · 10 flags ·
              00 an exchange code, which makes the primary's port remote
  qqq qqq     secondary payload (10–15).  The tag says what it is, the type
              whose it is
  sss hhh     a local port: units digit, then hundreds, each digit LSB first
  SSS HHH     the same six bits, but a port at the exchange the payload names —
              the two reserved forms only.  This port's own number is its slot
  bbb eee     an exchange code, second digit then first, the same way round
  P b D       line: priority · busy-out · data line
  z b 0       restricted: 0-only · busy-inbound · MBZ, which holds the carve-out
  g dd        trunk: glare, then direction N/E/S/W (its low bit at frame 6)
  LUK         conditions: local-only · unequipped-owner · busy-owner (§2.2.1)
  0           must-be-zero; a 1 → OOS, not a soft ignore
  11 111 111  FF, the top byte of a card with nothing more to say.  An unfitted
              second '165 is strapped to ones and reads exactly this, so every
              word is sixteen bits and every form above is printed in full:
              there is no such thing as a short word on the wire
  RESERVED    the shape is settled and the decoder fails it closed: OOS until a
              sender exists (§2.2, "the two reserved forms")
  ··· / ---   any / not sent
```

**The encoding, whole.** A tied nail, an answers-to and a call nail are forms of the
word exactly as a class is, and belong in one table with them:

| bit-times 0–3 | the form | bit-times 4–7 | `WORD[4:2]` |
|---|---|---|---|
| `00 · ·` | **tied nail** | dest `h s` across 2–7 | — |
| `01 · ·` | **answers-to** | the number `h s` across 2–7 | — |
| `10 · ·` | **call nail** | dest `h s` across 2–7 | — |
| `1100` | **unequipped** (`m`=0) · **reserved** (`m`=1) | not sent · OOS | 0 · 4 |
| `1110` | **source** (`m`=0) · **outside line** (`m`=1) | `000` MBZ | 1 · 5 |
| `1101` | **trunk** (`m`=0) · **tone trunk** (`m`=1) | `g d d` · `000` MBZ | 2 · 6 |
| `1111` | **line** (`m`=0) · **restricted** (`m`=1) | `P b D` · `z b 0` | 3 · 7 |

| bit-times | meaning |
|---|---|
| **0–1** | type: `00` tied nail · `01` answers-to · `10` call nail · `11` class |
| **2–7** | local `s s s h h h`, or family `a a` + member `m` + options `p p p` |
| **8–9** | **secondary tag** |
| **10–15** | **secondary payload** (meaning from the tag) |

**All ones is inside the subscriber family, and that is deliberate.** A plain line card
has no word parts at all: its pin is tied to ground and reads sixteen ones, which the
family bits make an ordinary subscriber line before anything else is decoded. The one
class that can put ones in bit-times 2–4 is *restricted*, and its frame 7 is must-be-zero,
so **no legal class word can read all ones** and the constant stays unambiguous.
Restricted's MBZ is the whole of that guarantee.

#### Primary options `p p p` (bit-times 5–7)

| family · member | class | options 5–7 |
|---|---|---|
| `00` · 0 | unequipped | — (never sent) |
| `00` · 1 | reserved | — (any word → OOS) |
| `10` · 0 | source | `000` MBZ |
| `10` · 1 | outside line | `000` MBZ |
| `01` · 0 | tie trunk | `g d d` — glare, then direction (its low bit at frame 6) |
| `01` · 1 | tone trunk | `000` MBZ. Offers tone on seize; never a flood seat, so it carries no direction and no glare |
| `11` · 0 | line | `P b D` — priority, busy-out, **data line** |
| `11` · 1 | restricted | `z b 0` — 0-only, busy-inbound; bit 7 **MBZ 0** |

**Frame 5 is the one-bit flag on every class that has one**: `P` on a line, `z` on
restricted, `g` on a trunk. **Frame 6** is busy-out on the two classes that take calls,
and the direction's low bit on a trunk. **Frame 7** is `D` on a line and must-be-zero
everywhere else. **Must-be-zero bits are decoder-enforced:** a 1 where MBZ is required
→ out of service, not a soft ignore. A line and a trunk now spend all three frames and
have no MBZ bit left; the reserved class has no legal word at all.

**The trunk's fourth bit is a class code, not an option bit.** Direction, glare and
offers-tone are four things and there are three option frames, so the offers-tone seat
is the trunk family's *second member* rather than a bit inside one. That is what pays
for folding the trunk out of the secondary, and it is what class `110` — the old *data
line* — was freed to buy.

#### Reading only the first bits

The word arrives LSB first, so a reader may decide on a prefix instead of waiting for
sixteen bits:

| bits | what they settle | cost |
|---|---|---|
| **2** (`tt`) | a class word against a nail, an answers-to or a call nail | one gate |
| **4** (`tt` + `aa`) | the **family**: subscriber (incl. the plain-line constant) · trunk · source/outside · unequipped-or-reserved. So *trunk or not*, and *special or ordinary*, are each one gate | 4 stages + a gate |
| **5** (+ `m`) | the exact class | 5 stages + a gate |

- **A monitor wants four.** It attends only a slot whose word says trunk
  (`monitor.md` §4), which is now the prefix `1101` — one `'164` and a gate where it
  billed two and a gate; a fifth bit-time tells a flood seat from a tone seat.
- **The port watch wants the octet.** `observers.md` §5 reads the primary into one
  `'164` and lights eight lamps; class, glare and direction are all in that octet now,
  so "in from the west" needs no second chip.
- **It buys gates, not time.** Nothing acts on the word before the visit ends: the
  marker latches all sixteen bits at the octet boundary, and the scanner's rest is one
  `CLK_8K` period whatever the word says. A short read shortens the decoder, not the
  scan.

#### The secondary: one rule

**The tag says what the payload *is*; the primary says whose it is.**

| tag 8–9 | payload 10–15 | what it is |
|---|---|---|
| `11` | `111111` | **`FF`** — nothing more to say. What a card with one `'165` sends, the strap making the byte |
| `01` | a local port `h s` | a second local port |
| `10` | flags | conditions on this port |
| `00` | an exchange code `b b b e e e` | the primary's `h s` is at that exchange |

Beside `FF` there are **six** pairings, three of them live and three reserved.
**Every other one is out of service, fail closed:**

| primary | tag | |
|---|---|---|
| a class, not the trunk family | `01` | **cover** — the port answers to `h s` beside its own class and options |
| answers-to | `01` | **dual membership** — it answers to the primary number *or* this one |
| answers-to | `10` | **hunt conditions**, §2.2.1 |
| call nail | `00` | **network nail** — on lift, dial `1 e b h s`. **Reserved** |
| answers-to | `00` | **net-wide forward** — a call arriving here goes to `1 e b h s`. **Reserved** |
| a class, not the trunk family | `10` | **flags on that class** — the one pairing still unspent. **Reserved**, below |
| any | `11` | `FF` — the top byte of most cards in the exchange |

What falls out of the one rule, and is the whole of what the secondary may mean:

- **A tied nail with a remote address is impossible**, because a latch names only a
  local port (`protocol.md` §3). Tag `00` beside a tied nail is OOS.
- **A class has no port in its primary**, so no class word can name a remote one: the
  twelve bits exist only on a port form. Tag `00` beside a class is OOS.
- **A trunk's secondary must be `FF`.** That is what makes a trunk a one-chip card, and
  it keeps the network unit fail-closed: the unit has no out-of-service decode of its
  own, and `FF` is the check that stands in for one.
- **Two forms can carry a network-wide address, and both are reserved** — where the old
  layout left three further pairings able to hold one with no rule saying which might.
  The old *field A*, tag `00` beside an answers-to with a zero payload, was accepted and
  ignored; it is **retired**, and its bit shape is now the net-wide forward's.
- Unused or unfitted → **`FF`**. Tag `11` with any other payload → OOS. Never treat bare
  ones in 10–15 as exchange or port `77`.

##### The two reserved forms

`1 e b h s` is twelve bits: the primary's `h s` and the payload's `e b`, with the key
`1` implied by the form. Tag `00` puts the primary's port **at another exchange**, and
the two port forms that can carry one are opposite ends of the same idea:

| | trigger | the call |
|---|---|---|
| **network nail** (call nail + tag `00`) | this port's hook rises | out: dial `1 e b h s`, as if its user had |
| **net-wide forward** (answers-to + tag `00`) | a call arrives at this port | on: the caller is sent to `1 e b h s` |

**Read the forward's primary carefully.** In every other answers-to word the primary is
*a local number this port answers to*. Under tag `00` it is **the far exchange's port**,
and the port's own number goes back to being its slot address, as an ordinary line's is.
That is the one place where the tag changes what the primary means rather than only what
the payload means, and a card built from the table without reading this paragraph would
be wired backwards.

Both are **reserved**, and everything below is true of both.

- **What unlocks them is a sender in common control** (`network.md` §9, set aside), not
  §3.4's dialling card. That card carries its own number in jumpers, dials as a caller
  would and never reads a word, so it cannot make either form live. Earlier text said
  "until a dialler exists"; it means a sender.
- **There is no back door for the forward either.** Pointing a cover at a dialling-card
  hotline does not forward a call: once that card answers it is in the call and cannot
  also dial. Four things block both forms — a latch names only a local port, the marker
  has no sender, the network unit never originates, and the register does not outpulse
  (`groups.md` §2.6).
- **Neither may fall back to local, and "may not" means out of service.** With no
  sender fitted the port is OOS: lifting it is ignored, and a call to it gets
  cannot-complete. A network nail is never a local call nail to `h s`, and a forward is
  never a local answers-to.
- **Payload `000000` is exchange 00**, which is a legal code — all sixty-four are
  assignable (`network.md` §2) — so it needs no special case. `111111` is already walled
  off as `FF`.
- **`e` or `b` of 8 or 9 cannot be expressed** in three bits, so the word can never name
  the reserved `1 8 …` / `1 9 …` space, whatever a gateway later does with it.

##### 2.2.1 Answers-to secondary: dual membership, conditions, and the forward

| | form | the marker |
|---|---|---|
| **Idle** | secondary `FF` | answers to its primary `h s` only |
| **Dual membership** | tag `01`, payload a second `h s` | the hunt matches **either** number. One phone in two local groups — a desk that covers two numbers |
| **Conditions** | tag `10`, payload `L U K 0 0 0` or `111111` | qualifies when this member may be taken. `111111` is no feature, i.e. unconditional. `U` ∧ `K` → OOS; any other pattern → OOS |
| **Net-wide forward** | tag `00`, payload `e b` | **reserved** — OOS until a sender exists. The primary is then the *far* port, not a local number (§2.2) |

**Why the forward is not on tag `01`.** Dual membership's payload and the primary are
twelve bits between them, which is exactly a net-wide address, so a forward could have
been spelled there instead. It is not, because dual membership is the one secondary
feature the marker can actually carry out — one comparator, matched against either
number, measured in `make groups` — while any remote destination is dead until a sender
exists. Tag `00` was doing nothing at all, and now carries the shape instead.

**Condition flags** (bit-times 10, 11, 12 — the payload's first three, `000` MBZ after):

| bit | | the marker, on an answers-to hunt |
|---|---|---|
| `L` | **local callers only** | skip this member when the caller is a claimed trunk — desk overflow for internal calls, not for the network |
| `U` | **unequipped owner only** | take it only when the dialled or pilot port failed the probe as unequipped, out of service or empty — night service, not merely busy |
| `K` | **busy owner only** | take it only when that port failed as busy, busy-out or already held — cover while the owner is in a call |

**One tag a word.** Dual membership and conditions are alternate encodings of bits 8–9,
never both, so a two-group member cannot be conditional and a conditional member cannot
be in two groups. Unconditional members — `FF`, dual without conditions, `111111`, or
`L U K` all clear — stay eligible for every hunt reason. `L` may combine with `U` or `K`.
Class options (`P`, `b`, `z`) stay on the class beside a cover, never in the flags.

**What these bits do not buy.** Remote cover, roaming, multi-exchange hunt, overflow to
`1 e b h s`, call waiting, transfer, camp-on, distinctive ring, hunt rank, or a
conference LEG mark: the marker leaves after two latch writes, latches name one local
port, and the flood has no sender (`groups.md` §2.6, §3.4). Hop-by-hop nails and
dialling-card hotlines remain the network paths.

The no-forward strap stays on the network unit, one jumper a compass direction
(`network.md` §3.3) — not in the word, because the six channels of a trunk card share
one word and the strap is per link.

##### The space still unspent: a class with tag `10`

`11 aam ppp 10 pppppp` — a class word carrying the flag tag — is the **one pairing
left over**, and the largest space in the word: six payload bits beside a class's own
three option frames, on any class but one. It is out of service today and the decoder
fails it closed, exactly as tag `00` does.

- **Not the trunk family.** A trunk's secondary must read `FF` or the network unit
  stops seeing it as a flood seat, which is the check standing in for the
  out-of-service decode it does not have (§2.2). Tag `10` on a trunk would take it out
  of the network as surely as a dead link, so the exclusion is the same one cover has.
- **Flags or a cover, never both.** One tag a word. A card that wants six flags gives
  up naming a cover port, and the other way about.
- **It costs the second `'165`**, like any secondary — so it is for a card that already
  has something more to say.

What it could hold has to pass the test everything else here passes: *can the marker
act on it, leaving after two latch writes?* Three things do.

| | what it would say | why it can work |
|---|---|---|
| **Dialling limits on any class** | no 9, no 1, no 8 — separately | today a phone that may not reach the CO must be class *restricted*, which also forces `z` or the local-only floor. The marker already files the caller's limits into a per-register mark at seizure; this widens that mark rather than adding a mechanism |
| **Inbound restriction** | take no call from a claimed trunk | the same predicate as the hunt condition `L` (§2.2.1), read at the terminating test instead of during a hunt |
| **A conference LEG mark** | this line is a bridge leg, not a phone | `groups.md` §6 set a group-with-a-bridge aside for want of "a way to mark a leg that is not a class — layout, a pin, or **another word form**". This is another word form, and it spends no class code |

What it cannot hold is the same list as ever — call waiting, transfer, camp-on,
distinctive ring, hunt rank — because nothing is in charge of a call once the marker
has gone (`marker.md` §5). **No width of secondary buys them.**

#### Whole-word constants and decode order

| word | meaning |
|---|---|
| all ones | plain line (grounded pin) |
| all zeros | no word / OOS / link down |
| primary OK + top byte `FF` | the card has nothing more to say — most cards |
| bad primary/tag/MBZ | OOS — no hunt, nail, or seizure side-effect |

Decode: (1) all ones → plain line; (2) all zeros → none; (3) the primary — type, then
family and member, then the options against their MBZ; (4) if the secondary is not `FF`,
accept only a listed tag × primary pairing with its MBZ payload bits clear; else OOS.

**Incremental fit:** (1) one-`'165` cards, their top byte strapped to `FF` — which
now includes every trunk; (2) tag `01`: a cover beside a class, and dual membership beside
an answers-to; (3) tag `10` hunt conditions; (4) tag `00`, both reserved forms, only
with a sender.

Three 6-bit port forms plus class-and-options do not fit beside four option bits in the
primary, so the class field has **three** bits: a family of two and a member of one. The
fourth option bit was spent on the type bits that name a 6-bit port, and a trunk gets it
back as a second member rather than as an option. Tied nail to 00 collides with all
zeros (unequipped) — and 00 is never a line. Answers-to 77, call nail to 77 and **tied
nail to 77** are free as primary destinations.

- **A plain line card carries no part and no jumper for this.** Its word pin is
  tied to ground, which reads all ones, and that means a line with no options.
  Plain lines are most of an exchange. Only a card with something more to say
  carries the word's parts.
- **The word's parts**: one 74HC165 loaded from jumpers on
  `CLK_8K` (`TX_OCT` / a3) and shifted on **`LOOP_HB` (a2, 128 kHz)**, into a
  **2N7002** (gate from the serial output, held off at power-up by an RC of about
  100 ms): **≈ 1 package + FET**. The one chip plus a strap to ones on the
  chain input is a complete card, and that is now every card the exchange has,
  trunks included; a second '165 daisy-chained (**≈ 2 + FET**) buys only a
  secondary. A line card has the footprint. The port's pull-up is **~680 Ω**.
  `LOOP_HB` is already on the socket for the CVSD encoder; a word card that is
  not a CVSD line still takes a2 for the shift clock.
- **Held off at power-up.** The FET gate stays low through the RC until the
  '165s are loading properly. Without
  this a random word is a tied nail, a call nail or an answers-to about three times in
  four. A trunk card also gates that enable with "link up", so a dead link sends
  nothing and is never hunted. A trunk whose secondary is anything but `FF` is
  out of service and not hunted — the check the network unit leans on, since it
  has no out-of-service decode of its own.
- **A tied-nail port sends no class.** It is never hunted, dialled or a call
  request (§3.1), so the marker never needs one. Whether it rings is `/ANS`.
  The dest of a tied nail is not written and keeps whatever word it already had.
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
  from bit-times 0–1, the family from 2–3 and the secondary tag from 8–9. A card
  that wants only the family — a monitor's *trunk or not*, a port watch — needs
  neither the second '164 nor the '30 (§2.2, "Reading only the first bits").
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
5–7: the class took frames 2–4 as a family and a member, and the fourth option
bit was spent on the two type bits that name a 6-bit port. A trunk, which wants
four, takes its fourth as the family's second member instead (§2.2).

#### Line (family `11`, member 0)

| frame | bit | | the marker |
|---|---|---|---|
| 5 | `P` | **priority** | under register overload, a `P` line is given the next free register before a non-`P` line that is already waiting (§2.4.1) |
| 6 | `b` | **busy-out** (DND as busy) | on a **terminating** call, the port is **not free** — same path as `BUSY` set: the caller hears **busy** tone. **Lifting still gets a register and dial tone**; outbound is unchanged. Against out of service (§2.2): OOS is unequipped both ways (lift ignored). Against a latch make-busy (`console.md` §4): this mark is in the word and survives hang-up. Same bit and test as restricted *busy-inbound* |
| 7 | `D` | **data line** | the marker will not pair it with a voice port, nor a voice port with it. It replaces class `110`, and it is the option the freed code paid for |

**Why busy, not cannot-complete.** Cannot-complete (fast busy / reorder) means the
number cannot be completed — empty slot, wrong digit, restricted dialling.
Busy-out means “this phone is not taking calls,” which is what a busy line
already says. Distinctive DND tone would be a second source and a second marker
steer; not worth it.

**Overflow `o` is retired** (`groups.md`). A hunt group is a port that *answers
to* the number people dial, not a run of adjacent ports.

**Warm is not an option.** A courtesy / lift / help phone is a **call nail**
(§2.2): on lift, connect as if dialled `h s`, with no register. Call nail to 04
is the operator, and holds nothing while idle. Against a private line (§3.1):
a private line rings one fixed phone, both ways, and holds two latches for good.

#### Restricted (family `11`, member 1)

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

**A data line is a line with `D` set** (frame 7), not a class of its own: the
marker will not connect it to a voice port, nor the reverse — the mismatch
`channel-cards.md` §1 warns is "loud, locked, not squelched". The check is made
where both classes can be read, which is inside one exchange; a call from another
exchange arrives on a trunk. **As the marker stands, `D` is enforced by omission**:
a data line is in none of the marker's connect lists, so it is neither called nor
a caller and reaches a circuit only through a nail (§3.2), which is exactly what
class `110` did. Comparing `D` at both ends — one more bit beside the caller's
`z` and floor marks — is the cheap way to let data call data, and is not built.

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
by the scanner from jumpers on the two cards: **each card nails its own port to
the other's** (Joel, 2026-09-26).

### 3.1 The tied-nail word

A card holds the port it listens to — the dest — in jumpers and sends it as its
word (§2.2) in place of its class. Type `00`, dest in frames 2–7; all zeros is
excepted (an empty slot, so **tied nail to 00 is the missing code** — and 00 is
never a line). **A tied nail is one way.** It sets its own port's latch and
nothing else, because a card speaks only for its own port; a connection both
ways is a nail on each card.

| | |
|---|---|
| **The card** | the word's parts (§2.2), with the dest in the jumpers. A plain line card to be nailed has them fitted, and its ground link opened |
| **The marker** | type `00` and not all zeros. An empty slot reads all zeros and a plain line all ones, and neither is a tied nail |
| **The rule** | checked at each port before any other: **a tied nail and `BUSY` clear → write this port to the dest, with `BUSY` set.** One visit, one write. The dest is not written, so the nail is made whatever the dest is doing. A port that sends a tied nail is never free, never hunted, never connected by a dialled number, and its lifting is never a call request or a seizure |
| **The dest** | is not touched: it keeps its word, its latch and whatever it is doing, and a line can still call, be called and be hunted. The nail's port hears it, and is rung by its lifting if its `/ANS` is open (§2.3), because the dest's M is the nail port's E. **A source may be nailed**: nothing writes the radio (`features.md` §6), so a port that listens to it for good — a paging amplifier with music, a recorder — is one card's jumpers |
| **Release** | nothing stops it. When a call over it ends, the release detectors clear the nail port's latch as on any call (`marker.md` §5) — its own M falling, or its dest's — and within one scan, 8 ms, the scanner writes it back. The port circuit is unchanged |
| **After `/RESET`, or a card plugged in** | the first scan writes every nail, within 8 ms. The nailing cards are the only record, and nothing else is needed |
| **Both ways is two nails** | a private line, a ringdown hotline or a data circuit is **a mutual nail: each card names the other**, so each port listens to the other. One nail alone is a one-way path: its port hears the dest, and the dest hears nothing of it. Neither end of a mutual pair is ever a caller, so a phone left off-hook when the other hangs up is always nailed again, and rings the other (§3.2). A channel nailed hop by hop is nailed from both ends the same way (§3.3), so it is never a trunk to the flood or the monitor |
| **The console** | can still point two latches at each other by hand, as bring-up step 3 does — one key, two crossed words in one tenure (`console.md` §1, §6). **It rings nothing**: with both phones on hook the pair is held by nothing, so an operator rings each end from a source first and pairs them once both have answered. It is a call, and it clears when it is released; nothing remembers it, which is the whole difference from a nail |
| **Counters** | a nail's writes are not calls (§4) |

The tied-nail word replaces a nail card that wrote nails from a diode matrix: a '161,
a '138 and up to 88 diodes for four connections at most. There is no limit on
the number of nails, and changing a local pair is one card's jumpers.

### 3.2 Ringdown

A mutually nailed pair of phones — each card naming the other — is a ringdown
hotline. Nothing in it is new: it is the hotline rule of `channel-cards.md` §1
under the exchange's supervision (`fabric.md` §3.5):

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

A **one-way ringdown** — A's lift rings B, and B's lift is an ordinary call — is
a call nail on A's card (§2.2), not a tied nail. A **private line that never
rings** is a mutual nail between two cards with `/ANS` low and no ringer; a
phone's card cannot be one, because a phone with `/ANS` low rings continuously
(§2.3).

**A data circuit** is two data cards, each nailed to the other, with `/ANS` on both so
that `DSR` follows `DTR` without the cadence. It is bit-exact inside one
exchange and over copper ties. Across MF8 it is async oversampled data only
(`network.md` §8), except to a loop-timed subscriber terminal
(`terminal.md` §4).

### 3.3 Across the network: nailed hop by hop

A tied-nail word names a port of its own exchange, because a latch can name nothing
else (`protocol.md` §3). A channel held end to end across exchanges is
nailed at every exchange on the way, each exchange nailing its own pair:

```
 exchange 22      phone A ↔ trunk channel toward 23            A's card names the channel, and the channel names A
 exchange 23      channel from 22 ↔ channel toward 24          each channel names the other
 exchange 24      channel from 23 ↔ phone B                    B's card names the channel, and the channel names B
```

Every pair on the path is a mutual nail (§3.1), so a trunk channel sends a nail
word of its own and is never a trunk to the monitor or the flood, not even in
the 8 ms after a release.

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
on lift, connect as if dialled `h s`. A **private line** (§3.1) rings faster and
holds two latches.

A tester who wants to **drive a register and the flood without a handset** is
the same live A with the number keyed rather than jumpered: `pulse-gen.md`.

### 3.5 Which to use

| | private line: a mutual nail (§3.1) | nailed hop by hop (§3.3) | a card that dials (§3.4) |
|---|---|---|---|
| reaches | its own exchange | another exchange, by a fixed path | anywhere in the network |
| named by | each end's port, on the other's card | a mutual nail at each exchange | the number, on one card |
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
| the card word and `/ANS` | nothing on a plain line card; ≈ 1 + FET on any other, ≈ 2 + FET only where a secondary is fitted; two ~680 Ω pull-ups a port; ≈ 3 at the marker | the cards, the block, the marker |
| lines that answer at once | `/ANS` tied low on the card | the card |
| restricted lines, hunt groups, call nail, busy-out | class *restricted* with `z b 0` (local floor if ¬z); line `P b D`; call nail a 6-bit form; shared frame 6 for `b`; secondary tagged per §2.2 (dual membership, condition flags `LUK`) | the cards, the marker |
| nailed-up connections | a one-way nail, one word and one write a card; both ways is a nail on each card | the nailed cards |
| nailed hop by hop | a mutual nail at every exchange on the path | the cards and trunk cards |
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
- **The word as gates**: the '165 load against `CLK_8K`, the probe's capture
  in the scanned port's cell, the all-ones detector, the power-up hold-off, and
  a plain card's ground link against a fault that reads the same.
- **`/ANS` alone forming `ON`**, drawn.
- **The line options in the marker**: restricted `z` (0-only) with local-only
  floor if ¬z; priority `P` on frame 5; call nail on type `10`; busy `b` on
  shared frame 6; the data bit `D` on frame 7; secondary tag/payload per §2.2
  including dual membership (answers-to + tag `01`) and the condition flags
  `L U K`. `make word`, `make priority`, `make groups`.
- **The nail rule**: one way, one write, its place ahead of the call-request
  rule, and the 8 ms after a release in which a mutual pair is half made.
  `make word`.
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
