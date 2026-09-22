# The voice path in Falstad

Three CircuitJS circuits, built from one set of subcircuit modules by
`falstad_cvsd.py`. Every value comes from the codec law in `mf8.params(64000)`
and the line constants of `mf8-spec.md` §9.

| file | what it is | speed |
|---|---|---|
| `cvsd_link.txt` | audio → CVSD encoder → differential Manchester → line with noise → receiver → CVSD decoder → audio. The decoder runs on the clock the receiver recovers | 0.4 ms of circuit time a second |
| `dm_link.txt` | the line code alone, carrying a PRBS: encoder, line, receiver | 1.5 ms a second |
| `cvsd_engine.txt` | the codec alone, encoder looped to decoder on two clock sources | 0.5 ms a second |

Open one at falstad.com/circuit with **File → Open File…**. The files are
CircuitJS's XML format, which the current falstad.com build reads and writes;
an older copy of CircuitJS may not. Press **Run** if the simulation is stopped.

## The modules

Each block on the page is a subcircuit with its own schematic. How to open one
depends on the CircuitJS build: look for a subcircuit entry in the block's
right-click menu. The modules were checked by importing a file and exporting it
again: all seven come back with their schematics intact.

| module | contents | from |
|---|---|---|
| `CVSD-ENC` | LM311 with a pull-up, three-flip-flop run register, coincidence gates ('86, '32), syllabic RC, op-amp and PNP `Iabc` source, LM13700, integrator and follower. Pins `Y` and `SYL` are test points | `mf8-spec.md` §12.1, `circuit-review.md` §2.4 and §4 |
| `CVSD-DEC` | the same engine with no comparator: `BIT` and `CLK` come from outside | the same |
| `TX-CLK` | 128 kHz half-bit clock `LOOP_HB`; half a 74HC112 divides it by two for the bit clock `H` | §9.1 |
| `DM-ENC` | `EN = H + /bit`, then a 74HC112 half with J = K = EN, clocked by `LOOP_HB`'s falling edge. `/bit` is the encoder flip-flop's own `/Q`, so the gate is one quarter of a '32 | §9.2, `circuit-review.md` §1 |
| `LINE` | the pair as the slicer sees it: the transmit bit as ±`LEVEL` volts, plus `NOISE`, plus a 40 kHz ring (τ 60 µs) started by each edge on `IMP`; then the two-RC input filter at 128 kHz. `SUM` is the line before the filter | §9.5; the ring is `phy.plant_noise`'s |
| `DM-RX` | slicer with ±50 mV hysteresis, transition detector ('86 and an RC), dead time ('221), interval classifier ('123), `LONG` and `MID`, recovered clock `RXC`, carrier detect `CD`. `RXD` and `DT` are test points | §9.4, §9.6, on `circuit-review.md` §3's two-phase timing |
| `RECON` | 3rd-order 3.4 kHz reconstruction low-pass | §12.1 |

| codec part | value | sets |
|---|---|---|
| `C_int` ∥ `R_int` | 10 nF ∥ 100 kΩ | τ_int 1 ms |
| R1, `C_syl` ∥ R2 | 51.1 kΩ, 100 nF ∥ 2.55 MΩ | τ_syl 5.0 ms; `I_max`/`I_min` = (R1+R2)/R1 = 50.9, 34.1 dB |
| `R_set` | 30.9 kΩ | 160 µA from the PNP at full syllabic level, 3.1 µA at none; the OTA passes 98.9 % of it |
| OTA inputs | 47 kΩ / 2.2 kΩ from Q and /Q | ±224 mV, so the OTA gives ±`Iabc` |

**A slider cannot reach inside a module.** That is why the line's three sources
sit on the page and feed pins on `LINE`. It is also why the `R_set` and R2 sliders
of the first version are gone: to mistrim the decoder, build a variant with
`python3 sim/falstad_cvsd.py link --dec-imin 1.2 -o F` (or `--dec-imax`), or edit the
value inside `CVSD-DEC`.

## The line's controls

| slider | what it is | reading it |
|---|---|---|
| Line level | the signal's peak at the slicer, volts. The slicer's hysteresis stays ±50 mV, so 1 V is 5 % and 0.25 V is 20 % | §9.3's "deliver about a volt" |
| Line noise | a fresh uniform value in ±V every time step. 1 V is 0.577 V rms on the line and **0.242 V rms at the slicer** | the documents' `sd` X (`linecodes.py`) is this slider at **1.53 X**: sd 0.4 → 0.61 V, sd 0.7 → 1.07 V, sd 1.0 → 1.53 V |
| Impulse peak | the ring's first peak on the line, volts: 3 is three times the signal | `linecodes.py` uses 0.5–3 |
| Impulse source, Hz | a square wave; each edge starts a ring, so impulses a second are twice this. They are periodic, not Poisson; 258.5 Hz drifts across the bit phase | |

## What the measurements say

`falstad_cvsd.log`: `falstad/sim.mjs` ran each file in falstad.com's simulator,
headless, and `python3 sim/falstad_cvsd.py check` compared the recording with the
Python model.

| `dm_link.txt`, 100 ms, 6 400 bits | bit errors | bits lost | recovered clock, steps of 16 |
|---|---|---|---|
| clean | 0 | 0 | 16 to 16 |
| the documents' sd 0.4 (slider 0.61 V) | 0 | 0 | 14 to 18 |
| sd 0.7 (1.07 V) | 0 | 0 | 12 to 19 |
| sd 1.0 (1.53 V) | 33 | 53 | 8 to 32 |
| slider 2 V | 313 | 211 | 8 to 49 |
| impulses, 3 V peak, 517 a second | 62 | 60 | 10 to 31 |
| level 0.25 V with sd 0.10: hysteresis at 20 % of the signal | 0 | 0 | 14 to 18 |

| `cvsd_link.txt`, 24 ms, 1 kHz | line errors | recovered clock | decoder against `cvsd.decode` | SINAD, circuit / model |
|---|---|---|---|---|
| nominal level, clean line | 0 | 15 to 17 | −43.3 dB | 33.4 / 33.1 dB |
| −20 dB, clean line | 0 | 15 to 17 | −37.5 dB | 26.2 / 27.2 dB |
| nominal, sd 0.4 on the line | **0** | 14 to 18 | −43.2 dB | **27.8** / 33.1 dB |
| nominal, sd 0.7 | 0, and 1 bit lost | 13 to 24 | −43.0 dB | 22.7 / 33.1 dB |
| nominal, impulses 3 V at 517 a second | 15, and 12 bits lost | 11 to 30 | −42.7 dB | 9.9 / 32.9 dB |

The noise source is not seeded, so a rerun moves the noisy rows: two earlier
runs at sd 0.7 lost no bits and scored 25.2 and 27.6 dB.

**The receiver is the repository's receiver.** On the slicer output the circuit
itself produced, `fast.mono_decode` and the circuit agree strobe for strobe in
every run up to sd 1.0 and under impulses. At 2 V on the slider, 7 strobes of
6 188 differ (see "simulator settings"). The input filter matches the same two
RC sections in Python to numerical precision.

**The decoder follows the clock it is given.** With every bit lasting as long
as the recovered clock made it, the decoder's integrator matches `cvsd.decode`
given those same intervals to −43 dB, clean or noisy.

**Clock jitter costs audio before it costs bits.** At sd 0.4, the documents'
design limit, the line made no errors and lost no bits, but the recovered
clock's period ranged over 14–18 steps of a nominal 16 and the tone's SINAD
fell from 33.4 to 27.8 dB. The analog integrator's step is `Iabc` × the bit's
duration, so a transition-timed clock puts the line's jitter straight into the
step size. This is the effect `cvsd.py`'s `dt` argument exists to model, and the
decoder column shows the model reproduces it. These are 24 ms runs on a 1 kHz
tone, not speech, and the jitter here is quantised to a sixteenth of a bit. The
trunk's receive clock is divided from the same strobes.

**A dead pair still produces bits.** With the level at 0 and sd 0.10 of noise,
`CD` was high 68 % of the time and the receiver put out 1 263 strobes in 50 ms.
That is `mf8-spec.md` §13's case for a mandatory squelch. The prototype has
none: `CD` is brought out and drives nothing.

**Two changes to `circuit-review.md` §3 came out of building it:**

- *`MID` needs no gate.* §3 has `MID ← '123 Q · /MID` through a quarter of a
  '08. A JK does that itself with J = the classifier's Q and K = 1, and `LONG` is
  the same part wired as a D. So one 74HC109 (J = /K = expired; J = not expired,
  /K = ground) replaces the '74 and the AND. The gate is also a hazard. The
  classifier is retriggered when the dead time ends, and a transition accepted
  just after that reads the classifier through the gate's delay. Here, where a
  gate costs a whole time step, that roughly doubled the error count until the
  gate went. On a board the window is tens of nanoseconds, but it is the same
  window.
- *An edge-triggered decoder needs no `W`.* `RXC = NOR(DT, MID)` rises when the
  dead time ends, iff that transition completed a bit, and falls at the next
  accepted transition. §3's `W` pulse (the other half of the '221) is for the
  trunk card's '259, a transparent latch. §3's own caveat was visible here until
  `W` went: a transition four steps after a long gap rewrote `LONG` in the step
  the pulse read it.

