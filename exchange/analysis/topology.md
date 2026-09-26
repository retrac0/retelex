# The exchange — topology: chains, hubs, trees and rings, and how large a network can be

`network.md` says how a call crosses a network under the **pulse flood**:
the caller's own dial pulses go live down every trunk, every exchange hears them,
and the one they name claims the call. This document is about the network's shape. What shapes
the protocol allows, what each carries, where each stops, and whether a network
may have a loop in it.

> **Analysis of the model of its day; its guard-limited results are not re-run.** `exch.py topo` (`sim/exch.log`): Erlang B on a tree, the arithmetic of §11, which `exch.py net` confirmed to two decimal places, then the shapes call by call with `net`'s engine — timing, channels and pools, **not the gates** — at 3 calls a line an hour of 48 s, spread evenly over the other exchanges. §11–§12 are the old `network.md` §5, §5.1 and §7, moved as they were.
> **Changed: the hop and the pools.** Every guard limit here (§1's guard row, §4's eleven exchanges, §5's "limited by the guard", §6's hops and taps, §10) takes 12 ms as the *slow* hop and a hub as a hop and a third; the unit's hop is a 9 ms sweep, ≈ 12 ms typical and ≈ 22–30 ms slow (`network.md` §6); at a hub only the extra legs' writes add to it. On the 128 ms tap the slow case covers ≈ 4–5 hops, so the twelve-channel chain of eleven, the tandem with chains of five and the eight-hop shapes no longer fit it. Every forwarding exchange takes a resolver for every flood (`network.md` §3.5) and the monitors are one pool on the unit, not "on a trunk block": the "monitors, resolvers" columns and §2's pools count hubs only, and the loss when none is free, or at the one forwarder, is modelled nowhere (`network.md` §10). §8's SS0 hop is now ≈ 35 ms, not 26–28 (`proposed/ss0.md` §6).
> **Changed: the plant.** §1's "seven groups of six channels, one a block" is MF8's; the local trunk gives eight channels a block and a single-channel card takes any socket (`trunks.md` §1). §5's and §11.2's "four directions of twelve" is 48 channels, where blocks 1–7 hold seven six-channel groups (42); §1's 12 + 12 + 12 + 6 is the split that fits. §10's glare is built: it joins the two callers (`network.md` §5). §2's 4.8–5.3 s and §3's "fit three" are `exch.py`'s; the class marker's walk, one port every 4 ms, makes dial tone slower than any model here assumes.

---

---

## 1. The rules of shape

Six things decide what can be built. None of them is a route table.

| | the rule | where it comes from |
|---|---|---|
| **Directions** | an exchange faces **four neighbours at most**. A direction is two bits of a trunk's word, N, S, E or W | `card-word.md` §2 |
| **One neighbour a direction** | every trunk facing one way goes to the same exchange. The origin seizes one free trunk a direction, so a direction split between two neighbours would send each flood to one of them and not the other | `network.md` §1 |
| **Trunk groups** | **seven at most**, one MF8 link of six channels each, one a block. Two groups facing the same way are one direction of twelve channels; three, eighteen; four, twenty-four | `numbering.md` §2 |
| **The flood sees a tree** | the links a flood may be forwarded along must have no cycle in them. A no-forward jumpered link is outside the tree (§7) | `network.md` §7 |
| **Sixty-four codes** | `e b`, both digits 0–7, octal as a line's number is. 00–17 are the backbone's by convention: the tandems and hubs, as ports 00–07 are an exchange's services and 10–17 its first trunk group when networked | `numbering.md` §5 |
| **The guard** | the flood must cross the whole network inside the origin's guard, which is **a jumper**: 128 ms is ten hops at a slow marker's 12 ms, 256 ms twenty-one and 512 ms forty-two, less a third of a hop for each hub on the way. It is the same tap at every exchange in one network and it is the only number in the protocol that says how big the network is | `analysis/monitor-rules.md` §4 |

**Trunk groups cost lines.** The first trunk group sits in block 1, whose
slots are not lines (block 0 holds tones and the operator bank). Each group
after that takes eight line slots:

| trunk groups | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|
| lines left | 48 | 40 | 32 | 24 | 16 | 8 | 0 |

An exchange with all seven is a **tandem**: 42 channels of trunk and the 04–07
bank. Its seven groups divide among its directions as 12 + 12 + 12 + 6, as
18 + 12 + 12, as 18 + 18 + 6. At 1 % blocking six channels carry
1.91 E, twelve 5.88 E, eighteen 10.44 E and twenty-four 15.30 E.

---

## 2. What every network pays: the flood

Every call that leaves its exchange holds one channel **on every link of the
network** from the key until `e` and `b` are dialled (`network.md` §4.3).
**How long depends on the code called**, because a flood lasts as long as its
two digits take to dial: a 1 is one pulse and a 0 is ten.

