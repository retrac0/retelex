# Conference: a bridge with no codec in it

A meet-me conference on CVSD bit streams: one talker at a time, bits switched
rather than summed, in a block of its own with a private party bus between its
eight leg cards.

> **Proposed.** **Measured in:** `sim/exch.py confer` (`sim/exch.log`): the
> detector, floor and switch. No circuit is drawn and no RTL bench runs a
> bridge; the marker's side is the answers-to hunt `tb_max` runs (`card-word.md` §5).

---

## 1. Architecture

The conference **block** is an ordinary block (`block-stack.md`): its number
from its header jumper, eight port cards, eight ports dialled `h 0` to `h 7`,
and nothing on the bus that any block does not have. Inside, its eight **leg
cards** share a **party bus** — `DATA`, `HELD`, `KEEP`, `ASK`, and `PRI`, a
chain in slot order — and one jumper makes them **two bridges of four or one
of eight** (§5).

**The party bus never leaves the block.** The channel socket has one spare pin
(`a14`) and the bus one spare, pin 48, which the console claims (`bus.md` §2).
Five more signals would have to borrow line-feed and ringing pins or grow the
bus, for something only eight ports use.

**Nothing external**: no subscriber line, so no −48 V, no ringing and no
analog rails, 74HC at 5 V throughout.

---

## 2. Why bits, not a sum

**CVSD bits cannot be added.** Summing needs every party decoded, summed and
encoded again: a codec pair on every leg, a codec tandem for every party
(about 2 dB of codec noise, `analysis/why-bits.md` §1), and every open
microphone's noise in the sum. **Bits can be switched.** One party talks at a
time; the bridge chooses who, and every other party receives that party's bits
exactly as sent — no codec, no tandem, no added noise however many legs are
open. It is a voice-switched speakerphone done on the bit streams.

An analog sum bus for two × 4 costs about as many packages (~80 against ~72),
but semi-analog ones (LM13700, LM311, TL07x) needing ±12 V and trims, and a
tandem on every path. Prefer the party bus unless true full duplex is required.

---

## 3. How it works

```
 legs      ordinary ports, /ANS low, each connected both ways to its caller
 detector  on the caller's bits: runs of three equal bits, counted over a 16 ms
           window.  8 or more in a window = the caller SPOKE
 silent    8 windows, 128 ms, without speaking
 floor     one leg at a time.  The holder keeps it until it is silent AND another
           leg has spoken; then the first leg in slot order that spoke takes it.
           No holder yet: the first leg to speak
 bus       DATA  the holder's C_RX, driven by it alone    HELD  a leg holds the floor
           KEEP  the holder is not silent                  ASK   another leg spoke
           PRI   a daisy chain in slot order
 C_TX      HELD and not mine → DATA;  otherwise FILL.  The holder hears silence
 A_TX      = A_RX: a leg answers when called and drops when its caller does
```

**Runs of three** drive the decoder's syllabic filter, so their density is
the signal's loudness read from the bits without decoding them.

**The floor stays with the last talker.** It passes only when someone else
talks, so a holder's next word after a pause is never clipped, and a silent
bridge does not switch. A listener whose line echoes the holder "speaks" only
while the holder does, so the floor never passes on echo; with one direction
open there is no loop through two hybrids to sing.

---

## 4. Measured

`exch.py confer`, with the repository's test talkers and room noise 45 dB below
nominal speech in every microphone. **The detector**, as the share of 16 ms
windows whose count reaches 8:

| | windows reaching 8 | "talking": 16 ms rms within 30 dB of nominal |
|---|---|---|
| speech at nominal | 66.0 % | 73.5 % |
| 10 dB down | 46.5 % | 64.1 % |
| 20 dB down | 19.8 % | 43.9 % |
| 30 dB down | 1.4 % | 21.7 % |

Room noise alone trips it in **every** window at 20 dB below speech, 0.10 % at
30 dB, never at 40 dB or on `FILL`.

**The hangover.** B says "mm-hm" while A talks, then answers 100 ms after A
stops; separately, all 126 ordered pairs of seven talkers, one talking over the
other for 3 s:

| silent after | "mm-hm" heard | answer switched after its onset | floor changes in 3 s of double talk (mean / most) | interrupter carried | holder cut off |
|---|---|---|---|---|---|
| 64 ms | 0 | 7 ms | 3.6 / 8 | 61 % | 34 % |
| **128 ms** | **0** | **7 ms** | **2.2 / 5** | **54 %** | **38 %** |
| 256 ms | 0 | 135 ms | 1.1 / 3 | 41 % | 34 % |
| 512 ms | 0 | 423 ms | 0.5 / 3 | 26 % | 28 % |

