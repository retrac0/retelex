"""
The N = 1 / 3 / 7 family, at every CVSD rate, with the framing and line rates
computed rather than asserted.

The frame clock IS the codec clock (spec 3), so the CVSD rate sets the frame
rate and everything scales from it:

    frame length   flen = 2 + 2N                  (power of two only at N=1,3,7)
    line rate      = codec rate x flen
    symbol rate    = 2 x line rate                (differential Manchester)
    oscillator     = 16 x symbol rate             (the /16 tap on the 4040)
    osc / frame    = 32 x flen                    -> binary iff flen is
"""
import numpy as np, sys

RATES = (16000, 32000, 64000)
NS = (1, 3, 7)
REACH_ANCHOR = (128e3, 1.7)     # spec 10: fundamental 128 kHz -> order 1.7 km


def cfg(n, rate):
    flen = 2 + 2 * n
    line = rate * flen
    sym = 2 * line
    osc = 16 * sym
    f0, km = REACH_ANCHOR
    return dict(
        n=n, rate=rate, flen=flen, line=line, sym=sym, osc=osc,
        div=osc // rate, abits=int(np.log2(flen)) if flen & (flen - 1) == 0 else None,
        cell_us=1e6 / line, half_ns=1e9 / sym, mono_ns=0.75e9 / line,
        fund=line / 2, reach=km * np.sqrt(f0 / (line / 2)),
        binary=(osc // rate) & ((osc // rate) - 1) == 0,
    )


def frame_str(n):
    return ''.join(f'[A{i+1}][C{i+1}]' for i in range(n)) + '[S][T]'


def main():
    print('=' * 100)
    print('FRAMINGS')
    print('=' * 100)
    for n in NS:
        c = cfg(n, 32000)
        print(f'  N={n}  {c["flen"]:2d} bits, {c["abits"]}-bit frame counter, '
              f'{c["flen"]-1:2d} wrong alignments')
        print(f'        {frame_str(n)}')
    print()
    print('  Payload at counts 0..flen-3, framing at the last two.  S=0, T=1.')
    print('  Signalling and voice alternate, so no two adjacent interior bits')
    print('  are static and every wrong alignment is gated by a CVSD bit.')
    print('  2+2N is a power of two only at N = 1, 3, 7 (then 15), and only')
    print('  then is the whole crystal-to-frame chain a set of binary taps.')

    print()
    print('=' * 100)
    print('LINE RATES')
    print('=' * 100)
    h = (f'{"N":>2s} {"frame":>6s} {"CVSD":>7s} {"frame clk":>10s} {"line rate":>11s} '
         f'{"symbol":>11s} {"oscillator":>11s} {"osc/frame":>11s} {"fund":>8s} {"reach":>7s}')
    print(h)
    print('-' * len(h))
    for n in NS:
        for r in RATES:
            c = cfg(n, r)
            d = c['div']
            dstr = f'{d} = 2^{int(np.log2(d))}' if c['binary'] else f'{d} NOT 2^k'
            print(f'{n:2d} {c["flen"]:6d} {r/1000:6.0f}k {r/1000:9.0f}k '
                  f'{c["line"]/1000:10.0f}k {c["sym"]/1e6:10.3f}M '
                  f'{c["osc"]/1e6:10.3f}M {dstr:>11s} '
                  f'{c["fund"]/1000:7.0f}k {c["reach"]:6.2f}k')
        print()

    print('=' * 100)
    print('RECEIVER TIMING')
    print('=' * 100)
    print(f'{"N":>2s} {"CVSD":>7s} {"cell":>9s} {"half-cell":>11s} {"monostable (0.75 cell)":>24s} '
          f'{"+-13% window":>14s}')
    print('-' * 72)
    for n in NS:
        for r in RATES:
            c = cfg(n, r)
            print(f'{n:2d} {r/1000:6.0f}k {c["cell_us"]:8.2f}u {c["half_ns"]:10.0f}n '
                  f'{c["mono_ns"]:23.0f}n {0.13*c["mono_ns"]:13.0f}n')
        print()

    print('=' * 100)
    print('EQUAL-LINE-RATE GROUPS  -- the trade that actually matters')
    print('=' * 100)
    groups = {}
    for n in NS:
        for r in RATES:
            groups.setdefault(cfg(n, r)['line'], []).append((n, r))
    for line in sorted(groups):
        g = groups[line]
        if len(g) < 2:
            continue
        c0 = cfg(*g[0])
        print(f'  {line/1000:.0f} kbps line ({c0["sym"]/1e6:.3f} Mbaud, '
              f'osc {c0["osc"]/1e6:.3f} MHz, reach {c0["reach"]:.2f} km):')
        for n, r in g:
            print(f'      N={n} at {r/1000:.0f} kbps  ->  {n} channels, '
                  f'{2+2*n:2d}-bit frame')
        print()
    print('  Same pair, same driver, same receiver, same reach.  The only')
    print('  differences are the frame width and the codec RC values, so these')
    print('  are strap options on one design rather than different designs.')


if __name__ == '__main__':
    main()
