# Channel cards — the CVSD line card, the FXS/FXO card, the data card

Three cards for the channel socket of an MF8 shelf or an exchange block, and a
measurement of the one signalling bit each way that all three use. The socket,
its pins card by card and the rails are `common-cards.md` §1 and §3; the E&M
card is `mf8-spec.md` §12.1.

> **Built:** the CVSD line card, `newimpl/rtl/cvsd_line_card.v` on `dm_rx.v`, bench `tb_line`.
> **Proposed:** the FXS/FXO and data cards, and every circuit here; nothing has been on a bench.
> **Measured in:** `subscriber-line.md` §3–§5 (`sim/subline.log`); §5 here (a scratch script).

---

## 1. Which card faces which

| end | `A_TX`, sent | `A_RX`, received |
|---|---|---|
| **station end**: CVSD line card, FXS, E&M | the phone is off-hook (M) | ring the phone (E) |
| **office end**: FXO | ringing is present on the CO line | close the loop toward the CO |

| near end | far end | result |
|---|---|---|
| CVSD line, FXS or E&M | FXO | an extended line: the phone is on the CO as if wired to it |
| CVSD line or FXS | CVSD line or FXS | a hotline: either phone off-hook rings the other |
| E&M | E&M | a tie trunk between two PBXs |
| data | data | a 64 kbps pipe |
| FXO | FXO | **not a configuration**: each CO line would seize the other on ring |
| any voice card | data card | **wrong**: loud, locked, not squelched (`mf8-spec.md` §13). Label every slot |

Station ends are interchangeable, digital or analog. Dial pulses are on-hook
pulses on A (§5). In an exchange block `A_TX` is the port's M and `A_RX` its E,
chopped by the ring cadence while the port rings (`fabric.md` §5.2).

---

## 2. The CVSD subscriber line card

Two pairs to one phone. The phone holds the codec; the card holds the two line
interfaces, the hook detector and the slot logic. The line is
`subscriber-line.md`; the packaged phone is `su-1.md`.

```
 phone ══ upstream ══▶ [ receiver §9.4 ] ─Q, strobe──▶ [ '175 ] ──────────────▶ C_TX
                             │ LONG, MID, carrier       TX_CLK
                             └─▶ [ hook detector ] ─ ON_HOOK ─┬─▶ A_TX
 phone ◀═ downstream ◀═ [ encoder '112 ] ◀─ DN_D ◀─ [ '157 ] ◀┤◀─ C_RX ─▶ [ '175 ]
          48 V phantom     TX_CLK, LOOP_HB                    │◀─ A_RX ─▶ [ RC, '14 ]
                                                              └◀─ FILL, MUTE
```

### 2.1 The line side

The driver, receiver, termination and protection are `mf8-spec.md` §9 at the
64 kbps line rate:

| item | specification | from |
|---|---|---|
| Downstream driver | 75176 driver half, series matching, 150 ns slew limit | §9.3 |
| Line transformers, both pairs | **Murata 78615/9C**: 1CT:1CT, 10 mH minimum, 56 V·µs, 6-pin DIP. The requirement is L/R ≥ 2.5 cells, ≥ 4 mH at 64 kbps | §9.3 (`subline.py xfmr`) |
| Upstream receiver | the §9.4 classifier at the **64 kbps plug**: filter 128 kHz, threshold 0.75 cell = 11.7 µs, dead time 3.1 µs, carrier timeout 31.3 µs; a fixed footprint, since the card runs at no other rate | §9.4, §9.7 |
| Termination, protection | 100–135 Ω on the line side of the comparator; gas tubes, series PTC, TVS clamping above the 48 V feed | §9.3 |
| Phantom feed | 48 V into the line-side centre tap of the downstream transformer (pin 2 or 5, whichever winding faces the line), returned through the upstream one's; a 100 mA PTC; ≤ 40 mA to the phone | `subscriber-line.md` §1.1 |

The −48 V comes from socket c9/c10 in an MF8 shelf, in series with the slot
fuse. **In an exchange block it comes on the card's own harness**: the port
card's edge header carries no rail above +5 V (`block-stack.md` §5).

### 2.2 The hook detector

`subscriber-line.md` §3's detector, on the receiver's own outputs:

| term | parts |
|---|---|
| X = Q ⊕ Q[n−2] | two flip-flops on the bit strobe (one 74HC74), ¼ 74HC86 |
| violation: LONG · MID at an accepted edge | ¼ 74HC08 into ½ 74HC74, sampled at the dead-time pulse's leading edge, before MID moves on it (`mf8-spec.md` §9.4) |
| violation: gap > 1.25 cells | ½ 74HC123, retriggerable, **19.5 µs** |
| violation held 16 cells | the **other** ½ 74HC123, retriggerable, **250 µs** |
| G = X + violation + /carrier | ¼ 74HC32 |
| G → RC τ = 4 ms → `ON_HOOK` | ¼ LM339 at 0.85 / 0.70 of the swing, resistive reference |

**The gap timer and the hold are two timers**: one '123 half has one pulse width.
The gap must sit between 1.0 and 1.5 cells (15.6–23.4 µs). Below one cell it
fires on every `1` bit and reads a talking line as on-hook; trim at or above
19.5 µs, never below (`stu-1.md` §4). `dm_rx.v` has the two timers apart, and
`sim/subline.log` was measured at 1.25 cells. A comparator and not a '14, because
0.85 and 0.70 sit where no Schmitt threshold does.

### 2.3 The slot logic

The exchange-side rule of `subscriber-line.md` §4, in socket signals:

```
DN_D  =  (ON_HOOK + MUTE) ? ( A_RX_f ? 0 : FILL ) : C_RX_s
C_TX  =  Q_s          A_TX  =  NOT ON_HOOK
```

`C_RX_s` and `Q_s` are `C_RX` and the receiver's latch through two stages on
`TX_CLK`, one 74HC175 for both crossings (`mf8-backplane.md` §2). `A_RX_f` is
`A_RX` through the RC of `mf8-spec.md` §14 (τ = 2 ms) and ¼ 74HC14. `FILL` is the
socket's `1010`, so the card makes no idle pattern; the rule is ¾ of a 74HC157.
`MUTE` puts `1010` on an off-hook phone while an MF8 trunk is not locked; a block
ties it locked. The phone's `1100` crosses the channel as bits, which the far
card ignores: it reads hook state from A.

### 2.4 The downstream encoder

`mf8-spec.md` §9.2's: `EN = H + /DN_D` with `H` = `TX_CLK`, into a JK wired
J = K = EN. At the boundary H is 1 and it always toggles; at mid-cell H is 0 and
it toggles for a 0. **The flip-flop is half a 74HC112, clocked by `LOOP_HB`'s
falling edge**, with EN from ½ 74HC00. A 74HC74 has no J or K (a toggle on a D
input is D = Q ⊕ EN, an XOR more), and a 74HC109 with J and /K tied is a D
flip-flop. `cvsd_line_card.v` models the function on `LOOP_HB`'s rise, reading H
after that edge; its comment's "half a '74" is wrong. The block's timing: §6.

### 2.5 Pins and parts

In `common-cards.md` §1.3's matrix this is the one card that reads a2 `LOOP_HB` (the
encoder) and a4 `FILL`. It ignores a7 `RX_CLK`: its receive timing comes off the
loop, and everything it is handed crosses into T on `TX_CLK`. It reads a11
`MUTE`. a12 is tied to ground, a plain line; a13 `/ANS` is open, so the port rings
it. Where the '165 word is fitted it shifts on `TX_CLK`, a bit a frame, and only
its primary octet is read (`card-word.md` §3). a14 is spare. The rear connector
carries the two pairs.

| block | parts |
|---|---|
| Upstream receiver | `mf8-spec.md` §9.4: 74HC86, 74HC221, 74HC123, 74HC74 |
| Hook detector | 1½ 74HC74, ¼ '86, ¼ 74HC08, 74HC123, ¼ 74HC32, ¼ LM339 |
| Encoder | ½ 74HC112, ½ 74HC00 |
| Synchronizers, rule, A filter | 74HC175; 74HC157, ¼ 74HC04; ¼ 74HC14 and an RC |
| Line | 75176 driver and receiver, two 78615/9C, gas tubes, PTCs, TVS |

**No relay, no ring generator, no ring trip, nothing above the 48 V feed**: the
phone's ringer is armed by a bit pattern. The phone's end is `subscriber-line.md`
§4; it is loop-timed, by a circuit still open there (§1, §7).

