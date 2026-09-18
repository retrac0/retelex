# Strappable line rate and channel count — feasibility

Can the nine modes (spec §2) be selected with 74HC logic and jumpers at both ends,
given that the receiver's input filter and timers are tied to the symbol rate?

Status: exploration, **not yet adopted into the spec** (§11 lists the edits it
implies). Three tracks each designed an option and measured it
(`feas_analog_rx.py`, `feas_digital_rx.py`, `feas_rptx.py`). An independent
reviewer then re-measured each track's key results with new noise seeds and
checked its hardware claims against datasheets. **Where a reviewer disagreed,
this document uses the reviewer's figure.** Constraints set by the owner: no
auto-configuration, and the transmitter and receiver are both jumper-set to
match.

All margins use the absolute method of `strap.py` §31: one sample rate, one
1 MHz cable and one noise floor for every rate, so filter effects are visible.
Differences under about 1 dB are within seed-to-seed spread.

---

## 1. The answer

**Feasible, with caveats.**

| card | configuration | cost |
|---|---|---|
| **Transmitter** | unchanged: RATE jumper, CHANNELS from the end's shared field | add a worst-case edge limit at 1024 kbps (§8) |
| **Receiver** | keep the clockless analog design; one RATE control, labelled like the TX field and set to the **far end's** TX rate; CHANNELS from the shared field | within **1.0 dB** of a per-rate receiver at every rate; the filter buffer becomes mandatory; the classifier timer needs select-on-test at 512 and 1024 kbps |
| **Repeater** | **no jumper**: fixed ~2.05 MHz two-pole filter, 75 ns edge, 33 mH | 2–5 dB at 64 kbps on repeatered routes; 1024 kbps routes need a skew limit |
| CVSD card, data card | no strap (unchanged) | — |

The rule for a technician is one line: **CHANNELS is the same at both ends; the
receiver's RATE copies the other end's transmitter.**

A digital receiver with its own crystal also works (§6). It loses 1.4–2.6 dB below
1024 kbps and fails 74HC worst-case timing as designed, so it is not recommended.

Two things remain undemonstrated: the classifier timer's worst-case tolerance
over temperature at 1024 kbps (§4), and per-hop delay skew on 1024 kbps
repeatered routes (§7).

---

## 2. How much of the receiver moves with the rate

Fewer parts than the current five-row rate plug (`line-receiver.md` §8).

### 2.1 Input filter — three bands

Loss against a filter at each rate's own symbol rate, mean of two seeds:

| filter settings | 64k | 128k | 256k | 512k | 1024k |
|---|---|---|---|---|---|
| five (own symbol rate) | 0 | 0 | 0 | 0 | 0 |
| **three: 128 kHz / 362 kHz (128, 256) / 1.448 MHz (512, 1024)** | **0.0** | **−0.3** | **−0.4** | **−0.7** | **−0.3** |
| two: 256 kHz (64–256) / 1.448 MHz | −2.5 | 0.0 | −1.6 | −0.7 | −0.3 |
| best single corner, 724 kHz | −7.2 | −3.4 | −0.6 | −0.5 | −8.2 |
| one fixed at 2.048 MHz | −11.8 | −8.8 | −5.0 | −2.1 | 0 |

(dB; `feas_analog_rx.py a`.) Built end to end with its dead time, the
three-band receiver measured −0.1 / 0.0 / −0.5 / −1.0 / −0.3 dB, and the two-band
one −2.6 dB at 64 kbps and −3.0 dB at 256 kbps (`e`). The 1.448 MHz band tolerates
parasitics: +10% capacitance costs about 0.1 dB, +25% about 0.8 dB
(`feas_verify_analog_rx.py band`).

**The buffer between sections is mandatory.** Unbuffered, the same values cost
3.0–3.9 dB at 1024 kbps and 1.1–1.5 dB at 64 kbps (`feas_verify_analog_rx.py
ladder`). Doubling the corner of an unbuffered ladder recovered 1024 kbps, but
was not tested at the other rates.

### 2.2 The other parts

| part | settings | measured basis |
|---|---|---|
| Classifier timer | **five**, cannot be grouped | a timer one or two steps off never locks |
| Dead time | **two**: 977 ns (64–256k), 195 ns (512–1024k) | a fixed 250 ns cost 1.3–2.6 dB at 128 kbps (two seeds); 977 ns at 64k tolerates ±50% for ≤ 0.6 dB |
| Carrier detect | **one**: fixed 31.25 µs | 0 trips on signal at every rate; always trips on a quiet dead line. At 1024k with sd 0.1 noise it trips 0% of the time, against 41.5% for a 2-cell timeout, so it is a weaker backstop there and relies on the framer never locking on noise |

