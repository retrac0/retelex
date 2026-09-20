# The exchange — the console: a second master on cable B

`exch-features.md` §4 has the console as "a busy-lamp field … and keys that drive
the marker's control bus by hand", and says to build it first. `exch-mainboard.md`
§2.3 calls that bus multi-master and gives the console one conductor, `/CON`:
"the console has the bus; the marker's drivers go high-impedance. One '244
enable." `exch-marker.md` §8 lists a second master as not modelled.

This document is the console as a master: how it takes the bus from a marker
that is using it, and the two things an operator does with it that a marker
never does — **forced release** and **service observing**. The lamp field is a
listener and is not here.

> **Status: proposed; the arbitration and both functions measured in RTL.**
> `exrtl/rtl/console.v` is the console, `marker.v` has the yield, and
> `exrtl/tb/tb_console.v` runs sixteen lines of random traffic against a console
> writing hundreds of times faster than an operator can, with a listener on the
> bus checking every word either master believes it sent. It passes under
> Verilator and Icarus. `make console-naive` is the control: `/CON` as first
> written, measured losing calls (§2.1). The parts are a sketch; nothing has been
> drawn and nothing has been on a bench. The bench runs the release detectors at
> an eighth of their real time, as every `exrtl` bench does, and §7 says which
> figures scale.

---

## 1. The console has no verbs

Two pairs of octal wheels, two toggles and two keys, and what they make is the
marker's own sixteen-bit word (`exch-mainboard.md` §2.3.1) — `G`, the spare,
`DST`, `SRC`, `BSY`, `CLM` — out of two 74HC165. **Everything the console does is
a latch write.**

| key | the word | what it is for |
|---|---|---|
| **WRITE** | as the wheels and toggles have it: *`DST` listens to `SRC`* | bring-up step 3 (`exch-fabric.md` §7); a patch by hand; **service observing** (§5), which is this key with a sink's port on the `DST` wheels |
| **RELEASE** | the same `DST`, and **`SDATA` held low for the second byte**: `SRC` 00, `BSY` 0, `CLM` 0 | **forced release** (§3). The word a call's own end would have written, had anyone written it. **One gate on the serial stream**, enabled by the bit counter's top bit |
| **HOLD** | none — a toggle | keep the bus (§2.4) |

`G` is wired high and the spare low. A console cannot send a word the marker
could not have sent, and a block cannot tell whose word it is.

---

## 2. Taking the bus: `/CON` is a request, and there is no grant

### 2.1 Measured: what one '244 enable does

As first written, `/CON` falling turns the marker's drivers off, at once, and the
marker is not told. `make console-naive` builds exactly that and offers it the
traffic of §7:

| | console quiet | console writing |
|---|---|---|
| calls answered | CTRL_Q_ANS | **CTRL_W_ANS** |
| callers given no dial tone in 600 ms | CTRL_Q_NODT | **CTRL_W_NODT** |
| marker writes the blocks never saw | 0 | **CTRL_LOST** of CTRL_SAID |
| runt `WR` pulses | 0 | CTRL_RUNT |

Three things go wrong, and only the first is obvious:

- **A word cut short is a lost write.** The marker's sequencer believes it sent
  it. A lost dial-tone write is a caller who waits for ever; a lost half of a
  connect pair is a one-way call.
- **A `WR` cut short is a runt clock into a '273.** What a latch does with half
  a clock pulse is not in the data sheet.
- **The marker goes on scanning, and reads the wrong block.** The block that
  drives `PB` is the block the shift register names (`exch-rtl.md`,
  "steering the probe costs a visit") — and the shift register now holds the
  *console's* word. Every visit until the marker next steers the probe pairs
  the right port's hook, off `HA`, with some other port's `BUSY` and class.

### 2.2 The rule

**The marker:**

1. **Honours `/CON` between words and never inside one.** A word already in
   flight when `/CON` falls finishes, `WR` and all. Then the '244 goes off.
2. **Holds while it is off.** The write sequencer starts nothing; every visit
   from `/CON` falling is distrusted, so the scanner repeats it instead of
   stepping. This is the hold the serial bus already made the scanner have
   (`exch-rtl.md`): `/CON` is one more term in it.
3. **Steers the probe again when `/CON` rises**, before any visit counts. It is
   the "probe dirty" request a block turn-over already raises.

**The console:** opens every tenure with **silence** — `/CON` low, its own '244
still off — for longer than any word the marker can send. Then sixteen bits,
`WR`, and both lines let go together.

