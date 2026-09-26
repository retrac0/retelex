# STU-1 — the subscriber line test set

STU-1 is a lineman's set that clips onto one CVSD subscriber line, both pairs at
once, and names the fault instead of showing a waveform. Two `mf8/mf8-spec.md`
§9.4 front ends, one a direction, feed a lamp field read as (downstream
× upstream), with LEVEL and PHANTOM meters and a violation counter; SU-1's SU-A
lets it answer, talk and dial.

> **Proposed.** Nothing drawn, nothing on a bench; the bridge, the power budget
> and the package count are arithmetic. Measured in: `subscriber-line.md` §3,
> `sim/subline.log`, for every detector and threshold the set reads.

## 1. What it is

It clips onto one line with four clips, plus the two line-side centre taps for
PHANTOM; it receives on two §9.4 front ends at the §9.7 64 kbps plug, each with
`subscriber-line.md` §3's violation term; it transmits only through the **ST-B**
break adapter, which opens the pair; it reads out on 22 lamps, LEVEL (0–2 V, by
direction), PHANTOM (0–60 V) and a log2 violation bar.

**Two front ends, because a fault is named by what both pairs do**: downstream
alive and upstream dead is a starved or dead phone; both dark with phantom volts
present is a broken signal path on a whole DC path.

## 2. What it may put on a pair

- **No sustained zeros, ever**: zeros ring the subscriber (`subscriber-line.md`
  §2). The transmit mux has three inputs, ÷2 (`1010`), ÷4 (`1100`) and
  `BIT_ENC`; **the set has no hold node anywhere**, and a revision must not add
  one.
- **The transmit interlock is mechanical.** The TALK driver's supply comes
  through a link inside ST-B's shell, and the MODE wafer air-gaps its enable in
  every listening position, so a dead or browned-out set is open toward the
  line.
- **Bridge or terminate.** The 100–135 Ω termination is on its own wafer pole,
  OUT in WATCH, IN in TERM, with a TERM-IN lamp. The transformers are §9.3's
  78615/9C. Bridged, the set's magnetizing inductance sits across the far
  receiver's: two 10 mH parts give 5 mH, L/R 3.2 cells at 100 Ω against §9.3's
  2.5, and the ~1.2 kΩ tap costs a few tenths of a dB. WATCH is sound where the
  span delivers ≥ 0.5 V to the comparator (§9.3); a pair at full reach may not.

## 3. Boards and headers

| board | holds | pkgs |
|---|---|---|
| **ST-P**, top | three switchers, 22 lamps, both meters, battery-low | 4 |
| **ST-K** | the dialler, 16 SMD keys (§7) | 11 |
| **ST-L** | detectors, lamp decode, TX mux and §9.2 encoder, dividers, counter, squelch, lamp buffers; presents S | 18 |
| **ST-D**, bottom | transformers, protection on four conductors, both front ends and rate plugs, LEVEL peaks | 15 |
| **ST-A**, on S | `su-1.md`'s SU-A and one mic gain stage | 13 + 2 |

All 100 × 100 mm at 0.4″: a ≈ 42 mm stack of ≈ 61 packages behind a
≈ 140 × 110 mm panel, a two-hand set. The front ends sit with the magnetics so
the rate plug is never split across a connector; the switchers sit at the far
end from the ~50 mV comparator.

**Header T** is a keyed 2×16 bussed through ST-D, ST-L, ST-K and ST-P; from ST-L
every pin is an input but `TX_LINE`, `/TX_EN` and `TICK`. Pins
1, 2, 6, 11, 16, 20, 32 `GND`; 3 `+5 V`, 4 `+12 V`, 5 `−12 V`; 7–10 `DN_Q`,
`DN_STB`, `DN_VIOL`, `/DN_CD`; 12–15 the same for UP; 17 `DN_HB`, 128 kHz (§6);
18 `TX_LINE` to the 75176; 19 `/TX_EN`; 21, 22 `DN_LEVEL`, `UP_LEVEL` and 24
`PHANTOM`, analog, returned on 23; 25–27 `MODE[2:0]`; 28 `DIR` (1 = up); 29
`TERM`; 30 `TICK`, 1 kHz; 31 `BREAK` from ST-K.

**Header L** (2×13) carries 22 lamp lines and four grounds to ST-P. **Header S**
is `su-1.md` §6 pin for pin, presented by ST-L; ST-A is its third population.

