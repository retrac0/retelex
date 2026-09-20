# The exchange — SS0: a common signalling channel

Today the network speaks the **pulse flood**: the caller's own dial pulses. They go live down a flood
of seized trunks, and a monitor at every exchange reads the one digit it needs
(`exch-network.md` §3–4). **SS0 is the alternative.** The number crosses each
link as one message, on a channel of its own: the spare bit of the MF8 frame's S
lane. **Only the number moves.** Seizure, claim, ringback, busy and release stay
on the A lead, in band, exactly as they are.

This is the "second signalling system" that `exch-network.md` §9 set aside. It is
written up here so that the choice between the two can be made on numbers. The
name puts it below CCITT No. 6 and No. 7. It is not called CCS, because in
traffic engineering CCS means hundred call-seconds (`ex-extensions.md` §4).

> **Status: proposed, not adopted.** The numbers are `exch.py ss0`. They are
> arithmetic on the constants `flood` uses, plus binomial arithmetic for line
> errors. They are not a simulation of the gates or of a network (`net` does not
> exist). No circuit has been drawn, and nothing has been on a bench. SS0 would
> replace `exch-network.md` §3's pulses and `exch-monitor.md`, and it would leave
> the fabric, the marker's rules and the release rule as they are.
>
> **The numbering has since changed** to `h s` locally and `1 e b h s` across the
> network, with sixty-four exchange codes (`exch-network.md` §2). This document's
> message, its worked call and `exch.py ss0` are of the earlier numbering, in
> which every exchange shared `e`. §4 says what the message gains, and §1 and §7
> compare SS0 with the live flood as it now is.

---

## 1. What moves and what stays

| | the live flood | SS0 |
|---|---|---|
| **the number** | the caller's pulses, live on forward A down every seized trunk; a monitor at each exchange reads `e` and `b` | **one `SEIZE` message a link**, once all the digits are in |
| **trunks seized** | at the key `1`, every way the exchange faces, for every call that leaves, and held until `e` and `b` are in | at the last digit, and only if the code is another exchange's |
| seizure | forward A rises | the same |
| which trunk won | the claim: backward A = 1, steadily | the same |
| answer | at claim | the same |
| ringback, busy | in band, from the owner | the same |
| release | a fall of A through every patch | the same |
| which way the owner lies | learned from the claim | the same |

**Why forward only.** A message going backward ("answered", "busy") would have
to be relayed hop by hop. A transit relaying it must know which incoming channel
each outgoing channel is patched to. That map is in the transit's latches, and
nothing reads a latch back. Real common-channel signalling ran both ways because
a processor kept the map. Here the claim level already crosses every patch with
no logic at a transit. **For the same reason a call gets one message a hop**: a
transit could not tell which call a second message belonged to.

---

## 2. The bearer: the spare S bit

`mf8-spec.md` §3.5 recorded two ways of freeing one of the S lane's eight states
and recommended the complement pair: `[x][A1][A2][A3][/x][A4][A5][A6]`. That
frees **x, one bit a superframe: 8 kbps a link, and no voice channel spent.**

| | |
|---|---|
| **Idle is x = 0** | that is today's fixed guard: S is 0 at state 0 and 1 at state 4 (`mf8-spec.md` §2). A quiet SS0 sends exactly today's frame, and a converted trunk card facing an unconverted one reads an idle channel. Only messages themselves (x = 1) fail an old receiver's guard, so both ends of a link are converted before either sends |
| **Transmit** | x comes from a flip-flop loaded at the superframe edge, so state 0 and state 4 of one superframe always carry a matching pair. /x is one inverter. The trunk card already transmits in the exchange's clock (`exch-network.md` §1) |
| **Receive** | the A '259's Q0 holds x from state 0, and one XOR checks state 4 against it (`mf8-spec.md` §3.5). `MUTE` clears the '259, so a dead link reads x = 0, idle |
| **What it costs the frame** | a chance false acquisition in 1 of 28 attempts, where the fixed guard gives 1 in about 500 (`mf8-spec.md` §3.5) |
| **The pin** | x belongs to the trunk slot; its pin on the trunk card's connector is to be assigned. On a channel slot the `RAI` pin was reserved for this bit on the MF8 shelf; the exchange leaves it spare (`ex-extensions.md` §2.1), and a channel card never sees the S lane |
| **Remote alarm** | **Decided: x is the remote alarm on every MF8 link, and between exchanges it carries SS0 as well.** One rule serves both. An end holds x at 1 while its own receiver is not locked (`MUTE`), and a receiver takes x at 1 for 32 ms as the alarm. A message never holds x at 1 for more than 17 ms (the start bit and 16 data bits; the stop bit is 0), so a message never reads as the alarm. An SS0 receiver reads the alarm as a start bit with a bad stop bit, and discards it. A subscriber terminal (`exch-terminal.md`) or a plain MF8 link uses x for the alarm alone. The trunk card needs no strap: it sends `MUTE` OR its SS0 transmitter, and no message ever goes to a terminal, because the marker sends `SEIZE` only on a trunk. What the alarm does at the far end is not modelled |

