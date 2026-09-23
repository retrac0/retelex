#!/usr/bin/env python3
"""
Talker segSNR through the type-A ngspice enc→dec loopback.

Loads sim/talker*.wav (same prep as tolerance.py / cvsd_law.py), drives
spice/cvsd-dec loopback, scores decoder Y with audio.seg_snr_db against
the source and against a pure-Python CVSD path.

    python3 talker_snr.py                  # talkers 1–7, 1 s each, parallel
    python3 talker_snr.py --seconds 2 -j 4
    python3 talker_snr.py --talkers 1,4,6 --seconds 0.5
    python3 talker_snr.py --dec-only       # Python encode, spice decode only

Wall time defaults to a fast deck (100 ns clock edges, one print step per
bit, trap / reltol 5e-3).  Pass --accurate for the old 1 ns / gear deck.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
SIM = ROOT / 'sim'
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(SIM))

import audio  # noqa: E402
import cvsd   # noqa: E402
import mf8    # noqa: E402

RATE = 64000
TBIT = 1.0 / RATE
SKIP = int(0.010 * RATE)
OUT = HERE / 'out' / 'talkers'

# Fast defaults: soft clock edges + one print step per bit.  The 1 ns edges in
# the accuracy decks force ~0.1 ns internal steps on every clock and dominate
# wall time; for segSNR we only sample Y at bit midpoints.
CLK_RISE = 1e-6            # 1 µs edges (bit = 15.625 µs); was 1 ns
TSTEP = TBIT               # print / preferred step = 15.625 µs
RELTOL = 1e-2
METHOD = 'trap'


def load_talker(n: int, seconds: float) -> np.ndarray:
    """Band-limit, resample, level-normalise; start at first active speech."""
    # Read enough to find onset + the requested clip (talkers open with silence).
    x, fs = audio.read_wav(f'talker{n}.wav', seconds=max(8.0, seconds + 2.0))
    x = audio.bandlimit(x, fs)
    x = audio.resample_to(x, fs, RATE)
    w = int(0.020 * RATE)
    nfr = (len(x) // w) * w
    frames = x[:nfr].reshape(-1, w)
    thr = (0.02) ** 2  # ~−34 dBFS on ±1 wav
    active = (frames ** 2).mean(1) > thr
    if not active.any():
        start = 0
    else:
        start = int(np.argmax(active)) * w
    need = int(seconds * RATE)
    # Keep a little pre-roll so syllabic filter has something to settle on.
    start = max(0, start - int(0.050 * RATE))
    if start + need > len(x):
        start = max(0, len(x) - need)
    x = x[start:start + need]
    return x * (mf8.NOMINAL_RMS / max(x.std(), 1e-9))


def write_audio_pwl(path: Path, x: np.ndarray, decim: int = 4):
    """PWL stim; decimate (speech is already ≤3.4 kHz)."""
    idx = np.arange(0, len(x), max(decim, 1))
    if idx[-1] != len(x) - 1:
        idx = np.append(idx, len(x) - 1)
    t = idx * TBIT
    v = x[idx]
    with path.open('w') as f:
        f.write(f'* auto-generated audio PWL ({len(t)} points, decim={decim})\n')
        f.write('Vaud audio 0 PWL(\n')
        for ti, vi in zip(t, v):
            f.write(f'+ {ti:.10g} {vi:.8g}\n')
        f.write('+ )\n')


def write_bit_pwl(path: Path, bits: np.ndarray):
    """PWL with one point per level change (not two holds per bit)."""
    with path.open('w') as f:
        f.write(f'* auto-generated bit PWL ({len(bits)} bits)\n')
        f.write('Vbit bit 0 PWL(\n')
        prev = None
        for i, b in enumerate(bits):
            v = 5.0 if b else 0.0
            if prev is None or v != prev:
                f.write(f'+ {i * TBIT:.10g} {v:.1f}\n')
                prev = v
        f.write(f'+ {len(bits) * TBIT:.10g} {prev:.1f}\n')
        f.write('+ )\n')


def load_wrdata(path: Path, nsig: int):
    """wrdata with leading `time` vector: (t,t), (t,sig0), (t,sig1), ...

    Matches check.py: time in col 0, signals in cols 3, 5, 7, ...
    """
    d = np.loadtxt(path)
    t = d[:, 0]
    cols = [d[:, 3 + 2 * i] for i in range(nsig)]
    return t, cols


def write_cir(path: Path, stim_rel: str, seconds: float, mode: str, wave_rel: str,
              accurate: bool = False):
    """Circuit deck; paths are relative to HERE (cvsd-dec)."""
    if accurate:
        tr, tf = 1e-9, 1e-9
        tstep, reltol, method = 5e-6, 1e-3, 'gear'
    else:
        tr = tf = CLK_RISE
        tstep, reltol, method = TSTEP, RELTOL, METHOD
    pw = TBIT / 2 - tr  # keep ~50% duty with soft edges
    if pw < TBIT / 4:
        pw = TBIT / 2

    clk = f'Vclk clk 0 PULSE(0 5 {TBIT/2:.10g} {tr:.10g} {tf:.10g} {pw:.10g} {TBIT:.10g})'

    if mode == 'loop':
        body = f"""
