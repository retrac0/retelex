# exch — an exchange at MF8's level of technology

A telephone exchange in 74HC and a few tuned analog circuits, that grows eight
ports at a time, takes every MF8 channel card unchanged, and is tied to other
exchanges by MF8. No processor, no memory part in the exchange logic.

```
 card ── C, A each way ── port ──▶ 8-slot highway, 512 kbps, one per block ──▶ every block
                          port ◀── [ latch: highway | slot ] ◀── marker: hunt a class, write two latches
```

- **The internal protocol is the MF8 slot interface**: a 64 kbps bit stream and one
  signalling level each way. Bits are switched, never decoded: one codec pair end
  to end, over any number of exchanges.
- **The connection memory is a latch at each port**, so the fabric grows linearly
  and adding a block touches nothing installed.
- **Dialled digits are the address**: octal as dialled, ports 00–77.
- **Features are lines.** Operator, outside line, tones, announcements, conference
  and the registers are cards with a class mark; the marker's one special skill is
  hunting a class in fixed order. Nothing anywhere says where anything is.
- **Nobody is in charge of a call.** The marker writes two latches and leaves;
  ringing, ringback, answer and release are done by the ports.

## Documents

| | |
|---|---|
| [docs/exch-protocol.md](docs/exch-protocol.md) | the internal protocol, why it is bits and not voice band (measured), the highway fabric cell by cell (measured), numbering |
| [docs/exch-marker.md](docs/exch-marker.md) | class marks, reading a number, the hunt, supervision and release — with the two faults the model found in the rule as first written — registers as a pool, dialling on the A line |
| [docs/exch-features.md](docs/exch-features.md) | the features that are lines: registers, analog tones, ROM announcements and their seams, operator and console, the FXO card's one change, meet-me conference, data |
| [docs/exch-network.md](docs/exch-network.md) | **analysis**: trunk and tie blocks, `e e h s`, flood–monitor–claim with a worked call and its timing, the caller's own dial pulses as the network's signalling, long distance without a sender, clocking, what was set aside (a register-sender; serial characters on A, measured) |

## Tool

```
python3 exch/exch.py            everything                    (exch/exch.log is the run)
python3 exch/exch.py tandem     N codecs in tandem
python3 exch/exch.py fabric     the highway, cell by cell
python3 exch/exch.py calls      one exchange, a millisecond at a time
python3 exch/exch.py announce   a message as a ROM of CVSD bits
python3 exch/exch.py aline      serial characters on A over 1–7 trunk hops
python3 exch/exch.py flood      the timing of a flooded call, with a sender and live (arithmetic, not a simulation)
```

It imports `audio`, `cvsd` and `mf8` from the repository root and reads the
`talker*.wav` files there (not committed; see the root README). `announce` writes
its image to `exch/out/`, which is not committed.

## What is settled and what is not

Settled, in simulation: the fabric is transparent and its delay is one frame for
every pair of ports; a re-point costs at most one repeated bit; one exchange
sets up, supervises and releases every call in the scenario battery with every
latch idle at the end — once a port reads busy while a release detector is still
timing out, and once ringing is gated by the filtered hook. Both of those came
out of the model, not out of the design.

Decided and not yet modelled: **the network.** All pulse, no DTMF: a call opens a
flood on its first digit and the caller's own dial pulses go down it, live;
every exchange hears them and the owner drops the call in. No sender, no
matrix, no route table. It is described, and timed by arithmetic on measured
constants, but not simulated; `net` is the second pass. Proposed and awaiting a
decision: long distance with no sender either — `1` as a second trigger digit,
area codes beginning 8 or 9 so that a monitor can tell them from an exchange
digit. Every circuit is still to draw. Nothing has been on a bench.
