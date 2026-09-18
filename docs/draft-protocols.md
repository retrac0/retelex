# Draft — the protocols, and what can be strapped

> **Working record.** The standard adopted from this work is `spec.md`
> (2026-09-16). Where this document conflicts with it — framing header, empty-slot
> fill, data-slot rules, scrambling, crystal, acquisition count, loss-of-frame
> policy — the spec governs. Section references here are to the spec as it stood
> when each section was written.

A companion to `spec.md`, which says what the 3-channel build *is*, and to
`family.md`, which tabulates the (N, codec rate) family. This one says what the
protocol stack is made of, why the frame ended up the shape it did, and how much
of the design can be moved with a **jumper** rather than a crystal swap or a
re-spin.

Status: draft. §§1–4 restate settled design. §§5–9 are new work, measured by
`strap.py`; nothing in them is committed to. Two of them **correct claims in
`spec.md` §2.2.2 and `family.md` §2** — see §6.3 and §6.5.

---

## 1. Three protocols, stacked, sharing nothing

```
   audio  ──→  CVSD              1 bit per sample, no sample boundary, no framing
          ──→  2+2N bit frame    channel interleave, signalling, start/stop
          ──→  diff. Manchester  clock, DC balance, polarity immunity
          ──→  pair
```

Each layer is ignorant of the ones around it, and the design leans on that
repeatedly:

- **CVSD does not know it is being framed.** No sample boundary to align to and
  no sync word, so the frame layer may interleave it at any width.
- **The frame does not know what the line code is.** It is bits; differential
  Manchester carries bits.
- **The line code does not know there is a frame.** A repeater slices and
  re-drives, so it is transparent to both layers above — no oscillator, no
  framer, no configuration (`repeater.md` §2.3).

The consequence that matters for everything below: **the frame layer is the only
layer with a parameter in it.** Change the channel count and the other two layers
do not notice.

---

## 2. Raw CVSD

### 2.1 What it is

Continuously variable slope delta modulation. One bit per sample, meaning "the
input is above / below what I have reconstructed so far". Both ends run the same
integrator; the encoder contains a decoder, and the only difference between the
two populations of the channel card is where the data bit comes from
(`channel-card.md` §2).

Two feedback loops set the step size:

- a **run register** (3 bits here) detecting coincidence — three identical bits
  in a row means the integrator is losing the race
- a **syllabic filter**, τ = 6 ms, integrating that coincidence into a step size
  spanning 30 dB from `step_min` to `step_max`

so the step adapts over a syllable, not over a sample. The integrator is an OTA
driving `C_int ∥ R_int`, leak τ = 3 ms.

### 2.2 The property the whole carrier is built on

```
step per bit = I · t / C
```

The integrator is analog. Its step is proportional to the **actual** bit
interval, not to a nominal one. Three things follow, and all three are
load-bearing:

**It needs a uniform clock, not an average one.** Deliver a channel's bits as a
burst at the line rate and then stall for the rest of the frame and the
reconstruction falls apart — ~5× the amplitude error even with the integrator
gated off during the stall, and far worse without. **This is why the frame
interleaves bits and not bytes.** Not a preference; measured (`cvsd.dt_burst`,
`run.py` experiment 4).

**The codec clock can be the frame clock, and then jitter is structurally zero.**
One bit per channel per frame, spaced by exactly one frame period, with no buffer
anywhere in the system.

**The components set slew, not step size.** `slew = I_abc / C_int`, with the bit
rate cancelling. That is the single most useful fact in this document: the
channel card is specified in full-scale units per *second*, so it does not know
what bit rate it is running at. §6.3 is what that buys.

### 2.3 Rate versus quality

Roughly 6 dB of segmental SNR per doubling, no knee. Measured on seven
independent talkers (`family.md` §3):

| CVSD rate | mean | worst talker |
|---|---|---|
| 16 kbps | 10.80 dB | 9.02 dB |
| **32 kbps** | **17.40 dB** | **14.91 dB** |
| 64 kbps | 23.28 dB | 19.69 dB |

Every doubling costs the same in line rate and buys the same in quality, which
is why a rate strap is a real option rather than a false economy. Specify against
the worst talker: the per-talker spread (~2.5 dB, tracking crest factor) is
larger than anything the carrier itself contributes.

### 2.4 What CVSD does not give you

No sample framing, no parity, no sync word, no error detection of any kind. A
bit error is an audible click and nothing more — which is the good case, because
it leaves the framing problem entirely to the frame layer, and the frame layer is
allowed to solve it with two bits.

---

## 3. How the header format was settled

```
count:  0     1     2     3     4     5     6     7
      [ A1 ][ C1 ][ A2 ][ C2 ][ A3 ][ C3 ][ S ][ T ]
                                          0     1
```

Four separate decisions produced that, and only the first was obvious.

### 3.1 Start/stop rather than a sync word

A sync word costs bits and needs a correlator. Start/stop costs two bits per
frame and two gates: check that one position is always 0 and another always 1,
slip one line bit when it fails. It works *only* if every wrong alignment is
eventually rejected — which is what §3.2 is about.

### 3.2 Signalling and voice must alternate — a constraint, not a preference

At a wrong alignment of *k* bits the receiver reads frame bit *k* as its start
and bit *k−1* as its stop, so **every candidate alignment tests one adjacent pair
of interior bits**. Alternating A and C bits guarantees each such pair contains a
CVSD bit, which is effectively random, so every wrong alignment is rejected
within a few frames.

Group the signalling instead — `[C1..C3][A1..A3][S][T]` — and the pair
`(An, An+1)` is two static bits. One channel on-hook next to one off-hook is an
ordinary operating state, and it holds that false alignment **indefinitely**.
Counted exhaustively (`strap.py` §4):

| ordering | N=1 | N=2 | N=3 | N=7 |
|---|---|---|---|---|
| interleaved | 0 | 0 | 0 | 0 |
| grouped | 0 | 1 | **2** | **6** |

(adjacent-static violations: wrong alignments that can never be rejected).
Simulated, the grouped ordering false-locks on every non-zero start-up skew at
N = 3 and on 13 of 16 at N = 7, and the decoded output is digital silence,
because the false alignment feeds the constant S and T bits to the codecs.

Note the first column. **At N = 1 the two orderings are the same frame reversed,
and neither has a violation.** The rule has no teeth until there are two channels
to put next to each other — so a framer validated only at N = 1 proves nothing
about the ordering.

### 3.3 Framing bits last, not first

Looks cosmetic; is not. With the framing bits at the end, the payload
multiplexer's address is the frame counter taps **with no offset at all**, and
the framing bits are decoded from the top of the same counter:

```
payload mux address    = frame counter taps, directly
S/T select             = AND of every counter bit above the LSB
line bit when selected = the counter LSB   ->  S = 0 at count 6, T = 1 at count 7
```

Put the framing bits first and both identities acquire an offset, which costs an
adder. Verified bit-for-bit against `link.build()` at N = 1, 3 and 7.

### 3.4 `2 + 2N` a power of two — which is what picked N = 3

`2 + 2N` is a power of two only at N = 1, 3, 7 and 15. Only then does the whole
crystal-to-frame chain divide by 2ⁿ, and only then:

- the transmitter's entire timing chain — half-bit clock, line bit clock, frame
  counter, frame clock — collapses into taps on **one 74HC4040**, with no
  divider, no decoded modulus and no sync-clear gate
- the receiver's 74HC259 needs no enable gating: with `2N` payload bits in an
  8-deep latch, the framing bits land in spare positions instead of overwriting
  A1 and C1 every frame

The earlier design was 4 channels in a 10-bit frame. Moving to 3 channels in 8
bits removed roughly two packages from the transmitter and one gate from the
receiver, and it is the reason the family has the members it has.

---

## 4. The two committed members

| | N = 3 (committed) | N = 7 (`seven-channel.md`) |
|---|---|---|
| Frame | 8 bits | 16 bits |
| Line rate | 256 kbps | 512 kbps |
| Symbol rate | 512 kbaud | 1.024 Mbaud |
| Oscillator | 8.192 MHz | 16.384 MHz |
| Crystal-to-frame | ÷256 = 2⁸ | ÷512 = 2⁹ |
| TX packages | ~6 | 7–8 |
| Estimated reach | order 1.7 km | order 1.2 km |

The 7-channel work found that **nothing structural changes**: the interleaving
rule generalises, acquisition takes the same time, the loss-of-frame policy
covers every slip size, signalling is unchanged, the monostable window is the
same ±13% in relative terms, and the audio is transparent to within 0.14 dB.
What it costs is reach, because doubling the line rate doubles the fundamental
and √f attenuation takes 1/√2 of the distance.

That result is what makes the rest of this document worth writing. If N = 7 is
the same design with one more counter tap, the question is whether N *and* the
rate can be set in the field.

---

## 5. Strapping: the nine modes

`family.md` tabulates the family as (N, codec rate) pairs and reaches the rates
by **changing the crystal** — 2.048 through 32.768 MHz. That is right for a build
option and wrong for a strap, because a crystal swap is a soldering iron.

All nine come off **one 4.096 MHz crystal** and one ripple counter, with two
independent jumper fields. The decomposition that makes them independent is the
one to get right:

> **Strap on line rate and channel count, not on codec rate.** Line conditions
> set one field, local needs set the other, and the codec rate falls out as
> `line / frame length`.

Strap on the codec rate instead and the two fields interact — the half-bit clock
is `2 × flen × codec rate`, so the rate selector would have to know N. Strap on
the line rate and it does not: the half-bit tap is a function of the line rate
alone, and the mask and frame-clock stage are a function of N alone.

