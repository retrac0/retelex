# The exchange

A telephone exchange in 74HC and a few analog circuits: 64 ports on one
8 × 8 fabric, every MF8 channel card taken unchanged, tied to other exchanges
by the *pulse flood*. No processor and no memory part in the exchange logic.

> **Status.** The fabric, both markers, the register, the network unit, the
> baseband tie and the local eight-channel trunk are built in RTL
> (`newimpl/`) and measured in simulation. The block header and port card are
> drawn in KiCad (`pcb/`). Nothing has been on a bench. Test status and what
> the benches do not cover: `newimpl/README.md`.

---

## 1. What it is

```
 card ── C, A each way ── port ──▶ HC[h]: 8 slots at 512 kbps, one per block ──▶ every port
                          port ◀── latch: highway | slot ◀── marker writes it on the control bus
                          port ──▶ /HA (M), /HB (BUSY): one bit-time a port, 1 ms a pass
```

- **The switch carries bits, never voice band.** A port is a 64 kbps stream
  and one signalling level each way — the MF8 channel slot. One codec pair
  end to end, over any number of exchanges (`analysis/why-bits.md`).
- **The connection memory is a latch at each port**: it names the highway and
  slot the port listens to. A cleared latch listens to 00, idle.
- **Dialled digits are the address.** Octal as dialled, ports 00–77
  (`numbering.md`).
- **The card says what it is.** A port's card tells the exchange everything
  about it in one serial word (`card-word.md`); nothing on common control
  says where anything is. Features are cards, not parameters.
- **Nobody is in charge of a call.** The marker writes the latches and
  leaves. Ringing, ringback, answer and release are done by the ports, and a
  port releases on a fall (`fabric.md` §5).

Rules the RTL taught, which every part of the design follows:

- **An event on a wire is a race; a level valid when read is not.** A claim, a
  digit, a seizure, a register falling free: each is a level held until the
  other side has seen it.
- **Act on the latched port, never on live `SCAN`.**
- **Do not let go of a connected call until the called port could let go of
  it** (`marker.md` §5).
- **A store must be empty whenever it is idle.**
- **Nothing read out of turn, so nothing to remember** (the class marker's
  walk, `marker.md` §4).
- **Arbitration appears only where there are two of something.**

## 2. The three builds

Each build is an RTL top around the same `exch` — the clock card, the bus,
the blocks, the port cards. Common control is the one family of cards that is
swapped rather than added to; everything else a build gains is a card whose
word says what it is.

| | `top_min` | `top_net` | `top_max` |
|---|---|---|---|
| common control | the mini marker, its one register on the card | the mini marker and a network unit | the class marker and a register card; the unit fitted or not |
| a caller | M and not `BUSY` | the same, and not a trunk, not none | read by the walk, by its word |
| dial tone within | a pass, 1 ms | a word read and a pass | a round of the walk, about 250 ms |
| key 1 | highway 1 | the flood | the flood with a unit, else highway 1 |
| 0, 9 | cannot-complete | cannot-complete | the operator and answers-to; outside lines |
| a busy line | cannot-complete (Open, `numbering.md` §6) | cannot-complete | busy tone |
| the card word | not read | trunk or none only | the primary octet |
| answers-to, nails, sources, restricted, busy-out, `PWAIT`, CO lines, data lines | no | no | yes |
| benches | `tb_mini` | `tb_net`, `tb_chain`, `tb_lnet`, `tb_lfull`, `tb_lchain` | `tb_max`, no unit fitted |

- **`top_min`, the minimal exchange**: the clock card, one block in position 2
  (0 and 1 are keys, so 20–77 are the first numbers anyone can dial), a port
  card and a line card for each phone, and the mini marker. Two phones dial
  `2 0` and `2 1`. Tone cards at 01 and 03 are optional: without them the
  caller hears silence and the call still completes. Everything absent reads
  idle (`bus.md` §6).
