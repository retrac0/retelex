# SDU-1 — mk1 subscriber data unit

A freestanding **synchronous data NT** on the two-pair subscriber line of
`subscriber-line.md`. The line is **raw differential Manchester (biphase)** at
64 kb/s — no MF1/MF2/MF8 frame on the pair. SDU-1 does **not** touch the
copper: the **subscriber voice unit** (SU-1’s SU-D, or an equivalent line base)
owns the DM PHY, phantom power, `1100` / zeros signalling, and the hook and
ring detectors. SDU-1 is a **pass-through riser** on mezzanine header **S**:
either alone in place of the CVSD audio board (SU-A), or as the **DATA** half
of a dual-mode riser with a panel switch (`su-1.md` §6). The exchange still
sees an ordinary CVSD subscriber line card (`channel-cards.md` §2).

> **Status: proposed.** The insert-1 alphabet and the hook/ring margins are
> checked in analysis against `subscriber-line.md` §3’s detectors (below).
> Nothing has been on a bench. Outline and S reuse are locked for PCB
> provisioning; schematic and copper are not drawn. A framed single-channel
> carrier (MF1) was considered and **not taken** — false lock without a guard
> on transparent data; signalling stays in `1100` / insert-1 instead.

```
  DTE ── RS-422 ──► SDU-1 (payload + DTE)           ← this document
                       ║ S  (board-to-board)
                     SU-D (line / power / 1100)     ← su-1.md (biphase + 1100)
                       ║ K
  Autovon pad ───────► SU-K (dial)                  ← su-1.md §6.5
                     SU-D
                       ║
                  two pairs + 48 V phantom
                       ║
                  CVSD line card ──► exchange
```

**Populations.** Data-only: SDU-1 on S, SU-A not fitted. Dual-mode: both
engines on one riser; **VOICE / DATA** selects which drives `BIT_ENC`
(`su-1.md` §6). Do not stack SU-A and SDU-1 as two layers on S.

---

## 1. What it is

| | |
|---|---|
| **Line** | none on this board — SU-D’s two pairs, **raw** 64 kbps differential Manchester |
| **Payload (switched)** | **32 kbps** insert-1 into the 64 kbps plug (§3) — default |
| **Payload (nailed)** | **64 kbps raw** strap (§3.6) — fixed/nailed lines only |
| **Role** | encode / decode at the NT; DTE face; seize via SU-D and dial via SU-K when switched |
| **Clocking** | slave to SU-D’s `TX_CLK` / `RX_CLK` on S — both from **recovered** downstream (`su-1.md` §5); no crystal on the set |
| **Not** | a shelf data card (`channel-cards.md` §4); not a DM PHY; not a framed carrier |

Silk: **32 kb/s** (switched). The **RAW64** jumper is unmarked or recessed —
nailed use only.

---

## 2. Split with the voice unit

| function | board | note |
|---|---|---|
| Differential Manchester TX/RX | **SU-D** | `mf8-spec.md` §9.2 / §9.4 — biphase on the pair |
| Phantom 48 V → +5 / ±12 | **SU-D** | feeds S |
| On-hook / dial-break pattern `1100` | **SU-D** | mux ahead of the line encoder |
| Hook detect | **line card** (`Q ⊕ Q[n−2]`); on the set it is SU-D's cradle switch (**X = Q**) | `subscriber-line.md` §3 — not duplicated here |
| Ring detector (ones density / zeros) | **SU-D** | arms `RING` on S |
| Dial pad + pulse sequencer | **SU-K** | its own board on ribbon **K** (`su-1.md` §6.5); `BREAK` and `OFF_NORM` into SU-D |
| Insert-1 / raw payload | **SDU-1** | §3 |
| DTE (RS-422, clocks, control) | **SDU-1** | §5 |
| CVSD codec / handset / sounder | **absent** on data-only; present on dual-mode (`su-1.md` §7) | switch steers `BIT_*`; base speaker UI on SU-D stays |

SU-D’s interface law is unchanged (`su-1.md` §2):

```
TX   = ON-HOOK or dial break  ?  1100  :  BIT_ENC     ← from SDU-1, or dual-mode switch
BIT_DEC = RING ? 1010 : Q                            ← into SDU-1 decode (when DATA)
ring  = RING · ON-HOOK                               ← RI to DTE; no piezo required
```

SDU-1 never drives the pair and never generates `1100`. When the set is
on-hook, SU-D substitutes `1100` and SDU-1’s encoder is don’t-care (hold mark
or high-Z on `BIT_ENC` per §6). On dual-mode **VOICE**, the data path is
deselected the same way — don’t-care on its `BIT_ENC` leg.

---

## 3. Payload — insert-1 (switched) and raw 64 (nailed)

The pair carries a **raw** 64 kb/s biphase bit plug. There is no frame header
on the subscriber line. Call signalling for a **switched** data set is the same
`1100` / zeros law as a phone. A transparent 64 kb/s payload can synthesise
`1100` and false the hook detector, so **switched service is 32 kb/s insert-1**
only. **Nailed** (fixed) circuits may strap **RAW64** and run transparent
64 kb/s when dial/hook-on-the-wire is not required.

