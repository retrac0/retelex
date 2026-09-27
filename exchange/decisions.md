# The exchange — decisions and what they retired

This is the log of ideas the spec no longer holds, one bullet each with the
reason it went. The old text of every file named under "Was:" is in git at
commit `ab23e74`, e.g. `git show ab23e74:exchange/mainboard.md`; a bare `.md`
name is in `exchange/`, a bare `.v` in `newimpl/rtl/`. The current design is in
the other documents; nothing here is normative.

---

## The fabric and the planes

- **Eight A highways `HA[0..7]`, the block's A commutator and the port's A
  highway select**, and the hook read-backs built on them (the console's two
  '151 on a 13-conductor cable-A tap, a hook-lamp field of eight '259 on
  `SLOTQ`) — replaced by `/HA` and `/HB`, two scanned open-drain planes at
  64 kbps (the fold, 2026-09-24); M is the port's drain on `/HA`, read by
  probes. Was: fabric.md §1.1, §3.1, §3.2; protocol.md §3; mvp.md §3;
  port-card.md; console.md §1.1, §7.2, §9; observers.md §2; terminal.md §1,
  §3.
- **The probe bus `PB[1:0]` and the block's `BUSY` and word commutators**, and
  what read `BUSY` and class off them (the console inside its tenure; a
  busy-lamp field with a word-decoded row, a '123 inhibit and `/CLR` =
  `/RESET`; the port watch's block match, word '164 and STALE) — `BUSY` has
  its own scanned plane, `/HB`, needing no word, inhibit or tenure, and a word
  is read on `/HW` by a `/WS` select; nothing is block-steered. Was: fabric.md
  §1.1, §2, §3.1; mainboard.md §2.3, §3.2; console.md §1.1, §7.2, §9;
  observers.md §3, §5; terminal.md §1, §3.
- **A scanner that could stall and repeat a visit** (the marker's 6-bit
  counter on `CLK_8K`, eight ports a millisecond, `SCAN[2:0]`, `ADVANCE` and
  `START` on cable B; a disturbed visit repeated, an event dirtying the probe,
  the probe re-steered when `/CON` rose) — `SCAN[5:0]` is six free-running
  stages of the clock card's divider with no enable; a pass is 1 ms and
  nothing is repeated. Was: fabric.md §2; mainboard.md §2.3.3, §2.3.4, §3.2,
  §8; marker.md §3, §4; mvp.md §2; console.md §2.2; counters.md §9.3.
- **The scanner and monitors stepping on `CLK_8K`, a 125 µs visit; word costs
  reckoned against a 1 ms block visit and an 8 ms scan** — the scan steps at
  every frame edge, a port's turn is one 15.6 µs bit-time, and a pass is 1 ms
  for all 64 ports. Was: common/clocks.md §1; mainboard.md §2.1; console.md
  §2.5.
- **The probe steered by a control word** (a console `PROBE` word with no `WR`
  on `DST[2:0]`, the marker's once-a-block steer, reads on cable B by a
  pointing word, the last-word display's mode that showed steers at the end of
  an `SCLK` burst) — a reader names a port on `/WS` in its bit-time and reads
  `/HW` through `word_rx`; the control bus carries writes only, and every word
  ends in `WR`. Was: fabric.md §1.1; mainboard.md §2.3.2, §2.3.3;
  mini-marker.md §4, §10; extensions.md §2.2; console.md §1, §7.2;
  observers.md §6.
- **`/HW` driven from whichever port the '164s last named, write words
  included** — a block drives `/HW` only after a `/WS` select; `faults.py` F24
  restores the old rule and turns `tb_word` red. Was: debugger.md §5.
- **"Sixteen wires are the switch"** — eight `HC` highways; supervision is on
  the planes. Was: fabric.md §1.1.
- **The economy form (A in the second half of the cell)** — superseded by the
  fold, which saves wires without spending edge margin. Was: fabric.md §6.
- **A trunk's A out as "E + `CLAIM`, 2 × '32 on trunk blocks", or as "E as it
  stands"** — `CLM` is in every port's `A_RX` gate (`A_RX` = E + `CLM`), never
  on the plane, so the claim crosses on the A wire. Was: fabric.md §3.1;
  baseband.md §3.1, §3.5.
- **`MUTE_BLK` ORed by the block into its `BUSY` commutator, jumpered in when
  stuffed; "`MUTE_BLK` stops the card's words"** — every port ORs it into its
  own `BUSY`, a pull-down on J6, no jumper; it only forces `BUSY`, and lock
  gates the words (`port.v`). Was: fabric.md §5.2; local-trunk.md §3;
  mf8-unit.md §5.4, §5.8; terminal.md §2.
- **`RBT` substituted by 2 × 74HC157 a block** — one '157 on each port card
  (block-stack.md §2.2 U12). Was: common/tone-card.md §5.
- **A "no port" seat for a ringback card** (a commutator input with no port
  circuit) — `block.v` puts `FILL` on an unfitted port and a lane is driven
  only through a port card's '157; the block-stack form has no such seat.
  Was: features.md §2; common/tone-card.md §5.1 (quoting mvp.md).

## The bus and the physical form

- **Two cables, fabric cable A (64-way) and control cable B (26-way)**, with
  the console on cable B, the debugger on the common-control tap, and
  `HB[0..7]` on a future cable A with no pin table for the folded plane — one
  bus of 32 signals on one 2 × 25 header (Joel, 2026-09-25), the debugger in
  any position; bus.md §2 pins the eleven nets, and `/HB` did better. Was:
  mainboard.md §1, §3, §3.1, §3.2; operator.md §1; debugger.md §1;
  hookbusy.md §3.2, §8, §9.
- **`/CON`, the console's bus request, and the marker's '244 enable honouring
  it** — no console is built and `/CON` left the bus; spare pin 48 is kept for
  a proposed console request line, and the unit has no yield input (open).
  Was: fabric.md §2; mainboard.md §2.3, §3.2, §8; console.md §1.1,
  §2.1–§2.2, §9, §11.
- **The scanned port's M, `BUSY` and word carried to the cards** (on cable B /
  `PB1` for a card to watch the scan; pin 23 held because "`M` of the scanned
  port wants a pin"; the console's pin claim) — each listener fits its own
  probe, and M is `/HA`; M was never a bus conductor. Was: mainboard.md §3.2,
  §9; marker.md §4; common-control.md §2.2, §2.4; mvp.md §5; console.md §2.3.