| code | 11 | 17 | 21 | 77 | 00 | mean over all 64 |
|---|---|---|---|---|---|---|
| flood held | 2.0 s | 2.6 s | 2.1 s | 3.2 s | 3.8 s | 2.7 s |

That is a tax on every link, set by the size of the whole network and not by the
link's own traffic. At 30 % of calls leaving and the mean code, each 1 000 lines
in the network lay 0.67 E on every link; at 20 %, 0.45 E; at 50 %, 1.12 E.

- **It is the reason to keep the backbone's codes short.** The busiest exchanges
  are called most, and each pulse of their code adds 0.1 s to every flood made to
  them. 11, 12, 13 cost 2.0–2.2 s where 70, 77, 00 cost 3.1–3.8 s. The convention
  of `numbering.md` §5 — 00–17 for the backbone — puts the cheap codes where
  the traffic is, except 00 itself.
- **An eight-channel link to a 48-line leaf** carries that leaf's own 1.15 E at 30 %
  leaving. It has room for about 1.98 E of flood before it blocks 1 %: **a
  network of about 2 900 lines**. Past that, every link is sixteen channels.
- **The pools grow with the flood.** Monitors on a trunk block and resolvers at a
  hub are held for the same time by every call that leaves. For 0.5 % turned
  away: three of each to about 400 lines, four to 1 700, five beyond
  (`analysis/monitor-rules.md` §6). A monitor is ≈ 8½ packages.
- **The flood does not grow with distance**, and neither does what a caller
  waits: **4.8 to 5.3 s** from lifting to ringback on a network call in every
  shape here, from five exchanges to forty-seven, because the claim is 133 ms
  whatever the hop count and the rest is dialling.

---

---

## 3. The reference: two hubs, six leaves

```
   leaf ─┐ 6 ch                                   6 ch ┌─ leaf
   leaf ─┤ 6 ch      12 ch: two groups, one way   6 ch ├─ leaf
   leaf ─┤ 6 ch   ┌──────┐            ┌──────┐   6 ch ┤
         └────────┤  11  │════════════│  12  ├────────┘─ leaf
                  └──────┘            └──────┘
       48 lines a leaf          five groups and 24 lines a hub; 336 lines
        codes 21-23, 31-33           codes 11 and 12: the backbone's
```

Each hub faces its three leaves and the other hub: four directions, the most an
exchange has. `exch.py net` runs it call by call, smooth and in bursts
(§11.1):

| | predicted, 30 % leaving | measured |
|---|---|---|
| a leaf link, six channels | 1.28 E, 0.17 % | 1.25 E, 0.13 % |
| the hub link, twelve | 2.58 E, 0.00 % | 2.57 E, 0.00 % |
| flood held a leg | 2.2 s | 2.0 s |
| lifting to ringback, local / network | | 2.3 s / 4.8 s |

At 50 % leaving the leaf links block 2.1 %, and want twelve channels. Bursts of
demand leave every link alone and fall on the registers: fit three.

---

---

## 4. Chains

```
   ○ ─── ○ ─── ○ ─── ○ ─── ○            every exchange two directions; the ends one
```

The middle link carries everyone's traffic across it, and a call between the
ends holds a channel on every link. 30 % of calls leaving (`topo` 1). *Pair* is
the worst loss between any two exchanges, and *lost* the mean over all calls
that leave:

| exchanges | six-channel links: busiest link | pair | lost | twelve-channel links: lines | busiest link | pair | channels a call | spread |
|---|---|---|---|---|---|---|---|---|
| 3 | 1.23 E, 0.14 % | 0.28 % | 0.19 % | 132 | 1.15 E, 0.00 % | 0.00 % | 1.4 | 24 ms |
| 4 | 1.64 E, 0.53 % | 0.84 % | 0.51 % | 168 | 1.44 E, 0.00 % | 0.00 % | 1.7 | 36 ms |
| 5 | 1.86 E, **0.91 %** | 2.15 % | 1.22 % | 204 | 1.59 E, 0.00 % | 0.00 % | 2.1 | 48 ms |
| 6 | 2.24 E, 1.89 % | 4.67 % | 2.55 % | 240 | 1.87 E, 0.00 % | 0.00 % | 2.4 | 60 ms |
| 8 | 2.87 E, 4.52 % | 15.0 % | 7.90 % | 312 | 2.33 E, 0.00 % | 0.00 % | 3.1 | 84 ms |
| 10 | 3.49 E, 8.17 % | 32.5 % | 17.0 % | 384 | 2.79 E, 0.00 % | 0.01 % | 3.8 | 108 ms |
| 11 | 3.77 E, 10.1 % | 43.1 % | 22.8 % | 420 | 3.00 E, 0.01 % | 0.02 % | 4.1 | 120 ms |
| 12 | | | | 456 | 3.26 E, 0.01 % | 0.04 % | 4.4 | **132 ms** |