### 5.1 The nine modes and what each is for

Quality is `family.md` §3's seven-talker figures. Reach is √f analysis scaled
from `spec.md` §10's single unmeasured anchor — **ratios, not absolutes**
(`strap.py` §26).

| mode | ch | segSNR (worst talker) | line | baud | reach | monostable | edge | what it is for |
|---|---|---|---|---|---|---|---|---|
| N=7 @ 64k | 7 | 23.3 dB (19.7) | 1024k | 2.048 M | 0.50× ≈ 0.85 km | 732 ns | **75 ns** | maximum capacity, short haul — 448 kbps of voice |
| N=3 @ 64k | 3 | 23.3 dB (19.7) | 512k | 1.024 M | 0.71× ≈ 1.2 km | 1465 ns | 150 ns¹ | program / music circuit |
| N=7 @ 32k | 7 | 17.4 dB (14.9) | 512k | 1.024 M | 0.71× ≈ 1.2 km | 1465 ns | 150 ns¹ | capacity at committed quality |
| N=1 @ 64k | 1 | 23.3 dB (19.7) | 256k | 512 k | 1.00× ≈ 1.7 km | 2930 ns | 150 ns | best audio at no plant cost |
| **N=3 @ 32k** | **3** | **17.4 dB (14.9)** | **256k** | **512 k** | **1.00× ≈ 1.7 km** | **2930 ns** | **150 ns** | **the committed build** |
| N=7 @ 16k | 7 | 10.8 dB (9.0) | 256k | 512 k | 1.00× ≈ 1.7 km | 2930 ns | 150 ns | maximum channels at no plant cost |
| N=1 @ 32k | 1 | 17.4 dB (14.9) | 128k | 256 k | 1.41× ≈ 2.4 km | 5859 ns | 150 ns | **reach at committed quality** |
| N=3 @ 16k | 3 | 10.8 dB (9.0) | 128k | 256 k | 1.41× ≈ 2.4 km | 5859 ns | 150 ns | three channels, long haul |
| N=1 @ 16k | 1 | 10.8 dB (9.0) | 64k | 128 k | 2.00× ≈ 3.4 km² | 11719 ns | 150 ns | maximum reach |

¹ 150 ns is 15.4% of a 977 ns half-cell — inside the eye but a real
EMI-versus-eye choice, per `seven-channel.md` §5.3.
² The √f law is leaving the skin-effect region at a 32 kHz fundamental; treat
2.00× as an upper bound (§6.2).

**The three axes trade against each other and you may pick any two.** Channels
× quality × reach is roughly conserved: every row that doubles the channels at
constant reach costs ~5.9 dB, and every row that doubles the reach at constant
channels costs the same ~5.9 dB. There is no free corner.

Read the table by what is scarce:

- **Cable is scarce** → move down the table. `N=1 @ 32k` is the one to know
  about: the committed build's audio, 1.41× the reach, one channel.
- **Slots are scarce** → move up. `N=7 @ 16k` gets seven channels with no change
  to the plant at all, at the intelligibility floor.
- **Neither is scarce and quality matters** → `N=1 @ 64k` or `N=3 @ 64k`.

### 5.2 What each mode has been measured on

Not all nine have equal standing, and the table above does not show that:

| mode | status |
|---|---|
| N=3 @ 32k | committed; `validate.py`, 15 spec claims end to end |
| N=7 @ 32k | `n7.py` end to end, `seven-channel.md` |
| N=3 @ 64k | `strap.py` §19 — full chain, −0.09 dB, BER 0 |
| **N=7 @ 64k** | **`strap.py` §29 — full chain, −0.16 dB, BER 0** |
| N=1 @ 32k | `strap.py` §5–8, link layer, 128 kbps |
| N=1 @ 64k, N=7 @ 16k, N=3 @ 16k, N=1 @ 16k | arithmetic plus the shared PHY; no end-to-end run |

The four unrun modes all sit at **lower** line rates than modes already measured,
on frame widths already measured, so the PHY is strictly easier and the framer is
frame-width-dependent rather than rate-dependent. That is an argument, not a
measurement. Run them before committing the strap to a build.

### 5.3 The corner mode, measured

`family.md` §6 calls N=7 @ 64k past the practical corner, on analysis. Adding it
to the grid made that worth checking (`strap.py` §29, 2.048 Mbaud, simulated at
32.768 MHz):

| | N=7 @ 64k |
|---|---|
| Lock to true phase, all 16 skews | yes |
| Acquisition | 0.98–1.39 ms |
| Clean BER through the full chain | **0** |
| segSNR, codec alone → over the link | 25.12 → 24.95 dB (**−0.16 dB**) |
| Noise margin | error-free to **sd = 0.6** |
| Monostable window at sd 0.4 | 0.60–0.85, **±13%**, 732 ± 98 ns |

**In simulation it is as good as every other mode**, and the ±13% window holds.
Every constraint on it is physical rather than logical:

- **0.85 km.** Half the committed reach. This is the real cost.
- **±98 ns absolute window.** A 1% resistor and 2% C0G still give ±3%, so the RC
  itself is fine — but layout stray and the '4040's own ripple skew (~110 ns)
  are no longer negligible against it.
- **The output stage must be re-specified, not inherited.** 150 ns edges are
  **31%** of a 488 ns half-cell. 75 ns brings it back to 15%, at the cost of the
  radiated-emissions margin that slew limiting was bought for.
- **NEXT.** Two octaves above the 512 kHz that `repeater.md` §3.3 budgets 20 dB
  at, so roughly **29 dB + span loss** of coupling loss required (§6.8). Not
  simulated at any rate; this is the gap.

So: supported by the strap, measured clean, and the mode where the plant
requirements stop being inherited. Keep it in the table, specify the 75 ns edge
for it, and do not use it before NEXT is measured.

### 5.4 The two strap fields

**Rate strap — five positions, set by the line.** Picks the half-bit tap, and
with it the receiver's monostable RC. Nothing else on either card moves.

| line rate | half-bit clock | tap | H | monostable |
|---|---|---|---|---|
| 1024 kbps | 2.048 MHz | Q1 | Q2 | 732 ns |
| 512 kbps | 1.024 MHz | Q2 | Q3 | 1465 ns |
| **256 kbps** | **512 kHz** | **Q3** | **Q4** | **2930 ns** |
| 128 kbps | 256 kHz | Q4 | Q5 | 5859 ns |
| 64 kbps | 128 kHz | Q5 | Q6 | 11719 ns |

**Channel strap — three positions, set by the office.** Picks the mask and which
frame-counter stage is the frame clock.

| N | frame | mask | frame clock | S/T select |
|---|---|---|---|---|
| 1 | 4 bits | 0x3 | counter stage 2 | stage 1 straight through |
| **3** | **8 bits** | **0x7** | **counter stage 3** | **2-input AND** |
| 7 | 16 bits | 0xF | counter stage 4 | 3-input AND |

The mask is applied wherever the counter is consumed — payload mux address, S/T
select, the receiver's '259 address — and one 3-input AND with unused inputs
strapped high covers all three S/T cases.

**Verified.** A gate-level model of one transmitter card — free-running counter,
mask, tap select, mux, S/T override — reproduces `link.build()` **bit for bit at
all three channel straps** (`strap.py` §3).

### 5.5 The strap matrix, and what an invalid setting does

Five rate positions × three channel positions is fifteen combinations, of which
nine are the grid (`strap.py` §28):

| line | N=1 | N=3 | N=7 |
|---|---|---|---|
| 1024k | — above 64k | — above 64k | **64 kbps** |
| 512k | — above 64k | **64 kbps** | **32 kbps** |
| 256k | **64 kbps** | **32 kbps** | **16 kbps** |
| 128k | **32 kbps** | **16 kbps** | — below 16k |
| 64k | **16 kbps** | — below 16k | — below 16k |

The nine valid settings form a diagonal band, which is the whole trade drawn as
a picture: down-left is reach, up-right is capacity, and the diagonal is constant
line rate.

**The six invalid settings are not hazardous.** They produce a working, locked,
correctly framed link with a codec running outside its characterised range —
8 kbps and 4 kbps sound useless, 128 kbps and 256 kbps would very likely sound
excellent and have never been measured. Silly rather than dangerous.

**That is emphatically not true of the two *ends* disagreeing.** §10 is that
case, and it locks.

### 5.6 What the strap touches, card by card

| | rate strap | channel strap |
|---|---|---|
| **TX card** | half-bit tap (jumper) | mask, frame-clock stage (jumpers); payload mux width at N=7 |
| **RX card** | monostable resistor (jumper), and the tap into the framer | mask, frame-clock stage, '259 address (jumpers) |
| **Channel card** | **nothing** — not even the `Iabc` trim (§6.3) | nothing; the slot count is a backplane question |
| **Repeater** | **nothing** active; transformer per §6.5 | **nothing** — it never sees the frame |
| **Backplane** | nothing | slot count, which is the one thing that cannot be deferred |

The channel card and the repeater being untouched is the whole reason this is
worth doing. A mode change is two jumpers at each end of a span and a resistor,
on two cards, and nothing in between or below.

### 5.7 The two directions may be strapped differently

The rate strap, not the channel strap. The two directions are independent one-way
systems, each timed end to end by its transmitting end's crystal, and the channel
card takes its transmit clock and its receive clock from different backplane pins
that are never compared (`channel-card.md` §1, §6). So **A→B may run at 256 kbps
while B→A runs at 128 kbps**, and the only consequence is that one direction
sounds better than the other.

