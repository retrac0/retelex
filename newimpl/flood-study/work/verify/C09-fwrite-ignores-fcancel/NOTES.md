# C09-fwrite-ignores-fcancel -- verification notes (2026-09-26)

## Code read (snapshot rtl/net_unit.v) -- mechanism holds
- C_HOLD watch: first low sample of cls_port -> cst C_UNHOLD (581-583); next tick w_cls pushes
  cls_port <- 00 bsy0 and sets f_cancel (590-594). w_cls outranks w_fwd (488-493).
- F_WANT (714) and F_HUNT (722) read f_cancel; F_WRITE (725) and w_fwd (492) do not.
- h_done is registered on the SAME sp_fresh that moves cst to C_UNHOLD when that sample is the
  CONFIRM's 64th. On the next tick F_HUNT reads the OLD f_cancel (0) -> F_WRITE; the UNHOLD pushes.
  Tick after: w_fwd pushes leg(s) and, for one leg, the way back f_in <- leg BUSY (732-736).
- Sweep is scan-locked: last read is h_idx = 1+9*63 mod 64 = 56 = port 70; CONFIRM counts 64
  sp_fresh from 00, so h_done is ALWAYS at port 77's sample. A C_WAIT steal of the reader delays the
  sweep by whole passes, never changes the phase. So the h_done coincidence is port-77-only.
- Other ports: exposed only if F_WRITE waits (room < cnt_fwd, i.e. >= 13 of 16 queue entries) past
  their own sample (>= 128 ticks after h_done for 01). Needs a near-full unit queue. Rare.
- 1 leg: 77 <- 13 bsy1 after the unhold; 77's M=0, 13's M=0; fM never armed (M < T_ARM), fE never
  rises -> no rel ever (port.v 176-194). Resolver: R_LEG needs 13's M, R_GONE needs 77 !BUSY: neither.
- 2-3 legs: 77 stays at 00 bsy0 -> R_GONE next pass drops the legs. Clean. Permanent needs 1 leg.
- Scale 8 cannot show it: watch ends T_ARM+2 = 4 ms after hold, sweep ends ~11 ms.
- NOT "for good": 77 is BUSY so B never classifies a new M on it (cls_seen needs !sp_busy) but the
  patch 77<->13 is a live wire. The next seizure from EITHER far end passes straight through B
  (unmonitored, not flooded to B's other directions), arms fM/fE, and its end clears both ports and
  R_GONE/R_LEG frees the resolver. Cost: that one call fails if it needed B (or B's other dirs).

## Benches / jobs (queued via sim.sh, 2026-09-26)
- rtl_fix/net_unit.v (RTL_fix.list): MINIMAL fix only -- F_WRITE: if (f_cancel) fst <= F_IDLE;
  w_fwd gated with !f_cancel. (= cableb's +fixfc knob; the fwd copy also carries rs_lb/rs_lf.)
- tb_c09.v: two sites, ALL REAL TIMERS, A11==B77, B13 to a silent far end (link up, A=0). A20 dials 1
  (60/40), A floods, B holds 77 + one-leg forward on 13; A20 HANGS UP at B scan k (4) in B's CONFIRM.
  Stage 2: A20 calls B21 (1 2 3 2 1), checks B claims. Stage 3: all idle.
- jobA.sh: auditor tb_fcan (knob RTL) mode0/mode1/mode0+fixfc; tb_c09 on snapshot and on rtl_fix.
- jobB.sh: tb_net and tb_chain on rtl_fix.
- Fix completeness (code read): with cst==C_UNHOLD and fst==F_WRITE, w_fwd can fire only when w_cls
  is false, i.e. room<1 or w_claim -- both also block w_fwd. So the UNHOLD always precedes the legs
  and the F_WRITE gate always sees f_cancel. If F_WRITE fires first, the later unhold overrides the
  way back and R_GONE drops the legs: clean. The auditor's alternative (combinational cancel in
  F_HUNT) covers only the h_done tick, not an F_WRITE that waits. Strictly only the F_WRITE line is
  needed; the !f_cancel on w_fwd just avoids one tick of w_res/w_ev lockout.
- Real triggers (conforming): caller abandons right after key 1 (M falls live everywhere); origin glare
  "taken as the claim" drops its other directions up to T_GUARD after the seize. Needs the 1-ms pass
  ending at 77's CONFIRM sample, incoming trunk in socket 77 (can be a group's first choice: the far
  end's glare order), and exactly one leg. Rare; heals at the channel's next use.
- Slots: all 5 held by 3-4 h load runs at queue time (16:5x); jobs A/B waiting.

## Results
- 19:46 tb_fcan rerun (auditor bench, knob RTL): run_fcan_mode0.log FAIL 3/6, identical to the
  auditor's (unhold, leg 13<-77, way back 77<-13; 485 ms: both BUSY, res 01). mode1 PASS, mode0+fixfc
  PASS. Reproduced exactly.
- 19:54 tb_c09 SNAPSHOT, all real timers, A20 hangs up at B scan 4 in CONFIRM (run_c09_base.log):
  B77 M up 720 ms, hold 722, hang-up 732, B77 M down at B scan 18, h_done+UNHOLD 733 on one tick,
  FORWARD pushed with f_cancel 1; cable B: 77<-00 b0, 13<-77 b1, 77<-13 b1. 3 s on: B77, B13 BUSY,
  res_b 01 -> FAIL x3. Stage 2: A20's next call to B (1 2 3) seizes A11 again (A sees it free), B77 is
  BUSY so B never classifies it: no monitor, no claim -> A's T_CLAIM NOGO (FAIL). A's drop at 8182
  arms nothing new; B77 fM (armed by the 2nd call) falls, R_GONE drops 13 at 8439: HEALS. Stage 3 idle.
  => conforming trigger (subscriber abandons after key 1) at real timers; cost = stuck pair + held
  resolver until the channel's next use, and that next call is lost if it needed B.
- 20:03 tb_c09 on rtl_fix (minimal F_WRITE gate), run_c09_fix.log: 7/7 PASS. Same hang-up tick
  (h_done + UNHOLD at 733); no FORWARD; B77/B13 idle, res 00. The next call is held, forwarded
  (f_cancel 0), claimed by B (6182: 77 CLAIM, leg 13 dropped), B21 connected by the marker.
- jobB (tb_net, tb_chain on rtl_fix) still queued at 20:03.
- 20:51 tb_net on rtl_fix: 88/88 PASS (run_net_fix.log). 20:58 tb_chain on rtl_fix: 32/32 PASS
  (run_chain_fix.log). At scale 8 the gate is provably inert (the watch ends ~4 ms after the hold,
  before any h_done), so identical output is expected. All obj dirs removed.
