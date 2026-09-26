# The console: keys that write the control word by hand

Octal wheels and keys that make the masters' own control word, a listener
that shows what a port was last told, and reads of a port's hook, `BUSY` and
word: **forced release**, **service observing**, **connecting two lines by
hand**, and **transfer**. The phone on the desk is `features.md` §3.

> **Proposed.** No `console.v` in `newimpl`. The latch-level results below
> (release, the pair, the ring source, observing, patch-then-lift) were
> benched on the retired tree's port circuit, whose release and ringing rules
> `fabric.md` §5 keeps; its bus layer is gone, and arbitration is open (§9).

---

## 1. Keys, and the word they make

Two pairs of octal wheels (`DST`, `SRC`), toggles for `BSY` and `CLM`, and the
keys below. The word is `bus.md` §4's control word out of two '165, `G` wired
high and the spare low: **a console cannot send a word a master could not have
sent, nor an event word** (`proposed/counters.md` §5). A block cannot tell
whose word it is, and a counter card counts the console's writes as a
master's.

| key | what it does | for |
|---|---|---|
| **WRITE** | one word as the wheels have it: *`DST` listens to `SRC`* | a patch; observing (§5); one leg of a connection (§6) |
| **RELEASE** | the same `DST`, `SDATA` held low for bits 7–0: `SRC` 00, `BSY` 0, `CLM` 0 | forced release (§3); one gate on the stream |
| **BOTH** | a toggle: the key's word goes out twice in one tenure, the port fields crossed the second time (a '153 on the stream, a flip-flop for *second*) | WRITE + BOTH connects; RELEASE + BOTH frees both ends |
| **READ** | no word: reads the wheel port's word off `/HW` (§7.2); with BOTH, both ports' | what a card says it is |
| **HOLD** | a toggle: keep the bus (§2) | freezing the masters to look |
| **ARM** | clears the watch's SEEN lamp (§7.3); touches no wire | |

---

## 2. Taking the bus

**A console never cuts a master's word** (a lost write, or a runt `WR` into a
'273). It raises its request, waits out a **silence** longer than any master's
longest tenure, sends its words and `WR`, and lets go. **There is no grant**:
a silence behaves the same with a marker, without one, and with one that has
stopped, which is what a bring-up tool needs.

The request is a line on the bus's spare pin 48 (`bus.md` §2), ranked above
both masters. The marker already yields between transactions to the unit's
`/UREQ` (`bus.md` §5); the console's request must stop the marker **and** the
unit, and the unit has no yield input (§9).

**HOLD** keeps the tenure after the word, or opens one with none. It stops the
masters and nothing else: calls in progress carry on bit for bit, because
nobody is in charge of a call, and nothing new is set up. **A lamp on the
request line**: an exchange left in HOLD gives no dial tone and says nothing
about why.

---

## 3. Forced release

`/RESET` clears every latch; RELEASE clears one. The port hears idle, its `E`
detector falls one release time later (`fabric.md` §5), and a phone still off
hook is then a caller like any other. The port's own supervision does the rest.

**One end is not enough.** With 20 released, 21 still listens to 20 and is
still busy: 21's `E` is 20's hook, not anything in 20's latch. **A call is
released with RELEASE + BOTH.**

**A port held by nothing** — a latch written `BUSY` with both phones on hook —
is held for ever: release is on a *fall*, and nothing rose. One RELEASE frees
it. **On a trunk port** RELEASE is the word the unit lets a trunk go with; if
the far end still holds forward A up, `M` on a free trunk is a seizure
arriving, and the unit treats it as one (`network.md` §3).

---

## 4. Make-busy does not stick

A line written to 00 with `BUSY` set is busy only until its phone is next
lifted and replaced: then the port releases itself. Out of service and
busy-out that survive hang-up are the card's word (`card-word.md` §2, §4).
**The one use is the operator's own line** (§7.1): a make-busy before the
handset is lifted keeps the lift from being a caller, and goes with the handset.

---

## 5. Service observing

**The sink card** is half a line card — a CVSD decoder, filter, headphone
amplifier and jack — with `A_TX` tied low (never off hook, never releasing
itself), `/ANS` low (never rung) and **no word**, the pin open: to the class
marker an empty slot, never a caller, cannot-complete if dialled. **Only the
console writes it.**

**WRITE with the sink on `DST`, the observed port on `SRC`, `BSY` up.** Any
number of latches may point at one slot, and the observed port's is not
touched. Benched on a call between 20 and 21 with a sink on each: 2 466 bits
each way, 0 wrong; each sink heard its party bit for bit; 20 hanging up cleared
its sink one release time later (the sink's `E` is 20's hook); a sink on a line
on hook waits for that line's next call and lets go at its end.

**One party a sink**: both sides of a call is two sinks, and there is no
barge-in (that is `proposed/conference.md`). A trunk call is observed at the
trunk port. **It cannot be detected**, not by a bit, which is why WRITE and
RELEASE belong behind the same lock as `/RESET`.

---

## 6. Connecting two lines

A port's '273 holds only who it listens to, so a conversation is two latches:
**WRITE + BOTH** writes `20 ← 21` then `21 ← 20` in one tenure, and no master's
word lands between them. **A pair does not ring:**

| both phones … | what happens |
|---|---|
| **on hook** | neither rings, and both are busy for ever: each `E` is the other's hook and no detector ever armed. RELEASE + BOTH frees them |
| **one off hook** | it rings the other and hears ringback; the other answering is a call |
| **both off hook** | they talk from the frame after the second word |

