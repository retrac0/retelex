# The markers

The common control of one exchange: how a caller is found and given a
register, how the number it dials is acted on, and how the marker leaves a
call that nobody is then in charge of. Two markers are built, a small one and
a class marker, and a network unit plugs in beside either. The number itself
is `numbering.md`; what a card says about its port is `card-word.md`.

> **Built:** `newimpl/rtl/mini_marker.v` in `top_min` (`tb_mini`) and `top_net`
> (`tb_net`, `tb_chain`); `marker.v` and `word_dec.v` in `top_max` (`tb_max`).
> **Not built:** a register pool; the class marker on a network (§7).
> **Measured in:** the benches above; `sim/exch.py calls` for §6's scenarios.

---

## 1. What a marker does

A marker takes a caller, gives it the register, reads the number the register
collects, and then connects the caller, lets it listen, or hunts for a port
that will take the call. After the connect it watches the caller until the
called port can release itself (§5), and then it leaves. Ringing, ringback,
answer and release are the ports' own (`fabric.md` §5).

| | |
|---|---|
| **reads** | every port's M and `BUSY` through its probe on `SCAN`, one port a bit-time, a pass a millisecond (`fabric.md` §3). A card's word when it needs one: a select on `/WS` in the port's bit-time, then eight frames of `/HW` (`fabric.md` §4) |
| **writes** | latch writes on the bus, and nothing else: `DST`, `SRC`, `BUSY`, `CLAIM` (`bus.md` §4). A caller the marker holds is written `BUSY` |
| **a connection** | two writes queued in one tick, caller ← called and then called ← caller, both `BUSY`, with nothing of the marker's between them |
| **tones** | addresses: 00 silence, 01 dial tone, 02 busy, 03 cannot-complete (`numbering.md` §2) |
| **the register** | handed a caller's port; its digits, and whether the caller has gone, come back as levels (`register.md` §3) |
| **holds** | nothing about the exchange: no route table, no translation, no record of where anything is. Move a card and its role moves with it |

**Three rules are not optional**, in either marker:

1. **Act on the port the probe or the reader latched, never on live `SCAN`.**
   By the time the sequencer has decided, the scan has moved on.
2. **Do not return to idle with writes still queued.** The caller's `BUSY` is
   what stops it being seized a second time. A word takes 133 µs and a port
   comes round every 1 ms, so a marker that idled early would seize the same
   caller twice.
3. **Do not let go of a connected call until the called port could let go of
   it**: the watch (§5).

The marker is a card, and common control is the one family of cards that is
swapped rather than added to: the mini marker in `top_min` and `top_net`, the
class marker in `top_max`. Both speak the same register ribbon and the same
unit ribbon. Features are cards and straps on the board that owns the fact;
no marker grows a jumper to become the other. In RTL each fits a `ctl_queue`,
a model part (`bus.md` §5).

---

## 2. A call, step by step

20 calls 21, rotary at 10 pps, as `tb_mini` and `tb_max` scenario 2 run it:

```
 20 lifts      M on /HA in 20's bit-time, BUSY clear.  The mini marker's probe offers
               it within a pass, 1 ms.  The class marker takes it when its walk reads
               20: up to a round, about 250 ms (§4.2).  20 ← 01, BUSY; the register
               attaches to 20
 dial 2        the register counts 20's breaks off /HA.  The digit is in when a make
               has lasted 128 ms (register.md §1).  20 ← 00: dial tone off
 dial 1        called = 21.  The marker looks at 21 at its turn: its M and BUSY, and
               its word (class marker, or any marker with a unit fitted)
 connect       21 is a line, on-hook, not busy: 20 ← 21, 21 ← 20.  The marker watches
               20 for 32 ms, then frees the register (§5)
 21 rings      on-hook with E high: its port gives its card E in the ring cadence and
               sends 20 ringback in place of 21's voice (fabric.md §5)
 21 answers    M rises; ringing and ringback stop.  Nothing else acts
 hang up       in either order.  Each port clears its own latch 256 ms after its M or
               its E falls.  A party left off-hook with an idle latch is a new call
               request, and gets dial tone
```

- **A second caller** while the register is held is not refused. The mini
  marker is offered it again every pass, the class marker's walk reads it
  again a round later, and it gets dial tone once the register is free.
