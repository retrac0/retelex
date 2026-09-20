# The exchange — topology: chains, hubs, trees and rings, and how large a network can be

`exch-network.md` says how a call crosses a network under the **pulse flood**:
the caller's own dial pulses go live down every trunk, every exchange hears them,
and the one they name claims the call. This document is about the network's shape. What shapes
the protocol allows, what each carries, where each stops, and whether a network
may have a loop in it.

> **Status: analysis, with the arithmetic checked call by call.** `exch.py topo`
> is the run (`exch.log`). Its tables are Erlang B on a tree, the arithmetic of
> `exch-network.md` §5, which `exch.py net` confirmed to two decimal places. Its
> last parts run the shapes call by call with `net`'s engine, which models the
> timing, the channels and the pools, **not the gates**. Traffic is the figure
> used throughout `exch/`: a line makes 3 calls an hour of 48 s, 0.08 E a line,
> and the calls that leave home are spread evenly over the other exchanges. A
> real community is not even. No network has been built.

---

---

## 1. The rules of shape

Six things decide what can be built. None of them is a route table.

| | the rule | where it comes from |
|---|---|---|
| **Directions** | an exchange faces **four neighbours at most**. A direction is two bits of a trunk's word, N, S, E or W | `ex-extensions.md` §2.2 |
| **One neighbour a direction** | every trunk facing one way goes to the same exchange. The origin seizes one free trunk a direction, so a direction split between two neighbours would send each flood to one of them and not the other | `exch-network.md` §3 |
| **Trunk groups** | **eight at most**, one MF8 link of six channels each, one a block. Two groups facing the same way are one direction of twelve channels; three, eighteen; four, twenty-four | `exch-protocol.md` §5 |
| **The flood sees a tree** | the links a flood may be forwarded along must have no cycle in them. A link strapped with `n` is outside the tree (§7) | `exch-network.md` §3.3 |
| **Sixty-four codes** | `e b`, both digits 0–7, octal as a line's number is. 00–17 are the backbone's by convention: the tandems and hubs, as ports 00–17 are an exchange's trunks and services | `exch-network.md` §2 |
| **The guard** | the flood must cross the whole network inside the origin's guard, which is **a strap**: 128 ms is ten hops at a slow marker's 12 ms, 256 ms twenty-one and 512 ms forty-two, less a third of a hop for each hub on the way. It is the same tap at every exchange in one network and it is the only number in the protocol that says how big the network is | `exch-monitor.md` §3.5 |

**Trunk groups cost lines.** The first two groups sit in blocks 0 and 1, whose
slots are not lines anyway. Each group after that takes six line slots:

| trunk groups | 1–2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|
| lines left | 48 | 42 | 36 | 30 | 24 | 18 | 12 |

An exchange with all eight is a **tandem**: 48 channels of trunk and twelve lines.
Its eight groups divide among its directions as 12 + 12 + 12 + 12, as
24 + 12 + 12, as 18 + 18 + 12 or as 24 + 24. At 1 % blocking six channels carry
1.91 E, twelve 5.88 E, eighteen 10.44 E and twenty-four 15.30 E.

---

## 2. What every network pays: the flood

Every call that leaves its exchange holds one channel **on every link of the
network** from the key until `e` and `b` are dialled (`exch-network.md` §4).
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
  of `exch-network.md` §2 — 00–17 for the backbone — puts the cheap codes where
  the traffic is, except 00 itself.
- **A six-channel link to a 48-line leaf** carries that leaf's own 1.15 E at 30 %
  leaving. It has room for about 0.76 E of flood before it blocks 1 %: **a
  network of about 1 100 lines**. Past that, every link is twelve channels.
- **The pools grow with the flood.** Monitors on a trunk block and resolvers at a
  hub are held for the same time by every call that leaves. For 0.5 % turned
  away: three of each to about 400 lines, four to 1 700, five beyond
  (`exch-monitor.md` §4). A monitor is ≈ 8½ packages.
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
       48 lines a leaf          five groups and 30 lines a hub; 348 lines
        codes 21-23, 31-33           codes 11 and 12: the backbone's
```

Each hub faces its three leaves and the other hub: four directions, the most an
exchange has. `exch.py net` runs it call by call, smooth and in bursts
(`exch-network.md` §5.1):

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
through a resolver and keeps the branch that claims (`exch-network.md` §3.2).

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
          ●             ●       ■ tandem: 4 × 12 ch, 12 lines
         /│\           /│\      ● sub-hub: 12 ch up, 6 or 12 ch down
        ○ ○ ○         ○ ○ ○
```

30 % leaving (`topo` 2):

| | exchanges | lines | flood a link | busiest link | pair | lost | channels a call | spread | monitors, resolvers |
|---|---|---|---|---|---|---|---|---|---|
| star: a hub and four spokes, 6 ch | 5 | 228 | 0.12 E | 1.24 E on 6, 0.15 % | 0.29 % | 0.24 % | 1.6 | 28 ms | 2, 2 |
| star: a tandem and four spokes, 12 ch | 5 | 204 | 0.11 E | 1.15 E on 12, 0.00 % | 0.00 % | 0.00 % | 1.7 | 28 ms | 2, 2 |
| two hubs, six leaves | 8 | 348 | 0.20 E | 1.29 E on 6, 0.17 % | 0.35 % | 0.27 % | 2.1 | 44 ms | 3, 3 |
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
  break a hop against an 8 ms window (`mf8-cards.md` §5); the slips, which at
  eight crossings of 40 ppm are 32 dB against the codec's own 25 dB
  (`mf8-backplane.md` §7); or the wait, which is 4.8–5.3 s in every shape.
