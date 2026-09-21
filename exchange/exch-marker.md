# The exchange — marker, classes and supervision

The common control of one exchange: how a port says what it is, how a number is
read, how the marker finds what was asked for, and how a call ends with nobody
in charge of it. The fabric the marker writes to is `exch-protocol.md`; the
cards it hunts for are `exch-features.md`.

> **Status: proposed, measured in simulation.** `exch.py calls` runs one exchange
> a millisecond at a time — ports, latches, `BUSY`, class marks, release
> detectors with their tolerances, and cards that behave — and `exch.log` is the
> run. The first run of that model found two faults in the rule as first written;
> §5 has both, with the before and after. **The model predates the port map of
> `exch-protocol.md` §5**. It agrees on idle at 00. It still puts tones and
> registers on an older layout (tones not at 01–03, trunks mixed into block 0),
> where the map now has dial/busy/cannot-complete at 01–03, the operator bank at
> 04–07, and MF8 trunks from block 1. Its scenarios also put
> outside lines at 10–11 and operators in line slots. Nothing it measures depends
> on which address holds what; it is to be brought in line. No circuit here has been drawn, and nothing
> has been on a bench.

---

## 1. Class marks

Every port says what it is in a **word**: eight bits that whatever sits behind
it sends, one a frame, on one pin (`ex-extensions.md` §2.2). A card sends it for
its one port, and a trunk card for each of its six channels (`exch-network.md`
§1). The word carries a 3-bit class and four options that depend on the class: a
trunk's direction, a hunt group, a warm line. Or it names the port this one
is nailed to. **Class *restricted*** is its own code (`exch-fabric.md` §3.5), not
an option. **A plain line card ties the pin to ground**, which reads all ones
and means a line with no options. The marker's probe reads the word at every
visit, beside the port's M and its `BUSY` (§4). **Nothing on the marker says
where anything is**: move a card and its role moves with it. Whether a port rings
is not the marker's business: the card says it to the port's own gates on a pin,
`/ANS` (`ex-extensions.md` §2.3).

| class | is | reached by | free when |
|---|---|---|---|
| 0 | unequipped — an empty slot | its number → class 6 | — |
| 1 | line: a phone, a data card, a conference bridge leg | its number | `BUSY` = 0, M = 0, settled (§5) |
| 2 | operator | **0** | same |
| 3 | external trunk: an FXO to a CO, a foreign PBX | **9** | same |
| 4 | tie trunk. **Its direction is not the class**: the port's word says N, S, E or W (`ex-extensions.md` §2.2), and an MF8 trunk card sends one word to all six channels | the network card (`exch-network.md`), a free trunk facing the way it wants | same, and a valid direction word: a trunk card sends none while its link is down |
| 5 | dial tone | the marker, on seizure | always: a source, one latch write |
| 6 | cannot-complete: busy / error tone, or a looping announcement | the marker, whenever it cannot complete | always |
| 7 | spare in this older map. Under `exch-fabric.md` §3.5, code **111** is *restricted* | — | — |

**Proposed, not applied here or in the model:** the codes renumbered
(`exch-fabric.md` §3.5), with *source*, *data line* and *restricted*. *Source* is
anything that talks and never listens: the two tones, reached by address rather
than hunted, and a radio or a clock that anyone may dial (`exch-features.md`
§6). *Data line* is a line the marker will not connect to a voice port. A
conference bridge leg is an ordinary line (`exch-features.md` §7.4); class
*conference* is retired. *Restricted* (`111`) options are `z w b L`
(`ex-extensions.md` §2.4): **0-only**, reserved (warm), **busy-inbound**,
**local-only**; bare restricted still floors as local-only. A line's options are
`o w b ·` — overflow, warm, busy-out, spare — with `o`/`w`/`b` in the same
frames as restricted and as overflow on operator and data.

**Proposed further** (`ex-groups.md`): a port may *answer to a number*. A
dialled number that cannot be completed where it was dialled is hunted for among
the ports that answer to it, 0 becomes a call to 04, and class *operator* and
§2's overflow step go.

---

## 2. Reading a number

```
 first key   2–7   highway h; wait for the slot digit s, 0–7; called = h s
             0     hunt class 2
             9     hunt class 3
             1     networked: 1 e b h s (opens the flood)
                   standalone: highway 1; wait for s — 10–17 are ordinary lines
             8 * # class 6
 called      class 0, 4 or 7 → class 6     class 5 or 6 → listen to it (one write)
             itself → class 6               not free (BUSY or busy `b`), overflow set → try next
             not free → class 6 (busy tone) else → connect
 caller      class restricted: `z` → only 0; else `L` or floor → no 9 / no flood   (ex-extensions.md §2.4)
             busy `b` does not block a call request
```

