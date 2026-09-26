# The card word

What the card behind a port says about it: whether it rings, on one pin, and
everything else in one serial word — its class and options, a number it
answers to, or a nail. This document owns the word's encoding, what a card
does to send it, and what each form means; reading it off `/HW` is
`fabric.md` §4, and what the markers do with it is `marker.md` §4.

> **Built:** `newimpl/rtl/word_dec.v` (the decode, `tb_max`); the '165 on
> `baseband_card.v` and `local_trunk.v` (`tb_word`, `tb_tie`, `tb_ltu`).
> **Proposed:** the secondary byte (§7), a bridge as a group (§5), the card
> that dials (§6.5).

---

## 1. What a card says

**Whatever sits behind a port says everything the exchange needs to know
about it, in two places.** The block keeps no per-port settings and common
control keeps no table, so **move a card and all of it moves with the card.**

| pin | at the block | on the card |
|---|---|---|
| a12, **card word** | pulled up; read through `/HW` when a reader selects the port (`fabric.md` §4). Open reads none | tied to ground on a plain line card, which reads all ones; otherwise a '165 into a 2N7002 (§3) |
| a13, **`/ANS`** | pulled up: open reads "rings" | tied to ground on a card that must never be rung in cadence |
| a14 | spare | |

A card only ever pulls these pins to ground, and an MF8 shelf leaves a12–a14
unconnected, so a card built for the exchange works unchanged in an MF8 shelf
(`common/common-cards.md` has the socket).

**`/ANS` is the one thing the port's own gates need at every instant**: open,
the port rings its card in cadence and sends the caller ringback; low, it
hands its card E steady, never chopped (`fabric.md` §5.2). Whether a
port rings is how it is supervised, not what it is, so the class does not
enter into it — but **the class and the pin must agree** on a card that is not
a line. Cards that tie `/ANS` low: a trunk, an outside line, a bridge leg, a
source, the loopback test line, a paging amplifier, a relay port, an
announcement that must answer at once, and a data card whose `DSR` should
follow `DTR`. **Never a phone's card**: an on-hook phone given steady E rings
continuously, and its caller hears no ringback.

**The word** is read by three things: the class marker, for every decision it
makes (`marker.md` §4); the mini marker, only with a network unit fitted, to
tell a trunk or an absent card from a caller (`marker.md` §3); and the network
unit, to find incoming seizures and hunt trunks by direction (`network.md`
§3).

- **A card** says it for its one port.
- **A trunk card** says it for each channel: a word line and an `/ANS` line a
  channel. One '165 may serve every channel of a card whose channels are all
  alike: the local eight-channel trunk fans one to eight FETs.
- **An empty slot** says nothing: it reads none.

---

## 2. The primary octet

Eight bit-times, **printed in wire order**: bit-time 0 is leftmost, and is
`WORD[0]` as `word_dec.v` holds it. Every numeric field goes least significant
bit first, so a two-digit number appears **units digit first**, each digit low
bit first: `s s s h h h`. `WORD[7:2]` is the same six bits read as `h s`. A
card's jumpers are cut from this table; a table that prints `h h h s s s`
gives a card that answers to the wrong number. **A 1 is the pin pulled low.**

