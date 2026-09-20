# The exchange — groups: a number in the word, a second word, and a bridge that is a group

The marker finds a port it was not given the address of in three ways, and each
was written for one purpose. `exch-marker.md` §3 hunts a **class**, for 0 and
for 9. `ex-extensions.md` §2.4 walks a **run** of adjacent ports marked `o`, for
a hunt group and for a conference bridge (`exch-features.md` §7.4). And
`exch-network.md` §3.2 hunts a trunk by its **direction**. A second operator's
position, a sales desk, a pool of data ports, a bridge's legs and a bank of
call-in lines are all one request — *the first free port of these* — and only
the trunk hunt is really a different one.

This document proposes one rule for everything but the trunks: **a port may say
that it answers to a number.** It then asks how much room a card's word needs
for that, which is the question of a second byte; trades what should go in which
byte; and works the conference bridge into the result, first as a group and then
as something a group may contain.

The short answers, before the detail:

- **A number, not a group number.** A card says "I answer to `h s`", and a call
  to `h s` that cannot be completed there is offered to it. A group is named by
  the number people dial, so there is no second numbering to keep, no limit on
  how many groups, and no rule about which slots.
- **The commonest cards need one '165, as now, or none.** The word gets one new
  form, *a plain line that answers to `h s`*, in the last unused quarter of its
  code space. A second operator's position, a member of a hunt group, a phone
  that covers another and an extension phone all say it with the parts a nail
  takes today.
- **A secondary word, on a14, for the port that needs a class or options *and*
  a number.** It is optional card by card and block by block, and it takes the
  last spare pin of the slot and the last spare conductor of cable B.
- **§4 trades what goes in which word.** What another card reads, and what would
  be unsafe to miss, is primary. A number on a port that already has a class is
  secondary. Most exchanges will fit the secondary read-out in one place, the
  conference block.
- **A bridge is a group, at no cost**: its legs answer to its number, and the
  run, its `o` bits and its rule about block boundaries leave the marker. **And
  a group may contain a bridge**: phones that answer to a bridge's number ring
  together when it is called, whoever answers is in, and one lifted later joins.
  Nothing remembers the call.

> **Status: proposed. Nothing here is measured.** None of it is in the `calls`
> model or in `exrtl`. The class hunt it partly replaces is measured in `calls`
> and built in `exrtl`, where no bench yet dials 0 or 9; the run it wholly
> replaces was never in either. Every package count is an estimate from parts
> the other documents already use, no circuit has been drawn, and nothing has
> been on a bench. §6 changes the conference bridge of
> `exch-features.md` §7, whose switch and detector *are* measured
> (`exch.py confer`), in ways that model has not run. §9 lists what is owed.

---

## 1. Three hunts, and what each cannot do

| | written for | finds | built |
|---|---|---|---|
| **a class** (`exch-marker.md` §3) | 0, 9 | the first free port of the class, in fixed order from 00 | in `exrtl`; measured in `calls` |
| **a run** (`ex-extensions.md` §2.4, `exch-features.md` §7.4) | a hunt group, a bridge | from the dialled port onward, the first free port, while each busy one has `o` set | no |
| **a direction** (`exch-network.md` §3.2) | tie trunks | a free trunk facing each way | in `exrtl`, and measured there |

**The class hunt cannot make a second group.** One class is one group. A bank of
call-in lines on key 8 would be a new class, and all eight codes are taken
(`exch-fabric.md` §3.5).

**The run cannot lose a card.**

1. An empty slot reads *not free, `o` clear*, which ends a run. Pull one
   member's card and the group stops there.
2. Make the run skip empty slots instead, and pull the *last* member's card: the
   run walks on and rings the next free plain line, a stranger. No end mark of
   either sense prevents that. Only membership does.
3. Its members must sit in adjacent slots, in order of priority. And it cannot
   replace the class hunt even so: 04's neighbours are trunk channels, and then
   the tones.

The class hunt has none of these faults. A pulled card sends no word and is
passed over, a port that is not of the class is never rung, and members sit
anywhere. **What makes it robust is that it compares, where the run walks.** So
the run should become a comparison, and the question is what to compare.

