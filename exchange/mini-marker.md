# The exchange — the mini-marker: one register, local calls, and a network unit's hooks

A marker that makes local calls on a single exchange: two phones dial `h s`,
one rings, they talk, either hangs up, and nobody is in charge of the call. It
reads **M and `BUSY`**. It does not hunt a class. One pulse collector lives
**inside** it.

It is also the marker of a network exchange. Fit a network unit beside it and
the same card hands key `1` to the unit, reads a port's card word before it
takes a caller or connects one, and gives a claimed trunk its register (§8).
Take the unit out and none of that happens: the unit's presence is one line,
`/NET`, and not a jumper, so a minimal exchange pays nothing for the network
half but the parts on the card.

It is a marker, not a parameter of the marker of `marker.md`. Cards stay. You
may unplug it when a class marker and its register pool go in. You may also
leave it fitted beside a network unit, which is a pulse-flood exchange
(`common-control.md` §4). The ribbons are the same either way.

This is also not the outpulsing register-sender `network.md` §9 set aside.
The "register" is `register.md` §4's pulse collector (`pulse_reg` in RTL),
the same listener. Its `restart` is live only with a unit fitted: key `1` and
the unit's own-code restart are then the only things that consume a prefix.

This document absorbs `nano-marker.md`, the one-board form, as §10. The retired
text is at commit `63bafbb`.

> **Status: built in RTL and measured in simulation.**
> `newimpl/rtl/mini_marker.v` is fitted alone in `top_min` and beside a
> network unit in `top_net` (§7).
> - `make mini` (35 checks): 20 calls 21:
>   seize within a pass, dial tone, `2 1`, ringback, ringing in cadence,
>   answer, voice both ways, and 21 hanging up first. Then §5's wrong numbers,
>   among them **`2 8` refused on the second key** and **key 1 as highway 1**
>   with no unit fitted.
> - `make net` (two exchanges, 15 scenarios, 76 checks) and `make chain`
>   (three, 4 scenarios, 32 checks) run it with a unit (§8).
> - Not run: 21 calling 20, 20 hanging up first, §5's "already in a call"
>   row, a tone trunk arriving at a central (§9), and a hub, a ring or an MF8
>   link.
> - Nothing has been on a bench.

---

## 1. What is fitted

```
 phone ── line card, slot 20 ──┐
                               ├── block 2 ── /HA, /HB ── mini-marker
 phone ── line card, slot 21 ──┘                           (probe, sequencer,
 clock card ── SCAN, SLOTQ, TICK, FILL, RING_CAD            one register, cable B)
```

Tone cards at 01 and 03 are optional. The mini-marker **addresses** them; it
does not hunt a class. With none fitted, seize and cannot-complete write the
caller's latch at those numbers anyway, and the caller hears silence — the
same as `mvp.md` §2.

**The scanner is not this card's.** It is six stages of the clock card's
divider, free-running at a port every 15.63 µs and a pass every 1 ms, with no
enable that anything could clear (`newimpl/README.md` §1). This card holds one
probe on `SCAN` and takes a port when it happens to find it free.

**Not fitted, and not missed for local calls:** a class matrix, a hunt, a
second register, trunks, monitors, a network unit, nails, answers-to, a
console, event words. §8 is what a network unit adds without replacing this
marker. The card's word reader is fitted in every build and used only when
`/NET` is low. On a minimal build nothing reads `/HW`: the marker never points
at a port to read it.

---

## 2. Seizure and the free test

A call request is **M and not `BUSY`**. That is the whole rule on an exchange
with no unit. The probe (`probe.v`: a comparator on `SCAN`, and flip-flops
that hold M and `BUSY`) follows the scanner. It captures M off `/HA` and
`BUSY` off `/HB` in each port's own bit-time, so it offers the marker every
port once a pass. The marker takes the first that asks while the register is
free and cable B is idle. **A port it could not
take comes round again 1 ms later.** Nothing steers the scanner, so no port's
turn is ever repeated or skipped. The marker's own probe may be held on one
port (§4, §7).

It acts on the probe's latched port, **never on live `SCAN`**. By the time the
sequencer has decided, the scan has moved on (`rtl.md` §1).

