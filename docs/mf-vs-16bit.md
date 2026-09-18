# `mfspec.md` against the 16-bit 7-channel frame

> **Review of the frame format.** On line coding the two formats are identical
> (§1). On complexity the encoder is better and the decoder is cheaper because
> it is missing load-bearing parts (§§3–4). Constant payload is safe — safer
> here than in the 16-bit frame (§5) — and random data holds lock for 31 s with
> zero unlocks (§6). Throughout, the missing loss-of-frame counter is the
> dominant defect: at matched payload quality it costs 50× the outage.
>
> **This review produced a design.** `mf8-spec.md` is the 8-bit frame with the
> header replaced, and every failure recorded in §4 is measured closed there.
>
> Two companion documents carry what began here and outgrew it:
> **`line-codes.md`** (is differential Manchester the right code at all?) and
> **`frame-rate.md`** (what should the frame rate be?). Everything was measured
> by `mfcmp.py`; `mfcmp.log` is the run.

Two formats, both differential Manchester on one pair at 512 kbps:

| | 16-bit, N = 7 (`spec.md`) | 8-bit (`mfspec.md`) |
|---|---|---|
| Frame | `[A1][C1]…[A7][C7][S][T]` | `[F][S][C1]…[C6]` |
| Frame rate | 32 kHz | 64 kHz |
| Voice channels | 7 @ 32 kbps | 6 @ 64 kbps |
| Header | 2 bits, end of frame | 2 bits, start of frame |
| Signalling | in-band, one bit per channel per frame | sub-commutated, 8-frame superframe |
| Multiframe phase anything depends on | none | **the signalling demux** |

---

## 1. Line coding — there is no difference to compare

Both formats are differential Manchester at 512 kbps, so both are 1.024 MBaud
with a 512 kHz maximum fundamental and a 977 ns half-cell. `mfspec.md` §2 is
`spec.md` §2.1's `N=7 @ 32k` row: same driver, same transformer, same slicer,
same 1465 ns monostable, same ±13% timing window, same −1.9 dB noise margin
against the 256 kbps reference, same 0.71× reach. Polarity-blind, DC-free,
disparity bounded at ±1 cell, no threshold and no AGC — all unchanged, because
none of it knows what the bits mean.

**The frame layout cannot affect the line code, and it does not.** Anything
`mfspec.md` §2 claims for the line is inherited, and the whole of this
comparison lives in §§2–15 below. §6 asks the separate question — whether the
code should be differential Manchester at all — by running this protocol over
both codes with noise.

Three things in §2 are wrong or need saying, none of them about the code
itself:

- **The stated master clock cannot generate the stated modulation.** 512 kHz is
  the *bit* clock. Differential Manchester needs a half-bit clock at the baud
  rate, 1.024 MHz, and a raw Pierce output is not 50% duty, so the crystal must
  be at least one divide above that: **2.048 MHz minimum**, 4.096 MHz to stay on
  the family value (`spec.md` §4.1). As written the oscillator is half the
  frequency the line needs.
- **74LS is the wrong family here.** Every tolerance the receiver rests on was
  measured in 74HC at 5 V — the ±13% classifier window, the ≤10% comparator
  hysteresis at a 50 mV input, the 0.2 cell dead time (`rx_review.py`). 74LS
  input current, VOH and monostable drift are a different set of numbers, and
  none of them has been measured. The named parts also do not quite fit: a
  74LS93 is ÷2 plus ÷8 with separate clocks, and two mod-8 counters are wanted
  (§3), so it is a 74LS393 or two '93s.
- "1024 kMaud" in §2 should read kBaud.

**Verdict on line coding: identical, and the two formats interoperate on one
physical layer.** A rate strap and a receiver rate plug are the only PHY items,
and both formats need the same ones.

---

## 2. What the 8-bit frame buys

This is the real result, and it is in `mfspec.md`'s favour. At 512 kbps:

| | 16-bit, N = 7 | 8-bit, mfspec |
|---|---|---|
| Voice payload | 224 kbps | **384 kbps** |
| Voice, % of line | 43.8% | **75.0%** |
| Signalling | 224 kbps | 48 kbps |
| Signalling per channel | 32 kbps | 8 kbps |
| Framing | 64 kbps | 80 kbps |
| Per-channel CVSD segSNR | 17.4 dB (14.9 worst talker) | **23.3 dB (19.7)** |

