# The exchange — the calls-in-progress display

Two seven-segment digits on the wall that say how many ports are in a call
right now, in octal, refreshed eight or nine times a second. It is the
smallest of the cards that only listen — eight conductors, about ten packages
— and it is the one that answers the question an operator actually asks.

`counters.md` §4 says that number cannot exist: *"No call ever ends on the
control bus… Every counter here is a **peg count** and none can be counted
down; there is no 'calls in progress' and no holding time. That is not a
limitation of the card, it is the architecture."* That is true of **cable B**
and false of the exchange. A port's `BUSY` is a live latch bit, and the probe
reads it. §1 is why the distinction matters and §8 is what it costs
`counters.md`.

> **Status: proposed; the card measured in RTL.** `verilog/rtl/inprog.v` is the
> card and `verilog/tb/tb_inprog.v` drives it **two ways**: a directed scanner
> for the decode, the range, the overflow, the repeat and the `/CON` freeze,
> and a whole `net_site` exchange — real marker, real calls — where every
> check compares the display against `$countones()` of the ports' own
> `port_busy`; §4a breaks `SCAN`, `ADVANCE` and `START` in turn while running,
> and §4b kills each of `ADVANCE` and `START` from reset, which is the case
> the first draft of this card failed silently. **43 checks, 0 errors under
> Verilator**, and the Icarus reference agrees, both reporting the same
> 72-visit pass and the same naive over-read. `make iv-inprog` carries `IVPAR_inprog := -Ptb_inprog.CALLS=0`
> and leaves §7's dialling to Verilator — the same bargain `IVPAR_erlang`
> and `IVPAR_console` already make. The
> §7 parts list is a sketch by function and has not been drawn; nothing has
> been on a bench.
>
> **The conductors it needs are now on the cable.** `SCAN[2:0]`, `ADVANCE`
> and `START` are cable B pins 17–25 (`mainboard.md` §2.3.3, §2.3.4, §3.2),
> which took cable B from a sixteen-way to a twenty-six-way. The block
> connector went from forty-eight signals to fifty-one — `SCAN` only:
> `ADVANCE` and `START` are for listeners and no block reads them.
> `SCAN[2:0]` was brought out for a reason larger than this card: without it
> the documented mainboard could not build the probe mux `block.v`:108
> implements.

---

## 1. The probe carries what the control bus cannot

Everything an observer wants is a broadcast, except one thing.

| | what it carries | who can read it |
|---|---|---|
| `HA[0..7]` | all 64 ports' hook, every frame, commutated by `SLOT` | anybody, free (`observers.md` §2) |
| `SDATA`/`SCLK`/`WR` | every decision the marker makes, as a 16-bit word | anybody, free (`counters.md`) |
| `PB[1:0]` | **one** port's `BUSY` and card word, held for a 125 µs visit | the marker — and, since `SCAN[2:0]` says *which* port, anybody (§2) |

The asymmetry is `counters.md` §4's whole subject. A latch write says a call
began; nothing says a call ended, because *"the port clears its own latch"*
(`fabric.md` §3.5). So a card listening to cable B can light a lamp and never
put it out, which is why `observers.md` §5 needs `STALE` and why every counter
in `counters.md` is a peg count.

**`BUSY` on the probe is the live bit, not a shadow of a write.** The port's
'273 drives it through the block's commutator, so when the port releases
itself the next visit reads zero. A card that can address the probe therefore
sees releases, and once it sees releases it can count what is up *now* rather
than what has ever started. That is the whole of this document.

---

## 2. Which port is the probe showing?

**Not the one `SLOT` names.** `fabric.md` §1.1 puts it in bold — the `BUSY`
and word muxes are addressed by the scanner, **"not by `SLOT`"** — and
`block.v`:108 is the sentence in Verilog:

```
wire [2:0] pb_sel = con_n ? scan_port : cw[10:8];
mux8 u_cc (.d(c_mux),    .s(slot),   .y(hc_out));     // the highways: SLOT
mux8 u_cb (.d(busy_com), .s(pb_sel), .y(pb_busy_i));  // the probe: NOT slot
```

