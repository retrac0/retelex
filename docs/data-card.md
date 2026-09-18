# Data channel card — synchronous, bit-transparent

The second channel card option, alongside the CVSD voice card
(`channel-card.md`). It occupies one slot, uses the same backplane signals, and
turns that slot into a synchronous bit pipe at the mode's per-channel rate.

Status: interface definition. The framing rules in §2 are measured
(`seatmix.py`, `seatmix_sim.py`); the circuit in §4 is a proposal and has not
been built or simulated.

---

## 1. What the slot carries

| mode rate | pipe rate | bonded pair (§3) |
|---|---|---|
| 16 kbps | 16 kbps | 32 kbps |
| 32 kbps | 32 kbps | 64 kbps |
| 64 kbps | 64 kbps | 128 kbps |

The pipe is:

- **synchronous** — one data bit per frame, clocked by the frame clock: the TX
  card's frame clock for transmit, the RX card's recovered frame clock for
  receive. There is no elastic store and no slip, for the same reason there is
  none anywhere else (spec §1).
- **bit-transparent** — the carrier never inspects the data. Any pattern,
  including all zeros, all ones and periodic patterns, is carried without
  affecting framing (§2).
- **not octet-aligned** — the framer establishes bit alignment and slot
  identity, and nothing coarser. Equipment that needs octets or HDLC frames
  finds its own phase, as it would on any synchronous bearer.
- **not scrambled** — no scrambler is needed and none should be fitted (§2.3).

## 2. Framing rules for the card

### 2.1 Data on C only, A strapped high

```
   A bit ── tied to logic 1 ──────────────────→ TX card mux   (never carries data)
   C bit ── TXD, clocked by the TX frame clock ─→ TX card mux

   A bit ← from RX card demux ── ignored
   C bit ← from RX card demux ── RXD, clocked by the RX frame clock
```

These two rules are what make any combination of voice cards, data cards and
empty slots safe against false frame lock under the S4 header (spec §3). The
receiver can only be held at a wrong alignment by a pair of adjacent bits whose
first bit can stay 0 and whose second can follow `1110` indefinitely — and only
a data bit can do the second. With data confined to C, the bit in front of every
data bit is that card's own A, which is 1. The bit after it is the next slot's A,
which never carries data.

Enumerated over every combination of voice card, data card and empty slot:

| N | combinations | unsafe |
|---|---|---|
| 1 | 4 | 0 |
| 3 | 64 | 0 |
| 7 | 16 384 | 0 |

Simulated at N = 7 against constant 0, constant 1, `1110`, `0111`, `1010` and
random data, at both hook states: one data card in seat 1, one in seat 7, seven
data cards, and mixed voice / empty / data layouts — **0 false locks in every
case**.

### 2.2 What breaks if the rules are not followed

| card variant | false locks, N = 7, worst data | why |
|---|---|---|
| data on C, **A strapped low** | **14 / 16** | a data bit behind a static 0 can spell `1110` |
| **64 kbps on one slot** (data on A and C) | **2 / 16** | same, with the data in A behind the previous slot's C |

The second row is why the card is 1 bit per frame and higher rates come from
bonding (§3), not from putting data on A.

### 2.3 No scrambler

Earlier work proposed a self-synchronising scrambler for data slots
(`draft-protocols.md` §8.5). Under S4 with the §2.1 rules it is unnecessary, and
it is worse than unnecessary: a multiplicative scrambler must be seeded nonzero
or all-zero data passes straight through, and even seeded it locks up on about
2^-7 of all-zero idle onsets (measured 0.73%). Do not fit one.

## 3. Bonding two cards

Two data cards in slots *j* and *j*+1 form one pipe at twice the rate: C*j*
carries the even bits, C*j*+1 the odd bits, in every frame. Slot identity is
fixed by the framer, so the order is fixed forever:

- no marker, no multiframe, no alignment state
- measured bit-exact at all 8 start-up skews (32 kbps slots into a 64 kbps pipe,
  N = 3; `strap.py` §35 — run with the earlier framer, but bonding depends only
  on slot identity, which every framer provides)
- adjacent data cards are covered by the §2.1 enumeration

Bonding is a strap on the two cards (one is "even", one is "odd") and a short
link between them; the carrier does not know it is happening.

## 4. Circuit — proposal

Not designed. What the card needs, as a starting point:

| function | proposal |
|---|---|
| Transmit data in | RS-422 receiver (26LS32), TXD |
| Transmit clock out to the equipment | TX frame clock, RS-422 driver (26LS31) — the carrier is the clock source (DCE) |
| Receive data out | RXD, RS-422 driver |
| Receive clock out | RX frame clock, RS-422 driver |
| Retiming | one D flip-flop per direction onto the backplane frame clock |
| A bit | tied high |
| Mute / LOF | force RXD to 1 (mark idle) while the receiver is not locked |
| Bond strap | even / odd / none, and the pair link to the neighbour |

The equipment sees an ordinary synchronous DCE. The clock edges it must sample
on, and the setup margin against the backplane timing, are for the schematic.

## 5. Commissioning

**The same card type must sit in the same slot at both ends.** A voice card
facing a data card decodes the data stream as CVSD. That makes loud noise, and
squelch will not mute it because the framer is correctly locked. The voice
card's output clamp (spec §10.2) bounds the level, but only a correct
configuration fixes it. Label every slot with its card type at both ends.

A data card facing an **empty** slot receives the empty-slot fill (spec §8.3),
an alternating `1010`, which is harmless idle to synchronous data equipment.

## 6. Bring-up

1. **Loop TXD to RXD on the card** with the backplane frame clock running and no
   line. Confirms clocking and retiming.
2. **Over the backplane, card to card**, still no line.
3. **Over the link, all zeros, then all ones, then random data**, with the
   framer's lock indicator watched through a cold start. All three must lock at
   the true phase: this is the in-service check of §2.1.