**Not the whole word.** Comparing a busy member's word with every other port's
makes a group of the ports whose words are equal, and that needs a group number
in the word. A line's options have one bit spare (`ex-extensions.md` §2.2).
Spending all four of a class's option bits gives sixteen groups at most, shared
by everything in the exchange that hunts, and a second numbering beside the one
people dial. That is the tight encoding. §2 is the loose one, and it needs no
group numbers at all.

**The trunk hunt stays as it is.** The glare bit and the strap differ between
trunks that face the same way, and what is wanted there is one trunk *each* way,
not the first free.

---

## 2. A port answers to a number

### 2.1 The form

The word of `ex-extensions.md` §2.2 has two forms and two constants, and a
quarter of its codes — bit 0 and bit 7 both set, short of all ones — mean "no
word". That quarter is a number:

```
 frame of the octet    0    1  2  3    4  5  6  7
 class and options     0    c  c  c    p  p  p  p     as it is                         (ex-extensions.md §2.2)
 a nail                1    h  h  h    s  s  s  0     as it is                         (ex-extensions.md §3.1)
 answers to            1    h  h  h    s  s  s  1     NEW: a plain line that answers to h s
 a plain line          1    1  1  1    1  1  1  1     the pin tied to ground
 nothing               0    0  0  0    0  0  0  0     an empty slot; out of service; a link down
```

| | |
|---|---|
| **The card** | the word's parts as they are, ≈ 1¼ packages, with the number in the jumpers. It is a plain line in every other respect: class line, no options. Whether it rings is still `/ANS`, so an announcement card at the end of a hunt ties that pin low and says the rest in this form |
| **The marker** | bit 0 set, bit 7 set, and not all ones: the nail's own decode with bit 7 taken the other way |
| **77** | cannot be answered to in this form, which would be all ones. A group takes another number, or its members say it in the secondary word (§3) |
| **Power-up** | a random byte is a nail or a number one time in two, where it was a nail one time in four. The hold-off of `ex-extensions.md` §2.2 already covers it, and a number held for 100 ms is harmless where a nail is not |

### 2.2 The rule

```
 called = h s     from the dial · from a key · 04, for a warm line and for a CO line ringing in
   probe h s      as now.  Free, and a port this caller may be given → connect, two writes.  A source → one write
   otherwise      hunt, in fixed order from 00: the first free port that answers to h s → connect
   none           cannot-complete

 first key   0    called = 04
             8    called = a pilot, strapped in the matrix.  No strap → cannot-complete, as now
             9    hunt class outside line, as now             1    the network, as now
```

- **"Otherwise" is every reason the probe fails**: busy, ringing, an empty slot,
  a card out of service, a trunk, the caller's own number. Each gave
  cannot-complete at once (`exch-marker.md` §2), and now gives it one hunt later.
- **The port that owns the number needs no word for this.** It is found by its
  address, as every port is. 04 is the operator's phone on a plain line card.
- **A port that answers to a number keeps its own.** Dialled by its address it
  rings if it is free and gives busy if it is not. The number it answers to
  brings it only calls that were meant for another port and could not go there.
- **One hunt a call, never a chain.** The port the hunt finds is free, so there
  is nothing to pass on.
- **The port found is taken at the visit that finds it**: the two writes are
  issued then, and not at the end of the pass, because a first-free hunt has
  nothing to wait for. The class hunt as built in `exrtl` notes the port and
  writes at the end of its pass, and a marker that probes a dialled port out of
  the scanner's turn (`exch-marker.md` §4) can find that port still free in
  between. What is left is two calls at one visit, and `exch-rtl.md` §2 has the
  rule: the first takes the line and the second is told busy.
- **A key's pilot sits in 00–17**, which nobody can dial (`exch-protocol.md`
  §5), so it collides with no line's number. A pilot need hold nothing: an empty
  slot fails the probe and the hunt follows. **0's pilot is 04 because the
  operator's phone is already there.**
- **9 stays a class hunt.** An outside line needs its class in any case, for
  ringing in (`exch-marker.md` §3), so the class hunt costs its card nothing,
  and it is built. §4 has the trade.
- **Across the network nothing changes.** `h s` means after `1 e b` what it
  means at home (`exch-marker.md` §2), so a group, a covered number and a bridge
  are reached from anywhere.

### 2.3 What a number gives

