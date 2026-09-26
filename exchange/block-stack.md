# The exchange — a block as built: the block header and eight port cards in a stack

A block is a stack of 100 × 100 cards:
- **the block header, as two boards**: A, the bus board, at the bottom with the
  bus underneath, and B, the logic board, on top of A;
- **eight port cards** above B, each with an edge header to its subscriber card.

All ten boards share one set of pass-through stacking headers. Header A and
header B also share a six-signal link that the port cards never see.

This document is the contract between the boards, and between them and the
hand RTL they are checked against.

Joel decided the form on 2026-09-25:
- **Every per-slot lane goes up the stack**, and each port card is jumpered onto
  its lane, one jumper set per lane.
- **The port drains are ORed on the block**: a block-local `/HA_L` and `/HB_L`,
  with one drain per plane onto the bus.
- **The header has two jumpers**: the HC route and the number.
- The new port card **replaces `pcb/portcard` in place**.
- **The header is two boards, stacked like the port cards** (later the same
  day, when 19 DIPs and their connectors would not fit one 100 × 100 board).

Three alternatives were weighed and not taken:
- electronic lane selection by POS;
- lanes rotated a pin per layer, which through-hole cannot do because
  co-located holes are one net;
- the port driving its own cell.

The block backplane was the fourth alternative. It stays the better form for
service; this is the better form for a first breadboard.

| | |
|---|---|
| Pin and part description | `pcb/tools/stackdef.py` → `pcb/lib/block-stack.json` (the tables below are generated from it) |
| Schematics | `pcb/hdrbus/` (header A), `pcb/hdrlogic/` (header B), `pcb/portcard/` — first draft by `pcb/tools/gen_cards.py`; **the schematics are the design from here on** |
| Boards | the same directories: placed by `pcb/tools/pcb.py`, routed by `pcb/tools/route.py` (Freerouting) |
| Check | `make -C pcb netcheck` / `make -C pcb lockstep`: netlist → Verilog → the newimpl benches, `block.v` swapped for the boards, or run beside them |
| Reference | `newimpl/rtl/block.v`, `port.v`, `frame_decode.v`. A difference means a schematic is wrong until shown otherwise |

---

## 1. The form

```
        port card 7   ┐
        …             │  eight port cards, 100 × 100, 12.6 mm pitch (11 mm gap)
        port card 0   ┘  each: J1 J2 J3 long-tail stacking headers, J4 edge header front
   ─────────────────────
        header B          the logic board: J1 J2 J3 long-tail like a port card;
                          J8, a 2×6 pin header on its UNDERSIDE, into A
   ─────────────────────
        header A          the bus board: J1 J2 J3 sockets and J8's 2×6 socket on top;
                          the bus 2×25s underneath
   ═════════════════════  plate, 20 mm standoffs
```

- **Pitch: an 11 mm gap, 12.6 mm board to board.** 0.4″ does not close with
  stock parts. An 8.5 mm socket body under a 1.6 mm board leaves 0.05 mm of air,
  and the upper card's solder fillets sit exactly there. At 11 mm, the stock
  2×20 long-tail stacking header (Raspberry Pi HAT class) seats 5.9 mm deep,
  and about **9 mm of part height** is usable under the next card: DIPs in
  sockets, and shunts. Samtec SSQ-120-03-G-D is the gold-plated upgrade.
  - The other 0.4″ stacks (hookbusy, the CVSD riser, MF8) have the same
    problem and are not changed here.
- **Holes.** Four M3 holes, and the datum is the standoffs, not the headers.
  H2 sits 3 mm off its corner, so a card turned round does not line up with
  the stack.
- **Connectors by edge.**
  - **Stack:** left J1, back J2, right J3.
  - **Port card front edge:** the edge header J4, the test strip J5 and the
    jumpers, so they can be reached.
  - **Header A front edge:** the adapter commons J6, the test strip J7 and
    both header jumpers. Header B is above them; right-angle shunts are reached
    from the front.
  - **Header A underside:** the bus 2×25s, J4 on the right and J5 on the left.
  - **Header B front edge:** its own test strip J9.
  - **J8, the header link,** sits at the same place on A and B (§3.1), and is
    not on the port cards.
