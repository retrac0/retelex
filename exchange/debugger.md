# The debugger card: eleven lamps that name the board to pull

A listener on the bus that lights a lamp when the exchange breaks a rule it
cannot break while working. It drives nothing but LEDs and has **no
authority**: pulling it changes nothing, and fitting it disturbs nothing on the
exchange. A lamp does not say what went wrong; it says **which board to pull**.
The lamp fields of `proposed/lamps.md` show what the exchange is doing; this
card shows only what it must never do, and holds it until someone looks.

> **Built:** `newimpl/rtl/debugger.v`, benched by `tb_debug`: a quiet exchange
> and a clean write light nothing, each fault lights its own lamp, and one
> extra `SCLK` edge lights `SCLK_COUNT` and loses the write (`bus.md` §6).
> Fitted in no top; `tb_debug` fits it on `exch`. Not drawn, not counted.

---

## 1. What it is

| | |
|---|---|
| **Sits** | anywhere on the bus (`bus.md` §2) |
| **Reads, timing and planes** | `SLOT`, `SLOTQ`, the capture instant and the frame edge made from them as a block makes them, `SCAN[5:0]`, `/HA`, `/HB` |
| **Reads, control lines** | `SDATA`, `SCLK`, `WR`, and `/RESET`, which starts its scanner mirror with the clock card's divider (§4) |
| **Drives** | eleven LEDs. Nothing on the bus |
| **Keeps** | a mirror of the scanner; a mirror of the control word, shifted as a block shifts it; the `SCLK` edges since the last `WR`; the time since the last `SCLK` edge; whether each plane was seen released this pass; how many passes running some port has shown `M` with `BUSY` clear (one counter, not one a port) |
| **Lamps** | **sticky**: a fault that lasted one master tick a week ago is still lit when someone looks. `/CLR` is a button; it clears the lamps and the pass bookkeeping together |
| **Straps** | two counts (§2); no fitted map |

It leans on facts every build shares: port 00 is never fitted, a control word
is sixteen bits, and `SCAN` steps on every frame edge. `SCLK_COUNT` (lamp 6)
leans on `SCLK` gated per word, which is how both masters send it. `REG_WAIT`
(lamp 10) leans on how long a lifted phone may wait, which depends on the
build (§6, §7).

Every check is a handful of gates into one flip-flop. The lamps are eleven
sticky flip-flops, a '273 and a '175.

---

## 2. The lamps

Grouped by suspect: the group is the board to pull first.

| # | lamp | suspect | lights when | why it is a fault |
|---|---|---|---|---|
| 0 | `SCAN_STALL` | clock card | `SCAN` did not step at a frame edge, or stepped off one | the scanner has no enable (`common/clocks.md`); if this lights, the divider has grown one |
| 1 | `SLOTQ_LATE` | clock card | `SLOTQ` ≠ `SLOT` at a capture strobe | the '175 did not take; every strobe decoder is a cell off |
| 2 | `HA_P00` | the plane | `/HA` low in port 00's turn | 00 is never fitted, so nothing may drive its bit-time |
| 3 | `HB_P00` | the plane | the same on `/HB` | |
| 4 | `HA_STUCK` | the plane | `/HA` never high at any capture of a whole pass | a drain stuck on, or a short: one conductor, one failure domain (`fabric.md` §3). Lights with `HA_P00`, necessarily |
| 5 | `HB_STUCK` | the plane | the same on `/HB` | |
| 6 | `SCLK_COUNT` | control lines | `WR` arrives after a number of `SCLK` rises that is not a multiple of sixteen | one extra or missing edge, the glitch that can lose a call (`bus.md` §6), caught in the act |
| 7 | `WR_EDGE` | control lines | `WR` rises within a quarter bit-time of an `SCLK` edge, or an edge follows within that window | the control lines' one timing rule (`bus.md` §4) |
| 8 | `SELF_POINT` | a master | a write (G = 1) whose `SRC` is its `DST` | a port told to listen to itself; no sequence in any master makes it |
| 9 | `WR_P00` | a master | a write (G = 1) to port 00 | the port that is never fitted |
| 10 | `REG_WAIT` | the marker | some port shows `M` with `BUSY` clear at every pass of `REG_WAIT_PASSES` running | a phone lifted and nobody took it. With a register pool, a marker fault. With **one** register it is the register-queue lamp: a caller lifted while another held the register — dialling, in the watch after a connect (`marker.md` §5), or through a flood |

The straps: `REG_WAIT_PASSES` (16 passes, 16 ms) and `WR_GUARD` (8 master
ticks, a quarter of a 32-tick bit-time).

---

## 3. What it keeps, and on which edge

| | part | on |
|---|---|---|
| the scanner mirror | a '393 | the frame edge, as the clock card's divider; its wrap is the card's pass boundary, so a stalled `SCAN` does not also stop the pass bookkeeping |
| the word mirror | two '164, as a block has | `SCLK`'s rising edge |
| `SCLK` edges since `WR` | a '163, modulo sixteen | cleared by `WR`, stepped by `SCLK` |
| ticks since an `SCLK` edge, and a window after `WR` | two counters | the master clock |
| seen released this pass, `/HA` and `/HB` | two flip-flops | set at any capture with the wire high; cleared at the pass boundary |
| unserved this pass, and passes unserved | a flip-flop and a counter | set at a capture showing `M` and `BUSY` clear; judged at the pass boundary |

---

## 4. Why it does not light on a working exchange

