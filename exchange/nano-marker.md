# The exchange — a nanomarker on one board

A marker for a small PBX leaf, squeezed onto a single card. It makes two-digit
local calls, hunts an operator on `0` and an uplink group on `1`, and has one
register inside it. It reads **M, `BUSY`, and one bit of the card word** — not
the word itself, only whether the slot has one.

It is `mini-marker.md` with the network taken out and three things made
smaller: a **three-bit** pulse count, a **six-bit** digit store that is also
the called number, and **no write queue**. That is 25 packages against the
mini-marker's 33.

Key `0` hunts an operator at 04–07. Key `1` hunts an uplink group. Both hunts
read presence off the card word without reading the word — §4.

The trade is permanent and worth stating first: **`8` and `9` are gone as keys
of their own.** The register counts 1..7 and folds 8, 9 and 0 all onto 0, so
all three reach the operator. Its callers keep all ten digits on the *far*
exchange — see §7.

> **Status: proposed, measured in simulation.** `make nano` runs two lines and
> a gappy trunk block through seize, a two-digit call each way, `8` and `9`
> folding onto `0`, busy, self, an empty number, the operator hunt and its
> fixed order, an uplink hunt, the gap between two MF2 cards at four scanner
> phases, every uplink busy, abandon, and the no-digit timeout. 36 checks.
> `make nano-noop` is the same plant with `OP_EN` strapped off, 31 checks.
> Nothing has been on a bench.

---

## 1. What is fitted

```
 operators ── 04, 05 ──────────┐
 phone ── line card, slot 20 ──┤
 phone ── line card, slot 21 ──┼── blocks 0, 1, 2 ── HA, BUSY, PB ── nanomarker
 MF2 at 10 ── 10, 11 ──────────┤                     (scanner, sequencer,
 MF2 at 14 ── 14, 15 ──────────┘                      one register, cable B)
 clock card ── SLOTQ, TICK, FILL, RING_CAD
```

Straps on the card: **LEAF** (key `1` hunts, rather than being an ordinary
highway), **UP_BLK**, three DIP switches naming the uplink block, and
**OP_EN** / **OP_BLK** for the operator group. Nothing else is jumpered.
There is no class matrix, no second register, no network unit, no monitors, no
console tenure.

**Gaps in a hunt group are fine.** 12, 13, 16 and 17 above are open slots, and
the hunt walks past them — §4. It does not read the card word, only whether
there is one.

---

## 2. Seizure and the free test

**M and not `BUSY`**, as `mini-marker.md` §2. Seizure alone does not consult
the word, and does not need to: an open slot's highway line is idle, so it
never raises M and is never a call request. The word is asked about only where
the marker is choosing a port — a hunt, or a dialled number (§4, §5). There is
no trunk exclusion: a
trunk raising M is a caller like any other, which is what makes the leaf's
**offers-tone** contract work — the far end seizes the trunk, this marker
gives it dial tone, and the two digits that follow are an extension
(`leaf-uplink.md` §2).

---

## 3. The three-bit register

`rtl/nano_reg.v`. The pulse count is **three bits and one flip-flop**: half a
74HC393 counting 1..7, and a wrap FF that the eighth break sets, freezing the
count at 0.

```
 breaks    1 2 3 4 5 6 7   8   9  10  11 …
 count     1 2 3 4 5 6 7   0   0   0   0
 wrap                      ●   ●   ●   ●      (inhibits the count enable)
```

So **8, 9 and 0 all read 0**. That is the nano's own limit, and it loses no
number: a port number is six bits — two octal digits — and 8 and 9 were never
reachable numbers. The mini-marker and the full marker do not fold them: 8, 9
and 11–15 as the second digit are cannot-complete there (`protocol.md` §5).
The nano reads 2 8 as 2 0 (§5). The wrap FF is what keeps a dialled `0`
distinguishable from *no digit at all*: the strobe still fires, and the register stores a digit worth 0.

The store is **six bits in one 74HC174**, wired as a three-bit-wide two-stage
shift:

