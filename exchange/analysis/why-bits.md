# Why bits, and why 64 ports

Why the fabric switches 64 kbps bits and not voice band, why one exchange
stays 8 × 8 and grows by more exchanges, and why a bigger fabric of the same
highways is not built. The design these conclude in is `fabric.md`.

> **Analysis.** Measured by `exch.py tandem` and `exch.py timing` 6 (`sim/exch.log`) against the fabric before the fold (`HA[0..7]`, cable A/B).
> **Changed since:** A is two scanned open-drain planes at 64 kbps, which makes the 1 ms supervision pass, not the C cell, the binding limit on the port count (§3.5). The network trunk built is the local eight-channel trunk, filling all eight seats; an MF8 group takes appearances 1–3 and 5–7 of a block (`trunks.md` §4), and what seats 0 and 4 hold, and the adapter's face, are open (`trunks.md` §5). §1's slip, −25 dB for 5 ms, is the earlier codec law's: `mf8/mf8-backplane.md` §7 now gives −29 dB, settled in 1.3 ms.
> **Not re-run:** the timing table (§3.2) for the drawn boards; the tandem figures need no re-run.

---

## 1. Why bits and not voice band — measured

The classical answer is four-wire audio plus E&M between every card and the
switch. It is universal, and it was measured before being set aside
(`exch.py tandem`: 7 talkers × 12 s, each stage encode → decode → 3.4 kHz
reconstruction, the next card's 300–3400 Hz filter, level trimmed back to
nominal):

| codecs in the chain | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| segSNR, codec noise alone, dB | 23.40 | 21.38 | 19.09 | 18.00 | 17.09 |
| loss | — | **−2.02** | −4.31 | −5.40 | −6.31 |
| segSNR against the source, dB | 22.50 | 16.40 | 13.81 | 12.69 | 11.78 |

Each tandem costs about 2 dB of codec noise for the first two and about 1 dB
after. The first row scores against the source passed through the same filters
with no codec in the chain, so it is the codec's noise alone; the last row adds the
band-edge droop of the cascaded filters, which is real in kind and overstated in
size — the model's filters are zero-phase Butterworths, steeper than a card's.

What that does to calls, in codecs in the chain:

| call | voice-band fabric | bit fabric |
|---|---|---|
| CVSD phone to CVSD phone, one exchange | 2 | **1** |
| … across one MF8 trunk | 3 | **1** |
| … through a transit exchange | 4 | **1** |
| CVSD phone to analog phone, one exchange | 1 | 1 |
| analog phone to analog phone, one exchange | **0** | 1 |
| … across one trunk / through a transit | 1 / 2 | 1 / 1 |
| 64 kbps data | cannot | passes |

Voice band wins one row: two analog phones on one exchange never meet a codec.
Everywhere else it costs the digital phone — the project's centrepiece — a
tandem on a *local* call, puts the `mf8/mf8-spec.md` §12.1 engine on every digital
line and six of them behind every trunk card, and cannot switch data at all.
With bits switched, the only per-hop cost is the clock-crossing slip
`mf8/mf8-backplane.md` §7 measured at −25 dB for 5 ms.

What voice band gets right is kept another way:

| | here |
|---|---|
| anything connects to anything | **voice on the fabric is MF8's 64 kbps CVSD.** A card facing anything else transcodes on the card: the FXS card does; a DNVT card is two codecs back to back |
| E&M as the universal port signalling | kept exactly: `A` |
| tones, ringing, conference, DTMF are easy | they are **lines** (`features.md`, `proposed/conference.md`) |

The tandem loss with real filters is not measured: the "against the source"
row overstates the droop, and the codec-only row is the one to quote.

---

## 2. Past 64 ports: more exchanges, not a bigger one

**Decided: the exchange stays 8 × 8 — 64 ports**, and a larger system is several
of them joined by trunks and the flood (`network.md`). Four ways of
making one fabric bigger were worked through and set aside as too complex for
what they bought:

| | what it was | why not |
|---|---|---|
| banks joined by junctors, a rack marker, a shared service highway | several 64-port fabrics in one rack as one exchange | a fifth of all ports become junctors at 100 lines and a third at 1000; registers cannot be pooled; tie wiring, a tandem stage, a marker that hunts paths |
| 64-slot highways at 4.096 Mbps | a rack of 512 ports behind one '151 | a 244 ns cell is outside comfortable 74HC |
| allocated talk slots, 16 to a highway at 1.024 Mbps | a port holds a slot only while it is in a call, so a listener need only reach the slots in use | a second rate; ≈ 8 packages a port against 5 |
| the same in MF8's own frame at 512 kbps, highways pooled in fours | one rate, sixteen banks in one stage | ≈ 11 packages a port: four to six packages a line more than anything else here |

The four rows are junctors, a 244 ns cell, allocated slots, and pooling
highways. A bigger fabric of the same highways still costs a third octal
digit (§3). The exchange stays 8 × 8.