- **Hang up while dialling** and the register sees a break of 256 ms, CLR: the
  caller is written to 00 with `BUSY` clear, and the register is free.
- **Off-hook, nothing dialled**: 03 after the 10 s no-digit timeout. The port
  stays `BUSY`, listening to 03, until the phone is hung up. **03 is written
  only while the register reads the caller off-hook**: on-hook at the timeout,
  the caller's port may already have released itself, and a `BUSY` written
  then would hold it with no edge to clear it; the marker waits for `gone`, or
  the make. The same holds for YIELD's cannot-complete and the watch's `nodig`.
- **Wrong numbers**, and which get busy tone: `numbering.md` §4.

---

## 3. The mini marker

`newimpl/rtl/mini_marker.v`: M and `BUSY`, two digits, one register on the
card, tones by address. No class, no hunt, no busy tone. It reads a card's
word only when a network unit is fitted.

- **A call request is M and not `BUSY`**, at the probe's sample, with the
  register free and nothing queued. The probe follows the scanner; a port it
  could not take comes round again 1 ms later. Nothing steers the scanner, so
  no turn is repeated or skipped.
- **The number**: `numbering.md` §3. 0, 8, 9 and 11–15 are cannot-complete on
  the first key; 1 is highway 1 with no unit and the flood with one.
- **The called port** is looked at on its turn. Itself, M up or `BUSY` →
  03. Otherwise the two writes, and the watch. **Dial only fitted ports**: an
  empty slot reads free, the caller is written to it and hears silence.
- **With a unit fitted** (`/NET` low) it reads a would-be caller's word first:
  a flood trunk (`11 01 0`) or none is never a caller, and anything else is
  taken at its next turn if it is still asking. A port refused so is read
  again every other pass for as long as it shows M with `BUSY` clear, and the
  seven ports behind it in scan order are never offered meanwhile (§7). A
  dialled trunk is 03; a port that reads none is connected as an empty slot
  is, and so is a tone trunk, which the class marker refuses (§7). A tone
  trunk lifting is a caller, which is how a leaf's uplink arrives at its
  central (`proposed/leaf-uplink.md`; not benched).

```
IDLE     M · /BUSY, register free, queue empty:
           no unit → caller ← 01 → COLLECT
           unit    → READ the port's word
READ     a caller's word: trunk or none → IDLE; else → TAKE
TAKE     its next turn, still asking → caller ← 01 → COLLECT; else → IDLE
COLLECT  h, then s → PROBE (no unit) or READ (unit)
         a bad key, or the no-digit timeout → 03, DRAIN
         key 1 with a unit → restart, flood_go → YIELD
READ     a called port's word: trunk → 03, DRAIN; else → PROBE
PROBE    the called port's turn: self, M or BUSY → 03, DRAIN; else the two writes → WATCH
WATCH    §5 → IDLE, or DRAIN
YIELD    local → COLLECT; done → DRAIN; nogo or the no-digit timeout → 03, DRAIN
         in COLLECT, PROBE and YIELD a hang-up is looked at first: caller ← 00,
         BUSY and CLAIM clear, DRAIN
DRAIN    queue empty → IDLE
```

**A claim never takes this register** (mini marker, with a unit: §4.8). It is
given the claim register at once, whatever state the sequencer is in, and a
second, small sequencer finishes it:

```
K_COLLECT  the claim register collects h s off the trunk, beside this card's call.
           With the sequencer parked (IDLE, COLLECT, YIELD, DRAIN):
           1, 0, 8, 9 or a service second digit → trunk ← 03, K_DRAIN;
           gone → trunk ← 00, BUSY and CLAIM clear; the no-digit timeout, off-hook → 03
           h s → K_READ
K_READ     the called port's word (the reader is free: the sequencer is parked);
           trunk → 03, K_DRAIN; else → K_PROBE
K_PROBE    the called port's turn, on the marker's probe: self, M or BUSY → 03;
           else the two writes, CLAIM on the trunk's → K_WATCH
K_WATCH    §5, on the claim register → K_IDLE, or K_DRAIN
K_DRAIN    queue empty → K_IDLE
```

