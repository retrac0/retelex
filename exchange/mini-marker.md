# The exchange — a mini-marker for bring-up

A marker that makes local calls on a single exchange: two phones dial `h s`,
one rings, they talk, either hangs up, and nobody is in charge of the call. It
reads **M and `BUSY` only**. It does not look at a card's option word. It does
not hunt a class. One pulse collector lives **inside** it.

It is a marker, not a parameter of the marker of `marker.md`. Cards stay. You
may unplug it when a class marker and its register pool go in; you may also
leave it fitted and add a network unit and monitors, which is a pulse-flood
exchange (`common-control.md` §4). The ribbons are the same either way.

This is also not the outpulsing register-sender `network.md` §9 set aside.
The "register" is `register.md` §4's pulse collector (`pulse_reg` in RTL),
the same listener. `restart` is tied off until a network unit is fitted,
because nothing then consumes a prefix.

> **Status: proposed, measured in simulation.** `make mini` runs two lines on
> block 2 through seize, a two-digit call each way, busy, self, an empty
> number, the first keys that go nowhere, abandon, and the no-digit timeout.
> The flood path of §8 is specified against `common-control.md` and has not
> been tied as a site. Nothing has been on a bench.

---

## 1. What is fitted

```
 phone ── line card, slot 20 ──┐
                               ├── block 2 ── HA[2], BUSY ── mini-marker
 phone ── line card, slot 21 ──┘                              (scanner, sequencer,
 clock card ── SLOTQ, TICK, FILL, RING_CAD                     one register, cable B)
```

Tone cards at 01 and 03 are optional. The mini-marker **addresses** them; it
does not hunt a class. With none fitted, seize and cannot-complete write the
caller's latch at those numbers anyway, and the caller hears silence — the
same as `mvp.md` §2.

**Not fitted, and not missed for local calls:** the card-word probe, a class
matrix, a hunt, a second register, trunks, monitors, a network unit, nails,
answers-to, the console's `/CON`, event words. §8 is what a network unit adds
without replacing this marker.

The option word pin may still wiggle. Nothing here samples it. `pb_word` is
not a port of the module.

---

## 2. Seizure and the free test

A call request is **M and not `BUSY`**. That is the whole rule. The scanner
visits the 64 ports in order, eight a millisecond, and the probe captures M
off `HA` and `BUSY` off PB in the port's own cell, the way `marker.md` §4
does — minus the '164 that would have taken in the word.

| what the full marker used the word for | what happens here |
|---|---|
| class line / operator / restricted → register | any free off-hook port gets the register |
| class source, trunk, nail | not distinguished. A source never raises M, so it is never a caller. Do not fit a trunk or a ring source |
| busy-out, priority | ignored |
| empty slot (no word) | looks like an idle on-hook line |

**Dial only fitted ports.** An empty slot reads `M = 0`, `BUSY = 0`, so a
number that lands there is treated as free: the caller is pointed at it, the
write to the empty latch is ignored if no port circuit is populated, and the
caller hears silence. That is acceptable on a jig; it is why the real marker
reads the word.

A second lift while the register is held waits for the next scan (~8 ms), as
with one register in `marker.md` §5. After release, an idle off-hook port is
a new call request.

---

## 3. Reading a number

Two digits, octal as dialled. Ten pulses are 0, the same `oct()` as the
marker. Digit `1` is a **highway**, not a prefix: no `restart`, no flood, no
`e b`.

```
 first key   1–7   highway h; drop dial tone (caller listens to 00); wait for s
             0     cannot-complete     8, 9, 11–16  cannot-complete
 second      called = h s; probe that port
 called      self, or M, or BUSY → cannot-complete
             else → two writes, register released, mini-marker done
```

Tones are addresses, not hunts:

| | write |
|---|---|
| seize | caller ← 01, `BUSY` |
| first highway digit | caller ← 00, `BUSY` (dial tone off) |
| cannot-complete | caller ← 03, `BUSY` |
| connect | caller ← called, called ← caller, both `BUSY` |

There is no busy-tone port. Busy, self, and a bad first key all get 03. With
no source card at 03 the caller hears silence and hangs up.