So the receiver has **ten** rate-switched parts: five timer resistors, four
filter capacitors (two per section, if single-ended) and one dead-time part.

---

## 3. Why the rate must be one control

With independent jumpers, a technician can change some parts and not others.
Measured with the transmitter at a known rate and one receiver part wrong
(`feas_analog_rx.py d`, `d2`):

| half-changed receiver | result |
|---|---|
| whole receiver ±1 or ±2 rate steps | never locks — muted |
| classifier timer alone ±1 or ±2 steps | never locks — muted |
| filter one step too wide | no loss |
| filter two steps too wide (4×) | locks; errors near the noise limit (2.9e-3 at 64k) |
| 512/1024 filter left in at 128 kbps | clean on the bench; at the design noise level 17 locks and 16 losses of frame, locked 87.5% of the time, **BER 3.1e-2 delivered unmuted** |
| dead time 2× too long | relock cycles, **BER 2.0e-3 to 2.6e-2** |
| carrier detect one step short | 10⁴–5×10⁴ trips per second — a dead link |
| any configuration, noise-only line | never locks |

Several of these pass a clean bench loopback and then fail silently on a real
line. **A loose array of jumpers is therefore unsafe.** Whatever selects the
rate must not be capable of being half-changed.

| selector | extra packages | notes |
|---|---|---|
| **One universal shorting plug in one of five keyed, shrouded headers** (1024 / 512 / 256 / 128 / 64, ordered like the TX field) | **0** | Cannot be half-changed. Unselected parts are open-circuit, not loading the timing node. A seventh pair, PRESENT, can force mute when no plug is fitted (analysis). Stub and routing capacitance of shared filter capacitors is unmeasured |
| One RATE shunt driving 74HC148 + 74HC4051 + 74HC4066 | **5–7** (card ~20–22) | Identical in form to the TX field. The filter needs Vcc/2 bias; the 4051's on-resistance is 1.5–3.8% of the 1024k timer resistor; unselected resistors add an estimated 10–30 pF of position-dependent loading to the timer (analysis) |
| Coded rotary switch | ~4 | Could replace the shunt and 74HC148; not measured |
| Loose multi-section jumpers | 0 | **Rejected** — §3 above |

**Recommended: the keyed plug.** It is the only option with no parasitic
penalty and no package cost.

---

## 4. The timer tolerance problem

Usable classifier threshold at the design noise level, in fractions of a cell:

| line rate | 64k | 128k | 256k | 512k | 1024k |
|---|---|---|---|---|---|
| window | 0.625–0.875 | 0.625–0.900 | 0.650–0.850 | 0.625–0.875 | **0.675–0.825** |
| margin about 0.75 | ±17% | +20 / −17% | ±13% | ±17% | **±10%** |

(1024k is the intersection over three noise seeds; `feas_verify_analog_rx.py
win`.) The 74HC123's guaranteed pulse-width tolerance is **±11% at 25 °C and ±14%
over −40 to 85 °C**. Resistor, capacitor, supply and stray variation already take
±9.5% at 1024 kbps (linear stack). Even with a per-board trim, the stack fits
only on an RSS basis.

**At 512 and 1024 kbps the timer resistor must be selected on test**, and the
window checked on the bench at every header position. **Worst-case operation
over temperature at 1024 kbps is not demonstrated.** At 64 kbps the ±17% window
fits comfortably.

Two further hardware items, both unmeasured: the dead-time timer at 195 ns is
near the 74HC221's minimum pulse width, and the timer's formula constant is
unpublished below 10 nF. All timer resistor values are therefore starting
points.

---

## 5. Recommended receiver values

| header (= far-end TX RATE) | filter C per section, R = 1.00 kΩ, buffered | classifier Rext, Cext 270 pF C0G | dead time |
|---|---|---|---|
| 1024 | 110 pF (1.448 MHz) | 5.9 kΩ, **select on test** | 195 ns |
| 512 | 110 pF | 11.8 kΩ, **select on test** | 195 ns |
| 256 | 440 pF (362 kHz) | 23.5 kΩ | 977 ns |
| 128 | 440 pF | 47.0 kΩ | 977 ns |
| 64 | 1.244 nF (128 kHz) | 94.0 kΩ | 977 ns |
| all | — | carrier detect fixed at 31.25 µs | — |

Whether the filter is built differentially (doubling the switched capacitors) or
single-ended after a buffer is not yet decided.

---

## 6. The digital receiver, and why it is not recommended

A local crystal, counters on the comparator samples, and one RATE shunt on counter
taps replace every analog rate part. Integrate-and-dump averaging recovers most of
the low-rate noise advantage digitally.