K_READ, K_PROBE and K_WATCH hold the sequencer where it is, about 35 ms; the
unit's `local` and `done` are kept meanwhile, as its `nogo` always was.

**The probe tap.** The probe's port, M, `BUSY` and `probe_fresh` are brought
out for a watcher, which must use `probe_fresh`: the levels hold for a whole
pass. The probe is re-pointed at the called port in PROBE and TAKE, so the tap
freezes there, and a listener fits a probe of its own, as the unit does.

**What it will not do**: hunt, follow a nail or an answers-to, limit a
restricted card, give busy tone, or hold more than one caller.

Each rule it keeps has a fault in `newimpl/faults.py` that turns a bench red
when put back: F09 (second key folded), F10 (register armed on a stale
sample), F14 (key 1 read as the flood with no unit), F21 (a second key after
the own code), F05 (a trunk's M taken as a caller; F05b with the unit's hold
gone too), F03b (a claim refused before the unit's `CLAIM` word), F37–F39 (no
watch, or a watch on half of `settled`).

---

## 4. The class marker

`newimpl/rtl/marker.v`, with `word_dec.v` for what a word says. The mini
marker's sequencer, and every decision taken on the port's word as well as
its M and `BUSY`: who may lift for the register, what a dialled number
reaches, where a failed number is hunted, which lines go first when the
register is short. It reads only the primary octet: no covers, no second
numbers, no hunt conditions (`card-word.md` §7).

### 4.1 What it reads, and when

One word reader, shared by the walk and the sequencer. It reads:

- **one port every `WALK` passes, always**: the walk, §4.2;
- **the dialled port**, before it connects it;
- **every port from 01 in turn, only while a hunt runs**: 9, or a number
  that failed at its own port, 0's 04 included (§4.5).

Every reader waits out another's eight frames before it selects. The walk
reads one port in four passes, not one a pass, because a select that moved one
port a pass would hold off the network unit's reads, whose target stays put,
for up to eight passes: a transit's hop would grow from about 12 ms to about
28, and the guard would cover four hops instead of ten. With two or more
passes between the walk's reads a unit read waits at most a pass.

### 4.2 The walk

**The walk is the only way in.** It reads the next port in order, 01 to 77,
whatever the last one said, one every 4 passes; a round is 63 × 4 passes,
about 250 ms, the longest a caller waits for dial tone. It pauses while the
sequencer reads (§4.4, §4.5) or makes a nail. At each read, with the port's M
and `BUSY` as they were at its select, it takes every decision about that
port:

| the port reads | the walk |
|---|---|
| a tied nail, `BUSY` clear | the nail's one write: port ← dest, `BUSY` (`card-word.md` §6.1). The dest is not read or written |
| M up, `BUSY` clear, a word that may call (a line without `D`, restricted, answers-to, a tone trunk) | if the register is free, this marker idle and nothing queued: the register, and dial tone. Under `PWAIT` only a `P` line (§4.3) |
| M up, `BUSY` clear, a call nail | the register, no dial tone; called = its dest, as if dialled (§4.6) |
| M up, `BUSY` clear, an outside line | a CO ringing in: the register, no dial tone; called = 04, as if 0 (§4.6) |
| anything else | passed over, and read again a round later |

**Nothing is read out of turn, so nothing needs remembering.** A data line
left off-hook, a trunk before the unit holds it, a card in its power-up RC:
each is read once a round like every other port. A read of whoever lifts, the
mini marker's way, re-reads such a port every other pass and shadows the seven
behind it (§3).

### 4.3 `PWAIT`

Priority under register overload, for lines whose word sets `P`
(`card-word.md` §4). Two flip-flops, closed at 77 by the walk: a round that
finds a `P` line wanting the register and not getting it sets `PWAIT` at 77,
and a round that finds none clears it. While it is set the walk passes over
every caller but a `P` line, the register free or not. A call nail and a CO
line are not held by it. Passing a caller over costs nothing, because the walk
comes back to it; when the register frees under `PWAIT` it waits, up to a
round, for the walk to reach the `P` line. A lone lift into an idle exchange is
never delayed.

### 4.4 The dialled number

The keys, and a restricted caller's limits, are `numbering.md` §3. For
`h s`, or 04 for 0, the marker reads the called port's word, with its M and
`BUSY` at the select:

| the called port | |
|---|---|
| a source, not the caller | one write: caller ← source, `BUSY`. The register is freed; the source is never written and never tested free (`features.md` §5) |
| a voice line, not the caller, M and `BUSY` clear, not busy-out | connect: the two writes, then the watch (§5) |
| anything else | the hunt (§4.5) |

"Anything else" is every reason the port fails: busy, ringing, busy-out, an
empty slot, none, out of service, a trunk, a tone trunk, an outside line, a
data line, and the caller's own number.

### 4.5 The hunt

**Every failure of the dialled port is hunted among the ports that answer to
its number** (`card-word.md` §5), the caller's own number included. 9 hunts
the class *outside line* instead.

- **Every port from 01 to 77 in slot order**, a read a pass, about 63 ms for
  the round. The first that is free at its select (M and `BUSY` clear), is not
  the caller, and answers to the number — or, for 9, is an outside line — is
  taken at the read that finds it: the two writes, then the watch.
- **None found**: busy tone if the number's own port was a voice line that was
  not free, and cannot-complete otherwise (`numbering.md` §4).
- **Fixed order is the feature.** Priority is where a card is plugged in. 0
  rings 04; 04 busy, the first free port answering to 04, a second position,
  then an announcement; all busy, busy tone. 9 takes CO lines in slot order.
- **One hunt a call, never a chain**: the port found is free, so there is
  nothing to pass on.
- **Across the network nothing changes**: `h s` after `1 e b` is hunted at the
  far exchange as it would be at home.

### 4.6 Call nails, CO lines and claims take the register for the watch

A call nail and a CO line ringing in dial nothing, but each takes the
register, with no digits and no dial tone, so that the watch (§5) follows its
connect; the port is written to 00, `BUSY`, meanwhile. A call nail to a busy
dest is hunted like a dialled number and ends in busy tone. A CO line is
routed as 0, so fit an operator before outside lines.

A claimed trunk is a caller the network unit brings (§4.8): on the mini marker
it is given the claim register, with no dial tone, and dials `h s` or one key
from the far end; the class marker still gives it its one register.

### 4.7 Restricted, busy-out and data lines

The options are `card-word.md` §4. At the marker: restricted `z` lets only 0
through, and bare restricted is refused 9 and the flood; busy-out makes a
dialled line not free, so its caller hears busy, while its own lift still gets
the register; **a data line is neither caller nor called**, so it reaches
another port only through a nail.

### 4.8 With a network unit

Both markers take the same part in a network call; the interface is
`network.md` §3.6. With `/NET` low, key 1 is consumed and the marker yields
until the unit says local, done or nogo. **On the mini marker a claimed trunk
is given the claim register** (`register.md` §4), a second register that no
local caller ever takes, with `CLAIM` on every later write to it — at once,
whatever this card's own call is doing, since the attach writes nothing — or
written to 03 while that register is on another claim. Given the one register
instead, a claim was refused whenever the owner's register was busy, which it
is for its own caller through every digit and through `1 e b` of an outgoing
call — exactly when the other exchange's claim arrives: two exchanges refused
each other, 9–16 % of incoming calls at design load, and two-way traffic past
the knee carried nothing (`newimpl/flood-study/REPORT.md` §2–§3). **The class marker still does that**,
refusing at once, a watch included (§7). The unit outranks the marker on the
bus (`bus.md` §5).

---

## 5. The watch after a connect

**A port releases only on the fall of a detector** (`fabric.md` §5), and the
called port's E detector rises only once the caller's M has stood `T_ARM`,
16 ms, after the connect's write. A caller who hangs up inside that window —
measured, 0 to 14 ms after the write; 18 ms does not — leaves the called port
`BUSY` with no edge ever to release it: unreachable, then ringing as a phantom
when the caller next lifts, and listening in on that call.

So **after every connect the marker keeps the register on the caller**:

