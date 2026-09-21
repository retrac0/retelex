# MF8 channel cards — specification

Three cards for the eight channel slots of `mf8-backplane.md`:

| card | faces | the codec is | signalling |
|---|---|---|---|
| **CVSD subscriber line card** (§2) | a CVSD phone on two pairs, `subscriber-line.md` | in the phone | held bit patterns on the line; the A bit on the trunk |
| **Analog FXS / FXO card** (§3) | a 2-wire telephone (FXS) or a 2-wire CO line (FXO) | on the card — `mf8-spec.md` §12.1's engine | loop start, through the A bit |
| **Data card** (§4) | a synchronous DTE, a PCM codec, or an async terminal | none | DTR / DSR through the A bit |

All three present the slot interface of `mf8-backplane.md` §3 and nothing else
to the backplane. The E&M four-wire CVSD card of `mf8-spec.md` §12.1 is the
fourth card; its engine, audio path and E&M leads are specified there and are
reused here unchanged.

> **Status: proposed.** Measured: the signalling path through the A bit (§5),
> the plesiochronous slip (`mf8-backplane.md` §7), the codec's component
> tolerances (`mf8-spec.md` §12.1), the subscriber line's detectors
> (`subscriber-line.md` §3). The circuits are proposals from data-sheet figures;
> nothing has been on a bench.

---

## 1. Which card faces which

The trunk carries one signalling bit each way per channel, and every card gives
it one of two meanings:

| end | `A_TX` — sent | `A_RX` — received |
|---|---|---|
| **station end** — subscriber line card, FXS card, E&M card | the phone is off-hook (the M lead) | ring the phone (the E lead) |
| **office end** — FXO card | ringing is present on the CO line | close the loop toward the CO |

So a station end at one end of a channel and an office end at the other
**extend a line**: the CO rings, the FXO card sends A, the far phone rings; the
phone goes off-hook, its card sends A, the FXO card closes the loop, and the CO
sees a phone answer. Dial pulses are on-hook pulses on A, and §5 measures them
end to end. Two station ends make a **hotline**: either phone going off-hook
rings the other, and both off-hook is a call.

| near end | far end | result |
|---|---|---|
| subscriber line, FXS, or E&M | FXO | an extended line: the phone is on the CO as if wired to it |
| subscriber line or FXS | subscriber line or FXS | a hotline between two phones |
| E&M | E&M | a tie trunk between two PBXs |
| data | data | a 64 kbps pipe |
| FXO | FXO | **not a configuration** — each CO line would seize the other on ring |
| any voice card | data card | **wrong**: loud, locked, not squelched (`mf8-spec.md` §13). Label every slot |

The station ends are interchangeable: a digital phone at one end and an analog
one at the other need nothing special, because both cards put off-hook on A and
read ring from A.

---

## 2. CVSD subscriber line card

Two pairs to one phone. The phone holds the codec; this card holds the line
interfaces, the hook detector and the slot logic. Everything about the line
itself is `subscriber-line.md`; what follows is the card.

```
  phone ═══ upstream pair ═══▶ [ 128 kBaud receiver, §9.4 ] ─Q, strobe──▶ [ sync ] ──▶ C_TX[n]
                                       │ LONG, MID, carrier                  TX_CLK
                                       └─▶ [ hook detector ] ── ON_HOOK ──┬─▶ /A_TX[n]
                                                                          │
  phone ◀══ downstream pair ◀══ [ encoder, §9.2 ] ◀── DN_D ◀── [ rule ] ◀─┤◀── C_RX[n] ─▶ [ sync ]
              48 V phantom          TX_CLK, TX_HB                          │◀── A_RX[n] ─▶ [ RC, '14 ]
                                                                          └◀── FILL, MUTE
```

### 2.1 The line side

| item | specification | from |
|---|---|---|
| Downstream driver | 75176 driver half, series matching, 150 ns slew limit, 1:1 transformer ≥ 33 mH **with the line-side centre tap brought out** | `mf8-spec.md` §9.3 |
| Downstream encoder | ½ 74HC74 + ¼ 74HC00, `H` = `TX_CLK`, clocked by `TX_HB` | §9.2 |
| Upstream receiver | the §9.4 interval classifier — '86, '221, '123, '74 — at the **64 kbps plug**: filter corner 128 kHz, classifier 11.7 µs, dead time 3.1 µs, carrier timeout 31.3 µs | §9.4, §9.7 |
| Upstream transformer | 1:1, ≥ 33 mH, centre tap brought out; 100–135 Ω termination on the line side of the comparator | §9.3 |
| Protection, both pairs | gas tube to ground on both conductors, series PTC, TVS clamping above the 48 V feed | §9.3 |
| Phantom feed | 48 V from the `−48 V` rail into the downstream centre tap, returned through the upstream centre tap; 100 mA PTC on the card in series with the slot fuse; ≤ 40 mA to the phone | `subscriber-line.md` §1 |

