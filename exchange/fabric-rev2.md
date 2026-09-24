# The exchange — `A` folded into slot 4: eight highways, seven seats a block

`fabric.md` is eight highways of eight ports with **sixteen highway conductors,
because `C` and `A` each get one**. This document folds `A` into the C highway,
in one sacrificed slot a block.

The fabric becomes **eight conductors**. The port loses a package. The block
loses a '244 of receivers and gains half a '157. Nothing else in the design
moves: the address stays six bits and two-digit, the control word stays sixteen
bits, the card option word stays as `extensions.md` §2.2 prints it, and **a
card cannot tell the difference** (§7).

The cost is one slot a block. Seven usable slots × eight blocks, less port 00,
is **55 seats against today's 63**.

> **Status: proposed, not measured.** No circuit has been drawn and nothing has
> been on a bench. Package figures are deltas against `fabric.md` §§3.1–3.2,
> and see the warning in §2 — that section's stated total does not match its own
> printed list. There is also **no port bill of materials anywhere in the tree**
> at any population: every figure is a package fraction by function, which
> `fabric.md` §8 admits of itself ("the supervision's gate count in particular
> is a sketch"). This is an accounting basis, not a BOM.

---

## 1. The change, entire

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
(`mf8_trunk_card.v`'s `s_bit`, one channel a superframe position, positions 0
and 4 idle). The spare position needs nothing: the fabric is wholly synchronous
to the clock card, so unlike a link there is no alignment to find.

**The rule is `A` cycle ≤ visit**, not a rate. Seven ports sharing one cell a
frame is 109.4 µs inside a 125 µs visit, with 15.6 µs to spare.

**Slot 4, not slot 0.** A released port clears its '273 to zeros — highway 0,
slot 0 — and `fabric.md` §3.3 works because port 00 is never fitted, so that
cell carries `FILL` and `A` = 0. Make cell 0 the A cell and every released port
in the exchange is pointed at block 0's signalling stream and hears it as audio.
Slot 4 is already not a channel on trunk and terminal blocks (`protocol.md` §5:
"10 and 14 free"), and 04's operator convention moves to 05.

---

## 2. The block

Against `fabric.md` §3.1, item by item. Three lines move.

| function | today | here |
|---|---|---|
| commutators: `C`, `A` | 2 × '151, both on `SLOT` | **unchanged in count** — the `A` commutator is re-addressed by `frame_in_oct` and its output wired into the `C` commutator's **freed input 4**. No output mux, no input mux |
| strobe decoder | '138 on `SLOTQ` | '138 **+ ½ '157** to address it from the A index during the A cell, so a port's existing slot-select picks up its `A` (§3.1) |
| receivers | 4 × '244 for **sixteen** highways plus clocks, counts, the serial pair | **−1** — `HA` is gone |
| `u_cb`'s select | `pb_sel` (`SCAN`-held) | **`slot`** — zero packages, and it repairs the busy lamp field by construction (§6.2). Needs one line at the marker |
| everything else | probe commutators, ringback, write decoder, control word, block select, guard, backward `A`, drivers | unchanged |
| | **≈15¼** | **≈14¾** |

The fold is **free at the block**: sacrificing a slot frees exactly the
commutator input the `A` stream needs, so the commutator count does not move.

> **`fabric.md` §3.1's stated total is right; its printed list is not.** The
> list sums to 18¼ where the row beneath it prints ≈15¼. Fifteen and a quarter
> is the figure four other places carry, and the only one that reproduces
> `fabric.md` §5: a fitted block is 8 × 8¼ + 15¼ = 81¼, printed at `:314` as
> ≈82, and eight of those is 656, printed at `:315` as ≈655. On 18¼ they would
> be 84¼ and 674, which reproduce neither. `mainboard.md`:186 reaches it from
> the other side — `mvp.md`'s 13 for the same shared parts, plus "≈3¼ added,
> about one '244 freed: net ≈2¼ a block".
>
> Two of the three packages are the `2 × '32` backward-A row, which its own note
> marks trunk-only ("used on trunk blocks; harmless elsewhere"), so on the
> list's basis **a line block is 16¼ and a trunk block 18¼**. The third is the
> "about one '244 freed" credit, taken in the total and never struck off the
> receiver row. **The list is what needs editing, not the total.**

---

## 3. The port

| function | today | here |
|---|---|---|
| listen latch | '273 — 6 port bits + `BSY` + `CLM` | **unchanged** |
| highway select, `C` | '151, the eight `HC` | unchanged |
| **highway select, `A`** | **'151, the eight `HA`** | **deleted** |
| slot select | '151, the eight strobes; its `W` is the capture clock | unchanged |
| capture, `C` and `A` | '74, both halves on `W` | '74, halves clocked separately |
| `A`/`C` qualifier | — | **¼ '02** — `Wc = W · /A_CELL`, `Wa = W · A_CELL` |
| crosspoint | **5** | **4¼** |
| supervision (`fabric.md` §3.5) | 3¼ | 3¼ — no dependency on any of this |
| **a port** | **8¼** | **7½** |

**The port gets cheaper.** It is the first change in this design that has.

**Supervision genuinely does not move with the address.** Checked against the
RTL rather than the prose: in `port.v`, `addr` appears at only `:55-57` — the
two selects and `W` — and `:107-108`, the release clear and the write. Every
supervision expression at `:69-80` reads `a_tx`, `e`, `fm`, `fe`, `claim`,
`RINGS` and `ring_cad_n` and nothing else.

**The one exposure**: the ¼ '02 assumes §3.5's spare gate fractions are really
spare, and `fabric.md` §8 calls that count a sketch. If they are not, the port
is 8¼ and the fold is a wash at the port, still a saving at the block and the
cable.

### 3.1 How a port picks its `A` out

Address the block's strobe '138 by the A index **during the A cell** instead of
by `SLOTQ`. Strobe line *s* then fires in the A cell of frame *s*, so a port
listening to slot *s* sees its correspondent's `A` arrive on **the same strobe
line it already selected for `C`**, through the '151 it already has. All the
port adds is the ¼ '02 above, to send that capture to the other half of its '74.

That is what deletes the per-port `A` '151, and it is the whole economy.

---

## 4. The scan

The marker reads M off the highway at `slotq == scan[2:0]` — the port's own
cell — once a frame, eight times in a visit. Folded, a port's `A` is no longer
in its own cell; it is in the sacrificed cell of frame *p*.

**The marker already has what it needs to follow that.** `marker.v:31` declares
`frame_stb` and uses it at no line; `oct_stb` is beside it. A 3-bit counter
between them is `frame_in_oct` locally, and the capture becomes
`slotq == A_SLOT && frame == scan[2:0]`. **Half a package, on one card.**

Set `SCAN[2:0]` = `frame_in_oct` and the scan is frame-locked: in frame *f* the
marker points at port *f* while port *f*'s `A` sits in the A cell of that frame.
Eight ports an octet, then the block re-point — **250 µs a block, 2.0 ms a
pass**, against today's 9 ms.

A third probe commutator for M on a third `PB` conductor was considered and
**rejected**: it costs one '151 a block to buy speed nothing needs, where
counting frames at the marker is half a package once.

---

## 5. What it costs, assembled

| | today | here |
|---|---|---|
| a port | 8¼ | **7½** |
| a block | ≈15¼ (but see §2) | **≈14¾** |
| seats | 63 | **55** |
| lines, after tones and the operator bank | 56 | **49** |
| fabric total | ≈642 | **≈530** |
| **packages a seat** | 10.19 | **9.65** |
| highway conductors | **16** | **8** |
| cable A signals | 31 + 1 spare | **23**, 41 free positions in the 64-way |

The fold itself is worth about **−45 packages**; the rest of the difference is
eight fewer ports. Twenty-three signals will not reach signal-ground-ground
throughout (23 × 3 = 69 > 64), but it will give **the eight highways two grounds
each** and everything else one, at 54 conductors with ten spare — and the
highways are the aggressors.

---

## 6. Two bugs this work turned up

### 6.1 `m_acc` has no per-visit clear

`marker.v` has four appearances of it — declaration at `:150`, reset at `:443`,
the capture at `:498`, the read at `:502`. Today that is harmless only because
`slotq == scan[2:0]` matches once a frame and a visit is eight frames, so M is
sampled eight times and the last wins.

With **one** sample a visit — which is what the fold implies — a port the probe
never serves reads **the previous port's hook**: a phone nobody lifted is seized
and given dial tone, a phone that did lift is never seen, and the free test is
wrong for it. **Add the clear and a valid flag.**

### 6.2 The busy lamp field is wrong at HEAD

`lamp_card.v:61, 65-66` takes `d = pb0` while addressing its '259 by `slotq`,
against `block.v:111`'s `SCAN`-held `PB0` — so **one port's `BUSY` is written
into all eight positions** of that block's lamp field.

The repair is `u_cb`'s select, `.s(pb_sel)` → `.s(slot)` (§2). **Zero
packages**, and it makes `common_card.v:26-30` and `hookbusy.md` §3.5's "by
construction" claim true. It obliges the marker to gate its own capture —
`marker.v:509` and `:517` sample `pb_busy` as a held level — with
`if (tick == 3'd4 && slotq == scan[2:0]) b_acc <= pb_busy;`, which is what
`nano_core.v:95` already does. One line, no packages.

---

## 7. What this does not change

**The socket.** Six signals a slot, point to point — `C_TX`, `A_TX`, `C_RX`,
`A_RX`, the word pin a12, `/ANS` a13, a14 spare — clocks and rails common, no
slot-ID. An unfitted slot still idles by resistor. **A card cannot tell the
difference**, with one number attached: `A_RX` is `(e || claim) && !(on &&
/RING_CAD)` and `e` is now captured once an octet rather than once a frame, so
its edges quantise to **125 µs**. Nothing that exists cares — the ring cadence
is 2 s/4 s, a data card's `DSR` rises at claim, and the MF8 trunk card samples
`port_a_rx` at 8 kHz anyway. The tightest consumer is an FXO card repeating dial
pulses, and 0.125 ms sits inside the 0.5 ms a hop the A path already spends.

**The trunk path.** `port.v:73` `a_hw = a_tx`; `port.v:80`
`a_rx = (e || claim) && !(on && ring_cad_n)`; `mf8_trunk_card.v:63`
`a_lat <= port_a_rx`; `:71-72` the `s_bit` sub-commutation. A trunk forwards
what its port captured off the highway, `CLAIM` rides the same wire, and the
fabric delivers `A` at exactly the 8 kHz the S channel wants.

**Also unchanged**: the six-bit address and two-digit dialling; the sixteen-bit
control word, which *is* a 64-port word; the card option word
(`option-word-rev2.md`); `/ANS` on a pin; the presence test `nano-marker.md` §4
does by ORing the word across a visit; ringback substitution; the supervision
gates; the release rule; the block shunt; cable B.

---

## 8. Open

- **`fabric.md` §3.1's base total** — §2's warning.
- **The per-visit clear on `m_acc`** — §6.1. Fix regardless.
- **The busy lamp repair** — §6.2, and the merged display card that goes with
  it: eight cards of sixteen lamps instead of sixteen of eight, with row 4
  unstuffed on every one.
- **The block ribbon**, which has no conductor count, pin map, connector family,
  length or loading rule anywhere in the tree, and is the gap that blocks
  building one.

---

## 9. Not measured

- Every package count is a delta against `fabric.md` §§3.1–3.2, on a base that
  is itself in doubt, and no port BOM exists at any population.
- The ¼ '02 of §3 rests on spare gate fractions `fabric.md` §8 calls a sketch.
- No bench exists for a fabric with `A` folded.
- The 125 µs `A_RX` quantisation of §7 against a real FXO repeat.
