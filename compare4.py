"""
4 channels x 32 kbps CVSD, 10-bit frame, biphase vs AMI.

  frame   [A1][C1][A2][C2][A3][C3][A4][C4][S][T]   32 kHz -> 320 kbps line
  biphase 640 kbaud     AMI 320 kbaud

Identical line bit stream for both, so framing overhead is identical and this is
purely a line-code comparison.  Common master clock: OS samples per LINE BIT, so
AMI gets OS ticks per symbol and biphase only OS/2 -- that asymmetry is real at a
shared crystal and is kept in.
"""
import numpy as np
from scipy import signal
import audio, cvsd, phy, link, run

OS = 16
LINE = 320_000
FS = LINE * OS
SYM_BI, SYM_AMI = 640_000, 320_000
NCH, FLEN = 4, 10
LOF = dict(lof_mode='updown', lof=12, lof_up=2, lof_down=1)   # the fixed policy


def cable(x, fc):
    b, a = signal.butter(1, min(0.99, 2.0 * fc / FS), btype='low'); return signal.lfilter(b, a, x)


def rxf(x, fc):
    b, a = signal.butter(2, min(0.99, 2.0 * fc / FS), btype='low'); return signal.lfilter(b, a, x)


def wide_ber(ref, test, hi=4000):
    best = 1.0
    for o in range(0, hi):
        n = min(len(ref) - o, len(test))
        if n < 3000: break
        e = float((ref[o:o + n] != test[:n]).mean())
        if e < best: best = e
        if best == 0.0: break
    return best


def biphase_link(line, sigma, fc, seed=0):
    rng = np.random.default_rng(seed)
    x = np.repeat(phy.dm_encode(line).astype(float) * 2 - 1, OS // 2)
    x = cable(x, fc); x = x / np.abs(x).max()
    x = rxf(x + rng.normal(0, sigma, len(x)), SYM_BI)
    return phy.dpll_decode(phy.slice_hyst(x, h=0.05), OS)[0]


def ami_link(line, sigma, fc, seed=0):
    rng = np.random.default_rng(seed)
    x = np.repeat(phy.ami_encode(line), OS)
    x = cable(x, fc); x = x / np.abs(x).max()
    x = rxf(x + rng.normal(0, sigma, len(x)), SYM_AMI)
    return phy.ami_decode(x, OS, thresh=0.5)


if __name__ == '__main__':
    RATE = 32000
    p = run.params(RATE)
    secs = 0.4
    files = ['spk_300.wav', 'spk_600.wav', 'spk_900.wav', 'speech30.wav']
    src = []
    for f in files:
        a, fs = audio.read_wav(f, seconds=secs)
        a = audio.bandlimit(a, fs); a = a * (run.NOMINAL_RMS / a.std())
        src.append(audio.resample_to(a, fs, RATE))
    L = min(map(len, src))
    ch = np.array([cvsd.encode(s[:L], p) for s in src])

    for scen, sg in (('all idle (A=0: worst ones-density for AMI)',
                      np.zeros((NCH, L), np.uint8)),
                     ('2 off-hook (A=1 on ch2, ch4)',
                      np.array([np.zeros(L, np.uint8), np.ones(L, np.uint8),
                                np.zeros(L, np.uint8), np.ones(L, np.uint8)]))):
        line = link.build(ch, sg)
        dens = line.mean()
        z = link.runs_of(line, 0)
        print(f'=== {scen} ===')
        print(f'    line mark density {dens:.3f}, max zero run {z.max()} '
              f'(T bit bounds it at {FLEN-1})')
        for fc in (900_000, 300_000):
            print(f'  cable 3 dB @ {fc//1000} kHz')
            print(f'  {"noise sd":>9s} {"peak SNR":>9s} {"biphase BER":>12s} {"bi LOF":>7s}'
                  f' {"AMI BER":>12s} {"AMI LOF":>8s}')
            for sigma in (0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7):
                out = []
                for fn in (biphase_link, ami_link):
                    rb = fn(line, sigma, fc)
                    c, s, st = link.framer(rb, NCH, **LOF)
                    if st['frames'] < 200:
                        out.append((0.5, -1))
                    else:
                        out.append((wide_ber(ch[0], c[0]), st['lof_events']))
                print(f'  {sigma:9.2f} {20*np.log10(1/sigma):8.1f}dB '
                      f'{out[0][0]:12.2e} {out[0][1]:7d} {out[1][0]:12.2e} {out[1][1]:8d}')
        print()
