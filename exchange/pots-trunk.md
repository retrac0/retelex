# The exchange — dual-tone voice-band trunk over a two-wire POTS pair

`network.md` §1.1 allows a voice-band card on a leased circuit or a radio, with
a codec pair on the card and A carried somehow. `baseband.md` is the copper
case with A on its own wire. This document is the other single-channel case:
**one trunk over a dry two-wire pair**, speech in the voice band, **A in-band on
a dual tone each way**, notched out of the speech path.

It is a **tie trunk**, not an outside line. Loop-start stays on the FXO
population of `channel-cards.md` §3. This card rides a POTS-grade 600 Ω pair
the way a leased voice circuit does: tip and ring, no battery feed, no ring
generator, no loop closure toward a CO.

> **Status: proposed; `sim/pots_trunk.py` measured.** The codec law, hybrid
> loss and pulse limits are cited from where they were measured
> (`mf8-spec.md` §12.1, `channel-cards.md` §3.3, `network.md` §1.1,
> `monitor.md` §5.1). Frequency plan and detector timing are assignments;
> §9 records what the sim found against them. No circuit has been drawn and
> no pair has been listened to.

---

## 1. What it is

```
 exchange 22, port 43                                    exchange 23, port 05
   port's C_RX ──▶ decode ──▶ speech TX ──┐
   port's A_RX ──▶ gate send-pair tones ──┼──▶ hybrid ══ tip/ring ══ hybrid ◀── …
   port's C_TX ◀── encode ◀── notches ◀───┤              │
   port's A_TX ◀── dual-tone detector ◀───┘              │
                                                         ▼
                                              far card, jumpers swapped
```

What the near port hears from its fabric is decoded to analog, mixed with the
idle dual tone when A is low, and put on the pair through a hybrid. What comes
back is notched, encoded, and presented as `C_TX`; the receive dual-tone
detector presents `A_TX`. The card holds no digits, counts nothing and decides
nothing — same bargain as `network.md` §1 and `baseband.md` §1.

**Against the other carriers:**

| | MF8 | baseband (`baseband.md`) | this card |
|---|---|---|---|
| conductors | a pair each way | four (or six with clock) | **two** |
| `C` | 64 kb/s on the frame | 64 kb/s NRZ on a wire | **voice band**, codec on the card |
| A | S bit | a wire | **in-band dual tone** |
| data | yes | yes, with the one-clock jumper | **no** — a tandem of about 2 dB (`network.md` §1.1) |
| link-alive | framer / carrier detect | clock conductor or edges | **idle tones present** |

One channel still carries little (`network.md` §1.1): a few lines at the far
end of a network, or a top-up beside an MF8 group. It is not a route for an
exchange's traffic.

---

## 2. Frequency duplex and jumpers

Both ends must send A. The pair carries **two dual-tone pairs**, W and E, and
each card is jumpered to send one and receive the other. Same PCB both ends;
only the jumpers differ.

| jumper | send (oscillators) | receive (detector) | typical end |
|---|---|---|---|
| **WEST** | pair **W** | pair **E** | one end of the hop |
| **EAST** | pair **E** | pair **W** | the other |

```
  WEST                                              EAST
  send W ─────────────────────────────────────────▶ detect W
  detect E ◀─────────────────────────────────────── send E
                    tip ════════ ring
```

### 2.1 The tones

| pair | f₁ | f₂ | why these |
|---|---|---|---|
| **W** | **2400 Hz** | **2600 Hz** | dual-tone AND detection; clear of `tone-plan.md`'s 425∿25 and 600∿120; clear of the DTMF grid so a keypad on the speech path cannot false-claim |
| **E** | **2200 Hz** | **2800 Hz** | same; far enough from W that a twin-T or ceramic notch set can split them |

Four frequencies total. The send gate puts **both** of the jumpered send pair
on the line together, equal amplitude, at a level about **−10 dBm0** relative
to the codec's nominal speech — loud enough for the far detector after hybrid
and line loss, quiet enough that a failed notch is a whistle and not a howl.

