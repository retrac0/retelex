"""Simulation check of seatmix.py's enumeration: the S4 header with empty slots
and 32k data cards (A strapped high), including the negative controls."""
import numpy as np, link, framing_review as fr

cv, sil = fr.load(1.5); L = len(cv)
S4 = fr.SCHEMES['S4 T=1110 period 4']
S0 = fr.SCHEMES['S0 static (0,1)']
idx = np.arange(L)
DATA = {'const 0': np.zeros(L, np.uint8), 'const 1': np.ones(L, np.uint8),
        '1110': np.array([1, 1, 1, 0], np.uint8)[idx % 4],
        '0111': np.array([0, 1, 1, 1], np.uint8)[idx % 4],
        '1010': (idx & 1).astype(np.uint8),
        'random': np.random.default_rng(9).integers(0, 2, L).astype(np.uint8)}


def frame(seats, data, hook=0):
    n = len(seats)
    A = np.zeros((n, L), np.uint8); C = np.zeros((n, L), np.uint8)
    for j, s in enumerate(seats):
        if s == 'V':  A[j] = hook; C[j] = np.roll(cv, 977 * j)
        elif s == 'E0': pass
        elif s == 'E1': A[j] = 1; C[j] = 1
        elif s == 'd1': A[j] = 1; C[j] = data
        elif s == 'd0': C[j] = data
        elif s == 'D':  A[j] = 0; C[j] = data
    return C, A


def falses(seats, data, sch, hook=0):
    C, A = frame(seats, data, hook)
    ln = fr.gbuild(C, A, sch); n = len(seats); flen = sch['F'] + 2 * n
    return sum(1 for k in range(flen) if fr.gframer(ln, n, sch, skew=k)[1]['false_lock']), flen


def row(label, seats, sch=S4, datas=DATA, hooks=(0, 1)):
    worst, flen, which = 0, 0, ''
    for dn, d in datas.items():
        for h in hooks:
            f, flen = falses(seats, d, sch, h)
            if f > worst:
                worst, which = f, f'{dn}, hook {h}'
    print(f'  {label:44s} {worst:>3d}/{flen}' + (f'   <-- locks ({which})' if worst else ''), flush=True)


print('S4 header (S=0, T=1110), N=7 -- worst false locks over every data pattern and hook state')
row('empty chassis, pulled low', ['E0'] * 7)
row('empty chassis, pulled high', ['E1'] * 7)
row('one data card, seat 1, rest empty', ['d1'] + ['E0'] * 6)
row('one data card, seat 7, rest empty', ['E0'] * 6 + ['d1'])
row('seven data cards', ['d1'] * 7)
row('V E d V E d V', ['V', 'E0', 'd1', 'V', 'E0', 'd1', 'V'])
row('d d d V V V V', ['d1', 'd1', 'd1', 'V', 'V', 'V', 'V'])
print('  -- negative controls (enumeration says these lock) --')
row('seven data cards with A strapped LOW', ['d0'] * 7)
row('64k card (data on A) in seat 1, rest empty', ['D'] + ['E0'] * 6)
print()
print('Present framer (0,1), N=7, voice cards and ONE empty slot')
row('V V V E0 V V V', ['V', 'V', 'V', 'E0', 'V', 'V', 'V'], sch=S0, datas={'-': DATA['const 0']})
row('V V V E1 V V V', ['V', 'V', 'V', 'E1', 'V', 'V', 'V'], sch=S0, datas={'-': DATA['const 0']})
print()
print('S4 mis-strap with data cards carrying 1110 (narrow TX into wide RX)')
for tx, rx in ((1, 3), (3, 7), (1, 7)):
    C, A = frame(['d1'] * tx, DATA['1110'])
    ln = fr.gbuild(C, A, S4)
    st = fr.gframer(ln, rx, S4)[1]
    print(f'  N={tx} into N={rx}: {"LOCKS" if st["lock_bit"] is not None else "mutes"}', flush=True)
print()
C, A = frame(['V', 'E0', 'd1', 'V', 'E0', 'd1', 'V'], DATA['random'], hook=1)
ln = fr.gbuild(C, A, S4); flen = 16
ms = [1000.0 * fr.gframer(ln, 7, S4, skew=k)[1]['lock_bit'] / (fr.RATE * flen) for k in range(flen)]
rf = [fr.gframer(link.impair(ln, ber=b, seed=5), 7, S4)[1]['lof_events'] for b in (1e-3, 1e-2, 3e-2)]
print(f'S4, V E d V E d V: acquisition {min(ms):.2f}-{max(ms):.2f} ms (confirm 64), '
      f'false reframes @1e-3/1e-2/3e-2 {rf}')
