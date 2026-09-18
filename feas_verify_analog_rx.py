"""
Adversarial re-checks of the ANALOG, JUMPER-CONFIGURED RECEIVER track (feas_analog_rx.py).
Imports that harness unchanged (same absolute method: 32.768 MHz, 1 MHz cable, one noise floor).

  python3 feas_verify_analog_rx.py win     1024k (and 512k) classifier window at design sd, seeds 1,2,3
  python3 feas_verify_analog_rx.py band    band-B corner sensitivity at 1024k / 512k (parasitic / tolerance shift), seeds 1,2
  python3 feas_verify_analog_rx.py ladder  UNBUFFERED equal-R, equal-C RC-RC ladder vs buffered, 1024k and 64k, seeds 1,2
  python3 feas_verify_analog_rx.py dead    64k dead-time near the limit (977 ns nominal = 0.0625 cell +- tolerance), seeds 1,2
"""
import sys, gc, time
import numpy as np
from scipy import signal
import feas_analog_rx as A


def front_generic(B, cab, b, a, seed):
    class F: pass
    f = F()
    f.sf = A.lfilt(b, a, A.chunks(cab), len(cab))
    nz = A.noise(len(cab), seed)
    f.nf = A.lfilt(b, a, A.chunks(nz), len(nz)); del nz; gc.collect()
    f.w = lambda sd: A.slicer(f.sf, f.nf, sd)
    return f


def lim_of(F, B, dead=0.2, g=1.0):
    ev = lambda sd: A.good(A.score(A.decode(F.w(sd), B, dead=dead), B))
    if not ev(1e-3):
        return 0.0
    lo, hi, _ = A.threshold(ev, g)
    return lo


def ladder_ba(fc):
    # unbuffered R-C-R-C, equal R and C, RC = 1/(2 pi fc): H = 1/(s^2 T^2 + 3 s T + 1)
    T = 1 / (2 * np.pi * fc)
    return signal.bilinear([1.0], [T * T, 3 * T, 1.0], A.FSC)


def do_win():
    TG = [round(0.55 + 0.025 * k, 3) for k in range(18)]
    for lr in (1024000, 512000):
        B = A.build(lr); cab = A.cable_wave(B)
        for seed in (1, 2, 3):
            t = time.time()
            F = A.Front(B, cab, B['sym'], seed)
            lim = lim_of(F, B)
            sd = lim * 0.4 / 0.6
            win, ok = A.window(F, B, sd, TG)
            print(f'  {lr//1000}k own corner seed {seed}: limit sd {lim:.3f}, design sd {sd:.3f}, window {win} '
                  f'[{"".join("o" if x else "." for x in ok)}]  ({time.time()-t:.0f}s)', flush=True)
            del F; gc.collect()
        # 3-position design filter for 512k is 1.448 MHz, dead 195 ns = 0.1 cell
        if lr == 512000:
            for seed in (1, 2):
                F = A.Front(B, cab, 1448.15e3, seed)
                lim = lim_of(F, B, dead=0.1)
                win, ok = A.window(F, B, lim * 0.4 / 0.6, TG, dead=0.1)
                print(f'  512k design filter 1.448 MHz dead 0.1 seed {seed}: limit {lim:.3f}, window {win} '
                      f'[{"".join("o" if x else "." for x in ok)}]', flush=True)
                del F; gc.collect()
        del cab, B; gc.collect()


def do_band():
    for lr, corners in ((1024000, (1448.15e3 * 0.8, 1448.15e3 * 0.9, 1448.15e3, 1722e3, 2048e3)),
                        (512000, (1448.15e3 * 0.8, 1448.15e3, 1722e3))):
        B = A.build(lr); cab = A.cable_wave(B)
        dead = 195.0 / (1e9 / lr)
        for fc in corners:
            lims = []
            for seed in (1, 2):
                F = A.Front(B, cab, fc, seed)
                lims.append(lim_of(F, B, dead=dead, g=0.5 if lr == 1024000 else 0.8))
                del F; gc.collect()
            print(f'  {lr//1000}k corner {fc/1e3:7.1f} kHz ({fc/B["sym"]:.2f}x sym) dead {dead:.2f} cell: '
                  f'limits {lims[0]:.3f}, {lims[1]:.3f}; geo mean {np.sqrt(lims[0]*lims[1]):.3f}', flush=True)
        del cab, B; gc.collect()


def do_ladder():
    for lr, fc, dead in ((1024000, 1448.15e3, 0.2), (64000, 128e3, 0.0625)):
        B = A.build(lr); cab = A.cable_wave(B)
        for seed in (1, 2):
            Fb = A.Front(B, cab, fc, seed); lb = lim_of(Fb, B, dead=dead); del Fb; gc.collect()
            b, a = ladder_ba(fc)
            Fu = front_generic(B, cab, b, a, seed); lu = lim_of(Fu, B, dead=dead); del Fu; gc.collect()
            print(f'  {lr//1000}k corner {fc/1e3:.0f} kHz seed {seed}: buffered {lb:.3f}, UNBUFFERED ladder {lu:.3f} '
                  f'({20*np.log10(max(lu,1e-9)/lb):+.1f} dB)', flush=True)
        del cab, B; gc.collect()


def do_dead():
    B = A.build(64000); cab = A.cable_wave(B)
    for seed in (1, 2):
        F = A.Front(B, cab, 128e3, seed)
        row = []
        for d in (0.02, 0.031, 0.045, 0.0625, 0.09):
            row.append((d, lim_of(F, B, dead=d, g=2.5)))
        print(f'  64k corner 128 kHz seed {seed}: ' + ', '.join(f'dead {d:.4f} ({d*15625:.0f} ns): sd {v:.3f}' for d, v in row), flush=True)
        del F; gc.collect()
    B = A.build(128000); cab = A.cable_wave(B)
    F = A.Front(B, cab, 362.04e3, 2)
    row = [(d, lim_of(F, B, dead=d, g=1.6)) for d in (0.032, 0.0625, 0.125, 0.2)]
    print(f'  128k corner 362 kHz seed 2: ' + ', '.join(f'dead {d:.4f}: sd {v:.3f}' for d, v in row), flush=True)


if __name__ == '__main__':
    t = time.time()
    {'win': do_win, 'band': do_band, 'ladder': do_ladder, 'dead': do_dead}[sys.argv[1]]()
    print(f'[total {time.time()-t:.0f} s]')
