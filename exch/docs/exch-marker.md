# The exchange — marker, classes and supervision

The common control of one exchange: how a port says what it is, how a number is
read, how the marker finds what was asked for, and how a call ends with nobody
in charge of it. The fabric the marker writes to is `exch-protocol.md`; the
cards it hunts for are `exch-features.md`.

> **Status: proposed, measured in simulation.** `exch.py calls` runs one exchange
> a millisecond at a time — ports, latches, `BUSY`, class marks, release
> detectors with their tolerances, and cards that behave — and `exch.log` is the
> run. The first run of that model found two faults in the rule as first written;
> §5 has both, with the before and after. No circuit here has been drawn, and
> nothing has been on a bench.

---

## 1. Class marks

Every slot presents a 3-bit class on `TYPE0`–`TYPE2`, set by a jumper on the
card. The marker reads any port's class through the same probe that reads its M
and its `BUSY` (§4). **Nothing on the marker says where anything is**: move a
card and its role moves with it.

| class | is | reached by | free when |
|---|---|---|---|
| 0 | unequipped — an empty slot | its number → class 6 | — |
| 1 | line: a phone, a conference leg, a data card | its number | `BUSY` = 0, M = 0, settled (§5) |
| 2 | operator | **0** | same |
| 3 | external trunk: an FXO to a CO, a foreign PBX | **9** | same |
| 4 | trunk to another exchange of ours | the network card (`exch-network.md`) | same |
| 5 | dial tone | the marker, on seizure | always: a source, one latch write |
| 6 | cannot-complete: busy / error tone, or a looping announcement | the marker, whenever it cannot complete | always |
| 7 | register | the marker, on seizure — **this hunt is the register pool** | `BUSY` = 0 |

---

## 2. Reading a number

```
 first key   2–7   highway h; wait for the slot digit s, 0–7; called = h s
             0     hunt class 2
             9     hunt class 3
             1     long distance — reserved: class 6 until it exists
             8 * # class 6
 called      class 0 or 7 → class 6        class 5 or 6 → listen to it (one write)
             itself, or not free → class 6  else → connect
```

One jumper turns this into the networked form, `e e h s`: the first digit must
be the home district's (or 1, long distance) and opens the flood; the second is
the exchange digit, and if it is this exchange's the junctors are released and
what follows is parsed exactly as above (`exch-network.md` §3). **`h s` means the
same thing in both modes**, which is why ports 00–17 are never dialled by
anyone.

Dial tone goes off at the first digit: one write, the caller listens to port 00.

---

## 3. The hunt

The scanner steps the 64 ports in **fixed order from 00**, eight a millisecond,
and the probe reads class, `BUSY` and M at each. A hunt takes the first port of
the wanted class that is free. **Fixed order is the feature**:

| | what the order buys — measured, `exch.py calls` 9–12 |
|---|---|
| **0** | the first operator rings. In a call, or merely off-hook: the hunt falls to the next class-2 port — a second position. Both busy: the next is an announcement card, which answers by itself 300 ms later, plays, and drops; the release rule has the caller back at dial tone 0.3 s after the message ends |
| **9** | CO lines taken in order; a third caller with two lines fitted gets class 6 |
| tones | pull the dial-tone card and the next class-5 port serves. With no tone card at all a caller hears silence where the tones would be, and the call still completes |
| no class 2 fitted | 0 → class 6 |

**Seizure is handled by class too.** M rising on a free, idle port is a call
request. Class 1 or 2: hunt a register and point it at the caller; point the
caller at dial tone. Class 3 — a CO line ringing in, from a caller who cannot
dial — **is routed as if it had dialled 0**. Class 4 is the network card's.

---

## 4. Common control

| | |
|---|---|
| Clock card | 4.096 MHz → '4040 → 512 k, 64 k, 8 k, the 1 kHz tick, `FILL`, `RING_CAD` (2 s / 4 s), `RBT` |
| Scanner | a 6-bit counter on the 8 kHz mark. It moved here from `register.md` §5, where it was part of the register: a hunt must not wait for a register |
| Probe | the port's own listen structure — two '151 and a flip-flop — on the M, `BUSY` and class highways, addressed by the scanner or by the digit store. **The marker reads ports the way ports read each other** |
| Sequencer | a state counter and decode. Its whole output is latch writes on the control bus — `PORT[5:0]`, `SRC[5:0]`, `BUSY`, `WR` — which is multi-master: the operator's console drives it by hand |
| Diode matrix | prefix key → class. Nothing else: no addresses, no translation |
| Registers | lines of class 7, `exch-features.md` §1; digits come back on a ribbon |