| what a class marker reads the word for | here, alone | here, with a unit (§8) |
|---|---|---|
| class line / operator / restricted → register | any free off-hook port gets the register | the same |
| class source, trunk, nail | not distinguished. A source never raises M, so it is never a caller. Do not fit a trunk or a ring source | a flood trunk's M is the unit's, never a caller. A tone trunk is a caller (§9) |
| busy-out, priority | ignored | ignored |
| empty slot (no word) | looks like an idle on-hook line | the same when dialled. A port whose word is NONE is never taken as a caller |

**Dial only fitted ports.** An empty slot reads `M = 0`, `BUSY = 0`, so a
number that lands there is treated as free. The caller is pointed at it, the
write to the empty latch is ignored if no port circuit is populated, and the
caller hears silence. That is acceptable on a jig; it is why a class marker
reads the word for a dialled port's class.

A second lift while the register is held is offered again every pass, and
taken once the register is free. After release, an idle off-hook port is a
new call request. **The marker does not go back to IDLE with writes still
queued.** The caller's `BUSY` is what stops it being seized a second time. A
word takes 133 µs and the port comes round every 1 ms, so idling early would
seize the same caller twice.

With a unit fitted, the marker first reads the port's card word. It takes the
port at its next turn if the port is still asking (§8), so dial tone comes
about a pass later than on a minimal build.

---

## 3. Reading a number

Two digits, octal as dialled. A digit's value is the low three bits of the
pulse count, forced to 000 when bit 3 is set (`protocol.md` §5). So ten pulses
read 0, and so do 8, 9 and 11–15, which is why the first key tests all of them
as one.

On the second key ten pulses is 0, an address, and 8, 9 and 11–15 are
cannot-complete, **never folded onto 0**. A folded `2 8` rang 20: a wrong
number, and from another exchange one the caller cannot see. This rule holds
in every build (decided 2026-09-25). `newimpl/faults.py` F09 puts the fold
back, and `tb_mini` goes red.

Digit `1` is a **highway**, not a prefix: no `restart`, no flood, no `e b`.
With a network unit fitted it is the flood key instead (§8).

```
 first key   1–7   highway h; drop dial tone (caller listens to 00); wait for s
             0, 8, 9, 11–15   cannot-complete
             1, unit fitted   the flood: §8
 second      0–7   called = h s; probe that port
             8, 9, 11–15  cannot-complete, never folded onto 0 (protocol.md §5)
 called      self, or M, or BUSY → cannot-complete
             else → two writes, register released, mini-marker done
```

Tones are addresses, not hunts:

| | write |
|---|---|
| seize | caller ← 01, `BUSY` |
| first highway digit | caller ← 00, `BUSY` (dial tone off) |
| cannot-complete | caller ← 03, `BUSY` |
| connect | caller ← called, then called ← caller, both `BUSY`. Queued in one tick, and nothing of this card's comes between them |
| abandon (hung up before the connect) | caller ← 00, `BUSY` clear |

A claimed trunk's writes carry `CLAIM` too, up to its release: the abandon
clears `BUSY` and `CLAIM` together (§8).

There is no busy-tone port. Busy, self, and a bad key all get 03. With
no source card at 03 the caller hears silence and hangs up.

The register arms at its caller's first sample. It counts breaks off `/HA` on
the 1 kHz tick and lets go on CLR (256 ms of M down). It gives up after the
no-digit timeout, 10 s (`marker.md` §5.1), which runs from the seizure and
from the last digit. `marker.md` §8 states that rule and lists it as not
measured there; `pulse_reg.v` keeps it.

Ringing, answer, and release are the ports' (`marker.md` §5). The mini-marker
has already left.

---

## 4. A call

20 calling 21, rotary 10 pps, as `mvp.md` §3, with a register that lives on
this card rather than as a pool member.

```
 20 lifts             M on /HA in 20's bit-time, BUSY clear on /HB.  The probe
                      offers it within 1 ms.  The register attaches to 20.
                      20 listens to 01.
 dial 2 1             the register counts 20's breaks off /HA
                      first digit 2: 20 listens to 00
                      second digit 1: called = 21
 20 ↔ 21              the probe holds 21 until its turn: on-hook, not busy.
                      two writes.  the register is free.  the mini-marker is
                      done once both words are on the wire
 21 rings             on-hook · E, in RING_CAD.  20 hears ringback, not 21's card
 21 answers           M rises; ringing drops.  Nothing else acts
 hang up              256 ms of M or E down, the port clears its own latch
```