The receiver's five timing components go on the §9.7 rate plug, populated for
64 kbps: this card never runs at another rate, so the plug is a fixed footprint
here. The centre taps carry DC only; the transformers' 33 mH is specified for
the family's 64 kbps line rate already.

### 2.2 The hook detector

`subscriber-line.md` §3, on the receiver's own outputs:

```
X          =  Q XOR Q[n−2]                        two flip-flops (½ 74HC74) and ¼ 74HC86
violation  =  LONG · MID at an accepted edge      ¼ 74HC08
           +  gap > 1.25 cells                    ½ 74HC123, retriggerable, 14.6 µs at 128 kBaud
           →  held 16 cells                       the same '123's pulse width, 250 µs
G          =  X + violation + /carrier            ¼ 74HC32
G ─[ RC, τ = 4 ms ]─[ ¼ LM339, 0.85 / 0.70 ]─→ ON_HOOK
```

The thresholds are a comparator with a resistive reference, not a Schmitt gate:
0.85 and 0.70 of the swing sit where no '14 threshold does. Measured clean of
false events to sd 0.8 and 100 impulses/s, and on a dead pair at every noise
level (`subscriber-line.md` §3.1); the violation term is what makes a cut pair
read on-hook rather than off-hook, and it is not optional.

### 2.3 The slot logic

The exchange-side rule of `subscriber-line.md` §4, in bus signals:

```
DN_D     =  ON_HOOK ? ( A_RX_f ? 0 : FILL ) : C_RX_s
C_TX[n]  =  Q_s
A_TX[n]  =  NOT ON_HOOK
```

where `C_RX_s` and `Q_s` are `C_RX[n]` and the receiver's data latch each
passed through two 74HC74 stages clocked by `TX_CLK` — the two clock-domain
crossings of `mf8-backplane.md` §2, one 74HC175 for both — and `A_RX_f` is
`A_RX[n]` through the §14 RC (τ = 2 ms) and ¼ 74HC14. `FILL` is the bus's
`1010`, so the card generates no idle pattern of its own; all-zeros is ground.
The rule is three 2:1 selections, ¾ of a 74HC157.

`MUTE` needs no gate: while the trunk is not locked the receiver's '259 is
cleared, `A_RX[n]` reads 0 and the phone hears `FILL` if on-hook; if off-hook
it hears `C_RX[n]`, which is then the far end's fill or nothing — add `MUTE` to
the `ON_HOOK` select so an off-hook phone hears `1010` through an outage rather
than the receiver's last latched bits:

```
select   =  ON_HOOK + MUTE
```

The phone's own `1100` on-hook pattern crosses the trunk as channel bits, as
`subscriber-line.md` §4 notes; the far line card ignores it, because it reads
hook state from A.

### 2.4 The card's pins

Two connectors: the channel socket of `common-cards.md` §1, and its rear connector
there, §7.3, for the two pairs. **This card uses nine of the fourteen signal
pins, eleven where its optional word parts are fitted — more than anything else
in the set — and it is the only one that needs a2 and a4.**

