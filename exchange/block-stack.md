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
- The new port card **replaces `pcb/portcard` in place** (since 2026-09-26 it is
  `pcb/portcard_RevC`, drawn by hand; the generated `pcb/portcard` is gone).
- **The header is two boards, stacked like the port cards** (later the same
  day, when 19 DIPs and their connectors would not fit one 100 × 100 board).

And on 2026-09-26:
- **The stack is two 2×25**: J1 on the left carries the 19 clock-class lines
  in a checkerboard, J2 on the right the rest. Both sit toward the front with
  pin 1 at the back, which frees the back edge (§3).
- **The header boards are `blkhdr_bus_RevA` (A) and `blkhdr_logic_RevA` (B).**
- **Header A takes the bus on one right-angle IDC at its front edge**, for the
  ribbon. The underside pair is gone. Its test strip and the adapter commons
  go along the back edge (§6).
- **Every jumper is a vertical header in the interior**, beside the logic it
  sets, for low-profile shunts (§4).
- **Header B shows each slot's M and BUSY on sixteen lamps** at its back edge,
  held by two 74HC '595s, plus FIT, RESET and RING_CAD status lamps (§2.1).
- **An RBT SOURCE jumper on header A** lets the block holding the ringback card
  drive the bus `RBT` (§4, `bus.md` §7).

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
| Schematics | `pcb/blkhdr_bus_RevA/` (header A), `pcb/blkhdr_logic_RevA/` (header B), `pcb/portcard_RevC/` (the port card, drawn by hand) — the headers' first draft by `pcb/tools/gen_cards.py`; **the schematics are the design from here on** |
| Boards | the same directories: placed by `pcb/tools/anneal.py` and `place.py`, routed by `pcb/tools/route.py` (Freerouting). Each carries a `.kicad_dru` letting a footprint's own pads sit 0.2 mm apart (the stock TO-92's 0.22 mm, under the 0.25 mm track clearance) |
| Check | `make -C pcb netcheck` / `make -C pcb lockstep`: netlist → Verilog → the newimpl benches, `block.v` swapped for the boards, or run beside them |
| Reference | `newimpl/rtl/block.v`, `port.v`, `frame_decode.v`. A difference means a schematic is wrong until shown otherwise |

---

## 1. The form

```
        port card 7   ┐
        …             │  eight port cards, 100 × 100, 12.6 mm pitch (11 mm gap)
        port card 0   ┘  each: J1 J2 long-tail stacking headers, J4 edge header front
   ─────────────────────
        header B          the logic board: J1 J2 long-tail like a port card;
                          J8, a 2×6 pin header on its UNDERSIDE, into A; the lamps at the back
   ─────────────────────
        header A          the bus board: J1 J2 sockets and J8's 2×6 socket on top;
                          the bus IDC at the front edge
   ═════════════════════  plate, 20 mm standoffs
```

- **Pitch: an 11 mm gap, 12.6 mm board to board.** 0.4″ does not close with
  stock parts. An 8.5 mm socket body under a 1.6 mm board leaves 0.05 mm of air,
  and the upper card's solder fillets sit exactly there. At 11 mm, the stock
  2×25 long-tail stacking header (Raspberry Pi HAT class) seats 5.9 mm deep,
  and about **9 mm of part height** is usable under the next card: DIPs in
  sockets, and low-profile shunts. Samtec SSQ-125-03-G-D is the gold-plated upgrade.
  - The other 0.4″ stacks (hookbusy, the CVSD riser, MF8) have the same
    problem and are not changed here.
- **Holes.** Four M3 holes, and the datum is the standoffs, not the headers.
  H2 sits 3 mm off its corner, so a card turned round does not line up with
  the stack. The stack headers key it too: both sit toward the front.