| | how |
|---|---|
| **a hunt group** | its members answer to the number people dial. A sales desk at 55 is the phone at 55 and two more, in any slots, that answer to 55. Any number of groups. The number may be an empty slot's, and then every member is found by the hunt |
| **a second operator's position, and the night announcement** | lines that answer to 04. Class *operator* is not needed: its code is spare, and the first position's card carries no word at all |
| **night service** | the operator's out-of-service switch (`ex-extensions.md` §2.2): 04 reads unequipped, and 0 goes on to whoever answers to 04 |
| **cover** | a secretary's phone answers to 23. It rings when 23 is busy, switched out or pulled, and only then |
| **a call-in bank on one digit** | key 8 strapped to a pilot, and the bank's lines answer to it |
| **a message at the end** | an announcement card (`exch-features.md` §3), `/ANS` low, that answers to the number and sits after the group's last member |
| **a bridge** | §5 |

### 2.4 Fixed order is still the feature

`exch-marker.md` §3's table survives:

| | |
|---|---|
| **0** | 04 rings. In a call, off-hook or switched out: the first free port that answers to 04, in slot order — a second position, then the announcement, which answers by itself |
| **a group** | the number's own port first, then its members in slot order. Priority is where a card is plugged in |
| nobody free answers to it | cannot-complete, one hunt later |

### 2.5 The marker's part, and the time

| | |
|---|---|
| the comparison | a 74HC688: the word's six bits of number against the called number |
| the called number | from the digit store, as now, or from straps for 0 and 8: a 74HC244 onto the comparator's other side. The diode matrix gives a key a class or a number, where it gave a class |
| the form | two gates beside the nail's |
| | **≈ 3 packages, an estimate**, in place of the ≈ 2 of `exch-features.md` §7.4's run, which is not built. The class comparator stays, for 9 and for trunks |

**Time.** The hunt is the class hunt's: up to a scan for the scanner to come
round to 00 and a scan to go round, **two scans at most**, about 17 ms as
`exrtl` runs (`exch-rtl.md` §2). A caller to a busy number hears the tone that
much later. **One scanner is one hunt at a time**, and a second call waits for
it. At `exch-marker.md` §6's 480 calls an hour, were a third of them to hunt,
the hunt is in use for under three seconds of the hour.

### 2.6 What a number cannot do

- **No answer.** Cover is for busy and for out. Nothing times a ringing phone,
  so a call that rings unanswered rings on.
- **Call waiting, transfer, camp-on, pre-emption.** Each needs something in
  charge of a call, and nothing is (`exch-marker.md` §5). No width of word buys
  them.
- **Another exchange.** The number is `h s`. A number elsewhere is four digits,
  and the network has no sender to send them (`ex-extensions.md` §3.4).

---

## 3. The secondary word

A port that already has something to say — a restricted phone, a data port, a
conference leg — has no room left to answer to a number: seven bits of class and
options, six of number. It needs a second byte.

### 3.1 How sixteen bits are read

A card's word pin is on the probe bus only in its own cell, once a frame,
because the block's commutator is addressed by `SLOT` (`exch-fabric.md` §3.1),
and the scanner rests on a port for one octet. **One pin is eight bits a visit,
and there are two ways to sixteen.**

| | what it costs |
|---|---|
| **two octets a visit** | no wire, and the scan doubles. A hop of the flood is two scans, about 17 ms as built (`exch-rtl.md` §2), against the origin's 128 ms guard (`exch-monitor.md` §3): it would be about 34. Every hunt, every nail's re-write and every time `exrtl` has measured moves with it. And the card must be told which octet is which, which is a new clock on the same spare pin. **Rejected** |
| **a second pin** | two bits a frame, side by side, in the same visit. The scan, and every measured time, stays where it is |

### 3.2 The pin, and the path

`ex-extensions.md` §2.1 left one of the slot's three reserved pins spare:

| pin | on the MF8 shelf | in the exchange | at the port | on the card |
|---|---|---|---|---|
| a12 | `TYPE0`: reserved | the **primary** word: `ex-extensions.md` §2.2, with §2.1's form | unchanged | unchanged |
| a13 | `TYPE1`: reserved | `/ANS` | unchanged | unchanged |
| a14 | `RAI`: reserved | **the secondary word** (§3.3) | a pull-up: open reads "no number" | left open by every card with nothing to say here; otherwise a second '165 into a second gate of the same '03 |

- **One card still serves both shelves.** The MF8 shelf connects none of the
  three, and its remote alarm is between trunk cards and reaches the panel from
  the trunk slot (`mf8-backplane.md` §8), so a14 stays open there.
