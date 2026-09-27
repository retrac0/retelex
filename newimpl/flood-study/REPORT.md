# The pulse flood under load: capacity, overload, races

Study of `newimpl`'s pulse-flood network RTL, 2026-09-26/27.

> Moved here from the gitignored `newimpl/build/flood/`. Scripts, notes and logs still name the old paths
> (`newimpl/build/flood/work/...`, `.../build/flood/rtl`): read them as `newimpl/flood-study/work/...` and
> `newimpl/flood-study/snapshot/rtl`. Build products (obj dirs) were left behind; rebuild with `sim.sh`.

Line references are into the **frozen snapshot**
`newimpl/flood-study/snapshot/rtl/` (HEAD 645f9ef plus the working tree of 00:40 on 09-26). Commit a03a34c has since
changed comments in `rtl/`, so live line numbers may be a few lines off. The evidence (every bench, log, fix
copy and NOTES.md) is under `newimpl/flood-study/work/`.

**How it was done**
- A traffic-load harness, `work/load/load_harness.svh`, drives every line as a random subscriber. Each phone
  sends a signature that survives slips, so the bench knows who hears whom and can classify every call. Its
  WRONG classification was proven on a deliberate misdial and a forged signature. After a drain it checks that
  every port, pool and state machine is idle.
- Five load studies ran on it: capacity, transit, overload, timing, and hub/ring.
- Seven subsystem audits used directed benches.
- Every finding of the first round was put through a verifier that tried to refute it (re-running the
  reproducer at real timers) and one or two independent skeptics. That was 50 agents; nothing was refuted
  except one item.

**Caveats**
- Most load points run at the benches' scale 8. Protocol timers are scaled but the sweep and cable B are not,
  so scale-8 rates are converted by about 6.4–7.2, not 8. Each load point has 15–200 calls, so allow ±25–40 %.
- The timing study and the release audit were stopped before they finished (§7).
- Round-2 findings (§5.3) are reproduced by one agent and not independently verified.

---

## 1. In brief

1. **Capacity is set by the one register an exchange, not by trunks, monitors, resolvers or the unit.** A claim is
   refused whenever the called exchange's register is busy with anything, so refusals track that register's
   occupancy.
   - At the documents' design load (48 lines, 3 calls a line an hour, 30 % leaving) **9–16 % of incoming network
     calls are refused**. The link meanwhile carries 0.5–3 of its 8 channels.
   - Keeping refusals at 1 % needs fewer than about 10 attempts an hour per exchange.
2. **Overload is not graceful: two-way network traffic collapses to zero goodput, and the collapse is metastable.**
   - Each register is held for its own outgoing caller through all of `1 e b h s`, and that is exactly when the
     other exchange's claim arrives. So the two registers refuse each other.
   - Past the knee, carried network calls fall towards 0 rather than levelling off. They stay near 0 until the
     backlog of lines waiting for dial tone gives up.
   - A jammed network side also takes the register from local callers.
3. **Under random traffic, safety and liveness held everywhere.** More than 4,500 attempts were made across two
   exchanges, a three-exchange chain and a hub with a ring, under overload, bursts, abandonment storms, hot spots,
   bad and reserved codes and lone keys:
   - 0 wrong numbers, joined callers or phantom rings;
   - every drain passed its invariant check, with nothing left held.
4. **Directed and fault scenarios break both properties.** Twenty clusters were confirmed in mechanism.
   - The worst are **silent wrong numbers**:
     - a monitor cell that outlives a short seizure (C03), including through ordinary RC tolerance on the
       release detectors;
     - a flood that arrives late at a deep exchange (C05; reproduced **under load at real timers** on an
       eight-exchange chain);
     - a link outage counted as a dial pulse (C07).
   - The permanent **stuck states** are:
     - a phantom seizure that nothing times out (C08);
     - a claim refused after its trunk released (C01);
     - a nogo written after the caller's port released (C17).
   - Most have small tested fixes: a gate, a flip-flop, or at most about two packages.

---

## 2. Capacity

### 2.1 The register is the bottleneck

| study | topology | knee (scale 8) | binding resource | unit pools |
|---|---|---|---|---|
| capacity | 2 exchanges, 8-ch local trunk, 48 lines each | 0.75 attempts/s an exchange (pnet 100 %) | register (occupancy 0.67, half of claims refused) | monitors ≤ 1 of 2; resolvers unused; link ≤ 5 of 8 |
| overload | same | about 1.0 attempts/s (pnet 50 %) | register | never ran out |
| transit | chain A–B–C, local trunks | about 1 attempt/s | the end registers; B never limits | B: nofwd 0, nomon 0, res_max 2 of 2 in 293 floods |
| hub | star H + 3 leaves | between 2.0 and 6.3 attempts/s in total | leaf registers | NRES 2 short at the hub (§2.3) |

