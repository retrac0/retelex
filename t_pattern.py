"""
How simple can the T pattern be?

Three candidates, all with S = 0 in every frame and all run through the same
battery, including the slot rules and empty-slot fill of spec §3.4:

  toggle   T = 0,1,0,1         check  T != T one frame ago        TX: 1 flip-flop
  pair     T = 1,1,0,0         check  T != T two frames ago       TX: 2 flip-flops, no gate
  S4       T = 1,1,1,0         check  exactly one 0 in last four  TX: 2 flip-flops + NAND
                               (spec §7: + predictive counter and phase counter)

For toggle and pair the check is phase-free and self-contained, so the same
check serves acquisition and loss of frame with one +2/-1 trip 12 counter.
S4 uses the spec's two-counter policy (s4_lof.py P4).

Usage:  python3 t_pattern.py
"""
import numpy as np, fast, link, framing_review as fr, s4_lof
from scipy import signal

CONF = 32
SCHEMES = {
    'toggle 0101': dict(pat=(0, 1), lag=1),
    'pair 1100':   dict(pat=(1, 1, 0, 0), lag=2),
    'S4 1110':     dict(pat=(1, 1, 1, 0), lag=None),
}
P4 = s4_lof.POLICIES['P4 +2/-1 trip 12, plus window +1/-1 16']


def build(C, A, pat):
    n, L = C.shape; flen = 2 + 2 * n
    f = np.zeros((L, flen), np.uint8)
    for j in range(n):
        f[:, 2 * j] = A[j]; f[:, 2 * j + 1] = C[j]
    f[:, flen - 1] = np.array(pat, np.uint8)[np.arange(L) % len(pat)]
    return f.reshape(-1)


def framer_lag(line, n, lag, skew=0):
    """S == 0 AND T != T `lag` frames ago at this alignment (scored on S alone
    until `lag` frames have been seen since the last slip).  One counter,
    +2/-1 trip 12, on the same check after lock."""
    flen = 2 + 2 * n
    if skew:
        line = np.roll(line, -skew)
    true = (flen - skew % flen) % flen
    i = cc = err = 0; locked = False; hist = []
    st = dict(lock_bit=None, false_lock=False, lof_events=0); pos = []
    N = line.size
    while i + flen <= N:
        s, t = int(line[i + flen - 2]), int(line[i + flen - 1])
        good = (s == 0) and (len(hist) < lag or t != hist[-lag])
        hist = (hist + [t])[-lag:]
        if not locked:
            if good:
                cc += 1
                if cc >= CONF:
                    locked = True; st['lock_bit'] = i; st['false_lock'] = (i % flen) != true
                i += flen
            else:
                cc = 0; hist = []; i += 1
            continue
        err = max(0, err - 1) if good else err + 2
        if err >= 12:
            locked = False; cc = err = 0; hist = []; st['lof_events'] += 1; i += 1
            continue
        pos.append(i); i += flen
    st['pos'] = np.array(pos, np.int64)
    return st


def run(name, line, n, skew=0):
    sc = SCHEMES[name]
    if sc['lag'] is None:
        return s4_lof.framer(line, n, P4, skew=skew, confirm=CONF)
    return framer_lag(line, n, sc['lag'], skew=skew)


def falses(name, C, A):
    n = C.shape[0]; flen = 2 + 2 * n
    ln = build(C, A, SCHEMES[name]['pat'])
    return sum(1 for k in range(flen) if run(name, ln, n, skew=k)['false_lock'])