```
 after one digit    q = { 0 0 0 , d0 }      the first-key test is q[2:0]
 after two          q = {  d0   , d1 }      the called port is q[5:0]
```

**The store is the called number.** After two digits the six bits are `{h, s}`
in port order, so they go straight to the probe comparator and the DST mux.
The core keeps no `called` register, and there is no parallel mirror: a 74HC670
has one addressed read port, which is the only reason `pulse_reg` carries
`dig_r` alongside its store.

The index saturates at two. That also holds the store still — a third digit
arriving while the core is still walking the scanner round to the called port
would otherwise shift `h` out of it.

Against `pulse_reg`: the '163 goes (the count is half the '393), the '670 and
its three '174s of mirror go, the SRC latch goes, and one '74 comes back for
the wrap FF. 15 packages become 11.

---

## 4. The core

`rtl/nano_core.v`. Scanner, probe and sequencer as `mini-marker.md` §7, minus:

**No write queue.** The mini-marker carries four 15-bit slots and a pointer
pair — four '670s on a board. A nanomarker never has more than two writes
outstanding, and the second is the first **with DST and SRC swapped**, which
is one select on the '157 mux. What is left is three flip-flops and a '174 for
the far end of the pair.

| | DST | SRC | BUSY |
|---|---|---|---|
| seize | caller | 01 | set |
| first key taken | caller | 00 | set |
| cannot-complete | caller | 03 | set |
| let go | caller | 00 | clear |
| connect | caller | far | set |
| …then | far | caller | set |

The caller's address is the register's own port latch, which `nano_reg` holds
past release rather than clearing, so the core does not keep a second copy of
it.

**No 64-bit trunk mask.** `UPLINK_MASK[64]` is eight '151s or a PROM on a
board. A hunt group is one strapped block: `scan[5:3]` against three DIP
switches. The hunt walks that block in scan order, takes the first port that
is free *and fitted*, and gives up when it comes back round to the slot it
started on — one revolution, at most 8 ms.

**One hunt, two keys.** Key `1` hunts `UP_BLK`, rotary from wherever the
scanner is. Key `0` hunts the operator at `OP_BLK` 4–7, in fixed order from 04
— the hunt is held off until 04 comes round, so 04 answers whenever it is
free, which is where `mvp.md` puts the operator's home. The difference between
the two is one flip-flop, a three-input NOR and a select.

**Presence, without reading the word.** An open slot reads `M = 0`,
`BUSY = 0` — bit for bit what a free trunk reads. The scanner cannot skip it,
because slot *k* has its time on the highway whether or not a card is in it.
What separates them is the card word: all-zero is the reserved `none/OOS`
constant (`extensions.md` §2.2), the pin is low for a 1, and an open pin floats
up through its 680 Ω to read all zeros.

The nanomarker does not take the word in. It only asks **whether there is
one**:

```
 visit:  w_acc <= w_acc | PB_word        accumulate across the 16 bit-times
 octet:  p_word <= w_acc ; w_acc <= 0    present = the word was not all zeros
```

Two flip-flops and a gate, against a '164 and an eight-input NOR for the full
read. A single bit-time will not do it — `none/OOS` is all-zero but the other
forms are mixed (a trunk's `TT` is `10`, `class+cover` is `01`, a tied nail's
`tt` is `00`), so it has to be the OR across the visit.

That is what lets a group have gaps in it. An MF2 takes two channel slots
(`mf2/spec.md` §10), so an MF2 at 10 and another at 14 are four channels with
12, 13, 16 and 17 open between and after them; the hunt walks 10, 11, 14, 15
and never offers a caller an empty slot. Nothing is strapped for it, and it
follows the plant when a card is added.

```
IDLE → (M · /BUSY, register free) → COLLECT
     → (two keys) → PROBE → visit called, free → pair writes, IDLE
     ↘ first key 0 / 8 / 9, OP_EN → HUNT 04–07 → pair, or 03, IDLE
     ↘ first key 0 / 8 / 9, no OP_EN → 03, IDLE
     ↘ first key 1, LEAF → HUNT UP_BLK → pair, or 03, IDLE
     ↘ register let go (CLR, no-digit) → 03 or 00, IDLE
```

