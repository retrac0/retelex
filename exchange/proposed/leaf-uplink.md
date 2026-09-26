# PBX leaf off a central

A leaf is a small exchange with no network unit and no code, hung off a central
by one trunk group. The network reaches a leaf station through the central's
group and the leaf's own dial tone; a leaf station reaches the central by an
uplink and the central's dial tone. The leaf never floods; the central pays for
the network. Unlike a terminal (`proposed/terminal.md`), it keeps its numbers.

> **Proposed.** The central side is what `newimpl/rtl/mini_marker.v`,
> `marker.v`, `word_dec.v` and `net_unit.v` already do with a tone trunk (§2),
> on no bench; a class-marker central cannot be dialled into its leaf (§3).
> The leaf side is not designed (§3).

## 1. The plant and its numbers

Central 22 is a full member of the network, with a unit and code 22. Its group
on block 7 faces the leaf over one six-channel MF8 link, channels 71–73 and
75–77 (`trunks.md` §4); the leaf's end is its block 1, channels 11–13 and
15–17. Further leaves take further groups on 22.

| who dials | digits | what happens |
|---|---|---|
| anyone in the network | `1 2 2 7 1`, then the leaf's `h s` | claim at 22; 22 connects the caller to channel 71 (`7 1` alone from a line on 22); the leaf gives dial tone and connects `h s` |
| a leaf line | `h s` | local; no trunk touched |
| a leaf line | an uplink (§3), then a number on 22 | the central's dial tone; `h s` on 22, or `1 e b h s`, which 22 floods as for its own line |

The pulses after the leaf's dial tone are the leaf's register's, not another
flood. Nothing dials `1 <leaf e b>`. A central must own a code and claim, so a
router cannot parent a leaf (`newimpl/README.md` §7). Release is either hook
falling, as on any call; the leaf's leg carries no `CLAIM`.

## 2. The central side

Each channel of the group sends class **tone trunk** (family `01`, member 1,
options must-be-zero: `card-word.md` §2) and ties `/ANS` low. It faces no
direction and carries no glare.

- **Seized from the leaf, it is a caller**: M and not `BUSY`, like a line. The
  mini marker refuses only a flood trunk's word, and the class marker counts
  tone trunk among its callers (`newimpl/rtl/word_dec.v`). It gets dial tone.
- **The unit leaves it alone.** Its classifier and its hunt take only a flood
  trunk, member 0 (`network.md` §3), so no flood is forwarded into it.
- **Dialled, it depends on the build.** The mini marker connects it. The class
  marker leaves tone trunk out of what a number may be connected to, so `7 1`
  hunts, finds nobody who answers to 71, and gets cannot-complete (§3).

## 3. Open

- **The leaf's uplink is not designed.** Inbound needs nothing: the central's
  seizure is M and not `BUSY` at the leaf, and a channel that sends tone trunk
  is a caller in every build. Outbound, no strap says which ports are
  uplinks: that is the cards' to say, and a key's meaning is behaviour
  (`newimpl/README.md` §5). As built, a minimal leaf takes `1` as
  highway 1, so `1 1` reaches channel 11 by number, with no hunt. Wanted: a hunt
  on `1` for a free port whose word says tone trunk, the register released after
  the connect so the caller's pulses reach the central. That needs a leaf marker
  that reads words. It blocks every leaf → central call.
- **A class-marker central cannot be dialled into its leaf** (§2): the
  markers' difference over a dialled tone trunk is `marker.md` §7's open item.
  It blocks network → leaf on `top_max`; `top_net` dials it.
- **One channel a number, and no pilot.** `7 1` names one channel, and a busy
  one is a failed call. A tone trunk cannot also answer to a number, because
  answers-to is a form of its own (`card-word.md` §5).
- **No bench** has run either side.