The alternatives:
- **Give up channel 6** for 64 kbps. A link is then five voice channels, 1.36 E
  at 1 % blocking instead of 1.91, and a doubled direction carries 4.46 E instead
  of 5.88 (`exch.py ss0` 4).
- **Use a spare pair** on a copper tie between exchanges in one rack.

---

## 3. The line format

| | |
|---|---|
| framing | async, inverted to suit the guard: **idle 0, start bit 1, stop bit 0** |
| rate | **1 000 baud from the clock card's 1 kHz `TICK`**. Start, 16 data bits, stop: **18 ms a message** |
| receive | x crossed into the exchange's clock by two flip-flops on the 8 kHz superframe mark: **8 samples a bit**. A plesiochronous slip repeats or drops one sample, an eighth of a bit, and the next start bit re-times the receiver. Synchronous framing would lose a message at every slip |
| a data bit | **the majority of the middle five samples**: a count of ones, 3 or more |
| checks | odd parity over the 16 data bits; a bad stop bit discards the message |
| transmit | a message begins on a `TICK` and shifts one bit a `TICK` |

---

## 4. The message

```
  bit    15..13   12..10   9..7   6..4   3..1   0
         type     chan     b      h      s      parity, odd
```

| type | | |
|---|---|---|
| 000 | never valid | so a line stuck at idle never reads as a message |
| **001** | **`SEIZE`** | the only type the basic form needs |
| 010 / 011 | `BLOCK` / `UNBLOCK` *chan* | optional: take a channel out of service, and back. The receiver writes that trunk port's latch with `BUSY` set, so it is never hunted |
| 100–110 | reserved | `1` out of the network; a longer `SEIZE` that also carries the caller (§9) |
| 111 | never valid | so a line stuck at 1 never reads as a message either |

**`chan`** is the channel of this link, given as its slot: 1–3 or 5–7, the
same three bits as its position in the MF8 frame and its trunk port's slot
(`exch-protocol.md` §5). 0 and 4, F and S on the wire, are invalid. **`b h s`** is
the number after `e`, which every exchange of one network shared when this was
drawn. **With sixty-four codes the message carries `e` as well**, three bits as
`b` is, since both are octal: 19 data bits,
21 ms a message, and a third shift register in each receiver and transmitter
(`exch-network.md` §2). The last two fields carry either kind of number with no
translation at either end:

- **A line**: `h` is 2–7 and `s` is 0–7, as dialled.
- **A service key as the third digit**: `e b 0` for the operator, `e b 9` for the
  outside line, `e b 1` reserved. A conference is a number like any line
  (`exch-features.md` §7.4). `h` is 0 or 1, which
  no line has. `h`'s low bit and `s` together are the key's own 4-bit register
  code (`register.md` §4: 0 is `1010`, 8 is `1000`, 9 is `1001`, 1 is `0001`).
  So `e b 0` travels as `h` = 001, `s` = 010, and the far marker puts that code
  where a register's would go.

---

## 5. At each exchange

**A received `SEIZE` is a register that has finished.** Its caller is the trunk
port at slot *chan* of the group the link serves (01–03, 05–07 or 11–13,
15–17), and its digits come from the message. **The A lead must confirm it**: the marker acts
only if that trunk port's M is high (seized) and its latch is idle. Otherwise the
message is discarded. M rises about 2 ms after the far end seizes, and a message
takes 18 ms, so a genuine message always finds M up.