.include models.inc
.include ../cvsd-enc/enc_a.sub
.include dec_a.sub
.include {stim_rel}

Vdd vdd 0 DC 5
Vcc vcc 0 DC 12
Vee vee 0 DC -12
{clk}

Xenc audio clk bit nbit y_enc syl_e vdd vcc vee cvsd_enc_a
Xdec bit   clk y_dec syl_d vdd vcc vee cvsd_dec_a
"""
        # Only Y — source is known; cuts wrdata size in half.
        wr = f'wrdata {wave_rel} time y_dec'
        nsig = 1
    else:
        body = f"""
.include models.inc
.include dec_a.sub
.include {stim_rel}

Vdd vdd 0 DC 5
Vcc vcc 0 DC 12
Vee vee 0 DC -12
{clk}

Xdec bit clk y_dec syl_d vdd vcc vee cvsd_dec_a
"""
        wr = f'wrdata {wave_rel} time y_dec'
        nsig = 1

    # tmax caps internal step away from breakpoints (4th tran arg).
    tmax = tstep
    path.write_text(f"""* talker SNR — mode={mode}, T={seconds}s, accurate={accurate}
{body}
.option method={method} reltol={reltol} abstol=1n vntol=1m chgtol=1e-14 rshunt=1e12
.control
  save y_dec
  tran {tstep} {seconds} 0 {tmax}
  set filetype=ascii
  {wr}
  quit
