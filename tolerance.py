"""
Encoder/decoder component-mismatch tolerance for semi-analog CVSD.

A codec chip puts encoder and decoder on one die with matched components.
Building CVSD discretely puts the transmitting card's integrator on one board
and the receiving card's on another, so the mismatch between two independently
built cards is a real error source.  This sweep turns that into a number: the
component tolerance that the channel card BOM has to hold.

Three networks are swept independently, because each is set by different parts:

    tau_int   integrator leak        R and C around the integrator op-amp
    tau_syl   syllabic filter        R and C of the syllabic network
    step      step size / slew       OTA Iabc scaling and the integrator cap

A step-size mismatch shows up mostly as a GAIN error, which for voice is just a
level shift, so gain and distortion are reported separately.
"""
import numpy as np
from dataclasses import replace
import audio, cvsd, mf8

RATE = 32000
SECS = 8.0
SOURCES = ('speech30.wav', 'spk_600.wav')


def load(path):
    x, fs = audio.read_wav(path, seconds=SECS)
    x = audio.bandlimit(x, fs)
    return audio.resample_to(x * (mf8.NOMINAL_RMS / x.std()), fs, RATE)


def trial(x, enc_p, dec_p):
    """Encode with one card's parameters, decode with another's."""
    bits = cvsd.encode(x, enc_p)
    y = audio.reconstruct(cvsd.decode(bits, dec_p), RATE)
    r, t, _ = audio.align(x, y)
    g = float(np.dot(r, t) / max(np.dot(t, t), 1e-20))
    return audio.seg_snr_db(r, t * g, RATE), g


def sweep(x, base, field, errs):
    """Perturb one decoder parameter; return (err, segSNR, gain) rows."""
    rows = []
    for e in errs:
        if field == 'step':
            dec_p = cvsd.CVSDParams(rate=base.rate, slew=base.slew * (1 + e),
                                    run_length=base.run_length, tau_syl=base.tau_syl,
                                    tau_int=base.tau_int, companding_db=base.companding_db)
        else:
            dec_p = replace(base, **{field: getattr(base, field) * (1 + e)})
        s, g = trial(x, base, dec_p)
        rows.append((e, s, g))
    return rows


def tolerance_at(rows, ref, drop=1.0):
    """Largest |error| whose segSNR stays within `drop` dB of matched."""
    ok = [abs(e) for e, s, _ in rows if s >= ref - drop]
    return max(ok) if ok else 0.0


if __name__ == '__main__':
    base = mf8.params(RATE)
    errs = (-0.30, -0.20, -0.15, -0.10, -0.05, -0.02, 0.0,
            0.02, 0.05, 0.10, 0.15, 0.20, 0.30)
    print('Semi-analog CVSD: encoder on one card, decoder on another.')
    print(f'base: tau_syl={base.tau_syl*1e3:.0f}ms tau_int={base.tau_int*1e3:.0f}ms '
          f'slew={base.slew:.0f} run={base.run_length} comp={base.companding_db:.0f}dB\n')

    limits = {}
    for path in SOURCES:
        x = load(path)
        ref, _ = trial(x, base, base)
        print(f'=== {path}  (matched pair: {ref:.2f} dB) ===')
        for field, label in (('tau_int', 'integrator leak'),
                             ('tau_syl', 'syllabic filter'),
                             ('step', 'step size / slew')):
            rows = sweep(x, base, field, errs)
            tol = tolerance_at(rows, ref)
            limits.setdefault(field, []).append(tol)
            print(f'  {label:18s} ' + ' '.join(
                f'{e:+.0%}:{s:5.1f}' for e, s, _ in rows if e in (-0.30, -0.15, -0.05, 0.05, 0.15, 0.30)))
            print(f'  {"":18s} gain error at +-15%: '
                  + ' '.join(f'{g:.3f}' for e, s, g in rows if abs(abs(e) - 0.15) < 1e-9)
                  + f'   |  within 1 dB out to +-{tol:.0%}')
        print()

    print('=== BOM implication (worst case across sources, 1 dB criterion) ===')
    for field, label in (('tau_int', 'integrator R*C'),
                         ('tau_syl', 'syllabic R*C'),
                         ('step', 'step size')):
        t = min(limits[field])
        print(f'  {label:18s} card-to-card mismatch must stay within +-{t:.0%}')
