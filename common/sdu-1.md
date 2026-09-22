# SDU-1 — mk1 subscriber data unit

A freestanding **synchronous data NT** on the two-pair subscriber line of
`subscriber-line.md`. It does **not** touch the pair: the **subscriber voice
unit** (SU-1’s SU-D, or an equivalent line base) owns differential Manchester,
phantom power, `1100` / zeros signalling, and the hook and ring detectors.
SDU-1 is a **pass-through riser** on mezzanine header **S** in place of the
CVSD audio board (SU-A). The exchange still sees an ordinary CVSD subscriber
line card (`channel-cards.md` §2).

> **Status: proposed.** The insert-1 alphabet and the hook/ring margins are
> checked in analysis against `subscriber-line.md` §3’s detectors (below).
> Nothing has been on a bench. Outline and S reuse are locked for PCB
> provisioning; schematic and copper are not drawn.

```
  DTE ── RS-422 ──► SDU-1 (payload code + DTE)     ← this document
                       ║ S  (board-to-board)
  Autovon pad ───────► SU-D (line / dial / power)   ← su-1.md (voice unit base)
                       ║
                  two pairs + 48 V phantom
                       ║
                  CVSD line card ──► exchange
```

SU-A (codec / handset) is **not fitted** when SDU-1 is fitted. One riser at a
time on S.

---

## 1. What it is

| | |
|---|---|
| **Line** | none on this board — SU-D’s two pairs, 64 kbps differential Manchester |
| **Payload** | **32 kbps** synchronous into the 64 kbps bit plug (insert-1, §3) |
| **Role** | encode / decode at the NT; DTE face; seize / dial via SU-D’s existing hook and pulse path |
| **Clocking** | slave to SU-D’s `TX_CLK` / `RX_CLK` on S (mk1 free-run crystal on SU-D stands) |
| **Not** | a shelf data card (`channel-cards.md` §4); not a DM PHY; not a ROM line code |

Declared silk rate: **32 kb/s**. The wire remains a 64 kb/s CVSD-shaped plug.

---

## 2. Split with the voice unit

| function | board | note |
|---|---|---|
| Differential Manchester TX/RX | **SU-D** | `mf8-spec.md` §9.2 / §9.4 |
| Phantom 48 V → +5 / ±12 | **SU-D** | feeds S |
| On-hook / dial-break pattern `1100` | **SU-D** | mux ahead of the line encoder |
| Hook detector (`Q ⊕ Q[n−2]`) | **SU-D** / line card | `subscriber-line.md` §3 — not duplicated here |
| Ring detector (ones density / zeros) | **SU-D** | arms `RING` on S |
| Dial pad + pulse sequencer | **SU-D** | same Autovon → pulses as `su-1.md` §4 |
| Insert-1 encode / decode | **SDU-1** | §3 |
| DTE (RS-422, clocks, control) | **SDU-1** | §5 |
| CVSD codec / handset / sounder | **absent** | SU-A not stacked |

SU-D’s interface law is unchanged (`su-1.md` §2):

```
TX   = ON-HOOK or dial break  ?  1100  :  BIT_ENC     ← BIT_ENC from SDU-1
BIT_DEC = RING ? 1010 : Q                            ← into SDU-1 decode
ring  = RING · ON-HOOK                               ← RI to DTE; no piezo required
```

SDU-1 never drives the pair and never generates `1100`. When the set is
on-hook, SU-D substitutes `1100` and SDU-1’s encoder is don’t-care (hold mark
or high-Z on `BIT_ENC` per §6).

---

## 3. Payload line code — insert-1

### 3.1 Map

Each payload bit becomes two bits on the 64 kb/s plug:

| payload | line dibit | stream |
|---|---|---|
| `0` | `01` | … |
| `1` | `11` | … |

Equivalently: **emit the data bit, then a constant `1`** (insert-1 after).
The alternate polarity insert-1-before (`0→10`, `1→11`) is electrically
equivalent for the detectors; mk1 standardises **after**.

Rate: **32 kb/s** payload on a **64 kb/s** bit clock.

### 3.2 Why this code

It is the smallest concatenation-safe alphabet under the exchange hook metric:

