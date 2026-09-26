# Terms — one name per object

Other documents cite this list. They do not re-name these things.

> **Status: normative for naming.** The exchange's glossary is
> `../exchange/README.md` §3; this list says what *not* to call things. The MF8
> shelf's connector family is still open (`common-cards.md` §7).

---

## Connectors

| Use | What it is | Do not use |
|---|---|---|
| **channel socket** | the 2 × 16 pin contract of §1 in `common-cards.md` — same roles on an MF8 shelf and an exchange block | bare “socket”, “slot interface” |
| **J4** | a port card's edge header to its subscriber card: the channel socket's signal pins in an exchange block, rails by harness (`../exchange/block-stack.md` §5) | "channel socket" when the block's J4 is meant and the rails matter |
| **stack header C** | the MF8 spacer-stack realization of that pinout (through the channel layers into Trunk-D) | bare “C”, “through-header”, “pinheader C” alone |
| **block header** | the bottom of a block's stack, two boards (A, the bus board; B, the logic board), with the adapter commons on J6 (`../exchange/block-stack.md`) | “face T”, “face C”; bare “header” when framing is meant |
| **port card** | one seat's latch, listener, gates and plane drains, stacked on the block header (`../exchange/fabric.md` §5) | "port circuit" for the board |
| **block adapter** | a trunk card serving a whole block's seats from the adapter commons (`../exchange/fabric.md` §6.2). Users: the local eight-channel trunk and the MF8 six-channel face (`../exchange/trunks.md` §3, §4) | “collect unit”, “adapter stuffing” alone; “highway tap” for the exchange MF8 face |
| **rear connector** | plant leave on the card (tip/ring, E&M, trunk pair); data DTE is the front edge | bare “connector” when this is meant |
| **the bus** | the exchange's one set of signals on a 2 × 25 header (`../exchange/bus.md`) | “cable A”, “cable B”, “mainboard” for the signals |
| **lamp stack** | the lamp panel's through-headers (`../exchange/proposed/lamps.md`) | “stack header” alone |
| **NUMBER, HC ROUTE, POS** | the block header's two jumpers (its number, and which highway it drives) and the port card's slot jumper (`../exchange/block-stack.md` §2.3) | “shunt field”, “block shunt” |
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
| **`LINE_HB`** | the MF8 line's 1.024 MHz half-bit clock; not on the exchange bus | `HB` |
| **`/HA`, `/HB`** | the supervision planes: port *p*'s M and `BUSY` in bit-time *p* | `HA[h]`, “A highway”, `PB` |
| **`/WS`, `/HW`** | the word select and the word wire | “pointing word”, “probe bus” |
| **`LOOP_HB`** | 128 kHz half-bit clock for the subscriber loop, socket a2 | `TX_HB` |
| **`SEIZE`** | the FXO jumper position, or the SS0 opcode — always say which | the pulse-generator level (`seized`) |
| **card word** / **F word** / **control word** | three different words; name which | bare “word” until the sentence has named one |
| **line frame** | MF8’s 8-bit frame on the pair | bare “frame” when fabric is meant |
| **fabric frame** | eight cells on a highway | bare “frame” when the line is meant |
| **cell** | one time position on a highway | “slot” for that (keep `SLOT[2:0]` as the counter; dialled `s` as the digit) |
| **card slot** / **seat** | on an MF8 shelf, the physical seat a card plugs into; on an exchange block, one of the eight **seats** | bare “slot” when the highway cell or dialled digit is meant |
| **F word** / **F lane** | framing alignment on the MF8 line | “header” for framing |
| **MF8 shelf** | the MF8 stack of channel cards and trunk | calling an exchange block a “shelf” |
| **exchange block** | eight ports, one highway: a header and eight port cards in a stack | calling it a shelf |
| **network unit** | the flood / claim unit | “network card” |
| **interface card** | the lamp panel's bus-facing card | |
