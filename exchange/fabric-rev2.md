# The exchange — a fabric that grows: more highways, eight slots, A in a sacrificed cell

`fabric.md` is eight highways of eight ports: 64 seats, 512 kHz, sixteen
conductors because `C` and `A` each get one. This document is that fabric with
three changes, and it is written so that **the minimum configuration is the one
already specified** and everything else is empty footprints.

1. **The port selects among up to 32 highways**, four 8:1 into a 4:1, populated
   in groups of eight. A small exchange fits one '151 and the 4:1 strapped out.
2. **Three-digit dialling**, slot **three** bits and highway up to **five**.
3. **`A` rides the C highway in one sacrificed slot a block**, so the fabric is
   eight conductors, not sixteen, at every size.

> **Status: proposed, not measured.** Nothing here has been on a bench and no
> circuit has been drawn. The package counts are recounts of `fabric.md` §§3.1
> and 3.2; the scan and flood figures are arithmetic on `marker.v`'s own
> counters and `monitor.md` §3.5's taps. §7 lists what is still open, and one
> of the open items decides the size.

---

## 1. The shape, and why the slot stays three bits

A block *P* ports wide needs *P* cells a frame, so **the slot width sets the
cell rate and the highway count sets the conductors**. Each bit moved from the
slot to the highway halves the rate and doubles the port's mux.

| | ports | cell | cable A signals | block header | scan pass | slow flood hop |
|---|---|---|---|---|---|---|
| **8 × 8**, `fabric.md` today | 64 | 512 kHz | 31 + 1 spare | 48 | 9.0 ms | 12 ms |
| **16 × 8** — this document | 128 | **512 kHz** | 31 | **48** | 18 ms | 21 ms |
| 32 × 8 | 256 | 512 kHz | 47 | 48 | 36 ms | 39 ms |
| 32 × 16 | 512 | **1.024 MHz** | 49 | **96** | 68 ms | 71 ms |
| 64 × 8 | 512 | 512 kHz | 79 | 48 | 72 ms | 75 ms |

Signals are with `A` folded in, i.e. as specified here. Scan pass is
(*N* + *B*) visits at 8 kHz — `marker.v` dirties the probe once a block, so it
is 64 + 8 at today's size, not a per-port factor.

**Sixteen slots is rejected, for three reasons that have nothing to do with the
cell rate.** It doubles the block header from 48 signals to 96, which
redesigns every block adapter; it ends the rule that **one highway is one MF8
group**, because a single 3-bit address today picks a channel's C bit, its A
bit, its input on the trunk card's frame mux and its port, "and the trunk card
is wired straight across"; and it breaks `A` — §3.

**The rate is not the binding constraint. The flood guard is.** §4.

---

## 2. The port: up to 32 highways, fitted in groups of eight

```
        HC[0..7]  ─▶ '151 ─┐
        HC[8..15] ─▶ '151 ─┤
        HC[16..23]─▶ '151 ─┼─▶ ½ '153 (4:1) ─▶ D of the capture '74
        HC[24..31]─▶ '151 ─┘
                     ▲                ▲
                  h[2:0]           h[4:3]
```

The board carries holes and traces for all four '151 and the '153. **A small
exchange fits one.** A '151's active-low enable forces `Y` low, so the four-way
merge is an OR with three dead branches — with one chip fitted, link its `Y`
across the '153 footprint to the '74's D pad and nothing else changes.

| minimum configuration (`mvp.md` §1) | `fabric.md` today | here |
|---|---|---|
| port crosspoint | 5.00 | **5.00** — '151 (C), '151 (slot), '273, '74, and the C/A qualifier gates in place of the deleted A '151 |
| empty sites beside it | — | three DIP-16 and the '153 |
| block shared | 15¼ | +1 '164 (the wider control word, §5) |
| fabric cable A | 31 + 1 spare | 31, `A` folded in |
| block header | 48 | **48** |

**The minimum port is unchanged at five packages**, which is the whole point of
the arrangement: growth is paid when it is taken.

**Hold one seat per fitted group.** With the 4:1 strapped out, `h[4:3]` are
ignored, so a cleared latch (`fabric.md` §3.3, highway 0 slot 0) lands on the
*fitted* group's input 0. Hold that port unfitted exactly as port 00 is held
today; it comes back when the group and the '153 are fitted. No gate, no
resistor.

---

## 3. `A` in a sacrificed slot

One slot a block carries `A` instead of a port's `C`. The A cell's port index
advances each frame, so the block's remaining ports are covered in turn.

**The rule is `A` cycle ≤ visit**, not a rate. The marker reads M off the
highway *inside* the 125 µs visit to that port, so every port's `A` must appear
at least once in any 125 µs window.

| slots a block | usable seats | A cycle | visit | |
|---|---|---|---|---|
| **8** | **7** | 7 × 15.625 = **109.4 µs** | 125 µs | **fits, 15.6 µs to spare** |
| 16 | 15 | 15 × 15.625 = 234 µs | 125 µs | **fails** — §3.1 |

So at eight slots **one sacrificed slot is exactly right**, and the ratio is the
invariant one A cell per eight C cells. `mf8_trunk_card.v` already does this on
the line: `S` is sub-commutated `A` with positions 0 and 4 idle.