A connection is two writes — caller listens to called, called listens to caller
— and the marker is finished with the call.

---

## 5. Supervision: nobody is in charge of a call

`mf8-cards.md` §1: two station ends facing each other are a hotline — either
off-hook rings the other, both off-hook is a call. **The exchange sets up
hotlines on demand**, and everything after the two writes is done by the ports.

```
 ringing   at the called port:  on-hook · E      → A_RX = E · RING_CAD        the phone rings, in cadence
                                                 → highway C = RBT            the caller hears ringback
 answer    called M = 1 → both conditions drop.  No marker.
 release   M falls for 256 ms, or E falls for 256 ms → clear own latch and BUSY
           off-hook, latch idle, BUSY = 0 → a call request → dial tone
```

Release is on a **fall**, not a level: a phone being rung, a caller listening to
a tone, and a register's caller between digits all sit at 0 legitimately. Each
port has two detectors — RC, Schmitt, differentiator, about half a '14 — that
arm after 16 ms high and fire after 256 ms low. 256 ms is `register.md` §2's
CLR: the longest dial break is 103 ms. **Nothing in the exchange ever winks**, so
the rule has no exceptions.

`RBT` is bussed like `FILL`: ringback is the one tone that is not a line, because
it is made where the call state is.

### 5.1 Measured: the scenarios

Every one of these ends with every latch idle and every `BUSY` clear
(`exch.py calls` 1–15); the log has each as a timeline of what every party hears.

| | what happens |
|---|---|
| a local call, caller hangs up first | the called party, still off-hook, is released 30 ms later and **gets dial tone** — it is an idle off-hook port, which is a call request |
| called party hangs up first | the same, mirrored |
| busy; dialling oneself | class 6 |
| an empty slot; 1; 8; 2 then 9 | class 6 |
| abandoned while ringing | the called phone stops ringing at once (E fell) and is free 300 ms later |
| abandoned while dialling | **the register lets go by itself**: it is a port, and its E is the caller's hook |
| off-hook, nothing dialled | class 6 after 10 s, register freed; the port stays busy until the phone is hung up |
| two callers dialling each other | both get class 6 |
| a called phone lifting 3 ms before the test | reads busy: M is part of the free test |
| one register, two callers | the second gets dial tone 1.9 s late: when the first has dialled, and the freed register has settled (§5.2) |
| a rotary phone, 10 pps | the register counts pulses on **its own `A_RX`** — the fabric switches A with C, so `register.md` §4's line-select '151 is not needed. 0 is ten pulses |
| 7 pps at 72 % break (103 ms), every detector at its shortest, 204 ms | dials and completes; no release during dialling |

### 5.2 Found by the model: a stale release kills the next call

A port's two detectors have different RCs. When one fires, the port is free; the
other may still be timing out — and if the marker seizes the port for a new call
in that window, the second detector's pulse clears it. 300 calls between random
pairs, the two parties hanging up within 600 ms of each other, a third party
dialling the first number freed with its last digit landing about 270 ms after
that hang-up, detectors drawn ±20 % about 256 ms (`exch.py calls` 16):

| a port reads busy while a detector is timing out | new calls killed by a stale release | longest a port listened to a party no longer listening back |
|---|---|---|
| no — the rule as first written | 6 | 2 439 ms |
| **yes** | **0** | 94 ms |

**The fix is what the `BUSY` highway carries: `BUSY` + any detector whose filter
is still high while its input is already low.** About one gate a port. The same
term holds off a call request from a port that has just been released, and it is
the guard time a trunk needs. Its price is that a number reads busy for up to
about 0.6 s after its call ends — the two detectors time out one after the
other — so the third party above is given class 6 in 289 runs of 300 instead of the
call (109 without the term).

No run in either row overheard another call: a dangling listener hears a port
that is on-hook, which is `RBT` or silence.

