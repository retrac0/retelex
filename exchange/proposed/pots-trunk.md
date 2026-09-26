# Dual-tone trunk over a two-wire pair

One tie trunk over a dry two-wire pair: speech in the voice band through a codec
and a hybrid, and A in band as a dual tone each way, notched out of the speech
path. It is a single-channel trunk card for a channel socket, the voice-band
case of `network.md` §2. It is not an outside line: no battery feed, no ringing,
no loop closure toward a CO; loop start stays on the FXO card (`features.md` §4).

> **Proposed.** No circuit drawn, nothing listened to on a pair.
> Measured in: `sim/pots_trunk.py` (`pots_trunk.log`), a signal-level model (§8).
> **As written the card drops every call held past 200 ms (§9).**

## 1. What it is

The port's `C_RX` is decoded, joined by the idle tones while `A_RX` is low, and
put on the pair through a hybrid. What comes back is notched and encoded as
`C_TX`, and its tones are detected as `A_TX`. The card holds no digits and
decides nothing (`trunks.md` §1). Against the other carriers it has **two
conductors**, where MF8 has a pair each way and the baseband card six
(`trunks.md` §2); it carries **no data**, being a voice-band tandem of about
2 dB; and its sign of a live link is **the idle tones**.

## 2. Frequency duplex and jumpers

Two dual-tone pairs share the line. A board jumper makes a card **WEST** (sends
W, receives E) or **EAST** (sends E, receives W); the same PCB goes at both ends.

### 2.1 The tones

| pair | f₁ | f₂ | why |
|---|---|---|---|
| **W** | **2400 Hz** | **2600 Hz** | AND detection; clear of the tone plan's 425 and 600 Hz (`common/tones.md`) and of the DTMF grid, so a keypad on the speech path cannot false-claim |
| **E** | **2200 Hz** | **2800 Hz** | the same, and far enough from W for twin-T or ceramic notches to split them |

Both send tones go on together at about **−10 dBm0** re nominal speech: loud
enough for the far detector, quiet enough that a failed notch whistles rather
than howls. An optional footprint takes an MT8870 and two DTMF digit pairs
instead; the default stays the one a keypad cannot talk onto.

### 2.2 A polarity

| near state | tones toward the far end | far `A_TX` (M at its port) |
|---|---|---|
| idle, on-hook, **a pulse break** | **both** of the send pair **present** | **0** |
| seized, off-hook, a make, **a claim** | send pair **absent** | **1** |

`A_RX` high gates the oscillators off, so each dial break restores the tones and
a claim is steady silence toward the origin. Tone present means idle so that the
idle tone doubles as carrier detect (§5, but see §9). **AND, never OR**: talk-off
must hit both frequencies at once, and one tone alone is not a valid pair.

## 3. The audio path

The codec is `mf8/mf8-spec.md` §12.1's half-LM13700 pair; the hybrid, trims and
300–3400 Hz filters are the FXS card's (`common/channel-cards.md` §3.1).

| block | specification |
|---|---|
| hybrid | transformer, 600 Ω, compromise balance: **10–15 dB** trans-hybrid loss on a real pair |
| tone inject | **after** speech TX, into the hybrid's four-wire TX leg, so the near talker is not notched |
| notches | **both** W and E on the RX speech leg, before the encoder filter, **≥ 40 dB** each: the near send pair leaks through the hybrid only 10–15 dB down |
| line | dry: no −48 V, no ring relay, no loop detector. Gas tube, PTC and TVS ahead of the hybrid |

**Echo binds.** With a hybrid here, `network.md` §2's round-trip bound applies
as soon as either subscriber is analog: **the hop is local or short leased
only**. A data card must not be pointed at this trunk.

## 4. Detector timing

A break of 8 ms or more must survive, a make must not grow past 128 ms nor a
break past 256 ms, and A's wander counts against the guard (`network.md` §2, §6).

| | target | why |
|---|---|---|
| tone present → A low (idle) | **≤ 16 ms** | the ports' own M detector rises in 16 ms (`fabric.md` §5) |
| tone absent → A high (seize) | **≤ 8 ms** | seize and claim should not lag the baseband card by much |
| break shortening | **≤ 2 ms** a hop | not met: §9 |
| valid receive pair | both tones above threshold for the idle time | AND, not OR |
| link down | no valid receive pair for **100–200 ms** | clear of a long dial break (but see §9) |

