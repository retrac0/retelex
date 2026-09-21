# The exchange — the operator's position

`features.md` §4 had the operator and the console in one breath. They sit on one
desk and they are two different things. **This document is the phone**: a line
card in a channel slot, reached by dialling 0, that answers, talks, and hangs
up like any other. The keys, the bus master, forced release, observing and
hand-patched connections are `console.md`. The lamps that show what the
exchange is doing are `observers.md` and `hookbusy.md`.

> **Status: proposed.** Ordinary answer and dial from the position follow every
> other line (`marker.md`, `exch.py calls`). Transfer from the **console** is
> measured in `console.md` §7 (`make console`). **Phone flash transfer is
> deferred** (§5): the register's held-party field and the marker's consult path
> exist in RTL as hooks; they are not wired, and transfer for now is console
> keys only. Nothing has been drawn for a special station card.

---

## 1. Two things on one desk

| | the position | the console |
|---|---|---|
| what it is | a **phone** on a station card | keys and wheels that emit the marker's control word |
| where | a channel slot (default **04**) | cable B; no port, no latch, no number |
| reached by | key **0** (class *operator* hunt) | nothing — it is not dialled |
| alone | answers 0, dials out, talks | bring-up and maintenance without a phone |
| needs the other for | **transfer**, busy ports, force-release, observe, hand patch | a talking party (or a ring-source card) |

Either works without the other. A console with a ring-source card and no
position is still a manual board (`console.md` §6.3). A position with no console
still answers 0 and dials like a subscriber — and cannot start a second leg
(§3).

---

## 2. The position

### 2.1 What it is

**A station card with a phone on it**, in some slot whose word says *operator*
(`extensions.md` §2.2). It has a port circuit, a latch, two release detectors
and a `BUSY` bit like every other port. The map is the only place in the
exchange the number appears.

| | |
|---|---|
| **the card** | any station card: FXS or CVSD line (`channel-cards.md`). The word's `'165` fitted for class *operator* |
| **`/ANS`** | open — it rings in cadence |
| **reached by** | **key 0 only** as a subscriber. 0 hunts class *operator* in fixed order from 00 (`marker.md` §3). From another exchange: `1 e b 0`, the same key once the far monitor has claimed (`network.md` §3) |
| **not reached by** | its own number when it sits at 00–07 — those ports are never dialled, because 0 is the operator key (`protocol.md` §5) |
| **to the console** | a number on the `SRC` wheels (`console.md` §7.1) |

**04 is the default home, not a fabric requirement.** 00 stays empty (cleared
latches listen there). 01–03 are the switched tones. That leaves 04–07 as four
undialable line seats — operator, night/backup, more positions or single-channel
trunks. Further positions may sit in any dialable line slot; the hunt finds them.
Nothing in a block or the marker knows the number.

Under `groups.md` §2 class *operator* is retired: the first position is a plain
line at 04, and a second seat **answers to** that pilot. Until that lands, class
*operator* is how 0 finds the phone.

### 2.2 More than one, and none

| | |
|---|---|
| a second position / night announcement | nominally 05, then 06–07, then any dialable line slot. 0's order from 00 reaches 04 first |
| night service | out-of-service switch on 04's word (`extensions.md` §2.2): 04 reads unequipped, 0 walks on |
| no position fitted | 0 gives cannot-complete. A CO line ringing in is routed as 0, so an exchange with incoming trunks wants one |

### 2.3 Ordinary use — no console

Lift, dial `h s` (or `1 e b h s` when networked), talk, hang up. The marker does
the rest. A subscriber dialling 0 gets this phone by the class hunt. That is the
whole of the position as a line.

---

## 3. Transfer — console only, for now

Once the position is in a call its latch is written and the port is busy. **The
marker will not give a busy port a register on a plain lift** (`console.md` §7).
A second leg from the handset alone needs flash (`register.md` §6.1) — and flash
is deferred (§5).

**Transfer is done from the console**, measured end to end in `console.md` §7:

```
 CALL / RING / PAIR / DROP     WRITE+BOTH, WRITE, WRITE+BOTH, RELEASE
                               operator on SRC; called ports on DST;
                               hand-over pairs the two parties; RELEASE drops 04
```

**Patch first, then lift** — or make-busy the position before lifting — so a
register is not taken from the pool for the no-digit timeout (`console.md`
§7.1). The console document is the procedure; this one only names the boundary.

---

## 4. What needs the console, and what the lamps show

| job | where |
|---|---|
| answer 0, dial out | the phone alone (§2.3) |
| **transfer / second leg** | console (`console.md` §7) |
| force-release, service observing, hand patch, ring a busy or unequipped port | console (`console.md` §3, §5, §6) |
| see idle / off-hook / busy / call across the exchange | hook and busy fields (`observers.md`, `hookbusy.md`) |
| watch one port's last write, class, STALE | port watch (`observers.md` §5); the console's own watch is the same idea (`console.md` §3.2) |

The lamp field is a listener, not part of the position and not part of the
console as a bus master. Fitted beside the desk it is how the operator sees
state that lives only as latches and hooks — nobody is in charge of a call
(`fabric.md` §3.5).

---

## 5. Deferred: phone flash transfer

Hook-flash from the handset — attach a register with the held party in `SRC`,
consult, hang up to pair the two legs — is **not fitted**. The register field
and the marker's `M_CONSULT` / CLR pair path are in RTL as future hooks
(`register.md` §6.1, `marker.md` §8); flash detect on a busy operator port and
filling `attach_src` are not.

**Why it waits.** Latches cannot be read back (`console.md` §7.2). Flash needs
held-party memory the `'273` does not provide. A write-shadow on a station card
(scaled with fitted cards, any slot classed *operator*) was the preferred shape
when revisited; it is not designed here. Until then, every transfer goes through
the console (§3).

---

## 6. What this changes elsewhere

- **`features.md` §4`**: the operator is this document; the console is
  `console.md`. The lamp field is not “off the M and `BUSY` highways” —
  `observers.md` §1.
- **`console.md` §8`**: the position in brief; detail and the phone/console
  split live here.
- **`register.md` §6.1` / `marker.md` §8`**: flash deferred; console is the
  transfer path.