### 3.1 Insert-1 map (default)

Each payload bit becomes two bits on the 64 kb/s plug:

| payload | line dibit | stream |
|---|---|---|
| `0` | `01` | … |
| `1` | `11` | … |

Equivalently: **emit the data bit, then a constant `1`** (insert-1 after).
The alternate polarity insert-1-before (`0→10`, `1→11`) is electrically
equivalent for the detectors; mk1 standardises **after**.

Rate: **32 kb/s** payload on a **64 kb/s** bit clock.

### 3.2 Why insert-1 on switched lines

It is the smallest concatenation-safe alphabet under the exchange hook metric:

| property | insert-1 | classic Manchester `0→01`/`1→10` | raw 64 kb/s |
|---|---|---|---|
| Worst sustained `Q ⊕ Q[n−2]` | **0.50** | **1.00** (unsafe) | **1.00** if data holds `1100` |
| Ones density under any payload | **[0.50, 1.00]** | mid, XOR2 fails | full range |
| Literal `1100` in the coded stream | **never** | can via XOR2≡1 | **yes** |
| Dial / seize on `1100` | safe | unsafe | **unsafe** |

Speech CVSD stays ≤ ~0.53 on XOR2; `1100` sits at 1.00; the hook comparator
is 0.85 / 0.70 (`subscriber-line.md` §3). Insert-1’s ceiling **0.50** cannot
false **on-hook**. Ones never fall below **0.50**, so the phone-side ring
detector cannot false **ring** on payload alone.

FDDI 4B/5B and other dense tables were rejected for this plant: they enter the
hook hold band. 6B/8B @ 48 kb/s and 3B/5B @ 38.4 kb/s work but need maps;
insert-1 is the mk1 choice for gate count.

### 3.3 Encode (NT → line), insert-1

```
phase 0 (first half):   BIT_ENC = TXD_bit
phase 1 (second half):  BIT_ENC = 1
```

`phase` toggles on `TX_CLK` (64 kHz). Payload advances on phase 0 only →
32 kHz `TXC` to the DTE. About **½ 74HC74 + ¼ 74HC157** (or discrete mux).

### 3.4 Decode (line → NT) and word sync, insert-1

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
| `1100` on-hook / dial break | SU-D TX mux (`BREAK` from SU-K) | not generated; encoder bypassed |
| all-zeros ringing (downstream) | exchange → SU-D | `RING` high; `BIT_DEC` already forced `1010` on SU-D before S |
| `1010` idle fill | SU-D / bus | seen only when SU-D substitutes |

A stuck insert-1 encoder cannot synthesise `1100` or long zeros. A stuck
**mux** on SU-D that forces zeros still rings — that fault is on the voice
unit, not the code.

### 3.6 RAW64 — nailed / fixed lines only

A board jumper (or recessed switch) **RAW64** bypasses insert-1:

```
BIT_ENC = TXD          sampled on TX_CLK (64 kHz)
BIT_DEC → RXD          no hunt; 1:1
TXC = TX_CLK           RXC = RX_CLK
```

| | |
|---|---|
| **When** | both ends strapped RAW64 on a **nailed** circuit (`extensions.md` §3 — `/ANS` low, `DSR` follows `DTR`, no dial, no ring cadence) |
| **Why allowed** | no register needs `1100` breaks; hook may be held off by `DTR` / nail. Detector falsing is an operational problem, not a dialing one |
| **When forbidden** | any dialled / hunted / flood-originated call — leave RAW64 **open** (insert-1) |
| **Peer** | far SDU-1 also RAW64, or an exchange-side 64 kb/s transparent tail. A 32 kb/s insert-1 peer is a mismatch |
| **Silk** | default open = 32 kb/s switched |

Mk1 does not auto-negotiate rate. Mis-strap → garbage / hunt forever / hook chatter.

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
**RAW64 has no such guarantee** — that is why it is nailed-only (§3.6).

---

## 5. DTE face

Synchronous DCE, rate per §3.6 strap:

| signal | dir | insert-1 (default) | RAW64 |
|---|---|---|---|
| `TXD` | in | payload on `TXC` | payload on `TXC` |
| `RXD` | out | payload; mark while hunt / `MUTE` | payload; mark while `MUTE` |
| `TXC` | out | **32 kHz** (`TX_CLK` ÷ 2) | **64 kHz** (`TX_CLK`) |
| `RXC` | out | **32 kHz** when locked | **64 kHz** (`RX_CLK`) |
| `DTR` | in | seize → off-hook on SU-D (§6) | same; usually held for a nail |
| `DSR` | out | carrier · /`MUTE` · decode lock | carrier · /`MUTE` (no hunt) |
| `RI` | out | `RING` from S | usually unused on a nail |
| `RTS`/`CTS` | — | jumpered or looped in mk1 | same |

Electrical: **RS-422** differential on a rear/DTE connector (shelf data card
practice). Logic on the board is HC at +5.

No octet alignment in mk1: the subscriber plug has no superframe. Byte packing
is the DTE’s problem, or a later jumper.

