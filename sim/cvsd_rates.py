#!/usr/bin/env python3
"""
The CVSD law at 16 - 128 kbps, rendered for listening.

mf8-spec.md 12.1's codec is MIL-STD-188-113 -- the DNVT's law -- and the only
thing that moves with the channel rate is the clock.  This renders the same law
at seven rates so the ladder can be heard rather than read off a segSNR column:

    16  24  32  48  64  96  128 kbps

Chain per rate: input band filter, level set to mf8.NOMINAL_RMS,
resample to the bit rate, encode, decode, reconstruction filter, resample to
the output rate.  No line, no framing, no bit errors -- this is the codec
alone.  Every output is gain-matched to the reference by one scalar and the
whole set of a source shares one peak scaling, so what you hear between rates
is quantising noise, not level.

THE SLEW.  cvsd_law.py's finding is that slew and input level are one knob:
raising the slew moves every level column toward the loud end.  mf8.SLEW only
defines 16k/32k/64k, so an untuned 24/48/96/128 would be a level error wearing
the costume of a rate comparison.  SLEW below is the per-rate optimum of the
same sweep cvsd_law.py scores with -- mean segSNR over -30..+6 dBm0, talkers
1-3 -- and `--tune` reruns it.

Usage:  python3 sim/cvsd_rates.py                 all sources, telephone band
        python3 sim/cvsd_rates.py --wide          50 Hz - 7 kHz, 16 kHz out
        python3 sim/cvsd_rates.py --only tek      one source
        python3 sim/cvsd_rates.py --tune          rerun the slew sweep
"""
import argparse, os, sys, time
import numpy as np
from multiprocessing import Pool
import audio, cvsd, mf8

RATES = (16000, 24000, 32000, 48000, 64000, 96000, 128000)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'out', 'cvsd_rates')

# Per-rate slew, full-scale units/s: the `--tune` optimum, one table per band.
# Both curves are smooth and monotone in the rate, and every cell but one is an
# interior maximum of TUNE_SLEWS rather than a value the sweep ran out of room
# to improve.
SLEW = {
    # tel: reproduces mf8.SLEW exactly at 64 kbps (16000, mean 22.24 dB against
    # cvsd_law.log's 22.2).  It lands under mf8.SLEW at 16k and 32k -- 5000 v
    # 7000, 8500 v 12000 -- but the mean there is flat to 0.3 dB, and mf8.SLEW
    # only ever swept 64k; these are the first measured values at the others.
    'tel':  {16000: 5000., 24000: 7000., 32000: 8500., 48000: 12000.,
             64000: 16000., 96000: 20000., 128000: 28000.},
    # wide wants roughly half the slew at every rate: opening the band down to
    # 50 Hz puts most of the energy below 300 Hz, so at the same RMS the
    # waveform's slope is gentler and a smaller step tracks it.  16k is the one
    # cell still pinned at the bottom of TUNE_SLEWS: 16 kbps cannot carry a
    # 7 kHz band at all (9.5 dB), and the sweep just keeps asking for less slew.
    'wide': {16000: 3000., 24000: 4000., 32000: 5000., 48000: 7000.,
             64000: 10000., 96000: 12000., 128000: 14000.},
}

BANDS = {
    'tel':  dict(lo=300.0, hi=3400.0, wav_fs=8000),
    'wide': dict(lo=50.0,  hi=7000.0, wav_fs=16000),
}

# name, path, offset into the file
SOURCES = [('tek', '/home/joel/tek.wav', 30.0)] + \
          [(f'talker{j}', f'talker{j}.wav', 0.0) for j in range(1, 8)]

GAP = 0.4          # silence between segments of the ladder file
TUNE_SLEWS = (3000., 4000., 5000., 6000., 7000., 8500., 10000., 12000., 14000.,
              16000., 18000., 20000., 24000., 28000., 34000., 40000., 48000.)
TUNE_LEVELS = (-30, -20, -10, 0, 6)
TUNE_TALKERS = (1, 2, 3)
TUNE_SECS = 6.0


