# The exchange — the minimum that makes calls

The smallest exchange that does automatic calls: two phones dial each other with
two digits, one rings, the other hears it ringing, they talk, and either can
hang up first, with nobody in charge of the call. Every part of it is a part of
the full exchange (`fabric.md`, `marker.md`). It grows into the
48-line exchange by adding cards, never by changing the fabric or the line
cards. Common control is a family you may swap: a mini-marker stays a marker
when a network unit is added (`common-control.md`). A network is those
cards, not a different marker.

> **Status: proposed; measured in simulation as a whole.** `exch.py calls` 19
> runs this configuration: two rotary phones, one register, no tone
> cards, nothing else. It makes a call each way, releases in both orders, then
> dials 0, 9 and 8 — the first keys that go nowhere on an exchange this
> small — then `1` as a highway and hangs up, then an empty number and the
> caller's own number. Digit `1` as a highway is the standalone map
> (`protocol.md` §5); the timestamps in §4 for 0, 9, 8, 25 and 20 are from
> that run. Every latch ends idle. The package counts come from the parts
> lists of `fabric.md` §3 and §5 and `channel-cards.md`, except the marker's,
> which is estimated by function (§2). **The register is a pool member and
> takes no port**, matching the design (`marker.md` §4). No circuit has been
> drawn, and nothing has been on a bench.

---

## 1. What is fitted

```
 phone ── line card, slot 20 ──┐                                  clock card ── every clock, FILL, RING_CAD, TICK
                               ├── block 2 ── HC[2], HA[2] ──┐
 phone ── line card, slot 21 ──┘   port circuits 20, 21      └── marker ── one register
```

| | does | ≈ packages |
|---|---|---|
| Clock card | `HCLK`, `SLOT`, `SLOTQ`, `TX_CLK`, `TX_OCT`, `FILL`, `RING_CAD`, the 1 kHz `TICK` (`fabric.md` §2) | 10 |
| Block 2, its shared parts | commutators, strobe and write decoders, highway drivers and receivers (`fabric.md` §3.1) | 13 |
| Two port circuits | each a crosspoint of 5 and supervision of 3¼ (`fabric.md` §3.2, §3.5). **The block's other six port circuits are not populated** — a port circuit exists only with its card on a **slot** of the block ribbon (`fabric.md` §5.1) | 17 |
| Marker | scanner, probe, sequencer. 0 and 9 go to hunts that find nothing; 8 to cannot-complete; **1 is a highway** (§2, §4). The mini-marker of `mini-marker.md` is this job with no word and no hunt | 15–20, estimated; the mini-marker is less |
| One register | `register.md` §4's pulse counter, reading the caller's hook off the M highway through its own probe (`marker.md` §4). On the mini-marker it lives on the same card; the ribbon is the same (`common-control.md` §2.1) | 9 |
| | **exchange logic** | **≈ 70** |
| Two line cards | **either** the analog FXS card, ≈ 11 packages, a transformer and a ring relay each, plus one ring generator for the block's `RING` bus (20 Hz, ≈ 90 V rms); **or** the CVSD subscriber line card, ≈ 10 packages and two transformers each, with no ring generator and nothing above the 48 V feed, for the CVSD phone (`channel-cards.md` §2, §3) | per card |
| Power | 5 V for the logic; the 48 V feed | |

**Not fitted, and not missed:** blocks 0, 1 and 3–7; tone cards and the
ringback card; an operator; outside lines; a second register; trunks, the
network unit and monitors; the console. §2 and §4 say what a caller gets
without each, and §5 how each is added.

---

## 2. Where it sits, and what an absent part reads as

**The one block goes in position 2.** 0 and 1 mean something as a first digit —
the operator, and the network's key — so no number beginning with either ever
reaches a line: lines are 20–77 and block 2 is the first block with ports anyone
can dial (`protocol.md` §5). 8 and 9 are first keys as well, but there is
no block 8 or 9 to lose. Line cards go in any of block 2's slots, and are
dialled `2 0` to `2 7`. A plain line card says what it is with no part and no
jumper: its word pin tied to ground, its `/ANS` pin open (`extensions.md`
§2).

