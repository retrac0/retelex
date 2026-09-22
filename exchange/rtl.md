# The exchange — what building it in Verilog found

`verilog/` is the exchange of these documents in synthesisable Verilog: the
fabric, the mainboard and its serial control bus, the supervision, MF8 trunk
cards, and the common control — marker, registers, a network unit, monitors.
Eight testbenches run it, up to three exchanges in a chain making dialled calls
over the pulse flood. The flood is `net_unit`, not the marker
(`common-control.md`).

This document is the part that matters to the design rather than to the code:
**ten things the documents did not say, or said in a way that does not survive
contact with a second of anything.** Each names the document and section it
belongs to. They are collected here because six of those documents
were being revised in the working tree at the time and this one could be
written without disturbing them.

> **Status: measured in simulation.** Every finding below made a testbench fail
> and then pass; none is an argument. What is measured is behaviour in RTL, not
> timing in a real part: `verilog` has no gate delays, so it cannot see the hazard
> of `fabric.md` §3.2 and cannot confirm §4's nanoseconds. Nothing has been
> on a bench. Package counts are untouched by all of this except where said.

---

## 1. The one rule the rest are instances of

> **An event on a wire is a race. A level that is valid when read is not.**

A claim offered as a pulse, a digit handed over as a strobe, a store read a
cycle before it was written: three of the ten below are this one mistake, and
every fix was the same conversion — a pulse became a held request, a strobe
became a store, a signal read too early got a hold-off. It is worth stating in the design because the exchange is full of
things that look like events and must not be: a claim, a digit, a seizure, a
register falling free.

Three more are about **arbitration** — two of something reaching for one thing
in the same instant — and they only appear once there *is* two of something. An exchange with one register and one monitor a block hides all of
them.

---

## 2. Findings, by the document they belong to

### `fabric.md` §3.1 — `A out = E + CLAIM` is the port's `A_RX`

The line reads "Backward A on a claimed trunk: `A` out = E + `CLAIM`, 2 × 74HC32,
used on trunk blocks", and it is ambiguous between the A the port puts on the
**highway** and the A it hands its **card**. It must be the card's: `A_RX`.

Three things agree. Two '32s is exactly eight OR gates for eight ports, which is
a per-port signal, not a per-block one. Backward A leaves on the link, and the
trunk card's transmit A is fed from `A_RX`. And decisively: the highway must go
on carrying the **far caller's dial pulses**, because the register that the
claim itself summons reads `h s` off exactly that highway. Put `CLAIM` on the
highway and the claim jams its own register.

So the supervision of §3.5 becomes, for a trunk block:

```
 A_RX = ( E + CLAIM ) · /( ON · /RING_CAD )
```

### `fabric.md` §3.5 — a claimed trunk keeps `CLAIM` until release

`network.md` §3 says "a trunk port with `CLAIM` set sends backward A = 1,
steadily, until release". That is a constraint on the **marker**, and it is easy
to miss: every later write to that port — dial tone off, the connect — must
carry `CLAIM` too. Written without it, backward A drops for one write, and every
patch behind it clears itself 256 ms later. The call reaches the far exchange,
rings nothing, and the origin's trunk lets go.

### `marker.md` §3 — two calls may reach one line in one scan

**Not in any document, and it cannot happen with one register.** Two registers
can finish dialling the *same* number inside one 8 ms scan. Both probe the
called port at the same visit, both find `BUSY` clear, and **both write its
latch**. One caller is then patched to a line that is ringing for someone else,
and the other's write is overwritten.

It is ordinary glare and takes the ordinary answer — the first takes the line,
the second is told busy — but the hunt rules of §3 should say so, because any
marker that serves more than one call at a time needs it, in 74HC as much as in
RTL. In `verilog` it is one flag, set when a connect is issued and tested by every
other call in the same cycle.

### `marker.md` §4, §6 — what a pool of registers actually requires

§6 offers "one to three of them" and §4 says the scanner is their finder, but
the marker as drawn holds a call's digit-position state, and with the state in
the **marker** a second register buys nothing: the marker can still only follow
one call. `register.md` §4 already has the answer — the '670 store and its index
live in the **register** — and once the digits are there the rest follows:

- the marker's six digit-states collapse to **two**, local and network, each
  waiting for a store to reach a count;
- the key `1` and an own-code `e b` are consumed by **restarting the store**, so
  `e b h s` land in slots 0–3 — which is why four is the right depth — and `h s`
  after a restart are indistinguishable from a local number. An own-code call,
  an incoming claimed call and a plain local call become one path;
- a call's remaining state — its caller, the trunks it seized, whether one has
  claimed — goes with its register, which is where `network.md` §3.2
  already puts the trunks ("a '574 a direction in a bank a register").

**There is one scanner, so there is one hunt.** With several calls, the hunt
needs an owner and a queue: a call that wants one waits until it is free, and a
caller who hangs up mid-hunt must release it or the scanner is locked for good.

