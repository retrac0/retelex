# Release / stuck-state slice -- running notes (successor agent, 2026-09-26)

Directory: work/audit/release/.  Snapshot RTL only (rtl/, tb/ under build/flood).

## State inherited from the cut-off agent (read 2026-09-26 afternoon)
- tb_rel.v: hang-up sweep, 3 sites A-X-B (+stub S link at X), families 0-10.
- tb_rc.v: tb_rel.v + per-site T_REL (TRELA/X/B) + family 11 (re-seizure of a
  trunk inside the far end's release) + PHANTOM counts only >2 ms of RB.
  tb_rc.v had NEVER been built when the agent stopped.
- batch.sh ran: build base (tb_rel.v) OK; smoke (fam 2, 2 trials) OK
  (run_smoke.log: REF PHANTOM there was the old 1-tick blip rule, fixed in tb_rc).
- run_A_timers.log (tb_rel.v, fams 8+9): family 8 COMPLETE (25 trials),
  family 9 never started (killed).
  * fam 8 = pattern 1 (dial 1 3 2, nobody answers), A20 hangs up T_REL before
    A's T_CLAIM: LEAK at k=10..15 (d = 217.50 .. 218.75 ms after f2), i.e. a
    ~1.5 ms window.  State: A20 addr=03 bsy=1 BUSY=1, everything else idle.
    Lifting A20 once clears it (hears zeros = 03).  == cluster C17 reproduced
    at scale 8 (T_CLAIM nogo written after the caller port released itself).
- rtl_fix/mini_marker.v: the r_hook gate on the three timer/nogo BUSY writes
  (C17's alternative fix).  Never built.
- batch3.sh (tb_rc.v, trimmed sweep) and batch2.sh NEVER ran (no status files).
- No obj dirs left.

## My runs (newest last)

### Setup changes (successor)
- tb_rc.v now has +define+SCALE1 (real timers: T_ARM 16, T_REL 256, HIT 8, ID 128,
  CLR 256, NODIG 10000, guard 128, T_KEY 5000, T_CLAIM 2000; bench waits x8,
  dial 60/40, STAB 160 ms idle).  tb_rc.v.orig = the cut-off agent's version.
- tb_rc.v family 12 (pattern 5): A20 keys 1, dials e=1 (B's cell has e, waits
  for b), hangs up at t_h; X20's key makes at t_h + d; X's sweep seizes the
  lowest free E trunk (X13 -> B11) and X20 dials 2 1 2 0.  B21 rung = WRONG
  NUMBER (C03 rc-tolerance-reseize), needs X's port RC faster than B's cell CLR:
  build with +define+TRELX=9'd26.
- tb_j1.v = frozen copy of tb_rc.v for job 1 (batch4.sh).
- Job 1 = batch4.sh (scale 8): S3 S4 S7 S10 S2 S1 S5 S6 S9.  Queued 15:1x.

### Write table (reasoned from the snapshot RTL; see final report)
(filled in as the analysis goes)

#### Write -> edge table (snapshot line numbers)
Port rule (port.v:156-194): latch cleared only on a FALL of fM (own M low T_REL,
armed only after M stood T_ARM) or fE (listened-to M low T_REL, same arming).
BUSY = bsy | fE | fM&!M | MUTE (port.v:147).  Tone ports 01/03 have M = 0
(site_net s_a), so a port listening to 01/03 has no fE ever.

| write (where) | lands with | cleared by | always an edge? |
|---|---|---|---|
| HOLD p<-00 B (net_unit 609-611) | p's M up (just classified) | fM fall; if M dies < T_ARM the C_HOLD watch (584-588) UNHOLDs | yes, watch = push+T_ARM+2 > rise+T_ARM. Dial break inside the watch = C04 |
| UNHOLD p<-00 !B (590-594) | - | frees | yes; but F_WRITE after it re-holds (C09) |
| CLAIM p<-00 B C (656-671) | at the cell's b strobe: M up ID ms | fM fall | yes IF not delayed: w_claim waits cl_st==IDLE (487), a long att wait (C01/C02) can push it past p's own release (window: T_REL..CLR+1 ms) -> CLM on a free port, phantom at neighbour.  Variant of C02, not run |
| refusal p<-03 B C (mini 320-327) | att answered | fM fall | NO if the wait outlasted T_REL (C01) |
| origin seize t<-caller B (808-816) | caller M up (key+sweep) | fE fall (caller M) / fM fall (claim) | if the caller already left: e never rises -> held until N_DROP at o_gone (859) = CLR: covered |
| origin drop t<-00 !B (823-837) | - | frees | yes; late far claim after it = C18 |
| N_DONE caller<-trunk B (818-822) | caller M up (o_last strobe) | caller fM fall / fE fall (trunk M) | yes, unless the trunk M already gone (C11) |
| forward leg<-in B (725-729) | in's M up (normally) | leg fE fall (in's M) | if in's M died first: leg e never arms -> R_GONE drop (688-698) covers; one-leg way back re-holds in (C09) |
| way back in<-leg B (732-736, 701-705) | - | in's fM fall | yes (in's fM armed) except C09 |
| resolver drops leg<-00 !B (694-698) | - | frees | yes |
| marker dial tone caller<-01 B | caller M up | caller fM fall; blip < T_ARM -> COLLECT r_gone writes 00 !B (396-403) | yes |
| key caller<-00 B (428) | M up (strobe) | fM fall | yes |
| YIELD nogo caller<-03 B (515-523) | TIMER (T_KEY/T_CLAIM/nodig) | fM fall | NO if the caller released in (T_REL, gone] ~1 ms: C17 (reproduced run_A fam 8) |
| COLLECT nodig caller<-03 B ctx_clm (404-410) | TIMER | fM fall | NO, same window; on a CLAIMED TRUNK it is 03+BSY+CLM -> backward A for ever -> phantom seizure at the neighbour.  Family 10 tests it (NEW?) |
| WATCH nodig caller<-03 B ctx_clm (542-548) | TIMER (chattering line) | fM fall | NO, same window (rare: chattering line) |
| COLLECT/PROBE/READ refusals caller<-03 B | digit strobe / read ~2 ms later | fM fall | yes (T_REL >> read) |
| connect called<-caller B, caller<-called B C (487-490) | M up | fE/fM falls; WATCH writes called free on gone (542-548) | yes |
| gone writes caller<-00 !B | - | frees | yes |