A lamp that lights on a working exchange is worse than no lamp.

- **The first frame edge after reset arms the scanner mirror and does not step
  it.** Stepped there, the mirror would be one ahead for ever. On a board the
  '393 and the divider share one edge and one `/RESET` and have no such tick;
  it is the RTL strobe's artefact, and the code says so.
- **Only a shared `/RESET` puts the mirror in step.** Fitted to a running
  exchange, the '393 starts wherever it powers up and `SCAN_STALL` lights at
  once, every frame, whatever `/CLR` does, until the exchange's next
  `/RESET`. Fit the card with the exchange held in reset.
- **Every word ends in `WR`.** A word read is a `/WS` select and eight frames
  of `/HW` and moves no `SCLK` (`fabric.md` §4).
- **An event word** (G = 0) pulses `WR` and writes nothing. `SELF_POINT` and
  `WR_P00` are gated on G, so the unit's event words light neither
  (`proposed/counters.md` §5).
- **`WR` on the very tick of an `SCLK` edge** counts that edge as arrived: a
  sixteenth edge coincident with `WR` lights `WR_EDGE`, the rule it breaks, and
  not `SCLK_COUNT`.
- **`/CLR` restarts the pass bookkeeping**, so a lamp cleared mid-pass is not
  relit by the half-pass it was cleared in.

`tb_debug` checks the first two cases on the bench (four quiet passes, then one
written word); the event-word case is argued from the code.

---

## 5. What it does not watch, and why

- **`/HW`.** A card drives it only after a `/WS` select in its port's
  bit-time (`fabric.md` §4), and this card does not know what any card's word
  should be. A write does not steer `/HW`; `faults.py` F24 puts that back and
  turns `tb_word` red.
- **`/WS`.** A select made inside another read's eight frames is what a faulty
  reader would do, and nothing here sees it (§7).
- **The other 63 turns of `/HA` and `/HB`.** In a fitted port's turn low is a
  legitimate answer: this card cannot tell "21 off-hook" from "21 on-hook and
  another port answering 21's turn", which a port card's slot jumper set to
  the wrong socket does (`block-stack.md` §4). **The test belongs on the port**:
  in its own turn a port knows what it drives and already receives `/HA`, so a
  port that releases and reads the wire low shares its turn — a gate and a
  flip-flop a port, and a lamp or a wired-OR "turn clash" line. Proposed.
- **A write to an unfitted port other than 00.** That needs the fitted map:
  sixty-four straps.
- **Glare: a seizure of an already-busy port.** It needs last pass's `/HB` for
  the port just written — a 64-stage shift register, eight '164, and a compare
  at the right turn. **The most valuable lamp not on this card, and the first
  to add.** The network unit keeps a 64-bit per-port memory of the same shape
  for its own use (`newimpl/rtl/net_unit.v`).

---

## 6. On a network exchange

With the network unit fitted there are two masters, the unit ranked above the
marker on `/UREQ`, each letting go only between transactions (`bus.md` §5).
Argued, not run:

- **The control-line lamps still hold.** Each master sends whole words, and a
  clean handover looks like two clean words.
- **A collision would show.** Two masters' words at once — `b_clash` in the
  network benches, never lit — would almost certainly reach a `WR` with a
  shift count not a multiple of sixteen.
- **`REG_WAIT` is advisory.** A caller who lifts while the unit sweeps waits
  out the sweep (9 ms) before the marker can read its word, about 12 passes
  with the marker's read and the caller's turn: inside 16, and 32 is the safer
  strap where the unit may sweep twice running. A burst of incoming seizures
  is not covered: a trunk shows `M` with `BUSY` clear until the unit holds it,
  the unit classifies about one seizure each 18 ms (`network.md` §3.3), and the
  third of three waits about 36 passes.
- **Lamps a network build would want**, none built: `/UREQ` held longer than a
  sweep (the unit wedged holding the bus); two masters' '244s on at once, which
  tri-state drivers hide from the wires.

---

## 7. Open

- **`REG_WAIT` at 16 passes is wrong for the class marker.** Its WALK reaches a
  lifted phone up to a round later, 63 × 4 ≈ 252 passes (`marker.md` §4.2), so
  the lamp lights on ordinary lifts in `top_max`. It also lights for good on
  ports that are not faults: an off-hook data line, which the walk reads once a
  round and never takes (`marker.md` §4.2); a console ring source, `M` up and
  never `BUSY` (`proposed/console.md` §6); and on `top_max`, a port whose word
  reads none while `M` is up. Options: a strap per build (≥ 256 on `top_max`),
  or judge only ports whose word says caller, which needs a word read. Until
  then the lamp means something only on `top_min` and `top_net`.
- **No lamp watches `/WS`** (`newimpl/README.md` §6): a select inside another
  read's eight frames. A mirror of the eight-frame window and a compare.
- **The card itself**: not drawn, its packages not counted. The mirrors and
  counters of §3 are the whole of it.
- **A mirror that loads itself from `SCAN`** would let the card be fitted to a
  running exchange (§4). Not built.
- **Any network build with the card fitted.** §6 is argument.
- **Open-drain control lines.** If `SDATA`, `SCLK` and `WR` went open-drain and
  low-true (`bus.md` §7, undecided), the card's receivers would follow
  the blocks': the rules stay, the edges it watches invert.
- **Whether the lamps are grouped right in practice.** Faults injected one at
  a time each lit their own lamp; a real fault may light more.
