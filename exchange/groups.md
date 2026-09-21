# The exchange — groups: a number in the word, and a bridge that is a group

The marker finds a port it was not given the address of in three ways, and each
was written for one purpose. `marker.md` §3 hunts a **class**, for 0 and
for 9. `extensions.md` §2.4 walks a **run** of adjacent ports marked `o`, for
a hunt group and for a conference bridge (`conference.md` §6). And
`network.md` §3.2 hunts a trunk by its **direction**. A second operator's
position, a sales desk, a pool of data ports, a bridge's legs and a bank of
call-in lines are all one request — *the first free port of these* — and only
the trunk hunt is really a different one.

This document proposes one rule for everything but the trunks: **a port may say
that it answers to a number** — in the **one** word on `a12`. A conference
bridge is then a group of ordinary lines. Class *conference* is **retired**
(code `111` is now *restricted*); the secondary word on `a14` and the fifth
`'151` / `PB2` path are **retired** as well.

The short answers, before the detail:

- **A number, not a group number.** A card says "I answer to `h s`", and a call
  to `h s` that cannot be completed there is offered to it. A group is named by
  the number people dial, so there is no second numbering to keep, no limit on
  how many groups, and no rule about which slots.
- **One `'165`, or none.** The word gets one new form, *a plain line that answers
  to `h s`*, in the last unused quarter of its code space. A second operator's
  position, a member of a hunt group, a phone that covers another and a meet-me
  bridge leg all say it with the parts a nail takes today.
- **No second byte.** A port that already carries class or options cannot also
  *answer to* a number in this plan: use a plain member beside it, or the old
  `o` run. `w` stays lifts-to-04. Pin `a14` stays spare.
- **A bridge is a group, at no cost**: its legs answer to its number (or keep the
  `o` run of `conference.md` §6), as ordinary lines with `/ANS` low.
- **§6** (extensions that ring together through a bridge) and **§3–§4** (secondary
  word) are **set aside** with class 111 and the fifth `'151`.

> **Status: proposed. Nothing here is measured.** None of it is in the `calls`
> model or in `verilog`. The class hunt it partly replaces is measured in `calls`
> and built in `verilog`, where no bench yet dials 0 or 9; the run it wholly
> replaces was never in either. Every package count is an estimate from parts
> the other documents already use, no circuit has been drawn, and nothing has
> been on a bench. The conference bridge of `conference.md` — switch and
> detector — *is* measured (`exch.py confer`); only how the marker finds a leg
> changes here. §9 lists what is owed.

---

## 1. Three hunts, and what each cannot do

| | written for | finds | built |
|---|---|---|---|
| **a class** (`marker.md` §3) | 0, 9 | the first free port of the class, in fixed order from 00 | in `verilog`; measured in `calls` |
| **a run** (`extensions.md` §2.4, `conference.md` §6) | a hunt group, a bridge | from the dialled port onward, the first free port, while each busy one has `o` set | no |
| **a direction** (`network.md` §3.2) | tie trunks | a free trunk facing each way | in `verilog`, and measured there |

**The class hunt cannot make a second group.** One class is one group. A bank of
call-in lines on key 8 would be a new class, and all eight codes are taken
(`fabric.md` §3.5).

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
in the word. A line's options have one bit spare; restricted uses all four
(`z w b L`, with `w` reserved) (`extensions.md` §2.4).
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

The word of `extensions.md` §2.2 has two forms and two constants, and a
quarter of its codes — bit 0 and bit 7 both set, short of all ones — mean "no
word". That quarter is a number:

```
 frame of the octet    0    1  2  3    4  5  6  7
 class and options     0    c  c  c    p  p  p  p     as it is                         (extensions.md §2.2)
 a nail                1    h  h  h    s  s  s  0     as it is                         (extensions.md §3.1)
 answers to            1    h  h  h    s  s  s  1     NEW: a plain line that answers to h s
 a plain line          1    1  1  1    1  1  1  1     the pin tied to ground
 nothing               0    0  0  0    0  0  0  0     an empty slot; out of service; a link down
```

