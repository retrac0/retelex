# STU-1 — mk1 subscriber test unit

`su-1.md` is a telephone that lives on a subscriber line. `pulse-gen.md` is a card
that seizes and dials with nothing in the ear. **This is the instrument in
between**: a set a lineman clips onto one subscriber line — both pairs at once —
that names the fault instead of showing a waveform. Two complete `mf8-spec.md`
§9.4 front ends at the §9.7 64 kbps plug, one per direction, feed a two-column
lamp field read as (downstream state × upstream state), a violation counter, a
level meter and a phantom voltmeter. It carries `su-1.md` §6.3's SU-A verbatim,
so it can also answer, talk and dial.

> **Status: proposed.** Nothing here is newly measured. Everything carried over
> is a committed run elsewhere: the detector thresholds, the pattern densities,
> the dead-pair and dial-pulse tables from `sim/subline.py` / `sim/subline.log`
> (`subscriber-line.md` §2, §3.1, §5); the register windows from
> `exchange/register.md` §3.2 and the same log; the squelch figures from
> `mf8-spec.md` §13; the ring cadence from `common/channel-cards.md` §5; the
> impulse falloff from `sim/impulse_sweep.log`. **Three numbers in this document
> are arithmetic and are marked in place**: the bridging tap's insertion loss and
> its droop (§2.2), the power budget (§8) and the package count (§12). The
> LM339 common-mode limit in §5.2 is a data-sheet figure, not a repository
> measurement. `mf8-spec.md` §15 lists the whole physical layer as inherited and
> not re-measured, and `sim/subline.log` — the only 64 kbps run in the tree — has
> no attenuation sweep in it, so there is no measured amplitude ladder at this
> rate anywhere. Nothing has been drawn, and nothing has been on a bench.

---

## 1. What it is

| | |
|---|---|
| **Clips onto** | one subscriber line, both pairs, four clips, plus the two transformer centre taps for the phantom meter |
| **Receives** | two independent `mf8-spec.md` §9.4 front ends at the §9.7 **64 kbps** plug — filter 128 kHz, classifier 11 719 ns, dead time 3 125 ns, carrier timeout 31.3 µs — each with the mandatory violation term |
| **Transmits** | only through the **ST-B** break adapter, which physically opens the pair. Never while bridged |
| **Reads out** | 22 lamps in two columns, a 0–2 V LEVEL meter switched by direction, a 0–60 V phantom voltmeter, a log2 violation bar |
| **Timing** | loop-timed off the recovered §9.4 strobe. **No crystal**, as `su-1.md` §5 |
| **Power** | four AA cells. **Never the phantom** |
| **Boards** | five 100 × 100 mm at 0.4″ (10.16 mm), **≈ 61 packages + 2 transistors** (§12) |
| **Audio** | `su-1.md` §6.3's SU-A, unchanged, as the third population of header **S** |

**The lamp field is the whole value, and it is why there are two front ends.** A
subscriber line is two one-way pairs, and almost every fault in §11 is named by
the *combination* of what the two pairs are doing — downstream alive with
upstream dead is a starved phone; both dark with phantom volts present is a
broken signal path on an unbroken DC path. One front end fills one column and
leaves the other blank, which names nothing. The second front end costs
13 packages and it buys the table.

---

## 2. The interface law — what the set may put on a pair

Everything in this section is a constraint the circuit had to be built around,
not a feature.

### 2.1 The alphabet

`subscriber-line.md` §2. Every held pattern on this line is signalling:

```
 upstream    1100 repeating (bit clock ÷ 4)  =  on-hook, or a dial break
             CVSD                            =  off-hook
             nothing                         =  dead or unpowered phone

 downstream  1010 (bit clock ÷ 2)            =  on-hook idle, and MUTE
             all zeros                       =  RINGING NOW
             the trunk's C bit               =  a call
```

**Three rules follow, and the set is built so it cannot break them.**

- **No sustained zeros, ever.** Zeros ring a subscriber. `subscriber-line.md` §2
  chose them precisely because a dead pair cannot make them — measured ones
  density on a dead pair never below **0.64** in any condition. The set contains
  no source of sustained zeros at all: §7.1's transmit mux has three inputs
  (÷2, ÷4, `BIT_ENC`) and **no hold node exists anywhere in the set**. That is a
  construction, not a discipline, and it is written here so a later revision does
  not add one by habit.
- **No held level.** Switching mid-word from speech to a held level slams the far
  CVSD integrator to its rail, **+33.6 dB above the speech peak**; `1100` costs a
  +2.0 dB transient and then sits −66.5 dB below speech rms
  (`subscriber-line.md` §2 — and that document flags those three figures as
  still from a scratch script, so they are quoted here as it quotes them).
- **The transmit interlock is mechanical.** The 75176 driver half's supply
  arrives through a link that exists **only inside the ST-B adapter's shell**,
  and the MODE wafer air-gaps the driver enable in every listening position. An
  unpowered, mis-powered or browned-out set is an open circuit toward the line.

### 2.2 Bridge or terminate, and what a bridge actually costs

`mf8-spec.md` §9.3 states the rule flatly: the termination is *"the pair's
characteristic impedance, 100–135 Ω, on the line side of the comparator. A
receiver must never look like a bridged tap."* A butt set exists to bridge, so
this has to be answered rather than quoted.

**The flat insertion loss is negligible and is not the constraint.** With the
termination switched out, the tap presents the transformer's magnetizing branch
in parallel with the §9.5 input filter, the 75176's receiver input and §9.3's
mandatory TVS junction capacitance. At the bottom of the band — 32 kHz, a run of
ones at 64 kbps — a 33 mH magnetizing branch is 6.6 kΩ; the parallel total with a
1 kΩ first filter section, a 12 kΩ unit load and ~300 pF of TVS is of order 1.4 kΩ
at 64 kHz. Against §9.3's 100 Ω source (two ~50 Ω resistors) into a 120 Ω pair
that is **about 0.1 to 0.35 dB, with roughly 0.25 dB of tilt across the band**.
A tap would have to present **54.5 Ω** to cost 6 dB. The 1.5 m clip cord is
7.6 ns one way, ~15 ns round trip, against a 15 625 ns cell and §9.7's 3 125 ns
dead time — the tap is lumped, not a transmission line. *All arithmetic; the TVS
and filter values are types and corners in §9.3/§9.5, not part numbers.*

**The constraint is droop, and it nearly bit.** §9.3: *"Running disparity is
bounded at ±1 cell and under 5 % droop needs `L/R > 20 × cell`; 33 mH covers the
whole family down to the 64 kbps line rate (arithmetic, not simulated)."* At
64 kbps, 20 cells is 312.5 µs, so L ≥ **31.25 mH at 100 Ω, 37.5 mH at 120 Ω,
42.19 mH at 135 Ω** — §9.3's own 33 mH satisfies §9.3's own rule only at the
bottom of §9.3's own stated impedance range. Clip a second 33 mH magnetizing
path across the span and the two sit in parallel: L_eff = 16.5 mH, L/R = 165 µs,
**10.6 cells against the required 20**, 4.73 % droop per cell rising to 9.47 %
at 100 Ω, against §9.4's *"hysteresis ≤ 10 % of received"*. A bridge equal to the
line transformer takes the span out of the transformer spec written for it.

> **Specify: STU-1's line transformers are 1:1, centre-tapped, ≥ 330 mH** — ten
> times the line card's ≥ 33 mH. In parallel with a nominal 33 mH line
> transformer that gives L_eff = 30 mH, 19.2 cells, 5.21 % per cell: inside the
> rule. ≥ 590 mH would clear it outright at 100 Ω. The same transformer serves
> TERM, because §9.3's floor is a "≥".