That is worth having. Pair quality in a real cable is not symmetric, and one bad
pair currently drags both directions down.

The channel strap must match, because a slot at one end must be the same slot at
the other.

### 5.8 Why 4.096 MHz

The committed build divides an 8.192 MHz crystal by 16 to reach a 512 kHz
half-bit clock. That is 16× oversampling of the baud rate in a design whose
receive side has **no clock at all**. Nothing needs it (`strap.py` §20):

| node | committed build | what it is for |
|---|---|---|
| crystal | 8.192 MHz | — |
| Q1 / Q2 / Q3 | 4.096 / 2.048 / 1.024 MHz | **nothing — getting down to Q4** |
| Q4 half-bit clock | 512 kHz | the biphase T flip-flop and the H divider |
| Q5 line bit clock (`H`) | 256 kHz | half-cell phase into the encoder NAND |
| Q6:Q8 frame counter | 256 kHz | mux address, S/T select |
| Q8 frame clock | 32 kHz | CVSD clock to the channel cards |

**The fastest node with a job is the half-bit clock, and the half-bit clock is
the baud rate.**

The ÷16 was forced once. The design before this one ran a 10-bit frame at
320 kbps, so the half-bit clock was 640 kHz, and no ubiquitous crystal divides
to 640 kHz — the binary multiples are 1.28 / 2.56 / 5.12 / 10.24 MHz and only
10.24 is stock. Moving to the 8-bit frame made it 512 kHz, which several stock
values divide to, and the ÷16 stayed because nothing prompted a revisit.

For the nine-mode grid the crystal is set by the *fastest* mode: N=7 @ 64k needs
a 2.048 MHz half-bit clock, and the half-bit clock must be `crystal / 2ⁿ` with
`n ≥ 1` — at least one divide, because a raw Pierce output is not 50% duty.
**That makes 4.096 MHz the minimum, and it is sufficient**: taps Q1…Q8 cover
every mode with four stages of a 74HC4040 to spare (`strap.py` §21, §26). Drop
N=7 @ 64k and 2.048 MHz would do.

**Ripple skew is not an argument for a faster crystal, and it looks like one.**
The skews that matter — within the frame counter, which is what the S/T select
and the mux address decode across, and half-bit-clock to frame counter — sit
*below* the half-bit clock and are identical at every crystal. The stages a fast
crystal adds are all *above* it, and nothing decodes across them.
`line-transmitter.md` §4 quotes a Q1→Q8 skew of ~100 ns, but the decode it
worries about is `Q8·Q7`, one stage apart.

What a faster crystal does cost is real but modest: top-of-board frequency and
its harmonics, which sits oddly beside slew-limiting the line driver to be
quieter; and clock-chain current, ~2× at 8.192 MHz and ~4× at 16.384 MHz against
4.096 MHz (`strap.py` §22). At 4.096 MHz the 74HC speed-margin question that
`seven-channel.md` §3.1 raises for a 16.384 MHz oscillator does not arise at all.

### 5.9 Every mode off one chain, tap by tap

4.096 MHz, one ripple counter (`strap.py` §26). The frame counter is the `k`
stages below the line-bit clock; the mask is the channel strap:

| mode | line | baud | half-bit | H | frame counter | frame clock | mask | monostable |
|---|---|---|---|---|---|---|---|---|
| N=7 @ 64k | 1024k | 2.048 M | **Q1** 2.048 MHz | Q2 | Q3:Q6 | Q6 = 64 kHz | 0xF | 732 ns |
| N=3 @ 64k | 512k | 1.024 M | **Q2** 1.024 MHz | Q3 | Q4:Q6 | Q6 = 64 kHz | 0x7 | 1465 ns |
| N=7 @ 32k | 512k | 1.024 M | **Q2** 1.024 MHz | Q3 | Q4:Q7 | Q7 = 32 kHz | 0xF | 1465 ns |
| N=1 @ 64k | 256k | 0.512 M | **Q3** 512 kHz | Q4 | Q5:Q6 | Q6 = 64 kHz | 0x3 | 2930 ns |
| **N=3 @ 32k** | **256k** | **0.512 M** | **Q3** 512 kHz | **Q4** | **Q5:Q7** | **Q7 = 32 kHz** | **0x7** | **2930 ns** |
| N=7 @ 16k | 256k | 0.512 M | **Q3** 512 kHz | Q4 | Q5:Q8 | Q8 = 16 kHz | 0xF | 2930 ns |
| N=1 @ 32k | 128k | 0.256 M | **Q4** 256 kHz | Q5 | Q6:Q7 | Q7 = 32 kHz | 0x3 | 5859 ns |
| N=3 @ 16k | 128k | 0.256 M | **Q4** 256 kHz | Q5 | Q6:Q8 | Q8 = 16 kHz | 0x7 | 5859 ns |
| N=1 @ 16k | 64k | 0.128 M | **Q5** 128 kHz | Q6 | Q7:Q8 | Q8 = 16 kHz | 0x3 | 11719 ns |

The committed row maps onto `line-transmitter.md` §4 exactly, shifted one tap:
that document's Q4/Q5/Q6:Q8/Q8 at 8.192 MHz is Q3/Q4/Q5:Q7/Q7 here.

#### The topology a strappable chain wants

The rate strap moves *which tap* is the half-bit clock, so on a single ripple
chain it drags the frame counter with it — the counter LSB is two stages below
the half-bit tap, and it lands anywhere from Q3 to Q7. Jumpering `k` moving taps
is a 4 × 5 matrix. Re-clocking is not: give the frame counter its own package,
fed by the selected line-bit clock, and its bits sit on fixed pins at every
strap.

```
 4.096 MHz ─→ [74HC4040 prescaler, Q1..Q5] ─→ jumper ─→ half-bit clock ─→ biphase JK
                                            (rate strap)      │
                                                              ÷2 ─→ H ─→ encoder NAND
                                                              │
                                    [74HC393 frame counter, 4 stages]
                                              │          │
                                       jumper │          └─→ mask ─→ mux addr,
                                   (channel strap)                   S/T, '259
                                              └─→ frame clock ─→ channel cards
```

**The cost is one package on the TX card and none on the RX card.** The '393
takes over the ÷2 and the frame counter that the committed build takes as '4040
taps; the two selectors are jumper fields, not multiplexers, which is what
"strappable" means in 74HC. The RX needs no new package at all — its frame
counter is already a separate counter clocked by the recovered line bit, so its
strap is three jumper fields and a five-resistor network for the monostable.

| | committed (fixed) | nine-mode strappable |
|---|---|---|
| Timing chain | 74HC4040 | 74HC4040 + 74HC393 |
| Selectors | none | 3 jumper fields (+ 2 on RX) |
| Monostable | one RC | RC with 5 selectable resistors |
| TX packages | ~6 | ~7, or ~9 with the N=7 payload mux |
| RX packages | unchanged | **unchanged** |

The frame content is unaffected: §5.4 verified the generator against
`link.build()` from the counter *value*, and re-clocking a counter does not
change what it counts.

**This is the one place where strappability has a real price** — it costs the
single-package timing chain that §3.4 went to some trouble to earn. If modes are
chosen at build time rather than in the field, the answer is a wire link and no
'393 at all.


---

## 6. Moving the baud rate — down, and up

### 6.1 The bandwidth requirement scales exactly

Error-free from **0.12 × symbol rate** at N = 1 — the same figure N = 3 and N = 7
both give (`strap.py` §10). Halving the rate halves the bandwidth needed, with no
second-order penalty and no new failure mode.

Same caution as `seven-channel.md` §5.1: the cable in the model is a first-order
lowpass, which captures dispersion and not attenuation. **This is not a reach
measurement.**

### 6.2 Reach is analysis, and the low rows are optimistic

In the skin-effect region attenuation goes as √f, so halving the fundamental buys
√2 in distance for the same loss budget:

> order 1.7 km at 256 kbps → **order 2.4 km at 128 kbps** → order 3.4 km at
> 64 kbps.

Those are `family.md`'s numbers and they come from the same scaling. Treat the
last one with suspicion, and this is an addition to what `family.md` says: the √f
law holds **while the pair is skin-effect limited**. At a 32 kHz fundamental a
24 AWG pair is heading out of that region into the resistance-limited one, where
attenuation flattens and the strap stops paying. **The 1.41× is plausible; the
2.00× is an upper bound.** Both want a bench measurement, as does the 1.7 km they
are scaled from.

Where the rate strap beats a repeater: a repeater is a box in a hole in the
ground with power fed to it, and a jumper at each end is not. Below about three
spans, try the strap first.

### 6.3 The channel card does not need re-trimming — measured

