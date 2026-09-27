# The exchange — the network

Exchanges joined by trunks, and how a call reaches a line on another exchange:
the pulse flood, the network unit that runs it and its interface to the marker,
glare, the guard, rings and clocking. A standalone exchange carries none of it.

> **Built:** `newimpl/rtl/net_unit.v`, `word_rx.v`, beside the mini marker in `top_net.v`; benches `tb_net`, `tb_chain`, `tb_lnet`, `tb_lchain`, `tb_lfull`.
> **Not run:** a hub's fan-out of two or more legs, a ring and its strap, the unit beside the class marker, a relayed pulse at real speed.
> **Measured in:** `analysis/monitor-rules.md` (the monitor's rules); `analysis/topology.md`, `analysis/traffic.md` (sizes, on the model's hop, not the unit's; not re-run).

## 1. The pulse flood

A call to another exchange crosses a **tie trunk**: two ports, one in each
exchange, whose cards are linked, so that what one hears from its fabric the
other says into its own, `C` and `A` both. To the called line the far trunk port
*is* the caller, ringing and releasing by the ordinary rules (`fabric.md` §5).
A trunk port holds no digits and decides nothing.

An exchange faces up to four **directions**, N, S, E and W. Each trunk card says
in its word which way its link goes (`card-word.md` §2), and every trunk facing
one way goes to the same neighbour; three or four directions make a **hub**. A
line is dialled `h s` at home and `1 e b h s` from anywhere: `1` is the network's
key, `e b` the exchange's octal code (`numbering.md` §1, §5). **Nobody routes and
nobody sends:**

1. the origin consumes the key and seizes a free trunk in **every** direction,
   each listening to the caller, so the next digits go down them all live on A;
2. every exchange a seizure reaches holds it, gives it a **monitor**, and patches
   it onward into every *other* direction;
3. the monitor at the exchange that `e b` name **claims**: backward A rises on
   its trunk and crosses every patch back to the origin;
4. the origin and each transit keep the trunk that claimed and drop the others,
   and the owner's register reads `h s` off the trunk's A.

After the claim a transit holds two patched ports and nothing else. **A local
call never floods**, and nothing says which exchange lies behind which direction.

**The claim is a level, not a wink**: `CLAIM` set in the owner's trunk port holds
backward A = 1 until release (§4.2). A port releases on a *fall* of M or E, so a
wink would clear every patch it crossed. So backward A across the network says
*claimed*, not *answered*: a CO line extended to another exchange is answered at
the claim, and a data card's `DSR` rises there.

## 2. What a carrier must do

A trunk is any port whose card says it is one (`trunks.md` §1). What is behind
the card matters in these ways only, and **not how long it is**:

| | the carrier must |
|---|---|
| **A** | carry a level each way, and dial pulses with it: every break of 8 ms or more must survive (`register.md` §1). It may **shorten** a break — MF8 by 0.5 ms a hop, a two-wire voice-band tie by 5–10 ms a hop (`proposed/pots-trunk.md`), the CVSD line card's hook detector by 6.1 ms once — and must not lengthen a make past the 128 ms that ends a digit, or a break past the 256 ms that is a hang-up |
| **A's delay** | **anything.** The seizure and the caller's pulses travel the same wire and arrive equally late, so a constant delay costs the guard nothing (measured to 160 ms a hop: `analysis/monitor-rules.md` §5.1) |
| **A's wander** | delay **lost** between the seizure and the next digit — a buffer draining, a link re-timing — costs the guard a millisecond for a millisecond (§6) |
| **C** | 64 kbps each way bit for bit, crossed into the exchange's clock on the card; or voice band through a codec pair: a tandem of about 2 dB, and no data (`analysis/why-bits.md` §1) |
| **Round trip, signalling** | under 2 s over the whole path, less about a millisecond a hop each way: the owner's monitor counts `b` as the origin's register does, one forward delay later, and the origin gives up 2 s after its own count (§4.1) |
| **Round trip, echo** | **20–30 ms, and this is the one that binds.** No echo canceller or suppressor exists anywhere. A CVSD subscriber is four-wire; an analog FXS or FXO card's 600 Ω hybrid returns 10–15 dB, and **one 15 ms hop is already 30 ms of round trip**. A carrier of tens of milliseconds is for a network of CVSD sets |
| **One way, conversation** | with no hybrid at either end, G.114's 150 ms for transparency, 400 ms to be usable at all |
| **Link down** | be seen by the card, which then reads none, so it is never hunted, and drops A, so a call in progress releases — and keeps A down both ways until the channel has been idle both ways 300 ms, so an outage is a release, never a dial pulse or a fresh seizure (`trunks.md` §1) |

## 3. The network unit

One card on the bus beside the marker. Everything the network adds is on it or on
the trunk cards; the fabric, the ports, the register, the marker and the release
rule are the standalone exchange's, unchanged. Any marker may sit beside it
(`README.md` §2).

### 3.1 What it holds

**Straps**: its code `e b`, three bits each; the guard's tap (§6); the ring
strap, one a direction (§7). **No jumper says a port is a trunk or which way it
faces**: the card says so. **Stuffing**: `NMON` monitor cells, `NRES` resolvers.
**Its own** probe on `/HA` and `/HB` (`fabric.md` §3), never the marker's, which
stops on a called port; word reader (`fabric.md` §4); bus master (§3.6); and a
bit a port (§3.3), eight '164. Its machines are the classifier, the monitor
cells, one forwarder with the resolvers, and one origin bank; the last two share
one sweep.

### 3.2 The sweep

A read starts only at its port's turn, so **the sweep visits the ports on a
stride of 9**: a read ends eight frames after its select, and the port nine on is
the next one round. 9 is odd, so 64 steps visit every port once: **9 ms**,
whatever the exchange holds. Every port is read, and its M and `BUSY` at its
select are kept with its word. A candidate was free at its select and is a flood
trunk facing a direction asked for; for each direction the sweep keeps **the
lowest-numbered, or the highest where the trunk's word sets glare** (§5). A last
pass, 1 ms, drops any candidate showing M or `BUSY` at its own turn. The origin
and the forwarder share the sweep: a forward waits for one already running, and
for the origin's.

**The hunt hold-off.** A trunk the unit wrote free is no candidate for
256–384 ms. A seizure dropped younger than `T_ARM` — glare, a guard abandon, a
forward whose incoming died — frees at once at both ends, since neither port's
detector had armed, while the far classifier is still timing the low M to tell
a dial break from a death (§3.3). Re-seized inside that, the far end kept its
hold and its cell, which counted the gap as a pulse: a wrong number
(`newimpl/flood-study/REPORT.md` C03 against C05, and C20). An older trunk's
drop needs no hold-off: its port stays `BUSY` `T_REL` on its detector. One slot
a direction, the last trunk the unit dropped that way, aged on a 128 ms tap:
about six packages (Joel, 2026-09-27).

### 3.3 The classifier

A port showing M with `BUSY` clear is an incoming seizure or a caller, and only
its card knows which. The classifier takes such a port — not 00, not one the unit
seized itself, not one its bit says is dealt with — and reads its word. **A flood
trunk** (class trunk, member 0: `card-word.md` §2) is **held**: written listening
to 00 with `BUSY`, so the marker never takes its M and no hunt takes it. It gets
a monitor if one is free (§3.4) and goes to the forwarder (§3.5). Anything else —
a line, a tone trunk, a channel nailed hop by hop (`card-word.md` §6.4) — is the
marker's.

**The bit a port** is set when the classifier takes the port or sees M under
`BUSY`, and cleared when M is seen down: a waiting line is read once, a trunk
whose `BUSY` falls under a standing M is no fresh seizure, and a missed rise is
read later.

**A hold is watched through the ports' arming time.** A port's M detector rises
only after `T_ARM`, 16 ms, and a port clears itself only on a detector's fall
(`fabric.md` §5.3), so a seizure that dies sooner — a far origin abandoning,
glare, a bounce — would leave the hold `BUSY` for good. For `T_ARM` the
classifier watches it. **M down in the watch is not yet a death**: a flood that
arrives late may show its first dial break there. M back inside `ID`, 128 ms,
was a dial break: the hold stands and the watch starts again from the make. M
down for `ID` is no dial pulse: the classifier writes the hold away, calls off
the forward, and frees the hold's monitor cell with it. Written away at the
break, the make after it was a fresh seizure and a fresh cell counted `e` one
short: a wrong number (`newimpl/flood-study/REPORT.md` §5.1, C05). The
classifier takes no other seizure meanwhile, so a burst is classified about one
each 18 ms, and a death holds it 128 ms; one seen while a sweep has the reader
is read ahead of its next step.

### 3.4 The monitors

A **monitor** decides whether a seizure is this exchange's call. It is not a
register: every flood wants one at every exchange, and a busy monitor loses a
call this exchange owned where a busy register only delays a caller's dial
tone. (A claim loses the call on a busy register too, so it has one of its
own: §4.2.) **One pool,
on the unit**: each cell is a probe on the held port, a `pulse_rx` with
`register.md` §1's windows and a compare against the code straps, attached at the
hold.

A first digit that is not this exchange's `e` — or 8, 9 or more than ten pulses;
ten count as 0 — lets the cell go at once; a second that is not its `b` likewise.
Both ours: **the claim**, a request held as a level until the unit writes `CLAIM`
(§4.2). Two digits and no more. **A break of `ID`, 128 ms, frees the cell**
whatever it was doing: no dial pulse is that long, so the trunk released —
and a far port whose RC runs short (80 % of nominal `T_REL` is 205 ms) can
clear and the channel be seized again inside 256 ms, when a cell still
counting took the death and the make for a pulse. So does the classifier
writing its hold away (§3.3). **A cell older than 2 × `T_KEY`** (an age of two
bits a cell on a shared strobe every `T_KEY`: 10–15 s) lets go: a seizure
nobody dials on, a stuck A conductor, would otherwise hold it for good. The
hold stays, parking the port `BUSY` until the fault is mended. **With no cell free the seizure is still held and
forwarded**, but this exchange cannot own the call. **Three rules** keep a
monitor from claiming a wrong number (measured: `analysis/monitor-rules.md`):

1. **A monitor counts only a seizure whose rise it saw**, or it may count `b` as
   `e`. The classifier takes a port only on a rise its bit has seen, and the cell
   attaches 2–3.5 ms after it, up to 20 ms behind a classifier busy with an
   earlier hold: time inside the guard's budget (§6).
2. **The origin abandons a call whose next break comes inside the guard** after
   its seizure (§6): a caller who dials before the flood has reached the last
   exchange has a pulse swallowed there, and only the origin sees both events.
3. **A claim coming back is not a seizure.** A far claim is M rising on a trunk
   this exchange holds: the classifier ignores M under `BUSY`, read in M's own
   bit-time, and every port the unit seized itself.

A claim is held, not pulsed: cells on one 1 ms tick can decide together, and the
unit serves one a tick.

### 3.5 The forwarder and the resolvers

The **forwarder** passes a held seizure into every direction but the one it came
from and any strapped one (§7). It sweeps once and writes a **leg** in each
direction where it found a free trunk, listening to the incoming trunk with
`BUSY`, so the caller's pulses go down every leg at once. **With one leg** (a
chain transit) it also writes the incoming trunk listening to the leg, both ways
at once. **With two or more** (a hub) the incoming trunk stays on 00 until a leg
claims.