**Register time per call, measured and scaled to real timers.**
- A local call holds the register about 2.3 s.
- A network call holds the origin register about 5 s, from dial tone to `N_DONE` at `o_last`.
- A taken claim holds the far register about 2.5 s.
- **A refused network attempt holds the origin register as long as a successful one** (about 4.7 s). The caller
  dials all five digits into silence and hears cannot-complete only after `s`.

**Real-time figures.** These come from a model calibrated on 16 RTL points, checked against a real-timer RTL run
(48 lines, 10 s hold). The ranges assume 0.5 s to 4 s from dial tone to the first pulse.

| load | carried calls/h an exchange | of which network | incoming claims refused | dial tone mean / p99 |
|---|---|---|---|---|
| 3 calls a line an hour, 30 % leaving (design) | 131–135 | 36–38 | **9–16 %** | 0.3–0.6 s / 4.4–6.9 s |
| 6 calls a line an hour, 30 % leaving | 235–250 | 50–67 | 26–37 % | |
| 12 calls a line an hour, 30 % leaving | 371–419 | 42–83 | 44–70 % | |
| 3 calls a line an hour, 100 % leaving | — | 101–112 | 18–29 % | |
| peak at 100 % leaving (6–8 calls a line an hour) | — | 127–180 | 38–66 % | |

The other studies' independent estimates at design load are 15–25 % refused (transit), 15 % (hub) and 16–19 %
(protocol audit).

**One-way against two-way traffic.** One-way traffic (A calls B only) at 1.58 attempts/s: 0 of 15 claims refused.
Two-way traffic at the same load: 57–67 %. Of 175 refusals analysed on the chain, 126 found the far register busy
with **its own outgoing network caller**, 12 with a local caller and 4 with another incoming claim.

### 2.2 Transit resolvers: the model in network.md §10 is wrong

- Every forward, even a chain's one-leg patch, takes a resolver.
- With none free, the seizure is held but not forwarded, and the owner beyond never hears the call. The caller
  hears cannot-complete at `T_CLAIM`, and the lost forward costs about 4.5 s of trunk and caller time.
- With one register an exchange, **at most one flood per source exchange is pending at a transit**. So the loss
  follows Engset in the number of source exchanges, not Erlang B:
  - measured on the chain with NRES = 1: 22.9 % lost, against 22 % predicted;
  - measured with NRES = 2: 0 of 293.
- Extrapolated, with u the source register's network occupancy:

| NRES | sources | lost at u = 0.25 | at 0.5 | saturated |
|---|---|---|---|---|
| 2 | 3 | 1.2 % | 4.8 % | 19 % |
| 2 | 4 | 3.2 % | 11 % | 36 % |
| 2 | 8 | 15 % | 36 % | 67 % |
| 3 | 4 | 0.1 % | 1.1 % | 8.5 % |

§10's 1.4 % should be replaced by this.

### 2.3 Hubs and pools

- **At a hub, NRES must be at least the number of leaves.** With NRES 2 at a three-leaf hub, 1 of 30 floods was
  lost at light load and 26 % at overload. With NRES 3, 0 of 44.
- **The hub's monitor cells are shared by every flood in the network.** Each flood holds a cell until its `e` is
  decided, about 0.9 s real, so a call *to* the hub is lost when two other floods are in that window. A leaf needs
  NMON 3 once the hub also originates (2 calls were lost to no free cell).
- **Spokes need channels ≥ talking calls + number of leaves**, because a flood holds a channel on every spoke until
  its claim. On 2-channel spokes, 29 of 81 attempts found no trunk. A fan-out into a full spoke silently misses the
  owner behind it: the caller waits out `T_CLAIM`, and a resolver and the other spokes' channels are held
  meanwhile.
- **Losses to the single forwarder happen only at scale 8.** At real timers the 18 ms `T_ARM` watch spaces
  classifications further apart than the 10.6 ms forward takes: 0 of 27 lost, crossings included.