`extensions.md` §2.2 says why it has to be that way: the card word is sixteen
bits at 128 kHz and *"for the whole visit `PB` holds that card's pin steady,
so the marker may clock sixteen bits"*. A probe commutated by the cell could
not carry a word at all.

So the only thing that says which port is on `PB0` is the scanner's own low
three bits. The RTL has always had them as a bundle — `marker.v`:330 is
`assign scan_port = scan[2:0];`, `block.v`:54 takes it, and `exch_top.v`:51
files it under *"cable B: the control bus"* — but **`mainboard.md` never listed
the conductor**, so the cable as documented could not build the probe mux the
RTL implements. That was a mainboard defect independent of any card, and
`mainboard.md` §2.3.3 now settles it.

It could not have been a field in the word instead. A sixteen-bit word at
128 kHz is 125 µs and a port visit is 125 µs, so steering the probe by word
would saturate the control bus exactly and leave nothing for writes — which is
why the marker sends `{scan[5:3], 3'd0}`, the block with the port field zeroed,
once a block (`marker.v`:510). Under `/CON` the console *does* steer by word,
and that is the one place the cost is worth paying, because an operator aims
the probe by hand a few times a minute.

**Five conductors on cable B settle it, and now do.** `mainboard.md` §2.3.3
and §2.3.4 carry them: cable B is a twenty-six-way, pins 1–15 unchanged from
the sixteen-way so nothing already built moves, `SCAN0/1/2` at 17, 19 and 21,
and `ADVANCE` and `START` at 23 and 25 (§5). Cable B was the one to grow
because it carries no signal whose edges matter to a layout argument. Only
`SCAN` reaches a block: the block connector went from forty-eight signals to
fifty-one, against sixty-four pins across rows a and c of a 96-way, and
`ADVANCE` and `START` stop at the ribbon because no block reads them.

The alternative — eight `HB` conductors making `BUSY` a broadcast like `HA`
(`hookbusy.md` §9) — is the better end state and the wrong cable. Cable A is
the 64-way carrying the three signals whose edges matter, full at 31 + 1 spare.

---

## 3. It does not need the block

The scanner is a free-running counter over all 64 ports. **Any 64 consecutive
distinct visits are one of each port**, so the total over them is the total
over a pass, however the pass happens to be aligned. The card counts
`SCAN[2:0]` wrapping 7 → 0 eight times and is done.

That deletes the '164, the `DST` decode, `SDATA`, `SCLK` — and one whole
failure mode. A **write** word puts its own `DST` on the bus, and the probe is
not re-steered until the word after it (`marker.v`:525), so a card that took
the block from the word would mis-attribute that visit. This card never looks
at the word, so the question does not arise.

Six conductors, then:

| | from | why |
|---|---|---|
| `CLK_8K` | cable A pin 21 | the visit boundary; a port visit is one period |
| `SCAN[2:0]` | cable B pins 17, 19, 21 | which port `PB0` belongs to |
| `ADVANCE` | cable B pin 23 | the scanner stepped — so this visit is not a repeat |
| `START` | cable B pin 25 | a pass begins here |
| `PB0` | cable B pin 11 | that port's `BUSY` |
| `/CON` | cable B pin 15 | stop: the probe is the console's now (§6) |

No `/BLK`, no shunt column, no `SDATA`, no `SCLK`, no word, no connection to
the marker — the same list `counters.md` §1 opens with.

---

## 4. The de-dup is the instrument

**The marker dirties its own probe constantly**, and a dirtied probe costs a
repeated visit. `marker.v`:485 says so in its own comment:

```
// A re-point cannot finish before the visit it governs, so a
// disturbed visit is REPEATED, not lost.
if (pv) scan <= scan + 1'b1;
```

| what dirties it | how often |
|---|---|
| `marker.v`:500 — `scan[2:0] == 3'd7`, every block end | **8 a pass, always** |
| `marker.v`:525 — after every write | 2 a call |
| `marker.v`:546 — after a yield | with traffic |