- **Service:** power down to change a card. A card in the middle comes out with
  every card above it, so the whole block is out of service while it is changed.
  That is the price of the form.

## 2. What is on which card

The cut follows the RTL. The header, A and B together, is `block.v` without
its eight `port`s, plus `frame_decode.v`. A port card is `port.v`, plus the
ringback '157 that `block.v` had for its slot.

Between A and B, the cut follows the bus.
- **A holds everything the bus touches:** the receivers, the strobes and the
  commutator (they run on the bus's cell timing), the plane drains, the
  adapter, the jumpers.
- **B holds the rest:** the control word, the write decode, the frame decode and
  the `/WS` select.

Everything B needs from A is already a stack net except six, which ride J8.
Reference designators are unique across the pair, so "U14" names one part in a
block's header.

### 2.1 The block header — 20 DIP on two boards

| ref | board | part | does | RTL |
|---|---|---|---|---|
| U1–U3 | A | '244 ×3 | bus receivers: HCLK, SLOT, SLOTQ, SCLK, WR, SDATA, RBT, `/RING_CAD`, SCAN, HC0–5 | — |
| U4 | A | '244 | HC6–7 in; FILL and FILL_R off SCAN0; MUTE_BLK and H0–2 up the stack | `frame_decode.v:51`, `block.v:77` |
| U5 | A | '244 | adapter commons out; **HC_OUT**, enabled by `/FIT` | `block.v:229-230` |
| U6 | A | '14 | `/HA` → HA_RX; `/WS` → WS; the `/RESET` filter → `/RST` | `block.v:63`, `port.v:38` |
| U7 | A | '14 | `/SLOT2` → TX_CLK, `/SLOT1` → LOOP_HB, WS → the cleaned `/WS` for B | `frame_decode.v:47` |
| U14 | A | '138 | **the strobe lines** `/STB0–7`: SLOTQ, enabled by HCLK low (ticks 4–7) | none — `port.v` assumes "the block's '138" |
| U15 | A | '151 | **the commutator**: lane `C_TXk` in cell k | `block.v:226-230` |
| U19 | A | '02 | the plane OR onto the bus, gated by FIT | `block.v:237-238` |
| Q1–Q3 | A | 2N7000 | the block's one drain each on `/HA`, `/HB`, `/HW` | `block.v:65-66`, `:84` |
| U8 | B | '11 | TX_OCT = SCAN[2:0] == 7 | `frame_decode.v:48` |
| U9 | B | '74 ×2 halves | RX_OCT = TX_OCT a frame late, **in two steps**: TX_OCT taken as `/STB4` rises (the start of cell 5), then onto the frame edge (TX_CLK rises) — §8.1 | `frame_decode.v:49`, bus.md §3 |
| U10, U11 | B | '164 ×2 | the control word: CLM BSY SRC0–5, DST0–5, G | `block.v:89-100` |
| U12 | B | '688 | `/BLK` = FIT · DST[5:3] = h · **G** (the guard folded into the spare pair) | `block.v:102-113` |
| U13 | B | '138 | `/WR0–7` = `/BLK` · WR, by DST[2:0] | `block.v:115-118` |
| U16 | B | '688 | SCAN[5:3] = h, for the `/WS` select | `block.v:261-268` |
| U17 | B | '175 | the select latch: SCAN[2:0] and ours, clocked at `/STB4`'s fall while `/WS` is low | `block.v:263-270` |
| U18 | B | '151 | lane `WORD[sel]` | `block.v:272-273` |
| U20 | B | '02 | `hw_pd` (to A's Q3 on J8); the latch clock; the match, inverted into the latch | `block.v:273`, `:259-267` |

The header also carries RN1–RN9 and R1–R11 (all on A except RN2, RN4 and RN9):
- **Lane terminations.** `C_TXk` has 4.7 k to FILL_R, so an empty lane idles on
  FILL. `WORDk` has 10 k to +5 V, so an empty lane reads no word.
- **Series resistors.** 33 Ω on `/STB`, `/WR`, TX_CLK, LOOP_HB and the adapter
  lines, the sixteen strobe and write lanes in four 4-resistor SIP-8s; 100 Ω on
  HC_OUT.
