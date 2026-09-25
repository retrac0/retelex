# The exchange — the debugger card: eleven lamps that name the board to pull

A listener on the common-control tap that lights a lamp when the exchange
breaks a rule it cannot break while working. It reads the bus's timing, planes and control lines,
keeps its own copy of the scanner and of the last control word, and drives
nothing but LEDs. It has **no authority**: pulling it changes nothing, and
fitting it to a live exchange disturbs nothing on the exchange. (The card
itself is in step only from the exchange's next `/RESET`; §4.) A lamp does not
say what went wrong; it says **which board to pull**.

It is the fault-finding cousin of the lamp fields of `hookbusy.md` and
`observers.md`. Those show what the exchange is doing; this shows only what it
must never do, and holds it until someone looks.

> **Status: built in RTL and measured in simulation.**
> `newimpl/rtl/debugger.v`, benched by `tb_debug` (18 checks): a quiet
> exchange and a clean write light nothing. Eleven faults, one at a time, each
> light their own lamp, and the two `STUCK` faults light their `P00` lamp with
> it, as §2 says they must. Seven of the faults are mangled on the wires
> between the exchange and the card. The extra `SCLK` edge goes into the
> exchange as well. `SELF_POINT` and `WR_P00` are real words sent through the
> exchange, and `REG_WAIT` is a real phone lifting with no marker fitted.
> `mainboard.md` §7's `SCLK` hazard is reproduced: one extra edge lights the
> lamp and loses the write, and the next clean word lands. The card is not
> drawn and its packages are not counted. **It is fitted in neither top.**
> Neither brings out `SLOT`, `SLOTQ` or the capture strobe, and `top_min` has
> no control lines out. Fitting it means widening a
> top, and `tb_debug` fits it on `exch` directly. Nothing has been on a
> bench.
>
> **It had a twelfth lamp, `FILL_SCAN0`**, which lit when `FILL` and `SCAN[0]`
> disagreed: one divider stage on two pins. Since 2026-09-25 `FILL` has no pin
> of its own — it *is* `SCAN[0]` (`mainboard.md` §3.5) — so there is nothing
> left to disagree, and the lamp went.

---

## 1. What it is

| | |
|---|---|
| **Sits** | on the common-control tap, like a lamp field (`common-control.md` §2.2, `hookbusy.md` §3) |
| **Reads, timing and planes** | `SLOT`, `SLOTQ`, the capture strobe, the frame edge (`SLOT2`'s fall), `SCAN[5:0]`, `/HA`, `/HB`. The pass boundary is its own mirror wrapping, not `SCAN5` off the bus, so a stalled `SCAN` lights `SCAN_STALL` without also stopping the pass bookkeeping the other lamps judge by |
| **Reads, control lines** | `SDATA`, `SCLK`, `WR`, and `/RESET`, which starts its scanner mirror with the clock card's counter (§4) |
| **Drives** | eleven LEDs. Nothing on the bus |
| **Keeps** | a mirror of the scanner; a mirror of the control word, shifted exactly as a block shifts it; the `SCLK` edges since the last `WR`; the time since the last `SCLK` edge; whether each wire was seen released this pass; how many passes running some port has shown M with `BUSY` clear (one counter, not one a port) |
| **Lamps** | **sticky**: a fault that lasted one master tick a week ago is still lit when someone looks. `/CLR` is a button, and clears the lamps and the pass bookkeeping together |
| **Build** | MINIMAL+MAXIMAL. It leans on facts every build shares: port 00 is never fitted, a control word is sixteen bits, and the scanner steps on every frame edge. Two lamps lean on more. `SCLK_COUNT` assumes `SCLK` gated per word (lamp 7). `REG_WAIT` assumes a lifted phone is taken within a few passes, and how many is the one strap that depends on the build (§6). It needs no fitted map; its only straps are two counts (§2) |

Every check is a handful of gates into one flip-flop. The lamps are eleven
sticky flip-flops, a '273 and a '175.

---

## 2. The lamps

Grouped by suspect: the lamp's group is the board to pull first.

| # | lamp | suspect | lights when | why it is a fault |
|---|---|---|---|---|
| 0 | `SCAN_STALL` | clock card | `SCAN` did not step at a frame edge, or stepped off one | the scanner has no enable (`newimpl/README.md` §1). If this lights, the divider has grown one |
| 1 | `SLOTQ_LATE` | clock card | `SLOTQ` ≠ `SLOT` at a capture strobe | the '175 did not take; every strobe decoder is off by a cell |
| 2 | `HA_P00` | the plane | `/HA` low in port 00's turn | 00 is never fitted (`fabric.md` §3.3), so nothing may ever drive its bit-time |
| 3 | `HB_P00` | the plane | the same on `/HB` | |
| 4 | `HA_STUCK` | the plane | `/HA` never seen high at any capture of a whole pass | a drain stuck on, or a short. One conductor, one failure domain (`newimpl/README.md` §6). Lights with `HA_P00`, necessarily |
| 5 | `HB_STUCK` | the plane | the same on `/HB` | |
| 6 | `SCLK_COUNT` | control lines | `WR` arrives after a number of `SCLK` rises that is not a multiple of sixteen | one extra or one missing edge: `mainboard.md` §7's hazard, the one signal besides `/RESET` that can lose a call, caught in the act. **Only with `SCLK` gated per word.** On `mainboard.md` §2.3.2's jumper that free-runs `SCLK` off `HCLK` ÷ 4, the count at `WR` is arbitrary, the lamp would light on every write, and its LED is left out |
| 7 | `WR_EDGE` | control lines | `WR` rises within a quarter bit-time of an `SCLK` edge, or an edge follows within that window | `mainboard.md` §2.3.2's one timing rule |
| 8 | `SELF_POINT` | the marker | a write (G = 1) whose `SRC` is its `DST` | a port told to listen to itself. No sequence in any marker produces it |
| 9 | `WR_P00` | the marker | a write (G = 1) to port 00 | the port that is never fitted |
| 10 | `REG_WAIT` | the marker | some port shows M with `BUSY` clear at every pass of `REG_WAIT_PASSES` running (16) | a phone lifted and nobody took it. With a register pool this is a marker fault. With **one** register it is the register-queue lamp: it lights when a caller lifts while another caller holds the register — through their dialling, or on a network build through a whole flood. The mini marker frees the register at the connect, so a lift during a conversation is taken at once. Worth a lamp too |

The two straps are counts, not features: `REG_WAIT_PASSES` (16 passes, 16 ms;
"the marker takes a port within about a pass and a word; sixteen is
generous") and `WR_GUARD` (8 master ticks, a quarter of a 32-tick bit-time).

---

## 3. What it keeps, and on which edge

| | part | on |
|---|---|---|
| the scanner mirror | a '393 | the frame edge, as the clock card's own counter. Its wrap is the card's pass boundary |
| the word mirror | two '164, exactly as a block has | `SCLK`'s rising edge, as a block's '164 takes it |
| `SCLK` edges since `WR` | a '163, modulo sixteen | cleared by `WR`, stepped by `SCLK` |
| ticks since an `SCLK` edge, and a window after `WR` | two counters | the master clock |
| seen released this pass, `/HA` and `/HB` | two flip-flops | set at any capture with the wire high; cleared at the pass boundary |
| unserved this pass, and passes unserved | a flip-flop and a counter | set at a capture showing M and `BUSY` clear; judged at the pass boundary |

---

## 4. Why it does not light on a working exchange

A lamp that lights on a working exchange is worse than no lamp. Each of these
is a place it would, and does not:

- **The first frame edge after reset arms the scanner mirror, and does not
  step it.** The RTL's reset state reads as a frame edge that no count
  preceded; stepped there, the mirror is one ahead for ever and `SCAN_STALL`
  is lit. On the board the '393 and the '4040 stage share one edge and one
  `/RESET` and have no such tick — this is the RTL strobe's artefact, and the
  comment says so.
- **But only a shared `/RESET` puts the mirror in step.** Fitted to a running
  exchange, the card's '393 starts wherever it powers up, and `SCAN_STALL`
  lights at once. `/CLR` cannot put it out, because the mismatch comes back
  every frame. It goes out after the exchange's next `/RESET`. Fit the card
  with the exchange held in reset. A mirror that loads itself from `SCAN`
  would remove the need, and is not built.
- **Every word ends in `WR`.** A word read is a select on `/WS` in the port's
  own bit-time and eight frames of `/HW`, and moves no `SCLK` at all
  (`newimpl/README.md` §1). The pointing word it replaced shifted sixteen with
  no `WR`, which is why the count is taken modulo sixteen rather than exactly.
- **An event word** (G = 0) pulses `WR` and writes nothing. `SELF_POINT` and
  `WR_P00` are gated on G, so the unit's event words light neither. They have
  G = 0 and the event code as `SRC`, and `DST` is 00 for `EV_NOTRUNK` and the
  glared trunk for `EV_GLARE` (`net_unit.v`, `evw`).
- **`WR` on the very tick of an `SCLK` edge** counts that edge as arrived, so a
  sixteenth edge coincident with `WR` is still sixteen: it lights `WR_EDGE`,
  the rule it breaks, and not `SCLK_COUNT`.
- **`/CLR` restarts the pass bookkeeping**, so a lamp cleared mid-pass is not
  relit by the half-pass it was cleared in.

`tb_debug`'s first two checks are the quiet exchange and the clean write:
four passes, then one written word, light nothing. The pointing-word and
event-word cases are argued from the code; no bench sends either to the card.

---

## 5. What it does not watch, and why

- **`/HW`.** The card knows which port is pointed at, since its word mirror
  holds `DST`. It does not know what that card's word should be. `/HW` also
  has no released time to test. A block drives it from whichever port its
  '164s last named, write words included. So on a build with word pins, after
  every write the written port's card drives its word onto `/HW` until the
  next word shifts in, and a plain line card holds it low. A minimal build
  leaves the word pins unstuffed, and an empty port drives nothing.
- **The other 63 turns of `/HA` and `/HB`.** Port 00's turn is released by
  construction; in any fitted port's turn, low is a legitimate answer. This
  card cannot tell "21 off-hook" from "21 on-hook, and another port answering
  21's turn". That second case is newly possible: a port card's 2 × 3 slot
  jumper set to the wrong socket takes another port's turn, and its M and
  `BUSY` OR into that port's. **The test belongs on the port, not here**: in
  its own turn a port knows what it drives, and it already receives `/HA` for
  its E capture. A port that releases and reads the wire low shares its turn —
  a gate and a flip-flop a port, and a lamp or a wired-OR "turn clash" line.
  Proposed, not built.
- **A write to an unfitted port other than 00.** That needs the fitted map:
  sixty-four straps this card does not have.
- **Glare: a seizure of an already-busy port.** It needs last pass's `/HB` for
  the port just written — a 64-stage shift register, eight '164, and a compare
  at the right turn. **It is the most valuable lamp not on this card, and the
  first one to add.** The network unit now keeps a 64-bit per-port memory of
  the same shape, for its own purpose (`newimpl/rtl/net_unit.v`).

---

## 6. On a network exchange

The card was written for one master on the control lines. With the network unit fitted
(`newimpl/README.md` §3, `top_net`) there are two, the unit ranked above the
marker on `/UREQ`, each letting go only between transactions. What that means
here, argued and not run:

- **The cable-B lamps still hold.** Each master sends whole words, and a word
  read does not use cable B at all: it is a select on `/WS` and eight frames of
  `/HW`. `SCLK_COUNT` and `WR_EDGE` judge the bus, not a master,
  and a clean handover between two masters looks like two clean words.
- **A collision would show.** Two masters' words on the bus at once — the fault
  `top_net`'s `b_clash` counts, and which no bench has produced — would almost
  certainly reach a `WR` with a shift count that is not a multiple of sixteen,
  and light `SCLK_COUNT`.
- **`REG_WAIT` on a network build is advisory.** A caller who lifts while the
  unit is hunting waits out the sweep before the marker can read their word:
  the sweep's reads are back to back on `/HW`, a select every nine frames, so
  no other reader finds a free turn until it ends. Since `/WS` the sweep is
  9 ms, and the 1 ms confirming pass after it leaves `/HW` free
  (`net_unit.v`), so the caller waits about 9 passes, and about 12 once the
  marker's read and the caller's turn are added: inside the lamp's 16. It was
  18 to 20 with the pointing word, and the advice then was to strap 32; 32 is
  still the safer strap where the unit may sweep twice in a row. Neither
  covers a burst of incoming seizures. A trunk port shows M with `BUSY` clear until
  the unit holds it, and the unit classifies about one seizure each 18 ms
  (`newimpl/README.md` §6), so the third of three waits about 36 passes. The
  card cannot tell a trunk's port from a line's. By arithmetic; no bench fits
  the card beside a unit.
- **Lamps a network build would want**, none built: `/UREQ` held longer than a
  sweep (the unit wedged holding the bus); two masters' '244s enabled at once
  (not visible from the wires with tri-state drivers, which is part of the case
  for the open-drain proposal below).

**If the control lines' multi-master lines go open-drain** (the proposal of 2026-09-25:
`SDATA`, `SCLK` and `WR`, low-true, the driven edge active), the card's
receivers follow the blocks': shift on `/SCLK` falling, count on `/SCLK`
falling, judge `/WR` falling. The rules are unchanged; the edges it watches are
the other ones. Not decided.

---

## 7. Not measured

- **The card itself**: not drawn, and its package count not made. The mirrors
  and counters in §3 are the whole of it.
- **Any network build with the card fitted.** §6 is argument.
- **Whether the lamps are grouped right in practice.** Eleven faults injected
  one at a time each lit their own lamp, and the two `STUCK` faults lit their
  `P00` lamp with it. A real fault may light more.
