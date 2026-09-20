# The exchange — the counter card

`ex-extensions.md` §4 proposes traffic counters and wires them into the marker:
"each is a pulse from a state the marker's sequencer already reaches", on "a
counter card beside the marker". It does not need to be. **The control bus is a
broadcast** (`exch-mainboard.md` §2.3) — the marker's whole output is one
sixteen-bit word shifted out on `SDATA` and strobed by `WR`, and every tap on
the ribbon sees it. A counter can therefore be a card that *only listens*: three
of the cable's thirty-eight signals, no `/BLK`, no shunt column, no probe, no
clock, and no connection to the marker at all.

This document is the peg-count half of `ex-extensions.md` §4, built that way.
The usage half — erlangs by sampling `BUSY` on the probe — is not this card
(§5).

> **Status: proposed; the counting measured in RTL.** `exrtl/rtl/stats.v` is the
> card and `exrtl/tb/tb_stats.v` drives `ctl_write` with the exact sequence of
> words `marker.v` pushes for five calls, checking what each strap field counts.
> It passes under both Icarus and Verilator. The parts are a sketch from the
> monitor's and the block's; nothing has been drawn and nothing has been on a
> bench. §3's negative result — that an outbound and an inbound completion are
> the same sixteen bits — is measured, and it is the reason the fourth strap is
> not the one first asked for.

---

## 1. One card, one counter, sixteen bits

| | parts |
|---|---|
| the word | 1 × 74HC164 — `SRC[5:0]`, `BSY`, `CLM` |
| the strap field | 1 × 74HC688, eight three-way straps |
| the count | 4 × 74HC161 — sixteen bits, and 16 LEDs |
| the match | ¼ gate, inverting the '688's active-low answer into `ENP`/`ENT` |
| | **≈ 6¼ packages**, 16 LEDs, one reset key |

**One '164, not two.** A block needs a pair because it must read `DST` as well;
this card tests only `SRC`, `BSY` and `CLM`, and those are bits 7–0 — the whole
of the second register, and exactly eight bits, which is exactly one '688. Bits
15–8 fall out of the end unread.

**Clocked by `WR`.** The '688's answer is stable through the whole pulse,
because `exch-mainboard.md` §2.3.2's one rule already keeps `WR` clear of every
`SCLK` edge — the same rule that makes a block's write decoder work. So `WR` is
the counter chain's clock and the match is its `ENP`/`ENT`. No synchroniser, and
the card takes no clock off the cable.

**'161 and not '163.** The monitor's '163 has a *synchronous* clear, which needs
a clock edge to take effect — and the reset key gets pressed when the bus is
quiet. '161's clear is asynchronous and works with no traffic at all. Same
package otherwise.

**The shift register has no phase, only content**, exactly as at a block: nothing
reads it until `WR`, so the card needs no bit counter and no frame reference, and
it does not care whether `SCLK` is gated or free-running.

---

## 2. The strap field is the '688's Q side

A '688 compares eight bits and has no mask input, but a don't-care costs
nothing: **strap `Q`ᵢ to `P`ᵢ and that bit always matches.** Three ways a bit —
ground, Vcc, or `P`ᵢ — and one package is any pattern over `SRC`+`BSY`+`CLM`. It
is the same bargain as the mainboard's shunt column: the card is one design and
a jumper says what it is.

`P` below means the strap is left on `P`ᵢ — don't care.

| strapped for | `SRC[5:0]` | `BSY` | `CLM` | what it counts |
|---|---|---|---|---|
| **cannot-complete given** | `001100` (`o14`) | 1 | `P` | every failure: wrong numbers, busy lines, empty slots, no free trunk, no free register |
| **dial tone given** | `001000` (`o10`) | 1 | 0 | one a call **originating** here — the calling rate `exch-marker.md` §6 assumes |
| **trunks let go** | `000000` | 0 | 0 | the flood's teardown, and a hub's legs dropped when one claims |
| **calls over a trunk** | `bbb PPP` | 1 | 0 | a port pointed at a trunk on block *bbb* — network calls completed, **either direction** (§3) |
| claims | `000000` | 1 | 1 | **two** a call: the claim and the dial-tone-off that follows it are the identical word. Read the LEDs ignoring the bottom one |
| every write | `PPP PPP` | `P` | `P` | the marker's occupancy |

The first four are the card's four; the last two come free from the same field.

**The tone ports are jumpered here as they are at the marker.** `DIALTONE` and
`NOGO` are port numbers, and the card's straps carry the same two numbers the
marker's own jumpers do.

---

## 3. Measured: outbound and inbound are the same word

The fourth strap was first written as *outbound completed*. It cannot be.

| | the write | the word |
|---|---|---|
| an **outbound** call completes | `marker.v` 562, when the far end's claim returns | `DST` a line, `SRC` a trunk, `BSY` 1, `CLM` 0 |
| an **inbound** call completes | `marker.v` 555, the second of the connect pair | `DST` a line, `SRC` a trunk, `BSY` 1, `CLM` 0 |

