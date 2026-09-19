# Circuit review — four findings ahead of the breadboard

Reading `mf8-spec.md` §9–§12 and `mf8-cards.md` as a wiring list for a first
breadboard — a looped CVSD engine, then one channel over differential
Manchester, then the multiplex — turned up four places where the documents stop
short of a circuit that works. One is an error in the spec as written; two are
gaps that the removed `channel-card.md` (in git at `29b31c7^`) filled with
wiring that would not work; one is a hazard the spec names but under-describes.

| | where | finding | fix |
|---|---|---|---|
| 1 | `mf8-spec.md` §9.2, §10; `mf8-cards.md` §2.1, §2.4 | the encoder's flip-flop does not toggle on either part the drawing names | 74HC112, J = K = EN; package count unchanged |
| 2 | `mf8-spec.md` §12.1; `mf8-cards.md` §3.2 | there is no `Iabc` drive in the documents, the one that was sketched cannot hold `I_min`, and `I_min` is the tightest tolerance on the card | op-amp and PNP, ratio set by two resistors; one op-amp section per engine |
| 3 | `mf8-spec.md` §9.4 | "sample, then retrigger" is three same-edge reads, not one; the bit strobe cannot be a gate on the transition pulse; none of it scales with the rate | use both edges of the dead-time pulse; no added package on the trunk card |
| 4 | `mf8-spec.md` §12.1 | the three connections between the 5 V logic and the ±12 V engine are unspecified, and the obvious wiring of one of them has no down-step | pull-up, a differential drive from Q and /Q, one ground |

> **Status: analysis from data-sheet figures, plus scratch measurements on the
> codec model** (§2.2–2.3, `cvsd.py` at 64 kbps). Nothing here has been built.
> The fixes are proposals in the same sense the circuits they amend are.

---

## 1. The encoder flip-flop does not toggle as drawn

§9.2 draws `J` and `K` tied to `EN` on a part labelled "74HC74/109" and says "a
JK wired J = K = EN toggles when EN is high". The parts lists (§10,
`mf8-cards.md` §2.1 and §2.4) say "½ 74HC74 + ¼ 74HC00". Neither part does
that:

- **A 74HC74 is a D flip-flop.** It has no J or K. Toggle-with-enable on a D
  input is `D = Q ⊕ EN` — one XOR the parts list does not have.
- **A 74HC109 has J and /K.** Tied together they make it a D flip-flop — the
  data sheet offers that as a feature — so the line would carry `EN` delayed by
  a half-bit. Toggle-with-enable is `J = EN`, `/K = NOT EN`: one inverter more.
- **`/H` is not available either.** `H` is a ripple-counter output (the '393's
  QA on the trunk card, `TX_CLK` from the bus on a line card) with no
  complement, so `EN = NAND(/H, bit)` is two NANDs, not one.

| flip-flop | wiring | gates | clock edge |
|---|---|---|---|
| **74HC112** (or '73, '107) | J = K = EN, as drawn | `EN = H + /bit`: on the trunk card the frame '151's complementary output is `/bit`, so ¼ 74HC32; otherwise ½ 74HC00 | **falling — the edge the '4040 and '393 count on** |
| 74HC109 | J = EN, /K = /EN | ¾ 74HC00 | rising |
| 74HC74 | D = Q ⊕ EN | ½ 74HC00 + ¼ 74HC86 | rising |

**Use the 74HC112.** It is the only one of the three for which §9.2's drawing
and its timing note are both true as written: the JK and the divider that makes
`H` take the same falling edge of `HB`, the JK reads `H` from before it, and the
condition is the one §9.2 states — the '393's clock-to-Q against the JK's hold
time, a few nanoseconds at most. Check it against the parts, as §9.2 says.

A rising-edge part on the falling-edge chain also works, and has no race at all
— it samples half an `HB` period after `H` last moved — but every decision moves
a quarter-cell early. Bit *n* is then read 0.25 cell into counter cell *n*
rather than 0.5, so `mf8-backplane.md` §5's transmit margins become setup from
1.25 cells (2.44 µs, was 2.93) and hold 1.46 µs (was 0.98), and the mux has
0.25 cell to settle: 244 ns at 1 024 kbps against ~100 ns of ripple and '151.
All still clear; it is a different table, not a problem.

---

## 2. The `Iabc` drive