| pin | | | what this card does with it |
|---|---|---|---|
| a1 | `TX_CLK` | in | `H` into the downstream encoder (§2.1), and the clock of both synchronizer stages of §2.3 — the one 74HC175 that crosses `C_RX[n]` and the receiver's latch into T |
| a2 | `TX_HB` | in | **the downstream encoder's clock.** 128 kHz, and this card is its only customer in either shelf. Without it the card cannot be fitted at all: `clocks.md` §4 exists for this pin and this card |
| a3 | `TX_OCT` | ○ | nothing in the base card. It loads the word '165 where that footprint is populated — an operator's position, a restricted phone (class 111, including warm), a hunt group, a nail (`extensions.md` §2.2) |
| a4 | `FILL` | in | the bus's `1010`, sent **downstream to the phone** while it is on-hook and not being rung. a data input of §2.3's ¾ 74HC157, and the reason the card carries no oscillator and no idle-pattern generator |
| a5 | `C_TX[n]` | **out** | `Q_s`: the upstream receiver's data latch, resynchronized to `TX_CLK` |
| a6 | `A_TX[n]` | **out** | `NOT ON_HOOK`, off §2.2's LM339 through ¼ 74HC04. Off-hook, held through dial pulses by the 4 ms RC and the violation term |
| a7 | `RX_CLK` | — | **this card has no R domain.** Its receive side is clocked by the *loop*, recovered on the card by §2.1's interval classifier, and everything the backplane hands it crosses into T on `TX_CLK`. That is what makes it indifferent to which shelf it is in (`clocks.md` §5) |
| a8 | `RX_OCT` | — | |
| a9 | `C_RX[n]` | in | through two 74HC74 stages on `TX_CLK` to `C_RX_s`, then downstream to the phone while it is off-hook |
| a10 | `A_RX[n]` | in | through the §14 RC (τ = 2 ms) and ¼ 74HC14 to `A_RX_f`: **ring the phone.** With it asserted and the phone on-hook the card sends all-zeros downstream, which is the ringer's own detector at the far end (`subscriber-line.md` §4) |
| a11 | `MUTE` | in | ORed into the `ON_HOOK` select, so an off-hook phone hears `1010` through an outage rather than the receiver's last latched bits (§2.3). **Two cards in the set read this pin and this is one** |
| a12 | the word | **out** | **tied to a row-*c* ground**: all ones, a plain line with no options (`common-cards.md` §2). The '165 footprint is on the board and unpopulated |
| a13 | `/ANS` | — | **open.** The port rings in cadence and gives the caller ringback, which is what a telephone wants |
| a14 | spare | ○ | open |
| c1, c3 | `+5 V` | in | all the logic |
| c9, c10 | `−48 V`, `−48 RET` | in | **the phantom.** 48 V into the downstream centre tap through the card's own 100 mA PTC in series with the slot fuse, returned through the upstream centre tap; ≤ 40 mA to the phone (§2.1) |
| c5, c7 | `±12 V` | — | there is no analog signal path on this card. The phone holds the codec |
| c12 | `RING` | — | **the point of the whole design.** No ring generator, no ring relay, no ring trip, no 90 Vrms anywhere near the card: the phone's ringer is armed by a bit pattern |
| | rear, 4 pins | | downstream pair, upstream pair, both carrying the phantom |

**a2 and a4 are on the channel socket because of this card.** No other card in
either shelf reads either: nothing else encodes a line, and every other card's
idle is its own codec's `1010`. `clocks.md` §4 calls that "one bullet away from
being noticed", and the matrix of `common-cards.md` §1.3 is where it stops being
possible to miss.

**a7 and a11 are the two pins that say what kind of card this is.** It ignores
`RX_CLK` because its receive timing comes off the subscriber loop and not off the
backplane. It reads `MUTE` because it is the one card that can act on it for
free: the downstream path already carries a 2:1 select with `FILL` on an input,
so muting is one more term in §2.3's `ON_HOOK` and not a gate. The cards that do
not read it are the ones that would have to add the mux (`common-cards.md` §1.4),
which is why they have not.

### 2.5 Parts

| block | parts |
|---|---|
| Upstream receiver | 74HC86, 74HC221, 74HC123, 74HC74 |
| Hook detector | ½ 74HC74, ¼ '86, ¼ '08, ½ 74HC123, ¼ '32, ¼ LM339 |
| Downstream encoder | ½ 74HC74, ¼ 74HC00 |
| Synchronizers | 74HC175 |
| Rule | 74HC157, ¼ 74HC04 |
| A filter | ¼ 74HC14, one R, one C |
| Line | 75176, two transformers, gas tubes, PTCs, TVS |

**≈ 10 packages, two transformers, no relay, no ring generator, no high
voltage above the 48 V feed.** The '74, '123, '86 and '08 quarter-packages
share; the count above is what is populated.

### 2.6 The phone

The other end of I1 is the same receiver, the same encoder and the §12.1 codec
engine, with `subscriber-line.md` §4's phone logic: hook switch and dial
contact in series, `1100` sent on-hook, the ringer armed on the all-zeros
detector, the decoder fed `1010` while ringing. It is not a card in this
shelf, and its clocking — loop-timed from the downstream or free-running — is
open in `subscriber-line.md` §7; `mf8-backplane.md` §7 measured that either is
acceptable for voice.

### 2.7 Bring-up

1. **Receiver alone**, from a signal generator at 128 kBaud: eye, classifier
   threshold, dead time — the §9.4 checks at the 64 kbps plug.
2. **Hook detector** against `1100`, speech from a phone, and a dead pair with
   noise: confirm the 0.85 / 0.70 comparator and the violation hold.