The other way, 21 calling 20, is the same. Hang up in either order; the ports
release themselves. The party left off-hook with an idle latch is a new call
request.

With a unit fitted, the same call costs this marker two word reads: 20's
before it is taken, and 21's before it is connected. The unit reads 20's word
as well, and first, because it outranks the marker. So cable B carries three
reads of about 250 µs each.

---

## 5. Wrong numbers

| 20 dials | mini-marker |
|---|---|
| 0, 8, 9 | cannot-complete on the first digit |
| 2 8, 2 9 | cannot-complete on the second digit |
| 1 then hang up, no unit fitted | 1 was a highway: dial tone went off; no flood |
| 2 0 | itself, busy → cannot-complete |
| 2 1 while 21 is already in a call | 21 busy → cannot-complete. **No bench runs this row** |
| 2 5, no port circuit at 25 | treats 25 as free; 20 is pointed at it and hears silence |
| hang up mid-dial | the register lets go on CLR (256 ms). No latch left pointing at 03 |
| off-hook, nothing dialled | cannot-complete after the no-digit timeout; 20 stays busy until hung up |

The rows a unit adds are in §8.

---

## 6. What it will not do on its own

- Hunt a class, or follow a nail or an answers-to. It reads a card word only
  with a unit fitted: to tell a flood trunk or an absent card from a caller,
  and to refuse a dialled flood trunk (§8).
- Treat `1` as `1 e b h s` **until a network unit is fitted** (§8). Standalone
  numbering still has 10–17 as lines; this marker will complete `1 s` if that
  port is free.
- Share cable B with a console. It yields the bus to a network unit's `/UREQ`
  and to nothing else. Bring-up with the console is `mvp.md` §6.3 (latches by
  hand) and does not need this marker.
- Hold more than one caller. A second phone waits for the register.
- Become the class marker by adding jumpers. The class marker is a different
  card. Fit it, and unplug this — or don't: a network unit does not need the
  class marker.

---

## 7. RTL

`newimpl/rtl/mini_marker.v`, one card:

| part | RTL | |
|---|---|---|
| the probe | `probe.v` | a comparator on `SCAN`, and flip-flops that hold M and `BUSY`. It offers every port once a pass, or holds one port |
| the register | `pulse_reg.v`, `pulse_rx.v` | §3. Its ribbon is brought out (`common-control.md` §2.1) |
| cable B | `ctl_queue.v`, `ctl_write.v` | eight words deep, one serialiser. **The queue is a model part**: on a board the sequencer holds until its word is away (`newimpl/README.md` §6) |
| the word reader | `word_rx.v`, in `ctl_queue` | a pointing word, then eight frames of `/HW`. Used only with `/NET` low |

It is fitted in `top_min.v`, with the network half tied to "no unit", and in
`top_net.v`, beside `net_unit.v`. The network half is tagged `// NETWORK`.
Two rules are not optional. Act on the probe's latched port, never on live
`SCAN`. Do not return to IDLE with writes still queued (§2). States:

```
IDLE    M · /BUSY, register free, bus idle:
          no unit → dial tone → COLLECT
          unit    → READ the port's word
READ    a caller's word:  trunk or NONE → IDLE;  else → TAKE
TAKE    its next turn, still asking → dial tone → COLLECT;  else → IDLE
COLLECT h, then s → PROBE (no unit) or READ (unit)
        bad key, no digit → 03, DRAIN
        key 1, unit → dial tone off, restart, flood_go → YIELD
READ    a called port's word:  trunk → 03, DRAIN;  else → PROBE
PROBE   the called port's turn:  self, M or BUSY → 03;  else the two writes;  → DRAIN
YIELD   local → COLLECT;  done → DRAIN;  nogo or no digit → 03, DRAIN
        in COLLECT, PROBE and YIELD a hang-up is looked at first:
        → 00, BUSY and CLAIM clear, DRAIN
DRAIN   queue empty → IDLE
        and from IDLE, TAKE or DRAIN, register free: the unit's claim →
        COLLECT, with the trunk as the caller
```

`make mini` is the bench without a unit (`tb_mini`, on `top_min`). `make net`
and `make chain` are the benches with one (`top_net`). `newimpl/faults.py`
puts back, one at a time, the faults this card's rules exist to prevent, and
each must turn a bench red:
- F09, the second key folded onto 0 (`mini`);
- F10, the register armed before its probe has the caller's first sample
  (`net`);