Runs not idle at the end were all one thing: the party left off-hook was given a
register and hung up inside the detector's 16 ms arming time, so the register
never saw E rise. The 10 s no-digit timeout frees it.

### 5.3 Found by the model: the hang-up ping

On-hook with E high is the ring condition — and a caller who hangs up first,
with the other party still off-hook, meets it for the 256 ms until the release
fires. His own phone is rung, and the other party is sent ringback
(`exch.py calls` 17):

| ring and `RBT` gated by the filtered hook | caller rung, ms | other party hears ringback, ms |
|---|---|---|
| no | 267 | 268 |
| **yes** | **0** | 1 |

**On-hook, for ringing and for `RBT`, means the raw hook *and* the detector's
filtered hook both low.** Ring trip stays immediate, because the raw hook is
still in the term; the filtered hook is a signal the port already has.

---

## 6. Registers are a pool, and callers wait

A caller who finds no register free is not refused: dial tone is late. 48 lines,
200 000 calls a cell, holding time = lift to last digit (`exch.py calls` 18):

| calls / line / h | holding, s | erlang | registers | delayed | mean wait of those | wait > 3 s |
|---|---|---|---|---|---|---|
| 3 | 4 | 0.16 | 1 | 16.0 % | 2.6 s | 5.7 % |
| 3 | 4 | 0.16 | **2** | **1.2 %** | 1.4 s | **0.1 %** |
| 3 | 10 | 0.40 | 2 | 6.5 % | 3.9 s | 3.6 % |
| 3 | 10 | 0.40 | 3 | 0.8 % | 2.7 s | 0.3 % |
| 10 | 4 | 0.53 | 2 | 10.9 % | 1.7 s | 1.7 % |
| 10 | 4 | 0.53 | **3** | **1.7 %** | 1.1 s | **< 0.1 %** |

4 s is a keypad; 10 s is `register.md` §5's figure for a dial. **Two registers
for a group of keypad phones, three for dials or for a busy one.** `register.md`
§5's "one is enough" was eight lines.

---

## 7. Dialling is on the A line

**Decided: all pulse.** A register is `register.md` §4's pulse counter reading its
own `A_RX`. The store and its code would take an MT8870 as a second writer
(`register.md` §7), and the scenarios of §5.1 were run with a keypad as well as
a dial, but a keypad's digits are in band and **the network hears only the A
line** (`exch-network.md` §4): a keypad phone could place local calls and no
others. The comparison that settled it:

| | DTMF | pulses on A |
|---|---|---|
| hears | `C`: a CVSD decoder half, a reconstruction filter, an MT8870 and its crystal | **`A_RX` only** — all 74HC, no audio, no trim |
| packages | ≈ 9–10, one trim, one LSI | ≈ 9 (`register.md` §4 less its '151) |
| four digits by hand | 1–2 s | 4–5 s; the octal 0 is ten pulses |
| a data card | cannot dial | **can: the terminal pulses `DTR`** |
| against the release rule | — | breaks ≤ 103 ms against a release ≥ 204 ms: measured, §5.1 |

**The network speaks the second, live**: a caller's own pulses go down the flood
and every monitor is this same pulse register (`exch-network.md` §4). Nothing
is sent twice.

---

## 8. Not measured

- **The circuits.** The probe, the sequencer, the detectors and the two gates of
  §5.2 and §5.3 are described, not drawn.
- **The detectors as RCs.** The model gives each a fixed time drawn ±20 %. A real
  RC into a Schmitt gate has a threshold tolerance on top, and a filter that is
  high "while its input is low" is two comparisons of one capacitor's voltage.
- **The 1 ms glitch** at the instant a release fires: the filtered hook has fallen
  and the latch is cleared in the same tick, and for that tick the ring condition
  is met. In hardware it is a frame or two; it is where the "1 ms" in §5.3's
  bottom row comes from.
- **A CO's ring cadence against `RING_CAD`** at the operator's phone: the two are
  ANDed (`exch-features.md` §5).
- **Marker contention**: two requests in one tick are served in scan order in the
  model; a second master on the control bus is not modelled.
- **Partial dialling**: the 10 s timeout runs from the last digit as well as from
  seizure, and is modelled only from seizure.
