# The CVSD engine in Falstad

`cvsd_engine.txt` is the 64 kbps CVSD encoder and decoder of `mf8-spec.md`
§12.1 as a CircuitJS circuit, looped back. It uses the `Iabc` drive of
`circuit-review.md` §2.4 and the logic connections of §4. Its values come from
the codec law in `mf8.params(64000)`, through `falstad_cvsd.py`:

| part | value | sets |
|---|---|---|
| `C_int` ∥ `R_int` | 10 nF ∥ 100 kΩ | τ_int 1 ms |
| R1, `C_syl` ∥ R2 | 51.1 kΩ, 100 nF ∥ 2.55 MΩ | τ_syl 5.0 ms; `I_max`/`I_min` = (R1+R2)/R1 = 50.9, 34.1 dB |
| `R_set` | 30.9 kΩ | 160 µA from the PNP's collector at full syllabic level, 3.1 µA at none; the OTA passes 98.9 % of it |
| OTA inputs | 47 kΩ / 2.2 kΩ from Q and /Q | ±224 mV, so the OTA gives ±`Iabc` |

## Opening it

falstad.com/circuit → **File → Open File…** → `falstad/cvsd_engine.txt`. The file
is CircuitJS's XML format, which the current falstad.com build reads and writes.
An older copy of CircuitJS, such as an offline install, may read only the older
text format. Press **Run** if the simulation is stopped.

Encoder on top, decoder below. The comparator (an LM311 with a pull-up) feeds a
three-flip-flop register, which feeds the coincidence gates, the syllabic RC, the
op-amp and PNP `Iabc` source, the OTA and the integrator. The decoder takes
`C_TX` on its own clock, `RX_CLK`, half a bit after `TX_CLK`, as a receiver
samples. Its output goes through a 3rd-order 3.4 kHz reconstruction filter to
`OUT`. The OTA's diode-bias pin is left open, as on the LM13700; it shows as an
open post.

Scopes, left to right:

1. The input and the encoder's integrator: the staircase tracking the sine.
2. The input and `OUT`.
3. The two syllabic nodes, which sit at 4.90 V × (1 − syl).

The first trace in each scope is green and the second red.

## Things to try

| slider | what it shows |
|---|---|
| Sine level | the companding: the steps shrink toward `I_min` as the level falls, and the syllabic node climbs toward 4.90 V |
| Sine frequency | slope overload, with the level raised: the 16 000 V/s maximum slew is a 1 V peak sine at 2.5 kHz, or nominal level at 12 kHz |
| Encoder or decoder `R_set` | `I_max` and `I_min` together. A mismatch between the cards is a pure gain change, which §12.1 allows to ±30 % |
| Decoder R2 | `I_min` alone, so the decoder's gain follows the signal level. §12.1 allows ±10 % |

The switch next to the sine selects **Audio In** instead. Load a WAV through
that element's edit dialog; ±1 in the file is the integrator's ±1 V full scale.

**It is slow.** About a third of a millisecond of circuit time per second on the
machine that measured it. A 1 kHz cycle takes about 3 s, and three syllabic time
constants about 40 s, so listening is not practical: 1 s of audio takes about 45
minutes. For listening use `mf8_render.py`.

## Against the model

`falstad_cvsd.log`: `falstad/sim.mjs` ran the file in falstad.com's simulator,
headless, and `python3 falstad_cvsd.py check` compared the recording with
`cvsd.py`. 24 ms, a 1 kHz sine:

| | nominal | −20 dB |
|---|---|---|
| decoder against `cvsd.decode` on the circuit's own bits | −42.8 dB | −37.4 dB |
| syllabic node against the law on the same bits, rms | 1.6 mV | 0.2 mV |
| OTA output current / `Iabc` | 0.989 | 0.990 |
| runs of three, circuit / `cvsd.encode` on the same input | 0.130 / 0.131 | 0.003 / 0.004 |
| in-band SINAD, circuit / model | 35.7 / 33.6 dB | 28.4 / 29.7 dB |

The circuit's analog parts do what the model's equations say. The one parameter
of the law that comes out off is the ratio, 50.9:1 against 51.3:1, because R1
and R2 are E96 values.

## Simulator settings, not circuit choices

Keep these if you edit the circuit. Each fixed a measured error:

- **16 time steps per bit** (976.6 ns). At 8, the encoder's decisions drifted
  from the model's. At −20 dB it made runs of three 0.026 of the time against the
  model's 0.003, and lost 6 dB of SINAD, and the decoder was further from
  `cvsd.decode` too, −27.4 dB against −37.4. The OTA and the syllabic node were
  right at 8, and 32 steps agrees with 16, so the cause is the time grid, not
  the circuit. Which part of a bit the coarse grid gets wrong was not found.
- **A 1 ns propagation delay on every gate.** At zero delay, CircuitJS moves a
  change through a gate only as far as its solver iterates within the step. The
  coincidence pulse then fell two steps late but rose on time, and the syllabic
  level read about 20 % low. Any delay under a time step makes each gate take
  exactly one step on both edges.
- **Two clock sources**, not an inverter. The inverter's output edge wandered by
  a step, so some decoder bits were 7 or 9 steps long.
- **Clock edges half a time step off the grid**, so rounding in the simulator's
  time cannot move an edge.

## Not modelled

- **Offsets.** The op-amps and the comparator are ideal. The `Iabc` source
  op-amp's offset is the one `circuit-review.md` §2.4 warns about. Under the
  current law its control voltage at `I_min` is 98 mV (`mf8-spec.md` §12.1), so
  3 mV of offset is 3 % of `I_min`. To see it, put a small DC source in series
  with the op-amp's + input.
- **74HC timing**, apart from the 1 ns above.
- **Ripple on `V_A`**, which is an ideal 5 V here.
- **Temperature**, and tolerances beyond what the sliders move. The PNP's β is
  fixed at 100.

`python3 falstad_cvsd.py` rebuilds the file from the law and overwrites it, so
save edited versions under another name.
