"""
Can the S4 receiver drop its phase counter and predictive counter?

P4 (spec §7.2): predictive counter +2/-1 trip 12, plus window counter +1/-1 trip 16.
P6: window counter alone, +1/-1 trip 16.  No phase counter, nothing loaded at
lock, the same check for acquisition and tracking -- a 4-bit T history, an
"exactly one zero" decode and one 74HC193.

Measured on everything that has broken a framer in this project: idle voice,
empty slots with data cards, speech, steady tones near fs/4 at 16 kbps, line
errors, and the family-wide sanity set.

Usage:  python3 s4_simple.py         P4 against P6
        python3 s4_simple.py spec    the spec §7 receiver (framer_single), full battery
"""
import numpy as np, link, cvsd, run, framing_review as fr, s4_lof

POL = {'P4 spec (two counters)': s4_lof.POLICIES['P4 +2/-1 trip 12, plus window +1/-1 16'],
       'P6 window only +1/-1 trip 16': dict(up=0, dn=0, trip=10 ** 9, win=(1, 1, 16))}


def lof_worst(ln, n, pol, L):
    flen = 2 + 2 * n; at = (L // 3) * flen; worst = 0
    for k in range(1, flen):
        st = s4_lof.framer(link.slip(ln, at, n=k), n, pol); pp = st['pos']; after = pp[pp >= at]
        if len(after) == 0:
            continue
        worst = max(worst, int((((after + k) % flen) != (pp[0] % flen)).sum()))
    return 'NEVER' if worst >= (L - L // 3) - 64 else str(worst)


if __name__ == '__main__' and not (len(__import__('sys').argv) > 1 and __import__('sys').argv[1] == 'spec'):
    S4 = fr.SCHEMES['S4 T=1110 period 4']
    cv, sil = fr.load(3.0); L = len(cv); idx = np.arange(L); tog = (idx & 1).astype(np.uint8)

    print('LOSS OF FRAME: frames misaligned after a slip (worst over slip sizes); false reframes, clean alignment')
    for n in (3, 7):
        hooks = np.array([np.full(L, j % 2, np.uint8) for j in range(n)])
        idle = fr.gbuild(np.array([np.roll(sil, 13 * j) for j in range(n)]), hooks, S4)
        C = np.array([tog if j % 2 == 0 else np.ones(L, np.uint8) for j in range(n)])
        A = np.array([np.zeros(L, np.uint8) if j % 2 == 0 else np.ones(L, np.uint8) for j in range(n)])
        emd = fr.gbuild(C, A, S4)
        sp = fr.gbuild(np.array([np.roll(cv, 977 * j) for j in range(n)]), hooks, S4)
        print(f'  N={n}: {"policy":30s} {"idle voice":>10s} {"empty+data":>10s} {"speech":>7s} {"reframes @1e-3/1e-2/3e-2/5e-2":>30s}')
        for nm, pol in POL.items():
            w = [lof_worst(x, n, pol, L) for x in (idle, emd, sp)]
            rf = [s4_lof.framer(link.impair(sp, ber=b, seed=5), n, pol)['lof_events'] for b in (1e-3, 1e-2, 3e-2, 5e-2)]
            print(f'        {nm:30s} {w[0]:>10s} {w[1]:>10s} {w[2]:>7s} {str(rf):>30s}', flush=True)

    print('\n16 kbps, steady tone on an on-hook channel (N=3): frames misaligned after a slip')
    rate = 16000; p = run.params(rate); L16 = int(4.0 * rate); t = np.arange(L16) / rate
    src, fs = fr.audio.read_wav('speech30.wav', seconds=4.0)
    bl = fr.audio.bandlimit(src, fs)
    sp16 = cvsd.encode(fr.audio.resample_to(bl * run.NOMINAL_RMS / np.std(bl), fs, rate), p)
    sp16 = np.concatenate([sp16, sp16])[:L16]
    print(f'  {"tone":14s} ' + ' '.join(f'{nm:>30s}' for nm in POL))
    for f in (1004.0, 2600.0, 3000.0, 3400.0, 3800.0):
        x = run.NOMINAL_RMS * np.sqrt(2) * np.sin(2 * np.pi * f * t)
        b = cvsd.encode(x, p)
        C = np.array([b, np.roll(sp16, 977), np.roll(sp16, 1954)]); A = np.zeros((3, L16), np.uint8)
        ln = fr.gbuild(C, A, S4)
        print(f'  {f:6.0f} Hz 0 dB ' + ' '.join(f'{lof_worst(ln, 3, pol, L16):>30s}' for pol in POL.values()), flush=True)

    print('\nACQUISITION (frames, N=3 speech): clean / @1e-2 / @3e-2 -- first lock only')
    ln = fr.gbuild(np.array([np.roll(cv, 977 * j) for j in range(3)]), np.zeros((3, L), np.uint8), S4)
    for nm, pol in POL.items():
        cl = [s4_lof.framer(ln, 3, pol, skew=k)['lock_bit'] / 8 for k in range(8)]
        ab = []
        for b in (1e-2, 3e-2):
            x = []
            for s in (11, 12, 13):
                imp = link.impair(ln, ber=b, seed=s)
                # first lock: stop at the first lock by using an infinite trip on a copy of the policy
                st = s4_lof.framer(imp, 3, dict(up=0, dn=0, trip=10 ** 9, win=None), skew=3)
                x.append(st['lock_bit'] / 8 if st['lock_bit'] is not None else np.nan)
            ab.append(np.nanmean(x))
        print(f'  {nm:30s} clean {min(cl):.0f}-{max(cl):.0f}, @1e-2 {ab[0]:.0f}, @3e-2 {ab[1]:.0f}', flush=True)

    print('\nSANITY, P6 across the family (false locks, LOF events, off-phase frames)')
    s4_lof.POLICIES['P4 +2/-1 trip 12, plus window +1/-1 16'] = POL['P6 window only +1/-1 trip 16']
    s4_lof.sanity()


# ----------------------------------------------------------------------------
# The receiver as specified (spec §7): one counter, and the hardware-friendly
# rule for the first frames after a slip -- S alone until three frames have been
# seen, taken from the acquisition counter the framer already has.
# ----------------------------------------------------------------------------
def framer_single(line, n, skew=0, confirm=32, up=1, dn=1, trip=16):
    """Reference model of the spec §7 framer.

        check   := S == 0  AND  (fewer than 3 frames since the slip
                                 OR the last four T contain exactly one 0)
        acquire :  32 consecutive good frames; slip one line bit on a bad one
        track   :  the same check; +1 bad / -1 good, floor 0, trip at 16
    """
    flen = 2 + 2 * n
    if skew:
        line = np.roll(line, -skew)
    true = (flen - skew % flen) % flen
    i = cc = err = 0; locked = False; hist = []
    st = dict(lock_bit=None, false_lock=False, lof_events=0); pos = []
    N = line.size
    while i + flen <= N:
        s, t = int(line[i + flen - 2]), int(line[i + flen - 1])
        good = (s == 0) and (len(hist) < 3 or (hist[-3:] + [t]).count(0) == 1)
        hist = (hist + [t])[-3:]
        if not locked:
            if good:
                cc += 1
                if cc >= confirm:
                    locked = True; st['lock_bit'] = i; st['false_lock'] = (i % flen) != true
                i += flen
            else:
                cc = 0; hist = []; i += 1
            continue
        err = max(0, err - dn) if good else err + up
        if err >= trip:
            locked = False; cc = err = 0; hist = []; st['lof_events'] += 1; i += 1
            continue
        pos.append(i); i += flen
    st['pos'] = np.array(pos, np.int64)
    return st


def validate_spec_receiver(secs=3.0):
    import fast, t_pattern as tp
    from scipy import signal
    S4 = fr.SCHEMES['S4 T=1110 period 4']
    cv, sil = fr.load(secs); L = len(cv); idx = np.arange(L); tog = (idx & 1).astype(np.uint8)
    DATA = {'0': np.zeros(L, np.uint8), '1': np.ones(L, np.uint8),
            '1110': np.array([1, 1, 1, 0], np.uint8)[idx % 4], '1100': np.array([1, 1, 0, 0], np.uint8)[idx % 4],
            '1010': tog, 'random': np.random.default_rng(4).integers(0, 2, L).astype(np.uint8)}

    def layout(kind, n, data=None, hook=None, a_data=1, empty_c=None):
        A = np.zeros((n, L), np.uint8); C = np.zeros((n, L), np.uint8)
        for j in range(n):
            s = kind[j % len(kind)]; h = (j % 2) if hook is None else hook
            if s == 'V': A[j] = h; C[j] = np.roll(cv, 977 * j)
            if s == 'S': A[j] = h; C[j] = np.roll(sil, 13 * j)
            if s == 'E': C[j] = tog if empty_c is None else empty_c
            if s == 'd': A[j] = a_data; C[j] = data
        return C, A

    def falses(C, A):
        n = C.shape[0]; flen = 2 + 2 * n; ln = fr.gbuild(C, A, S4)
        return sum(1 for k in range(flen) if framer_single(ln, n, skew=k)['false_lock'])

    print('SPEC RECEIVER (framer_single): false locks over all start-up skews')
    for n in (1, 3, 7):
        flen = 2 + 2 * n
        rows = [('speech, mixed hooks', falses(*layout('V', n))),
                ('idle voice, on-hook', falses(*layout('S', n, hook=0))),
                ('idle voice, off-hook', falses(*layout('S', n, hook=1))),
                ('empty chassis', falses(*layout('E', n))),
                ('data cards, worst data', max(falses(*layout('d', n, d)) for d in DATA.values())),
                ('voice/empty/data, worst data', max(falses(*layout('VEd', n, d)) for d in DATA.values())),
                ('empty pulled low + data idling 1', falses(*layout('Ed', n, DATA['1'], empty_c=DATA['0']))),
                ('CONTROL data A low, worst data', max(falses(*layout('d', n, d, a_data=0)) for d in DATA.values()))]
        for nm, v in rows:
            print(f'  N={n} {nm:34s} {v}/{flen}', flush=True)

    print('\nSPEC RECEIVER: frames misaligned after a slip (worst over slip sizes); false reframes')
    for n in (3, 7):
        flen = 2 + 2 * n; at = (L // 3) * flen
        def worst(C, A):
            ln = fr.gbuild(C, A, S4); w = 0
            for k in range(1, flen):
                st = framer_single(link.slip(ln, at, n=k), n); pp = st['pos']; after = pp[pp >= at]
                if len(after): w = max(w, int((((after + k) % flen) != (pp[0] % flen)).sum()))
            return 'NEVER' if w >= (L - L // 3) - 64 else str(w)
        sp = fr.gbuild(*layout('V', n), S4)
        rf = [framer_single(link.impair(sp, ber=b, seed=5), n)['lof_events'] for b in (1e-3, 1e-2, 3e-2, 5e-2)]
        print(f'  N={n}: idle voice {worst(*layout("S", n))}, empty+data {worst(*layout("Ed", n, DATA["1"]))}, '
              f'speech {worst(*layout("V", n))};  reframes @1e-3/1e-2/3e-2/5e-2 {rf}', flush=True)

    print('\nSPEC RECEIVER: 16 kbps steady tone on an on-hook channel, N=3, frames misaligned after a slip')
    rate = 16000; p = run.params(rate); L16 = int(4.0 * rate); t = np.arange(L16) / rate
    src, fs = fr.audio.read_wav('speech30.wav', seconds=4.0); bl = fr.audio.bandlimit(src, fs)
    sp16 = cvsd.encode(fr.audio.resample_to(bl * run.NOMINAL_RMS / np.std(bl), fs, rate), p)
    sp16 = np.concatenate([sp16, sp16])[:L16]
    out = []
    for f in (1004.0, 2600.0, 3000.0, 3400.0, 3800.0):
        b = cvsd.encode(run.NOMINAL_RMS * np.sqrt(2) * np.sin(2 * np.pi * f * t), p)
        ln = fr.gbuild(np.array([b, np.roll(sp16, 977), np.roll(sp16, 1954)]), np.zeros((3, L16), np.uint8), S4)
        at = (L16 // 3) * 8; w = 0
        for k in range(1, 8):
            st = framer_single(link.slip(ln, at, n=k), 3); pp = st['pos']; after = pp[pp >= at]
            if len(after): w = max(w, int((((after + k) % 8) != (pp[0] % 8)).sum()))
        out.append(f'{f:.0f} Hz {("NEVER" if w >= (L16 - L16 // 3) - 64 else w)}')
    print('  ' + ',  '.join(out), flush=True)

    print('\nSPEC RECEIVER: acquisition, N=3 speech (frames): clean / @1e-2 / @3e-2, first lock')
    ln = fr.gbuild(*layout('V', 3), S4)
    cl = [framer_single(ln, 3, skew=k)['lock_bit'] / 8 for k in range(8)]
    ab = []
    for b in (1e-2, 3e-2):
        x = [framer_single(link.impair(ln, ber=b, seed=s), 3, skew=3, trip=10 ** 9)['lock_bit'] for s in (11, 12, 13)]
        ab.append(np.nanmean([v / 8 if v is not None else np.nan for v in x]))
    print(f'  clean {min(cl):.0f}-{max(cl):.0f}, @1e-2 {ab[0]:.0f}, @3e-2 {ab[1]:.0f}', flush=True)

    print('\nSPEC RECEIVER: mis-strap, narrow TX into wide RX (speech / idle / data cards 1110)')
    for tx, rx in ((1, 3), (1, 7), (3, 7)):
        r = ''.join('L' if framer_single(fr.gbuild(C, A, S4), rx)['lock_bit'] is not None else '.'
                    for C, A in (layout('V', tx), layout('S', tx, hook=0), layout('d', tx, DATA['1110'])))
        print(f'  N={tx} into N={rx}: {r}   (L locks, . mutes)', flush=True)

    print('\nSPEC RECEIVER: noise-only line, N=3 at 256 kbps -- locks on how many of 8 skews')
    OS = 32; FS = 256000 * OS
    def lp(x, fc, o):
        bb, aa = signal.butter(o, min(0.99, 2 * fc / FS)); return signal.lfilter(bb, aa, x)
    for sd in (0.05, 0.2, 1.0):
        rng = np.random.default_rng(1)
        rb = fast.mono_decode(fast.slice_hyst(lp(rng.normal(0, sd, int(3.0 * FS)), 512000, 2), 0.05), OS)
        print(f'  sd {sd:4.2f}: {sum(1 for k in range(8) if framer_single(rb, 3, skew=k)["lock_bit"] is not None)}/8', flush=True)


if __name__ == '__main__' and len(__import__('sys').argv) > 1 and __import__('sys').argv[1] == 'spec':
    validate_spec_receiver()