3. **Loop the card to itself** across a short pair, downstream to upstream:
   `FILL` should come back as `1010` and `ON_HOOK` should read from the
   pattern sent.
4. **With a phone**, no trunk: off-hook must switch the downstream to `C_RX`
   (which is `FILL` with the trunk down) and put `A_TX` high; `A_RX` forced
   high from a jumper must ring it.
5. **Over the trunk**, against an FXO card on a CO line: ring in, answer, dial
   out by pulses and DTMF.

---

## 3. Analog FXS / FXO card

One board, two populations, the codec on it. It is the E&M card of
`mf8-spec.md` §12.1 with the E&M leads replaced by a loop-start line circuit
and a hybrid: the engine, its values and tolerances, the audio filters and the
level rule carry over unchanged, and are not repeated.

```
 2-wire line ══▶ [ protection ]─[ hybrid, 600 Ω ]─┬─▶ [ trim ]─[ 300–3400 Hz ]─▶ ENCODER ─▶ C_TX[n]   (TX_CLK)
                                                  └─◀ [ trim ]◀[ recon 3400 ]◀─ DECODER ◀─ C_RX[n]   (RX_CLK)
                 FXS: feed, loop detect, ring relay, ring trip ──▶ A_TX[n] ; A_RX[n] ─▶ ring
                 FXO: ring detect, loop closure                   ──▶ A_TX[n] ; A_RX[n] ─▶ close loop
```

### 3.1 Signal mapping

| | **FXS** — faces a telephone | **FXO** — faces a CO line |
|---|---|---|
| `A_TX[n]` — sensed here | loop current flowing: the phone is off-hook | ringing present on the line |
| `A_RX[n]` — from the far end | apply ringing to the phone | close the loop toward the CO |

Both go through the §14 RC (τ = 2 ms) and ¼ 74HC14 on the receive side; the
far end's cadence passes through as a slow A pattern, so distinctive ringing
reproduces without special handling, and dial pulses cross as §5 measures.

### 3.2 The engine

`mf8-spec.md` §12.1, verbatim — MIL-STD-188-113's law at 64 kbps: 3-bit run
window, τ_syl 5 ms, τ_int 1 ms, 16:1 compression at 30 % run-of-threes (51:1,
34.2 dB full scale), `C_int` 10 nF, `R_int` 100 kΩ, `Iabc` 160 µA max and
3.1 µA min, `C_syl` 100 nF 2 %, `R_syl` 49.9 kΩ; 1 % resistors, 5 % film for
`C_int`, against the measured ±10 % syllabic budget. One LM13700 serves both
engines; `Iabc max` is the one trimmer, set by measuring `C_int`, not by ear.
The encoder is in the T domain on `TX_CLK`, the decoder in R on `RX_CLK`, and
the two never meet (`mf8-backplane.md` §2).

### 3.3 Audio path and hybrid

| item | specification |
|---|---|
| Hybrid | transformer, 600 Ω, with a compromise balance network — 600 Ω resistive to start |
| Trans-hybrid loss | **10–15 dB** per end, against real loops. This is the singing margin, and it is all the hybrid has to do |
| Level trims | one per direction, set so the engine sees its nominal 0.15 rms of full scale at the trunk's design level — before the `Iabc` trim, or the two fight |
| Filters | 300–3400 Hz on the encoder input, a 3rd- or 4th-order reconstruction low-pass at 3400 Hz on the decoder output; one TL074 |

**Echo needs no treatment.** The round trip through the carrier is one CVSD
bit each way, a frame, the trunk's propagation and the far hybrid: under
0.1 ms plus 5 µs per km. Echo is objectionable above 20–30 ms round trip. No
canceller, no suppressor, and no precision balance per loop; the compromise
network is for singing, not echo.

### 3.4 FXS population

| block | specification |
|---|---|
| Battery feed | from the backplane `−48 V` rail through the slot's 100 mA PTC; a feed bridge current-limited to **25–45 mA**; an inductive bridge or an electronic feed |
| Loop detect | a sense resistor in the feed into an opto, threshold **10–15 mA**; output → `A_TX[n]` |
| Ringing | the shelf `RING` bus, 20 Hz, ~80 Vrms (`mf8-psu.md`), from the Noisy PSU; a ring relay driven by `A_RX_f` connects it to the line **and disconnects the feed while it is connected**. **Cadence is `A_RX`** — the exchange (or far MF8) drives the A bit; this shelf does not generate `/RING_CAD` |
| Ring trip | **mandatory.** Sense the DC component through the ring path; on loop current, drop the ring relay within **200 ms**. Without it an answered phone keeps ringing |
| Protection | gas tube, PTC, TVS ahead of everything; the ring path rated for the 250 V peak the bus carries on top of battery |

