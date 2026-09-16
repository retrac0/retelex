"""Render channel 1 audio through both line codes at high error rates, for listening."""
import numpy as np
from scipy import signal
import audio, cvsd, phy, link, run

RATE, LINE, NCH = 32000, 320_000, 4
LOF = dict(lof_mode='updown', lof=12, lof_up=2, lof_down=1, emit_always=True)
SECS = 1.2
p = run.params(RATE)

src = []
for f in ('spk_300.wav', 'spk_600.wav', 'spk_900.wav', 'speech30.wav'):
    a, fs = audio.read_wav(f, seconds=SECS)
    a = audio.bandlimit(a, fs)
    src.append(audio.resample_to(a * (run.NOMINAL_RMS / a.std()), fs, RATE))
L = min(map(len, src)); src = [s[:L] for s in src]
ch = np.array([cvsd.encode(s, p) for s in src])
line = link.build(ch, np.zeros((NCH, L), np.uint8))


def filt(x, fc, FS, order=1):
    b, a = signal.butter(order, min(0.99, 2.0 * fc / FS), btype='low')
    return signal.lfilter(b, a, x)


def run_code(code, sigma, fc, seed=0):
    OS = 32 if code == 'biphase' else 16          # equal ticks per SYMBOL
    FS = LINE * OS
    rng = np.random.default_rng(seed)
    if code == 'biphase':
        x = np.repeat(phy.dm_encode(line).astype(float) * 2 - 1, OS // 2)
    else:
        x = np.repeat(phy.ami_encode(line), OS)
    x = filt(x, fc, FS); x = x / np.abs(x).max()
    x = x + rng.normal(0, sigma, len(x))
    x = filt(x, 640_000 if code == 'biphase' else 320_000, FS, order=2)
    rb = (phy.dpll_decode(phy.slice_hyst(x, h=0.05), OS)[0] if code == 'biphase'
          else phy.ami_decode(x, OS, thresh=0.5))
    c, s, st = link.framer(rb, NCH, **LOF)
    if st['frames'] < 200:
        return None, st
    return c, st


def score_and_save(c, tag):
    dec = cvsd.decode(c[0], p)
    y = audio.reconstruct(dec, RATE)
    n = min(len(y), len(src[0]))
    a, b, _ = audio.align(src[0][:n], y[:n])
    b = audio.gain_match(a, b)
    audio.write_wav(f'out/L_{tag}.wav', audio.resample_to(b, RATE, 16000), 16000)
    return None, audio.seg_snr_db(a, b, RATE)


audio.write_wav('out/L_reference.wav', audio.resample_to(src[0], RATE, 16000), 16000)
cc, _ = run_code('biphase', 0.0, 900_000)
print('clean ->', score_and_save(cc, 'clean'))

for fc, cases in ((900_000, {'biphase': (0.60, 0.65, 0.70, 0.75),
                             'ami':     (0.50, 0.55, 0.60, 0.65)}),
                  (300_000, {'biphase': (0.45, 0.50, 0.55),
                             'ami':     (0.50, 0.55, 0.60)})):
    print(f'\n=== cable {fc//1000} kHz ===')
    print(f'{"code":8s} {"sd":>5s} {"BER":>10s} {"LOF":>5s} {"segSNR":>8s}  file')
    for code, sigmas in cases.items():
        for sg in sigmas:
            c, st = run_code(code, sg, fc)
            tag = f'{fc//1000}k_{code}_{sg:.2f}'
            if c is None:
                print(f'{code:8s} {sg:5.2f} {"NO LOCK":>10s} {st["lof_events"]:5d}')
                continue
            _, seg = score_and_save(c, tag)
            pos = st['pos']; m = min(len(pos), len(ch[0]))
            fi = np.clip(pos[:m] // link.frame_len(NCH), 0, len(ch[0]) - 1)
            ber = float((c[0][:m] != ch[0][fi]).mean())      # exact, per-frame mapped
            print(f'{code:8s} {sg:5.2f} {ber:10.2e} {st["lof_events"]:5d} {seg:8.2f}  L_{tag}.wav')
