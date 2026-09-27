# The register

The register counts a caller's dial pulses into a store the marker reads: its
three windows and its timers, the circuit, the ribbon it speaks, and how many
an exchange wants. How the windows were measured is `analysis/dialling.md`.

> **Built:** `newimpl/rtl/pulse_reg.v`, `pulse_rx.v` (`tb_dial`, and in use in
> `tb_mini`, `tb_net`, `tb_max`); one in every build. **Not built:** a pool.
> **Measured in:** `analysis/dialling.md` (`sim/subline.py register`, `dial`);
> `sim/exch.py calls` 18 for §4.

---

## 1. What it is

**Dialling is pulses on A, and the register is not a line: it takes no
port.** It counts breaks in its caller's M and nothing else: no audio, no
trim, all 74HC. A DTMF receiver would need the caller's C, which only a port
carries, and could place local calls and no others, since the network hears
only A and a caller's own pulses cross it live; none is fitted.

The register reads its caller's M itself, off `/HA` through a probe of its own,
once a pass: every edge it measures is quantised to 1 ms. It makes three
decisions from one timer on the 1 kHz tick, reset whenever M changes:

| decision | window | must be yes for | must be no for |
|---|---|---|---|
| is this break a pulse? | **HIT: break ≥ 8 ms** | the shortest dial break: 46.7 ms at 12 pps 56 %, 28 ms at 20 pps | a hit the line card's detector passed |
| does this make end the digit? | **ID: make ≥ 128 ms** | the shortest pause between digits, ≥ 720 ms from a phone to ES 201 187 | the longest make inside a digit, 62.9 ms at 7 pps 56 % |
| is this break a hang-up? | **CLR: break ≥ 256 ms** | anything held on-hook | the longest dial break, 102.9 ms at 7 pps 72 % |

It is designed for **7–12 pps at 56–72 % break** and takes 20 pps. ID is also
the post-dialling delay: the last digit is known 128 ms after the last break
ends. The tightest ratio is HIT's: the shortest break ever measured, 18 ms at
20 pps, is eighteen samples against eight. 3 200 dialled digits, none wrong,
and where each window gives way: `analysis/dialling.md`.

- **A break is counted once**, when it has lasted HIT. A make that lasts ID
  with a count in hand completes the digit. A break that lasts CLR is the
  caller gone: `gone` rises and stays.
- **The count is binary, 1 to 15, and stops at 15.** Ten pulses is `1010`,
  which is also an MT8870's code for 0. The store keeps the counts as counted;
  the marker applies the digit rule (`numbering.md` §1). **Four digits deep**,
  so that the network key and an own code can be consumed by restarting the
  store and `e b h s` still land in slots 0–3.
- **A flash is a digit 1**, and a longer one a hang-up. Nothing offers recall.
- **The no-digit timer, `NODIG` = 10 s**, counts the tick whenever the
  register is attached. It is cleared at attach, at `restart` and at every
  completed digit, and runs straight through a digit in progress: a line that
  pulses without ever making for ID — a bad dial, a loose jack — would
  otherwise hold the register for ever, and the longest real digit, a 0 at
  7 pps, is about 1.5 s. At 10 s `nodig` rises and stays.
- **`steady`**: a make that has stood `SETTLE`, 32 ms, with no break since.
  **`settled`** = attached · `steady` · the no-digit timer past `SETTLE`: the
  caller off-hook `SETTLE`, counted from the last restart. The marker's watch
  reads it (`marker.md` §5).
- **The store is empty whenever the register is idle**: cleared on attach and
  on release, and the collector held clear while unattached. A marker that
  read a store a tick after attaching would otherwise find the last caller's
  number in it.
- **It arms at the first sample of its own caller.** Re-pointed at attach, the
  probe holds the port it watched before for up to a pass, often a 0, which is
  a break; at a HIT strapped as low as 1 ms that stale sample would count
  (F10).

---

## 2. The circuit

Not drawn and not counted. By block, as `pulse_reg.v` and `pulse_rx.v` have it:

| block | parts |
|---|---|
| probe on the caller | a '688 comparing `SCAN` with the held port, half a '74 holding M from that port's bit-time (`fabric.md` §3); half a '74 more, `seen`, to arm at the first sample of the caller's own |
| the tick | `TICK`, the fall of `SCAN5`: one gate on `SCAN` and the frame edge |
| the port held | a '174 loaded at attach |
| M as it stood, and the edge | a flip-flop on the tick; the timer's reset is the edge |
| timer | a '4040 on the tick, reset by the edge: Q4 = 8 ms HIT, Q6 = 32 ms `SETTLE`, Q8 = 128 ms ID, Q9 = 256 ms CLR |
| this break counted, the last event a digit | two flip-flops, '74 |
| pulse count | a '163, four bits, stopping at 15; restarted at 1 by the first pulse after a completed digit |
| store | one '670, four digits of four bits, and a digit index |
| no-digit timer | a second counter on the tick, and its compare (§5) |
| gating | `counting` = count ≠ 0 and not a completed digit; `gone`, `nodig`, `settled` |

`counting` falls one gate after the digit strobe, not with the '163's clear,
because the store samples the count in the strobe's own tick.

---

## 3. The ribbon to the marker

Every line the register drives is a **level held until the other side has seen
it**, except `brk`. An event on a wire is a race.