- **On six-channel links a chain is five exchanges at 30 % leaving**, seven at
  20 %, and none at 50 %: even two exchanges block 1.3 % then.
- **On twelve-channel links traffic never limits a chain. The guard does, at
  eleven exchanges**: a twelfth makes eleven hops, 132 ms at a slow marker, and a
  caller's next digit could reach the far end before the flood does. Every
  exchange inside such a chain has four groups and 36 lines.
- **A chain never wants more than twelve channels.** At eleven exchanges the
  busiest link carries 3.0 E, half of what twelve hold.
- **Long chains are dear in channels**, not in blocking: a call in a chain of
  eleven holds four channels on average, and ten between the ends.

Run call by call, a chain of six on six channels loses 19 network calls in
1 000, against 26 predicted (`topo` 7).

---

---

## 5. Hubs

An exchange that faces three or four directions is a hub. It fans each flood out
through a resolver and keeps the branch that claims (`network.md` §3.5).

```
        ○                          ○   ○   ○              a star: a hub and four spokes
        │                           \  │  /
    ○ ──●── ○                 ○ ─── ● ═══ ● ─── ○         two hubs (§3)
        │                           /  │  \
        ○                          ○   ○   ○

    ○─○─○─○──●──○─○─○─○                                   a tandem with four chains
             ┆ (two more)

          ○ ○ ○     ○ ○ ○
           \│/       \│/
            ●═══ ■ ═══●                                    a tree: a tandem, four sub-hubs,
           /  ═══╩═══  \                                   three leaves, or chains, on each
          ●             ●       ■ tandem: 4 × 12 ch, 6 lines
         /│\           /│\      ● sub-hub: 12 ch up, 6 or 12 ch down
        ○ ○ ○         ○ ○ ○
```

30 % leaving (`topo` 2):

| | exchanges | lines | flood a link | busiest link | pair | lost | channels a call | spread | monitors, resolvers |
|---|---|---|---|---|---|---|---|---|---|
| star: a hub and four spokes, 6 ch | 5 | 228 | 0.12 E | 1.24 E on 6, 0.15 % | 0.29 % | 0.24 % | 1.6 | 28 ms | 2, 2 |
| star: a tandem and four spokes, 12 ch | 5 | 204 | 0.11 E | 1.15 E on 12, 0.00 % | 0.00 % | 0.00 % | 1.7 | 28 ms | 2, 2 |
| two hubs, six leaves | 8 | 336 | 0.20 E | 1.29 E on 6, 0.17 % | 0.35 % | 0.27 % | 2.1 | 44 ms | 3, 3 |
| tandem, four chains of 3; 12 ch, 6 to the last | 13 | 516 | 0.31 E | 1.35 E on 6, 0.22 % | 0.44 % | 0.15 % | 3.4 | 76 ms | 3, 3 |
| tandem, four chains of 5, the same | 21 | 804 | 0.49 E | 1.52 E on 6, 0.38 % | 1.03 % | 0.36 % | 5.1 | 124 ms | 4, 4 |
| tandem, four chains of 5, 12 ch throughout | 21 | 780 | 0.48 E | 4.09 E on 12, 0.08 % | 0.21 % | 0.16 % | 5.1 | 124 ms | 4, 4 |
| tandem, four chains of 6 | 25 | 924 | 0.58 E | 4.84 E on 12, 0.27 % | 0.88 % | 0.63 % | 6.0 | **148 ms** | 4, 4 |
| tree: tandem, four sub-hubs, twelve leaves; 6 ch to a leaf | 17 | 708 | 0.41 E | 1.49 E on 6, 0.34 % | 0.74 % | 0.56 % | 3.1 | 60 ms | 4, 4 |
| the same, 12 ch to every leaf | 17 | 636 | 0.37 E | 3.33 E on 12, 0.01 % | 0.03 % | 0.02 % | 3.2 | 60 ms | 4, 4 |
| tree with 24 leaves, in chains of two; 12 ch throughout | 29 | 1 068 | 0.66 E | 5.56 E on 12, 0.71 % | 1.41 % | 1.08 % | 4.2 | 84 ms | 4, 4 |
| tree with 31 leaves | 36 | 1 320 | 0.83 E | 7.40 E on 12, **3.58 %** | 7.07 % | 3.96 % | 4.8 | 108 ms | 5, 5 |
| three tandems in a chain, five branches, 28 leaves | 36 | 1 296 | 0.81 E | 5.91 E on 12, 1.04 % | 2.38 % | 1.57 % | 5.0 | 116 ms | 5, 5 |

- **A star is the cheapest network there is.** A spoke's link carries one
  exchange's traffic and nothing else. Five exchanges on six channels each lose
  0.24 % of their network calls, where a chain of five loses 1.22 %.