**A resolver is taken for every forward**, one leg or three, and watches the
incoming port and the legs once a pass. A leg's M standing four samples, 4 ms,
the same rule as the origin's claim (§4.1) — that branch claimed: it
patches the incoming trunk to that leg (done already with one leg), drops every
other leg to 00 with `BUSY` clear, each then releasing itself, and frees itself.
The incoming trunk's `BUSY` falls before any claim: it drops every leg and frees
itself. **A leg seen `BUSY` and then free has released itself** and is no longer
the forward's — M on it is no claim, and a claim or a drop leaves it alone — and
a forward whose every leg has gone frees itself, writing nothing: an incoming
trunk whose link is down stays `BUSY` (`MUTE_BLK`), so its `BUSY` never falls,
and the stale resolver cut or re-pointed the live calls later hunted onto its
legs (`newimpl/flood-study/REPORT.md` §5.2, C10). **A resolver older than 2 × `T_KEY`** drops its legs, as a cell
lets go (§3.4); one that patched a single leg both ways puts the incoming trunk
back on 00, still held. This exchange claims: the claim's own write drops the legs (§4.2). A
chain transit needs one as much as a hub: a leg written after the caller's A has
gone has no edge left to release on. A fan-out of two or more legs is **built,
and not run.**

**One forwarder.** A seizure held while the forwarder is busy, or while no
resolver is free, is held and watched **but never forwarded**; a forward that
finds no free trunk anywhere writes nothing, and one that finds none in some
directions skips them. The unit counts the first two in `n_nofwd`, a bench
output; nothing on the bus reports any of them. The flood then silently misses
part of the network (§10).