**This corrects `spec.md` §2.2.2** ("on the channel card only the `Iabc` slew trim
changes") **and `family.md` §2** ("changing the CVSD rate is a crystal swap and new
codec RC values"). Neither is wrong in principle — the optimum trim does move with
rate — but the measured cost of *not* moving it is small enough that it changes
what the strap is:

| CVSD rate | trim left at 12000 | best slew | best | re-trim buys |
|---|---|---|---|---|
| 16 kbps | 10.97 dB | 7000 | 11.32 dB | **0.35 dB** |
| **32 kbps** | **18.86 dB** | 12000 | 18.86 dB | — |
| 64 kbps | 24.77 dB | 16000 | 25.06 dB | **0.28 dB** |

(`strap.py` §9, one talker, so read the deltas and not the absolutes.)

**A third of a decibel across a 4:1 rate range.** `slew = I_abc / C_int` with the
bit rate cancelling, and the optimum is broad — within 1 dB of peak from roughly
0.5× to 1.5× nominal, per `channel-card.md` §2.3 — so a 2:1 rate change does not
walk out of it. The syllabic and integrator RCs are real-time constants matched to
speech, not to the bit rate, so they do not move at all.

So a rate strap is genuinely a jumper: **no channel card needs touching, no card
needs re-trimming, and a strap change does not invalidate the recorded trim
values.** Re-trim if the link is running at 16 kbps permanently and the third of a
decibel is wanted; do not treat it as a prerequisite.

### 6.4 The receiver window is unchanged in relative terms

At the sd = 0.4 design limit, same clip and seed (`strap.py` §11):

| build | usable window | margin about 0.75 | absolute |
|---|---|---|---|
| N = 3, 256 kbps | 0.60–0.85 of a cell | ±13% | 2930 ± 391 ns |
| N = 1, 128 kbps | 0.60–0.90 of a cell | ±20% | 5859 ± 1172 ns |

One grid point wider at the top, i.e. **no worse**. Keep specifying against ±13%;
1% resistor and 2% C0G give ±3% and clear it at every strap. The absolute window
gets *easier* as the rate comes down, which is the opposite of the problem
`family.md` §5 flags at the top of the table.

### 6.5 Two things that do scale, and one correction

**The transformer.** Running disparity is bounded at ±1 cell and the cell doubles
with the strap. The 10 mH specified for 256 kbps gives under 5% droop over
3.91 µs; at 128 kbps the same winding droops roughly twice as much, at 64 kbps
four times. **If the rate strap is to be real, specify ~25 mH now** — same part
number, same footprint, and retrofitting a transformer is exactly the kind of
change this design has been avoiding. This is arithmetic on the existing droop
budget, not a simulation result; check it on the bench.

**The correction:** `repeater.md` §2.3 says the repeater has "no line rate — no
oscillator and no bit-rate-dependent RC anywhere on the card." The active path is
indeed rate-blind, but the card carries four line transformers and those are not.
It should read *no bit-rate-dependent **active** element*; the transformer spec
follows the terminal's.

**The output stage gets easier.** 150 ns edges are 7.7% of a 1.95 µs half-cell at
256 kbps and 3.8% at 128 kbps, so the EMI-versus-eye trade relaxes and the edges
can be softened further if emissions are a problem.

### 6.6 The other way to halve the baud rate

Halving the *line rate* halves baud and payload together. Halving only the *baud*
— same payload, half the symbols — means changing the line code, and `spec.md` §4
already evaluated that: AMI halves the symbol rate but needs a three-level driver
and a slicer threshold that tracks received amplitude, measured to fail at 0.6×
gain error where biphase has no threshold at all.

They fix different problems. **The rate strap fixes attenuation; AMI fixes
dispersion.** The bandwidth sweeps say this plant is attenuation-limited, which is
why the strap is the interesting one and AMI stays on file.

### 6.7 Does a lower rate actually buy robustness? Partly

"Lower baud for more robustness" is two different claims, and only one of them
survives measurement.

**At a fixed line rate, lowering the codec rate buys channels, not robustness.**
The 256 kbps group under line errors, channel 1, same PHY throughout
(`strap.py` §17):

| mode | clean | 1e-4 | 1e-3 | 3e-3 | 1e-2 | 3e-2 |
|---|---|---|---|---|---|---|
| N=1 @ 64k | 25.71 dB | 24.69 | 16.69 | 11.30 | 5.93 | 2.03 |
| **N=3 @ 32k** | **19.34 dB** | **18.90** | **14.14** | **9.61** | **4.63** | **1.28** |
| N=7 @ 16k | 11.65 dB | 11.49 | 9.76 | 7.55 | 4.01 | 1.08 |

Zero loss-of-frame events in every cell. The low-rate mode *degrades* more
gently — it loses 7.6 dB from clean to 1e-2 where the 64 kbps mode loses 19.8 dB
— but it starts so far down that **it is never actually better**, at any error
rate tested. The curves converge; they do not cross. So N = 7 @ 16 kbps is a
capacity mode, and calling it a robustness mode would be wrong.

**Lowering the *line* rate does buy robustness, and §6.9 measures it: +3 dB per
halving.** That gain does not appear in the receiver — the margin is sd = 0.6 at
every rate when the bandwidth is scaled with the symbol rate, and the ±13%
timing window is unchanged in relative terms (§6.4). It appears because a slower
mode filters harder and collects less noise from the same cable. **Do not expect
a bench test on a short cable with a scaled generator to show it**; it needs one
fixed cable and one fixed noise floor to be visible at all.

That is the honest answer to "N = 3 at 16 kbps for robustness": it is a real
mode, it gives three channels at 1.41× reach, and it costs 6.6 dB of audio to
get there — down to 9.0 dB for the worst talker, which is the intelligibility
floor rather than a quality target. If what is wanted is margin at the committed
quality, **N = 1 @ 32 kbps is the better buy** — same 17.4 dB, same 1.41× reach,
one channel instead of three.

**One thing genuinely does favour the narrow frame: cold-start acquisition.**
64 consecutive good frames, and any bad frame slips a bit and restarts, so an
attempt costs `64 × flen` line bits. Mean lock time over three error seeds, at
256 kbps (`strap.py` §18):

| mode | frame | 1e-3 | 3e-3 | 1e-2 | 2e-2 | 3e-2 |
|---|---|---|---|---|---|---|
| N=1 @ 64k | 4 bits | 1.23 ms | 1.52 | 2.37 | 4.38 | 15.5 |
| N=3 @ 32k | 8 bits | 2.61 ms | 2.86 | 4.70 | 11.4 | 37.7 |
| N=7 @ 16k | 16 bits | 4.93 ms | 4.93 | 8.28 | 24.2 | 37.9 |

Clean 2× per doubling of frame length at low BER, widening as errors rise. At
5e-2 all three are in the hundreds of milliseconds to seconds and the ordering
is seed noise, so treat that column as "unusable" rather than as data. None of
this is a cliff — `spec.md` §9 shows tracking surviving far past the rate at
which acquisition gets slow — but on a marginal line the narrow frame gets in
first, and that is a real operational difference during a fault.


### 6.8 Doubling instead — is the 512 kbps group realistic?

`N = 3 @ 64 kbps` and `N = 7 @ 32 kbps` are **the same waveform on the wire**:
512 kbps, 1.024 Mbaud, 1.95 µs cell, 1465 ns monostable (and a 1.024 MHz
half-bit clock, which `seven-channel.md` reaches from a 16.384 MHz crystal and
§5.8 reaches from a 4.096 MHz one).
Only the frame width and the codec rate differ, so the PHY question has one
answer for both, and `seven-channel.md` has already answered most of it for the
N = 7 member. The N = 3 @ 64 kbps member had never been run at all; it has now
(`strap.py` §19).

**Nothing new breaks.** Measured through the full chain at 1.024 Mbaud:

| mode | codec alone | over the link | delta | clean BER | error-free to | window |
|---|---|---|---|---|---|---|
| N=3 @ 64k | 24.80 dB | 24.71 dB | **−0.09 dB** | 0 | sd = 0.6 | 0.60–0.85, ±13% |
| N=7 @ 32k | 18.68 dB | 18.58 dB | **−0.11 dB** | 0 | sd = 0.6 | 0.60–0.85, ±13% |

Identical margins, as they must be — it is one waveform. Both are the same
numbers the committed 256 kbps build gives. The link layer at N = 3 @ 64 kbps is
clean too: lock to true phase at all 8 skews, bit-exact recovery, acquisition
0.98–1.45 ms (64 frame periods again, now 1.00 ms because the frame clock is
64 kHz), worst loss-of-frame detection 0.36 ms over all seven slip sizes, zero
false reframes to 3e-2 BER.

So the simulation says yes. What the simulation does not model is where the
answer actually lives:

**Reach, 1.2 km.** The whole cost, and an unmeasured one — §6.2's caveats apply
in full. Historical sanity check, not a measurement: T1 ran 1.544 Mbps AMI over
22–24 AWG with repeaters at ~1.8 km, and AMI at that rate puts its fundamental
near 772 kHz. Differential Manchester at 512 kbps sits between 256 and 512 kHz.
**The 512 kbps group asks less of the cable than T1 did.** That is reassuring
about feasibility and says nothing about this particular plant.

**74HC at 16.384 MHz** — and this one is self-inflicted. It is inside the
family's rating (25–50 MHz at 5 V) but without much margin at 4.5 V and 85 °C,
and `seven-channel.md` §3.1 rightly says to scope the ripple at bring-up.
**§5.8 removes the concern rather than managing it:** a 4.096 MHz crystal
produces the same 1.024 MHz half-bit clock from Q2, with nothing on the board
running above 4 MHz. The skews that matter are below the half-bit clock and do
not change.

**The output stage.** 150 ns edges are 15.4% of a 977 ns half-cell against 7.7%
at 256 kbps. Still inside the eye, but the EMI-versus-eye trade that was
comfortable becomes a choice: keep 150 ns and accept a visibly softer eye, or
tighten to ~75 ns and give back radiated-emissions margin.

**Near-end crosstalk, which is the one I would worry about.** `repeater.md` §3.3
budgets 20 dB of NEXT rejection relative to the wanted signal, and states the
plant requirement as `20 dB + span loss` of coupling loss between the two
directions' pairs **at 512 kHz**. NEXT loss falls at roughly 15 dB/decade, so an
octave of frequency costs about 4.5 dB: the same budget at 1.024 Mbaud becomes
roughly **24.5 dB + span loss**. That is textbook scaling rather than anything
measured here, and it is the strongest argument for keeping the two directions
in separate binder groups at this rate. NEXT at 1.024 Mbaud has not been
simulated; it should be, before either mode is committed.

#### Which of the two is worth building

**N = 7 @ 32 kbps is the one with a reason.** It spends the doubled line rate on
capacity — 7 channels, 224 kbps of voice, 88% framing efficiency — and
`seven-channel.md` already carries the full analysis and the recommendation to
keep it open. Giving up 30% of reach for 2.33× the channels is a trade someone
will want.

**N = 3 @ 64 kbps is realistic but hard to justify.** It spends the doubled line
rate on fidelity: the same three channels the committed build carries, at
23.3 dB instead of 17.4 dB, for 0.71× the reach. Set against it:

- Those three channels already exist at 256 kbps and 1.7 km. The strap buys
  5.9 dB of audio and costs 500 m.
- 300–3400 Hz E&M trunk telephony does not reward 23 dB over 17 dB very much.
  Where it would reward it is a **program or music circuit**, which is a real
  telco service and the honest niche for this mode.
- At 64 kbps per channel the comparison with companded PCM becomes live —
  µ-law at the same bit rate is a different quality class. `bond.py` is already
  looking at exactly that question, and it should settle before anyone commits
  to 64 kbps CVSD as the way to spend 512 kbps.

| | N=3 @ 64k | N=7 @ 32k | N=3 @ 32k (committed) |
|---|---|---|---|
| Oscillator (as specified) | 16.384 MHz | 16.384 MHz | 8.192 MHz |
| Oscillator (§5.8 minimum) | 4.096 MHz | 4.096 MHz | 4.096 MHz |
| Frame clock tap | Q8 | Q9 | Q8 |
| Half-cell | 977 ns | 977 ns | 1953 ns |
| 150 ns edge | 15.4% | 15.4% | 7.7% |
| Payload mux | 1 × 74HC151 | 2 × 74HC151 | 1 × 74HC151 |
| S/T select | 2-input AND | 3-input AND | 2-input AND |
| TX packages | ~6 | 7–8 | ~6 |
| Channels | 3 | 7 | 3 |
| segSNR/ch | 23.28 dB | 17.40 dB | 17.40 dB |
| Estimated reach | 1.2 km | 1.2 km | 1.7 km |

Worth noting that **N = 3 @ 64 kbps is the cheaper of the two in logic** — one
'151 and a 2-input select against two '151s and a 3-input — so if the 512 kbps
group is built, the N = 3 strap is the one that fits the existing transmitter
card unchanged.


### 6.9 All nine modes under noise

Two different questions get conflated here, so both were run (`strap.py` §30–31).

**(a) Relative margin** — cable bandwidth and noise scaled with the symbol rate,
the convention `n7.py` and `validate.py` use. This asks *is any mode
intrinsically worse?*

> **All nine modes are error-free to sd = 0.6.** Identical, from 64 kbps to
> 1024 kbps, at every channel count.

Nothing about the line code, the slicer or the monostable prefers a rate. That is
the result that makes the strap legitimate in the first place.

**(b) Absolute margin** — one physical cable (1 MHz, 3 dB), one noise floor, all
modes simulated at a common 32.768 MHz so a given sd is the same noise power
spectral density, each receiver low-passing at its *own* symbol rate. These are
`compare.py`'s fairness rules. This asks *on the pair I actually have, which mode
survives?* — and it had never been run.

| mode | line | baud | error-free to | vs committed |
|---|---|---|---|---|
| N=1 @ 16k | 64k | 0.128 M | **sd = 2.0** | **+6.0 dB** |
| N=1 @ 32k | 128k | 0.256 M | sd = 1.4 | +2.9 dB |
| N=3 @ 16k | 128k | 0.256 M | sd = 1.4 | +2.9 dB |
| N=1 @ 64k | 256k | 0.512 M | sd = 1.0 | 0.0 dB |
| **N=3 @ 32k** | **256k** | **0.512 M** | **sd = 1.0** | **0.0 dB** |
| N=7 @ 16k | 256k | 0.512 M | sd = 1.0 | 0.0 dB |
| N=3 @ 64k | 512k | 1.024 M | sd = 0.8 | −1.9 dB |
| N=7 @ 32k | 512k | 1.024 M | sd = 0.8 | −1.9 dB |
| N=7 @ 64k | 1024k | 2.048 M | **sd = 0.4** | **−8.0 dB** |

Three things fall out of that table, and the third is the one to act on.

**Noise margin is a function of the line rate alone.** The three 256 kbps modes
give identical figures; so do the two at 512 kbps and the two at 128 kbps. The
channel count does not enter. Straps that share a line rate share their noise
margin exactly, which is the same statement as §5.6's "modes sharing a line rate
share every analog part".

**Halving the line rate buys +3 dB, and that is textbook.** 256k→128k is
+2.9 dB, 128k→64k is +3.1 dB. The receiver's lowpass halves with the symbol
rate, so noise power halves, so tolerable amplitude rises by √2. Nothing
mysterious and nothing mode-specific — which is worth knowing, because it means
the rate strap's value can be *computed* for a given plant rather than guessed.

**N=7 @ 64k falls off a cliff, not a slope: −8.0 dB where the trend predicts
−4.8.** At 2.048 Mbaud the 1 MHz cable is below the symbol rate, so that mode is
penalised twice — more noise bandwidth *and* a signal the cable is already
eating. **It is the only mode in the family where cable bandwidth binds rather
than attenuation**, and it inverts `spec.md` §10's "the limit is attenuation, not
dispersion, which is the good case." For this one mode it is the bad case. On a
wider pair the −8.0 would come back toward −4.8; on a narrower one it gets worse
fast.


---

## 7. Down to the 4-bit frame

```
count:  0     1     2     3
      [ A1 ][ C1 ][ S ][ T ]
                    0    1
```

It works, and every link-layer property survives (`strap.py` §5–8):

| | N = 1 (4-bit) | N = 3 (control) |
|---|---|---|
| Lock to true phase, all skews | yes (4/4) | yes (8/8) |
| Bit-exact channel recovery | yes | yes |
| Acquisition | 1.97–2.02 ms | 1.97–2.50 ms |
| Worst loss-of-frame detection, +2/−1 trip 12 | **0.81 ms** | **0.81 ms** |
| Worst detection, 16-consecutive policy | never recovers | never recovers |
| False reframes at 1e-3 / 1e-2 / 3e-2 BER | 0 / 0 / 0 | 0 / 0 / 0 |
| Spurious ring assertions to 6e-2 BER | 0 | 0 |

Two rows are worth pulling out.

**Acquisition is 64 frame periods, always.** 2.00 ms at a 32 kHz frame clock, at
every channel count and every rate strap. `seven-channel.md` §2 saw the same
invariance at N = 7 and read it as two effects cancelling; it is simpler than
that. The framer needs 64 consecutive good frames, and a frame *is* a CVSD bit
period by construction, so **acquisition time is set by the codec rate alone**.
The narrow frame is slightly better only because there are fewer wrong phases to
search.

**Loss-of-frame detection is identical to the millisecond**, and the consecutive
policy fails at N = 1 exactly as it does everywhere else. The up/down counter is
not a 3-channel tuning; it is the policy.

### 7.1 What the 4-bit frame costs

**Half the line is overhead.** 50% framing efficiency against 75% at N = 3 and
88% at N = 7. Two bits on framing and two on one channel, so at 256 kbps it
carries one 64 kbps channel where the same line carries three at 32 kbps. Not a
defect — the start/stop framer costs the same two bits at every width — but it is
why N = 1 is a reach-and-simplicity option and never a capacity one.

**The ordering rule goes quiet** (§3.2). There is nothing to interleave.

### 7.2 What it is good for

- A single long circuit where 2.4 km at half rate beats 1.7 km at full and a
  repeater is not wanted.
- One **64 kbps channel at 23.3 dB** on the committed line rate — the best audio
  the family can produce, with no change to the transmission plant at all.
- Bring-up and fault-finding. The 4-bit frame is the smallest thing that
  exercises the whole chain, and one channel card is enough to run it.

---

## 8. The 64 kbps slot as a transparent pipe

**Decision: the carrier stays CVSD for 1–7 channels and does not learn what PCM
is.** A slot strapped at 64 kbps is a transparent bit pipe; anything that wants
to put G.711 through it brings its own framing. That removes the multiframe from
this design entirely, and §8.3 is why it is the right call.

### 8.1 The rate arithmetic, and why the pipe is clean

At 64 kbps per channel the frame clock is 64 kHz, so **one C-bit slot is
8 kHz × 8 bits**. One slot, one 64 kbps synchronous pipe, no bonding and no
spare bits needed. The pipe is:

- **bit-transparent** — the carrier never inspects it
- **synchronous**, clocked by the recovered frame clock, so there is no elastic
  store anywhere and no slips (§1 applies unchanged)
- **not octet-aligned.** The S/T framer establishes *bit* alignment and slot
  identity, and stops there.

That last point is the whole architecture in one line. Octet phase is the end
equipment's problem, which is normal for a data circuit and is exactly how it
should be: a 64 kbps codec at each end recovers its own octet phase, the same way
it would on any other bearer.

### 8.2 What PCM would buy, if someone brings it

Worth recording, because it is better than expected and it is why the 64 kbps
column is worth keeping. Same talker, both scored at 8 kHz (`strap.py` §32.1):

| line BER | µ-law | A-law | CVSD @ 64k | PCM advantage |
|---|---|---|---|---|
| clean | 28.96 dB | 29.00 dB | 25.28 dB | **+3.68 dB** |
| 1e-4 | 28.39 | 28.45 | 24.07 | +4.31 |
| 1e-3 | 23.51 | 23.76 | 16.60 | **+6.90** |
| 1e-2 | 8.23 | 8.51 | 5.82 | +2.41 |

**The clean-line gain is +3.7 dB, not a different quality class** — a correction
to what raw SQNR figures suggest, and to what I claimed earlier in this work.

**PCM does not degrade faster under line errors; it degrades slower.** The
advantage *widens* to +6.9 dB at 1e-3, which is the opposite of the usual
intuition. The mechanism is plain once measured: a PCM error corrupts one 125 µs
sample, while a CVSD error is a step into an integrator with a 3 ms leak, so it
rings on for two orders of magnitude longer. **Memory is what makes CVSD
fragile, and PCM has none.**

### 8.3 Why the carrier must not do it itself

Because PCM has a sample boundary and CVSD does not, and the existing framer
finds bit alignment only. All eight phases of an 8-frame multiframe on a clean,
correctly framed line (`strap.py` §32.3):

| phase | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|---|
| segSNR | **28.96 dB** | −0.01 | −0.02 | −0.03 | −0.01 | −0.02 | −0.01 | −0.00 |

Seven of eight are not degraded, they are *uncorrelated* — and the bit framer is
locked and content throughout, which is precisely the category §10.2 identifies
as the dangerous one: locked, confident and wrong. `bond.py` reaches the same
place from the other direction and prices it: a multiframe marker, a 2-bit
counter and comparator per pipe per end, and its own acquisition and
loss-of-multiframe policy — *a second framer, subordinate to the first*.

**Keeping that out of the carrier is worth more than the 3.7 dB it would buy.**
The end equipment already has to solve octet alignment for its own reasons; it
does not need this design to solve it a second time, worse.

### 8.4 Does a data slot need scrambling? Only in the wrong seat

**No — and the first version of this section overstated it.** "µ-law idle
false-locks the framer" is true but it is not a property of the payload, it is a
property of the *adjacency*, and it is fixed by where the slot sits and one
pull-up. Two questions were run together and they have different answers
(`strap.py` §36).

**An established lock is untouched.** Lock on normal traffic, then drive the data
slot hard to a constant half way through the clip:

| data slot goes to | locked | lock phase | LOF events | phase stable |
|---|---|---|---|---|
| constant 0 | yes | 0 | **0** | yes |
| constant 1 | yes | 0 | **0** | yes |

Of course it is: the framer checks S and T, and nothing a payload slot does
reaches them. **There is no loss-of-frame mechanism here at all.**

**Acquisition is the only thing at risk**, because the framer checks *one*
adjacent pair per candidate alignment and looks for `(0,1)`. A constant C bit is
dangerous only when its neighbour makes that exact pattern static — and which
neighbour depends on which constant:

- `C_j` constant **1** pairs with `A_j` before it. Dangerous when `A_j = 0`.
- `C_j` constant **0** pairs with `A_j+1` after it. Dangerous when the *next*
  channel is off-hook.

Cold start from all eight skews, N = 3 (`strap.py` §36b):

| data slot | payload | its A bit | other A bits | false locks |
|---|---|---|---|---|
| slot 1 | all 0 | 0 | 0 | 0/8 |
| slot 1 | all 0 | 0 | **1** | **3/8** |
| slot 1 | all 1 | **0** | 0 | **2/8** |
| slot 1 | all 1 | 1 | 0 | 0/8 |
| **slot 3 (last)** | **all 0** | **any** | **any** | **0/8** |
| slot 3 (last) | all 1 | **0** | any | **6/8** |
| **slot 3 (last)** | **all 1** | **1** | any | **0/8** |

Exhaustively, over every hook state of every other channel, at N = 3 and N = 7
(`strap.py` §37):

> **Last slot, all zeros: safe at every hook state.
> Last slot, all ones: safe iff that slot's own A bit is 1.**

**A uniformly constant frame is not the hazard, and it is worth being precise
about this.** If *every* payload bit is 1 — all A bits and all C bits — there is
no 0 anywhere to begin a `(0,1)` pair, so no wrong alignment can pass; if every
payload bit is 0 there is no 1 to complete one. Both acquire on 8/8 skews with
zero false locks and hold:

| N = 3 payload | present framer | toggling T |
|---|---|---|
| every payload bit 1 | 8/8 true, 0 false | 8/8 true, 0 false |
| every payload bit 0 | 8/8 true, 0 false | 8/8 true, 0 false |
| slot 1 all 1s, its A bit 0, rest voice | 6/8 true, **2/8 false** | 2/8 true, **6/8 false** |

**The hazard is the mixture, not the constant**: a constant C slot sitting next
to a static A bit of the opposite value, which is what forms the `(0,1)` the
framer is looking for. A data slot's unused A bit idling at 0 beside an all-ones
payload is exactly that shape, which is why §8.5's rule strapping it to 1 is the
fix.

### 8.5 So the rule is placement and a pull-up, not a package

**Put the data slot last and tie its A bit high.** (Or make the framer verify
the strap: `framing-review.md` §5's S3 layout, `[1][1][0][D]…`, puts the
strapped A bit inside the framing word, so a wrong strap cannot lock at all.) A data slot has no E&M
signalling to carry, so its A bit is free, and strapping it to 1 removes the
constant-1 case. Being last removes the constant-0 case, because the bit after
`C_N` is `S`, which is always 0 and can never complete a `(0,1)` pair. Cost: one
resistor. There is no other combination of payload and hook state left to worry
about.

At N = 7 that gives one data slot (slot 7) and six voice; a second data slot
would have to sit further up, where the constant-0 case comes back whenever its
neighbour goes off-hook.

**And a merely biased payload is not a problem at all** — this was the other
thing I got wrong. Only an *exactly* constant slot false-locks. Worst adjacency,
cold start from eight skews (`strap.py` §38):

| P(1) | 0.50 | 0.70 | 0.90 | 0.95 | **0.99** | **1.00** |
|---|---|---|---|---|---|---|
| false locks | 0/8 | 0/8 | 0/8 | 0/8 | **0/8** | **2/8** |
| wrong-alignment pass rate | 0.500 | 0.700 | 0.900 | 0.951 | 0.990 | **1.000** |

At 99% ones the wrong alignment still fails often enough during the 64-frame
confirmation that the true alignment wins every time. The cliff is at exactly
1.000 and nowhere before it. **The requirement on a payload is not "random", nor
even "high entropy" — it is "not a permanent constant in a bad seat."**

#### Two toggling framing patterns: proposed, measured, rejected

The obvious way to keep every channel identical is to attack the framer instead
of the payload. A false lock needs a *static* `(0,1)` pair, so make the stop bit
alternate and check it as a **transition**: `good := (S == 0) AND (T changed
since last frame)`. In counter terms the framing bit becomes `LSB · toggle`, one
flip-flop and one gate on the transmitter and a T register plus an XOR on the
receiver. No placement rule, no pull-up, nothing per channel.

It does fix the channel-count mis-strap of §10.2 that §10.3's polarity trick
could not — TX N=1 into an N=3 or N=7 receiver, and N=3 into N=7, all stop
locking, because a wide receiver samples the narrow frame's T every *other*
narrow frame and so always catches the same toggle phase.

**And it is unusable. Across 48 configurations the present framer false-locks in
96 skew-cases and the toggling T in 208** (`strap.py` §39) — including, fatally,
on traffic with no data slot in it at all:

| N = 3, all channels on-hook | acquires true phase | false locks |
|---|---|---|
| present framer | **8/8 skews** | 0/8 |
| toggling T | 2/8 | **6/8** |

Three ordinary CVSD voice channels, nothing unusual anywhere, and the toggling
stop bit false-locks on six of eight start-up skews. That is the normal
configuration of the committed build, not a corner case.

The reason is a property of CVSD that the level-based check never had to care
about:

| | |
|---|---|
| A real CVSD stream alternates on | **95.4%** of bit pairs |
| Longest continuous alternation in 6 s of speech | **6836 bits = 214 ms** |
| CVSD encoding pure silence | `101010101010…`, **100%** alternating |

A delta modulator tracking a constant emits `1010…` forever. **A CVSD bit
transitions almost every frame, so the transition check does not distinguish the
stop bit from a payload bit — it matches it.** Paired with a static A bit at 0,
an *idle voice channel* passes the new check on ~95% of frames and 100% during
silence, which is far more than the 64 consecutive that acquisition needs. The
proposal trades a failure on constant data for a failure on silence, which is a
much more common operating state.

The present check works for the mirror-image reason, and it is worth stating
explicitly because it is the load-bearing fact: **CVSD is random in *level* and
nearly deterministic in *transition*.** Checking levels is gated; checking
transitions is not.

**Toggling *both* framing bits is the better version of the idea, and it also
fails.** Alternate the pair — `(S,T) = (0,1)`, `(1,0)`, `(0,1)` … — and check
`(S != T) AND (S changed since last frame)`. In counter terms the framing bit
becomes `LSB XOR toggle`, still one flip-flop and one gate. This is strictly
better than toggling T alone, because now *both* positions have to move: a
static A bit fails the "changed" test deterministically, which was exactly the
hole that let CVSD through before. On speech it looks excellent —

| N = 3, 6 s of speech | present framer | S+T toggle |
|---|---|---|
| 3 voice channels, on-hook / off-hook / mixed | 0/8 false | **0/8 false** |
| constant data slot, all seats and hook states | up to 6/8 false | **0/8 false** |
| TX N=1 → RX N=3 / N=7, N=3 → N=7 (§10.2) | **LOCKS** | **mutes** |

— and then it dies on an **idle link**, which is the normal night-time state of
any carrier:

| all channels silent | present framer | S+T toggle |
|---|---|---|
| N = 3 | 0/8 false, longest wrong-alignment run **1 frame** | **7/8 false**, run **128000 frames** |
| N = 7 | 0/16 false, longest wrong-alignment run **1 frame** | **15/16 false**, run **128000 frames** |

Permanent, not transient. The mechanism is one line: **CVSD encoding silence is
`1010101010…`, and an alternating framing bit is `1010101010…`. They are the
same sequence**, so no test applied to those two bits can distinguish them. The
vulnerable alignment is the `(C_N, S)` pair, where the alternating framing bit
meets a C bit that is alternating in antiphase.

That one is structural, not a detail. In `[A1][C1]…[A_N][C_N][S][T]` the bit
immediately before S is always a C bit. Swapping the A and C order just moves the
problem to `(T, C1)` at the other end. With a two-bit framing field at the end of
an alternating A/C frame, **one neighbour of the framing pair is always a CVSD
bit**, so there is nowhere to put an alternating pattern where silence cannot
reach it.

#### The general result

Three things are now measured about what CVSD can produce, and together they
settle it:

| CVSD produces | so a framing pattern that is | is |
|---|---|---|
| random levels, 50/50 | **static** | **well gated** — a C bit rejects it half the time |
| perfect alternation when idle | **period-2** | **perfectly mimicked** |
| (a data slot produces) a constant | **static** | **mimicked by constant data** |

The present design picks the only row that works for voice, and pays for it with
the constant-data case. Every alternating variant trades that for a failure on
*silence*, which is incomparably more common. A longer-period pattern would evade
both, but detecting one needs its own phase, which is the multiframe §8.3 rules
out.

**So the framing pattern stays static `(0,1)`, and the constant-payload case is
fixed in the payload.** Two proposals have now looked correct on reasoning and
measured wrong — this one and §10.3's — which is the argument for keeping the
framer exactly as it is.

#### When a scrambler is still the answer

A self-synchronising scrambler, `x⁷ + x⁴ + 1`, restores every payload to the CVSD
figure (`strap.py` §33): µ-law idle goes from a 1.000 pass rate to 0.500, longest
run 6. Seven flip-flops and two XORs, no alignment to acquire, ×3 error
multiplication (measured 2.9–3.6×).

**With one correction to what §33 first claimed.** The shift register must be
seeded nonzero: a multiplicative scrambler with a zero state and an all-zero
input passes all zeros straight through, and all-zero is the commonest data
idle there is. Seeded, an all-zero input yields the period-127 m-sequence and
the framer is clean. A residual remains that no seed removes — if the register
happens to hold zero at the moment the input goes all-zero, it locks up; measured
**29 of 4000 idle onsets, 0.73%, against the 2^-7 = 0.78% expected**
(`strap.py` §40). That is the known weakness of self-synchronising scramblers,
and it is why the framing-side fix in `framing-review.md` is preferred to any
payload-side one.

#### Cheaper transforms than a scrambler, measured

The obvious question is whether something smaller than an LFSR would do. Every
seat × every hook state × all skews, present framer, false locks summed
(`strap.py` §40):

| transform on the data slot | all 0 | all 1 | `1010` | `0101` | `0x7E` flags | RX needs phase? |
|---|---|---|---|---|---|---|
| none | 16 | 24 | 0 | 0 | 0 | — |
| **alternate-bit inverter** (every other bit NOT'd) | **0** | **0** | **16** | **24** | 0 | **yes** — parity |
| NRZI (differential) | 16 | 0 | 0 | 0 | 0 | no |
| LFSR `x⁷+x⁴+1`, seed 0 | **16** | 0 | 0 | 0 | 0 | no |
| LFSR `x⁷+x⁴+1`, seed 1 | 0 | 0 | 0 | 0 | 0 | no |

The alternate-bit inverter clears both constants and **moves the hole, count for
count, onto an alternating payload** — which a data pipe can carry just as easily
as a constant. It also has a defect the others do not: frame sync gives the
receiver the frame *boundary* but not the frame *parity*, so the recovered data
comes out inverted half the time, and can flip on any reframe. NRZI is
self-synchronising and clears only one constant, because all-zero data produces
no transitions. In general **every one- or two-bit linear transform has a
period-two input that maps to a constant**; the LFSR pushes that to one specific
127-bit sequence, which is as good as a payload-side fix gets.

Two cases call for it:

- **A data slot that cannot be last** and cannot control its neighbour's hook
  state — a second pipe, at N = 7.
- **Keeping every carrier slot identical.** If the placement rule of §8.5 is
  unwelcome because it makes one seat special, the scrambler is the alternative
  that preserves interchangeable slots, and it is cheaper than it looks in that
  light: **it does not live in the carrier.** A data slot is already not a CVSD
  channel card, so the scrambler sits on the data interface card with the rest of
  that slot's differences. Every carrier slot, backplane position and voice card
  stays identical; one card that was already different gains a package.

For a single pipe that can have the last seat, it is a package solving a problem
a resistor already solved, and it should not be fitted.

### 8.6 Bonding two 32 kbps slots — simpler than it looks

Investigated as asked, and **the complexity `bond.py` found is all in the PCM,
not in the bonding**. Take the multiframe out and it collapses.

The S/T framer already establishes slot identity — that is what §10.2 shows it
doing, and getting it wrong is catastrophic precisely because it is normally
exact. So for a bonded pair, **C1 is the even bit and C2 the odd bit,
deterministically, forever.** No marker, no multiframe counter, no second framer.

Measured on the committed 32 kbps build, a random 64 kbps stream split across
slots 1 and 2 with CVSD speech in slot 3 (`strap.py` §35):

> **Bit-exact 64 kbps pipe recovered at all 8 start-up skews. Extra state: none.
> Extra packages: none.**

What it costs is two slots and one of the two A bits, which goes spare. What it
does *not* give you is octet alignment — same as §8.1, same answer.

So bonding is available at every channel count and every rate strap: at N=3 @ 32k
bond slots 1+2 and keep slot 3 as voice; at N=7 @ 32k bond two pairs and keep
three voice channels. The scrambler of §8.5 applies to a bonded pipe exactly as
to a native 64 kbps one.

**The honest comparison** with a native 64 kbps slot: bonding gets a 64 kbps pipe
without leaving the committed 256 kbps line rate and its 1.7 km, where N=3 @ 64k
would cost −1.9 dB of noise margin and 500 m (§6.9). Bonding is the cheaper way
to a pipe. A native slot is the cleaner one.

### 8.7 What this means for the strap

**Nothing changes.** No multiframe, no new framing layer, no change to the frame,
the framer, the line code, the channel card or the repeater. The additions are
optional and local:

- a slot strap that says "this slot is a pipe, not a codec" — which is a channel
  card that is not populated with a CVSD engine, plus the backplane connection
- a pull-up on that slot's A bit, and the slot wired last (§8.5)
- a scrambler package *only* for a second pipe that cannot sit last

And one rule worth writing down now, because it costs a resistor: **a data slot
goes in the last position with its A bit strapped high.** That makes every
payload safe, constants included, at every hook state of every other channel
(§8.5). A scrambler is only needed for a second data slot that cannot have the
last seat.

---

## 9. What cannot be strapped

**N = 2, 4, 5, 6.** `2 + 2N` must be a power of two for §3.3's identities. N = 2
gives a 6-bit frame needing a decoded modulus, a sync-clear gate and a mux
address that is no longer the counter — three packages and a class of glitch, to
save one slot. Populate three slots and leave one empty instead.

**N = 15.** Arithmetically fine, practically not: see `family.md` §6.

**Ground start.** It needs two independent static conditions per channel per end,
and §3.2 forbids a second static bit next to the first. A framer change, not a
strap.

---

## 10. Mis-strapping — and the one case that is dangerous

A strap that can be set wrong will be set wrong. The two straps fail completely
differently, and only one of them fails safe.

### 10.1 A rate mis-strap fails safe

Receiver monostable RC set for the wrong line rate, TX sending the committed
256 kbps. Levels measured **with the mute defeated**, so the failure is visible
(`strap.py` §12):

| RX monostable set for | bits out | framer locks | mean run of 1s | rms | peak |
|---|---|---|---|---|---|
| 256 kbps (correct) | 767,999 | **yes** | 1.0 | 0 dB | +16.3 dB |
| 128 kbps (RC 2× too long) | 647,959 | **no** | 0.0 | +11.9 dB | +47.7 dB |
| 512 kbps (RC 2× too short) | 1,295,920 | **no** | 1,295,920 | +8.9 dB | +47.7 dB |

The unmuted output is the `spec.md` §8.1 pathology in its purest form: with the
RC too short every interval classifies as full-cell, the monostable emits a solid
run of 1s for the entire clip, the syllabic filter reads continuous coincidence
as a loud signal, and the integrator slams rail to rail at +47.7 dB peak.

**But the framer never locks**, so the not-locked level that `spec.md` §8.2
already mandates as the mute holds it off. A rate mis-strap is a dead link and it
announces itself as one.

### 10.2 A channel mis-strap does not

Same crystal, same line rate, only the frame width set wrong. Clean line, no
noise, nothing out of tolerance (`strap.py` §13):

| TX strapped | RX strapped | framer locks | LOF events | result |
|---|---|---|---|---|
| N = 1 | N = 3 | **yes** | 0 | 1 slot pinned, 2 duplicated |
| N = 1 | N = 7 | **yes** | 0 | 3 slots pinned, 4 duplicated |
| N = 3 | N = 7 | **yes** | 0 | 1 slot pinned, 6 scrambled |
| N = 3 | N = 1 | no | — | mutes |
| N = 7 | N = 3 | no | — | mutes |

**Every frame length in the family is a power of two, so the shorter frame always
divides the longer one.** A narrow transmitter therefore presents a perfectly
valid S/T pattern to a wide receiver at a stable phase, and the wide receiver
locks solidly and never lets go — zero loss-of-frame events over the whole clip.
The reverse never locks, because a wide frame does not fit a narrow one.

What comes out of a locked mis-strap, mute defeated:

```
TX N=1 into RX N=3, ch 1 on-hook:
   slot 1   mean 1-run     2.8 bits   rms +18.9 dB   peak +33.8 dB   (ch 1, half speed)
   slot 2   mean 1-run 128000 bits    rms +18.9 dB   peak +47.7 dB   (pinned at the rail)
   slot 3   mean 1-run     2.8 bits   rms +18.9 dB   peak +33.8 dB   (ch 1 again)
```

Slot 2's C bit is the transmitter's T bit — constant 1 forever, which is the
syllabic pathology again, at **+47.7 dB peak, the same number a noise-only line
produces**. Squelch cannot help: the framer is locked, which is the one condition
`spec.md` §8.2 says squelch does not cover.

The only thing between a wrongly set jumper and a full-scale tone in somebody's
ear is the output clamp of `spec.md` §8.2. **Those two diodes are now
load-bearing.**

### 10.3 The obvious fix does not work

Give alternate family members `(S,T) = (1,0)` instead of `(0,1)` — one XOR in the
S/T path, strapped with the frame width — and the divisibility no longer produces
a valid pattern. Tested rather than assumed (`strap.py` §14):

| TX | channel 1 | RX expecting (0,1) | locks |
|---|---|---|---|
| N = 1, (S,T) = (1,0) | on-hook | N = 3 | no |
| N = 1, (S,T) = (1,0) | on-hook | N = 7 | no |
| N = 1, (S,T) = (1,0) | **off-hook** | N = 3 | **yes** |
| N = 1, (S,T) = (1,0) | **off-hook** | N = 7 | **yes** |

It works until somebody picks up the phone. With `(S,T) = (1,0)` and channel 1
off-hook, the boundary pair `(T, A1)` reads `(0, 1)` — a static pair that is
exactly what the other strap's receiver is looking for. The inverted pattern is
perfectly sound *within* a matched pair (exhaustive enumeration: zero ungated
wrong alignments for both patterns in both hook states) and useless as a guard
against a mismatched one.

### 10.4 A half-frame monitor would work, and is cheap

A mis-strapped narrow transmitter presents a valid S/T at the receiver's own
framing positions **and** at the half-frame position. A genuine stream has payload
there, so it matches only about half the time. Measured on real speech, worst case
(that channel on-hook, so its A bit is a static 0):

| stream | half-frame check matches | longest run |
|---|---|---|
| genuine N = 3 | 50.0% of frames | 13 frames (0.41 ms) |
| genuine N = 7 | 50.0% of frames | 17 frames (0.53 ms) |
| N = 1 into an N = 3 receiver | **100%** | never clears |
| N = 1 into an N = 7 receiver | **100%** | never clears |

Trip on 64 consecutive matches and the mis-strap is caught in 64 frames — 2 ms,
the same as acquisition — with 3.8× margin over the worst genuine run. In hardware
it is a second check on the '193 that is already there, plus a gate.

Read that margin carefully before committing to it: 13 and 17 frames are maxima
over 192,000 and 384,000 frames of four speech extracts, and the underlying bit is
CVSD rather than a fair coin, so the tail is not binomial. **Soak it on more
material before relying on 64.** Offered here as a measured idea, not a design
change.

### 10.5 What to do about it

1. **Make the strap one field per end, not one per card.** A single jumper block
   or rotary switch on the backplane, distributed to the TX and RX cards, so the
   two cards at one end cannot disagree. Free, and it removes half the failure
   space.
2. **Keep the output clamp, and treat it as safety rather than polish** (§10.2).
3. **Record the strap setting on the label, both ends.** The failure is silent at
   the transmitting end — a mis-strapped link looks perfect from the end that is
   wrong.
4. **Consider the half-frame monitor** if the channel strap is ever exposed to
   the field rather than set at installation.

---

## 11. Summary

| | strappable | cost of the strap | fails safe |
|---|---|---|---|
| Line rate, 1024 / 512 / 256 / 128 / 64 kbps | **yes** | one counter tap, one RC | **yes** — never locks, mutes |
| Channel count, 1 / 3 / 7 | **yes** | tap select + address mask + 3-input AND | **no** — §10.2 |
| Asymmetric rate per direction | **yes** | nothing extra | yes |
| Asymmetric channel count | no | — | — |
| N = 2, 4, 5, 6 | no | decoded modulus, ~3 packages | — |
| Line code (biphase → AMI) | no | different driver and slicer | — |

**Nine modes — 1 / 3 / 7 channels at 16 / 32 / 64 kbps — off one 4.096 MHz
crystal** (§5.1). Modes sharing a line rate share every analog part of both
boards, so moving within a group is two jumpers and moving between groups adds a
resistor. The cost of full strappability is **one package on the TX card and
none on the RX** (§5.9).

Five things cost nothing now and keep all nine modes open:

1. **Lay out the backplane for seven slots** and bring the strap field out on it.
   This and `seven-channel.md` §7 agree; it is the one decision that cannot be
   made later.
2. **Specify ~25 mH line transformers** rather than 10 mH, terminal and repeater
   alike, so the low-rate straps are not blocked by droop (§6.5).
3. **Use a re-valuable 74HC123 RC** for the monostable with all five strap
   resistors footprinted, rather than a trimmed one-off.
4. **Footprint the '393 and the jumper fields** even if the first build is wired
   for one mode. A wire link where the '393 will go costs nothing (§5.9).
5. **Specify the output stage for 75 ns edges** if N=7 @ 64k is to stay in the
   table — it is 31% of that mode's half-cell at 150 ns (§5.3).

---

## 12. Reproducing

```
python3 strap.py all        # everything above, ~90 s
python3 strap.py matrix     # the one-crystal strap matrix
python3 strap.py hw         # one board, three straps, bit-exact; adjacency
python3 strap.py link       # the 4-bit frame: framing, acquisition, LOF, signalling
python3 strap.py audio      # CVSD rate versus the Iabc trim
python3 strap.py phy        # bandwidth, monostable window, rate mis-strap
python3 strap.py mismatch   # channel mis-strap, and the pattern that would fix it
python3 strap.py monitor    # the half-frame discriminator
python3 strap.py modes      # every mode each crystal can be strapped to
python3 strap.py robust     # degradation and acquisition, mode by mode
python3 strap.py fast512    # the 512 kbps group, both members, full chain
python3 strap.py crystal    # what actually sets the crystal frequency
python3 strap.py taps       # every mode off one chain, tap by tap
python3 strap.py grid       # the 3x3 grid and the strap matrix
python3 strap.py corner     # N=7 @ 64k, the 2.048 Mbaud corner
python3 strap.py noise      # all nine modes, relative and absolute margin
python3 strap.py pcm        # PCM vs CVSD at 64k, and the multiframe
python3 strap.py pipe       # transparent 64k slot statistics, scrambler
python3 strap.py bond       # bonding two 32k slots, no multiframe
python3 strap.py dataslot   # constant data slots: lock, acquisition, adjacency
```

Caveats that affect how the numbers should be read:

- The cable is a first-order lowpass. It models dispersion, not attenuation, so
  §6.1 is not a reach measurement and §6.2 is analysis.
- Reach ratios are √f scaling from `spec.md` §10's unmeasured anchor, and the
  quarter-rate row leaves the region where that law holds (§6.2).
- §6.3's absolute segSNRs are one talker; read the deltas. `family.md` §3 has the
  seven-talker figures.
- Transformer droop (§6.5) is arithmetic on the existing budget, not simulated.
- §10.4's margin comes from four speech extracts. It wants a longer soak.
- §6.8's NEXT scaling is textbook 15 dB/decade, not simulated. Near-end
  crosstalk at 1.024 Mbaud is the gap in the 512 kbps case.

**One inconsistency found while writing this, in the existing docs rather than
here.** `spec.md` §10 calls the 256 kbps build's fundamental **256 kHz**;
`seven-channel.md` §5.2 and `family.md` §2 call it **128 kHz**. Both are
defensible — differential Manchester runs at the line rate on an all-zeros
pattern and half that on all-ones — but they are not the same number. Every
reach figure in these documents is a *ratio* scaled from one anchor, so the
factor of two cancels and no conclusion moves. It will not cancel for whoever
takes a cable attenuation table to the bench.