**The termination sits on its own wafer pole** and is OUT in WATCH, IN in TERM.
A TERM-IN lamp is on the panel, because terminating a pair that still has its own
receiver at the far end is a fault the set can commit silently.

**What the set cannot do is adjudicate its own bridge.** The LEVEL meter reads
the voltage at the tap *with the tap connected*, which is within a few tenths of
a dB the voltage the far receiver now sees; one reading cannot separate "the span
already arrived low" from "the bridge cost something". Worse, droop is a waveform
shape and an envelope detector cannot see it. **The lid says: bridging loss
≈ 0.3 dB by arithmetic; bridge transformer ≥ 10× the line transformer; droop
unmeasured; the bench check is a before/after level at the FAR receiver.**

**And WATCH has a stated condition.** It is defensible where the span's
pre-bridge amplitude is at or better than 0.5× — §9.3's *"specify ≤ 10 %, which
is 0.5 V for 50 mV"*. It is **not** enough to be inside §9.4's 20 % single-span
maximum: `subscriber-line.md` §1 runs this line at twice the 256 kbps reference
reach, and `frame-rate.md` §3 puts that reference at amplitude 0.251 / "20 % —
the single-span limit", so a maximum-reach subscriber pair is sitting on the
0.25× row before anything is clipped to it.

**Two citation corrections, because this design nearly leaned on them.**
`line-codes.md` §3's attenuation ladder is **512 kbps on one 1.8 MHz cable**, has
no dB column, and its 0.12× row reads **237 LOF, 69.53 % down** (its own
committed run, `sim/linecodes.log`:191, reads 434 LOF / 53.48 %). The figures
"431 LOF, 55.33 % down in 1 s" and "+0.00 dB end to end" belong to
`mf8-spec.md` §7.2 / `sim/mf8_line.log`:70 — a different battery, also at
512 kbps. **There is no measured attenuation ladder at 64 kbps anywhere**:
`sim/subline.log` sweeps Gaussian sd and impulse rate only. §3's mechanism
(hysteresis as a fraction of received amplitude) is rate-independent so the
transfer is defensible, but it is a transfer and the lid says so.

### 2.3 What was rejected

| | why |
|---|---|
| Transmitting while bridged | two 75176 drivers on one upstream pair. Nothing in the tree specifies it and the subscriber's own SU-D is already driving. Architectural, not a mk1 omission |
| Taking phantom power | `subscriber-adapter.md` §4 budgets **40 mA / 1.92 W total** for the phone, no current-sharing scheme is specified anywhere, and a set that dies on a dead pair is useless on the commonest job. The phantom is **read, never taken** |
| Keying the carrier off to trace a pair | rejected in `subscriber-line.md` §6: a phone with no downstream has no clock, and the absence is indistinguishable from a cut |
| A channel-socket pigtail | the connector family is unchosen (`common-cards.md` §7.1) and the MF8 stack's header C fanning is deferred (`mf8-trunk.md` §3). Anything built today is scrap when the family is picked |
| A framer and a LOCK lamp | `subscriber-line.md` §1: "There is no frame." A LOCK lamp would be dark for ever |
| DTMF | `su-1.md` §3 — every key is a pulse count. DTMF passes the codec (measured usable from −25 dB to +6 dB of nominal, `subscriber-line.md` §5) but there is no DTMF receiver on the line, only a proposed one in the register (`register.md` §7) |

---

## 3. Five boards

```
            ┌──────────────────────────────────────┐
  panel ──► │ ST-P  regs, 22 lamps, 2 meters, BATT │
            └──────┬──────────────────────┬────────┘
                header L (2×13)        header T (2×16, bussed)
            ┌──────┴──────────────────────┴────────┐
            │ ST-K  dialler, 16 keys                │
            ├───────────────────────────────────────┤
            │ ST-L  detectors, patterns, counters,   │──┐
            │       encoder, squelch, lamp buffers   │  │ header S (2×12)
            ├───────────────────────────────────────┤  │
            │ ST-D  magnetics, protection, both      │  │
            │       §9.4–§9.6 front ends, rate plugs │  │
            └───────────────────────────────────────┘  │
                          │                            │
                 4 clips + 2 centre taps      ┌─────────┴──────────┐
                                              │ ST-A  SU-A verbatim│
                                              └────────────────────┘
```

| board | role | packages |
|---|---|---|
| **ST-D** | line: 2 transformers, protection on four conductors, both §9.4 front ends, the two rate plugs, LEVEL peak detectors | 15 |
| **ST-L** | logic: density detectors, lamp decode, TX mux, §9.2 encoder, dividers, violation counter, squelch, lamp buffers; presents header **S** | 18 |
| **ST-K** | `pulse-gen.md` §5's dialler entire, 16 Autovon keys | 11 |
| **ST-P** | panel: three regulators, 22 lamps, LEVEL and PHANTOM meters, battery-low | 4 |
| **ST-A** | `su-1.md` §6.3's SU-A + one mic gain stage | 13 + 2 transistors |

**Why the front ends stay with the magnetics and the switchers do not.**
`mf8-trunk.md` §1 already says one 100 × 100 cannot hold a framer, two demuxes
and *"two line transformers with creepage beside the classifier"*, which is why
Trunk-A exists. STU-1 has no framer, but it has twice the protection (four
conductors, not two). The §9.7 rate plug is **one plug of five components** —
filter corner, classifier, dead time, carrier timeout, and this set's violation
gap — so the whole §9.4–§9.6 chain must sit on one board or the plug is split
across a connector. It sits on ST-D. The three switchers go to ST-P, at the
other end of the stack from a comparator whose hysteresis is fixed at ~50 mV and
which must resolve 0.5 V.

### 3.1 Header **T** — the set's own bus

Keyed 2×16 0.1″, bussed through ST-D / ST-L / ST-K / ST-P. Names and directions
from **ST-L's** view.

| pin | name | dir | |
|---|---|---|---|
| 1, 2 | `GND` | — | |
| 3 | `+5 V` | in | |
| 4 | `+12 V` | in | |
| 5 | `−12 V` | in | |
| 6 | `GND` | — | |
| 7 | `DN_Q` | in | recovered bit, downstream |
| 8 | `DN_STB` | in | accepted-transition strobe, downstream |
| 9 | `DN_VIOL` | in | violation, 250 µs hold |
| 10 | `/DN_CD` | in | low = carrier |
| 11 | `GND` | — | |
| 12 | `UP_Q` | in | |
| 13 | `UP_STB` | in | |
| 14 | `UP_VIOL` | in | |
| 15 | `/UP_CD` | in | |
| 16 | `GND` | — | |
| 17 | `LINE_HB` | in | 128 kHz recovered half-bit, downstream |
| 18 | `TX_LINE` | out | encoded line waveform → 75176 `D` |
| 19 | `/TX_EN` | out | driver enable. The driver's **supply** link is in ST-B |
| 20 | `GND` | — | |
| 21 | `DN_LEVEL` | in | analog DC, peak at the comparator input |
| 22 | `UP_LEVEL` | in | analog DC |
| 23 | `GND` | — | analog return |
| 24 | `PHANTOM` | in | divided phantom sense |
| 25–27 | `MODE[2:0]` | in | wafer |
| 28 | `DIR` | in | 0 = downstream, 1 = upstream |
| 29 | `TERM` | in | termination wafer pole, for the TERM-IN lamp |
| 30 | `TICK` | out | 1 kHz to ST-K |
| 31 | `BREAK` | in | from ST-K's dialler |
| 32 | `GND` | — | |