- **Leaves sweep for nothing.** Every seizure at a leaf runs a 10 ms forward sweep that finds nothing and increments
  `n_nofwd`, so `n_nofwd` cannot tell a lost flood from a leaf. Strapping a leaf's absent directions (STRAP_N, no
  parts) stops it; tested on tb_chain.

### 2.4 Hop timing and the guard's reach, measured

**One transit hop.**
- About 13 ms: 2.1–2.9 ms to classify, then 10.6–10.8 ms to the forward write.
- A second flood that arrives within 18 ms waits out the hold watch: 18.5–21 ms.
- Behind another sweep: about 30 ms.

**Reach of the 128 ms guard**, measured at real timers on an eight-exchange chain:
- 8 hops with no slow event;
- 7 hops with one;
- **4–5 hops against three compounding slow events** in a burst of coincident keys.

A conforming 720 ms pause between digits leaves about 590 ms of margin, so this matters only for fast diallers (a
data card pulsing DTR) or deep networks. §10's "4–5 hops" is right for the compounding case and pessimistic for
the typical one.

---

## 3. Overload

**Scale 8, two exchanges, pnet 100 %** (OK calls a minute an exchange):

| offered attempts/s an exchange | carried | claims refused | no dial tone |
|---|---|---|---|
| 0.5 | 13.1 | 50 % | |
| 0.9 | 17.5 | 57–67 % | |
| 1.8 | 2.5 | 93 % | 19 % |
| 3.2 | **0** | 97 % | 42 % |

- The chain behaves the same way: 5 of 119 network calls completed at 2.2 attempts/s, and 3 of 139 at 3.1–3.5.
- The hub completed 0 of 212 at 21 attempts/s.
- At real timers, about 1000 attempts an hour per exchange carried 1 call a minute for both exchanges together.

**Why it collapses.**
- A refused network attempt holds the origin register to `o_last` (net_unit.v:881, :410).
- A claim is refused the instant it finds the register busy (mini_marker.v:282).
- A freed register is re-taken by the next waiting line within one scan pass.
- So a claim succeeds only if it lands in about 1 ms of each register cycle. At overload, 64–96 % of all register
  time goes to network attempts that are then refused.

**It is metastable.**
- A 5 s burst followed by a load *below* the hub's good operating point completed no call for the next 15 s; the
  registers stayed 100 % busy for about 9 s.
- Nothing is latched. Recovery takes about one dial-tone timeout: 3 s at scale 8, 15–20 s real. That is how long
  the backlog takes to clear by callers giving up.

**Local service suffers.**
- With half the lines retrying network calls, lines numbered above them got no dial tone at all. Lines below got
  it 5.7× slower, and half their calls found the called line BUSY.
- Service is lowest port first, because almost every register release lands on `tick_1k` (scan 00). At 4× load,
  blocks 2x see about 5 % no dial tone and blocks 5x–7x about 100 %.

**Fewer trunks carry more.** Two baseband channels carried 7× what eight channels carried at the same overload:
callers who find no trunk give up at the key and free the register.

**Everything pathological was bounded.**
- A hot spot: every network caller refused by the hot line's own exchange.
- A bad code: `T_CLAIM`.
- Reserved `1 8`: refused at `e`.
- A lone key: `T_KEY`.
- `1 e b` of a real code, then nothing: held to `NODIG` (about 13 s of register at real timers).
- An own code: turns local.
- A burst of all 96 phones lifting in one millisecond: one caller served every 0.46 s per exchange, and 86 % with
  no dial tone in 3 s.
- Abandonment storms, with 78 hang-ups at every phase of the call: no leak.

**What changes the collapse.**
- **Connect at the claim.** At net_unit.v:881 write `if (claimed && dmo == 0) nst <= N_DONE;` and drop `o_last`;
  this *removes* gates.
  - Tested: 10× the goodput at overload, no caller left without dial tone, and the refusal heard at once instead
    of after `h s`.
  - A crossing pair loses one call, not two.
  - It also shrinks C11's window from about 2 s to milliseconds.
  - It still collapses further out.
- **Graceful saturation**, in the model, needs the called register out of the claim path: the monitor cell reads
  `h s` itself, or registers are pooled.

---

## 4. Safety and liveness under traffic

| study | attempts / floods | wrong, joined, phantom | invariants after drain |
|---|---|---|---|
| capacity (16 runs) | 625 calls | 0 | 416 / 416 |
| overload (23 runs) | 2832 attempts | 0 (one harness artefact) | all PASS |
| transit (13 runs) | 357 floods into B | 0 | 38 / 38 each run |
| hub and rings | 888 attempts | 0 wrong; **1 joined pair** (C13 leg glare, 2-channel spokes about 80 % busy) | 50 / 50 each run |
| timing (8-exchange chain, real timers) | directed bursts | **wrong numbers reproduced** (below) | 98 / 98 |