```
bit-time        0 1   2 3 4   5 6 7     WORD[7:0]   WORD[4:2]
class form      1 1   a a m   p p p                 family a a, member m, options p p p
port form       t t   s s s   h h h                 a local port h s

CONSTANTS
plain line      1 1   1 1 1   1 1 1     FF                      a grounded pin, no part fitted
none            0 0   0 0 0   0 0 0     00                      no card, held off, link down

PORT FORMS
tied nail       0 0   s s s   h h h     hs,00                   this port listens to h s (§6)
answers-to      0 1   s s s   h h h     hs,10                   a line that answers to h s (§5)
call nail       1 0   s s s   h h h     hs,01                   on lift, as if h s were dialled (§6)

CLASS FORMS
unequipped      1 1   0 0 0   · · ·     -           0           never sent: out of service
source          1 1   1 0 0   0 0 0     07          1           talks, never listens
trunk           1 1   0 1 0   g d d     0B          2           a flood seat: glare, direction
line            1 1   1 1 0   P b D     0F          3           priority, busy-out, data
reserved        1 1   0 0 1   · · ·     13          4           out of service, whatever follows
outside line    1 1   1 0 1   0 0 0     17          5           an FXO to a CO or a foreign PBX
tone trunk      1 1   0 1 1   0 0 0     1B          6           offers dial tone on seize
restricted      1 1   1 1 1   z b 0     1F          7           a lobby or public phone
```

The `WORD[7:0]` column is each class with its options clear; `hs,10` means
`WORD[7:2]` = `h s` and `WORD[1:0]` = `10`. **The type bits are wire order
too**: answers-to's `01` is `WORD[1:0] = 2'b10`, as the trunk family's `01` is
`WORD[3:2] = 2'b10`; `faults.py` F50 reads them the other way round and turns
`tb_max` red. Examples: a line with busy-out is `4F`, with `P` `2F`, a data
line `8F`; restricted with `z` is `3F`; a trunk facing south `4B`; answers to
21 is `46`.

**The families**, bit-times 2–3 in wire order: `11` subscriber (line,
restricted), `10` talks-but-is-not-a-line (source, outside line), `01` trunk
(flood seat, tone trunk), `00` unequipped or reserved. A reader that wants
only "flood seat or not" compares bit-times 0–4 with `11 01 0`, as the mini
marker and the unit do.

**The trunk's options**: `g` at bit-time 5, glare, makes the unit's hunt take
the highest-numbered free trunk facing that way instead of the lowest
(`network.md` §5). `d d` at 6–7 is the direction, low bit at 6: N = 0,
S = 1, E = 2, W = 3. A trunk spends all three option frames; its fourth fact,
offers-tone, is the family's second member.

**Decode**, as `word_dec.v` does it:

1. **All ones is a plain line**, taken before anything else: decoded by its
   bits it would be restricted with bit 7 set, which is out of service.
2. **All zeros is none**: an empty socket, a card in its power-up RC, a trunk
   whose link is down. Never a tied nail to 00, which is why 00 is the one
   port a tied nail cannot name.
3. **The type**: `00` tied nail, `01` answers-to, `10` call nail, `11` a class.
4. **The class**, and its options against **must-be-zero, which is
   enforced**: a 1 in an MBZ frame is out of service, not a soft ignore.
   Source, outside line and tone trunk have `000` in 5–7; restricted has bit 7
   MBZ, which is the whole of what keeps a class word off the plain-line
   constant. Unequipped and reserved are out of service.

| form | lifts (M up, `BUSY` clear) | dialled by its number | found by a hunt |
|---|---|---|---|
| plain line, line | a caller; a data line (`D`) never | connected if free; a data line never | — |
| restricted | a caller, limited (§4) | connected if free | — |
| answers-to | a caller | connected if free | for its number (§5) |
| call nail | connected to its dest (§6.3) | connected if free | — |
| tied nail | never | never | never; the walk makes it (§6.1) |
| source | never: its M is low | listened to, one write | — |
| outside line | a CO ringing in, routed as 0 | 03 | by 9 |
| trunk | the network unit's | 03 | by the unit, by direction |
| tone trunk | a caller | 03; the mini marker connects it (`marker.md` §7) | — |
| none, out of service | never | 03 | never |

Why the class field is three bits: three 6-bit port forms and the class forms
fill the two type bits, which leaves a family of two, a member of one and
three option frames in one octet.

---

## 3. What the card does to send it

