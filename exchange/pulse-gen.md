# The exchange — a hook/pulse generator, no handset

A channel card that **seizes and dials**. A hook switch and sixteen SMD
buttons on the front — each button is also a pin — 10 pps breaks on `A_TX`,
nothing in the ear. Registers and the pulse flood read only A, so they see an
ordinary caller (`network.md` §3, `register.md` §1). It is the interactive
cousin of the stored-number hotline of `extensions.md` §3.4: that card dials
one jumpered number when its phone is lifted; this one is a tester, and the
number is whatever is keyed. The handset cousin with the same 1–16 pulse map
(Autovon labels) and a codec is `su-1.md`.

> **Status: proposed, measured in simulation.** `make pulse_gen` runs the
> timebases, the hex map including D = 16, and a `net_site`
> call originated from this card — local, and the flood. The circuit is a
> proposal from data-sheet behaviour. Nothing has been on a bench.

---

## 1. What it is

A line that lifts, with no codec and no ringer. To the exchange it is a plain
line whose card never rings. The pulses are loop-disconnect on its own `A_TX`,
live, the way a rotary phone's are: no sender, and the flood carries them
because they *are* forward A.

| | |
|---|---|
| **Face** | channel slot of `common-cards.md` §1, plus sixteen SMD buttons (each a pin), a hook switch, and the `SRC` / wait / DIP jumpers on the front |
| **`A_TX`** | off-hook with 10 pps breaks. High is a make |
| **`C_TX`** | `FILL`. There is no microphone |
| **`/ANS`** | tied low. The port never rings. A tester who dials it hears silence |
| **the word** | pin grounded: a plain line, no part (`extensions.md` §2.2) |
| **clocks** | `TX_OCT` off the socket. **No oscillator on the card** (`clocks.md` §3). The RC astable of §2.2 is timing, not a clock, the same way a line card's one-shots are |

A phone on a line card does the same with its hook. Fitting this card in the
slot *is* that hook: `A_TX` is M, and a register attached to the port counts
what the buttons send.

---

## 2. Two timebases

The register, the flood and the monitors were measured at **10 pps, 60/40**,
and they hold at 10 pps ± 10 % (`register.md` §2, `network.md` §4, `monitor.md`
§5). The card can send that exactly, off the crystal, or something else, off
jumpers or a pot, so a tester can walk the windows.

Jumper `SRC` picks the source. Both paths run on the same 1 kHz `TICK` when the
source is the crystal; the RC path is analog and is a model of that astable
in the RTL (`PPS`, `BREAK_PCT`, `T_OH`).

### 2.1 Precise: the crystal, divided

`TX_OCT` is 8 kHz, a tap of the exchange's 4.096 MHz (`clocks.md` §1). ÷ 8 is
the register's own `TICK`. A decade counter on that tick is 100 ms; six of its
states NOR'd are a 60 ms break. That is `extensions.md` §3.4's dialler, reused:

```
 TX_OCT 8 kHz ──[ ½ 74HC393, ÷8 ]── TICK, 1 kHz
 TICK ──[ 74HC4017 ]── one-hot 100 ms
 Q0–Q5 ──[ ¼ 74HC4002 NOR ]── BREAK_xtal     60 ms of every 100, 10 pps 60/40
```

