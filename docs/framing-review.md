# Framing and sync — re-evaluated

> **Working record.** Its conclusion was adopted, with refinements found while
> writing the standard: the check must require *exactly* one zero in the last four
> T, and that one check with a single +1/−1 trip 16 counter replaces the phase
> counter and predictive check described below (`s4_simple.py`). The standard is
> `spec.md` §3 and §7.

The framer in `spec.md` §6 was designed once and then patched three times in
`draft-protocols.md` as failure modes turned up. This document starts over: it
states what frame sync has to survive, turns every failure found so far into one
test battery, and runs every framing scheme worth considering through it side by
side (`framing_review.py`). Nothing here is argued that was not measured, except
§9, which says so.

---

## 1. What sync has to do, and what it does not

Three layers, and only the middle one is in question:

| layer | mechanism | status |
|---|---|---|
| bit sync | differential Manchester + monostable interval classifier | settled (`spec.md` §4–5); no clock, no threshold, rate-blind |
| **frame sync** | find the frame boundary, hence slot identity | **this document** |
| sample sync | — | none; CVSD has no sample boundary, and data slots bring their own (`draft-protocols.md` §8) |

The two directions never synchronise to each other (`spec.md` §1), so frame sync
is a one-way problem solved twice.

## 2. What the framer has to survive

Each of these broke something in the last week of work. Together they are the
battery.

| payload class | property that matters | what it broke |
|---|---|---|
| CVSD speech | random in level (50/50); **~95% alternating** in transition | the toggling-T framer |
| CVSD silence | **exactly `1010…`** | both toggling framers, permanently on an idle link |
| constant data slot | all-0 or all-1 in one C position | the present framer, when adjacent to the opposite static A bit |
| static A bits | on-hook 0 / off-hook 1, mixed across channels | completes static pairs with the above |
| narrow TX into wide RX | every CVSD bit becomes a **constant** when subsampled during silence | every static scheme; the present one locks permanently |
| line errors to 3e-2 | | acquisition time and false reframes |

And the constraints that stay: `2 + 2N` a power of two (`spec.md` §2), the
framing field at the end of the frame (`line-transmitter.md` §2), 74HC, and no
multiframe that anything downstream depends on.

## 3. The candidates

| scheme | framing field | TX pattern | RX check | RX state |
|---|---|---|---|---|
| **S0** present | 2 bits | `(0,1)` static | level match | none |
| **S2** | 4 bits | `(0,1,1,0)` static | level match | none |
| **S2b** | 4 bits | `(0,0,1,1)` static | level match | none |
| **S4** | 2 bits | S = 0, T = `1110` repeating | S = 0, T window is a rotation of `1110` | 4-frame phase, after lock |
| **S5** | 2 bits | S = 0, T = period-7 m-sequence | S = 0, T window is a rotation | 7-frame phase, after lock |
| **S3** | 3 bits + a designated data slot | `110` then `D`: the word's third bit *is* the data slot's strapped A bit | level match on `110`; D is free | none |

Two more were built, measured and rejected before this review — T toggling alone
and S,T toggling together (`draft-protocols.md` §8.5); both are period-2 patterns
and CVSD silence *is* a period-2 pattern. They are not in the table because they
false-lock on 7/8 skews with the link idle.

Note on the 4-bit words: their power-of-two family is N = 2 and N = 6, not 3 and
7. The battery ran them at N = 3 and 7 for comparability of the *framing*
behaviour; the channel cost is in §5.

## 4. Side by side

3 s of speech, mixed hook states, `confirm = 64`, `+2/−1 trip 12`. "fl" = false
locks out of all start-up skews. The constant-slot column is the exhaustive
count — every seat, both constants, every hook state — not the battery's
four-adjacency sample, which missed S2's hole.