- **A tandem with chains is limited by the guard, not by traffic**: four chains of
  five, twenty-one exchanges, are 124 ms across. Four chains of six would carry
  their traffic and are 148 ms across.
- **A tree is limited by the tandem's own links.** A tandem has 48 channels, and
  four directions make them twelve each. Each of those links carries a quarter of
  the network's lines against the other three quarters. It passes 1 % at about
  1 100 lines: **twenty-nine exchanges.** A tree of thirty-six blocks 3.6 % there.
- **Splitting the centre goes further.** Three tandems in a chain on
  eighteen-channel links, with five twelve-channel branches between them, put
  only a sixth of the network behind each branch link. That carries 36 exchanges
  and 1 296 lines at 1.0 % on its busiest link, and 47 exchanges at a fifth of
  calls leaving (§6).
- **A tree is short.** Twenty-nine exchanges are six hops across and thirty-six
  eight, where a chain of eleven is ten. A call holds three to five channels.

---

---

## 6. How large

The largest of each family with no link over 1 %, inside the sixty-four codes
and the guard (`topo` 4). What stops each is in bold:

| | 20 % of calls leave | 30 % | 50 % |
|---|---|---|---|
| chain, 6 ch | 7 exchanges, 336 lines, **traffic** | 5, 240 | none |
| chain, 12 ch | 11, 420, **the guard** | 11, 420 | 11, 420 |
| star, 6 ch | 5, 228, **four directions** | 5, 228 | none: a spoke blocks 1.5 % |
| tandem and four chains, 12 ch | 21, 780, **the guard** | 21, 780 | 17, 636, **traffic** |
| tree, 12 ch | 43, 1 572, **traffic and the guard together** | 29, 1 068, **the tandem's links** | 17, 636 |
| three tandems, five branches, 12 ch | **47, 1 692** | 35, 1 260 | 21, 756 |

**The upper limits of the protocol as it stands:**

| limit | is | set by |
|---|---|---|
| exchanges | **64** | the codes 00–77 |
| neighbours of one exchange | **4** | the direction is two bits |
| channels at one exchange | **48**, and then 12 lines | eight blocks |
| hops across the network | **10**, less a third for each hub — **21 at the next tap of the guard** | the origin's 128 ms guard against a slow marker's 12 ms a hop |
| exchanges in a line | **11**, or **22** at 256 ms | the same |
| the largest network measured here | **47 exchanges, 1 692 lines** at a fifth of calls leaving; **35 and 1 260** at a third; **21 and 756** at a half | the flood, and the centre's 48 channels |
| six-channel links | to **≈ 1 100 lines** in the network | the flood: 0.67 E of it on every link for each 1 000 lines |
| monitors a block, resolvers a hub | **5** at the largest | the flood |

- **Traffic, not numbering, is the ceiling.** Sixty-four codes are more than
  full exchanges can use: no shape reaches them, and at 50 % leaving none passes
  756 lines. The codes would bind only on a network of small exchanges — sixty
  of twenty lines each is 1 200 lines, which the centre can carry.
- **What the limits are not set by**: the pulses, which lose 0.5 ms of a 60 ms
  break a hop against an 8 ms window (`common/channel-cards.md` §5); the slips, which at
  eight crossings of 40 ppm are 32 dB against the codec's own 25 dB
  (`mf8/mf8-backplane.md` §7); or the wait, which is 4.8–5.3 s in every shape.
- **The hop limit is one tap on one counter, and moving it fills the plan.** The
  128 ms is `analysis/monitor-rules.md` §1's guard, and the only thing in the protocol that
  is a function of the hop count at all. At the next tap up:

  | the guard's tap | a chain of 12 ch | the largest network at 30 % leaving | what stops it |
  |---|---|---|---|
  | **128 ms** | 10 hops, 11 exchanges | 63 exchanges, 756 lines, 12 a piece | the guard |
  | **256 ms** | 21 hops, 22 exchanges | **64 exchanges, 1 428 lines, 22 a piece** | traffic and the four directions |
  | 512 ms | 42 hops, 43 exchanges | the same 64 and 1 428 | the same |

  **256 ms fills the sixty-four codes and nearly doubles the lines**, and 512 buys
  nothing more in size — past 256 what stops the search is the traffic on the
  centre and the four directions an exchange has, and neither of those is a timer
  (`exch.py big` 7). The tap may go to 590 ms, the caller's own 720 ms pause less
  the 130 ms the digit and the seizure take, and no further.
- **Past these limits** the way on is SS0 (§8), or a second network reached
  through `1 8` or `1 9` (`numbering.md` §5).
- **And smaller exchanges.** Both the traffic on a link and the flood on it are
  proportional to the *lines* in the network, not to the exchanges, so what fills
  the numbering plan is exchanges that are not full: `analysis/traffic.md` §8 searches
  the shapes again with a line cap and reaches **63 exchanges of 12 lines**, seven
  or eight hops across and inside the guard. It also settles what a **fully
  connected core of hubs** is worth — nothing, because the flood must see a tree
  and every link off it is a jumper that carries its own two ends only (§7).

