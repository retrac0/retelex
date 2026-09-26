# MF8 Pico adapter — gateway, reference terminal and test instrument

A Raspberry Pi Pico on a small 74-series adapter board that can sit on either
side of every interface in the shelf. In one role it is the host gateway that
puts MF8 channels on an Asterisk exchange. In the others it is what
the codec's breadboard needs and the shelf never had: a trunk card
for a channel card with no trunk, six channel cards for a trunk card with no
cards, and a known-good far end for a line — all driven from the same reference
model as `mf8.py`, so the model becomes an instrument.

> **Status: proposed; no firmware exists.** Measured: how coarse a timing grid
> the §9.4 classifier tolerates (§5), which sizes the PIO receiver. Everything
> about the Pico itself — PIO timing, clock dividers, pin tolerance, USB — is
> from the RP2040 data sheet as remembered and is to be checked against it
> before a board is laid out.

---

## 1. Roles

| | role | the Pico stands in for | it faces | used for |
|---|---|---|---|---|
| **G** | gateway | any subset of the six channel cards | the backplane's gateway slot (§3) | Asterisk, or any host: CVSD octets and A bits over USB (§7) |
| **M** | monitor | nothing — it listens | the gateway slot | a protocol analyser on all 24 per-slot lines, with a shelf in service |
| **T** | trunk emulator | the trunk card | one channel card, or a CVSD engine on a breadboard | bring-up with no trunk: clocks, `C` and `A` each way, `MUTE`, a programmable ppm offset between the two clock domains |
| **C** | channel emulator | six channel cards | a trunk card | the `mf8.py` battery on hardware: every payload class, every byte in every seat, every hook state |
| **L** | line terminal | a whole MF8 terminal | a trunk pair, through the trunk card's line interface | a far end built from the reference model: framer, slips, injected errors |
| **S** | subscriber emulator | a CVSD phone, or a line card | a subscriber line's two pairs, through the same line interface | hook, ring, dial pulses and the held patterns of `subscriber-line.md` |

One adapter, one firmware image, the role chosen from the host. Roles G, M, T
and C use the adapter's shift-register port (§2.2); L and S use its line port
(§2.3); both can run at once, which makes the adapter **a software trunk
card**: line port to a pair, shift-register port to real channel cards.

---

## 2. The adapter board

### 2.1 Principle

**PIO state machines touch every edge; software only moves buffers.** A PIO
program is cycle-exact and waits on a pin, so each of the two clock domains of
`mf8-backplane.md` §2 gets its own state machine clocked by its own bus clock.
That is what the Pi's I2S port could not do — one bit clock for both
directions — and it means the adapter needs no retiming and adds no slip.
Nothing on a 125 µs or a 15.6 µs deadline is ever in a C function.

**The Pico can make MF8's clocks itself, exactly — at a 128 MHz system
clock.** At the SDK's default 125 MHz the PIO divider a 512 kbps line wants,
15.2588, does not fit the divider's eight fractional bits, and the nearest is
+64 ppm. That would not matter: 64 ppm is one CVSD slip per 244 ms at a
line-card crossing, measured at 34.3 dB against the clean decode, and 200 ppm —
the worst case against a ±100 ppm far end — is 33.0 dB, above the codec's own
25.4 (`mf8-backplane.md` §7). But it is avoidable. From the standard 12 MHz
crystal a 1 536 MHz VCO over 12 is 128 MHz, the dividers for 64, 512 and
1 024 kbps become 125, 15.625 and 7.8125, all exact, and USB is untouched
because it has a PLL of its own. What remains is the Pico crystal's tolerance,
the same class as a 4.096 MHz can. The fractional divider dithers between two
integer lengths, so a generated clock carries 7.8 ns of bounded jitter, 0.4 %
of a 512 kbps cell against the receiver's ±13 %.

So the adapter's own 4.096 MHz oscillator and '4040 chain are **optional**: fit
them where a role should be clocked exactly as a trunk card is, with the same
parts and the same jitter, and leave them off otherwise. A clock state machine
drives the clock pins the other state machines wait on, so the programs are the
same either way. What the PIO divider cannot do is a *small* programmed offset:
its step at 15.625 is 250 ppm. A second domain ±100 ppm away needs a second
oscillator, or a clock state machine fed its period words by DMA, which gives
any average rate at the same 7.8 ns of jitter.

### 2.2 The shift-register port