```
 /CON  ~~\________________________________________________/~~~~
 '244  ___________________/~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\_____      the console's
          | 32 periods, silent | 16 bits            | WR |
                                                                       766 µs at 64 kHz
```

**In parts, at the marker: one flip-flop** — set by `/CON` low *and* the
sequencer idle, cleared by `/CON` high, its output the '244's enable, the
sequencer's hold and the scanner's. Half a '74 and two gate inputs.

### 2.3 Why no grant

A grant line would let the console start the moment the marker let go. It is
not worth its conductor:

- **The console must work with no marker at all.** It is the bring-up tool, and
  `exch-fabric.md` §7 brings it up two steps before the marker. A console that
  waits for a grant needs a pull that reads "granted" when nobody is there to
  grant, and then a marker that is fitted but dead grants too. **A console that
  waits out a silence behaves identically with a marker, without one, and with
  one that has stopped.**
- **Cable B has one spare conductor** and two claims on it already — `/HUNT_INH`
  (`exch-basebandcard.md`) and the scanned port's `M` (`exch-mainboard.md` §9).
- **What the silence costs is half a millisecond**, on an event that happens
  when a person presses a key.

**The one constraint: the silence outlasts the marker's longest word.** That is
16½ `SCLK` periods at the marker's rate. `exch-mainboard.md` §2.3 lets the marker
run `SCLK` anywhere from 512 kHz down to 64 kHz — 32 µs to 258 µs — and the
console's silence is 32 periods of `TX_CLK`, **500 µs: twice the slowest**.

