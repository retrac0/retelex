# The exchange — the counter card

`extensions.md` §4 proposes traffic counters and wires them into the marker:
"each is a pulse from a state the marker's sequencer already reaches", on "a
counter card beside the marker". It does not need to be. **The control bus is a
broadcast** (`mainboard.md` §2.3) — the marker's whole output is one
sixteen-bit word shifted out on `SDATA` and strobed by `WR`, and every tap on
the ribbon sees it. A counter can therefore be a card that *only listens*: three
of the cable's forty-three signals, no `/BLK`, no shunt column, no probe, no
clock, and no connection to the marker at all.

This document is the peg-count half of `extensions.md` §4, built that way.
The usage half — erlangs by sampling `BUSY` on the probe — is not this card
(§5). **§9 is what makes the other half of §4's list countable at all**: the
marker says the things no latch write says, in a word that writes nothing.

> **Status: proposed; the counting measured in RTL.** `verilog/rtl/stats.v` is the
> card and `verilog/tb/tb_stats.v` drives `ctl_write` with the exact sequence of
> words `marker.v` pushes for five calls, checking what each jumper field counts.
> It passes under both Icarus and Verilator. The parts are a sketch from the
> monitor's and the block's; nothing has been drawn and nothing has been on a
> bench. §3's negative result — that an outbound and an inbound completion are
> the same sixteen bits — is measured, and it is the reason the fourth jumper is
> not the one first asked for.
>
> **§9, the event word, is built**: `marker.v` sends one for each of five
> occasions, `ctl_write.v` carries the guard bit, and `tb_stats.v` and
> `tb_stress.v` measure both halves of the claim — that a plain jumper counts
> them, and that not one of them reaches a jumper meant for a call.

---

## 1. One card, one counter, sixteen bits

| | parts |
|---|---|
| the word | 1 × 74HC164 — `SRC[5:0]`, `BSY`, `CLM` |
| the jumper field | 1 × 74HC688, eight three-way jumpers |
| the count | 4 × 74HC161 — sixteen bits, and 16 LEDs |
| the match | ¼ gate, inverting the '688's active-low answer into `ENP`/`ENT` |
| | **≈ 6¼ packages**, 16 LEDs, one reset key |

**One '164, not two.** A block needs a pair because it must read `DST` as well;
this card tests only `SRC`, `BSY` and `CLM`, and those are bits 7–0 — the whole
of the second register, and exactly eight bits, which is exactly one '688. Bits
15–8 fall out of the end unread.

**Clocked by `WR`.** The '688's answer is stable through the whole pulse,
because `mainboard.md` §2.3.2's one rule already keeps `WR` clear of every
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

## 2. The jumper field is the '688's Q side

A '688 compares eight bits and has no mask input, but a don't-care costs
nothing: **jumper `Q`ᵢ to `P`ᵢ and that bit always matches.** Three ways a bit —
ground, Vcc, or `P`ᵢ — and one package is any pattern over `SRC`+`BSY`+`CLM`. It
is the same bargain as the mainboard's shunt column: the card is one design and
a jumper says what it is.

`P` below means the jumper is left on `P`ᵢ — don't care.

| jumpered for | `SRC[5:0]` | `BSY` | `CLM` | what it counts |
|---|---|---|---|---|
| **cannot-complete given** | `000011` (`o03`) | 1 | `P` | every failure: wrong numbers, empty slots, no free trunk, no free register |
| **dial tone given** | `000001` (`o01`) | 1 | 0 | one a call **originating** here — the calling rate `marker.md` §6 assumes |
| **busy tone given** | `000010` (`o02`) | 1 | `P` | called party busy (when the marker points at 02; today RTL still uses `o03` for both) |
| **trunks let go** | `000000` | 0 | 0 | the flood's teardown, and a hub's legs dropped when one claims |
| **calls over a trunk** | `bbb PPP` | 1 | 0 | a port pointed at a trunk on block *bbb* — network calls completed, **either direction** (§3) |
| claims | `000000` | 1 | 1 | **two** a call: the claim and the dial-tone-off that follows it are the identical word. Read the LEDs ignoring the bottom one |
| every write | `PPP PPP` | `P` | `P` | the marker's occupancy |

