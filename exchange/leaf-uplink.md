# The exchange — PBX leaf (offers-tone, no flood on the leaf)

A **leaf** that behaves like a small PBX hung off a **central** exchange: no
network unit and no monitors on the leaf, no pulse flood to the leaf's own
code. Network-wide access is **central's trunk group**, then the leaf's own
dial tone and a two-digit extension. The leaf reaches the rest of the world the
other way: digit `1` hunts an uplink and hears the **central's** dial tone.

No wink, no delay-dial dual-mode, no flood seats on this plant.

> **Status: proposed.** Leaf → central was measured in the retired tree's RTL
> (`make mini-leaf` in `old/verilog/`); newimpl has no LEAF (`mini-marker.md` §9).
> Central → leaf (`1 e b g s` then extension) is the same offers-tone contract
> in the other direction; a full-marker central bench is not yet wired for it.

---

## 1. Plant

Example: central exchange **22**, leaf on MF8 group **70–77** (six working
channels; 70 and 74 free as on any trunk block). Leaf trunks sit at **10–17**.

```
                    network (pulse flood)
                           │
                           │  1 e b h s  →  other exchanges
                           │
                    ┌──────┴──────┐
                    │  central 22 │  full marker + network unit (or mini+unit)
                    │  lines 20–67│  floods land here
                    │  group 70–77│  offers-tone seats → leaf
                    └──────┬──────┘
                           │  MF8 (six channels)
                           │
                    ┌──────┴──────┐
                    │  leaf (PBX) │  mini-marker, no HAS_NET
                    │  trunks 10–17│  on seize: register + dial tone
                    │  lines 20–77│  local h s
                    │  LEAF jumper│  digit 1 = uplink toward 22
                    └─────────────┘
```

| | central | leaf |
|---|---|---|
| Marker | full marker + network unit (owns floods), or mini+unit | mini-marker, **no** network unit, **no** monitors |
| Digit `1` | network key / flood (`HAS_NET`) | **LEAF**: hunt uplink; not highway, not flood |
| This link | class **tone trunk** on 70–77 | ordinary trunks 10–17; seize → caller → dial tone |
| Flood ties elsewhere | class **trunk**, as today | none on this exchange |
| Local lines | `h s` | `2–7` + `s` (and `0` / `8` / `9` as cannot-complete unless fitted) |
| `0` / `8` / `9` on the leaf | as the central is built | cannot-complete unless fitted. The **one-board form** proposed for a leaf (`mini-marker.md` §10; retired tree only) made all three one key: `0` hunted the operator and a misdialled 8 or 9 landed there too, and no prefix 8 or outside-line 9 could ever be told apart from it. Reaching the central over the uplink is unaffected — those pulses are the central's register |

**LEAF** and solo highway-`1` are mutually exclusive with **HAS_NET** on the
leaf. The leaf is not a network code: nothing dials `1 <leaf e b> …` to reach
it.

---

## 2. Numbers

**From anywhere on the network to a station on the leaf:**

```
 1  2  2  7  0     …second dial tone…     e  x
 │  └──┘  └──┘                            └─ leaf extension (two digits)
 │    │     └─ local h s on central 22 → offers-tone port 70
 │    └─ exchange code of the central (claim here)
 └─ network key
```

After the flood claims at 22, `7 0` is an ordinary local connect to port 70.
That port offers dial tone **from the leaf** through the trunk. Further pulses
are the leaf's register, not another flood. The digit budget after key `1` is
still four: `e b h s` = `2 2 7 0`.

**Other ways to the same trunk group** (once you are already on 22): dial
local `7 0` (or hunt a pilot that answers to the group). Same second dial tone,
same extension.

**From a leaf station to the central / the network:**

```
 leaf:  1          uplink hunt; hear central dial tone
        then       local h s on 22, or 0 / 9, or 1 e b h s if 22 is networked
```

**Leaf local** stays `h s` with no trunk touched.

| who dials | string | what happens |
|---|---|---|
| anywhere | `1 2 2 7 0` + `e x` | flood → 22 → port 70 → leaf DT → extension |
| on 22 | `7 0` + `e x` | local connect to 70 → leaf DT → extension |
| on leaf | `2 5` | leaf local |
| on leaf | `1` then `2 1` | uplink; central DT; central local 21 |
| on leaf | `1` then `1 2 3 4 7` | uplink; central DT; flood from 22 to exchange 23 line 47 |

Convention for several leaves off one central: further groups on 22
(`60–67`, `50–57`, …) each tied to another leaf's `10–17`, each dialled as
`1 2 2 g s` with that group's `g s`.

---

## 3. Offers-tone (both ends of this plant)