| property | insert-1 | classic Manchester `0→01`/`1→10` |
|---|---|---|
| Worst sustained `Q ⊕ Q[n−2]` (max-mean-cycle) | **0.50** | **1.00** (unsafe) |
| Ones density under any payload | **[0.50, 1.00]** | mid, but XOR2 fails |
| Literal `1100` in the coded stream | **never** | can appear in spirit via XOR2≡1 |
| Logic | mux + 1-bit phase | same size, wrong alphabet |

Speech CVSD stays ≤ ~0.53 on XOR2; `1100` sits at 1.00; the hook comparator
is 0.85 / 0.70 (`subscriber-line.md` §3). Insert-1’s ceiling **0.50** cannot
false **on-hook**. Ones never fall below **0.50**, so the phone-side ring
detector (all-zeros → ones RC → 0) cannot false **ring** on payload alone.

FDDI 4B/5B and other dense tables were rejected for this plant: they enter the
hook hold band. 6B/8B @ 48 kb/s and 3B/5B @ 38.4 kb/s work but need maps;
insert-1 is the mk1 choice for gate count.

### 3.3 Encode (NT → line)

```
phase 0 (first half):   BIT_ENC = TXD_bit
phase 1 (second half):  BIT_ENC = 1
```

`phase` toggles on `TX_CLK` (64 kHz). Payload advances on phase 0 only →
32 kHz `TXC` to the DTE. About **½ 74HC74 + ¼ 74HC157** (or discrete mux).

### 3.4 Decode (line → NT) and word sync

Downstream bits arrive on `BIT_DEC` with `RX_CLK`. Insert-1 is a fixed template
`x1 x1 x1 …`: the **second** half of every dibit is `1`.

**Hunt:** shift until the sampled “mark” half reads `1` for N consecutive
dibits (mk1: N = 16). **Lock:** take the other half as data. **Loss:** mark
half errors accumulate → return to hunt; force `RXD` to mark (`1`) while
hunting.

No ROM. Framer is a 1-bit phase + counter + compare — a few MSI gates, or one
GAL with the encode.

### 3.5 Intentional signalling stays outside the map

| pattern | owner | SDU-1 |
|---|---|---|
| `1100` on-hook / dial break | SU-D TX mux | not generated; encoder bypassed |
| all-zeros ringing (downstream) | exchange → SU-D | `RING` high; `BIT_DEC` already forced `1010` on SU-D before S |
| `1010` idle fill | SU-D / bus | seen only when SU-D substitutes |

A stuck insert-1 encoder cannot synthesise `1100` or long zeros. A stuck
**mux** on SU-D that forces zeros still rings — that fault is on the voice
unit, not the code.

---

## 4. Detecting `1100` (reference — on the voice unit / line card)

SDU-1 does not implement a hook detector. The plant detector, for any reader
of this spec, is:

```
X = Q ⊕ Q[n−2]          ½ 74HC74 + ¼ 74HC86
G = X + violation-hold + /carrier
G ──[ RC, τ = 4 ms ]──[ LM339, 0.85 / 0.70 ]──→ ON_HOOK
```

Do **not** use a shift-register “equals `1100`” matcher: it needs bit phase and
fails under noise. Lag-2 XOR is the matched filter for period-4 `1100` at any
alignment (`subscriber-line.md` §3, `channel-cards.md` §2.2). The violation
and `/carrier` terms are mandatory so a dead pair reads on-hook.

Insert-1 is designed so that, while SU-D is passing `BIT_ENC` through,
sustained X stays ≤ 0.50 and the comparator cannot acquire on-hook on data.

---

## 5. DTE face

Synchronous DCE, **32 kb/s**, two clocks (same idea as the shelf data card,
halved rate):

| signal | dir | |
|---|---|---|
| `TXD` | in | payload; sampled on `TXC` |
| `RXD` | out | payload; changes on `RXC`; mark while hunt or `MUTE` |
| `TXC` | out | 32 kHz — `TX_CLK` ÷ 2 (phase-0 edges) |
| `RXC` | out | 32 kHz — `RX_CLK` ÷ 2 when locked |
| `DTR` | in | seize: DTR true → off-hook request to SU-D (§6) |
| `DSR` | out | from SU-D carrier / not `MUTE` / decode lock (mk1: AND of the three) |
| `RI` | out | `RING` from S (cadenced zeros on the line) |
| `RTS`/`CTS` | — | strapped or looped in mk1; no flow control in the code |

