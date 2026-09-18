"""Adversarial re-check of feas_digital_rx.py (digital RX with a local crystal).

  mid   : the two UNMEASURED rates, 512 kbps (B=2) and 128 kbps (B=8), BER curves,
          analog reference vs DESIGN (M=8) vs ALT16, absolute method, fresh seeds 11,12,13.
  seed  : re-run of the verdict-bearing 64k / 1024k BER comparison with seeds 21,22,23.
  miscfg: rate mis-configuration from TX 512k and TX 64k (report only tested TX 256k).
Usage: python3 feas_verify_digital_rx.py mid seed miscfg
"""
import sys, time, gc
import numpy as np
import feas_digital_rx as D
import s4_simple as ss


def curve(link, sds, seeds, variants):
    names = ['REF'] + [v['name'] for v in variants]
    out = {nm: [] for nm in names}
    for sd in sds:
        tot = {nm: [0, 0] for nm in names}
        for seed in seeds:
            t_ref, t_wb = link.front(sd, [2 * link.lr, D.F_AA], seed=seed)
            rb = D.mono_times(t_ref, link.spb); e, nb = D.line_errors(rb, link.line)
            tot['REF'][0] += e if e is not None else nb; tot['REF'][1] += nb
            cache = {}
            for v in variants:
                rb, _ = D.digital(t_wb, link.ns, link.lr, v, cache=cache)
                e, nb = D.line_errors(rb, link.line)
                full = len(link.line) - 64 - 2 * 4096
                if e is None or nb < 0.9 * full:          # count a slip as a failure, not as 0
                    e = max(e or 0, 1000); nb = max(nb, 1)
                tot[v['name']][0] += e; tot[v['name']][1] += nb
            del t_ref, t_wb, cache; gc.collect()
        for nm in names:
            e, nb = tot[nm]; out[nm].append(e / nb if nb else 1.0)
    return names, out


def show(title, link, sds, seeds, variants, ref256=1.264):
    t0 = time.time()
    names, E = curve(link, sds, seeds, variants)
    print(f'\n{title}: {len(link.line)} line bits x {len(seeds)} seeds per point ({time.time() - t0:.0f} s)')
    print(f'  {"receiver":36s} ' + ' '.join(f'{s:>7.3f}' for s in sds) + '   sd@1e-4   dB vs 256k REF(1.264)')
    for nm in names:
        a = D.sd_at(sds, E[nm], 1e-4)
        db = f'{20 * np.log10(a / ref256):+5.1f}' if a else '  n/a'
        print(f'  {nm:36s} ' + ' '.join(('      0' if x == 0 else f'{x:7.0e}') for x in E[nm])
              + f'   {a if a else float("nan"):6.3f}   {db}', flush=True)


V = [D.DESIGN, D.ALT16]


def do_mid():
    grid = lambda lo, k: [round(lo * 10 ** (i / 20), 3) for i in range(k)]
    link = D.Link(512000, secs=0.25, n=3, rate=64000)
    show('512 kbps N=3 @64k', link, grid(0.6, 9), (11, 12, 13), V)
    del link; gc.collect()
    link = D.Link(128000, secs=0.5, n=1, rate=32000)
    show('128 kbps N=1 @32k', link, grid(1.1, 9), (11, 12, 13), V)
    del link; gc.collect()


def do_seed():
    link = D.Link(64000, secs=0.8)
    show('64 kbps (seeds 21-23)', link, [1.69, 1.89, 2.12, 2.38, 2.67, 3.0], (21, 22, 23), V)
    del link; gc.collect()
    link = D.Link(1024000, secs=0.25)
    show('1024 kbps (seeds 21-23)', link, [0.24, 0.27, 0.30, 0.34, 0.38, 0.42, 0.47], (21, 22, 23), V)
    del link; gc.collect()


def do_miscfg():
    for tx_lr, n, rate, secs in ((512000, 3, 64000, 0.1), (64000, 1, 16000, 0.6), (1024000, 7, 64000, 0.06)):
        link = D.Link(tx_lr, secs=secs, n=n, rate=rate)
        t = link.front(0.0, [D.F_AA], seed=4)[0]
        for rx_lr in (1024000, 512000, 256000, 128000, 64000):
            rb, s = D.digital(t, link.ns, rx_lr, D.DESIGN)
            # the RX channel strap is set to match the TX (N correct), only the rate jumper is wrong;
            # also try every N in case a wrong-rate stream aliases into a lockable pattern
            locks = {}
            for nn in (1, 3, 7):
                fl = 2 + 2 * nn
                locks[nn] = sum(1 for k in range(4) if ss.framer_single(rb, nn, skew=k)['lock_bit'] is not None)
            nc = D.gaps_frac(s, 2 * D.DESIGN['M'])
            print(f'  TX {tx_lr // 1000}k N={n}  RX {rx_lr // 1000:5d}k: {len(rb) / len(link.line):.2f}x bits, '
                  f'ones {rb.mean() if len(rb) else 0:.2f}, locks N1/N3/N7 (all skews) '
                  f'{locks[1]}/4 {locks[3]}/4 {locks[7]}/4, no-carrier {nc:.3f}', flush=True)
        del link, t; gc.collect()


if __name__ == '__main__':
    T0 = time.time()
    for w in sys.argv[1:]:
        {'mid': do_mid, 'seed': do_seed, 'miscfg': do_miscfg}[w]()
    print(f'[total {time.time() - T0:.0f} s]')