| block | parts | does |
|---|---|---|
| Capture, 32 bits | 4 × SN74LV165A at 3.3 V | parallel-in from the bus — the LV-A family's inputs take 5 V at a 3.3 V supply, so the capture register **is** the level shifter. Loaded by a PIO-timed pulse ~50 ns after the domain's clock edge, against a data-valid window of 1.6 µs (`mf8-backplane.md` §5); shifted out to the Pico at ~10 MHz |
| Drive, 16 bits | 2 × 74HCT595 at 5 V | serial-in from the Pico — HCT thresholds accept 3.3 V — and **the output latch clock is the bus clock itself**, so the outputs change on the clock edge in hardware, exactly as `mf8-backplane.md` §3 requires of a card |
| Per-line enable | 4 × 74HCT125, enables from a third '595 | any driven line can be released. Default at power-up: everything released — role M |
| Clock source, optional | 4.096 MHz oscillator, 74HC4040, 74HC393 | `TX_CLK`, `LOOP_HB`, `TX_OCT`, `FILL` for roles T, C and L, made as a trunk card makes them. Unfitted, the `clk` state machine makes them (§2.1). A second oscillator, or `clk` fed period words by DMA, puts a second domain a known number of ppm away |
| Clocks in | ¼ SN74LV165A-class buffer | `TX_CLK`, `TX_OCT`, `RX_CLK`, `RX_OCT` to four Pico pins |

Per 15.6 µs frame the Pico shifts 32 bits in and 16 out, 5 µs of a 10 MHz
shift clock, entirely in PIO and DMA. About ten Pico pins. A **personality
cable** maps the 32 inputs and 16 outputs onto the connector a role faces:

| role | the 16 outputs drive | the 32 inputs read |
|---|---|---|
| G, M | `C_TX[1..6]`, `A_TX[1..6]` (G only, per-slot enabled) | `C_RX[1..6]`, `A_RX[1..6]`, `C_TX[1..6]`, `A_TX[1..6]`, `MUTE`, `LOCK`, `CD` |
| T | one slot's `C_RX`, `A_RX`, `MUTE`, plus the clocks from the adapter's chain | that slot's `C_TX`, `A_TX`; spare inputs on card test points |
| C | the trunk-card slot's `C_TX[1..6]`, `A_TX[1..6]` | its `C_RX[1..6]`, `A_RX[1..6]`, `MUTE`, `LOCK`, `CD` |

### 2.3 The line port

The trunk card's analog section and nothing else: 75176, transformer, the §9.5
filter, the comparator, the §9.7 rate plug. Its comparator output goes to one
Pico pin through the LV buffer; its driver input comes from one Pico pin through
an HCT gate. The encoder state machine is **clocked by `LINE_HB`** — from the
adapter's chain or from `clk` — so the line rate is exact; the receiver state
machine runs at the full system clock and times intervals, as §9.4's hardware
does.

### 2.4 Pico or Pico 2

Either fits the footprint. The Pico 2 (RP2350) is the better fit: a
floating-point core, so the CVSD model runs on the adapter and roles T and S
can generate and score audio with no host; twelve PIO state machines instead
of eight; and inputs that tolerate 5 V — which removes nothing from the board,
because the '165s are still needed as capture registers and 3.3 V outputs are
still not a valid high for 5 V 74HC.

---

## 3. The gateway slot

A seventh bus position carrying what the trunk-card slot carries, mirrored: all
six `C_TX[n]`, `A_TX[n]`, `C_RX[n]`, `A_RX[n]`, the four clocks, `MUTE`, `LOCK`
and `CD`, on the trunk slot's 2 × 32 pinout. No new bus signal is needed — the
shift registers work between the existing clock edges.

**Drive rule.** The gateway may drive `C_TX[n]` and `A_TX[n]` only for a slot
that holds no card. The 4.7 kΩ `FILL` and pull-down network of
`mf8-backplane.md` §6 stays, and an enabled gateway output overrides it exactly
as a fitted card does; a fitted card and an enabled gateway output on the same
slot fight. The firmware powers up with every output released, a slot is
enabled from the host, and **a mixed shelf is the normal case**: real cards in
some slots, Asterisk extensions in the rest, and role M on all of them.

The power supply moves off slot 7, to the end of the backplane.

---

## 4. Firmware

