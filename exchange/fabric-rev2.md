# The exchange — a fabric that grows: the block and the port redefined

`fabric.md` is eight highways of eight ports: 64 seats, 512 kHz, and **sixteen
highway conductors because `C` and `A` each get one**. This document redefines
the block (§2) and the port (§3) so that the fabric is **eight conductors at
every size**, the port selects among **up to 32 highways** fitted in groups of
eight, and the **minimum configuration is no dearer than today**.

`A` does not leave the highway. It is time-interleaved into one sacrificed slot
a block (§4), which is what deletes the eight `HA` conductors and the A
highway-select at every port. The marker keeps reading M off the highway; it
simply counts frames to know when to look (§2.1), using a `frame_stb` it
already receives and does not use.

The card socket is untouched: six signals a slot, point to point, no slot-ID.
**A card cannot tell the difference** (§6).

> **Status: proposed, not measured.** No circuit has been drawn and nothing has
> been on a bench. Package counts are deltas against `fabric.md` §§3.1–3.2 —
> see the warning at the end of §2, because that section's own total does not
> match its own list. §8 is what is still open, and one open item decides the
> size.

---

## 1. What forces the shape

A block *P* ports wide needs *P* cells a frame, so **the slot width sets the
cell rate and the highway count sets the conductors**. Each bit moved from the
slot to the highway halves the rate and doubles the port's mux.

| | ports | cell | cable A signals | block header |
|---|---|---|---|---|
| **8 × 8**, `fabric.md` today | 64 | 512 kHz | 31 + 1 spare | 48 |
| **16 × 8** — this document | 128 | **512 kHz** | 31 | **48** |
| 32 × 8 | 256 | 512 kHz | 47 | 48 |
| 32 × 16 | 512 | **1.024 MHz** | 49 | **96** |
| 64 × 8 | 512 | 512 kHz | 79 | 48 |

**The slot stays three bits.** Sixteen slots doubles the block header from 48
signals to 96, which redesigns every block adapter; it ends the rule that **one
highway is one MF8 group**, since a single 3-bit address today picks a
channel's `C` bit, its `A` bit, its input on the trunk card's frame mux and its
port, "and the trunk card is wired straight across"; and it breaks `A` (§4.2).

---

## 2. The block redefined

Against `fabric.md` §3.1, item by item. Only four lines move.

| function | today | here |
|---|---|---|
| commutators: `C`, `A` | 2 × '151, both on `SLOT` | **2 × '151, unchanged in count** — the `A` commutator is re-addressed by `frame_in_oct` and its output wired into the `C` commutator's **freed input 4** (§4). No output mux, no input mux |
| probe commutators: `BUSY`, the word | 2 × '151 on `SCAN[2:0]` | unchanged |
| `u_cb`'s select | `pb_sel` (`SCAN`-held) | **`slot`** — zero packages, and it repairs the busy lamp field by construction (§10.4). Needs one line at the marker |
| ringback substitution | 2 × '157 | unchanged |
| strobe decoder | '138 on `SLOTQ` | '138 **+ ½ '157** to address it from the A index during the A cell, so a port's existing slot-select picks up its `A` (§4.1) |
| write decoder | '138 | unchanged |
| the control word | 2 × '164 | unchanged to 7-bit ports; **+1 '164** at 8 or 9 (§5) |
| block select | '138 | unchanged to 8 blocks; 5 bits of block needs a second |
| the guard bit | ¼ | unchanged |
| backward `A` on a claimed trunk | 2 × '32 | unchanged — `A` out = E + `CLAIM` still |
| receivers | 4 × '244 for **sixteen** highways plus clocks, counts, the serial pair | **−1** at eight highways, since `HA` is gone; **+2** at 32, which must all be received |
| drivers | '244 for `HC[h]`, `HA[h]`, `PB` | unchanged — `HA[h]` gone, the third `PB` takes its place |
| | **≈15¼** | **≈14¾ at 8 highways, ≈17¾ at 32** |

The A fold is **free at the block**: the commutator count does not move,
because the sacrificed slot frees exactly the commutator input the A stream
needs. The block grows only with the **highway count**, because it must receive
every highway to fan out to its eight ports.

