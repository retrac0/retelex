# Subscriber line — 64 kbps CVSD over differential Manchester, four-wire

One phone on two pairs. Each pair carries one direction of the raw 64 kbps CVSD
stream in differential Manchester, with no frame. Signalling is two held bit
patterns that the codec cannot produce, detected by an RC and a comparator at
each end. Digits go as in-band DTMF, or as dial pulses using the same on-hook
pattern. The phantom carries DC power only.

> **Status: proposed, measured in simulation.** The numbers here were measured
> on the receiver of `mf8-spec.md` §9.4 and the codec of §12.1, at the 64 kbps
> row of §9.7, by `subline.py` (`subline.log`), except §2's switching
> transients, which are still from a scratch script (§7). The register that
> reads the dial is `register.md`. Nothing has been on a bench.

---

## 1. The line

| | |
|---|---|
| Pairs | two, one per direction; the exchange transmits continuously |
| Rate | 64 kbps, differential Manchester, **128 kBaud** — the §9.7 64 kbps plug: filter 128 kHz, classifier 11.7 µs, dead time 3.1 µs |
| Receiver | §9.4, unchanged, at both ends |
| Reach | 2× the 256 kbps reference of `frame-rate.md` §1 by the same √f law — a ratio, kilometres not measured |
| Power | 48 V DC on the phantom between the two pairs (§1.1), through the centre-tap footprint §9.3 already specifies; no ring generator, ring relay or loop detector anywhere |

There is no frame because a CVSD stream needs none: the receiver recovers the
bit strobe from the line and the decoder runs on it (`phy.py`'s original
premise). Everything a frame would have carried — hook state, ringing — is the
stream itself.

### 1.1 DC phantom power

The 48 V goes in at the line-side centre tap of the downstream pair's
transformer and returns through the centre tap of the upstream pair's
(`channel-cards.md` §2.1). Each pair, both wires together, works as one conductor 
of the DC circuit:

```
 exchange                                            phone
 −48 V ─┬─ centre tap ═══ downstream pair ═══ centre tap ─┐
        │    (both wires carry the DC together)           │  the phone's
        │                                                 │  power supply
 return ┴─ centre tap ═══ upstream pair   ═══ centre tap ─┘
```

The signals are not affected by the DC bias for two reasons:

- **Each pair's signal is differential**, the voltage between its two wires.
  The DC sits equally on both, so it is common mode, and the receiver's
  comparator rejects it.
- **The transformers do not saturate.** The DC splits evenly between the two
  halves of each line-side winding and flows through them in opposite
  directions, so the ampere-turns cancel.

**Not within one pair.** Feeding the DC between the two wires of one pair, as
an analog loop's battery is fed, would make it differential. It would then sit
across the transformer's winding, which is nearly a short at DC. Separating
signal from power would take a split winding with a blocking capacitor, and
feed inductors, which is the analog line card's feed bridge. The phantom needs
none of it.

**Half the loop resistance.** Each leg of the phantom is two wires in
parallel, so the DC loop has the resistance of one conductor for the loop's
length. The same current fed around one pair would see two conductors in
series, twice as much.

---

## 2. Signalling 

This is based on two patterns the CVSD codec cannot make.

| direction | state | on the line |
|---|---|---|
| phone → exchange | off-hook | CVSD |
| | **on-hook, or a dial break** | **`1100` repeating** (the bit clock ÷ 4) |
| | phone dead or unpowered | nothing — reads as on-hook (§3) |
| exchange → phone | phone off-hook | the trunk's C bit |
| | phone on-hook, idle | `1010` — the codec's idle pattern, §12.3 |
| | **phone on-hook, ringing** | **all zeros**, in the ring cadence |

The two patterns are recognised by the same measurement: the RC-filtered
density of a one-bit function of the received data, against a comparator at
0.85 / 0.70. For the exchange the function is `Q[n] XOR Q[n−2]`, which `1100`
makes constantly 1; for the phone it is `Q` itself, which all-zeros makes
constantly 0. CVSD stays near the middle whatever it is fed — the encoder is a
delta modulator and cannot hold a level. Measured over 7 talkers × 30 s, speech
at +10 and +20 dB (clipped), silence, and 300 Hz–3.4 kHz tones to 3× full scale
(τ = 4 ms):