- **The card**: the second '165 is loaded and shifted with the first, and the
  one hold-off RC gates both. **≈ 1 package and eight jumpers more**, on a card
  that wants it.
- **The block**: a fifth '151 commutates the eight a14 pins onto a third probe
  line, `PB2`, through a spare section of the `PB` driver. **Only a block that
  holds a card with a secondary word needs it.** The position is on every block,
  and unfilled its line is tied to "no number".
- **The cable**: `PB2` on cable B pin 1, its one spare (`exch-mainboard.md`
  §3.2), pulled low at the marker as `PB[1:0]` are, and one more signal at the
  block connector.
- **The trunk socket carries no secondary.** A tie trunk says everything in one
  byte, and a subscriber terminal's lines (`exch-terminal.md` §3) say what the
  primary can say.

### 3.3 The word

```
 frame of the octet    0  1    2  3  4    5  6  7
 the secondary word    k  k    h  h  h    s  s  s     a number, and what it is to this port
 no number             0  0    ·  ·  ·    ·  ·  ·     the pin left open
 answers to            0  1    h  h  h    s  s  s     as §2.1's form, on a port whose primary says something else
 lifts to              1  0    h  h  h    s  s  s     this port's lifting is a call to h s
 spare                 1  1
```

- **Answers to.** §2.2's hunt takes this port as it takes one that says so in
  the primary. A port may say it in both words, and then it answers to two
  numbers: a secretary who covers two.
- **Lifts to** is the warm line of `ex-extensions.md` §2.4, to any number of its
  own exchange. The port's lifting is a call to `h s` with no register: the
  probe, then the hunt, then cannot-complete. **`w` remains, in the primary, as
  *lifts to 04*.** A ringdown to another phone of the same exchange is then one
  jumpered word, where it was a nail holding two latches or the ≈ 8 packages of
  `ex-extensions.md` §3.4's dialling card. To another exchange it is still the
  card that dials (§2.6).
- **`o`, a line's overflow bit, keeps its name and loses its neighbours.**
  Dialled, not free, and `o` set: the hunt is for the number this port answers
  to, and not for its own. A member's own calls then roll to its group when it
  is busy. The bit is an option and its number cannot share a word with it, so
  `o` is a card with both words.

| at the marker | |
|---|---|
| the second byte | 74HC164 |
| a port may answer from either word | a second 74HC688 |
| a number that came from a word, held while the scanner moves on: *lifts to*, and `o` | 74HC574 |
| | **≈ 3 packages, an estimate** |

### 3.4 What it takes

**The last spare pin of the slot and the last spare conductor of cable B.**
`/HUNT_INH` wanted the same two: `exch-basebandcard.md` §2 found it specified
and landing nowhere, and named a14 and a third `PB` line as what a card in a
channel slot would need in order to drive it. After this it cannot have them.
Nothing built is lost. The only card ever proposed to drive it is the network
card, which stands beside the marker and can reach it on a ribbon of their own
as the registers do, and `exrtl`'s marker has no such line at all: it reads the
direction bits itself.

---

## 4. What goes in which word

Both words arrive in the same visit, so nothing is later for being in the
secondary. Three things decide.

1. **Who else reads it.** The marker is not a word's only reader. A trunk
   monitor takes the slot's word off its own block's commutator and attends only
   a slot that says trunk, and a nailed channel is left alone *because it sends
   a nail and not a class* (`exch-monitor.md` §4). The network card reads a
   trunk's direction off the probe (`exch-network.md` §3.2). The port watch
   shows the class from one '164 on `PB1` (`ex-observers.md` §5). None of them
   should grow a second register. **What another card reads is primary.**
2. **What a missed secondary reads as.** A block without its fifth '151, an
   exchange without `PB2`, a bent pin: the port is then read by its primary
   alone, and that reading must be safe. A restriction that is missed is an
   unrestricted phone. A class that is missed is a trunk handed a register. A
   number that is missed is a member that gets no calls, or a warm line that
   gets dial tone: both fail quiet. **What is unsafe to miss is primary.**
3. **How many cards say it.** The cost is a '165 and eight jumpers on every card
   that speaks, for the life of the card. Plain lines are most of an exchange
   and say nothing. Of the rest, the members of groups and the phones that cover
   are the most. **What many cards say goes where one '165 says it.**

