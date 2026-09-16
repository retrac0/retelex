"""
Fair comparison: FRAMED AMI vs FRAMELESS BIPHASE.

Both carry the same 30 kbps CVSD payload.
  biphase, frameless : 30 kbps line -> 60 kbaud
  AMI, 16-bit frame  : 32 kbps line -> 32 kbaud   (1 framing bit in 16)
The framing overhead is therefore charged against AMI, as it should be.

Fairness rules:
  - common sample rate 960 kHz, so noise is added at the SAME power spectral
    density to both (this is what makes the bandwidth advantage count)
  - the cable is one physical cable: identical ABSOLUTE filter for both
  - each receiver filters at 1.0x ITS OWN symbol rate
  - equal PEAK amplitude (line drivers are voltage limited, not power limited)
"""
import numpy as np
from scipy import signal
import audio, cvsd, phy, run

FS = 960_000
PAYLOAD = 30_000
FRAME = 16
OS_BI = FS // PAYLOAD            # 32 samples per biphase bit (16 per half-cell)
AMI_RATE = PAYLOAD * FRAME // (FRAME - 1)   # 32000 baud
OS_AMI = FS // AMI_RATE          # 30 samples per AMI symbol
SYM_BI, SYM_AMI = 2 * PAYLOAD, AMI_RATE     # 60 kbaud, 32 kbaud


def cable(x, fc_hz):
    b, a = signal.butter(1, min(0.99, 2.0 * fc_hz / FS), btype='low')
    return signal.lfilter(b, a, x)


def rxfilt(x, fc_hz):
    b, a = signal.butter(2, min(0.99, 2.0 * fc_hz / FS), btype='low')
    return signal.lfilter(b, a, x)


def insert_f(bits, n):
    k = (len(bits) // (n - 1)) * (n - 1)
    b = bits[:k].reshape(-1, n - 1)
    return np.hstack([np.ones((len(b), 1), np.uint8), b]).reshape(-1)


def deframe1(bits, n, confirm=64):
    """Single framing-1 framer; returns payload bits."""
    i, c, locked, out = 0, 0, False, []
    while i + n <= len(bits):
        if bits[i] == 1:
            c += 1
            if c >= confirm:
                locked = True
            if locked:
                out.append(bits[i + 1:i + n])
            i += n
        else:
            c = 0; locked = False; i += 1
    return np.concatenate(out) if out else np.zeros(0, np.uint8)


def wide_ber(ref, test, lo=-64, hi=3000):
    """BER with a wide alignment search -- the framer's acquisition delay can be
    ~confirm*frame bits, far beyond a +/-8 window."""
    best = 1.0
    for o in range(lo, hi):
        if o >= 0:
            a, b = ref[o:], test
        else:
            a, b = ref, test[-o:]
        n = min(len(a), len(b))
        if n < 5000:
            break
        e = float((a[:n] != b[:n]).mean())
        if e < best:
            best = e
        if best == 0.0:
            break
    return best


def run_biphase(src, sigma, fc_hz, seed=0):
    rng = np.random.default_rng(seed)
    hc = phy.dm_encode(src)
    x = np.repeat(hc.astype(float) * 2 - 1, OS_BI // 2)
    x = cable(x, fc_hz)
    x = x / np.abs(x).max()                     # equal PEAK
    x = x + rng.normal(0, sigma, len(x))
    x = rxfilt(x, SYM_BI)
    r, _ = phy.dpll_decode(phy.slice_hyst(x, h=0.05), OS_BI)
    return wide_ber(src, r)


def run_ami(src, sigma, fc_hz, seed=0):
    rng = np.random.default_rng(seed)
    fb = insert_f(src, FRAME)
    lv = phy.ami_encode(fb)
    x = np.repeat(lv, OS_AMI)
    x = cable(x, fc_hz)
    x = x / np.abs(x).max()                     # equal PEAK
    x = x + rng.normal(0, sigma, len(x))
    x = rxfilt(x, SYM_AMI)
    rb = phy.ami_decode(x, OS_AMI, thresh=0.5)
    pay = deframe1(rb, FRAME)
    ref = insert_f(src, FRAME)
    refpay = ref.reshape(-1, FRAME)[:, 1:].reshape(-1)
    if len(pay) < 5000:
        return 0.5
    return wide_ber(refpay, pay)


if __name__ == '__main__':
    p = cvsd.CVSDParams(rate=PAYLOAD, slew=11000.0, **run.BASE)
    x, fs = audio.read_wav('spk_300.wav', seconds=1.5)
    x = audio.bandlimit(x, fs); x = x * (run.NOMINAL_RMS / x.std())
    src = cvsd.encode(audio.resample_to(x, fs, PAYLOAD), p)
    print(f'payload {PAYLOAD} bps | biphase {SYM_BI//1000} kbaud frameless | '
          f'AMI {SYM_AMI//1000} kbaud + 1-in-{FRAME} framing bit')
    print(f'{len(src)} payload bits, {len(src)/PAYLOAD:.2f} s\n')

    for fc in (150_000, 60_000, 40_000):
        print(f'=== cable 3 dB at {fc//1000} kHz  '
              f'({"above both" if fc>SYM_BI else "between the two symbol rates"}) ===')
        print(f'{"noise sd":>9s} {"peak SNR dB":>12s} {"biphase BER":>12s} {"AMI BER":>12s}')
        for sigma in (0.02, 0.05, 0.10, 0.15, 0.20, 0.30, 0.40):
            snr = 20 * np.log10(1.0 / sigma)
            print(f'{sigma:9.2f} {snr:12.1f} {run_biphase(src,sigma,fc):12.2e} '
                  f'{run_ami(src,sigma,fc):12.2e}')
        print()
