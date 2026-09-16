# FXO / FXS support card

Sits between the E&M channel card and a real 2-wire line or telephone. One board,
two populations.

```
 2-wire line ──→ [ FXO/FXS support card ] ──E&M 4-wire──→ [ channel card ] ──→ backplane
   or phone         hybrid + signalling        TX pair, RX pair, M, E
```

**E&M stays the internal standard and the channel card never changes.** That is
how carrier equipment was actually organised — one internal interface, with the
"personality" in a separate module — and it is why all the high voltage, the
hybrid and the loop signalling live here instead of contaminating the digital
card.

---

## 1. Signal mapping

One bit each way, which is exactly what the frame carries. The mapping is exact,
not a compromise:

| | **FXO** (faces a CO line) | **FXS** (faces a telephone) |
|---|---|---|
| **M** lead — sensed here, transmitted | ringing detected on the line | loop closed (phone off-hook) |
| **E** lead — received from far end | close the loop toward the CO | apply ringing to the phone |

### The pair extends a line

FXO at the exchange end, FXS at the remote end:

```
CO rings          → FXO ring detect → M → A bit → far E → FXS rings the phone
phone off-hook    → FXS loop detect → M → A bit → far E → FXO closes loop to CO
```

Both directions are one bit, and the cadence passes through as a slow A-bit
pattern — so distinctive ringing is reproduced without doing anything special.

---

## 2. Shared blocks (both populations)

- **Line transformer**, 600 Ω, 2-wire side
- **Hybrid** with compromise balance network (§4)
- **Protection**: gas tube, series fuse or PTC, TVS
- **Level trim**, one per direction (§5)
- **Connector to the channel card**: TX audio pair, RX audio pair, M, E

Everything above is common. Only the signalling front end differs, so lay out
one board and depopulate what the personality does not need — cheaper than two
layouts and one part number to stock.

---

## 3. FXO population — faces a CO line

**Ring detect.** Ringing is ~20 Hz at 40–90 Vrms sitting on −48 V DC.

```
tip/ring ──[ 1 µF, 250 V ]──[ bridge ]──[ R limit ]──→ opto LED
                                                          │
                                        RC ~100 ms ───────┴──→ M lead
```

The series capacitor blocks the DC feed; the bridge rectifies so both half-cycles
drive the opto. The opto then pulses at twice the ring frequency, so **an
integrator is required** — roughly 100 ms, long enough to hold through the 20 Hz
pulsing but short enough to follow the 2 s on / 4 s off cadence. Without it the
far end receives 40 Hz chopping instead of a ring signal.

**Loop closure.** The E lead drives a relay or solid-state switch across tip and
ring. Closing it must present the CO with a correct DC path (loop current in the
20–100 mA range it expects) and the right AC impedance, which the transformer
already provides.

---

## 4. FXS population — faces a telephone

More involved, because this end supplies power and ringing.

**Battery feed.** −48 V through a feed bridge, current limited to ~25–45 mA. A
classic inductive feed bridge works; an electronic feed is smaller.

**Loop current detect.** Sense resistor in the feed path into an opto, threshold
around 10–15 mA. Output → M lead.

**Ring relay.** The E lead connects the ringing bus to the line and **must
disconnect the battery feed while ringing.**

**Ring trip — do not omit this.** If the subscriber answers mid-burst, DC loop
current flows through the ringing path, and ringing must be removed within about
200 ms. Sense the DC component through the ring path and drop the relay. Leaving
it out means the phone keeps ringing into the answered call.

**Ringing source: a shared bus, not a per-card generator.** One 20 Hz, ~90 Vrms
generator per shelf feeding every FXS card through its ring relay. Per-card
generators are the expensive way to build this and buy nothing.

---

## 5. The hybrid — and why echo is not a problem here

2-wire to 4-wire conversion, transformer with a compromise balance network.
600 Ω resistive is a reasonable starting point.

**The link's round-trip delay is under a millisecond** — roughly one bit of CVSD
each way (31 µs), a frame of multiplexing (31 µs), and ~5 µs per km of cable.
Echo only becomes perceptually objectionable above about 20–30 ms round trip, so
**no echo canceller and no echo suppressor are needed**, and a precision
per-loop balance network is not worth the trouble.

What the hybrid *does* still have to do is prevent **singing** — oscillation
around the 4-wire loop formed by hybrid leakage at both ends. Target 10–15 dB
trans-hybrid loss per end for a comfortable singing margin. A compromise network
achieves that against real loops; a perfect null is unnecessary.

---

## 6. Levels

The channel card's CVSD companding is tuned around a nominal level (0.15 rms of
full scale), and **getting this wrong costs SNR directly** — not gracefully.

The hybrid has insertion loss, so provide a gain trim in each direction and set
them so the channel card sees its nominal level at the trunk's design TLP. Set
these before trimming the codec's `Iabc`, or the two adjustments fight each other.

---

## 7. Safety — this is the boundary

**This card is where high voltage first appears in the system**: −48 V battery,
~90 Vrms ringing (roughly 250 V peak on top of battery), and outside-plant
surges. Keeping it off the channel card was the point of the E&M split.

Consequences for the layout:

- Creepage and clearance between the line side and the logic side
- **The optos are a safety barrier, not merely noise isolation** — specify them
  for the isolation rating, not just CTR
- Protection ahead of everything: gas tube, series fuse or PTC, TVS
- The ringing bus needs the same treatment wherever it runs

---

## 8. Parts

| block | population | parts |
|---|---|---|
| Line transformer | both | 600 Ω, 1:1 |
| Hybrid + balance | both | transformer + compromise network |
| Protection | both | gas tube, PTC, TVS |
| Level trim | both | op-amp per direction |
| Ring detect | FXO | cap, bridge, opto, RC integrator |
| Loop closure | FXO | relay or solid-state switch |
| Battery feed | FXS | feed bridge, current limit |
| Loop detect | FXS | sense resistor, opto |
| Ring relay + trip | FXS | relay, DC sense |

A handful of packages plus the transformer and relay — the cost here is the
magnetics and the relay, not the silicon.

---

## 9. Bring-up

1. **Hybrid alone.** Measure trans-hybrid loss against a 600 Ω load and confirm
   10–15 dB before connecting anything digital.
2. **Levels**, into the channel card at nominal. Do this before the codec trim.
3. **FXO: ring detect** against a real ring generator — verify the integrator
   holds through the 20 Hz pulsing and follows the cadence cleanly.
4. **FXS: feed and loop detect**, then ringing, then **ring trip specifically** —
   answer mid-burst and confirm ringing drops inside 200 ms.
5. **FXO/FXS pair end to end** over the carrier: ring the remote phone from the
   CO, answer it, confirm supervision returns and audio is clean both ways.