§12.1 gives the two ends of the step current — 120 µA and 3.8 µA, 31.6:1 — and
no circuit that produces them. The only sketch was in the removed
`channel-card.md` §2.1: two resistors into the LM13700's bias pin, one from a
fixed bias for `I_min` and one from the syllabic node for the rest.

### 2.1 The pin is not at ground

The bias pin is the input of a current mirror to the negative rail. TI's data
sheet: "the Bias Input pins are 2 diode drops above the negative supply,
V_BIAS = 2·V_BE + V−". The wanted law is linear in the syllabic voltage,

```
Iabc = I_min + syl · (I_max − I_min)          syl = V_node / 5 V
```

so the slope resistor is 5 V / 116.2 µA = **43 kΩ whatever the rails are**, and
at `syl` = 0 it carries whatever the pin's voltage puts across it:

| LM13700 V− | pin | slope resistor at `syl` = 0 | so the bias resistor must | every 10 mV of 2·V_BE moves `I_min` |
|---|---|---|---|---|
| −12 V | −10.7 V | **+249 µA** into the pin | *remove* 245 µA, through the 1.3 V between pin and rail | 2.1 µA — **56 %** |
| logic ground | +1.3 V | **−30 µA**, out of the pin | supply 34 µA; `I_min` is 34 − 30 | 0.32 µA — **8.5 %** |

Either way `I_min` is a small difference of two currents that are both set by a
junction voltage. 2·V_BE moves −4 mV/°C, which on the grounded arrangement is
+3.4 % of `I_min` per degree: it doubles in about 30 °C. And the 43 kΩ hangs on
the 60 kΩ / 100 nF syllabic node, so as listed τ_syl is 2.5 ms, not 6.

### 2.2 Measured: what those drives do to the codec

`cvsd.py`'s engine at 64 kbps with the step law replaced, encoder and decoder
alike, scored against the source; `talker1` / `talker4`, 8 s each:

| drive, matched at both ends | segSNR at nominal | at −20 dB |
|---|---|---|
| the designed law, 31.6:1 | 26.9 / 17.3 dB | 22.0 / 19.7 dB |
| one resistor from the node, ±12 V rails — **1.47:1** | **8.8 / 7.7** | **0.2 / 0.3** |
| two resistors, pin at +1.3 V, the bias sized for 3.8 µA with the slope resistor's pull ignored — **zero step below `syl` = 0.24** | 20.9 / 17.5 | 33.2 / 28.8 |
| the designed law with τ_syl = 2.5 ms | 27.2 / 18.1 | 22.0 / 20.0 |

The first failure is outright: on split rails the codec does not compand. The
second is not a failure *in the model*. A dead zone is a compander with more
range, the loop restarts itself, and a matched pair scores well. But the knee
sits near `syl` = V_pin / 5 V — set by each chip's V_BE, not by a resistor — and
§2.3 is what that costs. The last row says the loading is a values problem,
not a quality one.

### 2.3 Measured: `I_min` mismatch is the tolerance nobody swept

`tolerance.py` scales `I_min` and `I_max` together, which is why it finds step
size to be pure gain. `I_min` alone is a different error: the decoder's step is
wrong at low `syl` and right at high `syl`, so its gain follows the signal
level. Decoder `I_min` in error, encoder nominal, change in segSNR after one
gain match, against the matched pair:

| decoder `I_min` | −50 % | −30 % | −20 % | −10 % | −5 % | +5 % | +10 % | +20 % | +30 % | +50 % | +100 % |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `talker6`, nominal — the worst | −9.1 | −5.8 | −3.8 | −1.5 | −0.4 | −0.8 | −1.9 | −3.9 | −5.5 | −8.0 | −11.8 dB |
| `talker4`, nominal — the best | −3.9 | −2.1 | −1.1 | −0.3 | 0.0 | −0.2 | −0.6 | −1.4 | −2.2 | −3.6 | −6.0 |
| `talker1`, −20 dB | −7.3 | −3.2 | −1.6 | −0.4 | −0.1 | −0.1 | −0.3 | −1.0 | −1.6 | −2.7 | −4.4 |

**On `tolerance.py`'s 1 dB criterion `I_min` must match to about ±5 %** — the
tightest figure on the card. For context, `tolerance.py` itself re-run at
64 kbps, where the matched pair scores 23–25 dB rather than 32 kbps's 17–19 and
a given mismatch therefore shows sooner:

| network | §12.1, measured at 32 kbps | the same sweep at 64 kbps |
|---|---|---|
| integrator R·C | ±30 % | **±20 %** |
| syllabic R·C | ±20 % | **±10 %** |
| step size, `I_min` and `I_max` together | ±30 %, pure gain | ±30 %, pure gain |
| **`I_min` alone** | not swept | **±5 %** |

Two cautions. **The scorer overstates this.** A level-dependent gain is scored
as noise in full, and an ear may not hear it as any. Measured as gain instead,
`I_min` 10 % out moves the output level **0.5 dB** between nominal speech and
−20 dB (0.44–0.58 dB, `talker1` and `talker6`, either sign). At the scale §2.1
predicts it is not subtle — `I_min` 2× high plays speech at −20 dB about 5 dB
loud and nominal speech 1.5 dB loud — but where between those it becomes
audible has not been rendered. **And
§12.1's BOM no longer clears its own budget**: 1 % resistors and 5 % film are
±6 % a card and ±12 % card to card, against ±10 % for the syllabic network at
this frame's only rate. A 2 % `C_syl` restores it.

Against ±5 %, §2.1's grounded arrangement has 6 mV of 2·V_BE to spend, which is
1.5 °C.

### 2.4 Proposed drive

Take the pin out of the law: an op-amp and a PNP as a current source into it,
the law set by resistor ratios, the syllabic filter run in the opposite sense so
that the source can hang from the rail.

```
 /coincidence ── R1 61.9k ──┬────────────────── (+) ┐
   = XOR01 + XOR12, ¼ 74HC32│                       op-amp ──── base ┐
   where the '08 was        C_syl 100n ∥ R2 1.91M   (−) ┐            │ PNP, 2N3906
                            │                           │            │
                           gnd        V_A ── R_set ─────┴── emitter ─┘
                                                            collector ──→ Iabc pin

 V_node = k · V_A · (1 − syl)       k = R2 / (R1 + R2) = 0.9686
 Iabc   = (V_A − V_node) / R_set
        = V_A · (1 − k) / R_set   at syl = 0          I_min
        = V_A / R_set             at syl = 1          I_max
```

| item | value | sets |
|---|---|---|
| R1, R2 | 61.9 kΩ, 1.91 MΩ, 1 % | the ratio, 1 / (1 − k) = 31.9 — **by two resistors and nothing else**; R1 ∥ R2 = 60.0 kΩ, so τ_syl is still 6 ms on 100 nF |
| R_set | 36.5 kΩ + 10 kΩ trimmer | `I_max`: 41.7 kΩ for 120 µA. **Still the one trimmer**, and it scales `I_min` with `I_max` — so trimming is pure gain, which §12.1 tolerates to ±30 % |
| V_A | the +5 V rail through 100 Ω and 100 µF, feeding **both** R_set and the coincidence gate's package | the gate's high level and the source's reference are one node, so the law is ratiometric in it. The node lags V_A by 6 ms, so faster ripple appears across R_set whole — against 157 mV at `I_min`, where 8 mV is 5 % |
| op-amp | JFET input, on ±12 V | its **offset is the `I_min` specification**: 157 mV is the whole control voltage at `I_min`, so a TL072's 3 mV typical is 2 % and its 10 mV worst case is 6 %. Take a low-offset grade, or trim |
| PNP | 2N3906 or any small-signal part | nothing: the base current is 1–2 % and the same on both cards |

Expected `I_min` accuracy, ratio plus a typical offset: ±4 %, inside §2.3's
figure and independent of temperature, the rails and the OTA. The node now
drives only an op-amp input, so τ_syl is 6 ms as drawn. Cost: **one op-amp
section and one transistor per engine** — a dual op-amp more on the card — and
a '32 for the '08, powered from V_A.

§12.1 gives slew 12 000 and 120 µA, while `mf8.py` runs its 64 kbps codec at
16 000, which is 160 µA and R_set = 31.2 kΩ. The removed `channel-card.md`
measured the one-setting compromise at 0.28 dB at 64 kbps; with 64 kbps now the
only rate, one of the two numbers should change. Nothing else in the drive
moves with it.

---

## 3. Sample, then retrigger — and the strobe

