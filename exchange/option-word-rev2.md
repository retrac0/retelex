# The exchange — the card option word: what a nine-bit port would have cost

**Superseded in its main purpose.** This document was written when the port
address was to be nine bits. The address is six bits again — two-digit `h s`,
sixty-four addresses — so `extensions.md` §2.2's word stands **exactly as
printed**: sixteen bits, two '165, the same forms, the same constants. Nothing
in the layout has to change.

What survives is one decision the owner made independently, one bug the work
turned up, and three facts worth not rediscovering.

> **Status: mostly superseded.** §1 is live. §2 is a bug in the design as it
> stands. §3 is reference. The layout this document previously proposed is
> withdrawn — it solved a problem that no longer exists.

---

## 1. Live: the three reserved forms go

| | was | |
|---|---|---|
| **network nail** | `10 SSS HHH \| 00 bbb eee` | RESERVED, never implemented — dead until a sender exists (`network.md` §9) |
| **netwide fwd** | `01 SSS HHH \| 00 bbb eee` | RESERVED, same |
| **class flags** | `11 aam ppp \| 10 ··· ···` | RESERVED, "the last unspent space" |

Dropping them costs nothing and frees three secondary pairings. It is an
independent decision and it holds at six-bit targets.

**Dual membership stays.** It was dropped only because two nine-bit targets is
twenty-two bits against sixteen. At six bits it is `01 sss hhh | 01 sss hhh` —
the original, and it fits. `extensions.md` §2.2.1 calls it "the one secondary
feature the marker can actually carry out", `marker.v:176, :223` implement it
and `tb_groups.v:274-280` measures it. There is no longer any reason to lose it.

**`cover` stays** for the same reason: a class, its options and a six-bit port
is sixteen bits exactly, as printed.

---

## 2. A bug in the design as it stands: `FF` fails open

`extensions.md` §2.2 makes an unfitted secondary read `FF`, meaning *no
extension*, and `marker.v:233/241` enforces it.

For an **answers-to with conditions** that is a fail-**open**. A card whose
second '165 is unfitted, unseated, or still inside its ~100 ms power-up RC
reads `FF`, which §2.2.1 defines as *unconditional* — so a member meant to be
taken only on night service, or only when the owner is busy, becomes
**eligible for every hunt**.

The cure is to invert the rule for the conditions pairing alone: an
`answers-to` whose secondary reads `FF` is out of service, not unconditional.
A card that means unconditional says so with `L U K` all clear, which §2.2.1
already lists as equivalent.

This is not conditional on the address width and should be fixed.

---

## 3. Three facts worth keeping

**Sixteen is a visit, not a bit budget.** 1/128 kHz = 7.8125 µs, and sixteen of
those is 125.000 µs — one `CLK_8K` period, one scanner visit. `marker.v:152`'s
`wdiv` is a ÷32 of 4.096 MHz, `w_take` fires at `wdiv == 31`, and `wdiv` is
re-zeroed on `oct_stb`: **sixteen samples a visit and no seventeenth.** The
ceiling is the marker's sampler, not the '165's shift edges.

**The shift clock cannot be raised.** 256 kHz exists as a spare divider tap, but
a2 carries 128 kHz to three customers — the CVSD encoder, the word's two '165
and the control bus — and `clocks.md` §4's contract is "`LOOP_HB` ÷ 2 **is**
`TX_CLK`, in phase". a2 is block-common, so it cannot be raised for one slot:
doubling it stops every CVSD phone encoding. A faster word clock would have to
arrive on **a14**, the last spare socket pin, which `common-cards.md` §1.2
classes as a per-slot open-drain declaration — "pull low, or leave open. Never
drive high" — so driving it ends the rule that an exchange card sits unchanged
in an MF8 shelf.

**The word's spare capacity is in the pairings, not the bits.** §2.2 declares
six of its sixteen type-by-tag pairings out of service. Each carries six payload
bits. That is where room comes from if the word is ever short again — not from
re-ordering fields, and not from a faster clock.

---

## 4. Not measured

- The power-up RC of §2, and therefore how long a card reads `FF` after
  insertion. `extensions.md` §2.2's ~100 ms is the only figure.
- Whether any plant actually uses dual membership or `cover`.