`DN_LEVEL` / `UP_LEVEL` / `PHANTOM` are analog about ground; everything else is
0 / +5 V HC. GND is repeated for the same reason `su-1.md` §6.1 repeats it: a
clock edge and an analog sense never share a return pin.

**Header L** is 2×13 to ST-P: 22 lamp lines and four grounds, not alternating.
The lamps are 2 mA DC levels, not edges; the odd-signal/even-ground idiom of
`fabric.md` §5.2's commons shell is for clocks.

**Header S** is `su-1.md` §6.1 unchanged, pin for pin, presented by ST-L. ST-A is
the **third population of S** alongside SU-A and SDU-1 — not a second layer
stacked on one (`su-1.md` §6.4).

---

## 4. ST-D — the two front ends

One direction; the other is identical, with its own rate plug.

```
  pair ─┬─ gas tube ─┬─ PTC ─┬────────┐
        │  to gnd    │       │     1:1, ≥ 330 mH        ┌─ 100–135 Ω
        └─ gas tube ─┴─ PTC ─┴──── centre-tapped ───────┤  (MODE wafer pole,
                                     │       │          └─  OUT in WATCH)
                              centre tap     │
                              → PHANTOM      │
                                             ▼
                              ┌─ R1 ─┬─ ½ TL072 ─┬─ R2 ─┬──► 75176 RX
                              │      C1          │      C2       │
                              │   two §9.5 sections, 128 kHz     │
                              │   BUFFERED — see 4.1             │
                              └──────────────────────────► ½ TL072 peak
                                                            → xx_LEVEL
                                                                 │
     ¼ '86 ── ½ '221 ── ½ '123 ── '74 ──────────────────────◄────┘
     edge     dead      0.75 cell  LONG / MID     §9.4 classifier
      │        3 125 ns  11 719 ns      │
      │                                 ├──► xx_Q, xx_STB
      ├──────────────── ½ '123 retrig, 2 cells,  31.3 µs ──► /xx_CD   §9.6
      ├──────────────── ½ '123 retrig, 1.25 cells, 19.53 µs ┐
      │                                                      ├ ¼'32 ─┐
      └─ LONG · MID at an accepted edge ── ¼ '08 ────────────┘       │
                                          ½ '123 retrig, 16 cells, 250 µs
                                                              └──► xx_VIOL
```

### 4.1 The §9.5 filter must be buffered, and the LEVEL tap must be after it

§9.5 gives two options: *"Buffer them, or make the second section's R at least
ten times the first so it barely loads it."* **Take the first.** Unbuffered with
R2 = 10·R1 into a 75176 receiver's 12 kΩ minimum input, the divider is
12 / (10 + 12) = 0.545 — **−5.3 dB at the slicer**. A 1.0 V line then arrives at
the comparator as 0.545 V, sitting exactly on §9.3's ≤ 10 % floor with nothing
in hand. Half a TL072 per direction removes it.

**And the LEVEL peak detector taps the comparator input, not the transformer.**
A detector ahead of the filter cannot see that loss, and would read comfortably
green while the slicer is inside its own hysteresis. The 0.5 V silk mark on the
meter only means what §9.3 says it means if the meter is looking at the same node
the comparator is.

### 4.2 The violation gap timer is 19.53 µs, and it needs its own monostable

`subscriber-line.md` §3 specifies the gap term as **"gap > 1.25 cells"**, held
16 cells. `sim/subline.py`:44 is `VLONG, HOLD = 1.25, 16` with `OS = 32`, so
`VL = 40` samples at 2.048 MHz: at the 64 kbps cell of 15 625 ns that is
**19 531 ns**, and that is the value every row of `sim/subline.log`'s HOOK and
RING tables was measured at.

**`common/channel-cards.md` §2.2 prints 14.6 µs and it is wrong twice.** 14 649 ns
is 1.25 × the §9.7 *classifier* threshold (11 719 ns), not 1.25 × the cell — a
column slip. It lands at 0.9375 cell, **976 ns below one full cell**, and
`mf8-spec.md` §9.4 says plainly *"A 1 bit has no mid-cell transition, so its gap
is a full cell"*. So a timer set there fires a violation on **every valid 1 bit**,
pins G high through the 250 µs hold and reads a talking line as permanently
on-hook. The failure does not depend on ones density: with a 16-cell hold, one 1
bit per 250 µs is enough, so speech, idle `1010` and `1100` all fail. Only
all-zeros — the ring pattern, whose gaps are all 7 813 ns — is immune.

The correct window is strictly inside (1.0, 1.5) cells = **(15 625, 23 437) ns**;
the lower bound is a valid 1 bit, the upper is the shortest gap a *deleted*
boundary transition can make. 19 531 ns is that window's exact centre, ±20.0 %.
§9.4 already warns to *"check the timer IC's own pulse-width tolerance"*: a 1 %
R and a 2 % C0G give ±3 %, leaving the HC123's own spread and its Vcc
dependence. And a noise edge accepted up to one dead time (3 125 ns) before a
true boundary stretches a legal gap to 1.2 cells = 18 750 ns, only +4.2 % under
nominal.

> **Specify: trim the gap '123 at or above 19.5 µs, never below**, and hold the
> +5 V rail tight — an HC123's pulse width tracks Vcc, and this set runs four AA
> cells from 6.0 V to 4.8 V.

**Three retriggerable halves per direction, six in the set, three packages.** One
retriggerable half has one pulse width; it cannot be simultaneously a 19.53 µs
gap timeout and a 250 µs hold, which is what `channel-cards.md` §2.2's *"the same
'123's pulse width"* asks of it. This is true at any gap value, so the count does
not depend on which figure is right.

`channel-cards.md`'s own package total is unaffected: §2.5 already bills a whole
74HC123 to the upstream receiver (§9.4 classifier half, §9.6 carrier-detect
half) and a further "½ 74HC123" to the hook detector, i.e. a second package with
one half idle. That idle half is the 250 µs hold. **≈ 10 packages stands; one
line of §2.2 does not.** `su-1.md`, `sdu-1.md` and `subscriber-adapter.md` state
no gap figure at all and are not affected.

### 4.3 ST-D parts

| block | parts |
|---|---|
| Magnetics | 2× 1:1 **≥ 330 mH**, centre-tapped, centre taps out (§2.2) |
| Protection | gas tube to ground on **all four** conductors, series PTC each, TVS clamping **above** the 48 V feed — `mf8-spec.md` §9.3 |
| Termination | 100–135 Ω per direction, on its own MODE wafer pole |
| Line transceivers | 2× 75176 — receiver half each; **one package's driver half is the TALK driver**, supply-gated through ST-B |
| §9.5 filters | 1× TL072 (one section per direction), 128 kHz corner, rate plug |
| LEVEL | 1× TL072 peak detectors; 1× LM339 (DN LOW, UP LOW at 0.5 V, 2 quarters spare) |
| Classifiers, both directions | 1× '86, 1× '221, 1× '123, 2× '74 |
| Violation and carrier | 3× 74HC123 — six halves: gap 19.53 µs ×2, hold 250 µs ×2, carrier 31.3 µs ×2 |
| Violation glue | 1× '08 (LONG·MID ×2), 1× '32 (the ORs into G ×2) |
| Rate plugs | two plug-in headers, five components each |
| | **15 packages, two transformers, four gas tubes, four PTCs, four TVS** |

**The rate plug also moves the timebase.** The TICK ÷64 and LINE ÷65536 taps on
ST-L are selected from the plug, so fitting a trunk plug does not silently make
the set's stopwatch eight times fast. The fitted plug's rate reads through a
window in the plug itself, so the panel always states the rate the set is set to
rather than the rate on the wire.