| scheme | frame | acq clean | fl speech | fl idle | **fl constant slot** | LOF worst | reframes 1e-3 / 1e-2 / 3e-2 | acq @ 3e-2 | mis-strap 1→3 / 1→7 / 3→7 |
|---|---|---|---|---|---|---|---|---|---|
| **S0** present | 8b | 1.97–2.09 ms | 0/8 | 0/8 | **40 / 192** | 0.66 ms | 0 / 0 / 0 | 33 ms | **LOCK LOCK LOCK** |
| S2 `(0,1,1,0)` | 10b¹ | 1.97–2.06 ms | 0/10 | 0/10 | **3 / 240** | 0.16 ms | 0 / 0 / 0² | fast² | LOCK³ |
| S2b `(0,0,1,1)` | 10b¹ | 1.97–2.00 ms | 0/10 | 0/10 | **0 / 240** | 0.16 ms | 0 / 0 / 1–3² | fast² | LOCK³ |
| S3 `110` + D | 16b, N=6 | 1.97–2.12 ms | 0/16 | 0/16 | **0 / 240**⁴ | — | 0 / 0 / 1 | — | LOCK (2→6) |
| **S4** T = `1110` | 8b | 1.97–2.25 ms | 0/8 | 0/8 | **0 / 192** | 1.16 ms | 0 / 0 / 0 | 38 ms | **ok ok ok** |
| S5 T = m-seq 7 | 8b | 1.97–2.31 ms | 0/8 | 0/8 | 0 / 192 | 0.78 ms | 0 / 0 / 0 | 38 ms | LOCK LOCK LOCK |

¹ At N = 3 for comparability; the real members are 8b at N = 2 and 16b at N = 6.
² The battery reported 1.1–2.4 s "acquisition" at 3e-2 for the 4-bit words. That
was an artefact: they lock in milliseconds and then, at 3e-2, reframe one to
three times in 3 s because all four bits must be right every frame, and the
metric reported the last re-lock. The 2-bit schemes had zero reframes.
³ In their real family, N = 2 → N = 6: locks, for the same word and for
different words (§7).
⁴ D as voice, constant 0, constant 1, `1010`, `0101`, at all-on-hook,
all-off-hook and mixed, plus idle; and a *second* constant slot in seat 6. A
second constant slot in seat 1, adjacent to D, false-locks (3/16): that seat
must stay voice.

Same results at N = 7 in every column, with S4 at 0/512 on the exhaustive
constant-slot test and 0/16 on idle.

## 5. What the table says

**S0 — the present framer — is clean on every voice case and fails on exactly
two things:** a constant data slot in the wrong adjacency, and the mis-strap.
Both are permanent locks. Everything else is 0.

**S2b — a 4-bit static word — fixes the data slot and nothing else.** It also
rejects slips four times faster (0.16 ms against 0.66) because a slipped window
almost never matches four bits. The word matters more than the length:

- It must be **bifix-free** (no prefix equal to its own suffix), or a window
  straddling the frame boundary can be completed by one data slot and a static A
  bit. Enumerated over all sixteen 4-bit words and confirmed by simulation:
  `(0,0,0,1)`, `(0,0,1,1)`, `(0,1,1,1)` are safe; `(0,1,1,0)` has a hole at
  offset 3 and measures 3 false locks; `(0,1,0,1)` has two.
- `(0,0,1,1)` **is the second counter bit** — where the present `(0,1)` is
  `LSB`, this is `LSB+1`. Zero additional logic on either card.
- It costs **one channel at every power-of-two frame**: N = 2 not 3 at 8 bits,
  N = 6 not 7 at 16 bits. At the committed 256 kbps that is a third of the
  capacity.
- It costs occasional reframes at 3e-2 BER, where the 2-bit schemes have none.
- It does not touch the mis-strap.

**S3 — `110` followed by a designated data slot — is the present framer's
"strap the data slot's A bit" rule made verifiable.** Read `1100` as `11` plus a
pseudo-channel `[A=0][C]`, then let that C carry data: the frame is
`[1][1][0][D][A1][C1]…[A6][C6]`, the framer checks `110`, and D is free. The
strapped A bit is now *inside the framing check*, so a mis-set strap is a link
that never locks rather than a silent hole. Measured: 0 false locks for D as
voice, constant 0, constant 1, `1010` and `0101` at every hook state, 0 on
idle, and a second constant slot in seat 6 is also safe; a second constant slot
in seat 1 — adjacent to D — false-locks on 3/16 skews, so that seat stays voice.
The word is bifix-free, which is why the two windows straddling into D fail on
word bits before D matters. Cost relative to N = 7: one voice channel becomes
the data channel and the framing field grows by one bit, at the same line rate;
one reframe at 3e-2 BER where the 2-bit words have none; and the mis-strap is
untouched (N = 2 → N = 6 locks). Against the present framer with the seat-7
rule it is the same 6 voice + 1 data capability with the strap enforced by the
protocol instead of by a label.

