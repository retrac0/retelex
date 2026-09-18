# MF8 — a six-channel digital voice carrier in discrete logic

Six 64 kbps channels and a sub-commutated signalling channel in an 8-bit frame,
over one twisted pair, built in 74HC. A channel slot is a **DS0**: 64 kbps and
octet-aligned, so it takes a CVSD voice card, a synchronous data card, or a
G.711 PCM stream.

```
[ F ][ C1 ][ C2 ][ C3 ][ S ][ C4 ][ C5 ][ C6 ]      8 bits, 15.625 µs, 64 kHz
                                                     512 kbps, 1.024 MBaud
```

The superframe is 8 frames. It carries signalling (one bit per channel at
8 kHz), it carries the framing word, **and it is the octet counter** — so at a
64 kHz frame rate the superframe rate is 8 kHz, the PCM sample rate exactly, and
one superframe carries one sample.

## Documents

| | |
|---|---|
| [docs/mf8-spec.md](docs/mf8-spec.md) | **the specification** — frame, header, framer, cards, line code, circuits |
| [docs/line-codes.md](docs/line-codes.md) | nine line codes; differential Manchester against AMI, and the one question left open |
| [docs/frame-rate.md](docs/frame-rate.md) | what the frame rate should be: reach against quality, capacity and DS0 |
| [docs/subscriber-line.md](docs/subscriber-line.md) | the subscriber line: raw CVSD four-wire, hook and ring as held bit patterns, DTMF in band |
| [docs/mfspec.md](docs/mfspec.md) | the predecessor this design replaced the header of |

## Tools

| | |
|---|---|
| `mf8.py` | reference model and frame-layer battery — the F word, false locks, superframe phase, where S sits, slot rules over every byte in every seat, line errors, slip recovery |
| `mf8_line.py` | end to end: six independent talkers, real CVSD, a real waveform, both line codes |
| `linecodes.py` | the line itself — which code, how it fails, what the rate costs |
| `impulse_sweep.py` | the impulse falloff curve: 23 rates, both codes, error bars, thresholds |
| `mf8_render.py` | renders 15 s of every channel to `out/` under nine line conditions in both codes, for listening |
| `tolerance.py` | CVSD encoder/decoder component-mismatch tolerance |
| `audio.py` `cvsd.py` `phy.py` `fast.py` | shared: audio I/O and scoring, the CVSD codec, the physical layer, C-accelerated inner loops |
| `talkers.py` | builds the seven independent test talkers from LibriSpeech |

```
python3 mf8.py            frame layer          (mf8.log)
python3 mf8_line.py       over the line        (mf8_line.log)
python3 linecodes.py      line codes and rate  (linecodes.log)
python3 impulse_sweep.py  impulse falloff      (impulse_sweep.log, .csv)
python3 mf8_render.py     listenable renders   (mf8_render.log; wavs in out/)
```

`out/` is not committed. Each render is the full 15 s as the link delivers it —
muted wherever the framer was not locked, so outages are heard in place rather
than edited out. Files are `{dm,ami}_{condition}_ch{n}.wav`, with
`source_ch{n}.wav` as the reference.

The `.log` files beside each are the committed runs. Every table in the
documents is reproducible from them.

## Test audio

`talker1.wav` … `talker7.wav` are seven independent LibriSpeech dev-clean
speakers, 30 s each, and are **not committed** — they are extracts from
third-party material. Rebuild them with `python3 talkers.py --root <dev-clean>`.
`phy_fast.c` builds to `libphyfast.so`; see the header of `fast.py`.

## What is settled and what is not

Settled: the frame, the header, the framer, and that the carrier is transparent —
six talkers through the whole chain in both line codes add **+0.00 dB**.

Not settled, and not settleable here: **the impulse rate on the target loops.**
The curve is measured (`impulse_sweep.py`, `docs/line-codes.md` §4.5): each
impulse costs differential Manchester about 0.77 breaks and AMI about 0.13, so
differential Manchester reaches one click a second at 1.3 impulses/s and AMI at
7.3. AMI holds that advantage until it collapses outright between 800 and 900
impulses/s. Which matters depends on the loop, and that is a counter on a real
pair.