**The pair is the last step, not the first.** The exchange rings a port one
way: point it at something whose `M` is up. **The ring source** is a blank card:
`A_TX` tied **high**, `/ANS` low, the word pin **open** (none), `C_TX` `FILL` or
a looping "please hold" (`features.md` §2). A port pointed at it rings if on
hook and, once answered, is **parked** — busy, held, hearing the source —
until it hangs up. **The word pin must be open**: grounded, it reads a plain
line, a permanently off-hook caller.

```
 RING  20      WRITE        DST 20  SRC rs  BSY    20 rings, answers into the source
 RING  21      WRITE        DST 21  SRC rs  BSY    21 rings, answers into the source
 PAIR  20 21   WRITE+BOTH   DST 20  SRC 21  BSY    they talk
```

Benched: both rang, answered and were held while the other was rung; the pair
carried 1 920 bits each way, 0 wrong; 20 hung up and 21 released by the
ordinary rule. **The order matters and nothing enforces it**: pairing two
ports not yet off hook is silent. Afterwards nobody is in charge and nothing
remembers the pair; one that must survive a release is a nail on each card
(`card-word.md` §6.2). A party who never answers rings until released. Sinks and
the ring source sit anywhere; keep them off the test lines' slots
(`features.md` §7).

---

## 7. Calling from the console, and transfer

The console does what the position cannot: reach a port with no number or no
word, start a second leg while in a call, ring a busy or out-of-service port.

### 7.1 The call, and the order to do it in

```
 the position (04) ON HOOK
 CALL 20        WRITE+BOTH   DST 20  SRC 04  BSY    nothing rings yet
 lift                                               04's hook is 20's E: 20 rings
 SECOND LEG
 RING 21        WRITE        DST 21  SRC 04  BSY    21 rings; 20 still hears 04
 HAND OVER
 PAIR 20 21     WRITE+BOTH   DST 20  SRC 21  BSY    they hear each other
 DROP           RELEASE      DST 04                 the operator is out
```

Benched, every line: 20 rang when the handset came up and not before, both
lines heard the operator bit for bit, and after the release the two talked on
with nobody in the call.

**Patch first, then lift.** Patched first, the lift raises `M` on a port
already `BUSY`: not a caller, no register. Lifted first, the position is a
caller: dial tone, and **the exchange's one register** until the no-digit
timeout (`register.md` §1), when the marker writes the position to
cannot-complete **over the patch** (`newimpl/rtl/marker.v`; reasoned, not
run). If the handset must be up first, make-busy the position (§4).

### 7.2 Reading a port

| | what | how |
|---|---|---|
| **hook** | the port's `M`, which its partner sees as `E` | a probe on `/HA` in the port's turn: a '688 on `SCAN` against the wheels and half a '74 (`fabric.md` §3); every pass, 1 ms |
| **`BUSY`** | the port's full busy term | the same probe on `/HB` |
| **the word** | the primary octet: what the card says it is | READ: a select on `/WS` in the port's turn, eight frames of `/HW` (`fabric.md` §4); a word reader, `newimpl/rtl/word_rx.v`, ≈ 6 packages |

**None of these needs a bus tenure, a master, or stops one**; a read waits out
any other reader's eight frames. READ gives a line on a free line card, and
none on an empty slot, a sink or the ring source (whose hook is up). **A latch
cannot be read back**: §7.3 is the only way to know who a port listens to.

### 7.3 The watch

A listener on `SDATA`, `SCLK`, `WR`: two '164, a '688 on `DST` and `G` against
the wheels, a '574 clocked by `WR` · match. It shows **what the watched port's
latch was last written**, by either master: for a called port, the caller, a
call trace. It is `proposed/lamps.md` §6's port watch without hook, `BUSY` and
word, and keeps its rules: armed before the call (the SEEN lamp), stale once
the port's `BUSY` is out, a trunk port and nothing beyond.
**With a hook/busy panel fitted** every port's hook and `BUSY` are on the wall
already, and the console needs only READ and the watch.

---

## 8. Parts, a sketch

The word: 2 × '165, four octal wheels, two toggles. The tenure: a bit-time
count — silence, 16 bits, `WR` — ≈ 2 packages and gates, and ½ '74. Drivers:
a '244 on `SDATA`, `SCLK`, `WR`, and an open drain on the request line. BOTH:
¼ '153 and ½ '74. Hook and `BUSY` of two ports: 2 × '688 and a '74. READ: a
word reader, ≈ 6. The watch: 2 × '164, a '688, a '574. A sink: a line card's
receive half. A ring source: a blank card and three ties.

---

## 9. Open

- **Arbitration.** The request on pin 48 must stop both masters, and
  `net_unit.v` has no yield input: its tenure is its own timer on `/UREQ`,
  held until its queue is empty. Options: a yield input on the unit as the
  marker has; a console only where no unit is fitted. The silence must outlast
  the unit's longest tenure — up to five words decided in one tick
  (`network.md` §10) — not one marker word, and HOLD on a network
  exchange stalls the unit's claims and drops mid-flood. Blocks the console on
  `top_net`, and on `top_max` with its unit.
- **The builds the sink and the ring source work in.** Only the class marker
  reads their empty word as no caller and no line. Under the mini marker a
  dialled sink is connected, and hears the caller. In `top_min`, which reads no
  word, the ring source takes the one register at every `/RESET` for the
  no-digit time and is then parked on cannot-complete (reasoned from
  `mini_marker.v`; not run); in `top_net` it is re-read every other pass and
  the seven ports after it are never offered while it stands (`marker.md` §7).
- **The console's shift clock** has no bus tap, as the masters' has none
  (`bus.md` §7).
- **`/RESET` from the console**, open-drain against the power-on circuit: not
  designed.
- **Not measured in `newimpl`:** all of it; nothing is drawn. Patch-then-lift
  is a habit nothing enforces. Forced release of a port that is dialling turns
  off its dial tone only: the register stays and the call completes (reasoned
  from `marker.v`).
