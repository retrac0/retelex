# The MF2 repeater — a comparator and a driver

A biphase repeater does not reclock. It slices the received waveform back to two
levels and re-launches it, and that is the whole of it: **no framer, no
classifier, no encoder, no counter, no crystal, and no timing element anywhere in
the hut.** Nothing to drift, nothing to set per rate but one filter corner, and
no clock to slip against.

`line-codes.md` §2.2 already stated the rule — "Repeaters are unaffected; they
slice and re-drive and never see the frame" — and on this code that is literally
the circuit.

> **Status: proposed circuit, measured span.** The section length and the hop
> limit are measured: `sim/mf2_repeater.log`. Nothing here has been drawn or
> built, the power budget is arithmetic off `subscriber-adapter.md`'s 84 Ω/km,
> and every package count is a count of an undrawn schematic.

Parent: [`spec.md`](spec.md). The unit at each end is [`unit.md`](unit.md).

---

## 1. Three boards, and two of them are the terminal's

Name the pairs by the direction they carry. The west side receives the eastbound
pair and transmits the westbound one; the east side is the other way round. That
is exactly one MF2-A's worth of line interface per side:

```
  eastbound ══▶ RX ┐                                    ┌ TX ══▶ eastbound
                   │  MF2-A ══ G ══ MF2-R ══ G ══ MF2-A │
  westbound ◀══ TX ┘   west                        east └ RX ◀══ westbound
```

The two MF2-A are **not mirror variants**: the west side does what the *east
terminal's* MF2-A does and the east side what the *west terminal's* does. One
board, wired one way at each end, and the four-wire cross stays in the plant
where it already is.

| board | population | fitted | ≈ packages |
|---|---|---|---|
| **MF2-A**, terminal | full | front end, §9.4 classifier, §9.2 encoder, 75176, magnetics, protection | 6–8 + 2 xfmr |
| **MF2-A**, repeater | **reduced** | front end and 75176 only — **classifier and encoder unpopulated** | **≈ 2** + 2 xfmr |
| **MF2-R** | — | cross-connect, squelch, loopback, the power population | **≈ 2** + regulator |

**A repeater is about six packages and four transformers**, against a terminal's
twenty-odd. And because nothing in it knows the bit rate except the input filter
corner, **the same repeater serves MF8** at the Q2 plug — it is a family part,
not an MF2 part.

### 1.1 The reduced population, in two links

MF2-A is one board. The repeater population leaves two footprints empty and
closes two links:

| link | terminal | repeater |
|---|---|---|
| `RX SOURCE` | comparator → §9.4 classifier → `RX_BIT`/`RX_STB` on P | comparator → **`SLICED` on G** |
| `TX SOURCE` | `TX_BIT` on P → §9.2 encoder → 75176 | **`DRIVE` on G** → 75176 |

Pass header **P** is unpopulated on a repeater; regen link **G** is unpopulated
on a terminal. Neither board type can be mis-stuffed into the other's role
without leaving a connector unmated.

---

## 2. Regen link G — MF2-A ⇄ MF2-R

2 × 5, odd signal and even ground, one per side, keyed. Directions are signal
flow.

| pin | | pin | |
|---|---|---|---|
| 1 | `SLICED` — 512 kBaud two-level, A → R | 2 | `GND` |
| 3 | `DRIVE` — 512 kBaud two-level, R → A | 4 | `GND` |
| 5 | `/CD` — level, A → R | 6 | `GND` |
| 7 | `SQUELCH` — level, R → A | 8 | `GND` |
| 9 | `+5 V` | 10 | key |

`SLICED` is the comparator's output and `DRIVE` is what the 75176 transmits.
Both are the line waveform, not a decoded bit: **there is no bit in a repeater**.

## 3. MF2-R — what is left once reclocking is gone

| function | part | rule |
|---|---|---|
| cross-connect and loopback | ½ 74HC157 a direction | `DRIVE[west] = LOOP ? SLICED[west] : SLICED[east]`, and the mirror |
| squelch on loss of carrier | ¼ 74HC00 | `SQUELCH[east] = /CD[west]`, and the mirror (§4) |
| lamps | ¼ 74HC244 | `CD` a direction, `LOOP` |
| power | the §6 population | line-fed shunt regulator, or a local brick |

No crystal, no counter, no flip-flop in the signal path. `DRIVE` is a
combinational function of `SLICED`, which is why nothing here can introduce a
slip.

---

## 4. Failure behaviour

**Loss of carrier propagates by squelch, not by a pattern.** When one direction's
input dies, the *other* board's driver is squelched, so the far terminal sees no
carrier, forces LOF and mutes — `spec.md` §13's squelch, reached deterministically
across a repeatered span. `mf8-spec.md` §13's "Squelch is mandatory, not
optional", and its measurement of what an unsquelched CVSD card does on a dead
pair — **+24.1 dB rms, +47.7 dB peak** relative to normal speech — apply at every
hut.

