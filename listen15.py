"""15 s listening comparison: biphase (10.24 MHz) vs AMI (5.12 MHz), 4ch/10-bit frame."""
import numpy as np, gc
from scipy import signal
import audio, cvsd, link, run, fast

RATE, LINE, NCH, SECS = 32000, 320_000, 4, 15.0
LOF = dict(lof_mode='updown', lof=12, lof_up=2, lof_down=1, emit_always=True)
p = run.params(RATE)

src = []
for f, off in (('speech30.wav', 0.0), ('spk_300.wav', 0.0), ('spk_600.wav', 0.0), ('spk_900.wav', 0.0)):
    a, fs = audio.read_wav(f, seconds=SECS, offset=off)
    a = audio.bandlimit(a, fs)
    src.append(audio.resample_to(a * (run.NOMINAL_RMS / a.std()), fs, RATE))
L = min(map(len, src)); src = [s[:L] for s in src]
ch = np.array([cvsd.encode(s, p) for s in src])
line = link.build(ch, np.zeros((NCH, L), np.uint8))
print(f'{SECS:.0f}s, {L} samples/ch, {len(line)} line bits')


def lp(x, fc, FS, order):
    b, a = signal.butter(order, min(0.99, 2.0 * fc / FS), btype='low')
    return signal.lfilter(b, a, x)


def run_code(code, sigma, fc=900_000, seed=0):
    OS = 32 if code == 'biphase' else 16
    FS = LINE * OS
    rng = np.random.default_rng(seed)
    if code == 'biphase':
        x = np.repeat(fast.dm_encode(line).astype(np.float64) * 2 - 1, OS // 2)
    else:
        x = np.repeat(fast.ami_encode(line), OS)
    x = lp(x, fc, FS, 1); x /= np.abs(x).max()
    x += rng.normal(0, sigma, len(x))
    x = lp(x, 640_000 if code == 'biphase' else 320_000, FS, 2)
    rb = (fast.dpll_decode(fast.slice_hyst(x, 0.05), OS)[0] if code == 'biphase'
          else fast.ami_decode(x, OS, 0.5))
    del x; gc.collect()
    c, s, st = link.framer(rb, NCH, **LOF)
    if st['frames'] < 500:
        return None, None, st
    pos = st['pos']; m = min(len(pos), len(ch[0]))
    fi = np.clip(pos[:m] // 10, 0, len(ch[0]) - 1)
    ber = float((c[0][:m] != ch[0][fi]).mean())
    return c, ber, st


def render(c, tag):
    y = audio.reconstruct(cvsd.decode(c[0], p), RATE)
    n = min(len(y), len(src[0]))
    a, b, _ = audio.align(src[0][:n], y[:n])
    b = audio.gain_match(a, b)
    audio.write_wav(f'out/L15_{tag}.wav', audio.resample_to(b, RATE, 16000), 16000)
    return audio.seg_snr_db(a, b, RATE)


audio.write_wav('out/L15_reference.wav', audio.resample_to(src[0], RATE, 16000), 16000)
print(f'\n{"code":8s} {"sd":>5s} {"BER seed0":>10s} {"BER seed1":>10s} {"LOF":>5s} {"segSNR":>8s}  rendered')
for code, sigmas in (('biphase', (0.50, 0.60, 0.62, 0.64, 0.66, 0.70)),
                     ('ami',     (0.50, 0.55, 0.60, 0.65, 0.70))):
    for sg in sigmas:
        c0, b0, st0 = run_code(code, sg, seed=0)
        _, b1, st1 = run_code(code, sg, seed=1)
        if c0 is None:
            print(f'{code:8s} {sg:5.2f} {"NO LOCK":>10s}')
            continue
        seg = render(c0, f'{code}_{sg:.2f}')
        print(f'{code:8s} {sg:5.2f} {b0:10.2e} {("--" if b1 is None else f"{b1:.2e}"):>10s} '
              f'{st0["lof_events"]:5d} {seg:8.2f}  L15_{code}_{sg:.2f}.wav')
        gc.collect()