| | |
|---|---|
| while the connect's words are queued | the marker holds the register's `restart`, so the no-digit timer starts when they are out |
| `settled` | the caller off-hook `SETTLE` with no break, and `SETTLE` since the restart: off-hook `SETTLE` counted from the connect. `SETTLE` = 2 × `T_ARM` = 32 ms. Two taps of timers the register already has (`register.md` §1) → the register is freed |
| `gone` (the caller left first) | called ← 00 with `BUSY` clear: the called port written free. The caller's own port releases itself |
| `nodig` (the line chattered for the whole no-digit time) | called ← 00, `BUSY` clear; caller ← 03, `BUSY` — the caller off-hook only; on-hook, wait for `gone` |

Every connect is watched: dialled, hunted, a call nail, a CO line, a claimed
trunk. A source's one write is not, nor a tied nail: neither has a called port
waiting to release. A claim arriving during a watch is refused at once (§4.8). The
network unit keeps a like watch on a trunk it holds (`network.md` §3.3). F37
and F48 remove the watch from each marker, F38 and F39 half of `settled`.

---

## 6. Release

**Nobody is in charge of a call.** After the watch the marker has nothing to
do with it: each port clears its own latch when its M or its E has been down
for 256 ms, and an idle off-hook port with `BUSY` clear is a call request
again (`fabric.md` §5). Nothing in the exchange winks, so the rule has no
exceptions: a break longer than CLR is a hang-up, and a flash is a digit 1
(`register.md` §1).

Measured on the exchange model, every case ends with every latch idle and
every `BUSY` clear (`sim/exch.py calls` 1–15):

| | what happens |
|---|---|
| caller hangs up first | the called party, still off-hook, is released with it and gets dial tone |
| called party hangs up first | the same, mirrored |
| abandoned while ringing | the called phone stops ringing at once (its E fell) and is free 300 ms later |
| abandoned while dialling | the register lets go by itself: the hook it watches stays down 256 ms |
| two callers dialling each other | each finds the other not free |
| a called phone lifting 3 ms before the test | reads busy: M is part of the free test |
| a second caller, one register | dial tone 1.9 s late, when the first caller's number is in |
| 7 pps at 72 % break, every detector at its shortest | dials and completes; no release during dialling |

The model predates busy tone, the walk and the watch. Two rules of the port
circuit that it found — `BUSY` also carries a detector still timing out, and
ringing and ringback are gated by the filtered hook — are `fabric.md` §5's.

---

## 7. Open

- **The class marker on a network.** `top_max` fits the unit, but no bench
  runs a flood, a claim or a unit read beside the walk through `marker.v`.
  Blocks any claim that the maximal build is a network exchange.
- **One caller at a time.** Both markers follow one call and fit one register
  for callers; the mini marker adds the claim register for claims (§4.8). A
  pool needs per-register call state and an owner for the one reader's hunt
  (`register.md` §5).
- **The class marker's claims.** `marker.v` still gives a claim its one
  register and refuses it when that is busy: the collapse the claim register
  removes from `top_net`. It wants the same second register and sequencer, and
  a flood run beside the walk first.
- **Dial tone on the walk.** A lift waits up to a round, about 250 ms, on
  `top_max`, against 1 ms on the mini marker. Acceptable on a breadboard; a
  lamp or timer that assumes a pass is wrong there (`debugger.md` §7).
- **The mini marker's re-read, with a unit fitted.** A port showing M with
  `BUSY` clear and a word of none — an out-of-service line off-hook, the
  console's ring source (`proposed/console.md` §9) — is read every other pass,
  and the seven ports after it are never offered while it stays up (from
  `mini_marker.v`, seen on a scratch bench; no `newimpl` bench runs it).
  Options: a bit a port, as the unit keeps (`network.md` §3.3), or a walk.
- **A CO line rung in with no position free** stays `BUSY` on busy tone and is
  never answered, even when a position frees: `features.md` §8.
- **A dialled tone trunk.** The class marker refuses it: `word_dec.v` makes a
  tone trunk a caller but not a voice line, so a number that lands on one is
  hunted and ends in 03. The mini marker connects it (in `top_net` it refuses
  only a flood trunk). So a PBX leaf can be dialled into through a mini-marker
  central and not through a class-marker one (`proposed/leaf-uplink.md`). The
  two markers differ; which is right is not decided.
- **Transfer.** Neither marker transfers a call, and a flash is a digit 1.
  Transfer is the console's (`proposed/console.md`); no marker hook for it is
  built.
