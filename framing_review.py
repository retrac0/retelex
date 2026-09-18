"""
Framing and sync, re-evaluated from scratch.

Everything this session learned about what a framer must survive, turned into
one battery, and run against every framing scheme worth considering, side by
side.  The framer is generic: a scheme is a framing-field width F, a TX pattern
generator, and an RX check that sees the current framing bits and the history
of framing bits at the SAME alignment (cleared on every slip).

Payload classes the battery uses -- each one has already broken something:
    speech        CVSD, random in level, ~95% alternating in transition
    silence       CVSD idle, exactly 1010...  (killed both toggling schemes)
    constant      a data slot at all-0 or all-1 (breaks static framing)
    static A bits in either hook state, mixed across channels
    the narrow-frame-into-wide-receiver mis-strap (spec family divisibility)

Usage:  python3 framing_review.py [quick|all]
"""
import sys, numpy as np
import audio, cvsd, link, run

RATE = 32000
CONF, LOF, LUP, LDN = 64, 12, 2, 1
MSEQ7 = (1, 1, 1, 0, 0, 1, 0)                 # period-7 m-sequence


# ------------------------------------------------------------------ schemes
def _rot_ok(win, pat):
    """Is `win` a prefix of some rotation of `pat`?"""
    P = len(pat)
    for r in range(P):
        if all(win[j] == pat[(r + j) % P] for j in range(len(win))):
            return True
    return False


def rx_static(word):
    return lambda fb, hist: fb == word


def rx_tperiodic(pat, P):
    """S == 0, and the T history (including now) is consistent with `pat` at
    some rotation.  Phase-free."""
    def rx(fb, hist):
        if fb[0] != 0:
            return False
        win = [h[1] for h in hist[-(P - 1):]] + [fb[1]]
        return _rot_ok(win, pat)
    return rx


SCHEMES = {
    'S0 static (0,1)':
        dict(F=2, tx=lambda i: (0, 1), rx=rx_static((0, 1)), K=1),
    'S2 static 4-bit (0,1,1,0)':
        dict(F=4, tx=lambda i: (0, 1, 1, 0), rx=rx_static((0, 1, 1, 0)), K=1),
    'S2b static 4-bit (0,0,1,1)':
        dict(F=4, tx=lambda i: (0, 0, 1, 1), rx=rx_static((0, 0, 1, 1)), K=1),
    'S4 T=1110 period 4':
        dict(F=2, tx=lambda i: (0, (1, 1, 1, 0)[i % 4]),
             rx=rx_tperiodic((1, 1, 1, 0), 4), K=3, P=4, tpat=(1, 1, 1, 0)),
    'S5 T=m-seq period 7':
        dict(F=2, tx=lambda i: (0, MSEQ7[i % 7]),
             rx=rx_tperiodic(MSEQ7, 7), K=6, P=7, tpat=MSEQ7),
}


# ------------------------------------------------------------ build / frame
def gbuild(chan, sig, sch):
    chan = np.atleast_2d(chan); sig = np.atleast_2d(sig)
    n, L = chan.shape
    F = sch['F']; flen = F + 2 * n
    f = np.zeros((L, flen), np.uint8)
    for j in range(n):
        f[:, 2 * j] = sig[j]
        f[:, 2 * j + 1] = chan[j]
    idx = np.arange(L)
    for b in range(F):
        f[:, 2 * n + b] = [sch['tx'](i)[b] for i in idx] if F else 0
    return f.reshape(-1)


