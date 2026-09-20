# The exchange — the console: a second master on cable B

`exch-features.md` §4 has the console as "a busy-lamp field … and keys that drive
the marker's control bus by hand", and says to build it first. `exch-mainboard.md`
§2.3 calls that bus multi-master and gives the console one conductor, `/CON`:
"the console has the bus; the marker's drivers go high-impedance. One '244
enable." `exch-marker.md` §8 lists a second master as not modelled.

This document is the console as a master: how it takes the bus from a marker
that is using it, and the things an operator does with it that a marker never
does — **forced release**, **service observing**, **connecting two lines by
hand**, and **reading a port back**. The lamp field is a listener and is not
here, except where the console's own supervision overlaps it (§7.3).

> **Status: proposed; the arbitration, the four functions and the supervision
> measured in RTL.** `verilog/rtl/console.v` is the console, `marker.v` has the
> yield, and `verilog/tb/tb_console.v` runs sixteen lines of random traffic
> against a console writing hundreds of times faster than an operator can, with
> a listener on the bus checking every word either master believes it sent; then
> it works a board by hand — release, observe, connect, dial, supervise — for
> **87 checks**. It passes under Verilator; the Icarus run of the same bench,
> `make iv-console`, was still going when this was written. `make console-naive` is
> the control: `/CON` as first written, measured losing calls (§2.1). The parts
> are a sketch; nothing has been drawn and nothing has been on a bench. The
> bench runs the release detectors at an eighth of their real time and the
> register's no-digit timeout at a sixteenth, as §10 says; the bus figures are
> the exchange's own. **The ring source of §6.3 is new here and is three ties on
> a blank card; it has no circuit and no bench either.**

---

## 1. The console has no verbs

Two pairs of octal wheels, two toggles for the word's own flags, three keys and
two toggles more — HOLD and BOTH — and what they make is the marker's own
sixteen-bit word (`exch-mainboard.md` §2.3.1) — `G`, the spare,
`DST`, `SRC`, `BSY`, `CLM` — out of two 74HC165. **Everything the console does
is one word on those same three wires.** Two keys end the word with `WR`, which
is a latch write. The third does not, and a word with no `WR` writes nothing at
all: it steers the probe, which is exactly how the marker reads a port
(`exch-marker.md` §4, `marker.v`).

| key | the word | what it is for |
|---|---|---|
| **WRITE** | as the wheels and toggles have it: *`DST` listens to `SRC`* | bring-up step 3 (`exch-fabric.md` §7); a patch by hand; **service observing** (§5), which is this key with a sink's port on the `DST` wheels; **one leg of a connection** (§6) |
| **RELEASE** | the same `DST`, and **`SDATA` held low for the second byte**: `SRC` 00, `BSY` 0, `CLM` 0 | **forced release** (§3). The word a call's own end would have written, had anyone written it. **One gate on the serial stream**, enabled by the bit counter's top bit |
| **PROBE** | the same word, **and no `WR` at all** | **supervision** (§7.2). The block the word names drives the probe bus, and the console reads `BUSY` and the card's word out of the octet that follows. Nothing is written, because `WR` is what writes |
| **BOTH** | a toggle: the key runs **twice in one tenure**, the second word with the two port fields crossed | **a connection** — WRITE + BOTH is `DST ← SRC` and `SRC ← DST` (§6). **A release of both ends** — RELEASE + BOTH is §3.1's two words. **Both ends read** — PROBE + BOTH |
| **HOLD** | none — a toggle | keep the bus (§2.4) |

`G` is wired high and the spare low. A console cannot send a word the marker
could not have sent — a probe word is the marker's own probe steer — and a block
cannot tell whose word it is. There is a fourth key, **ARM**, which belongs to
the watch (§3.2) and touches the bus not at all: it clears the SEEN lamp.

**BOTH is not a second word stored anywhere.** The serial stream is already cut
by the bit counter: that is RELEASE's one gate. BOTH is the same cut one field
wider — bits 13–8 and 7–2 are the two port fields, and which pair of wheels
feeds which is the pass number. **≈ 1½ packages**: a '153 on the stream and a
flip-flop that says *second*.