- F14, key 1 read as the flood with no unit fitted (`mini`);
- F21, a second key after the call's own code sending a second flood (`net`);
- F05b, a flood trunk's M taken as a caller (`net`). F05 alone stays green,
  because the unit's hold keeps the trunk from being a caller as well, so
  F05b removes both;
- F03b, the claim refusal landing before the unit's `CLAIM` word (`net`).
  F03 alone stays green, because the rank on `/UREQ` still orders the words,
  so F03b also makes the marker deaf to `/UREQ`.

The probe is also brought out on the tap (`probe_port`, `probe_m`,
`probe_busy`, `probe_fresh`; `common-control.md` §2.2). A watcher must use
`probe_fresh`, because the levels hold for a whole pass. The tap also freezes
on the called port in PROBE and TAKE, so a listener should fit its own probe,
as the unit does.

The retired tree's `make mini-net`, `mini-load` and `mini-leaf` (in
`old/verilog/Makefile`) have no newimpl counterpart beyond `net` and `chain`.

---

## 8. With a network unit

The ribbons of `common-control.md` §2.2. This marker does not grow a flood
sequencer. It grows the **hooks** a unit needs, on the same card, and live
only while `/NET` is low:

| | |
|---|---|
| presence | `/NET`: the unit card grounds it, and it is pulled up here. No parameter and no jumper (`newimpl/STYLE.md` §4) |
| key `1` | consumed at once: the store is restarted so `e b h s` land in slots 0–3, dial tone goes off, `flood_go`. The unit owns the call; the marker waits in YIELD |
| YIELD | the unit says `local` (the call's own code: the store is restarted again and `h s` follow as a local number), `done` (it wrote caller ↔ trunk; the register is freed) or `nogo` (→ 03). A hang-up is abandon, as ever |
| a second `1` | after the call's own code, or from a claimed trunk: cannot-complete. After the own code, `h = 1` would be the trunks' highway, and ports 10–17 are never dialled on a networked exchange (`protocol.md` §5). A claimed trunk's flood would go back up the link it came in on |
| the word | read before a port's M is taken as a call, and before a dialled port is connected: a pointing word, then eight frames of `/HW`, about 250 µs of cable B. **The card says what it is.** Nothing on this card or the unit's says it for the card |
| a flood trunk (class *trunk*: family 01, member 0, `11 01 0` in wire order; `extensions.md` §2.2) | never a caller: its M is the unit's. Never dialled: cannot-complete |
| NONE, all zeros | a card held off by its power-up RC, out of service, or a trunk whose link is down. Never a caller. Dialled, it is an empty slot, and is connected as §2 says |
| a tone trunk (the same family, member 1) | a caller like a line: a leaf's uplink arriving at its central (§9) |
| claim attach | the unit, having written a trunk's `CLAIM`, holds `att` until this marker gives the trunk the register: a caller with no dial tone, taken ahead of any local caller, with `CLAIM` on every later write to it up to its release (the abandon clears it with `BUSY`). With the register busy the marker instead writes trunk ← 03, `BUSY` and `CLAIM`. The unit raises `att` only once its `CLAIM` word has gone out, so the refusal lands after it |
| cable B | the unit is a second master, ranked above this one. With `/UREQ` low the marker lets go between transactions. There is no grant: the unit waits 1152 ticks, longer than the marker's longest transaction (a word read). The marker's queue holds its words meanwhile |
| the register's ribbon | the unit taps the digits, the count, `brk`, `gone`, `nodig` and the caller. Its `restart` is ORed with the key's |

The unit itself is `network.md` and `newimpl/rtl/net_unit.v`: holds on
incoming seizures, the forwarder, the trunk hunt, the monitors and the
resolvers. **The monitors are cells on the unit card**, not cards on the
trunk block. The link is the baseband tie card (`baseband.md`); MF8 comes
later.

A two-exchange network is this marker and a unit at each exchange, and a tie
card at each end of every link. `make net` fits two links (A11–B11 and
A12–B12), plus a trunk card at A25 looped to itself so that a dialled trunk
has a word to be refused on. `make chain` adds a transit. Hubs, rings and MF8
are not run.
That is a pulse-flood exchange (`common-control.md` §4), not a growth of this
file into `marker.md`.

---

## 9. PBX leaf (no network unit)

**Not built in newimpl.** The retired tree had a jumper, **LEAF**: digit `1`
hunted the first free port of `UPLINK_MASK` (block 1's trunks), patched the
caller to it and left (`old/verilog/rtl/mini_core.v`, `make mini-leaf` in
`old/verilog/`). Both straps are kinds newimpl has since given up. LEAF chooses
behaviour, which makes it a feature, and features are cards
(`newimpl/STYLE.md` §4). `UPLINK_MASK` names trunk ports, which the cards now
say for themselves (`newimpl/README.md` §5). How a newimpl leaf finds its
uplinks is not designed.

The far end must offer dial tone on that seizure. Its trunk card says *tone
trunk* (family 01, member 1: the offers-tone seat of `extensions.md` §2.2), and
the central's marker gives that port dial tone as it would a line. **The
central side should work in both builds as the code stands, but no bench has
run it.** An uplink's seizure is M and not `BUSY`, like a line's. A minimal
build takes it without reading the word. With a unit fitted, the uplink's word
is not a flood trunk's, so the marker takes it and the unit leaves it alone.

The same plant in the other direction: the **central** keeps an offers-tone
trunk group (e.g. 70–77) tied to the leaf's 10–17. Network-wide access is
`1 <central e b> <g s>`, then the leaf's two-digit extension after a second
dial tone. The leaf has no flood code. `leaf-uplink.md` is the contract.

---

## 10. The one-board form

`nano-marker.md` proposed the retired tree's mini-marker cut from 33 packages
to 25 for a PBX leaf: one Eurocard, with its DIN 41612 and two strap switches.
newimpl has no BOM, so whether the marker as built fits one board is not known.
The proposal was retired into this section on 2026-09-25, and its full text is
at commit `63bafbb`. It was built and benched only in the retired tree, and
nothing of it is in newimpl:
- RTL: `old/verilog/rtl/nano_marker.v`, `nano_reg.v` and `nano_core.v`;
- benches: `make nano` and `make nano-noop`, in `old/verilog/`.

**Its scope still stands** (Joel, 2026-09-23). A one-board site knows its 64
ports and never an exchange code, so it is never a network node, and it is no
reason to retire this marker. Its callers still reach the network. Key `1`
patches the caller to an uplink and the register is **released**, so the loop
pulses that follow ride the trunk to the central. There the central's own
register counts `1 e b h s` (`leaf-uplink.md` §2).

What it cut, and where each cut stands against this marker as built:

| | the one-board form | now |
|---|---|---|
| pulse count | three bits and a wrap flip-flop: 8, 9 and 10 pulses all read 0, so `2 8` read as `2 0` | **overtaken.** It cannot refuse 8 or 9 on the second key, which is cannot-complete in every build (§3) |
| digit store | six bits in one '174, and the store *is* the called number | coherent only on a board that never takes a unit. The unit reads `e b h s` from this register's four-digit store |
| write queue | none: two writes at most, the second the first with `DST` and `SRC` swapped | no queue is true of any board, since the queue here is a model part (§7). The pure swap holds only without a unit: a claimed trunk's `CLAIM` rides on its own write of the pair, not on the called port's |
| caller address | the register's own port latch, held past release | `pulse_reg` holds it too. This marker keeps its own copy, a '174 it could drop |
| key `0` | hunts an operator at 04–07, in fixed order from 04 | this marker makes 0 cannot-complete. `protocol.md` §5 has 0 as the operator, and a four-bit count could hunt on 0 and still refuse 8 and 9. Not built, not decided |
| key `1` | hunts one strapped uplink block, skipping empty slots | §9: the straps are overtaken, and the hunt is not designed |
| presence | the OR of `PB`'s word line across a visit: "is there a word" | `PB` is gone. Presence is now a read of `/HW` by §8's reader, about 250 µs a port |
| an empty slot dialled | cannot-complete, by presence | this marker points the caller at it (§5) |
| straps | `LEAF`, `UP_BLK`, `OP_EN`, `OP_BLK` | `LEAF` and `OP_EN` choose behaviour, and features are cards (`newimpl/STYLE.md` §4). `UP_BLK` and `OP_BLK` name ports, a fact the port's own card owns (the same §4: one strap, on the board that owns the fact) |
| packages | 25, against the old mini-marker's 33 | both are the retired tree's hand BOMs (`old/verilog/tech/hc/pack.py`). newimpl has no BOM for either |