### 2.1 Two consumers of `A`, and why the marker needs no probe

There are two consumers and they are different in kind:

| | who | how many at once | mechanism |
|---|---|---|---|
| **fabric path** | every port in a call, reading its *correspondent's* `A` | up to 64, each pointing elsewhere | broadcast highway + a per-port mux. **Unavoidable** |
| **probe path** | the marker, reading the *scanned* port's hook | one, at one port | point-and-read on `SCAN` |

A probe can never serve the first: 64 ports each want a different port's `A` in
the same instant, which is what a highway is for. So **`A` stays on the highway
and the fold does not touch the ports or the trunks** (§6).

The marker is the awkward case, because today it is a second kind of *highway*
reader — `ha[scan[5:3]]` gated by `slotq == scan[2:0]`, the port's own cell.
Folded, a port's `A` is no longer in its own cell; it is in the sacrificed cell
of frame *p*.

**The marker already has what it needs to follow that.** `marker.v:31` declares
`frame_stb` and uses it at no line; `oct_stb` is beside it. A 3-bit counter
between them is `frame_in_oct` locally, and the capture becomes
`slotq == A_SLOT && frame == scan[2:0]`.

**Half a package, on one card.** The alternative considered and rejected was a
third probe commutator — a '151 a block on the ports' `a_tx`, on a third `PB`
conductor. It reads M a little sooner, but it costs **one package a block** (8
at 64 ports, 32 at 256) plus a conductor and a block-connector pin, to buy speed
the levels pass does not need (§10.1). Counting frames at the marker is the
cheaper half of the same job and gets cheaper as the exchange grows.

It does **not** delete §4.3's `m_acc` hazard, which stands and must be fixed.

> **`fabric.md` §3.1's total does not match its own list.** Summing the parts it
> prints gives 18¼, not the ≈15¼ it states. The deltas above are sound; the
> base is not, and it needs a recount before anyone builds from it.

---

## 3. The port redefined

### 3.1 The crosspoint

| function | today | here |
|---|---|---|
| listen latch | '273 — 6 port bits + `BSY` + `CLM` | '273 **+ ½ '174** at 9-bit ports (11 bits); '273 + one FF at 7 |
| highway select, `C` | '151, the eight `HC` | **1–4 × '151 into ½ '153**, fitted in groups of eight |
| **highway select, `A`** | **'151, the eight `HA`** | **deleted** |
| slot select | '151, the eight strobes; its `W` is the capture clock | unchanged |
| capture, `C` and `A` | '74, both halves on `W` | '74, halves clocked separately |
| `A`/`C` qualifier | — | **¼ '02** — `Wc = W · /A_CELL`, `Wa = W · A_CELL` |
| | **5** | **4¾ minimum · 8¼ at 32 highways** |

```
        HC[0..7]  ─▶ '151 ─┐
        HC[8..15] ─▶ '151 ─┤
        HC[16..23]─▶ '151 ─┼─▶ ½ '153 ─▶ D of the capture '74
        HC[24..31]─▶ '151 ─┘
                     ▲                ▲
                  h[2:0]           h[4:3]
```

The board carries holes and traces for all four '151 and the '153; **a small
exchange fits one**. A '151's active-low enable forces `Y` low, so the four-way
merge is an OR with three dead branches — with one chip fitted, link its `Y`
across the '153 footprint to the '74's D pad.

**Hold one seat per fitted group.** With the 4:1 strapped out, `h[4:3]` are
ignored, so a cleared latch (`fabric.md` §3.3, highway 0 slot 0) lands on the
*fitted* group's input 0. Hold that port unfitted exactly as port 00 is held
today. It comes back when the group and the '153 are fitted. No gate, no
resistor.

### 3.2 Supervision — unchanged

`fabric.md` §3.5 stands as written, ≈3¼: the '14 with two RC, two CR and two
diodes for `fM`/`fE`; two ~680 Ω pull-ups for `/ANS` and the word pin; and
½ '02 + ¾ '08 + ¼ '00 + ⅓ '4075 + ⅓ '4073 for `ON`, `RB`, `A_RX`, the in-flight
term, `BUSY` out and the clear.

