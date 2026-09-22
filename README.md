# Retelex

Retro telephone exchange.  Also retro telex exchange.  

# MF8 — a six-channel digital voice carrier in discrete logic

Six 64 kbps channels and a sub-commutated signalling channel in an 8-bit frame,
over one twisted pair, built in 74HC. A channel slot is equivalent to  **DS0**: 64 kbps
and octet-aligned.  

Works with a CVSD voice card (the normal Retelex protocol), a synchronous data card, or a
G.711 PCM stream.

```
[ F ][ C1 ][ C2 ][ C3 ][ S ][ C4 ][ C5 ][ C6 ]      8 bits, 15.625 µs, 64 kHz
                                                    512 kbps, 1.024 MBaud
```

The superframe is a sequence of 8 frames. It carries signalling (one bit per channel at
8 kHz), it carries the framing word, **and it is the octet counter**, so at a
64 kHz frame rate, the superframe rate is 8 kHz, the PCM sample rate exactly, and
one superframe carries one sample.  

But we don't use PCM in practice.  Though byte-boundary support does exist.

# Exchange

Sixty-four line exchange.  Supports MF8 trunks between exchanges.

Up to 48 subscriber lines.  0x and 1x are reserved for trunk and supervisor features.

Anywhere from 1 to 64 lines can be trunks.  Each exchange supports connections
up to four different exchanges, in any number of lines.  For example,
MF8 can be doubled so an exchange has 12 lines tying it to its neighbour.  This 
could be done on two fronts for a total of 24 tie lines.

The directions are labelled after the compass points NSEW but this is purely
notional.

Digital switching, CVSD or data.

Pulse flood protocol.  Sending exchange calls all outward directions which is
passed on by all exchanges until dropped or accepted.  Preliminary traffic
simulation suggests this scales to about a thousand lines across a few dozen
exchanges.

General purpose architecture.  Chains, stars and rings are possible.

## Layout

```
common/     the cards, and everything that belongs to neither shelf
mf8/        the MF8 carrier: frame, line, backplane
exchange/   the exchange
verilog/    the exchange in Verilog: rtl/, tb/, Makefile
sim/        every model, and the committed run beside each
falstad/    the voice path as Falstad circuits
```

A card plugs into an MF8 shelf or an exchange block unchanged, so its
specification belongs to neither: `common/` is that, and it is why the split
exists. Run the models from the repo root — `python3 sim/mf8.py`.

## Documents