A reply loses what is left of the hangover, plus up to a window to detect it.
128 ms costs double talk (the floor changes about twice in 3 s, not once); it
is also the silence counter's Q3, where 256 ms would need a fifth bit.

**The switch.** The listener's decoder follows the new talker from the state
the old one left. Over 400 switches between talkers 1–7:

| | back within −30 dB of the new talker's own decode | peak in 20 ms, heard ÷ own decode |
|---|---|---|
| **as the bridge does it**: the old holder silent 128 ms | 16.1 ms median, 27.6 ms worst | −0.8 dB median, **+3.6 dB worst** |
| the floor passed while both talked | 14.4 ms median, 26.4 ms worst | +0.1 dB median, **+26.2 dB worst** |

**The hangover keeps the switch clean**: after 128 ms of silence the decoder
has relaxed to its smallest step and the new talker fades in without a pop.
Clear of a switch, the other parties hear the holder's own decode, any
difference 84 dB or more below it.

---

## 5. The circuit, the jumper and the cost

| per leg | parts |
|---|---|
| the caller's last three bits; all equal | 74HC164, ½ 74HC86, ¼ 74HC02 |
| window: the 1 ms tick ÷ 16; the runs in it, Q3 = spoke | 74HC393 |
| silence: windows since spoke, Q3 = 128 ms, held there | ½ 74HC393 |
| spoke latch; the floor | 74HC74 |
| `DATA` three-state; `HELD`, `KEEP`, `ASK` open-drain | 74HC125 |
| take and let go, the priority chain, the `C_TX` select | 74HC00, 74HC08 |

**≈ 9 packages a leg, all 74HC**: ≈ 72 for eight legs and the ribbon, beside
the block's own header and port cards. Every leg counts the same 1 ms tick,
`TX_OCT` ÷ 8 in the silence counter's spare half '393 (the socket carries no
`TICK`), from `/RESET`, so all windows end together and take and let-go are
decided on one edge. A leg whose caller hangs up drops the floor with `A_RX`.

**The jumper: one bridge of eight, or two of four.** It cuts the party bus and
the priority chain between legs 3 and 4, and forces the one bit in which the
second four legs' answers-to number differs, so the segmentation, the chain and
the numbers move together and cannot disagree:

```
             70   71   72   73  │ jumper │  74   75   76   77
 answer to   70   70   70   70  │   ○    │  74   74   74   74    out: two bridges
             70   70   70   70  │   ●    │  70   70   70   70    in:  one of eight
```

**Two of four is the default.** The worst failure is one leg wedging a bridge
(§7): eight legs give eight chances of it and lose the whole bridge, four lose
half the capacity. Two small conferences also outnumber one large one, and §4
measured three parties: four is a short step from that, eight is not.

**A conference block spends a dialable block** (`numbering.md` §2): at 7 the
bridges are 70 and 74.

---

## 6. The marker's part

- **A leg is an ordinary line with `/ANS` low**, so `E` reaches it steadily and
  the caller hears no ringback and waits for no cadence.
- **Every leg answers to its bridge's number** (`card-word.md` §5), in the
  primary octet, wired on the leg card, the first leg like the rest. No class
  of its own, no secondary word.
- **Dialling a bridge** (`h s`, or `1 e b h s` from anywhere): the class marker
  reads the number's own port, 70; free, it is connected; otherwise the marker
  hunts from 01 for the first free port that answers to 70 (`marker.md` §4.5). No
  free leg: **busy tone**, since 70 is a line that was not free. A remote party
  holds one trunk channel on every link between it and the bridge.
- **No key is special to it.** A bigger bridge is more legs on one segment,
  up to the block's eight; there is no sum to clip.

---

## 7. What it is not

- **Two at once.** An interrupter gets through only in the holder's pauses,
  54 % of its speech; cross-talk comes out one voice at a time.
- **The holder hears nobody** while holding (that would need a second `DATA`).
- **A quiet caller**, 30 dB down, reaches the threshold in 1.4 % of windows.
- **A caller in noise 20 dB below speech** never falls silent and keeps the
  floor until hanging up or the console releases the leg.

---

## 8. Open

- **A floor-hold limit.** A cap on how long one leg may hold the floor would
  cure §7's wedged leg; not modelled.
- **The party bus in the block-stack form.** Four bussed lines and a chain
  between eight leg cards; the stack carries three pass-through spares
  (`block-stack.md` §3), so the bus wants a ribbon of its own across the leg
  cards. Not drawn.
- **Not measured:** every circuit (the leg, the party bus, the jumper); the
  bridge with real phones — handset levels, room noise and echo from real
  hybrids — and how people take to a half-duplex meeting; a bridge in any RTL
  bench, and through a network.