Run call by call at 30 % leaving with five monitors and resolvers (`topo` 7): the
tree of twenty-nine refuses 0.55 % on its busiest link where 0.71 % was
predicted, and loses 7 network calls in 1 000. The thirty-six on three tandems
refuses 0.95 % where 1.04 % was predicted, and loses 9 in 1 000. **The pools must
be sized**: the tree of seventeen with three monitors and resolvers loses 8 calls
in 1 000 to them, and with four, 0.3.

---

---

## 7. Rings and loops

**A loop is possible, if one link of it is jumpered. A loop with no jumper is not.**

A flood has no memory of where it has been. Sent round a ring, it comes back to
the exchange that made it, which forwards it again as any seizure, on another
channel. `exch.py topo` 7 lifts one handset on a ring of six exchanges of six
channels and counts the channels seized a second and a half later:

| | channels seized by one call |
|---|---|
| one link jumpered | 6 of 36 |
| no jumper | **36 of 36** |

The whole ring is held until the code is dialled, two seconds or more, for every
call that leaves. Under ordinary traffic a ring of six with no jumper loses **100
network calls in 1 000**, and a ring of four 72 (`topo` 7).

**A no-forward jumper — one plug a compass direction on the network unit**, set for every
channel of one link at both ends (`network.md` §7). A seizure is never forwarded into a
jumpered link, and one that arrives on it is never forwarded onward. An origin
may still seize it and the far end may still claim, so **the jumpered link
carries the calls between its own two ends, and no others.** The links without
the bit must form a tree:

```
 jumpers needed  =  links  −  exchanges  +  1          a ring: one.  A tree: none
```

**What a ring buys** (`topo` 5, 30 % leaving, six channels):

| | busiest link | pair | lost | channels a call |
|---|---|---|---|---|
| chain of 4 | 1.64 E, 0.53 % | 0.84 % | 0.51 % | 1.67 |
| ring of 4, one link jumpered | 1.26 E, 0.16 % | 0.18 % | 0.10 % | 1.33 |
| chain of 6 | 2.24 E, 1.89 % | 4.67 % | 2.55 % | 2.33 |
| ring of 6 | 2.01 E, 1.23 % | 2.78 % | 1.39 % | 2.07 |
| chain of 8 | 2.87 E, 4.52 % | 15.0 % | 7.90 % | 3.00 |
| ring of 8 | 2.70 E, 3.71 % | 11.9 % | 5.89 % | 2.79 |

Run call by call, the ring of six loses 10 network calls in 1 000 where the
chain of six loses 19.

- **It takes one pair's traffic off the chain**, the pair at the ends, which was
  crossing every link. That is worth most on a short ring and less on a long
  one.
- **It does not share load both ways round.** The flood goes one way, so the call
  does. Every other pair is served exactly as on the chain.
- **It is a spare.** If a link fails, move the jumper to it and the ring is a
  chain again with every exchange reachable. That is a jumper, or a switch on the
  trunk card, at both ends of two links. Nothing moves it by itself: a trunk card
  takes its dead link out of the hunt, but the jumper elsewhere stays until
  someone moves it, and until then the network is in two parts.
- **At the jumper's two ends a call between them arrives twice**, once direct and
  once the long way. The direct copy is a hop away and claims first; the origin
  then releases the long way (`network.md` §7).

**Loops through hubs** work the same way. A jumpered link between a leaf of one
hub and a leaf of the other in §3's network takes that pair's calls off three
links: the mean loss falls from 0.31 % to 0.25 %, and nothing else changes. A
leaf has two directions then, and still 48 lines.

**Two links between the same two exchanges are not a loop if they face the same
way.** They are one direction of twelve channels and one hunt. Jumpered as two
different directions they are a loop of two, and need a jumper like any other.

---

## 8. What SS0 would change

`proposed/ss0.md` is the alternative to pulse flood: the number crosses each link
as one message on the spare bit of the MF8 frame's S lane, and A keeps
everything else. Its seizures go the same way — every direction at the origin,
every other direction at a hub — but they are held only until the claim comes
back, tens of milliseconds rather than the seconds a caller takes to dial two
digits. Taking that as 0.4 s (`topo` 6, which is arithmetic; SS0 has never been
run call by call):

| family, 30 % of calls leaving | pulse flood | SS0 |
|---|---|---|
| chain, 6 ch | 5 exchanges, 240 lines | 5, 240 |
| chain, 12 ch | 11, 420 | 12, 456 |
| star, 6 ch | 5, 228 | 5, 228 |
| tandem and four chains, 12 ch | 21, 780 | **33, 1 212** |
| tree, 12 ch | 29, 1 068 | 30, 1 104 |
| three tandems, five branches | 35, 1 260 | **39, 1 404** |
| post-dial delay | **133 ms at any distance** | 128 ms, and 28 ms a hop: 242 ms across a chain of five, 572 ms across a tandem with four chains of eight |