| what | if primary | if secondary | goes |
|---|---|---|---|
| the class | every reader has it; one '165 on a card with a class, as now | unsafe to miss; a second register in every monitor | **primary** |
| a trunk's `d d g n` | one '165 for six channels, as now, and the network card reads it | six more lines at the trunk socket | **primary** |
| `r` | as now | unsafe to miss | **primary** |
| `w`, to the operator | one bit: the operator is 04, and needs no jumpers to say so | six jumpers to say 04, and the read-out on its block | **primary** |
| a nail | as now, and the monitor's rule rests on it | the port would keep its class, which only a traffic counter wants; still one '165 on a plain card | **primary** |
| answers to, on a plain phone | one '165 on the commonest card that says anything. 77 excluded | the fifth '151 on every block with a member on it | **primary**: §2.1's form |
| answers to, on a port with a class or options | no room | fails quiet | **secondary** |
| a second number | no room | fails quiet | **secondary** |
| lifts to any number | fits only by breaking the class field, below | the rare case of `w`; fails quiet, as dial tone | **secondary** |
| `o` | the bit, among the options | its number | both |
| 9 as a number, as 0 is | no room beside class *outside line*, which ringing in needs | a second '165 on every FXO card, to replace a hunt that works | **neither: 9 stays a class hunt** |

**A tighter primary was considered and is not proposed.** Cut the class form to
`0 0 c c c p p p` and three quarters of the codes are numbers: *lifts to* fits
in the primary as a third kind. But a trunk needs four option bits and would
have to take two class codes to find them, and the class would no longer be the
same three frames of every word, which is what the monitors, the network card
and the port watch decode. It would save one '165 on the rarest card here.

**Who then needs what:**

| the card | primary | secondary | parts for its words |
|---|---|---|---|
| a plain line; the first operator's position | the pin to ground | open | none |
| a tie trunk, a source, an outside line, a data line; a restricted line; a warm line to the operator | class and options | open | ≈ 1¼, as now |
| a nailed port | the nail | open | ≈ 1¼, as now |
| **a member of a hunt group, a covering phone, a second position, a night announcement, an extension phone (§6)** | **answers to** | open | **≈ 1¼** |
| a port that lifts to a number | the pin to ground, if it has no more to say | lifts to | ≈ 1¼ |
| a restricted or a data member of a group; a line with `o`; a phone that covers two | class and options, or a number | a number | ≈ 2¼ |
| a conference leg | class, and `p` (§6.4) | answers to its bridge | wired on the block (§5) |

**Most exchanges will fit the secondary read-out in one place, the conference
block**, which builds it into its own fabric. An exchange with no bridge and no
card that speaks on a14 never fits it, and gives up nothing in §2.

---

## 5. A bridge is a group

`exch-features.md` §7.4 makes a bridge a run: adjacent legs, `o` on all but the
last, its number its first leg's. **Its legs answer to its number instead.**

```
                70   71   72   73   │ strap │   74   75   76   77

  answer to     70   70   70   70   │   ○   │   74   74   74   74      strap out: two bridges of four
                70   70   70   70   │   ●   │   70   70   70   70      strap in: one bridge of eight
```

- **74 and 70 differ in one bit, and the strap that joins the party bus forces
  it** on four legs, where it carried the overflow bits (`exch-features.md`
  §7.3). It is still one strap, and still nothing on it can disagree with
  anything else.
- **The marker's run goes**: its flip-flop, its comparator of the scanner
  against the digit store, its ≈ 2 packages and its rule that a run never
  crosses a block boundary. That a party bus never leaves its block is the
  block's business, and was never the marker's.
- **A leg says class 111 in the primary and its bridge's number in the
  secondary**, wired and without jumpers, the first leg like the rest, and the
  block carries its own fifth '151. §6 needs the class. Where only a meet-me
  bridge is wanted and the secondary read-out is not fitted, the legs say §2.1's
  form instead and are plain lines that answer at once: §2.2 serves them with
  nothing added.
- A bridge is dialled as it was, `h s` or `1 e b h s`, and 8 stays out of it.

---

## 6. A group with a bridge in it

### 6.1 What is wanted