**Bring-up:** the receiver from a generator at 128 kBaud; the detector against
`1100`, speech and a noisy dead pair; the card looped to itself; a phone with no
trunk, as `tb_line` runs it; then over a trunk against an FXO card.

---

## 3. The analog FXS / FXO card

One board, two populations: the E&M card of `mf8-spec.md` §12.1 with the E&M
leads replaced by a loop-start line circuit and a hybrid.

```
 2-wire ══▶ [ protection ]─[ hybrid 600 Ω ]─┬─▶ [ trim ]─[ 300–3400 ]─▶ ENCODER ─▶ C_TX  (TX_CLK)
                                            └─◀ [ trim ]◀─[ recon ]◀── DECODER ◀─ C_RX  (RX_CLK)
            FXS: feed, loop detect, ring relay, ring trip ─▶ A_TX ; A_RX ─▶ ring
            FXO: ring detect, loop closure                ─▶ A_TX ; A_RX ─▶ close the loop
```

`A_RX` goes through the `mf8-spec.md` §14 RC (τ = 2 ms) and ¼ 74HC14 to
`A_RX_f`. The far end's cadence passes as a slow A pattern, so distinctive
ringing reproduces and dial pulses cross as §5 measures. What the FXO's `A_TX`
means is a jumper (`common-cards.md` §5).

### 3.1 Engine, audio and hybrid

Both engines sit on the CVSD codec riser (`cvsd-codec.md`), stacked on header R;
the base keeps the hybrid, trims, line circuit and socket. An on-base stuffing
with R open stays valid. The encoder is in T on `TX_CLK`, the decoder in R on
`RX_CLK`, and the two never meet (`mf8-backplane.md` §2).

| item | specification |
|---|---|
| Hybrid | transformer, 600 Ω, compromise balance network, 600 Ω resistive to start |
| Trans-hybrid loss | **10–15 dB** per end against real loops: the singing margin |
| Level trims | one per direction, to `mf8.NOMINAL_RMS` (0.15 rms of full scale) at the channel's design level, **before** the `Iabc` trim, or the two fight |
| Filters | 300–3400 Hz ahead of the encoder on the base; the 3.4 kHz reconstruction on the riser |

**Echo needs no treatment**: the round trip is under 0.1 ms plus 5 µs a km,
against 20–30 ms before echo is objectionable.

### 3.2 FXS population

| block | specification |
|---|---|
| Battery feed | −48 V through a 100 mA PTC; a feed bridge current-limited to **25–45 mA** |
| Loop detect | a sense resistor into an opto, threshold **10–15 mA**, → `A_TX` |
| Ringing | 20 Hz, ~80 Vrms (`mf8-psu.md` §3.2); a ring relay on `A_RX_f` connects it **and disconnects the feed while connected**. The cadence is `A_RX`: the card makes none |
| Ring trip | **mandatory**: DC sensed through the ring path drops the relay within **200 ms**, whatever `A_RX` says |

### 3.3 FXO population

| block | specification |
|---|---|
| Ring detect | series 1 µF 250 V, bridge, current limit, opto, an **RC of ~100 ms** that holds through the 20 Hz and follows the 2 s / 4 s cadence, → `A_TX` |
| Loop closure | `A_RX_f` drives a relay or solid-state switch across tip and ring, a **20–100 mA** DC path; low opens it, which is how dial pulses leave |

**Safety.** −48 V, ~80 Vrms ringing and outside-plant surges first appear on this
card. Gas tube, PTC and TVS ahead of everything, the ring path rated for 250 V
peak; creepage and clearance between line side and logic; the optos are the
barrier and are specified for isolation, not only CTR.

### 3.4 Rails, pins and parts

The FXS takes +5 V, ±12 V, −48 V and ringing; the FXO +5 V and ±12 V. In an MF8
shelf they come on socket row *c*, ringing jumpered to FXS slots only
(`mf8-backplane.md` §8). **In an exchange block ±12 V, −48 V and ringing come on
the card's own harness**, star-wired from a fused point; the edge header carries
+5 V only (`block-stack.md` §5). Both populations read a7 `RX_CLK`. The FXS
grounds a12 (a plain line) and leaves a13 open; the FXO carries a '165 with class
101, outside line, and ties a13 low, since an outside line is never rung and gives
no ringback. Neither reads a11 `MUTE` (§6).