### 1.1 Every conductor the console touches

| signal | cable | the console is | for |
|---|---|---|---|
| `SDATA`, `SCLK`, `WR` | B | **a master**, through its own '244, **only inside a tenure** | every key: §1's words |
| `/CON` | B | a driver, low for the whole tenure and high at every other instant | taking the bus, §2 |
| `SDATA`, `SCLK`, `WR` | B | **a listener**, at every instant, its own words included | the watch, §3.2 |
| `PB0`, `PB1` | B | a listener, in the octet after a PROBE word | `BUSY` and the card's word, §7.2 |
| `HA[0..7]` | A | a listener, every frame, for ever | the hook of either end, §7.2 |
| `SLOTQ[2:0]`, `HCLK`, `TX_OCT` | A | a listener | which cell and which octet, for the two rows above |
| `/RESET` | B | a driver **if** the console carries the key bring-up step 4 asks for (`exch-fabric.md` §7) — open-drain, because the marker and the power-on circuit drive it too | clearing every latch at once. **Not measured**, and the one console control that is not one port's business |
| `HC[0..7]`, `FILL`, `RBT`, `TICK`, the clocks | — | **not connected** | the console has no port, no latch, no number and no bit stream |

**It drives nothing on cable A**, and nothing on cable B outside a tenure. Its
own shift clock is `TX_CLK`'s rate and has no phase to keep (§2.3); the only
thing it must know about the exchange's time is which cell and which octet, and
those are three signals and a strobe.

---

## 2. Taking the bus: `/CON` is a request, and there is no grant

### 2.1 Measured: what one '244 enable does

As first written, `/CON` falling turns the marker's drivers off, at once, and the
marker is not told. `make console-naive` builds exactly that and offers it the
traffic of §10:

| | console quiet | console writing |
|---|---|---|
| calls answered | 10 | **2** |
| callers given no dial tone in 600 ms | 0 | **10** |
| marker writes the blocks never saw | 0 | **30 of 179** |
| … and writes they saw mangled | 0 | **5** |
| runt `WR` pulses | 0 | 1 |

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
progress carry on, bit for bit (§10), because nobody is in charge of a call.
Nothing new is set up: no dial tone, no register, no nail re-made after a
release (`ex-extensions.md` §3.1). Words keyed during a hold go out with no
silence; the bus is already the console's. Dropping the toggle, the marker
steers its probe and carries on from the port it stopped at.

It is the state bring-up steps 3–5 are done in, and a maintenance one: freeze
the marker and look. **A lamp on `/CON`**, because an exchange left in HOLD gives
no dial tone and says nothing about why.

### 2.5 What a word costs the marker

| the tenure | measured | against |
|---|---|---|
| one word — WRITE, RELEASE | **766 µs** | the scanner spends 1 ms on one block |
| two words — WRITE + BOTH, RELEASE + BOTH | **1 031 µs**, the two writes **266 µs** apart | one silence, not two: the second word wants none, the bus is already the console's |
| PROBE: a word and the octet that answers it | **951 µs** | the octet is 125 µs, and up to another 125 waiting for its edge |
| PROBE + BOTH | **1 499 µs** | **the only thing the console does that is longer than a block's visit** |

A scan of 64 ports is 9.02 ms with the console quiet; with a console word every
16 ms on average — a rate no operator reaches — 9.19 ms mean, 10.75 ms worst.
Against that, the origin's guard is 128 ms and a flood lasts seconds
(`exch-network.md` §3).

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

Measured: dial tone 35 ms after the key, where the bench's release time is 32 ms
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

**A call is released at both ends: two words.** That is the BOTH toggle (§1):
**RELEASE + BOTH** sends them in one tenure, `DST ← 00` and then `SRC ← 00`, and
measured it frees both ends with one key. Keyed one at a time it is two tenures
and the wheels turned in between, which is how the fault above is made.

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

**A pair of latches pointed at each other with both phones on hook is this
twice**, and §6.2 measures it: it is the reason a connection has to be made in
the right order.

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

