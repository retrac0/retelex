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
`extensions.md` §2.2 prints its own.

```
bit-time        0     1 2 3     4 5 6 7
PRIMARY         E     - - -     - - - -        the first '165, or a grounded pin

  E = 1   one chip.  ccc = class, oooo = options.  The secondary reads FF.
  E = 0   two chips. aaaaaaa = target bits 0–6.

bit-time        8 9   10 11 12   13 14 15
SECONDARY       a a    k  k  k    v  v  v      fitted only when E = 0
                aa = target bits 7–8   kkk = the kind   vvv = kind-specific
```

### 2.1 Constants

```
plain line      1  111  1111  |  (no secondary)     a grounded pin, no part fitted
none / OOS      0  000  0000  |  0000 0000          no card, held off, or link down
```

Both are what they were. All ones falls inside the class forms as *line, no
options*, so a plain line still says everything it needs to with a wire to
ground; all zeros is still caught first and means nothing is there.

### 2.2 Class forms — `E = 1`, one chip

```
  ccc   oooo
  111   1111   line, no options            ← the all-ones constant lands here
  111   PbD1   line: priority, busy-out, data
  110   zb00   restricted: z b, frame 7 MBZ
  101   0000   outside line
  100   0000   source
  011   0000   tone trunk (offers-tone seat, `leaf-uplink.md` §3)
  010   gdd0   trunk: glare, then direction (`network.md` §1)
  001   ----   reserved → OOS
  000   ----   unequipped, never sent
```

The class is three bits as before; the option field gains a bit, because the
type field that used to sit at bit-times 0–1 is now the single `E` bit.

### 2.3 Address forms — `E = 0`, two chips

```
  kkk
  000  tied nail     target = dest h s              vvv = 111
  001  answers-to    the number this port answers to  vvv = 111, or L U K (§4)
  010  call nail     on lift, connect as if dialled the target   vvv = 111
  011  cover         target = the coverer           vvv = the covered class
  100  spare
  101  spare
  110  spare
  111  ILLEGAL → OOS                ← what an unfitted secondary reads
```

---

## 3. The three properties this keeps

**The fitting rule is the first bit.** `E` is bit-time 0, so a reader knows
before anything else whether a second '165 is fitted. A card that carries no
target fits one chip and straps the daisy-chain exactly as `extensions.md` §2.2
already has it; a card that carries a target fits two. Nothing else has to be
read to know which.

**The first four bit-times still decode.** §2.2 leans on "a reader of the first
four bit-times gets the right answer" for the family. Here bits 0–3 give `E`
and the whole class, which is strictly more than the old `tt aa`.

**An unfitted secondary fails safe, for nothing.** `kkk` lives in the
*secondary*, so a card whose primary says `E = 0` but whose second '165 was
never fitted reads `kkk = 111` and goes out of service. That is §2.2's "every
other pairing → OOS" preserved without reserving a block, a slot or a class
code — and it is the reason the kind field moved out of the primary.

---

## 4. Conditions fold into `answers-to`

`extensions.md` §2.2.1 spends bit-times 8–9 as a tag, so dual membership and the
condition flags are alternate encodings and "a two-group member cannot be
conditional and a conditional member cannot be in two groups".

With dual membership gone (§5) the tag is gone with it. Conditions become the
`vvv` field of an ordinary `answers-to`: `111` is unconditional — §2.2.1's own
"`111111` is no feature" — and any other pattern is `L U K` as that section
defines them. `U` ∧ `K` is still OOS.

**Every member may now be conditional.** That restriction was an artefact of
the shared tag, not of the feature.

---

## 5. What is dropped

| | was | why it goes |
|---|---|---|
| **network nail** | `10 SSS HHH \| 00 bbb eee` | RESERVED, never implemented — dead until a sender exists (`network.md` §9) |
| **netwide fwd** | `01 SSS HHH \| 00 bbb eee` | RESERVED, same |
| **class flags** | `11 aam ppp \| 10 ··· ···` | RESERVED, "the last unspent space" |
| **dual membership** | `01 sss hhh \| 01 sss hhh` | **does not fit.** Two nine-bit targets is eighteen bits before any kind code, against sixteen |

The first three cost nothing; they were tag space that was never spent.

**Dual membership is a real loss.** `extensions.md` §2.2.1 calls it "the one
secondary feature the marker can actually carry out — one comparator, matched
against either number, measured in `make groups`", and its use is *one phone in
two local groups: a desk that covers two numbers*. There is no one-card
substitute, because it is the desk's own card that claims both numbers and
`cover` points the other way. A desk that must answer two numbers now needs
either two ports or a hunt arrangement that does not exist.

What it buys is §4, three spare kinds where the old layout had none, and a word
that fits the visit.

---

## 6. The alternative not taken: a faster shift clock

256 kHz is 4.096 MHz ÷ 16, a clean tap of the existing chain, and gives
**thirty-two bit-times a visit** instead of sixteen. That carries every form
including the reserved ones and dual membership, with a third '165 available in
the same idiom — fitted only where needed, strapped to FF where not.

It is not taken here because it has not been checked against `SCLK` (also
128 kHz), `LOOP_HB`, and the MF8 half-bit clock, and because it changes a
conductor on the block header rather than a table on a page. It is the better
answer if it is free.

Worth recording either way: §2.2 rejects word-steered probing because "a
sixteen-bit word at 128 kHz is 125 µs and so is a visit, so steering by word
would saturate the bus and leave no room for a write". At 256 kHz the word is
62.5 µs and half the visit comes free — which is the out-of-turn probing
`marker.md` §4 carries as intent and `marker.v` does not implement.

This layout and the faster clock are not exclusive. The reorder is worth having
on its own, because it puts the fitting rule in the first bit and keeps the
common card at one chip.

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

- **The visit arithmetic against the RTL.** 16 bits at 128 kHz is 125 µs on
  paper; no bench has clocked a '165 through a visit.
- **Whether `vvv` is enough for `cover`.** Three bits is exactly a class code
  under §2.2, and this layout assumes the class stays three bits.
- **The 256 kHz clock of §6** — against `SCLK`, `LOOP_HB`, the MF8 half-bit
  clock, and every '165 and '164 in the tree.
- **What a plant actually needs.** The case for dropping dual membership is a
  bit budget, not a survey of how many desks cover two numbers.