Everything absent reads as idle, and idle is what every rule already expects:

| absent | reads | why that is right |
|---|---|---|
| blocks 0 and 1 | `HC` = `FILL`, `HA` = 0: an absent block's wires are pulled there (`protocol.md` §3; `exch.py fabric` 2) | a cleared latch listens to port 00 (`fabric.md` §3.3). Port 00 is on block 0 and is never fitted anyway, so a cleared latch hears silence and A = 0 with or without block 0 |
| an empty slot, or a slot with no port circuit | its commutator inputs pulled to `FILL`, 0 for `A` and `BUSY`, and its word pin pulled up: no word | class 000, *unequipped*: the marker never writes its latch, and dialling it gives cannot-complete |
| the probe bus `PB` when an absent block is selected | **a pull-down on `BUSY`'s wire and a pull-up on the word's**: not busy, and no word, which is class 000 (`extensions.md` §2.2) | the scanner steps all 64 ports whatever is fitted |
| the ringback card | `RBT` tied to `FILL` | a caller hears silence while the other phone rings |
| tone cards | the marker's hunt for dial tone and cannot-complete finds nothing, and the caller's latch is written cleared | silence where the tone would be; the call still completes (`exch.py calls` 12b, 19) |
| the network unit, and the trunk ports with it | digit `1` is a highway: 10–17 are ordinary lines, none fitted here | a local `1 s` that lands on an empty slot is silence or cannot-complete the way any empty number is. The flood is the unit, which is not here (`common-control.md` §3, `protocol.md` §5) |
| `/HUNT_INH` | pulled up: *accept*, so a hunt is the plain first-free-of-a-class | the one input by which a card not yet fitted will later steer a hunt (`marker.md` §4, `common-control.md` §2.4) |

**The marker, estimated by function.** It is the one piece without a parts list
in `marker.md`. The count is a sketch to size the minimum, not a design:

| function | parts |
|---|---|
| scanner: a 6-bit count, eight ports a millisecond | 74HC393 |
| probe: M from `HA` (highway select, slot select, capture); `BUSY` and the card's word from `PB`, the word into a shift register over the visit | 2 × 74HC151, 74HC74, 74HC164, 74HC30 |
| what goes into the control word's `DST`/`SRC`: the scanner, the register's digits, or a fixed address | 3 × 74HC157 |
| the word out: parallel load, sixteen bits on `SDATA` (`mainboard.md` §2.3) | 2 × 74HC165 |
| sequencer: state count, decode, the class tests, and `/HUNT_INH` into the hunt (pulled up, so nothing here drives it) | 74HC163, 74HC138, 2–3 gate packages |
| control bus drivers — four lines now, the probe's M and word among them (§5) | 74HC244 |
| prefix key → class | a few diodes. **Not** key `1`: that diode lives on the network unit |

---

## 3. A call

`exch.py calls` 19, 20 calling 21. Rotary dials at 10 pps, 60 % break.

```
   0.100  20 lifts            its M rises on HA[2].  The scanner finds it off-hook, idle and not busy
   0.106  register → 20       the marker hands the register 20's port number: within one scan, 8 ms
                              no dial tone card: 20 hears silence and dials anyway
          dial 2 1            the register counts 20's breaks off HA; a digit ends after 128 ms of make
   1.988  20 ↔ 21             128 ms after the last pulse: the marker probes 21 (a line, free, on-hook,
                              settled), writes both latches, and frees the register.  The marker is done
          21 rings            21 is on-hook with E high: its supervision gate gives its card E in the ring
                              cadence, and puts RBT in 21's highway cell (silence here)
   3.488  21 answers          M rises: ringing and RBT stop.  Nothing else acts
   6.000  21 hangs up         21's M falls
   6.266  21 releases         256 ms later (each detector drawn ±20 %) 21's port clears its own latch
   6.284  20 releases         20's E fell with 21's M; 20's port clears its own latch too
   6.290  register → 20       20 is still off-hook with an idle latch: a new call, offered the register
   7.267  20 releases         20 hung up at 7.000; the register let go on the same fall
```