- **`top_net`, a pulse-flood exchange with the small marker**: `top_min` plus a
  network unit, which grounds `/NET`, and trunk cards in any sockets.
  `1 e b h s` reaches any line; local numbers do not change. A flood never
  needs a smarter marker (`network.md` §3).
- **`top_max`, the class marker**: pull the mini marker, fit the class marker
  and a register card. Every feature is then a card whose word says it: tones
  at 01–03, an operator at 04 and more positions answering to 04, an FXO card
  whose word says outside line, a card with a nail in its jumpers
  (`features.md`). The unit plugs in beside it unchanged; the class marker on a
  network has not been benched.

More lines are port cards and line cards, then blocks 3–7. More registers need
a pool, which is not built (`register.md` §4).

**Bring-up order.** The fabric first, block by block, with no marker at all
(`fabric.md` §6.3): the clock card, a header, then latches written by hand
from a jig — 20 and 21 pointed at each other are a hotline that rings and
releases itself. Then the builds in order: the mini marker (`top_min`, dial 20
and 21); a network unit and trunk cards (`top_net`, dial across a link); the
class marker and a register card (`top_max`: 0, 9, answers-to, nails).

## 3. Glossary

One name per object. Signals are in `bus.md` §1; word fields in
`card-word.md` §2.

| term | meaning |
|---|---|
| cell | 1.953 µs, one of eight in a 64 kHz frame; one slot of a highway |
| bit-time | one 64 kHz frame, 15.63 µs, in which port *p* = `SCAN` owns `/HA` and `/HB` |
| pass | 64 bit-times, 1 ms, the `TICK` period: every port once on the planes |
| capture instant | mid-cell 4, 8.79 µs into a bit-time, where every open-drain line is sampled |
| highway, `HC[h]` | block *h*'s eight ports' C, one a cell, 512 kbps |
| plane | `/HA` (M) or `/HB` (`BUSY`): one open-drain wire, port *p* in bit-time *p* |
| select, `/WS`; word wire, `/HW` | a reader names a port on `/WS` in its bit-time; that card's word follows on `/HW` for eight frames |
| seat | one of a block's eight port positions |
| lane | a per-seat net up a block's stack (`C_TXk`, `WORDk`, `/WRk`) |
| FIT | the header jumper that says a block is fitted |
| port card | a seat's latch, listener, supervision gates and plane drains |
| block adapter | a trunk card serving a whole block's seats |
| probe | a scanner-addressed listener: latches one port's M and `BUSY` from the planes |
| M, E | the port's own hook (`A_TX` from its card) and what it hears on A from the port it listens to |
| `BUSY` | a port that is not free: written into a call (`BSY`), or held by its own detectors or its block's `MUTE_BLK` (`fabric.md` §5) |
| control word | 16 bits on the control bus: `DST`, `SRC`, `BSY`, `CLM`, `G` |
| event word | a control word with `G` = 0: counted, never written |
| card word | the serial word on a card's word pin saying what its port is; the **primary octet** is all the exchange reads; the **secondary byte** is not readable yet |
| wire order | bit-time 0 first, each field LSB first: how every word table is printed |
| plain line | a card whose word pin is grounded: all ones, a line with no options |
| none | all zeros: no card, a card held off, a trunk whose link is down |
| `/ANS` | the a13 pin: open, the port rings; low, it answers at once |
| marker | the card that takes callers, gives them the register, connects, lets listen or hunts: the **mini marker** or the **class marker** |
| walk | the class marker's read of one port every 4 passes, 01 to 77: the only way a caller is taken; a **round** is one walk, about 250 ms |
| hunt | the class marker's read of every port from 01 for the first free one that answers to a number, or for 9 an outside line |
| watch | the marker keeping the register on the caller after a connect until the called port can release itself (`SETTLE` = 2 × `T_ARM`, 32 ms) |
| register | the pulse collector: counts a caller's breaks into a digit store; **HIT, ID, CLR** its windows (8, 128, 256 ms); **no-digit timer** 10 s |
| key | a first digit that is not a highway: 0, 1, 8, 9 |
| cannot-complete, busy tone | ports 03 and 02 |
| answers-to | a line that also takes calls to another number that could not be completed there |
| tied nail, mutual nail, call nail | a port that listens to its dest for good (one write, one way); two tied nails naming each other (a private line); a port that on lift connects as if its dest were dialled |
| source | a port listened to, never written or rung |
| flood | a network call: the origin seizes a trunk in every direction and each exchange forwards it, until the owner claims |
| network unit | the card that runs the flood: its own probe, its own bus master, the monitors, resolvers and forwarder |
| monitor | a cell on the unit that reads a seizure's dial pulses and claims the call if the code is its own |
| claim | the owner's backward A = 1 on the trunk the call arrived on |
| resolver | the unit's hold on a forwarded flood until the claim decides which leg won |
| guard | the window after the origin's seizure in which a break from the caller abandons the call rather than risk a wrong number: a strap on the unit, 128, 256 or 512 ms (`network.md` §6) |
| strap | per direction on the unit: no flood is forwarded into or out of that link (rings) |
| glare | both ends seizing one channel at once; the claim takes it and joins the callers |
| `/NET` | grounded by a fitted network unit; makes 1 the flood key |
| SU-1, SDU-1, STU-1 | the subscriber set, the data set, the test set (`common/`) |

