# exrtl — the exchange in Verilog

A register-transfer model of the exchange of [`exch/docs`](../exch/docs): the
64 × 64 crossbar, the ports that supervise themselves, and the clock card, in
synthesisable Verilog. It is built the way the 74HC design is built — a '151 is
a `mux8`, a '273 is the port's `addr` register, the block has no address and no
comparator — so that the RTL and the documents can be read against each other.

> **Status: the fabric, the mainboard and the supervision run and are checked.**
> No marker, no register, no trunks. `make fabric` reproduces `exch.py fabric`
> 1, 3 and 4 bit for bit; `make mvp` runs `mvp-ex.md` §6.3, the manual board
> with no marker at all; `make two` runs two whole exchanges on crystals 100 ppm
> apart in one simulation. Nothing here has been on an FPGA.

**The hierarchy is the layout.** Each module is a thing you could point at in a
rack, and the module boundaries are the connectors.

```
 exch_top          ONE exchange -- the logic of mvp-ex.md 1, and nothing that plugs in
   clock_card      HCLK, SLOT, SLOTQ a quarter cell later, TX_CLK, TX_OCT, RX_OCT,
                   HB, FILL, the ring cadence, TICK          (exch-mainboard.md 2.1)
   mainboard       the ribbon's sixteen highway conductors, the eight BLK conductors,
                   and the SHUNT field that gives each block position its number
                                                             (exch-mainboard.md 1, 6)
   block  x8       four commutators, the write and strobe decoders, the ringback
                   '157s, and eight ports                    (exch-fabric.md 3.1)
     port x8       the crosspoint: '273, three '151s, a '74 pair   (exch-fabric.md 3.2)
                   the supervision: two detectors and the gates    (exch-fabric.md 3.5)
   mux8            a 74HC151.  The whole fabric is this part used three ways

 line_card         a card that plugs into a channel slot -- OUTSIDE exch_top, because
                   that is where it is                       (mf8-backplane.md 8)
```

`exch_top`'s edge is the 64 channel-slot pin groups and the two cables. Cards
are instantiated beside it, never inside it, which is why a port has no idea
what it is and why an MF8 trunk card can tap `hc[h]`/`ha[h]` from outside.

## Running it

```
make fabric   every source to every listener, bit-exact, one frame
make mvp      mvp-ex.md: absent parts read as idle, and the hotline
make two      two exchanges, own crystals 100 ppm apart, both making calls
make lint     verilator, the whole exchange fitted
make synth    yosys: what the 64-port exchange costs in cells
```

## What is decided here, and why

**One clock: the clock card's own 4.096 MHz crystal** (`mf8-spec.md` §9.1).
Eight master ticks to a 512 kHz cell, eight cells to a frame, eight frames to an
octet. Everything the 74HC design does with separate clock wires comes out here
as strobes on that one domain, so the model is synchronous throughout and
`SLOTQ` still sits a quarter of a cell behind `SLOT`, where `exch-fabric.md`
§3.2 puts it. **This does not reproduce the §3.2 hazard** — a race between a
'138's address and its enable has no meaning in RTL, where nothing glitches by
construction. `SLOTQ` is here because the hardware has it, not because the model
needs it.

**Capture at mid-cell, sampled at the frame edge.** A port's '74 pair clocks at
tick 4 of the selected cell, and a card reads `C_RX` at the frame edge and
nowhere else. That gives the one frame of delay for every pair of ports that
`exch.py fabric` measured, whatever the two slots — which is what keeps octets
aligned (`exch-fabric.md` §3.4).

**No tri-state.** The highways have one driver a wire, so they are plain signals.
The probe bus `PB` *is* tri-state in 74HC, and here it is a mux with the same
observable behaviour: pulled low when no block is selected, so an absent block
reads as eight unequipped slots (`exch-mainboard.md` §6).

