# The exchange — conference: a bridge with no codec in it

A meet-me conference on CVSD bit streams: one talker at a time, bits switched
rather than summed, in a block of its own on the mainboard bus with a private
party bus inside.

> **Status: proposed.** Speech detector, floor and switch measured in
> simulation (`exch.py confer`; `exch.log` is the run). No circuit on a bench.
> Class *conference* is **retired**: a leg is an ordinary line (§6). Marker
> hunting of legs is proposed with `ex-groups.md`; the `calls` model still has
> a conference leg as a line.

---

## 1. Architecture

The conference **unit** is one ordinary exchange block. It attaches to the
mainboard buses like any other block. Inside it keeps a private **party bus**.
Onto that bus sit the bridge modules: **two of four legs, or one of eight**, by
strap (or by fitting two 4-leg modules vs one 8-leg module).

```
 main exchange buses (highways, clocks, FILL, SDATA/SCLK, …)
         │
    conference block  ← ordinary block: HC_OUT, HA_OUT, /BLK, eight ports
         │
    internal party bus (DATA, HELD, KEEP, ASK, PRI + overflow)
         │
    ┌────┴────┐
   4-leg     4-leg     strap open  → two conferences
   bridge    bridge
         or
      one 8-leg bridge  strap closed → one conference
```

| | |
|---|---|
| **Outer face** | `HC_OUT`, `HA_OUT`, `/BLK`: three pins and three shunt columns, its number set like any block's (`exch-mainboard.md` §1). The common cable: clocks, `FILL`, `TICK`, the serial control word. Eight ports, dialled `h 0` to `h 7` |
| **Inside** | `DATA`, `HELD`, `KEEP`, `ASK`, `PRI` on the block's own ribbon. Which leg holds the floor, and when it passes. The legs' words and `/ANS`, fixed, no jumper |
| **On the party bus** | **leg modules** — detector, floor, `DATA` drive — not mini exchange blocks. The exchange sees **one** block number and eight ports, not nested `/BLK` identity |

**Why the party bus never leaves the block.** The channel slot has one pin spare
(`a14`, `ex-extensions.md` §2.1), and the mainboard cable is thirty-eight
signals identical at every tap (`exch-mainboard.md` §1). Five more bussed
signals would have to borrow line-feed and ringing pins — ninety volts of
ringing beside a 74HC input — or grow the cable. Neither is worth paying for
something only eight ports will ever use. The primary bus stays exactly what it
is.

**Nothing external.** No subscriber line, so no −48 V, no ringing, no PTC, no
analog rails and no hybrid: 74HC at 5 V throughout.
`exch-mainboard.md` §2.4's rule that −48 V and `RING` never leave a subrack does
not reach it.

**A bridge is not legs scattered through the line slots.** Callers dial into
the block's ports; the fabric treats them like any hunt group. The marker does
not mux every line in the exchange onto a conference selector.

---

## 2. Why bits, not a sum

**CVSD bits cannot be added.** Summing needs every party decoded, summed and
encoded again. That is a codec pair on every leg, a codec tandem for every party
(−4.8 dB, `exch-protocol.md` §2), and every open microphone's noise in the sum.
The meet-me bridge first written here was that. **Bits can be switched.** One
party talks at a time. The bridge chooses who, and every other party receives
that party's bits exactly as sent: no codec, no tandem, and no added noise
however many legs are open. This is a voice-switched speakerphone, done on the
bit streams.

An analog sum bus for the same two×4 costs roughly the same *package count*
(~80 vs ~72 incremental) but those packages are semi-analog codecs (LM13700,
LM311, TL07x), need ±12 V and trims, and put a tandem on every path. Prefer the
digital party bus unless true multi-talker full-duplex is required.

---

## 3. How it works

```
 legs      eight cards in a conference block (§1, §5), ordinary lines with `/ANS`
           low, joined by the block's own ribbon: the party bus.  Each is an
           ordinary port.  Its caller listens to it and it listens to its
           caller: a two-way connection
 detector  on the caller's bits: runs of three equal bits, counted over a 16 ms window (TICK / 16).
           8 or more in a window = the caller SPOKE
 silent    8 windows, 128 ms, without speaking
 floor     one leg at a time.  The holder keeps it until it is silent AND another leg has spoken; then the
           first leg in slot order that spoke takes it.  No holder yet: the first leg to speak
 bus       DATA  the holder's C_RX, driven by the holder alone      HELD  a leg holds the floor
           KEEP  the holder is not silent                            ASK   a leg other than the holder spoke
           PRI   a daisy chain in slot order
 strap     cuts all five between legs 3 and 4: one bridge of eight, or two of four (§5)
 C_TX      HELD and not mine → DATA;  otherwise FILL.  The holder's own caller hears silence
 A_TX      = A_RX: a leg answers the moment it is called and drops when its caller does
```

**Why runs of three.** A CVSD encoder sends three equal bits in a row when its
step is too small for the signal it follows. The density of those runs is what
drives the decoder's syllabic filter (the law's run length is 3), so it is the
loudness of the signal, read from the bits without decoding them. The detector
is a shift register, two gates and a counter.