**S2b as a plain 6-channel system with a fixed `1100` header** — the simplest
reading of the above, with no designated seat — measures the same way (`1100` is
`0011` inverted, and the framer's failure modes are polarity-symmetric):

| `1100`, N = 6, 16 bits | result |
|---|---|
| speech, idle, any hook state | 0/16 false locks |
| one constant or periodic data slot, **any of the six seats** | safe (bifix-free; **0/768** exhaustive at N = 6 — every seat × both constants × every hook state × 16 skews; 0/240 at N = 3) |
| two data slots, non-adjacent seats | safe — (1,3) (1,4) (1,5) (1,6) (2,4) (2,5) (2,6) (3,5) (3,6) (4,6) |
| two data slots, **adjacent** seats | **unsafe** — a 4-window `(A,C,A,C)` with both C constant can equal the word |
| acquisition, `confirm = 16` | 0.47–0.62 ms clean, 0.8 ms at 1e-2, 0 false locks |
| reframes at 1e-2 / 3e-2 | 0 / 1–2 per 2 s |
| mis-strap N = 2 → N = 6 | **locks** |

**Using both bits of a slot as data.** The enumeration never assumed a data
slot's A bit is 0 — every static bit was a free value — so a slot carrying data
on A *and* C is covered. Measured for one such slot at seats 1, 3 and 6, with
A,C = `0,1` / `1,0` / `1010,1` / `1,0101` / random: **0/16 everywhere**. The
present 2-bit framer false-locks on 2/16 and 3/16 for the same slot. So the
4-bit header is what makes a 2-bit data channel (64 kbps at 32 kHz) safe, not
what prevents it.

**Mixing voice, data and unused seats.** V = CVSD voice, D = data on A and C
(any idle value, each seat independently), N = unused, A and C pulled to a fixed
value. Enumerated over all 729 seat patterns at every pull value, and simulated
at the worst data idles:

| pattern | result |
|---|---|
| `VVVVVV` all voice | safe |
| `DVDVDV`, `VDVDVD` data between voice | **safe** (0/16 simulated) |
| `NNNNNN` all unused, any fixed pull | safe |
| `DNDNDN` data between unused | **unsafe** — 11–12/16 simulated |
| `DDDDDD` all data | **unsafe** when neighbouring seats idle different values — 12/16 with `11`/`00` alternating; safe only if every seat idles the same value, which cannot be relied on |

The rule that holds exactly: **every data seat must have voice on both sides (or
the header).** No pattern obeying it is unsafe at any pull value — 0 of 729 —
while unused seats may sit next to each other and next to voice freely. The rule
is sufficient rather than necessary; some data-beside-unused patterns are safe
for particular pull values and orderings, but none is safe for all of them, and
a label should not depend on which resistor was fitted.

A 4-bit word gates a random window at 1/16 per frame instead of 1/2, so
`confirm = 16` gives the same 2^-64 per-attempt safety the present framer gets
from 64, at a quarter of the acquisition time. The rule for data slots is one
line: **any seat, but never two adjacent.**

**S4 — S static, T carrying `1110` — passes everything.** Zero false locks on
speech, on idle, on every constant-slot adjacency exhaustively at N = 3 and 7, on
idle *with* a constant slot, and it is the only scheme that **mutes on every
mis-strap, on speech and on idle**. Zero reframes to 3e-2. Why it works where
the toggling schemes died:

- A CVSD bit alternates; `1110` does not. Silence at the T position gives a
  window with two zeros in four and fails. The worst wrong alignment (A = 0 in
  the S position, CVSD in the T position) passes 25% of frames against S0's
  50% — S4 is *better* gated than the present framer, not worse.
- A constant fails the window outright.
- A wide receiver samples the narrow frame's T every other narrow frame:
  `1110 1110` decimated by two is `1111` or `1010`, and neither has exactly one
  zero in four. Decimated by four it is a constant. **The divisibility that
  defeats every static scheme is exactly what defeats the mis-strap here.**

Its costs: the TX pattern is `T = NOT(Q_f+1 · Q_f+2)` — two taps that already
exist on the '4040 one and two stages below the frame clock, and one gate. The
RX is a 4-bit shift register on T, an "exactly one zero" decode, an AND with
S = 0, and — this is the part that must be said plainly — **a 2-bit phase
counter synchronised at lock**, because checking the window after lock instead
of predicting T from the phase is unusable:

| S4 post-lock check | LOF worst | reframes 1e-3 / 1e-2 / 3e-2 | acq @ 3e-2 |
|---|---|---|---|
| predict T from tracked phase | 1.16 ms | **0 / 0 / 0** | 38 ms |
| keep using the 4-frame window | 0.19 ms | 2 / 52 / 63 | 3 s |

One line error corrupts one predicted frame but four windowed ones, and the
`+2/−1 trip 12` counter cannot survive that at 1e-2. So S4's receiver carries a
4-frame phase. Nothing downstream uses it — it is not a multiframe in the sense
`draft-protocols.md` §8.3 ruled out, where PCM needed the phase — but it is phase
state in the framer, and it is about half a package: one '164 or '175 for the
window, one '74 for the phase, gates.

**S5 — an m-sequence on T — is dominated by S4.** Same voice results, slower LOF
at N = 7 (2.12 ms), and it does *not* fix the mis-strap: decimating an
m-sequence by 2 yields a shift of the same m-sequence, so a wide receiver sees a
valid pattern. Longer is not better here; the period being a power of two is
what matters.

## 6. The acquisition threshold

64 consecutive good frames was never justified. With the interleaving rule a
wrong alignment passes at most ~50% of frames, so a false lock per attempt is
2^-confirm, and the `+2/−1` counter clears any transient one in ~0.5 ms anyway.
Only permanent (static) false locks are immune to the count, and those do not
depend on it.

| confirm | S0 acq clean | S0 @ 1e-2 | S0 @ 3e-2 | S4 acq clean | S4 @ 3e-2 | false locks, speech + idle |
|---|---|---|---|---|---|---|
| 16 | 0.47–0.59 ms | 0.5 ms | 0.6 ms | 0.47–0.75 ms | 1.2 ms | 0 |
| **32** | **0.97–1.09 ms** | **1.6 ms** | **2.2 ms** | **0.97–1.25 ms** | **2.3 ms** | **0** |
| 64 | 1.97–2.09 ms | 4.5 ms | 33 ms | 1.97–2.25 ms | 38 ms | 0 |

**Use 32.** Half the clean acquisition time, 15× faster at 3e-2, and 2^-32 per
attempt is one chance in four billion of a transient lock that would clear
itself. In hardware it is one fewer stage on the acquisition counter.

## 7. The mis-strap, definitively

`draft-protocols.md` §10.2–10.4 found that a narrow transmitter locks a wide
receiver permanently, that changing the framing polarity does not help, and that
a half-frame monitor can detect it. This review adds the mechanism and the
consequence:

**Under a ×2 mis-strap every CVSD bit in the narrow payload becomes a constant
during silence**, because the wide receiver samples it every other narrow frame
and silence is `1010…`. The gating the interleaving rule relies on collapses for
*every* static framing word — distinct 4-bit words per frame width still
cross-lock in almost every combination (measured, N = 2 → N = 6). No static
pattern can be chosen around it.

S4 is the only scheme measured that *prevents* it, for the reason in §5. If S4
is not adopted, the half-frame monitor remains the answer, as a detector.

## 8. What real systems did

The same three tools, used by everyone who has had this problem:

| system | frame sync | where it sits in this review |
|---|---|---|
| **T1 / DS1** | one F-bit per 193-bit frame carrying a periodic pattern — 12 frames in D4, `001011` over 24 frames in ESF, plus a CRC-6 | the **S4 / S5 family**. D4 was known to false-frame on repetitive payloads; ESF added the CRC-6 to *verify* the frame, which is the same lesson as §2 |
| **E1 / G.704** | a 7-bit word `0011011` in TS0 of alternate frames, and a `1` in bit 2 of the other frames specifically so that no wrong alignment can see the word twice running | the **S2b family**, with an anti-imitation bit that is the alternate-frame ancestor of the bifix-free rule |
| **ISDN BRI U / 2B1Q — what DAML pair-gain is built on** | a 9-symbol sync word per 120-symbol frame (~7.5%), an 8-frame superframe marked by *inverting* the sync word, and a self-synchronising scrambler on the payload | a multibit word **and** a superframe **and** a scrambler, together — every tool in `draft-protocols.md` §8 in one standard |
| **MIL-STD-1553, IEEE 802.5, FDDI, ISDN S/T** | **framing by code violation** — a symbol the line code cannot produce from data: 1553's 3-bit-time invalid Manchester sync, token ring's J/K, I.430's bipolar violation on the F bit | **§9** — the one approach not in the table, and the one that sidesteps §2 entirely |
| **TRI-TAC** | CVSD at 16/32 kbps over conditioned diphase — the same codec and the same line-code family as this design, in the same power-of-two rate family | I do not trust my memory for its framing word; the MIL-STD-188-200 series is where it is specified, and it is worth looking up before §9 is pursued |

Two things stand out. First, nobody uses a bare 2-bit static pair on a
payload-agnostic link; the systems that carry arbitrary data either scramble
(2B1Q) or verify (ESF CRC). Second, every system built on a Manchester-family
line code — 1553, 802.5, FDDI — frames by **code violation**, not by data bits.

A note on scrambling, since 2B1Q relies on it: a self-synchronising scrambler
must be seeded nonzero or an all-zero payload passes through unchanged, and even
seeded it locks up on ~2^-7 of all-zero idle onsets (measured 0.73%,
`draft-protocols.md` §8.5). Cheaper transforms — inverting alternate bits, or
NRZI — merely relocate the hole onto a period-two or all-zero payload. A
payload-side fix therefore never quite closes; a framing-side one (S4) or a
code-violation one (§9) does, which is a further reason to prefer them.

## 9. Framing by code violation — proposed, not measured

Every scheme in §3 uses data bits for framing, and §2's impossibility result
follows from that: a static pattern is mimicked by static payload, a period-2
pattern by silence, a longer period needs a phase. **A code violation is not a
data bit**, and no payload can produce one, because the payload is confined to
valid symbols.

In differential Manchester a violation is a missing boundary transition: an
interval of 1.5 or 2 cells where the code only ever produces 0.5 or 1. The
transmitter suppresses the transition at the framing position — one gate on the
T flip-flop's enable. The receiver adds a second monostable at ~1.25 cells,
whose firing *is* the frame pulse. MIL-STD-1553 does exactly this at 1 Mbaud with
a symmetric 1.5-high / 1.5-low sync that stays DC-balanced and keeps a
mid-sync transition for timing.

What it would give: framing that no payload can mimic, at any hook state, with
any data slot, on an idle link; no phase state; no scrambler; and a mis-strap
that announces itself as violations arriving where none are expected. The
2-bit framing field stays 2 bits (the violation replaces S and T, or one of
them), so the power-of-two frame and every counter identity survive.

What it would cost, and why it is not in §4: it changes the **physical layer**,
not the framer. The monostable receiver's self-healing state machine
(`spec.md` §5.1) has never seen a 1.5-cell interval; the noise margin, the ±13%
timing window and the squelch pathology were all measured on a waveform with a
transition every cell; and the repeater slices and re-drives, so a violation
must survive regeneration. All of that is a PHY simulation — `phy.py`,
`fast.py`, `repeater.py` — and none of it has been run. It is the strongest
candidate on precedent and the least measured, and it should not be adopted on
precedent.

## 10. Recommendation

1. **Set `confirm = 32`** whatever else is decided (§6). It is free.
2. **Among data-bit schemes, S4 is the measured winner** and the only one that
   closes every hole in §2 including the mis-strap. Its price is a 2-bit phase
   counter in the receiver and about half a package. If that phase state is
   acceptable — it is used by nothing but the framer — adopt it. If not, the
   present framer stays, with the data-slot fix in the payload
   (`draft-protocols.md` §8.5 — a *seeded* scrambler, which still carries a
   ~2^-7 lockup per idle onset) and the half-frame monitor for the mis-strap.
3. **If one data slot is the goal and the phase counter is not wanted, S3 is
   the cleanest static answer**: `110` + D, the strap verified by the framer,
   6 voice + 1 data at 512 kbps, no new state. It does not close the mis-strap.
4. **A 4-bit word is the wrong trade for this design.** It fixes only the data
   slot, at the cost of a channel per frame, and it must be bifix-free; if it is
   ever wanted, `(0,0,1,1)` is the second counter bit and costs no logic.
5. **Simulate code violation before choosing between S0 and S4.** It is what
   every Manchester-family system in the field does, it removes the problem
   rather than gating it, and it is the only option here whose risks live in a
   layer this repository can already simulate. Two days of PHY work decides
   whether the framer question needs answering at all.

## 11. Reproducing

```
python3 framing_review.py all      # the side-by-side battery + the 110+D layout, ~45 min
python3 framing_review.py quick    # 2 s clips, ~15 min
```

The exhaustive constant-slot tests, the bifix enumeration, the confirm sweep,
the post-lock mode comparison and the idle mis-strap were run as one-off scripts
against `framing_review.py`'s harness and are reported in the tables above; they
belong in the script's `all` target and are not there yet.

Caveats: 3 s of one talker; silence is the codec's own idle output; N = 7
constant-slot runs sampled four seats; the 4-bit words were battery-tested at
N = 3 and 7 rather than their true family; §9 is unmeasured.
