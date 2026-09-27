# C04 hold-watch-dial-break: skeptic review (realism and severity lens)

No simulation run: read-only review. Sources: the cluster json, the verifier's NOTES.md and logs
(run_brkrt_snap.log, run_brk_fix.log, run_net_fix.log, run_chain_fix.log, fix/net_unit.diff),
snapshot rtl/net_unit.v 256-296, 540-735, 850-866, rtl/port.v 134-199, exchange/network.md
2-6, analysis/dialling.md 2, proposed/pulse-gen.md, card-word.md 355, common/su-1.md 65,
and the related clusters C03 (stale cell), C05 (late flood / reach), C09 (F_WRITE vs f_cancel).

## Mechanism: agree
- C_HOLD 584-588 unholds on any M-low sample. 566-567 clears st. 590-594 writes bsy=0 and sets f_cancel.
  port.v:147 BUSY = bsy|fe|(fm&!m), so BUSY=0 at the make, whether or not fM had armed. cls_seen
  then gives a second hold and a second cell. The first cell is not released. Confirmed by the
  verifier's real-timer run: off 2 and off 10 are wrong numbers, C21 rings.
- The window is slightly wider than [hold, hold+18]. A break that lands between the rise and the
  hold (C_READ/C_ACT) is still low at the first C_HOLD sample, so it unholds too: about rise..hold+17.
- e=1 case (not in the report): the second cell attaches after the only pulse, so it counts b as e
  and h as b. The wrong-number condition is then (b,h) = X, not (e-1,b). e=0 (10 pulses) gives
  9 = vacant, so it is never wrong.
- NMON=2: the double hold uses both cells at the exposed exchange for about 1 s.

## Realism
- The band is a first-break arrival of about tap..tap+17 ms after the seizure. That means a key-1-to-e
  pause of 267-285 ms at 128, 395-413 at 256 and 651-669 at 512.
  - The origin's r_brk comes HIT into the break (C05), which shifts everything down about 8 ms. It
    changes no conclusion.
- Automatic dialers never reach it. ES 201 187 requires 720 ms, and Joel's own su-1, hotline card
  and pulse-gen all use 700 ms: above 669, so outside the band at every tap up to 512.
- Hand rotary: the pause is the user's, and no equipment enforces 720. At 128 the band is at or below
  a dial's mechanical floor after '1' (return lost motion plus winding the next hole): essentially
  never. At 256 it would take a very fast dialler. At 512 it is ordinary brisk dialling, but a 512 net
  is ~40 typical hops deep and also abandons ~10% of rotary calls. Not a real configuration.
- Edge exchange: the exposed exchange must hold in the last ~17 ms before the break reaches it.
  - In a net planned to the slow case (network.md 6: 4-5 hops at 128), the deepest exchange holds at
    40-60 ms unloaded. Reaching 111+ ms needs nearly every hop at its slow maximum, so ~1e-3..1e-4.
  - In a net built out to the typical reach (10 hops at 128) it is routine.
- Wrong number vs harmless: at a leaf it takes X = (e-1,b) (or (b,h) for e=1), so ~1/N. Otherwise the
  second cell just drops. At a transit the flood is cancelled or re-flooded late, and the call is lost
  or wrong downstream.
- Order of magnitude, with 50 inter-exchange calls/BH originated per exchange and N=10:
  - 128 tap, slow-case plan: <1e-5 wrong numbers per exchange per BH (never).
  - 128 tap built to 10 hops, rotary: ~1e-3/BH, about one per ~400-1000 BH per exchange. The guard's
    own abandonments of faster callers dominate it.
  - 512: ~0.04/BH, but in a network nobody builds.
- What the subscriber hears: silence to the connect, then ringback, and a stranger at h s of (e-1,b).
  If the dialled code also exists, both owners claim and the first claim back wins (a coin flip). If
  (e-1,b) has no h s, that exchange's marker gives a tone. At a transit: cannot-complete after the 2 s
  or 5 s rule.
- Verdict on severity: LOW. It is a real silent wrong number, but inside the envelope of any
  conforming network it is the same failure as C05's reach edge, moved 18 ms. The actual defect is
  that network.md 6's reach table leaves out the destination's own 18 ms watch.

## Plausible-fault lead (verifier's, unverified): a 1 ms A dropout or hit inside a watch
- No wrong number: both cells see the rise before e.
- At a transit mid-sweep, the re-hold finds fst != F_IDLE, so it is not forwarded, and f_cancel kills
  the first forward. The flood dies there: a clean cannot-complete beyond.
- At the owner, two cells claim: two w_claim/att on one trunk. Effect at the marker unknown.
- The rate depends on how often a link glitches. Digital links: negligible. The fix covers it.

## Fix (C_LOW, CLR threshold, watch restarts at the make)
- Right, and nearly free in 74HC: cst code 6 is unused, the cls_ms clear exists, and >=256 is
  cls_ms[8], a wire. The restart at the make is needed so that fM arms under the watch. CLR over ID
  is right given network.md 2 (a carrier may lengthen a break to just under 256).
- It keeps BUSY through the break, so there is no R_GONE and no f_cancel. It also closes the
  bounce, hit and dropout variants, and it sidesteps C09's race for deaths inside the watch (the
  unhold now comes 256 ms later, with fst idle).
- Costs and gaps:
  1. Classifier stall: 80-120 ms per dial-break event (a whole digit at 20 pps) and 256 ms per real
     death in the watch (guard abandonments, glare drops, blips). This is harmless at 128 and 256 for
     720 ms callers (slack ~450 and ~325 ms). At 512 the slack is ~68 ms, so a 256 ms stall at a deep
     exchange can push another conforming call past its first break. So "only matters to callers
     faster than the standard" is true only up to the 256 tap. The stall also runs against C05's
     "take the watch off the classifier".
  2. A rise inside C_LOW is taken as the make of the same call. If the far end re-seizes the channel
     within CLR, the new flood gets no cell and no forward at X, and the old cell miscounts it (C03's
     wrong number, which persists). The far end can do this when it dropped the channel before its
     fE armed: a glare drop, or C03 trigger 2. Rare x rare, but fix C03 and C04 together.
  3. A second copy of the same flood that reaches X during the watch is classified after the break
     and counts e-1 (C05). The fix does not touch it.
- If C05's watcher-beside-the-classifier is adopted, put C_LOW there instead. Or let the attached
  cell's own 256 ms CLR write away an unarmed hold, keeping a watch only for cell-less seizures.
- Docs-only alternative (+18 ms in the 6 budget): closes the wrong-number mode in a net sized to the
  corrected guard, but not the transit, glitch or double-att modes. With the RTL fix the term is not
  needed for C04, though C05 still re-budgets.
