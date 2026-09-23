# The exchange — the card option word at nine-bit ports

`extensions.md` §2.2's word is sixteen bits because sixteen bit-times at
128 kHz is 125 µs and so is a scanner visit. Three-digit dialling makes a port
address **nine** bits, and three of the word's forms no longer fit. This
document is §2.2 re-laid-out for nine-bit targets: the reserved forms and dual
membership are dropped, the fields are reordered so that **the common card
still fits one chip and only an address form needs two**, and the fitting rule
moves to the first bit out of the register.

Nothing else about the word changes. The pin is still low for a 1, a plain line
is still a grounded pin with no part fitted, and an empty slot still reads all
zeros.

> **Status: proposed, not measured.** No circuit has been drawn and nothing has
> been on a bench. The bit budget is arithmetic on `extensions.md` §2.2's own
> layout; the visit figure is that section's. `marker.v`'s word decode is
> written for the six-bit form and would have to be rewritten for this one
> whatever layout is chosen.

---

## 1. What forces the change

| | |
|---|---|
| **Nine-bit ports** | `hhhhh ssss` — 32 blocks of 16 slots, 512 ports (`protocol.md`, three-digit dialling). A target that was six bits is now nine |
| **Sixteen is a visit, not a budget** | 16 ÷ 128 kHz = 125 µs, and the scanner rests exactly one `CLK_8K` period a port (`extensions.md` §2.2). A wider word at the present shift rate does not fit a visit — §6 |
| **Only address-bearing forms overflow** | a class form carries no port and is unchanged at eight bits. A plain line is a constant and fits no part at all |

At nine-bit targets the old layout overflows in four places: `cover` by three
bits, `dual member` by four, and the two reserved network forms by three each.
Everything else fits sixteen bits — but a single-target form now spans both
chips where it used to fit one, which is what §2 reorders to make explicit.

---

## 2. The layout

Printed in wire order, bit-time 0 leftmost, every field LSB first, as
`extensions.md` §2.2 prints its own. **Every anchor stays where it was**: `tt`
at bit-times 0–1, the class family at 2–3, the secondary tag at 8–9. So every
prefix decode in §2.2's *"Reading only the first bits"* survives unchanged, and
the monitor's four bits and the port watch's octet cost exactly what they cost
today.

```
bit-time      0 1   2 3 4 5   6 7   8 9   10 11 12   13 14 15
tied nail     0 0   s s s s   h h   0 1    ·  ·  ·    H  H  H     dest HHH hh ssss
call nail     1 0   s s s s   h h   0 1    ·  ·  ·    H  H  H
answers-to    0 1   s s s s   h h   1 0    L  U  K    H  H  H     number + conditions
class form    1 1   a a m     p p p 1 1    1  1  1    1  1  1     unchanged, FF above
```

The nine-bit target is `HHH hh ssss` — five highway bits split across the two
chips, four slot bits in the primary. The three bits it needs in the secondary
are literally the `000` MBZ that `marker.v` reads as `p_pay[5:3]` today.

**Where the room came from.** §2.2 says "Beside `FF` there are six pairings…
**Every other one is out of service, fail closed**." Four types × four tags is
sixteen pairings: four are `FF`, three live, three reserved — leaving **six
already out of service**, each carrying six payload bits where a nine-bit port
needs three. This layout spends two of them. Four stay unspent, so the word is
not full.

### 2.1 Constants

```
plain line    1 1   1 1 1   1 1 1   1 1    1  1  1    1  1  1   a grounded pin, no part
none / OOS    0 0   0 0 0   0 0 0   0 0    0  0  0    0  0  0   no card, held off, link down
```

Both are kept, and **one improves**. All ones is still the plain line, and now
doubly guaranteed: a port form can never carry tag `11`, so the constant no
longer rests solely on *restricted*'s frame-7 MBZ. All zeros is still
none/OOS — and better, because no legal word carries tag `00` any more, which
retires §2.2's wart *"tied nail to 00 collides with all zeros"*. **Port 000
becomes an expressible destination.**

### 2.2 The rule that inverts, and the bug it closes

**For a port form, an `FF` secondary is now out of service.** Today it means
"no extension", and `marker.v:233/241` enforces exactly that.

It has to invert, because at nine-bit ports a target-bearing card needs two
'165 regardless — 2 + 9 = 11 > 8. Without the inversion, a far card whose
second chip is unfitted, unseated, or still inside its ~100 ms power-up RC
reads tag `11`, which today is a legal near nail naming a real port, and the
marker does two latch writes to the wrong port.

Inverting costs nothing and **closes a fail-open that is in the design now**: a
*conditions* card with its secondary missing currently reads `FF` =
unconditional, so a night-service-only member is eligible for every hunt.

---

## 3. The properties this keeps

**Every prefix decode survives.** `tt` at 0–1 and the family at 2–3 are where
§2.2 put them, so a reader of the first four bit-times still gets the family,
and nothing that reads only the first bits has to change.

**A class card still fits one chip.** A class form carries no port: ten bits,
`FF` above, one '165 — or none at all for a plain line, which is still a pin
tied to ground. **Keeping sixteen bits saves no package on any card that
survives it**, because a target-bearing card needs two '165 at nine-bit ports
whichever width is chosen. What it saves is the socket pin of §6.

**An unfitted secondary fails safe** — §2.2 above.

---

## 4. Conditions

Conditions stay where `extensions.md` §2.2.1 put them — the `10` pairing beside
an `answers-to` — and the flags keep their meanings: `L` local callers only,
`U` unequipped owner only, `K` busy owner only, `U` ∧ `K` still OOS.

