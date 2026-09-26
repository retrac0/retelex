# Numbering

What a caller dials and what each number reaches: the digit rule, the port
map, the keys, what a failed number gets, and exchange codes. How the markers
act on a number is `marker.md`; the flood that carries `1 e b h s` is
`network.md`.

> **Built:** `newimpl/rtl/mini_marker.v` (`tb_mini`), `marker.v` (`tb_max`),
> `net_unit.v` (`tb_net`: own code, 8 and 9 in the code).
> **Not built:** key 8 as a pilot (§6).

## 1. The number

**Octal as dialled: a line's two digits `h s` are its port address**, highway
and slot (`fabric.md` §2). A line elsewhere is `1 e b h s`: the network's key,
that exchange's code, then the same `h s`. Joining a network changes nobody's
number.

**The digit rule.** A register stores each digit as its pulse count, 1–15
(`register.md` §1). An address digit is the count's low three bits, forced to
000 when bit 3 is set: ten pulses read 0. **8, 9 and 11–15 are service
digits, tested on the count before anything is an address, in every
position.** Folded, `2 8` would ring 20: from another exchange, a wrong number
the caller cannot see.

## 2. The port map

| port | is |
|---|---|
| 00 | idle, never fitted: a cleared latch listens to it (`fabric.md` §2.4) |
| 01, 02, 03 | dial tone, busy tone, cannot-complete: addresses, not hunts. No tone card fitted, the caller hears silence (`features.md` §1) |
| 04 | the operator, 0's pilot: a line |
| 05–07 | lines nobody can dial: a second position or an announcement answering to 04, or single-channel trunks |
| 10–17 | standalone: lines. Networked: never dialled; by convention the trunks |
| 20–77 | lines |

- **00–07 are never dialled**, 0 being the operator key; **10–17 neither with
  a unit fitted**, 1 being the flood. The operator is not at 00 because every
  cleared latch listens there: every idle phone would ring when it lifted.
- **A trunk card says it is a trunk** (`card-word.md` §2), so any socket may
  hold one. By convention trunks go in block 1 (the local eight-channel trunk
  at 10–17; an MF8 group's six channels at *h*1–*h*3 and *h*5–*h*7, *h*0 and
  *h*4 unequipped: `trunks.md` §4), then in blocks 2–7 at the cost of lines,
  never block 0. A subscriber terminal's six lines take the same seats of a
  block in 1–7 (`proposed/terminal.md`).
- **Registers and monitors take no ports** (`register.md` §1, `network.md` §3.4).

## 3. Keys

| first digit | class marker (`top_max`) | mini marker (`top_min`, `top_net`) |
|---|---|---|
| 0 (ten pulses) | 04, then the ports that answer to 04 (`marker.md` §4.5) | 03 |
| 1 | `/NET` low, a unit fitted: the flood key (`network.md` §4). Else highway 1 | the same |
| 2–7 | highway *h*; wait for *s* | the same |
| 9 | the first free outside line, in slot order | 03 |
| 8, 11–15 | 03 | 03 |

- **The second digit**: 1–7 or 0 is the slot; **8, 9 and 11–15 are 03 in
  every build, never folded onto 0** (`newimpl/faults.py` F09).
- **Dial tone goes off at the first digit**, whatever it is.
- **A restricted caller** is limited further (`card-word.md` §4).
- **One key a call.** A caller on a claimed trunk who keys 1 gets 03 (the
  flood would go back up its own link), and so does a 1 after the call's own
  code: `h = 1` is the trunks' highway there.

## 4. What a failed number gets

The class marker first offers a number that fails at its own port to the
ports that answer to it (`marker.md` §4.5). When nothing free answers:

| tone | the class marker gives it for |
|---|---|
| **02, busy** | a dialled voice line not free: `BUSY`, off-hook or busy-out `b`. So also 0 with 04 and every position busy, and a call nail whose dest is busy |
| **03, cannot-complete** | the rest: an empty slot, none or out of service; a trunk, tone trunk, outside line or data line dialled by number; the caller's own number; a service digit; 9 with no line free; a restricted caller's refused key; the no-digit timeout; a failed network call, or a claim refused for want of a register (`network.md` §4) |

**The mini marker gives 03 for every failure, busy included**, and connects a
dialled empty slot, where the caller hears silence (`marker.md` §3).

## 5. Exchange codes

- **`e b`, each 0–7: sixty-four codes, 00–77**, compared with the unit's
  jumpers. A code says who an exchange is, never where anything is.
- **By convention 00–17 are the backbone's** (tandems, hubs) and 20–77
  ordinary exchanges'. Nothing enforces it.
- **8, 9 or 11–15 in either place is 03.** `1 8 …` and `1 9 …` are kept for
  out of the network (`network.md` §9).
- **The own code works from inside**, at the cost of a flood.
- **After the code, `h s` or one key**: `1 e b 0` is that exchange's operator,
  `1 e b 9` its outside line; a far mini marker refuses both. A third digit of
  8 or 11–15 also ends the number, and the far end gives it 03.
- **Few pulses for busy exchanges**: a pulse of code is 0.1 s of flood on
  every call to it (`network.md` §4.3).

## 6. Open

- **Busy tone on the mini marker.** `top_min` and `top_net` give a busy line
  03, the class marker 02. Options: a second tone address for a called port
  that reads M or `BUSY` (it still cannot tell an empty slot), or busy stays
  03 on the small builds. Decides only what a caller hears there.
- **Key 8 as a pilot**, a strapped pilot in 00–07 whose answers-to ports
  form a call-in bank: not built (`marker.v` makes 8 03), and no place is
  decided for the pilot's jumper.