**The second call, 21 to 20, released caller-first**, runs the same way. 21
lifts at 8.000 and finishes dialling `2 0` at 10.660. The call is connected at
10.788 and answered at 12.288. 21 hangs up at 15.000; 21's port clears at
15.266 and 20's at 15.284, and 20, still off-hook, is offered the register until
it hangs up. A second caller lifting while the one register is busy is not
refused: it gets the register once the first caller's number is in
(`exch.py calls` 13: 1.9 s after lifting).

**How A carries all of it.** Every signal in the table above is the A bit.
Each card's M is on `HA` in the same cell as its C bit on `HC`. Each port's A
select and capture bring the other party's M back as E, from the same latch
that picks its voice. The port's supervision gate turns E into ringing for an
on-hook phone and releases the port when M or E falls. The scanner and the
register read M off `HA` through their probes. There is no other signalling
path (`fabric.md` §1.1, §3.5).

---

## 4. Wrong numbers

With no tone card, cannot-complete is silence. The caller hangs up and the port
is free. From `exch.py calls` 19:

| 20 dials | marker | told, s | the port released after hang-up |
|---|---|---|---|
| 0 | no operator fitted: the class-2 hunt finds nothing → cannot-complete | 19.888 | yes |
| 9 | no outside line fitted: the class-3 hunt finds nothing → cannot-complete | 23.288 | yes |
| 1 then hang up | highway 1: dial tone off, waiting for `s`; hang-up frees the register, no cannot-complete latch | — | yes |
| 8 | spare: cannot-complete, and no hunt at all | 29.688 | yes |
| 2 5 | 25 is an empty slot, class 000 → cannot-complete | 33.788 | yes |
| 2 0 | its own number, busy → cannot-complete | 38.788 | yes |

**0, 9 and 8 are refused on the first digit**, 128 ms after its last pulse.
`1` is a highway on a standalone exchange (`protocol.md` §5): 10–17 are
ordinary lines, none fitted here, and hanging up mid-number is abandon
(`mini-marker.md` §5). The flood is a network unit, which is not here
(`common-control.md` §3). What would have followed the key on a network never
matters, and two of the things that may follow it are not implemented anywhere:
`1 8` and `1 9` are reserved for out of the network, and are cannot-complete on
every networked exchange today (`network.md` §6).

Every latch idle and every `BUSY` clear at the end. At no time did a port hear a
call it was not in.

---

## 5. Growing it

Nothing fitted on the fabric or the line cards changes. Each row is cards and
populated parts, and each is measured or specified where the last column says.
**Common control may be swapped** (`common-control.md`): the mini-marker, the
class marker, and a network unit speak the same ribbons, so a flood is not a
new marker.

**That holds for the network too**: everything it needs is on the network unit,
including the trunks an origin seizes — a '574 a direction in a bank a
register — which is why the registers here are the ones a networked exchange
has (`network.md` §3.2). Two things the minimum must carry for that to be
true, and does: **the marker's probe on the control bus**, the scanned port's M
and its word beside `PORT`, `SRC`, `BUSY` and `WR` on the '244s it already has;
and **`/HUNT_INH`**, one pulled-up input to the hunt, which reads *accept*
until a card drives it. A mini-marker has no hunt, so `/HUNT_INH` is unused; it
still puts M out, and it still takes the attach / `CLAIM` / `restart` side of
the ribbon, which is enough for a one-direction flood (`common-control.md` §4).