### 3.6 The marker and the unit

The marker never learns what a direction is or hunts a trunk; the unit never
attaches a register.

| line | way | what |
|---|---|---|
| `/NET` | unit → marker | grounded by the unit, pulled up at the marker. Low: `1` is the key, and the mini marker reads a port's word before it takes its M as a call or connects it (`marker.md` §3). High: `1` is highway 1 (`numbering.md` §3) |
| `flood_go` | marker → unit, a tick | the key: the marker consumed a first digit `1` at once, restarted the register so `e b h s` land in its first four slots, took dial tone off, and waits in **YIELD** |
| `local`, `done`, `nogo` | unit → marker, a tick each | the code is this exchange's: the store has restarted again, and `h s` follow as a local number · caller ↔ trunk is written: free the register · cannot-complete this origin call (§4.1) |
| `att` + port | unit → marker, **a level** | a claimed trunk wants a register. Raised only once the unit's `CLAIM` word has left its queue; held until `att_ack` |
| `att_ack` | marker → unit, a tick | the trunk has the claim register (the class marker: its register) as a caller with no dial tone, `CLAIM` on every later write to it until release; **or** that register was busy and the marker wrote the trunk to cannot-complete with `BUSY` and `CLAIM` — after the unit's `CLAIM` word, since `att` waited for it |
| register ribbon | tapped | the caller's port, the digits and their count, `brk`, `gone`, `nodig`, busy (`register.md` §3). The unit's `restart` is ORed with the marker's |
| `/UREQ` | unit → bus | low while the unit has writes queued: the marker finishes its word and starts no other, and the unit drives after `WAIT`, 640 master ticks. No grant (`bus.md` §5) |