A main number with extensions: every phone rings, whoever answers has the call,
and a phone lifted later is in it too. The fabric gives the ringing for nothing —
any number of latches may point at one port, and a port rings itself. It cannot
give the third, because **CVSD bits cannot be added** (`exch-features.md` §7).
And it cannot give the second without something that remembers which phones were
rung, because latches cannot be read back (`exch-network.md` §3.2). A bridge is
the exchange's one way of putting three parties in a call, and §5 has made it
something a group can hold.

**Phones that answer to a bridge's number are its extensions.** Nothing else
marks them: their cards say §2.1's form and no more.

### 6.2 A call

```
 70 is dialled             the probe finds a leg.  The caller is given a free leg of 70: two writes, as any call.
                           The leg answers at once, as it always did
 the bridge rings out      one party is present, so every other leg of the bridge raises its M (§6.3)
 the marker pairs          each free phone that answers to 70 with a free leg of 70: two writes a pair, as any
                           call.  The phone's E is its leg's M, so it rings in the cadence, by its own port's gates
 a phone answers           its leg sees A_RX rise: two are present.  Ring-out drops, every unanswered leg's M falls,
                           the other phones stop at once, and each unanswered pair releases itself 256 ms later
                           (exch-marker.md §5).  No marker
 a phone is lifted later   a call request from a port that answers to 70.  Before dial tone the marker looks for a
                           busy leg of 70.  There is one: the phone is given a free leg of 70, and no register
 anyone hangs up           that pair releases itself.  The rest talk on
```

**Nothing remembers the call.** Every pair is an ordinary call of two latches
that supervises itself. Ringing comes from a leg's M, so it stops when the
bridge says so and needs nobody to stop it. And what tells the marker that a
phone lifted later belongs in a call is a leg's `BUSY`, which it reads on the
probe like any other: **the legs are the record.**

### 6.3 The bridge's part

```
 bus, added   PRES   a leg's caller is off-hook            TWO    a second one is          (both open-drain)
              SEEN   a daisy chain in slot order: a leg before this one is present.  A leg that is present
                     and sees SEEN pulls TWO
              DATA2  the previous holder's C_RX            PREV   a previous holder is driving it
 ring-out     OUT  = PRES · /TWO                           exactly one party present.  A strap enables it
 A_TX         = A_RX + OUT                                 was A_RX.  A leg rings the phone it is paired with
 spoke        counts only while A_RX + /TWO                a ringing phone's ringback may hold the floor while
                                                           there is nobody to interrupt, and never after
 C_TX         the holder:  PREV → DATA2, else FILL         was FILL
              the others:  HELD → DATA,  else FILL         as it was
 strap        the bus strap cuts these five with the other five                  (exch-features.md §7.3)
```

| per leg, added to `exch-features.md` §7.3's ≈ 9 | parts |
|---|---|
| `PRES` and `TWO` open-drain, the `SEEN` chain, `OUT`, the OR into `A_TX`, the detector's gate | ≈ 1 |
| `DATA2` three-state and `PREV` open-drain, the previous-holder flip-flop, the holder's `C_TX` select | ≈ ½–1 |

- **Ring-out is a strap, and a meet-me bridge leaves it out.** Under it *every*
  idle leg raises M, paired or not, and when it drops each reads busy for 256 ms
  while its detector times out (`exch-fabric.md` §3.5). On an extension bridge
  that costs a phone lifted in that quarter second its place: it gets dial tone.
  On a meet-me bridge it would cost a third party arriving within a quarter
  second of the second, which is likelier, and would buy nothing.
- **A leg's free test is `BUSY` alone.** M is part of every other port's
  (`exch-marker.md` §1), and a leg's M is up whenever its bridge is ringing out.
  A leg is never a call request, as now.
- **Ringback reaches the caller through the floor.** A ringing phone's port
  sends `RBT` in place of its voice (`exch-fabric.md` §3.5), so its leg hears
  ringback, and while one party is present it may take the floor with it: the
  caller hears ringback in the caller's own silences. With two present such a
  leg is mute, or ringback would take every pause in the conversation.
- **The second `DATA` line is what makes this usable.** Every call to an
  extension group goes through the bridge, and as `exch-features.md` §7.1 stands
  the holder of the floor hears nobody: between two parties that is a
  half-duplex call. §7.5 declined the cure, and this needs it. The previous
  holder drives `DATA2` with its caller's bits, and the holder listens there.
  **Between two parties each then hears the other all the time**, whichever
  holds the floor, from the first time the floor changes hands, and its changing
  hands again changes nothing either of them hears. Among three or more, the
  holder hears the last to hold it.