**They are identical.** What separates them is not in the word but in its
history: an outbound completion is a *lone* write, because the trunk was pointed
at the caller seconds earlier when the flood was seized; an inbound one is the
*second of a reciprocal pair*. Telling them apart needs a detector that holds the
previous word — two more packages and a strobe eight `SCLK` into the next word —
and that is not a pattern counter.

So the strap counts **calls completed over a trunk, both directions**, which is
honest and still useful: against *dial tone given* it splits the exchange's
traffic into local and network. At a **hub** it also counts every tie-through and
resolver write, because those have a trunk as `SRC` too; at a leaf it does not.

Two cards recover the split: *calls over a trunk* minus *claims ÷ 2* is the
outbound half.

---

## 4. What the bus cannot see at all

**No call ever ends on the control bus.** The port clears its own latch
(`exch-fabric.md` §3.5 — "nobody is in charge of a call"), so the marker writes
nothing at release. Every counter here is a **peg count** and none can be counted
down; there is no "calls in progress" and no holding time. That is not a
limitation of the card, it is the architecture, and it is why §5 exists.

**Answer** is `E` rising inside the port. No answer-seizure ratio.

**`G` is unread.** The guard is in bits 15–8, which this card discards, so it
counts words the blocks themselves may have rejected on a bad guard. For a
counter that is tolerable; for a route it would not be.

**`DST` is unread**, so no strap can ask *which port was written*. That wants a
second '164 and a second '688 — a different strap field, not a different card.

---

## 5. Not this card

Erlangs. `ex-extensions.md` §4's usage sample — one enabled pass of the
scanner on each `RING_CAD` edge, counting ports of one class that read `BUSY` on
the probe, 600 counts to the erlang-hour — needs `PB`, `RING_CAD` and a wrap
detector, and a gate that the marker's own use of the probe does not disturb.
Different signals and a different card. Keeping it off this one is what makes
this one six packages.

---

## 6. The panel

A 3U eurocard's front edge is 100 mm and a single-width panel about 20 mm
across. Sixteen LEDs at 0.2-inch pitch is 81 mm of roughly 90 mm usable —
grouped 4-4-4-4 with the reset key below, it fits 4HP with nothing to spare.
That is why the card carries one counter and not two: a second row would want
8HP, and a toggle to share one row would cost 3 × '157, half the card again.

**How long before it wraps**, at 48 lines and 3 calls a line an hour:

| strapped for | a busy hour | 65 536 counts |
|---|---|---|
| dial tone given | 144 | 19 days |
| cannot-complete given | ≈ 22 | 124 days |
| calls over a trunk | ≈ 86 | 32 days |
| trunks let go | 43–130 | 21–63 days |
| every write | ≈ 720 | **3.8 days** |

Sixteen bits is what makes *since reboot* mean something for the four; the
occupancy strap is the one to read weekly.

---

## 7. Measured

`exrtl/tb/tb_stats.v` drives `ctl_write` with `marker.v`'s own `push()`
sequences for five calls — a local call that connects, one that does not, an
outbound network call, an inbound call claimed here, and an inbound call with no
register free — and reads six cards on the ribbon:

| strapped for | counted | expected |
|---|---|---|
| dial tone given | 3 | one per originating call |
| cannot-complete given | 2 | the local failure and the claimed one |
| trunks let go | 1 | the flood's second direction |
| calls over a trunk | 2 | **the outbound and the inbound, indistinguishable** |
| claims | 2 | two per inbound call |
| every write | 18 | all of them |

and then that the reset key clears a counter with the bus quiet, and that 300
counts land, so the chain is wider than one '161.

---

## 8. Not measured

- **Against a running network.** The bench replays the marker's words; it does
  not yet sit inside `tb_net` or `tb_hub` and check the totals those benches
  already know. That is the run that would prove the strap patterns are complete
  as well as correct — in particular whether the marker ever writes a word this
  card's straps misread.
- **A hub's tie-throughs** against the trunk strap, which §3 predicts are counted
  and a leaf's are not. Not run.
- **The console's writes.** The bus is multi-master (`exch-mainboard.md` §2.3);
  a word from the operator's console counts exactly as the marker's does, which
  is probably right and has not been thought through.
- **The circuit.** A sketch from the block's front end and the monitor's
  counter. The '688's don't-care strap, the match into `ENP`/`ENT`, and `WR` as
  the chain's clock against the '161's setup time have not been drawn.
- **The reset key**, which in `stats.v` is synchronous to the model's one clock
  domain and in the card is the '161's asynchronous clear.
- **LED current** and whether sixteen at 0.2-inch pitch is actually readable in
  groups of four at arm's length in a rack.