---

## 5. ST-L — the detectors and the lamp decode

### 5.1 The detector, twice, with both senses

`subscriber-line.md` §3, unchanged:

```
 X          =  Q ⊕ Q[n−2]        exchange sense      ½ '74 and ¼ '86
            =  Q                 phone sense         a wire
 violation  =  LONG · MID at an accepted edge   +   gap > 1.25 cells,  held 16 cells
 G          =  X + violation-hold + /carrier                          ¼ '32

 G ─[ RC, τ = 4 ms ]─[ ÷2 ]─┬─[ ¼ LM339, 0.85 / 0.70 ]──► 1100 present
                            └─[ ¼ LM339, ≈ 0.05      ]──► SPEECH  (§5.3)
 /G ────[ same RC ]──[ ÷2 ]──[ ¼ LM339, 0.85 / 0.70 ]──► ZEROS   = RING
```

Both functions on both directions: four density comparators plus two SPEECH
comparators, six quarters, two LM339s.

**The phone-side sense is not an inversion of the document.** `sim/subline.py`:371
is `comparator(y, HI, LO) if xor2 else comparator(1 - y, HI, LO)` with
`TAU, HI, LO = 0.004, 0.85, 0.70`, and `sim/subline.log`:68 heads that block
*"PHONE ring detector — density of Q; ringing below 0.15, released above 0.30"*.
Applying the same fixed 0.85 / 0.70 window to the **complement** of the filtered
node is assert-on-low by definition, which is exactly `subscriber-line.md` §3's
*"phone: RING when low"*. `subscriber-line.md` §2 fixes it independently — *"for
the phone it is `Q` itself, which all-zeros makes constantly 0"* — so 0.85 / 0.70
are distances to the held pattern, giving 1 − 0.85 = 0.15 and 1 − 0.70 = 0.30.
§3.1's own table then confirms it: idle `1010` or speech at **0.462 – 0.688** and
a dead pair at **0.633 – 1.000**, both with **0 false events**, which could not
have printed if the window sat at 0.70 / 0.85 on Q. Nothing built is backwards.
The only real gap is documentary: **0.15 and 0.30 appear nowhere in the tree's
prose**, only in `subline.py` and `subline.log` (§15).

### 5.2 A divider on the RC node, and why

An LM339's input common-mode range is V− to V+ − 1.5 V — 0 to 3.5 V on a +5 V
rail (data sheet; not a measurement in this repository). On a 5.00 V HC swing
the exchange sense's references are 0.85 × 5 = **4.25 V** and 0.70 × 5 =
**3.50 V**, at and above that ceiling.

> **Specify: the filtered node and its references are divided 2:1 before the
> LM339.** The thresholds become 2.125 V and 1.750 V, comfortably inside range,
> and the ratio — which is all the detector measures — is unchanged. The RC is
> unaffected: divide after it, into the comparator's high-impedance input.

The same applies to `channel-cards.md` §2.2's ¼ LM339 and no file states which
rail that card's comparator runs from (§15).

### 5.3 What the lamps can and cannot say

| lamp, per direction | asserted by | what it means |
|---|---|---|
| `CARRIER` | `/xx_CD`, §9.6, 2 cells | edges present. **Always live, straight off the cells** |
| `1100` | xor2 density > 0.85 | on-hook, or a dial break. Legal **upstream only** |
| `ZEROS` | Q density < 0.15 | ringing now. Legal **downstream only** |
| `SPEECH` | xor2 density > ≈ 0.05, ~0.5 s peak hold | real traffic on the pair |
| none of them | | idle `1010`, or a silent talker. **These are the same bits** |

**`SPEECH` is buildable and `IDLE` is not, and both are measured.**
`sim/subline.log`'s DENSITY table encodes 5 s — 320 000 bits — of digital silence
through the `mf8-spec.md` §12.1 law and reports **longest run 1 b**, Q density
0.499 – 0.501, Q ⊕ Q[n−2] 0.000 – 0.000. A run of one means strict alternation:
the quiescent encoder emits `1010` exactly, and the density band is just the
4 ms RC's own ripple on an alternation. So an abandoned loop carrying the
exchange's `1010` fill and a MUTE-silent call carrying this set's own ÷2 output
are **bit-identical**, and no circuit in the bit domain separates them. §11 keeps
both rows ambiguous and the lid says so.

But real traffic *does* separate, on a node ST-L already has. From the same log's
EXCHANGE hook detector block, xor2 density through τ = 4 ms:

| condition | speech, mean / max | idle `1010`, mean / max |
|---|---|---|
| clean | 0.138 / 0.491 | 0.000 / 0.003 |
| sd 0.8 | 0.144 / 0.518 | 0.006 / 0.109 |
| impulse 100/s | 0.151 / 0.498 | 0.014 / 0.177 |
| impulse 1000/s | 0.251 / 0.601 | 0.128 / 0.400 |

46:1 on the mean clean, about 3:1 at 100 impulses/s, merging only at 1000
impulses/s — the condition §3.1 itself says no link here survives. **One more
comparator quarter per direction at ≈ 0.05 (clean) to ≈ 0.25 (noisy), with a
~0.5 s peak hold so speech pauses do not blink it.** It is labelled `SPEECH` and
not `TRAFFIC`, because that is what it measures.

**A lag-1 detector was considered and is worse.** The same DENSITY table's
longest-run column — 44 b speech nominal, 69 b at +10 dB, **81 b** for a
3× full-scale 300 Hz tone — pulls a lag-1 density through the 4 ms RC to 0.842,
0.764 and 0.729, i.e. below a 0.85 operate and 0.03 above a 0.70 release. It
would drop out on ordinary speech and it still could not split idle from silence.

### 5.4 `SWAPPED`

Downstream can never legitimately show `1100` and upstream can never
legitimately show zeros. Either lights one `SWAPPED` lamp — **ANDed with that
column's carrier**. Ungated it is wrong twice: on a dead pair the measured ones
density is 0.633 – 1.000 and `/carrier` forces G high, so a cut pair would light
`SWAPPED` when the answer is "cut". ¼ '08 and ¼ '32.

### 5.5 ST-L parts

| block | parts |
|---|---|
| Lag-2 pairs | 2× '74 (two FFs each direction) |
| XORs | 1× '86 (DN xor2, UP xor2, 2 quarters spare) |
| Density comparators | 2× LM339 — DN xor2, DN Q, UP xor2, UP Q, DN SPEECH, UP SPEECH; 2 quarters spare. Four τ = 4 ms RCs, four 2:1 dividers (§5.2) |
| Direction mux | 1× '157 — `BIT_DEC` and `RX_CLK` from the selected direction onto **S** pins 10 and 8. This is what lets one riser hear either pair |
| TX mux | 1× '157 — inputs ÷2, ÷4, `BIT_ENC` only. **No hold node** (§2.1) |
| §9.2 encoder | 1× '74 (H phase + the toggle FF) and a gate from a spare quarter — `mf8-spec.md` §9.2, `EN = NAND(/H, bit)` |
| Dividers | 2× 74HC4040 chained. `TICK` ÷64 = 1 kHz; `LINE` ÷65536 = 0.9766 Hz. Q0 = ÷2 = `1010`, Q1 = ÷4 = `1100` — the pattern generators are divider taps, so no separate flip-flop |
| Violation counter | 1× 74HC4040, eight taps to the log2 bar, one reset key |
| Squelch and mute | 1× '32 (`/carrier` + violation-hold + mode-change), 1× '123 (mode-change one-shot), 1× 74HC4066 (the ear gate) |
| `SWAPPED`, state decode | 1× '08 |
| Lamp buffers | 3× '244 — 24 outputs, 22 used |
| | **18 packages** |