**1.71× the voice payload and +5.9 dB per channel, on the same pair at the same
reach.** The 16-bit frame spends 43.8% of the line sending hook states 32 000
times a second, where `spec.md` §9 needs one bit per 2 ms. Sub-commutating the
signalling recovers nearly all of it. Six channels at 64 kbps is a better
product than seven at 32 kbps, and the trade is not close.

That is the honest headline, and the rest of this document is the bill.

### 2.1 What the interleaved A bits were actually paying for

`spec.md` §3.2: *A and C bits alternate. No two adjacent payload positions may
both be static.* The A bits are not only signalling — they are the anti-false-
lock mechanism. At a wrong alignment the receiver checks an adjacent pair of
payload positions, and the alternation guarantees one of them is a CVSD bit.

Dropping them is therefore not free, and `mfspec.md` does not replace the
guarantee with anything. Note that all six of its payload lanes are CVSD or
data, so an all-voice wrong alignment now sees *two* random bits rather than
one — structurally better, when the payload is speech. The failures are all in
the cases where a lane is **not** random, and CVSD's idle output is the worst of
them.

---

## 3. Encoder complexity — the 8-bit frame is better

Checked the way `spec.md` §4.3 checks its own: a literal gate-level model
against the frame builder, 4096 frames of random payload and hook states,
**bit-exact** (`mfcmp.py tx`).

The model needs, and needs only:

```
3-stage frame counter        b0..b2, addresses the frame mux directly
3-stage superframe counter   addresses the signalling mux; its LSB *is* F
8:1 frame mux                in0 = F, in1 = signalling mux, in2..7 = C1..C6
8:1 signalling mux           in3 tied high, in7 tied low, rest = A1..A6
```

Putting the framing bits at the **start** of the frame, as mux inputs 0 and 1,
is better than putting them at the end. `line-transmitter.md` §2 puts them last
so the mux address needs no offset, and pays for it with an S/T select gate, a
framing-data AND and an output override. In the 8-bit frame the framing bits are
*mux inputs*, so the address is still offset-free and **the override path
disappears**. Channel *n* wires to input *n*+1; that is layout, not logic.

| function | 16-bit, N = 7 | 8-bit, mfspec |
|---|---|---|
| Timing / counters | '4040 + '393 (mod-16 frame + 2-bit multiframe) | '4040 + '393 (mod-8 frame + mod-8 superframe) |
| Payload mux | **2 × '151 + ½ '157 selector** (14 positions) | **1 × '151** (6 positions) |
| Signalling | in the payload mux | **1 × '151** |
| S/T select | 3-input AND — needs a '10 or '11 (§3.2 of `seven-channel.md`) | **none** |
| Framing data | `b0 AND T`, plus `T = NAND(m0,m1)` | **none — F is a counter bit** |
| Biphase encoder | ½ '74 + gate | ½ '74 + gate |
| **Total** | **7–8 packages** | **5–6 packages** |

**About two packages lighter, and one less thing to get wrong.** The two pads
also pay off exactly as `mfspec.md` §4 claims: states 3 and 7 are the only ones
with `b1·b0 = 1`, and the expected value is the complement of `b2`, so the
transmitter spends two tied mux inputs and the receiver spends one AND and one
XOR. Placing them at binary boundaries is a genuinely good piece of design.

There is one new race. F is the superframe counter's LSB and is read at bit-count
0, which is when that counter has just ticked. Clock the superframe counter off
the opposite edge, or from the 7→0 transition. The 16-bit frame has the same
class of problem in its ripple chain (`seven-channel.md` §3.1) and it is equally
benign, but it wants scoping at bring-up.

---

## 4. Decoder complexity — cheaper, and that is the problem

As written, the `mfspec.md` §5 receiver is **2–3 packages** against the §6
framer's **five** (`spec.md` §7.5):

| function | 16-bit, N = 7 | 8-bit, mfspec |
|---|---|---|
| Header check | 4-bit T shift register + "exactly one zero in four" decode ('164 + '151 as a lookup) | ½ '74 + XOR (F alternates) |
| Guard | — | 1 AND + 1 XOR (pads at 3 and 7) |
| Acquisition count | to 32, '393 both halves | to 8, ½ '393 |
| Loss of frame | **'193, +1/−1, floor 0, trip 16** | **absent** |
| Lock state | ½ '74 | ½ '74 |
| Signalling demux | 1 × '259, address = frame counter, **no phase** | 1 × '259, address = **superframe counter** |
| Squelch / mute on unlock | required, `spec.md` §10 | **absent** |

