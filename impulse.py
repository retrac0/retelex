"""Three receivers vs telco-plant impulse noise.  Writes WAVs for listening."""
import numpy as np, gc
from scipy import signal
import audio, cvsd, link, run, phy, fast

RATE, LINE, NCH, SECS = 32000, 320_000, 4, 8.0
OS = 32; FS = LINE * OS
LOF = dict(lof_mode='updown', lof=12, lof_up=2, lof_down=1, emit_always=True)
p = run.params(RATE)

src = []
for f in ('speech30.wav', 'spk_300.wav', 'spk_600.wav', 'spk_900.wav'):
    a, fs = audio.read_wav(f, seconds=SECS)
    a = audio.bandlimit(a, fs)
    src.append(audio.resample_to(a * (run.NOMINAL_RMS / a.std()), fs, RATE))
L = min(map(len, src)); src = [s[:L] for s in src]
ch = np.array([cvsd.encode(s, p) for s in src])
line = link.build(ch, np.zeros((NCH, L), np.uint8))


def lp(x, fc, o):
    b, a = signal.butter(o, min(0.99, 2.0 * fc / FS), btype='low')
    return signal.lfilter(b, a, x)


def make_wave(sigma, rate_hz, seed=0):
    rng = np.random.default_rng(seed)
    x = np.repeat(fast.dm_encode(line).astype(np.float64) * 2 - 1, OS // 2)
    x = lp(x, 900_000, 1); x /= np.abs(x).max()
    x += rng.normal(0, sigma, len(x))
    if rate_hz:
        x += phy.plant_noise(len(x), FS, rate_hz=rate_hz, tau_s=(10e-6,50e-6), seed=seed + 100)
    w = fast.slice_hyst(lp(x, 640_000, 2), 0.05)
    del x; gc.collect()
    return w


def decode(w, kind):
    if kind == 'digital': return fast.dpll_decode(w, OS)[0]
    if kind == 'analog':  return fast.apll_decode(w, OS, kp=0.35, ki=0.10)
    return fast.mono_decode(w, OS)


def score(rb, tag=None):
    c, s, st = link.framer(rb, NCH, **LOF)
    if st['frames'] < 300:
        return None, None, st
    pos = st['pos']; al = pos % 10 == 0
    fi = pos[al] // 10; m = fi < len(ch[0])
    y = audio.reconstruct(cvsd.decode(c[0], p), RATE)
    if tag:
        audio.write_wav(f'out/I_{tag}.wav', audio.resample_to(y, RATE, 16000), 16000)
    snr, bad = audio.block_snr_db(src[0], y, RATE)
    return snr, bad, st


audio.write_wav('out/I_reference.wav', audio.resample_to(src[0], RATE, 16000), 16000)
print(f'{SECS:.0f}s, background noise sd=0.20 (well inside every receiver\'s clean range)')
print('impulses: damped rings, 20-200us, 1-6x signal peak, Poisson arrivals\n')
print(f'{"imp/s":>6s} {"receiver":>10s} {"blockSNR":>9s} {"blocks hit":>11s} {"LOF":>5s}  file')
for rate_hz in (0, 2, 10, 50):
    w = make_wave(0.20, rate_hz)
    for kind in ('digital', 'analog', 'mono'):
        tag = f'{rate_hz}ips_{kind}'
        snr, bad, st = score(decode(w, kind), tag)
        if snr is None:
            print(f'{rate_hz:6d} {kind:>10s} {"NO LOCK":>9s}')
            continue
        print(f'{rate_hz:6d} {kind:>10s} {snr:9.2f} {bad:10.1f}% {st["lof_events"]:5d}  I_{tag}.wav')
    del w; gc.collect()
    print()