Ring cadence comes from the far end's A bit, as it does for E&M; the ring
relay follows it through the 2 ms RC. `subscriber-line.md` §6 rejected DC loop
signalling *on the phantom* of a digital line; this card is the classical
alternative for an analog telephone, and carries the relay, the trip and the
ringing bus that the digital line was designed to avoid.

### 3.5 FXO population

| block | specification |
|---|---|
| Ring detect | series 1 µF 250 V capacitor, bridge rectifier, current limit, opto; the opto pulses at twice the ring frequency, so an **RC of ~100 ms** holds through the 20 Hz and follows the 2 s / 4 s cadence; output → `A_TX[n]` |
| Loop closure | `A_RX_f` drives a relay or solid-state switch across tip and ring, presenting a DC path in the **20–100 mA** range the CO expects; the transformer supplies the AC impedance |
| Dial pulsing | `A_RX_f` low opens the loop; §5 measures the pulses as they arrive |
| Protection | as FXS, without the ringing path |

### 3.6 Safety

This card is where high voltage first appears in the shelf: −48 V battery,
~80 Vrms ringing, outside-plant surges. Creepage and clearance between the line
side and the logic side; the optos are the safety barrier and are specified for
isolation rating, not just CTR; protection ahead of everything; and the `RING`
bus gets the same treatment wherever it runs (`mf8-backplane.md` §8 puts it
between ground pins, on the power row, and straps it only to FXS layers).

### 3.7 The card's pins

Two connectors: the channel socket of `common-cards.md` §1, and its rear connector
there, §7.3, which here is two pins — tip and ring. **One board, and the socket is
where the two populations differ most**: the FXS takes every rail the socket
offers, and the FXO takes `+5 V` and `±12 V` and nothing else.

| pin | | FXS | FXO | what the card does with it |
|---|---|---|---|---|
| a1 | `TX_CLK` | ● | ● | the encoder's clock. The engine's T half runs on it and only on it (§3.2) |
| a2 | `TX_HB` | — | — | nothing on this card encodes a line. Its line is analog and the only modulation on the board is the codec |
| a3 | `TX_OCT` | ○ | ● | loads the word '165, which the FXO always carries (class 100, *outside line*) and the FXS carries only where the line is more than a plain line |
| a4 | `FILL` | — | — | **the engine's own `1010` at silence is the idle**, so the card needs no fill pattern. That is the same property the tone card leans on (`tone-card.md` §3) |
| a5 | `C_TX[n]` | ● | ● | the encoder out, in T |
| a6 | `A_TX[n]` | ● | ● | **FXS:** loop current flowing — the 10–15 mA opto of §3.4, the phone is off-hook. **FXO:** ringing present, and *which* ringing is §5 of `common-cards.md`'s OFFICE / SEIZE strap: raw in the CO's cadence, or held 5 s and ORed with the loop closed. The strap is on this pin's meaning, not on a pin of its own |
| a7 | `RX_CLK` | ● | ● | **the decoder's clock.** The decoder is in R and the encoder in T, and the two never meet (§3.2) — which is why this card reads a7 where the CVSD line card does not (§2.4) |
| a8 | `RX_OCT` | — | — | |
| a9 | `C_RX[n]` | ● | ● | into the decoder, in R |
| a10 | `A_RX[n]` | ● | ● | through the §14 RC (τ = 2 ms) and ¼ 74HC14 to `A_RX_f`. **FXS:** drive the ring relay, which connects the `RING` bus and disconnects the feed while it is connected; ring trip drops it within 200 ms whatever this pin says (§3.4). **FXO:** close the loop; low opens it, and that is how dial pulses leave (§3.5) |
| a11 | `MUTE` | — | — | **not read, and arguably should be.** See below |
| a12 | the word | GND | '165 | **FXS:** tied to a row-*c* ground — all ones, a plain line. **FXO:** class 100, so the marker knows it is an outside line and 9 hunts it (`common-cards.md` §2) |
| a13 | `/ANS` | open | low | **FXS:** open, and the phone rings in cadence. **FXO:** tied low — an outside line must never be rung, and must not give its caller ringback |
| a14 | spare | ○ | ○ | open |
| c1, c3 | `+5 V` | ● | ● | the logic and the engine's digital half |
| c5, c7 | `±12 V` | ● | ● | **the analog card's rails**: LM13700, TL074, TL072, LM311, the filters and the trims (§3.2, §3.3, §3.8) |
| c9, c10 | `−48 V`, `−48 RET` | ● | — | the battery feed through the slot's 100 mA PTC, current-limited to 25–45 mA (§3.4). The FXO takes its battery from the CO |
| c12, c13 | `RING`, `RING RET` | ● | — | 20 Hz, ~80 Vrms, from the Noisy PSU, through the ring relay. Cadence = `A_RX`. **The strap at c12 is fitted only for an FXS layer** (`mf8-backplane.md` §8) |
| | rear, 2 pins | | | tip and ring |