| state machine | domain | does |
|---|---|---|
| `cap_r` | R — waits on `RX_CLK` | pulses the R-side '165 load, shifts 16 bits in, pushes one word per frame to DMA |
| `cap_t` | T — waits on `TX_CLK` | the same for the T-side monitor inputs |
| `drv_t` | T — waits on `TX_CLK` | pulls one word per frame from DMA and shifts it into the '595s before the next edge latches it |
| `dm_tx` | T — waits on `LINE_HB` | differential Manchester encoder: `mf8-spec.md` §9.2's truth table, one bit per two `LINE_HB` edges; pico-examples' `differential_manchester` is the starting point |
| `dm_rx` | free-running, full system clock | the §9.4 interval classifier — dead time, 0.75-cell threshold, the `MID` pairing that self-heals — emitting bits with no clock, as `fast.mono_decode` does; **not** the fixed-delay sampler of the pico-examples receiver, which has no dead time |
| `clk` | the source of T, or of an offset R | `LINE_HB`, `TX_CLK`, `TX_OCT` and `FILL` on pins, from the 128 MHz system clock at an exact divider; or one period word per cycle from DMA, for a programmed ppm offset |
| `cfg` | — | the enable and configuration '595 |

Core 0: USB and the host protocol. Core 1: the role — the framer of
`mf8.framer` in C for L, pattern sources and comparators for T and C, the CVSD
model on a Pico 2. Between PIO and cores, DMA ring buffers only.

**Host protocol.** One USB packet per millisecond each way: eight superframes
of six `C` octets, one octet of `A` bits and one of status — 64 bytes. A Python
module presents the streams as the numpy arrays `mf8.py`, `cvsd.py` and
`audio.py` already use, so a repository tool runs against hardware by changing
where its bits come from. Interval capture (§6) is burst mode: timestamps to
RAM, then upload.

---

## 5. Measured: the receiver's timing grid

A PIO receiver sees the comparator only on its own clock edges, asynchronous to
the line. `mf8_line.py`'s chain with the sliced waveform re-sampled onto a
coarser grid — +200 ppm and an arbitrary phase from the line — then the same
classifier, framer and scoring; six talkers, 1 s, Gaussian noise. The reference
is the simulation's own 32 samples per cell.