## Simulator settings, not circuit choices

Keep these if you edit a circuit. Each fixed a measured error:

- **16 time steps per bit** (976.6 ns). At 8 the encoder's decisions drifted from
  the model's and cost several dB at −20 dB (`engine_minus20_8steps` in the log);
  32 agreed with 16.
- **Every chip takes exactly one time step**, 1 µs here against 25 ns on a
  board: CircuitJS reads a chip's inputs once per step. So the receiver's timers
  are whole steps: dead time 3, classifier 9 from its end. A transition under
  4 steps (0.25 cell) after the last accepted one is ignored, and a gap of 13 or
  more (0.78 cell) is a 1. Those are `fast.mono_decode`'s `dead=0.25` and its
  0.75 threshold on this grid. `mf8-spec.md` §9.7 has the real values.
- **The transition detector's RC is 1.5 time steps**, not 100 ns, so its pulse
  is two steps wide and the '221 sees it. A slicer glitch one step wide therefore
  makes one pulse where `fast.mono_decode` counts two transitions.
- **A 1 ns propagation delay on every gate.** At zero delay CircuitJS moves a
  change through a gate only as far as its solver iterates within the step.
- **Clock edges half a time step off the grid**, so rounding in the simulator's
  time cannot move an edge; and two clock sources in `cvsd_engine.txt`, not an
  inverter, whose output edge wandered by a step.

## Not modelled

- **The pair itself.** `LINE` is a level, two noise sources and the receiver's
  filter. There is no cable response, transformer, driver slew or 75176.
- **Squelch and mute**, as above.
- **Offsets.** The op-amps and the comparator are ideal. Under the current law
  the `Iabc` source's control voltage at `I_min` is 98 mV (`mf8-spec.md` §12.1),
  so 3 mV of offset is 3 % of `I_min`.
- **74HC timing**, apart from the one-step delays above; **ripple on `V_A`**;
  **temperature**. The PNP's β is fixed at 100.
- **Listening.** One second of audio through `cvsd_link.txt` is about 40
  minutes. For listening use `mf8_render.py`.

`python3 sim/falstad_cvsd.py` rebuilds all three files from the law and overwrites
them, so save edited versions under another name.