def gframer(line, n_ch, sch, skew=0, predictive=True):
    F = sch['F']; flen = F + 2 * n_ch
    if skew:
        line = np.roll(line, -skew)
    true_phase = (flen - (skew % flen)) % flen
    rx, K = sch['rx'], sch['K']
    P, tpat = sch.get('P'), sch.get('tpat')
    chan_out = [[] for _ in range(n_ch)]
    sig_out = [[] for _ in range(n_ch)]
    i = 0; cc = 0; err = 0; locked = False; hist = []
    phase = None; since = 0
    st = dict(lock_bit=None, lock_phase=None, slips=0, lof_events=0, frames=0,
              false_lock=False)
    pos = []; N = line.size
    while i + flen <= N:
        f = line[i:i + flen]
        fb = tuple(int(x) for x in f[flen - F:])
        if locked and predictive and tpat is not None and phase is not None:
            good = (fb[0] == 0) and (fb[1] == tpat[(phase + since) % P])
        else:
            good = rx(fb, hist)
        hist = (hist + [fb])[-K:] if K else []
        if not locked:
            if good:
                cc += 1
                if cc >= CONF:
                    locked = True
                    st['lock_bit'] = i; st['lock_phase'] = i % flen
                    st['false_lock'] = (i % flen) != true_phase
                    if tpat is not None:            # derive pattern phase from history
                        win = [h[1] for h in hist]
                        for r in range(P):
                            if all(win[j] == tpat[(r + j) % P] for j in range(len(win))):
                                phase = (r + len(win)) % P; break
                        since = 0
                i += flen
            else:
                cc = 0; st['slips'] += 1; hist = []; i += 1
            continue
        since += 1
        err = max(0, err - LDN) if good else err + LUP
        if err >= LOF:
            locked = False; cc = 0; err = 0; hist = []; phase = None
            st['lof_events'] += 1; i += 1
            continue
        for c in range(n_ch):
            chan_out[c].append(f[2 * c + 1]); sig_out[c].append(f[2 * c])
        st['frames'] += 1; pos.append(i); i += flen
    ch = np.array([np.array(c, np.uint8) for c in chan_out]) if st['frames'] \
        else np.zeros((n_ch, 0), np.uint8)
    st['pos'] = np.array(pos, np.int64)
    return ch, st


# ---------------------------------------------------------------- battery
def load(secs):
    src, fs = audio.read_wav('speech30.wav', seconds=secs)
    src = audio.resample_to(audio.bandlimit(src, fs) * 0.15, fs, RATE)
    p = run.params(RATE)
    return cvsd.encode(src, p), cvsd.encode(np.zeros(len(src)), p)


def bitexact(c, ref):
    best = 1.0
    for o in range(600):
        nn = min(len(ref) - o, len(c))
        if nn < 10000: break
        best = min(best, float((c[:nn] != ref[o:o + nn]).mean()))
        if best == 0.0: break
    return best == 0.0