| | analog, keyed plug | digital M = 8 (8.192 MHz) | digital M = 16 (16.384 MHz) |
|---|---|---|---|
| margin vs per-rate analog, 64k | −0.1 dB | −2.5 dB | −2.2 to −2.4 dB |
| 128k | 0.0 | −2.6 | −2.4 |
| 256k | −0.5 | −1.4 | −0.6 |
| 512k | −1.0 | −1.4, with errors where the analog is clean | +0.5 |
| 1024k | −0.3 | −0.4 to −2.4 (seed-dependent); 40 errors in 223 538 bits end to end at sd 0.4 | −0.9 to 0.0 |
| 74HC timing | — | **fails as designed**: the compare path is 118–184 ns against a 122 ns clock; needs a pipeline register or 74AHC | **not buildable in 74HC**, even at 25 °C maximum timing |
| packages | ~15–16 | ~23–26 plus a crystal | +1 |
| wrong rate | mutes | never locks — mutes | same |
| lost | — | the clockless receiver; zero frame-clock jitter (−0.28 dB CVSD worst case) | same (−0.07 dB) |

(`feas_digital_rx.py b2`, `feas_verify_digital_rx.py seed`, `mid`, `miscfg`;
datasheet timing from TI CD74HC163/85/175/08.) Its one advantage is crystal-exact
thresholds, which remove the §4 tolerance problem. It is the fallback if 1024 kbps
cannot be made to fit with select-on-test.

---

## 7. Repeater

A repeater's front-end filter can be **fixed** — no jumper — if it is never
narrower than the fastest symbol rate on the route.

| repeater filter, against one matched to the rate | 4 spans | 9 spans |
|---|---|---|
| 64k: fixed 2.05 MHz two-pole | −4 to −5 dB | −2 to −4 dB |
| 64k: no filter | −8 dB | −6 dB |
| 256k: fixed 2.05 MHz | 0 dB | 0 dB |
| 256k: at half the symbol rate (too narrow) | −3 dB | −6 dB |
| 256k: at a quarter of the symbol rate | never locks | never locks |
| 1024k: fixed 2.05 MHz | 0 (it is matched) | 0 |
| 1024k: 1.024 MHz (too narrow) | −3 dB | −5 dB |

(`feas_rptx.py a`, two seeds at 64k; `feas_verify_rptx.py v4` at 256k.) A wide
filter costs less in a chain than at a single terminal, because the terminal
filters again; a narrow filter costs more, because timing error accumulates at
every hop. Even with the fixed filter, 64 kbps beats 256 kbps with a matched
filter by 2 dB at 4 spans and 4 dB at 9. 128 and 512 kbps were not measured.

**The filter shape matters at 1024 kbps.** Two RC sections each at 2.048 MHz fail
9 spans; RC sections at 3.18 MHz cost 3–4 dB. A true two-pole is needed:
Sallen-Key on a fast op-amp, or a passive LC section. Neither was simulated. An
LC section halves the signal at the comparator, and an op-amp adds current to the
line-power budget.

**1024 kbps repeatered routes need their own limits:**

- A 9-span chain loses **12 dB** against one span, confirmed over three seeds.
  Noiseless, the shortest regenerated interval shrinks from 0.492 to 0.430 of a
  cell over 9 spans. Deterministic distortion *does* accumulate at 1024 kbps on
  this cable, contrary to `repeater.md` §1.3, which was measured at 256 kbps.
- **Per-hop delay skew** (rising versus falling propagation delay) accumulates.
  7.6 ns per hop moves the 9-span limit from sd 0.125 to about 0.07, a 5 dB loss.
  15 ns per hop fails 9 spans at every noise level tried. 256 kbps tolerates
  30.5 ns per hop. (`feas_verify_rptx.py v3`, `v3b`.)

**Transformer:** 33 mH performs within 1 dB of no transformer at 1, 4 and 9 spans
at 64 kbps. 10 mH loses 6–7 dB at 9 spans and fails the 9-span check
(`feas_rptx.py c`). `repeater.md`'s "≥ 10 mH" is wrong; the spec's 33 mH is right.

---

## 8. Transmitter edge rate

At 512 kbps and below, 75 ns and 150 ns edges show no measurable loss (512k
validly measured to 4 spans). At 1024 kbps over 9 spans at sd 0.125:

| edge | 0 ns | 75 ns | 100 ns | 150 ns | 190 ns |
|---|---|---|---|---|---|
| BER, two seeds | 0 / 0 | 0 / 3e-5 | 3e-5 / 3e-5 | **8e-2 / 3e-4** | **4e-1 / 4e-1** |