### 3.3 A port, all in

| | today | minimum config | 32 highways |
|---|---|---|---|
| crosspoint | 5 | 4¾ | 8¼ |
| supervision | 3¼ | 3¼ | 3¼ |
| **a port** | **8¼** | **8** | **11½** |

**The minimum port is cheaper than today**, because the deleted `A` '151 more
than pays for the wider latch and the qualifier gates — with three empty DIP-16
sites and a '153 footprint beside it for growth.

**The one exposure**: the ¼ '02 assumes §3.5's spare gate fractions are really
spare, and `fabric.md` §8 calls that count "a sketch". If they are not, the
port is 8¼ and the arrangement is a wash with today rather than a saving.

---

## 4. `A` in a sacrificed slot

One slot a block carries `A` instead of a port's `C`, and its content follows
`frame_in_oct` — the 3-bit frame-within-octet counter `clock_card.v:37` already
carries, because it must exist to make `CLK_8K` at all.

```
                cell 0  cell 1  cell 2  cell 3  cell 4  cell 5  cell 6  cell 7
  frame 0        C p0    C p1    C p2    C p3   A of p0  C p5    C p6    C p7
  frame 1        C p0    C p1    C p2    C p3   A of p1  C p5    C p6    C p7
  frame 2         ·       ·       ·       ·     A of p2   ·       ·       ·
  frame 3                                       A of p3
  frame 4                                       — spare —        (slot 4 has no port)
  frame 5                                       A of p5
  frame 6                                       A of p6
  frame 7                                       A of p7
```