In YIELD a hang-up is abandon and the no-digit timeout cannot-complete. One key
a call (`numbering.md` §3). A claim that finds the register in a watch after a
connect is refused at once, like any other (`marker.md` §4.8).

### 3.7 Sizing

Measured under random traffic (`newimpl/flood-study/REPORT.md` §2; two exchanges, a three-exchange chain,
a hub of three leaves):

- **Resolvers: `NRES` ≥ the number of source exchanges** whose floods reach this
  one — every leaf behind a hub, both ends of a chain transit. An exchange's one
  register lets it have one flood pending at a transit at a time, so the loss is
  Engset in the sources, not Erlang B (§10). A hub with `NRES` 2 and three
  leaves lost 1 flood in 30 at light load and 26 % at overload; with 3, none of 44.
- **Monitor cells: `NMON` 3 at a hub, and at a leaf once the hub originates.**
  Every flood in the network holds one of the hub's cells until its `e` is
  decided, ≈ 0.9 s, so a call *to* the hub is lost when two others are in that
  window.
- **Channels on a spoke ≥ the calls talking on it + the number of leaves**: a
  flood holds a channel on every spoke until its claim, and on 2-channel spokes
  29 of 81 attempts found no trunk. A fan-out into a full spoke silently misses
  the owner behind it.