- **One 74HC165, loaded from jumpers.** Its SH//LD is /(`TX_OCT` · `TX_CLK`),
  a quarter '00 (the '165 loads while the pin is low): the load happens in the
  first half of frame 7 and is released half a frame before the edge that
  shifts. Loaded on `TX_OCT` alone, the load would be released at the very
  edge that shifts, and which won would be the board's propagation delays.
- **Shifted at each frame edge on `TX_CLK`**, 64 kHz: a bit a frame. Frame 7
  carries bit 0, frame 0 bit 1, frame *f* bit *f* + 1 mod 8, and the octet
  repeats every eight frames. A reader's select comes at its port's turn,
  which fixes the frame its read starts on; the reader lands every bit in its
  place (`fabric.md` §4).
- **`SER` is strapped high**, so what shifts in behind the octet is ones.
- **The serial output drives a 2N7002 onto a12**: the pin low for a 1.
- **Held off at power-up.** The FET's gate is held low for about 100 ms by an
  RC, so a '165 clocking before its load settles says nothing. A random byte
  is a port form about three times in four, and a live flood seat one time in
  32. A trunk card also gates the FET with link-up, so a dead link reads none
  and is never hunted, and holds its M off with the same RC (`trunks.md` §1).
- **Out of service** is no word: a switch in the FET's gate, or on a plain
  card the ground link opened. The port reads none; a call to it gets
  cannot-complete and its lifting is ignored. On a trunk card a switch a
  channel takes one channel out of the hunt.
- **Parts**: about one package and a FET, and none on a plain line card. The
  tone cards at 01–03 need no word: they are reached by address.
- **What is given up**: a word pin shorted to ground reads as a plain line.

---

## 4. Line options

A line's and a restricted card's option frames are read only by the class
marker; a trunk's are the unit's (§2). **Frame 5 is the one-bit flag on every
class that has one** (`P`, `z`, `g`); frame 6 is busy-out on the two classes
that take calls; frame 7 is `D` on a line, a direction bit on a trunk, and
MBZ everywhere else.

**Line** (family `11`, member 0):

| frame | bit | | at the class marker |
|---|---|---|---|
| 5 | `P` | **priority** | under register overload a `P` line is given the register before a waiting non-`P` line: `PWAIT` (`marker.md` §4.3) |
| 6 | `b` | **busy-out** | on a terminating call the port is not free, as with `BUSY` set: the caller is hunted for among the ports that answer to the number, then hears busy tone. Its own lift still gets the register and dial tone. It survives hang-up, being in the word |
| 7 | `D` | **data line** | neither a caller nor called: the marker never pairs it with a voice port, and it reaches another port only through a nail (§6). `D` is enforced by omission (§8) |

**Why busy, not cannot-complete**, for busy-out: cannot-complete means the
number cannot be completed; busy-out means this phone is not taking calls,
which is what busy already says. A distinctive tone would be a second source
for nothing.

**Restricted** (family `11`, member 1): a lobby or public phone, with a
line's free test and ringing. The class is a jumper the user cannot clear, so
the dialling limits live in its options:

| frame | bit | | at the class marker |
|---|---|---|---|
| 5 | `z` | **0-only** | only a first key of 0 completes (04, then the ports that answer to it); any other is cannot-complete |
| 6 | `b` | **busy-inbound** | the same terminating busy path as a line's busy-out; its lift is unchanged |
| 7 | `0` | **MBZ** | a 1 is out of service. It keeps `z b` set off the all-ones constant |

**The floor.** With `z` clear the caller is local only: 9 is cannot-complete,
and so is 1 when a network unit is fitted. A help point that may only reach
the operator is a call nail to 04 (§6.3), which needs no `z`.

**Warm is not an option**: a courtesy, lift or help phone is a call nail.

---

## 5. Answers to a number

**A port may say that it answers to a number.** An answers-to card is a plain
line in every other respect, class line and no options, with `h s` in its
jumpers. A call to `h s` that cannot be completed at `h s` is offered to it.