---

## 5. Wrong numbers

| 20 dials | nanomarker |
|---|---|
| 0, 8, 9 | the operator at 04–07. All three count as 0, so a misdialled 8 or 9 reaches the operator too — that is not optional |
| 0, 8, 9 with `OP_EN` off | cannot-complete on the first key |
| 0, every operator busy | cannot-complete after one revolution |
| 2 8, 2 9 | port 20, the same as 2 0. The second key folds too |
| 2 0 | itself, busy → cannot-complete |
| 1, every uplink busy | cannot-complete after one revolution of the block |
| 1, open slots in the trunk block | walked past; the hunt only offers fitted ports |
| 2 5, an unequipped slot | cannot-complete, and the empty latch is never written. `mini-marker.md` §2 patches the caller to it instead and calls the silence acceptable on a jig; the same word bit the hunt uses buys the full marker's answer here for one more input on an OR |
| hang up mid-dial | the register lets go on CLR (256 ms) |
| off-hook, nothing dialled | cannot-complete after the no-digit timeout |

---

## 6. Packages

`make synth-hc-nano`. Both totals are the hand BOMs in
[`pack.py`](../verilog/tech/hc/pack.py), on the same basis.

| | mini-marker | nanomarker |
|---|---|---|
| register | 15 | **11** |
| core | 16 | **12** |
| cable B serialiser | 2 | 2 |
| **total** | **33** | **25** |

Where the eight go:

| | |
|---|---|
| write queue: four '670s | −4 |
| digit store: '670 + three '174s of mirror → one '174 | −3 |
| pulse count: '163 → half the '393 already there | −1 |
| SRC latch | −1 |
| wrap FF, and a '174 for the far end of a pair | +2 |
| `called` register folded into the store, no 64-bit mask | −1 |
| operator hunt: 1 FF + ~3 gates; presence: 2 FFs + 1 gate | in the glue already billed |

25 DIP packages, a DIN 41612 and the two strap switches is a Eurocard.

---

## 7. What it will not do, ever

**No `8` and no `9` as keys of their own.** The register counts to seven and
folds 8, 9 and 0 all onto 0, so the three are one key. An operator survives
that — `0` against `1–7` is still a distinction — but a prefix 8 and an
outside-line class are not separable from it, and a misdial of 8 or 9 goes to
the operator. Fit a mini-marker if the leaf needs 8 or 9 to mean something.

**But its callers keep all ten digits on the far exchange.** Digit `1` patches
the caller to an uplink and the register is **released** — this marker has
left. The loop pulses that follow ride the trunk's M lead to the central,
whose own full-width register counts them. `1` then `0`, or `9`, or
`1 e b h s`, all work exactly as `leaf-uplink.md` §2 says, because none of
those digits was ever counted here.

Also not, and not missed: a card word, a class hunt, a nail, an answers-to, a
second register, a network unit, monitors, event words, `/CON`.

---

## 8. RTL

| | |
|---|---|
| `verilog/rtl/nano_marker.v` | register + `ctl_write` + core |
| `verilog/rtl/nano_reg.v` | §3, the three-bit register |
| `verilog/rtl/nano_core.v` | §4, scanner, probe, write engine, sequencer |
| `verilog/rtl/pulse_rx.v` | shared with `pulse_reg`; `CNTW = 3` is §3's count |
| `make nano` | the bench (`tb/nano_site.v`, `tb/tb_nano.v`), 36 checks |
| `make nano-noop` | the same plant with `OP_EN` off, 31 checks |
| `make synth-hc-nano` | §6 |

`pulse_rx` is the same listener the shared register uses. `CNTW` picks the
count: 4 is the '163 freezing at 15, 3 is §3. Nothing else differs, so the
break, interdigit and clear windows stay in one place.