.endc
.end
""")
    return nsig


def sample_at_bits(t, y, nbits: int):
    mid = 7.8125e-6 + (np.arange(nbits) + 0.5) * TBIT
    mid = mid[mid <= t[-1]]
    return np.interp(mid, t, y)


def score_pair(ref: np.ndarray, test: np.ndarray):
    r = audio.reconstruct(ref, RATE)
    s = audio.reconstruct(test, RATE)
    r, s, lag = audio.align(r, s)
    s = audio.gain_match(r, s)
    return audio.seg_snr_db(r, s, RATE), audio.snr_db(r, s), lag


def run_one(talker: int, seconds: float, mode: str, outdir: str,
            accurate: bool = False) -> dict:
    """Worker entry — all args must be picklable."""
    outdir = Path(outdir)
    work = outdir / f't{talker}_{mode}'
    work.mkdir(parents=True, exist_ok=True)
    # Drop stale wrdata from a previous (slower) config.
    for stale in work.glob('wave*'):
        stale.unlink()

    x = load_talker(talker, seconds)
    p = mf8.params(RATE)
    nbits = len(x)

    py_bits = cvsd.encode(x, p)
    py_y = cvsd.decode(py_bits, p)
    py_seg, py_snr, _ = score_pair(x, py_y)

    stim = work / 'stim.inc'
    cir = work / 'run.cir'
    wave = work / 'wave'
    log = work / 'run.log'

    if mode == 'loop':
        write_audio_pwl(stim, x, decim=1 if accurate else 4)
    else:
        write_bit_pwl(stim, py_bits)

    # Paths relative to HERE for .include / wrdata
    stim_rel = os.path.relpath(stim, HERE)
    wave_rel = os.path.relpath(wave, HERE)
    cir_rel = os.path.relpath(cir, HERE)
    nvec = write_cir(cir, stim_rel, seconds, mode, wave_rel, accurate=accurate)

    t0 = time.time()
    r = subprocess.run(
        ['ngspice', '-b', cir_rel],
        cwd=HERE,
        capture_output=True, text=True,
    )
    wall = time.time() - t0
    log.write_text(r.stdout + '\n' + r.stderr)

    # ngspice may write wave or wave.data
    wpath = wave if wave.exists() else Path(str(wave) + '.data')
    if not wpath.exists():
        cands = list(work.glob('wave*'))
        wpath = cands[0] if cands else None

    if r.returncode != 0 or wpath is None:
        err = (r.stderr or r.stdout or 'no wrdata')[-600:]
        return {
            'talker': talker, 'ok': False, 'wall': wall, 'err': err,
            'py_seg': py_seg, 'py_snr': py_snr,
        }

    tt, cols = load_wrdata(wpath, nvec)
    y_dec = cols[-1]
    ys = sample_at_bits(tt, y_dec, nbits)
    n = min(len(x), len(ys))
    if n <= SKIP + int(0.040 * RATE):
        return {
            'talker': talker, 'ok': False, 'wall': wall,
            'err': f'too short: {n} samples',
            'py_seg': py_seg, 'py_snr': py_snr,
        }

    seg, snr, lag = score_pair(x[SKIP:n], ys[SKIP:n])
    seg_py, snr_py, lag_py = score_pair(py_y[SKIP:n], ys[SKIP:n])

    return {
        'talker': talker, 'ok': True, 'wall': wall,
        'spice_seg': seg, 'spice_snr': snr, 'lag': lag,
        'vs_py_seg': seg_py, 'vs_py_snr': snr_py, 'vs_py_lag': lag_py,
        'py_seg': py_seg, 'py_snr': py_snr,
        'y_std': float(ys[SKIP:n].std()), 'x_std': float(x[SKIP:n].std()),
    }


def main():
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument('--talkers', default='1,2,3,4,5,6,7')
    ap.add_argument('--seconds', type=float, default=1.0)
    ap.add_argument('-j', type=int, default=0,
                    help='parallel jobs (default: one per talker)')
    ap.add_argument('--dec-only', action='store_true',
                    help='Python encode, spice decode only')
    ap.add_argument('--accurate', action='store_true',
                    help='1 ns clock / gear / reltol 1e-3 (much slower)')
    ap.add_argument('--outdir', type=Path, default=OUT)
    args = ap.parse_args()

    talkers = [int(x) for x in args.talkers.split(',') if x.strip()]
    mode = 'dec' if args.dec_only else 'loop'
    jobs = args.j or min(3, len(talkers))
    args.outdir.mkdir(parents=True, exist_ok=True)
    outdir = str(args.outdir.resolve())

    print(f'Talker SNR through ngspice ({mode}), {args.seconds}s × {talkers}, '
          f'-j {jobs}, accurate={args.accurate}\n', flush=True)

    def report(row):
        if row['ok']:
            print(
                f"  talker{row['talker']}: spice segSNR {row['spice_seg']:5.2f} dB  "
                f"(python {row['py_seg']:5.2f})  vs-py-dec {row['vs_py_seg']:5.2f}  "
                f"[{row['wall']:.0f}s]",
                flush=True,
            )
        else:
            print(
                f"  talker{row['talker']}: FAIL "
                f"({(row.get('err') or '')[:100].replace(chr(10), ' ')}) "
                f"[{row['wall']:.0f}s]",
                flush=True,
            )

    results = []
    t0 = time.time()
    if jobs <= 1 or len(talkers) == 1:
        for n in talkers:
            row = run_one(n, args.seconds, mode, outdir, args.accurate)
            results.append(row)
            report(row)
    else:
        # Threads: ngspice is the work; avoids sandbox ProcessPool semaphore issues.
        with ThreadPoolExecutor(max_workers=jobs) as ex:
            futs = {
                ex.submit(run_one, n, args.seconds, mode, outdir, args.accurate): n
                for n in talkers
            }
            for fut in as_completed(futs):
                row = fut.result()
                results.append(row)
                report(row)

    results.sort(key=lambda r: r['talker'])
    print(
        f'\n{"talker":>8} {"spice seg":>10} {"spice SNR":>10} '
        f'{"python seg":>11} {"vs py Y":>10} {"wall s":>8}',
        flush=True,
    )
    ok = [r for r in results if r['ok']]
    for r in results:
        if not r['ok']:
            print(f"{r['talker']:>8} {'FAIL':>10}", flush=True)
            continue
        print(
            f"{r['talker']:>8} {r['spice_seg']:10.2f} {r['spice_snr']:10.2f} "
            f"{r['py_seg']:11.2f} {r['vs_py_seg']:10.2f} {r['wall']:8.1f}",
            flush=True,
        )
    if ok:
        print(
            f"\n  mean spice segSNR  {np.mean([r['spice_seg'] for r in ok]):.2f} dB\n"
            f"  mean python segSNR {np.mean([r['py_seg'] for r in ok]):.2f} dB\n"
            f"  mean |spice−python| "
            f"{np.mean([abs(r['spice_seg'] - r['py_seg']) for r in ok]):.2f} dB",
            flush=True,
        )
    print(
        f'\n  total wall {time.time() - t0:.0f}s  '
        f'(mode={mode}, {args.seconds}s clips)',
        flush=True,
    )

    summary = args.outdir / 'summary.txt'
    with summary.open('w') as f:
        for r in results:
            f.write(repr(r) + '\n')
    return 0 if ok and len(ok) == len(results) else 1


if __name__ == '__main__':
    sys.exit(main())
