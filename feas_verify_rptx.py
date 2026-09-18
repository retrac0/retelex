"""
Adversarial checks on the feas_rptx track (repeater front end, TX edge rate).

  v1  seed check of the 1024 kbps chain limit (fixed 2.048 MHz Butterworth =
      matched filter at 1024k), 128 samples/bit, seeds 2 and 3; plus a 256
      samples/bit grid-convergence check with seed 1.
  v2  terminal classifier window at 1024 kbps, 4 and 9 spans, absolute frame
      (1 MHz cable, 128 spb), TX/repeater edge 0 / 75 / 150 ns, at and below
      the 9-span limit.  The track reported edge cost only at 1 and 4 spans.
  v3  driver/receiver propagation-delay skew (tPLH != tPHL) per repeater hop,
      which the track did not model: 1024k, 128 spb, 4 and 9 spans.
  v4  256 kbps, 9 spans, seed 2: fixed 2.048 MHz vs matched 512 kHz (+1 dB claim).
  v5  64 kbps, 9 spans, classifier window: fixed 2.048 MHz vs matched 128 kHz.

Usage: python3 feas_verify_rptx.py v1|v2|v3|v4|v5
"""
import sys, time, gc
import numpy as np
import fast
import feas_rptx as R
from repeater import track_ber

flush = R.flush