| fault | west terminal | east terminal | repeaters |
|---|---|---|---|
| eastbound cable cut in section *j* | `CD` on, `LOCK` on | `CD` **off**, LOF, `MUTE` | ≥ *j*: west `CD` off, east driver squelched |
| a repeater unpowered | `CD` off, LOF | `CD` off, LOF | dark |
| both directions cut | `CD` off, LOF | `CD` off, LOF | dark |

An alarm indication signal — a defined pattern sent onward instead of silence, so
the far end can tell "upstream is alive but deaf" from "the cable is cut" — is
**not in mk1**. It would need a generator and a mux in the hut, which is exactly
the timing element this design is built to avoid. If it is ever wanted, the
pattern is `1010`, because the guard at S states 0 and 4 exists precisely to
reject a period-2 lane (`spec.md` §3.2) and it is the family's own `FILL`.

---

## 5. Section length — measured, and it is the whole design

The repeater restores **amplitude completely and edge timing not at all**. The
comparator fires where the sloped, dispersed edge crosses its threshold, and that
displacement is re-launched as a real edge for the next section to add to. The
budget is the §9.4 classifier's ±13 % threshold tolerance — a peak-to-peak
allowance of about 26 % of a cell, **1 016 ns** at MF2's 3 906 ns cell.

`sim/mf2_repeater.log`, 1 s × 3 seeds, quiet:

| section | displacement a section | repeaters that decode | total span |
|---|---|---|---|
| **1.0 km** | **~0 %** | **24** | **25 km** |
| 1.5 km | 6.2 % | 3 | 6.0 km |
| 2.0 km | ~19 % | 1 | 4.0 km |

**The non-linearity is the result.** Halving the section from 2.0 km to 1.0 km
does not double the span; it multiplies it by six. At 1.5 km the chain crosses
the ±13 % window between 3 and 4 repeaters and dies exactly there — the model
landing on the documented tolerance. At 1.0 km it spends nothing measurable until
about 24 huts.

**So the section is 1 km**, and it closes three constraints at once:

- **Signal** — 24 huts, 25 km, before displacement closes the window.
- **Amplitude** — 1 km is 10.0 dB in differential Manchester's band (measured
  law: 17.0 dB at 1.7 km, `sim/mf2_span.log`). A 5 V 75176 launching ~2.7 V
  differential leaves ~0.85 V at a 50 mV comparator — **5.8 % hysteresis**,
  inside `mf8-spec.md` §9.3's "specify ≤ 10 %". **No preamp, no equaliser, no HV
  bridge.**
- **Power** — §6.

### 5.1 The displacement is a bias, and that is the design lever

It accumulates linearly, not as a random walk: each comparator fires late or
early on the *same side* every time, and the next section re-launches that as a
real edge. So the lever is **where the slicing level sits — DC restore and
threshold centring — not gain, and not more sections.** At 1.5 km and above that
lever is what would buy hops. At 1 km it is not needed, which is the cheaper
answer and the reason the section length is fixed first.

Two constraints on the front end follow from `line-codes.md` §4:

- the AC-coupling corner must stay **well below 128 kHz**, MF2's spectral region.
  A 120 kHz high pass cuts differential Manchester's break rate 2.5× and is free,
  which is why it is worth choosing deliberately rather than letting leakage
  inductance choose it;
- the comparator's hysteresis must be **tight**, not loose: under impulse,
  hysteresis moves the threshold the wrong way (bits lost go 13–23 at h = 0.02 to
  77–85 at h = 0.20).

---

## 6. Power

A repeater is two 75176 driving continuously — differential Manchester has no
space level — plus two front ends:

| | |
|---|---|
| two drivers, ~25 mA from 5 V each | 0.25 W |
| comparators, bias, lamps | ~0.15 W |
| **a repeater** | **≈ 0.4 W** |

### 6.1 Line-fed — the default

DC out on one pair's transformer centre taps and back on the other's, repeaters
in series on the loop. The feed is common mode, the ampere-turns cancel, and the
56 V TVS is tip–ring so it never sees it — which is the entire point of injecting
at the centre taps, and why `mf8-spec.md` §9.3 says to **specify the tap now**
because "retrofitting means a new transformer".

24 AWG is **84 Ω/km** of simplex loop (`subscriber-adapter.md`: 84 Ω/km a
conductor, two in parallel a leg). For *N* repeaters the feed is `N·P/I + I·R`,
minimised at `I = √(N·P/R)`, where exactly half the voltage is line loss:

| repeaters | span | loop R | best I | feed, one end | **split-fed, per end** |
|---|---|---|---|---|---|
| 3 | 4 km | 336 Ω | 60 mA | 40 V | **20 V** |
| **6** | **7 km** | 588 Ω | 64 mA | 75 V | **38 V** |
| 10 | 11 km | 924 Ω | 66 mA | 122 V | 61 V |
| 24 | 25 km | 2 100 Ω | 68 mA | 284 V | 142 V |