---

## 6. Seize, dial, and S control

| SU-D input | SDU-1 drives | |
|---|---|---|
| hook / seize | `DTR` → off-hook when true (wired to the cradle sense net or an OR with the physical hook) | data call looks like a lifted handset |
| dial | Autovon pad on **SU-K**, unchanged | `BREAK` into SU-D still forces `1100` on the line — **insert-1 mode only** |
| `MUTE` | in from SU-D during pulse off-normal (SU-K's `OFF_NORM`, passed through) | encoder may free-run; line is `1100` anyway |
| `RING` | in | → `RI`; decoder already gets `1010` on `BIT_DEC` |
| `BIT_ENC` | out | insert-1 or raw per §3.6, when off-hook and not muted |
| `BIT_DEC` | in | matching decode |
| `TX_CLK` / `RX_CLK` | in | 64 kHz |

Mk1 **reuses SU-K's pad** for dialling in insert-1 mode; nothing about the
riser population reaches **K**. A headless data-only face (DTR seize, SU-K not
fitted) is a population option — SU-D holds `BREAK` and `OFF_NORM` low with the
ribbon unplugged. **RAW64** populations leave SU-K off and the circuit nailed.

---

## 7. Mezzanine header **S**

Same keyed **2×12** 0.1″ map as `su-1.md` §6.1. SDU-1 is the riser mate.

| pin | name | SDU-1 use |
|---|---|---|
| 3–5 | `+5` / `±12` | +5 for logic; ±12 unused in mk1 (reserve) |
| 7–8 | `TX_CLK` / `RX_CLK` | 64 kHz bit clocks |
| 9 | `BIT_ENC` | payload TX to SU-D mux |
| 10 | `BIT_DEC` | from SU-D (post-RING gate) |
| 14 | `MUTE` | dial mute / encoder don’t-care |
| 15 | `RING` | → `RI` |
| 16 | `/OE` | optional |
| 11–12, 17–20 | `AUDIO_*` / `SPK` / `MIC_EN` / test | **open / NC** on data-only SDU-1 (voice UI absent) |

Pins that only exist for SU-A stay no-connects. Do not drive `BIT_ENC` against
SU-D’s `1100` mux output; SU-D selects.

---

## 8. Parts (rough)

| block | parts |
|---|---|
| Insert-1 encode | ½ 74HC74 (phase), ¼ 74HC157 or OR/AND |
| Insert-1 decode + hunt/lock | ~2–3 HC MSI or 1× GAL16V8 |
| RAW64 bypass | jumper + mux (or GAL select) — `TXD`/`RXD` 1:1 to `BIT_*` |
| Clock divide | ½ 74HC74 → 32 kHz when insert-1; bypassed when RAW64 |
| DTE | RS-422 tx/rx (75176 / 26LS31 family), connector |
| Control | few gates: DTR→seize, `DSR`/`RI` buffers |
| Header | **S** mate; DTE connector |

**≈ 6–10 packages** plus line drivers — well under a CVSD SU-A. No ROM. No
codec analog. No framed-carrier MSI.

---

## 9. Against the exchange

The far end is a **CVSD subscriber line card**, not a shelf data card. On a
**switched** call, hook and dial are the line’s `1100` detector and the
register on A; payload is insert-1. A matching SDU-1 (insert-1) must sit on
the far subscriber line, or an exchange-side adapter must terminate insert-1
into a 32 kb/s DTE.

A **nailed** RAW64 circuit is two transparent 64 kb/s ends (or one SDU-1 and a
shelf data card / tail). Label the ports; do not hunt them.

Connecting insert-1 through the fabric to a **64 kb/s shelf data card** without
an insert-1 peer is a rate/code mismatch — label the port.

A dual-mode peer left on **VOICE** while this end is on **DATA** is the same
kind of failure: noise / hunt, no exchange alarm (`su-1.md` §6).

---

## 10. Not measured / deferred

- Bench confirm of XOR2 / ones RC with real insert-1 vs `subline.py` thresholds.
- Loop-timing on SU-D (`su-1.md` §5) — DPLL vs hard lock still open.
- GAL vs MSI for the framer; exact hunt constant N.
- Async DTE (UART ≤ 32 kBaud into a bit packer) as a later jumper.
- Exchange-side insert-1 tail for calls into shelf data ports.
- RAW64 against a real nail and against accidental dial attempts.
- Dual-mode combined riser layout and switch (`su-1.md` §6) — proposed, not drawn.
- PCB: outline 100 × 100 mm riser assumed; not drawn.

---

## 11. Related

| doc | |
|---|---|
| `su-1.md` | voice unit; SU-D base, S pin map, **dual-mode switch** (§7) |
| `subscriber-line.md` | pair law, raw biphase, `1100` / zeros, detectors |
| `channel-cards.md` §2 | CVSD line card (exchange end of this call) |
| `channel-cards.md` §4 | shelf 64 kb/s data card — different socket; peer for RAW64 nails |
| `extensions.md` §3 | nailed data circuit (`/ANS`, no cadence) |