- **Connectors by edge.**
  - **Stack:** J1 at the left edge, J2 at the right, pads y 27.0–87.96 mm
    (front-aligned, 7.3 mm clear of the front holes), pin 1 at the back end.
  - **Front edge:** the port card's edge header J4; header A's bus IDC J4;
    header B's test strip J9. Each right-angle IDC shroud stands about 9 mm,
    so the card above keeps its leads over it trimmed to 1 mm.
  - **Back edge:** the lamps (header B, and the port card's own); the test
    strips of header A (J7) and the port card (J5); header A's adapter
    commons J6.
  - **Interior:** every jumper, vertical, beside the logic it sets (§4).
    They are set once, with the boards above lifted off.
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
- **B holds the rest:** the control word, the write decode, the frame decode,
  the `/WS` select and the lamps.

Everything B needs from A is already a stack net except six, which ride J8.
Reference designators are unique across the pair, so "U14" names one part in a
block's header.

### 2.1 The block header — 22 DIP on two boards

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
| U20 | B | '02 | `hw_pd` (to A's Q3 on J8); the latch clock; the match, inverted into the latch; LAMP_CK = NOR(`/STB4`, `/SELM`), the lamps' shift clock | `block.v:273`, `:259-267` |
| U21, U22 | B | '595 ×2 | **the lamps**: slot k's `/HA_L` (U21, M) and `/HB_L` (U22, BUSY) in its turn | none: a display |
| D1–D16 | B | 3 mm LED, right-angle | one row at the back edge, 5 mm pitch, the lenses over the edge by about 4 mm: hook (M) for slots 0–7 on D1–D8, green, beside U21; BUSY on D9–D16, orange, beside U22; RN10, RN11 1 k behind them | — |
| D17–D19 | B | 3 mm LED, standing | FIT, RESET, RING_CAD, a column at the back right behind the lamp row; each 1.5 k from +5 V to `/FIT`, `/RST`, `/RING_CAD` | — |

**The lamps.** In each of the block's eight frames `/STB4` falls mid-frame
while `/SELM` is low, so LAMP_CK rises once a slot, in slot order, and shifts
that slot's `/HA_L` into U21 and `/HB_L` into U22. `/SELM` rises as the scan
leaves the block and copies all eight to the outputs at once, slot 0 on Q7.
A lamp is lit while its card pulled the plane in its last turn: one pass,
8 ms, behind, lit by DC at about 2.9 mA, with no scanning. `/OE` is `/FIT`, so
an unfitted block's lamps are dark. The '595 replaced the '259 first proposed:
its shift clock is U20's spare NOR, where the '259's active-low enable would
have needed an inverter B does not have, and it needs no address lines. The
stack wrapper checks every lamp against its own card's drain (§8).

The header also carries RN1–RN11 and R1–R15 (all on A except RN2, RN4, RN9,
RN10, RN11 and R13–R15):
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
- **The stack is two 2×25, and the header card is ribbon-fed** (2026-09-26).
  The three 2×20 spent 36 grounds guarding every fast line from every side;
  the checkerboard on J1 guards each clock-class line with a ground or a
  static line on all sides for 18. The back edge came free for lamps and test
  strips. Header A lost its underside bus pair and J5: the block header uses
  the ribbon fill only (`bus.md` §2.3).
- **The number is its own jumper.** The 2×8 of `block.v:23-30` routes HC_OUT onto
  HC[h], and both of its pins are live highway nets, so a '148 cannot read it.
  - JP2 NUMBER, a 2×4, gives h directly: a shunt reads 0.
  - Its fourth position, FIT, is the '148's old GS. It gates HC_OUT's '244,
    `/BLK`, the `/WS` answer and the plane drains.
  - The '148 is gone. The two jumpers must agree; nothing checks them.
- **The strobe '138 is drawn.** `port.v` assumes it; `block.v` has no region for it.

---

## 3. The stack