- **Bus pull-downs.** 100 k on the bus inputs, so an unplugged header reads
  idle and holds itself in reset.
- **The plane pull-ups.** 1 k on `/HA_L` and on `/HB_L`.
- **The `/RESET` filter.** 10 k into 100 nF, about 1 ms. It swallows anything
  shorter, by design (`bus.md` §6.2), so **whatever drives the bus `/RESET`
  must hold it low for at least 2 ms**.

### 2.2 The port card — 13 DIP

| ref | part | does | RTL |
|---|---|---|---|
| U1 | '273 | the listen latch: addr[5:0], bsy, clm; clocked on `/WR`'s leading edge, cleared by a release or `/RST` | `port.v:70-73`, `:190-194` |
| U2 | '151 | highway select, HC[addr[5:3]] | `port.v:75-78` |
| U3 | '151 | slot select on `/STB0–7`; its W is the capture clock | `port.v:80-83` |
| U4 | '688 | eq_src: SCAN = addr | `port.v:85-88` |
| U5 | '688 | eq_own: SCAN = {h, POS} | `port.v:90-99` |
| U6 | '74 | C capture on W; E capture on WA | `port.v:108`, `:169-173` |
| U7 | '14 | the two detectors' Schmitts, the two CR squarers, `/M` | `port.v:134-136`, `:175-188` |
| U8 | '11 | ON = RINGS·`/M`·`/FM`; RB = ON·E; `/CLR` | `port.v:144`, `:146`, `:193` |
| U9 | '02 | FM·`/M`; the two drain gates; WA = `/STB4`·eq_src | `port.v:105-106`, `:123-124`, `:147` |
| U10 | 4002 | `/BUSY` = NOR(BSY, FE, FM·`/M`, MUTE_BLK); WRCLK = NOT `/WR` | `port.v:131-132`, `:147` |
| U11 | '00 | A_RX = (E + CLM)·`/(ON·/RING_CAD)` | `port.v:153` |
| U12 | '157 | **the ringback substitution, moved here**: this card's lane carries RB ? RBT : C_TX | `block.v:120-131` |
| U13 | '244 | the socket drivers: a1–a4, a7–a10 | `port.v:153-154` |
| Q1, Q2 | 2N7000 | M onto `/HA_L`, BUSY onto `/HB_L`, in this port's turn | `port.v:112-124` |

The detectors are **RC networks**, as `port.v` says they are:
- **Charging:** a 1N4148 and 18 k charge 1 µF, up in about 16 ms.
- **Discharging:** 270 k lets it down in about 256 ms.
- **Release:** a 1 nF / 10 k CR on the '14's output squares the detector's fall
  into the '273's `/CLR`, with a diode clamp.

Each cluster sits on its own sheet (`det.kicad_sch` ×2, `cr.kicad_sch` ×2),
because a digital simulator has no capacitor (§8).

### 2.3 What moved, and why

- **Ringback onto the port card.** `c_mux[k]` (`block.v:124-131`) becomes the
  card's own '157, so the lane carries its output. That removes the RB lane:
  **three lane jumpers a card, not four.** Behaviour at `block.v`'s port list is
  unchanged. An empty lane still reads FILL, now by RN1.
- **The plane OR onto the block.** `block.v:237-238` computes `JUMPERED && |ha_pd_k`,
  and its comment at `:233-236` says the drains sit on the bus conductor; the two
  disagree. Joel chose the OR: the bus sees 8 drains, not 64. A block without FIT
  is off both planes. `/GS` never reaches a port.
- **The header is two boards.** At 100 × 100, 19 DIPs, three stack sockets, two
  bus 2×25s underneath and the front-edge jumpers and headers did not fit: 14
  of 19 packages placed. Split along the bus, A holds 10 packages and B holds
  10. The one added part is U20, a '02 that takes over the three gates B needs,
  where A's '02 had them. U9's mid-frame clock is now `/STB4`'s rise, not
  SLOT2's, because SLOT2 is not on the stack.