| the signal the detector filters | CVSD traffic, extremes | the pattern |
|---|---|---|
| ones density (phone's ring detector) | **0.41 – 0.59** | 0.00 |
| `Q ⊕ Q[n−2]` density (exchange's hook detector) | **0.00 – 0.53** | 1.00 |

Longest run of one value CVSD produced: 81 bits (an overdriven tone) — 1.3 ms,
against a 4 ms RC. Longest run of `Q ⊕ Q[n−2]` = 1, the `1100` signature:
**8 bits**. On a clean line a detector a few dozen bits long would do; the 4 ms
RC is there for the noise, not for the codec (`subline.py density`).

**Why `1100` and not all-ones.** Either is unmistakable; the difference is what
the far party hears in the ~5 ms before the detector reacts, and on every hook
flash. Switching mid-word from speech to a held level slams the CVSD integrator
to its rail: **+33.6 dB above the speech peak.** `1100` decodes as a 16 kHz
ripple the reconstruction filter removes: +2.0 dB transient, then −66.5 dB
below speech rms. That costs two flip-flops and an XOR at the exchange, and
nothing at the phone.

**Why ringing is all-zeros.** A dead or noisy pair must not ring the phone. The
receiver's data latch idles at 1, no-carrier forces 1, and noise decodes as a
mix: the ones density of a dead pair never fell below **0.64** in any condition
measured. Zeros cannot arrive by accident.

---

## 3. The detector

```
 §9.4 receiver ──Q, strobe, LONG, MID, carrier──┐
                                                │
 violation = LONG·MID at an accepted edge       │   (a half-cell with no partner)
          + gap > 1.25 cells                    │   (a missing boundary transition)
          → hold 16 cells (250 µs)              │
                                                ▼
 G = X  +  violation-hold  +  /carrier          X = Q ⊕ Q[n−2]   (exchange)
                                                X = Q            (phone)
 G ──[ RC, τ = 4 ms ]──[ comparator 0.85 / 0.70 ]──→  exchange: ON-HOOK when high
                                                       phone:    RING     when low
```

**The violation term is mandatory.** Without it a dead pair with noise at
sd 0.3 or more decodes as speech-like bits, the density sits at 0.4 and the
exchange reads *off-hook*: a cut cable would seize every line in it. Valid
differential Manchester never leaves a half-cell unpaired and never skips a
boundary; noise does both constantly, and each one forces G high for 250 µs.
The two conditions are one AND gate on signals the receiver already has, and a
second timer of the shape §9.6's carrier detect already is, set at 1.25 cells.

**Thresholds need a comparator, not a '14.** 0.85 / 0.70 of the logic swing
sit far from where a Schmitt gate's thresholds fall, and vary less. ¼ LM339
per detector.

### 3.1 Measured over the line

`subline.py hook`: 2 s per cell, one seed; Gaussian noise sd referred to the
signal peak, impulse noise as `phy.plant_noise`. *False events* is the number
of times the detector left the correct state. The receiver runs at `mf8-spec.md`
§9.4's dead time of 0.2 cell; the scratch runs this table first came from used
0.25, and every density moved by less than 0.06.

| exchange hook detector | density min – max | false events |
|---|---|---|
| on-hook `1100`, clean … sd 0.8 | 0.970 – 1.000 | 0 |
| on-hook `1100`, impulse 10 – 1000/s | 0.903 – 1.000 | 0 |
| off-hook, speech, clean … sd 0.8 | 0.000 – 0.518 | 0 |
| off-hook, speech, impulse 1000/s | 0.005 – 0.601 | 0 |
| off-hook, idle `1010`, every condition | 0.000 – 0.400 | 0 |
| **dead pair**, noise sd 0.01 – 1.0 | 0.757 – 1.000 | **0** |
| **dead pair**, impulse 100/s | 0.867 – 1.000 | **0** |
| dead pair, impulse 1000/s | 0.620 – 0.993 | 9 (2.2 % of the time off-hook) |

| phone ring detector | density min – max | false events |
|---|---|---|
| ringing (zeros), clean … sd 0.8 | 0.000 – 0.061 | 0 |
| ringing, impulse 100/s | 0.000 – 0.182 | 0 |
| ringing, impulse 1000/s | 0.002 – 0.280 | 0 |
| idle `1010` or speech, all conditions | 0.462 – 0.688 | 0 |
| **dead pair**, every condition | 0.633 – 1.000 | **0** |

Clean of false events to sd 0.8 — beyond the sd 0.7 at which the trunk's
framer loses lock (`mf8-spec.md` §7.2) — and to 1000 impulses/s everywhere
but one cell: a dead pair under 1000 impulses/s, which no link here survives
either.

---

## 4. Logic at each end

**Phone.** Hook switch and dial contact in series, as on an analog loop.

```
TX   = ON-HOOK or dial break  ?  1100 (bit clock ÷ 4)  :  CVSD encoder
encoder input = dial off normal ? silence : microphone    (§5, register.md §1.1)
ring = RING · ON-HOOK                                   → ringer
decoder input = RING ? 1010 : Q ;  audio output muted while ON-HOOK
```

**Exchange, per line.**

```
TX   = OFF-HOOK ? C from the trunk : ( trunk A asserted ? all zeros : 1010 )
trunk A out = OFF-HOOK
```

Ring cadence comes from the far end's A bit as it does with E&M. **Ring trip
is automatic**: the phone unarms its ringer the instant the hook closes, and
the exchange's detector releases within ~2 ms and switches the phone to the C
bit, with no ring-trip circuit and no relay. About 10 packages per line at the
exchange, four of them the §9.4 receiver; the phone is the same receiver, an
encoder and a codec.

---

## 5. Dialling

**Dial pulses** are the on-hook pattern, keyed by the dial contact. Digit 0
(10 breaks) at seven dial settings from 7 pps 56/44 to 20 pps 60/40, each
clean, at sd 0.8 and at 100 and 1000 impulses/s (`subline.py dial`):

| the makes carry | pulses seen | break as received, against sent |
|---|---|---|
| `1010`: the transmitter muted while the dial is off normal | **10 / 10** in all 28 cells | **6.1 ms short, every pulse**; −6.9 to −4.9 ms at 1000 impulses/s |
| speech: not muted, and someone talking | **10 / 10** in all 28 cells | 0.1 – 7.5 ms short |

Breaks arrive short by the detector's asymmetry. The RC climbs from the make's
density to 0.85 (7.6 ms from 0) and falls from 1.0 to 0.70 (1.4 ms), and the
thresholds cannot move to centre it, because talk-state safety holds them both
high (`register.md` §1.2). **Specify the mute:** it makes the shortening one
number, which a 6.16 ms monostable on `ON_HOOK`'s release removes to within
−0.7 to +1.3 ms. That matters wherever pulses are repeated onward, as on an
extended line to a CO (`register.md` §1.3). Where pulses are read into a
register, the shortening costs nothing. `register.md` §3 reads 3 200 random
digits over 7–12 and 20 pps, 56–72 % break, both kinds of make and every line
condition, with none wrong.

**DTMF** goes through the 64 kbps codec of §12.1 intact. All 16 digits, high
group +2 dB, 40 ms window after the syllabic filter settles, worst digit:

| per-tone level re nominal speech | −30 dB | −25 | −20 | −10 | 0 | +6 |
|---|---|---|---|---|---|---|
| SINAD | 15.8 dB | 21.7 | 24.0 | 27.2 | 29.6 | 23.5 |
| twist change | −0.7 dB | +0.2 | +0.2 | +0.1 | −0.1 | −0.1 |
| margin over the other tones in the group | 17.6 dB | 30.1 | 31.4 | 35.8 | 38.0 | 32.7 |

Usable from 25 dB below nominal speech level to 6 dB above it. A DTMF receiver
belongs at the exchange, where one can serve every line: `register.md` §7 puts
it in the register, writing the same store as the dial.

---

## 6. What was rejected

- **DC loop signalling on the phantom** — the old FXS card on the centre taps.
  It works, but it puts 90 Vrms ringing on the data transformers and in the
  phone, and needs a ring relay, ring trip and loop detector per line.
- **Switching the carrier off** to signal. Absence of signal *is* the dead-pair
  problem of §3, and needs the same violation check to be safe; and a phone
  without a downstream has no clock and cannot tell idle from cut.
- **Deliberate code violations** as a side channel. Impulse noise deletes
  transitions, which is exactly what a violation looks like.
- **Tones** need detectors and can be talked off; **bit stealing** needs the
  frame the line does not have.

---

## 7. Not measured

- **§2's switching transients** (+33.6 dB into all-ones, +2.0 dB and
  −66.5 dB into `1100`) are still from a scratch script. Everything else here
  is `subline.py`, and `subline.log` is the run.
- **Clocking of the upstream.** A phone loop-timed from the downstream gives a
  slip-free upstream and needs a DPLL or PLL in the phone (`line-codes.md`
  §2.2 C); a phone on its own crystal slips one CVSD bit every ~150 ms at
  100 ppm, which the codec should not hear. Neither is designed or measured,
  and the same question exists between the two directions of the trunk.
- **Glare.** A hook closure during a ring burst feeds the decoder a few ms of
  zeros before the exchange switches. §4's `1010` substitution while RING is
  detected covers it by reasoning only.
- **A real pulse receiver.** `register.md` measures its own register's windows
  in simulation. A CO's receiver against uncorrected pulses (53 % for a 60 %
  break, over an extended line) is not measured, and neither is the off-normal
  mute on a real phone.
- **Long runs and crosstalk.** 2 s per cell, one seed; one line alone.
- **Phantom imbalance.** A resistance difference between the two wires of a
  pair puts part of the feed current through the winding as a net DC. It has
  not been computed against the 33 mH transformer's saturation, and neither
  has the feed's voltage drop over a real loop.