Whether `1` is the flood or highway 1 is the network strap: network card fitted,
or the jumper that says the same with none (`exch-protocol.md` §5). A number on
another exchange is `1 e b h s`: the key, the exchange's code, then the line.
The key opens the flood. If the `e b` that follows is this exchange's own, the
trunks are released and what follows is parsed exactly as above
(`exch-network.md` §3). `e` and `b` are 0–7. Either being 8 or 9 is reserved:
the trunks are released and the caller gets class 6. A local number in 20–77 is
the same two digits alone or networked; **`h s` after `1 e b` means the same
port**. Ports 00–07 are never dialled (0 is the operator key). Ports 10–17 are
lines when standalone and undialable when networked.

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

**A nail comes first.** A card's word is either its class or a nail. A nail with
`BUSY` clear is written before anything else is considered, and a port that sends
a nail is never free and never a call request (`ex-extensions.md` §3.1).

**Seizure is handled by class too.** M rising on a free, idle port is a call
request. Class 1 or 2: give a free register the caller's number; point the
caller at dial tone. Class 3 — a CO line ringing in, from a caller who cannot
dial — **is routed as if it had dialled 0**, and so is a line whose word says
warm line (`ex-extensions.md` §2.4). Class 4 is the network card's, and a hunt
for one is steered by that card on `/HUNT_INH` (§4): the marker hunts the class
and never knows which way a trunk faces.

---

## 4. Common control

| | |
|---|---|
| Clock card | 4.096 MHz → '4040 → 512 k, 64 k, 8 k, the 1 kHz tick, `FILL`, `RING_CAD` (2 s / 4 s). **`RBT` is not its**: it is carried with these and generated by the ringback tone card, which drives the conductor through a buffer on the card. The clock card terminates it to `FILL` and nothing else (§5, `exch-features.md` §2, `exch-mainboard.md` §2.1, `tone-card.md` §5) |
| Scanner | a 6-bit counter on the 8 kHz mark. It moved here from `register.md` §5, where it was part of the register: a hunt must not wait for a register |
| Probe | the port's own listen structure — two '151 and a flip-flop — on the M highway and the probe bus (`BUSY` and the card's word, which a 74HC164 takes in over the visit), addressed by the scanner or by the digit store. A port probed out of the scanner's turn is read for one whole octet, up to 250 µs. **The marker reads ports the way ports read each other.** M and the word go out on the control bus as well, so that a card may watch the scan without the marker knowing what it is looking for (`exch-network.md` §3.2) |
| Sequencer | a state counter and decode. Its whole output is latch writes on the control bus — one sixteen-bit word shifted out on `SDATA`, then `WR` (`exch-mainboard.md` §2.3) — which is multi-master: the operator's console drives it by hand. Its hunt takes one input, `/HUNT_INH`, pulled up on the backplane: a card may reject the port the probe is on and the hunt walks on. Nothing else may steer a hunt, and with no card fitted the line reads *accept* |
| Diode matrix | prefix key → class. Nothing else: no addresses, no translation |
| Registers | `register.md` §4, one to three of them. The marker's scanner is their finder: it hands a free register the caller's port number **and optional held party `SRC`**, the register's own probe — two '151 and a flip-flop on the M highway — reads the caller's hook, and its digits and `SRC` come back on a ribbon. It lets go on `register.md`'s CLR (hook down 256 ms), the no-digit timeout, or the marker's word. **No port, no class.** `SRC` non-zero is an operator transfer consult (`register.md` §6.1): the register is kept after the second leg connects, and CLR pairs held ↔ called. On a networked exchange the trunks it seized for its caller are held in a bank of its own **on the network card**, so a register is the same ~12 packages whether the exchange stands alone or not (`exch-network.md` §3.2) |

A connection is two writes — caller listens to called, called listens to caller
— and the marker is finished with the call.

---

## 5. Supervision: nobody is in charge of a call

`channel-cards.md` §1: two station ends facing each other are a hotline — either
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
| abandoned while dialling | **the register lets go by itself**: the hook it is watching stays down 256 ms |
| off-hook, nothing dialled | class 6 after 10 s, register freed; the port stays busy until the phone is hung up. On a network call the origin releases its trunks first, 5 s after the key (`exch-network.md` §3–4) |
| two callers dialling each other | both get class 6 |
| a called phone lifting 3 ms before the test | reads busy: M is part of the free test |
| one register, two callers | the second gets dial tone 1.9 s late: when the first has dialled, and the freed register has settled (§5.2) |
| a rotary phone, 10 pps | the register counts the pulses of the caller's hook. 0 is ten pulses |
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
for an exchange of keypad phones, three for dials or for a busy one.** `register.md`
§5's "one is enough" was eight lines.

---

## 7. Dialling is on the A line

**Decided: all pulse.** A register is `register.md` §4's pulse counter reading the
caller's hook. The store and its code would take an MT8870 as a second writer
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

**The network speaks the second, live**: a caller's own pulses go down the flood,
and each exchange's monitor — a cut-down pulse register on the trunk block,
`exch-monitor.md` — reads the one digit it needs. Nothing is sent twice.

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
- **Operator flash transfer**: the register's `SRC` field and the marker's consult
  / CLR pair path are in RTL (`register.md` §6.1). Flash detect on a busy
  operator port, and filling `attach_src` from a listen-latch read-back, are not.