## 4. Documents

**The design, as built** — each topic is said once, in the document that owns it.

| | |
|---|---|
| [numbering.md](numbering.md) | the number, the port map, the keys, what a failed number gets, exchange codes |
| [fabric.md](fabric.md) | the C plane, the supervision planes `/HA` `/HB`, reading a card's word on `/WS` `/HW`, the port circuit and its gates, the block, timing |
| [bus.md](bus.md) | the one bus: signals by function, the 2 × 25 header, the control word, two masters, what an absent part reads as |
| [block-stack.md](block-stack.md) | the block as built: header boards and eight port cards in a stack, lanes and jumpers, the adapter commons |
| [marker.md](marker.md) | the mini marker and the class marker: a call step by step, the walk, the hunt, `PWAIT`, the watch, release |
| [register.md](register.md) | the register: windows, no-digit timer, circuit, its ribbon, how many |
| [card-word.md](card-word.md) | what a card says about its port: classes, options, answers-to, nails, the secondary byte |
| [network.md](network.md) | the pulse flood: carriers, the network unit, a call across the network, glare, the guard, rings, clocking |
| [trunks.md](trunks.md) | trunk cards: the baseband tie, the local eight-channel trunk, the MF8 six-channel face |
| [features.md](features.md) | tones and ringback, announcements, the operator, outside lines, sources, data lines, test lines |
| [debugger.md](debugger.md) | the debugger card: eleven lamps that name the board to pull |
| [decisions.md](decisions.md) | what the spec no longer holds, and why: one line each |

**Proposed, not built** — [proposed/](proposed/)

| | |
|---|---|
| [console.md](proposed/console.md) | the operator's console: release, pair, patch, supervise |
| [conference.md](proposed/conference.md) | a codec-free voice-switched bridge whose legs answer to its number |
| [lamps.md](proposed/lamps.md) | the hook/busy lamp panel, the port watch, the last-word display |
| [counters.md](proposed/counters.md) | the peg counter card, event codes, calls in progress |
| [pulse-gen.md](proposed/pulse-gen.md) | a hook and pulse generator card for test |
| [ss0.md](proposed/ss0.md) | the number as one message on MF8's spare bit, instead of the live flood |
| [leaf-uplink.md](proposed/leaf-uplink.md) | a PBX leaf off a central exchange |
| [pots-trunk.md](proposed/pots-trunk.md) | one trunk over a dry two-wire pair |
| [terminal.md](proposed/terminal.md) | six subscriber lines at another site over MF8 |

**Analysis** — measurements and sizing behind the design; not normative. Each
says at the top what has changed since it ran. [analysis/](analysis/)