**But it is exactly the tool for one line: the operator's own** (§7.1). A
make-busy written on the operator's port before the handset is lifted keeps the
marker from treating that lift as a call request, and it goes with the handset —
measured, and the one place this document asks for the write that does not
stick.

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
**Its own converse is the ring source of §6.3**: the same three ties with `A_TX`
the other way up, and no decoder behind them.

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

## 6. Connecting two lines

`ex-extensions.md` §3.1 says the console "can still point two latches at each
other by hand, as bring-up step 3 does. That is a call, and it clears when it is
released." That is true of the latches and **not true of the call**, because
nothing in it rings. This section is the whole of it: the word pair, what it
does at each combination of hooks, and the card that makes two idle phones ring.

### 6.1 A connection is two latches, so it is two words

A port's '273 holds **who it listens to** and nothing else
(`exch-protocol.md` §3). Hearing is one-way, so a conversation is two latches,
and the marker itself sets one up with two writes (`exch-marker.md` §4). The
console's **WRITE + BOTH** is those two writes:

```
 wheels   DST = 20   SRC = 21   BSY up
 word 1   20 <- 21, BUSY            the tenure's first sixteen bits
 word 2   21 <- 20, BUSY            the same wheels, port fields crossed -- 266 µs later
```

**Both words are inside one tenure.** `/CON` stays low across them, so the
marker's drivers are off for both and **no word of the marker's can land between
them** — measured, with a bus listener checking every word either master sent.
For 266 µs one end hears the other and is not heard back; at 64 kb/s that is
seventeen bits, and neither party is off hook yet in the sequence below.

### 6.2 Measured: a pair does not ring

| both phones … | what happens |
|---|---|
| **on hook** | **neither rings, and both are busy for ever.** `E` at each end is the *other end's hook*, and neither has one up, so the ring condition (`exch-marker.md` §5) is never met — and no detector ever armed, so nothing will ever fall to release them. It is §3.3's port held by nothing, twice. Measured: still held at 150 ms; RELEASE + BOTH frees both |
| **one off hook** | the off-hook end rings the other, in cadence, and hears ringback from it: `channel-cards.md` §1's hotline, made by hand. The other answering is a call |
| **both off hook** | they are talking, from the frame after the second word. This is the useful one, and §6.4 is how both come to be off hook |

So **the pair is the last step of a connection, not the first**. Something has
to ring the two phones and get them answered, and the exchange has exactly one
way to ring a port: point it at something whose `M` is up.

### 6.3 The ring source: a blank card with three ties

| pin | tied | so |
|---|---|---|
| `A_TX` (`M`) | **high** | a port pointed at it is being called: on-hook, it **rings**; off-hook, its `E` never falls, so it is **held** |
| `/ANS` | low | it is never rung itself |
| the word | none — **the pin left open** | unequipped: never hunted, never dialled, and **its `M` is not a call request** |
| `C_TX` | `FILL`, or a looping "please hold" (`exch-features.md` §3) | what a party parked on it hears |

**It is `exch-features.md` §6's source with `A_TX` the other way up**, and that
document's reason for tying `A_TX` low is exactly what makes this card need
care: "a source cannot hold `M` high to say it is alive, because `M` high on an
idle port is a seizure to the scanner". A seizure is `M` high on a **free port
of a class the marker serves**; a port that sends no word has no class, and the
marker passes over it. Measured: a ring source at 75 with its `M` permanently up
is never seized — nothing is ever written to it and no register is ever handed
to it — reads not-busy on the probe, and gives cannot-complete when dialled. It
is not *hunted* for the same reason the sink is not, a hunt comparing a class it
does not have; no hunt is dialled in this bench.

> **The word pin must be left open, not grounded.** A plain line card grounds it,
> which reads all ones and means *a line with no options* (`ex-extensions.md`
> §2.2) — and a permanently off-hook line is a call request at every scan, which
> would hold a register for ever. It is a blank card, not a line card.

| pointed at it | measured |
|---|---|
| a phone on hook | **rings**, in cadence, and hears the source |
| it answers | ringing stops; it is **parked**: busy, held, hearing the source. Still held at 150 ms, because nothing can fall |
| it hangs up | its own `M` falls: the port releases itself by the ordinary rule, and the park is over |
| any number of ports at once | free: the fabric fans out (`exch-features.md` §6) |
| dialled by a subscriber | cannot-complete |