- **A call-out conference is one more strap**: ring out while *anyone* is
  present, for a count of `RING_CAD` bursts (½ 74HC393 a bridge), and everyone
  who answers is in.

### 6.4 The marker's part

```
 a call lands on a leg          the probe of the called h s finds class 111
   one pass                     the first free leg that answers to h s, and whether any leg that answers to h s is busy
   p set, and one was busy      cannot-complete: the number is engaged
   no free leg                  cannot-complete
   else                         caller ↔ that leg: two writes, as any call
   then, while both are found   the next free leg of h s; then the first free port that answers to h s and is not
                                a leg, written at the visit that finds it: phone ↔ leg, two writes

 a port that answers to h s lifts
   one pass, before dial tone   a busy leg that answers to h s, and a free one
   both                         the port ↔ the free leg: two writes, and no register
   otherwise                    a register and dial tone, as any caller
```

| | |
|---|---|
| the passes | §2.2's hunt with two more terms in its match — class leg, and busy in place of free — and a flag, *a busy leg was seen* |
| a leg in hand while a phone is looked for | 74HC574 |
| the sequence | states in the sequencer |
| | **≈ 4–5 packages, an estimate, not drawn** |

- **A leg is never taken on the probe alone.** Every leg is given out by the one
  hunt, so two calls cannot be given the same leg, and a pair is written at the
  visit that finds its phone.
- **`p`, a leg's option: private.** A call that would land on a bridge with a
  leg already busy gets cannot-complete: the number is engaged. An extension
  group sets it, or a second outside caller joins the first one's call. A
  meet-me bridge leaves it clear, since joining is what it is for. Extensions
  join by lifting, and `p` does not stop them.
- **Every port that answers to a number pays one pass before dial tone**, bridge
  or no bridge: up to two scans. A card could say *extension* and spare the
  rest, but §2.1's form has no bit for it, and the pass is cheaper than a second
  '165 on every extension.
- **The hunt is held for up to two scans a pair**: a main number and three
  extensions, about 70 ms.

### 6.5 What it costs the call, and what it cannot do

- **Legs.** One for the caller and one for every phone rung. A bridge of four is
  a main number and three extensions, and a fourth phone is not rung. After the
  first answer the unanswered legs are free again.
- **Voice-switched**, with `exch-features.md` §7.5's limits among three or more:
  one talker at a time, a quiet party seldom heard, a noisy one holding the
  floor.
- **An extension's own call is an ordinary call.** It uses no leg, so nobody can
  join it.
- **A caller left alone stays.** When the last extension hangs up, the outside
  caller's leg still answers it, and it hears silence until it hangs up, where
  an ordinary call would have released it to dial tone (`exch-marker.md` §5.1).
  A bridge that dropped a lone party would cure that and break meet-me, where
  the first to arrive waits.
- **It needs a conference block**: ≈ 154 packages before §6.3's additions
  (`exch-features.md` §7.3), and one of the six dialable blocks.

### 6.6 Set aside: ringing every phone without a bridge

`exch-network.md` §3.2's resolver would do it: hold the caller's address and the
phones', point every phone at the caller, and at the first M to rise point the
caller at that phone and the rest at idle. The call is an ordinary one, full
duplex, and costs no legs. But it must remember a call for as long as it rings,
tens of seconds where a hub's resolver holds two or three; it needs a way for a
card to say *ring us all*, which §2.1's form has no bit for; and a phone lifted
later still gets dial tone. **The bridge does more and remembers nothing.**

### 6.7 Which to use

| | a hunt group (§2) | cover (§2) | extensions on a bridge (§6) |
|---|---|---|---|
| rings | the first free member | the covering phone, when the number is busy or out | every free member at once |
| the call | two latches, full duplex | the same | through a bridge: voice-switched, and full duplex between two with `DATA2` |
| a phone lifted later | dial tone | dial tone | joins |
| a member's card | §2.1's form, ≈ 1¼ | the same | the same |
| needs | §2.5's ≈ 3 at the marker | the same | a conference block with ring-out, the secondary read-out on it, and §6.4's ≈ 4–5 |
| remembers | nothing | nothing | nothing: the legs' `BUSY` is the record |