- **SS0 buys the long shapes, not the wide ones.** Where the guard was the limit —
  a tandem with chains — it lifts the ceiling by half, because there is no live
  pulse to race and no guard at all. Where traffic was the limit, it changes
  almost nothing: a six-channel chain still carries five exchanges, because a
  leaf's own traffic, not the flood, fills its link.
- **It has more post-dial delay.** The flood's claim is 133 ms from
  any exchange to any other; SS0's message is relayed hop by hop, so the far end
  of a long network answers half a second after the caller's last pulse.
- **It would not run on the trunks that are not MF8.** A single-channel card, a
  voice-band circuit or a radio carries A, and the pulse flood needs nothing else
  (`network.md` §2). SS0 needs the S lane, or a pair of its own.

---

## 9. Choosing a shape


 * up to five exchanges along a road or a cable - a chain on six channels - nothing at any exchange but two trunk groups 
 * the same, six to eleven - a chain on twelve channels - traffic stops mattering; 36 lines an exchange inside it 
 * exchanges round one centre - a star, then a tandem with chains - a spoke carries only its own exchange's traffic 
 * more than twenty, or more than about 800 lines - a tree, twelve channels throughout 
 * very large networks - three tandems, five branches - the only shape that reaches 1500+ or so lines

Give the backbone the codes 00–17 and ordinary exchanges 20–77, and inside each
run hand out the codes of fewest pulses first: 11, 12, 13 before 17, and 21, 22
before 77. Every pulse of an exchange's code adds 0.1 s to every flood made to it
(`numbering.md` §5).

---

## 10. Not measured

- **Uneven traffic.** Calls are spread evenly over the other exchanges. Real
  traffic favours neighbours, which eases the centre and leaves the flood as it
  is, since a flood goes everywhere whatever the call's destination.
- **How many calls leave.** Every limit here moves with it. 20 % and 50 % bracket
  it; a network's own figure is a counter on a working exchange
  (`proposed/counters.md`).
- **The guard at the hop limit.** Ten hops at 12 ms rests on the slow marker of
  `analysis/monitor-rules.md` §1, which is an estimate. A chain of eleven and a tandem with
  chains of five sit within 8 ms of it.
- **Bursts in the larger shapes.** `net` found that bursts fall on the registers
  in the eight-exchange network. The larger shapes were run with smooth demand.
- **SS0 (§8) has never been run call by call.** Its 0.4 s seizure is arithmetic
  from `proposed/ss0.md`'s hop of 26 ms, and its own §9 lists what it has not settled,
  glare among it.
- **A jumper moved while calls are up**, and a ring healing: by hand, and not
  modelled.
- **Glare.** Two ends seizing one channel at once is not in the model; the
  opposite-order hunt of `network.md` §5 is assumed to leave it rare.

---

## 11. Link loads — from the old `network.md` §5

A direction of six channels carries 1.91 erlang at 1 % blocking; **of twelve, 5.88 —
more than twice the calls for twice the trunks.** The tables below were run on
six-channel groups (1.91 E / 5.88 E at twelve) and are the shape, not the new
capacity. In a chain the middle link carries
everyone's traffic across it, and the flood adds its own. 48 lines an
exchange at 0.08 E a line and 3 calls a line an hour, calls spread evenly over
the other exchanges, and every call that leaves flooding every link for 2.7 s
(`network.md` §4.3); erlangs on the busiest link (traffic + flood) and calls blocked there:

| exchanges | | 20 % of calls leave | 30 % | 50 % |
|---|---|---|---|---|
| 2 | one link | 0.77 + 0.04 E, 0.0 % | 1.15 + 0.06, 0.1 % | 1.92 + 0.11, 1.3 % |
| 3 | chain | 0.77 + 0.06, 0.0 % | 1.15 + 0.10, 0.2 % | 1.92 + 0.16, 1.4 % |
| 3 | triangle | 0.38 + 0.06, 0.0 % | 0.58 + 0.10, 0.0 % | 0.96 + 0.16, 0.1 % |
| 4 | chain | 1.02 + 0.09, 0.1 % | 1.54 + 0.13, 0.6 % | 2.56 + 0.21, 4.0 % |
| 5 | chain | 1.15 + 0.11, 0.2 % | 1.73 + 0.16, 1.0 % | 2.88 + 0.27, 6.1 % |
| 6 | chain | 1.38 + 0.13, 0.4 % | 2.07 + 0.19, 2.0 % | 3.46 + 0.32, 10.1 % |

The same busiest link, six channels against twelve (traffic and flood together):