def battery(name, sch, cv, sil, ns=(3, 7)):
    F = sch['F']; L = len(cv); R = {}
    for n in ns:
        flen = F + 2 * n
        ch = np.array([np.roll(cv, 977 * j) for j in range(n)])
        sg = np.array([np.full(L, j % 2, np.uint8) for j in range(n)])
        ln = gbuild(ch, sg, sch)
        # B1 speech: acquire, bit-exact, acquisition time
        acq = []; fl = 0; be = True
        for k in range(flen):
            c, st = gframer(ln, n, sch, skew=k)
            if st['lock_bit'] is None: acq.append(np.nan); continue
            fl += st['false_lock']
            acq.append(1000.0 * st['lock_bit'] / (RATE * flen))
            if k in (0, 3): be &= bitexact(c[0], ch[0])
        # LOF worst over slip sizes, false reframes at BER
        lnq = gbuild(ch, np.zeros((n, L), np.uint8), sch)
        at = (L // 2) * flen; worst = 0.0
        for k in range(1, flen):
            st = gframer(link.slip(lnq, at, n=k), n, sch)[1]; pp = st['pos']
            if len(pp) == 0: worst = 9e9; continue
            tp = np.where(pp < at, pp % flen, (pp + k) % flen)
            worst = max(worst, 1000 * int((tp != tp[0]).sum()) / RATE)
        fr = [gframer(link.impair(lnq, ber=x, seed=5), n, sch)[1]['lof_events']
              for x in (1e-3, 1e-2, 3e-2)]
        # B5 acquisition under errors
        acqb = {}
        for ber in (1e-2, 3e-2):
            t = [gframer(link.impair(lnq, ber=ber, seed=s), n, sch, skew=3)[1]['lock_bit']
                 for s in (11, 12, 13)]
            t = [1000.0 * x / (RATE * flen) if x is not None else np.nan for x in t]
            acqb[ber] = np.nanmean(t) if not all(np.isnan(t)) else np.nan
        # B2 idle link
        chs = np.array([np.roll(sil, 13 * j) for j in range(n)])
        lni = gbuild(chs, sg, sch)
        idle_fl = sum(1 for k in range(flen) if gframer(lni, n, sch, skew=k)[1]['false_lock'])
        # B3 constant data slot, the four worst adjacencies, first and last seat
        cfl = 0
        for slot in (0, n - 1):
            for const, a_s, oth in ((1, 0, 0), (0, 0, 1), (1, 0, 1), (0, 1, 1)):
                ch2 = ch.copy(); ch2[slot] = const
                sg2 = np.full((n, L), oth, np.uint8); sg2[slot] = a_s
                ln2 = gbuild(ch2, sg2, sch)
                cfl += sum(1 for k in range(flen) if gframer(ln2, n, sch, skew=k)[1]['false_lock'])
        R[n] = dict(flen=flen, acq=(np.nanmin(acq), np.nanmax(acq)), speech_fl=fl,
                    bitexact=be, lof=worst, fr=fr, acqb=acqb, idle_fl=idle_fl,
                    const_fl=cfl, const_cases=8 * flen)
        print(f'    {name} N={n}: done', flush=True)
    # B4 mis-strap (uses N=1 TX)
    ms = {}
    for tx_n, rx_n in ((1, 3), (1, 7), (3, 7)):
        cht = np.array([np.roll(cv, 977 * j) for j in range(tx_n)])
        lnt = gbuild(cht, np.zeros((tx_n, L), np.uint8), sch)
        ms[(tx_n, rx_n)] = gframer(lnt, rx_n, sch)[1]['lock_bit'] is not None
    R['mis'] = ms
    return R


def report(results):
    print('\n' + '=' * 100)
    print('FRAMING SCHEMES, SIDE BY SIDE   (N=3 / N=7;  "fl" = false locks out of all start-up skews)')
    print('=' * 100)
    hdr = (f'{"scheme":28s} {"F":>2s} {"frame":>7s} {"acq ms":>11s} {"speech fl":>9s} {"idle fl":>8s} '
           f'{"const fl":>9s} {"LOF ms":>7s} {"reframes@1e-3/1e-2/3e-2":>24s} {"acq@1e-2":>9s} {"acq@3e-2":>9s} '
           f'{"1>3":>4s} {"1>7":>4s} {"3>7":>4s}')
    print(hdr)
    for name, R in results.items():
        for n in (3, 7):
            r = R[n]; m = R['mis']
            print(f'{name if n==3 else "":28s} {R[3]["flen"]-6:>2d} {r["flen"]:>4d}b N{n} '
                  f'{r["acq"][0]:5.2f}-{r["acq"][1]:<5.2f} {r["speech_fl"]:>4d}/{r["flen"]:<4d} '
                  f'{r["idle_fl"]:>3d}/{r["flen"]:<4d} {r["const_fl"]:>4d}/{r["const_cases"]:<4d} '
                  f'{r["lof"]:7.2f} {str(r["fr"]):>24s} {r["acqb"][1e-2]:8.1f}m {r["acqb"][3e-2]:8.1f}m '
                  + (f'{"LOCK" if m[(1,3)] else "ok":>4s} {"LOCK" if m[(1,7)] else "ok":>4s} '
                     f'{"LOCK" if m[(3,7)] else "ok":>4s}' if n == 3 else ''))
        print()


# ----------------------------------------------------- the 110 + D layout
# frame = [1][1][0][D][A1][C1] ... [A6][C6]  (16 bits): a 3-bit word whose third
# bit is the strapped A of a designated data slot, so the strap is VERIFIED by
# the framer rather than relied on.  D is the data slot's C bit and is free.
def build_110(D, voice, hooks, extra=None):
    n = voice.shape[0]; L = voice.shape[1]; flen = 4 + 2 * n
    f = np.zeros((L, flen), np.uint8)
    f[:, 0] = 1; f[:, 1] = 1; f[:, 2] = 0; f[:, 3] = D
    for j in range(n):
        f[:, 4 + 2 * j] = hooks[j]; f[:, 5 + 2 * j] = voice[j]
    if extra is not None:                       # a second constant slot (slot, value)
        f[:, 5 + 2 * (extra[0] - 1)] = extra[1]
    return f.reshape(-1)


def framer_110(line, n, skew=0):
    """Checks positions 0..2 == (1,1,0).  Same acquisition and LOF policy as gframer."""
    flen = 4 + 2 * n
    if skew:
        line = np.roll(line, -skew)
    true = (flen - skew % flen) % flen
    i = cc = err = 0; locked = False; lockbit = None; false = None; lof = 0
    while i + flen <= len(line):
        f = line[i:i + flen]
        good = (f[0] == 1 and f[1] == 1 and f[2] == 0)
        if not locked:
            if good:
                cc += 1
                if cc >= CONF:
                    locked = True; lockbit = i; false = ((i % flen) != true)
                i += flen
            else:
                cc = 0; i += 1
            continue
        err = max(0, err - LDN) if good else err + LUP
        if err >= LOF:
            locked = False; cc = err = 0; lof += 1; i += 1
            continue
        i += flen
    return dict(lock_bit=lockbit, false_lock=false, lof_events=lof)


def battery_110(cv, sil, n=6):
    flen = 4 + 2 * n; L = len(cv)
    voice = np.array([np.roll(cv, 977 * j) for j in range(n)])
    idle = np.array([np.roll(sil, 13 * j) for j in range(n)])
    tog = (np.arange(L) & 1).astype(np.uint8)
    HK = {'on-hook': [0] * n, 'off-hook': [1] * n, 'mixed': [j % 2 for j in range(n)]}
    print(f'\n110 + D, {n} voice channels, {flen} bits -- false locks / {flen} skews')
    print(f'  {"D payload":>12s} ' + ' '.join(f'{h:>9s}' for h in HK))
    for dn, D in (('voice', np.roll(cv, 4321)), ('const 0', np.zeros(L, np.uint8)),
                  ('const 1', np.ones(L, np.uint8)), ('1010', tog), ('0101', 1 - tog)):
        row = [sum(1 for k in range(flen) if framer_110(build_110(D, voice, hk), n, k)['false_lock'])
               for hk in HK.values()]
        print(f'  {dn:>12s} ' + ' '.join(f'{r:>6d}/{flen}' for r in row))
    ln = build_110(np.roll(cv, 4321), idle, [0] * n)
    print(f'  {"idle link":>12s} {sum(1 for k in range(flen) if framer_110(ln, n, k)["false_lock"]):>6d}/{flen}')
    print('  second constant slot in the voice area (D=1, all off-hook):')
    for slot in (1, n):
        for c in (0, 1):
            ln = build_110(np.ones(L, np.uint8), voice, [1] * n, extra=(slot, c))
            print(f'    slot {slot} const {c}: {sum(1 for k in range(flen) if framer_110(ln, n, k)["false_lock"])}/{flen}')
    ln = build_110(np.roll(cv, 4321), voice, HK['mixed'])
    ms = [1000 * framer_110(ln, n, k)['lock_bit'] / (RATE * flen) for k in range(flen)]
    frs = [framer_110(link.impair(ln, ber=b, seed=5), n)['lof_events'] for b in (1e-3, 1e-2, 3e-2)]
    print(f'  acquisition {min(ms):.2f}-{max(ms):.2f} ms; false reframes @1e-3/1e-2/3e-2: {frs}')


if __name__ == '__main__':
    what = sys.argv[1] if len(sys.argv) > 1 else 'all'
    secs = 2.0 if what == 'quick' else 3.0
    cv, sil = load(secs)
    print(f'material: {secs:.0f} s speech ({len(cv)} frames), CVSD silence '
          f'{"".join(map(str, sil[:12]))}...', flush=True)
    results = {}
    for name, sch in SCHEMES.items():
        print(f'  running {name}', flush=True)
        results[name] = battery(name, sch, cv, sil)
    report(results)
    battery_110(cv, sil)