`C` is untouched: every fitted port still gets one `C` bit every 64 kHz frame,
so CVSD never notices. Eight frames is 125 µs — one octet — so each port's `A`
comes round at **8.000 kHz**, which is MF8's own signalling rate
(`mf8_trunk_card.v`'s `s_bit`, one channel a superframe position). The spare
position needs nothing: the fabric is wholly synchronous to the clock card, so
unlike a link there is no alignment to find.

**Sacrifice slot 4, not slot 0.** A released port clears its '273 to zeros —
highway 0, slot 0 — and `fabric.md` §3.3 works because port 00 is never fitted,
so that cell carries `FILL` and `A` = 0. Make cell 0 the A cell and every
released port in the exchange is pointed at block 0's signalling stream and
hears it as audio. Slot 4 is already not a channel on trunk and terminal blocks
(`protocol.md` §5: "10 and 14 free"), and 04's operator convention moves to 05.

### 4.1 How a port picks its `A` out

Address the block's strobe '138 by the A index **during the A cell** instead of
by `SLOTQ`. Strobe line *s* then fires in the A cell of frame *s*, so a port
listening to slot *s* sees its correspondent's `A` arrive on **the same strobe
line it already selected for `C`**, through the '151 it already has. All the
port adds is the ¼ '02 of §3.1 to send that capture to the other half of its
'74.

That is what deletes the per-port `A` '151, and it is the whole economy.

### 4.2 Why sixteen slots breaks it

The rule is **`A` cycle ≤ visit**, not a rate. At eight slots the cycle is
7 × 15.625 = 109.4 µs inside a 125 µs visit. At sixteen it is 234 µs, and a
visit sees only half the index values.

Worse, both counters divide the same crystal, so **the phase is fixed, not
drifting**: visit *v* sees index values {0…7} when *v* is even and {8…15} when
odd, and scanning slot-fastest the scanned slot's parity equals *v*'s. Solving,
the visible slots are **{0, 2, 4, 6, 9, 11, 13, 15}** — eight of sixteen, the
same eight, for ever.

### 4.3 A latent bug, not conditional on any of this

`m_acc` in `marker.v` has four appearances — declaration, reset, the capture at
`:498`, the read at `:502` — and **no per-visit clear**. Today that is harmless
only because `slotq == scan[2:0]` matches once a frame and a visit is eight
frames, so M is sampled eight times and the last wins.

With one sample a visit — which is what both the A fold and any faster scan
imply — a port the probe never serves reads **the previous port's hook**: a
phone nobody lifted is seized and given dial tone, a phone that did lift is
never seen, and the free test is wrong for it. **Add the clear and a valid flag
whatever else is built.**

---

## 5. The control word

`mainboard.md` §2.3.1 is exactly sixteen bits and exactly full. The scaling law
is **word = 2 × address + 4**, because the word carries two port numbers, so
sixteen bits *is* a 64-port word.

| ports | address | word | |
|---|---|---|---|
| 64 | 6 | 16 | as built |
| **128** | **7** | **16** | fits — spend the spare bit, keep `CLM` |
| 256 | 8 | 18 | +1 '164 a block |
| 512 | 9 | 20–21 | +1 '164 a block, +½ '174 a port |

At 128 ports the word does not grow at all: seven and seven and `G` and `BSY`
is sixteen exactly.

---

## 6. What this does not change

**The socket.** Six signals a slot, point to point — `C_TX`, `C_RX`, `A_TX`,
`A_RX`, the word pin a12, `/ANS` a13, a14 spare — clocks and rails common, no
slot-ID, nothing contending. An unfitted slot still idles by resistor, `C_TX`
to `FILL` through 4.7 kΩ and `A_TX` to ground. **A card cannot tell the
difference**: it still puts one `C` bit a frame on `C_TX` and its hook on
`A_TX`. That is `common-cards.md` §1's portability contract, and it is why the
MF8 shelf and the exchange block take the same card.

**The trunk path.** `port.v:73` `a_hw = a_tx`; `port.v:80`
`a_rx = (e || claim) && !(on && ring_cad_n)`; `mf8_trunk_card.v:63`
`a_lat <= port_a_rx`; `:71-72` the `s_bit` sub-commutation. A trunk forwards
what its port captured off the highway, `CLAIM` rides the same wire, and the
fabric delivers `A` at exactly the 8 kHz the S channel wants.

**Also unchanged**: the card option word (`option-word-rev2.md`), `/ANS` on a
pin, the presence test `nano-marker.md` §4 does by ORing the word across a
visit, ringback substitution, the supervision gates, the release rule, the
block shunt, cable B's existing signals.

---

## 7. What it costs, assembled

| | today | this, minimum (8 hw) | this, 32 hw |
|---|---|---|---|
| a port | 8¼ | **8** | 11½ |
| a block | ≈15¼ (but see §2) | ≈14¾ | ≈17¾ |
| highway conductors | **16** | **8** | **32** |
| cable A signals | 31 + 1 spare | 31 | 47 |
| block header | 48 | 48 | 48 |

---

## 8. Open

- **The size ceiling stands, and §10 says why.** A levels-only scan is 8× to
  72× faster than today, but it does not move the flood hop, because the hop is
  a *hunt* and a hunt reads the card word at every port. The word rate is fixed
  exchange-wide (§10.2), so a hunt is N × 125 µs whatever the scan does, and
  `monitor.md` §3.5's guard is sized on that. **128–256 ports remains the
  ceiling for a networked exchange.** What the fast scan buys is dial-tone
  latency and call setup, not size.
- **The numbering.** Three digits over 16 highways of 8 slots is 7 address bits
  in 9 digit bits. Highways 0–15 should dial **200–377** — first digit
  `01h[3]` — keeping 128 dense numbers and leaving first keys 0, 1, 4, 5, 6, 7
  free. Not yet in `protocol.md` §5.
- **`fabric.md` §3.1's base total** — §2's warning.
- **The per-visit clear on `m_acc`** — §4.3. Fix regardless.

---

## 9. Not measured

- Every package count is a delta against `fabric.md` §§3.1–3.2, not a drawn
  circuit, and that base is itself in doubt (§2).
- The '151-enable strapping of §3.1 is a data-sheet argument.
- No bench exists for a fabric with `A` folded, a third `PB` conductor, or a
  block wider than eight.
- The ¼ '02 of §3.1 rests on spare gate fractions `fabric.md` §8 calls a sketch.

---

## 10. The scan, separated into levels and words

The 125 µs visit is **the card word's** sixteen bit-times at 128 kHz. `M` and
`BUSY` are levels and need none of it. Separating them is worth a great deal —
but only to the things levels decide.

### 10.1 The levels pass, frame-locked

`block.v:110` already commutates all eight of a block's `A` per cell —
`mux8 u_ca (.d(a_com), .s(slot), .y(ha_out))` — so on an **unfolded** fabric a
scanner tracking `SLOT` matches in every cell and the floor is 1.953 µs a port.

**Folded, the scan is frame-locked instead**: set `SCAN[2:0]` = `frame_in_oct`,
and in frame *f* the marker points at port *f* while port *f*'s `A` sits in the
A cell of that frame. Eight ports an octet, 125 µs, then the block re-point at
`marker.v:538`, another 125 µs — **250 µs a block**.

| ports | today (`N+B` word-bearing visits) | **this: frame-locked, folded, no PB2** | word pass — hunts |
|---|---|---|---|
| 64 | 9.0 ms | **2.0 ms** | 8.0 ms |
| 128 | 18.0 ms | **4.0 ms** | 16.0 ms |
| 256 | 36.0 ms | **8.0 ms** | 32.0 ms |
| 512 | 72.0 ms | 16.0 ms | 64.0 ms |

At 256 ports — the size the word pass caps the exchange at anyway — the levels
pass is 8 ms, inside the 9 ms today's 64-port exchange already lives with.

**`SCAN` is not widened.** Widening it to the full port address would delete the
125 µs block re-point and take the pass to 0.125–1.0 ms, but nothing needs that:
it is a hard cutover to a 34-way cable B with no graceful degradation, where
`SCAN[2:0]` today degrades gracefully because `DST` steering still works. The
re-point stays, and with it `mainboard.md` §3.2's siting argument and the
26-way.

Settling is not the limit either way: the `SCAN`-out / `PB`-back round trip on
`mainboard.md` §5.3's own cable model is ~0.25 µs, eight times inside a cell.

### 10.2 Words cannot be read faster, at any scan rate

`line_card.v:54` reloads on `frame_stb && tx_oct` and shifts on its own ÷32, so
**every card in the exchange is in the same bit-time at the same instant**. The
bus yields at most one port-word per 125 µs *exchange-wide*, whatever `SCAN`
does. `extensions.md` §2.2 already says it: "it buys gates, not time."

A short dwell is a **rotation** of a static word, not noise, and there is no
cheap detector — the all-ones and all-zeros constants are rotation-invariant
and no bit is spare. A fast scan needs a word-valid flag that no `PB1` listener
has today.

### 10.3 "The word only after a lift" does not hold as stated

Two places need it in the same visit as M, or without M at all:

- `marker.v:779` — `if (visit && p_valid && p_nail && !p_busy)`: a tied nail
  fires with **no M term**, so `p_nail` is wanted on every visit. Deferring the
  word silently stops re-establishing nails after a release.
- `marker.v:813` — the seizure branch consumes `p_cnail` and the class fields
  in the **same** visit as `p_m`.

So a deferred word is two visits for every real request, not one.

### 10.4 A bug at HEAD, and its fix

`lamp_card.v:61, 65-66` takes `d = pb0` while addressing its '259 by `slotq`,
against `block.v:111`'s `SCAN`-held `PB0` — so **one port's `BUSY` is written
into all eight positions** of that block's lamp field.

The repair is to slot-commutate `u_cb`: `block.v:111`, `.s(pb_sel)` → `.s(slot)`.
**Zero packages**, and it makes `common_card.v:26-30` and `hookbusy.md` §3.5's
"by construction" claim true.

It is **not** free of consequence, and an earlier draft of this document was
wrong to call it the same change as the scan. `marker.v:509` and `:517` sample
`pb_busy` as a held level, precisely because `u_cb` is `SCAN`-addressed today.
Slot-commutating it obliges the marker to gate the capture:

```
if (tick == 3'd4 && slotq == scan[2:0]) b_acc <= pb_busy;
```

which is what `nano_core.v:95` already does. One line, no packages — but a
separate change from the scan, to be made deliberately.