**Why finish the word, and not cut it and send it again.** A write is idempotent
(`exch-mainboard.md` §7: a second `WR` "writes the latch a second time, with the
same data"), so the marker could be cut off at once and repeat the word when it
gets the bus back. The lost write would be cured. The runt `WR` would not.

**Two rates on one bus, on purpose.** The marker shifts at 512 kHz and the
console at 64, off `TX_CLK`. The blocks' shift registers "have no phase, only
content" (`exch-mainboard.md` §2.3.2), so nothing has to agree.

### 2.4 HOLD

The toggle keeps the tenure open after the word, or opens one with no word.
**With a marker fitted, that stops the marker** — and nothing else. Calls in
progress carry on, bit for bit (§7), because nobody is in charge of a call.
Nothing new is set up: no dial tone, no register, no nail re-made after a
release (`ex-extensions.md` §3.1). Words keyed during a hold go out with no
silence; the bus is already the console's. Dropping the toggle, the marker
steers its probe and carries on from the port it stopped at.

It is the state bring-up steps 3–5 are done in, and a maintenance one: freeze
the marker and look. **A lamp on `/CON`**, because an exchange left in HOLD gives
no dial tone and says nothing about why.

### 2.5 What a word costs the marker

A tenure is 766 µs, **less than the 1 ms the scanner spends on one block**, and
the scan it lands in is that much longer. A scan of 64 ports is 9.0 ms with the
console quiet; with a console word every 16 ms on average — a rate no operator
reaches — 9.2 ms mean, SCAN_WORST worst. Against that, the origin's guard is
128 ms and a flood lasts seconds (`exch-network.md` §3).

---

## 3. Forced release

`/RESET` clears every latch in the exchange and drops every call. RELEASE clears
one.

```
 RELEASE 20       20's latch: listening to 00, BUSY clear.  20 hears idle
   + one release time      20's E detector, which was high, times out; until then 20 still reads busy
                            (exch-marker.md 5.2) and nothing may seize it
   + one scan     20 is off hook with an idle latch: a CALL REQUEST.  A register, and dial tone
```

Measured: dial tone 37 ms after the key, where the bench's release time is 32 ms
— in the exchange, 256 ms and a scan. It is exactly what the party left off-hook
at the end of any call gets (`exch-marker.md` §5.1), by the same path. **The
console writes one word and the port's own supervision does the rest**; nothing
in the marker knows a release was forced.

### 3.1 One end is not enough — measured

With 20 released and at dial tone, **21 is still listening to 20, and still
busy.** 21's `E` is 20's *hook*, straight off the `A` highway, not anything in
20's latch — so no write at 20 can make it fall, and 21's port releases only
when 20 hangs up or 21 does. Until then 21 hears 20, who can no longer hear 21:
20's dialling, 20's next call.

**A call is released at both ends: two words.**

### 3.2 Finding the other end: the watch

Latches cannot be read back, so the console cannot ask who 20 is talking to. It
can only have been listening when the marker said so. **The watch** is a listener
on the same three wires — two '164, a '688 on `DST` against the `DST` wheels and
`G`, a '574 clocked by `WR`, six LEDs in two octal groups:

- it shows **what the watched port's latch was last written with**. For a caller
  that is the called port; for a called port it is the caller, which makes it a
  call trace. Measured: armed on 20 before 20 called 21, it read `21`, `BSY` 1;
- **it must be armed before the call is set up.** A call already up when the
  wheels are turned to it is invisible, and the operator is left with the lamp
  field and a sink (§5): listen to each busy port in turn;
- **a port clears its own latch and tells nobody.** The watch is stale once the
  port's `BUSY` lamp is out;
- across a trunk it names the trunk port, and nothing beyond it.

### 3.3 A port held by nothing

The case a maintenance key is really for. A latch written `BUSY` by hand with
both phones on hook — a slip at the console, or a marker fault — is held for
ever: release is on a *fall* (`exch-marker.md` §5), and nothing here ever rose.
Measured: still held after 150 ms; one RELEASE, free; the line then lifts and
gets dial tone.

**On a trunk port** RELEASE is the word the marker itself lets a trunk go with.
If the far end is still holding forward `A` up, the scanner's next visit finds
`M` high on a free trunk, which is a seizure arriving — correctly.

---

## 4. Measured: make-busy by a latch write does not stick

Writing a line `00` with `BUSY` set looks like a busy-out key, and while it lasts
it is one: a caller to it gets cannot-complete, and the mark outlasts that call.
**But the first time the line's own phone is lifted and replaced, the port
releases itself** — its `M` rose and fell, which is a release — and the mark is
gone. The same is true of `ex-ss0.md`'s `BLOCK`, which marks a trunk the same way
and is cleared by the far end's next seizure and release.

**Out of service is the switch on the card's word** (`ex-extensions.md` §2.2):
no word, so the port reads unequipped, and nothing at the port can undo it.
The console is not the tool.

---

## 5. Service observing

### 5.1 The sink card

Half a line card: **the receive half** — a CVSD decoder, its filter, a headphone
amplifier and a jack — and three ties.

| pin | tied | so |
|---|---|---|
| `A_TX` (`M`) | low | never off hook: never a call request, never a seizure, and its own `M` can never release it |
| `/ANS` | low | never rung, never sends ringback (`ex-extensions.md` §2.3) |
| the word | none | **to the marker it is an empty slot**: never hunted, and cannot-complete if dialled |

To the fabric it is a port with a latch like any other, and **only the console
ever writes it**. It is the converse of `exch-features.md` §6's source, and it is
also `ex-extensions.md` §3.1's "speaker on a radio" with the nail taken off.

### 5.2 The write

**WRITE, with the sink on the `DST` wheels, the observed port on the `SRC` wheels
and `BSY` up.** The fabric already lets any number of latches point at one slot
(`exch-features.md` §6: 63 listeners on one source), and the observed port's own
latch is not touched. Measured, on a call between 20 and 21 with a sink pointed
at each:

| | |
|---|---|
| the call, bit for bit, across both writes | 2 466 bits each way, **0 wrong** |
| what each sink hears | its party's transmit, bit-exact |
| the observed ports' `BUSY`, and who they hear | unchanged |
| 20 hangs up | **its sink clears itself** one release time later: the sink's `E` is 20's hook, and it fell |
| 21, still off hook | its sink still hears it — into dial tone, and its next call |
| a sink pointed at a line on hook | **waits**: `E` never rose, so nothing falls. It hears the line's next call and lets go at the end of it |
| dialling a sink's number | cannot-complete |

- **One party a sink.** A sink hears what the observed port *sends*. Both sides
  of a call is two sinks, one in each ear. CVSD does not mix, and this needs no
  mixing.
- **No barge-in**, for the same reason: speaking into a call is a conference
  bridge (`exch-features.md` §7), not a latch.
- **A port being rung is sending ringback**, so that is what its sink hears.
- **A call over a trunk** is observed at the trunk port, which sends what the
  far party says.
- **Two adjacent slots by convention** — 76 and 77 in the bench, beside the test
  lines `ex-extensions.md` §1 suggests at 75–77. A suggestion, not a rule.

### 5.3 It cannot be detected

Not a click, not a level change, not a bit: the observed call is the same
2 466 bits with the sink as without. That is a property of a fabric that
switches bits and fans out free, and it is why RELEASE and WRITE belong behind
the same lock as `/RESET`.

---

## 6. Parts — a sketch

| | parts |
|---|---|
| the word | 2 × 74HC165, from four octal wheels and two toggles |
| the tenure | a 6-bit count of `TX_CLK` — 32 silent, 16 bits, `WR` — ≈ 2 packages and a package of gates |
| taking and keeping the bus | 1 × 74HC74: the tenure, and RELEASE; ½ 74HC14 on the keys |
| drivers | 1 × 74HC244 on `SDATA`, `SCLK`, `WR`, enabled after the silence; `/CON` from the tenure flip-flop |
| | **≈ 7 packages** |
| the watch (§3.2) | 2 × '164, '688, '574: **≈ 4**, the '164 pair shared with a lamp field |
| at the marker | **½ 74HC74** and two gate inputs (§2.2) |
| a sink card | a line card's receive half. Nothing in the exchange |

---

## 7. Measured — `make console`, `make console-naive`

Sixteen lines calling each other at random for five seconds, twice: once with
the console quiet, once with it writing a word every 2–30 ms — pointing the two
sinks at random lines and releasing them — **two words in three timed to land
inside a word the marker had already begun**, and half of those inside a latch
write.

| | console quiet | console writing |
|---|---|---|
| lifted / answered | Q_TRY / Q_ANS | W_TRY / W_ANS |
| dial tone after the lift, mean / worst | Q_DT ms / Q_DTW | W_DT ms / W_DTW |
| no dial tone in 600 ms | Q_NODT | W_NODT |

| over the run | |
|---|---|
| console words | N_CON, N_AIMED aimed; `/CON` fell inside a marker word **N_MID** times, **N_MIDWR** of them a latch write |
| marker writes | N_MK. The blocks never saw: **0**. Saw mangled: **0** |
| console words the blocks saw wrong | **0** |
| clocks with both '244s on; runt `WR` pulses | **0**; **0** |
| one-way patches; two callers on one line | 0; 0 |
| held afterwards | nothing |

Then, scripted: forced release of one end and of both (§3), a port held by
nothing (§3.3), make-busy (§4), observing (§5) and HOLD — 150 ms with the marker
stopped, a call carried 10 257 bits each way with 0 wrong, a caller given nothing
until the toggle dropped and dial tone 7 ms after. **40 checks.**

**What scales.** The bench runs the port's release detectors at 1 ms and 32 ms
where the exchange has 16 and 256, and dials at 20 ms a pulse. Every figure
quoted as "a release time" scales with it; the bus figures — 766 µs, the scan,
every count in the second table — are the exchange's own, at its own 4.096 MHz.

---

## 8. What this changes elsewhere

- **`exch-mainboard.md` §2.3**, `/CON`: a request honoured between words, not an
  enable; and §7's glitch table gains a row — `/CON` low is a stopped marker,
  costing nothing in progress.
- **`exch-marker.md` §8**, "a second master on the control bus is not modelled":
  it is now.
- **`ex-counters.md` §8**, the console's writes: a counter card counts them as
  the marker's. **A RELEASE is the *trunks let go* pattern exactly**, and an
  observe write whose `SRC` is a trunk port matches *calls over a trunk*. At an
  operator's rate that is a handful a day. If it ever matters, the spare bit 14
  could mark a console's word; it is not spent here.

---

## 9. Not measured

- **The circuit.** The tenure counter's decode, `WR` placed clear of `SCLK` off
  `TX_CLK`'s two phases, the key's synchroniser, and the marker's flip-flop
  against its sequencer's idle state have not been drawn.
- **`/CON` as a wire.** In the bench the two masters share one clock. On the
  cable `/CON` is asynchronous to the marker's sequencer and wants a synchroniser
  there; the silence has 240 µs in hand to pay for it.
- **The free-running `SCLK` strap** of `exch-mainboard.md` §2.3.2 with two
  masters on the bus.
- **Two consoles.** `/CON` would want to be open-drain and the silence is not an
  arbiter between them.
- **A hold under traffic, for long.** In 74HC the sequencer simply waits. The
  model's marker queues its writes fifteen deep, and a long hold under heavy
  traffic would overrun that queue — a property of the model, which the bench
  avoids by holding with two lines up.
- **Forced release against a call being set up.** Releasing a port that is
  dialling turns its dial tone off and nothing else — the register is still
  attached and the call completes. Reasoned from `marker.v`, not run.
- **The sink as a card**: the decoder half alone, with no encoder beside it.
- **The watch across a hub**, where tie-through and resolver writes name trunk
  ports many times a call.