§9.4: "at each accepted transition the classifier timer's state must be captured
before that same transition retriggers it. The timer's trigger-to-output delay
gives the flip-flop its hold margin." Three things about that.

**It does not scale with the rate plug.** The margin is the '123's
trigger-to-Q delay, less the '74's hold time, less any gate that sits in the
flip-flop's clock and not in the timer's trigger. That is tens of nanoseconds
at 64 kbps exactly as at 1 024, and the transition pulse is itself a gate
output (the '86 pulse gated by the dead time). So the 128 kBaud bring-up tests
the same margin the fastest rate has — it should be checked on the first
receiver built, not left for the fast one — and it rests on a *minimum*
propagation delay, which 74HC data sheets generally do not specify.

**It is three reads, not one.** At an accepted transition the circuit needs,
from *before* the edge:

| read | needs | changes after the edge |
|---|---|---|
| `LONG` ← has the classifier expired | the '123's state | ~30 ns, when it retriggers |
| `MID` ← not expired · not `MID` | the '123's state and `MID` | ~30 ns and ~20 ns |
| strobe ← expired + `MID` | the '123's state and `MID` | the same |

**The strobe cannot be a gate on the transition pulse.** "Accepted transition
gated by `LONG + MID`" reads two signals that both move ~20 ns into a pulse
~100 ns wide. On the first half of a 0, `MID` sets and opens the gate for the
rest of the pulse: a false strobe. On the second half, `MID` clears and cuts the
strobe to a 20 ns runt. The removed `line-receiver.md` had the requirement in a
parenthesis — "(before MID updates)" — and nothing in the circuit enforces it.

**Proposed: use both edges of the dead-time pulse.** The '221's output `DT` is
a pulse of 0.2 cell that begins at every accepted transition and at nothing
else; it *is* the accepted transition. Sample on its leading edge, act on its
trailing edge:

```
 DT leading edge     LONG ← '123 /Q                  expired: the bit is a 1
                     MID  ← '123 Q · /MID            = NOT emit      (¼ 74HC08)
 DT trailing edge    '123 retriggered, DT into its falling-edge input /A
                     '221 second half: DT into /A, /MID into B — fires on
                     DT's fall iff /MID                                → W
 W, ~100 ns fixed    /W (the '221's own /Q) enables the '259 write; the bit
                     is LONG; W's falling edge advances the bit counter
```

`MID`'s next state is exactly "this transition emitted nothing", so `/MID` after
the leading edge is the emit decision, stable for 0.2 cell before anything uses
it. Every classifier read gets 0.2 cell of hold — 195 ns at the fastest rate,
3.1 µs at 128 kBaud — where it had a propagation delay. Two same-edge relations
remain, both of the ordinary kind with a specified hold time on the receiving
part: the '259 closes and the counter advances on W's fall, which is "latch,
then advance" (`line-receiver.md` §5.1) resting on the '393's clock-to-Q against
the '259's address hold; and `/MID` must not rise while DT is still low, or the
'221's B input triggers W on its own, which the '74's clock-to-Q after DT rises
guarantees. The second half of the '221 was spare, and the AND is a quarter of
the '08 the trunk card and the line card each already carry.

A transition can still arrive just outside the dead time. The next DT then
begins as W does, and `LONG` can change during the '259 write: the circuit and
`fast.mono_decode` may disagree about a bit that noise has already spoiled.

What it costs is on the rate plug. The classifier now times from the *end* of
the dead time, so its network is 0.75 − 0.2 = **0.55 cell**, and the threshold
is the sum of two timers:

| line rate | dead time, 0.2 cell | classifier, **0.55 cell** | was, 0.75 cell |
|---|---|---|---|
| 1024 kbps | 195 ns | 537 ns | 732 ns |
| 512 kbps | 391 ns | 1 074 ns | 1 465 ns |
| 256 kbps | 781 ns | 2 148 ns | 2 930 ns |
| 128 kbps | 1 563 ns | 4 297 ns | 5 859 ns |
| 64 kbps | 3 125 ns | 8 594 ns | 11 719 ns |

With the same 1 % and 2 % parts on both timers the sum holds ±3 % as before.
The dead time's own window is unchanged, 0.05–0.30 cell, but it is no longer
loose for free: it is 27 % of the threshold, so a 10 % error in it moves the
threshold 2.7 % of the ±13 %. `W` is fixed and stays off the plug; on a valid
line the next transition is at least 0.5 cell behind the last, and W is over by
0.30 cell at the fastest rate.

The behaviour is `fast.mono_decode`'s exactly — accept outside the dead time,
call a gap long above 0.75 cell — so nothing measured over the line changes.

The hook detector's violation term (`mf8-cards.md` §2.2, "`LONG · MID` at an
accepted edge") needs the *old* `MID`, which this scheme overwrites at DT's
leading edge. Capture it there too: `'123 /Q · MID` into a flip-flop on the same
edge, ¼ '08 and ½ '74 more than §2.2 lists. And the raw '123 output now expires
*inside* DT whenever a gap falls between 0.55 and 0.75 cell — it is retriggered
only at DT's trailing edge — so nothing may read it except at DT's leading edge.
Neither is checked against §2.2's hold timer here.

---

## 4. Between the logic and the engine

§12.1 specifies the engine and the backplane gives it +5 V and ±12 V. The three
connections between the two are not in any document.

**The LM311's output is a floating transistor.** Collector to +5 V through
4.7 kΩ, emitter pin to logic ground, supplies ±12 V. With no pull-up there is
no logic level; pulled to +12 V it drives the 74HC input through its clamp
diode.

**The data bit into the OTA must be differential.** The removed
`channel-card.md` has it "resistively divided to roughly ±100 mV about the bias
point". On ±12 V rails the bias point is ground, and a 0 / 5 V bit divided down
is 0 / +200 mV about it: `Iout` is 0 or +`Iabc`, and **there is no down-step**
— the integrator climbs and leaks. Drive both inputs, which the '74 already
allows:

```
 Q  ── 47k ──┬── (+)        /Q ── 47k ──┬── (−)        Vd = ±224 mV
            2.2k                       2.2k            common mode +112 mV
             │                          │              pins 2 and 15 open
            gnd                        gnd
```

`Iout = Iabc · tanh(Vd / 2V_T)`: ±224 mV steers 99.96 % of `Iabc`; the ±100 mV
of the removed document steers 95.8 %, with a small temperature coefficient of
its own. The limit is ±5 V. Up and down steps are then as equal as the OTA's
own output mirrors make them, with no midpoint reference to drift. **The sign is worth a minute**: a 1 must raise
the integrator that the LM311 compares the audio against. Reversed, the encoder
loop is positive feedback and sits on a rail, while a decoder merely inverts —
so a wrong decoder passes a listening test and a wrong encoder does not.

**One ground, and keep the clocks off the integrator.** `C_int ∥ R_int` is a
300 kΩ node, and the smallest step on it is `I_min · t_bit / C_int` =
3.8 µA × 15.6 µs / 10 nF = **5.9 mV**, in a ±1 V full scale. A few millivolts of
4.096 MHz on that node is the size of the idle step. On a breadboard: the
engine on its own board, the oscillator and '4040 on another, the grounds
joined once at the sampling '74 and the LM311's emitter, 100 nF at every
package and 10 µF on each rail of each board.

---

## 5. Not measured

- **Everything in §1, §3 and §4.** Data-sheet reading and arithmetic. §3's
  pulse widths and delays are typical 74HC figures at 5 V.
- **§2.4's drive.** The ±4 % is a sum of tolerances. The ripple sensitivity at
  `I_min` — 157 mV of control voltage on a 5 V rail — is the thing to look at
  first on a bench.
- **How `I_min` mismatch sounds.** §2.3 is gain-matched segSNR, which counts a
  level-dependent gain as noise. It needs a render, as `mf8_render.py` does for
  the line.
- **§2.2 and §2.3 are from scratch scripts**, not repository tools: 8 s per
  talker, `talker1`, `talker4` and `talker6`, the 64 kbps parameters of
  `mf8.params`, the step law replaced in a copy of `cvsd.py`'s loop. The 64 kbps column of §2.3's second table is `tolerance.py`
  with `RATE = 64000` and nothing else changed. An `imin` field in
  `tolerance.py`, and its `RATE` moved to 64 000, would make both reproducible.
- **The syllabic and integrator tolerances at 64 kbps under the same caution.**
  ±10 % and ±20 % are the same scorer's figures and are as likely overstated as
  `I_min`'s.
- **The violation term under §3's change** — left open there.