The savings come almost entirely from the rows that say *absent*, and the repo
has already measured what each of them costs.

### 4.1 Stage 1 is the header this project rejected

`spec.md` §3.3, row 2: an alternating `10`/`01` header is *"imitated by CVSD
silence, which is exactly `1010…`"* — 7/8 and 15/16 skews false-locked on an
idle link, permanently. `mfspec.md`'s F bit is that pattern, and a wrong bit
alignment puts the Stage 1 test on a payload lane:

| payload lane | P(bit flips) | fraction of 8-frame windows that pass Stage 1 |
|---|---|---|
| **CVSD silence** | 1.000 | **1.000** |
| **CVSD, −40 dB tone** | 1.000 | **0.999** |
| **CVSD speech** | 0.957 | **0.699** |
| random data | 0.500 | 0.004 |
| octet `10110010` | 0.750 | 0.000 |
| data, all ones | 0.000 | 0.000 |

An idle voice channel holds Stage 1 open **for ever**, and a channel carrying
speech holds it open on 70% of attempts. Against CVSD — the payload this system
exists to carry — eight frames of "is it alternating?" is not a filter. It
rejects data lanes well, which is the reverse of what is needed.

### 4.2 Stage 2 carries the entire design, and it is a 2-bit check

Credit where it is due: the guard works for the reason the pads are 4 apart.
Frames 3 and 7 differ by an even number, so **any lane of period 2 or 4 gives
the same value at both** and can never satisfy `S(3)=1, S(7)=0`. Constants fail
outright. So CVSD silence — which defeats Stage 1 completely — is caught
deterministically by Stage 2, and an all-voice link measures **0 false bit
locks at all 8 skews**, idle or speech.

What escapes is a lane of period 8, and `mfspec.md` §3.1 explicitly permits
"unconstrained serial data" in bits 2–7:

| payload, mfspec receiver, all 8 start-up skews | false bit locks |
|---|---|
| speech, all voice | 0 / 8 |
| idle, all voice | 0 / 8 |
| **idle + one data card** | **4 / 8** |
| **speech + one data card** | **4 / 8** |
| one data card, swept over all 8 octet phases | **56 / 64** |

A byte-aligned 64 kbps data channel beside a silent voice channel is a
**permanent** false lock: the silent lane holds Stage 1, the octet lane satisfies
the period-8 signature every superframe, and nothing ever unlocks it.

**Repetition cannot fix this**, because the check and the payload have the same
period:

| signature required to hold over | false locks |
|---|---|
| 1 superframe (125 µs) | 4 / 8 |
| 2 superframes | 4 / 8 |
| 4 superframes | 4 / 8 |
| 8 superframes (1 ms) | 4 / 8 |

Control, same clip and same line rate, the 16-bit frame with a data card strapped
per `spec.md` §3.4 — both the original static `(0,1)` header and the current
`S = 0, T = 1110`:

| payload | header | locks | false |
|---|---|---|---|
| speech | static `(0,1)` | 16 / 16 | **0** |
| speech | `S=0 T=1110` | 16 / 16 | **0** |
| idle | static `(0,1)` | 16 / 16 | **0** |
| idle | `S=0 T=1110` | 16 / 16 | **0** |
| idle + one data card | static `(0,1)` | 16 / 16 | **0** |
| idle + one data card | `S=0 T=1110` | 16 / 16 | **0** |

### 4.3 The superframe phase is unpinned, and this is the worst finding

Sub-commutating the signalling creates a multiframe phase that the signalling
demux depends on. `spec.md` §3 avoided one deliberately: *"The only multiframe
in the system is T's four-frame pattern, and nothing tracks its phase."* In
`mfspec.md` the two pads are the only thing that pins it, and they cannot.

Offset *d* means the local frame counter reads true superframe index (*s*+*d*)
mod 8. The signature admits *d* iff `A[(3+d) mod 8] == 1` and
`A[(7+d) mod 8] == 0`, where `A = [a1,a2,a3,1,a4,a5,a6,0]`. Enumerated over all
64 hook-state combinations and all 8 offsets:

| | |
|---|---|
| Hook combinations admitting ≥ 1 wrong superframe phase | **56 / 64 (87.5%)** |
| Wrong phases admitted, mean / max | 1.50 / 3 |
| Offsets structurally rejected | **only *d* = 4** |