Because the scanner is held still, **a repeated visit is one with no
`ADVANCE`** — so counting on `ADVANCE` removes it exactly, with no comparison
and no memory at all. `SCAN[2:0]` alone could do it, by spotting that the port
had not changed, but that costs a '175 and an '86 and gets the direction wrong
if you are not careful (§5). One conductor is cheaper than both, and it is
exact rather than inferred.

**Measured, against a naive control.** `tb_inprog` runs a second counter on
the same `PB0` that takes every visit, as a card without `SCAN[2:0]` would
have to:

```
72 visits a pass, 64 counted;  de-duped 4, naive 6
```

Seventy-two visits for sixty-four ports — the eight forced re-steers, exactly
as predicted. And the naive count is **6 against a true 4**: the repeats land
on slot 0 of each block, ports 20 and 30 are slot 0 of blocks 2 and 3, and
both were in a call, so both were counted twice. The error is not a smooth
11 % — it is a 50 % over-read that depends on *which* ports are busy, which is
worse than a bias, because it cannot be calibrated out.

This is why `counters.md` §5 defers the usage half by name: it needs *"a gate
that the marker's own use of the probe does not disturb."* This is that gate.

---

## 5. The three signals check each other

Any one of `SCAN[2:0]`, `ADVANCE` and `START` is derivable from the other two
while the scanner behaves, so the card carries a **six-bit counter clocked by
`ADVANCE` and cleared by `START` whose only job is to disagree**. It never
feeds the data path. Three rules:

| | catches |
|---|---|
| `SCAN` ≠ (`ADVANCE` last tick ? prev + 1 : prev) | a jump inside a block, a lost or spurious `ADVANCE`, `SCAN` stuck high or low |
| `START` ≠ (`lcnt` = 0) | not exactly 64 advances in the pass — a jump of 8, 16 … preserves the low three bits, so only the count sees it |
| **unarmed for two passes** | `ADVANCE` or `START` dead *from reset* — see below |

`ERR` latches on any of them and holds until the reset key. **It is a check on
the cable, not on the card's own reckoning**, and that is the whole difference
between carrying the address and deriving it locally: a card that counted the
scan for itself would have a detector that mostly caught its own inhibit being
wrong. This one catches the wire, which on a bus where nothing acknowledges
anything is the only fault detection there is.

**The third rule exists because the first two cannot fire until the card is
armed, and only `START` can arm it.** A conductor that is dead before the card
ever sees a good pass would otherwise leave it sitting blank and silent for
ever — `00` on the wall with every lamp out, which is exactly the reading §8
says this card must never give. Two defences:

- **`FROZEN` is lit from reset**, not dark. It clears only when a whole pass
  has latched, so a blank display always says whether the blank is news.
- **The watchdog counts *visits*, not advances**, while unarmed — if `ADVANCE`
  is the dead conductor there are none to count. Two passes with no `START` is
  a conductor, not a wait: the next `START` is never more than 64 visits away.
  It reuses `lcnt`, which is idle while unarmed, so it costs no package.

This matters more than it looks, because the documented response to a lit `ERR`
is the reset key — and without the watchdog, pressing it while a conductor was
dead would have converted a lit lamp into a permanent, unlit, wrong `00`.

**A fourth rule was tried and taken out.** `lcnt[2:0]` ≠ `SCAN[2:0]`, an
absolute check against the `START` anchor beside the step rule's relative one,
**caught nothing**: deleting it leaves every check in `tb_inprog` green, and no
cable fault survives the step rule long enough to reach it — the step rule
re-anchors to `prev` every tick, so a jump fires it within one visit, and a
jump of eight is the count rule's business. What it did guard was the step
rule's own '175. That is a card fault, not a cable fault, it is not testable
from outside, and §9 carries it rather than the card carrying a package for
it.

**The step rule's direction is not the obvious one, and getting it wrong is
the mistake to avoid.** `ADVANCE` on a visit means *that visit was the last
for that port*, so `SCAN` changes on the tick **after** it. At a block boundary
the real marker gives

