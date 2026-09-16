"""Band-limiting, rate conversion, alignment and objective quality metrics."""
import numpy as np
from scipy import signal
import wave


def read_wav(path, channel=0, seconds=None, offset=0.0):
    w = wave.open(path)
    fs, nch, sw = w.getframerate(), w.getnchannels(), w.getsampwidth()
    assert sw == 2, "16-bit only"
    w.setpos(int(offset * fs))
    n = w.getnframes() - int(offset * fs)
    if seconds:
        n = min(n, int(seconds * fs))
    raw = np.frombuffer(w.readframes(n), dtype='<i2').astype(np.float64) / 32768.0
    if nch > 1:
        raw = raw.reshape(-1, nch)[:, channel]
    return raw, fs


def write_wav(path, x, fs):
    x = np.clip(x, -1.0, 1.0)
    w = wave.open(path, 'wb')
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(int(fs))
    w.writeframes((x * 32767).astype('<i2').tobytes())
    w.close()


def bandlimit(x, fs, lo=300.0, hi=3400.0):
    """Telephone band.  This is the anti-alias / input filter of the channel unit."""
    sos = signal.butter(6, [lo, hi], btype='band', fs=fs, output='sos')
    return signal.sosfiltfilt(sos, x)


def reconstruct(x, fs, hi=3400.0):
    """Output reconstruction filter following the CVSD decoder."""
    sos = signal.butter(8, hi, btype='low', fs=fs, output='sos')
    return signal.sosfiltfilt(sos, x)


def resample_to(x, fs_in, fs_out):
    from math import gcd
    g = gcd(int(fs_in), int(fs_out))
    return signal.resample_poly(x, int(fs_out) // g, int(fs_in) // g)


def align(ref, test, max_lag=4096):
    """Integer-sample alignment by cross-correlation; returns trimmed (ref, test)."""
    n = min(len(ref), len(test))
    ref, test = ref[:n], test[:n]
    seg = min(n, 200000)
    c = signal.correlate(test[:seg] - test[:seg].mean(),
                         ref[:seg] - ref[:seg].mean(), mode='full')
    lags = signal.correlation_lags(seg, seg, mode='full')
    m = np.abs(lags) <= max_lag
    lag = int(lags[m][np.argmax(c[m])])
    if lag > 0:
        test = test[lag:]; ref = ref[:len(test)]
    elif lag < 0:
        ref = ref[-lag:]; test = test[:len(ref)]
    n = min(len(ref), len(test))
    return ref[:n], test[:n], lag


def gain_match(ref, test):
    """Remove overall gain difference (CVSD step scaling is not unity-gain)."""
    g = np.dot(ref, test) / max(np.dot(test, test), 1e-20)
    return test * g


def snr_db(ref, test):
    e = ref - test
    return 10 * np.log10(np.dot(ref, ref) / max(np.dot(e, e), 1e-20))


def seg_snr_db(ref, test, fs, win_ms=20.0, lo=-10.0, hi=35.0, silence_db=-45.0):
    """Segmental SNR: the standard speech metric; ignores silent frames."""
    w = int(fs * win_ms / 1000)
    n = (len(ref) // w) * w
    r = ref[:n].reshape(-1, w)
    t = test[:n].reshape(-1, w)
    pr = (r ** 2).sum(1)
    pe = ((r - t) ** 2).sum(1)
    active = 10 * np.log10(pr / w + 1e-20) > silence_db
    if not active.any():
        return float('nan')
    s = 10 * np.log10(pr[active] / np.maximum(pe[active], 1e-20))
    return float(np.clip(s, lo, hi).mean())


def block_snr_db(ref, test, fs, block_s=0.10, max_lag=4000, silence_db=-45.0):
    """
    Segmental SNR with PER-BLOCK re-alignment.

    A cycle slip shifts the whole remaining stream by a sample or two.  Globally
    aligned SNR then collapses even though nothing audible happened.  Aligning
    each block independently measures what you actually hear.
    """
    w = int(fs * block_s)
    nb = min(len(ref), len(test)) // w
    if nb == 0:
        return float('nan'), 0.0
    vals, bad = [], 0
    for k in range(nb):
        r = ref[k * w:(k + 1) * w]
        lo = max(0, k * w - max_lag); hi = min(len(test), (k + 1) * w + max_lag)
        t = test[lo:hi]
        if len(t) < w or 10 * np.log10((r ** 2).mean() + 1e-20) < silence_db:
            continue
        c = signal.correlate(t - t.mean(), r - r.mean(), mode='valid')
        off = int(np.argmax(c))
        tt = t[off:off + w]
        if len(tt) < w:
            continue
        g = np.dot(r, tt) / max(np.dot(tt, tt), 1e-20)
        tt = tt * g
        s = 10 * np.log10(np.dot(r, r) / max(np.dot(r - tt, r - tt), 1e-20))
        vals.append(np.clip(s, -10, 35))
        if s < 3.0:
            bad += 1
    if not vals:
        return float('nan'), 0.0
    return float(np.mean(vals)), 100.0 * bad / len(vals)
