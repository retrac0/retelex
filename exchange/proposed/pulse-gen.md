# The pulse generator: a card that seizes and dials, with no handset

A channel card with a hook switch and sixteen buttons that sends 10 pps
loop-disconnect breaks on its own `A_TX` and has nothing in the ear. Registers
and the flood read only A, so they see an ordinary caller (`register.md` §1,
`network.md` §4). It is a tester: the interactive cousin of the hotline card
that dials one jumpered number when lifted (`card-word.md` §6.5). The handset
cousin with the same 1–16 pulse map and a codec is `common/su-1.md`.

> **Proposed.** A circuit from data-sheet behaviour; nothing drawn, nothing on
> a bench. No `newimpl` model: the only bench that ran it was in the retired
> tree.

---

## 1. What it is

A line that lifts, with no codec and no ringer. The pulses are loop-disconnect
on its own `A_TX`, live, as a rotary phone's are: no sender, and the flood
carries them because they *are* forward A.

| | |
|---|---|
| **Face** | the channel socket (`common/common-cards.md` §1), sixteen SMD buttons (each also a pin), a hook switch, and the `SRC`, wait and DIP jumpers on the front |
| **`A_TX`** | off hook with 10 pps breaks; high is a make |
| **`C_TX`** | `FILL`: there is no microphone |
| **`/ANS`** | tied low: the port never rings. A tester who dials it hears silence |
| **the word** | pin grounded: a plain line, no part (`card-word.md` §2) |
| **clocks** | `TX_OCT` off the socket. **No oscillator on the card** (`common/clocks.md` §3); the RC astable of §2.2 is timing, not a clock, as a line card's one-shots are |

Fitting the card in a slot *is* a phone's hook: `A_TX` is `M`, and the
register attached to the port counts what the buttons send.

---

## 2. Two timebases

The register, the flood and the monitors are measured at **10 pps, 60/40**,
and hold at 10 pps ± 10 % (`register.md` §1, `analysis/monitor-rules.md` §5).
The card sends that exactly, off the crystal, or something else off jumpers or
a pot, so a tester can walk the windows. Jumper `SRC` picks the source.

### 2.1 Precise: the crystal, divided

`TX_OCT` is 8 kHz, a tap of the exchange's 4.096 MHz. The card divides it by 8
for its own 1 kHz tick (the socket carries no `TICK`), and by 10 again for a
10 ms step. A decade counter on the step is 100 ms, and six of its states
NOR'd are a 60 ms break:

```
 TX_OCT 8 kHz ──[ ½ 74HC393, ÷8 ]── tick, 1 kHz
 tick ──[ ½ 74HC390, ÷10 ]── step, 10 ms
 step ──[ 74HC4017 ]── one-hot 100 ms, its carry 100 ms
 Q0–Q5 ──[ ¼ 74HC4002 NOR ]── BREAK_xtal     60 ms of every 100: 10 pps 60/40
```

Nothing else is a rate. The seize delay and the interdigit pause are counts of
the '4017's carry: 500–800 ms before the first digit (ES 201 187's 500 ms
floor), 700 ms between digits. The debounce (§4) counts the tick.

### 2.2 Adjustable: DIP, or RC

**DIP**, still from the crystal: jumpers on the '4017 and a gate pick 8 / 10 /
12 pps and 60 / 67 % break — the two break ratios ES 201 187 allows, and the
three rates a GPO register was expected to take. A 4-bit DIP loads the seize
delay, 100–1600 ms in 100 ms steps.

**RC**, analog: ¼ 74HC14 Schmitt astable, pot and capacitor, for the rate; ½
74HC123 for the break and for the seize delay. A tester who wants 7 pps, a 72 %
break or a 200 ms seize turns a pot.

```
 ¼ '14 astable, R pot, C ── period ──[ ½ '123 ]── BREAK_rc
 DIP on the '4017 / extra gate ── BREAK_dip
 SRC ── 74HC157 ── BREAK
```

---

## 3. Off hook, then breaks

The hook switch seizes; hanging up aborts a train at once and drops `A_TX`.
**The first digit waits for a register**, because a register attached late
counts from the middle of a train. Two ways, jumpered:

| jumper | wait |
|---|---|
| **dial tone** | `C_RX` XOR `FILL`, and a counter: the card dials when `C_RX` leaves the idle pattern. The marker points a caller at dial tone when it hands it the register (`marker.md` §2). **This is the safe one.** With no dial-tone card fitted it never ends |
| **RC / DIP delay** | a fixed delay after seize, deaf. **Safe only when the register is certainly free and prompt**, which no build promises: every build has one register, held by another caller through dialling, through the watch after a connect (`marker.md` §5) and through a flood, and the class marker's walk reaches a lifted port up to a round, ≈ 250 ms, later (`marker.md` §4.2). A delay that ends first dials into no register |