**common/** — the cards, the socket they share, and the line to the telephone

| | |
|---|---|
| [common/channel-cards.md](common/channel-cards.md) | the channel cards: the CVSD subscriber line card, the analog FXS/FXO card, the data card; each card's pins; signalling through the A bit, measured |
| [common/common-cards.md](common/common-cards.md) | the common card set: four cards that plug into an MF8 shelf or an exchange block unchanged — one socket with a column per card, what a card says about itself, the FXO's one strap, and the connectors |
| [common/clocks.md](common/clocks.md) | every clock in MF8 and in the exchange: one 4.096 MHz crystal, nine taps, three domains, and where a card's 128 kHz comes from |
| [common/subscriber-line.md](common/subscriber-line.md) | the subscriber line: raw CVSD four-wire, hook and ring as held bit patterns, DTMF in band |
| [common/su-1.md](common/su-1.md) | SU-1 mk1 subscriber unit: native CVSD set, 4P4C handset, Autovon pad → dial pulses, two-board stack |
| [common/sdu-1.md](common/sdu-1.md) | SDU-1 mk1 subscriber data unit: 32 kb/s insert-1 riser on SU-D; voice unit keeps the line code and `1100` |
| [common/subscriber-adapter.md](common/subscriber-adapter.md) | a stock dial telephone on that line: where the 2-wire conversion sits — in the exchange, at the subscriber, or at a shared site — and the adapter that puts it at the subscriber, its parts, its ringing and its power budget |
| [common/tone-plan.md](common/tone-plan.md) | the tone plan: four tones in two timbres — the Australian warble for *progressing*, the old Bell buzz for *stop* — why a warble is one oscillator and not three, eight ROM planes as two switchable standards, and the analog card beside it |
| [common/tone-card.md](common/tone-card.md) | the tone card: one generator holding a whole shelf on fast busy — a plain 2 × 16 channel card, the backplane strap field that lets one slot feed the others, and the only card in the set that drives and never listens |
| [common/circuit-review.md](common/circuit-review.md) | four circuit findings ahead of the breadboard: the encoder flip-flop, the `Iabc` drive, sample-then-retrigger, the logic-to-engine connections |

**mf8/** — the carrier

| | |
|---|---|
| [mf8/mf8-spec.md](mf8/mf8-spec.md) | MF8 specification — frame, header, framer, cards, line code, circuits |
| [mf8/mf8-backplane.md](mf8/mf8-backplane.md) | remote MF8 unit backplane — modules, slot interface, three clock domains and where they meet, and the measured cost of the plesiochronous slip |
| [mf8/mf8-psu.md](mf8/mf8-psu.md) | MF8 shelf power: 15–18 V in, regulated −48 V talk battery and ~80 Vrms / 20 Hz ring as two converter paths, split across noisy and quiet 100 × 100 end boards |
| [mf8/mf8-trunk.md](mf8/mf8-trunk.md) | MF8 trunk split: Trunk-D / Trunk-A on 100 × 100, classifier on A, pass-header pinout |
| [mf8/mf8-pico.md](mf8/mf8-pico.md) | the Pico adapter: host gateway to Asterisk, trunk and channel emulator, reference line terminal — the model as an instrument for the breadboard; the receiver's timing grid, measured |
| [mf8/line-codes.md](mf8/line-codes.md) | nine line codes explored; differential Manchester against AMI |
| [mf8/frame-rate.md](mf8/frame-rate.md) | what the frame rate should be: reach against quality, capacity and DS0 |
| [mf8/mfspec.md](mf8/mfspec.md) | the predecessor this design replaced the header of |

**exchange/**, **verilog/**, **falstad/**

| | |
|---|---|
| [exchange/](exchange/README.md) | **the exchange**: 64 line expandable exchange using the pulse flood protocol. Documents in [exchange/](exchange/) |
| [exchange/register.md](exchange/register.md) | the register: dial pulses read into a digit store in 74HC, one register for every line, pulse correction and the dialling technique, measured end to end |
| [verilog/](verilog/README.md) | the exchange as a register-transfer model: `rtl/`, `tb/` and the benches the Makefile runs |
| [falstad/](falstad/README.md) | the voice path as Falstad circuits built from subcircuit modules: CVSD encoder, differential Manchester, a line with noise and impulses, the receiver and its recovered clock, the decoder; what to try, and how each matches the model |

## Tools

| | |
|---|---|
| `mf8.py` | reference model and frame-layer battery — the F word, false locks, superframe phase, where S sits, slot rules over every byte in every seat, line errors, slip recovery |
| `mf8_line.py` | end to end: six independent talkers, real CVSD, a real waveform, both line codes |
| `linecodes.py` | the line itself — which code, how it fails, what the rate costs |
| `impulse_sweep.py` | the impulse falloff curve: 23 rates, both codes, error bars, thresholds |
| `mf8_render.py` | renders 15 s of every channel to `sim/out/` under nine line conditions in both codes, for listening |
| `subline.py` | the subscriber line: CVSD against the held patterns, the hook and ring detectors, dial pulses as the line card sees them, the register end to end, DTMF through the codec |
| `cvsd_law.py` | the codec law: MIL-STD-188-113 read from the standard's own test patterns, against the previous law, whether it is bit-rate specific, and a DNVT on a 64 kbps channel |
| `tolerance.py` | CVSD encoder/decoder component-mismatch tolerance at 64 kbps, `I_min` included |
| `falstad_cvsd.py` | builds the Falstad (CircuitJS) modules and the three circuits in `falstad/` from the codec law and the line constants; and `check`, which compares a Falstad run with `cvsd.py` and `fast.mono_decode` |
| `falstad/sim.mjs` | runs a circuit in falstad.com's simulator in headless Chromium and records every labeled node, for that check |
| `audio.py` `cvsd.py` `phy.py` `fast.py` | shared: audio I/O and scoring, the CVSD codec, the physical layer, C-accelerated inner loops |
| `talkers.py` | builds the seven independent test talkers from LibriSpeech |
| `tones.py` | call-progress tones as looped CVSD: the shortest seamless loop, what ROM depth buys, eight tone plans compared, five ways to make a warble, and the cadence as a binary divide. Renders the plan to `sim/out/` |
| `exch.py` | the exchange: the fabric cell by cell, calls a millisecond at a time, the flood across a network, traffic. `exchange/README.md` lists its twenty runs |

```
python3 sim/mf8.py            frame layer          (mf8.log)
python3 sim/mf8_line.py       over the line        (mf8_line.log)
python3 sim/linecodes.py      line codes and rate  (linecodes.log)
python3 sim/impulse_sweep.py  impulse falloff      (impulse_sweep.log, .csv)
python3 sim/mf8_render.py     listenable renders   (mf8_render.log; wavs in out/)
python3 sim/subline.py        subscriber line      (subline.log)
python3 sim/cvsd_law.py       the codec law        (cvsd_law.log)
python3 sim/tolerance.py      codec tolerances     (tolerance.log)
python3 sim/tones.py          call-progress tones   (tones.log; wavs in sim/out/)
python3 sim/falstad_cvsd.py   Falstad prototypes   (falstad_cvsd.log; falstad/*.txt)
```

`sim/out/` is not committed. Each render is the full 15 s as the link delivers it —
muted wherever the framer was not locked, so outages are heard in place rather
than edited out. Files are `{dm,ami}_{condition}_ch{n}.wav`, with
`source_ch{n}.wav` as the reference.

The `.log` files beside each in `sim/` are the committed runs. Every table in
the documents is reproducible from them.

## Test audio

`sim/talker1.wav` … `sim/talker7.wav` are seven independent LibriSpeech dev-clean
speakers, 30 s each, and are **not committed** — they are extracts from
third-party material. Rebuild them with `python3 sim/talkers.py --root <dev-clean>`.
`sim/phy_fast.c` builds to `sim/libphyfast.so`; see the header of `fast.py`.

## What is settled and what is not

Settled: the frame, the header, the framer, and that the carrier is transparent —
six talkers through the whole chain in both line codes add **+0.00 dB**.

Not settled, and not settleable here: **the impulse rate on the target loops.**
The curve is measured (`impulse_sweep.py`, `mf8/line-codes.md` §4.5): each
impulse costs differential Manchester about 0.77 breaks and AMI about 0.14, so
differential Manchester reaches one click a second at 1.3 impulses/s and AMI at
about 8. AMI holds that advantage until it collapses outright between 800 and 900
impulses/s. Which matters depends on the loop, and that is a counter on a real
pair.

## Todo

* Hook flash - put the call on hold!  Implemented probably in the subscriber card
  When on hold the keypad could become available 