Electrical: **RS-422** differential on a rear/DTE connector (shelf data card
practice). Logic on the board is HC at +5.

No octet alignment in mk1: the subscriber plug has no superframe. Byte packing
is the DTE’s problem, or a later strap.

---

## 6. Seize, dial, and S control

| SU-D input | SDU-1 drives | |
|---|---|---|
| hook / seize | `DTR` → off-hook when true (wired to the cradle sense net or an OR with the physical hook) | data call looks like a lifted handset |
| dial | Autovon pad on SU-D, unchanged | breaks still force `1100` on the line |
| `MUTE` | in from SU-D during pulse off-normal | encoder may free-run; line is `1100` anyway |
| `RING` | in | → `RI`; decoder already gets `1010` on `BIT_DEC` |
| `BIT_ENC` | out | insert-1 stream when off-hook and not muted |
| `BIT_DEC` | in | insert-1 decode |
| `TX_CLK` / `RX_CLK` | in | 64 kHz |

Mk1 **reuses the pad on SU-D** for dialling. A headless data-only face (DTR
seize, no pad) is a population option: leave the keypad unstuffed; dial from
the far application only if the call plan allows — the flood still wants pulse
on A for register digits (`network.md` §3).

---

## 7. Mezzanine header **S**

Same keyed **2×12** 0.1″ map as `su-1.md` §5.1. SDU-1 is the riser mate.

| pin | name | SDU-1 use |
|---|---|---|
| 3–5 | `+5` / `±12` | +5 for logic; ±12 unused in mk1 (reserve) |
| 7–8 | `TX_CLK` / `RX_CLK` | 64 kHz bit clocks |
| 9 | `BIT_ENC` | insert-1 TX to SU-D mux |
| 10 | `BIT_DEC` | from SU-D (post-RING gate) |
| 14 | `MUTE` | dial mute / encoder don’t-care |
| 15 | `RING` | → `RI` |
| 16 | `/OE` | optional |
| 11–12, 17–20 | audio / codec test | **open / NC** on SDU-1 |

Pins that only exist for SU-A stay no-connects. Do not drive `BIT_ENC` against
SU-D’s `1100` mux output; SU-D selects.

---

## 8. Parts (rough)

| block | parts |
|---|---|
| Insert-1 encode | ½ 74HC74 (phase), ¼ 74HC157 or OR/AND |
| Insert-1 decode + hunt/lock | ~2–3 HC MSI (phase, counter, compare) or 1× GAL16V8 |
| Clock divide | ½ 74HC74 → 32 kHz `TXC`/`RXC` |
| DTE | RS-422 tx/rx (75176 / 26LS31 family), connector |
| Control | few gates: DTR→seize, `DSR`/`RI` buffers |
| Header | **S** mate; DTE connector |

**≈ 6–10 packages** plus line drivers — well under a CVSD SU-A. No ROM. No
codec analog.

---

## 9. Against the exchange

The far end is a **CVSD subscriber line card**, not a shelf data card. Hook and
dial are the line’s `1100` detector and the register on A. Payload bits are
opaque channel bits once off-hook; a matching SDU-1 (or any insert-1 peer) must
sit on the far subscriber line, or an exchange-side adapter must terminate
insert-1 into a 32 kb/s DTE.

Connecting this NT through the fabric to a **64 kb/s shelf data card** without
an insert-1 peer is a rate/code mismatch — label the port.

---

## 10. Not measured / deferred

- Bench confirm of XOR2 / ones RC with real insert-1 vs `subline.py` thresholds.
- Loop-timing on SU-D (open, same as `su-1.md` §7).
- GAL vs MSI for the framer; exact hunt constant N.
- Async DTE (UART ≤ 32 kBaud into a bit packer) as a later strap.
- Exchange-side insert-1 tail for calls into shelf data ports.
- PCB: outline 100 × 100 mm riser assumed; not drawn.

---

## 11. Related

| doc | |
|---|---|
| `su-1.md` | voice unit; SU-D base and S pin map this riser reuses |
| `subscriber-line.md` | pair law, `1100` / zeros, detectors |
| `channel-cards.md` §2 | CVSD line card (exchange end of this call) |
| `channel-cards.md` §4 | shelf 64 kb/s data card — different socket, full rate, no insert-1 |