Nothing else is a rate. The seize delay and the interdigit pause are counts of
the same tick: 500–800 ms before the first digit (ES 201 187's 500 ms floor),
700 ms between digits.

### 2.2 Adjustable: DIP, or RC

**DIP**, still from the crystal. Jumpers on the '4017 and an extra gate pick
8 / 10 / 12 pps and 60 / 67 % break — the two break ratios ES 201 187 allows,
and the three rates a GPO register was expected to take. A 4-bit DIP loads the
seize delay, 100–1600 ms in 100 ms steps of `TICK`.

**RC**, analog. ¼ 74HC14 Schmitt astable, pot + C, for the pulse rate; ½ 74HC123
for the break width and for the seize delay. A tester who wants 7 pps, or 72 %
break, or a 200 ms seize, turns a pot. The RTL does not solve an RC: it is
`PPS`, `BREAK_PCT` and `T_OH`, the same way `T_RISE` stands in for a port's
detector.

```
 ¼ '14 astable, R pot, C ── period ──[ ½ '123 ]── BREAK_rc
 DIP on the '4017 / extra C ── BREAK_dip
 SRC ── 74HC157 ── BREAK
```

---

## 3. Off-hook, then breaks

The hook switch seizes. Hanging up aborts a train at once and drops `A_TX`.
The first digit waits, because a register attached late would count from the
middle of a break (`extensions.md` §3.4). Two ways, jumpered:

| jumper | wait |
|---|---|
| **RC / DIP** | a delay after seize, default 500–800 ms. Deaf: the card does not listen. Enough, because a register is attached in one scan and dial tone is prompt |
| **dial tone** | `C_RX` XOR `FILL`, a counter. The marker points a caller at dial tone when it hands it a register (`marker.md` §3). With no dial-tone card fitted this wait never ends |

Then each key is `n` breaks at the selected rate, a 700 ms pause, and the next
key. `A_TX = seized · /BREAK`.

---

## 4. The buttons

Sixteen SMD push-buttons in the hex layout, **each its own pin**, pulled up,
to ground when pressed. No matrix, no scan. Debounce on `TICK`, about 20 ms,
one-key lockout while a train is out, **one-deep queue** so `1 e b h s` can be
typed without waiting each train. The same sixteen nets come off a header, so
a bench can drive them with no buttons fitted.

```
        KEY1  KEY2  KEY3  KEYA          pulses  1  2  3 13
        KEY4  KEY5  KEY6  KEYB                  4  5  6 14
        KEY7  KEY8  KEY9  KEYC                  7  8  9 15
        KEY*  KEY0  KEY#  KEYD                 11 10 12 16
```

1–9 are 1–9 pulses; 0 is ten, as a rotary dial. \* is 11, # is 12, A–D are
13–16. The numbering plan does not use them: the marker's `isvc` still treats
anything past 10 as service (`protocol.md` §5, `marker.md` §2), so a first
digit of \* is cannot-complete. They exist so a register and a monitor can
*count* them. **The exchange register counts to 15 and stops** (four bits,
one '670 for four digits — `register.md` §4). Hex **F** is in that width;
sixteen-pulse **D** is not stored as 16 until the count grows again. This
card may still emit 16 pulses; the register saturates.

---

## 5. The circuit

```
 TX_OCT ──[ ½ '393 ÷8 ]── TICK ──[ '4017 ]── 100 ms, Q0–Q5 NOR = BREAK_xtal
 RC / ¼ '14 astable ──[ ½ '123 ]── BREAK_rc
 DIP ── jumpers on the '4017 ── BREAK_dip
 SRC ── mux ── BREAK

 HOOK ──[ ½ '123, or DIP-loaded '163 on TICK ]── seized
        jumper: wait that, or C_RX XOR FILL ('86 and a '74)

 KEY 1–9 0 * # A–D ── pull-up ──[ 2 × '148 ]── load 5-bit count (½ '193 + FF)
 count ── BREAK edges, down; zero ──[ '393 pause ]── next key
 A_TX = seized · /BREAK
 C_TX = FILL          /ANS = 0          word pin = GND
```

| block | parts |
|---|---|
| `TICK` ÷ 8, pause | 74HC393 |
| 100 ms and 60 % break | 74HC4017, ¼ 74HC4002 |
| `SRC` mux, DT XOR | ¼ 74HC157, ¼ 74HC86, ½ 74HC74 |
| seize delay | ½ 74HC123, or a '163 and the DIP |
| buttons, debounce | 16 SMD, resistor network, ½ 74HC74 |
| encode 16 pins to 1..16 | 2 × 74HC148 |
| pulse count | ½ 74HC193 and one FF (five bits on **this** card so D can still load 16; the exchange register saturates at 15) |
| RC astable (if fitted) | ¼ 74HC14, pot, C; ½ 74HC123 |

**≈ 11 packages.** The hotline's eight, plus encode. Fitted only on this card.

```
  KEY 1–9 0 * # A–D ── encode ── sequencer ── A_TX
  hook       ── seize delay ──┘    ┌── C_TX = FILL
  TX_OCT ── ÷ ── TICK ── SRC mux ──┘
  RC / DIP ─────────────┘
```

---

## 6. Against a register, and against the flood

The card is a caller. Lift, wait, dial `h s`, and the called line rings. Dial
`1 e b h s` and the same pulses go down every seized trunk live: the origin's
register consumes the key and restarts, the monitors read `e b`, the owner
claims, and `h s` land in the owner's store (`network.md` §3). Nothing in the
exchange is different from a rotary phone on a line card. `make pulse_gen`
does both, with this card originating and no handset on the port.

---

## 7. Not measured

- **The circuit.** A proposal from data-sheet behaviour, including the '4017's
  60 % NOR and the buttons against bounce.
- **A real RC astable** against the register's 7–12 pps window, and a pot at
  the end of its travel.
- **Dial-tone detect** against a real tone card, as `extensions.md` §3.4 left
  the hotline's XOR.
- **A first digit of A–D** through a marker that has been given a meaning for
  them. They nogo today, on purpose.
