# 8-bit superframe carrier — specification

Six 64 kbps channels and a sub-commutated signalling channel in an 8-bit frame,
over one twisted pair in discrete 74HC logic. A channel slot is a DS0: 64 kbps
and octet-aligned, so it takes a CVSD voice card, a synchronous data card, or a
G.711 PCM stream.

Every number here was measured by `mf8.py` unless it is marked as analysis.
§15 lists what has not been measured.

> **Status: proposed, validated at the frame layer.** This is `mfspec.md`'s frame
> with the header replaced. The original header was measured broken in three
> independent ways (this document §§4.1–4.3) and none of those failures
> survives here. The physical layer is this document's unchanged, and is not
> re-measured; `line-codes.md` records the one open question about it.

---

## 1. What changed from `mfspec.md`, and why

| | `mfspec.md` | this spec |
|---|---|---|
| F bit | `1010`, period 2 | **`11111110`, period 8** |
| Superframe phase pinned by | two S-lane pads, 4 apart | **F itself** |
| Wrong superframe phases admitted | **56 of 64 hook states** | **0** |
| Acquisition | 8 alternating frames + one guard | **32 consecutive good frames** |
| Tracking after lock | *unspecified* | **+2/−1, floor 0, trip 12** |
| Squelch / mute | *absent* | **required, §13** |
| Data slot rules | *absent* | **§5** |

The 8-bit geometry, the 6 × 64 kbps payload, the sub-commutated signalling and
the pads-at-binary-boundaries idea are all `mfspec.md`'s and are kept. What is
replaced is the part that decides where the frame is.

---

## 2. Frame and superframe

**Frame — 8 bits, 15.625 µs, 64 kHz:**

```
 bit:   0     1      2      3      4      5      6      7
      [ F ][ S ][ C1 ][ C2 ][ C3 ][ C4 ][ C5 ][ C6 ]
      000   001   010    011    100    101    110    111    <- mux address
```

**Superframe — 8 frames, 125 µs, 8 kHz:**

| state | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|---|
| **F** | 1 | 1 | 1 | 1 | 1 | 1 | 1 | **0** |
| **S** | A1 | A2 | A3 | **1** | A4 | **0** | A5 | A6 |

`An` is channel *n*'s signalling bit; the two fixed S bits are the guard (§3.2).
Signalling is one bit per channel per superframe — **8 kbps per channel**.

The superframe counter is the only phase state in the system, and it does three
jobs: it addresses the signalling demultiplexer, it carries the framing word,
and it is the octet counter (§6).

---

## 3. The header

### 3.1 F — the word `11111110`

F carries an 8-bit word across the superframe, so **one check pins both the bit
alignment and the superframe phase.** The word is `11111110`: one zero, at
state 7.

Why this word and not the alternatives this project has already killed. The
figure is the longest run of consecutive frames a payload lane can match the
word, over every superframe phase — acquisition needs 32 in a row, so anything
below 32 is rejected *deterministically*:

| word | CVSD speech | CVSD silence | constant 1 | constant 0 | random |
|---|---|---|---|---|---|
| `10101010` — `mfspec` | 4708 | **8192 (the whole clip)** | 1 | 1 | 12 |
| `11101110` — period 4 | 4 | 3 | 3 | 1 | 14 |
| **`11111110`** | **4** | **3** | **7** | **1** | **20** |
| `11111100` | 4 | 2 | 6 | 2 | 14 |
| `11101100` | 5 | 3 | 3 | 2 | 14 |

`1010` *is* CVSD silence, which is why `mfspec`'s Stage 1 was no filter at all.
A period-4 word cannot pin an 8-state superframe. Of the three period-8 words
that work, `11111110` is chosen because its generator is the cheapest: F is 0
only at state 7, so

```
F = NAND(q2, q1, q0)        one 3-input gate, from the superframe counter
```

and the receiver forms the identical term from its own counter.

### 3.2 The guard — S at states 3 and 5

F alone is not sufficient, because a data card can carry the framing word. The S
lane supplies a second, independent condition: **S = 1 at state 3 and S = 0 at
state 5.**

Both positions are chosen, and both choices are load-bearing:

- **Same parity** (3 and 5 are both odd) **with different required values.** A
  period-2 lane — CVSD silence — gives the *same* value at two same-parity
  states, so it fails deterministically. (`mfspec`'s pads at 3 and 7 had this
  property, and it is the one thing about that header that worked.)
- **Different from the F word at those states.** `11111110` is 1 at both state 3
  and state 5, so a data lane carrying the framing word satisfies F and fails the
  guard. `mfspec`'s pads were `1,0` at states 3 and 7 — *exactly* what the word
  does there — so the guard added no information: **384 of 512 false locks** on
  the F word, against **0** here.
- **Not half a superframe apart.** The regular choice, 3 and 7, fails on this
  count even with the values inverted to `0,1`. A 4-state shift maps 3 and 7 onto
  each other, swapped. With every channel off-hook the S lane has a single zero
  and can impersonate F, and locking on it shifts the receiver by exactly 4 — so
  the guard reads the *next* lane at states 7 and 3, where the F word gives `0,1`,
  which is what the inverted guard wants. One data card in seat 1 then
  false-locks on 1 of 512 start-ups. That is a layout §5's slot rule permits, and
  the rule is only worth having if "one data card, any seat, anything" holds with
  no exceptions. It is the same half-superframe symmetry that sank `mfspec`'s
  pads, arriving by a different route. 3 and 5 have no such symmetry, and cost
  one XOR gate more.

