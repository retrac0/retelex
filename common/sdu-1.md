# SDU-1 — the subscriber data riser

SDU-1 is SU-1's data riser: it codes a DTE's bits into the subscriber line's
64 kb/s biphase stream.

> **Proposed.** Nothing drawn, nothing on a bench. Insert-1 is checked by
> arithmetic against `subscriber-line.md` §3's detector thresholds.

## 1. What it is

SDU-1 sits on header S (`su-1.md` §6) in place of SU-A, or is the DATA half of
the dual-mode riser (`su-1.md` §7); SU-D keeps the pair, the phantom, `1100` and
the ring detector. It sends **insert-1** at 32 kb/s on switched calls, the
default (§3.1), or **RAW64**, 64 kb/s transparent, on a nailed circuit, by a
recessed jumper (§3.2). It runs on S's `TX_CLK` and `RX_CLK` (`su-1.md` §5).
About 6–10 HC packages and an RS-422 pair, by arithmetic.

## 2. The DTE face and header S

Synchronous DCE on RS-422 (75176 / 26LS31 family). No octet alignment: the line
has no frame, so byte packing is the DTE's.

| signal | insert-1 | RAW64 |
|---|---|---|
| `TXD`, `RXD` | payload; `RXD` mark while hunting or `OFF_NORM` | payload; mark while `OFF_NORM` |
| `TXC`, `RXC` | 32 kHz; `RXC` once locked | 64 kHz |
| `DTR` in | seize, ORed with the cradle; then dial on SU-K as a phone does | held |
| `DSR` out | carrier · /`OFF_NORM` · lock | carrier · /`OFF_NORM` |
| `RI` out, `RTS`/`CTS` | `RING` from S; looped | as insert-1 |

On S it uses 3 (+5 V), 7–10, 14 (`OFF_NORM`), 15 (`RING`) and 16 (`/OE`); ±12 V
is unused and 11–12, 17–20 are no-connects. SU-D's mux selects; SDU-1 never
drives `BIT_ENC` against it.

## 3. Payload

### 3.1 Insert-1 — switched calls

Each payload bit is sent as itself followed by a constant `1`: `0` → `01`, `1`
→ `11`, so `TXC` is `TX_CLK` ÷ 2 (½ '74 and a gate). **It cannot signal by
accident**: with every second bit `1`, `Q ⊕ Q[n−2]` never exceeds 0.50, below
the exchange's on-hook release; ones density never falls below 0.50, so it
cannot ring the far set; and `1100` never appears. Transparent 64 kb/s can do
all three.

Decode hunts for the phase whose bit reads `1` for 16 pairs running and takes
the other as data; errors in the `1`s return it to the hunt, with `RXD` held at
mark meanwhile. A phase flip-flop, a counter and a compare, or one GAL16V8 with
the encoder.

### 3.2 RAW64 — nailed circuits

The jumper puts `TXD` onto `BIT_ENC` and `BIT_DEC` onto `RXD` bit for bit, on
`TX_CLK` and `RX_CLK`. The far end must be RAW64 too: another SDU-1, or a
64 kb/s data card at the exchange (`channel-cards.md` §4). Nothing negotiates; a
mis-strap is garbage, an endless hunt or hook chatter.

The circuit is a **mutual nail** (`card-word.md` §6.2): each end's line card has
its word parts fitted (`channel-cards.md` §2.5) and sends a tied-nail word
naming the other, and the class marker makes it. The DTE holds `DTR`, so SU-D
stays off-hook and never sends `1100`. **The line card still reads hook from the
stream alone**: a payload that dwells on `1100`-like fill (`0x33`, `0xCC`) reads
on-hook, the port releases 256 ms later (`fabric.md` §5), and the walk makes the
nail again up to a round after (`marker.md` §4.2).

## 4. Against the exchange

The far end of a switched call must be a matching insert-1 set; a 64 kb/s data
card or a voice port is a mismatch that nothing flags. **Switched data needs the
line's word to leave `D` clear**: a `D` line is neither a caller nor called
(`card-word.md` §4). Letting data call data is `card-word.md` §8's open item.

## 5. Open

- **`/ANS` on the CVSD line card** is open with no strap (`channel-cards.md`
  §6), so a RAW64 end whose DTE drops `DTR` while the far end holds it is rung
  in cadence and `RI` follows the cadence, where `card-word.md` §6.2's data
  circuit has `/ANS` low. A strap on the card, or accept the cadence.
- **RAW64 is slip-free on the line because the set is loop-timed**
  (`subscriber-line.md` §1), by a circuit still open there (§7). Between
  exchanges it slips as any data does (`network.md` §8); insert-1 re-hunts
  after a slip.
- **`DSR`'s carrier term has no pin on S**: a spare pin, or `RX_CLK` activity.
- **Not measured:** insert-1 on a real detector, the hunt constant, RAW64 on a
  nail. **Not built:** an async DTE, an insert-1 tail into a 64 kb/s data card.