| | |
|---|---|
| **The card** | the word's parts as they are, ≈ 1¼ packages, with the number in the jumpers. It is a plain line in every other respect: class line, no options. Whether it rings is still `/ANS`, so an announcement card at the end of a hunt ties that pin low and says the rest in this form |
| **The marker** | bit 0 set, bit 7 set, and not all ones: the nail's own decode with bit 7 taken the other way |
| **77** | cannot be answered to in this form, which would be all ones. A group takes another number |
| **Power-up** | a random byte is a nail or a number one time in two, where it was a nail one time in four. The hold-off of `extensions.md` §2.2 already covers it, and a number held for 100 ms is harmless where a nail is not |

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
  cannot-complete at once (`marker.md` §2), and now gives it one hunt later.
- **The port that owns the number needs no word for this.** It is found by its
  address, as every port is. 04 is the operator's phone on a plain line card.
- **A port that answers to a number keeps its own.** Dialled by its address it
  rings if it is free and gives busy if it is not. The number it answers to
  brings it only calls that were meant for another port and could not go there.
- **One hunt a call, never a chain.** The port the hunt finds is free, so there
  is nothing to pass on.
- **The port found is taken at the visit that finds it**: the two writes are
  issued then, and not at the end of the pass, because a first-free hunt has
  nothing to wait for. The class hunt as built in `verilog` notes the port and
  writes at the end of its pass, and a marker that probes a dialled port out of
  the scanner's turn (`marker.md` §4) can find that port still free in
  between. What is left is two calls at one visit, and `rtl.md` §2 has the
  rule: the first takes the line and the second is told busy.
- **A key's pilot sits in 00–07**, which nobody can dial (`protocol.md`
  §5), so it collides with no line's number. A pilot need hold nothing: an empty
  slot fails the probe and the hunt follows. **0's pilot is 04 because the
  operator's phone is already there.**
- **9 stays a class hunt.** An outside line needs its class in any case, for
  ringing in (`marker.md` §3), so the class hunt costs its card nothing,
  and it is built. §4 has the trade.
- **Across the network nothing changes.** `h s` means after `1 e b` what it
  means at home (`marker.md` §2), so a group, a covered number and a bridge
  are reached from anywhere.

### 2.3 What a number gives

| | how |
|---|---|
| **a hunt group** | its members answer to the number people dial. A sales desk at 55 is the phone at 55 and two more, in any slots, that answer to 55. Any number of groups. The number may be an empty slot's, and then every member is found by the hunt |
| **a second operator's position, and the night announcement** | lines that answer to 04. Class *operator* is not needed: its code is spare, and the first position's card carries no word at all |
| **night service** | the operator's out-of-service switch (`extensions.md` §2.2): 04 reads unequipped, and 0 goes on to whoever answers to 04 |
| **cover** | a secretary's phone answers to 23. It rings when 23 is busy, switched out or pulled, and only then |
| **a call-in bank on one digit** | key 8 strapped to a pilot, and the bank's lines answer to it |
| **a message at the end** | an announcement card (`features.md` §3), `/ANS` low, that answers to the number and sits after the group's last member |
| **a bridge** | §5 |

### 2.4 Fixed order is still the feature

`marker.md` §3's table survives:

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
| | **≈ 3 packages, an estimate**, in place of the ≈ 2 of `conference.md` §6's run, which is not built. The class comparator stays, for 9 and for trunks |

**Time.** The hunt is the class hunt's: up to a scan for the scanner to come
round to 00 and a scan to go round, **two scans at most**, about 17 ms as
`verilog` runs (`rtl.md` §2). A caller to a busy number hears the tone that
much later. **One scanner is one hunt at a time**, and a second call waits for
it. At `marker.md` §6's 480 calls an hour, were a third of them to hunt,
the hunt is in use for under three seconds of the hour.

### 2.6 What a number cannot do

- **No answer.** Cover is for busy and for out. Nothing times a ringing phone,
  so a call that rings unanswered rings on.
- **Call waiting, transfer, camp-on, pre-emption.** Each needs something in
  charge of a call, and nothing is (`marker.md` §5). No width of word buys
  them.
- **Another exchange.** The number is `h s`. A number elsewhere is four digits,
  and the network has no sender to send them (`extensions.md` §3.4).

---

## 3–4. Set aside: the secondary word