| exchanges in a chain | 30 % of calls leave | 50 % |
|---|---|---|
| 4 | 1.66 E: 0.6 % → 0.00 % | 2.77 E: 4.0 % → 0.00 % |
| 5 | 1.89 E: 1.0 % → 0.00 % | 3.15 E: 6.1 % → 0.01 % |
| 6 | 2.27 E: 2.0 % → 0.00 % | 3.78 E: 10.1 % → 0.04 % |

**Doubling the trunks at the centre is what lets a chain of six carry busy
traffic**, and it costs the central exchanges twelve lines each (36, not 48).
A doubled centre needs its edges doubled too: in a longer chain the links just
outside a doubled core carry nearly as much as the core, and become the
bottleneck.

**A star does the same with less.** Five exchanges of 48 lines, `b` from 2:

| | busiest link, 30 % of calls leave | 50 % | MF8 links | trunk ports | line slots given up | links a call crosses |
|---|---|---|---|---|---|---|
| chain | 1.0 % | 6.1 % | 4 | 48 | 0 | 2.0 |
| chain, the middle two links doubled | 0.19 % | 1.72 % | 6 | 72 | 24 | 2.0 |
| star: a hub and four spokes (`network.md` §3.5) | 0.19 % | 1.72 % | 4 | 48 | 12 | 1.6 |

A spoke's link carries one exchange's traffic, as a chain's end link does, so the
star blocks exactly as the doubled chain does, with a third fewer trunks, two MF8
links fewer and half the lines given up, all of them at the hub. It also fits a
plant that radiates from a centre.

### 11.1 Measured: eight exchanges, call by call

`exch.py net` runs two hubs of four directions with three leaves each — 12
channels between the hubs, 6 to every leaf, 30 lines at a hub and 48 at a leaf,
348 in all — for twelve hours. A line makes 3 calls an hour and holds one 48 s;
30 % leave home. **Bursty** is the same calls arriving together: 30 s at eight
times the rate, every 5 minutes, an office at a shift change.

| | calls an hour | leaf link, 6 ch | hub link, 12 ch | flood held a leg | dial tone, mean / 99 % / worst | lift to ringback, local / network |
|---|---|---|---|---|---|---|
| smooth, 30 % leaving | 1 053 | 1.25 E, 0.13 % | 2.57 E, 0.00 % | 1.98 s | 6 ms / 10 ms / 1.1 s | 2.33 s / 4.82 s |
| bursty, 30 % | 1 047 | 1.26 E, 0.25 % | 2.46 E, 0.00 % | 1.98 s | 15 ms / 10 ms / 5.6 s | 2.34 s / 4.82 s |
| bursty, 50 % | 1 047 | 1.87 E, 2.12 % | 3.78 E, 0.12 % | 1.99 s | 19 ms / 249 ms / 4.2 s | 2.35 s / 4.82 s |
| bursty, 30 %, two registers | 1 047 | 1.24 E, 0.59 % | 2.45 E, 0.00 % | 1.98 s | 79 ms / 2.1 s / 7.4 s | 2.39 s / 4.89 s |
| bursty, 30 %, one register | 1 047 | 1.34 E, 0.26 % | 2.61 E, 0.00 % | 1.98 s | 1.0 s / 13.2 s / 35.9 s | 3.25 s / 5.71 s |

The hubs are 11 and 12, backbone codes, and the leaves 21–23 and 31–33 (`numbering.md` §5). The
model dials each call's own code, so these floods are short ones: the codes are
cheap.

- **§5's arithmetic holds.** Worked with these codes' own floods it predicts
  1.28 E and 0.17 % on a leaf link at 30 % leaving, and 2.58 E on the hub link;
  the run gives 1.25 E and 0.13 %, and 2.57 E. The flood is held 2.0 s a leg
  against 2.2 s by arithmetic, the difference being this model's pauses,
  0.5–0.9 s against 0.8 s.
- **Bursts do not move the erlangs.** The same calls arrive, in a different
  order. What they move is what a caller waits for: dial tone's mean more than
  doubles and its worst case goes from 1.1 s to 5.6 s, while every link and pool
  reads the same.
- **Bursts fall on the registers, and nowhere else.** Three at a 48-line leaf
  carry them: 1.2 % of callers wait a scan for one. Two, and 6.8 % wait, with
  one caller in a hundred waiting 2 s. One, and a third of all callers wait,
  1 in 100 for 13 s. **Fit three.**
- **The pools built for the flood are barely touched**: a hub's resolvers reach
  0.14 E and turn away 0.1 % of the calls that want one; a leaf's monitors 0.09 E
  and 0.0 %. Three of each is generous, two would do at this size.
- **At 50 % leaving the leaf links are the constraint**, 2.12 % blocked against
  0.12 % on the doubled hub link. Twelve channels to each leaf, or fewer calls
  leaving home.