Two 2×25, identical on every card. The port cards and header B carry a
long-tail stacking header (`telco:Stack_2x25_P2.54mm_LongTail`, the stock
2×25 socket's pads); header A carries a plain 2×25 socket in the same holes.
Pin *n* of every card is one net. Both sit toward the front, pads y 27.0 to
87.96 mm, with pin 1 at the back end, so a card turned round cannot seat. They
sit 2 mm further back than first drawn, clear of the front holes (Joel).

**69 signals** (43 commons, 24 lanes, and the two plane lines), **6 × +5 V,
18 × GND**, and 7 spares that pass through and connect to nothing.

**J1 is the clock connector.** Its 19 lines whose edges are capture instants
(bold: `/STB0–7`, `/WR0–7`, TX_CLK, LOOP_HB, `/RST`) sit in a checkerboard.
Each has only GND, +5 V or a static line (H0–2, MUTE_BLK, `/RING_CAD`) beside
it and across from it. `stackdef.py` asserts that. **J2** carries what is
sampled mid-cell or held for a frame: SCAN, HC, the control word, the planes
and the C_TX and WORD lanes. The '164 outputs ripple on every shift, so SRC,
BSY and CLM are read only at a `/WR` edge, as on the bus.

#### J1 — left: the clocks and the socket commons

| pins | odd | even | | pins | odd | even |
|---|---|---|---|---|---|---|
| 1–2 | +5 V | +5 V | | 27–28 | **`/WR1`** | GND |
| 3–4 | **`/STB0`** | GND | | 29–30 | GND | **`/WR2`** |
| 5–6 | GND | **`/STB1`** | | 31–32 | **`/WR3`** | GND |
| 7–8 | **`/STB2`** | GND | | 33–34 | GND | **`/WR4`** |
| 9–10 | GND | **`/STB3`** | | 35–36 | **`/WR5`** | GND |
| 11–12 | **`/STB4`** | GND | | 37–38 | `MUTE_BLK` | **`/WR6`** |
| 13–14 | GND | **`/STB5`** | | 39–40 | **`/WR7`** | `/RING_CAD` |
| 15–16 | **`/STB6`** | GND | | 41–42 | GND | `HA_RX` |
| 17–18 | GND | **`/STB7`** | | 43–44 | `RBT` | `FILL` |
| 19–20 | **`TX_CLK`** | `H0` | | 45–46 | `TX_OCT` | `RX_OCT` |
| 21–22 | `H1` | **`LOOP_HB`** | | 47–48 | spare | spare |
| 23–24 | `/RST` | `H2` | | 49–50 | +5 V | +5 V |
| 25–26 | GND | **`/WR0`** | |  |  |  |

#### J2 — right: data, the planes and the lanes

| pins | odd | even | | pins | odd | even |
|---|---|---|---|---|---|---|
| 1–2 | +5 V | GND | | 27–28 | `SRC4` | `SRC5` |
| 3–4 | `SCAN0` | `SCAN1` | | 29–30 | `/HA_L` | `/HB_L` |
| 5–6 | `SCAN2` | `SCAN3` | | 31–32 | `C_TX0` | `C_TX1` |
| 7–8 | `SCAN4` | `SCAN5` | | 33–34 | `C_TX2` | `C_TX3` |
| 9–10 | spare | spare | | 35–36 | `C_TX4` | `C_TX5` |
| 11–12 | `HC0` | `HC1` | | 37–38 | `C_TX6` | `C_TX7` |
| 13–14 | `HC2` | `HC3` | | 39–40 | spare | spare |
| 15–16 | `HC4` | `HC5` | | 41–42 | `WORD0` | `WORD1` |
| 17–18 | `HC6` | `HC7` | | 43–44 | `WORD2` | `WORD3` |
| 19–20 | GND | spare | | 45–46 | `WORD4` | `WORD5` |
| 21–22 | `CLM` | `BSY` | | 47–48 | `WORD6` | `WORD7` |
| 23–24 | `SRC0` | `SRC1` | | 49–50 | GND | +5 V |
| 25–26 | `SRC2` | `SRC3` | |  |  |  |

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
- **Position.** J8 is at (41, 60) on both boards, pin 1 at the back left,
  clear of the bus IDC and in the middle of what uses it.
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

Every jumper is a **vertical 2.54 mm header in the interior**, beside the logic
it sets, for low-profile shunts: about 6 mm tall against the 9 mm under the
next card (Joel, 2026-09-26: "move headers to the interior near where they are
needed"). None needs changing with the stack assembled. A port card's follow
its slot, and moving a card means unstacking anyway. The header's are set once
for the block's place in the exchange, and header A is the bottom board.

Each port card carries **four jumper blocks**, and all must say the same slot k:

| ref | size | shunt in column k means | missing |
|---|---|---|---|
| JP1 POS | 2×3 | a shunt reads 0: POS = k in binary, S0 S1 S2 | open reads 1: no shunts is slot 7 |
| JP2 WR | 2×8 | this card's `/WR` is lane `/WRk` | never written: 10 k holds `/WR` idle |
| JP3 C_TX | 2×8 | this card's C (after ringback) drives lane `C_TXk` | lane k stays on FILL; the card is heard by no one |
| JP4 WORD | 2×8 | the subscriber's a12 is lane `WORDk` | lane k reads no word: class 000, unequipped |

On the port card they sit by what they set: POS by U5 (the eq_own '688), WR by
J1's `/WR` pins and U10, C_TX by J2's C_TX pins and the '157, WORD by the
WORD pins and the edge's pull-up: on `portcard_RevC`, WR stands against J1's `/WR`
pins row for row, C_TX against J2's C_TX pins, WORD in the front-right corner.

Header A has three:

| ref | size | means | missing | beside |
|---|---|---|---|---|
| JP1 HC ROUTE | 2×8 | HC_OUT drives highway HC[h] (silkscreen h = 7…0) | the block drives no highway, and still listens | the bus's HC pins, R3 |
| JP2 NUMBER | 2×4 | FIT, then h0 h1 h2: a shunt reads 0; FIT shunted = the block is fitted | h reads 7; no FIT: no HC drive, no `/BLK`, no `/WS` answer, no plane turn, lamps dark | RN7, U4 |
| JP3 RBT SOURCE | 2×8 | lane k's C_TX drives the bus `RBT` through R12, 100 Ω | this block does not drive `RBT` (every block but one) | J2's C_TX pins, U15, RN1 |

**RBT SOURCE** answers `bus.md` §7: nothing brought a ringback card's output to
bus pin 42. The ringback card is a card in some block's slot k; that block
alone gets a shunt in column k, and its lane `C_TXk` goes onto the bus through
100 Ω, as every bus driver does (`bus.md` §2.4). Two shunted blocks would fight
on `RBT`: one per exchange. The netlist check leaves it open, because `block.v`
takes `rbt` as an input.

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

**The bus 2×25** is `bus.md` §2.1's pinout, unchanged, on **one shrouded,
keyed right-angle IDC at header A's front edge (J4)**, for the daisy-chained
ribbon (Joel, 2026-09-26). The underside pair and J5, the mirrored bridge
header, are gone: the block header uses the ribbon fill only. J4 is
`Connector_IDC:IDC-Header_2x25_P2.54mm_Horizontal`, centred, pin 1 at the
right-hand end, odd pins the inner row, like the port card's edge header; its
pads are in the contract and `pcb.py` checks them.

**The adapter commons J6**, at header A's back edge, is a shrouded, keyed 2×5, odd pins signal and even
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

| lamps | '595 outputs sink an LED from +5 V | 1 k each (RN10, RN11), about 2.9 mA | header B |
| status lamps | `/FIT`, `/RST`, `/RING_CAD` sink an LED | 1.5 k from +5 V, about 2 mA | header B R13–R15 |

Decoupling: 100 nF per package, plus 47 µF bulk on header A at the bus entry
and 10 µF on header B and on each port card. Power enters on the bus IDC and
travels up the stack on 6 +5 V and 18 GND pins a board.

## 8. The netlist check

`make -C pcb netcheck BENCH="…"` (or `lockstep`), which is `pcb/sim/gen.sh`
then `pcb/sim/run.py`. The steps:

1. `gen_cards.py --check` holds every stack, link, bus, adapter and edge pin of
   the three schematics to `block-stack.json`.
2. `kicad-cli sch export netlist`, then `netlist.py`'s own checks: missing
   `lib_symbols`, duplicate references. kicad-cli exits 0 on both.
3. `net2v.py` writes `blkhdr_bus_RevA_net`, `blkhdr_logic_RevA_net` and `portcard_RevC_net`:
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
   - **The lamp check.** At cell 4 of each of the block's frames it takes card
     k's own `/HA_L` and `/HB_L` drains, on both sides of `/STB4`'s fall, and
     after the turn it holds header B's sixteen '595 outputs (probe ports of
     `blkhdr_logic_RevA_net`) to them at every mid-cell. A slot whose card
     moved at that instant is not judged that pass. A wrong lamp prints
     `BLOCK-STACK`; the run ends with how many samples were right.
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
- **The HC ROUTE and RBT SOURCE jumpers are excluded.** Which highway a block
  drives is `mainboard.v`'s model, outside `block.v`'s ports; `rbt` is an input
  of `block.v`, driven by the bench.
- **The LEDs and their resistors are excluded.** A digital simulator has no
  LED. The '595s that drive them are simulated and checked.

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

### 8.2 Results, 2026-09-26

On the two-board header and the port card as drawn (newimpl at `6d69aef`; the
block RTL has changed only in comments since), in lockstep with `block.v`:

| bench | ports fitted | checks | block outputs differing from `block.v` |
|---|---|---|---|
| `tb_ctl` | 2 | 17 pass | none |
| `tb_debug` | 8 | 18 pass | none |
| `tb_line` | 2 | 23 pass | none |
| `tb_word` | 10 | 26 pass | none |
| `tb_tie` | 4 | 16 pass | none |
| `tb_dial` | 2 | 36 pass | none |
| `tb_mini` | 7 | 42 pass | none |
| `tb_ha` | 64 | 13 pass | none |
| `tb_fabric` | 64 | 9 pass | none |
| `tb_probe` | 64 | 9 pass | none |

Before the header split, with the boards driving the exchange: `tb_dial` 36,
`tb_debug` 18, `tb_line` 23, `tb_word` 26 and `tb_mini` 42 passed. `tb_mini` in
lockstep ran 2.8 hours.

The model's setup-and-hold watch fires in two places, both expected:
- **Each U9 once at power-on**, 12 ns in, before any clock has a history.
- **The port card's C capture (U6)**, 18 times across the three 64-port
  benches. When the '273 changes, by a write or a release, the highway select
  and the slot select move at once, and the capture can take one spurious edge.
  The next frame's capture replaces that bit: one bit of a new connection, which
  CVSD does not hear. It is the frame lockstep masks after a write.

Cost: a 64-port bench takes 15–45 minutes to build and up to an hour to run.
Every run is under `pcb/tools/capped`.

Where the boards may legitimately differ from `block.v` for a tick, a frame or
a pass, and what lockstep does about it, is step 6 above.

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

- **Results** are §8.2. The network benches (`net`, `chain`, `lnet`, `lfull`,
  `lchain`, `ltu`, `max`) have not been run on the boards: each builds a whole
  exchange of netlists, and the slowest took 88 minutes for one block.
- **Layout.** Placement is by script and routing by Freerouting 2.4.1, headless
  and without its optimiser.
  - All three boards are placed. Every connector is on its contract pads,
    checked by `pcb.py`, and KiCad's schematic parity is clean on each.
  - Routing state is in the commit that lands the boards, not here. The
    placement is a first pass for a human to improve.
- **Keying.** A card turned round meets the offset hole and finds its stack
  headers at the back, not the front.
- **`portcard_RevC` moved onto the two 2×25** (2026-09-26). In its schematic J3
  went and J1, J2 were redrawn from `block-stack.json`, keeping their symbol
  UUIDs; on its board J1 and J2 sit on the contract pads, J5 and the ten
  port-state LEDs moved to the back edge, the lane jumpers beside their lanes,
  and the rest was re-placed around them (`anneal.py`, pinned parts). The pin
  contract holds on all three cards and the board's schematic parity is 0. The
  placement is a first pass; RevC is a hand board, and Joel's to improve.
- **Heights** are from catalogue figures, not a mock-up. Build a bare three-layer
  mock-up with spacers before stuffing anything. The tightest places are the
  right-angle IDC shrouds, about 9 mm under an 11 mm gap: header A's bus J4
  and adapter J6, the port card's J4. Header B keeps its parts off A's bus
  shroud; its lamp row stands over A's J6, so those leads are trimmed.
- **The loading estimates** in §3 are arithmetic, not measured.
- **`exch.py mainboard`** has not been re-run for the block-local OR's single
  drain per block (`bus.md` §7).
- **The block adapter's face.** An 8-channel adapter has no single face on
  this form: it reaches the port cards by eight J4 ribbons, or the form grows
  one. Open until an adapter is built (§6).