def params(rate, band):
    return cvsd.CVSDParams(rate=rate, slew=SLEW[band][rate], **mf8.BASE)


def prepare(path, fs_out, band, secs, offset):
    """Read, telephone-band filter, set the level.  Returns audio at fs_out."""
    b = BANDS[band]
    x, fs = audio.read_wav(path, channel=0, seconds=secs + 0.5, offset=offset)
    x = audio.bandlimit(x, fs, lo=b['lo'], hi=b['hi'])
    x = x * (mf8.NOMINAL_RMS / max(x.std(), 1e-9))
    return audio.resample_to(x, fs, fs_out)[:int(secs * fs_out)]


def through(x_ref, fs_ref, rate, band):
    """One rate: resample in, codec, reconstruct, resample out, gain-match."""
    b = BANDS[band]
    p = params(rate, band)
    x = audio.resample_to(x_ref, fs_ref, rate)
    y = audio.reconstruct(cvsd.decode(cvsd.encode(x, p), p), rate, hi=b['hi'])
    y = audio.resample_to(y, rate, fs_ref)[:len(x_ref)]
    if len(y) < len(x_ref):
        y = np.pad(y, (0, len(x_ref) - len(y)))
    # One scalar from the aligned overlap, applied to the whole output: CVSD is
    # zero-delay and reconstruct() is zero-phase, so the lag is 0 and this only
    # removes the step-size gain.
    r, t, lag = audio.align(x_ref, y)
    g = np.dot(r, t) / max(np.dot(t, t), 1e-20)
    y = y * g
    return y, audio.seg_snr_db(r, t * g, fs_ref), lag


def render_one(a):
    name, path, offset, band, secs = a
    b = BANDS[band]
    fs = b['wav_fs']
    ref = prepare(path, fs, band, secs, offset)
    outs, rows = {}, []
    for rate in RATES:
        t0 = time.time()
        y, snr, lag = through(ref, fs, rate, band)
        outs[rate] = y
        rows.append((rate, snr, lag, time.time() - t0))
    peak = max(np.abs(ref).max(), max(np.abs(v).max() for v in outs.values()), 1e-9)
    k = 0.89 / peak
    d = os.path.join(OUT, band)
    os.makedirs(d, exist_ok=True)
    audio.write_wav(os.path.join(d, f'{name}_ref.wav'), ref * k, fs)
    for rate in RATES:
        audio.write_wav(os.path.join(d, f'{name}_{rate // 1000}k.wav'), outs[rate] * k, fs)
    gap = np.zeros(int(GAP * fs))
    ladder = np.concatenate([ref * k, gap] +
                            [c for rate in RATES for c in (outs[rate] * k, gap)])
    audio.write_wav(os.path.join(d, f'{name}_ladder.wav'), ladder, fs)
    return name, band, fs, len(ref) / fs, rows


# ------------------------------------------------------------------- tuning

def tune_cell(a):
    rate, slew, lvl, j, band = a
    b = BANDS[band]
    x = prepare(f'talker{j}.wav', rate, band, TUNE_SECS, 0.0) * (10 ** (lvl / 20.0))
    p = cvsd.CVSDParams(rate=rate, slew=slew, **mf8.BASE)
    y = audio.reconstruct(cvsd.decode(cvsd.encode(x, p), p), rate, hi=b['hi'])
    r, t, _ = audio.align(x, y)
    return (rate, slew, lvl), audio.seg_snr_db(r, audio.gain_match(r, t), rate)