def main(secs=2.0):
    cv, sil = fr.load(secs); L = len(cv); idx = np.arange(L)
    tog = (idx & 1).astype(np.uint8)
    DATA = {'0': np.zeros(L, np.uint8), '1': np.ones(L, np.uint8),
            '1100': np.array([1, 1, 0, 0], np.uint8)[idx % 4],
            '0110': np.array([0, 1, 1, 0], np.uint8)[idx % 4],
            '1110': np.array([1, 1, 1, 0], np.uint8)[idx % 4],
            '1010': tog, 'random': np.random.default_rng(4).integers(0, 2, L).astype(np.uint8)}

    def layout(kind, n, data=None, hook=None, a_data=1):
        A = np.zeros((n, L), np.uint8); C = np.zeros((n, L), np.uint8)
        for j in range(n):
            s = kind[j % len(kind)]
            h = (j % 2) if hook is None else hook
            if s == 'V': A[j] = h; C[j] = np.roll(cv, 977 * j)
            if s == 'S': A[j] = h; C[j] = np.roll(sil, 13 * j)
            if s == 'E': C[j] = tog
            if s == 'd': A[j] = a_data; C[j] = data
        return C, A

    print('FALSE LOCKS over all start-up skews (worst over data patterns and hook states)')
    print(f'  {"case":34s} ' + ' '.join(f'{nm:>13s}' for nm in SCHEMES))
    for n in (1, 3, 7):
        flen = 2 + 2 * n
        cases = [
            ('speech, mixed hooks', lambda nm: falses(nm, *layout('V', n))),
            ('idle voice, on-hook', lambda nm: falses(nm, *layout('S', n, hook=0))),
            ('idle voice, off-hook', lambda nm: falses(nm, *layout('S', n, hook=1))),
            ('empty chassis', lambda nm: falses(nm, *layout('E', n))),
            ('data cards, any data', lambda nm: max(falses(nm, *layout('d', n, d)) for d in DATA.values())),
            ('voice/empty/data, any data', lambda nm: max(falses(nm, *layout('VEd', n, d)) for d in DATA.values())),
            ('CONTROL data A low, any data', lambda nm: max(falses(nm, *layout('d', n, d, a_data=0)) for d in DATA.values())),
        ]
        for cname, fn in cases:
            print(f'  N={n} {cname:30s} ' + ' '.join(f'{fn(nm):>9d}/{flen:<3d}' for nm in SCHEMES), flush=True)
        print()

    print('MIS-STRAP, narrow TX into wide RX: locks?  (speech / idle / data cards sending 1100)')
    for tx, rx in ((1, 3), (1, 7), (3, 7)):
        row = []
        for nm in SCHEMES:
            r = []
            for C, A in (layout('V', tx), layout('S', tx, hook=0), layout('d', tx, DATA['1100'])):
                r.append('L' if run(nm, build(C, A, SCHEMES[nm]['pat']), rx)['lock_bit'] is not None else '.')
            row.append(''.join(r))
        print(f'  N={tx} into N={rx}:  ' + '  '.join(f'{nm} {r}' for nm, r in zip(SCHEMES, row)), flush=True)
    print('  (L = locks, . = mutes)\n')

    print('LOSS OF FRAME: frames misaligned after a slip (worst over slip sizes), false reframes on a clean alignment')
    for n in (3, 7):
        flen = 2 + 2 * n; at = (L // 3) * flen
        print(f'  N={n}: {"scheme":12s} {"idle voice":>11s} {"empty+data":>11s} {"speech":>7s} {"reframes @1e-3/1e-2/3e-2/5e-2":>31s}')
        for nm in SCHEMES:
            pat = SCHEMES[nm]['pat']; w = []
            for C, A in (layout('S', n), layout('Ed', n, DATA['1']), layout('V', n)):
                ln = build(C, A, pat); worst = 0
                for k in range(1, flen):
                    st = run(nm, link.slip(ln, at, n=k), n); pp = st['pos']; after = pp[pp >= at]
                    if len(after) == 0: continue
                    bad = int((((after + k) % flen) != (pp[0] % flen)).sum())
                    worst = max(worst, bad)
                w.append('NEVER' if worst >= (L - L // 3) - 64 else str(worst))
            ln = build(*layout('V', n), pat)
            rf = [run(nm, link.impair(ln, ber=b, seed=5), n)['lof_events'] for b in (1e-3, 1e-2, 3e-2, 5e-2)]
            print(f'        {nm:12s} {w[0]:>11s} {w[1]:>11s} {w[2]:>7s} {str(rf):>31s}', flush=True)
    print()

    print('ACQUISITION (frames): clean, @1e-2, @3e-2 -- N=3 speech')
    for nm in SCHEMES:
        n = 3; flen = 8; ln = build(*layout('V', n), SCHEMES[nm]['pat'])
        cl = [run(nm, ln, n, skew=k)['lock_bit'] / flen for k in range(flen)]
        ab = []
        for b in (1e-2, 3e-2):
            t = [run(nm, link.impair(ln, ber=b, seed=s), n, skew=3)['lock_bit'] for s in (11, 12, 13)]
            ab.append(np.nanmean([x / flen if x is not None else np.nan for x in t]))
        print(f'  {nm:12s} clean {min(cl):.0f}-{max(cl):.0f}, @1e-2 {ab[0]:.0f}, @3e-2 {ab[1]:.0f}', flush=True)
    print()

    print('NOISE-ONLY LINE (N=3 receiver, 256 kbps, 3 s): locks on how many of 8 skews?')
    OS = 32; FS = 256000 * OS
    def lp(x, fc, o):
        b, a = signal.butter(o, min(0.99, 2 * fc / FS)); return signal.lfilter(b, a, x)
    for sd in (0.05, 0.2, 1.0):
        rng = np.random.default_rng(1)
        rb = fast.mono_decode(fast.slice_hyst(lp(rng.normal(0, sd, int(3.0 * FS)), 512000, 2), 0.05), OS)
        print(f'  sd {sd:4.2f}: ' + '  '.join(f'{nm} {sum(1 for k in range(8) if run(nm, rb, 3, skew=k)["lock_bit"] is not None)}/8'
                                        for nm in SCHEMES), flush=True)


if __name__ == '__main__':
    main()