> **Retired with the conference / secondary-word path.** A second `'165` on
> `a14`, a fifth `'151` onto `PB2`, and the trade of what goes in which byte,
> lived here so a port could carry class/options *and* an *answers to* /
> *lifts to* number. Conference legs were the main customer; they no longer
> need it. Without that path: a restricted phone (class `111`) cannot also
> *answer to* a number in the same word — use a plain cover member or the `o`
> run; *lifts to* any number other than 04 is not offered (`w` remains
> lifts-to-04); one phone covers one number, not two. Pin `a14` is spare again.

---

## 5. A bridge is a group

`conference.md` §6 makes a bridge a run: adjacent legs, `o` on all but the
last, its number its first leg's. **Its legs answer to its number instead.**

```
                70   71   72   73   │ strap │   74   75   76   77

  answer to     70   70   70   70   │   ○   │   74   74   74   74      strap out: two bridges of four
                70   70   70   70   │   ●   │   70   70   70   70      strap in: one bridge of eight
```

- **74 and 70 differ in one bit, and the strap that joins the party bus forces
  it** on four legs, where it carried the overflow bits (`conference.md` §5).
  It is still one strap, and still nothing on it can disagree with
  anything else.
- **The marker's run goes**: its flip-flop, its comparator of the scanner
  against the digit store, its ≈ 2 packages and its rule that a run never
  crosses a block boundary. That a party bus never leaves its block is the
  block's business, and was never the marker's.
- **A leg says §2.1's form** (*answers to* the bridge number) in the primary,
  wired and without jumpers, the first leg like the rest. **No secondary word,
  no fifth `'151`, no class *conference*.** Legs are ordinary lines with `/ANS`
  low. §2.2 serves them with nothing added.
- A bridge is dialled as it was, `h s` or `1 e b h s`, and 8 stays out of it.

---

## 6. Set aside: a group with a bridge in it

> **Retired with the conference-leg class.** Extension phones that all ring
> through a bridge, ring-out, `DATA2`, and a marker pass that distinguished
> *leg* from *phone* by class, lived here. Without a conference class the
> marker cannot tell a leg from a cover phone that answers to the same number.
> Meet-me (§5) and ordinary hunt groups (§2) remain. Re-open only with a way to
> mark a leg that is not a class — layout, a pin, or another word form.
> (Code `111` is now *restricted*, not spare.)

---

## 7. Together

| stage | gives | adds | spends |
|---|---|---|---|
| **A. the number** (§2) | hunt groups, cover, operator's positions and night service, a bank on 8, a meet-me bridge as a group | ≈ 3 at the marker, for the ≈ 2 of the run. Cards as they are | nothing |

A stands alone. A meet-me bridge needs only A (or the `o` run of
`conference.md` §6). Secondary word and extensions-on-a-bridge are set aside.

---

## 8. What it would change

| where | what |
|---|---|
| `extensions.md` §2.2, §2.4 | §2.1's form (*answers to*); `o` may be re-defined for busy→group; `w` kept as *lifts to 04*; class *operator*'s code spare; class *restricted* at 111; **a14 stays spare** |
| `marker.md` §1–§4 | reading a number becomes §2.2; 0 is a call to 04; the diode matrix gives a number as well as a class; two calls at one visit; no conference class; restricted is a class |
| `features.md` §4; `conference.md` §1, §3, §5–§6 | the operator; the party bus; what the strap carries; legs as ordinary lines |
| `fabric.md` §3.5 | class 111 *restricted* |
| `protocol.md` §5, `network.md` §2–3 | 0 and 8 as numbers; nothing of the hunt itself |
| `mvp.md`, `rtl.md`, the `calls` model, `verilog` | 0 as a call to 04; the hunt; no conference class; no `PB2` |

---

## 9. Not measured

- **All of it.** None of this is in `calls` or in `verilog`, and the run it
  replaces never was either.
- **The form's decode** beside the nail's and the all-ones detector, and the
  power-up hold-off against a byte that is now a nail or a number one time in
  two.
- **A failed probe that hunts.** Every call to a busy number takes the one hunt.
  §2.5's load is arithmetic on `marker.md` §6's calling rate, not a run.
- **Taking a port at the visit that finds it**, against a direct call to that
  port at the same visit (`rtl.md` §2), and against the serialiser: the
  write is on the bus some words after the visit, and the port reads free until
  it lands.
- **A meet-me bridge as *answers to*** (§5), against the `o` run already in
  `conference.md` §6.
