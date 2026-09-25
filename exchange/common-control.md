# The exchange — common control as replaceable units

The fabric, the ports and the cards behind them do not change from a two-line
box to a networked one. What sits at the common-control tap does: a **marker**,
one or more **registers**, and — only if the exchange is on a network — a
**network unit** and **monitors**. Each is a card (or a pool of identical
cards) that can be unplugged and replaced by a simpler or a fuller one, because
they talk on named ribbons of **levels**, not by reaching into one another's
state.

The solo exchange of `mvp.md` is this tap with the smallest marker and one
register, and nothing of the network. A pulse-flood exchange is the same tap
with a network unit and monitors added. The mini-marker of `mini-marker.md` is
a marker: it is allowed to stay fitted when those go in.

> **Status: proposed.** The split is the one `network.md` §3.2 already named —
> the marker hunts a class and knows nothing of directions; the network unit
> holds the flood — and that `marker.v` had folded the flood back into the
> marker. The ribbons are the ones `register.md` §6, `monitor.md` §6 and
> `marker.md` §4 already carry, written as a contract so a second marker or a
> second register can speak them. `make mini` is a marker with no network unit;
> `make net` is a marker with one. Nothing has been on a bench.

---

## 1. What is fitted, and what is not

```
 HA, PB, SLOTQ, TICK ──┐
                       ├── marker ──── ribbon ──── register × N
 cable B (SDATA, SCLK, │      │
   WR, PB, /CON) ──────┘      ├── /HUNT_INH, the probe, flood_go
                              └── network unit (optional) ── CLAIM_REQ ── monitor × M
                                                              (on each trunk block)
```

| unit | always | does | may be |
|---|---|---|---|
| **Marker** | yes | scans, probes, attaches a register to a caller, writes latches, hunts a class if it has one | mini-marker (`mini-marker.md`); the class marker (`marker.md`); later, one that reads nails and answers-to |
| **Register** | yes | counts pulses on one caller's M, holds four digits, `restart`, `gone` | `register.md` §4's pulse collector; later, the same store with a DTMF writer (`register.md` §7) |
| **Network unit** | no | origin flood, transit forward, resolvers, own-code, guard, CLAIM writes | a one-direction jig (jumpered trunk ports, no `/HUNT_INH`); the card of `network.md` §3.2 |
| **Monitor** | no, and not on this tap | reads `e b` off a trunk's M, holds a claim until acked | `monitor.md`; a one-cell pool on a bring-up block |

**A local call never needs the last two.** `h s` is the marker and a register.
**A flood never needs a smarter marker.** The mini-marker plus a network unit
plus monitors on the trunk block is a pulse-flood exchange. The class marker
is what you fit when 0 and 9 must hunt, when a card's word must be read, when
a nail or an answers-to has to fire — not when you want trunks.

The fabric and the line cards do not move. Common-control cards are a family
you may swap. That is the exception to `mvp.md`'s "never by changing what is
already fitted", and it is only these cards.

---

## 2. The ribbons — levels, not events

`rtl.md` §1: an event on a wire is a race; a level valid when read is not. Every
line below is a level, held until the other side has seen it.

### 2.1 Marker ↔ register (`register.md` §6)

The short ribbon already there. One copy a register.

| from the marker | |
|---|---|
| `attach` + `attach_port` + `attach_src` | seize this register for this caller; `attach_src` is the held party or `00` |
| `release` | clear the store and go free |
| `restart` | begin the store again, caller unchanged |

| from the register | |
|---|---|
| `busy` | held |
| `digits`, `N` | the store, as pulse counts |
| `gone`, `nodig` | CLR, or the no-digit timeout |
| `brk` | a break just counted — the origin guard reads this (`monitor.md` §3, rule 2) |

The network unit **taps** `digits`, `N`, `brk`, `gone` and may pulse `restart`.
It does not sit in the register. The store is four digits so that `e b h s`
land after the key is consumed; that is why `restart` exists, and it is why
`restart` is on this ribbon rather than inside one marker.

A register that speaks this ribbon can replace another. The mini-marker may
keep its one collector on the same card; the wires are still these.

### 2.2 Marker ↔ network unit

The network unit sits on the same tap (`mainboard.md` §2.4) and watches the
scan. It is another master of cable B for the writes it owns (seize, forward,
CLAIM, drop), the way the console is. Until that third master is drawn, the
RTL marker **drains a burst of writes** the unit queued — same words, one
serialiser.

| from the marker (and its probe) | |
|---|---|
| scanned port, `M`, `BUSY`, the word, `visit` | the probe, already on the tap so a card can watch without the marker knowing what it is looking for (`marker.md` §4, `network.md` §3.2) |
| `flood_go` + the caller's port | this register just consumed key `1` and has restarted; the unit owns the call |
| `/HUNT_INH` is **to** the marker | the unit rejects a port whose word faces the wrong way; the mini-marker has no hunt and does not need the line |

| from the network unit | |
|---|---|
| `restart` | own `e b`: begin the store so `h s` land as a local number |
| `local` | the origin call is local from here; the marker goes back to collecting |
| `done` | the pair is written; free the register |
| `nogo` | cannot-complete this origin call (no trunk, 8/9 in the code, guard, no claim, `b` not in 5 s after the key) |
| `attach` + port | a monitor claimed: give a register this trunk as a line, keep `CLAIM` on later writes. None free: the marker points the trunk at cannot-complete, `BUSY` and `CLAIM` set |
| latch writes | seize / forward / CLAIM / drop; `CLAIM` is bit 0 of the word (`mainboard.md` §2.3) |