---

## 3. A bigger fabric, and why the exchange stays 8 × 8

The exchange is **8 × 8**: eight 512 kbps highways by eight slots, **64
ports**, grown eight at a time. Dialled digits are octal `0–7`. A port is two
of them, `h s`, `00–77`. A highway is eight slots at 512 kHz.

This section asked whether the same highways could make a larger
exchange. They can, in 74HC. **They should not.** 128 ports is three
octal digits, and there is nothing honest to do with the third.

### 3.1 The extra digit

64 ports is `00–77`. 128 ports is `000–177`. Every geometry that doubles
the exchange spends a bit, and that bit is a leading digit:

| geometry | cell | local number | the third digit |
|---|---|---|---|
| **8 × 8, as now** | 1.95 µs, 512 kHz | `h s`, **00–77** | **none** |
| 8 × 16 | 977 ns, 1.024 Mbps | blocks `00–17`, `20–37`, … | panel, or the top of a 4-bit slot |
| 16 × 8 | 1.95 µs, 512 kHz | highway `00–17`, slot `0–7` | the top of a 4-bit highway |
| 16 × 16 | 977 ns | packed `000–377` | two extra bits; not octal on a dial |

**Key 0 is the operator. Key 1 is a highway, or the flood.** Both are
already taken. A third local digit has to be collected on 0 (so a lone 0
times out as the operator) and is illegal on 1 when the exchange is
networked (so `100–177` cannot be lines). That is not a map. It is a
collision with the code that already works.

Two-digit local dialling, `1 e b h s` from elsewhere, lines on `20–77`: all of
that is two octal digits and eight highways (`numbering.md` §1, §2). A
128-port exchange does not fit in it. More lines are another exchange with
its own `00–77`.

### 3.2 74HC is not the reason to stop

The 8 × 8 cell has **752 ns** of set-up (`fabric.md` §7). Sixteen slots
cut that to 255 ns, 237 after 2 m of ribbon — 74HC, and not loved.
Sixteen highways at eight slots leave the cell alone (732 ns, 694 after
sixteen blocks). 32 slots are not 74HC (`SLOTQ` at 2 ns). The numbers
are `exch.py timing` 6, the same draw as `fabric.md` §7.

So a 16 × 8 would keep 512 kHz and keep one highway = one MF8 trunk, and
the gates would hold. It still needs the third digit. That is why it is
not built.

| | cell | set-up / hold | SLOTQ before enable |
|---|---|---|---|
| **8 × 8** | 1 953 | **752 / 927** | 368 |
| 16 × 8 | 1 953 | 732 / 930 | 368 |
| 8 × 16 | 977 | 255 / 427 | 123 |
| 16 × 16 | 977 | 239 / 434 | 124 |
| 8 × 32 | 488 | 31 / 160 | 2 |

### 3.3 One highway, one MF8 group

The highway is eight slots of 512 kbps NRZ. The MF8 *line* is the same
stream at 512 kbps: F at bit 0, S at bit 4, six payload channels on
1–3 and 5–7. The unit is a **block adapter** that inserts F and S on the way
to the pair (`trunks.md` §4). One highway is one group of six.

A 16-slot highway would still be a different exchange — two `'151`s, a
third octal digit, every port already fitted. An 8 × 8 does not ask for
one. Six payload channels over MF8 are the fused highway, not a wider
cell.

### 3.4 Verdict

**The exchange is 8 × 8.** 64 ports, eight highways, 512 kHz, two octal
digits. Growth is another exchange, not another bit in the latch.

Do not convert an 8 × 8. Do not bring up an 8 × 16 or a 16 × 8 beside it
as a family. The connectors of a 32-pin stack, the 16-bit card word, the
third local digit and a wider trunk frame are not work this exchange has.

### 3.5 The fold and the six-bit address are one decision

The supervision planes carry one port a 64 kHz bit-time, so a pass is as many
bit-times as there are ports (`fabric.md` §3). At six bits the pass is 1 ms
and every hook refreshes at 1 kHz: an 18 ms dial break is eighteen samples
against a register's eight-sample `HIT` window. At nine bits the pass is 512
bit-times, 8 ms, and a hook refreshes at 125 Hz, two samples in a dial break.
Keeping a kilohertz at 512 ports would mean putting A back on the 512 kHz cell
grid, which undoes the fold. The control word is fixed by the same number: it
is 2 × 6 + 4 = 16 bits, and its low eight are the port's '273 verbatim
(`bus.md` §4). So since the fold, **the supervision pass, not the C cell, is
what binds the port count**, and it binds it at 64 (`newimpl/rtl/exch.vh`).

### 3.6 Not measured

- **`exch.py timing` 6** is not a simulation of the gates, and not a
  bench. It is `fabric.md` §7's draw at other cell widths. It is why §3.2
  can say 16 slots is 74HC and still not wanted.
- Nothing here has been drawn. The 8 × 8 circuit is `fabric.md`.