**Offers-tone is a class, not a bit** (`extensions.md` §2.2): *tone trunk*, the
trunk family's second member, family `01` member 1.

| | | |
|---|---|---|
| class **tone trunk** | on seize (`M · /BUSY`), this port is a **caller**: attach a register, present dial tone. **Not** a pulse-flood hunt/monitor seat | |
| options 5–7 | MBZ `000` — a tone seat faces no direction and carries no glare, because the flood never hunts it. A 1 → OOS | |

On **central 22**, group 70–77 is jumpered class *tone trunk*. On the **leaf**,
trunks 10–17 may say the same, or a mini without a word treats fitted trunks on
that block as tone-access (`TONE0` in the retired tree's RTL site). Flood ties on the central
stay class *trunk*. The network unit and monitors **ignore** offers-tone ports when
seizing or forwarding a flood. One seat, one seize meaning.

A tone seat's whole word is one octet and a `FF` secondary: one '165, like
every other card.

---

## 4. Leaf — digit `1` (uplink)

```
 first key   1   (LEAF)  dial tone off; hunt UPLINK_MASK (block 1 = 10–17)
                        first free (!M · /BUSY) → caller ↔ trunk, both BUSY;
                        register released; mini-marker done
             1   no free uplink → cannot-complete
             2–7        highway h; wait for s   (unchanged)
             0, 8, 9    cannot-complete
```

No `flood_go`. No claim. Pulses after the patch go into the **central's**
register.

---

## 5. Calls

### 5.1 Network → leaf station (PBX access)

```
 anywhere 20          dials 1 2 2 7 0
 flood                claims at 22; register there reads 7 0
 22                   connects caller ↔ port 70 (offers-tone)
 leaf                 M on 1x → register → dial tone on the trunk
 anywhere 20          hears leaf dial tone; dials 2 5
 leaf 25              rings; answer / speech / release as usual
```

Release: either hook falls; the offers-tone latch and the leaf register clear
like any other call. No CLAIM sticky on this path.

### 5.2 Leaf → central local

```
 leaf 20              local dial tone; dials 1
                      hunt; patch 20 ↔ trunk 1x
 central              M on offers-tone mate → register → dial tone on trunk
 leaf 20              hears central dial tone; dials 2 1
 central 21           rings
```

### 5.3 Leaf → somewhere else on the network

```
 leaf 20              dials 1; hears central dial tone
                      dials 1 2 3 4 7
 central              consumes network key; flood toward exchange 23
 23 47                rings
```

The leaf never floods. Central originates the flood as if the caller were a
line on 22.

---

## 6. What this is not

- **Not** a pulse-flood leaf (`HAS_NET` + unit + monitors, `1 <leaf e b> h s`).
  The leaf has no exchange code on the wire.
- **Not** `terminal.md` — leaf lines are not appearances of central's ports;
  they keep a local dial plan and a second dial tone.
- **Not** wink / delay-dial on the same seats as flood ties.
- **Not** dialling `10` as a leaf line number for uplink — `1` alone is the key.
- **Not** five digits of flood to the leaf: `12270` is `1` + `22` + local `70`
  on the central, then a **second** dial-tone stage.

---

## 7. Why the leaf stays a mini

Inbound is only “trunk seized → give dial tone → read two digits → connect.”
Outbound is only “digit 1 → patch to a free uplink.” That is seizure, a
register, and an uplink hunt — what the mini-marker already is, plus **LEAF**
and tone-access trunks. Fan-out, claim attach, and `flood_go` stay off the leaf;
the central pays for the network.

---

## 8. RTL / bench

All of this is the retired tree's (`old/verilog/`). newimpl has none of it
(`mini-marker.md` §9).

| | |
|---|---|
| `mini_marker` | `LEAF`, `UPLINK_MASK`; digit `1` → uplink hunt |
| `marker.v` | trunk option bit 5 → caller path; OOS only on bits 6–7 |
| `net_unit` | flood hunt skips offers-tone |
| `mini_net_site` | `TONE0` / `LEAF`; trunks not in `TRUNK_MASK` when tone-access |
| `make mini-leaf` | leaf → parent dial tone → parent local (half of §5.2) |
| central → leaf | same contract; needs a networked central + offers-tone group in the bench |

---

## 9. Index

| | |
|---|---|
| mini dial plan | `mini-marker.md` §3, §9 |
| trunk word | `extensions.md` §2.2 |
| flood numbering | `network.md` §2 |
| flood ties | `network.md` §1, §3 |
| pulse-flood leaf (the other plant) | `mini-marker.md` §8, `common-control.md` §4 |
| terminal alternative | `terminal.md` (outpost as central's lines, no second DT) |