One thing re-spells. The payload's low three bits are now the target's `HHH`,
so "unconditional" is no longer `111111` but **`LUK = 000`**, which §2.2.1
already lists as equivalent ("`L U K` all clear ... stay eligible for every
hunt reason"). The `000` MBZ guard after the flags goes with the bits.

And the restriction §2.2.1 records — "a two-group member cannot be conditional
and a conditional member cannot be in two groups" — disappears with dual
membership (§5). **Every member may now be conditional.**

---

## 5. What is dropped

| | was | why it goes |
|---|---|---|
| **network nail** | `10 SSS HHH \| 00 bbb eee` | RESERVED, and now **permanently impossible**: `1 e b h s` is fifteen bits at nine-bit ports and will never fit sixteen again |
| **netwide fwd** | `01 SSS HHH \| 00 bbb eee` | RESERVED, same |
| **class flags** | `11 aam ppp \| 10 ··· ···` | RESERVED, "the last unspent space" |
| **dual membership** | `01 sss hhh \| 01 sss hhh` | **does not fit.** Two nine-bit targets is twenty-two bits against sixteen |
| **class beside a number** | `cover`: `11 aam ppp \| 01 sss hhh` | a class, its options and a nine-bit port is nineteen bits |

The three reserved forms cost nothing today — but the first two are now closed
off for good, not merely deferred, and `network.md` §9's sender would not
reopen them.

**Dual membership is a real loss.** `extensions.md` §2.2.1 calls it "the one
secondary feature the marker can actually carry out — one comparator, matched
against either number, measured in `make groups`", and its use is *one phone in
two local groups: a desk that covers two numbers*. There is no one-card
substitute, because it is the desk's own card that claims both numbers and
`cover` points the other way.

**Class beside a number is the quieter loss, and it costs two features.** The
*cover* feature itself survives as `answers-to` + `K`, which `groups.md` §2.3
already describes it as — but only on a **plain line**. What cannot be spelled
any more is a card that needs a class *and* a number:

- the **data pool** (`features.md` §8): class *line* with the `D` option, plus
  the pool's number;
- a **restricted** or **busied-out** position that also answers to a number.

---

## 6. The alternative not taken: a faster shift clock

Sixteen is a **visit** number. 1/128 kHz = 7.8125 µs and sixteen of those is
125.000 µs, one `CLK_8K` period. The RTL is exact about it: `marker.v:152`'s
`wdiv` is a ÷32 of 4.096 MHz, `w_take` fires at `wdiv == 31`, and `wdiv` is
re-zeroed on `oct_stb` — **sixteen samples a visit and no seventeenth**. The
ceiling is the marker's sampler, not the '165's shift edges. Twenty-four bits
at 128 kHz is 187.5 µs and cannot be made to fit.

256 kHz would give 93.75 µs for twenty-four bits, with eight bit-times spare,
and it is **free in the divider**: `clocks.md` §1's ÷16 tap is the one row in
that table with no customer, and it is already at every block on cable A.

**It is not free at the socket.** a2 carries 128 kHz to three customers — the
CVSD encoder, the word's two '165 and the control bus — and it is a
block-common net, so it cannot be raised for one slot: doubling it stops every
CVSD phone encoding. The clock would have to arrive on **a14, the last spare
socket pin**, which `common-cards.md` §1.2 classes with a12–a14 as a per-slot
open-drain declaration — "pull low, or leave open. Never drive high". Driving
it reverses that, ends the property that lets an exchange card sit unchanged in
an MF8 shelf, and obliges every word-bearing card to carry a pull-down so it is
safe in a shelf where a14 is unconnected.

So the faster clock is **available at a price**, not impossible. It is not
taken here because §2 keeps sixteen bits without spending the last pin, and
because what it would buy back — dual membership, class-beside-a-number, and
two reserved forms — is a smaller thing than the socket contract.

---

## 7. What has to change

| | |
|---|---|
| `extensions.md` §2.2 | the layout table, replaced by §2 above |
| `extensions.md` §2.2.1 | deleted, or reduced to the condition flags of §4 |
| `extensions.md` §§2.4, and the summary tables | lose their dual-membership clauses |
| `groups.md` §2 and its revision table | the tag-`01` story throughout |
| `verilog/rtl/marker.v` | the word decode, including the dual-membership comparator at `:176` and `:223`. It is rewritten for nine-bit targets whatever layout wins |
| `verilog/tb/tb_groups.v` | `DUAL20_25` and the dual-membership case |
| `verilog/rtl/nano_core.v` | **nothing.** It only ORs the word across the visit to test whether a card is fitted (`nano-marker.md` §4), so it is indifferent to field positions — the one part of the idiom no reordering can break |

---

## 8. Not measured

- **The visit arithmetic against a bench.** Sixteen bits at 128 kHz is 125 µs
  on paper and exact in `marker.v`'s `wdiv`; no scope has followed a '165
  through a visit.
- **The inverted `FF` rule against the power-up RC.** §2.2's argument is that a
  card still inside its ~100 ms RC must read OOS rather than a near nail. The
  RC is `extensions.md` §2.2's own figure and has not been measured.
- **What a plant needs.** Dropping dual membership and class-beside-a-number is
  a bit budget, not a survey of how many desks cover two numbers or how many
  data pools an exchange wants.
- **Whether nine-bit ports survive at all.** The card word is only one of three
  things that a 512-port exchange breaks; the flood guard and the one-highway-
  one-MF8-group rule are the others, and neither is bought with bits.