| at | does |
|---|---|
| **the origin** | the register already keeps all four digits (its '670 holds four). 128 ms after the last pulse: if `b` is ours, it is a local call and **no trunk is touched**. Otherwise, seize a free trunk in each direction there is, all listening to the caller so that forward A is the caller's hook, as now. Send `SEIZE` on each. Keep the one whose claim rises and release the others. No claim 2 s after the `SEIZE` → cannot-complete |
| **a transit** (`b` not ours) | hunt a free trunk in the other direction, write the two latches of the patch, and load that link's transmitter with its channel and the same `b h s`. A hub does this in each other direction and resolves the claim as the flood's hub does (`exch-network.md` §3.2). If there is no free trunk, no other direction, or the exchange is strapped NO-FORWARD, it does nothing: the incoming trunk stays seized until the origin lets it go |
| **the owner** (`b` ours) | parse the key or the line as a local call from the trunk (`exch-marker.md` §2). Free: two writes, `CLAIM` set, backward A = 1, the line rings. Busy or empty: trunk to cannot-complete, `CLAIM` set, as today (`exch-network.md` §3) |
| **a busy transmitter** | the marker waits for it: 18 ms at most |

**What goes:**
- **the monitors.** Nothing reads pulses on a trunk.
- **the origin's 128 ms guard**, which existed to protect the monitors' counting.
- **Nothing of the numbering.** `1 e b h s` stays. The key no longer opens
  anything early; it tells the register that a code and a line are coming.

**The parts, estimated by function:**

| | parts | ≈ |
|---|---|---|
| receiver, a link | two crossing flip-flops; a '393 for the sample phase and the bit count; a counter for the majority; 2 × 74HC595, whose output register holds the last message while the next shifts in; a parity flip-flop | 6 |
| transmitter, a link | 2 × 74HC165 loaded in parallel; a bit counter; parity | 4 |
| shared | the own-code compare (three XORs against the jumpers); type and validity decode; the transmitter's source mux (the register's store or a receiver, and the channel the hunt found) | 5 |
| trunk card | the x flip-flop, an inverter, an XOR | — |
| **an exchange with two trunk groups** | | **≈ 25**, against **≈ 38** for the monitors of two trunk blocks (`exch-monitor.md`) |

---

## 6. A call: 2144 dials 2355 on 21 ═ 22 ═ 23 ═ 24

Milliseconds from 44's last pulse (`exch.py ss0` 1). The origin is labelled 21 as
the model runs it. Under `exch-network.md` §2 no `b` can be 1, but nothing here
depends on the origin's own code:

```
     0   21   last pulse of 2 3 5 5
   128   21   the last digit is in; b = 3, not ours.  21 is at the end of the chain: one way to go
   130   21   a trunk toward 22 seized, channel k, listening to 44; SEIZE(k, 3 5 5) loaded
   131        the message begins on the TICK
   149   22   message complete; trunk k's M is high; b = 3, not ours
   156   22   patched to a free trunk toward 23, channel k′; SEIZE(k′, 3 5 5) loaded
   175   23   message complete; ours
   182   23   55 free: trunk ↔ 55, CLAIM, backward A = 1; 55 rings; ringback goes back in band
   185   21   backward A rises: 44 ↔ trunk
   187        44 hears ringback.  Post-dial delay 187 ms
```

Link 23–24 is never seized, and 24 hears nothing. Under the live flood the same
call held a trunk on 23–24 for about a second and a monitor at 22, 23 and 24
(`exch-network.md` §3.1).

**From the middle**, 2244 dials 2455. 22 seizes toward 21 and toward 23. 21 is
the end of the chain: `b` = 4 is not its own and it has nowhere to forward, so it
does nothing. 23 relays to 24, and 24 claims. 22 sees the claim about 187 ms
after the last digit and releases toward 21, whose trunk is free 256 ms later.
That wrong-way seizure is the only trunk SS0 ever holds for nothing.

---

## 7. The live flood against SS0