| | |
|---|---|
| [why-bits.md](analysis/why-bits.md) | why the switch carries bits, and why 64 ports |
| [dialling.md](analysis/dialling.md) | dial pulses as the register sees them, measured end to end |
| [monitor-rules.md](analysis/monitor-rules.md) | the rules that keep a flood from claiming a wrong number |
| [topology.md](analysis/topology.md) | chains, stars, trees, rings: what each carries and where it stops |
| [traffic.md](analysis/traffic.md) | bursty demand, flash crowds, peak against off-peak |
| [eight-channel-mf8.md](analysis/eight-channel-mf8.md) | the 16-bit, eight-channel MF8 frames — not taken |

The cards shared with the MF8 shelf, the subscriber line and the subscriber
equipment are in [`../common/`](../common/), indexed in the root `README.md`.

**The model:** `sim/exch.py` — `python3 sim/exch.py <run>`, with the committed
output in `sim/exch.log`: `tandem`, `fabric`, `calls`, `announce`, `aline`,
`flood`, `monitor`, `timing`, `mainboard`, `confer`, `ss0`, `net`, `topo`,
`traffic`, `big`. Each document names the run it cites.

## 5. Open

Each document ends with its own Open section. These are the questions that
need a decision rather than more work:

**The network**
- **A transit that cannot forward loses the call silently.** Every forwarding
  exchange takes a resolver for each flood, with two fitted and one forwarder;
  when none is free nothing is sent and nobody is told (`network.md` §10).
- **The guard's reach.** A slow hop is now ≈ 22–30 ms, so the 128 ms tap covers
  4–5 hops, not ten; the size limits in `analysis/topology.md` have not been
  re-run. And `GUARD` code 3 (1024 ms) abandons conforming dials (`network.md`
  §10).
- **The mini marker's lockout with a unit fitted.** A port showing M with a
  word of none is re-read every other pass, and the seven ports after it are
  never offered (`marker.md` §7).
- **A dialled tone trunk**: the class marker refuses it, the mini marker
  connects it, so a `top_max` central cannot dial into a PBX leaf
  (`marker.md` §7).
- **Console arbitration**: a third bus master needs both the marker and the
  unit to yield, and the unit has no yield input (`proposed/console.md` §9).

**Common control**
- **Busy on the mini marker**: 03 as built, or 02 like the class marker
  (`numbering.md` §6).
- **The card word's secondary byte cannot be read** at a bit a frame. Cover,
  dual numbers, L/U/K and the trunk's all-ones check wait on a load strobe or
  another way to get a second octet (`card-word.md` §8).
- **Data bit `D` bars switched data**: a `D` line is nailed only, so SDU-1's
  switched insert-1 needs `D` clear (`card-word.md` §8).
- **A CO line rung in with no position free** stays `BUSY` and is never
  answered (`features.md` §8).

**Hardware**
- **Who holds `/RESET` high**, and where the power-on RC and button go
  (`bus.md` §7).
- **Open-drain control lines** (`SDATA`, `SCLK`, `WR`): asked, not decided
  (`bus.md` §7).
- **Ringback has no path onto `RBT` in a block**, and the three ringback
  cadences disagree: every block build has silent ringback until this is
  settled (`../common/tones.md` §9).
- **The MF8 block adapter**: its 1.024 MHz is not on the adapter commons, seats
  0 and 4, and an eight-channel adapter's face (`trunks.md` §5).
- **One card, two ways in**: rails on socket row c in a shelf, a harness in a
  block (`../common/common-cards.md` §7).
- **The line card**: the phone's loop-timing circuit
  (`../common/subscriber-line.md` §7); the encoder's H against `TX_CLK`, the
  §9.5 filter buffer and the detector's comparator rail
  (`../common/channel-cards.md` §6).
- **`mf8/mf8-spec.md` §9 owes circuit-review's fixes**: the encoder as a '112
  (§9.2), the two-phase receiver timing (§9.4), the classifier column (§9.7),
  and §12.1's syllabic resistors. The common/ documents already say them;
  mf8-spec does not yet. §3.5 also still reads as if SS0 on the spare bit were
  decided (it is proposed; the remote alarm is decided).