- **The rule** is the class marker's hunt (`marker.md` §4.5): the dialled
  port first; on any failure, the first free port from 01 in slot order that
  answers to the number; one hunt a call.
- **A port that answers to a number keeps its own.** Dialled by its address
  it rings if it is free and gives busy if not. The number it answers to
  brings it only calls meant for another port that could not go there.
- **The port that owns the number needs no word for this.** It is found by its
  address, as every port is. The number may even be an empty slot's; then
  every member is found by the hunt.
- **A group is named by the number people dial**: no second numbering, no
  limit on groups, no rule about slots. It compares, where an adjacent run of
  ports walked: a pulled card is passed over, a stranger is never rung, and
  members sit anywhere.

| | how |
|---|---|
| a hunt group | members answer to the number people dial: a desk at 55 is the phone at 55 and any others, in any slots, that answer to 55 |
| a second operator's position, the night announcement | lines that answer to 04. The first position is a plain line at 04 and needs no word |
| night service | 04's out-of-service switch: 04 reads none, and 0 goes on to whoever answers to 04 |
| a message at the end | an announcement card, `/ANS` low, answering to the number, in a slot after the group's last member (`features.md` §2) |
| a meet-me bridge | its legs answer to its number (below) |

**A bridge is a group** (proposed with the bridge, `proposed/conference.md`).
Its legs are ordinary lines with `/ANS` low, each answering to the bridge's
number in its primary, wired and without jumpers. One jumper, forcing one bit
of four legs' number, joins two bridges of four into one of eight
(`proposed/conference.md` §5).

**What a number cannot do.** Nothing times a ringing phone, so a call that
rings unanswered rings on. Call waiting, transfer, camp-on and pre-emption
each need something in charge of a call, and nothing is. A number elsewhere
is four digits, and the network has no sender to send them. Cover, a second
number and conditions on a member are the secondary's (§7), which nothing can
read yet.

---

## 6. Nails

A connection that stays when both ends hang up. Two ports facing each other
are already a hotline: either lifting rings the other, both lifted is a call
(`common/channel-cards.md` §1). A nail is what keeps the pair after the
ports' release has cleared it.

### 6.1 The tied nail: one way, one write

A card holds the port it listens to, the dest, in jumpers, and sends it as its
word in place of a class: type `00`, dest in frames 2–7. **A tied nail sets
its own port's latch and nothing else**, because a card speaks only for its
own port.

- **The class marker's walk makes it** whenever it reads the port with `BUSY`
  clear: one write, port ← dest, with `BUSY` (`marker.md` §4.2). **The dest is
  not read, written or tested free**, so the nail is made whatever the dest is
  doing. A tied nail naming its own port is never made.
- **The dest is not touched.** It keeps its word, its latch and whatever it
  is doing, and can still call, be called and be hunted. The nail's port hears
  it, and is rung by its lifting if the nail's `/ANS` is open, because the
  dest's M is the nail port's E. **A source may be nailed**: a paging
  amplifier nailed to the radio at 30, a recorder, is one card's jumpers.
- **A port that sends a tied nail** is never a caller, never dialled, never
  hunted, and its lifting is never a seizure.
- **Release**: nothing stops the ports' own. When a call over the nail ends
  the port's latch is cleared as on any call (`fabric.md` §5), and the walk
  writes it back within a round, about 250 ms. After `/RESET` or a card
  plugged in, the first round makes every nail. The nailing cards are the only
  record. With the marker stopped a nail works until its first release, and
  not after.
- **Parts**: the word's (§3), with the dest in the jumpers; a plain line card
  to be nailed has them fitted and its ground link opened. No limit on the
  number of nails.

### 6.2 The mutual nail: private line, ringdown, data circuit

**Both ways is two nails: each card names the other**, so each port listens
to the other. Neither end is ever a caller, so a phone left off-hook when the
other hangs up is nailed again and rings the other.

