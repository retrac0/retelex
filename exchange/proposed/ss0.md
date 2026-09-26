# SS0: the number as one message a link

SS0 is the proposed alternative to the pulse flood (`network.md` §1). The
number crosses each link as one forward message on the MF8 frame's spare S
bit, x. Seizure, claim, ringback, busy and release stay on A exactly as they
are. SS0 would replace the network unit's monitor cells and the origin's guard,
and leave the fabric, the markers and the release rule alone. (Not "CCS",
which in traffic means hundred call-seconds.)

> **Proposed, not adopted.** Nothing drawn, nothing in RTL, nothing on a bench.
> Measured in: `exch.py ss0`, arithmetic on the flood's constants and binomial
> line errors, still with the retired 16-bit message and a marker's hunt (§9).

## 1. What moves and what stays

| | the pulse flood | SS0 |
|---|---|---|
| **the number** | the caller's pulses, live on forward A down every seized trunk; a monitor cell on each exchange's unit reads `e` and `b` | **one `SEIZE` message a link**, once the last digit is in |
| **trunks seized** | at the key `1`, one in every direction, held until `e b` are in | at the last digit, and only if `e b` is another exchange's |
| seizure, claim, ringback and busy in band, release on a fall of A | `network.md` §1 | the same |

**Why forward only.** A backward message ("answered", "busy") would have to be
relayed hop by hop, and a transit would have to know which incoming channel
each outgoing one is patched to. That map is in its latches, and nothing reads
a latch back; the claim level already crosses every patch with no logic at a
transit. **For the same reason a call gets one message a hop**: a transit could
not tell which call a second message belonged to.

## 2. The bearer: the spare S bit

The six-channel frame's S lane as the complement pair of `mf8/mf8-spec.md` §3.5,
`[x][A1][A2][A3][/x][A4][A5][A6]`, frees x: one bit a superframe, 8 kbps a
link, no voice channel spent.

**Decided, whether or not SS0 is built: x is the remote alarm on every MF8
link** (`mf8/mf8-spec.md` §3.5). An end holds x at 1 while its own receiver is
not locked (`MUTE`), and a receiver takes x at 1 for 32 ms as the alarm.

| | |
|---|---|
| **Idle** | x = 0, today's fixed guard: a quiet SS0 sends today's frame. Only x = 1 fails an unconverted receiver's guard, so both ends of a link are converted before either sends it, for the alarm or a message |
| **Beside the alarm** | a message holds x at 1 for at most 20 ms (the start bit and 19 data bits; the stop bit is 0), under the alarm's 32 ms, so one rule serves both. An SS0 receiver reads the alarm as a start bit with a bad stop bit and discards it. The adapter sends `MUTE` OR its transmitter, with no jumper; the unit sends `SEIZE` only on a flood trunk, so a terminal's link (`proposed/terminal.md`) carries the alarm alone |
| **Transmit** | x from a flip-flop loaded at the superframe edge, so states 0 and 4 of one superframe carry a matching pair; /x is an inverter. The adapter transmits in the exchange's clock (`trunks.md` §4) |
| **Receive** | the A '259's Q0 holds x from state 0, and one XOR checks state 4 against it. `MUTE` clears the '259, so a dead link reads idle |
| **Cost to the frame** | a chance false acquisition 1 in 28 attempts, against the fixed guard's 1 in about 500 (`mf8/mf8-spec.md` §3.5) |
| **The pin** | x is the adapter's, on its link side. A channel card never sees the S lane; socket a14 stays spare (`card-word.md` §1) |

Other bearers: **channel 6 given up** for 64 kbps, leaving five voice channels,
1.36 E at 1 % blocking instead of 1.91 (`exch.py ss0` 4); or **a spare pair**
on a copper tie, since the baseband and local trunks have no S lane.

## 3. The line format

| | |
|---|---|
| framing | async, inverted to suit the guard: **idle 0, start bit 1, stop bit 0** |
| rate | **1 000 baud on the 1 ms pass edge** (`SCAN5`, `common/clocks.md` §1); start, 19 data bits, stop: **21 ms a message**. A message begins on a pass edge |
| receive | x crossed into the exchange's clock by two flip-flops on the superframe mark: **8 samples a bit**. A slip repeats or drops one sample, and the next start bit re-times; synchronous framing would lose a message at every slip |
| a data bit, checks | the majority of the middle five samples; odd parity over the data bits; a bad stop bit discards the message |

