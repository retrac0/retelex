# The subscriber adapter — a stock telephone on the digital line

A dial telephone is two wires and a bell. Somewhere between it and the
exchange's port, which is 64 kbps of CVSD and one signalling bit each way
(`protocol.md` §1), something has to do the conversion: a hybrid, a codec,
a feed, a ringer and a loop detector. **This document is about where that
something sits**, and specifies the one placement the design does not already
have — an adapter at the subscriber's end of the digital line of
`subscriber-line.md`.

> **Status: proposed.** Nothing here is newly measured. The receiver, the
> encoder, the detectors, the codec engine, the hybrid and the FXS front end are
> all parts specified elsewhere and cited where they are used; what is new is
> their arrangement in one box and the power budget of §4, which is arithmetic
> from data-sheet figures and has not been on a bench.

---

## 1. Three places for one conversion

The exchange's port is an MF8 slot and never learns what is behind it. Its word
says *plain line* and `/ANS` is open (`extensions.md` §2.2) in all three
cases:

| | conversion at | outside plant | in the exchange slot | status |
|---|---|---|---|---|
| **A** | the exchange | one analog pair | analog FXS card, `channel-cards.md` §3 | specified |
| **B** | the subscriber | two digital pairs | CVSD subscriber line card, `channel-cards.md` §2 | specified; **the adapter is §2 below** |
| **C** | a shared site | one MF8 link, then analog loops | trunk card, class *line* a channel | `terminal.md` |

**The choice is per line and reversible.** Pull the FXS card, push a CVSD line
card, run the second pair, hang an adapter: the marker, the fabric and the
numbering never find out.

### 1.1 When each

**A is the default.** It is one card already specified — ≈ 11 packages, a
hybrid transformer, a ring relay, the shelf's `RING` bus, a feed bridge and ring
trip (`channel-cards.md` §3.4) — and it reaches further than B does. A loop at
20 mA on 24 AWG is loss-limited at order 5 km; the 128 kBaud digital line is
2× the 256 kbps reference of `frame-rate.md` §1, order 3.4 km. **B is not the
reach option**, and it costs two pairs to the building instead of one.

**B is for the loop that hurts the codec, or the exchange that should hold no
high voltage.** Its real win is that the encoder is 100 m from the telephone
whatever the subscriber's distance, so the engine sees its nominal 0.15 rms of
full scale for everyone and DTMF keeps the margins of `subscriber-line.md` §5.
Under A a distant subscriber arrives 6–8 dB low into an engine whose `Iabc` trim
was set for a nominal loop. B also keeps ringing voltage and per-line analog out
of the exchange shelf (`channel-cards.md` §3.6), and leaves the same two pairs and
the same exchange card able to serve a native CVSD phone or a data device by
swapping the far-end box.

**C the moment there are two or more subscribers at one site.** It shares the
line plant and still gives each line a codec of its own.

---

## 2. The adapter

The phone end of `subscriber-line.md` §4 with the hook switch replaced by a loop
detector, on the analog front of `channel-cards.md` §3.4.

```
            ┌─ §9.4 receiver ─Q, strobe─┬─ ring detector: Q density, 4 ms RC, 0.85/0.70 ─┐
 2 pairs ═══┤                           └─ decoder ◀─ RING ? 1010 : Q ─▶ recon 3400 ─┐   │
  48 V      │                                                                        ├─ hybrid ═ loop ═ phone
 phantom ═══┴─ §9.2 encoder ◀─ LOOP_OPEN + MUTED ? 1100 : encoder ◀─ 300–3400 Hz ─────┘   │
            │                                                                             │
            └─ switcher ─┬─ feed bridge, 20 mA ──────────────────────────────────────────┤
                         └─ 20 Hz inverter ─ ring relay ◀── RING ───────────────────────┘
                                             ring trip ──▶ LOOP
```

| block | from | parts |
|---|---|---|
| Line side, both pairs | `mf8-spec.md` §9.3 | 75176, two 1:1 ≥ 33 mH transformers with centre taps, gas tubes, PTC, TVS |
| Upstream receiver | §9.4 at the 64 kbps plug (§9.7) | 74HC86, '221, '123, '74 |
| Ring detector | `subscriber-line.md` §3, `X = Q` | ¼ '74, ¼ '32, ¼ LM339, 4 ms RC |
| Downstream encoder | §9.2 | ½ '74, ¼ '00 |
| Codec engine, both halves | §12.1 verbatim | 3 × '74, '86, '08, LM13700, TL072, LM311 |
| Filters, trims, hybrid | `channel-cards.md` §3.3 | TL074, TL072, 600 Ω transformer, compromise balance |
| Feed, loop detect | §3.4 | feed bridge current-limited to 20 mA, sense resistor, opto into ¼ LM339 |
| Ring relay, ring trip | §3.4, **and §3 below** | relay, DC sense, 200 ms |
| Rule and mute | §5 below | ¼ '157, ½ '123 |
| Supply | §4 below | switcher, 20 Hz inverter, reservoir |

**≈ 18 packages, three transformers, a relay and a supply** — against the ≈ 11
of the FXS card it displaces and the ≈ 10 of the CVSD line card at the exchange.
The adapter is the most expensive box in the access network, and there is one
per subscriber.

### 2.1 The rule

```
TX        =  LOOP_OPEN + MUTED  ?  1100  :  CVSD encoder        (§5)
decoder   =  RING ? 1010 : Q                                    as the phone's, §4 of subscriber-line.md
ring      =  RING · LOOP_OPEN                                   → the relay
LOOP_OPEN =  loop detector, or ring trip has not yet released
```