- **The hop limit is one tap on one counter, and moving it fills the plan.** The
  128 ms is `exch-monitor.md` §3's guard, and the only thing in the protocol that
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
  through `1 8` or `1 9` (`exch-network.md` §6).
- **And smaller exchanges.** Both the traffic on a link and the flood on it are
  proportional to the *lines* in the network, not to the exchanges, so what fills
  the numbering plan is exchanges that are not full: `ex-traffic.md` §8 searches
  the shapes again with a line cap and reaches **63 exchanges of 12 lines**, seven
  or eight hops across and inside the guard. It also settles what a **fully
  connected core of hubs** is worth — nothing, because the flood must see a tree
  and every link off it is a strap that carries its own two ends only (§7).

Run call by call at 30 % leaving with five monitors and resolvers (`topo` 7): the
tree of twenty-nine refuses 0.55 % on its busiest link where 0.71 % was
predicted, and loses 7 network calls in 1 000. The thirty-six on three tandems
refuses 0.95 % where 1.04 % was predicted, and loses 9 in 1 000. **The pools must
be sized**: the tree of seventeen with three monitors and resolvers loses 8 calls
in 1 000 to them, and with four, 0.3.

---

---

## 7. Rings and loops

**A loop is possible, if one link of it is strapped. A loop with no strap is not.**

A flood has no memory of where it has been. Sent round a ring, it comes back to
the exchange that made it, which forwards it again as any seizure, on another
channel. `exch.py topo` 7 lifts one handset on a ring of six exchanges of six
channels and counts the channels seized a second and a half later:

| | channels seized by one call |
|---|---|
| one link strapped | 6 of 36 |
| no strap | **36 of 36** |

The whole ring is held until the code is dialled, two seconds or more, for every
call that leaves. Under ordinary traffic a ring of six with no strap loses **100
network calls in 1 000**, and a ring of four 72 (`topo` 7).

**The strap is the `n` bit of a trunk's word**, set on every channel of one link
at both ends (`exch-network.md` §3.3). A seizure is never forwarded into a
strapped link, and one that arrives on it is never forwarded onward. An origin
may still seize it and the far end may still claim, so **the strapped link
carries the calls between its own two ends, and no others.** The links without
the bit must form a tree:

```
 straps needed  =  links  −  exchanges  +  1          a ring: one.  A tree: none
```

**What a ring buys** (`topo` 5, 30 % leaving, six channels):

| | busiest link | pair | lost | channels a call |
|---|---|---|---|---|
| chain of 4 | 1.64 E, 0.53 % | 0.84 % | 0.51 % | 1.67 |
| ring of 4, one link strapped | 1.26 E, 0.16 % | 0.18 % | 0.10 % | 1.33 |
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
- **It is a spare.** If a link fails, move the strap to it and the ring is a
  chain again with every exchange reachable. That is a jumper, or a switch on the
  trunk card, at both ends of two links. Nothing moves it by itself: a trunk card
  takes its dead link out of the hunt, but the strap elsewhere stays until
  someone moves it, and until then the network is in two parts.
- **At the strap's two ends a call between them arrives twice**, once direct and
  once the long way. The direct copy is a hop away and claims first; the origin
  then releases the long way (`exch-network.md` §3.3).

**Loops through hubs** work the same way. A strapped link between a leaf of one
hub and a leaf of the other in §3's network takes that pair's calls off three
links: the mean loss falls from 0.31 % to 0.25 %, and nothing else changes. A
leaf has two directions then, and still 48 lines.

**Two links between the same two exchanges are not a loop if they face the same
way.** They are one direction of twelve channels and one hunt. Jumpered as two
different directions they are a loop of two, and need a strap like any other.

---

## 8. What SS0 would change

`ex-ss0.md` is the alternative to pulse flood: the number crosses each link
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
  (`exch-network.md` §1.1). SS0 needs the S lane, or a pair of its own.

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
(`exch-network.md` §2).

---

## 10. Not measured

- **Uneven traffic.** Calls are spread evenly over the other exchanges. Real
  traffic favours neighbours, which eases the centre and leaves the flood as it
  is, since a flood goes everywhere whatever the call's destination.
- **How many calls leave.** Every limit here moves with it. 20 % and 50 % bracket
  it; a network's own figure is a counter on a working exchange
  (`ex-extensions.md` §4).
- **The guard at the hop limit.** Ten hops at 12 ms rests on the slow marker of
  `exch-monitor.md` §3, which is an estimate. A chain of eleven and a tandem with
  chains of five sit within 8 ms of it.
- **Bursts in the larger shapes.** `net` found that bursts fall on the registers
  in the eight-exchange network. The larger shapes were run with smooth demand.
- **SS0 (§8) has never been run call by call.** Its 0.4 s seizure is arithmetic
  from `ex-ss0.md`'s hop of 26 ms, and its own §10 lists what it has not settled,
  glare among it.
- **A strap moved while calls are up**, and a ring healing: by hand, and not
  modelled.
- **Glare.** Two ends seizing one channel at once is not in the model; the
  opposite-order hunt of `exch-network.md` §1 is assumed to leave it rare.