| guard | F word in every lane | one data card, worst seat |
|---|---|---|
| **3,5 = `1,0` — this spec** | **0 / 512** | **0 / 512** |
| 3,7 = `0,1` — regular | 1 / 512 | **1 / 512** |
| 3,7 = `1,0` — `mfspec`'s values | **384 / 512** | **1 / 512** |

(`mf8.py guard`: all 64 hook states × 8 skews per cell.) **Both** 3,7 layouts
break the slot rule; only 3,5 is clean in every seat.

The decode is three gates. States 3 (`011`) and 5 (`101`) are the only two with
`q0 = 1` and `q1 ≠ q2`, and at those two the expected value is `q1` itself:

```
guard enabled  =  q0 · (q1 XOR q2)
guard expected =  q1
```

### 3.3 Why the superframe phase can no longer be held wrong

At offset *d* the receiver expects `11111110` and sees it rotated by *d*. For
every *d* ≠ 0 that mismatches at **2 frames in every 8**, so the longest possible
run of good frames is 6 — against the 32 that acquisition requires:

| offset | frames matching of 8 | longest good run |
|---|---|---|
| 0 | 8 | (indefinite) |
| 1 … 7 | 6 | **6, 5, 4, 3, 4, 5, 6** |

**Hook states cannot enter into it**, which is the whole difference from
`mfspec.md`: there the phase was pinned only by two pads gated by hook bits, and
56 of 64 hook combinations admitted a wrong phase. Enumerated here over all 64
hook states: **0 admissible wrong superframe phases.**

---

## 4. Framer

One check, one acquisition counter, one up/down counter. The reference model is
`mf8.framer`.

```
good frame :=  F == word[sfc]
               AND ( sfc != 3  OR  S == 1 )
               AND ( sfc != 5  OR  S == 0 )

acquire    :  the word has exactly one zero, at state 7, so F == 0 IS the phase
              marker.  At a bit alignment with no candidate phase yet:
                  F == 0             -> load sfc = 7, start the count
                  8 frames, no zero  -> this cannot be the F lane, so slip one
                                        line bit and hunt at the next alignment
              With a candidate, the check is predictive; any mismatch slips one
              line bit and restarts the hunt.  Lock at 32 consecutive good frames.

track      :  the same check, +2 bad / −1 good, floor 0, trip at 12.
on trip    :  not locked, slip one line bit, acquire again.
```

**The superframe phase is read, not searched.** That makes acquisition a search
over 8 bit alignments rather than 8 × 8 combinations, and it is what lets slip
recovery be 8–15 frames (§4.2). The 32-frame count is §4's.

**Why +2/−1 and not +1/−1.** A `+1/−1` counter trips only when more than *half*
of frames fail. At a wrong alignment this check fails at almost exactly half —
the word is seven ones and one zero, so a random payload lane matches it 50% of
the time — and the counter random-walks instead of climbing. Measured over the
line at 10 impulses/s, a transient false lock held **28 050 frames** with
`+1/−1`. `+2/−1` trips above a *third*, which that 50% clears easily, and
§4 measured `+2/−1` as the correct pairing for a **predictive**
check, where one line error spoils one frame rather than four. §4.2 shows it
costs nothing in false reframes.

Both of these were found by running the chain end to end (§7). Neither was
visible at bit level: on clean data the old search locked at frame 31 and the old
counter never tripped.

### 4.1 False locks — measured

Every start-up skew, every payload class this project has used to break a framer,
plus the adversarial case constructed against *this* header:

| payload | locks | **false** | wrong sf phase | acquisition, frames |
|---|---|---|---|---|
| speech | 8/8 | **0** | **0** | 37–54 |
| idle (CVSD silence) | 8/8 | **0** | **0** | 37–54 |
| all constant 0 | 8/8 | **0** | **0** | 37–46 |
| all constant 1 | 8/8 | **0** | **0** | 38–78 |
| random data | 8/8 | **0** | **0** | 37–54 |
| octet `10110010` | 8/8 | **0** | **0** | 37–46 |
| one data card + idle | 8/8 | **0** | **0** | 37–54 |
| one data card + speech | 8/8 | **0** | **0** | 37–54 |
| **the F word as data** | 8/8 | **0** | **0** | 38–86 |
| the F word beside silence | 8/8 | **0** | **0** | 37–62 |
| **the F word beside a guard-satisfying pattern** | 8/8 | **6** | **0** | 37–38 |

Exhaustively over all 64 hook-state combinations × all 8 skews — 512 trials per
row — **0 false locks and 0 wrong superframe phases** on idle, both constants,
one data card, the F word in every lane, and the F word beside silence.

