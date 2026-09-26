# Subscriber line — 64 kbps CVSD over differential Manchester, four wires

One phone on two pairs, one direction each: the raw 64 kbps CVSD stream in
differential Manchester, with no frame. Signalling is two held bit patterns the
codec cannot make, read by an RC and a comparator at each end. Digits go as DTMF
or as dial pulses of the on-hook pattern. The phantom carries DC power only.

> **Built:** the exchange end, `newimpl/rtl/cvsd_line_card.v` on `dm_rx.v`; a phone model, `newimpl/tb/subscriber.v`; bench `tb_line`.
> **Proposed:** the phone (`su-1.md`, `subscriber-adapter.md`).
> **Measured in:** `sim/subline.py` → `sim/subline.log`: `mf8-spec.md` §9.4's receiver and §12.1's codec at §9.7's
> 64 kbps row. §2's switching transients are from a scratch script.

## 1. The line

| | |
|---|---|
| Pairs | two, one per direction; the exchange transmits continuously |
| Rate | 64 kbps, differential Manchester, **128 kBaud**: `mf8-spec.md` §9.7's 64 kbps plug |
| Receiver, front end | §9.4 at both ends; transformers, driver and protection §9.3 |
| Reach | 2× the 256 kbps reference of `frame-rate.md` §1 by the √f law: a ratio, not kilometres |
| Power | 48 V DC on the phantom between the two pairs (§1.1); no ring generator, ring relay or loop detector anywhere |
| Phone's clock | **loop-timed**: the upstream runs at the downstream's bit rate, so it never slips against the line card's synchronizer and RAW64 data (`sdu-1.md` §3.2) crosses bit-exact. No free-running phone clock. The circuit is open (§7) |

### 1.1 DC phantom power

−48 V goes into the line-side centre tap of the downstream pair's transformer
and returns through the upstream pair's (`channel-cards.md` §2.1): each pair,
both wires together, is one conductor. The DC is common mode, which the
comparator ignores; it splits between the halves of each winding in opposite
directions, so the ampere-turns cancel; and each leg is two wires in parallel.
Fed across one pair, as an analog loop is, it would need a feed bridge.

## 2. Signalling

| direction | state | on the line |
|---|---|---|
| phone → exchange | off-hook | CVSD |
| | **on-hook, or a dial break** | **`1100` repeating** (the bit clock ÷ 4) |
| | phone dead or unpowered | nothing: reads as on-hook (§3) |
| exchange → phone | phone off-hook | the channel's C bit |
| | phone on-hook, idle | `1010`, the codec's idle pattern |
| | **phone on-hook, ringing** | **all zeros**, in the ring cadence |

Both patterns are read by one measurement, the RC-filtered density of a one-bit
function of the received data: `Q ⊕ Q[n−2]` at the exchange, which `1100` holds
at 1, and `Q` at the phone, which all zeros holds at 0. A delta modulator cannot
hold a level, so CVSD stays near the middle whatever it is fed. Over 7 talkers
× 30 s, speech at +10 and +20 dB (clipped), silence, and 300 Hz–3.4 kHz tones to
3× full scale, τ = 4 ms (`subline.py density`):

| the function filtered | CVSD traffic, extremes | the pattern |
|---|---|---|
| `Q` (phone) | **0.41 – 0.59** | 0.00 |
| `Q ⊕ Q[n−2]` (exchange) | **0.00 – 0.53** | 1.00 |

CVSD's longest run of one value was 81 bits (1.3 ms, an overdriven tone), and
its longest run of `Q ⊕ Q[n−2]` = 1 was 8 bits: the 4 ms RC is for the noise.

**Why `1100`, not all ones.** A held level slams the far CVSD integrator to its
rail in the ~5 ms before the detector reacts, and on every hook flash:
**+33.6 dB above the speech peak**. `1100` decodes as a 16 kHz ripple the
reconstruction filter removes: +2.0 dB transient, then −66.5 dB below speech
rms. It costs two flip-flops and an XOR at the exchange, nothing at the phone.

