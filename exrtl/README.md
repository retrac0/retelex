# exrtl — the exchange in Verilog

A register-transfer model of the exchange of [`exch/docs`](../exch/docs): the
64 × 64 crossbar, the ports that supervise themselves, and the clock card, in
synthesisable Verilog. It is built the way the 74HC design is built — a '151 is
a `mux8`, a '273 is the port's `addr` register, the block has no address and no
comparator — so that the RTL and the documents can be read against each other.

> **Status: an exchange that dials.** The fabric, the mainboard and its serial
> control bus, the supervision, an MF8 trunk, and the common control — marker,
> register and seeker — run and are checked. `make net` runs two exchanges
> tied by one MF8 link making **dialled** calls, local and across the trunk by
> `exch-network.md` §3's pulse flood. What is not here: a transit hop (needs a
> third exchange), fan-out and the resolvers of §3.2, and more than one
> register or monitor an exchange. Nothing has been on an FPGA.

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
   ctl_write       the serialiser for cable B: one 16-bit word on one wire
                                                             (exch-mainboard.md 2.3)

 marker            scanner, probe, hunt in fixed order from 00, the number
                   parsing of 2, and the flood at both ends   (exch-marker.md,
                                                              exch-network.md 3)
 pulse_reg         the register: no port, no class, reads its caller's hook off
                   the M highway through its own probe        (register.md 4)
 monitor           the seeker, on a trunk block: the only part of the network
                   that reads a digit it was not sent         (exch-monitor.md)
   pulse_rx        register.md 2's three windows off one timer, shared by both

 line_card         a card that plugs into a channel slot -- OUTSIDE exch_top, because
                   that is where it is                       (mf8-backplane.md 8)
 mf8_trunk_card    six channels of a block made into a tie trunk (exch-network.md 1)
   mf8_encoder     differential Manchester: a transition a cell, two for a 0
                                                             (mf8-spec.md 9.2)
   mf8_decoder     the classifier: times gaps, no PLL, nothing to lose
                                                             (mf8-spec.md 9.4)
   mf8_framer      F = 11111110, the guard at states 0 and 4, 32 to lock,
                   two +2/-1 counters to track               (mf8-spec.md 3, 4)