| to add | fit | where |
|---|---|---|
| lines 22–27 | a port circuit (≈ 8¼) and a line card each, in block 2 | `fabric.md` §3 |
| lines 30–77 | blocks 3–7, ≈ 80 packages each when full | `fabric.md` §5 |
| dial tone, busy, cannot-complete, ringback | tone cards at 01–03 (`protocol.md` §5), and the ringback card on the `RBT` bus. The marker reaches the switched tones by address; a source never listens, so it needs no port circuit | `features.md` §2; `fabric.md` §3.5 |
| more registers | three at 48 lines of dial phones | `marker.md` §6 |
| an operator (0) | a phone on any line card whose word says operator (the card's 2×'165 fitted: `extensions.md` §2.2). 0 hunts that class in fixed order from 00, so 04 is its home once block 0 is fitted; 05–07 and dialable line slots follow | `operator.md`; `calls` 9 |
| the console | a busy-lamp field and keys on the control bus: a manual board, and the bring-up tool | `features.md` §4 |
| outside lines (9) | FXO cards in their exchange build, in any line slots; their word says outside line. 9 takes the first free one in fixed order. A CO ringing in is routed as if it had dialled 0, so fit an operator first | `features.md` §5; `calls` 10, 11 |
| lines at another site | an MF8 link on a block of lines, whose channels become lines *h*1–*h*3 and *h*5–*h*7, and a stock MF8 shelf of line cards at the far end. It is a trunk block whose channels say line | `terminal.md` |
| the network | a trunk block at 10–17 (and further groups in blocks 2+), the network unit and two or three monitors a block, and the exchange's own code `e b` jumpered on the unit. Local numbers in 20–77 stay `h s`; standalone had `1` as a highway, and fitting the unit makes `1` the flood again. A line on any exchange is `1 e b h s`, and another exchange's outside line is `1 e b 9`. The marker already fitted — mini-marker or class marker — stays (`common-control.md` §4) | `network.md`, `monitor.md` |

---

## 6. Bringing it up

`fabric.md` §7, cut to the minimum:

1. **The clock card alone.** `SLOTQ` a quarter of a cell behind `SLOT`; `FILL`
   is `1010`.
2. **Block 2 with no cards.** `HC[2]` is `1010`. Strobe line *k* is low for the
   second half of cell *k* and at no other time.
3. **Latches by hand**, from the console or a jig on the control bus: point 20 at
   21 and 21 at 20. That is a hotline. Lift one phone and the other rings;
   answer, talk, hang up in either order, and both latches clear themselves.
   **With the console setting up each call, this is a manual board with no
   marker at all.**
4. **The mini-marker** (`mini-marker.md`). One register inside, two digits,
   no card word. Dial 20 and 21. This **is** a marker: a network unit and
   monitors can plug in on its ribbons (`common-control.md` §4). Unplug it
   when a class marker is wanted for 0, 9, nails, or the word.
5. **The class marker and the register pool.** Dial 0 and 9; empty slots
   read unequipped.

---

## 7. Not measured

- **The circuits.** Nothing is drawn. The marker's count in §2 is an estimate by
  function, and the block's and port's counts are `fabric.md`'s parts lists
  by function.
- **`/HUNT_INH` and the probe on the control bus** (§5). Both are proposed here
  so that the network unit can be added without touching a fitted marker or
  register, and neither is in the `calls` model, which has no probe bus and hunts
  by reading the class directly. Digit `1` as a highway in `calls` 19 is the
  standalone map; the flood is `exch.py net`.
- **The pull-downs on `PB`, and `RBT` tied to `FILL`.** The fabric model
  measured absent blocks on the highways (`exch.py fabric` 2). The `calls` model
  has no probe bus and no `RBT` wire.
- **The model's layout.** Its register is a port (03) and its tones would be
  classes hunted anywhere. Scenario 19 fits no tone card, so only the register's
  port differs from this document, and nothing measured depends on which
  address a register holds.
- **Power, the ring generator, protection.** As `channel-cards.md` has them; not
  looked at again here.