**Why ringing is all zeros.** A dead or noisy pair must not ring the phone. The
latch idles at 1, no carrier forces 1, and a dead pair's ones density never fell
below **0.64** in any condition measured.

## 3. The detector

```
 §9.4 receiver ── Q, strobe, LONG, MID, carrier
 violation =  LONG · MID at an accepted edge     a half-cell with no partner
           +  gap > 1.25 cells (19.5 µs)         a boundary that never came
           →  held 16 cells (250 µs)             a second retriggerable timer
 G = X + violation-held + /carrier      X = Q ⊕ Q[n−2] (exchange),  X = Q (phone)
 G ──[ RC, τ = 4 ms ]──▶ d
     exchange:  ON-HOOK when d rises above 0.85; off-hook when it falls below 0.70
     phone:     RING when d falls below 0.15; released when it rises above 0.30
```

**One comparator at 0.85 / 0.70 of the distance to the held pattern**: on G at
the exchange, on /G at the phone (`subline.py`; the bench phone,
`newimpl/tb/subscriber.v`, leaves out the violation term). No
carrier and a violation force G to 1 at both ends: on-hook at the exchange, not
ringing at the phone. A comparator, not a '14: 0.85 and 0.70 of the swing sit far
from any Schmitt threshold.

**The violation term is mandatory.** Without it a dead pair with noise at sd 0.3
or more decodes as speech-like bits, the density sits near 0.4 and the exchange
reads *off-hook*: a cut cable would seize every line in it. Valid differential
Manchester never leaves a half-cell unpaired or skips a boundary; noise does
both. The gap timer and the hold are two timers, and the gap must lie strictly
between 1.0 and 1.5 cells. Parts: `channel-cards.md` §2.2.

### 3.1 Measured over the line

`subline.py hook`: 2 s a cell, one seed; Gaussian noise sd referred to the signal
peak, impulses as `phy.plant_noise`; dead time 0.2 cell. *False events* counts
departures from the correct state.

| detector, line state | conditions | density | false events |
|---|---|---|---|
| exchange, on-hook `1100` | clean to sd 0.8; impulses 10–1000/s | 0.903 – 1.000 | 0 |
| exchange, off-hook speech | clean to sd 0.8; impulses 1000/s | 0.000 – 0.601 | 0 |
| exchange, off-hook idle `1010` | every condition | 0.000 – 0.400 | 0 |
| exchange, **dead pair** | noise sd 0.01–1.0; impulses 100/s | 0.757 – 1.000 | **0** |
| exchange, dead pair | impulses 1000/s | 0.620 – 0.993 | 9 (2.2 % off-hook) |
| phone, ringing (zeros) | clean to sd 0.8; impulses to 1000/s | 0.000 – 0.280 | 0 |
| phone, idle `1010` or speech | every condition | 0.462 – 0.688 | 0 |
| phone, **dead pair** | every condition | 0.633 – 1.000 | **0** |

Clean to sd 0.8, beyond the sd 0.7 at which the trunk's framer loses lock
(`mf8-spec.md` §7.2), and to 1000 impulses/s except a dead pair under 1000
impulses/s, which no link here survives either.

## 4. Logic at each end

```
phone:     TX            = ON-HOOK or dial break ? 1100 : CVSD encoder
           encoder input = dial off normal ? silence : microphone      (§5)
           ringer        = RING · ON-HOOK
           decoder input = RING ? 1010 : Q ;  audio muted while ON-HOOK
exchange:  TX            = ON-HOOK ? ( A_RX ? all zeros : 1010 ) : C from the channel
           A_TX          = OFF-HOOK
```