**And the key must be consumed the moment it is read**, not when the hunt starts,
or a fast `e` arrives while the old store still holds the key and is wiped by the
restart when it finally comes.

### `marker.md` §4 — a register's store must be empty when idle

A digit handed over as a strobe is an event; a store read as a level is not. But
a store is only safe if it is **empty whenever the register is idle**, and if the
marker waits a beat after attaching one. Neither is obvious and both were found
by a failing test: a cycle after the register was handed to a new caller the
marker read the store, found the **previous** caller's number still in it, and
parsed a network call as a local one built from one caller's leftovers and
another's dialling. The store is now cleared on release, on CLR and on the
no-digit timeout.

### `monitor.md` §3 — the seizure rule has a third term

Written up in that document as §3.3 and §3.4: a claim coming back is not a
seizure, and a claim is a request rather than a pulse. Both are invisible at the
end of a chain and show on every call at a transit.

### `mainboard.md` §2.3.2 — steering the probe costs a visit

With the control bus serial, `/BLK` is each block's own '138 on `DST[5:3]`, so
**the block that drives `PB` is the block the shift register names**. The marker
therefore cannot probe a block without first shifting a word naming it. That is
safe — §2.3.2's "nothing reads the outputs until `WR`" is what makes it safe,
and the marker shifts such a word with `WR` suppressed — but it is not free:

- the word takes 125 µs at 128 kHz and the visit it governs takes its first `PB`
  sample about 1 µs in, so **a re-point can never complete before the visit it
  is for**. The first visit of every block reads the previous block's `BUSY` and
  word, and in the port map that is `00`, `10` and the first line of every block
  of lines;
- so the marker needs an interlock that distrusts a visit disturbed by the
  serialiser, **and a scanner that can hold for one visit** and repeat it. About
  one visit a block: a 64-port scan goes from 8 ms to about 9;
- and once the scanner can stall, anything keyed on "a visit happened" must be
  keyed on **the scanner advancing**. Two things that were right with the
  parallel bus are not with this one: a "block turns over" trigger keyed on the
  octet mark and slot 7 — a stalled scanner sits *at* slot 7 and re-triggers for
  ever — and a hunt sweep that terminates on port 63, which a repeated visit of
  port 63 ends the instant it starts.

### `network.md` §3.1 — a hop is two scans, not 7 ms

§3.1's worked example budgets 7 ms for a seizure to cross an exchange. A scanned
marker cannot: it needs one scan to *see* the seizure at its visit, and the
forwarder needs a second to sweep for a free trunk in the other directions. At
eight ports a millisecond that is about **17 ms**, and it was 26 until the
forwarder was made to sweep from where the seizure was seen rather than from
port 63.

Nothing breaks — the origin's guard is 128 ms and the flood lasts seconds — but
§3.1's arithmetic should carry the larger figure, and a ten-hop network should
be costed at about 170 ms of seizure propagation rather than 70.

### `network.md` §3 — the forwarder must not wait for the marker

"A transit needs no matrix and no route table" and patches "two latches, and
forget". It must also **not wait on a register**: if forwarding shares the
marker's call sequencer, a seizure arriving while the exchange happens to be
setting up a local call is dropped, and the flood silently fails to reach part
of the network. In `verilog` the forwarder is its own small machine sharing the
scanner and nothing else.

### `protocol.md` §5 — the digit rule, taken literally

"A digit's value is the low three bits of the register's pulse count, forced to
000 when bit 3 is set: three AND gates." Implemented as anything looser — say,
"ten pulses means zero" — a dialled 9 in an address position reads as 1 instead
of 0. The document is right and exact; it is worth implementing exactly.

---

## 3. What `verilog` does not settle

- **Nothing about timing in a real part.** No gate delays, so §3.2's hazard
  cannot appear and §4's nanoseconds cannot be confirmed. `exch.py timing` and
  `exch.py mainboard` remain the only analysis of those.
- **Nothing about the line.** The subscriber interface is four wires — CVSD each
  way, M and E — with no differential Manchester, no phantom feed, no ringing
  current. `subscriber-line.md` is untouched.
- **No CVSD anywhere.** Speech is opaque bits, which is the design's own claim
  about the fabric, but it means the tone cards are pseudo-random patterns and
  nothing here hears anything.
- **The sizing tables are still arguments.** `NREG` and `NMON` are parameters
  now, so `monitor.md` §4's Erlang table can be *measured* against offered
  traffic. It has not been.
- **Still unbuilt**: fan-out and the resolvers of `network.md` §3.2, rings
  and the jumper (a jumper a direction, not an option bit; both halves of its rule are in, but
  nothing closes a loop), the conference bridge, data cards, outside lines,
  nailed-up connections, and every option bit of `extensions.md` §2.2 beyond
  a trunk's direction, glare and jumper.