Because the pads sit 4 apart, the signature only ever compares channels 4 apart
— (1,4), (2,5), (3,6) — and **each pair whose two channels differ in hook state
admits exactly one wrong phase**:

- ch4 off-hook, ch1 on-hook → offset 1 holds; reversed → offset 5
- ch5 off-hook, ch2 on-hook → offset 2 holds; reversed → offset 6
- ch6 off-hook, ch3 on-hook → offset 3 holds; reversed → offset 7

**Worked example: channel 4 on a call, the other five idle.** Offset 1 satisfies
the signature for the whole duration of that call. The receiver is bit-aligned
and frame-aligned, every voice channel is bit-exact, the audio is perfect — and
every hook state is latched into the wrong channel. Ringing, seizure and
disconnect all go to the wrong line, silently. In simulation, with those hook
states, **7 of 8 start-up skews lock onto a wrong superframe phase** on both
speech and idle payloads — the two rows that showed 0 false *bit* locks above.

The 16-bit frame cannot do this. Its A bits are addressed by the frame counter
that is already locked, so there is no second phase to get wrong.

### 4.4 No tracking rule, no loss of frame, no squelch

`mfspec.md` §5 says what to do on a mismatch during the hunt and nothing about
after lock. Both readings fail:

- **If a mismatch unlocks:** one F-bit error costs lock. At a 64 kHz frame rate
  that is an F error every 15.6 ms at 1e-3 and every 1.56 ms at 1e-2. The link
  never stays up on a real pair.
- **If nothing is checked after lock:** §4.2's and §4.3's false locks are
  permanent by construction, and a bit slip is never detected.

`spec.md` §7.3 exists for exactly this: `+1/−1`, floor 0, trip 16, one '193,
measured at 0 false reframes to 3e-2 BER with every slip size detected within
0.84 ms. §7.4 also rules out the obvious alternative — "N consecutive bad
frames" — because a misaligned frame fails only part of the time; a 6-bit slip
never recovered.

And `spec.md` §10.1 makes squelch **mandatory**, not optional: a dead pair with
a little induced noise makes sparse transitions, the monostable emits long runs
of 1s, and the CVSD compander reads it as **+24 dB rms, +47.7 dB peak** relative
to normal speech. `mfspec.md` has no squelch, no mute-on-unlock and no
carrier-detect timeout.

Restoring the three absent rows puts the decoder back at **4–5 packages** —
roughly a wash with the 16-bit framer, and possibly half a package better, since
the alternating-plus-guard check is cheaper than a 4-bit window and an
exactly-one-zero decode.

---

## 5. Constant payload — lock is held, and this header is the better one

Asked directly: can sync lock be held with constant 1 or 0 on the channel
lanes? **Yes, on every arrangement measured, and constant payload is the
*safest* payload this header has.** Exhaustively, over all 64 hook-state
combinations × all 8 start-up skews (`mfcmp.py constant`):

| payload | false locks | failed to lock |
|---|---|---|
| all six lanes constant 0 | **0 / 512** | 0 / 512 |
| all six lanes constant 1 | **0 / 512** | 0 / 512 |
| lanes alternate 0 / 1 | **0 / 512** | 0 / 512 |
| one constant 0 in silence | **0 / 512** | 0 / 512 |
| one constant 1 in silence | **0 / 512** | 0 / 512 |
| one constant 0 in speech | **0 / 512** | 0 / 512 |
| two adjacent constants 0, 1 | **0 / 512** | 0 / 512 |

And tracking at the true alignment, on the strictest reading of `mfspec.md` §5
— the pads re-verified every superframe, any mismatch unlocking — over 6385
frames:
**0 unlocks and 0 off-phase frames on every one of those payloads.**

The reason is structural, and it holds at any N:

- **In the F position** a constant lane never alternates, so Stage 1 fails at
  once.
- **In the S position** a constant lane cannot be 1 at state 3 and 0 at state 7,
  so the guard fails deterministically.
- **The S lane itself cannot alternate for 8 frames.** An alternating run needs
  index 3 = 1 and index 7 = 0; `01010101` gives 1 and 1, `10101010` gives 0 and
  0. Both fail, so skew 1 never holds either.
- **Lock is held because F and S are dedicated bits.** The header does not
  depend on what the channels carry, so no payload can break a correct lock.