```
(SCAN 7, ADVANCE)   (SCAN 0, no ADVANCE)   (SCAN 0, ADVANCE)
```

— `SCAN` changes **on a non-advancing visit**. The first version of
`inprog.v` read that backwards and `tb_inprog` failed it against a real marker
at every block end, which is the case for driving a bench from the exchange
rather than from the design's own idea of the exchange.

`tb_inprog` breaks each of the three in turn and confirms the lamp lights;
more usefully, it asserts `ERR` stays **dark** through every other section,
which is thousands of real visits with the marker dirtying its own probe
throughout.

---

## 6. `/CON`, and never showing half a pass

While the console holds the bus, `block.v` selects `cw[10:8]` and `SCAN[2:0]`
stops describing what is on `PB0`. The card stops counting, **holds the last
complete pass**, and lights `FROZEN`.

It does not simply resume when `/CON` rises. A pass has to start at a
boundary, so the card disarms, re-aligns on the next `SCAN` wrap, counts a
whole pass and only then shows it — `FROZEN` stays lit throughout. The display
is either the last good pass or a complete new one, never a partial count.
The same mechanism aligns it after `/RESET` and after the reset key, so the
first number it ever shows is a true 64-port pass.

---

## 7. What it costs

| | parts |
|---|---|
| the accumulator | 2 × 74HC161, `ENP` = `ADVANCE` · `PB0`, cleared by `START` |
| the display | **2 × 74HC4511** — latch, decode and segment driver in one package. An octal digit is a BCD digit with `D` grounded. Clocked by `ADVANCE` · `START` |
| align, freeze | ½ 74HC74 and gates, one lamp |
| **the check counter** | 2 × 74HC161 on `ADVANCE` while armed, on `CLK_8K` while not; cleared by `START` (§5) |
| the previous port | 1 × 74HC175 — three of four, plus one for `ADVANCE` |
| the rules | ¾ 74HC86 and gates for the step rule, a 6-input NOR for `lcnt` = 0; ½ 74HC74 latches `ERR`, one lamp, sharing the reset key |
| | **≈ 9 packages, two displays, three lamps, one key** |

**Three of the nine are the cross-check** and none is in the way of the number:
pull the '175, the '86 and the second '161 pair and the card still counts
correctly, it just stops being able to say so. That is the right shape for a
check.

The '4511 is the part that makes octal free. It latches on `LE`, decodes
0–7 without a blanked state, and drives the segments directly, so the pass
strobe goes to two `LE` pins and there is no separate latch and no separate
driver. `counters.md` §1's sixteen LEDs off four '161 is the same card built
before anyone wanted to read the number at a distance.

**`OVF` is one lamp and it should never light.** Sixty-four busy ports would
be `100` octal and needs a third digit. Port 00 is *"idle: never fitted"*
(`protocol.md` §5), so the exchange cannot make more than 63 — `77` — and
the two digits hold the whole range with nothing wasted. The lamp is there
because a display that rolls to `00` when the exchange is at its busiest is
the one failure this card must not have silently.

---

## 8. It counts ports, not calls

The display is **busy ports**. A two-party call is two of them: `extensions.md`
§4's peg count pulses on *"the second latch write of a call"*, and `port.v`
takes `busy <= bsy_in` on each write. A call over a trunk is also two here —
the near line and the trunk port. **A caller on dial tone is one**, because a
source is listened to and is not written a latch pointing back.

So the number is not halveable. Dividing by two would be right for connected
calls, wrong for every caller in the middle of dialling, and would throw away
half the digit range for the privilege. The card shows what it measures.

**What this changes elsewhere:**

- **`counters.md` §4**, the paragraph beginning *"No call ever ends on the
  control bus."* Everything through *"no holding time"* is true of **this
  card and cable B** and should say so; the closing *"That is not a limitation
  of the card, it is the architecture"* is not true of the exchange, and the
  probe is the counter-example. §4's other three paragraphs — `DST` unread,
  `G` unread, answer is `E` inside the port — stand untouched.