```

`exch_top`'s edge is the 64 channel-slot pin groups and the two cables. Cards
are instantiated beside it, never inside it, which is why a port has no idea
what it is and why an MF8 trunk card can tap `hc[h]`/`ha[h]` from outside.

## Running it

**Two simulators run the same testbenches.** Icarus is the reference; Verilator
is about two orders of magnitude faster and is what to use while working. The
network testbench is 3 s of model time: minutes under Icarus, 22 s under
Verilator. Anything that passes under one must pass under the other.

```
make fabric   every source to every listener, bit-exact, one frame
make mvp      mvp-ex.md: absent parts read as idle, and the hotline
make two      two exchanges, own crystals 100 ppm apart, both making calls
make trunk    two exchanges tied by one MF8 link, calls patched across it
make net      the same two exchanges, calls DIALLED: local, and the pulse flood
make iv       the whole suite again under Icarus, as the reference
make trunk-ppm  the link with the two crystals 100 ppm apart
make lint     verilator, the whole exchange fitted
make synth    yosys: what the 64-port exchange costs in cells
```

| | Icarus | Verilator |
|---|---|---|
| `fabric`, 29 ms of model time | seconds | **0.28 s** |
| `trunk`, 70 ms | ~5 s | **0.72 s** |
| `net`, 3 s | minutes | **22 s** |

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

**The control bus is one word on one wire.** `exch-mainboard.md` §2.3: the
marker's whole output is sixteen bits — a guard, `DST`, and the port's '273
verbatim — broadcast to every block, and the block that answers `WR` is the one
its shunt column names. One consequence the RTL made plain: **`/BLK` steers the
probe as well as the write.** The block that drives `PB` is the block the shift
register names, so the marker cannot probe a block without first shifting a word
naming it. `ctl_write` takes a `strobe` input for that — low, it shifts the word
and never pulses `WR` — which is safe only because nothing reads a block's shift
register outputs until `WR`.

**A trunk is a pair of ports back to back, and nothing else.** What a trunk
port hears from its own fabric goes out on the line; what comes in off the line
is what that port's card says (`exch-network.md` §1). The card decides nothing
and holds no digits. A call across it is the hotline rule of `exch-fabric.md`
§3.5 running through the pair untouched: the far line rings because its port
sees E, and the caller hears ringback because the far port substitutes `RBT`
into its own highway cell — both of which `make trunk` watches happen across
two exchanges.

**A block does not know its own number.** `block`'s `H` parameter is carried so
an instance names itself in a waveform and is read by nothing. Which highway a
block drives is the `mainboard`'s `SHUNT` parameter -- three bits a position,
the three shunts in one silkscreened column of `exch-mainboard.md` §1. A
position whose shunts are left out drives nothing and its column is pulled to
`FILL`; two positions shunted onto one column read as `x`, which is what two
'244s on one conductor are. Layout, not logic.

## The link, measured

`make trunk` — two exchanges, one MF8 pair each way, the console patching
latches at both ends:

| | |
|---|---|
| both framers acquire | **38 frames** after reset — `mf8-spec.md` §4.1 measures 37–86 |
| re-acquire after the link is cut and restored | 33–55 frames |
| speech, each way, each channel | **0 wrong in 400 bits**, at a delay of 3–4 frames |
| two calls at once on channels 1 and 2 | same delay on both: no crosstalk |
| the link cut with two calls up | squelch, both framers unlock, **every call releases itself** |

**Crystal offset.** At 0 and 100 ppm the speech paths are bit-exact; at 100 ppm
a slip is one bit in 10 000 frames and the 400-frame window sees none, as
`mf8-backplane.md` §7 predicts. Driven far past the specification — 5 000 and
20 000 ppm, 50× and 200× the ±100 ppm the design assumes — the framer still
locks in 38 frames and the calls still run; what appears is **ten isolated
wrong bits in 400**, clustered at the slips, and not a broken link. That is the
failure mode the design was built for: a slip costs a bit, not a call.

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

## Two things the RTL settled

**`A out = E + CLAIM`** (`exch-fabric.md` §3.1) is the A the port hands its
**card**, not its highway contribution. Three things agree: "2 × 74HC32" is
eight OR gates for eight ports; backward A goes up the link, which is fed from
`A_RX`; and the highway must go on carrying the far caller's dial pulses so that
a register at the claiming exchange can read `h s` off them. Put it on the
highway instead and the claim jams the register the claim itself summoned.

**A claimed trunk keeps `CLAIM` for the whole call it brought in.** The marker's
later writes to that port — dial tone off, the connect — must carry it, or
backward A drops and every patch behind it releases itself 256 ms later. Found
by `make net`: the call reached the far exchange, rang nothing, and the origin's
trunk let go.

## Open, and deliberately not guessed

- **The word's encoding.** `exch-protocol.md` §5 says a plain line card ties its
  word pin to ground and "reads all ones and means a line with no options",
  while `exch-fabric.md` §3.5's table gives *line* as class 001. Both cannot be
  right. The fabric uses the word for nothing, so the commutator is wired and
  the encoding left alone until the marker is built.
- **Detector tolerance.** `exch.py calls` draws each port's detectors ±20 % about
  256 ms, which is why `mvp-ex.md` §3 has 21 release at 6.266 s and 20 at 6.284.
  Here they are exact, so both ports release in the same frame.

## Next

1. **A third exchange**, to make a chain: that is the first configuration with a
   **transit** in it, and transit forwarding is the one part of
   `exch-network.md` §3 that two exchanges cannot exercise. Then a hub and its
   resolvers (§3.2).
2. **More than one register and one monitor.** `exch-monitor.md` §4 wants two
   monitors a block to four exchanges and three to twenty; `exch-marker.md` §6
   wants three registers at 48 lines. Both are pools of one here.
3. **A testbench for the `SCLK` hazard** (`exch-mainboard.md` §7): a spurious
   shift puts the next write in the wrong port with the wrong source. It costs
   one call and does not persist, and it is worth watching it not persist.