def tune(bands, procs):
    for band in bands:
        jobs = [(r, s, l, j, band) for r in RATES for s in TUNE_SLEWS
                for l in TUNE_LEVELS for j in TUNE_TALKERS]
        with Pool(procs) as pool:
            res = pool.map(tune_cell, jobs)
        g = {}
        for key, v in res:
            g.setdefault(key, []).append(v)
        print(f'\nSLEW SWEEP -- {band} band {BANDS[band]["lo"]:.0f}-{BANDS[band]["hi"]:.0f} Hz, '
              f'talkers {TUNE_TALKERS}, {TUNE_SECS:.0f} s, segSNR dB')
        print(f'  {"slew":>7s} ' + ' '.join(f'{l:>6d}' for l in TUNE_LEVELS) + '    mean')
        best = {}
        for r in RATES:
            print(f'  === {r // 1000} kbps')
            means = []
            for s in TUNE_SLEWS:
                col = [float(np.mean(g[(r, s, l)])) for l in TUNE_LEVELS]
                means.append(float(np.mean(col)))
                tag = '  <- mf8.SLEW' if r in mf8.SLEW and s == mf8.SLEW[r] else ''
                print(f'  {s:>7.0f} ' + ' '.join(f'{v:6.1f}' for v in col) +
                      f'  {means[-1]:6.2f}{tag}')
            best[r] = TUNE_SLEWS[int(np.argmax(means))]
            edge = ' (EDGE -- widen TUNE_SLEWS)' if best[r] in (TUNE_SLEWS[0], TUNE_SLEWS[-1]) else ''
            print(f'      best {best[r]:.0f}{edge}')
        print(f"  SLEW['{band}'] = " + '{' + ', '.join(f'{r}: {best[r]:.0f}' for r in RATES) + '}')


# ------------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--secs', type=float, default=15.0)
    ap.add_argument('--wide', action='store_true',
                    help='50 Hz - 7 kHz at 16 kHz out, instead of the telephone band')
    ap.add_argument('--both', action='store_true', help='render both bands')
    ap.add_argument('--only', default=None, help='one source name, e.g. tek or talker3')
    ap.add_argument('--procs', type=int, default=os.cpu_count())
    ap.add_argument('--tune', action='store_true', help='rerun the slew sweep and stop')
    args = ap.parse_args()

    bands = ['tel', 'wide'] if args.both else (['wide'] if args.wide else ['tel'])
    if args.tune:
        tune(bands, args.procs)
        return

    srcs = [s for s in SOURCES if args.only is None or s[0] == args.only]
    if not srcs:
        sys.exit(f'no such source: {args.only}  (have {[s[0] for s in SOURCES]})')
    jobs = [(n, p, o, b, args.secs) for b in bands for (n, p, o) in srcs]
    print(f'CVSD {", ".join(f"{r // 1000}k" for r in RATES)} -- '
          f'{len(srcs)} sources x {len(bands)} band(s), {args.secs:.0f} s each')
    for b in bands:
        print(f'  {b:5s} {BANDS[b]["lo"]:.0f}-{BANDS[b]["hi"]:.0f} Hz, {BANDS[b]["wav_fs"]} Hz out, '
              f'slew ' + ' '.join(f'{SLEW[b][r]:.0f}' for r in RATES))
    t0 = time.time()
    with Pool(min(args.procs, len(jobs))) as pool:
        results = pool.map(render_one, jobs)
    print(f'\nsegSNR dB against the band-limited source (gain-matched, no channel)')
    print(f'  {"source":10s} {"band":5s} ' + ' '.join(f'{r // 1000:>6d}k' for r in RATES))
    for name, band, fs, secs, rows in results:
        print(f'  {name:10s} {band:5s} ' + ' '.join(f'{snr:7.1f}' for _, snr, _, _ in rows))
    lags = {lag for _, _, _, _, rows in results for _, _, lag, _ in rows}
    if lags != {0}:
        print(f'  note: non-zero alignment lags seen: {sorted(lags)}')
    print(f'\nwrote {len(results) * (len(RATES) + 2)} wavs to {OUT}/ in {time.time() - t0:.0f}s')
    print(f'  <src>_ref.wav  <src>_NNk.wav  <src>_ladder.wav (ref then every rate, '
          f'{GAP:.1f} s apart)')


if __name__ == '__main__':
    main()