- **The number is its own jumper.** The 2×8 of `block.v:23-30` routes HC_OUT onto
  HC[h], and both of its pins are live highway nets, so a '148 cannot read it.
  - JP2 NUMBER, a 2×4, gives h directly: a shunt reads 0.
  - Its fourth position, FIT, is the '148's old GS. It gates HC_OUT's '244,
    `/BLK`, the `/WS` answer and the plane drains.
  - The '148 is gone. The two jumpers must agree; nothing checks them.
- **The strobe '138 is drawn.** `port.v` assumes it; `block.v` has no region for it.

---

## 3. The stack

Three 2×20, identical on both cards. The port card carries a long-tail stacking
header (`telco:Stack_2x20_P2.54mm_LongTail`, the stock 2×20 socket's pads).
The header carries a plain 2×20 socket in the same holes. Pin *n* of every
card is one net. Bold marks the lines whose edges matter; each has a ground
beside it.

**69 signals** (43 commons, 24 lanes, and the two plane lines), **12 × +5 V,
36 × GND**, and 3 spares that pass through and connect to nothing.

#### J1 — left: the fast commons

| pins | odd | even | | pins | odd | even |
|---|---|---|---|---|---|---|
| 1–2 | +5 V | +5 V | | 21–22 | **`LOOP_HB`** | GND |
| 3–4 | **`/STB0`** | GND | | 23–24 | GND | GND |
| 5–6 | **`/STB1`** | GND | | 25–26 | `/RST` | GND |
| 7–8 | **`/STB2`** | GND | | 27–28 | `HA_RX` | GND |
| 9–10 | **`/STB3`** | GND | | 29–30 | `/RING_CAD` | `MUTE_BLK` |
| 11–12 | **`/STB4`** | GND | | 31–32 | `RBT` | `FILL` |
| 13–14 | **`/STB5`** | GND | | 33–34 | `TX_OCT` | `RX_OCT` |
| 15–16 | **`/STB6`** | GND | | 35–36 | GND | GND |
| 17–18 | **`/STB7`** | GND | | 37–38 | GND | GND |
| 19–20 | **`TX_CLK`** | GND | | 39–40 | +5 V | +5 V |

#### J2 — back: the lanes and the block-local planes

| pins | odd | even | | pins | odd | even |
|---|---|---|---|---|---|---|
| 1–2 | +5 V | +5 V | | 21–22 | `C_TX0` | `C_TX1` |
| 3–4 | **`/WR0`** | GND | | 23–24 | `C_TX2` | `C_TX3` |
| 5–6 | **`/WR1`** | GND | | 25–26 | `C_TX4` | `C_TX5` |
| 7–8 | **`/WR2`** | GND | | 27–28 | `C_TX6` | `C_TX7` |
| 9–10 | **`/WR3`** | GND | | 29–30 | `WORD0` | `WORD1` |
| 11–12 | **`/WR4`** | GND | | 31–32 | `WORD2` | `WORD3` |
| 13–14 | **`/WR5`** | GND | | 33–34 | `WORD4` | `WORD5` |
| 15–16 | **`/WR6`** | GND | | 35–36 | `WORD6` | `WORD7` |
| 17–18 | **`/WR7`** | GND | | 37–38 | `/HA_L` | `/HB_L` |
| 19–20 | GND | GND | | 39–40 | +5 V | +5 V |

#### J3 — right: the slow commons

| pins | odd | even | | pins | odd | even |
|---|---|---|---|---|---|---|
| 1–2 | +5 V | +5 V | | 21–22 | `CLM` | `BSY` |
| 3–4 | `SCAN0` | `SCAN1` | | 23–24 | `SRC0` | `SRC1` |
| 5–6 | `SCAN2` | `SCAN3` | | 25–26 | `SRC2` | `SRC3` |
| 7–8 | `SCAN4` | `SCAN5` | | 27–28 | `SRC4` | `SRC5` |
| 9–10 | GND | GND | | 29–30 | GND | GND |
| 11–12 | `HC0` | `HC1` | | 31–32 | `H0` | `H1` |
| 13–14 | `HC2` | `HC3` | | 33–34 | `H2` | spare |
| 15–16 | `HC4` | `HC5` | | 35–36 | spare | spare |
| 17–18 | `HC6` | `HC7` | | 37–38 | GND | GND |
| 19–20 | GND | GND | | 39–40 | +5 V | +5 V |

The '164 outputs ripple on every shift, so SRC, BSY and CLM stay on J3, away from
the strobes and the write lanes. They are read only at a `/WR` edge, as on the bus.

**Loading.** The worst common is `/RST`: three inputs a card, 201 pF estimated
through nine layers. `/HA_L` and `/HB_L` carry eight drains, about 230 pF on 1 k,
a 0.23 µs rise against a sample 8.8 µs into the bit-time. The per-net table is
`fanout` in `block-stack.json`. The estimates are arithmetic from typical input
and trace capacitance, not measured.

### 3.1 The header link, J8 — header A to header B only

| pins | odd | even |
|---|---|---|
| 1–2 | `SCLK_R` (bus SCLK, received) | GND |
| 3–4 | `SDATA_R` | GND |
| 5–6 | `WR_R` | GND |
| 7–8 | `/FIT` (the NUMBER jumper's FIT, pulled up on A) | GND |
| 9–10 | `WS_C_N` (`/WS` through A's two '14s) | GND |
| 11–12 | `HW_PD` (B's '02 into A's Q3 gate) | GND |

- **The physical join.** A carries a 2×6 socket on top; B carries a plain 2×6
  pin header on its underside, pins down into it. An 8.5 mm socket and a
  2.54 mm pin-header body mate at exactly the stack's 11 mm gap.
- **The port cards never see it.** B's pin header does not pass through.
- **Position.** J8 is at (47, 80) on both boards, pin 1 at the back left.
  `stackdef.py` asserts that its two halves meet pad for pad, and `pcb.py`
  checks both boards' pads.
- **The six nets and why.**
  - SCLK, SDATA and WR are bus signals, and only A touches the bus.
  - `/FIT` comes from A's NUMBER jumper.
  - The cleaned `/WS` comes from A's '14s.
  - `hw_pd` is made on B, beside the select latch, and drives A's `/HW` drain.
  - Every other net B uses is on the stack. `stackdef.py` fails if a net is
    used on both boards and is neither a stack net nor a link net.

## 4. Lanes and jumpers

Each port card carries **four jumper blocks**, all on the front edge, and all
must say the same slot k:

| ref | size | shunt in column k means | missing |
|---|---|---|---|
| JP1 POS | 2×3 | a shunt reads 0: POS = k in binary, S0 S1 S2 | open reads 1: no shunts is slot 7 |
| JP2 WR | 2×8 | this card's `/WR` is lane `/WRk` | never written: 10 k holds `/WR` idle |
| JP3 C_TX | 2×8 | this card's C (after ringback) drives lane `C_TXk` | lane k stays on FILL; the card is heard by no one |
| JP4 WORD | 2×8 | the subscriber's a12 is lane `WORDk` | lane k reads no word: class 000, unequipped |

The header has two:

| ref | size | means | missing |
|---|---|---|---|
| JP1 HC ROUTE | 2×8 | HC_OUT drives highway HC[h] (silkscreen h = 7…0) | the block drives no highway, and still listens |
| JP2 NUMBER | 2×4 | FIT, then h0 h1 h2: a shunt reads 0; FIT shunted = the block is fitted | h reads 7; no FIT: no HC drive, no `/BLK`, no `/WS` answer, no plane turn |

Nothing checks that a card's five settings agree, or that two cards do not
share a lane: that is the cost Joel accepted for jumpers over logic. The silkscreen
prints the column numbers on all three 2×8s at the same x. The netlist check
builds each card with all four at k (§8).

## 5. The edge header — port card J4

A shrouded right-angle 2×17 IDC header, keyed, in
`common/common-cards.md` §1.1 order:
- **odd pins are row a** (a*n* on pin 2*n*−1);
- **even pins are row c**;
- pins 33–34 are GND.

It feeds a ribbon of 0.3 m or less to the subscriber card. Subscriber cards
cannot share a layer with their port card at this pitch: their transformers,
relays and electrolytics are taller than 9 mm.

| a | signal | on the port card | c | |
|---|---|---|---|---|
| 1 | TX_CLK | '244 + 33 Ω | 1 | +5 V |
| 2 | LOOP_HB | '244 + 33 Ω | 2 | GND |
| 3 | TX_OCT | '244 + 33 Ω | 3 | +5 V |
| 4 | FILL | '244 + 33 Ω | 4 | GND |
| 5 | C_TX | in: 4.7 k to FILL (a pulled card leaves FILL); → the '157 | 5 | **+12 V: not connected** |
| 6 | A_TX (M) | in: 10 k pull-down | 6 | GND |
| 7 | RX_CLK = TX_CLK | '244 + 33 Ω | 7 | **−12 V: not connected** |
| 8 | RX_OCT | '244 + 33 Ω | 8 | GND |
| 9 | C_RX | the C capture, '244 + 33 Ω | 9 | **−48 V: not connected** |
| 10 | A_RX | the A_RX gate, '244 + 33 Ω | 10 | **−48 RET: not connected** |
| 11 | MUTE | tied to GND ("locked") | 11 | GND |
| 12 | card word | in, open drain: 680 Ω pull-up; → JP4 | 12 | **RING: never on this header** |
| 13 | `/ANS` | in, open drain: 680 Ω pull-up; → ON | 13 | **RING RET: never** |
| 14 | spare (RAI) | 680 Ω pull-up, unused | 14 | GND |
| 15 | key | | 15 | key |
| 16 | GND | | 16 | GND |

**No rail above +5 V passes through the port card.**
- ±12 V, −48 V and ringing reach a subscriber card on its own harness.
- The harness runs in a star from a fused distribution point, as
  `bus.md` §2.3 requires for ringing.
- `common/common-cards.md` §1.1 has RING on the socket's c12 in an MF8 shelf
  only. Here that pin stays open; how one card takes its rails from row c in a
  shelf and from the harness in a block is open (`common/common-cards.md` §7).

## 6. The bus and the adapter commons

**The bus 2×25** is `bus.md` §2.1's pinout, unchanged. It sits on the
header's **underside**, with row 1 outermost at both edges:
- **J4 on the right edge** is stock and serves the ribbon fill;
- **J5 on the left edge** is the mirrored footprint and serves the bridge fill.

J5 uses `telco:Bus_2x25_P2.54mm_Mirror`: the stock 2×25 with every x negated,
so pad 2 is at −2.54. Both are flipped to B.Cu, and their pads are checked
against the contract by `pcb.py`.

**The adapter commons J6** is a shrouded, keyed 2×5, odd pins signal and even
pins ground: TX_CLK (1), TX_OCT (3), FILL (5), MUTE_BLK (7), HCLK (9).
TX_CLK, TX_OCT, FILL and HCLK go out through 33 Ω. MUTE_BLK comes in with a
10 k pull-down, so an empty J6 busies nothing; what it does in the ports is
`fabric.md` §6.2. An 8-channel adapter (the MF8 unit, the local trunk) would
reach the port circuits by ribbon from each port card's J4. This form has no
single face for it (§9).

## 7. Electrical

| net | kind | pull | where |
|---|---|---|---|
| `/HA_L`, `/HB_L` | open drain, 8 a block | 1 k to +5 V | header R1, R2 |
| `/HA`, `/HB`, `/HW` (bus) | open drain, one each a block | 4.7 k, clock card | `mainboard.v` |
| `C_TXk` | totem ('157) from the card on lane k | 4.7 k to FILL_R | header RN1 |
| `WORDk` | open drain (the subscriber card) | 10 k, header RN2; 680 Ω on the port card | |
| `/WRk`, `/STBk` | totem, 33 Ω series | 10 k on the port card's side of JP2 | |
| POS, h, FIT | static, shunt to GND | 10 k to +5 V | RN2 (port), RN7 (header) |
| bus inputs | from the bus | 100 k to GND | header RN5, RN6 |

Decoupling: 100 nF per package, plus 47 µF bulk on header A at the bus entry
and 10 µF on header B and on each port card. Power enters on the bus 2×25 and
travels up the stack on 12 pins a board.

## 8. The netlist check

`make -C pcb netcheck BENCH="…"` (or `lockstep`), which is `pcb/sim/gen.sh`
then `pcb/sim/run.py`. The steps:

1. `gen_cards.py --check` holds every stack, link, bus, adapter and edge pin of
   the three schematics to `block-stack.json`.
2. `kicad-cli sch export netlist`, then `netlist.py`'s own checks: missing
   `lib_symbols`, duplicate references. kicad-cli exits 0 on both.
3. `net2v.py` writes `hdrbus_net`, `hdrlogic_net` and `portcard_net`:
   - one instance per package of `pcb/models/74hc.v`, keyed by pin number;
   - every multi-driver net resolved with no z;
   - the jumpers as module parameters (`POS`, `LANE`, `BLOCK`, `JUMPERED`).
4. `pcb/sim/mkstack.py` writes `pcb/out/gen/block_stack.v`, a module called
   **`block`** with `block.v`'s parameters and ports exactly.
   - It holds header A, header B, and one port card per `PORT_FITTED` bit, with
     POS = LANE = k.
   - It wires them as the stacking headers and J8 do: one wire per stack net
     and per link net.
   - Every multi-driver net is resolved from the sidecars `net2v` writes: open
     drains first, then enabled drivers, then weak ones.
   - A contention monitor sits on every net that two boards can drive.
   - It is generated, not written by hand, so a schematic edited in KiCad
     carries straight through.
5. `run.py` builds a newimpl bench from a snapshot of git HEAD with that file in
   place of `block.v`, and runs it. `--ref` runs the same snapshot on `block.v`.
6. **`run.py --lockstep`** is the stronger check (`pcb/sim/lockstep.v`). Its
   `block` holds `block.v` (renamed `block_ref`) and the boards side by side on the
   same inputs.
   - The exchange runs on the reference, so every bench's traffic is exactly the
     RTL's.
   - Every output of the boards is compared with the reference's at tick 5 of
     every cell, for the whole run.
   - A comparison counts once both sides have held their values for 3 master
     ticks, the tick just gone included. That absorbs three skews of a tick or
     less:
     - the boards' gate delays;
     - bench inputs moved off the clock, which one side sees a few ns early;
     - the '273 latching on `/WR`'s leading edge, a tick before `port.v`'s
       `wr_edge`.

     Once both are steady they must agree.
   - Comparisons are made at tick 5. The boards capture at the start of tick 4
     and the RTL at its end, so tick 5 is the first instant both have settled.
   - After a write, `c_rx` is not compared for a frame and `a_rx` for a pass.
     A latch that changes one tick early can move a port's capture a frame (C)
     or a pass (E) earlier: the same connection, begun one capture sooner.
     `tb_ha` showed one such frame on one port before the mask existed.
   - Any difference prints `BLOCK-STACK` and fails the bench.

**What is simulation only.**
- **The RC networks** (`rc_det`, `cr_rel`, `rc_filt` in `74hc.v`). A digital
  simulator has no capacitor. `rc_det` runs `port.v`'s own detector count on
  `tick_1k`, so the comparison is exact. `rc_filt` shortens the 1 ms `/RESET`
  filter to 1 µs, because `block.v` has none.
- **The HCLK shim.** `block.v` takes `cap_stb` and `clk`; the header takes HCLK
  from the bus.
- **The WORD lane.** The jumper joins two nets that both leave the card, and the
  generator cannot carry an outside driver through a switch. So `block_stack.v`
  passes the subscriber's `word_n[k]` to lane k itself. JP4's pins are held to the
  contract by step 1.
- **The HC ROUTE jumper is excluded.** Which highway a block drives is `mainboard.v`'s
  model, outside `block.v`'s ports.

### 8.1 What the check has found so far

- **A race in the RX_OCT flip-flop, now designed out.** As first drawn, U9
  sampled TX_OCT on TX_CLK's rise. TX_OCT changes on that same frame edge,
  so the flop took the old value only because the clock card's '4040 ripples.
  - The margin was CP at about 21 ns ('244 + '14) against D at about 48 ns
    (ripple, '244, '11), typical. At a fast-corner '4040, D moves inside the
    '74's setup time.
  - The netlist has no ripple, so the violation showed at every frame.
  - The fix uses U9's spare half. It takes TX_OCT on `/STB4`'s rise, the
    start of cell 5 (SLOT2's rise before the header split, §2.3), then moves
    it onto the frame edge. Each D now changes at least 5.9 µs from its clock.
    RX_OCT is unchanged: TX_OCT one frame late.
- **Two generator faults, fixed in `net2v.py`.**
  - A jumper column to a rail (POS, the block number, FIT) was dropped. Every
    strap read its pull-up, so every port card answered as slot 7 of block 7.
  - A resistor between two driven nets needs its direction given
    (`Sim.R = from:N`, on the lane pulls RN1 and the edge's R5).
- **The `/WS` select latch came out of reset "selected".** U17 stored the '688's
  active-low match as-is, so a cleared '175 (Q = 0) read slot 0 selected. The
  block then drove slot 0's card word onto `/HW` unasked, while `block.v` resets
  `sel_v` to 0. Only the lockstep comparison saw it; no bench checks `/HW`
  before a select. The fix uses a spare '14 section on U7: the latch now stores
  the match active high, and `/SELV` comes off `/Q3`.
- **`/RESET` is filtered on the board and not in `block.v`.** `tb_ctl` resets
  for about 1 µs, which the board's filter swallows by design. The simulated
  filter is 100 ns, and §2.1 states the 2 ms hold the real one needs.

**Where a difference is expected, and masked, in a lockstep comparison:**
- **The first pass after reset.**
- **The frame after a write to a port.** The '273 clocks at `/WR`'s edge, one
  `clk` earlier than `port.v`'s `wr_edge`.
- **The capture instants** are one master tick earlier on the boards, when
  `/STB` falls (tick 4), than in the RTL, which samples at the end of tick 4.
  The data are mid-cell and stable either way.

**The model library** (`pcb/models/`, `make test`) has 23 parts and 3 macro
cells:
- Each part is checked against its datasheet table on every input combination,
  with its delay checked 1 ns either side on every vector.
- Every pin table is checked against the KiCad stock symbol.
- It runs under Verilator and Icarus, inertial and transport.

The delay cell forks a timer per input change. Verilator 5.050 keeps one pending
`x <= #d` per variable and fires the survivor at the first one's time. That stuck
outputs after any two changes inside one delay, so it could not be used.

Every simulation runs under `pcb/tools/capped`, a cgroup with a memory ceiling.
A runaway netlist bench once reached 18 GB and took other sessions down with it.

## 9. Not measured, and open

- **Results.** See the netlist check's run log. Which benches have passed on the
  boards is recorded there and in the commit that lands them, not here.
- **Layout.** Placement is by script and routing by Freerouting 2.4.1, headless
  and without its optimiser.
  - All three boards are placed. Every connector is on its contract pads,
    checked by `pcb.py`, and KiCad's schematic parity is clean on each.
  - Routing state is in the commit that lands the boards, not here. The
    placement is a first pass for a human to improve.
- **Keying** the three stack headers against a card turned round rests on the
  offset hole alone.
- **Heights** are from catalogue figures, not a mock-up. Build a bare three-layer
  mock-up with spacers before stuffing anything.
- **The loading estimates** in §3 are arithmetic, not measured.
- **`exch.py mainboard`** has not been re-run for the block-local OR's single
  drain per block (`bus.md` §7).
- **The block adapter's face.** An 8-channel adapter has no single face on
  this form: it reaches the port cards by eight J4 ribbons, or the form grows
  one. Open until an adapter is built (§6).
- **Comments owed in the hand RTL.** They were not changed here (another session
  owns `newimpl`):
  - `block.v:6-7` (the mainboard's shunt field) and `:17` (cable A);
  - `block.v:23-30` (one jumper read three ways), `:42-43`, `port.v:27`,
    `:91-93`, `exch.v:108-113` and `mainboard.v:8-10` (the '148);
  - `:120` (the '157s);
  - `:233-238` (where the drains sit);
  - `port.v:2` ("eight and a half" packages: it is 13 with the socket drivers
    and the '157);
  - `mainboard.v:45`, `:75` (64 drains on each plane: it is one a block);
  - `frame_decode.v:7-8` (RX_OCT in one '74 half on TX_CLK: it is two, §8.1).
