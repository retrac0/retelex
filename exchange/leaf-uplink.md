# The exchange — leaf uplink (mini → full dial tone)

A **fixed** way for a mini-marker exchange with **no network unit** to reach a
parent that runs a full marker (or any marker that offers dial tone on seize).
No wink, no delay-dial dual-mode, no pulse flood on the leaf.

> **Status: proposed, measured in RTL.** `make mini-leaf` — leaf mini dials `1`,
> hunts block 1, hears parent dial tone, dials a parent local number. Word bit
> and full-marker behaviour are specified here; the bench uses a mini parent
> that treats fitted trunks as tone-access (no flood mask).

---

## 1. Roles

| | leaf | parent |
|---|---|---|
| Marker | mini-marker, **LEAF** jumper, **no** network unit | full marker (or mini without net) |
| Digit `1` | hunt first free **uplink** trunk in block 1; patch; done | unchanged (highway, flood, or local — not this path) |
| Trunks on the link | ordinary trunk appearances; leaf does not flood | **offers-tone** seats only on this plant |
| After patch | caller listens through the trunk | seize → register → dial tone on the trunk |

The leaf keeps local `2–7` + `s`. Solo highway-`1` (10–17 as lines) is the
other jumper position: **LEAF** and solo are mutually exclusive with **HAS_NET**.

---

## 2. Parent — offers-tone word bit

Trunk class form (`extensions.md` §2.2): primary options `t 0 0`.

| bit | | |
|---|---|---|
| **5** `t` | **offers-tone** | on seize (`M · /BUSY`), this port is a **caller**: attach a register, present dial tone. **Not** a pulse-flood hunt/monitor seat |
| 6–7 | MBZ | a 1 → OOS as today |

Flood ties keep `t = 0`. The network unit and monitors **ignore** offers-tone
ports when seizing or forwarding a flood. One seat, one seize meaning.

Secondary direction/glare unchanged (`tag 10`, `ddg`).

---

## 3. Leaf — digit `1`

```
 first key   1   (LEAF)  dial tone off; hunt UPLINK_MASK (block 1 trunks)
                        first free (!M · /BUSY) → caller ↔ trunk, both BUSY;
                        register released; mini-marker done
             1   no free uplink → cannot-complete
             2–7        highway h; wait for s   (unchanged)
             0, 8, 9    cannot-complete
```

No `flood_go`. No claim. The handset (or a dialling card) then pulses into the
**parent's** register: local `h s`, `0`, `9`, or `1 e b h s` if the parent is
networked.

---

## 4. Call

```
 leaf 20 lifts          local dial tone
 dial 1                 hunt; patch 20 ↔ trunk 1x
 parent                 M on offers-tone trunk → register → trunk ← 01
 20 hears               parent's dial tone through the trunk
 dial 2 1               parent's local call; 21 rings
 answer / speech / release as usual
```

---

## 5. What this is not

- Not a pulse-flood leaf (that is `HAS_NET` + `mini-marker.md` §8).
- Not wink / delay-dial on the same seats as flood ties.
- Not “dial `10` as a line number” on the leaf — `1` alone is the uplink key.

---

## 6. RTL / bench

| | |
|---|---|
| `mini_marker` | `LEAF`, `UPLINK_MASK`; digit `1` → uplink hunt |
| `marker.v` | trunk option bit 5 → caller path; OOS only on bits 6–7 |
| `net_unit` | flood hunt skips offers-tone |
| `make mini-leaf` | leaf LEAF + parent tone trunks, one MF8 link |

---

## 7. Index

| | |
|---|---|
| mini dial plan | `mini-marker.md` §3, §9 |
| trunk word | `extensions.md` §2.2 |
| flood ties | `network.md` §1, §3 |
| terminal alternative | `terminal.md` (outpost as parent's lines) |