Then each key is *n* breaks at the selected rate, a 700 ms pause, and the next
key. `A_TX = seized · /BREAK`.

---

## 4. The buttons

Sixteen SMD push-buttons, **each its own pin**, pulled up and grounded when
pressed: no matrix, no scan. Debounce on the tick, about 20 ms; one-key lockout
while a train is out; a **one-deep queue**, so `1 e b h s` can be typed without
waiting out each train. The same sixteen nets come off a header, so a bench can
drive them with no buttons fitted.

```
        KEY1  KEY2  KEY3  KEYA          pulses  1  2  3 13
        KEY4  KEY5  KEY6  KEYB                  4  5  6 14
        KEY7  KEY8  KEY9  KEYC                  7  8  9 15
        KEY*  KEY0  KEY#  KEYD                 11 10 12 16
```

1–9 are 1–9 pulses; 0 is ten, as a rotary dial; \* is 11, # 12, A–D 13–16.
**The numbering plan does not use 11–16**: as a first key they are
cannot-complete (`numbering.md` §3). They exist so that a register and a
monitor can *count* them. **The register counts to 15 and stops**
(`newimpl/rtl/pulse_rx.v`): F is stored, a sixteen-pulse D is not. This card
still sends 16; the register saturates.

---

## 5. The circuit

```
 TX_OCT ──[ ½ '393 ÷8 ]── tick ──[ ½ '390 ÷10 ]── step ──[ '4017 ]── 100 ms,
        Q0–Q5 NOR = BREAK_xtal
 RC / ¼ '14 astable ──[ ½ '123 ]── BREAK_rc
 DIP ── jumpers on the '4017 ── BREAK_dip
 SRC ── mux ── BREAK

 HOOK ──[ ½ '123, or DIP-loaded '163 on the '4017's carry ]── seized
        jumper: wait that, or C_RX XOR FILL ('86 and a '74)

 KEY 1–9 0 * # A–D ── pull-up ──[ 2 × '148 ]── load 5-bit count (½ '193 + FF)
 count ── BREAK edges, down; zero ──[ '393 pause ]── next key
 A_TX = seized · /BREAK
 C_TX = FILL          /ANS = 0          word pin = GND
```

| block | parts |
|---|---|
| tick ÷ 8, pause | 74HC393 |
| 10 ms step | ½ 74HC390 |
| 100 ms and 60 % break | 74HC4017, ¼ 74HC4002 |
| `SRC` mux, dial-tone XOR | ¼ 74HC157, ¼ 74HC86, ½ 74HC74 |
| seize delay | ½ 74HC123, or a '163 and the DIP |
| buttons, debounce | 16 SMD, a resistor network, ½ 74HC74 |
| encode 16 pins to 1..16 | 2 × 74HC148 |
| pulse count | ½ 74HC193 and one flip-flop: five bits, so D can still load 16 |
| RC astable (if fitted) | ¼ 74HC14, pot, C; ½ 74HC123 |

**≈ 12 packages**: the hotline card's dialler, plus the encode.

---

## 6. Against a register, and against the flood

The card is a caller. Lift, wait for dial tone, dial `h s`, and the called line
rings. Dial `1 e b h s` and the same pulses go down every seized trunk live: the
origin's register consumes the key and restarts, the monitors read `e b`, the
owner claims, and `h s` land in the owner's register (`network.md` §4).
Nothing in the exchange is different from a rotary phone on a line card.

---

## 7. Open

- **The DIP rates of §2.2.** On a 10 ms step a '4017 makes only whole
  multiples of 10 ms, so 8 pps (125 ms) and 12 pps (83 ms), and a 67 % break,
  are not jumpers on it: the jumpers would have to change the step itself
  (the ÷10 ahead of it). Not designed; 10 pps 60/40 is.
- **No model in `newimpl`.** A bench would fit the card on a socket of
  `top_net`, originate a local call and a flood, and walk the RC rate against
  the register's windows.
- **Not measured**: the circuit, including the '4017's 60 % NOR and the buttons
  against bounce; a real RC astable against the register's 7–12 pps window and
  a pot at the end of its travel; dial-tone detect against a real tone card, as
  for the hotline card's XOR; a first key of A–D through a marker that has been
  given a meaning for it.
