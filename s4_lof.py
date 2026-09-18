"""
S4 loss-of-frame policy.

After lock the S4 receiver checks T against its own phase counter (predictive),
because a sliding-window check spreads one line error over four frames.  But a
predictive check has a blind spot the level check never had: at a wrong
alignment whose T position carries a STATIC bit or a 1010 bit -- CVSD silence,
the frame-toggle empty-slot fill, a strapped-high A -- the prediction 1110
still matches three frames in four.  A +2/-1 counter trips only below 2/3, so
it never trips.  This measures candidate policies against that, and against
false reframes on a clean alignment under line errors.

SUPERSEDED: s4_simple.py shows the window counter alone (+1/-1 trip 16, no
phase counter) matches P4, and that is the framer in spec §7.  Kept as the record.

Result: P4 -- keep the predictive +2/-1 trip 12 counter, add a second counter
on the window check (+1/-1, trip 16), trip on either.  Detects every slip in
<= 18 frames on idle voice, empty slots with data cards, and speech, at N = 3
and 7; false reframes 0 / 0 / 0-1 at 1e-3 / 1e-2 / 3e-2.  P1 alone never
detects a slip onto the empty-slot fill or a data card.

Usage:  python3 s4_lof.py            policy comparison
        python3 s4_lof.py sanity     P4 end to end across the family
"""
import numpy as np, link, framing_review as fr

TP = (1, 1, 1, 0)
POLICIES = {
    'P1 predictive +2/-1 trip 12':          dict(up=2, dn=1, trip=12, win=None),
    'P1b predictive +3/-1 trip 12':         dict(up=3, dn=1, trip=12, win=None),
    'P2 predictive +4/-1 trip 16':          dict(up=4, dn=1, trip=16, win=None),
    'P3 predictive +5/-1 trip 20':          dict(up=5, dn=1, trip=20, win=None),
    'P4 +2/-1 trip 12, plus window +1/-1 16': dict(up=2, dn=1, trip=12, win=(1, 1, 16)),
    'P5 +2/-1 trip 12, plus window +1/-3 8':   dict(up=2, dn=1, trip=12, win=(1, 3, 8)),
}


def framer(line, n, pol, skew=0, confirm=32):
    flen = 2 + 2 * n
    if skew:
        line = np.roll(line, -skew)
    true = (flen - skew % flen) % flen
    i = cc = err = werr = 0; locked = False; hist = []; phase = 0; since = 0
    st = dict(lock_bit=None, false_lock=False, lof_events=0)
    pos = []; N = line.size
    while i + flen <= N:
        s, t = int(line[i + flen - 2]), int(line[i + flen - 1])
        win = hist[-3:] + [t]                      # T at this alignment, oldest first
        wok = (s == 0) and (win.count(0) == 1 if len(win) == 4 else win.count(0) <= 1)
        if not locked:
            hist = (hist + [t])[-3:]
            if wok:
                cc += 1
                if cc >= confirm:
                    locked = True; st['lock_bit'] = i; st['false_lock'] = (i % flen) != true
                    # win == TP rotated by r  ->  this frame's T is TP[r+3], the next is TP[r]
                    r = next(r for r in range(4) if all(win[j] == TP[(r + j) % 4] for j in range(4)))
                    phase = (r + 3) % 4; since = 0; err = werr = 0
                i += flen
            else:
                cc = 0; hist = []; i += 1
            continue
        since += 1
        good = (s == 0) and (t == TP[(phase + since) % 4])
        hist = (hist + [t])[-3:]
        err = max(0, err - pol['dn']) if good else err + pol['up']
        tripped = err >= pol['trip']
        if pol['win'] is not None:
            u, d, tr = pol['win']
            werr = max(0, werr - d) if wok else werr + u
            tripped |= werr >= tr
        if tripped:
            locked = False; cc = err = werr = 0; hist = []; st['lof_events'] += 1; i += 1
            continue
        pos.append(i); i += flen
    st['pos'] = np.array(pos, np.int64)
    return st


def misaligned_after_slip(ln, n, pol, k):
    flen = 2 + 2 * n; L = ln.size // flen; at = (L // 3) * flen
    st = framer(link.slip(ln, at, n=k), n, pol)
    pp = st['pos']
    after = pp[pp >= at]
    if len(after) == 0:
        return 0
    wrong = int((((after + k) % flen) != (pp[0] % flen)).sum())
    return wrong