**The FXS population is the only card in the set that uses every rail the socket
offers**, and c12 exists for it alone. A block or a shelf with no FXS card needs
no ring generator at all; the pins stay either way, because a card must be able
to arrive (`common-cards.md` §3).

**a11 `MUTE` is open on this card, in both populations, and that is a gap.** Two
of the seven columns in `common-cards.md` §1.3 read the pin: the CVSD line card
switches its phone to `FILL` (§2.3) and the data card forces `RXD` to 1 (§4.1). Here, while the trunk is not
locked the receiver's '259 is cleared, so `C_RX[n]` reads a steady 0 and the
decoder is handed all-zeros — which a CVSD integrator walks toward the rail on,
rather than the `1010` that is silence. `A_RX[n]` reads 0 at the same time, so
the FXS drops its ring relay and the FXO opens its loop and the call goes down
correctly; what is wrong is only what the subscriber hears on the way. The fix
is a gate into the decoder's input, ¼ of a package on a card that is already
≈ 11. **Nothing has been listened to and nobody has decided it is worth the
gate** (`common-cards.md` §9).

### 3.8 Parts

| block | population | parts |
|---|---|---|
| Engine, both halves | both | 3 × 74HC74, 74HC86, 74HC08, LM13700, TL072, LM311 — `mf8-spec.md` §12.1 |
| Audio filters and trims | both | TL074, TL072 |
| A filter | both | ¼ 74HC14 |
| Hybrid and balance | both | 600 Ω transformer, compromise network |
| Protection | both | gas tube, PTC, TVS |
| Ring detect | FXO | capacitor, bridge, opto, RC |
| Loop closure | FXO | relay or solid-state switch, opto drive |
| Battery feed | FXS | feed bridge, current limit |
| Loop detect | FXS | sense resistor, opto |
| Ring relay and trip | FXS | relay, DC sense |

**≈ 11 packages plus the transformer and a relay** in either population; the
cost is the magnetics and the relay. Lay out one board and depopulate.

### 3.9 Bring-up

1. **Engine looped to itself** on the card, no line: the §12.1 order — engine,
   then `Iabc`, then card to card over the backplane.
2. **Hybrid alone** against 600 Ω: 10–15 dB trans-hybrid loss before anything
   digital is connected.
3. **Levels** into the engine at nominal, before the codec trim.
4. **FXO ring detect** against a real ring generator; **FXS feed, loop detect,
   ringing, then ring trip specifically** — answer mid-burst, confirm ringing
   drops inside 200 ms.
5. **FXO–FXS pair over the trunk**: ring the remote phone from the CO, answer,
   supervision back, audio both ways, dial out by pulses.

---

## 4. Data card

One slot as a **64 kbps synchronous, bit-transparent, octet-aligned, slip-free
pipe**, with two clocks. The carrier never inspects the data; any pattern is
carried, and no scrambler is fitted or needed.

```
  DTE ─TXD─▶ [ RS-422 rx ]─▶ [ D flip-flop, TX_CLK ]─▶ C_TX[n]        TX_CLK ─▶ [ RS-422 tx ]─▶ TXC
                                                                       TX_OCT ─▶ [ RS-422 tx ]─▶ TX frame sync
  DTE ◀─RXD─ [ RS-422 tx ]◀─ [ D flip-flop, RX_CLK ]◀─ C_RX[n]        RX_CLK ─▶ [ RS-422 tx ]─▶ RXC
                                       ▲ forced 1 by MUTE              RX_OCT ─▶ [ RS-422 tx ]─▶ RX frame sync
  DTE ─DTR─▶ [ RS-422 rx ]─▶ A_TX[n]         A_RX[n] ─▶ [ RC, '14 ]─▶ [ RS-422 tx ]─▶ DSR
```

### 4.1 The pipe

