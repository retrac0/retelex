# Residual glare per link on traffic.md s8.5/8.6's 63-exchange design tree (20% leaving, ~1428 lines).
# Arithmetic only.  rate = P(N-1 busy) * lamX * lamY * 2D   (no extra 2: verifier's correction)
from math import factorial
def pk(N, A):
    t = [A**k/factorial(k) for k in range(N+1)]; s = sum(t); return [x/s for x in t]
TWO_D = 2.64e-3            # s, verifier's Monte Carlo / auditor's 2 x 1.32 ms (baseband, no carrier)
R_NET = 857/3600.0          # network (leaving) calls a second at the busy hour, traffic.md 8.6 row 1
HOLD  = 48.0; FLOOD = 2.73; NEX = 63
r = R_NET/NEX
# tree: 3 tandems in a chain, 2 sub-hubs each, 3 under each sub-hub, 2 leaves under each of those
links = [("tandem-tandem", 21, 42, 2), ("tandem-subhub", 10, 53, 6), ("subhub-mid", 3, 60, 18), ("mid-leaf", 1, 62, 36)]
for mult in (1.0, 2.0):
    print(f"\n=== load x{mult:g}: {R_NET*mult*3600:.0f} network calls/h, flood {R_NET*mult*FLOOD:.2f} E on every link")
    tot = 0.0
    for name, nx, ny, cnt in links:
        rr = r*mult
        conv = 2*rr*nx*ny/(NEX-1)*HOLD
        A = R_NET*mult*FLOOD + conv
        for N in ((12,) if name.startswith("tandem") else (12, 6)):
            p = pk(N, A)
            g = p[N-1]*(rr*nx)*(rr*ny)*TWO_D     # per second
            print(f"  {name:14s} x{cnt:2d}  N={N:2d} A={A:5.2f}E block={p[N]*100:6.2f}%  P(1 free)={p[N-1]:.4f}  "
                  f"seizures/h {rr*(nx+ny)*3600:6.0f}  glare 1 per {1/(g*3600):9.0f} busy h  per seizure {g/(rr*(nx+ny)):.1e}")
            if N == 12: tot += g*cnt
    print(f"  network (all links 12 ch): {tot*3600:.4f} glare/busy h = 1 per {1/(tot*3600):.0f} busy h; "
          f"per exchange per busy h {tot*3600/NEX:.1e}; per network call {tot/(R_NET*mult):.1e}")