**Parts: none.** A blank card, three ties, and whatever makes the sound if it is
to be more than silence. It is the sink of §5.1 with `A_TX` the other way and no
decoder, and the two belong together in the wiring field: **75 the ring source,
76 and 77 the sinks**, by the same convention that put the sinks there.

### 6.4 The sequence

```
 RING   20      WRITE        DST 20  SRC 75  BSY        20 rings; answers into the source
 RING   21      WRITE        DST 21  SRC 75  BSY        21 rings; answers into the source
                                                        the two hook lamps (§7.2) say when
 PAIR   20 21   WRITE+BOTH   DST 20  SRC 21  BSY        they are talking
```

Measured, end to end: both rang, both answered, both were held on the source
while the other was rung, and across the pair the call ran **1 920 bits each
way with 0 wrong**. Then 20 hung up, 21 was released by the ordinary rule one
release time later and got dial tone, and nothing was left held.

- **The order matters and nothing enforces it.** Pairing two ports that are not
  yet off hook is §6.2's first row, and it is silent: no tone, no lamp, no
  refusal. The remedy is the hook lamps, and the habit.
- **Nobody is in charge afterwards.** The pair is an ordinary call from the
  instant it is made: either party hanging up releases both, and the console has
  nothing left to do. It is not remembered anywhere. A connection that must
  survive a release is a **nail** (`ex-extensions.md` §3.1), which is two cards'
  jumpers and not a console word.
- **A party who never answers rings for ever.** Nothing times a ringing port
  (`ex-groups.md` §2.6). The operator releases it.
- **Either party may be a trunk channel, a sink or anything else with a latch.**
  The word does not know what is at the far end; §7 is the same sequence with
  the operator's own phone in the place of the ring source.

---

## 7. Dialling a port from the console, and supervising both ends

The operator's phone is a subscriber line (§8) and dials like one: lift, dial
`h s`, and the marker does the rest. **That is the ordinary way to call a port,
and the console has no part in it.** Three things it cannot do, and each is why
this section exists:

- it cannot reach a port with no number and cannot reach one with no word.
  00–17 are never dialled (`exch-protocol.md` §5) — a trunk channel, a tone, the
  position at 04 itself — and a sink or a ring source answers any dial with
  cannot-complete, because a card that sends no word reads unequipped;
- it cannot hold one call and start another. Once the operator's latch is
  written that port is busy, and **the marker will not give a busy port a
  register**: the second leg of a connection has to come from the console;
- it cannot ring a port that is busy, out of service or in a hunt group's
  shadow, which is most of what an operator is asked to do.

### 7.1 The call, and the order to do it in

**A call from the console is WRITE + BOTH with the operator's own port on the
`SRC` wheels.** It is §6's pair, made while one of the two phones is the
operator's:

```
 the operator's phone ON HOOK

 CALL 20        WRITE+BOTH   DST 20  SRC 04  BSY     20 <- 04 and 04 <- 20.  Nothing rings yet
 lift                                                04's hook is 20's E: 20 RINGS, and the
                                                     operator hears ringback out of 20's own cell
 20 answers                                          they are talking

 SECOND LEG                                          04 could not have dialled this
 RING 21        WRITE        DST 21  SRC 04  BSY     21 rings.  20 still hears 04: one source,
                                                     any number of listeners
 21 answers                                          both parties hear 04; 04 hears 20

 HAND OVER
 PAIR 20 21     WRITE+BOTH   DST 20  SRC 21  BSY     they hear each other
 DROP           RELEASE      DST 04                  the operator is out of it, and the call stands
```

Measured, every line of it: 20 rang when the handset came up and not before;
both lines heard the operator bit for bit (**1 920 bits each, 0 wrong**); the
pair carried the call the same way; after the release the two were still talking
and still busy with no console and no operator in the call; and 04, off hook
with a cleared latch, was a call request like anyone's and got dial tone.