**This is a real advantage over the 16-bit frame's original static `(0,1)`
header**, which a constant data slot false-locks permanently — `spec.md` §3.3,
measured at 40 of 192. The 8-bit header is immune to the case that forced that
one to be replaced. It is period-8 payload, not constant payload, that defeats
it (§4.2).

One caveat that cuts both ways: with every lane carrying the same constant, the
lanes are bit-identical, so **nothing in the payload can confirm the alignment
is right**. Lock is held, and it cannot be verified from the channels.

---

## 6. Random data — lock holds, and resync is the real story

Random data on all six channels, 2 000 000 frames = **31.25 s** of line time
(`mfcmp.py random`). Random is the *benign* end of the payload space: a random
lane alternates with p = 0.5, so it passes Stage 1 on only 0.4% of windows
(§4.1). It is octet-**periodic** data that is fatal (§4.2), not random data.

### 6.1 A clean line holds lock indefinitely

| reading of `mfspec.md` §5 | locked frames | unlocks | off-phase |
|---|---|---|---|
| `strict` — any pad mismatch unlocks | 1 999 985 | **0** | **0** |
| `none` — never re-checked after lock | 1 999 985 | **0** | **0** |

Zero unlocks over 31 s. The reason is the same one that makes constant payload
safe (§5): **F and S are dedicated bits, so no payload can disturb a correct
lock.** On this axis the header is sound, and that is worth saying plainly
before the rest.

### 6.2 With line errors, the missing hysteresis dominates

Strict reading, same 31 s:

| line BER | locked frames | unlocks | off-phase | **down** | mean resync |
|---|---|---|---|---|---|
| 0 | 1 999 985 | 0 | 0 | **0.0%** | — |
| 1e−05 | 1 997 176 | 26 | 0 | 0.1% | 109 frames |
| 1e−04 | 1 974 060 | 246 | 0 | 1.3% | 105 frames |
| 1e−03 | 1 760 818 | 2 238 | 3 | 12.0% | 107 frames |
| **1e−02** | 785 092 | **10 011** | 2 | **60.7%** | 121 frames |

Control, the 16-bit frame with `S = 0, T = 1110`, random data on all seven C
bits with A strapped to 1 (`spec.md` §3.4), same line length:

| line BER | locked frames | LOF events | off-phase |
|---|---|---|---|
| 0 | 999 968 | **0** | 0 |
| 1e−04 | 999 968 | **0** | 0 |
| 1e−03 | 999 968 | **0** | 0 |
| 1e−02 | 999 959 | **0** | 0 |

**At 1e−02 the 16-bit framer never loses frame once and mfspec is down 61% of
the time.** Note what the off-phase column says, though: mfspec's unlocks are
*not* false locks — it re-acquires on the true phase essentially every time (2–3
off-phase frames in 2 million). Random data does not fool the guard. The failure
is **availability, not misdelivery**, and it is entirely the absence of the
`+1/−1` trip-16 counter.

### 6.3 Resync: fast to the point of being twitchy

After an induced slip on a clean line, every slip size:

| slip, bits | `strict`: bad frames / frames to relock | `none`: bad frames |
|---|---|---|
| 1 | 1 / 1 | 999 999 |
| 2 | 0 / 0 | 999 999 |
| 3 | 1 / 1 | 999 999 |
| 4 | 0 / 0 | 999 999 |
| 5 | 0 / 0 | 999 999 |
| 6 | 0 / 0 | 999 999 |
| 7 | 0 / 0 | 999 999 |

**This is the one place mfspec beats the 16-bit frame outright.** Checking a
dedicated bit every frame with no hysteresis detects and corrects any slip
within **0–1 frames**, against `spec.md` §7.3's worst case of 0.94 ms (~30
frames) for the `+1/−1` counter. And acquisition is quick: 15–40 frames, mean
22.5 = **0.352 ms**, against 31–49 frames at N = 7 — about 3× faster in time
because the frame rate is doubled and the count is shorter.

Under the `none` reading a slip is **never** detected and the channels stay
rotated for the remaining half of the run — `spec.md` §7.4's finding restated: a
misaligned frame fails only part of the time, so a rule needing a run of bad
frames does not fire. `mfspec.md` specifies neither rule, and the two readings
bracket the outcome: **twitchy, or blind.**