**Growing the exchange is changing a parameter.** `BLOCK_FITTED` and
`PORT_FITTED` default to the MVP of `mvp-ex.md` §1 — block 2 alone, port
circuits at 20 and 21, `RBT` strapped to `FILL`. An unfitted block's highway is
pulled to `FILL` and its `A` to ground; an unpopulated slot the same. Nothing
that is fitted changes when more is.

**The subscriber interface is four wires.** A card's subscriber side is `tx`
and `rx` (CVSD each way) and `m` and `e` (the hook out, supervision back) --
the names `exch-fabric.md` §3.5 uses throughout, and the same four leads as
`mf8-spec.md` §12.1's E&M card. The transformers, the 48 V phantom and the
128 kBaud line code of `subscriber-line.md` change no bit that reaches the
exchange, so they are left out. `e` already carries the ring cadence: the
port's own gates did that, not the card.

**More than one exchange.** Nothing in the RTL is global and every module takes
its clock as a port, so an exchange is a thing you instantiate. `make two` runs
a pair on crystals 100 ppm apart -- the plesiochronous case `mf8-backplane.md`
§2 assumes of any two ends of a link.

**A block does not know its own number.** `block`'s `H` parameter is carried so
an instance names itself in a waveform and is read by nothing. Which highway a
block drives is the `mainboard`'s `SHUNT` parameter -- three bits a position,
the three shunts in one silkscreened column of `exch-mainboard.md` §1. A
position whose shunts are left out drives nothing and its column is pulled to
`FILL`; two positions shunted onto one column read as `x`, which is what two
'244s on one conductor are. Layout, not logic.

## What it costs

`make synth`, all eight blocks and all 64 ports fitted, after `techmap`:

| | |
|---|---|
| cells | 19 454 |
| flip-flops | 2 856 |
| of which, the two release detectors | **1 920** — 30 of every port's 44 |

That last row is the honest difference between this and the hardware. In 74HC
the two detectors are a diode, two resistors, a capacitor and a Schmitt gate
each: **an RC, not a counter.** The RTL has to count frames to get 16 ms and
256 ms, and two 15-bit counters a port is two thirds of the whole design's
flip-flops. Anyone putting this on an FPGA pays that; anyone building it in
74HC does not.

## Open, and deliberately not guessed

- **`A out = E + CLAIM`** (`exch-fabric.md` §3.1). Written as `E + CLAIM` in the
  document and implemented here as `A_TX | CLAIM`, which is identical wherever
  `CLAIM` is never written — every block but a trunk block. Which one is meant
  needs settling before a trunk block is modelled. Marked `FIXME` in `port.v`.
- **The word's encoding.** `exch-protocol.md` §5 says a plain line card ties its
  word pin to ground and "reads all ones and means a line with no options",
  while `exch-fabric.md` §3.5's table gives *line* as class 001. Both cannot be
  right. The fabric uses the word for nothing, so the commutator is wired and
  the encoding left alone until the marker is built.
- **Detector tolerance.** `exch.py calls` draws each port's detectors ±20 % about
  256 ms, which is why `mvp-ex.md` §3 has 21 release at 6.266 s and 20 at 6.284.
  Here they are exact, so both ports release in the same frame.

## Next

In `mvp-ex.md` §6's order, which is the order to bring real hardware up in:

1. **The marker** (`exch-marker.md`): the scanner, the probe on `HA` and `PB`,
   the sequencer on cable B, and the hunt by class in fixed order. Then a
   pulse register, and the MVP dials instead of being patched by hand.
2. **The MF8 trunk card**: the transmitter of `mf8-spec.md` §10 with F and S
   put back into its block's `HC[h]`, and the §9.4 receiver -- a classifier
   that times gaps between transitions, with no clock and no PLL on the
   receive path -- driving six ports' `C_TX` and `A_TX` through a '259. The
   taps it needs are already brought out of `exch_top`.
3. **A link between two exchanges**, which `make two` is the groundwork for:
   two crystals, two clock domains, and the one crossing of
   `mf8-backplane.md` §2 on the trunk card.