Two narrow filters (or a DTMF receiver) into an AND, then an RC and ¼ '14 into
`A_TX` (`mf8/mf8-spec.md` §14's habit): assignments, not measurements. The
filters' fixed delay costs the guard nothing (`network.md` §6).

## 5. Link down

**No valid receive pair for 100–200 ms is link down**: the word's open drain is
held off, so the port reads NONE and leaves the hunt, and `A_TX` is forced low,
so M falls and the port releases (`network.md` §2). A cut pair, a missing far
card and WEST facing WEST (both ends then read link down) all time out. `MUTE`
is unused; the card's detector owns the word enable, as the baseband card's
does (`trunks.md` §2).

## 6. The card's pins

The channel socket (`common/common-cards.md` §1), with pins not listed unused;
at the rear, **tip and ring only** on the FXS/FXO rear connector, dry behind it.

| pin | | this card |
|---|---|---|
| a1 `TX_CLK` | in | the encoder's clock; shifts the word's '165 |
| a3 `TX_OCT` | in | loads the '165 in the first half of frame 7 (`TX_OCT · TX_CLK`, `card-word.md` §3) |
| a5 `C_TX`, a6 `A_TX` | **out** | encoder, in T; the detector (§4), forced low on link down |
| a7 `RX_CLK`, a9 `C_RX` | in | the decoder, in R |
| a10 `A_RX` | in | a short RC and Schmitt to the tone gate: high silences the send pair |
| a12 card word | **out**, o.d. | primary `11 01 0 g d d`, class trunk (`card-word.md` §2); held off at power-up (`trunks.md` §1) and by §5 |
| a13 `/ANS` | **out** | tied low |
| c1, c3 `+5 V`; c5, c7 `±12 V` | in | logic; codec, oscillators, detectors, hybrid amps (§9) |

## 7. Parts

The FXS card's codec, hybrid, trims and TL07x filters; two gated Wien or twin-T
oscillators, or a DTMF generator; four twin-T notches or two duals; two detector
filters and a gate, or an MT8870; ¼ '14; ½ '123 for link down; one '165 and a
2N7002. No total until a schematic: more than the baseband card's ≈ 2¼
(`trunks.md` §2), about an FXO card without its ring detector.

## 8. Measured (`sim/pots_trunk.py`)

Dual-tone W/E, −12 dB hybrid leak, Q = 25 zero-phase notches (the card's are
causal and will disperse speech), a Goertzel AND with twist ≤ 6 dB standing in
for a twin-T and an LM567, a 16/8 ms Schmitt, Gaussian noise.

| | result |
|---|---|
| idle against noise | A stays idle to **0 dB SNR**; 3 % false seize at −3 dB, 30 % at −10 dB |
| dial pulses | digit 5 (60/40 ms) keeps all five breaks at ≥ 50 ms through 0 dB SNR: **5–10 ms shortening** |
| link down | unequipped **160 ms** after a cut made from idle |
| notches and speech | ≫ 40 dB at each tone (ideal IIR); whistle residue −95 dB, and without notches segSNR falls to 8 dB. With them, channel noise binds (17 dB at SNR 20) |
| talk-off | flat in-band synthetic speech false-idles 11 % of the time, worst run 50 ms; a 1 kHz tone, 0 %. A real talker is owed |

## 9. Open

1. **Link down fires on every call.** §2.2 sends no tones while seized,
   off-hook, making or claiming; §5 calls no receive pair for 100–200 ms link
   down. So every call held past 200 ms reads as a cut pair and releases:
   before the first dial break, every answered call, every claim. §8's 160 ms
   was measured from idle. Options named: qualify link down by the near end's
   state, reverse the polarity, or a separate "alive" signal (a pilot outside
   both pairs). None is worked out; until one is, the card holds no call.
2. **Break shortening.** The ≤ 2 ms target conflicts with the table's own
   asymmetry (A low after ≤ 16 ms, high after ≤ 8 ms, about 8 ms off every
   break) and with the sim's 5–10 ms. At that rate a path of POTS hops spends
   the break `network.md` §2 lets a carrier shorten, down to the register's
   8 ms, in a few hops. Equal assert and release times, or
   a limit on POTS hops in a path, would answer it; neither is chosen.
3. **±12 V.** The card needs ±12 V on c5 and c7 (`common/common-cards.md`
   §1.3); the block stack leaves both unconnected on J4 and brings rails to a
   card by a separate harness (`block-stack.md` §5). How one card takes its
   rails both ways is `common/common-cards.md` §7's open question.
4. **Owed on a bench**: talk-off with real speech; pulses through two cards and
   a real hybrid; notches against a compromise balance; levels; a schematic.