**The squelch is logic and the limiter is not.** After the reconstruction filter
there is a hard two-diode analog limiter, in series with the '4066 gate, against
`mf8-spec.md` §13's measured **+24.1 dB rms and +47.7 dB peak** on a dead pair.
A logic squelch fails silent when the logic is wrong; the limiter does not.

---

## 6. Clocking — loop-timed, no crystal

`su-1.md` §5, applied to an instrument. The §9.4 receiver recovers a bit strobe
from the downstream pair whenever the line is up — idle `1010`, ringing zeros or
speech — and that strobe is the set's only timebase.

```
 downstream §9.4 ──► recovered 128 kHz LINE_HB ──┬── ÷2 ──► 64 kHz  RX_CLK, TX_CLK
                                                 │           header S 7, 8
                                                 ├── ÷64 ──► 1 kHz  TICK  (dialler)
                                                 └── ÷65536 ► 0.9766 Hz  LINE lamp
                                                             (the stopwatch, §11)
```

**A free-run crystal population is not taken**, as `su-1.md` §5 does not take
one. The consequence is printed on the lid and it is the honest half of the
design:

| runs on the cells alone, on a dead pair | needs a recovered strobe |
|---|---|
| both `CARRIER` lamps | `TICK` and the dialler |
| both `LEVEL` readings | the ear |
| the phantom voltmeter | the `LINE` lamp |
| the `BATT` lamp | the violation counter's gate |

Those four readings are enough to name rows 1 to 5 of §11, and that is exactly
what the battery buys.

**The `LINE` lamp is the stopwatch.** `verilog/rtl/su1.v`'s `LED_DIV 65536` off
the 64 kHz strobe gives 0.9766 Hz, dark on no carrier. Counting ten blinks to
gate a violation count saves a freeze latch and a gate generator, and makes the
timebase and the health indicator the same part — so a reading taken while the
lamp stutters is visibly not a reading.

---

## 7. Transmit

### 7.1 The mux

```
 TX_LINE = §9.2 encoder ( ½ '157 select on MODE/off-normal )

    inputs:   ÷4  = 1100      on-hook, and every dial break
              ÷2  = 1010      mute, and the make under a dial
              BIT_ENC         ST-A's encoder, off-hook and unmuted

    there is no fourth input.
```

Every line of that is a `subscriber-line.md` §2 pattern or live CVSD. There is no
static source anywhere in the set to select.

### 7.2 The dialler — `pulse-gen.md` §5, unchanged

≈ 11 HC packages, on ST-K, at the keypad: TX-domain `TICK` ÷8 to 1 kHz, a '4017
decade with a ¼ '4002 NOR giving 60 ms of every 100 — **10 pps 60/40 exactly** —
two '148s encoding sixteen keys (their group-select gives the strobe free), a
½ '193 plus a flip-flop for five bits so key D can still load 16, and the
RC / ¼ '14 astable path with a ½ '123 so a tester can walk the windows
deliberately. Measured by `make pulse_gen`.

**The mute is mandatory while the dial is off normal**, so the makes carry `1010`.
`subscriber-line.md` §5 measures 10/10 pulses in all 28 cells either way, but
with the mute every break arrives **exactly 6.1 ms short** (−6.9 to −4.9 ms at
1000 impulses/s), whereas unmuted with speech under the dial the shortening
scatters 0.1 – 7.5 ms and depends on what the microphone heard. One fixed number
is a calibration; a scatter is not. The 6.16 ms monostable on `ON_HOOK`'s release
is **not** fitted: it belongs to a set that repeats pulses onward, and STU-1
dials into a register.

The windows the dialler can be walked against, from `register.md` §3.2, measured
on a clean line with idle makes:

| stress | holds at | gives way at |
|---|---|---|
| pause between two digits | 125 ms | 120 ms — read as one digit |
| a slow dial's make | 3.6 pps, 122 ms | 3.4 pps, 129 ms — splits the digit |
| one long break | 260 ms | 280 ms — CLEAR |
| one short break | 16 ms | 8–14 ms seen but short of HIT; 6 ms not seen at all |

---

## 8. Power budget

Four AA cells, 6.0 V fresh to 4.8 V end of life, into three switchers: a +5 V
boost, a +12 V boost and a −12 V inverting path. **Not one small switcher** —
ST-A's LM13700 and TL072s need both 12 V rails (`cvsd-codec.md` §5.1), and ST-D's
filter buffers and peak detectors need them too. ST-A's ±12 is gated off in the
listening positions; ST-D's is not.

| +5 V | |
|---|---|
| 2× 75176, receiver halves only | 40 mA |
| ST-D logic, 11 HC packages at 64–128 kHz | 28 mA |
| ST-L logic, 15 HC packages at ≤ 64 kHz | 20 mA |
| ST-A logic, 5 HC packages at 64 kHz | 12 mA |
| ST-K dialler, 11 HC packages at ≤ 1 kHz | 3 mA |
| 3× LM339 and the battery comparator | 3 mA |
| 22 lamps, all lit, 1k5 each | 42 mA |
| **worst case** | **148 mA** |

| ±12 V | |
|---|---|
| ST-D, 2× TL072, four sections — always | 6 mA a rail, **130 mW** |
| ST-A analog cluster, gated — LM13700, 3× TL072, LM311, ear amp | **≈ 300 mW** |

| | out | in at 80 % | from 6.0 V | from 4.8 V |
|---|---|---|---|---|
| listening, typical lamp field, ear down | 0.74 W | 0.93 W | 155 mA | 194 mA |
| **worst case, ear live, all lamps** | **1.17 W** | **1.46 W** | **244 mA** | **305 mA** |

At ~1 800 mAh usable from alkaline AA at these currents that is **about nine
hours watching and six hours talking**. *Arithmetic.* The HC figure is scaled
from `subscriber-adapter.md` §4's own "~8 HC packages at 128 kHz → ~100 mW"; the
analog cluster is that section's own ~300 mW; the lamp current is
`pcb/hookbusy/README.md`'s 1k5 ≈ 2 mA; the 80 % is `subscriber-adapter.md` §4's
figure; the cell capacity is a data-sheet class number. Nothing here is measured.

**The phantom is read, never taken.** 10 MΩ into a panel meter off the two
line-side centre taps — 4.8 µA at 48 V — **marked in VOLTS only**, against
`subscriber-adapter.md` §4's 48 / 37.9 / 31.2 V. No kilometre marks: those
figures are computed at exactly 40 mA into an 84 Ω/km loop, and a bridged
voltmeter with no current reading cannot know the far end's draw.

---

## 9. Mechanical

| | |
|---|---|
| Boards | five **100 × 100 mm**, 1.6 mm, **0.4″ (10.16 mm)** pitch — same spacer family as `cvsd-codec.md` §2, `pcb/su-1/` and `pcb/hookbusy/`. Spacers are the datum; headers float |
| Holes | four M3 clearance on the common MF8 pattern |
| Stack | 4 × 10.16 + 1.6 ≈ **42 mm** |
| Cells | 4× AA, 2 × 2, ≈ 31 × 58 × 29 mm |
| Panel | **≈ 140 × 110 mm** |
| Case | of order 150 × 120 × 75 mm with the cells |
| Handset | 4P4C (RJ9/RJ22), 600 Ω, `su-1.md` §3.1's pinout unchanged |