Parts: the riser (`cvsd-codec.md` §4), filters and trims, ¼ 74HC14, the hybrid,
protection; FXO adds ring detect and loop switch, FXS the feed bridge, loop-detect
opto, ring relay and DC sense. Lay out one board and depopulate.

**Bring-up:** the engine looped, then `Iabc`, then card to card (`mf8-spec.md` §12.1); the
hybrid alone against 600 Ω; levels; ring detect on a real generator, ring trip
answered mid-burst; then an FXO–FXS pair over a trunk.

---

## 4. The data card

One slot as a **64 kbps synchronous, bit-transparent, octet-aligned, slip-free
pipe** with two clocks. No scrambler is needed.

```
 DTE ─TXD─▶ [ RS-422 ]─▶ [ D, TX_CLK ]─▶ C_TX       TX_CLK, TX_OCT ─▶ [ RS-422 ]─▶ TXC, TX sync
 DTE ◀RXD── [ RS-422 ]◀─ [ D, RX_CLK ]◀─ C_RX       RX_CLK, RX_OCT ─▶ [ RS-422 ]─▶ RXC, RX sync
                            ▲ forced 1 by MUTE
 DTE ─DTR─▶ [ RS-422 ]─▶ A_TX             A_RX ─▶ [ RC, '14 ]─▶ [ RS-422 ]─▶ DSR
```

| property | | why |
|---|---|---|
| Clocks | **two**: `TXC` the local crystal, `RXC` the recovered clock, both from the carrier as a V.35 or X.21 DCE gives them. One clock in an exchange (`clocks.md` §5) | `mf8-backplane.md` §2: no elastic store, no slip |
| Octets | superframe state *k* is bit *k*, b0 first; `TX_OCT` and `RX_OCT` mark state 7 | `mf8-spec.md` §6 |
| Signalling | `DTR` on `A_TX`; `DSR` from `A_RX` through the `mf8-spec.md` §14 RC | a far end not ready is worth knowing |
| On `MUTE` | `RXD` forced to 1, mark idle; `DSR` drops with the '259 clear | `mf8-spec.md` §13 |

In an exchange a data circuit is a mutual nail: each card's word names the
other (`card-word.md` §6.2), and a13 is tied low. A data card in no circuit
says *line* with `D`, which no marker connects (`card-word.md` §4).

**Three uses.** *Synchronous DCE*: V.11, 26LS31 and 26LS32; the DTE changes `TXD`
on `TXC`'s fall and the card samples on its rise, and the reverse for `RXD`, so
setup and hold are 7.8 µs less cable. *A DS0*: `TX_OCT` and `RX_OCT` as frame
syncs make a µ-law codec's serial interface, so a G.711 codec hangs off the card
with no shift register. *Async by oversampling*: a MAX232 population, the waveform
sampled at 64 kHz on `TX_CLK` and replayed on `RX_CLK`, every edge within
15.6 µs; **≤ 9 600 bps** (15 % of a bit), by analysis.

**Bonding.** Two cards in adjacent slots, jumpered even and odd with a short link,
carry 128 kbps, even bits on the lower slot; three in slots 1–3 carry 192 kbps.
The framer fixes slot order, so there is no alignment state.

**The slot rule.** Two data cards may not sit three slots apart: not 1 and 4, 2
and 5, or 3 and 6 (`mf8-spec.md` §5). **Key the connector** against those pairs,
or to seats 1–3. PCM octets are safe in every seat. A data card carrying the F
word three seats from a voice card is acquired by chance about once in 500
attempts at one skew and released by the guard counter in milliseconds.

**Parts:** 26LS32 (`TXD`, `DTR`), 26LS31 (`RXD`, `TXC`, `RXC`, `DSR`, `TX_OCT`,
`RX_OCT`); ½ 74HC74 a direction; ¼ 74HC32 for `RXD` on `MUTE`; ¼ 74HC14; a
3-position bond jumper and a header; the word's 74HC165 and 2N7002
(`card-word.md` §3).

**Bring-up:** `TXD` looped to `RXD`; card to card; over the trunk all zeros, all
ones, `0x7F` and random, each from a cold start to lock at the true phase.

---

## 5. Measured: signalling through the A path