---

## 7. Together

| stage | gives | adds | spends |
|---|---|---|---|
| **A. the number** (§2) | hunt groups, cover, operator's positions and night service, a bank on 8, a meet-me bridge as a group | ≈ 3 at the marker, for the ≈ 2 of the run. Cards as they are | nothing |
| **B. the secondary word** (§3) | a number on a port with a class or options; a second number; *lifts to*; `o` | ≈ 3 at the marker; a '151 on each block that wants it; a '165 on each card that wants it; `PB2` | a14; cable B's spare; `/HUNT_INH` in a channel slot |
| **C. a bridge that rings out** (§6) | extensions that ring together and join; a call-out conference | ≈ 1½–2 a leg and five wires on the block's own ribbon; ≈ 4–5 at the marker | legs |

A stands alone. B can be fitted to an exchange already running A, a block at a
time. C needs B on the conference block and nowhere else.

---

## 8. What it would change

| where | what |
|---|---|
| `ex-extensions.md` §2.1, §2.2, §2.4 | a14; §2.1's form; the secondary word; `o` re-defined and `w` kept as *lifts to 04*; class *operator*'s code spare |
| `exch-marker.md` §1–§4 | reading a number becomes §2.2; 0 is a call to 04; the diode matrix gives a number as well as a class; two calls at one visit |
| `exch-features.md` §4, §7.1, §7.3–§7.5 | the operator; the party bus; what the strap carries; the marker's part; the second `DATA` line |
| `exch-fabric.md` §2, §3.1, §3.5 | `PB[2:0]`; the fifth '151's position; the class table |
| `exch-mainboard.md` §2.3, §3.2, §3.3 | `PB2` on cable B pin 1, and at the block connector |
| `exch-marker.md` §4, `exch-network.md` §3.2, `exch-basebandcard.md` §2 | `/HUNT_INH` is a wire between two cards and not a line of the bus |
| `mf8-backplane.md` §8, `ex-observers.md` §5 | what a14 is; the watch's second '164 |
| `exrtl` | `marker.v`: a call that fails its probe hunts, where it gave cannot-complete; the hunt's match takes a number, and takes its port at the visit; `C_OPER` goes. `block.v` and the cards: a second word. The word's layout there is its own, the class in the first three frames and no form bit (its README, "the word's encoding"), and would take this one along with the nail |

---

## 9. Not measured

- **All of it.** None of this is in `calls` or in `exrtl`, and the run it
  replaces never was either.
- **The form's decode** beside the nail's and the all-ones detector, and the
  power-up hold-off against a byte that is now a nail or a number one time in
  two.
- **A failed probe that hunts.** Every call to a busy number takes the one hunt,
  and so does every lifting of a port that answers to a number (§6.4), which
  also holds a register for up to two scans. §2.5's load is arithmetic on
  `exch-marker.md` §6's calling rate, not a run.
- **Taking a port at the visit that finds it**, against a direct call to that
  port at the same visit (`exch-rtl.md` §2), and against the serialiser: the
  write is on the bus some words after the visit, and the port reads free until
  it lands.
- **a14 as a word pin**: its pull-up and the '03's second gate, the fifth '151
  as one more load on the block's `SLOT`, `PB2` through the `PB` driver, and a
  forty-ninth signal at the block connector.
- **`/HUNT_INH`'s ribbon** between the network card and the marker, which no
  document has drawn either.
- **Ring-out**: `PRES`, `TWO`, `SEEN` and `OUT` as gates; a leg's M under `OUT`
  against its own port's detectors, and the quarter second a freed leg reads
  busy. **Whether `RBT` trips the runs-of-three detector at all**: `exch.py
  confer` has run speech and room noise, not a tone. If it does not, a caller to
  an extension group hears silence where ringback should be.
- **`DATA2`.** `exch.py confer` measured a *listener's* decoder across a change
  of talker (`exch-features.md` §7.2). The holder's decoder changing its source
  is a case it has not run, and neither is a two-party call through a bridge:
  its double talk, and its first words before the floor has changed hands.
- **The pairing**: a phone that lifts, or is dialled, at the visit that pairs
  it; legs running out part-way; two calls to one bridge queued on the hunt.
- **How many legs an extension group wants**, against `exch-features.md` §7.3's
  two bridges of four, and the call-out strap's count of bursts.