**STU-1 is panel-limited, not stack-limited, and it is not pocket-sized.** The
panel furniture is a 16-key pad at ~15 mm pitch (60 × 60), a 22-lamp field at the
locked 0.4″ LED pitch (≈ 31 × 82), two moving-coil meters at 45 × 45, the MODE
and DIRECTION wafers, a 4P4C, a line-out jack and a reset key — of order
9 400 mm² against 15 400 mm² of panel, **about 61 % full before bezels**. A
fourth or fifth board adds 10 mm to a stack inside a case whose depth is already
set by the cells; a bigger panel is what stops the set being carried up a pole
in one hand. This is a two-hand instrument on a neck strap, and the document says
so rather than discovering it at the pole.

---

## 10. The MODE wafer

| position | plugs into | what happens | intrusive |
|---|---|---|---|
| **WATCH** | both pairs of a live line, alongside the working phone, four clips | both front ends live, both columns driven, both LEVEL readings held, the ear on the DIRECTION wafer's choice through the squelch. The default | **bridging**, flagged unmeasured on the lid (§2.2). Termination OUT. The driver is unpowered and air-gapped, so WATCH cannot transmit |
| **TERM** | one pair, on the DIRECTION wafer, with the phone out or the pair dead | 100–135 Ω switched IN on the selected direction; the set is that pair's one receiver. Full decode into the handset with mandatory squelch. **The only position in which a level reading means what §9.3 says it means** | terminating, by design. A fault to use on a pair that still has a receiver at its far end — the position is detented and the TERM-IN lamp is lit |
| **TALK** | both pairs through **ST-B**, which physically opens the pair toward the subscriber | seize by leaving `1100`; dial on the sixteen keys at 10 pps 60/40 or walk the windows on the RC path; talk through SU-A | fully. The phone is physically out. The driver's supply link lives inside ST-B's shell, so TALK is unreachable without the adapter in hand |
| **COUNT** | either pair, bridged or terminated | the violation term — already computed in §4 and otherwise thrown into a 4 ms RC — into a '4040 and eight lamps as a **log2** bar, gated by counting blinks of the 0.9766 Hz `LINE` lamp | nothing beyond WATCH or TERM. The counter is a tap, not a load. On a dead pair it reads nothing and the `LINE` lamp is dark, which is itself the reading |
| **LEVEL** | both pairs, plus the two centre taps | LEVEL held on both directions, both LOW lamps, the phantom meter in volts | read-only. The voltmeter is 10 MΩ |

**Log2 and not a linear count**, because `sim/impulse_sweep.log` sweeps three
orders of magnitude, 0.3/s to 1000/s. Eight taps of one '4040 span 1 to 128 and
a technician reads the decade, which is the resolution the question needs.

**The line-out jack is a fixed pad from `AUDIO_RX`, ahead of every face pot**,
always live when recon is live, with no ring tone on it — `su-1.md` §3.2
verbatim. It is there so somebody else's meter can do the metrology this set
refuses to claim, and so a reading does not depend on where a knob is.

---

## 11. The fault table

Read as (downstream column × upstream column). "Standing" is where the
technician has to be for the set to say this.

| fault | what the set shows | standing |
|---|---|---|
| **Downstream pair open** — one conductor broken, or the exchange's transmitter dead | DN `CARRIER` dark, DN LEVEL zero, all DN lamps dark. UP `CARRIER` **also** dark, because the phone is loop-timed (`su-1.md` §5) and with no downstream it emits nothing at all. `LINE` dark — the set is loop-timed too. **PHANTOM still reads 31–48 V**, because both wires of a pair carry the DC together and one broken conductor need not break the DC circuit (`subscriber-line.md` §1.1). Both carriers dark with volts present is the signature | anywhere on the pair |
| **Upstream pair open or cut** | DN `CARRIER` lit, DN LEVEL normal, DN `SPEECH`. UP `CARRIER` dark, UP LEVEL zero, UP violation bar hard over. `LINE` blinking at 0.977 Hz. The set is stating what the exchange sees: **permanent on-hook**. §3.1 measures a dead pair's xor2 density at 0.757 – 1.000 over noise sd 0.01 – 1.0 with **0 false events**, and 0.867 – 1.000 at 100 impulses/s with 0 — so the far end reads this as a quiet on-hook phone, not a fault, which is exactly why somebody climbed | anywhere on the pair |
| **Both pairs cut, or the clips are on nothing** | both `CARRIER` dark, both LEVEL zero, `LINE` dark, **PHANTOM 0 V**. The meter is the only discriminator against the row above, and it runs off the cells | anywhere |
| **Phantom feed open, or the line card's 100 mA PTC tripped** | DN `CARRIER` lit and DN LEVEL normal — the exchange is still transmitting. PHANTOM at 0 V or well below `subscriber-adapter.md` §4's 31.2 V at 5 km. UP `CARRIER` dark. **Exchange alive, phone starved** | anywhere, but the meter decides |
| **Phone unpowered or dead, feed intact** | identical lamps to the row above — DN `CARRIER` and `SPEECH`, UP `CARRIER` dark — except PHANTOM reads 31–48 V. The two rows differ **in one needle** | anywhere |
| **Ringing now** | DN `CARRIER` lit, DN `ZEROS` lit in a 2 s on / 4 s off cadence (`clocks.md` §1; measured end to end at BER 3e−2 as 2.0005, 2.0005, 2.0004 s, `channel-cards.md` §5). UP `1100` lit — the phone is still sending on-hook | anywhere |
| **Permanent loop** — off-hook and abandoned | DN `SPEECH` or nothing, UP `SPEECH` or nothing, no `ZEROS`, indefinitely, LEVEL normal, violations quiet. **The set cannot tell this from a live call with both parties silent**, and the lid says so. What it can do is stop the guessing: the exchange's release detectors fire after 256 ms low and the port stays busy for up to about 0.6 s after (`fabric.md` §3.5, `marker.md` §5.2), so a loop up for minutes is not a release in progress | anywhere |
| **Trunk unlocked at the exchange, or `MUTE` asserted** — the subscriber hears silence on a call | the lamp field is **indistinguishable from a healthy quiet call**, because `MUTE` forces the downstream to `1010` and that is bit-identical to a silent talker (§5.3). The lamps cannot answer this and the set does not pretend to. **The handset does**: TERM or WATCH on the downstream pair and listen — idle and `FILL` are silence at −48.3 dB re nominal speech (`protocol.md` §4). The one row answered with an ear | at the subscriber end, on the downstream pair |
| **Marginal reach** — span loss, or a preamp footprint that should have been populated | both `CARRIER` lit, lamps correct, but LEVEL sits below the **0.5 V** mark on the offending direction and that column's `LOW` lamp is on. The threshold is not taste: §9.3 specifies ≤ 10 % hysteresis and 50 mV fixed reaches 10 % at exactly 0.5 V received | at either end, and **both**, if the bridge is under suspicion (§2.2) |
| **Impulse noise on the loop** | both `CARRIER` lit, both LEVEL normal, lamps correct — and the **violation bar climbing**. COUNT, gated by ten blinks of the `LINE` lamp, gives violations per second on real copper. The bar is labelled VIOLATIONS and **not BREAKS**: `line-codes.md` §4.1 defines a break as a bit-count slip that re-phases a frame, and `subscriber-line.md` §1 says of this line "There is no frame" | anywhere on a live pair, and for long enough — `README.md` calls this the project's one unsettled question |
| **Clips on the wrong pairs** | both `CARRIER` lit, both LEVEL normal, but the columns read impossibly: DN showing `1100`, or UP showing `ZEROS`. Either lights `SWAPPED`, ANDed with that column's carrier so a cut pair cannot false it. **Self-correcting in five seconds instead of half an hour** | at the set |
| **Tip and ring swapped within a pair** | **nothing**, and the lid says so. `line-codes.md` §2.3 measured differential Manchester bit-identical under a tip/ring swap — clean, at noise sd 0.4 and 0.6, at 100 impulses/s and at 0.25× attenuation, including while the link is making errors. Within a pair there is no polarity to get wrong | — |
| **Split pair** | both `CARRIER` lit, LEVEL depressed, violations counting — **which is exactly what plain span loss looks like**. STU-1 cannot tell them apart, and this is printed on the lid rather than buried, because an instrument should carry its own confusion matrix where the technician can read it | — |
| **Bad dialling** — worn contacts, a slow dial, cradle chatter | in WATCH on a dialling phone, UP `1100` flickers with the breaks and COUNT gives the break rate. **What mk1 has not got is a per-break timer** against `register.md` §2's 8 / 128 / 256 ms windows, so it cannot say *which* break was short. What it can do is substitute: TALK through ST-B and dial the same number at the measured 10 pps 60/40, or walk §7.2's edges on the RC path. If the set's dialling gets through and the phone's does not, the phone is the fault | at the subscriber end, with ST-B |
| **Wrong rate plug fitted** | both `CARRIER` dark or chattering while both LEVEL read normal amplitude — **signal present, nothing decoded**. The fitted plug's rate shows through a window in the plug itself, so the panel states the rate the set is set to, not the rate on the wire. §9.7's rule is on the lid: the receiver's rate must match the **far** end's transmitter, and the plug is per direction | at the set |
| **The set's own termination left IN while bridged** | `TERM-IN` lamp lit in WATCH. The far receiver now shares its load with this one and this set cannot see the consequence (§2.2) | at the set |
| **Cells flat** | `BATT` lit below ≈ 5.1 V at the cells. Below that the +5 V boost still regulates but the HC123 pulse widths are trimmed at 5.00 V, so the classifier and the 19.53 µs gap timer drift and the set may start inventing violations. **Believe the `BATT` lamp before believing the violation bar** | at the set |