**Optional second footprint.** An MT8870 (or kin) and two standard DTMF digit
pairs, jumper-selected, instead of discrete oscillators and AND gates. Same
WEST/EAST jumpers; different frequencies. The default above stays the one that
cannot be talked onto by a telephone keypad.

### 2.2 A polarity — SF sense, dual-tone resilience

| near state | tones toward the far end | far `A_TX` (M at its port) |
|---|---|---|
| idle / on-hook / **pulse break** | **both** of the send pair **present** | **0** |
| seize / off-hook / make / **claim** | send pair **absent** | **1** |

So `A_RX` from the port **gates the oscillators off** when it is high, and
leaves them running when it is low. Dial pulses are the fabric's own breaks on
A: each break restores the tones for the duration of the break; each make takes
them away again. Claim is a steady high on backward A and a steady silence of
the send pair toward the origin (`network.md` §3).

**Why tone-present = idle, not seize.** Idle tone continuous is **carrier
detect for free**: a cut pair, a dead far card and an unplugged jumpers all
look like "no receive pair", and §5 uses that to drop the direction word. Dual
tone with **AND** on "idle detected" means talk-off must hit both frequencies
at once — the same resilience DTMF buys for digits. The detector does **not**
OR the two tones for idle, and does not treat a single-tone hit as a valid
receive pair.

---

## 3. The audio path

The codec engine is `mf8-spec.md` §12.1 verbatim — the same half-LM13700 pair
the FXS card uses (`channel-cards.md` §3.2). The hybrid and the 300–3400 Hz
filters are `channel-cards.md` §3.3's, with notches added on the receive leg.

```
 C_RX ──▶ [ decoder, R on RX_CLK ] ──▶ [ 3400 Hz LPF ] ──▶ speech TX ──┐
 A_RX ──▶ [ invert: high silences ] ──▶ [ send-pair oscillators ] ─────┼──▶ [ hybrid, 600 Ω ] ══ tip/ring
                                                                        │
 C_TX ◀── [ encoder, T on TX_CLK ] ◀── [ 300–3400 Hz ] ◀── [ notch W and E ] ◀──┤
 A_TX ◀── [ AND both recv tones ] ◀── [ detectors on recv pair ] ◀─────────────┘
          then RC + Schmitt (§4)
```

| block | specification |
|---|---|
| Hybrid | transformer, 600 Ω, compromise balance — as FXS. Trans-hybrid loss **10–15 dB** against a real pair |
| Level trims | one per speech direction, same job as `channel-cards.md` §3.3 |
| Speech filters | 300–3400 Hz into the encoder; reconstruction LPF on the decoder |
| Tone inject | **after** speech TX, into the hybrid's four-wire TX leg, so the near talker is not notched |
| Notches | **both** W and E on the RX speech leg, before the encoder filter. Depth **≥ 40 dB** each. The near send pair leaks through the hybrid at only 10–15 dB down; without notching it, the encoder would carry a continuous whistle into every connected port |
| Line | dry tip/ring. **No −48 V feed, no ring relay, no loop detector.** Protection: gas tube, PTC, TVS ahead of the hybrid, as FXO without the ringing path |

**Echo is the binding limit.** This card has a hybrid, so
`network.md` §1.1's **20–30 ms round-trip** bound applies the moment either
subscriber is also analog (FXS / FXO / adapter). **The hop is local or short
leased only** — a few milliseconds of pair, not a satellite, not a long mux —
unless a canceller the design does not have is added later. A network of CVSD
sets with no hybrid at either phone still hears the two hybrids on this hop;
keep the pair short.

**No data.** Voice-band tandem, about 2 dB (`protocol.md` §2). A data card must
not be pointed at this trunk.

---

## 4. Detector timing

`network.md` §1.1: every break of **8 ms** or more must survive; a make must not
be lengthened past the **128 ms** that ends a digit; a break must not be
lengthened past the **256 ms** that is a hang-up. Wander under **12 ms** a hop
on the guard's 128 ms tap.