Ringing, answer, and release are the ports' (`marker.md` §5). The mini-marker
has already left.

---

## 4. A call

20 calling 21, rotary 10 pps, as `mvp.md` §3, with a register that lives on
this jig rather than as a pool member.

```
 20 lifts             M on HA[2], BUSY clear.  The scanner finds it within 8 ms.
                      The register attaches to 20.  20 listens to 01.
 dial 2 1             the register counts 20's breaks off HA
                      first digit 2: 20 listens to 00
                      second digit 1: called = 21
 20 ↔ 21              the scanner visits 21, on-hook, not busy.
                      two writes.  the register is free.  the mini-marker is done
 21 rings             on-hook · E, in RING_CAD
 21 answers           M rises; ringing drops.  Nothing else acts
 hang up              256 ms of M or E down, the port clears its own latch
```

The other way, 21 calling 20, is the same. Hang up in either order; the ports
release themselves. The party left off-hook with an idle latch is a new call
request.

---

## 5. Wrong numbers

| 20 dials | mini-marker |
|---|---|
| 0, 8, 9 | cannot-complete on the first digit |
| 1 then hang up | 1 was a highway: dial tone went off; no flood |
| 2 0 | itself, busy → cannot-complete |
| 2 1 while 21 is already in a call | 21 busy → cannot-complete |
| 2 5, no port circuit at 25 | treats 25 as free; 20 is pointed at it and hears silence |
| hang up mid-dial | the register lets go on CLR (256 ms). No latch left pointing at 03 |
| off-hook, nothing dialled | cannot-complete after the no-digit timeout; 20 stays busy until hung up |

---

## 6. What it will not do on its own

- Read a card word, hunt a class, or follow a nail or an answers-to.
- Treat `1` as `1 e b h s` **until a network unit is fitted** (§8). Standalone
  numbering still has 10–17 as lines; this marker will complete `1 s` if that
  port is free.
- Share cable B with a console. Bring-up with the console is `mvp.md` §6.3
  (latches by hand) and does not need this marker; it does not yield `/CON`.
- Hold more than one caller. A second phone waits for the register.
- Become the class marker by adding jumpers. The class marker is a different
  card. Fit it, and unplug this — or don't: a network unit does not need the
  class marker.

---

## 7. RTL

`verilog/rtl/mini_marker.v`: a scanner, a BUSY/M probe with the same
`p_valid` rule as the marker (a visit while the serialiser named another
block is discarded — `rtl.md`), a four-deep write queue, `ctl_write`, and
one `pulse_reg` with `restart` tied off unless a network unit is wired.
States:

```
IDLE → (M · /BUSY, register free, not a jumpered trunk) → COLLECT
     → (two highway digits) → PROBE
     ↘ bad first digit / nodig → 03, IDLE
     ↘ flood_go (unit fitted, key 1) → YIELD  (the unit owns the call)
PROBE → visit called, free → pair writes, IDLE
      ↘ busy / self / gone → 03 or just IDLE
YIELD → unit `local` → COLLECT; `done` → IDLE; `nogo` → 03, IDLE
```

`make mini` is the bench without a unit.

---

## 8. With a network unit

The ribbons of `common-control.md` §2.2. This marker does not grow a flood
sequencer. It grows the **hooks** a unit already needs from a class marker:

| | |
|---|---|
| key `1` | consume, restart, drop dial tone, `flood_go` — not highway 1 |
| `restart` | wired, so `e b h s` land in four slots |
| trunk ports | a jumpered mask: `M · /BUSY` there is not a caller. The unit holds and forwards |
| probe out | scanned port, M, `BUSY` (no word: the unit hunts by the same mask) |
| claim attach | the unit asks; attach the register to that trunk; later writes keep `CLAIM` |
| YIELD | the unit signals `local` / `done` / `nogo`; this marker does not wait for a claim itself |

A two-exchange chain is this marker, that unit, monitors on block 1, and an
MF8 trunk card. Resolvers, 0, 9, nails and the word stay off. That is a
pulse-flood compatible exchange (`common-control.md` §4), not a growth of
this file into `marker.md`.