**The last row is the exception, and it is not closed by the framer.** Two
*adjacent* data cards, one carrying the framing word and the other a pattern that
satisfies the guard, hold a wrong alignment: 6 of 8 skews here, 384 of 512
exhaustively. At a wrong alignment the F check lands on one lane and the guard on
the next, so with both lanes unconstrained there is nothing left to gate them.
**No confirmation count reaches it** — the match is exact, not probabilistic — so
it is closed by a slot rule instead. That is §5, and it is the one real cost this
frame carries.

Acquisition is **37–86 frames, 0.58–1.3 ms** at a 64 kHz frame rate.

### 4.2 Line errors and slip recovery — measured

6.25 s of random payload, tracking with the `+1/−1` trip-16 counter:

| line BER | locked frames | **LOF events** | off-phase frames | time down |
|---|---|---|---|---|
| 0 | 399 961 | **0** | **0** | 0.01% |
| 1e−04 | 399 961 | **0** | **0** | 0.01% |
| 1e−03 | 399 937 | **0** | **0** | 0.02% |
| 1e−02 | 399 937 | **0** | **0** | 0.02% |
| **3e−02** | 399 937 | **0** | **0** | 0.02% |

Zero loss-of-frame events to 3e−02, which is §4's standard. For
contrast, `mfspec.md` with no counter took **10 011 unlocks and 60.7% downtime
at 1e−02** on the same class of line (§4).

Recovery after an induced slip, every slip size:

| slip, bits | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|
| frames misaligned | 8 | 12 | **15** | 12 | 11 | 13 | 13 |

**Worst case 15 frames = 0.23 ms.** Reading the superframe phase
from the marker rather than searching for it is what does this: there is no
second phase to re-find, so recovery costs little more than re-finding the bit
alignment. (An earlier nested-search version of §4 measured 35–176 frames here.)

---

## 5. Slot rules

One rule, and it is measured rather than argued:

> **Two data cards may not occupy adjacent slots.**

A voice channel is CVSD and cannot hold a wrong alignment. A data card can carry
anything, including the framing word — and at a wrong alignment the F check lands
on one lane while the guard lands on the *next* one, so two adjacent data cards
can satisfy both halves with neither constrained.

Adversarial content — the F word in one lane, a guard-satisfying pattern (bit 3
= 1, bit 5 = 0) in another — over all 64 hook states × 8 skews:

| layout | false locks |
|---|---|
| one data card, **any** seat, voice or idle elsewhere | **0 / 512** |
| two data cards, **non-adjacent** (1,3) (1,4) (1,6) (2,4) (2,6) (3,6) (4,6) | **0 / 512** |
| six data cards, ordinary **random** content | **0 / 512** |
| **two data cards, adjacent** (1,2) (2,3) (3,4) (4,5) (5,6) | **128–384 / 512** |

Note the third row: **ordinary data is safe in every seat.** The hole needs the
framing word specifically, not merely arbitrary content, which is why the rule is
about adjacency and not about scrambling.