**Ringback here is `FILL`.** The bench fits no ringback card, so what the
operator hears while 20 rings is the silence `mvp-ex.md` describes; the `RBT`
substitution itself is `exch-fabric.md` §3.5's and is measured elsewhere. What is
measured here is that 20 was being rung, and by which hook.

**Patch first, then lift.** The order is the whole of the interface, and the
reason is the register pool:

| | measured |
|---|---|
| **patched, then lifted** | `M` rises on a port that is already busy, which is not a call request. **No register, no dial tone**, and the position is a talking port and nothing else |
| **lifted, then patched** | the lift was a call request: dial tone, and **a register out of the pool**. The console's word patches the port anyway, and the register goes on watching that hook until its own no-digit timeout — 594 ms in the bench, **ten seconds in the exchange** (`exch-marker.md` §5.1). It then lets go with an event word, which writes nothing, so the patch survives it |

An operator who habitually lifts first takes one register out of a pool of two
or three for ten seconds at a time (`exch-marker.md` §6). **The cure, if the
handset must be up first, is §4's make-busy on the position's own line** —
`WRITE`, `DST` = the position, `SRC` 00, `BSY` up — measured: no register, no
dial tone, the console rings from it as usual, and the mark goes when the
handset does.

> `exch.py calls`, the other model, gives a caller who dials nothing
> cannot-complete at the timeout. A marker that did that would write over the
> console's patch — the mark above is the safe habit under either model, and the
> difference between the two is `exch-marker.md` §8's business, not this
> document's.

### 7.2 Supervising both ends: what the console can read

Three read-backs, and they are not the same kind of thing:

| | what | where from | when | needs the marker? |
|---|---|---|---|---|
| **hook** | the port's `M` — off hook, and what the other end of its call sees as `E` | `HA[h]` in the port's own cell, **cable A** | **every frame, 15.6 µs**, for ever | **no** |
| **`BUSY`, and the card's word** | busy, and what the card says it is (`ex-extensions.md` §2.2) | `PB0`, `PB1`, in the octet after a **PROBE** word | once a tenure, 951 µs | no — and it stops the marker while it reads |
| **who a port listens to** | the last word written to its latch | the watch (§3.2), on cable B | only when somebody writes it | no |

**The hook, of both ends, all the time.** Two '151 on `HA[0..7]` picked by the
two block wheels, two flip-flops clocked when `SLOTQ` reaches the slot wheels —
the same bit, in the same cell, that the marker's probe reads. Measured: a phone
lifting moved the lamp **13 µs later**, inside one frame, and it went on doing it
with the marker stopped under HOLD. It is the supervision the console has at
bring-up step 2, before there is a marker at all.

**`BUSY` and the class, on demand.** `exch-mainboard.md` §2.3.2: the block that
drives `PB` is the block the shift register names. A console word names the port
on the `DST` wheels, so **a word with no `WR` steers the probe bus to it** and
the console reads what the marker reads at a visit. Measured:

| PROBE on | `BUSY` | the word |
|---|---|---|
| a free line | 0 | a line |
| both ends of a call, with PROBE + BOTH | 1, 1 | a line, a line |
| an empty slot in a fitted block | 0 | none |
| a sink (§5.1) | 0 | none |
| the ring source (§6.3) | 0 | none — **and yet its hook lamp is up**: an off-hook port that no hunt will ever take, because a card with no word has no class (§6.3) |

and **not one `WR` pulsed**: the call being probed did not notice, and nothing in
the exchange was written.

**Why the read is inside the tenure.** The marker re-steers `PB` at every block
turn-over, about every millisecond. A console that sent its word and then looked
would be reading whatever block the marker had moved on to. Holding the bus for
the octet after the word costs 125–250 µs and makes the reading unambiguous by
construction — the same argument `hookbusy-display.md` §3 makes for its row
decode.

**What cannot be read at all: a latch.** There is no read-back path from a '273,
which is why §3.2's watch exists and why it has to be armed first.

### 7.3 With a lamp field beside it