**Why the floor stays with the last talker.** The floor passes only when
someone else talks, so a holder's own next word after a pause is never clipped,
and a silent bridge does not switch at all. It also protects against echo: a
listener whose line echoes the holder's voice "speaks" only while the holder
does, and the floor never passes while the holder is talking. With only one
direction ever open, there is no loop through two hybrids to sing.

---

## 4. Measured

`exch.py confer`, with talkers of this repository's own test set and room noise
45 dB below nominal speech in every microphone.

**The detector.** Percentage of 16 ms windows whose count reaches 8:

| | windows reaching 8 | "talking": 16 ms rms within 30 dB of nominal |
|---|---|---|
| speech at nominal | 66.0 % | 73.5 % |
| 10 dB down | 46.5 % | 64.1 % |
| 20 dB down | 19.8 % | 43.9 % |
| 30 dB down | 1.4 % | 21.7 % |
| room noise alone, 20 dB down | **100 %** | |
| room noise alone, 30 dB down | 0.10 % | |
| room noise alone, 40 dB down, or `FILL` | 0 | |

**The hangover.** A three-party conversation: B says "mm-hm" while A talks,
then answers 100 ms after A stops. Separately, all 126 ordered pairs of seven
talkers, each with one talking over the other for 3 s:

| silent after | B's "mm-hm" heard | B's answer switched, after its onset | floor changes in 3 s of double talk (mean / most) | interrupter carried | holder cut off |
|---|---|---|---|---|---|
| 64 ms | 0 | 7 ms | 3.6 / 8 | 61 % | 34 % |
| **128 ms** | **0** | **7 ms** | **2.2 / 5** | **54 %** | **38 %** |
| 256 ms | 0 | 135 ms | 1.1 / 3 | 41 % | 34 % |
| 512 ms | 0 | 423 ms | 0.5 / 3 | 26 % | 28 % |

A reply loses whatever is left of the hangover when it begins, counted from the
last speaker's last loud window, plus up to one window to detect it. At 128 ms,
a reply 100 ms after A stopped lost 7 ms; at 256 ms, it lost 135 ms. The price
of 128 ms is in double talk, where the floor changes about twice in 3 s instead
of once. 128 ms is also the silence counter's Q3; 256 ms would need a fifth bit.

**The switch.** At the switch, the listener's decoder stops following one
talker and starts following another from the state the first left it in. Over
400 switches between talkers 1–7:

| | back within −30 dB of the new talker's own decode, after | peak in 20 ms, heard ÷ own decode |
|---|---|---|
| **as the bridge does it**: the old holder silent for 128 ms | 16.1 ms median, 27.6 ms worst | −0.8 dB median, **+3.6 dB worst** |
| if the floor passed while both were talking | 14.4 ms median, 26.4 ms worst | +0.1 dB median, **+26.2 dB worst** |

**The hangover is also what keeps the switch clean.** After 128 ms of the old
holder's silence the decoder has relaxed to its smallest step. The new talker
fades in over about 16 ms and nothing pops. A switch between two talkers in full
voice would leave the decoder with the first talker's step, and the result would
be a pop up to 26 dB above the speech. At a word's start (the usual case in the
conversation) the switch was clean within 4 ms. Clear of a switch, what the
other parties heard was the holder's own decode, with any difference 84 dB or
more below it.

---

## 5. The circuit, strap and cost

| per leg | parts |
|---|---|
| the caller's last three bits; all equal | 74HC164, ½ 74HC86, ¼ 74HC02 |
| window: TICK ÷ 16; the runs in it, Q3 = spoke | 74HC393 |
| silence: windows since spoke, Q3 = 128 ms, held there | ½ 74HC393 |
| spoke latch; the floor | 74HC74 |
| `DATA` three-state; `HELD`, `KEEP`, `ASK` open-drain | 74HC125 |
| take and let go, the priority chain, the `C_TX` select | 74HC00, 74HC08 |

**≈ 9 packages a leg, all 74HC: no codec and no analog part.** Every leg
divides the same bussed `TICK` from `RESET`, so all windows end together, and
take and let-go are decided on the same edge from the same bus state. A leg
whose caller hangs up drops the floor with its `A_RX`.

**The strap: one bridge of eight, or two of four.** One strap block cuts all five
bus signals between legs 3 and 4, and carries the two overflow bits with them:

```
                70   71   72   73   │ strap │   74   75   76   77

  DATA  HELD   ──●────●────●────●───┤   ○   ├───●────●────●────●──
  KEEP  ASK                         │       │
  PRI          ──►────►────►────►───┤   ○   ├───►────►────►────►
  o bit          o    o    o    ·   │   ○   │   o    o    o    ·

  strap out, as drawn   two bridges of four, at 70 and at 74
  strap in              one bridge of eight, at 70: the cut closes, PRI runs through, 73's o is set
```

