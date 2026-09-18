"""Pattern check: 1024k chain, 128 spb, lp2 2.048M, 9 spans, payloads speech / CVSD silence / data1 / data0."""
import time, numpy as np
import feas_rptx as R, framing_review as fr
lr = 1024000; fs = 128 * lr; f = ('lp2', 2.048e6)
n, rate = R.MODE[lr]; L = R.NBITS // (2 + 2 * n) + 1
cv, sil = R.cvsd_bits()
lines = {'speech': R.line_for(lr)[0], 'data1': R.line_for(lr, payload='data1')[0],
         'data0': R.line_for(lr, payload='data0')[0]}
C = np.array([np.roll(sil, 977 * j)[:L] for j in range(n)])
A = np.array([np.full(L, j % 2, np.uint8) for j in range(n)])
lines['silence'] = fr.gbuild(C, A, R.S4)
for nm, line in lines.items():
    for sg in (0.125, 0.099):
        t = time.time()
        r = R.run_chain(line, n, lr, fs, sg, 9, (4, 9), f, f, R.CABLE,
                        sd_scale=float(np.sqrt(fs / R.FSC)), abort=1.0, windows=True)
        R.flush(f'  {nm:8s} sd {sg:.3f}: ' + ' | '.join(
            f'{k} spans BER {R.fmt_ber(r[k]["B"]["ber"])} win {R.window_str(r[k]["B"]["win"], 1e-4)} lof {r[k]["B"]["lof"]}'
            for k in (4, 9)) + f' ({time.time()-t:.1f}s)')
