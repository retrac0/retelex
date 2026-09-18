"""1024k, 128 spb, 1 MHz cable, lp2 2.048M everywhere, 9 spans: edge 0/75/100/190 ns vs sd (seeds 1, 2)."""
import time, numpy as np, feas_rptx as R
lr = 1024000; fs = 128 * lr; f = ('lp2', 2.048e6)
line, n = R.line_for(lr)
for seed in (1, 2):
    for e in (0, 75, 100, 150, 190):
        for sg in (0.157, 0.125, 0.099, 0.079):
            t = time.time()
            r = R.run_chain(line, n, lr, fs, sg, 9, (9,), f, f, R.CABLE, edge_tau=R.tau_of(e), seed=seed,
                            sd_scale=float(np.sqrt(fs / R.FSC)), abort=1.0, windows=True)
            b = r[9]['B']
            R.flush(f'  seed {seed} edge {e:3d} ns sd {sg:.3f}: 9 spans BER {R.fmt_ber(b["ber"])} '
                    f'win {R.window_str(b["win"], 1e-4)} lof {b["lof"]} ({time.time()-t:.1f}s)')