if __name__ == '__main__' and not (len(__import__('sys').argv) > 1 and __import__('sys').argv[1] == 'sanity'):
    cv, sil = fr.load(3.0); L = len(cv)
    S4 = fr.SCHEMES['S4 T=1110 period 4']
    idx = np.arange(L); tog = (idx & 1).astype(np.uint8)
    for n in (3, 7):
        flen = 2 + 2 * n
        hooks = np.array([np.full(L, j % 2, np.uint8) for j in range(n)])
        # three worst-case idle lines: all silent voice; empty slots with the toggle fill;
        # data cards (A high) idling all ones next to toggle-filled empties
        idle_v = fr.gbuild(np.array([np.roll(sil, 13 * j) for j in range(n)]), hooks, S4)
        C = np.array([tog if j % 2 == 0 else np.ones(L, np.uint8) for j in range(n)])
        A = np.array([np.zeros(L, np.uint8) if j % 2 == 0 else np.ones(L, np.uint8) for j in range(n)])
        idle_mix = fr.gbuild(C, A, S4)
        speech = fr.gbuild(np.array([np.roll(cv, 977 * j) for j in range(n)]), hooks, S4)
        print(f'\nN={n}: frames left MISALIGNED after a slip (worst over slip sizes 1..{flen-1}), '
              f'and false reframes on a clean alignment')
        print(f'  {"policy":42s} {"idle voice":>11s} {"empty+data":>11s} {"speech":>8s} '
              f'{"reframes @1e-3/1e-2/3e-2/5e-2":>31s}')
        for name, pol in POLICIES.items():
            w = []
            for ln in (idle_v, idle_mix, speech):
                w.append(max(misaligned_after_slip(ln, n, pol, k) for k in range(1, flen)))
            rf = [framer(link.impair(speech, ber=b, seed=5), n, pol)['lof_events']
                  for b in (1e-3, 1e-2, 3e-2, 5e-2)]
            left = (L - L // 3)
            cells = [('NEVER' if x >= left - 64 else str(x)) for x in w]
            print(f'  {name:42s} {cells[0]:>11s} {cells[1]:>11s} {cells[2]:>8s} {str(rf):>31s}', flush=True)


def sanity(secs=2.0):
    """P4 end to end: every emitted frame at the true phase, no LOF on a clean
    line, across the family and the seat layouts the standard allows."""
    cv, sil = fr.load(secs); L = len(cv)
    S4 = fr.SCHEMES['S4 T=1110 period 4']; pol = POLICIES['P4 +2/-1 trip 12, plus window +1/-1 16']
    idx = np.arange(L); tog = (idx & 1).astype(np.uint8); d1110 = np.array([1, 1, 1, 0], np.uint8)[idx % 4]
    def layout(kind, n):
        A = np.zeros((n, L), np.uint8); C = np.zeros((n, L), np.uint8)
        for j in range(n):
            s = kind[j % len(kind)]
            if s == 'V': A[j] = j % 2; C[j] = np.roll(cv, 977 * j)
            if s == 'S': A[j] = j % 2; C[j] = np.roll(sil, 13 * j)
            if s == 'E': C[j] = tog
            if s == 'd': A[j] = 1; C[j] = d1110
        return fr.gbuild(C, A, S4)
    print('P4 sanity: false locks / skews, LOF events on a clean line, emitted frames off the true phase')
    for n in (1, 3, 7):
        flen = 2 + 2 * n
        for kind, name in (('V', 'voice'), ('S', 'idle voice'), ('E', 'empty chassis'), ('d', 'data cards 1110'), ('VEd', 'voice/empty/data')):
            ln = layout(kind, n); fl = lofs = off = 0
            for k in range(flen):
                st = framer(ln, n, pol, skew=k)
                fl += st['false_lock']; lofs += st['lof_events']
                true = (flen - k % flen) % flen
                off += int(((st['pos'] % flen) != true).sum())
            print(f'  N={n} {name:18s} false {fl}/{flen}  LOF {lofs}  off-phase frames {off}', flush=True)


if __name__ == '__main__' and len(__import__('sys').argv) > 1 and __import__('sys').argv[1] == 'sanity':
    sanity()