`hookbusy-display.md` is 64 hook lamps off cable A and eight busy lamps off
`PB0`, and **its busy row follows whatever word is on the bus** — including the
console's. So a console fitted beside that panel already has both read-backs:
press PROBE and the panel's busy column is the console's block; hold HOLD and it
stays there, because the marker is stopped and the last word on the bus is the
console's. **Then the console needs no cable A tap of its own** and §9's
supervision packages go. A console built alone needs them.

---

## 8. The operator at 04

### 8.1 What port 04 is

**A plain line card with a phone on it, in slot 4 of block 0** — and nothing
else. It has a port circuit, a latch, two release detectors and a `BUSY` bit
like every other port; it rings, it answers, it can be observed, released and
made busy from the console like every other port; and `exch-protocol.md` §5's
map is the only place in the exchange the number appears.

| | |
|---|---|
| **the card** | any station card: an FXS card or a CVSD line card (`channel-cards.md`). A plain one, with the word's '165 unfitted, is a line with no options |
| **its word** | *line*, today with class *operator* so that the 0 hunt finds it (`exch-marker.md` §1). Under `ex-groups.md` §2 that class goes: it is a plain line, and a second position is a card that **answers to** the pilot |
| **`/ANS`** | open. It is a phone and it rings in cadence |
| **reached by** | **key 0 only.** 0 hunts class *operator* in fixed order from 00 and 04 is the first such port (`exch-marker.md` §3) — and from another exchange by `1 e b 0`, which is the same key once the far monitor has claimed (`exch-network.md` §3) |
| **not reached by** | its own number. Ports 00–17 are never dialled, because 0 and 1 mean something as a first digit (`exch-protocol.md` §5) |
| **to the console** | a number on the `SRC` wheels, and nothing more (§7.1) |
| **to the fabric** | nothing at all. No block, no port circuit and no highway knows which port it is |

**Why slot 4, and why block 0.** A link's channels sit where they are on the
wire: MF8 puts F at frame position 0 and S at 4, so **slots 0 and 4 of a block
are never trunk channels** (`exch-protocol.md` §5). Block 0 is therefore a block
with six channel slots and two ports that survive a trunk group — 00 and 04 —
and 00 can never hold anything, because a cleared latch listens to 00: an
operator there would ring every idle phone whenever the handset came up, and
every caller waiting for a register would hear the operator's calls. **04 is the
one port of block 0 that anything may sit in**, and giving it to the position
costs no dialable number.

**What the console needs from it: a hook that goes up.** §7 uses the operator's
phone as §6.3's ring source, and any port whose `M` can be raised does that.
A console with no position at all still works — that is what the ring source
card is for — and a position in a line slot works exactly as well. **04 is a
default, not a requirement**, and the only thing in the exchange that ties the
operator to it is a hunt.

**What is not at 04: the console.** The console is a unit on cable B with no
port, no latch and no number; the phone is a card in a channel slot with no keys
on it. They sit on one desk and are two different things, and either works
without the other.

### 8.2 More than one position, and none

| | |
|---|---|
| a second position | another class-*operator* card in any line slot. 0's fixed order from 00 reaches 04 first, then it (`exch-marker.md` §3) |
| a night announcement | the same, last in slot order: an announcement card, `/ANS` low, that answers itself (`exch-features.md` §3) |
| night service | the out-of-service switch on 04's word (`ex-extensions.md` §2.2). 04 reads unequipped, and 0 goes on down the hunt |
| no position fitted | 0 gives cannot-complete. Nothing else changes: a console with a ring source needs no position, and a CO line ringing in — which is routed as 0 — gets cannot-complete too, so an exchange with incoming trunks wants one |

### 8.3 Should the position have 04 at all?

The exchange has exactly four ports that no trunk group can take and no
subscriber can dial: 00, 04, 10 and 14. 00 must stay empty, so there are three,
and they are spoken for — 04 the position, 10 dial tone, 14 cannot-complete
(`tone-card.md` §5.1 counts them the same way). Two things want another:
`tone-plan.md`'s **fourth tone**, which is proposed at 11 and has no home on an
exchange where block 1 is a trunk group, and the **ringback card**, which
`tone-card.md` §5.1 settles by giving it no port at all.

So the trade is worth stating, and it comes out one way:

| what an undialable slot gives | a source | a position |
|---|---|---|
| a slot that survives a trunk group | yes — but a source is content with **no port circuit at all**, or with slot 0 or 4 of a *trunk* block, which costs nothing either (`tone-card.md` §5.1) | yes |
| a number nobody can dial | **it does not want one**: a tone in a line slot is dialable, and `tone-card.md` §5.1 calls that a feature — a test line for the tone, the bus and the listener's decoder | yes: 0 is then the only way to a position, so the hunt's order — first position, second, night announcement — cannot be walked round by dialling a particular one |

**So the position keeps 04 on an attended exchange, and an unattended one should
give it to the fourth tone**, which is the one thing with nowhere else
guaranteed. Moving the position costs nothing in the marker: it is found by a
hunt, and "nothing on the marker says where anything is" (`exch-marker.md` §1).

**One trap if a source takes 04.** Under `ex-groups.md` §2, key 0 becomes *a call
to a pilot number*, the pilot is **probed first**, and a source found at a probe
is connected in one write — so a tone sitting at the pilot would answer 0 with a
tone. The pilot must then move to a port that fails the probe: 00, which is
never fitted, or any trunk channel. Under the marker as built, which hunts a
class, there is no such trap.

---

## 9. Parts — a sketch

| | parts |
|---|---|
| the word | 2 × 74HC165, from four octal wheels and two toggles |
| the tenure | a 6-bit count of `TX_CLK` — 32 silent, 16 bits, `WR` — ≈ 2 packages and a package of gates |
| taking and keeping the bus | 1 × 74HC74: the tenure, and RELEASE; ½ 74HC14 on the keys |
| drivers | 1 × 74HC244 on `SDATA`, `SCLK`, `WR`, enabled after the silence; `/CON` from the tenure flip-flop |
| **BOTH** (§1) | ¼ 74HC153 on the serial stream and ½ '74: **≈ 1½** |
| **PROBE's capture** (§7.2) | 1 × '164 for the card's word, ½ '74 for `BUSY` and SEEN, the octet gate off `TX_OCT` and a 3-bit compare on `SLOTQ`: **≈ 2½** |
| | **≈ 11 packages** |
| the watch (§3.2) | 2 × '164, '688, '574: **≈ 4**, the '164 pair shared with a lamp field |
| the two hook lamps (§7.2) | 2 × '151 on `HA`, 2 flip-flops, the same compares: **≈ 2½** — **and a cable A tap**: `HA[0..7]`, `SLOTQ[2:0]`, `HCLK`, `TX_OCT`, 13 conductors. **Nothing, with a hook/busy panel beside it** (§7.3) |
| at the marker | **½ 74HC74** and two gate inputs (§2.2) |
| a sink card (§5.1) | a line card's receive half. Nothing in the exchange |
| a ring source card (§6.3) | a blank card and three ties. Nothing at all |

**The one thing here that changes what the console is**: supervising both ends
off `HA` makes it a two-cable unit, where §2 built it on cable B alone. The
escape is §7.3 — a console beside a hook/busy panel reads both ends off the
panel and stays a cable-B unit — and a console built alone pays 2½ packages and
a connector for it.

---

## 10. Measured — `make console`, `make console-naive`

Sixteen lines calling each other at random for five seconds, twice: once with
the console quiet, once with it writing a word every 2–30 ms — pointing the two
sinks at random lines and releasing them — **two words in three timed to land
inside a word the marker had already begun**, and half of those inside a latch
write.

| | console quiet | console writing |
|---|---|---|
| lifted / answered | 32 / 10 | 33 / 8 |
| dial tone after the lift, mean / worst | 48 ms / 395 | 51 ms / 382 |
| no dial tone in 600 ms | 0 | 0 |

| over the run | |
|---|---|
| console words | 117, 76 aimed; `/CON` fell inside a marker word **73** times, **39** of them a latch write |
| marker writes | 196. The blocks never saw: **0**. Saw mangled: **0** |
| console words the blocks saw wrong | **0** |
| clocks with both '244s on; runt `WR` pulses | **0**; **0** |
| one-way patches; two callers on one line | 0; 0 |
| held afterwards | nothing |