| | target | why |
|---|---|---|
| Tone present → A low (idle assert) | **≤ 16 ms** | matches the fabric's supervision up-path order (`fabric.md` §3.5); a pulse break must reappear as A low before the digit ends |
| Tone absent → A high (seize assert) | **≤ 8 ms** | seize and claim should not lag the baseband case by much; the flood's own hop time dominates |
| Break shortening | **≤ 2 ms** a hop from the detector alone | budget beside MF8's 0.5 ms; seven hops still leave a 60 ms break as ≥ 40 ms |
| Valid receive pair | both tones of the jumpered recv pair above threshold for the idle-assert time | AND, not OR |
| Link down (§5) | no valid receive pair for **100–200 ms** | clear of a long dial-pulse break (≤ ~100 ms make/break machine) and inside the origin's patience |

The detectors are two narrow filters (or one DTMF receiver jumpered to the
recv digit) into an AND, then an RC and ¼ 74HC14 into `A_TX` — same Schmitt
habit as `mf8-spec.md` §14, with the time constants taken from the table
above rather than from §14's 2 ms bit-error filter. **Assignment, not
measured.**

---

## 5. Link down

`network.md` §1.1 requires the carrier to stop sending its word when the link
is down, so the port reads unequipped and is never hunted, and to let A fall
so a call in progress releases.

**No valid receive pair for 100–200 ms** is link down:

- gate the word's 2×'165 off (open-drain held off) — unequipped, leaves the hunt
- force `A_TX` low — M falls, the port's release rule runs

Idle tones make this free: a live idle hop always presents the far send pair;
a cut tip, a missing far card, or WEST facing WEST (both sending W, neither
hearing a partner) all time out. Glare between two ends that both seize is
unchanged from any other carrier — the word's `g` bit and the hunt order
(`network.md` §1); this card's one-way delay is the pair's propagation plus a
few milliseconds of filter, so glare is closer to copper than to a 40 ms mux.

`MUTE` on the socket stays unused: a block ties it to "locked", and this card's
own detector owns the word enable, as the baseband card's does
(`baseband.md` §3.5).

---

## 6. The card's pins

Two connectors: the channel socket of `common-cards.md` §1, and its rear
connector there, §7.3 — **tip and ring only**. Same star socket as a line card
or the baseband trunk; any slot that may hold a single-channel trunk
(`protocol.md` §5, `network.md` §1.1), including topping up an MF8 direction.

| pin | | | what this card does with it |
|---|---|---|---|
| a1 | `TX_CLK` | in | the encoder's clock; shifts the word's 2×'165 |
| a2 | `LOOP_HB` | — | nothing encodes a digital line |
| a3 | `TX_OCT` | in | loads the word's 2×'165 |
| a4 | `FILL` | — | codec idle is its own `1010` |
| a5 | `C_TX[n]` | **out** | encoder out, in T |
| a6 | `A_TX[n]` | **out** | dual-tone detector (§4), gated low on link-down. M at the port |
| a7 | `RX_CLK` | in | the decoder's clock, in R — same split as FXS (`channel-cards.md` §3.7) |
| a8 | `RX_OCT` | — | |
| a9 | `C_RX[n]` | in | into the decoder |
| a10 | `A_RX[n]` | in | through a short RC and Schmitt to the tone gate: high silences the send pair. E as it stands — `/ANS` is low, a trunk never rings |
| a11 | `MUTE` | — | unused; link-down is §5 on a12 |
| a12 | card word | **out**, o.d. | class trunk `11 101 000` + secondary tag `10` payload `d d g 000` (`extensions.md` §2.2). Held off at power-up by the RC, **and gated by §5's link-down detector** |
| a13 | `/ANS` | **out** | tied low on the board |
| a14 | spare | — | open |
| c5, c7 | `±12 V` | in | codec, oscillators, detectors, hybrid amps |
| c1, c3 | `+5 V` | in | logic |
| c9, c10, c12 | `−48 V`, `RING` | — | **not used** |