**Fed from both ends to a mid-span meet — the classic practice, and free — the
unit's own `−48 V` rail runs a 7 km span with six huts.** No mains in the field,
no converter, no new rail; `unit.md` §6 adds a constant-current source off the
existing rail and nothing else.

**Which limit binds is the useful part.** The signal carries 24 huts and 25 km;
the feed runs out at about six on `−48 V` and ten on an 80 V converter. **The
span is power-limited, not signal-limited**, which is a much better place to be:
it is solved with a converter rather than with a redesign.

### 6.2 Brick-fed

A local 15–18 V supply per hut, same intake as `mf8-psu.md` §1. Simpler
electrically and unbounded in hop count, but it needs mains at every hut, which a
buried span usually does not have. It is the population for a repeater in a
building.

---

## 7. Protection and housing

| | |
|---|---|
| per conductor | gas tube to ground, series PTC, then the bidirectional TVS tip–ring |
| **gas tube sparkover** | must exceed the maximum feed voltage with margin — a 90 V tube at a 38 V split feed, higher for a converter feed. `mf8-spec.md` §9.3's "the TVS must clamp above the eventual 48 V feed voltage" becomes a real number here |
| front end | series R into clamps at the logic rails |
| transformer | winding-to-winding isolation sized for the feed, not for the signal |
| housing | one sealed box, three 100 × 100 boards on the same 0.4 inch spacers, glands for two cables, no connector outside |
| earth | one point, the gas tube common. `−48 RET` and `RING RET` do not exist at a repeater |

---

## 8. Fault location

mk1 is deliberate about this: **a three-position plug on the housing —
NORMAL / LOOP WEST / LOOP EAST — and nothing in band.** The `'157` of §3 is the
whole mechanism.

From one end, the failure *direction* is already known without visiting anything:
a terminal that has `CD` and `LOCK` with the far end dark is upstream of the
break, and a terminal with `CD` off is downstream of it. What one end cannot do
is say *which section*. Walking the span does.

**And it needs no new instrument.** STU-1 (`common/stu-1.md`) is two
`mf8-spec.md` §9.4 front ends with the mandatory violation term, a LEVEL meter, a
0–60 V phantom voltmeter and a violation bar — and MF2's PHY *is* §9.4. The set
reads an MF2 section with a **Q3 rate plug** instead of its 64 kbps one:

| the plug's five components | STU-1 at 64 kbps | **at MF2** |
|---|---|---|
| filter corner | 128 kHz | **512 kHz** |
| classifier, 0.75 cell | 11 719 ns | **2 930 ns** |
| dead time, 0.2 cell | 3 125 ns | **781 ns** |
| carrier timeout | 31.3 µs | **7.8 µs** |
| violation gap, 1.25 cell | 19 531 ns | **4 883 ns** |

Its violation term is the §9.4 biphase one — `LONG · MID` at an accepted edge,
plus a gap over 1.25 cells — and **not** an AMI bipolar violation, so it
transfers to this code unchanged. Its 0–60 V phantom voltmeter also reads the
§6.1 simplex feed directly, which is the other thing a lineman wants to know at a
hut.

An addressed in-band loop-up would remove the walk, and it is not in mk1 because
it needs a burst detector and an address comparator in every hut — three
packages and a plug field to save a walk on a span that is at most ten huts long.
**If the span ever grows past that, this is the first thing to add.**

---

## 9. Not measured, and open

- **The circuit.** Nothing drawn, nothing on a bench. The comparator, the front
  end, the transformer and the 75176 are all `mf8-spec.md` §9's, which §15 marks
  as never measured on MF8 either. `spice/dm/` is where that starts.
- **Every power figure in §6.** Arithmetic from the driver's rated current and
  `subscriber-adapter.md`'s 84 Ω/km. No bench, no spice, no meter.
- **The measured span numbers carry two optimistic model caveats**, both stated
  in `sim/mf2_repeater.log`'s header: `phy.pair_24awg` is a **zero-phase** filter,
  so it models amplitude tilt and not group delay — real dispersion is worse — and
  the impulse rows elsewhere inject after the AGC. The hop *ranking* across
  section lengths is robust; the kilometres are not bench numbers.
- **Impulse on a repeatered span.** `sim/mf2_repeater.log` is quiet-line only.
  `sim/mf2_span.log` measures that differential Manchester takes ~42 LOF/s at 40
  impulses/s against AMI's ~7–8, **flat with distance** — so a chain does not make
  impulse worse per section, but nothing has measured what it does end to end.
- **DC restore** (§5.1) — the one circuit lever that would extend the chain, and
  it is not designed.
- **Thermal and sealing** at 0.4 W in a sealed box: expected to be trivial and
  not calculated.
- **AIS** (§4) — deliberately absent; recorded so the decision is visible.