The phone's hook switch and dial contact are in series. The exchange end is
`channel-cards.md` §2.3, where an MF8 shelf's `MUTE` joins ON-HOOK. Ring cadence
is the far end's A bit. **Ring trip is automatic**: the phone unarms its ringer
when the hook closes, and the exchange's detector releases within ~2 ms.

## 5. Dialling

**Dial pulses** are the on-hook pattern keyed by the dial contact. Digit 0 at
seven dial settings from 7 pps 56/44 to 20 pps 60/40, each clean, at sd 0.8, and
at 100 and 1000 impulses/s (`subline.py dial`):

| the makes carry | pulses seen | break received, against sent |
|---|---|---|
| `1010`: the transmitter muted while the dial is off normal | **10 / 10** in all 28 cells | **6.1 ms short, every pulse**; −6.9 to −4.9 ms at 1000 impulses/s |
| speech: not muted, someone talking | **10 / 10** in all 28 cells | 0.1 – 7.5 ms short |

Breaks arrive short by the detector's asymmetry: the RC climbs to 0.85 in
7.6 ms from 0 and falls from 1.0 to 0.70 in 1.4 ms, and talk-state safety holds
both thresholds high (`analysis/dialling.md` §1.2). **Specify the mute**: it
makes the shortening one number, which a 6.16 ms monostable on `ON_HOOK`'s
release removes to within −0.7 to +1.3 ms. A register does not need it: 3 200
random digits over 7–12 and 20 pps, 56–72 % break, both makes and every line
condition, read with none wrong (`analysis/dialling.md` §3). Pulses repeated
onward do: an extended line to a CO, and a caller's A relayed across a network,
which is not measured (`channel-cards.md` §6).

**DTMF** passes the 64 kbps codec intact. All 16 digits, high group +2 dB, a
40 ms window after the syllabic filter settles, worst digit: SINAD 15.8, 21.7,
24.0, 27.2, 29.6 and 23.5 dB at −30, −25, −20, −10, 0 and +6 dB per tone re
nominal speech; twist moves by at most 0.7 dB; margin over the group's other
tones at least 17.6 dB. Usable from 25 dB below nominal speech to 6 dB above,
so DTMF reaches a CO over an extended line; the exchange itself reads only
pulses (`register.md` §1).

## 6. What was rejected

**DC loop signalling on the phantom** puts the ring bus's ~80 Vrms
(`mf8-psu.md` §3.2) on the data transformers and needs a ring relay, ring trip
and loop detector a line.
**Switching the carrier off** is §3's dead-pair problem, and a phone with no
downstream cannot tell idle from cut. **Code violations** as a side channel are
what impulse noise makes. **Tones** can be talked off; **bit stealing** needs a
frame.

## 7. Open

- **How the phone loop-times** (§1): no circuit is drawn. `line-codes.md`
  §2.2 C's DPLL needs a local crystal as its sampling reference; the §9.4
  receiver gives only a once-a-bit strobe (`newimpl/rtl/dm_rx.v`), not the §9.2
  encoder's 128 kHz half-bit; a crystal-free PLL or strobe-timed one-shot is
  undrawn. `newimpl/tb/subscriber.v`'s free-running counter is a bench
  stand-in. The choice also decides whether the set transmits with no
  downstream. Blocks the SU-D schematic (`su-1.md` §5).
- **The §9.5 filter buffer and the comparator's rail**, for both ends:
  `channel-cards.md` §6.
- **§2's switching transients** are from a scratch script, not `subline.log`.
- **Glare.** A hook closure mid-burst feeds the decoder a few ms of zeros; §4's
  `1010` while RING is detected covers it by reasoning only.
- **Not measured:** a CO's pulse receiver against uncorrected pulses (53 % for a
  60 % break); the mute on a real phone; long runs, crosstalk, more than one seed.
- **Phantom imbalance.** A resistance difference between a pair's two wires puts
  net DC through the winding. Not computed against the line transformer's
  saturation (`mf8-spec.md` §9.3), nor the feed's drop over a real loop.
