"""
Frameless prototype physical layer: differential Manchester + oversampling DPLL.

Differential Manchester as used here:
    - a transition ALWAYS occurs at the bit-cell boundary  (this is the clock)
    - a transition additionally occurs at mid-cell iff the data bit is 0
The decoded bit depends only on whether the two half-cells are EQUAL, never on
absolute level, so the code is polarity-blind: swapping tip and ring is harmless.

There is no frame.  A CVSD stream has no alignment requirement, so the receiver
needs the bit clock and nothing else.
"""
import numpy as np
from scipy import signal


def dm_encode(bits):
    """bits -> half-cell level sequence, 2 entries per bit."""
    n = len(bits)
    out = np.empty(2 * n, dtype=np.uint8)
    lvl = 0
    for i in range(n):
        lvl ^= 1                       # boundary transition: always
        out[2 * i] = lvl
        if bits[i] == 0:
            lvl ^= 1                   # mid-cell transition iff bit == 0
        out[2 * i + 1] = lvl
    return out


def dm_decode_ideal(halfcells):
    """Known-phase decode, for reference."""
    a = halfcells[0::2].astype(int)
    b = halfcells[1::2].astype(int)
    return (a == b).astype(np.uint8)


def to_waveform(halfcells, os_bit, bw_ratio=2.0, snr_db=None, invert=False,
                ppm=0.0, seed=0, rx_bw=1.5):
    """
    Half-cells -> sampled line waveform.

    os_bit    samples per BIT (so os_bit/2 per half-cell)
    bw_ratio  cable 3 dB bandwidth as a multiple of the symbol (half-cell) rate
    snr_db    additive Gaussian noise power ratio; None = noiseless
    invert    swap tip/ring
    ppm       transmit clock offset relative to the receiver's nominal rate
    """
    rng = np.random.default_rng(seed)
    x = np.repeat(halfcells.astype(float) * 2.0 - 1.0, os_bit // 2)
    if ppm:
        n_new = int(round(len(x) * (1.0 + ppm * 1e-6)))
        if n_new != len(x):
            x = signal.resample_poly(x, n_new, len(x))
    sym_nyq = 2.0 / (os_bit / 2.0)          # symbol rate in units of Nyquist

    # 1. cable: first-order lowpass at bw_ratio x symbol rate
    b, a = signal.butter(1, min(0.99, bw_ratio * sym_nyq), btype='low')
    x = signal.lfilter(b, a, x)

    # 2. receiver front-end noise, referred to this point
    if snr_db is not None:
        sp = np.mean(x ** 2)
        x = x + rng.normal(0, np.sqrt(sp / (10 ** (snr_db / 10.0))), len(x))

    # 3. receiver input filter -- ALWAYS applied, so the noiseless reference
    #    goes through an identical chain and SNR means what it says
    if rx_bw:
        b2, a2 = signal.butter(2, min(0.99, rx_bw * sym_nyq), btype='low')
        x = signal.lfilter(b2, a2, x)

    x = x / np.sqrt(np.mean(x ** 2))        # normalise to unit rms at the slicer
    if invert:
        x = -x
    return x


def slice_hyst(x, h=0.05):
    """Vectorised hysteretic comparator (state only changes outside the dead band)."""
    ev = np.where(x > h, 1, np.where(x < -h, 0, -1))
    idx = np.maximum.accumulate(np.where(ev >= 0, np.arange(len(x)), 0))
    out = ev[idx].copy()
    out[out < 0] = 0
    return out.astype(np.uint8)


def _slice_hyst_slow(x, h=0.05):
    """Comparator with hysteresis -> binary waveform."""
    out = np.empty(len(x), dtype=np.uint8)
    s = 0
    for i in range(len(x)):
        if s == 0 and x[i] > h:
            s = 1
        elif s == 1 and x[i] < -h:
            s = 0
        out[i] = s
    return out


def dpll_decode(wave, os_bit, win=None, resync=True, lock_after=32):
    """
    Oversampling DPLL + differential Manchester decode.

    Locks a modulo-os_bit phase counter to the cell-boundary transitions.  The
    half-bit phase ambiguity (which edges are boundaries) is resolved by the
    fact that every '1' bit produces a FULL-bit gap between transitions, while
    a '0' produces two half-bit gaps: any gap longer than 0.75 bit must end on
    a boundary.
    """
    OS = os_bit
    half, qtr = OS // 2, OS // 4
    if win is None:
        win = OS // 4
    bits = []
    phase = 0
    prev = wave[0]
    last_edge = 0
    s1 = 0
    have_s1 = False
    stats = dict(resyncs=0, nudges=0, lock_sample=None)
    good = 0
    locked = False
    for i in range(1, len(wave)):
        cur = wave[i]
        edge = (cur != prev)
        prev = cur
        if edge:
            gap = i - last_edge
            last_edge = i
            boundary = gap > 0.75 * OS          # a full-bit gap must end on a boundary
            if boundary:
                err = phase if phase < half else phase - OS
                if abs(err) <= win:
                    good += 1
                    if not locked and good >= lock_after:
                        locked = True
                        stats['lock_sample'] = i
                else:
                    good = 0
                    locked = False
                if resync and not locked:
                    stats['resyncs'] += 1
                    phase = 0                   # hard acquire only while unlocked
                    prev_edge_handled = True
                else:
                    if err > 0:
                        phase -= 1
                    elif err < 0:
                        phase += 1
                    stats['nudges'] += 1
            else:
                p = phase
                if p < win:                     # boundary edge arrived late -> slow down
                    phase -= 1
                    stats['nudges'] += 1
                elif p > OS - win:               # arrived early -> speed up
                    phase += 1
                    stats['nudges'] += 1
        phase += 1
        if phase >= OS:
            phase -= OS
        elif phase < 0:
            phase += OS
        if phase == qtr:
            s1 = cur
            have_s1 = True
        elif phase == OS - qtr and have_s1:
            bits.append(1 if s1 == cur else 0)
            have_s1 = False
    return np.array(bits, dtype=np.uint8), stats


def ber(ref, test, max_shift=8):
    """BER after searching for the best alignment (frameless: any offset is legal)."""
    best = (None, 1.0)
    for o in range(max_shift):
        n = min(len(ref) - o, len(test))
        if n < 1000:
            break
        e = float((ref[o:o + n] != test[:n]).mean())
        if e < best[1]:
            best = (o, e)
        for o2 in range(1, max_shift):
            n2 = min(len(ref), len(test) - o2)
            if n2 < 1000:
                break
            e2 = float((ref[:n2] != test[o2:o2 + n2]).mean())
            if e2 < best[1]:
                best = (-o2, e2)
        break
    return best


# ------------------------------------------------------------------- AMI / pseudoternary

def ami_encode(bits):
    """1 -> alternating +/-1 pulse, 0 -> zero level.  One symbol per bit."""
    out = np.zeros(len(bits))
    pol = 1.0
    for i in range(len(bits)):
        if bits[i]:
            out[i] = pol
            pol = -pol
    return out


def ami_waveform(levels, os_bit, bw_ratio=2.0, snr_db=None, ppm=0.0, seed=0, rx_bw=0.75):
    """
    AMI line waveform.  Symbol rate == bit rate, i.e. HALF the biphase symbol
    rate, so both the cable filter and the receive filter are referred to that
    narrower symbol rate -- which is exactly where AMI's noise advantage comes from.
    """
    rng = np.random.default_rng(seed)
    x = np.repeat(levels, os_bit)
    if ppm:
        n_new = int(round(len(x) * (1.0 + ppm * 1e-6)))
        if n_new != len(x):
            x = signal.resample_poly(x, n_new, len(x))
    sym_nyq = 2.0 / os_bit                      # AMI symbol rate in units of Nyquist
    b, a = signal.butter(1, min(0.99, bw_ratio * sym_nyq), btype='low')
    x = signal.lfilter(b, a, x)
    if snr_db is not None:
        sp = np.mean(x ** 2)
        x = x + rng.normal(0, np.sqrt(sp / (10 ** (snr_db / 10.0))), len(x))
    if rx_bw:
        b2, a2 = signal.butter(2, min(0.99, rx_bw * sym_nyq), btype='low')
        x = signal.lfilter(b2, a2, x)
    return x


def ami_decode(x, os_bit, thresh=0.5, peak=None, lock_after=16):
    """
    Rectify -> DPLL on the mark pulses -> dual-threshold slice at mid-bit.
    With no marks there are no transitions at all, so the loop must coast.
    """
    OS = os_bit
    if peak is None:
        peak = np.percentile(np.abs(x), 99)
    t = thresh * peak
    r = np.abs(x)
    above = (r > t).astype(np.uint8)
    bits = []
    phase = 0
    prev = above[0]
    win = OS // 4
    for i in range(1, len(x)):
        cur = above[i]
        if cur and not prev:                    # leading edge of a mark
            p = phase
            if p < win:
                phase -= 1
            elif p > OS - win:
                phase += 1
            elif p < OS // 2:
                phase -= 1
            else:
                phase += 1
        prev = cur
        phase += 1
        if phase >= OS:
            phase -= OS
        elif phase < 0:
            phase += OS
        if phase == OS // 2:
            bits.append(1 if abs(x[i]) > t else 0)
    return np.array(bits, dtype=np.uint8)


# ------------------------------------------------------- telco plant impairments

def pair_24awg(x, fs, length_km=5.0, ref_db=12.0, ref_km=1.7, ref_hz=256e3):
    """Buried 24 AWG PIC pair: √f attenuation (frame-rate.md §3, scaled by length).

    The project's single-span reference is `ref_db` at `ref_hz` over `ref_km`
    (~1.7 km → 12 dB at 256 kbps).  Loss at length L and frequency f:

        loss_dB(f) = ref_db · (L / ref_km) · sqrt(f / ref_hz)

    Applied as a zero-phase FFT filter.  Propagation delay is not modelled
    (framer cares about bits, not absolute delay).
    """
    x = np.asarray(x, dtype=np.float64)
    n = len(x)
    # rfft frequencies in Hz
    f = np.fft.rfftfreq(n, d=1.0 / fs)
    # DC: use the lowest bin's law but floor at f=0 → loss 0 is wrong for loop
    # resistance; keep a small DC loss from the ref_hz curve at f→0 as 0, and
    # let the first AC bins carry the skin-effect roll-off.
    ratio = np.sqrt(np.maximum(f, 1.0) / ref_hz)
    loss_db = ref_db * (length_km / ref_km) * ratio
    loss_db[0] = ref_db * (length_km / ref_km) * 0.05   # tiny DC ohmic stand-in
    H = 10.0 ** (-loss_db / 20.0)
    X = np.fft.rfft(x)
    return np.fft.irfft(X * H, n=n)


def plant_noise(n, fs, rate_hz=10.0, amp=(1.0, 6.0), tau_s=(20e-6, 200e-6),
                ring_hz=(15e3, 80e3), hum_hz=50.0, hum_amp=0.0, seed=0):
    """
    Impulse noise of the kind subscriber loops actually carry: switching
    transients, relay operation, dial pulses bleeding off adjacent pairs,
    induction.  Each event is a damped oscillation -- the pair rings rather than
    stepping -- with Poisson arrivals.

    rate_hz  events per second
    amp      (min,max) amplitude relative to the signal peak (signal peak == 1)
    tau_s    (min,max) decay time constant
    ring_hz  (min,max) ringing frequency
    hum_amp  differential residual of mains induction (the pair rejects most of it)
    """
    rng = np.random.default_rng(seed)
    out = np.zeros(n)
    n_ev = rng.poisson(rate_hz * n / fs)
    for _ in range(n_ev):
        t0 = rng.integers(0, n)
        A = rng.uniform(*amp) * rng.choice([-1.0, 1.0])
        tau = rng.uniform(*tau_s)
        f = rng.uniform(*ring_hz)
        ln = min(int(6 * tau * fs), n - t0)
        if ln < 4:
            continue
        t = np.arange(ln) / fs
        out[t0:t0 + ln] += A * np.exp(-t / tau) * np.sin(2 * np.pi * f * t)
    if hum_amp:
        t = np.arange(n) / fs
        out += hum_amp * (np.sin(2 * np.pi * hum_hz * t)
                          + 0.3 * np.sin(2 * np.pi * 3 * hum_hz * t))
    return out