- **Strap a leaf's absent directions** (`STRAP_N`, §7; no parts). A leaf has
  nowhere to forward, but without the strap every seizure it holds runs a 10 ms
  sweep that finds nothing and counts in `n_nofwd`, which then cannot tell a
  lost flood from a leaf (`tb_chain`, `tb_lchain`).

## 4. A call across the network

### 4.1 The origin

```
 key       flood_go; sweep every direction.  None free anywhere → the event
           word EV_NOTRUNK, code 10 with DST 00, and nogo.  Else write one trunk
           a direction listening to the CALLER, with BUSY: the seizure.  The
           guard and the 5 s rule count from this write
 e, b      8, 9 or more than ten pulses → drop the trunks, nogo.  This
           exchange's own code → drop the trunks, restart, local
 claim     M standing on a held trunk for four samples (4 ms), after b.  Keep
           it; drop the others at once.  Inside the guard it is glare, taken
           as the claim all the same (§5).  Standing before b outside the
           guard, no monitor can have claimed: drop the trunks, nogo
 connect   at the claim, once the others are dropped: write the caller
           listening to the kept trunk; done, and the register is free.  h s,
           or a one-key number, go down the trunk live as they did before it
 gone      the caller hangs up, or the register times out or frees: drop the trunks
 nogo      a break inside the guard (§6), or between the key and the seizure
           write; b not counted 5 s after the seizure; no claim 2 s after the
           origin's register counted b
```

The caller hears silence from the key to the claim, and the owner from then on:
its refusal or busy tone the moment it decides, not after `h s`. **Connecting at
the claim frees the register ≈ 2 s sooner**, and that is when the other
exchange's claim would find it busy: waiting for `h s` made two exchanges'
registers refuse each other's claims, and two-way traffic past about one attempt
a second collapsed to no calls at all (`newimpl/flood-study/REPORT.md` §3). **The 5 s rule** keeps an
accidental key from holding a channel on every link for the register's 10 s; a
slow dial reaches the code 00 in 3.8 s. Event words: `proposed/counters.md` §5.

### 4.2 The owner

When a cell claims, the unit writes in one push the incoming trunk listening to
00 with `BUSY` and **`CLAIM`**, and drops every leg of its own forward of that
trunk; the cell is free at that write. A port with `CLAIM` sends backward A = 1
until release (`fabric.md` §5), so the claim crosses every patch to the origin.
Once the word has left the queue the unit raises `att`, and the trunk becomes a
caller like a line: **the claim register** reads `h s`, `0` or `9` off its A,
the far caller's next digit at least ≈ 590 ms away (a 720 ms pause less `ID`).
It is a second register that no local caller takes (`register.md` §4), so a
claim is refused only while it is on another claim — never because this
exchange's own caller is dialling, or dialling out. **Busy
is the owner's to say**: its marker gives the trunk a tone, heard through the
path already up (`marker.md` §4.8, `numbering.md` §4). Release is A falling through
every patch, each port clearing itself (`fabric.md` §5); a dead link drops its A
too (`trunks.md` §1).

### 4.3 Worked: line 44 of 22 dials `1 2 4 5 5` on the chain 22 ═ 23 ═ 24 ═ 25

10 pps, 60/40, 0.8 s between digits; milliseconds from lifting; the mini marker
everywhere; a hop of about 12 ms (§6). **Arithmetic on the RTL's constants, not
a bench run.**

```
   1188   22   44's 1 (ended 1060) is in: flood_go.  1199: the seizure toward 23
   1200   23   M rises: held, monitor on.  1212: a leg toward 24, a resolver taken
   1213   24   the same; a leg toward 25 at 1225
   1226   25   held, monitor on; no leg
   1327   22   the guard ends (128 ms tap)
   2148        "2" (ended 2020) is every monitor's e: all three read on
   3308   23   "4" (ended 3180) is not 23's b, nor 25's: those monitors let go
   3308   24   "4" is 24's b: CLAIM on the trunk from 23; the leg toward 25 dropped
   3310   23   the resolver sees M on its leg and frees itself.  24: att
   3311   22   backward A: the claim.  44 ↔ trunk, done, the register freed
   3565   25   its held port has released itself: link 24–25 is free
   5832   24   5 5 in, down the connected path: the trunk ↔ 55, CLAIM kept;
               55 rings; 44 hears ringback at 5833
```