| timing grid, counts per cell | sd 0.6: LOF, max BER | sd 0.7: LOF, max BER | |
|---|---|---|---|
| reference, 64 (the simulation's own) | 0, 0 — 1.6e−5, 1.6e−5 | 4, 3 — 3.3e−4, 4.9e−4 | two seeds each |
| **61.0** | 0, 0 — 1.6e−5, 1.6e−5 | 3, 2 — 3.6e−4, 2.6e−4 | the reference, to seed spread |
| **30.5** | 0, 0 — 1.6e−5, 1.6e−5 | 3, 0 — 3.3e−4, 1.6e−4 | the reference |
| **15.3** | 0, 0 — 1.6e−5, 1.6e−5 | 4, 1 — 3.6e−4, 3.1e−4 | the reference |
| 12.2 | **1**, 0 — 3.2e−4, 1.6e−5 | **21, 17** — 1.1e−3, unscored | clearly worse, both seeds; the second's longest locked run would not align for scoring |
| 8, exactly | 0 — 4.7e−5 | 0 — 3.4e−4 | fine — and misleading |
| 6, exactly | 1 — 2.2e−4 | 10 — 6.5e−4 | marginal |
| 4, exactly | 407 | 407 | collapses; clean line still perfect |

On a clean line every grid decodes without error, down to 4 counts per cell, so
a bench test on a short pair proves nothing about this. Under noise the floor
is **about 15 counts per cell at an arbitrary phase**: 15.3, 30.5 and 61 are the
reference to the digit at sd 0.6 and within seed spread at sd 0.7, and 12.2 is
not. The integer grids are a trap. A grid at exactly 8 per cell is nearly
synchronous with the line, its quantization error is almost the same from one
interval to the next, and it scores better than 12.2; a real PIO clock is never
an integer multiple of the line rate, every interval then carries an
independent ±1 count, and at 12 per cell that is ±8 % of a cell out of the
classifier's ±13 %.

**So `dm_rx` runs at the full system clock.** A PIO counting loop costs two
instructions a count, 15.6 ns at 128 MHz: 125 counts per cell at 512 kbps, 62 at
the family's 1 024 kbps, 500 on the subscriber line's 128 kBaud — four times the
floor at the worst rate. One second per cell, two seeds, and a re-sampling of a
waveform the simulation had already sampled at 64 per cell with the noise
density held; scratch script, not a repository tool.

---

## 6. What it checks on the breadboard

The four findings of the retired `circuit-review.md` (`exchange/decisions.md`),
now in `channel-cards.md` §2.4, `cvsd-codec.md` §3 and `falstad/README.md`, as
measurements this adapter makes, with the breadboard's other open items:

| finding | role | measurement |
|---|---|---|
| the encoder flip-flop (`channel-cards.md` §2.4) | L | decode the breadboard encoder's line with `dm_rx`, and histogram its intervals at 16 ns resolution: a '109 wired as a D flip-flop sends `EN` delayed, which is not differential Manchester at all and shows as intervals off the half-cell and full-cell peaks |
| `Iabc`, and `I_min` to ±5 % (`cvsd-codec.md` §3.1) | T | feed the encoder audio at nominal and at −20 dB, capture `C_TX`, decode with the model: a level-dependent gain is `I_min`. Then the converse — play model-encoded bits into the decoder. This is `tolerance.py` with one real card in the pair, and it is how two independently built cards get compared before there are two |
| sample, then retrigger (`falstad/README.md`'s two-phase timing) | L + M | the hardware classifier and `dm_rx` decode the same comparator output; any bit they disagree on, on a clean line, is a timing fault in the hardware. The interval histogram reads the 0.2-cell and 0.55-cell timers directly against the ±13 % budget |
| the sign of the OTA drive (`cvsd-codec.md` §3.2) | T | an encoder in positive feedback sits on a rail and sends a constant; a decoder that merely inverts passes a listening test and fails a correlation against the model |
| `mf8-backplane.md` §9 — the bus margins | M | capture `C_TX[6]` and `C_RX[6]` every frame at the fastest rate and compare with what was sent |
| the synchronizer crossings | T | run the R domain a programmed ±100 ppm from T and count slips at the line card's crossings: one per 156 ms and nothing else |
| `mf8.py`'s battery | C + L | every byte in every seat, every hook state, against a real framer; `LOCK` is the verdict |
| `channel-cards.md` §5 — the A path | T | dial pulses and ring cadence into `A_RX`, timed at the card's E lead or relay driver |

The Pico's own ADC and a PWM output are a convenience for a first look at an
engine — 12 bits in, 8–10 out — not metrology; codec scoring wants the host's
sound card on the analog side and the adapter on the bits.

---

## 7. The gateway to Asterisk

Role G, a host and a daemon:

```
 backplane ⇄ adapter ⇄ USB ⇄ daemon: CVSD ⇄ linear, 64 kHz ⇄ 8 kHz ⇄ SIP or AudioSocket ⇄ Asterisk
```

The adapter stays a bit pump: CVSD octets and A bits, no codec, so the phones
are CVSD end to end and the one conversion to linear PCM happens once, in
floating point, from the same model the cards are measured against. `A_RX[n]`
rising is an incoming seizure or an answer; the daemon sets `A_TX[n]` in the
ring cadence to ring an MF8 phone; dial pulses arrive as `channel-cards.md` §5
measured them, and DTMF in band. MF8's crystal paces the packets leaving; a
jitter buffer with an occasional dropped or repeated 8 kHz sample absorbs
Asterisk's clock on the way in, before the CVSD encoder, where it is inaudible.
Against `channel-cards.md`'s FXO-to-analog-port arrangement this is one conversion
instead of two, one card instead of six, and no analog ports at all.

---

## 8. Not measured, not built

- **The Pico.** No firmware exists. PIO reaction time, the '165 load pulse,
  the '595 timing and the fractional-divider figures are from the data sheet as
  remembered.
- **`dm_rx` in 32 instructions.** The classifier's dead time, threshold and
  `MID` state have to fit one PIO program; it has not been written.
- **The capture load pulse** sits ~50 ns after a bus clock edge by PIO timing,
  not by a hardware edge. A '574 ahead of the '165s makes it a true
  edge-triggered capture for two packages more, if the first board shows it
  matters.
- **USB latency** to the host, and the daemon's jitter buffer, under a loaded
  Linux machine.
- **The gateway slot** with a mixed shelf: the drive rule is by firmware, and
  nothing in hardware stops an enabled output fighting a fitted card.
