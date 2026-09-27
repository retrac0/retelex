# C11 skeptic (mechanism lens) -- notes

- Read cluster JSON + verifier verdict + verifier NOTES. RTL read: net_unit.v 794-804 (claim latched on first M sample),
  881 (N_WAITCL -> N_DONE on claimed && o_last && dmo==0), 818-822 (N_DONE write caller<-trunk BSY), port.v release rule
  (rel only on fM/fE FALL; fE arms after E stands T_ARM).
- mini_marker: every far write to a claimed trunk keeps CLM=1 (att_refuse 326, S_READ 370, nodig 407, key-1 424, 0 437,
  dialtone-off 443, svc 450, probe busy 477, connect 488-489, WATCH 545). CLM=0 only on r_gone paths (400, 470) and in
  S_YIELD (520; unreachable with ctx_clm). So the claim is a constant level (a_rx = e||clm) from CLAIM to release: a level
  watch is valid. Verifier's statement confirmed.
- Logs checked: c11_snap S4 FAIL listen-in (A20 follows B20 4/4); c11_fix S4 closed; c11_fix_trel26 12/12 left BUSY;
  c11_alt, c11_alt_trel26 PASS; net_c11/net_alt 88/88 (baseline 88); lfull_c11 2 FAIL glare; lfull_alt 40/40.
- Mechanism re-derived independently: CONFIRMED. No blocker found: o_gone is the register's only; the classifier is masked
  off the trunk by `mine` (d_held still names it); T_CLAIM runs only while !claimed; guard only before f2.
- Precision (minor): after the loss the trunk port clears at T_REL (fM fall) but stays BUSY another T_REL through fe
  (its E was the off-hook caller; after rel it listens to 00) -> huntable ~2*T_REL after the loss, not T_REL.
- Mitigation neither mentioned: once the overheard call's A reaches the stranded caller for T_ARM, its fE arms; when that
  call ends A falls and the stranded caller releases (dial tone if still off-hook). Listen-in bounded to one call.
- Aggravation neither mentioned: a FAR reseizure of the freed channel during the origin's wait is masked from the
  classifier by `mine` (st stays clear if it arrives after A11's fe fell) and is classified only after N_DONE clears
  d_held -- a late hold whose monitor/forward never saw the rise (monitor.md rule 1) -> wrong-number risk here and
  downstream. Rare (needs far reseize >= 2*T_REL after loss and before N_DONE). Closed by the same fix (N_DROP at P).
- Transit resolver has the same single-sample edge (R_LEG) but its unguarded window is only ~T_ARM + write latency;
  a loss propagates to the origin via T_in's E, so the origin-side fix covers it.
- Checked a candidate fault-free trigger: late F_WRITE (one-leg way back writes f_in<-leg CLM 0) after this exchange's
  own claim. Not reachable: F_WRITE follows classification by ~10-30 ms, a claim needs e b (>~1 s). Dropped.
- Spec framing: new network.md 4 table says "claim: the FIRST M seen ... keep it" and "connect: at the last digit
  write the caller listening to the kept trunk" -- the RTL follows the table; "the claim is a level" is about the far
  end holding CLAIM (which it does). So a spec GAP (release-by-level presumes a patch at the caller, absent until
  connect), not a departure. Verifier overstates slightly.
- Fix: auditor 4-sample unsafe (RC skew, glare) -- agree with verifier's evidence. Verifier alt (P~128 ms, N_DONE gated on
  lost==0) correct. Bounds: P > max dial break (~75 ms) and RC skew; P < earliest far reseize (~far RC T_REL, ~180 ms at
  -30%) because the watch cannot tell a claim from a new far seizure. 128 sits in [~80, ~180]. Residual: loss within
  T_ARM of the N_DONE write (~1% of window) -- optional post-connect T_ARM watch; spec table needs the rule.
- No simulation run (none needed: disagreements are derivable from port.v / net_unit.v).
