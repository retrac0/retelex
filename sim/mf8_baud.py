"""
PHY + rate-plug timers at the candidate MF8 bauds.

Compares the live 8-bit / six-channel line (512 kbps / 1.024 MBaud) against
the not-taken 10-bit lean (640 kbps / 1.280 MBaud) and 16-bit eight-channel
line (1024 kbps / 2.048 MBaud).  Arithmetic for the plug (§9.7 style), then a
differential-Manchester eye through the same oversampled chain linecodes.py
uses, at each rate's filter corner and half-cell.

Not a span-kilometre claim: CABLE is a fixed 1.8 MHz first-order, as in
linecodes.py.  The point is relative timer window and BER under the same
plant model when the symbol rate changes.

Usage:  python3 sim/mf8_baud.py            (mf8_baud.log)
"""
import sys
import numpy as np
from scipy import signal
import fast

OSB = 32
CABLE = 1.8e6
SLEW_NS = 150.0
TIMER_TOL = 0.10          # remaining window after IC pulse-width tol (±10%)
HYST = 0.05
DEAD = 0.20               # dead time in cells (spec 0.2)
THR = 0.75                # classifier threshold in cells

RATES = [
    # name, line kbps, baud, filter MHz
    ('8-bit / 6 C  (live)',         512, 1.024, 1.0),
    ('10-bit / 8 C (not taken)',    640, 1.280, 1.28),
    ('16-bit / 8 C (not taken)',   1024, 2.048, 2.0),
]


def plug_row(line_kbps, baud_m, filt_m):
    half_ns = 1e9 / (baud_m * 1e6)          # half-cell = 1/baud
    cell_ns = 2 * half_ns
    return dict(
        line_kbps=line_kbps,
        baud_m=baud_m,
        filt_m=filt_m,
        half_ns=half_ns,
        cell_ns=cell_ns,
        class_ns=THR * cell_ns,
        dead_ns=DEAD * cell_ns,
        cd_ns=2.0 * cell_ns,
        slew_pct=100.0 * SLEW_NS / half_ns,
        window_ns=TIMER_TOL * (THR * cell_ns),
    )


def _lp(x, fc, fs, order=2):
    b, a = signal.butter(order, min(0.99, 2 * fc / fs), btype='low')
    return signal.lfilter(b, a, x)


def raw_ber(rb, ln, span=60):
    best = 1.0
    for o in range(span):
        n = min(len(rb) - o, len(ln))
        if n < 1000:
            break
        best = min(best, float((rb[o:o + n] != ln[:n]).mean()))
        if best == 0.0:
            break
    return best


def rx_dm(ln, line_bps, filt_hz, sd=0.0, atten=1.0, seed=1):
    """Oversampled DM at this line rate; FS scales with baud."""
    baud = 2 * line_bps
    fs = baud * OSB
    rng = np.random.default_rng(seed)
    x = np.repeat(fast.dm_encode(ln).astype(np.float64) * 2 - 1, OSB // 2)
    x = _lp(x, CABLE, fs, order=1)
    x /= max(np.abs(x).max(), 1e-12)
    if atten != 1.0:
        x *= atten
    if sd:
        x += rng.normal(0, sd, len(x))
    x = _lp(x, filt_hz, fs, order=2)
    # hysteretic slice
    y = np.empty(len(x), np.uint8)
    s = 0
    for i, v in enumerate(x):
        if s == 0 and v > HYST:
            s = 1
        elif s == 1 and v < -HYST:
            s = 0
        y[i] = s
    return fast.mono_decode(y, OSB, thr=THR, dead=DEAD)


def plant():
    print('RATE PLUG — arithmetic (mf8-spec.md §9.7 shape)\n')
    print(f'  slew fixed at {SLEW_NS:.0f} ns; classifier {THR} cell; dead {DEAD} cell;')
    print(f'  remaining timing window after ±{100*TIMER_TOL:.0f}% IC tolerance.\n')
    print(f'  {"line":>6s} {"baud":>8s} {"filter":>8s} {"0.75 cell":>10s} '
          f'{"dead":>8s} {"CD":>8s} {"slew %hc":>9s} {"±10% win":>9s}')
    for name, line, baud, filt in RATES:
        r = plug_row(line, baud, filt)
        print(f'  {r["line_kbps"]:6d} {r["baud_m"]:8.3f} {r["filt_m"]:8.2f} '
              f'{r["class_ns"]:10.0f} {r["dead_ns"]:8.0f} {r["cd_ns"]:8.0f} '
              f'{r["slew_pct"]:9.1f} {r["window_ns"]:9.0f}')
        print(f'         {name}')
    print()
    print('  At 2.048 MBaud the 150 ns slew is ~31% of a half-cell; at 1.280 MBaud')
    print('  ~19%; at 1.024 MBaud ~15%.  Remaining ±10% window after the classifier')
    print('  shrinks from ~147 ns (512k) to ~73 ns (1024k).')
    print()

    print('EYE THROUGH THE MODEL — random bits, DM, cable 1.8 MHz, filter at baud\n')
    nf = 8000
    rg = np.random.default_rng(7)
    ln = (rg.random(nf) < 0.5).astype(np.uint8)
    print(f'  {nf} bits × 4 seeds.  raw BER after mono_decode; atten scaled to')
    print('  received peak before the RX filter.\n')
    print(f'  {"line":>6s} {"sd":>6s} {"atten":>6s} {"mean raw BER":>14s}')
    for name, line, baud, filt in RATES:
        filt_hz = filt * 1e6
        for sd, atten in ((0.0, 1.0), (0.10, 1.0), (0.10, 0.25), (0.10, 0.12)):
            bers = []
            for seed in (1, 2, 3, 4):
                rb = rx_dm(ln, line * 1000, filt_hz, sd=sd, atten=atten, seed=seed)
                bers.append(raw_ber(rb, ln))
            print(f'  {line:6d} {sd:6.2f} {atten:6.2f} {np.mean(bers):14.1e}  {name}',
                  flush=True)
        print()
    print('  Relative: under the same 0.10 sd / 0.12 atten cell, the faster line')
    print('  sees a smaller received fundamental against the fixed cable pole.')
    print('  This is not a kilometre; it is why 0.50× vs 0.63× reach in frame-rate.md')
    print('  is the right ordering to settle on a bench.')


if __name__ == '__main__':
    plant()