| | live flood | SS0 |
|---|---|---|
| signalling paths | **one**: A | **two**: A for supervision, the S lane's x for the number |
| change to MF8 | none | the complement-pair guard; both ends of a link converted |
| parts, two trunk groups | monitors, ≈ 48: two blocks of two, reading two digits (`exch-monitor.md` §6); ≈ 64 with three a block, which a network past about 400 lines wants | ≈ 25 (estimate), plus a flip-flop, an inverter and an XOR a trunk card |
| trunks held for nothing, a chain of four, 20 % of calls leaving | **≈ 0.08 E on every link**: every call that leaves floods 2.0–3.8 s by the code it calls, until `e` and `b` are in; a local call floods nothing (`exch-network.md` §4) | **≈ 0.002 E**; 0.006 at 50 % leaving (`ss0` 2) |
| how that grows | the flood's share rises with every exchange added: 0.65 E a link at twenty full exchanges, 1.2 E at thirty-six, which is what limits the network (`exch-network.md` §5, `Topology.md` §2) | only middle origins seize a wrong way, and only for tens of ms |
| post-dial delay, 1 to 7 hops | **132–140 ms**, and 133 ms at any distance | **160–324 ms**: 28 ms a hop (`ss0` 1) |
| when the number moves | digit by digit, while the caller dials | all at once, after the last digit |
| dialling pace | the flood must be up before the next digit: 242 ms of margin at 0.5 s between digits, and a faster caller fails | any pace the register reads |
| keypad phones across the network | no: the network hears only A | yes, with a DTMF register (`register.md` §7), which listens to the caller's `C` and so takes a port |
| a data terminal dialling | pulses `DTR` | the same |
| protection against a wrong number | the monitor's two rules: 0 false claims in 1 500 calls (`exch-monitor.md` §5) | parity, a 5-sample majority, invalid codes, and confirmation by A. At line error 1e−2, at most 0.012 wrong per million messages (`ss0` 3) |
| line errors | A is filtered on every card. Characters at 16 ms a bit crossed seven hops at 1e−2 with no errors (`exch-network.md` §9) | at 1e−2, 167 messages lost per million; each is a failed call, cannot-complete |
| link capacity, a direction at 1 % blocking | 1.91 E | 1.91 E on the S bit; 1.36 E if channel 6 is given over |
| out of the network | `1 8` and `1 9` are reserved; each level would claim one digit live | a reserved type or a longer message; area codes free |
| glare | residual glare joins two callers to each other | detectable: a `SEIZE` arrives for a channel just seized. The rule for it is not worked out (§10) |
| answer across the network | at claim | at claim (§9) |
| the largest network, 30 % leaving | 35 exchanges and 1 260 lines; 21 where the guard binds a tandem's chains | 39 and 1 404; 33 where the guard did (`Topology.md` §8) |
| trunks that are not MF8 | **any carrier that carries A**: a single-channel card, a copper tie, a voice-band circuit, a radio (`exch-network.md` §1.1) | the S lane, or a pair of its own |
| what is measured | the monitor's two rules, 0 false claims in 1 500 calls; the network call by call, `exch.py net` and `topo` | arithmetic only: `exch.py ss0`. No gate, no run |
| **a standalone exchange** | **nothing fitted** | **nothing fitted** |

In short: the flood is one signalling system, and it has already been measured.
SS0 is a second system and a change to the MF8 frame. Local calls touch no trunk
under either. What SS0 buys is a flood of a third of a second where the live one
lasts 2.7 s, so that adding exchanges adds almost no flood: it is the way past a
score of full exchanges. The number can also come from a keypad. It needs MF8
under it, where the live flood runs on any trunk that carries A
(`exch-network.md` §1.1).

---

## 8. A standalone exchange

**Neither is fitted.** A standalone exchange has no trunk blocks, no network card,
no monitors and no SS0 card. Its numbering jumper is at two digits, and nothing
in the fabric or the marker waits for any of them (`exch-network.md` §3, "Not
fitted"; `mvp-ex.md` §1).

What cannot be left out is **A inside the exchange**. A is not a network protocol
riding on the calls; it is the calls' supervision. Off-hook, ringing, ringback,
answer and release all reach the port's own supervision gate as M and E, and the
register reads dialling from M (`mvp-ex.md` §3). An outside line signals to its
central office on the FXO card, like a phone on its line card.

---

## 9. Where it stops being basic

- **Backward messages**, for true answer or busy with a cause, need a transit to
  map *k′* back to *k*. There are two ways. One makes the latches readable, a
  '244 a port onto a bus. The other addresses backward messages by the origin's
  number and has each transit relay anything not meant for it straight out of
  its other side. That works on a chain or a ring, where an exchange has two
  directions, but not on a mesh.
- **The caller's number**, for an operator's display, must ride in the one
  message a hop: a `SEIZE` of 25 data bits carrying both numbers, which is two
  more shift registers each way.
- **Flood search**, as MSE did it: a `SEARCH` relayed straight through, a `FOUND`
  back, and a trunk seized in one direction only. No trunk is then ever held
  for nothing, at the price of a round trip before seizing.
- **`1`**: the reserved types.

---

## 10. Not measured

- **All of it as gates**: the receiver, the transmitter, the marker's new source,
  and the x flip-flop's load at the superframe edge.
- **The complement-pair guard on a line.** `mf8-spec.md` §3.5 measured it at the
  frame layer.
- **Line errors are taken as independent.** x is one line bit in 64, so a burst
  shorter than 125 µs hits one sample. Longer bursts and a loss of frame are not
  modelled.
- **Glare.** Detection is easy. Resolving it without a fall of A at the winner,
  which the release rule would act on, is not worked out. The safe rule for now
  is that both ends give the channel up, so both calls fail and neither joins a
  stranger.
- **The network as a whole**: the second pass, `net`.
- **The loads** assume calls spread evenly over the other exchanges, one calling
  rate and rotary dials only.