Hysteresis is exactly the dial between them. mfspec sits at one end (detect a
slip in 1 frame, unlock on one line error); `spec.md` §7.3 sits near the other
(ride out 1e−02, detect any slip in 0.94 ms). The 16-bit design's choice is
better for voice, because CVSD degrades gracefully through errored bits —
13.65 dB segSNR at 1e−03 (`spec.md` §4) — while at that same 1e−03 mfspec takes
2238 unlocks in 31 s, a 107-frame (1.7 ms) mute every 14 ms, which is chopped
audio.

### 6.4 Where a resync can land

8 skews × 250 random payload seeds, 2000 frames each:

| | |
|---|---|
| False locks | **0 / 2000 hunts** |
| Acquisition, true phase | 15–40 frames, mean 22.5 (0.352 ms) |

Analytically one wrong phase tested once against random data passes with
p = 0.5⁸ × 0.25 = 9.8e−04 ≈ 2⁻¹⁰, against the 16-bit framer's 2⁻³². The
**measured** per-hunt rate is lower than that product — 0 of 2000, so ≤ 1.8e−03
at 95% — because a failing phase is abandoned after one bad frame rather than
retried, so the hunt walks away before it can accumulate an 8-frame run.

So the weak confirmation does not bite on random data. **§4.2's periodic-data
hole is structural, not statistical**, and no confirmation count reaches it —
which is why item 5 in §7 is a slot rule rather than a bigger counter.

---

## 7. Where this leaves it

**Keep the 8-bit geometry; it wins §2 and §3 on merit. Replace the header.**
The frame is the better division of a 512 kbps line and the encoder is genuinely
simpler. The sync is the one part that is worse, and it is worse in precisely the
ways this repository has already measured and closed.

**That replacement is now specified and validated: `mf8-spec.md`.** Against §4's
three findings it measures 0 false locks over 512 exhaustive trials per payload
class, 0 admissible wrong superframe phases over all 64 hook states, and 0
loss-of-frame events to 3e−02 BER. The changes it makes, in the order they
matter:

1. **The `+1/−1` trip-16 counter and a 32-frame acquisition count.** Across
   §§4.4 and 6, at matched payload quality the missing counter is worth 50× in
   outage. It is one 74HC193 and it is the single highest-value change.
2. **`11111110` on F instead of `1010`**, scored predictively against the
   receiver's own superframe counter. `1010` *is* CVSD silence (§4.1); the
   period-8 word pins bit alignment and superframe phase with one check, and
   costs one 3-input NAND.
3. **Guard bits in S at superframe states 3 and 5, not 3 and 7.** §4.3's hole was
   that the pads sat 4 apart and were gated by hook bits. Same-parity positions
   with different required values reject CVSD silence, and values that differ
   from the F word reject a data card carrying the framing word — measured at
   384/512 false locks before that change and 0 after.
4. **Squelch and mute-on-unlock** (`spec.md` §10). Not optional: a dead pair with
   induced noise reads as +47.7 dB peak.
5. **A slot rule: no two adjacent data cards.** §4.2's periodic-data hole is
   structural, not statistical, so no confirmation count reaches it. Measured
   safe for one data card in any seat and for any non-adjacent pair.

---

## 8. Reproducing

```
python3 mfcmp.py stage1     is "F alternates" a filter against CVSD?
python3 mfcmp.py sfphase    the superframe-phase enumeration, all 64 hook states
python3 mfcmp.py bitlock    bit-alignment false locks, both formats
python3 mfcmp.py errors     what one bad F bit costs
python3 mfcmp.py tx         gate-level encoder identity and the bit budget
python3 mfcmp.py constant   constant payload: false locks and tracking
python3 mfcmp.py random     random data: 31 s hold, resync, slips
```

(`line-codes.md` and `frame-rate.md` list the targets belonging to them, and
`python3 mfcmp.py` with no argument runs all of them, about an hour.)

How to read the numbers:

- §§1–4 are bit-level except where they say otherwise; §5 is exhaustive over
  hook states and skews on 0.1 s clips; §6's long runs use injected BER rather
  than a waveform, because 31 s at OS = 32 does not fit in memory.
- Stage 2 is modelled in its **stronger** reading: both guard checks must pass
  within one superframe. The weaker reading — lock granted at state 7 alone —
  measures 4–6 false bit locks of 8 even on all-voice payloads.
- §1's PHY claims are inherited from `spec.md` §2.1 and §§5–6, not re-measured.
