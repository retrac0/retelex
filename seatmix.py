"""
Which mixes of channel cards, empty slots and data cards are safe against
false frame lock, under which header?  Enumerates every combination of seat
types for a given header and counts the ones where some wrong alignment can be
held indefinitely by payload that is allowed to do whatever it likes.

Bit classes across frames, at one bit position:
    fix0 / fix1   pulled or strapped to a constant
    hook          a static level the adversary chooses (E&M hook state)
    cvsd          CVSD: random in speech, 1010 in silence -- holds no static
                  value and no period-4 pattern indefinitely
    tog           the frame toggle, 1010 at a fixed phase
    data          payload with no constraints at all: any constant, any pattern
"""
import itertools

SEATS = {
    'V':  ('hook', 'cvsd'),   # CVSD voice card
    'E0': ('fix0', 'fix0'),   # empty slot, both bits pulled low
    'E1': ('fix1', 'fix1'),   # empty slot, both bits pulled high
    'Et': ('fix0', 'tog'),    # empty slot, C fed the frame toggle
    'd0': ('fix0', 'data'),   # 32k data card, data on C, A strapped low
    'd1': ('fix1', 'data'),   # 32k data card, data on C, A strapped HIGH
    'dt': ('tog',  'data'),   # 32k data card, data on C, A fed the frame toggle
    'D':  ('data', 'data'),   # 64k data card, data on A and C
}


def bits(pat):
    out = []
    for s in pat:
        out += list(SEATS[s])
    return out


def static_word_unsafe(pat, W):
    """Frame = payload then header W (static).  A wrong alignment is held if
    every bit in its window can equal the word forever."""
    b = bits(pat) + [('fix%d' % x) for x in W]
    flen, F = len(b), len(W)
    for k in range(1, flen):
        ok = True
        for j in range(F):
            c = b[(flen - F + k + j) % flen]
            if c in ('cvsd', 'tog'):
                ok = False; break
            if c.startswith('fix') and int(c[3]) != W[j]:
                ok = False; break
        if ok:
            return True
    return False


def s4_unsafe(pat):
    """Frame = payload then (S, T), S = 0, T = 1110 repeating over 4 frames.
    A wrong pair (x, y) is held only if x can be 0 on every frame AND y can
    follow 1110 forever.  Only a DATA bit can do the latter."""
    b = bits(pat) + ['fix0', 'pat']
    flen = len(b)
    for k in range(1, flen):
        x, y = b[(flen - 2 + k) % flen], b[(flen - 1 + k) % flen]
        if x in ('fix0', 'hook', 'data') and y == 'data':
            return True
    return False


HEADERS = {
    '(0,1) static, N=7': (7, lambda p: static_word_unsafe(p, (0, 1))),
    '1100 static, N=6':  (6, lambda p: static_word_unsafe(p, (1, 1, 0, 0))),
    'S4 T=1110, N=7':    (7, s4_unsafe),
}

MIXES = [
    ('V + E0',            ('V', 'E0')),
    ('V + E0 + d1',       ('V', 'E0', 'd1')),
    ('V + E1 + d1',       ('V', 'E1', 'd1')),
    ('V + E0 + d0',       ('V', 'E0', 'd0')),
    ('V + Et + dt',       ('V', 'Et', 'dt')),
    ('V + E0 + D',        ('V', 'E0', 'D')),
    ('V + E0 + d1 + D',   ('V', 'E0', 'd1', 'D')),
]

if __name__ == '__main__':
    print('Unsafe combinations / all combinations, per header and seat alphabet')
    print('  (V voice, E0/E1 empty pulled low/high, Et empty with C = frame toggle,')
    print('   d1/d0/dt 32k data on C with A high/low/toggle, D 64k data on A and C)\n')
    print(f'  {"alphabet":18s} ' + ' '.join(f'{h:>20s}' for h in HEADERS))
    for name, alpha in MIXES:
        row = []
        for h, (n, f) in HEADERS.items():
            pats = list(itertools.product(alpha, repeat=n))
            u = sum(f(p) for p in pats)
            row.append(f'{u}/{len(pats)}')
        print(f'  {name:18s} ' + ' '.join(f'{r:>20s}' for r in row))
    print()
    for h, (n, f) in HEADERS.items():
        pats = list(itertools.product(('V', 'E0', 'd1', 'D'), repeat=n))
        bad = [p for p in pats if f(p)]
        withD = sum(1 for p in bad if 'D' in p)
        print(f'  {h}: unsafe patterns that contain no 64k card: {len(bad) - withD}')