---

## 12. Parts

| board | | packages |
|---|---|---|
| **ST-D** | 2× 75176, 2× TL072, 1× LM339, classifiers ('86, '221, '123, 2× '74), violation/carrier 3× '123, '08, '32 | **15** |
| **ST-L** | 3× '74, '86, 2× LM339, 2× '157, 2× '4040, 1× '4040 counter, '32, '123, '4066, '08, 3× '244 | **18** |
| **ST-K** | `pulse-gen.md` §5 entire — '393, '4017, ¼ '4002, '157, '86, 2× '74, '123, 2× '148, '193 + FF, ¼ '14 | **11** |
| **ST-P** | +5 boost, +12 boost, −12 inverter, 1× LM339 | **4** |
| **ST-A** | `cvsd-codec.md` §5.1's type-A engine (LM311, LM13700, 3× TL072, 3× '74, '86, '32) + ear amp + mic mux/gate (`su-1.md` §6.3) + one mic gain stage | **13** + 2× 2N3906 |
| | | **≈ 61 packages, 2 transistors** |

Not packages: 2 transformers ≥ 330 mH, 4 gas tubes, 4 PTCs, 4 TVS, two 100–135 Ω
terminations, two five-component rate plugs, 22 LEDs with 1k5 each, two
moving-coil meters, 16 SMD keys, a 4P4C jack, a line-out jack, two wafer
switches, a reset key, one R_set trimmer on ST-A, four AA cells.

**One trimmer in the whole set.** ST-A's R_set is factory-set against its own
C_int with an instrument and **never by ear** (`cvsd-codec.md` §5.2, §8). LEVEL
mode reads through it, which is why the field check on the audio path is dialling
the milliwatt (`extensions.md` §1) rather than turning a screw. Because bits are
switched, that tone reaches this set bit for bit however many exchanges it
crosses, so what it reads is **this set's own decoder and analog path and nothing
between**; the loopback returns the technician's own voice through his own ear
and closes the encoder's level the same way.

**Treat 61 as arithmetic.** The tree's recorded costing errors run in both
directions: commit `a0f39f2` corrected mini_marker from 673 packages to 26, a
pessimistic error from billing expanded counters and an FSM as SSI, while
`verilog/tech/hc/README.md` records a hand BOM corrected upward. `9d449f0`'s
rule — bill whole packages — is what the table above follows. No
packages-per-100 × 100 capacity is stated anywhere in the tree; the nearest data
points are `cvsd-codec.md` §2's 10-package riser and `su-1.md` §6's two boards
for a whole phone (§6.2's dialler ~11 plus §5.1's ≈ 10 + 2 gives ~36–40 over two
boards, ~18–20 a board, against STU-1's 12.2). It is a placement question and
nothing in this repository has been routed.

---

## 13. Bring-up

1. **ST-P alone.** Cells in, no other board. +5, +12, −12 into resistive loads at
   6.0 V and at 4.8 V. Ripple on +5 against the 50 mV the comparator budget lives
   on, and on ±12 against ST-A's 98 mV control voltage at I_min
   (`circuit-review.md` §2.4). Scope the switch nodes before anything sensitive
   is fitted next to them.
2. **ST-D on a bench pair, transmitter only.** ST-B fitted, TALK, ÷4 out of a
   signal generator: a 75176 through two ~50 Ω into 120 Ω, slew-limited to 150 ns
   on the rate plug. Check the slew limiting is populated — `mf8-spec.md` §9.3
   says do not skip it.
3. **ST-D receiving its own transmitter through a metre of pair.** Scope the
   comparator input for ≥ 0.5 V and the §9.5 buffer for the 128 kHz corner. Then
   the three '123 halves, on a counter: **19.5 µs and never below** (§4.2),
   250 µs, 31.3 µs, at 5.00 V and again at 4.80 V.
4. **ST-D + ST-L.** Feed `1100`, `1010`, all zeros and a CVSD recording in each
   direction. Every lamp in §5.3 in turn, then the impossible combinations, then
   `SWAPPED` with the carrier removed — it must stay dark.
5. **ST-K.** `TICK` at 1 kHz off the recovered strobe, then a break train on a
   counter: **60 ms of every 100**. All sixteen keys through the two '148s, D as
   sixteen pulses.
6. **ST-A alone on an S carrier**, before first stack-up with a live line, as
   `pcb/su-1/README.md` step 5 and `pcb/cvsd-codec/README.md` step 4 both call
   for. Loop `BIT_ENC` to `BIT_DEC`, tie the clocks, trim R_set against C_int
   with an instrument.
7. **The whole set into a bench pair against a second §9.4 front end**, then
   TERM against a real line card, then WATCH beside a working receiver — and for
   WATCH, **a level reading at the far receiver with the set off and on**, which
   is the only measurement that closes §2.2.

---

## 14. What it cannot do

- **Talk while bridged.** TALK needs ST-B, which opens the pair. Nothing in the
  tree specifies two transmitters on one upstream pair.
- **Work on a dead pair beyond four readings.** Loop-timed, no crystal: no
  downstream carrier means no strobe, no `TICK`, no dialler, no ear, no violation
  counter and a dark `LINE` lamp. What survives is §6's table.
- **Distinguish idle `1010` from a silent talker, in either direction, ever.**
  Measured identical (§5.3). This is why §11's `MUTE` row is answered with the
  handset.
- **Distinguish a split pair from plain span loss.** Both give carrier, depressed
  level and violations. On the lid.
- **Frame anything.** No framer, no LOCK lamp, no A-bit demux. On a trunk rate
  plug the set reads carrier, amplitude and violations only, and cannot name a
  channel, read an A bit or say which of six lines it is hearing.
- **Plug into a channel socket.** No slot pigtail in mk1 (§2.3).
- **Tap the Trunk-D ↔ Trunk-A pass header.** It is mated in any working shelf and
  getting at `RX_BIT` / `RX_STB` / `/CD` means unmating it, which takes the trunk
  down. A receive-only test header on Trunk-A would make this cheap and does not
  exist; that is a change to `mf8-trunk.md` §2, not a lead.
- **Read a card word, a port number, `BUSY`, or who is connected to whom.** There
  are no slot-ID pins anywhere (`mf8-backplane.md` §3, `fabric.md` §5.1), the
  word and `BUSY` reach only the marker over `PB[1:0]`, and there is no read-back
  path from a '273 (`console.md` §7.2). Those belong to the console and the lamp
  fields.
- **Write on the control bus.** `console.md` §2.2's measured naive control — 10
  answered calls down to 2, 30 of 179 marker writes unseen — is what happens to a
  second master that gets the tenure rule wrong, and §12 leaves two masters
  unarbitrated.
- **Time individual dial breaks** against `register.md` §2's 8 / 128 / 256 ms
  windows. It counts breaks and it can substitute its own measured dialling. A
  per-break window display is the obvious mk2.
- **Report dBm, kilometres, or an impulse rate.** It reads volts at the
  comparator against §9.3's 0.5 V floor (`frame-rate.md` §1 has √f ratios and no
  measured loss per km), and it reports violations per second, not impulses per
  second — `line-codes.md` §4.5's 0.77 breaks per impulse is a framed 1.024 MBaud
  statistic and does not carry to a frameless 64 kbps pair until somebody runs
  the conversion.