The first four are the card's four; the last two come free from the same field.

**The tone ports are jumpered here as they are at the marker.** `DIALTONE` and
`NOGO` are port numbers, and the card's jumpers carry the same two numbers the
marker's own jumpers do.

---

## 3. Measured: outbound and inbound are the same word

The fourth jumper was first written as *outbound completed*. It cannot be.

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

So the jumper counts **calls completed over a trunk, both directions**, which is
honest and still useful: against *dial tone given* it splits the exchange's
traffic into local and network. At a **hub** it also counts every tie-through and
resolver write, because those have a trunk as `SRC` too; at a leaf it does not.

Two cards recover the split: *calls over a trunk* minus *claims ÷ 2* is the
outbound half.

---

## 4. What the bus cannot see at all

**No call ever ends on the control bus.** The port clears its own latch
(`fabric.md` §3.5 — "nobody is in charge of a call"), so the marker writes
nothing at release. Every counter here is a **peg count** and none can be counted
down; there is no "calls in progress" and no holding time. That is not a
limitation of the card, it is the architecture, and it is why §5 exists.

**Answer** is `E` rising inside the port. No answer-seizure ratio.

**`G` is unread.** The guard is in bits 15–8, which this card discards, so it
counts words the blocks themselves may have rejected on a bad guard. For a
counter that is tolerable; for a route it would not be.

**`DST` is unread**, so no jumper can ask *which port was written*. That wants a
second '164 and a second '688 — a different jumper field, not a different card.
It is also why §9's event word can carry a port in `DST` for free: this card
cannot see it, and the cards that can (`observers.md` §5, §6) are looking at
the whole word anyway.

---

## 5. Not this card

Erlangs. `extensions.md` §4's usage sample — one enabled pass of the
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

| jumpered for | a busy hour | 65 536 counts |
|---|---|---|
| dial tone given | 144 | 19 days |
| cannot-complete given | ≈ 22 | 124 days |
| calls over a trunk | ≈ 86 | 32 days |
| trunks let go | 43–130 | 21–63 days |
| every write | ≈ 720 | **3.8 days** |

Sixteen bits is what makes *since reboot* mean something for the four; the
occupancy jumper is the one to read weekly.

---

## 7. Measured

`verilog/tb/tb_stats.v` drives `ctl_write` with `marker.v`'s own `push()`
sequences for five calls — a local call that connects, one that does not, an
outbound network call, an inbound call claimed here, and an inbound call with no
register free — and reads six cards on the ribbon:

| jumpered for | counted | expected |
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
  already know. That is the run that would prove the jumper patterns are complete
  as well as correct — in particular whether the marker ever writes a word this
  card's jumpers misread.
- **A hub's tie-throughs** against the trunk jumper, which §3 predicts are counted
  and a leaf's are not. Not run.
- **The console's writes.** The bus is multi-master (`mainboard.md` §2.3);
  a word from the operator's console counts exactly as the marker's does, which
  is probably right and has not been thought through.
- **The circuit.** A sketch from the block's front end and the monitor's
  counter. The '688's don't-care jumper, the match into `ENP`/`ENT`, and `WR` as
  the chain's clock against the '161's setup time have not been drawn.
- **The reset key**, which in `stats.v` is synchronous to the model's one clock
  domain and in the card is the '161's asynchronous clear.
- **LED current** and whether sixteen at 0.2-inch pitch is actually readable in
  groups of four at arm's length in a rack.

---

## 9. The event word: the marker says what no write says

`extensions.md` §4 asks for counts this card cannot reach, and they have one
thing in common — **nothing is written when they happen**:

| | why there is no write |
|---|---|
| a caller waited for a register | the marker does nothing at all. The caller waits and the scanner comes round again |
| all trunks busy, a count a direction | the hunt finds nothing. The only write is the caller's cannot-complete, and it says neither *why* nor *which way* |
| a register gave up with no digit | the register frees itself on its own timeout (`register.md` §2) |
| glare | the design **tolerates** it — `network.md` §1, "residual glare joins two callers to each other" — so there is nothing to undo and nothing to write |
| the write queue overran | a model part (`marker.v`), and the one thing a bench most wants to know did not happen |

§4 above says no call ever *ends* on the bus, and that is the architecture. This
is not that. These are occasions the marker **knows about at the instant they
happen** and merely had no way to mention.

### 9.1 One bit makes the channel

Bit 15 is the guard: `G`·`WR` at every block's write decoder
(`mainboard.md` §2.3.1), so **a word that does not carry it cannot write.**
That is a safety rule, and it is also a second channel on the same wire.

```
 G  spare   DST         SRC        BSY  CLM
 1    0     the port    the source   b    c     a latch write.  One block writes its latch
 0    0     a port      a CODE       0    1     an EVENT.  No block writes anything at all
```

- **Nothing at a block changes.** Not a gate, not a jumper, not a conductor. The
  word shifts through the same two '164 and is refused by the same quarter
  package that already refuses a word with a bad guard.
- **This card cannot tell the difference, and that is the point.** §1: bits 15–8
  fall out of the end unread, so a G = 0 word clocks the '688 and the '161 chain
  exactly as a write does. **A plain jumper counts an event.**
- **`BSY` = 0 with `CLM` = 1 is what keeps the two apart.** Every write the
  marker makes that sets `CLM` also sets `BSY` — a claim is a *seized* trunk —
  so that combination is one no latch write ever carries. Sixty-four codes live
  under it, in `SRC`, and a jumper for one of them can never count a call. §9.4
  measures both halves of that.
- **`DST` is free.** Nothing writes, so the field can say which port the event is
  about. This card cannot read it (§4) and does not need to; `observers.md`
  §5 and §6 can, so the same word is a count here and a diagnosis there.
- **A console cannot send one.** Its word comes off two '165 with `G` wired high
  (`console.md` §1). The converse of "a console cannot send a word the marker
  could not have sent" is now true as well, and it means **an operator cannot
  fabricate a count**.

### 9.2 Five codes of sixty-four

| `SRC` | event | `DST` | when |
|---|---|---|---|
| `o01` | **a caller waited for a register** | the caller | a call request found the pool full. **Once an occasion**, not once a scan: a flip-flop, set on the refusal and cleared when the next register is handed out, so a spell that outlasts several callers counts one |
| `o02` | **no digit dialled** | the caller | the register's own timeout fired rather than CLR. One conductor on the ribbon that already runs from the register to the marker says which |
| `o03` | the write queue overran | — | a model part. In 74HC the sequencer holds until its word is away and there is no queue; the code is spent anyway, because a bench that cannot see this is not measuring what it thinks |
| `o04` | **glare** | the trunk | M rose on a trunk we seized, **inside the origin's 128 ms guard**. A claim cannot come back that fast — the far end must hear `e b h s` first, which is seconds — so it is the other end seizing the same channel. Counting it changes nothing about what happens |
| `o10`–`o13` | **all trunks busy**, one a direction | — | the hunt saw a trunk facing that way and none of them free. A direction with **no** trunks fitted is not congestion and is not counted, which is one more flip-flop a direction in the hunt |

`o00` is left free so that *no event* and *an event* are not the same code.
`o05`–`o07` and `o14`–`o77` are unspent.

### 9.3 What it costs

