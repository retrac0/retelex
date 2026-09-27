# C06 skeptic -- realism & severity lens

(started 2026-09-27; read-only review)

## Static results (read-only)
- Mechanism as verifier says (net_unit.v:792-862; pulse_rx.v:81-88). Fix-b diff read: 5 lines, o_brk set in WANT/HUNT/SEIZE, cleared at flood_go/reset,
  NOGO at h_done (N_END, nothing seized), guard ORs o_brk. Complete: only the dig_stb->flood_go gap is uncovered, and flood_go needs only marker room>=1 (µs).
- Band: flood_go->push 10.0 ms uncontended (run_rt.log), r_brk = break start + HIT(8)+~1 => key-to-e make 129-130 ms timed.
  Contended: N_WANT waits hst==H_IDLE (<=10 ms forward sweep); classifier reads cut the sweep (~1 ms each, <=1 per ~18 ms). Band <= ~129-143 ms.
  Push->bus-write queue time does NOT widen the hole (the guard already runs from the push).
- dialling.md 3.2: timed make = sent + ~5 ms (CVSD detector). 125 ms sent holds, 120 sent merges two digits. So the band (~124-125 sent) sits
  right at the local digit-merging edge: any device there already misdials locally now and then.
- Every project pulse source is 700 ms IDP (pulse-gen.md 2.1/3; card-word.md:355 auto-dialler). Rotary: human rewind + lost motion, >=~400 ms.
  Dialler chips 500-800 ms. None reach the band. Only a hand-programmed/non-conforming dialler or a hook-tapper at the ID boundary.
- A device with a uniform in-band IDP: every e>=2 call NOGOs (2nd pulse inside the guard at 9-12 pps), e=1 misroutes. Its owner sees "network calls fail".

## Consequence (subscriber view) -- sharper than auditor/verifier
- e=1 in band, 5-digit number: far (b,h) claims; its register gets only s as "h": NO dial tone to a claimed trunk (mini_marker.v:305-317),
  waits NODIG 10 s -> 03 via path. Caller: ~10 s silence then cannot-complete; the wrong exchange's one register held 10 s.
  If (b,h) doesn't exist: NOGO 2 s after b (same as fixed RTL). Ringing wrong line needs a 6th digit (auditor S3b) or s=0 at a class-marker owner (-> its operator).
- NEW: e>=2 is NOT always safe. 2nd pulse r_brk at x+T+9 vs guard end P+128 (P=flood_go+10(+wait), x in band): escapes iff T >= ~129-136 ms,
  i.e. <= ~7.3-7.75 pps (register's design range is 7-12 pps; ES 201 187 is 9-11). Then the far counts e-1, b and (e-1,b) claims and gets h s intact:
  a genuine ringing wrong number from a normal 5-digit dial. Still needs the in-band pause, so realism unchanged. Fix b covers it (first r_brk in HUNT).

## Coordination
- skeptic-mechanism (sibling) is already running tb_c06sk at real timers: (a) 7 pps e=4 in band, (b) 10 pps control, (c) 25 ms hit -> O_LOCAL.
  Same test I'd have run for the e-1 variant: I do NOT run a duplicate; I read their run_sk.log.
- Their hit/O_LOCAL variant: not C06-specific. ANY hit counted in the ~590+ ms pause after the key (outside the 128 ms guard) gives the origin
  the same (1, e) view -> O_LOCAL if own code is 1e (and the far counts it too). The band adds ~2 ms (<1%) of that exposure. Generic pulse-hit risk.

## Sibling run read (skeptic-mechanism/run_sk.log, snapshot, real timers; I ran nothing)
- a: 7 pps 90/53, e=4, key make 129: first r_brk in N_HUNT (+9.0), push +10.0, 2nd r_brk at tmr 142 (guard over) -> B=32 CLAIMS a call dialled to 42. CONFIRMS the e-1 variant.
- b: same at 10 pps: 2nd r_brk at tmr 99 -> guard NOGO. Verifier right for 9-11 pps only.
- c: 25 ms hit in band, A=13, e=3 -> origin reads (1,3) own code -> local_go -> A21 rings. Generic (see Coordination): not a C06 severity driver.

## Verdict (realism lens)
- Real; confirmed-overstated vs auditor's medium; LOW is right. Conforming equipment: never (pause >= 720 ms vs band 129-~143 ms timed).
  No rotary dial, dialler chip or project pulse source gets near. Only a non-conforming machine/tapper at ID+1..15 ms; such a device already
  fails every other network call cleanly and sits ~5 ms from merging digits locally.
- Verifier errors: (1) "e must be single pulse" false at <= ~7.7 pps (run a); (2) e=1 case with a 5-digit number mostly ends in 10 s silence + 03
  at the wrong owner (NO ring) -- ring needs a 6th digit or s=0 at a class-marker owner; the slow-pulse variant DOES ring (e-1, b) line h s.
- Fix b: correct, complete (covers both variants + band hits). 74HC: 1/2 '74 + 2 gates; can drop the WANT/HUNT/SEIZE decode (set on any r_brk,
  clear at flood_go; only read at h_done and in the guard). Add a real-timer regression trial (129/130 ms key make; 7 pps e>=2) -- tb_net can't reach it.
