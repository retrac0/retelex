"""
Is a squelch actually necessary?

The spec claims one is required because both line codes fail as a cliff, so an
unmuted receiver below threshold would emit full-scale hash.  That was an
assertion, not a measurement.  This tests it.

Four cases, all through the real chain (slicer -> monostable -> framer ->
CVSD decode -> reconstruction filter):

  1  dead line      no signal, no noise -- cable pulled
  2  noise only     no signal, AWGN at several levels -- cable pulled, picking up
  3  cable break    good signal for half the clip, then cut -- the realistic case
  4  marginal       signal present but below threshold

What matters is the OUTPUT LEVEL relative to normal speech.  If a dead line
produces something 30 dB down, squelch is a nicety.  If it produces something at
or above nominal, squelch is mandatory.
"""
import numpy as np, gc
from scipy import signal
import audio, cvsd, link, run, fast

RATE, LINE, NCH, OS = 32000, 320_000, 4, 32
FS = LINE * OS
LOF = dict(lof_mode='updown', lof=12, lof_up=2, lof_down=1, emit_always=True)
p = run.params(RATE)
SECS = 6.0


def lp(x, fc, order):
    b, a = signal.butter(order, min(0.99, 2.0 * fc / FS), btype='low')
    return signal.lfilter(b, a, x)


def build_line():
    """Four channels of real speech, for the reference and the cable-break case."""
    src = []
    for f in ('speech30.wav', 'spk_300.wav', 'spk_600.wav', 'spk_900.wav'):
        a, fs = audio.read_wav(f, seconds=SECS)
        a = audio.bandlimit(a, fs)
        src.append(audio.resample_to(a * (run.NOMINAL_RMS / a.std()), fs, RATE))
    L = min(map(len, src))
    src = [s[:L] for s in src]
    ch = np.array([cvsd.encode(s, p) for s in src])
    return src, ch, link.build(ch, np.zeros((NCH, L), np.uint8))


def signal_wave(line, seed=0):
    x = np.repeat(fast.dm_encode(line).astype(np.float64) * 2 - 1, OS // 2)
    x = lp(x, 900_000, 1)
    return x / np.abs(x).max()


def receive(x, tag=None):
    """Slice, decode, deframe, reconstruct channel 1.  Returns (audio, stats)."""
    w = fast.slice_hyst(lp(x, 640_000, 2), 0.05)
    rb = fast.mono_decode(w, OS)
    del w
    gc.collect()
    if len(rb) < 100:
        return None, dict(bits=len(rb), frames=0, locked=False)
    c, s, st = link.framer(rb, NCH, **LOF)
    if st['frames'] < 50:
        return None, dict(bits=len(rb), frames=st['frames'], locked=False)
    y = audio.reconstruct(cvsd.decode(c[0], p), RATE)
    if tag:
        audio.write_wav(f'out/Q_{tag}.wav', audio.resample_to(y, RATE, 16000), 16000)
    return y, dict(bits=len(rb), frames=st['frames'],
                   locked=st['lock_bit'] is not None, lof=st['lof_events'])


def level(y, ref_rms):
    """Output level in dB relative to normal received speech."""
    if y is None or len(y) == 0:
        return float('-inf'), float('-inf')
    return (20 * np.log10(max(y.std(), 1e-12) / ref_rms),
            20 * np.log10(max(np.abs(y).max(), 1e-12) / ref_rms))


if __name__ == '__main__':
    src, ch, line = build_line()
    n_samp = len(line) * OS // 2

    # reference: a good link, for the level everything else is measured against
    ref_y, ref_st = receive(signal_wave(line), 'reference_good')
    ref_rms = ref_y.std()
    print(f'reference: good link, {ref_st["frames"]} frames, '
          f'rms {ref_rms:.4f} (0 dB by definition)\n')

    print(f'{"case":34s} {"bits out":>9s} {"locked":>7s} {"rms dB":>8s} {"peak dB":>8s}')

    # 1. dead line -------------------------------------------------------------
    y, st = receive(np.zeros(n_samp), 'dead_line')
    r, pk = level(y, ref_rms)
    print(f'{"1  dead line (no signal, no noise)":34s} {st["bits"]:9d} '
          f'{str(st["locked"]):>7s} {r:8.1f} {pk:8.1f}')

    # 2. noise only ------------------------------------------------------------
    for sg in (0.05, 0.2, 0.5, 1.0):
        rng = np.random.default_rng(1)
        y, st = receive(rng.normal(0, sg, n_samp), f'noise_{sg:.2f}')
        r, pk = level(y, ref_rms)
        print(f'{f"2  noise only, sd={sg}":34s} {st["bits"]:9d} '
              f'{str(st["locked"]):>7s} {r:8.1f} {pk:8.1f}')

    # 3. cable break mid-clip --------------------------------------------------
    x = signal_wave(line)
    cut = len(x) // 2
    rng = np.random.default_rng(2)
    x[cut:] = rng.normal(0, 0.3, len(x) - cut)
    y, st = receive(x, 'cable_break')
    r, pk = level(y, ref_rms)
    print(f'{"3  cable break at half-way":34s} {st["bits"]:9d} '
          f'{str(st["locked"]):>7s} {r:8.1f} {pk:8.1f}')
    if y is not None:
        h = len(y) // 2
        a1, _ = level(y[:h], ref_rms)
        a2, _ = level(y[h:], ref_rms)
        print(f'{"":34s} before {a1:.1f} dB   after {a2:.1f} dB')
    del x
    gc.collect()

    # 4. marginal: signal present but buried -----------------------------------
    for sg in (0.7, 0.9):
        x = signal_wave(line)
        rng = np.random.default_rng(3)
        x += rng.normal(0, sg, len(x))
        y, st = receive(x, f'marginal_{sg:.1f}')
        r, pk = level(y, ref_rms)
        print(f'{f"4  signal + noise sd={sg}":34s} {st["bits"]:9d} '
              f'{str(st["locked"]):>7s} {r:8.1f} {pk:8.1f}')
        del x
        gc.collect()