| | |
|---|---|
| the bus | 125 µs at 128 kHz, the same as any word, on an occasion that happens a handful of times an hour |
| the probe | **an event steers `/BLK` exactly as a write does**, so it dirties the probe and costs the same repeated visit (`rtl.md`, "steering the probe costs a visit"). Setting `DST` to the block the scanner is already on would make it free; carrying the port is worth more than one visit in a 9 ms scan |
| a call | **nothing.** An event is pushed only when the sequencer has room to spare and is simply dropped when it has not, so no caller ever waits behind a diagnostic. The counts are therefore **lower bounds**, and the occasion they would drop is the busiest one — which is what `o03` is for |
| the marker | the guard becomes a bit of the sequencer's word instead of a tie to Vcc; four flip-flops for "a trunk faces this way at all", one for the register spell, one for the overrun |
| a register | one conductor for `o02` |

### 9.4 Measured

**`verilog/tb/tb_stats.v`**, the same bench that replays `marker.v`'s five calls,
now sends seven event words after them:

| | |
|---|---|
| every event (`BSY` 0, `CLM` 1, code don't-care) | 7 of 7 |
| a caller waited for a register | 2 |
| all trunks busy — **all four directions on one card**, the two low bits jumpered to `P`ᵢ | 2 |
| glare | 1 |
| **the five jumpers meant for calls** — dial tone, cannot-complete, trunks let go, calls over a trunk, claims | **unchanged, every one** |
| the occupancy jumper | 25: every word on the bus, which is what it asks for and the one jumper that is not fooled because it is not trying to be |

**`verilog/tb/tb_stress.v`**, forty-eight callers and real traffic, carries five
such cards on each exchange's ribbon. It checks the invariant the whole scheme
rests on — over the run, **no latch write carried `CLM` without `BSY`**, not
once, either exchange — and the event codes account for every event word the
cards counted. What they counted is the point:

| the run | registers | callers who waited out dial tone | **`o01`, the pool was full** |
|---|---|---|---|
| `make stress`, 5.4 s of traffic | 8 | 0 | **7** |
| `make stress-overload`, the same traffic | 2 | 94 | **21** |

**Seven occasions on which the pool filled and not one caller noticed**, on a
run where every other instrument in the exchange says nothing happened: that is
the count `extensions.md` §4 asked for and the one no listener could get. And
21 against 94 is the definition working as §9.2 states it — a spell is one
count, however many callers queue behind it.

No `o10`–`o13`, `o02`, `o03` or `o04` in either run: a single exchange with its
trunks idle, nobody left off-hook for ten seconds, and a queue that never
overran. **Those four are unexercised**, and §9.5 says so.

### 9.5 Not measured

- **The circuit.** Nothing is drawn. In 74HC the change is where `G` comes from
  and a handful of flip-flops; none of it has been laid out with the sequencer's
  own states.
- **Bit 14.** `mainboard.md` §7 leaves parity over bits 13–0 open. An event
  word would carry it like any other and nothing here changes — but the two have
  never been thought about together, and bit 14 is the only place a *third*
  kind of word could ever come from.
- **The occasion flip-flop's edges.** `o01` counts a spell, and what ends a spell
  is "a register was handed out" — including one handed to an *inbound claim*
  rather than to the caller who waited. Defensible, arbitrary, and unmeasured
  against a real busy hour.
- **`o04` as a definition of glare.** It is *M inside the guard*, which is
  reasoned from the claim taking seconds and not from a measurement of a real
  collision; the stress bench makes line glare likely and trunk glare only
  possible.
- **Four of the five codes have never fired in a real run.** `tb_stats` sends
  them by hand and the jumpers count them; nothing has yet driven `marker.v` into
  sending `o02`, `o03`, `o04` or `o10`–`o13`. The trunk ones want the pair run
  with every channel seized, and `o04` wants a collision built on purpose.
- **A hub's congestion.** `o10`–`o13` are the *origin's* hunt. The forwarder at
  a hub looks for its own free trunk in every other direction and, finding none
  that way, simply does not fan out there; nothing counts it. It is the same
  event one layer along and it wants its own code, which the code space has
  plenty of.
- **What an operator does with a count of glare**, which is the honest question
  about the whole of §9: it is a number to put in a log book, and the design does
  not act on any of them.