Until the claim the call holds a trunk on every link, a monitor at 23, 24 and 25
and a resolver at 23 and 24; after it, two trunks patched at 23. **Every call
that leaves holds that much until `e b` are dialled**: 2.0 s for the code 11 up
to 3.8 s for 00, 2.7 s on average (`exch.py flood` 5). A call from the middle
floods both ways and drops the losing direction at the claim (`tb_chain`).

## 5. Glare

Both ends of a link can seize one channel before either sees the other. **The
ends hunt in opposite order**: the trunk cards at one end set the word's glare
bit and their sweep takes the highest free channel, the other end's the lowest
(§3.2), so both reach one channel only when it is the last free one.

**Glare is taken as the claim, and the two callers are joined.** Each origin sees
M on a trunk it holds — the other caller's hook — and takes it as the claim;
inside the guard, where no real claim can come (§6), it also counts it
(`n_glare`) and sends `EV_GLARE`, code 04 with `DST` the trunk
(`proposed/counters.md` §5). Neither classifier takes the channel, which each end
seized itself (§3.3); each origin connects at that claim, and the
two callers talk with nobody rung (`tb_lfull`). At a transit a glared leg is its
resolver's claim; not run.

## 6. The guard

The origin drops its trunks and gives cannot-complete if the caller's next break
comes inside **the guard** after its seizure write (rule 2, §3.4), or between
the key and that write, where a single-pulse `e` can break while the origin
sweeps: a failed call in place of a chance of a wrong number. **The tap is a two-bit strap on the unit,
`GUARD`: 128 ms doubled by each step of the code, 128, 256, 512 or 1024 ms.**
Code 3's 1024 ms is past the ceiling below and abandons conforming dials (§10).
It is the one number in the protocol that says how big the network is, and the
planner sets it the same at every exchange.

**It must cover**, from the seizure write, every transit's hop, the last
exchange's monitor attaching (§3.4), and any wander a carrier loses; **not** a
carrier's transmission delay, which the seizure and the pulses share. **A hop is
mostly a sweep**: the seizure seen (≤ 1 ms), the word read at the port's next
turn (≈ 1.1), the hold, the sweep's start (≤ 1), the sweep and its last pass
(10), the legs written (≈ 0.5): **≈ 12 ms typical**, and **≈ 22–30 ms slow**,
when the forward waits for a sweep already running (≤ 10 ms more) or the
classifier is still watching an earlier hold through `T_ARM` (≈ 17 ms more). So
128 ms covers ≈ 10 typical hops and ≈ 4–5 slow ones; 256 ms ≈ 21 and 8–11; 512 ms
≈ 42 and 17–23.

**The guard must cover the slow case**: past it is a wrong number, not a failed
call. **Measured at real timers** on an eight-exchange chain (`newimpl/flood-study/REPORT.md` §2.4): a hop
is 13 ms (2.1–2.9 to classify, 10.6–10.8 to the forward write), 18.5–21 ms
behind a flood still in the watch, ≈ 30 ms behind another sweep; the 128 ms tap
reached 8 hops with no slow event, 7 with one, and **4–5 against three
compounding slow events** in a burst of coincident keys. A conforming 720 ms
pause leaves ≈ 590 ms of margin, so the reach matters for fast diallers (a data
card pulsing DTR) and deep networks. The benches dial 8× fast and test the
mechanism, not the reach.

**Bounds.** Above: the caller's pause less ≈ 139 ms (the digit recognised,
128 ms, then the origin's sweep and seizure); a telephone to ES 201 187 pauses at
least 720 ms, so ≈ 580 ms, and 512 is the last tap under it. Below: nothing.
*Not* the earliest claim: a claim needs two more digits, so M on a held trunk
inside the guard is glare (§5). **A longer tap costs the fast caller**: one with
less than the tap plus ≈ 139 ms between digits is abandoned — under 267 ms at
128, 395 at 256, 651 at 512, 1 163 at 1024. No other timer moves with the hop
count.

