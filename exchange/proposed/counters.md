# Counters: the peg counter, event words, and calls in progress

Traffic counts, taken by cards that only listen. The control lines are a
broadcast, so a counter is a card that counts every word matching a jumpered
pattern; a master says what no write says in an **event word**; and a second
card counts busy ports off `/HB` for calls in progress and usage.

> **Built:** only the event words the network unit sends, glare and no trunk
> (`newimpl/rtl/net_unit.v`; seen on the bus in `tb_net` and `tb_lfull`).
> Neither marker sends any. **Proposed:** the counter card and the in-progress
> display; no `newimpl` bench models either.

---

## 1. The counter card

| | parts |
|---|---|
| the word | 1 × 74HC164: bits 7–0, `SRC[5:0]`, `BSY`, `CLM` |
| the jumper field | 1 × 74HC688, eight three-way jumpers (§2) |
| the count | 4 × 74HC161, sixteen bits, 16 LEDs; a reset key |
| the match | ¼ gate into `ENP`/`ENT` |
| | **≈ 6¼ packages** |

**One '164**: the card tests only bits 7–0, exactly one '688's worth; bits
15–8 fall out unread. **Clocked by `WR`**: the '688's answer is stable through
the pulse, because the rule that keeps `WR` clear of every `SCLK` edge
(`bus.md` §4) holds it so, and the card takes no clock off the bus. **'161, not
'163**: its clear is asynchronous and works with the bus quiet. **The shift
register has no phase, only content**: nothing reads it until `WR`.

---

## 2. The jumper field

A '688 has no mask, but **jumper `Q`ᵢ to `P`ᵢ and that bit always matches**:
ground, Vcc or `P`ᵢ a bit, and one package is any pattern over `SRC`, `BSY`,
`CLM`. `P` below is don't-care.

| jumpered for | `SRC` | `BSY` | `CLM` | what it counts |
|---|---|---|---|---|
| **dial tone given** | 01 | 1 | 0 | a call originating here; a claimed trunk is given none |
| **busy tone given** | 02 | 1 | `P` | a busy line dialled (the class marker; the mini marker gives 03) |
| **cannot-complete given** | 03 | 1 | `P` | every other failure: a wrong number, an empty slot, no free trunk or outside line, no digit, a refused claim |
| **a port written free** | 00 | 0 | 0 | an abandoned call, the watch freeing a called port (`marker.md` §5), the unit's drops and unholds — never a call ending, which writes nothing |
| **claims** | 00 | 1 | 1 | two a claimed call: the claim, and the identical dial-tone-off at its first digit |
| **calls over a trunk** | `h PPP` | 1 | 0 | where every trunk sits on block *h*, a block adapter's: calls completed over a trunk, both ways (§3) |
| every write | `PP` | `P` | `P` | both masters' occupancy, events included |
| every event | `PP` | 0 | 1 | every event word (§5) |

The tone ports are jumpered here as they are wired at the marker.

---

## 3. Outbound and inbound are the same word

An **outbound** call completes when the unit writes the caller to listen to the
trunk that claimed (`net_unit.v`); an **inbound** one with the marker's connect
pair, whose first word writes the called line to listen to the trunk. Both are
`DST` a line, `SRC` a trunk, `BSY` 1, `CLM` 0: **identical**. What separates
them is history — a lone write, or the first of a pair — and that is not a
pattern. So the jumper counts calls over a trunk both ways; against *dial tone
given* it splits local from network traffic. At a leaf, *calls over a trunk*
minus *claims* ÷ 2 is the outbound half; at a transit every tie-through counts
too.

---

## 4. What the control lines cannot show

- **A call ending.** The port clears its own latch (`fabric.md` §5), so a normal
  hang-up writes nothing and no peg count can be counted down. Calls in
  progress and holding time come off `/HB` (§6).
- **Answer**: `E` rising inside the port. No answer-seizure ratio.
- **`G` and `DST`**: this card discards bits 15–8. A second '164 and '688 read
  them — a different jumper field, not a different card.