## 4. ST-D — the two front ends

Per direction: gas tube, PTC and TVS on each conductor, a 78615/9C with its
centre tap to PHANTOM, the termination on the wafer, two §9.5 RC sections with
½ TL072 between them, then the 75176 receiver and §9.4 classifier; a second
½ TL072 peak-detects the comparator input for LEVEL. Three '123 halves: carrier
2 cells (31.3 µs), gap 1.25 cells (19.5 µs), hold 16 cells (250 µs).

- **The §9.5 filter is buffered**: unbuffered, R2 = 10·R1 into the 75176's 12 kΩ
  costs ~5 dB at the slicer. For other front ends: `channel-cards.md` §6.
- **The gap timer is trimmed at or above 19.5 µs, never below**: a valid 1 bit's
  gap is a full cell, 15.6 µs. +5 V is held tight: '123 widths track Vcc.
- **The rate plug also picks ST-L's `TICK` and `LINE` taps**, and shows its rate
  through a window, so the panel states the rate the set is set to.

## 5. ST-L — detectors and lamps

`subscriber-line.md` §3's detector in both senses on both directions, and a
SPEECH comparator each way: six LM339 quarters. **Each RC node and its
references are divided 2:1** before the LM339, whose common-mode range on +5 V
ends at 3.5 V, below 0.85 × 5 V (for other detectors: `channel-cards.md` §6).

| lamp | lit by | means |
|---|---|---|
| `CARRIER` ×2 | `/xx_CD` | transitions present, straight off the cells |
| `1100` ×2 | the exchange sense | on-hook or a break; legal upstream only |
| `ZEROS` ×2 | the phone sense | ringing now; legal downstream only |
| `SPEECH` ×2 | xor2 density > ≈ 0.05, ~0.5 s peak hold | real traffic |
| `LOW` ×2 | LEVEL < 0.5 V | near §9.3's hysteresis floor |
| `SWAPPED` | `1100` down or `ZEROS` up, ANDed with that column's carrier | clips on the wrong pairs |
| `TERM-IN`, `BATT`, `LINE`, bar ×8 | wafer; cells < ≈ 5.1 V; §6; the counter | |

**Idle and a silent talker are the same bits** — a quiet encoder emits exactly
`1010` (`subline.log`) — so there is no IDLE lamp. SPEECH separates traffic from
idle: xor2 mean 0.14 against 0.00 clean, 0.15 against 0.01 at 100 impulses/s.

Two chained '4040s on the strobe give `1010` (Q0), `1100` (Q1) and the timebase
of §6; a third counts violations. The ear is gated by a '4066 on /carrier +
violation-hold + a mode-change one-shot, behind a two-diode limiter against a
dead pair's +24.1 dB rms (`mf8-spec.md` §13): logic fails silent, a limiter does
not. A '157 puts either direction's `BIT_DEC` and `RX_CLK` on S.

## 6. Clocking

The 64 kHz downstream strobe is the set's timebase: `RX_CLK` on S, ÷ 64 `TICK`,
÷ 65 536 the 0.98 Hz `LINE` lamp, which is the stopwatch. In TALK it is
loop-timed as the phone is (`subscriber-line.md` §1): `TX_CLK` and the §9.2
encoder's 128 kHz half-bit, `DN_HB`, follow the downstream, by the phone's
circuit, still open (`subscriber-line.md` §7). On a dead pair only both
`CARRIER`s, both LEVELs, PHANTOM and `BATT` work, and they name §10's first four
rows.

## 7. Transmit and the dial

`TX_LINE` is the §9.2 encoder behind a '157: ÷4 `1100` on-hook and in each
break, ÷2 `1010` while muted and on the make under a dial, `BIT_ENC` off-hook.
ST-K is `exchange/proposed/pulse-gen.md` §5's sequencer on `TICK` from ST-L,
keeping the RC astable and `SRC` mux so a tester can walk the register's windows
(`register.md` §1). **The dial mute is fitted**, so each break arrives 6.1 ms
short (`subscriber-line.md` §5); the correction monostable is not.

## 8. Power

Four AA (6.0 → 4.8 V) into a +5 V boost, a +12 V boost and a −12 V inverter at
80 %; ST-A's ±12 V is off while listening. +5 V worst case is 148 mA (receivers
40, HC 63, lamps 42, LM339s 3); ±12 V is 130 mW for ST-D and ≈ 300 mW for ST-A.
From the cells: 0.93 W listening, 1.46 W worst — nine hours watching, six
talking. **The phantom is read, never taken**: 10 MΩ across the centre taps,
marked in volts only.