### Job chain (one sim.sh slot, runs sequentially)
- batch4.sh (job 1, tb_j1.v, scale 8): lint of tb_rc.v (3 variants) then
  S3 S4 S7 S10 S2 S1 S5 S6 S9; at its end runs next1.sh if present.
- next1.sh (job 2, tb_j2.v): S12x26 (fam 12, X T_REL 26), FIX10 + FIX8 (rtl_fix
  r_hook gate), S12eq (control).  Then next2.sh.
- next2.sh (job 3, tb_j3.v, SCALE1): R12x205, R10 (NODIGR 3000; window to fill
  from S10), R2, R1.
- Status files: batch4.status, next1.status, next2.status.  Logs run_<name>.log.

#### Pools / state machines: what returns each to idle (reasoned)
- classifier cst: C_READ/C_WAIT wait for the reader (bounded, a pass + 9 frames);
  C_ACT/C_UNHOLD wait for w_cls (room; only w_claim outranks) -> bounded; C_HOLD
  exits at cls_ms > T_ARM+1 (net_unit 587) -> bounded (18 ms real).  SOUND.
- sweep hst: 64 reads + 1 pass; h_issue yields to cls_issue each step, but a
  port is classified once per M rise (st bit) -> bounded.  SOUND.
- forwarder fst: F_WANT waits hst idle & nst != N_WANT (both bounded); F_HUNT
  ends at h_done; F_WRITE waits w_fwd, whose rs_free_any held since C_ACT (only
  F_WRITE takes resolvers).  SOUND for liveness; C09 (ignores f_cancel) = leak.