## 7. Rings and the strap

A flood sent round a ring comes back to its origin and goes round again, taking a
channel of every link at each turn (`analysis/topology.md` §7). **The ring strap
belongs to a link**, so it is one a direction on the unit (`STRAP_N`), not a bit
of a trunk's word and not a property of an exchange. **A seizure is never
forwarded into a strapped direction, and one that arrives on it is never
forwarded onward.** An origin still seizes it and the far end may still claim:
the link carries the calls between its own two ends.

**The links without the strap must form a tree**: one strapped link a ring, one
in every independent cycle of a mesh. **Strap both ends**: one end alone breaks
the cycle, but the other floods into a link that goes nowhere. At the two ends a
call arrives twice; the direct copy claims first and the origin drops the long
way, which may claim too, gets a register or a refusal (§4.2) and releases
unheard. **A ring is also a spare**: move the strap to a failed link and the ring
is a chain again.

**What getting the strap wrong costs** (run at 8× and at real timers:
`newimpl/flood-study/REPORT.md` §5.4, C19). **Unstrapped**, every call circulates, and only the pools
bound it: channels, cells and resolvers burn at every member, and owners claim
twice. **Strapped at one end only**, every call from *or to* the strapped end
arrives twice at its owner and is claimed twice: one copy gets the register,
the other a refusal, and when the refusal's claim reaches the origin first the
call fails — seen at real timers with conforming dials. Strapped at both ends,
each call is claimed once.

## 8. Clocking

**The network is plesiochronous.** Every exchange runs on its own ±20 ppm crystal
(`common/clocks.md` §2); no clock card is slaved to a trunk and no trunk re-frames
octets. Each trunk card crosses what it receives into its own frame, and between
neighbours up to 40 ppm apart a crossing slips a bit every 390–780 ms: below the
codec, 34.8 dB at 20 ppm against CVSD's own 25.4 (`mf8/mf8-backplane.md` §7).

**What crosses a tie.** CVSD voice, and async data oversampled at up to
9 600 bps (a slip moves an edge 15.6 µs), cross any tie. Synchronous data (HDLC)
crosses only a tie whose two ends share one clock card, bit-exact; on two clocks
a slip is a lost or doubled bit. **G.711 and other octet-framed data cross no
tie**, only a connection inside one exchange (`fabric.md` §2.3): each end frames
on its own `SCAN`, and the two directions' octet errors sum to 2 frames mod 8,
so no alignment of the counters fixes both (measured, `trunks.md` §2).

## 9. Set aside

- **A register-sender**: post-dial 0.49 s against 0.13 s (`exch.py flood` 1–4).
- **Serial characters on A** (`exch.py aline`): a second signalling system.
- **An in-band DTMF sender**: the caller's own pulses do its work.
- **Hop-by-hop dialling, route jumpers, a hub's sender and matrix**: §1.
- **A wink for the claim**: a wink clears every patch it crosses (§1).
- **`e` as the key**: local calls flood too, 0.35 E a link against 0.19 E.
- **One channel through every exchange**: 4.1 % blocked, chain of eight at 1 E.
- **A gateway behind `1 8`, `1 9`**: both stay reserved (`numbering.md` §5).
- **Octets across a tie**: a re-framer a card; nothing outside speaks G.711.
- **Slaving the clock cards**: nothing needs synchronous data between exchanges.
- **A bigger slip buffer**: slips rarer and longer, never fewer.

## 10. Open