## 9. The MODE wafer

| position | connects | does | intrusion |
|---|---|---|---|
| **WATCH** | both pairs, beside the phone | both columns and LEVELs; ear on the DIRECTION wafer through the squelch | bridging, termination OUT |
| **TERM** | one pair, phone out or pair dead | termination IN; the only position where LEVEL means what §9.3 says | terminating; detented, TERM-IN lit |
| **TALK** | both pairs through ST-B | seize by leaving `1100`, dial, talk through ST-A | full; impossible without ST-B |
| **COUNT** | either pair | violations into the bar, gated by ten `LINE` blinks | as WATCH or TERM |
| **LEVEL** | both pairs and the centre taps | both LEVELs held, both LOWs, PHANTOM | read-only |

The bar is log2: impulse rates span 0.3/s to 1000/s (`sim/impulse_sweep.log`).

## 10. The fault table

Anywhere on the pair unless the row says otherwise.

| fault | the set shows |
|---|---|
| downstream open, or the exchange not sending | DN `CARRIER` and `LINE` dark (UP too, unless the phone's loop-timing circuit coasts, `subscriber-line.md` §7), **PHANTOM 31–48 V**: one broken wire need not break the DC path (`subscriber-line.md` §1.1) |
| upstream open | DN normal; UP dark, LEVEL zero, bar hard over. The exchange sees a quiet on-hook phone |
| both cut, or clipped to nothing | all dark, **PHANTOM 0 V** |
| phantom feed open or the line card's PTC tripped; or the phone dead | DN lit, UP dark; PHANTOM under `subscriber-adapter.md` §4's 31 V for the feed, 31–48 V for the phone |
| ringing | DN `ZEROS` 2.048 s on, 4.096 s off (`newimpl/rtl/clock_card.v`); UP `1100` |
| a loop left off-hook | SPEECH or nothing for good: **the same as a silent call**. A release takes 256 ms (`fabric.md` §5), so minutes of it is not one |
| silence on a call: `MUTE` in an MF8 shelf (`channel-cards.md` §2.3), or a silent far end | a quiet call's lamps; answered by ear on the downstream, at the subscriber |
| marginal reach | LEVEL under 0.5 V, that column's LOW lit |
| impulse noise | the bar climbing; COUNT gives violations a second |
| clips on the wrong pairs | `SWAPPED` |
| tip and ring swapped | nothing: the code has no polarity (`mf8-spec.md` §9) |
| split pair | carrier, low LEVEL, violations: the same as span loss |
| bad dialling | UP `1100` flickers, with no per-break timer. At the subscriber, TALK through ST-B and dial the same number: if the set gets through, the phone is at fault |
| wrong rate plug | `CARRIER`s dark or chattering with LEVEL normal |
| own termination IN while bridged | TERM-IN lit in WATCH |
| cells flat | `BATT` lit: '123 widths drift and violations may be invented |

## 11. What it cannot do

It cannot talk while bridged, frame anything (on a trunk plug it reads carrier,
level and violations only), time single breaks, read dBm, kilometres or impulses
a second, or send DTMF. It cannot see inside the exchange: words, `BUSY` and
connections are on the exchange bus (`fabric.md` §3, §4), not the pair, and the
set is no bus master (`bus.md` §5).

## 12. Open

- **The bridge is arithmetic**: `subline.py xfmr` has no bridged row. Check the
  far receiver's level with the set off and on; if the tap costs more than
  computed, WATCH degrades every call it watches.
- **Transferred, not measured**: the 0.5 V LOW mark (no 64 kbps attenuation
  ladder exists), violations as impulses (run `subline.py`'s violation term
  against known impulse rates first), SPEECH's threshold and 0.5 s hold.
- **Not computed**: whether a real silent encoder idles at exact `1010` (offset
  against a 4.9 mV step, `mf8-spec.md` §12.1); phantom imbalance the clips add
  through a winding; the ear amplifier's current.
- **Trunk plugs**: MF2 is differential Manchester and readable at its plug; MF8
  is reserved for AMI, which this receiver cannot decode.
- **The loop-timing circuit** for `TX_CLK` and `DN_HB`: `subscriber-line.md` §7.