| from the marker | |
|---|---|
| `attach` + `attach_port` | one tick: seize this register for this caller. Clears the store and the timers |
| `release` | clear the store and go free |
| `restart` | begin the store again, the caller unchanged, and clear the no-digit timer. The network unit's `restart` is ORed with the marker's |

| from the register | read by |
|---|---|
| `busy` | attached. The marker; the unit |
| `port` | the caller. The unit |
| `ndig`, `digits` | how many digits are in (0–4), and the four counts. The marker; the unit |
| `gone` | CLR: the caller hung up, or the pair is cut. The marker; the unit |
| `nodig` | the no-digit timeout. The marker; the unit |
| `brk` | one tick a counted break: the origin's guard reads it (`network.md` §6) |
| `settled` | the watch after a connect (`marker.md` §5) |
| `counting`, `hook` | a digit part-collected; the caller's M as the probe has it. For a lamp field |

The network unit taps the ribbon and never sits in the register. A register
that speaks this ribbon can replace another. The mini marker keeps its one
register on its own card, with `busy`, `port`, `ndig`, `digits`, `gone`,
`nodig` and `brk` brought out for the unit; in `top_max` the register is a
card beside the class marker, on these wires.

---

## 4. How many

**One is built for callers**: inside the mini marker, or one register card in
`top_max`. A caller who finds no register free is not refused: dial tone is
late. **With a network unit, `top_net` fits a second, the claim register**: a
stock register card on this ribbon that only a claimed trunk is given
(`marker.md` §4.8). A busy register delays a local caller; it *loses* a claim,
whose far caller is already dialling. Sharing one, 9–16 % of incoming network
calls were refused at design load (48 lines, 3 calls a line an hour, 30 %
leaving), and past about one attempt a second two exchanges refused each
other's claims until neither carried a call (`newimpl/flood-study/REPORT.md` §2–§3). The claim register
is refused only while it is on another claim. Measured at 8× on two exchanges
of 48 lines, every call leaving (`tb_fl_load`'s harness, against the study's
runs on the old tree): claims refused 50 % → 14 % at 0.5 attempts a second an
exchange, 93 % → 28 % at 1.8, 97 % → 26 % at 3.2, where carried calls went from
none to 72 a minute an exchange and the eight trunks became the limit. Every
refusal traced was the same origin's next network caller: freed at the claim,
it dials `1 e b` in about the time the previous caller dials `h s`, and its
claim meets the claim register still collecting those. A claim cannot wait for
it — attached late it misses the start of `h` and rings the wrong line
(`F58`) — so the cure is a second claim register (§5).

48 lines, 200 000 calls a cell, holding time from lift to last digit
(`sim/exch.py calls` 18):

| calls / line / h | holding, s | erlang | registers | delayed | mean wait of those | wait > 3 s |
|---|---|---|---|---|---|---|
| 3 | 4 | 0.16 | 1 | 16.0 % | 2.6 s | 5.7 % |
| 3 | 4 | 0.16 | **2** | **1.2 %** | 1.4 s | **0.1 %** |
| 3 | 10 | 0.40 | 2 | 6.5 % | 3.9 s | 3.6 % |
| 3 | 10 | 0.40 | 3 | 0.8 % | 2.7 s | 0.3 % |
| 10 | 4 | 0.53 | 2 | 10.9 % | 1.7 s | 1.7 % |
| 10 | 4 | 0.53 | **3** | **1.7 %** | 1.1 s | **< 0.1 %** |

4 s is a keypad's holding time and 10 s a dial's. **At 48 lines: two
registers for keypad phones, three for dials or a busy exchange.** At eight
lines, three calls each in the busy hour and 10 s a call, one register makes a
caller wait about 11 s one time in 15, and two one time in 465 (arithmetic,
not a run). The same three pool sizes on the retired tree's 48-line stress
bench moved completed calls from 9 to 12 to 18.

The model hands a register out at the lift. On `top_max` the walk adds up to
a round, about 250 ms, before a caller is seen, and every connect holds its
register 32 ms more for the watch; neither is in the table.

---

## 5. Open

- **A pool is not built.** The marker follows one call and the unit has one
  origin bank. The claim register is the pool's first member with its hardest
  parts left out: it never originates, so it needs no origin bank, and never
  takes a local caller, so the two never race for a line; its call state is
  its own sequencer's (`marker.md` §2). A pool of callers' registers still
  needs: a bank a register on the unit for the trunks an origin seizes; a
  call's state kept with its register, not in the marker; an owner and a
  queue for the one reader's hunt, released by a caller who hangs up
  mid-hunt; the key consumed the moment it is read; and glare between
  registers — two finishing on one number in the same instant must not both
  write its latch: the first takes the line, the second is told busy. With a
  pool, a claim could take any free register and the claim register become
  one of them. Blocks sizing beyond one register for callers.
- **A second claim register.** One refuses the back-to-back claims of a busy
  pair of exchanges (§4): 14–28 % at 8× with every call leaving. A second is
  the same card and a second K_ sequencer, or the pool's first step.
- **The no-digit timer as parts.** 10 s is not a binary tap of the 1 kHz
  tick: the nearest are 8.2 s and 16.4 s. A tap or a compare; not decided.
- **The measured corner at 1 kHz.** `tb_dial` dials the nominal envelope's
  corners through `/HA`; nothing drives the measured 18 ms break at 20 pps
  through the 1 kHz plane, nor a pulse relayed across exchanges, each of which
  re-samples it at 1 kHz.