## 4. The message

```
 field   type   chan   e    b    h    s    parity
 bits    3      3      3    3    3    3    1, odd          19 data bits
```

| type | | |
|---|---|---|
| 000, 111 | never valid | a line stuck at idle, or at 1, never reads as a message |
| **001** | **`SEIZE`** | the only type the basic form needs |
| 010 / 011 | `BLOCK` / `UNBLOCK` *chan* | optional: the receiver writes that trunk port's latch with `BUSY` set, so it is never hunted, and back |
| 100–110 | reserved | out of the network; a `SEIZE` that carries the caller (§8) |

**`chan`** is the channel's slot, 1–3 or 5–7, as in the MF8 frame and the trunk
port's number (`trunks.md` §4); 0 and 4 are F and S, and invalid. **`e b h s`**
is the number after the key. A one-key number after the code (0 or 9,
`numbering.md` §3) travels as `h` = 001, which no line has, with `h`'s low bit
and `s` the key's register code (0 is `1010`, 9 is `1001`: `register.md` §1).

## 5. At each exchange

**All of it is the network unit's** (`network.md` §3). The marker's side is
unchanged (key `1` raises `flood_go`, the register counts on); the unit acts at
the last digit instead of the key. **A received `SEIZE` stands for a finished
register** whose caller is the trunk port at slot *chan* of the link's group.
**A must confirm it**: the unit acts only if that port's M is high and its
`BUSY` clear. M rises about 2 ms after the far end seizes; a message takes 21 ms.