Then, scripted: forced release of one end and of both (§3), a port held by
nothing (§3.3), make-busy (§4), observing (§5), HOLD — 150 ms with the marker
stopped, a call carried 10 257 bits each way with 0 wrong, a caller given nothing
until the toggle dropped and dial tone 4 ms after — **the pair, the ring source,
a call set up from the console and handed over (§6, §7.1), the register hazard
and its cure, and every read-back of §7.2. 87 checks.**

**What scales.** The bench runs the port's release detectors at 1 ms and 32 ms
where the exchange has 16 and 256, the ring cadence at 3 ms on and 6 off where
the exchange has 2 s and 4, and the register's no-digit timeout at 600 ms where
the exchange has 10 s. It dials at 20 ms a pulse. Every figure quoted as "a
release time", a cadence or a timeout scales with those; the bus figures — 766 µs,
1 031, 951, 1 499, the scan, every count in the second table — are the exchange's
own, at its own 4.096 MHz.

---

## 11. What this changes elsewhere

- **`exch-mainboard.md` §2.3**, `/CON`: a request honoured between words, not an
  enable; and §7's glitch table gains a row — `/CON` low is a stopped marker,
  costing nothing in progress.
- **`exch-marker.md` §8**, "a second master on the control bus is not modelled":
  it is now.
- **`ex-extensions.md` §3.1**, "the console can still point two latches at each
  other by hand… that is a call": it is a call only if a hook is up somewhere.
  §6 is what it takes, and §6.3 adds a card to the wiring field.
- **`exch-features.md` §4** has the console as a lamp field and keys. The keys
  are §1, the position is §8, and "build it first" is unchanged — with a ring
  source card and two phones, fabric plus console is a working manual board
  before the marker exists.
- **`exch-features.md` §6**, sources: `A_TX` is tied low there "because `M` high
  on an idle port is a seizure to the scanner". §6.3 is the exception and says
  why it is one — no word, no class, no seizure.
- **`ex-counters.md` §8**, the console's writes: a counter card counts them as
  the marker's. **A RELEASE is the *trunks let go* pattern exactly**, and an
  observe write whose `SRC` is a trunk port matches *calls over a trunk*.
  **A PROBE is counted by nothing**, because nothing is written. At an
  operator's rate the rest is a handful a day. If it ever matters, the spare bit
  14 could mark a console's word; it is not spent here.
- **`tone-card.md` §5.1** counts the four undialable ports and finds all four
  spoken for. §8.3 is the trade that frees one of them, and which exchange should
  take it.
- **`hookbusy-display.md`**: its busy row already follows the console's words,
  which §7.3 makes a function rather than a coincidence.

---

## 12. Not measured

- **The circuit.** The tenure counter's decode, `WR` placed clear of `SCLK` off
  `TX_CLK`'s two phases, the key's synchroniser, BOTH's stream mux, the probe's
  octet gate and the marker's flip-flop against its sequencer's idle state have
  not been drawn.
- **`/CON` as a wire.** In the bench the two masters share one clock. On the
  cable `/CON` is asynchronous to the marker's sequencer and wants a synchroniser
  there; the silence has 240 µs in hand to pay for it.
- **The ring source as a card.** Three ties on a blank card, and whatever it is
  to say. Nothing has been drawn, and the failure mode that matters — the word
  pin grounded instead of open, which makes it a permanently off-hook line — is
  reasoned from the marker's call-request rule and not run.
- **The console's cable A tap.** The two '151 on `HA` and their cell compare are
  modelled as the marker's probe is modelled, not drawn; and the tap's connector
  and conductor count (§9) are a sketch.
- **`/RESET` from the console** (§1.1). Bring-up step 4 asks for it held by hand
  with no marker fitted, and §5.3 puts it behind the same lock as RELEASE. The
  key, its open-drain driver against the marker's and the power-on circuit's, and
  what a whole exchange does when it is let go are not in the bench.
- **An operator's habits.** Patch-then-lift is a rule a person has to keep, and
  nothing on the panel enforces it or shows that it was broken. Whether it
  survives a busy hour is not something a bench can say.
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