- **Send DTMF** (§2.3).
- **Claim any of this was measured on a bench.** Nothing in this repository has.

---

## 15. What this changes in other documents

- **`common/channel-cards.md` §2.2**, line 96. *"½ 74HC123, retriggerable,
  14.6 µs at 128 kBaud"* must read **19.5 µs**: the figure is 1.25 × the §9.7
  classifier threshold, not 1.25 × the cell, and it sits below the full-cell gap
  of a valid 1 bit. Line 97's *"the same '123's pulse width, 250 µs"* must name
  the **other half** of that package. §2.5's package total is unaffected (§4.2).
- **`common/subscriber-line.md` §3**, the diagram. The phone branch's trip points
  in Q terms exist only in `sim/subline.py`:371 and `sim/subline.log`:68. One
  line closes it: *"comparator, 0.85 / 0.70 of the distance to the held pattern —
  exchange: ON-HOOK above 0.85 of G, release below 0.70; phone: the same window
  on /G, RING below 0.15 of Q, release above 0.30."* The detector is not
  inverted and nothing built is wrong (§5.1).
- **`mf8/mf8-spec.md` §9.3**, the Transformer row. *"33 mH covers the whole
  family down to the 64 kbps line rate"* holds only at the 100 Ω end of §9.3's
  own 100–135 Ω range: the rule needs 31.25 / 37.5 / 42.19 mH at 100 / 120 /
  135 Ω, so 33 mH gives 21.1, 17.6 and 15.6 cells against the 20 it asks for.
  Arithmetic, on §9.3's own arithmetic.
- **`common/terms.md`** has no row for a lineman's test set. STU-1, ST-A / ST-D /
  ST-K / ST-L / ST-P, header **T** and the ST-B break adapter want entries, and
  the name is Joel's call.
- **`mf8/mf8-trunk.md` §2** — a receive-only test header on Trunk-A carrying
  `RX_BIT`, `RX_STB` and `/CD` would make a trunk tap cost nothing. It does not
  exist (§14).

---

## 16. Not measured

- **The bridge.** §2.2's insertion loss, tap impedance and droop are all
  arithmetic — arithmetic in the same sense `mf8-spec.md` §9.3's own transformer
  figure is, which that row labels *"arithmetic, not simulated"*. No document,
  model or `sim/` run computes a bridging tap's insertion loss, its droop or its
  effect on the eye, and §15 lists the whole physical layer as inherited. The TVS
  and filter component values behind the ≈ 1.4 kΩ estimate are types and corners,
  not part numbers. If this is wrong, **WATCH — the default position, the one a
  technician reaches for first — degrades every call it is used on.** The bench
  check is a before/after level at the far receiver, not a reading on this set.
- **The ≥ 330 mH transformer.** Specified from the droop rule. Its interwinding
  capacitance and self-resonance at 128 kBaud are not computed anywhere, and a
  transformer ten times the line card's inductance is not the same part.
- **No attenuation ladder exists at 64 kbps.** `sim/subline.log`, the only run on
  this line, sweeps Gaussian sd and impulse rate. `line-codes.md` §3's ladder is
  512 kbps on a 1.8 MHz cable, with a framer, and this line has no frame. The
  set's LOW mark is transferred from §9.3's hysteresis ratio, which is
  rate-independent — but it is a transfer.
- **Phantom imbalance.** A clip-on set adds exactly the kind of resistance
  asymmetry between the two wires of a pair that puts net DC through a winding,
  and `subscriber-line.md` §7 already lists that as not computed against the
  transformer's saturation.
- **The LM339 common-mode ceiling** of §5.2 is a data-sheet figure. Nothing in
  this repository measures it, and no file states which rail
  `channel-cards.md` §2.2's comparator runs from.
- **The power budget of §8** is arithmetic throughout: the HC figure is scaled
  from `subscriber-adapter.md` §4, the analog cluster is that section's ~300 mW,
  switcher efficiency is its 80 %, cell capacity is a data-sheet class number.
  The ear amplifier's current is not specified anywhere — `su-1.md` §3.1 gives
  only "600 Ω" and "stop before clipping the capsule", and `pcb/su-1/README.md`
  leaves the amplifier part open.
- **The package count and the board count.** §12. No capacity figure for a
  100 × 100 exists in the tree, nothing here is routed, and `pcb/hookbusy/`'s
  committed placement is itself not DRC'd.
- **The silent encoder's limit cycle in hardware.** `sim/subline.log` measures it
  as exactly period-2 — longest run 1 bit over 320 000 — but `sim/cvsd.py`:54 is
  `b = 1 if x[i] >= y else 0`, an offset-free comparator. Strict alternation
  survives only while the net input-referred DC at the integrator stays under
  half a minimum step, 2.42 mV, and `mf8-spec.md` §12.1 warns that offset counts
  1.6× at I_min against a 4.9 mV step. Whether a real SU-A with a live mic in a
  real room idles at exact `1010` is a bench measurement nothing in the tree
  makes. If it does not, §11's two ambiguous rows are less ambiguous than stated.
- **The `SPEECH` threshold.** ≈ 0.05 clean to ≈ 0.25 noisy is read off
  `sim/subline.log`'s means; no run sweeps a second threshold on that node, and
  the ~0.5 s peak hold is a guess at how long a speech pause is.
- **The violation-to-impulse conversion.** `line-codes.md` §4.5's 0.77 breaks per
  impulse is a framer statistic at 1.024 MBaud. The lid refuses the conversion
  until `sim/subline.py`'s own violation term has been run against known impulse
  rates at 64 kbps — which is one afternoon's work on a script that already
  exists, and is the thing to do before any copper is cut.
- **`channel-cards.md` §5's A-path dial-pulse figures**, carried in §11's ringing
  row, have their own closing line calling that a scratch script rather than a
  repository tool. The `subscriber-line.md` §2 transient figures quoted in §2.1
  carry the same caveat from §7 of that document.
- **The whole instrument.** No schematic, no copper, no `pcb/stu-1/`. Nothing in
  this project has been on a bench, and a test set is the thing that would find
  out.