| at | does |
|---|---|
| **the origin** | at the last digit (`h s`, or a one-key number): own `e b` → a local call, no trunk touched; an `e` or `b` of 8 or 9 → cannot-complete. Otherwise seize a free trunk in every direction, each listening to the caller, and send `SEIZE` on each. Keep the one whose claim rises and release the rest. No claim 2 s after the `SEIZE` → cannot-complete |
| **a transit** | hunt a free trunk in every other direction (the unit's sweep), write the patch, and load each link's transmitter with its channel and the same `e b h s`. A fan-out holds a resolver until a leg claims, as for the flood. Never into a strapped link, nor onward from one (`network.md` §7). Nowhere to go: nothing, and the incoming trunk stays seized until the origin lets go |
| **the owner** | `CLAIM` on the trunk, and the call is local from the trunk to `h s` (`marker.md` §2). Free: two writes, backward A = 1, the line rings. Otherwise the trunk gets what a failed local number gets (`numbering.md` §4), `CLAIM` set |
| **a busy transmitter** | the unit waits for it: 21 ms at most |

**What goes**: the unit's monitor cells, since nothing reads pulses on a trunk,
and the origin's guard (`network.md` §6), which protects their counting.
**Nothing of the numbering goes**: `1 e b h s` stays.

| parts, by function | ≈ |
|---|---|
| receiver, a link: two crossing flip-flops, a '393 for sample phase and bit count, a majority counter, 3 × '595 holding the last message while the next shifts in, a parity flip-flop | 7 |
| transmitter, a link: 3 × '165 loaded in parallel, a bit counter, parity | 5 |
| shared: the own-code compare against the unit's `e b` straps, type and validity decode, the transmitter's source mux | 5 |
| each adapter: the x flip-flop, an inverter, an XOR | — |
| **two trunk groups** | **≈ 29** |

## 6. A call: line 44 of 21 dials `1 2 3 5 5` on the chain 21 ═ 22 ═ 23 ═ 24

```
 21   last digit in, 128 ms after its last pulse; 23 is not ours; one way to go.
      A trunk toward 22, channel k, listening to 44; SEIZE(k, 2 3 5 5) loaded
 22   message in; k's M high; not ours.  A free trunk toward 23, k′, patched to k; SEIZE(k′, …)
 23   message in; ours.  55 free: trunk ↔ 55, CLAIM, backward A = 1; 55 rings, ringback in band
 21   backward A rises: 44 ↔ trunk.  44 hears ringback
```

Link 23–24 is never seized. Under the flood the same call holds a trunk on
23–24, and a monitor cell at 22, 23 and 24, until `e b` are in. **A hop is
about 35 ms**: the 21 ms message and the unit's ≈ 12 ms hunt and writes
(`network.md` §6), more when the unit is already sweeping. Not re-run.

**From the middle**, 22 calling 24 seizes toward 21 as well. 21 has neither the
code nor anywhere to forward, and does nothing; 22 releases it at the claim.
That wrong-way seizure is the only trunk SS0 ever holds for nothing.

## 7. The pulse flood against SS0

| | pulse flood | SS0 |
|---|---|---|
| signalling paths | **one**: A | **two**: A, and x for the number |
| change to MF8 | none beyond the complement pair the alarm needs (§2) | the same |
| parts | the unit's monitor cells: not counted (§9) | ≈ 29, and three gates an adapter |
| trunks held for nothing, a chain of four, 20 % leaving | **≈ 0.08 E on every link**: each call that leaves floods for 2.0–3.8 s | **≈ 0.002 E**; 0.006 at 50 % (`exch.py ss0` 2) |
| as exchanges are added | the flood grows, and limits the network (`analysis/topology.md` §2) | only a middle origin's wrong way grows |
| post-dial delay | ≈ 133 ms at any distance | ≈ 130 ms plus ≈ 35 ms a hop |
| dialling pace | the flood must be up before the next digit (`network.md` §6) | any pace the register reads |
| keypad phones across the network | no: the network hears only A | given a DTMF register, which the design lacks |
| a wrong number | 0 false claims in 1 500 calls (`analysis/monitor-rules.md` §5) | ≤ 0.012 a million messages at line error 1e−2; 167 a million lost, each a failed call (`exch.py ss0` 3) |
| a direction at 1 % | 1.91 E | 1.91 E on x; 1.36 E on channel 6 |
| the largest network, 30 % leaving | 35 exchanges, 1 260 lines; 21 where the guard binds | 39 and 1 404; 33 (`analysis/topology.md` §8; to re-run, §9) |
| measured | the monitor's rules; `exch.py net`; the unit in RTL (`tb_net`, `tb_chain`) | arithmetic only |
| a standalone exchange | nothing fitted | nothing fitted |

The flood is one signalling system, built, and runs on any carrier that
carries A (`network.md` §2). SS0 is a second, on MF8's x or a pair of its own,
and buys a seizure held for tenths of a second where the flood's is held 2.7 s:
adding exchanges then adds almost no flood, the way past a score of full
exchanges. Neither replaces **A inside an exchange**, which is the calls'
supervision, not a network protocol.

## 8. Beyond the basic form

- **Backward messages** (true answer, busy with a cause) need a transit to map
  *k′* back to *k*: readable latches (a '244 a port onto a bus), or messages
  addressed by the origin's number and relayed out of the other side, which
  works on a chain or a ring but not a mesh.
- **The caller's number**, for an operator's display, rides in the one message:
  a `SEIZE` with the caller's `e b h s` too, 31 data bits, which could hold x at
  1 for 32 ms, the alarm's own threshold.
- **Flood search**, as MSE did it: a `SEARCH` relayed through, a `FOUND` back,
  and a trunk seized one way only, at the price of a round trip before seizing.

## 9. Open

- **`exch.py ss0` is not of this design**: it sends a 16-bit message (18 ms)
  and hunts on a marker (28 ms a hop). Every figure credited to it above
  wants re-running for 19 bits and the unit's sweep.
- **The parts comparison has one side.** The monitor cells SS0 would remove
  (each a probe, a `pulse_rx` and a two-digit compare, on the unit) have not
  been counted. Earlier counts of ≈ 24 a block, ≈ 38 and ≈ 48 were for
  per-block monitors, which no longer exist. §7's parts row waits on it.
- **The owner's hand-off.** The owner's marker must take `h s`, or a key's
  code, from the unit where a register's digits go: a second source on the
  register ribbon (`register.md` §3). Not designed.
- **Glare** (which joins two callers under the flood, `network.md` §5) shows as
  a `SEIZE` for a channel just seized. Resolving it without a fall of A at the
  winner is not worked out; for now both ends give the channel up.
- **The largest networks** (`analysis/topology.md` §8) were sized on a 12 ms
  flood hop; the slow hop is now ≈ 22–30 ms, with a resolver taken at every
  transit (`network.md` §6). Both move the guard-bound shapes in SS0's favour.
- **Not measured**: any of it as gates; the complement pair on a line (measured
  at the frame layer only); what the remote alarm does at the far end; bursts
  longer than 125 µs, and loss of frame (line errors are taken as independent);
  uneven calling and keypads (the loads assume even calling and rotary dials).