- **Resolver loss at a transit is silent.** Every forward takes a resolver; with
  none free the seizure is held but not forwarded, and the caller times out
  2 s after `b` having held a channel and a trunk ≈ 4.5 s. With one register
  an exchange, at most one flood per *source exchange* is pending at a transit,
  so the loss is **Engset in the sources** — measured on the chain, `NRES` 1:
  22.9 % against 22 % predicted; `NRES` 2: 0 of 293. With u the source
  register's network occupancy (`newimpl/flood-study/REPORT.md` §2.2):

  | `NRES` | sources | u = 0.25 | 0.5 | saturated |
  |---|---|---|---|---|
  | 2 | 3 | 1.2 % | 4.8 % | 19 % |
  | 2 | 4 | 3.2 % | 11 % | 36 % |
  | 2 | 8 | 15 % | 36 % | 67 % |
  | 3 | 4 | 0.1 % | 1.1 % | 8.5 % |

  The one forwarder loses nothing at real timers — the 18 ms watch spaces
  classifications wider than its 10.6 ms forward (0 of 27, crossings
  included); the 8× benches overstate it. Nothing counts the loss
  (`proposed/counters.md` §7). Options: `NRES` by §3.7, a transit that claims
  a flood it cannot pass on, to refuse it at once.
- **The guard's reach, and a flood picked up late.** Measured (§6): 7–8 hops
  typical, 4–5 compounding at 128 ms; the chain, tandem and "63 exchanges at
  128 ms" limits of `analysis/topology.md` and `analysis/traffic.md` still need
  re-running at that hop. Past the reach the watch's wait (§3.3) makes most
  late floods a lost call, not a wrong number — but not a trunk the classifier
  first takes *after* its first dial break: after every watch it restarts at
  port 00, so a high-numbered trunk can wait behind others, and its make then
  reads as the rise. The timing study's fix, a memory of a rise, a break and
  a rise again a port (three bits a port: a RAM or 24 '164s), turned every such
  wrong number into a lost call (`newimpl/flood-study/REPORT.md` §4, `work/load/timing/fix`); not taken.
  Options: that memory; plan on 256 ms; a forward that need not wait for a
  running sweep; a classifier that watches more than one hold.
- **`GUARD` code 3.** The strap's fourth code gives 1024 ms, past §6's ≈ 580 ms
  ceiling: an exchange strapped 3 abandons every caller who pauses less than
  ≈ 1.16 s between digits, conforming dials included. Options: a jumper field
  that cannot make code 3, or another meaning for it. Not a bench question.
- **Left open by the flood study's fixes** (`newimpl/tb/tb_fl_chain.v` headers,
  2026-09-27). **A blip, then a real seizure inside `ID`**: a noise blip on an
  idle trunk's A is held, and a genuine seizure of that channel within 128 ms
  looks like a dial break to the watch's wait (§3.3), so the blip's cell counts
  the gap as a `1` — a wrong number at an exchange whose `e` is 1, a lost call
  elsewhere. The hunt hold-off (§3.2) covers only a far unit that itself wrote
  the channel free. Options: two samples of M before the classifier takes a
  port (a second bit a port). **The killer trunk**: a stuck A conductor is
  parked `BUSY` at the far end once its cell and resolver age out (§3.4), but
  the near end still reads the channel free and every call from it that way
  takes it first and fails. Options: the far unit writing the parked port to a
  tone so the near caller hears it; a word the far card can clear.
- **The unit's writes want a sequencer.** The unit decides up to five writes in a
  tick (a `CLAIM` and four leg drops) and hands them to `ctl_queue`, a model
  part. A board needs a stepping sequencer, a word at a time, with the watches
  running on their own; a 16-deep FIFO would be a memory part. Not drawn.
- **The rest of the card.** One origin bank serves one register; a pool wants a
  bank a register (`register.md` §5). The monitor pool must be sized again as
  one pool (`analysis/monitor-rules.md` §6). A flood through the class marker
  has run nowhere (`marker.md` §7). The card is not drawn.
- **Relayed dial pulses.** Each exchange a pulse crosses re-samples it once a
  pass, at 1 kHz; nothing measures a relayed pulse, or the shortest break after
  many hops.
- **Not run**: a hub's fan-out, a ring and its strap, glare at a transit, how often an accidental `1` happens (a flood and a
  cannot-complete, never a wrong number), and how fast people dial between digits
  (under ≈ 267 ms the 128 ms guard abandons them).
