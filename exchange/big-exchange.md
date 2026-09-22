# The exchange — a bigger fabric, and why the exchange stays 8 × 8

The exchange of these documents is **8 × 8**: eight 512 kbps highways by
eight slots, **64 ports**, grown eight at a time. Dialled digits are octal
`0–7`. A port is two of them, `h s`, `00–77`. A highway is eight slots at
512 kHz. An MF8 group occupies a block: the highway **is** the 8-bit
frame with F and S given back as ports (`fabric.md` §1.1, `mf8-spec.md` §2).

This document asked whether the same highways could make a larger
exchange. They can, in 74HC. **They should not.** 128 ports is three
octal digits, and there is nothing honest to do with the third.

> **Status: analysis.** The nanoseconds are `exch.py timing` 6: the same
> 400 000 draws as `fabric.md` §4. Numbering is arithmetic on `protocol.md`
> §5. The 8 × 8 exchange is not converted, and a bigger family is not
> brought up beside it. More lines are more exchanges (`protocol.md` §3.1,
> `network.md`).

---

## 1. The extra digit

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

Two-digit local dialling, `1 e b h s` from elsewhere, trunks on block 1
as `11–13` / `15–17`, lines on `20–77`: all of that is two octal digits
and eight highways. A 128-port exchange does not fit in it. More lines
are another exchange with its own `00–77`.

---

## 2. 74HC is not the reason to stop

The 8 × 8 cell has **752 ns** of set-up (`fabric.md` §4). Sixteen slots
cut that to 255 ns, 237 after 2 m of ribbon — 74HC, and not loved.
Sixteen highways at eight slots leave the cell alone (732 ns, 694 after
sixteen blocks). 32 slots are not 74HC (`SLOTQ` at 2 ns). The numbers
are `exch.py timing` 6, the same draw as §4 of `fabric.md`.

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

---

## 3. One highway, one MF8 group

This is `fabric.md` §1.1, not a new bargain:

The highway is eight slots of 512 kbps NRZ. The MF8 line is the same
stream at 512 kbps: F at slot 0, S at slot 4, six payload channels on
1–3 and 5–7. The trunk card taps `HC[h]`/`HA[h]` and inserts the F word
(`mf8-unit.md` §1). One highway is one group of six. Eight highways are
eight groups; block 0 never takes one, so seven groups on this fabric
(`protocol.md` §5).

A 16-slot highway would still be a different exchange — two `'151`s, a
third octal digit, every port already fitted. An 8 × 8 does not ask for
one. Six payload channels over MF8 are the fused highway, not a wider
cell.

---

## 4. Verdict

**The exchange is 8 × 8.** 64 ports, eight highways, 512 kHz, two octal
digits. A highway is an MF8 group of six channels. Growth is another
exchange, not another bit in the latch.

Do not convert an 8 × 8. Do not bring up an 8 × 16 or a 16 × 8 beside it
as a family. The connectors of a 32-pin stack, the 16-bit card word, the
third local digit and a wider trunk frame are not work this exchange has.

---

## 5. Not measured

- **`exch.py timing` 6** is not a simulation of the gates, and not a
  bench. It is `fabric.md` §4's draw at other cell widths. It is why §2
  can say 16 slots is 74HC and still not wanted.
- Nothing here has been drawn. The 8 × 8 circuit is `fabric.md`.