**One strap, not two things that must agree.** The segmentation of the bus, the
priority chain and the overflow bits the marker hunts on are all inside the
block, so all three move together and cannot be set inconsistently. Everywhere
else a hunt group is jumpers on each card (`ex-extensions.md` §2.4), where
getting one wrong is possible; here it is not.

**Two of four is the default, and the strap is the exception.** §7's worst
failure is one leg wedging a whole bridge: a caller in noise 20 dB below speech
never falls silent, so that leg holds the floor until it hangs up. Eight legs
give eight chances of it per conference and lose the whole bridge; four give four
and lose half the exchange's conference capacity. Two conferences at once is also
the commoner traffic — two three-party calls far outnumber one six-party call.
And §4 measured three parties, and pairs in double talk: four is a short step
from what was measured, eight is not.

**Cost.** ≈ 9 packages a leg, above, and ≈ 82 for the block's own fabric and
supervision (`exch-fabric.md` §5): **≈ 154 packages for eight legs, two bridges
and the ribbon.** The only part of it that is not an ordinary block is the
ribbon and its strap.

**Where it sits in the numbering.** Blocks 0 and 1 are never dialled — 0 is the
operator and 1 the network's key, so `h` is 2–7 (`exch-marker.md` §2). A
conference block takes one of those six: at 7 the bridges are 70 and 74, and the
exchange keeps 40 of its 48 dialable ports as lines. A second conference block is
another dialable block spent, and four bridges.

---

## 6. The marker's part

> **Class *conference* is retired** (its former code `111` is now *restricted*).
> A leg is an ordinary line: `/ANS` low, `A_TX` = `A_RX`, no special class in the
> word. The marker reaches a bridge by number like any hunt group — by the `o`
> run below, or by *answers to* (`ex-groups.md` §5) with no secondary word and
> no fifth `'151` — both retired with class *conference*.

- **`/ANS` tied low** on the leg, so that it does not ring: E reaches the leg
  steadily, not in the ring cadence, and the caller hears no ringback. A leg
  that rang in cadence would take up to 4 s to answer, with ringback in the
  caller's ear the whole time.
- **A bridge is a hunt group: a run of adjacent legs on one segment of the party
  bus, and its number is its first leg's.** It is the hunt group of
  `ex-extensions.md` §2.4: every leg but the last sets the overflow bit of its
  word. Dialling any leg takes the first free leg from that one onward, in slot
  order, until a leg that is not free has the bit clear. No free leg →
  cannot-complete. **A conference block is two bridges of four or one of eight,
  by its strap** (§5), and an exchange may have more than one such block. **A
  run never crosses a block boundary**, because the party bus never leaves the
  block. Under `ex-groups.md` §5 the same bridge is legs that *answer to* its
  number, and the run leaves the marker.
- **A bridge is reached only by its number.** No key is special to it: 8 stays a
  spare first key, and gives cannot-complete.
- **Across the network a bridge is dialled like any line**, `1 e b h s` from
  anywhere. If 55 on exchange 26 is a bridge, line 24 of exchange 25 dials
  `1 2 6 5 5`: the flood, exchange 26's claim on `2 6`, its register's `h s` = 55,
  then the same hunt. Each remote party holds one trunk channel on every link
  between it and the bridge.
- **The marker's part of the hunt** uses the free-running scanner, as every hunt
  does. A flip-flop is set when the scanner reaches the dialled port (a 74HC688
  comparing the scanner with the digit store), and cleared at a port that is not
  free and has its overflow bit clear. The first free port while it is set is
  taken: **≈ 2 packages**, and at most two scans, 16 ms. It is the same hunt for
  every kind of group.
- **A bigger bridge is more legs on one segment.** There is no sum to clip and no
  noise to add, so the limit is the block and its strap, not the audio: eight is
  the most one bridge can be, because eight is a block. The cost of a bridge is
  counted in dialable block numbers (§5), not in line slots, and what argues
  against spending more of them is §7, not the bit stream.
- **Nothing hunts onward unless its card says so.** Dialling a busy phone must
  not ring its neighbour, so a port overflows only if its word's overflow bit is
  set. A sales desk or a pool of data ports is a group in the same way
  (`ex-extensions.md` §2.4).

---

## 7. What it is not

- **Two at once.** The bridge picks one. An interrupter gets through only in the
  holder's pauses, in 54 % of its speech. Laughter and cross-talk come out as
  one voice at a time.
- **The holder hears nobody** while holding, not even someone trying to cut in.
  Sending the holder the previous holder's bits would need a second `DATA` line;
  not proposed.
- **A quiet caller**, 30 dB down, reaches the threshold in 1.4 % of windows and
  will seldom get the floor.
- **A caller in noise 20 dB below speech** never falls silent. Once that leg has
  the floor it keeps it, until that caller hangs up or the operator clears the
  leg's latch from the console. A limit on how long one leg may hold the floor
  would cure it; not modelled.

---

## 8. Not measured

- **Every circuit here.** The conference leg, its party bus and the block's
  strap.
- **The conference with real phones**: handset levels, room noise and echo from
  real hybrids, rather than the test set's talkers with added noise; and how
  people take to a half-duplex meeting.
