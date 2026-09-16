# Discrete digital voice carrier — simulation

Design exploration and bit-level simulation for a small CVSD voice carrier over
twisted pair, intended to be built in discrete 74HC logic.

## Design under study

    frame   [A1][C1][A2][C2][A3][C3][A4][C4][S][T]     10 bits @ 32 kHz
            S = 0, T = 1                                320 kbps line

    4 x 32 kbps CVSD, one signalling bit per channel per direction.
    Two independent one-way systems, one pair each direction; each direction is
    timed end to end by its source's crystal, so slips are structurally impossible.
    Differential Manchester line coding: DC-free, polarity-blind, no threshold.

Signalling alternates with voice so that no two adjacent interior bits are static.
That is what makes start/stop framing safe: every wrong alignment is gated by a
CVSD bit.  An on-hook A bit next to an off-hook one would otherwise hold a false
alignment indefinitely.

## Modules

| file | contents |
|---|---|
| `cvsd.py` | CVSD codec.  Integrator step is proportional to the **actual** bit interval (`I*t/C`), so clock jitter and gapped clocking fall out of the model. |
| `link.py` | Frame build/strip, bit-slip framer with acquisition and loss-of-frame counters, bit noiser, signalling RC+Schmitt integrator. |
| `phy.py` | Differential Manchester and AMI encoders, cable/noise/receiver chain, oversampling DPLL. |
| `phy_fast.c`, `fast.py` | C implementations of the hot loops (slicer, DPLL, analog-PLL and monostable decoders), verified bit-identical to the Python. |
| `audio.py` | Band-limiting, rate conversion, alignment, segmental SNR. |
| `run.py`, `compare*.py`, `listen*.py`, `link_tests.py` | Experiments. |

## Findings so far

- **Bit interleaving, not byte.** CVSD has no sample boundary and its decoder needs a
  uniform clock.  A gapped clock costs ~5x amplitude error even with the integrator
  gated off, and destroys the signal without.
- **Loss-of-frame must not use "N consecutive bad frames."** An even-numbered bit slip
  rotates the channel slots and lands the S/T check on an (A,C) pair, which fails only
  ~50% of the time; a 6-bit slip then never recovers.  A saturating up/down counter
  (+2 bad, -1 good, trip 12) catches every slip size in under 0.9 ms with no false
  reframes to 3e-2 BER, and cuts crosstalk after a slip from 558 ms to 0.84 ms.
- **Signalling is the most robust part of the system.** RC + Schmitt on the A bit gives
  zero spurious ring assertions at any BER tested up to 6e-2, and dial pulses recover
  78/78 with 0.16% ratio error.
- **Clock recovery does not need oversampling.** An analog PLL at 1.28 MHz and a
  monostable interval classifier with *no* receive clock both match a 10.24 MHz
  oversampling DPLL to within 3x at the noise edge.
- **Biphase beats AMI**, but not for the expected reason: AMI's threshold must track
  received amplitude (fails at 0.6x gain error) where biphase decides on a zero
  crossing.  Framed AMI degrades gracefully; biphase is perfect until it isn't.

## Test audio

Not committed.  The speech extracts came from a third-party video via
`yt-dlp` + `sox`; regenerate locally and place `speech30.wav`, `spk_300.wav`,
`spk_600.wav`, `spk_900.wav` (mono, 48 kHz) in this directory.

## Building

    gcc -O3 -march=native -shared -fPIC -o libphyfast.so phy_fast.c -lm