- origin nst: every N_NET/N_WAITCL exit has a timer or o_gone (r_gone|r_nodig|
  !r_busy); N_WANT/N_HUNT bounded by the sweep.  SOUND.  flood_go is accepted
  only in N_IDLE, but the origin is back in N_IDLE ticks after the register is
  freed, long before another key can be dialled.  SOUND.
- cl_st/att: CL_WAIT waits q_empty (bounded); CL_ACK waits att_ack: bounded
  except in S_WATCH (C01/C02).
- monitors: freed by e/b mismatch, claim, or d_clr (CLR of break).  No timeout
  on a steady M (C08).  Cell survives an UNHOLD (C03).
- resolvers: freed by R_LEG, R_GONE, or the claim (rs_mine).  R_GONE needs the
  incoming !BUSY: never under MUTE_BLK (C10), or after C09's way back.
- marker: YIELD exits on gone/local/done/nogo/nodig; WATCH on gone/nodig/
  settled; COLLECT on gone/nodig/digits.  All bounded by NODIG.  SOUND.
- register: released by the marker on every exit path.  SOUND.

### 17:55 slot situation
- All 5 sim.sh slots are held by other agents' queue runners (load/hub, load/transit,
  load/timing, load/overload, load/cap2) that append work; job 1 waited 2.5 h.
- Job 1's waiter re-launched DETACHED (setsid nohup ./sim.sh bash batch4.sh >
  batch4.out) so it survives this session ending.  It chains next1.sh and
  next2.sh in the same slot.  A successor: read batch4.status / next1.status /
  next2.status and the run_*.log files (./summ.py run_X.log summarises).

### Draft findings (update with results)
1. C17 REPRODUCED (run_A_timers.log fam 8): T_CLAIM nogo lands after A20 released;
   window hang-up in [T_CLAIM-T_REL-0.5, T_CLAIM-T_REL+0.75] ms after f2
   (217.50..218.75, 6 of 25 trials at 0.25 ms); A20 addr=03 bsy=1 BUSY=1; a lift
   clears it.  Same write (mini_marker 515-523) serves T_KEY (fam 9) and nodig.
2. NEW? trunk variant: COLLECT nodig (mini_marker 404-410) on a CLAIMED TRUNK
   writes 03+BSY+CLM; if the far caller left T_REL..gone before -> no edge AND
   backward A = 1 for ever -> neighbour classifies a phantom seizure (hold +
   monitor + forward), permanent.  Family 10 (S10) tests; fix = r_hook gate
   (rtl_fix/mini_marker.v, FIX10).
3. C03 rc-tolerance-reseize: family 12 (S12x26 vs S12eq): abandoned flood after
   e, X's ports 20 % fast, X20's flood re-seizes X13 inside B's cell CLR ->
   B's stale cell counts the gap as b = 1 and claims -> B21 rung for X20 (who
   dialled 2 1 ...): wrong number.  Real-timer window ~ CLR - T_REL_fast - sweep.