This is the same shape of rule a 4-bit static framing word needs ("any seat, but
never two adjacent"). A frame that carries a signalling bit in *every* frame can
avoid needing it, by strapping that bit high so one half of the check is never
arbitrary data — a bit this frame does not have, because signalling is
sub-commutated into the superframe. **That is the price of §2's efficiency,
stated plainly: three data cards of six, not six.**

---

## 6. Octet alignment — the slot is a DS0

The superframe counter is **already the octet counter.** It has 8 phases, a
channel takes one bit per frame, so superframe state *k* is bit *k* of that
channel's octet:

```
superframe state   0   1   2   3   4   5   6   7
signalling S      A1  A2  A3   1  A4   0  A5  A6    -> the '259 address
channel n octet   b0  b1  b2  b3  b4  b5  b6  b7    -> the byte boundary
```

At a 64 kHz frame rate the superframe rate is 64/8 = **8 kHz, the PCM sample
rate exactly**, so one superframe carries one sample. A PCM card is a shift
register clocked by the frame clock and transferred at state 7 — one 74HC164 and
a latch per channel.

This matters because a framer that establishes bit alignment and slot identity
establishes nothing coarser, so a plain synchronous pipe is not octet-aligned and
the endpoints must find their own byte phase. Here it is aligned, for no extra
logic, and the slot is a true DS0 rather than merely a 64 kbps pipe.

**It depends entirely on §3.3.** If the superframe phase could be held wrong — as
it could in `mfspec.md` — a wrong phase would rotate every PCM sample and produce
garbage audio on a link that is otherwise bit-perfect. The phase is worth pinning
properly for signalling alone; carrying octets on it makes that mandatory.

---

## 7. End to end, over the line

`mf8_line.py`. Six independent LibriSpeech talkers → CVSD 64 kbps → the mf8
frame → a real waveform in both line codes → 1.8 MHz cable → impairment →
receiver → framer → per-channel CVSD decode. 1.0 s clips.

segSNR is scored inside the **longest contiguous locked run**, against the same
codec bits over the **same window** with no link in the path, so the "Δ" column
is what the *carrier* adds. The frame offset is found rather than assumed,
because a slip re-phases the stream and can rotate the channel slots.

### 7.1 A clean line is transparent

| code | segSNR | down | LOF | Δ mean | Δ worst | max BER |
|---|---|---|---|---|---|---|
| differential Manchester | 21.23 dB | 0.06% | **0** | **+0.00** | **+0.00** | **0** |
| AMI | 21.23 dB | 0.06% | **0** | **+0.00** | **+0.00** | **0** |

Per channel, differential Manchester:

| channel | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---|---|---|---|---|---|
| segSNR | 20.70 | 14.85 | 29.04 | 19.87 | 14.23 | 28.71 |
| vs codec | **+0.00** | **+0.00** | **+0.00** | **+0.00** | **+0.00** | **+0.00** |
| bit BER | 0 | 0 | 0 | 0 | 0 | 0 |

**The carrier adds exactly nothing**, in either code. The 14–29 dB spread across
channels is the talkers' own crest factors, not slot position — the Δ row is
+0.00 for all six. Isolation: off-diagonal 0.134 against a source-correlation
floor of **0.129 measured on the same 1.0 s window**, an excess of +0.005. (The
0.009 floor in §9.3 is for 30 s clips; a short window
correlates more by chance, and reading an off-diagonal against a mismatched floor
is the error that section records.) With BER identically zero the recovered bits
*are* the transmitted bits, so crosstalk is exactly zero by construction and the
matrix can only report its own floor.

### 7.2 Noise — and the two codes fail differently

| condition | differential Manchester | AMI |
|---|---|---|
| sd 0.3 | +0.00 dB, 0 LOF | +0.00 dB, 0 LOF |
| sd 0.4 | **+0.00 dB**, 0 LOF | −0.11 dB, 0 LOF |
| sd 0.5 | **+0.00 dB**, 0 LOF | **−5.59 dB**, 0 LOF |
| sd 0.6 | **+0.00 dB**, 0 LOF | **−16.08 dB**, 0 LOF |
| sd 0.7 | −0.79 dB, **5 LOF**, 421 ms clean | **no lock** |
| impulse 1/s | +0.00 dB, 0 LOF | +0.00 dB, 0 LOF |
| impulse 10/s | **−0.01 dB**, 5 LOF | −0.01 dB, 1 LOF |
| impulse 100/s | chopped, 71 LOF | chopped, 13 LOF |
| atten 0.25 | **+0.00 dB**, 0 LOF | −0.11 dB, 0 LOF |
| atten 0.12 | chopped, 462 LOF | chopped, 52 LOF |

Differential Manchester is transparent to sd 0.6 where AMI is degraded from 0.4,
which is `line-codes.md` §3's raw-BER result now heard as audio.

**The interesting column is not which is better but how each fails.** At sd
0.5–0.6 **AMI never loses frame** — 0 LOF, 0.06% downtime — while the audio falls
5 to 16 dB. At sd 0.7 differential Manchester's audio inside a clean stretch is
only −0.79 dB, but the link breaks five times. **AMI degrades in fidelity;
differential Manchester degrades in continuity.** That is the same split
`line-codes.md` §4.3 found under impulse noise, and it holds on a Gaussian floor
too. For voice behind a mute (§11), continuity is the one that is audible as
damage, which is a point in AMI's favour that the raw margin figures hide.

### 7.3 What this found in the framer

Both defects in §4 were found here and are invisible at bit level:

| | symptom on clean data | symptom over the line |
|---|---|---|
| nested acquisition search reached only even superframe offsets | lock at frame 31 | lock at frame **41 082** after one impulse-induced slip |
| `+1/−1` counter against a check that fails at 50% | never tripped | transient false lock held **28 050 frames** |

Neither would have been caught by any amount of further bit-level testing. That
is the argument for this section existing.

---

## 8. Rates and the family

F + S + N channels must be a power of two, so **N = 2, 6, 14**.

| frame | N | per-channel | line | baud | capacity | reach | superframe |
|---|---|---|---|---|---|---|---|
| 4 b | 2 | 64k | 256k | 0.512 M | 128k | **1.00×** | 4 fr |
| **8 b** | **6** | **64k** | **512k** | **1.024 M** | **384k** | 0.71× | **8 fr** |
| 8 b | 6 | 32k | 256k | 0.512 M | 192k | **1.00×** | 8 fr |
| 16 b | 14 | 32k | 512k | 1.024 M | 448k | 0.71× | 16 fr |

**This spec is N = 6 at 64 kHz.** It is the only mode that is one-for-one with a
DS0 (§6). Reach is the √f law scaled to `frame-rate.md` §1's reference — ratios
sound, kilometres not measured. `frame-rate.md` analyses the choice; the short
version is that line rate sets reach and frame length decides how it is divided,
so 64 kbps channels are available at any reach, at two of them for 1.00× or six
for 0.71×.

Only N = 6 is specified here. The other frame lengths need their own F word and
guard positions, and the mis-strap case between them is **not measured**.

---

## 9. Line code — differential Manchester

Unchanged from §9, and not re-measured; the frame layout cannot affect
the line code.

- Transition at **every** cell boundary. This is the clock.
- An additional transition at mid-cell **iff** the data bit is 0.

At 512 kbps: **1.024 MBaud**, 977 ns half-cell, 512 kHz maximum fundamental.
Two-level, DC-free with disparity bounded at ±1 cell, polarity-blind (verified
bit-identical under a tip/ring swap, `line-codes.md` §12), and a transition every
bit so clock recovery never starves.

**Oscillator: 4.096 MHz.** It divides every family rate exactly and reaches the
2.048 MHz half-bit clock the top rate needs. Note that `mfspec.md` §2 specified a
512 kHz master clock, which is *half* what the modulation requires — a half-bit
clock at 1.024 MHz cannot be divided down from 512 kHz.

`line-codes.md` records the one open question: AMI is measured better under
impulse noise and worse on Gaussian noise and attenuation, and which matters is a
plant measurement nobody has made.

### 9.1 Oscillator and clock chain

**4.096 MHz**, a standard E1-family value. It is the lowest crystal that reaches
the 2.048 MHz half-bit clock of the fastest family rate, with the one divide a
Pierce oscillator's duty cycle needs. Nothing on the card needs a faster clock.

```
4.096 MHz ─→ 74HC4040 prescaler ─→ RATE jumper ─→ HB, half-bit clock
                                                       │
                                                 ÷2 ─→ H, line bit clock
```

| rate jumper | line rate | HB (half-bit) | H (line bit) |
|---|---|---|---|
| Q1 | 1024 kbps | 2.048 MHz | 1.024 MHz |
| **Q2** | **512 kbps — this spec** | **1.024 MHz** | **512 kHz** |
| Q3 | 256 kbps | 512 kHz | 256 kHz |
| Q4 | 128 kbps | 256 kHz | 128 kHz |
| Q5 | 64 kbps | 128 kHz | 64 kHz |

The frame counter is clocked from H rather than taken as a tap on the prescaler.
The rate jumper moves the half-bit tap, so on one ripple chain the frame counter
would move with it and the mux address would need a matrix of jumpers. Re-clocked
from H, its bits sit on fixed pins at every strap. **That one 74HC393 is the whole
price of the rate strap.**

**Accuracy is nearly irrelevant.** The far-end receiver tolerates ±13% of a cell
and the oscillator contributes ~0.01%. Specify the crystal for unit-to-unit
repeatability, not accuracy.

**Ripple.** The skews that matter are within the frame counter, two or three
stages of a '393 — tens of nanoseconds against a settling budget of half a cell,
977 ns here. Scope it at bring-up.

### 9.2 Encoder circuit — one gate, one flip-flop

§9.2, unchanged. Let `H` be the half-cell phase (0 in the
first half of a line cell, 1 in the second) and `HB` the half-bit clock:

```
        line bit ──┐
                   ├── NAND ──> EN ──┬── J ┐
        /H ────────┘                 └── K ┤ 74HC74/109  ──> line
                                           │  clocked by HB
        HB ────────────────────────────────┘

EN = NAND(/H, line bit) = H OR NOT(line bit)
```

| H before edge | line bit | EN | behaviour |
|---|---|---|---|
| 1 | 0 | 1 | entering a new cell — boundary transition, always |
| 1 | 1 | 1 | entering a new cell — boundary transition, always |
| 0 | 0 | 1 | mid-cell — transition, encoding a 0 |
| 0 | 1 | **0** | mid-cell — **hold**, encoding a 1 |

A JK wired J = K = EN toggles when EN is high and holds when it is low, which is
exactly the code. H and the flip-flop are both clocked from HB; the JK samples
H's value from *before* the edge, so same-edge synchronous clocking is correct,
but it depends on the divider's clock-to-Q exceeding the JK's hold time. 74HC
satisfies that comfortably — **check it against the specific parts, because a
hold violation works on a warm bench and fails at temperature.**

### 9.3 Output stage and line interface

| item | specification |
|---|---|
| Driver | 75176 differential transceiver, driver half |
| Series matching | two ~50 Ω resistors into the 100–135 Ω pair, ~25 mA from a 5 V swing; trim against the actual cable |
| Slew limiting | **150 ns edges**, one series R with a shunt C, switched by the rate jumper. At 1.024 MBaud that is 15.4% of a 977 ns half-cell — still inside the eye, but tighten toward 75 ns if the eye matters more than radiated emissions. Do not skip it: a raw 75176 edge into outside plant is unnecessarily noisy |
| Transformer | 1:1, **centre-tapped on the line side, ≥ 33 mH**. Running disparity is bounded at ±1 cell and under 5% droop needs `L/R > 20 × cell`; 33 mH covers the whole family down to the 64 kbps line rate (arithmetic, not simulated) |
| Centre tap | brought out to an unpopulated footprint for a simplex feed. DC injected there is common-mode and the ampere-turns cancel. **Specify it now** — retrofitting means a new transformer |
| Protection | gas tube to ground on both conductors, series PTC or fuse, TVS. **The TVS must clamp above the eventual 48 V feed voltage**, not above signal level |
| Termination | the pair's characteristic impedance, 100–135 Ω, on the line side of the comparator. A receiver must never look like a bridged tap |
| Preamp / equaliser | footprint, unpopulated on short spans; populate when span loss leaves under about 0.5 V at the comparator |

**Deliver about a volt to the comparator.** Its hysteresis is fixed in millivolts
(~50 mV for a 75176-class receiver), so what matters is the *ratio* to received
amplitude — and §7.2's attenuation rows are that ratio running out. A single span
tolerates 20%; **specify ≤ 10%**, which is 0.5 V for 50 mV of hysteresis.

### 9.4 Decoder circuit — no PLL, no clock

§9.4, unchanged. The receiver times the gap between transitions
against two thresholds. There is no clock anywhere on the receive timing path.

```
on each transition from the comparator:
    if less than DEAD since the last ACCEPTED transition:   ignore it
    otherwise accept it:
        if more than 0.75 cell since the previous accepted: emit 1, clear MID
        else if MID is set:                                 emit 0, clear MID
        else:                                               set MID
```

A 1 bit has no mid-cell transition, so its gap is a full cell. A 0 bit produces
two half-cell gaps, and the MID flip-flop pairs them. **The state self-heals:**
any full-cell gap clears MID, so a disturbed state recovers within a couple of
bits and there is no lock to lose.

| function | part |
|---|---|
| Line interface | transformer, then two RC sections at the symbol rate |
| Comparator | hysteresis ≤ 10% of received amplitude (≈1 V at a 50 mV comparator) |
| Transition detector | 74HC86: comparator output XOR a short RC-delayed copy — one pulse per transition |
| Dead-time timer | ½ 74HC221, **non-retriggerable**, 0.2 cell |
| Classifier timer | ½ 74HC123, **retriggerable**, 0.75 cell |
| LONG sample, MID state | 74HC74 |
| Bit strobe | accepted transition gated by `LONG + MID`; recovered bit = LONG |

| parameter | specify | usable range |
|---|---|---|
| Classifier threshold | **0.75 cell** | ±13% at the sd 0.4 design limit |
| Dead time | **0.2 cell** | 0.05–0.30 cell to sd 0.5 |
| Comparator hysteresis | ≤10% of received | 20% on a single span |
| Carrier-detect timeout | 2 cells | never trips on signal |

A 1% resistor and a 2% C0G capacitor give ±3% against the ±13% needed. **Check
the timer IC's own pulse-width tolerance against the remaining ±10%** before
committing. At 1.024 MBaud the absolute window is ±98 ns, where layout stray
capacitance stops being negligible — scope it at bring-up.

**Sample, then retrigger.** At each accepted transition the classifier timer's
state must be captured before that same transition retriggers it. The timer's
trigger-to-output delay gives the flip-flop its hold margin; confirm it against
the specific parts, as §9.2 does for the encoder.

### 9.5 Input filter

A low-pass ahead of the comparator sets how much line noise reaches the slicer,
and **it must move with the rate** — a filter left at the fastest setting puts a
slow line rate at many times its symbol rate and throws its noise advantage away.

**Specify: two first-order RC sections, corner at the symbol rate** — 1.0 MHz
here. Two RC sections reach within one grid step of a second-order Butterworth
optimum and hold it from 0.75× to 1.5× the symbol rate, so component tolerance
does not matter. Buffer them, or make the second section's R at least ten times
the first so it barely loads it.

### 9.6 Carrier detect

A retriggerable timer (the other half of the '123), retriggered by every
comparator transition, timeout **2 cells**. Timed out means no carrier. A valid
line has a transition every cell by construction and never trips it; the
quiet-noise case that makes squelch mandatory (§12) reads as no carrier 92% of
the time.

**Feed no-carrier into the framer as a forced loss of frame**, not only into the
mute OR. Every timeout then drops lock and the mute is held until 32 good frames.
Without that, a detector flickering at 92% would chatter the mute.

### 9.7 Rate plug

Five components move with the line rate. Put them on a **plug-in header, one plug
per rate**, so a rate change swaps all five and none can be left behind:

| line rate | symbol rate | filter corner | classifier, 0.75 cell | dead time, 0.2 cell | carrier timeout |
|---|---|---|---|---|---|
| 1024 kbps | 2.048 MBaud | 2.0 MHz | 732 ns | 195 ns | 1.95 µs |
| **512 kbps — this spec** | **1.024 MBaud** | **1.0 MHz** | **1 465 ns** | **391 ns** | **3.9 µs** |
| 256 kbps | 512 kBaud | 512 kHz | 2 930 ns | 781 ns | 7.8 µs |
| 128 kbps | 256 kBaud | 256 kHz | 5 859 ns | 1 563 ns | 15.6 µs |
| 64 kbps | 128 kBaud | 128 kHz | 11 719 ns | 3 125 ns | 31.3 µs |

**The receiver's rate must match the FAR end's transmitter**, not this end's. The
two directions are independent and may run different rates, so the rate plug is
set per direction.

---

## 10. Transmitter

```
4.096 MHz ─→ 74HC4040 ─→ RATE jumper ─→ half-bit clock HB ─→ biphase encoder
                                              │
                                        ÷2 ─→ H, line bit clock
                                              │
                            3-bit frame counter (bit position in frame)
                                              │ wrap
                            3-bit superframe counter  q2 q1 q0
                                     │                     │
                          F = NAND(q2,q1,q0)        S mux address
```

| function | part | notes |
|---|---|---|
| Prescaler and rate tap | 74HC4040 | one per card |
| Frame + superframe counters | 74HC393 | 3 stages each, both halves |
| Frame mux | 74HC151 | in0 = F, in1 = S mux, in2–7 = C1–C6, addressed directly |
| Signalling mux | 74HC151 | addressed by the superframe counter; state 3 tied high, state 5 tied low |
| F generator | ⅓ 74HC10 | one 3-input NAND |
| Biphase encoder | ½ 74HC74 + ¼ 74HC00 | §8.1 |
| Driver | 75176 | §8.1 |
| **Total** | **≈ 6 packages** | |

The framing bits are **mux inputs, not an override**. §9.2
puts the framing field last so the mux address needs no arithmetic, and pays for
it with an S/T select gate, a framing-data AND and an output selector. Here the
address is still offset-free *and* the override path disappears: channel *n*
wires to input *n*+1, which is layout rather than logic. A gate-level model
reproduces the frame bit-for-bit (§4).

**One race to watch.** F is a superframe-counter output read at bit-count 0,
which is when that counter has just ticked. Clock the superframe counter off the
opposite edge, or from the 7→0 transition of the frame counter.

---

## 11. Receiver

| function | part |
|---|---|
| Interval classifier | §8.2 — '86, '221, '123, '74 |
| Superframe counter | ½ 74HC393 |
| Expected F | ⅓ 74HC10 — `NAND(q2,q1,q0)` |
| Guard decode | ¼ 74HC86 + ¼ 74HC08 — enable `q0·(q1⊕q2)`, expected `q1` |
| Compare and good-frame gate | 74HC86 / 74HC08 remainder |
| Acquisition count to 32, rephase count to 8 | ½ 74HC393 |
| Loss of frame, +1/−1 floor 0 trip 16 | 74HC193 — up on bad, down on good, carry = trip |
| Lock state | ½ 74HC74 |
| Signalling demux | 74HC259, addressed by the superframe counter, 6 of 8 used |
| Channel demux | frame counter, shared |
| **Total** | **≈ 9 packages** |

Everything except the interval classifier is shared with, or the same shape as,
§9.4's. The framer is about five of those nine, which is
about five packages — **a framer, not a package-count problem.**

---

## 12. Channel cards

A slot takes one of three cards. All use the same backplane signals: the frame
clock, a C bit in and out, an A bit in and out, and the mute line.

### 12.1 CVSD voice card

Semi-analog CVSD, E&M four-wire. The card's components set slew, not step size,
so the same card runs at any family rate with no strap.

| parameter | value |
|---|---|
| bit rate | set by the mode, not the card — **64 kbps here** |
| run window | 3 bits |
| τ_syl | 6 ms |
| τ_int | 3 ms |
| companding | 30 dB (31.6:1) |
| slew | 12 000 full-scale units/s |

| component | value | note |
|---|---|---|
| `C_int` | 10 nF film | |
| `R_int` | 300 kΩ | τ_int = 3 ms |
| `Iabc` max | **120 µA** | `slew · C_int` — **the bit rate cancels** |
| `Iabc` min | 3.8 µA | 31.6:1 companding |
| `C_syl` | 100 nF film | |
| `R_syl` | 60 kΩ | τ_syl = 6 ms |

| network | tolerance | failure mode |
|---|---|---|
| integrator R·C | ±30% | distortion |
| **syllabic R·C** | **±20%** | distortion — the binding spec |
| step size | ±30% | **pure gain error, no distortion at all** |

**A** is the E&M signalling bit: the M lead sensed through an opto-isolator to
the TX card, the E lead driven from the received A bit through the §13 RC.

### 12.2 Data card

Synchronous and bit-transparent: one data bit per frame on C, clocked by the
frame clock — the TX card's for transmit, the recovered frame clock for receive.
No elastic store and no slip. At a 64 kHz frame rate the pipe is **64 kbps**.

Unlike the frame it replaces, this pipe **is octet-aligned** (§6): the superframe
counter is the octet counter, so a data card can be a true DS0 and carry G.711
without the endpoints finding their own byte phase.

**A data card must not sit beside another data card** (§5). One in any seat is
safe whatever it carries; any non-adjacent pair is safe; ordinary random data is
safe in all six seats.

### 12.3 Empty slot

An unfitted slot presents A = 0 and C = a `1010` toggle, fed through 4.7 kΩ so a
fitted card overrides it. The toggle matters for what the far end *hears* when a
slot is empty at one end only: a constant fill drives the far CVSD integrator
rail to rail, where `1010` is the codec's own idle pattern and decodes as silence.

---

## 13. Failure behaviour

| event | response |
|---|---|
| Not locked | **Mute all channel outputs**; force received A bits idle (74HC259 clear); data cards present RXD = 1 |
| Loss of signal, no transitions | **Squelch — required** |
| Slip | detected and corrected within 2.75 ms (§4.2) |
| Wrong superframe phase | cannot be held (§3.3) |
| Two adjacent data cards | **forbidden** (§5) |
| Card type mismatch slot for slot | loud, locked, not squelched — label every slot |

**Squelch is mandatory, not optional.** §13 measured a CVSD card with
the framer bypassed on a dead pair with a little induced noise: **+24.1 dB rms,
+47.7 dB peak** relative to normal speech. Sparse transitions make the monostable
emit long runs of 1s and the syllabic compander reads it as a loud signal.
`mfspec.md` specified no squelch, no mute-on-unlock and no carrier-detect
timeout.

---

## 14. Signalling

One bit per channel per direction, sampled once per superframe at **8 kHz**.
A = 1 means active. E&M is a two-lead interface with one lead driven and one
sensed, so one bit each way carries seizure, answer, disconnect, dial pulses and
wink or delay start.

Received A bit → RC, τ = 2 ms → 74HC14 Schmitt: one resistor, one capacitor and
one gate per channel, serving as both error filter and debounce. §14
measured 0 spurious assertions to 6e−2 BER at a 32 kHz signalling rate; here the
rate is 8 kHz, so a burst of *k* bad samples lasts 125*k* µs instead of 31*k* µs.
The measured worst run was 4 samples, which is 0.5 ms against the ~1.7 ms needed
to assert — **still clear, with about 3.4× margin instead of 13×.** Analysis, not
re-measured.

---

## 15. What is and is not measured

**Measured here** (`mf8.py`): the F word choice; false locks over ten payload
classes at every skew, and exhaustively over all 64 hook states for the six that
can hold an alignment open; the superframe-phase enumeration; the slot rule;
acquisition time; loss of frame to 3e−02 BER; slip recovery at every slip size.

**Inherited from this document and not re-measured**: the whole physical layer — line
code, driver, transformer, filter, comparator, classifier tolerances, reach,
noise margin, squelch levels, CVSD performance, signalling RC.

**Measured over the line** (`mf8_line.py`, §7): six independent talkers through
the whole chain in both line codes, clean and under Gaussian noise, impulse noise
and attenuation; per-channel segSNR against a matched control; isolation against
a floor computed on the same window.

**Not measured at all:**

- **Mis-strap between family members** (N = 2, 6, 14). A period-4 word defeats a
  ×2 mis-strap by a divisibility argument; the equivalent argument for
  `11111110` has not been made or tested.
- **The other frame lengths.** Only N = 6 has an F word and guard positions.
- **The residual slot-rule risk beyond adjacency.** Three data cards at seats
  1, 3, 5 is safe by the rule but was not enumerated as a triple.
- **Squelch, mute timing and carrier detect.** §13 specifies them from
  the squelch measurement; none has been exercised on this frame. §7's "chopped" rows are
  exactly the condition a mute has to handle, and what a listener would hear
  through one has not been measured.
- **Long runs.** §7 is 1.0 s per cell, one seed. Enough to establish that the
  carrier is transparent and to place the failure modes; not enough for outage
  rates. §4.2's 6.25 s BER runs are the longest anything here has run.
- **Repeatered spans.** Nothing here has been through more than one span.

**And the open question is not in this document.** `line-codes.md` §6 records it:
differential Manchester and AMI rank opposite ways under impulse noise, §7.2
reproduces that split on this frame, and which matters depends on the impulse
rate on the target loops — a plant measurement. The curve that converts it into
a break rate is measured (`line-codes.md` §4.5): 1 break/s at 1.3 impulses/s for
differential Manchester and 7.3 for AMI, with AMI collapsing between 800 and 900.

---

## 16. Reproducing

```
python3 mf8.py            frame layer, ~15 min          (mf8.log is the run)
python3 mf8.py word       why 11111110 and not the alternatives
python3 mf8.py locks      false locks, every payload class and hook state
python3 mf8.py sfphase    superframe phase, exhaustive
python3 mf8.py guard      why the guard is at 3 and 5, not 3 and 7
python3 mf8.py seats      the slot rule
python3 mf8.py errors     line errors, acquisition, slip recovery

python3 mf8_line.py       over the line, ~20 min        (mf8_line.log is the run)
python3 impulse_sweep.py  impulse falloff, ~22 min      (impulse_sweep.log, .csv)
python3 mf8_line.py clean clean line, both codes, per channel, isolation
python3 mf8_line.py noise Gaussian sweep
python3 mf8_line.py plant impulse and attenuation
```

Caveats that affect how the numbers should be read:

- `mf8.py` is bit level throughout: no waveform, no noise beyond injected BER.
  `mf8_line.py` is the waveform, and §7.3 is why it exists — two defects in §4
  were invisible until the chain ran end to end.
- The impulse model (`phy.plant_noise`) is a damped ringing sinusoid with a
  randomly signed amplitude, so each event swings **both polarities** many times
  — a 40 kHz ring against a 512 kbps line reverses every 6.4 bit periods.
  Measured over 0.5 s at 200 events/s: min −3.165, max +2.859, mean −1.3e−04,
  and the fraction of samples below −0.1 (0.0193) matches the fraction above
  +0.1 (0.0191).
- The exhaustive hook-state sweeps use 3000-frame clips, which is ample for a
  32-frame acquisition but short for rare events.
- Speech is one talker rolled per channel, as elsewhere in this repository.
- this document is the review this design came out of, and records what the
  original header did and why each change here is here.
