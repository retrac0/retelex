# The subscriber adapter — a stock telephone on the digital line

This covers where a dial telephone's conversion to its 64 kb/s port can sit, the
adapter that puts it at the far end of the CVSD line of `subscriber-line.md`,
and the tree's one phantom power budget.

> **Proposed.** Every block is specified elsewhere and cited; the arrangement
> and the power budget are new, and the budget is arithmetic from data sheets.

## 1. Three places for one conversion

| | conversion at | outside plant | exchange card |
|---|---|---|---|
| **A** | the exchange | one analog pair | FXS card (`channel-cards.md` §3) |
| **B** | the subscriber | two digital pairs | CVSD line card (`channel-cards.md` §2), and this adapter |
| **C** | a shared site | one MF8 link, then analog loops | a trunk card, each channel a line (`exchange/proposed/terminal.md`) |

The port never learns which: its word says plain line (`card-word.md` §2) and
`/ANS` is open (`fabric.md` §5) in all three, so **the choice is per line and
reversible**. **A is the default**: one card, and it reaches further — a 20 mA
loop on 24 AWG near 5 km, the 128 kBaud line near 3.4 km by ratio
(`subscriber-line.md` §1). **B** suits a loop that hurts the codec (the encoder
sits by the telephone, so every subscriber arrives at nominal level, where under
A a distant one is 6–8 dB low) or an exchange that should hold no ringing
voltage; the same pairs and card also serve SU-1 or SDU-1. **C** suits two or
more subscribers at one site.

## 2. The adapter

`subscriber-line.md` §4's phone end with the hook switch replaced by a loop
detector, on the analog front of `channel-cards.md` §3.2. The line side,
receiver and encoder are `mf8/mf8-spec.md` §9.2–§9.4 at the §9.7 64 kbps plug;
the ring detector is `subscriber-line.md` §3's phone sense; the codec engine is
`cvsd-codec.md` §4; the filters and 600 Ω hybrid are `channel-cards.md` §3.1;
the feed, loop detector, ring relay and ring trip are §3.2's, with the feed
limited to 20 mA for the power budget (§4). The mute is ¼ '157 and ½ '123 (§5).
**About 18 packages, three transformers, a relay and a supply** — against the
FXS card's 11 — one per subscriber. It is loop-timed as the phone is
(`subscriber-line.md` §1; the circuit, §7).

It sends `1100` while `LOOP_OPEN` (the loop detector, or ring trip not yet
released) or `MUTED`, else the encoder; feeds the decoder `1010` while `RING`;
and drives the relay with `RING · LOOP_OPEN`. The cadence arrives as bursts of
zeros, because the exchange chops the port's E with it (`fabric.md` §5).

## 3. Ringing is moved, not eliminated

A bell needs what the native set does without — a 20 Hz inverter, a relay that
applies it and drops the feed, a DC ring trip releasing within 200 ms — now one
per subscriber; B saves only ringing voltage in the exchange. Ring trip stays
fast: the relay drops, `TX` leaves `1100`, the exchange releases within ~2 ms.

## 4. Power

The line card feeds ≤ 40 mA at 48 V (`channel-cards.md` §2.1); on 24 AWG,
84 Ω/km a conductor, the phantom loop is 84 Ω/km (`subscriber-line.md` §1.1).

| | 3 km | 5 km |
|---|---|---|
| phantom loop; drop at 40 mA | 252 Ω; 10.1 V | 420 Ω; 16.8 V |
| at the adapter; after a switcher at 80 % | 37.9 V, 1.52 W; **1.2 W** | 31.2 V, 1.25 W; **1.0 W** |

The continuous load is ~0.95 W: HC logic ~100 mW, the 75176 into 120 Ω ~250 mW,
the analog parts ~300 mW, the 20 mA feed 250–400 mW. **It closes at 3 km and is
marginal at 5.** The feed drops for a ring burst, and a 4700 µF, 50 V reservoir
(½C(38² − 30²) = 1 J) carries the bell's ~1 VA through 2 s on in a 2 s / 4 s
cadence. The supply is a jumper: **phantom only** (REN ≤ 1, reservoir and
inverter fitted, works through a power cut) or **local mains** with the phantom
keeping the digital half alive (fewer parts; the telephone dies in a power cut).

## 5. Dial pulses, and the mute

The loop detector's asymmetry adds to the 6.1 ms of `subscriber-line.md` §5, so
it is fast and symmetric: an opto into a comparator. **The adapter guarantees
the dial mute**: a retriggerable monostable on the loop detector holds `MUTED`
~100 ms after any break, so the makes carry `1010` whatever telephone is fitted.

## 6. Open

- **A real bell**: one REN's VA at 20 Hz, and whether 50–60 Vrms rings it, which
  would halve the inverter and reservoir and decide the phantom-only population.
- **Not measured**: the budget (the 75176's drive and the engine's analog
  current), the loop detector's asymmetry (`subline.py dial`), B's level
  advantage in SINAD and DTMF margin (`cvsd.py`).