**Rear connector: two pins**, tip and ring. Same physical leave as the FXS/FXO
converter; different circuit behind them (dry, no feed).

**WEST/EAST and the tone-pair frequencies are board jumpers**, not socket pins.
Wrong jumpers (both WEST) read as link down at both ends and take the trunk out
of the hunt — fail-safe, if surprising at bring-up.

---

## 7. Parts (order of magnitude)

| | |
|---|---|
| codec engine | `mf8-spec.md` §12.1 / FXS half — one LM13700, integrator and syllabic parts |
| hybrid, trims, speech filters | as `channel-cards.md` §3.3 — TL07x, 600 Ω transformer |
| send-pair oscillators | two Wien or twin-T oscillators, gated; or one DTMF generator jumpered |
| RX notches | four twin-T or two dual notches (W and E) |
| recv detectors + AND | two filters and a gate, or one MT8870 footprint |
| A path RC + Schmitt | ¼ 74HC14 |
| link-down | ½ 74HC123 |
| the word | ≈ 2 + FET — 2×'165 and 2N7002, as baseband |
| `/ANS` | tied low: no part |

No package total is claimed until a schematic exists. It is clearly more than
baseband's ≈ 4½ and in the same band as an FXO population without the ring
detector.

---

## 8. Delay, glare and the guard

| | this hop |
|---|---|
| A's constant delay | a few milliseconds of filter — **costs the flood's guard nothing** (`monitor.md` §5.1) |
| A's wander | detector RC; keep it inside §4's table and the 128 ms guard tap holds |
| Glare window | pair delay + marker, not tens of milliseconds of mux — closer to copper than to a leased digital hop |
| Echo | **binds** — §3 |

Nothing in the pulse-flood protocol changes. The monitor still wants every
break of 8 ms; the claim is still backward A high; release is still the fall
of filtered M or E.

---

## 9. Measured (`sim/pots_trunk.py`), and open

`pots_trunk.log` is the run. Model: dual-tone W/E, −12 dB hybrid leak, Q=25
zero-phase notches, Goertzel AND + twist ≤ 6 dB, 16/8 ms Schmitt, Gaussian
noise referred to one tone's rms.

| | result |
|---|---|
| **Notch depth** | ≫ 40 dB at each of 2200/2400/2600/2800 (ideal IIR; print capped at 80) |
| **Idle detect vs noise** | A stays idle to **0 dB SNR**; ~3 % false seize at −3 dB; ~30 % at −10 dB |
| **Dial pulses** | digit 5 (60/40 ms) keeps all five breaks ≥ 50 ms through **0 dB SNR**; ~5–10 ms shortening from the detector |
| **Link down** | cut pair → unequipped in **160 ms** (target 100–200) |
| **Speech + notches** | idle whistle residue **−95 dB** with notches; without them segSNR collapses to ~8 dB. With notches, tandem segSNR holds the ceiling against a notched reference; channel noise then binds (17 dB at SNR 20, 10 dB at SNR 10) |
| **Talk-off** | flat in-band synthetic speech false-idles **~11 %** of the time (worst stuck run ~50 ms). A 1 kHz tone at nominal: **0 %**. Real speech with formants is owed |

**What the sim does not settle.** A Goertzel-and-Schmitt stand-in is not a twin-T
plus LM567; causal notches on the card will disperse speech where filtfilt does
not; talk-off wants a real talker, not band-limited noise; and nothing has been
on a pair.

Still open on the bench:

- **Talk-off with real speech** into the jumpered detector.
- **Pulse integrity** through two cards and a real hybrid.
- **Notch depth with a compromise balance** — Q and the hybrid will fight.
- **Level plan** (−10 dB re nominal) against a working detector IC.
- **MT8870 footprint**, if built.
- **Schematic and Falstad.**
- **Canceller.** Out of scope; long hops stay forbidden by §3.