def chain_skew(line, n, lr, fs, sigma, n_spans, taps, filt_spec, cable_fc, skew_samp,
               edge_tau=0.0, seed=1, windows=True):
    """R.run_chain with every hop's output (TX excluded) given an asymmetric
    delay: rising edges pass, falling edges are late by skew_samp samples
    (high pulses stretch, low pulses shrink).  Repeater = terminal filter."""
    spb = int(round(fs / lr))
    x = np.repeat(fast.dm_encode(line).astype(np.float64) * 2.0 - 1.0, spb // 2)
    out = {}
    for k in range(1, n_spans + 1):
        y = x
        if edge_tau:
            y = R.filt(y, fs, ('lp1', 1.0 / (2 * np.pi * edge_tau)))
        y = R.filt(y, fs, ('lp1', cable_fc))
        y = y / np.abs(y).max()
        if sigma:
            y = y + sigma * np.sqrt(fs / R.FSC) * \
                np.random.default_rng(seed * 1000 + k).standard_normal(len(y))
        w = fast.slice_hyst(R.filt(y, fs, filt_spec), R.H)
        if skew_samp:
            # receiver + driver skew of this hop (applied to what the terminal sees too)
            ws = w.copy()
            for d in range(1, skew_samp + 1):
                ws[d:] |= w[:-d]
            w = ws
        if k in taps:
            out[k] = R.score(w, spb, line, n, windows=windows, framer=True)
        x = w.astype(np.float64) * 2.0 - 1.0
        del y, w
        gc.collect()
    return out


def cell(r):
    s = f'BER {R.fmt_ber(r["ber"])}'
    if 'win' in r:
        s += f' win {R.window_str(r["win"], 1e-4)}'
    if 'lock' in r:
        s += f' lock {r["lock"]} lof {r["lof"]}'
    return s


def v1():
    lr = 1024000
    line, n = R.line_for(lr)
    f = ('lp2', 2.048e6)
    flush('(v1) 1024k chain, lp2 2.048M everywhere, 1 MHz cable, sd in 32.768 MHz units')
    for spb, seeds in ((128, (2, 3)), (256, (1,))):
        fs = spb * lr
        for seed in seeds:
            for sg, spans, taps in ((0.397, 4, (4,)), (0.315, 4, (4,)), (0.25, 4, (4,)),
                                    (0.157, 9, (9,)), (0.125, 9, (9,)), (0.099, 9, (9,))):
                t = time.time()
                r = R.run_chain(line, n, lr, fs, sg, spans, taps, f, f, R.CABLE, seed=seed,
                                sd_scale=float(np.sqrt(fs / R.FSC)), abort=1.0)
                flush(f'  spb {spb} seed {seed} sd {sg:.3f} {spans} spans: '
                      + '  '.join(f'{k}: {cell(r[k]["B"])}' for k in taps if k in r)
                      + f'  ({time.time()-t:.1f}s)')


def v2():
    lr = 1024000
    line, n = R.line_for(lr)
    f = ('lp2', 2.048e6)
    spb = 128
    fs = spb * lr
    flush('(v2) 1024k, 128 spb, 1 MHz cable, lp2 2.048M everywhere, edge on every driver; '
          'terminal window (BER<=1e-4) at 4 and 9 spans')
    for sg, spans in ((0.157, 4), (0.25, 4), (0.0, 9), (0.0625, 9), (0.099, 9), (0.125, 9)):
        for e in (0, 75, 150):
            t = time.time()
            r = R.run_chain(line, n, lr, fs, sg, spans, (spans,), f, f, R.CABLE,
                            edge_tau=R.tau_of(e), sd_scale=float(np.sqrt(fs / R.FSC)),
                            abort=1.0, windows=True)
            flush(f'  sd {sg:.4f} {spans} spans edge {e:3d} ns: {cell(r[spans]["B"])}  ({time.time()-t:.1f}s)')


def v3():
    lr = 1024000
    line, n = R.line_for(lr)
    f = ('lp2', 2.048e6)
    spb = 128
    fs = spb * lr
    ts = 1e9 / fs
    flush(f'(v3) 1024k, 128 spb ({ts:.2f} ns/sample), 1 MHz cable, lp2 2.048M, per-hop skew '
          f'(falling edge late), terminal window')
    for skew in (0, 1, 2, 4):
        for sg, spans, taps in ((0.0, 9, (4, 9)), (0.157, 9, (4, 9)), (0.25, 4, (4,))):
            t = time.time()
            r = chain_skew(line, n, lr, fs, sg, spans, taps, f, R.CABLE, skew)
            flush(f'  skew {skew*ts:5.1f} ns/hop sd {sg:.3f}: '
                  + ' | '.join(f'{k} spans {cell(r[k])}' for k in taps) + f'  ({time.time()-t:.1f}s)')


def v4():
    lr = 256000
    line, n = R.line_for(lr)
    fs = R.FSC
    flush('(v4) 256k, 32.768 MHz, 9 spans, terminal lp2 512k, seed 2 (and 3)')
    for rep in (('lp2', 512e3), ('lp2', 2.048e6)):
        for seed in (2, 3):
            for sg in (0.891, 0.794, 0.707, 0.630):
                t = time.time()
                r = R.run_chain(line, n, lr, fs, sg, 9, (9,), rep, ('lp2', 512e3), R.CABLE,
                                seed=seed, abort=1.0)
                flush(f'  rep {R.fname(rep):>10s} seed {seed} sd {sg:.3f}: 9 spans {cell(r[9]["B"])}'
                      f'  ({time.time()-t:.1f}s)')


def v5():
    lr = 64000
    line, n = R.line_for(lr)
    fs = R.FSC / 2
    flush('(v5) 64k, 16.384 MHz (sd in 32.768 MHz units), 9 spans, terminal lp2 128k: window')
    for rep in (('lp2', 128e3), ('lp2', 2.048e6)):
        for sg in (0.707, 1.0):
            t = time.time()
            r = R.run_chain(line, n, lr, fs, sg, 9, (9,), rep, ('lp2', 128e3), R.CABLE,
                            sd_scale=float(np.sqrt(fs / R.FSC)), abort=1.0, windows=True)
            flush(f'  rep {R.fname(rep):>10s} sd {sg:.3f}: 9 spans {cell(r[9]["B"])}  ({time.time()-t:.1f}s)')


if __name__ == '__main__':
    t0 = time.time()
    if sys.argv[1] != "v3b": dict(v1=v1, v2=v2, v3=v3, v4=v4, v5=v5)[sys.argv[1]]()
    flush(f'[{sys.argv[1]} done in {time.time()-t0:.0f}s]')


def v3b():
    lr = 1024000
    line, n = R.line_for(lr)
    f = ('lp2', 2.048e6)
    fs = 128 * lr
    flush('(v3b) 1024k 128 spb 9 spans, skew per hop vs sd (limit search, seed 1)')
    for skew in (1, 2):
        for sg in (0.125, 0.099, 0.079, 0.0625):
            t = time.time()
            r = chain_skew(line, n, lr, fs, sg, 9, (9,), f, R.CABLE, skew)
            flush(f'  skew {skew*1e9/fs:5.1f} ns/hop sd {sg:.4f}: 9 spans {cell(r[9])}  ({time.time()-t:.1f}s)')
    flush('(v3b) 256k 32.768 MHz (128 spb) 9 spans, lp2 512k, skew per hop')
    lr = 256000
    line, n = R.line_for(lr)
    fs = R.FSC
    for skew in (0, 1, 2, 4):
        for sg in (0.5, 0.63):
            t = time.time()
            r = chain_skew(line, n, lr, fs, sg, 9, (9,), ('lp2', 512e3), R.CABLE, skew)
            flush(f'  skew {skew*1e9/fs:5.1f} ns/hop sd {sg:.3f}: 9 spans {cell(r[9])}  ({time.time()-t:.1f}s)')


if __name__ == '__main__' and sys.argv[1] == 'v3b':
    v3b()