- **What a caller hears**, whatever the load: 2.3 s from lifting to ringback on a
  local call, 4.8 s on a network call to these codes, of which most is dialling
  five digits at 10 pps. The claim itself is 133 ms after the last pulse, this
  model's figure.

### 11.2 A hub as a tandem

**A hub with four directions of twelve channels is a tandem switch.** It gives
blocks 1–7 to trunk groups: seven groups, and the 04–07 bank (`numbering.md` §2,
`trunks.md` §4). Each direction is a
chain of *k* exchanges of 48 lines. With 30 % of calls leaving, erlangs on each
link of a branch from the hub outward, and calls blocked there on six channels
and on twelve:

| *k* | exchanges | flood a link | hub to 1st | 1st to 2nd | 2nd to 3rd | 3rd to 4th | 4th to 5th |
|---|---|---|---|---|---|---|---|
| 1 | 4 | 0.13 E | 1.28 E: 0.2 % / 0.00 % | | | | |
| 2 | 8 | 0.26 | 2.23: 1.9 % / 0.00 % | 1.41: 0.3 % / 0.00 % | | | |
| 3 | 12 | 0.39 | 3.21: 6.4 % / 0.01 % | 2.48: 2.7 % / 0.00 % | 1.54: 0.4 % / 0.00 % | | |
| 4 | 16 | 0.51 | 4.20: 13 % / 0.09 % | 3.51: 8.3 % / 0.02 % | 2.66: 3.5 % / 0.00 % | 1.67: 0.6 % / 0.00 % | |
| 5 | 20 | 0.64 | 5.19: 21 % / 0.45 % | 4.52: 16 % / 0.17 % | 3.73: 9.8 % / 0.04 % | 2.82: 4.3 % / 0.00 % | 1.79: 0.8 % / 0.00 % |

**Twenty full exchanges work around one hub** with twelve channels on every link
but the outermost, where six will do. The hub wants four resolvers (`network.md` §3.5) and
each exchange's trunk blocks three monitors (`analysis/monitor-rules.md` §6).

**`analysis/traffic.md` takes the demand further** — bursts, a flash crowd, peak against
off peak, and the whole of this section's network run a second time **in the gates**
(`old/verilog`'s `make traffic-net`, eight whole exchanges in RTL) and read against the
model here. Two things it changes: **Erlang B holds to about 1 % on a link and
understates past it**, because a flood puts a seizure on every link of the network
at the same instant; and **a caller is a line**, which cannot lift while it is off
hook, so a burst does not offer the calls the arithmetic says it does.

**§1–§10 above take this further**: chains, stars, trees and a split centre,
the largest of each, and rings. **What sets the limit is the flood, not the
numbering.** The flood's share — the
second figure above — is every call that leaves, anywhere, held on every link for
2.7 s. Thirty-six full exchanges would put 1.2 E of it on every link: more than
half of what six channels carry, and a fifth of twelve. **The sixty-four codes are
more than full exchanges can use**: the largest network §6 finds is 47
exchanges and 1 700 lines, with a fifth of calls leaving. Past that the way on
is SS0 (`proposed/ss0.md`), whose message floods for a third of a second, or a second
network reached through `1 8` or `1 9` (`numbering.md` §5). A pair can put both groups between
them (twelve channels, no blocking to speak of). **Closing a chain into a ring**
puts a link between its two ends and takes their traffic off every link between
(`network.md` §7): at five exchanges and 30 % leaving the busiest link falls from 1.89 E to
1.60 E, 1.0 % blocking to 0.5 %, and the new link carries 0.45 E. At 50 % it is
3.15 E to 2.67 E, 6.1 % to 3.5 %. The gain is that one pair's traffic and no
more, because the flood, and so the call, goes one way round: the jumpered link
carries only calls between its own two ends.

---

## 12. Why a transit chooses its own channel — from the old `network.md` §7

The first version of the flood hard-wired channel *k* through every exchange, so
a call needed the same *k* free on every link while its origin chose *k* seeing
only its own. A scratch simulation — a chain of 8, 6 channels a link, uniform
traffic, 150 000 calls a cell, % blocked for all calls / calls of 4+ hops:

| offered, whole chain | a channel chosen at each hop | **the same *k*, chosen blind** | the same *k*, all-knowing |
|---|---|---|---|
| 0.5 E | 0.00 / 0.00 | **2.10 / 4.29** | 0.00 / 0.00 |
| 1 E | 0.00 / 0.00 | **4.14 / 8.21** | 0.00 / 0.01 |
| 2 E | 0.11 / 0.18 | **8.34 / 16.4** | 0.13 / 0.21 |
| 4 E | 2.21 / 3.60 | **16.1 / 31.0** | 2.61 / 4.62 |

The damage is the blind choice, not continuity. Since seizure comes before the
number, a transit can patch to any free onward trunk with its ordinary fabric,
and blocking becomes the first column. Not in `exch.log`; `net` reproduces it.
