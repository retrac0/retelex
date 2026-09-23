# Terms — one name per object

Other documents cite this list. They do not re-name these things.

> **Status: normative for naming.** Nothing here is newly measured. Connector
> family (DIN 41612 vs 0.1-inch) is still open; pin *roles* are not.

---

## Connectors

| Use | What it is | Do not use |
|---|---|---|
| **channel socket** | the 2 × 16 pin contract of §1 in `common-cards.md` — same roles on an MF8 shelf and an exchange block | bare “socket”, “slot interface” |
| **stack header C** | the MF8 spacer-stack realization of that pinout (through the channel layers into Trunk-D) | bare “C”, “through-header”, “pinheader C” alone |
| **block ribbon** | the breakout of the block’s card-side star: loom of eight **slots**, ending at the **block header** (`fabric.md` §5.1) | “card-side ribbon”, bare “ribbon” for this object |
| **slot** | one channel-socket appearance on the block ribbon — the seat a card plugs into | “IDC tap”; bare “slot” when `SLOT[2:0]` or dialled `s` is meant |
| **block header** | the star collect on the shared board (`fabric.md` §5.2): eight appearances + commons (`MUTE_BLK`). The block ribbon ends here; a **block adapter** mates here instead | “face T”, “face C”, “T + C”; bare “header” when framing is meant |
| **block adapter** | the non-breakout mate of the same star — one board on the block header, ribbon slots not populated. Live users: MF8 (`mf8-unit.md` §1), local-trunk (`local-trunk.md`) | “collect unit”, “adapter stuffing” alone; “highway tap” for the exchange MF8 face |
| **rear connector** | plant leave on the card (tip/ring, E&M, trunk pair); data DTE is the front edge | bare “connector” when this is meant |
| **fabric cable A** | the 64-way IDC harness on the mainboard (`mainboard.md` §3) | bare “ribbon” / “cable” when A or B is meant |
| **control cable B** | the 16-way IDC harness on the mainboard | same |
| **hookbusy stack** | HA / LEB / PWR / control through-headers on the lamp cards | “stack header” without hookbusy |
| **block shunt** | the three 2 × 8 columns HC / HA / `/BLK` that give a block its number | “ONE 2x8 shunt field” (there are three columns); bare “jumper” for these |
| **jumper** | a config plug (OFFICE/SEIZE, compass, rate, tone-card 3-pin field) | **strap** as a hardware noun |
| **tied** | a pin held to a rail or to another pin by a wire | “strapped” for that |

Left alone on purpose — keep the wording those pages already use; do not invent
new names: the MF8 shelf 2 × 32 trunk/gateway connector; the Trunk-D ⇄ Trunk-A
board-to-board link (`mf8-trunk.md`); the PSU noisy ⇄ quiet link (`mf8-psu.md`);
the CVSD riser.

---

## Signals

| Use | What it is | Do not use |
|---|---|---|
| **`A_TX` / `A_RX`** | supervision on the channel socket | lead with `hook`, `ON_HOOK`, `M`, or `E` at the socket |
| **`M` / `E`** | the same levels inside the port: `M` is the card’s `A_TX`, `E` is the card’s `A_RX` | either pair alone when crossing the socket boundary — say both once |
| **card word** | pin a12 — class / options, open drain | bare “word”; `TYPE0` except once as the old MF8 reserved name |
| **`/ANS`** | pin a13 — open means the port may ring | `TYPE1` except once as the old MF8 reserved name |
| **`MUTE`** | channel-socket mute (framer not locked; an exchange block ties it locked) | `MUTE_BLK`, `LOCK`, `CD` |
| **`MUTE_BLK`** | block-header commons’ block-busy force when the link is down | shelf `MUTE` |
| **`LOCK` / `CD`** | trunk-board lamps / carrier detect — not socket pins | as aliases for `MUTE` |
| **`LINE_HB`** | 1.024 MHz half-bit clock for the MF8 line / fabric | `HB`, fabric `HB` |
| **`LOOP_HB`** | 128 kHz half-bit clock for the subscriber loop, socket a2 | `TX_HB` |
| **`SEIZE`** | the FXO jumper position, or the SS0 opcode — always say which | the pulse-generator level (`seized`) |
| **card word** / **F word** / **control word** | three different words; name which | bare “word” until the sentence has named one |
| **line frame** | MF8’s 8-bit frame on the pair | bare “frame” when fabric is meant |
| **fabric frame** | eight cells on a highway | bare “frame” when the line is meant |
| **cell** | one time position on a highway | “slot” for that (keep `SLOT[2:0]` as the counter; dialled `s` as the digit) |
| **card slot** | on an MF8 shelf, the physical seat a card plugs into; on an exchange block, prefer **slot** (ribbon) | bare “slot” when the highway cell or dialled digit is meant |
| **F word** / **F lane** | framing alignment on the MF8 line | “header” for framing |
| **MF8 shelf** | the MF8 stack of channel cards and trunk | calling an exchange block a “shelf” |
| **exchange block** | eight ports, one highway | calling it a shelf |
| **network unit** | the flood / claim unit | “network card” |
| **interface card** | the hook/busy stack’s cable-facing card | requiring a Verilog module rename (`common_card.v` stays) |