Sacrifice **slot 4, not slot 0**. A cleared '273 is highway 0 slot 0 and must
keep reading `FILL` with `A` = 0 (`fabric.md` §3.3); make slot 0 the A cell and
every released port is pointed at the signalling stream. Slot 4 is already not
a channel on trunk and terminal blocks (`protocol.md` §5: "10 and 14 free", "six
lines over an MF8 link"), and 04's operator convention moves to 05.

Index the A cell **mod 8**, from `clock_card.v`'s existing `frame_in_oct`, not
mod 7: the offset is then fixed, so `marker.v`'s `slotq == scan[2:0]` keeps
working unchanged.

### 3.1 Why sixteen slots breaks it, and the latent bug it exposes

With 16 slots the A cycle is 250 µs against a 125 µs visit, so a visit sees
only 8 of the 16 index values. Both counters divide the same crystal, so **the
phase is fixed, not drifting**: visit *v* sees index values {0…7} when *v* is
even and {8…15} when odd, and scanning slot-fastest the scanned slot's parity
equals *v*'s. Solving, the visible slots are **{0, 2, 4, 6, 9, 11, 13, 15}** —
eight of sixteen, the same eight, for ever.

`m_acc` in `marker.v` has four appearances — declaration, reset, the capture at
`:498`, the read at `:502` — and **no per-visit clear**. Today that is harmless
because `slotq == scan[2:0]` matches once a frame and a visit is eight frames,
so M is sampled eight times and the last wins. With one sample a visit, a port
the lane never serves reads **the previous port's hook**: a phone nobody lifted
is seized and given dial tone, a phone that did lift is never seen, and the
free test is wrong for all eight.

**Add the per-visit clear and a valid flag regardless of which shape is built.**
The eightfold redundancy is the only thing standing between the present design
and a silent wrong-port read, and it is not written down anywhere as a
requirement.

---

## 4. The ceiling is the flood guard, not the fabric

`monitor.md` §3.5's guard taps — 128 / 256 / 512 ms — are sized on "12 ms a
hop at a slow marker", and `network.md` §3 says that 12 ms *is* one scan pass
and a write. So the pass sets the hop, the hop sets how far a flood reaches
inside a tap, and `network.md` §3 wants about eight hops.

| ports | pass | hop | hops inside 128 / 256 / 512 ms |
|---|---|---|---|
| 64 | 9.0 ms | 12 ms | 10 / 21 / 42 |
| **128** | 18 ms | 21 ms | 6 / **12** / 24 |
| 256 | 36 ms | 39 ms | 3 / 6.6 / 13 |
| 512 | 68 ms | 71 ms | 1.8 / 3.6 / **7.2** |

The guard is bounded above at ~590 ms (ES 201 187's 720 ms inter-digit floor
less the 130 ms a digit and a seizure take), so **512 ms is the last tap**. And
it is one value for a whole network: a 512-port exchange puts every exchange on
512 ms, which gives cannot-complete to anyone dialling faster than 642 ms
between digits.

**So the exchange ceiling is about 256 ports, and 128 is the comfortable
size** — not because the fabric cannot carry more, but because the marker's
revolution is the flood's clock. Past that the answer is more exchanges, which
is what the network is for.

---

## 5. The control word

`mainboard.md` §2.3.1 is exactly sixteen bits and exactly full: G, spare, DST 6,
SRC 6, BSY, CLM. The scaling law is **word = 2 × address + 4**, because the word
carries two port numbers, so sixteen bits *is* a 64-port word.

| ports | address | word | |
|---|---|---|---|
| 64 | 6 | 16 | as built |
| **128** | **7** | **16** | fits — spend the spare bit, keep `CLM` |
| 256 | 8 | 18 | +1 '164 a block |
| 512 | 9 | 20–21 | +1 '164 a block, +½ '174 a port for the 11-bit latch |

At 128 ports the word does not grow at all: seven and seven and G and BSY is
sixteen exactly. **That is the second reason 128 is the comfortable size.**

---

## 6. What this does not change

The card option word — see `option-word-rev2.md`, which is written for nine-bit
ports and is if anything easier at seven. `/ANS` on a pin. The presence test
that `nano-marker.md` §4 does by ORing the word across a visit, which is
indifferent to any of this. The ringback substitution, the supervision gates,
the release rule, the block shunt, cable B.

---

## 7. Open

- **The size.** 128 ports (16 × 8) needs no wider control word and sits well
  inside the guard. 256 (32 × 8) needs one more '164 a block and lands at 6.6
  hops on the 256 ms tap. The port's 32-highway capability of §2 is worth
  building either way, because it is free until fitted.
- **The numbering.** Three digits over 16 highways of 8 slots is 7 bits of
  address in 9 bits of digit. Highways 0–15 should dial **200–377** — first
  digit `01h[3]` — which keeps 128 dense numbers and leaves first keys 0, 1, 4,
  5, 6, 7 free. Not yet written into `protocol.md` §5.
- **The per-visit clear on `m_acc`** — §3.1. This one is not conditional on the
  shape and should be fixed now.
- **Whether the guard analysis is accepted.** Everything in §4 rests on
  `network.md` §3's "12 ms is up to one scan and a write". If the guard is not
  a function of the scan pass, the ceiling moves.

---

## 8. Not measured

- Every package count is a recount of `fabric.md` §§3.1–3.2, not a drawn
  circuit.
- The '151-enable strapping of §2 is a data-sheet argument.
- The scan-pass figures come from `marker.v`'s counters, not a run; `mainboard.md`
  §2.3.4's measured 72 visits to a 64-port pass is the only observed number.
- No bench exists for a block wider than eight or a fabric with `A` folded in.