- **The unit's writes drained through the marker's serialiser ("the marker
  drains a burst of writes the unit queued")** — the unit is the bus's second
  master, with its own serialiser, `/UREQ` and a `WAIT` of 640 ticks, no
  grant. Was: common-control.md §2.2.
- **Two consoles; a free-running `SCLK` jumper with two masters** — dropped;
  two masters exist already, and the `SCLK` jumper is bus.md's. Was:
  console.md §12.
- **"Absent reads empty because `PB` is pulled low"; "`HA` is pulled to
  ground: on-hook"** — the planes idle high, and absence reads idle because
  nothing pulls. Was: mainboard.md §2.2, §6; protocol.md §3; mvp.md §2.
- **mainboard.md §9's open items on `SCAN[2:0]`, the shunt as a stub,
  1.024 MHz radiation and ground bounce on fourteen lines** — the signals they
  concern left the bus. Was: mainboard.md §9.
- **The block shunt field on the mainboard (HC / HA / `/BLK` columns), and
  diagnosing its column from the two lamp fields** — the block's own header
  jumpers route `HC_OUT` and give its number, a '688 makes `/BLK`, and
  header- and slot-jumper signatures replace the diagnosis. Was: mainboard.md
  §1, §4, §6; fabric.md §2, §3.1, §5.1; observers.md §4.2.
- **One header jumper read by a '148 as the block's number** — two jumpers, HC
  ROUTE and NUMBER: the route jumper's pins are live highway nets, so a '148
  cannot read them (block-stack.md §2.3). Was: newimpl/README.md §3; `block.v`,
  `port.v`, `exch.v`, `mainboard.v` comments.
- **A 96-way DIN block connector with the eight `/BLK` decoder lines** — the
  bus 2 × 25 sits under the block header. Was: mainboard.md §3.3.
- **The block ribbon whose slots are the channel sockets, each port circuit
  populated beside its card; two blocks in an 84 HP subrack; a 21-slot
  subrack of switch cards** — the block is a stack: header boards and eight
  port cards, each card on a J4 ribbon (block-stack.md). Was: fabric.md §5.1;
  protocol.md §3; port-card.md.
- **The block adapter mating a 64-way DIN appearances shell on the header;
  "eight ribbon plugs on one board are refused"** — the stack has no single
  face; open in block-stack.md §9. Was: fabric.md §5.2.
- **"The connector family is chosen once for shelf and block, or this document
  is void"** — the block has chosen a 2 × 17 IDC J4 ribbon while the shelf has
  not; the two-ways-in question is open (common-cards.md §7). Was:
  common/common-cards.md §7.1.
- **Rails on socket row *c* in an exchange block** (−48 V phantom, FXS
  battery, ringing, ±12 V; the POTS trunk's ±12 V on c5/c7) — the block's J4
  carries +5 V only and leaves them unconnected; the rest come on the
  subscriber card's own harness (block-stack.md §5), and for the POTS trunk it
  is open. Was: common/channel-cards.md §2.1, §2.4 c9/c10, §3.7 c5/c7,
  c9–c13; common/cvsd-codec.md §7.1; pots-trunk.md §6.
- **Ringback and ROM tone-card outputs punched in a wiring field** (to ports
  02/03 and to `RBT`, pin 42, the ringback card's rear pin included) — the
  block-stack form has no wiring field and no path from a subscriber card onto
  `RBT`; how the card reaches it is open (bus.md §7; common/tones.md §9). Was:
  mainboard.md §2.1; features.md §2; common/tone-plan.md §4.4;
  common/tone-card.md §1, §5.
- **Package counts: a port 8¼, a block ≈ 15¼ shared / ≈ 82 full, an exchange
  ≈ 655; "13 a block, ≈ 80"; ≈ 82 for a block's fabric and ≈ 154 in all
  (conference.md)** — pre-fold counts; as drawn, 13 DIP a port card and 20 a
  header, ≈ 124 a full block. Was: fabric.md §3.1, §3.2, §5; protocol.md §3;
  mvp.md §1; conference.md §5.

## Clocks

- **`LINE_HB` (1.024 MHz) on the bus** — nothing read it; the tap stays in the
  clock card for `SLOTQ`. Was: fabric.md §2; mainboard.md §2.1, §3.1, §8;
  common/clocks.md §1, §6.
- **`TX_CLK`, `TX_OCT`/`CLK_8K`, `RX_OCT`, `FILL` and `TICK` as bus signals
  from the clock card** — each block makes them from `SLOT2` and `SCAN`. Was:
  fabric.md §2, §3.4; mainboard.md §2.1, §3.1; common/clocks.md §1;
  common/common-cards.md §1.1; mvp.md §1.
- **`RX_OCT` from one flip-flop (one '74 half on `TX_CLK`)** — two halves: the
  one-step form races the '4040 ripple. Was: fabric.md §3.4; mainboard.md
  §3.5.
- **A slot counter ('393, reset by `SYNC`) at each block** — one '163 on the
  clock card. Was: protocol.md §3.
- **`RX_CLK` as the opposite phase of `TX_CLK`** — `RX_CLK` is `TX_CLK`. Was:
  protocol.md §6.
- **A trunk slaving the clock card to its far end** (a jumper and footprint
  for a trunk's `RX_CLK`, a socket pin, the bus spare, the baseband fifth
  conductor, MF8's spare commons pin as a recovered-clock lead) — the network
  is plesiochronous and no slaving is kept (network.md §9). Was:
  common/common-cards.md §1.4, §9; mainboard.md §3.4; network.md §8, §10;
  baseband.md §3.3, §3.5; mf8-unit.md §5.4.
- **"Bit-exact 64 kb/s data passes over copper ties"; "two crystals in a
  system"** — every exchange has its own crystal; data slips between
  exchanges (network.md §8). Was: common/clocks.md §2, §5.

## The card word, classes and nails

- **The card word as sixteen bits at 128 kHz on `LOOP_HB`**, loaded every
  `CLK_8K` on `TX_OCT` alone into 2 × '165 (the second for a secondary, a
  trunk's secondary `FF`) and read over a 125 µs visit — the card shifts one
  '165 on `TX_CLK` at 64 kHz, loaded on `TX_OCT` · `TX_CLK`, and only the
  primary octet is read, a bit a frame on `/HW`. Was: common/common-cards.md
  §1.2, §1.3, §2; common/clocks.md §1, §5; protocol.md §5; mainboard.md §2.1,
  §2.3.2; extensions.md §2.2; common/channel-cards.md §2.4 (a2, a3), §4.4;
  baseband.md §3.5; mf8-unit.md §4.2, §5.4; pots-trunk.md §6 a3, a12;
  terminal.md §3.
- **"Reading only the first bits buys gates, not time"; a fourth '151 on
  `DST[2:0]` commutating word pins; two '164 and a '30 at the marker** — the
  block's '151 is addressed by the select latch, and `word_rx` takes eight
  frames. Was: extensions.md §2.2.
- **The secondary "fails closed"; a trunk's secondary must be `FF` for the
  unit** — nothing reads the secondary; the claims are recorded as not in
  force (card-word.md §7). Was: extensions.md §2.2; groups.md §2.6.
- **A secondary word on pin a14 (a fifth '151 and `PB2`; "eleven pins where
  its optional word parts are fitted")** — retired with groups.md; a14 stays
  spare (`rai_n` in the RTL). Was: groups.md intro, §3–4;
  common/channel-cards.md §2.4.
- **"A secondary word's 16-frame strobe is `SCAN[3:0]` decoded on the card"**
  — the socket carries no `SCAN`; the secondary is open (card-word.md §8).
  Was: mainboard.md §3.4.
- **`tt h h h s s s` digit order** — the RTL and extensions.md put the units
  digit first. Was: groups.md §2.1.
- **Legacy class numbers (class 4 the unit's, class 6 cannot-complete, class 5
  or 6 for sources, class 2/3 hunts for 0 and 9)** — classes are family and
  member in wire order; cannot-complete is port 03. Was: marker.md §3, §5.2;
  extensions.md status; mvp.md §4.
- **Class *operator* (code 100), and a second position of that class** — a
  position is a line that answers to 04; the code is reserved. Was: groups.md
  intro, §1; marker.md §1; extensions.md §2.3; terminal.md §3.
- **Class *data line* (110)** — option `D` on a line; the freed code is the
  tone trunk. Was: extensions.md §2.
- **A data call "set up like any other"; data bit `D` as "optional hygiene" on
  a dual-mode line** — a `D` line is never switched: under the class marker it
  is neither caller nor called (`word_dec.v`), so `D` would bar every switched
  call; a data circuit is a mutual nail, and switched (SDU-1 insert-1) data
  needs `D` clear and is open. Was: features.md §8; common/su-1.md §7;
  common/sdu-1.md §9.
- **The `o` run of adjacent ports for hunt groups and bridges** (overflow
  bits, a scanner-compare hunt of ≈ 2 packages, 16 ms) — a comparison
  (answers-to) cannot lose a card or ring a stranger; a bridge's legs answer
  to its number, and the class marker hunts them from 01, a read a pass. Was:
  groups.md §1; extensions.md §2.4; conference.md §5, §6.
- **Class *conference* and a leg class; a group with a bridge in it** — a
  bridge is a group of ordinary lines; extensions ringing through a bridge are
  set aside until a leg can be marked. Was: groups.md §5, §6.
- **Field A (tag `00` beside an answers-to with a zero payload)** — retired;
  its shape is the reserved net-wide forward. Was: extensions.md §2.2.
- **Restricted option `L`, campus-only and CO-ok profiles** — the floor
  replaces them. Was: extensions.md §2.4.
- **A distinctive do-not-disturb tone** — busy-out gets busy tone. Was:
  extensions.md §2.4.
- **A tied nail as two writes, checked "before anything else", made only when
  the dest reads free; a tied nail as a ringdown** — a nail is one way and one
  write, made by the walk, the dest never read (Joel, 2026-09-26); a private
  line is a mutual nail. Was: marker.md §3; groups.md §2.1 (pre-edit);
  extensions.md §3.1 (earlier text); terminal.md §3.
- **Tied nails re-made "within 8 ms" by the scanner** — within a round of the
  walk, about 250 ms. Was: extensions.md §3, §3.1, §3.2, §3.3.
- **The nail card (a '161, a '138 and up to 88 diodes for four nails)** — the
  tied-nail word. Was: extensions.md §3.1.
- **Holding off a nail's release with a '259 a block** — not adopted; a nail
  needs the marker after each release. Was: extensions.md §6.

## Markers and the register

- **A claim is given the exchange's one register, or refused** — the register
  is held for its own caller through every digit and through `1 e b` of an
  outgoing call, exactly when the other exchange's claim arrives: 9–16 % of
  incoming network calls refused at design load, and two-way traffic past the
  knee collapsed to no calls. `top_net` now gives a claim a second register,
  the claim register, finished by its own sequencer in the mini marker. Joel,
  2026-09-27, over the cell collecting `h s` itself (a store and timer a cell)
  and a full pool (a bank a register), keeping the pool in view (`newimpl/flood-study/REPORT.md` §2–§3,
  §6.2). Was: marker.md §4.8, register.md §4, network.md §4.2.
- **A claim waits out the marker's watch** — it was refused a tick late on
  a stale `r_busy` when the watch ended, and a long watch (a chattering line)
  let the claimed trunk release first, so the refusal held a released port
  `BUSY` for good at both ends; a claim is now refused at once (2026-09-27,
  `newimpl/flood-study/REPORT.md` C01, C02). Was: marker.md §4.8, §5; network.md §3.6.
- **Cannot-complete written at the no-digit timeout whatever the hook** — on
  a caller already released it held the port `BUSY` for good; it is now
  written only while the caller reads off-hook (2026-09-27, `newimpl/flood-study/REPORT.md` C17). Was:
  marker.md §2.
- **The marker's probe as two '151, a '74 and two '164 on `PB`, reading a
  16-bit word at 128 kHz over each visit** — `PB` is gone; the probe is a '688
  and half a '74 on `SCAN`, and the word is read on demand off `/HW`. Was:
  marker.md §1, §4; mvp.md §2; protocol.md §5.
- **mvp's marker estimate by function ('393 scanner, 2 × '151, 2 × '164,
  3 × '157, 2 × '165, '163, '138, '244, diodes; 15–20 packages)** — it
  described the retired probe and scanner. Was: mvp.md §2.
- **The class marker reading every port's word at every visit** — the WALK
  (one port every 4 passes) plus reads on demand; a read every pass would hold
  the unit's reads off up to eight passes. Was: marker.md §1, §3.
- **A read of whoever lifts, for the class marker (the mini marker's way)** —
  it re-reads a non-caller every other pass, shadows the ports behind it and
  needed a 64-bit "dealt with" memory; rejected for the walk, which needs no
  memory (Joel, 2026-09-25). Was: `marker.v` history; newimpl/README.md §5.
- **The diode matrix (prefix key → class)** — the key decode is a few gates on
  the count. Was: marker.md §4; mvp.md §2; groups.md §2.5.
- **Self, empty slot, trunk, reserved → cannot-complete at once** — every
  failure of the dialled port is first hunted among the ports that answer to
  its number. Was: marker.md §2.
- **Busy → cannot-complete on the class marker, a bridge with no free leg
  included** — a busy voice line gets busy tone, 02 (Joel, 2026-09-25), and a
  bridge's own port is a busy line; the old `marker.v`'s busy-tone task was
  never called. The mini marker still gives 03 (open, `numbering.md` §6). Was: marker.md §2, §5.1
  (pre-edit); groups.md §2.2; conference.md §6; counters.md §2.
- **The class hunt noting a port and writing at the end of its pass** — the
  port is taken at the read that finds it free. Was: groups.md §2.2.
- **The hunt "from 00", 0's in fixed order; "two scans, about 17 ms"** — the
  answers-to hunt starts at 01, a read a pass, about 63 ms a round. Was:
  groups.md §2.2, §2.5; marker.md §3; features.md §4; operator.md §2.1–§2.2;
  console.md §8.2.
- **"Two writes and the marker is done"; the register freed at the connect,
  the mini marker's included** — the marker watches the caller until
  `settled` (32 ms) and holds the register in that watch, or a caller gone
  inside `T_ARM` leaves the called port `BUSY` for good. Was: mini-marker.md
  §3, §4, §7; mvp.md §3; debugger.md §2.
- **Call nails, CO lines and help points take no register** — they take it for
  the watch after their connect. Was: marker.md §2, §3; extensions.md §2.4.
- **"A register is attached in one scan"; "the marker takes a port within
  about a pass"** (the reason given for the pulse generator's RC/DIP seize
  delay, SU-1's seize wait and `REG_WAIT`) — with one register the class
  marker's walk takes up to ~252 passes, about 250 ms, and a busy register
  longer: only the dial-tone wait is safe; SU-1's 500–800 ms wait is kept
  under Open, and `REG_WAIT` is open. Was: pulse-gen.md §3; common/su-1.md §4;
  debugger.md §2.
- **The mini marker's `WAIT` of 1152 ticks, "longer than a word read"** —
  reads left the bus; the unit waits 640 ticks, one written word. Was:
  mini-marker.md §8.
- **The register as a finder for eight lines** (a 3-bit counter stepping
  `LINE`, a '151 line select, a `BUSY` bit per line kept by the marker) — the
  marker hands the register a port; its probe is a '688 on `SCAN`. Was:
  register.md intro, §4, §5.
- **Tick = `TX_OCT` ÷ 8 on half a '393** — `TICK` is `SCAN5`'s fall. Was:
  register.md §2, §4.
- **One register per line; a scanned memory register; direct control** —
  rejected alternatives to one shared register. Was: register.md §5.
- **Operator flash transfer through the register (`SRC`, `attach_src`,
  `M_CONSULT`, a held-party field), said to "exist in RTL as hooks"** — old
  tree only, not in newimpl; transfer is the console's, and phone flash is an
  Open item. Was: register.md §4, §6, §6.1; marker.md §4, §8; operator.md
  status, §5.
- **`DONE` on the ribbon; `gone` = CLR or a timeout** — no `DONE`; `gone` is
  CLR and `nodig` is separate. Was: register.md §6; common-control.md §2.1
  (`attach_src`).
- **The no-digit timer running only from seizure, or only between digits** —
  it runs whenever attached, through a digit in progress (F36). Was:
  marker.md §8; mini-marker.md §3; register.md §8 ("not modelled").
- **DTMF into the register's store; "a DTMF receiver belongs at the
  exchange"** — decided all pulse: the network hears only A, and the exchange
  reads pulses only; the DTMF measurement now serves an extended line to a CO.
  Was: register.md §7; marker.md §7; common-control.md §1;
  common/subscriber-line.md §5.
- **A register-sender for trunk calls** — the caller's own pulses cross live;
  set aside with the network's sender. Was: register.md §6.
- **The shelf switch sketch (an 8:1 selector per line on the MF8 shelf)** —
  the exchange is the fabric. Was: register.md §6.

## The PBX leaf

- **The one-board mini marker (nano-marker) for a PBX leaf, and its
  `0`/`8`/`9` row** — retired 2026-09-25, text at commit `63bafbb`; never built
  in newimpl, no BOM. Its scope stands: a one-board site knows 64 ports and
  never a code, so it is never a network node; its three-bit count cannot
  refuse 8 or 9 on the second key. Was: mini-marker.md §10; leaf-uplink.md §1.
- **The `LEAF` strap, `UPLINK_MASK` (block 1 = 10–17), `HAS_NET`, `TONE0`,
  `mini_net_site`, `make mini-leaf`** — the retired tree's straps: a strap that
  chooses behaviour is a feature, trunk ports are the cards' to say, and
  `HAS_NET` is `/NET`; how a newimpl leaf finds its uplinks is Open. Was:
  mini-marker.md §9; leaf-uplink.md §1, §3, §4, §6, §8.
- **"A mini without a word treats fitted trunks on that block as
  tone-access"** — a minimal build reads no word and takes any M · /`BUSY` as a
  caller; nothing extra is needed inbound. Was: leaf-uplink.md §3.
- **The central's group dialled as port 70** — 70 is not a channel of a
  six-channel MF8 face (slots 1–3, 5–7); the example is now `7 1`. Was:
  leaf-uplink.md §1, §2, §5.
- **"Or hunt a pilot that answers to the group"** — a tone-trunk word cannot
  also answer to a number; now Open. Was: leaf-uplink.md §2.

## The network and SS0

- **The classifier writes a hold away the moment M falls in its watch** — a
  late flood's first dial break fell there, the make was a fresh seizure, and a
  fresh cell counted `e` short: a wrong number. M must now stay down `ID`, and a
  make restarts the watch (2026-09-27, `newimpl/flood-study/REPORT.md` C05). Was: network.md §3.3.
- **A monitor cell freed only by 256 ms of break** — it outlived a seizure the
  watch wrote away, or a far port whose RC ran short, and counted the death and
  a re-seizure's make as a pulse; a cell now goes with its hold, on a break of
  `ID`, and at an age of 2 × `T_KEY` (2026-09-27, `newimpl/flood-study/REPORT.md` C03, C08). Was:
  network.md §3.4.
- **The first M seen on a held trunk is the claim** — one sample, at any time,
  so a glitch or a stale cell's early claim connected the caller to it; now M
  standing four samples after `b`, or glare inside the guard (2026-09-27, `newimpl/flood-study/REPORT.md`
  C12). Was: network.md §4.1.
- **A resolver lives until a leg claims or the incoming `BUSY` falls** — an
  incoming link held `BUSY` by `MUTE_BLK` kept it alive past its legs'
  release, and a seizure nobody dialled on kept it for ever; legs seen to
  release are dropped from it, and it ages out at 2 × `T_KEY` (2026-09-27,
  `newimpl/flood-study/REPORT.md` C08, C10). Was: network.md §3.5.
- **The origin connects at the last digit** (`h s`, or a third digit of 8
  pulses or more), the caller hearing silence until then — it held the origin's
  register about 2 s past the claim, exactly when the other exchange's claim
  arrives, so two exchanges' registers refused each other and two-way traffic
  collapsed under overload; the origin now connects at the claim, which also
  lets the owner's refusal be heard at once (2026-09-27, flood study §6.1:
  `newimpl/flood-study/REPORT.md` §3). Was: network.md §4.1.
- **The costs behind network.md §9's set-aside list** — the register-sender
  (repeating the number at 20 pps, ≈ 6–7 packages); serial characters on A
  (it needs a sender); `e` as the key (at six exchanges); one channel through
  every exchange (chosen blind, against none in a scratch run); a gateway behind
  `1 8`, `1 9` (each digit claimed in turn, `exch.py flood` 7); octets across a
  tie (≈ 3–4 packages a card); slaving the clock cards (a PLL and VCXO on each,
  ≈ 2–3 packages); a bigger slip buffer (≈ 5 packages a channel a crossing).
  Was: network.md §9.
- **"Round trip, signalling: under 0.9 s" as a carrier requirement** — it had
  no basis; the RTL's bound is the origin's 2 s claim wait from `b`, less about
  1 ms a hop each way (network.md §2). Was: network.md §1.1.
- **Monitors on each trunk block** (a pool reading that block's M; a scanner
  stepping the block's eight slots on the octet mark, two or three cells a
  block, `BUSY` read "at the last visit" through one more '151) — one pool of
  cells on the network unit, each its own probe and `pulse_rx`, attached when
  the unit reads a seizing port's word; `BUSY` is read live in M's bit-time,
  plus a bit a port. Was: monitor.md §1, §3.3, §4, §6; network.md §3.2, §4,
  §5; common-control.md §2.3, §4; fabric.md §5.2; mainboard.md §2.4;
  protocol.md §5; baseband.md §4; local-trunk.md §1, §3; mf8-unit.md §5,
  §5.8, §6.2.
- **Monitors sized and counted by the trunk block** ("two a trunk block, three
  to twenty exchanges, four to thirty-six, five beyond"; ≈ 38 packages for two
  trunk blocks, ≈ 48 / ≈ 64 at two or three a block) — figures for the retired
  per-block form; the unit's one pool must be sized again and is uncounted
  (Open). Was: monitor.md §4; network.md §3.2, §5; topology.md §2, §6;
  traffic.md §8.6; ss0.md §5, §7.
- **The claim handshake, `CLAIM_REQ` held until the unit acknowledges it** —
  the cell's request is held until the unit writes `CLAIM` and is freed at
  that write; the held level moved to `att`, unit → marker, raised only once
  the `CLAIM` word is out. Was: monitor.md §2, §3.4, §6; common-control.md
  §2.3.
- **The monitor's four-bit code jumpers, a 0 jumpered `1010`** — three-bit
  octal straps on the unit; ten pulses fold to 0, and 8, 9 and 11–15 are
  rejected. Was: monitor.md §6.
- **The marker hunting trunks** (`/HUNT_INH`, a pulled-up input a card could
  use to veto a port; the probe's M and word on the control bus's '244s; a
  jumpered port mask, `TRUNK_MASK` and `TRUNK_DIR`; a one-direction jig with
  jumpered trunk ports) — the unit hunts its own trunks by a 9 ms sweep
  reading each card's word; the card says it is a trunk, and no jumper
  anywhere says so. Was: network.md §1, §1.1, §3, §3.2; common-control.md §1,
  §2.2, §2.4, §5; marker.md §3, §4; common/common-cards.md §1.4, §9; mvp.md
  §2, §5, §7; baseband.md §2.3, §7; console.md §2.3.
- **"1 is the flood with the unit fitted, or the jumper that says so"** —
  `/NET`, grounded by the unit; no jumper. Was: protocol.md §5;
  common-control.md §2.2.
- **A glare or no-forward jumper on a trunk card ("one jumper on one card
  here"), or one per exchange** — glare is in the word; the one strap left,
  the ring (no-forward) strap, belongs to a link: one a direction on the unit
  (`STRAP_N`). Was: common-control.md §4; groups.md §1; baseband.md §4;
  ss0.md §5.
- **"A chain transit holds nothing: two latches, and forget"; resolvers only
  at a hub** — a resolver is taken for every forward, one leg or three, and
  held until a leg claims or the incoming trunk goes; a leg written after the
  caller's A has gone would otherwise stay `BUSY`. Was: network.md §3, §3.2;
  common-control.md §4.
- **"No resolver free → patch into the first direction found"** — with no
  resolver free, or the one forwarder busy, the seizure is held and watched
  and forwarded nowhere (`n_nofwd`). Was: network.md §3.2.
- **"A transit with no free onward trunk claims the call to refuse it", stated
  as the protocol** — not built; the unit only counts it, and the idea is an
  option under network.md §10. Was: network.md §3.
- **Glare "read as glare and not as a claim"** — M on a held trunk inside the
  guard is taken as the claim, counted and reported (`EV_GLARE`), and the two
  callers are joined (`tb_lfull`). Was: monitor.md §3.5.
- **The guard as a three-way jumper field and a '151** — a two-bit strap,
  128 / 256 / 512 ms (1024 unused). Was: monitor.md §3.5; network.md §3.1.
- **A hop of 7 ms, 12 at a slow marker; a hub as a hop and a third; "128 ms
  covers ten hops" as the slow case** — a hop is a 9 ms sweep, ≈ 12 ms typical
  and ≈ 22–30 ms slow; the hub's third is ≈ 1 ms. Was: network.md §3.1, §3.2,
  §4; monitor.md §3, §3.5, §7; topology.md §1, §4–§6, §10; traffic.md §8.
- **"Ready 130 ms plus the tap"; the 5 s rule "after the key"** — the origin
  sweeps before it seizes, ≈ 139 ms plus the tap, and the guard and the 5 s
  rule count from the seizure write. Was: network.md §4; monitor.md §3.
- **A pooled monitor "given a seizure within one scan of its rise, 1 ms"** —
  the cell attaches 2–3.5 ms after the rise (≈ 20 ms behind a busy
  classifier), and the guard covers it. Was: monitor.md §3.
- **The network unit's size: "twenty-odd packages, one card"; a resolver
  4 × '574 ≈ 4½; a shared comparator ≈ 3; a hub two cards** — the RTL unit
  carries its own probe, `word_rx`, queue and serialiser, a bit a port, a
  probe and `pulse_rx` a cell and the `T_ARM` watch; it is not drawn. Was:
  network.md §3.2.
- **"x carries SS0 between exchanges", read as decided** — only the remote
  alarm on x is decided (2026-09-19); SS0 stays proposed, not adopted. Was:
  ss0.md §2 (mf8/mf8-spec.md §3.5 says the same and is not rewritten).
- **SS0's 16-bit `SEIZE` of `type chan b h s`, the origin testing "if `b` is
  ours"** — the shared-`e` numbering is retired; the message is `type chan e b
  h s`, 19 data bits, 21 ms, and holds x at 1 for 20 ms, not 17. Was: ss0.md
  §4, §5, §6.
- **`e b 1` reserved as a key after the code; a conference as a number** —
  after the code a 1 is refused, and class conference is retired. Was: ss0.md
  §4.
- **SS0 on the marker** (the marker hunting onward, waiting for a busy
  transmitter, a new marker source) — all network work is the unit's; SS0
  would sit there too. Was: ss0.md §5, §7, §10.
- **SS0's transmitter "on the clock card's 1 kHz `TICK`"** — `TICK` is `SCAN5`
  and has no pin; it is the 1 ms pass edge. Was: ss0.md §3.
- **SS0's parts estimate, ≈ 25 for two trunk groups** — raised to ≈ 29 for the
  third shift register each side that `e` needs (the old doc's own
  statement). Was: ss0.md §5.
- **"Its numbering jumper is at two digits" for a standalone exchange** —
  nothing is jumpered for the numbering. Was: ss0.md §8.
- **SS0's worked call 2144 → 2355 and its millisecond timeline (187 ms
  post-dial, 28 ms a hop)** — old numbering and a marker's hunt; replaced by
  `1 2 3 5 5` as events, ≈ 35 ms a hop by arithmetic, not re-run. Was: ss0.md
  §6.

## Trunks and carriers

- **A link outage is A falling for as long as the link is down** — an outage
  of 8–256 ms was a dial pulse to every monitor and register beyond, and a
  longer one ending mid-dial a fresh seizure counted from mid-number; the card
  now holds A down both ways until the channel has been idle both ways 300 ms
  (2026-09-27, `newimpl/flood-study/REPORT.md` C07). Was: trunks.md §1, §3; network.md §2.
- **A dialled trunk port "unsettled", a reason to prefer seats 06–07** —
  cannot-complete. Was: baseband.md §4, §7.
- **The baseband card on a slot of a block ribbon; "a port circuit is fitted
  only with its card"; "a monitor is what does not swap"** — the block stack
  (port cards, J4 ribbons) and one monitor pool on the unit. Was: baseband.md
  intro, §2.1, §4.
- **The POTS trunk as "more than baseband's ≈ 4½"** — the baseband card is
  ≈ 3½ (`baseband_card.v`). Was: pots-trunk.md §7.
- **The POTS trunk's link down as settled design** — it contradicts its §2.2
  (no tones while seized); moved to Open, not resolved. Was: pots-trunk.md §5.
- **"Break shortening ≤ 2 ms a hop" as a met target** — the detector asymmetry
  and the sim give 5–10 ms; moved to Open. Was: pots-trunk.md §4.
- **The MF8 trunk card on a 2 × 32 socket needing `HCLK`, `LINE_HB` and
  `SLOT`** — a block adapter on a block's header. Was: baseband.md §2.3.
- **The local trunk's receive crossing on '174s** — two '273s. Was:
  local-trunk.md §1, §9.
- **A through RC and Schmitt on the local trunk ("as MF8"); "level in cell or
  a slower conductor" left open** — A is a clocked bit in its own cell, no RC,
  measured in `tb_ltu`. Was: local-trunk.md §10; `local_trunk.v` header
  comment.
- **Only the word held off at power-up on the local trunk** — the whole group
  (word, A, `C`, `MUTE_BLK`) is held off for ≈ 100 ms. Was: local-trunk.md §3,
  §6.
- **Seizing a local-trunk channel "from the console" at bring-up** — no console
  is built; patch by hand. Was: local-trunk.md §9.
- **The MF8 unit owning a 4.096 MHz line crystal, `LINE_HB` 2.048 MHz** — the
  adopted six-channel frame transmits in the exchange's clock; its 1.024 MHz
  source is open. Was: mf8-unit.md §5.5.
- **MF8 group F and S seats "given back as ports"; trunks on block 1 at 11–13 /
  15–17** — removed from the analysis; the MF8 adapter's seat mapping is open
  (trunks.md §4). Was: big-exchange.md intro, §1, §3, §4.
- **Eight channels on the subscriber terminal, lines h0–h7, "one word for all
  eight"** — a leftover of mf8-unit.md's eight-channel frames; the terminal is
  six channels, h1–h3 and h5–h7. Was: terminal.md §2.
- **"Monitors not fitted; class 1 is not the network unit's"** — monitors are
  one pool on the unit, and its classifier leaves line-class ports to the
  marker; class numbering "1" is retired. Was: terminal.md §2.
- **The terminal adapter's cost, "transmitter ≈ 6, receiver ≈ 10"** — it
  disagrees with mf8-trunk.md and mf8-unit.md; dropped, the cost belongs to
  trunks.md §4. Was: terminal.md §2.
- **"Slots 0 and 4 stay free or take local leftovers"** — the adapter's face
  is open under block-stack.md §6. Was: terminal.md §2.
- **The terminal's `CLAIM` gate row and slip figures (34.8 dB)** — dropped;
  network.md §8 owns slips. Was: terminal.md §2, §4.

## Features, operator, console and observers

- **"There is no BUSY highway"** — `/HB` carries every port's `BUSY` every
  pass, 1 ms. Was: features.md §4; operator.md §6; observers.md §1, §8.
- **The operator's first position carrying an answers-to-04 word** — 0 calls
  04 by number (`PILOT_0`); a plain card is the first position, and only
  further positions answer to 04. Was: operator.md §2.1; console.md §8.1.
- **A source tying `A_TX` low "because M high on an idle port is a
  seizure"** — the class marker never takes a source as a caller; the reason
  is that a listener's E is the source's M, so a falling M would release every
  listener. Was: features.md §6.
- **"One class, source, for everything that talks, the two tones included"; a
  pulled tone card served by the next source port** — tones are addresses,
  reached by number, never hunted. Was: features.md §6; observers.md §4.3.
- **A CO's ring cadence ANDed with `RING_CAD` at the operator's phone** — the
  exchange-build FXO card holds M steady, so the position rings on `RING_CAD`
  alone. Was: features.md §9.
- **"Build the console first; fabric plus console is a working manual
  board"** — the console is unbuilt and its arbitration is open; features.md
  states no bring-up order. Was: features.md §4.
- **"Lifted then patched: the register lets go with an event word and the
  patch survives"** — the class marker writes cannot-complete at the no-digit
  timeout, over the patch. Was: console.md §7.1.
- **Sink and ring source "never a call request / cannot-complete if dialled"
  in every build** — true only under the class marker. Was: console.md §5.1,
  §6.3.
- **Ring source at 75, sinks at 76–77 by convention** — collides with the test
  lines' suggested slots; left free. Was: console.md §5.2, §6.3.
- **The conference bridge's `HA_OUT`, three shunt columns, "the mainboard
  cable is forty-three signals", `FILL` and `TICK` pins** — ports drive `/HA`,
  the block number is a header jumper, and the bus is one of 32 signals. Was:
  conference.md §1.
- **The panel's busy row following the console's words** — the panel reads
  `/HB` directly, no word. Was: console.md §7.3.
- **One bicolour lamp grid** — position carries hook versus busy;
  single-colour lamps. Was: observers.md §7.
- **A flood lighting every free trunk in every direction (a whole column)** —
  the unit seizes one trunk a direction. Was: hookbusy.md §5.2; observers.md
  §4.4.
- **"Green, dark: a pass or two, normal"** — up to a round of the walk under
  the class marker. Was: hookbusy.md §5.1; observers.md §4.1.
- **The panel's stack header called `control`** — called SIG in the spec, to
  keep it apart from the exchange's control lines; the boards keep their net
  names. Was: hookbusy.md §3.3, §4.2.
- **Class signatures: a conference leg class, the operator "answers to its own
  number", the tone trunk "busy then hook"** — class conference is retired, 04
  is a plain line, and the tone trunk is left to leaf-uplink. Was:
  observers.md §4.3.
- **The debugger's twelfth lamp, `FILL_SCAN0`** — `FILL` is `SCAN0`; nothing
  to disagree. Was: debugger.md status.
- **The markers sending five event codes (o01, o02, o03, o04, o10–o13)** —
  neither marker sends any; the unit sends o04 glare and o10 no-trunk (one
  code, `DST` 00), and the rest are reserved. Was: counters.md status, §9.2,
  §9.3.
- **The "trunks let go" pattern (00, 0, 0)** — it is also abandons, the watch
  freeing a called port, and unholds: "a port written free". Was: counters.md
  §2.
- **"Calls over a trunk: `SRC` = `bbb PPP`"** — holds only for a block
  adapter; tie cards sit in any socket. Was: counters.md §2.
- **Outbound completion written by `marker.v` 562** — written by the unit.
  Was: counters.md §3.
- **"No calls in progress, no holding time: the architecture"; erlangs
  needing `PB`, a wrap detector and a probe gate** — counting `/HB` low over a
  pass gives both. Was: counters.md §4, §5; extensions.md §4.
- **The calls-in-progress display on the probe bus** (`SCAN[2:0]`, `ADVANCE`,
  `START` on a 26-way cable B; de-dup, a three-signal cross-check, a `/CON`
  freeze, a check counter; 72 visits, an 8 ms pass) — two '161 on `/HB` and
  two '4511, a 1 ms pass. Was: inprogress.md §1–§7, §9.
- **Usage by an enabled scanner pass counting a class's `BUSY` on the probe;
  "600 counts to the erlang-hour"; a peg of "all trunks busy, one a
  direction"** — the scanner has no enable and `/HB` carries no class;
  `/RING_CAD`'s period is 6.144 s (≈ 586 counts); the unit's no-trunk event is
  one code. Was: extensions.md §4.
- **The pulse generator's "both paths run on the same 1 kHz `TICK`"** —
  `TICK` is not a bus or socket signal; the card divides `TX_OCT`. Was:
  pulse-gen.md §2.

## Channel cards, the subscriber line, tones and codec

- **The line card's encoder as ½ 74HC74 + ¼ 74HC00** — a '74 has no J or K,
  and a '109 with J and /K tied is a D flip-flop; the part is ½ 74HC112, J = K
  = EN, on `LOOP_HB`'s falling edge (circuit-review §1, falstad DM-ENC). Was:
  common/channel-cards.md §2.1, §2.5; common/circuit-review.md §1.
- **A violation gap timer of 14.6 µs, one '123 half serving as both gap timer
  and 250 µs hold** — 14.6 µs is 1.25 × the classifier threshold, not the
  cell, and fires on every `1` bit; the gap is 1.25 cells, 19.5 µs, on its own
  '123 half, the hold on the other (`dm_rx.v`, stu-1.md §4). Was:
  common/channel-cards.md §2.2.
- **Line transformers "1:1, ≥ 33 mH"** (5 % droop, `L/R > 20 cells`, by
  arithmetic; on the line card, SU-D and the adapter; the erratum "33 mH
  covers the family only at 100 Ω") — L/R ≥ 2.5 cells (≥ 4 mH at 64 kbps), a
  Murata 78615/9C, measured by `subline.py xfmr` (Joel, 2026-09-26;
  mf8/mf8-spec.md §9.3). Was: common/channel-cards.md §2.1, §2.5;
  common/subscriber-line.md §7; common/su-1.md §6.2, §9;
  common/subscriber-adapter.md §2; pcb/su-1/README.md; common/stu-1.md §15.
- **`R_syl` 49.9 kΩ** — loaded by the slope resistor it gives τ_syl 1.9 ms;
  the drive is R1 51.1 kΩ / R2 2.55 MΩ (circuit-review §2.4). Was:
  common/channel-cards.md §3.2 (and mf8/mf8-spec.md §12.1, not rewritten).
- **"≈ 10 packages" for the CVSD line card** — not re-counted with the '112,
  the second '123 half and the violation capture; the parts table stands
  without a total. Was: common/channel-cards.md §2.5;
  common/subscriber-line.md §4.
- **Chance acquisition "once in 300 attempts" for a data card three seats from
  a voice card** — mf8-spec.md §5 and §13 say about once in 500. Was:
  common/channel-cards.md §4.3.
- **The riser's pitch "0.4″ (10.16 mm)" as a spec** — it does not close with
  stock parts (block-stack.md §1); now open. Was: common/cvsd-codec.md §2,
  §10.
- **The phone's clock "by hard lock or a small DPLL (line-codes.md §2.2 C)",
  no crystal** — §2.2 C is a DPLL off a local crystal, and the receiver
  (`dm_rx.v`) yields only a once-a-bit strobe, no 128 kHz half-bit for the
  encoder. Loop timing itself stands (a free-running set is not taken); the
  circuit that does it is open (subscriber-line.md §7). Was:
  common/subscriber-line.md §7; common/channel-cards.md §2.6; common/su-1.md
  §5, §9; common/sdu-1.md §1, §10; common/stu-1.md §6, §11;
  common/subscriber-adapter.md §6.
- **The phone's ring detector "Q against 0.85 / 0.70, RING when low"** — read
  literally, idle and speech (0.46–0.69 on Q) would ring; it is 0.15 / 0.30 on
  Q, i.e. 0.85 / 0.70 on /G (`subline.py`, `tb/subscriber.v`). Was:
  common/subscriber-line.md §2, §3.
- **"Where pulses are read into a register, the shortening costs nothing", as
  the whole story** — a networked caller's A is also relayed to far exchanges,
  unmeasured (newimpl/README.md §6). Was: common/subscriber-line.md §5.
- **The trunk's two-direction loop-timing question in the subscriber-line Open
  list** — an MF8 matter, and mf8/mf8-backplane.md §7 measured free-running
  crystals as inaudible. Was: common/subscriber-line.md §7.
- **`/RING_CAD` made by the ROM tone card** (a NOR of the ring gate, a 4.096 s
  double pulse, "locked by construction", the clock card keeping a pull-down)
  — the clock card drives `/RING_CAD`, 2.048 s low / 4.096 s high
  (`clock_card.v`, mainboard.md §3.4). Was: common/tone-plan.md §4.3, §4.4
  (rear pin 4), §5.2 (the analog card's `/RING_CAD` out of the rear).
- **The analog tone card's busy mask `1111 0000 …` and cannot-complete
  `1100 1100 …`** — one stage slower than the ROM taps (cannot-complete landed
  on busy's cadence); now `1100 …` and `1010 …` at the 256 ms step. Was:
  common/tone-plan.md §5.2.
- **The analog card's cadence counter as one '4040 with a Q13 tap** — a '4040
  has twelve stages; the 256 ms step and its four-bit count need a '4040 and a
  '393, as on the ROM card. Was: common/tone-plan.md §5.1.
- **The tone card in the MF8 gateway slot** — a gateway card reaches the
  exchange, not its own shelf's phones; it is a plain channel card plus a tone
  bus (common/tones.md). Was: common/common-cards.md §6.

## Subscriber equipment

- **LOF on the subscriber line; "the LED stutters through LOF"** — the line
  has no frame. Was: common/su-1.md §5, §9.
- **"P loads 16 so a register can count keys 11–16"** — the register
  saturates at 15 (`pulse_rx.v`), so I and P read alike; SU-K still sends 16.
  Was: common/su-1.md §4, §6.5.
- **"SU-K is fitted in all three populations"** — sdu-1's headless and RAW64
  data sets leave it off; SU-D pulls `BREAK`/`OFF_NORM` low with K unplugged.
  Was: pcb/su-1/README.md; common/su-1.md §6.4.
- **S pin 14 named `MUTE`** — renamed `OFF_NORM`, what it carries; `MUTE` is
  the channel socket's trunk-unlocked pin a11. Was: common/su-1.md §6.1;
  common/sdu-1.md §5–§7.
- **SU-1's "why the dial is its own board" (kept as the reason, cut from
  the spec)** — the 4×4 pad sets its own outline
  (~60 × 60 mm), is panel furniture placed by the bezel not the spacers, and
  cuts at the same seam as STU-1's ST-K. Was: common/su-1.md §6 "Why the dial
  is its own board".
- **A `sounder` on the dual-mode riser; "hook and ring detectors" on SU-D** —
  SU-1 has no sounder (the loudspeaker rings) and no density hook detector
  (the hook is the cradle). Was: common/sdu-1.md intro, §2.
- **A RAW64 nail "with `/ANS` low, hook held off by `DTR`/nail"** — the CVSD
  line card has no `/ANS` strap and reads hook from the stream alone; a
  `1100`-like payload reads on-hook, the port releases, and the walk
  re-nails. Was: common/sdu-1.md §3.6.
- **A framed single-channel carrier (MF1) for SDU-1** — false lock on
  transparent data without a guard; signalling stays in `1100` and insert-1.
  Was: common/sdu-1.md status.
- **Denser SDU-1 payload codes (4B/5B; 6B/8B at 48 kb/s; 3B/5B at
  38.4 kb/s)** — 4B/5B enters the hook hold band, the others need maps, and
  insert-1 wins on gate count; insert-1-before (`0`→`10`) is equivalent and not
  used. Was: common/sdu-1.md §3.1, §3.2.
- **A shift-register "equals `1100`" matcher** — it needs bit phase and fails
  under noise; lag-2 XOR is the matched filter (subscriber-line.md §3). Was:
  common/sdu-1.md §4.
- **STU-1's "≥ 330 mH" bridging transformers** — derived only from the
  retired 20-cell droop rule; under L/R ≥ 2.5 cells two 78615/9C in parallel
  (5 mH) still meet 4 mH, and STU-1 uses the §9.3 part. Was: common/stu-1.md
  §2.2, §4.3, §12, §16.
- **STU-1's view of the exchange: "no slot-ID pins", "word and `BUSY` reach
  only the marker over `PB[1:0]`", "two masters unarbitrated"** — the fold:
  `/HB` and `/HW` read with `/WS`, POS and block-number jumpers, `/UREQ`; STU-1
  still cannot see them from the pair. Was: common/stu-1.md §14.
- **STU-1 header T pin 17 named `LINE_HB`** — renamed `DN_HB`; `LINE_HB` was
  the bus signal dropped 2026-09-25. Was: common/stu-1.md §3.1.
- **STU-1's clock tree off a "recovered 128 kHz `LINE_HB`", ÷ 64 = 1 kHz,
  ÷ 65536 = 0.9766 Hz** — the receiver gives a 64 kHz strobe, and from 128 kHz
  those taps would be 2 kHz and 1.95 Hz; the taps hang off the 64 kHz node.
  Was: common/stu-1.md §6.
- **ST-K as "pulse-gen §5 unchanged, `TX_OCT` ÷ 8 to `TICK`"** — `TICK`
  arrives at 1 kHz on header T. Was: common/stu-1.md §7.2.
- **STU-1's rejected designs** — transmitting while bridged (two drivers on
  one pair), taking phantom power (a set that dies on a dead pair), keying the
  carrier off to trace (no downstream is no clock), a channel-socket pigtail
  (connector family unchosen), a framer and LOCK lamp (the line has no
  frame), DTMF (no receiver on the line). Was: common/stu-1.md §2.3.
- **A lag-1 activity detector for STU-1** — speech runs of 44–81 bits pull its
  density below the operate, so it would drop out on ordinary speech and still
  not split idle from silence. Was: common/stu-1.md §5.3.

## Benches and models of the retired tree

- **`make groups`, `make priority`, `make word` (options), `make mini-net`,
  `mini-load`, `mini-leaf`, `nano`** — retired-tree benches; newimpl's are
  `tb_max` (options, answers-to, `PWAIT`, nails) and `tb_word` (transport).
  Was: groups.md status, §9; extensions.md §2.4.1, §6; mini-marker.md §7, §10.
- **`make regs`, the retired tree's register-pool bench** — newimpl has one
  register; its result is kept as a note in register.md §4. Was: marker.md
  §6.
- **`make console`, `make console-naive`, `make iv-console` and their figures
  (87 checks, the naive `/CON` losing calls)** — retired tree; the latch-level
  results stay as "benched on the retired tree". Was: console.md status,
  §2.1, §10.
- **The old panel bench `tb_panel` (57 checks)** — retired tree. Was:
  hookbusy.md §7.
- **`stats.v`, `tb_stats`, `tb_stress`, `make stress`, `make
  stress-overload`** — retired tree only. Was: counters.md status, §7, §9.4.
- **SU-1's RTL (`verilog/rtl/su1.v`, `su_dial.v`), `make su1`, and `make
  pulse_gen` with a `net_site` call** — retired with `verilog/` (now
  `old/verilog/`); newimpl models only the set's line behaviour
  (`tb/subscriber.v`, bench `line`), with no dial, face or LED. Was:
  common/su-1.md status, §8; common/stu-1.md §6, §7.2; pulse-gen.md status,
  §6.

## Documents and claims

- **Source and tone trunk "not in the marker", "not measured"** — both are
  decoded in `word_dec.v`, and a source is benched in `tb_max`. Was:
  features.md §9.
- **Eight payload channels on a 16-bit MF8 line "adopted", "done in the live
  tree", "the working tree until a choice is frozen"** — not taken; six
  channels on the 8-bit frame. Was: mf8-unit.md §4.2, §5.2½–§9.
- **"`net` does not exist"** — `exch.py net` exists. Was: ss0.md status.
- **`tones.log` as the record of the plans, warble and seam** — the committed
  log holds only the IMAGE section; those figures are now marked "not
  logged". Was: common/tone-plan.md status, §2.
- **Plane SNR "best / worst" and crest factor per image** — not in the
  committed log; replaced by the logged image SNR (36.4 / 34.2 dB). Was:
  common/tone-plan.md §1.
- **rtl.md as a findings log** — its rules are folded into their owners
  (README.md §1; register.md §1, §5; marker.md §1; numbering.md §1;
  network.md); its findings "steering the probe costs a visit" and "a hop is
  two scans, 17 ms" are obsolete with the fold and the 9 ms sweep. Was:
  rtl.md §2, §3.
- **port-card.md, the stub** — superseded by block-stack.md §2.2 and
  fabric.md §5. Was: port-card.md.
- **circuit-review.md as a document** — its findings are folded: §1 into
  channel-cards.md §2.4, §2 and §4 into cvsd-codec.md §3. The edits it implies
  for mf8-spec.md §9.2 (the '112), §9.4 and §9.7 are NOT yet made there
  (`README.md` §5); §1's rising-edge alternative table and
  §2.2–§2.3's scratch tables are dropped (the tolerance is mf8-spec.md
  §12.1's). Was: common/circuit-review.md.
- **cvsd-codec.md's "Documents and models" table and its before/after
  comparison table** — the references moved to the status box; the
  comparison is history. Was: common/cvsd-codec.md §1, §9.
- **common-cards.md §8's table of edits owed to other documents** — one-time
  edits, done or superseded. Was: common/common-cards.md §8.
- **counters-rev2.md** — an empty file; deleted. Was: counters-rev2.md.
- **The register-is-not-a-line argument in features.md** — moved to
  register.md. Was: features.md §1.
- **"Who drives `RBT`" history (mainboard.md §2.1 vs marker.md §5 vs
  fabric.md §4)** — history, dropped. Was: common/tone-card.md §8.
- **"Why a fourth tone" (the older single cannot-complete class)** — history;
  02 vs 03 is numbering.md's. Was: common/tone-plan.md §1.
- **The per-pin tables of the line, FXS/FXO and tone cards** — the socket
  matrix is common-cards.md's; each card keeps only what its circuit does with
  a pin. Was: common/channel-cards.md §2.4, §3.7; common/tone-card.md §2.
- **The earlier A-path figure (78 of 78 pulses at 32 kHz)** — history. Was:
  common/channel-cards.md §5.
- **leaf-uplink.md's "What this is not" list and its index** — dropped; the
  terminal distinction is kept in one clause. Was: leaf-uplink.md §6, §9.
- **STU-1's bring-up list and costing history** — build notes, dropped until
  a `pcb/stu-1/` exists. Was: common/stu-1.md §12, §13.