| property | | why |
|---|---|---|
| Rate | 64 kbps, one bit per frame on `C` | the frame |
| Clocks | **two.** `TXC` is the local crystal, `RXC` the recovered clock; the DTE is clocked by the carrier in both directions, as a DCE clocks V.35 or X.21 | `mf8-backplane.md` §2: no elastic store, no slip, at the price of a DTE that accepts two clocks |
| Octets | aligned: superframe state *k* is bit *k* of the octet, b0 first at state 0; `TX_OCT` and `RX_OCT` mark state 7 | `mf8-spec.md` §6 |
| Signalling | `DTR` in on `A_TX[n]`, `DSR` out from `A_RX[n]` through the §14 filter; one bit each way at 8 kHz | the A bit is otherwise unused, and a far end that is not ready is worth knowing |
| On `MUTE` | `RXD` forced to 1 — mark idle to a synchronous DTE, idle to an async one; `DSR` drops with the '259 clear | `mf8-spec.md` §13 |

`A_TX` need not be strapped. Under this frame the signalling lane takes no part
in whether a data lane can hold a wrong alignment — `mf8-spec.md` §5 was
measured over every byte in every seat under every hook state — so the bit is
free to carry `DTR`, and does.

### 4.2 Three ways to use it

**Synchronous DCE.** V.11 / RS-422 levels, 26LS31 drivers and 26LS32 receivers:
`TXD`, `TXC`, `RXD`, `RXC`, `DTR`, `DSR`. The DTE changes `TXD` on the falling
edge of `TXC` and the card samples it on the rising edge; the card changes
`RXD` on the rising edge of `RXC` and the DTE samples it on the falling edge.
Setup and hold are half a frame, 7.8 µs, less cable, in both directions.

**PCM codec, a DS0.** The same six signals with `TX_OCT` and `RX_OCT` brought
out as frame syncs: a µ-law codec's serial interface — bit clock, frame sync,
data each way — is exactly this at 64 kHz and 8 kHz, so a G.711 codec hangs
off the card with no shift register on it; the superframe counter is the octet
counter. That gives a G.711 channel on the same trunk as CVSD ones, at the same
64 kbps, with the alignment `mf8-spec.md` §6 made mandatory.

**Async by oversampling.** An RS-232 population: a MAX232-class transceiver in
place of the RS-422 parts, no clocks presented. The async waveform is sampled
at 64 kHz on `TX_CLK` and reproduced at `RX_CLK`, so every edge lands within
one sample, 15.6 µs. At 9 600 bps that is 15 % of a bit, non-accumulating,
against a UART's mid-bit sample: usable. At 19 200 it is 30 %: marginal. **Rate
≤ 9 600 bps**, analysis not measurement. The DTE's own clock never meets the
trunk's, so there is no slip in the carrier's sense; the far DTE receives the
waveform re-timed to `RX_CLK`.

**Bonding.** Two cards in adjacent slots — adjacent is safe under this frame's
slot rule — with a strap "even" on one and "odd" on the other and a short link
between them carry one 128 kbps stream, even bits on the lower slot; three in
slots 1, 2, 3 carry 192 kbps. Slot identity is fixed by the framer, so the
order is fixed forever and there is no alignment state. The carrier does not
know it is happening.

### 4.3 The slot rule

Two data cards may not sit in C0 and C7 together (`mf8-spec.md` §5,
`mf8-unit.md` §4.2). **Key the data card's connector so those two end
slots cannot both take one**, or key to C0–C6, or to C1–C7: seven data
cards, not the pair eight apart on the wire. PCM octets are safe in
every seat and every pair. With a data card carrying the F word in C0
and voice in C7, the residual is §5's: acquired by chance about once in
300 attempts at one skew and released by the guard counter in a few
milliseconds. It is the price of eight C plus F and S opposite.

### 4.4 Parts

| block | parts |
|---|---|
| RS-422 | 26LS32 (`TXD`, `DTR`), 26LS31 (`RXD`, `TXC`, `RXC`, `DSR`, `TX_OCT`, `RX_OCT`) |
| Retiming | ½ 74HC74 per direction |
| `RXD` idle on `MUTE` | ¼ 74HC32 |
| A filter | ¼ 74HC14 |
| Bond strap and link | a 3-position strap, one header |
| Async population | MAX232 in place of the RS-422 parts |

**4 packages.** The cheapest card in the shelf.

### 4.5 Bring-up

1. **Loop `TXD` to `RXD` on the card** with the backplane clocks running and
   no trunk: proves the retiming and the two clocks.
2. **Card to card over the backplane**, no trunk.
3. **Over the trunk: all zeros, all ones, `0x7F`, random**, watching the lock
   indicator through a cold start at each — the in-service check that this
   slot holds no wrong alignment. All must lock at the true phase.