**Timing study.**
- Coincident keys through seven hops, with a key-to-`e` gap of 120–153 ms, produced a **false claim and a wrong
  number** by the C05 mechanism: a late-arming monitor counts `e` short. This held with pools of 4 and at
  ±1000 ppm crystals.
- With the default pools of 2, the same dialling gives a lost call: the pool ran out before the design did.
- A second shape, a re-seized trunk at the same depth, rang the wrong line twice.
- The C_LOW fix (§5.1, C05) turned every one of these into a lost call.

**Release sweep** (the release audit's hang-up sweep across a transit call; 263 trials at scale 8):
- Call set-up and connect never leak.
- Every leak it found sits at a timer boundary, which is the C17 family: `T_KEY − T_REL`, `T_CLAIM`, `NODIG`. Fix B
  of C17 closes all of them.
- At real timers, with the transit's port `T_REL` at 80 % of nominal (205 ms against the cells' 256, an RC
  tolerance), **6 of 9 trials gave a wrong number**. That is the C03 RC variant, and the C03 fix (b) closes it.

---

## 5. Verified defects

Severities are as the verifier and skeptics settled them for real timers, usually *lower* than the auditors' when
the trigger needs a fault or non-conforming dialling.

### 5.1 Wrong numbers and cross-connections

| id | defect | real-timing trigger | severity | fix (cost), tested |
|---|---|---|---|---|
| **C03** | A seizure written away inside `T_ARM` (C_UNHOLD, net_unit.v:590-594) **keeps its monitor cell** (freed only at CLR, :647-649). A re-seizure of the channel within 256 ms gets a second cell. The stale cell counts the death plus the make as a digit `1`, then claims the new call one digit out of step. The RC variant: the far port releases before this port and its cell. | A short seizure (a guard abandon, or glare taken as a claim), then a re-seizure within CLR: likely under load, since the forwarder re-picks the lowest free channel. RC tolerance alone: 6/9 wrong in the sweep. | **high** | (a) `cls_cell`, one FF a cell, frees it at the unhold; (b) the cell lets go on a break ≥ ID (one gate). About 1 package. tb_net 88/88; closes the RC variant. `work/audit/monclaim/fix.patch` |
| **C05** / C04 | Nothing bounds a flood's age at arrival. The C_HOLD watch (:584-588) **unholds on a dial break**; the make is re-seen as a fresh seizure and a new cell counts `e` short. The serialised classifier (18 ms a seizure) and slow hops make it later. | A fast dialler or a deep network; reproduced under load at 7 hops. | medium | **C_LOW state**: M low in C_HOLD waits; back up restarts the watch; low for CLR unholds. **0 packages.** tb_net 88/88. `work/verify/C05-*/rtl_fix` |
| **C07** | A link outage of 8–256 ms is a dial pulse to every monitor and register beyond (baseband_card.v:154, local_trunk.v:188). An outage of 256 ms or more that ends mid-dial is a fresh seizure counted from mid-number. | A re-seated cable, an MF8 re-lock, or a hit during `e b` or `h s`. | medium | Make an outage a release on the card, never a pulse. The audit's card fix misses one-way outages; the verifier's version (`work/verify/C07-*`) is complete. |
| **C11** | A claimed trunk lost before `N_DONE` is never noticed. The caller is latched to a dead channel (no edge) and **overhears** whoever takes it next. | A link flap or far reset between claim and last digit. | medium | Watch the claim (`lost` counter, persistence about T_REL/2); or connect at the claim (§3), which closes most of it. |
| **C12** | The origin takes **one M sample on any held trunk** as the claim, even long before `b` (:795-804). | Needs another fault (C03 or C13) first. It is the missing second line of defence. | medium | The claim is M for 4 samples, and before `b` only inside the guard (glare). tb_net, chain, lfull pass. |
| **C13** | Glare on a forward leg: the transit's resolver takes the far origin's M as the claim (R_LEG, :683-686) and **joins two strangers**. Nothing counts it at the transit. | Residual glare (last free channel, both ends within about 1.35 ms). Seen once under load on 2-channel spokes. | low–medium | Watch the kept trunk until connect (F3', about 1 package); count EV_GLARE at the transit. |
| C06 | A break between the key being recognised and the seizure write is unguarded (`r_brk` checked only in N_NET/N_WAITCL, :862). | A key-to-`e` gap of about 128–160 ms and a single-pulse `e`. | low | Sticky `o_brk` (1 FF): abandon at `h_done`. Tested. |
| C02 | A claim queued behind another, or behind S_WATCH, attaches the far register mid-`h`. | Non-conforming pause, or a faulty local line. | low | Delete `&& (state != S_WATCH)` at mini_marker.v:282 (and marker.v:273). Closes C01 too. tb_net 88/88. |

### 5.2 Stuck state and leaks

| id | defect | trigger | severity | fix, tested |
|---|---|---|---|---|
| **C08** | **No timeout anywhere on the unit.** A seizure that never falls or pulses (a stuck A conductor) holds a monitor, a resolver and a channel on every link it floods, for good. | A single-conductor fault. Permanent and silent. | **high** (one skeptic: critical) | A 2-bit age per cell and per resolver on a shared T_KEY strobe, expiring at 2–3 × T_KEY. tb_net and tb_chain identical to baseline. |
| C01 | A claim waiting out S_WATCH is refused one tick late on a stale `r_busy`. If the WATCH is long (a chattering line) and the far caller has gone, the refusal's `03/BSY/CLM` lands on a released trunk: **BUSY for ever at both ends, plus a phantom seizure** next door. | A chattering line at the owner plus a far abandon. Cumulative. | medium | A hook-gated wait: `... && !r_release && ((state != S_WATCH) \|\| !r_hook)` (2 gate inputs), or C02's delete. Tested at real timers. |
| C17 | A nogo, or NODIG's cannot-complete write, lands after the caller's port released itself: the line stays BUSY listening to 03 until next lifted. | Hang-ups at the `T_KEY − T_REL`, `T_CLAIM` and `NODIG` boundaries. Found by the sweep. | medium (skeptic: high) | Fix B: gate those BSY writes on `r_hook` (mini_marker.v about :405, :521, :545). Sweep 0 leaks; tb_net and tb_chain pass. |
| C10 | A resolver whose incoming link goes down (MUTE_BLK keeps BUSY) outlives its call; its stale legs later cut or re-point live calls. | An outage of 256 ms or more during a forward. | medium | Per-leg seen-busy / seen-free FFs (about 2 packages). tb_net 88/88. |
| C09 | F_WRITE ignores `f_cancel`: a seizure on port 77 dying at the sweep's end leaves 77 and its leg BUSY and a resolver held. | One port in 64, one pass in about 18. | low | `if (f_cancel) fst <= F_IDLE` in F_WRITE: one gate. 7/7. |
| C18 | A claim after the origin dropped that trunk, or after a resolver resolved, is taken as a fresh seizure. | Rings or unequal paths, at the `T_CLAIM` boundary. | low | Gate `m_want1` on the cell's own M (one AND a cell). |
| C20/F4 | Drop-then-reseize is closed by only 0.1–0.3 ms on today's cards. A slower-falling A on a future carrier (MF8, pots trunk) reopens C03. | Carrier-dependent. | medium, latent | A design decision: a hunt hold-off per port. |

### 5.3 New in round 2 (classifier audit, reproduced at real timers, not independently verified)

- **word-read-across-link-hit:** a link hit during a word read can only clear bits, so it tears the word. Then either
  the marker takes a flood trunk as a caller, or the unit drops the seizure and re-takes it mid-digit, or it
  forwards the flood back the way it came.
- **classifier-overwrites-origin-seizure:** `mine` does not cover the sweep's candidates. A short far seizure on the
  origin's candidate makes C_ACT, then C_UNHOLD, hold and then free the trunk the origin has just seized.
- **st-cleared-by-dial-break:** on an unheld trunk, the make after a dial break is a fresh seizure, mid-number.
- **classifier-scan-order-priority:** after every hold watch the classifier restarts at port 00. A high-numbered
  trunk can be overtaken without bound and picked up after its first break (feeds C05).
- **marker-connects-caller-to-dead-trunk:** a trunk whose link is down (word NONE) is still connected to, and the
  caller's pulses go out when the link returns.
- **confirm-no-second-choice:** one candidate per direction, so a far seizure of it before CONFIRM costs the whole
  direction while other trunks that way are free.
- Fix sets for these are in `work/audit/cls/fix/` and `fix2/`, which passed tb_net; the chain and lfull
  regressions were not run.

### 5.4 Lesser, and refuted

- **Low (confirmed):**
  - the marker re-reads an unheld trunk every pass (C16), blinding it to the 8 ports after it;
  - the refusal is heard only after `h s` (C15);
  - WAIT is a hand constant with 93 ticks of margin;
  - nothing enforces that port 00 is unfitted, which every hold and idle convention depends on;
  - rings: an unstrapped ring is bounded only by resources, and a one-end strap does not stop double delivery
    (C19; a doc fix; strapped at both ends it completes once, verified).
- **Refuted:** the claim-leg slot collision with two resolvers (not a bug).

---

## 6. Improvements, in order

1. **Connect at the claim** (net_unit.v:881, delete `o_last`). It removes gates, gives 10× the goodput at
   overload, lets the refusal be heard at once, halves mutual refusal and shrinks C11. Tested.
2. **Take the called register out of the claim path**, or pool registers. This is the only change that makes
   saturation graceful in the model, and the real capacity fix. Also consider refusing a network key when the
   register has been held back to back, to protect local service.
3. **Close the wrong-number paths**, all tested:
   - C03: cell ownership plus a long-break drop (about 1 package);
   - C05/C04: the C_LOW state (0 packages);
   - C07: an outage is a release (on the card);
   - C12: claim persistence (a few FFs);
   - C06: `o_brk` (1 FF).
4. **Timeouts and edges**, all tested:
   - C08: 2-bit ages on cells and resolvers;
   - C17: the `r_hook` gate;
   - C01/C02: drop the S_WATCH exemption, or gate it on hook;
   - C09: one gate;
   - C10: leg watch.
5. **Sizing:**
   - NRES ≥ the number of source exchanges (leaves) at every transit and hub;
   - NMON 3 at a hub or where the hub originates;
   - spoke channels ≥ talking + leaves;
   - strap a leaf's absent directions so it stops sweeping and `n_nofwd` means something.
6. **Documents** (for telco-e3, who owns them now):
   - network.md §10: resolver loss is Engset in single-register sources, not Erlang B's 1.4 %; the guard covers 7–8
     hops typically and 4–5 compounding;
   - the refusal rate of the one register belongs in §3.4 / register.md §4. "A busy register only delays dial
     tone" is true for local callers and wrong for claims;
   - old §3.2's "no resolver: patch into the first direction" is not what the RTL does;
   - §7 should say what a one-end strap costs.
7. **Benches.**
   - Every scale-8 tree bench is green while all of the above ship. Scale 8 cannot test the guard's reach or the
     forwarder's timing, and overstates forwarder losses.
   - Add real-timer directed benches for C01/C03/C05/C07/C08/C17, a fault in `faults.py` for each fix, and a short
     run of the load harness as a regression.
   - Harness artefacts to discount: the `marker_state` STUCK watchdog under saturation, and NOSPEECH on 14–18 ms
     talks.

---

## 7. Not finished

- **Timing study** (`work/load/timing/NOTES.md`): stopped mid-run. Its wrong-number reproductions and guard-reach
  measurements (§2.4, §4) are in its notes; it never returned a structured report.
- **Release audit** (`work/audit/release/NOTES.md`): stopped mid-run. The sweep results (§4) and the C17 and C03
  confirmations are in its notes.
- **Round-2 findings** (§5.3, and the load studies' new items: network-jam-denies-local-service,
  partial-fanout-into-full-spoke, trunk scarcity as admission control): not independently verified.
- The hub study ran at scale 8 only. Real-time capacity figures rest on a model calibrated on RTL points, checked
  against two real-timer runs.

## 8. Where things are

| | |
|---|---|
| snapshot RTL and benches | `newimpl/flood-study/snapshot/{rtl,tb}`; the old docs are exchange/ as of 645f9ef (before a03a34c) |
| load harness | `work/load/load_harness.svh`, `tb_load2.sv`, `tb_load2b.sv`, `tb_load3.sv`, `smoke/` |
| load studies | `work/load/{cap2,transit,overload,timing,hub}/` (NOTES.md, models, logs) |
| audits | `work/audit/{cableb,monclaim,origin,fwd,proto,cls,release}/` |
| verification | `work/verify/C01…C20/` (benches, fix copies, logs); `verify_results.json`; `clusters.json` |
| raw results | `work/wf1_results.json` (round-1 audits), `work/wf2_partial.json` (loads and classifier audit) |