The cadence needs no generator: it arrives as bursts of zeros on the line,
because the exchange chops `A_RX` with it (`fabric.md` §3.5), and the relay
follows what the detector reads.

---

## 3. Ringing is what the digital line stops saving

`subscriber-line.md` §4's best claim — automatic ring trip, no ring-trip
circuit, no relay — **holds only for a native digital phone**, whose ringer is a
gate on a detector. A stock telephone has a real bell on a real loop, so the
adapter needs all three of the things the digital line was designed to avoid:
~90 Vrms at 20 Hz generated locally, a relay to apply it and to disconnect the
feed while it is applied, and a DC-sensing ring trip that drops the relay within
200 ms of the subscriber answering.

**They are not eliminated by going digital; they are moved to the subscriber and
multiplied by one per line.** What is avoided is the shelf's `RING` bus and
90 Vrms anywhere in the exchange — which is worth something, but it is a
different claim from the one §4 makes.

Ring trip stays fast end to end: the relay drops locally, `TX` leaves `1100`,
and the exchange's detector releases within ~2 ms, as it does for the digital
phone.

---

## 4. Power

The phantom gives ≤ 40 mA at 48 V (`subscriber-line.md` §1): **1.92 W at the
exchange**. Each leg of the phantom is two wires in parallel, so 24 AWG at
84 Ω/km a conductor makes an 84 Ω/km phantom loop.

| | 3 km | 5 km |
|---|---|---|
| phantom loop | 252 Ω | 420 Ω |
| drop at 40 mA | 10.1 V | 16.8 V |
| at the adapter | 37.9 V, 1.52 W | 31.2 V, 1.25 W |
| after a switcher at 80 % | **1.2 W** | **1.0 W** |

| what it goes on | |
|---|---|
| receiver, encoder, detectors, rule — ~8 HC packages at 128 kHz | ~100 mW |
| 75176 driving 120 Ω, continuously, ~4 V differential | ~250 mW |
| LM13700, TL074, TL072, LM311, LM339 | ~300 mW |
| feed, 20 mA to the telephone over a short house loop | ~250–400 mW |
| **continuous** | **~0.95 W** |

**It closes at 3 km and is marginal at 5.** Ringing is the difficulty: the bell
is mostly reactive, so the inverter must supply ~1 VA peak whatever the real
power is. The feed disconnects for the burst, which returns ~300 mW, and a
reservoir on the raw input carries the rest — ½C(38² − 30²) = 1 J wants 3.7 mF,
so 4700 µF at 50 V for a 2 s burst on a 2 s / 4 s cadence.

**Make the supply a strap.** Two populations:

| | |
|---|---|
| **phantom only** | REN ≤ 1, the reservoir and the inverter fitted. The telephone works through a power cut, as the classical loop does. Worth measuring first whether a real bell rings at 50–60 Vrms, which halves the VA and most of the supply with it |
| **local mains, phantom as keep-alive** | the phantom runs the digital half alone, so the line stays up and the exchange reads on-hook through a power cut: a caller hears ringing and no answer rather than cannot-complete. Far fewer parts, and **the telephone dies in a power cut** — a real regression against A |

---

## 5. Dial pulses, and the mute the adapter should guarantee

A break goes loop → the adapter's loop detector → `1100` on the line → the
exchange's hook detector, so **the adapter's own asymmetry adds directly to the
6.1 ms of `subscriber-line.md` §5.** Make the loop detector fast and symmetric:
an opto into a comparator, not a long RC.

§5 asks for the transmitter to be muted while the dial is off normal, so that
the makes carry the codec's `1010` and the shortening is one number, which a
6.16 ms monostable on `ON_HOOK`'s release removes to within −0.7 to +1.3 ms.
Most dials short the transmitter on the off-normal contact and give this for
free. Not all do. **The adapter should guarantee it**: a retriggerable
monostable on the loop detector holds `MUTED` for ~100 ms after any break, so
the makes carry `1010` whatever telephone is plugged in.

Where pulses are read into a register the shortening costs nothing —
`register.md` §3 reads 3 200 digits with none wrong — and the correction matters
only where they are repeated onward, as to a CO.

DTMF is unaffected: one codec either way, and `subscriber-line.md` §5 measures
it usable from 25 dB below nominal speech to 6 dB above. It does need the feed
to hold 20 mA, which a pad will not work below.

---

## 6. Not measured

- **The ring burst against a real bell.** The VA of one REN at 20 Hz, and
  whether 50–60 Vrms rings it. This decides §4's inverter and reservoir, and
  therefore whether the phantom-only population is worth building.
- **The whole power budget**, which is arithmetic from data-sheet figures. The
  75176's continuous drive into a transformer-coupled line and the engine's
  analog current are the two numbers to put a meter on.
- **The loop detector's asymmetry**, added to the 6.1 ms `subline.py` already
  measures. `subline.py dial` can carry it as one more delay.
- **The level argument for B**, which is the main reason to build it: the codec
  fed 6–8 dB low, in SINAD and in DTMF margin. `cvsd.py` can sweep it, and
  nothing here has.
- **Reach**, in kilometres, at 128 kBaud — a ratio in `frame-rate.md` §1, and a
  counter on a real pair everywhere else.
- **Clocking.** The adapter inherits `subscriber-line.md` §7's open question:
  loop-timed from the downstream, or its own crystal and one slipped bit every
  ~150 ms at 100 ppm.