4. **Bonded pair**, then the DS0 mode against a codec.

---

## 5. Measured: signalling through the A path

Every card above puts hook state, ringing or `DTR` on one bit sampled once per
125 µs superframe, sent as one line bit, latched by the receiver's '259 —
cleared while the trunk is not locked — and filtered by the §14 RC (τ = 2 ms)
into a 74HC14 (0.55 and 0.35 of the swing taken as its rising and falling
thresholds). This measures that path at this frame's 8 kHz signalling rate; the
earlier figure, 78 of 78 pulses at 0.16 % ratio error, was at 32 kHz.

**Dial pulses**, ten breaks, loop open = A 0, line errors applied to the A
samples:

| dial | BER | pulses | break sent → received | make sent → received |
|---|---|---|---|---|
| 10 pps 60/40 | 0 | **10 / 10** | 60.0 → 59.5–59.6 ms | 40.0 → 40.4–40.5 ms |
| 10 pps 60/40 | 6e−2 | **10 / 10** | 60.0 → 59.1–60.0 ms | 40.0 → 40.0–40.5 ms |
| 10 pps 67/33 | 6e−2 | **10 / 10** | 67.0 → 66.0–66.9 ms | 33.0 → 33.3–33.5 ms |
| 20 pps 60/40 | 6e−2 | **10 / 10** | 30.0 → 29.1–29.5 ms | 20.0 → 20.1–20.5 ms |

Breaks arrive 0.5 ms short and makes 0.5 ms long, which is the RC's asymmetry
— **assert 1.5 ms, release 2.0 ms** — and nothing else; line errors to 6e−2 add
±0.4 ms of spread and lose no pulse. Every count was 10 of 10 at every error
rate to 6e−2.

**Steady state under errors**, 60 s each way: 0 spurious transitions off-hook
or on-hook to BER 1e−1; at 2e−1, 6 on-hook in 60 s. A release needs the RC to
fall from 1 to 0.35, which is 16 consecutive wrong samples; an assert needs 12.
At 1e−1 neither happens; at 2e−1 runs of mostly-wrong samples begin to reach
the assert threshold.

**A reframe mid-make.** The '259 clears while the framer re-hunts, so an A that
was 1 reads 0 for the outage. A dropout of 1, 2, 4, 8 or 12 samples — up to
1.5 ms, seven times the 0.2 ms a slip costs (`mf8-spec.md` §4.2) — is **not
registered**: a 0.25 ms dropout dips the RC to 0.88 and a 1.5 ms one to 0.47,
against a 0.35 release threshold.

**Ring cadence** 2 s on / 4 s off at BER 3e−2: on periods received 2.0005,
2.0005, 2.0004 s.

For the cards: an FXO card pulses the CO within 0.5 ms of what the phone sent,
at 10 or 20 pps; an FXS or line card rings its phone in the far end's cadence
to half a millisecond; a slip in the trunk is invisible to the loop; and `DSR`
follows `DTR` with 1.5–2 ms of lag. Scratch script, not a repository tool.

---

## 6. Not measured

- **Every circuit here.** The line interfaces are `mf8-spec.md` §9's, measured
  in simulation; the SLIC functions, the hybrid, the ring detector and the
  relays are data-sheet designs.
- **The hybrid against real loops.** 10–15 dB trans-hybrid loss is the target;
  what a compromise network achieves on the loops at hand is a bench figure.
- **The async rate limit.** 9 600 bps is analysis from the 15.6 µs edge
  quantization; a UART's real tolerance decides it.
- **The ring trip time**, the loop-detect threshold and the FXO ring detector's
  integrator against a real 20 Hz generator.
- **`MUTE` heard through a phone**: `mf8-spec.md` §15's open item, one card
  further along. §3.7 sharpens it: the FXS, FXO and E&M cards leave a11 open,
  so their decoders are handed the cleared '259's all-zeros through an outage
  rather than `1010`, and **nothing has been listened to**. The CVSD line card
  and the data card do read the pin.
- **§2.4 and §3.7 are assignments.** Every pin is read off this document's own
  description of the card against the socket of `common-cards.md` §1, which is
  itself an assignment. No board has been laid out, no connector chosen, and
  nothing has been probed at a socket.
- **A CO's dial-pulse receiver** against the 0.5 ms distortion measured
  here; `subscriber-line.md` §5 measured the phone-to-exchange leg at 6.1 ms
  short with the phone muted while dialling (0.1–7.5 ms without), and the two
  legs add. `register.md` §1.3 corrects the first leg on the line card.