Every card puts hook state, ringing or `DTR` on one bit sampled once a 125 µs
superframe, latched by the receiver's '259 (cleared while the trunk is not
locked), through the `mf8-spec.md` §14 RC (τ = 2 ms) into a 74HC14 (thresholds
taken as 0.55 and 0.35 of the swing). Dial pulses, ten breaks, errors on A:

| dial | BER | pulses | break sent → received | make sent → received |
|---|---|---|---|---|
| 10 pps 60/40 | 0 | **10 / 10** | 60.0 → 59.5–59.6 ms | 40.0 → 40.4–40.5 ms |
| 10 pps 60/40 | 6e−2 | **10 / 10** | 60.0 → 59.1–60.0 ms | 40.0 → 40.0–40.5 ms |
| 10 pps 67/33 | 6e−2 | **10 / 10** | 67.0 → 66.0–66.9 ms | 33.0 → 33.3–33.5 ms |
| 20 pps 60/40 | 6e−2 | **10 / 10** | 30.0 → 29.1–29.5 ms | 20.0 → 20.1–20.5 ms |

Breaks arrive 0.5 ms short and makes 0.5 ms long: the RC's asymmetry, **assert
1.5 ms, release 2.0 ms**. Errors to 6e−2 add ±0.4 ms and lose no pulse. Held
states: no spurious transition in 60 s to BER 1e−1; at 2e−1, 6 on-hook in 60 s.
A reframe dropout of 1 to 12 samples (up to 1.5 ms, seven times a slip,
`mf8-spec.md` §4.2) is **not registered**: 1.5 ms dips the RC to 0.47 against a
0.35 release. Ring cadence 2 s / 4 s at BER 3e−2 arrives as 2.0004–2.0005 s on.

So an FXO card pulses the CO within 0.5 ms of the phone, a station card rings in
the far end's cadence to half a millisecond, a slip is invisible to the loop, and
`DSR` follows `DTR` with 1.5–2 ms of lag. Scratch script, not a repository tool.

---

## 6. Open

- **The §9.5 filter buffer.** `mf8-spec.md` §9.5 offers a buffer or a second R
  ten times the first and has not chosen; unbuffered into a 75176's 12 kΩ it
  costs 5.3 dB at the slicer (`stu-1.md` §4, which buffers). To be settled
  once in §9 for every receiver.
- **The detector's comparator rail.** 0.85 × 5 V is above an LM339's 3.5 V
  common-mode ceiling on +5 V; STU-1 divides the RC node and its references
  2:1 (`stu-1.md` §5). §2.2 and SU-1's ring detector state neither a rail nor
  a divider.
- **The encoder's H/`TX_CLK` timing in a block.** A setup/hold race between H
  (= `TX_CLK`) and the encoder's clock edge has been raised. In a block `TX_CLK`
  and `LOOP_HB` are `/SLOT2` and `/SLOT1` off one '163 edge through one '14
  (`block-stack.md` §2.1, U7). The '112 as drawn (§2.4) takes `LOOP_HB`'s fall,
  a quarter bit from any H edge by `clocks.md` §4 (arithmetic); the RTL acts on
  the rise, where H moves. Whether the drawn edge closes the race, and its
  margin, are undecided.
- **The violation capture** (§2.2) under §9.4's two-phase timing is not checked
  against the hold timer.
- **Pulse correction.** Breaks arrive 6.1 ms short (`subscriber-line.md` §5); a
  6.16 ms monostable on `ON_HOOK`'s release restores them
  (`analysis/dialling.md` §1.3). The card has none and `tb_line` measures the
  short break. Whether relayed pulses need it is `newimpl/README.md` §6's
  "Relayed dial pulses".
- **`/ANS` on the line card** is open with no strap. A non-ringing private line
  or a RAW64 nail (`card-word.md` §6.2, `sdu-1.md` §5) needs it low and a word fitted.
- **`MUTE` on the FXS, FXO and E&M cards** (MF8 only). They leave a11 open, so
  through an outage their decoders get the cleared '259's all-zeros, which walks a
  CVSD integrator to the rail. The fix is a gate into the decoder input. Nothing
  has been listened to, and nobody has decided it is worth the gate.
- **Not measured:** every circuit; the hybrid against real loops; the async limit
  against a UART; ring trip, loop detect and the FXO ring detector against a real
  20 Hz generator; a CO's pulse receiver against both legs added.