- **`counters.md` §5**, *"Not this card."* The gate it asks for is §4 here.
  With `SCAN[2:0]` out, `extensions.md` §4's usage sample becomes an ordinary
  listener on the ribbon rather than *"one card beside the marker"*, and the
  erlang half stops being deferred.
- **`mainboard.md` §2.3.3 and §3.2** now carry `SCAN[2:0]`, and `fabric.md`
  §1.1, `fabric.md` §2 and `extensions.md` §2.2 have been corrected to name
  the conductor rather than a field in the word — the word could never have
  done the job, since a sixteen-bit word at 128 kHz is 125 µs and so is a
  visit. `mainboard.md` §9's `M` is still open, but it now looks **derivable
  rather than carried**: the marker does not receive it on a wire either
  (`marker.v`:469 reads it off `HA`), and any card with `SCAN[2:0]` can do
  the same with two '151 off cable A.
- **`observers.md` §5**, the port watch. Its live `BUSY`, `STALE` and class
  displays are off `PB` and have the same root problem; the same conductor
  fixes all three, and the ¾ '86 block-only match it specifies should be
  deleted rather than patched.
- **`extensions.md` §4** gains a second use of the same gate, and its
  *"600 counts to the erlang-hour"* arithmetic gives average holding time by
  division: with a 6 s sample period, **holding time in seconds = 6 × usage ÷
  calls connected**, both numbers already on the panel.

---

## 9. Not measured

- **The circuit.** §7 is a parts list by function. Nothing is drawn, no '4511
  segment currents are budgeted, and the '175-plus-'86 change detector has not
  been checked against `CLK_8K`'s edge with real cable skew.
- **The scanner group as conductors.** `mainboard.md` §5's skew and §7's
  crosstalk figures are written for a sixteen-way cable B and have not been
  re-derived for a twenty-six-way carrying twelve signals. `SCAN` is the
  slowest thing on either cable, but `ADVANCE` and `START` are **pulses**, and
  a spurious `ADVANCE` costs a whole pass — §5's lamp would report it, which
  is the argument for the lamp, not a substitute for the arithmetic.
- **What an `ERR` actually means in the field.** The lamp says the three
  signals disagreed at least once since the key was pressed. It does not say
  which, how often, or whether the pass on the display was one of the bad
  ones. A counter rather than a latch would say all three for one more
  package, and nothing here decides whether that is worth it.
- **The card checks its own tap and no one else's.** The cable is a daisy
  chain of ten connectors. An open *between this card's tap and a block*
  leaves the card reading a perfectly consistent `SCAN`, `ADVANCE` and `START`
  while that block's probe commutator is misaddressed — `ERR` dark, display
  wrong, and nothing here can see it. §5's rules are a check on the
  conductors **as they arrive here**, and the document should not be read as
  promising more.
- **The rule that was removed.** `lcnt[2:0]` ≠ `SCAN[2:0]` guarded the step
  rule's own '175 against failing open or stuck. That failure is real — it is
  a single point in the only detector the card has — and nothing now catches
  it. It was removed because it is not testable from outside and had no
  coverage; whether a self-check the bench cannot reach is worth ¾ of a
  package is a judgement this document does not make. The conductors' effect
  on `PB`'s own timing — `PB` is pulled low at the marker and tri-stated per
  block (`mainboard.md` §6) — is not considered at all.
- **Two masters.** `/CON` is tested here as a clean level. On the cable it is
  asynchronous to this card's `CLK_8K` and wants a synchroniser, exactly as
  `console.md` §12 says of the marker's own `/CON`.
- **A whole pass against moving traffic.** Every comparison in `tb_inprog` is
  made on a quiescent exchange. A pass takes about 8 ms and the truth moves
  during it, so the display is a sample, not a snapshot, and nothing here
  bounds the error when calls are being set up and torn down inside one pass.
  That is the measurement to make next, and `tb_stress` is where to make it.
- **What an operator does with it.** A number on a wall is not an instrument
  until somebody has watched it during a busy hour and said what it told them.