## RESULTS
### S10 (scale 8, fam 10 = dial 1 1 1, B claims B11, nobody dials on; A20 hangs up d ms after B's att_ack), job 1 started 21:51
- k=4 d=1214.22: LEAK, BOTH writes after release:
  A20 addr=03 bsy=1 BUSY=1 (A's YIELD nodig, = C17 mechanism via r_nodig);
  B11 addr=03 bsy=1 clm=1 m=0 (B's COLLECT nodig, mini_marker 404-410) ->
  backward A for ever -> X13 held as a NEW incoming seizure (addr 00 bsy 1 m 1),
  X monitor on 13, X resolver in=13 legs X12 + X30 (both addr 13 e=1), A12 held
  (m=1) with A's monitor.  Still identical 1 s later (after A20's lift cleared
  A20).  PHANTOM FLOOD, PERMANENT.  == NEW finding (trunk variant of C17 with
  C01's consequence).
- S10 so far (0.43 ms steps): k=0..3 (d 1212.50-1213.79) OK; k=4..9 (1214.22-1216.37)
  LEAK A20+B11(+phantom flood X13/X12/X30/A12); k=10 (1216.80) LEAK B11 only;
  k=11,12 (1217.23, 1217.66) OK.  B-window >= 2.6 ms wide, A-window >= 2.2 ms.
  Why wider than 1 ms: pulse_rx clear fires 32 ticks after its DETECTION tick
  (t reset to 0 there, clear at t==31 a tick later) vs the port's fM falling at
  the 31st tick after the fall, plus the probe's 0-1 tick detection lag, plus
  fabric E-capture once a pass per hop: gone lags the release by 1-2 ticks.
  Tick-based, so the same width at real timers.
- S10 DONE 22:32: 17 trials, 7 LEAK (k=4..10), 0 PHANTOM, 0 LATE, 0 clashes.
  k=11..15 OK.  B11-stuck window d in [1214.22,1216.80] (bounds 1213.79/1217.23):
  2.6-3.4 ms; A20-stuck window [1214.22,1216.37]: 2.2-3.0 ms.
  i.e. hang-up at NODIG - T_REL - (1.2..3.8) ms after B's attach.

### S12x26 (scale 8, fam 12, X's ports T_REL 26, cells CLR 32, B T_REL 32)
- d = X20's key make - A20's hang-up.  d <= 1.91: X's sweep finds X13 not yet free,
  seizes X15 (-> B12, fresh, counted right) -> no claim, fine.
- d = 3.04, 4.17, 5.30 (X seizes X13 at t_h+30..32 ms): B's STALE cell on B11
  (A20's abandoned flood; e=1 counted) counts the gap as b=1, claims at t_h+49..51,
  B's register takes X20's "2 1" as h s: B21 RINGS (359835 ticks = 88 ms+).
  WRONG NUMBER, 3 of 17 trials.  (X's origin was claimed by it: +50.19 at d=3.04.)
- d >= 6.43: X13 re-seized at +33 or later, after B's cell CLR: no claim.
- "X claimed" column after d=3.04 is stale (claimed reg is not cleared at N_DROP;
  bench artefact, ignore).
- => C03 rc-tolerance-reseize REPRODUCED (was reasoning only).  Window at scale 8
  ~3.4 ms of key time with X 19 % fast; at real ~ CLR - T_RELX - ~4 ms.
- S12x26 DONE 22:47: 18 trials, 0 LEAK, 3 PHANTOM (= the 3 wrong numbers), 3 LATE.
### S12eq (equal RC 32/32/32, 2.26 ms steps) DONE 22:54: 10 trials, 0 LEAK/PHANTOM.
  X takes X13 only from +36 ms (d=9.82); B's cell long clear.  Finer run
  S12eqf (d 7.0..11.07 step 0.37) queued in next1.sh (the cell's +1 tick).
### S3 (fam 3, A20 hangs up -2..+11.6 ms around B's CLAIM, 1.13 steps) DONE 23:01: 14 trials 0 LEAK/PHANTOM/LATE.
### S4 (fam 4, A20 hangs up -3..+8.3 around B's connect) DONE 23:08: 12 trials clean.
- next1.sh extended (23:05): S0 (whole call, 70 x 7.37 ms), S4f/S2f/S1f/S7f/S3f finer
  steps, S11a26 (fam 11, A's ports 26 ms, re-seizure after a completed call,
  pattern 4 now fork-based so any d works; d 24..41 ms), then mcx26, FIX.
### S7 (both hang up around connect) 11 trials clean 23:15; S2 (around X forward) 10 trials clean 23:18
### S1 (around A's seizure) 15 clean 23:21; S5 (B21 lifts around connect) 12 clean 23:29; S6 (B21 hangs up after answer) 7 clean 23:35
### S9 (fam 9 = key 1 only, A20 hangs up d ms after A's seizure; T_KEY 625) DONE 23:50
- 15 trials, 3 LEAK at d = 592.5, 593.0, 593.5 (T_KEY - T_REL - 0.5 .. +0.5): A20
  addr=03 bsy=1 only.  C17 via T_KEY (net_unit 876-878 -> nogo -> mini 515-523).
  Window 1.5-2.5 ms.
- JOB 1 ALLDONE 23:50; next1 started 23:50.
### S12eqf (equal RC, d 7.0..11.07 step 0.37) DONE 00:00: 13 trials, 0 wrong.
- X's sweep takes X13 at +35 ms earliest (d >= 8.11); before that X15.  B's stale
  cell is clear by then.  So with EXACT RCs the margin holds (C20's margin, here
  ~2 ms); the wrong number needs X's RC faster than B's cell CLR by more than
  ~3-4 ms (scale 8) -- a 20 % tolerance gives 6.
### S0 (A20 hangs up at 3 + 7.37k ms from lift, k=0..69: every phase of the call to talk) DONE 00:30: 71 trials, 0 LEAK/PHANTOM/LATE.
### S4f (fam 4, 34 trials, 0.37 steps) 00:51 clean; S2f (fam 2, 29 trials, 0.37) 00:58 clean.
### S1f (34 trials, 0.5) 01:04 clean; S7f (24 trials, 0.5) 01:13 clean.
### S3f (39 trials, 0.37) 01:22 clean.  => at scale 8 the call-setup and connect families never leak (263 trials incl. S0).
### S11a26 (fam 11: completed call, A20+B21 hang up at t_h, A21 keys at t_h+x-12,
    dials 1 1 2 0; A's ports T_REL 26, X/B 32) DONE 01:38: 25 trials, 0 LEAK, B20 reached every time.
- A11 BUSY first falls at +26 (fE) but A11's M (X's backward claim) falls only ~+33,
  so fM.!M holds A11 BUSY to ~+59; A's sweep takes A11 only from +67 (> X11 free +64).
  => SOUND: after a claimed call the backward claim + BUSY's fM.!M term keep the near
  end busy past the far release even with the near RC 20 % fast.
- "25 PHANTOM" = bench artefact: B20 (legitimately rung by A21) rings 2.15 ms after
  the bench clears `second` (rb ticks B20 8805 > 8192 threshold).  Not a finding.
### S12x26mc (C03 fix (b) = work/audit/monclaim/rtl_fix, cell drops on a break >= ID; X 26) DONE 01:41
- d = 3.04/4.17/5.30: X13 re-seized at +30..32 exactly as before, B does NOT claim,
  B21 not rung.  6 trials 0 wrong.  => C03's fix (b) closes the rc-tolerance wrong number.
### FIX10 (rtl_fix/mini_marker.v: r_hook gate on the nodig/nogo BUSY writes, lines 405, 521, 545) DONE 01:49
- d = 1213.79 .. 1217.66 (all 7 baseline leak points inside): 10 trials, 0 LEAK.
  Closes both the A20 (C17) and the B11 phantom-flood leak.
### FIX8 (r_hook fix, fam 8 T_CLAIM) DONE 01:52: d 216.75..219.50 (baseline leaked 217.50..218.75): 12 trials, 0 LEAK.
### Fix regressions (RTL_fix.list = rtl_fix/mini_marker.v): tb_net 88/88 PASS, tb_chain 32/32 PASS,
  output identical to work/base-net.log / base-chain.log.  next1 ALLDONE 01:58; next2 (real timers) started 01:58.
### R12x205 (REAL timers, X T_REL 205 = 80 %): d=69.13 (X13 re-seized +208 ms) and 78.26 (+217): WRONG NUMBER, B claims +339/+348, B21 rung. d=60 (+199): X15, fine. (run continuing)
### R12x205 DONE 02:14 (REAL timers; X ports 205 ms, cells CLR 256, B 256): 9 trials, 6 WRONG NUMBER
- X13 re-seized at +208, +217, +226, +235, +244, +253 ms after A20's abandon: every one
  claimed by B's stale cell (B claim +339..+384 = re-seizure + ID 128), B21 rung.
  +199 (X15 taken) and +262 (cell clear) fine.  Window ~ +205..+256 = ~50 ms at real
  (vs ~3 ms at scale 8: the release RCs scale, the sweep does not).
