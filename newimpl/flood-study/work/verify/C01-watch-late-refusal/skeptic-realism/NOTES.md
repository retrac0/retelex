# C01 skeptic review (lens: realism and severity) -- notes
Started 2026-09-27. Read-only; no simulation run.

## Read (snapshot only)
- mini_marker.v:271-282 (att_take/att_refuse, WATCH exemption), 305-327 (take/refuse), 541-553 (WATCH exits:
  settled -> r_release + IDLE; gone/nodig -> r_release + DRAIN). pulse_reg.v:99 (settled = busy && steady &&
  nd_t >= SETTLE), 117-118 (busy clears the edge after release_it). pulse_rx.v (steady = make stood SETTLE; ANY
  break sample resets t, so a sub-HIT break also resets steady and the ID timer).
- port.v:147 (busy = bsy || fe || fm&&!m), 153 (a_rx = e||clm), 176-194 (clear only on fM/fE fall).
- net_unit.v:283 (cls_seen needs !st), 564-567 (st cleared by M down), 606-630 (hold + monitor + forward),
  640-662 (monitors: released only by a wrong digit or d_clr; NO timeout), 666-676 (cell freed at w_claim; CL_ACK
  waits only on att_ack).
- marker.v:271-273 identical exemption; top_max wires a net_unit (generate), so the class marker is in scope.
- Verifier logs r_snap_s1/s2/s3, r_hk_s1/s2/s3, net_hk.log (88/88, same count as work/base-net.log); rtl_hk and
  rtl_of diffs are exactly what the verdict says. cableb run_attw_scen{1,2}fixwatch.log: refused at att, clean.
  C02's run_net_fix.log (deletion) 88/88.
- Specs: exchange/marker.md 4.8 ("never during a watch, which a claim waits out"), 5 ("A claim arriving during a
  watch waits for it to end"), exchange/network.md:189.

## Realism
- watch-exit-refusal: window = words + SETTLE ~33 ms per local connect, every one. Refused claims/h at the owner
  = C x L x 0.033/3600 (C claims/h, L local connects/h). L=60, C=30: ~0.017/busy hour (one per ~60 BH).
  C15 (one register) already refuses C x occupancy ~ 30 x 6.7% ~ 2/BH, so this adds ~1% relative. The caller
  hears 03 only after h s (origin connects at the last digit). Clean. LOW.
- Stuck state needs refusal at WATCH end > t_a + T_REL (far hang-up + 256).
  * Conforming: needs t_c <= t_a < t_localbreak < t_w + 32: claim, far abandon (mid-dial, right after b), local
    hang-up ~130-160 ms after its own last pulse, all inside one ~32 ms window. ~1e-11 per claim. Never.
  * Dialling on cannot extend WATCH: 720 ms min pause vs WATCH over ~165 ms after the last pulse. 10 pps makes
    (40 ms) exceed SETTLE anyway; only a 20 pps dial with a 128-165 ms pause (non-conforming, would nearly merge
    digits) keeps WATCH open for one digit (<= 500 ms).
  * Fault route is rarer than the verifier's text implies:
    (a) the real line card's hook detector (cvsd_line_card.v:110-135, tau 4 ms; a break must last ~7.6 ms to
        show, a make shows +6.1 ms) swallows the bench's 4 ms/12 ms chatter (site_net drives M raw). A realisable
        chatter is raw breaks >= ~8 ms at < ~34 ms spacing, sustained: close to continuous 30 pps pulsing.
    (b) a line already chattering cannot complete a digit (any break sample resets ID), so the chatter must
        START within ~35 ms after s's dig_stb (tb_c01r aligns it by event: wait mks_b == 7).
    (c) the far caller hears silence from the key to the connect at h s (network.md 4.1), so he dials h s
        (~2-4 s) and then waits; the bench's "A20 on-hook 2 ms after att" (mid-dial) is the least likely
        behaviour. Stuck needs the chatter to last seconds past the claim, towards NODIG (10 s).
    A dirty hook switch bounces for ms at a transition (=> the conforming hang-up case), not for seconds.
    Estimate: healthy plant ~0; with a severe sustained-chatter fault ~1e-5..1e-3 per busy hour.
  * Damage: permanent, cumulative, silent (no subscriber misrouted): trunk at both ends + a monitor (1 of
    NMON=2) at the neighbour; via C08 (no unit timeout anywhere) a phantom flood through transits. Visible as a
    BUSY lamp (hookbusy card). Recovery: reset. MEDIUM, at the low end; HIGH is overstated.

## Fix
- Hook gate (verifier): correct. Only WATCH exit with a waiting claim is `settled`; !r_release covers the lag;
  first break refuses within 1 ms, <= ~33 ms after att vs >= ~223 ms before the trunk can release; take <= ~34 ms
  after att, h >= ~590 ms away, so no C02 late attach. 2 gate inputs (Q-bar of r_release; OR with !r_hook).
- Deletion of (state != S_WATCH): simpler (a gate input fewer), equally safe (answer at once, trunk up), refuses
  only claims the snapshot refuses today (no regression), no ribbon wire in top_max for marker.v. Both need a
  spec edit (the hook gate too: "waits unless the caller breaks"). Under breadboard-first, prefer deletion.
- Either way: same edit at marker.v:273 (untested there: tb_max). Not covered by either: C08's missing
  timeout (defence in depth; bounds this damage class), C17-style writes after release elsewhere.