```
 A lifts          A's M reaches B's port as E.  B is on-hook: its port rings it in cadence and
                  sends A ringback.  The first burst comes 0–4 s after the lift: RING_CAD is
                  shared and free-running
 B answers        B's M rises: ringing and ringback stop, and they talk
 both hang up     the ports clear both latches 256 ms after the first fall; the walk makes
                  each nail again within a round
 one stays off    it rings the other, and hears ringback, until the other answers or it hangs up
```

- **The two ends are made separately**, up to a round apart. Meanwhile the
  pair is half made: the end made first hears the other and is rung by it,
  and the other hears nothing.
- **A private line that never rings** is a mutual nail between two cards with
  `/ANS` low and no ringer. A phone's card cannot be one (§1).
- **A data circuit** is two data cards each nailed to the other, `/ANS` low so
  that `DSR` follows `DTR`. It is bit-exact inside one exchange and over a
  tie that carries the far clock; across a plesiochronous link it slips
  (`network.md` §8).

### 6.3 The call nail

Type `10`, dest in frames 2–7: **on lift, connect as if `h s` had been
dialled**, with no dial tone and no digits. It takes the register only for the
watch after its connect (`marker.md` §4.6), and holds nothing while idle. A
busy dest is hunted like a dialled number, and ends in busy tone.

- **A one-way ringdown**: A's lift rings B, and B's lift is an ordinary call.
- **A courtesy or help phone**, and **a call nail to 04**, the operator.

### 6.4 Across the network: a mutual nail at every exchange

A latch names only a port of its own exchange, so a channel held end to end is
nailed at every exchange on the way:

```
 exchange 22      phone A ↔ trunk channel toward 23      A's card names the channel, the channel names A
 exchange 23      channel from 22 ↔ channel toward 24    each channel names the other
 exchange 24      channel from 23 ↔ phone B              B's card names the channel, the channel names B
```

A nailed trunk channel sends a nail word, not a class, so it is never a flood
seat, never hunted and never watched by a monitor. Ringdown works both ways,
as in §6.2, with ringback in band from B's port. The cost is a channel on every
link crossed, for good — a direction's six channels become five, and its
capacity at 1 % blocking falls from 1.91 E to 1.36 E (`sim/exch.py ss0` 4) —
and a fixed route in jumpers at every exchange.

### 6.5 A card that dials (proposed)

A hotline to another exchange holds no path: a flood's patches clear on a
fall, and backward A across the network is the claim, not the far phone's
hook. So it **dials, every time its phone is lifted**: a station card with a
dialler and `1 e b h s`, or `h s`, in jumpers. To the exchange it is a caller
like any other.