**Key `1` is not a highway and not a hunt the marker completes.** With a
network unit fitted (a jumper, or the card present), the marker consumes the
digit at once, restarts, drops dial tone, and raises `flood_go`. It does not
learn a direction and it does not wait for a claim. Without the unit, `1` is
highway 1 (`protocol.md` §5). The diode that used to live on the marker lives
on the unit, which is why a solo exchange can dial `1 s`.

**A trunk's M is never a call request at the marker.** Class trunk, or a
jumpered mask on a mini-marker that does not read the word, is the unit's:
hold the port busy listening to idle, and forward. Leave this as `M · /BUSY`
and a flood seizes a register at every hop.

**`CLAIM` sticks** until release (`rtl.md`, `fabric.md` §3.5). The marker
keeps the bit on every later write to that port (dial tone off, the connect).
The unit set it.

### 2.3 Network unit ↔ monitor (`monitor.md` §2, §6)

Monitors sit on the trunk block and never touch the fabric.

| from the monitor | `CLAIM_REQ` + the channel, **held until acked** (`rtl.md`: a pulse is lost when two cells decide together) |
| from the unit | the ack, which frees the cell; the unit writes `CLAIM` and asks the marker for a register |

The marker does not see a monitor. A claim that finds no register is still
claimed: after the unit's `CLAIM` word the marker points the trunk at
cannot-complete, `BUSY` and `CLAIM` set, and the caller hears it through the
path already up (`monitor.md` §2).

### 2.4 `/HUNT_INH` and the probe on cable B

The two things a standalone marker must already carry so the unit can plug in
without a new marker (`mvp.md` §5, `network.md` §3.2):

- the scanned port's `M` and its word beside the write, on the '244s
- one pulled-up hunt input, *accept* with nothing driving it

The mini-marker has no hunt, so `/HUNT_INH` is unused. It still puts `M` (and
`BUSY`) out, and it still accepts the attach / `CLAIM` / `restart` side of §2.2.
A one-direction bring-up hunts by a **jumpered port mask**, not by the word.

`mainboard.md` §9: `M` has never been listed as a conductor on cable B. It
belongs to this tap, not to the block ribbon.

---

## 3. The solo exchange

`mvp.md`. Two line cards on block 2, one register, a marker, the clock card.
No network unit, no monitor, no trunk card.

```
 first key   1–7   highway h; wait for s; called = h s
             0     04, then whoever answers to it — cannot-complete if this marker has no hunt
             9     hunt class outside line, or cannot-complete
             8 * # cannot-complete
```

Digit `1` is a highway. Ports 10–17 are ordinary lines in the numbering, even
when none are fitted. That is `protocol.md` §5's standalone map, and it is
what the mini-marker already does. A class-4 hunt that finds nothing is **not**
how a solo exchange refuses `1`: that hunt belongs to the network unit, which
is not here.

Wrong numbers, release, a second caller waiting for the one register: `mvp.md`
§3–4. Growing lines, tones, an operator, outside lines: `mvp.md` §5, still
cards. Growing a **network** is §4 below, still cards, and either marker.

---

## 4. A basic pulse-flood exchange

The same marker — including the mini-marker — plus:

| fit | |
|---|---|
| network unit | own-code jumpers `e b`, the origin guard jumper, one seize-bank a register, the forwarder; resolvers only at a hub |
| block 1 | MF8 block adapter (six channels on the block header), `/ANS` low, word = class trunk + direction (or a jumper mask if the marker does not read the word) |
| monitors | two or three on that block (`monitor.md` §4) |

Origin: key `1` → `flood_go` → the unit seizes one free trunk every direction,
each listening to the **caller**, so the rest of the dial goes down A live.
Own `e b` → drop trunks, `restart`, `local`. Else wait for a claim, keep that
trunk, pair caller ↔ trunk, `done`. Guard, 8/9 in the code, no trunk, no claim,
`b` not in 5 s after the key: `nogo`.

Incoming: M on a free trunk → the unit holds it, forwards into every *other*
direction (one direction: hold only). Monitor match → `CLAIM`, attach a
register to the trunk, the register reads `h s` as from a phone.

A two-exchange chain is that list with one direction and no resolver. Hub
fan-out and the glare / no-forward jumper are the same unit with more parts
(`network.md` §3.2–3.3). They are not a smarter marker.

---

## 5. What each replacement is allowed to drop

| | mini-marker | class marker | network unit, one direction | network unit, hub |
|---|---|---|---|---|
| card word | no | yes | uses it if present, else a port mask | yes |
| class hunt | no | yes | hunts trunks by watching the scan | the same, plus resolvers |
| `/HUNT_INH` | unused | pulled up | unused if it hunts itself; drives it if the marker hunts class trunk | the same |
| key `1` | highway, or `flood_go` if the unit is fitted | the same | consumes it | the same |
| 0, 9 | cannot-complete | hunt | — | — |
| nails, answers-to, restricted | no | yes | — | — |
| `CLAIM` sticky | yes, once a unit has attached | yes | writes the bit | the same |
| ignore trunk as caller | by mask | by class | holds and forwards | the same |

The register does not gain parts when a network unit is fitted. The trunks an
origin seized live in a bank **on the unit** (`network.md` §3.2).

---

## 6. Not measured

- **A third master on cable B.** `mainboard.md` §2.3 is marker or console. The
  unit as a master is specified here and in `network.md` §3.2. newimpl's RTL
  has it as a second master, with its own serialiser and `/UREQ`
  (`newimpl/README.md` §5); no console is built, so a third has not been run.
- **The probe's `M` as a pin.** `mainboard.md` §9.
- **Mini-marker plus a network unit as a hub.** newimpl's `make net` and
  `make chain` run the mini-marker with a unit at one and two directions; a
  hub, three or four, has not been run. The retired tree's `make mini-net` was
  a one-direction chain, and its `make net` the class marker plus the unit,
  including hubs.
- **Swapping a marker on a live fabric.** Specified; not tried.
