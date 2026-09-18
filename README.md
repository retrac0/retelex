# Discrete digital voice carrier — simulation

Design exploration and bit-level simulation for a small CVSD voice carrier over
twisted pair, intended to be built in discrete 74HC logic.

## The standard

    frame   [A1][C1][A2][C2] ... [AN][CN][S][T]      2 + 2N bits, N = 1, 3 or 7
            S = 0;  T = 1,1,1,0 repeating over four frames

    16, 32 or 64 kbps per channel;  line 64 .. 1024 kbps;  4.096 MHz master
    each slot: CVSD voice card (A = E&M, C = CVSD), data card (A = 1, C = data),
    or empty (A = 0, C = frame toggle)

Two independent one-way systems, one pair each direction, each timed end to end
by its source's crystal, so slips are structurally impossible. Differential
Manchester line coding: DC-free, polarity-blind, no threshold. Two jumper fields
select among nine modes: line rate for the plant, channel count for the office.

The full specification is `docs/spec.md`. The card designs are
`docs/line-transmitter.md`, `docs/line-receiver.md`, `docs/channel-card.md`, `docs/data-card.md`,
`docs/fxo-fxs-card.md` and `docs/repeater.md`. How the framing was chosen is in
`docs/framing-review.md` and `docs/draft-protocols.md`.

## Modules

| file | contents |
|---|---|
| `cvsd.py` | CVSD codec.  Integrator step is proportional to the **actual** bit interval (`I*t/C`), so clock jitter and gapped clocking fall out of the model. |
| `link.py` | Frame build/strip, bit-slip framer with acquisition and loss-of-frame counters, bit noiser, signalling RC+Schmitt integrator. |
| `phy.py` | Differential Manchester and AMI encoders, cable/noise/receiver chain, oversampling DPLL. |
| `phy_fast.c`, `fast.py` | C implementations of the hot loops (slicer, DPLL, analog-PLL and monostable decoders), verified bit-identical to the Python. |
| `audio.py` | Band-limiting, rate conversion, alignment, segmental SNR. |
| `repeater.py` | Cascaded spans with amplifying, regenerating and retiming repeaters: jitter accumulation, terminal window erosion, near-end crosstalk, span loss, plant impulses. |
| `framing_review.py` | Generic framer harness; every candidate header through the same battery. |
| `rx_review.py` | Receiver front end: input filter, hysteresis, dead time, carrier detect, chain end to end. |
| `s4_simple.py` | The framer as specified (`framer_single`) and its full validation: `python3 s4_simple.py spec`. |
| `s4_lof.py`, `t_pattern.py`, `cvsd_tones.py` | Framer policies and T patterns considered and rejected; CVSD tone and offset limit cycles. |
| `seatmix.py`, `seatmix_sim.py` | Every combination of voice card, data card and empty slot: enumeration and simulation. |
| `strap.py` | The nine modes: straps, clock chain, noise margin per line rate, data pipes, mis-strap. |
| `n7.py`, `seven.py`, `talkers.py`, `family.py` | The 7-channel member and per-rate audio on independent talkers. |
| `validate.py` | End-to-end check of the spec's claims (on the previous framing header; see spec §13). |
| `run.py`, `compare*.py`, `listen*.py`, `link_tests.py`, `bond.py`, `g711.py` | Experiments. |

## Findings so far

- **Bit interleaving, not byte.** CVSD has no sample boundary and its decoder needs a
  uniform clock.  A gapped clock costs ~5x amplitude error even with the integrator
  gated off, and destroys the signal without.
- **Frame sync must be something payload cannot imitate forever.** A static header is
  imitated by static payload: a constant data slot, or an empty slot pulled low before
  an off-hook channel. A period-2 header is imitated by CVSD silence, which is exactly
  `1010`. S = 0 with T = `1110` over four frames is imitated only by a data bit placed
  after a bit that can stay 0; keeping data on C with A strapped high removes that for
  every card combination (0 of 16 384 at N = 7). A narrower-frame transmitter can't
  lock a wider receiver either: decimated by two, `1110` is `1111` or `1010`.
- **One check and one counter frame the link.** "S = 0 and exactly one zero in the last
  four T" fails every frame on static or `1010` T positions and at least 65% of frames on
  random CVSD, tones and offsets, so a +1/-1 counter tripping at 16 detects every slip in
  under 20 frames, while one line error spoils at most four frames and never trips it
  below 3e-2 BER. No multiframe phase is tracked. A predictive check with a phase counter
  was blind to three-in-four matches; "N consecutive bad frames" never recovers from some
  slips at all.
- **The T pattern must be unbalanced.** `0101` is CVSD silence. `1100` is what CVSD makes
  of a steady tone near a quarter of the frame rate (a 3 kHz tone at 16 kbps defeats it).
  `1110` has three ones to a zero, which a zero-mean signal cannot produce.
- **The crystal can be slow.** The fastest node with a job is the half-bit clock, which is
  the baud rate; 4.096 MHz reaches all nine modes.
- **Signalling is the most robust part of the system.** RC + Schmitt on the A bit gives
  zero spurious ring assertions at any BER tested up to 6e-2, and dial pulses recover
  78/78 with 0.16% ratio error.
- **Clock recovery does not need oversampling.** An analog PLL at 1.28 MHz and a
  monostable interval classifier with *no* receive clock both match a 10.24 MHz
  oversampling DPLL to within 3x at the noise edge.
- **A repeater should regenerate, not reclock.** Deterministic distortion does not
  accumulate in a slice-and-re-drive chain at all -- 33 spans give the same interval
  histogram as one, because re-squaring the waveform makes the ISI displacement a
  fixed point.  Only jitter accumulates, as `spans^0.41`.  A retiming stage measures
  indistinguishable and costs three packages per direction; a local crystal would make
  the repeater a timing boundary and bring the slips back.
- **Biphase beats AMI**, but not for the expected reason: AMI's threshold must track
  received amplitude (fails at 0.6x gain error) where biphase decides on a zero
  crossing.  Framed AMI degrades gracefully; biphase is perfect until it isn't.

## Test audio

Not committed.  The speech extracts came from a third-party video via
`yt-dlp` + `sox`; regenerate locally and place `speech30.wav`, `spk_300.wav`,
`spk_600.wav`, `spk_900.wav` (mono, 48 kHz) in this directory.

## Building

    gcc -O3 -march=native -shared -fPIC -o libphyfast.so phy_fast.c -lm