| | |
|---|---|
| waiting for the register | it must not dial before a register is attached. It waits for `C_RX` to leave the idle pattern, which is dial tone arriving: an XOR against `FILL` and a counter. No dial-tone card, no hotline |
| dialling | breaks on its own `A_TX` while the phone stays off-hook: 10 pps, 60/40, 0.7 s between digits, all from `TX_OCT`. The phone hanging up stops it |
| time | about 4–6 s from dial tone to the far port being rung, then 0–4 s to the first ring |
| both ways | a dialling card at each end; both lifting at once find each other busy |
| parts | the 10 ms step ('4040 and a gate), the pulse and its break ('4017, a NOR), the count ('193 through 2 × '153 from the jumpers), the digit pointer and pause ('393), the idle detector and control ('86, '74): about 8 packages |

### 6.6 Which to use

| | mutual nail (§6.2) | nailed hop by hop (§6.4) | a card that dials (§6.5) | call nail (§6.3) |
|---|---|---|---|---|
| reaches | its own exchange | another, by a fixed path | anywhere | its own exchange |
| the far end rings | at the lift | at the lift | 4–6 s after dial tone | at the lift |
| the far end's lift rings the near end | yes | yes | only with a dialling card there too | no |
| holds while idle | two latches | a channel on every link | nothing | nothing |
| parts | ≈ 1 + FET a card | ≈ 1 + FET a card or channel, every exchange | ≈ 8 | ≈ 1 + FET |

The console can still pair two latches by hand (`proposed/console.md`). It
rings nothing, and the pair clears on release: that is a call, not a nail.

---

## 7. The secondary byte (not readable yet)

**What a card can deliver at 64 kHz is the primary octet.** A card's '165
reloads on `TX_OCT`, every eight frames, and the socket carries nothing that
marks sixteen, so nothing in the exchange reads a bit past the eighth. The
secondary byte below is a proposal for a second '165 behind the first.

**The one rule: the tag says what the payload is; the primary says whose it
is.** Bit-times 8–9 are the tag, 10–15 the payload, in wire order:

| primary | tag | payload | it would be |
|---|---|---|---|
| any | `11` | `111111` | **`FF`**: nothing more to say. What an unfitted second '165, strapped to ones, sends |
| a class, not the trunk family | `01` | `s s s h h h` | **cover**: the port also answers to `h s` |
| answers-to | `01` | `s s s h h h` | **dual membership**: it answers to either number |
| answers-to | `10` | `L U K 0 0 0` | **hunt conditions** on this member |
| call nail | `00` | `b b b e e e` | **network nail**: on lift, dial `1 e b h s`. Reserved |
| answers-to | `00` | `b b b e e e` | **net-wide forward**: a call here goes to `1 e b h s`. Reserved |
| a class, not the trunk family | `10` | six flags | **class flags**: unspent. Reserved |

Every other pairing, and tag `11` with any payload but ones, would be out of
service. The conditions: **`L`** local callers only (skip the member when the
caller is a claimed trunk); **`U`** unequipped owner only (take it when the
dialled port failed as empty or out of service: night service); **`K`** busy
owner only (take it when that port was busy: cover in a call); `U` with `K`
out of service. One tag a word: dual membership and conditions never both.
The two reserved forms need a sender in common control, which the network
does not have (`network.md` §9), and neither may fall back to a local number.
The class flags could hold dialling limits on any class, an inbound
restriction, or a mark for a bridge leg.

**None of it can be read today, so none of it is in force:**

- a reserved tag-`00` form reads as the local form its primary spells: a
  network nail is a local call nail to `h s`, a net-wide forward a local
  answers-to;
- **a trunk whose secondary is not `FF` is hunted like any trunk.** No reader
  checks the secondary, and the unit has no out-of-service decode that it
  could stand in for;
- covers, second numbers, `L U K` and class flags do nothing.

**Every claim that the secondary "fails closed" is false until the secondary
can be read.**

---

## 8. Open

- **Reading the secondary.** Needs a load strobe on the socket that marks
  sixteen frames, or the card shifting at 128 kHz, or a second octet by another
  means. Blocks cover, dual membership, `L U K`, the trunk `FF` check, the
  reserved forms' fail-closed rule, and a bridge-leg mark.
- **`D` bars switched data.** A line with `D` is neither caller nor called, so
  it is nailed only. SDU-1's switched service seizes and dials like a phone
  (`common/sdu-1.md` §3), which works only with `D` clear, and then nothing
  stops a data set being connected to a voice port. Options: compare `D` at
  both ends so that data may call data, or a class for switched data. Blocks
  SDU-1 on switched lines.
- **The half-made mutual nail.** For up to a round after a release, one end of
  a private line hears and is rung by the other while the other hears
  nothing. Not measured whether a user notices; a one-write nail has no way to
  make both ends at once.
- **A dialled tone trunk**: the two markers disagree on whether one is
  connected (`marker.md` §7).
- **A group with a bridge in it**: extensions that all ring through a bridge
  need a mark for a leg that is not a class. The class-flag pairing of §7 is a
  candidate, and waits on the secondary.