(`feas_verify_rptx_edge.py`.) **Specify 75 ns nominal and ≤ 100 ns worst case
including component tolerance**, at the transmitter and at every repeater. Keep
the transmitter's rate-switched slew capacitor: it costs the technician nothing
and keeps slower edges at the low rates, where EMI matters more. Emissions were
not simulated.

---

## 9. Channel count

Unaffected by any of this. It is digital on both cards: a mask, a frame-clock
stage and the select term, from one CHANNELS field shared per end. A mismatch
never locks (spec §10.3).

---

## 10. Open measurements, ranked

1. **The classifier window on the bench at 1024 and 512 kbps**, with real 74HC123
   parts over 0–70 °C, including header stubs. This decides whether 1024 kbps is
   supportable at worst case. Add a simulation fine enough to resolve 0.025 cell;
   1024k currently has 32 samples per cell.
2. **Per-hop propagation skew** with datasheet limits for the 75179 or
   26LS31/32 at 512 and 1024 kbps, including tip/ring swaps between spans. This
   sets a hop limit or a part-matching rule.
3. **The receiver filter as built**: buffer op-amp and its bandwidth,
   differential or single-ended, header stub capacitance, end to end at all five
   rates.
4. **The repeater filter as built**: Sallen-Key with finite op-amp bandwidth, and
   doubly terminated LC against the comparator's fixed hysteresis.
5. **Wrong rate beyond ±2 steps**, no plug fitted, and half-changed cases with
   CVSD silence and idle patterns.
6. **Near-end crosstalk from a 1024 kbps route** into a 64 kbps repeater with the
   wide filter, and whether its carrier detect stays retriggered on a dead span.
7. **Fixed repeater filter at 128 and 512 kbps.**
8. **The 74HC221 at 195 ns**, and the dead-time upper edge at 1024k near the noise
   limit.
9. **Carrier detect fed to the framer as a forced loss of frame**, at 512 and
   1024 kbps with moderate noise.
10. **Everything together**: edge tolerance, transformer, fixed repeater filter
    and timer tolerance in one chain.

---

## 11. What this would change in the current documents

Not yet applied.

- **spec.md** — §2.2: the rate plug becomes one keyed header set with ten parts;
  carrier detect no longer moves; repeaters take no strap *with* a fixed filter
  and its stated cost. §6.1: three filter bands, buffered; dead time 977 / 195 ns;
  classifier ±10% at 1024k; carrier detect 31.25 µs. §8.5: RX RATE header labels
  match the TX field. §12: edge ≤ 100 ns worst case; the 9-span budget does not
  hold at 1024 kbps without a skew limit. §13: droop and edge rate are now
  measured.
- **line-receiver.md** — §3: three bands, buffer mandatory. §7: fixed 31.25 µs.
  §8: keyed header set instead of five plugs; correct the analog-switch parasitics.
  §9: buffer counted, ~15–16 packages. §10–11: select-on-test and a window check
  at every header position.
- **repeater.md** — §1.3: distortion accumulates at 1024 kbps. §2: add the fixed
  2.05 MHz two-pole filter and the never-narrower rule. §2.3: state the fixed
  filter's cost. §2.6: 75 ns / ≤ 100 ns edges, **≥ 33 mH** (not 10 mH). The
  9-span budget needs a 1024 kbps qualification.
- **line-transmitter.md** — §6: add the worst-case edge limit; note the RATE
  field is the reference the receiver headers copy.

---

## 12. Reproducing

| file | what |
|---|---|
| `feas_analog_rx.py` (`check`, `a`, `b`, `cd`, `d`, `d2`, `e`, `e2`), `feas_analog_budget.py` | analog receiver: filter bands, timers, half-change, tolerance arithmetic |
| `feas_verify_analog_rx.py` (`win`, `ladder`, `band`, `dead`) | reviewer's re-measurements |
| `feas_digital_rx.py`, `feas_digital_core.c` | digital receiver |
| `feas_verify_digital_rx.py` (`seed`, `mid`, `miscfg`) | reviewer's re-measurements |
| `feas_rptx.py` (`a`, `b1`, `b2`, `c`) and its logs | repeater filter, edge rate, transformer droop |
| `feas_verify_rptx.py` (`v1`–`v5`), `feas_verify_rptx_edge.py`, `feas_verify_rptx_pat.py` and logs | reviewer's re-measurements: seeds, skew, edge, payloads |

Assumptions common to every run: first-order 1 MHz cable; white Gaussian noise
only; an ideal comparator with 5% hysteresis; two or three noise seeds. All
package counts are estimates.