---

## 5. The event word

`G` is ANDed into `WR` at every block (`bus.md` §4), so **a word with `G` = 0
writes nothing**, and still shifts and pulses `WR`: a second channel on the
same wires.

```
 G  spare  DST        SRC         BSY  CLM
 1    0    the port   the source   b    c     a latch write
 0    0    a port     a CODE       0    1     an EVENT: no block writes anything
```

- **`BSY` 0 with `CLM` 1 keeps the two apart.** Every write that sets `CLM`
  sets `BSY` (a claim is a seized trunk), in every master's RTL, so a jumper
  for an event never counts a write; and since this card cannot see `G`, a
  plain jumper counts an event.
- **`DST` is free**: the port the event is about, for a watch or a last-word
  display (`proposed/lamps.md` §6, §7).
- **A console cannot send one**: its `G` is wired high
  (`proposed/console.md` §1). An operator cannot fabricate a count.
- **An event never delays a call.** It is queued only with room to spare and
  dropped otherwise (`ctl_queue.v`), so **counts are lower bounds**.

| `SRC` | event | `DST` | |
|---|---|---|---|
| 00 | never sent: *no event* and *an event* are different codes | | |
| 01 | a caller waited for a register | the caller | reserved |
| 02 | a register timed out with no digit | the caller | reserved |
| 03 | a master's write queue overran | — | reserved |
| **04** | **glare**: `M` rose on a trunk this call holds, inside the origin's guard — the far end seizing the same channel; taken as the claim, and counted | the trunk | **built**: the unit |
| **10** | **no trunk**: the unit's sweep found no free trunk facing any way, busy or unfitted | 00 | **built**: the unit |
| 11–13 | all trunks busy, one code a direction | — | reserved |
| 05–07, 14–77 | unspent | | |

---

## 6. Calls in progress, and usage, off `/HB`

`/HB` carries every port's `BUSY` every pass (`fabric.md` §3). **Two '161
count `/HB` low at each capture and clear at the pass boundary; two '4511 latch
the count there** and show it in octal — a '4511 decodes an octal digit with
`D` grounded. 63 is the most, `77`, because port 00 is never fitted; an OVF lamp
at 64 means a fault. About five packages, refreshed every 1 ms.

**It counts busy ports, not calls**: a two-party call is two, a call over a
trunk two, a caller on dial tone one; a port ringing, in its release time,
nailed, or in a muted block counts too. Halving it would be right for connected
calls only.

**Usage** is the same count sampled: a flip-flop set on each `/RING_CAD` edge
(every 6.144 s) and cleared at the next pass boundary gates `/HB` lows into a
'4040 chain. One busy port for an hour is ≈ 586 counts, and holding time is
6.144 s × usage counts ÷ calls. The Bell System sampled every 100 s, the origin
of the CCS.

---

## 7. Open

- **The reserved codes.** 01 needs a flip-flop that counts a spell of a full
  register once, not once a caller; 02 a line from the register saying which
  timeout fired; 11–13 a flip-flop a direction in the sweep, so an unfitted
  direction is not congestion. Neither marker puts `G` = 0 in its queue today.
- **A transit's congestion.** The forwarder that finds no free trunk one way
  does not fan out there, and nothing counts it; it wants its own code.
- **Trunks in any socket.** A tie card may sit anywhere (`trunks.md` §1), and
  a block pattern misses it. Counting calls over such trunks needs `SRC`
  compared against a set of ports, or the word. Undecided.
- **Usage by class** — trunks a direction, lines — needs each port's word,
  which `/HB` does not carry.
- **Glare as defined**: `M` inside the guard, provoked only on a local trunk's
  last free channel (`tb_lfull`); never on a tie or at a transit.
- **Not measured**: the circuits; the card inside `tb_net` or `tb_lfull`,
  checking the totals those benches know; whether sixteen LEDs in groups of
  four read at arm's length.
