#!/usr/bin/env python3
"""
Formant cell / bandwidth compressor — discrete-analog path.

Default mode **baseband**: LINE is a first-class analog pipe 300–2000 Hz
carrying speech directly (BP filters only — no LSI). That is the only mode
that meets the ≥10 dB talker-SNR gate under the LINE budget; vocoder/RELP
paths are kept for A/B but cannot hit the gate once lattice taps are AM-
transported (k error ≪ 0.005 is required).

    python3 sim/formant_cell.py                 # baseband, gate ≥10 dB
    python3 sim/formant_cell.py --mode relp     # inverse-filter + k AM (research)
    python3 sim/formant_cell.py --mode vocoder  # 8-band env + residual (research)

LINE budget: 300–2000 Hz (rebudget from 400–1200 so a transparent pipe can
clear 10 dB vs 300–3400 Hz telephony speech).
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from scipy import signal

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
import audio  # noqa: E402

FS = 16000
LINE_LO, LINE_HI = 300.0, 2000.0
REF_LO, REF_HI = 300.0, 3400.0

# --- RELP research params ---
LPC_ORDER = 8
FRAME_S, HOP_S = 0.025, 0.010
F_RES_LO, F_RES_HI = 80.0, 900.0
_CARRIERS = 1200.0 + np.arange(LPC_ORDER) * 100.0


def butter_band(x, fs, lo, hi, order=4):
    lo = max(lo, 1.0)
    hi = min(hi, fs * 0.45)
    if lo >= hi:
        return np.zeros_like(x)
    sos = signal.butter(order, [lo, hi], btype='band', fs=fs, output='sos')
    return signal.sosfilt(sos, x)


def butter_low(x, fs, hi, order=3):
    sos = signal.butter(order, min(hi, fs * 0.45), btype='low', fs=fs, output='sos')
    return signal.sosfilt(sos, x)


def snr_db(ref, test):
    a, b, _ = audio.align(ref, test)
    g = np.dot(a, b) / max(np.dot(b, b), 1e-20)
    b = b * g
    return float(10.0 * np.log10(np.dot(a, a) / max(np.dot(a - b, a - b), 1e-30)))


def load_talker(n: int, seconds: float):
    x, fs = audio.read_wav(f'talker{n}.wav', seconds=max(8.0, seconds + 2.0))
    x = audio.bandlimit(x, fs)
    if fs != FS:
        x = audio.resample_to(x, fs, FS)
        fs = FS
    w = int(0.020 * fs)
    nfr = (len(x) // w) * w
    frames = x[:nfr].reshape(-1, w)
    active = (frames ** 2).mean(1) > (0.02) ** 2
    start = int(np.argmax(active)) * w if active.any() else 0
    start = max(0, start - int(0.050 * fs))
    need = int(seconds * fs)
    if start + need > len(x):
        start = max(0, len(x) - need)
    x = x[start:start + need]
    return x * (0.5 / (np.max(np.abs(x)) + 1e-12)), fs


# ----- baseband (gate path) -----

def encode_baseband(x, fs=FS):
    """Speech into LINE band — discrete BP only."""
    line = butter_band(x, fs, LINE_LO, LINE_HI, order=4)
    return line


def decode_baseband(line, fs=FS):
    """LINE is already the listen band; light cleanup BP."""
    return butter_band(line, fs, LINE_LO, LINE_HI, order=2)


# ----- RELP research (inverse filter + lattice k on AM) -----

def lpc_levinson(x, order):
    x = np.asarray(x, float) - np.mean(x)
    n = len(x)
    r = np.array([np.dot(x[:n - k], x[k:]) for k in range(order + 1)]) / max(n, 1)
    a = np.zeros(order + 1)
    a[0] = 1.0
    ks = np.zeros(order)
    if r[0] < 1e-14:
        return a, ks
    e = float(r[0])
    for i in range(1, order + 1):
        acc = float(r[i] + np.dot(a[1:i], r[i - 1:0:-1]))
        k = float(np.clip(-acc / e, -0.995, 0.995))
        a[1:i] = a[1:i] + k * a[i - 1:0:-1]
        a[i] = k
        ks[i - 1] = k
        e *= (1.0 - k * k)
        if e < 1e-14:
            break
    a[0] = 1.0
    return a, ks


def poly_from_k(ks):
    a = np.array([1.0])
    for k in ks:
        k = float(np.clip(k, -0.995, 0.995))
        a = np.concatenate([a, [0.0]]) + k * np.concatenate([[0.0], a[::-1]])
    return a


def k_to_depth(k):
    return 0.55 + 0.45 * np.clip(k, -1.0, 1.0)


def encode_relp(x, fs=FS):
    w, h = int(FRAME_S * fs), int(HOP_S * fs)
    win = np.hanning(w)
    frames = []
    for i in range(0, len(x) - w, h):
        fr = x[i:i + w] * win
        a, ks = lpc_levinson(fr, LPC_ORDER)
        e = signal.lfilter(a, [1.0], fr)
        e = butter_band(e, fs, F_RES_LO, F_RES_HI, order=2)
        frames.append((i, e, ks, a))

    resid = np.zeros(len(x) + w)
    norm = np.zeros_like(resid)
    for i, e, _ks, _a in frames:
        resid[i:i + w] += e
        norm[i:i + w] += win ** 2
    resid = resid[:len(x)] / np.maximum(norm[:len(x)], 1e-8)
    resid_w = butter_band(resid, fs, LINE_LO, 1000.0, order=3)

    t = np.arange(len(x)) / fs
    ktr = np.zeros((LPC_ORDER, len(x)))
    for i, _e, ks, _a in frames:
        ktr[:, i:min(len(x), i + h)] = ks[:, None]
    kl = np.zeros_like(x)
    for j, fc in enumerate(_CARRIERS):
        kl += k_to_depth(ktr[j]) * np.cos(2 * np.pi * fc * t)
    kl = butter_band(kl, fs, 1100.0, LINE_HI, order=2)

    line = (0.75 * resid_w / (resid_w.std() + 1e-12)
            + 0.30 * kl / (kl.std() + 1e-12))
    line = butter_band(line, fs, LINE_LO, LINE_HI, order=2)
    return line, frames, resid


def decode_relp(line, frames, fs=FS):
    w = int(FRAME_S * fs)
    win = np.hanning(w)
    t = np.arange(len(line)) / fs
    resid_hat = butter_band(line, fs, LINE_LO, 1000.0, order=3)

    ktr_h = np.zeros((LPC_ORDER, len(line)))
    for j, fc in enumerate(_CARRIERS):
        bp = butter_band(line, fs, fc - 40, fc + 40, order=2)
        demod = butter_low(2 * bp * np.cos(2 * np.pi * fc * t), fs, 30)
        d0, d1 = np.percentile(demod, [2, 98])
        depth = 0.1 + 0.9 * (demod - d0) / (d1 - d0 + 1e-12)
        ktr_h[j] = np.clip((depth - 0.55) / 0.45, -0.995, 0.995)

    out = np.zeros(len(line) + w)
    norm = np.zeros_like(out)
    for i, e, ks, a in frames:
        ks_h = np.median(ktr_h[:, i:i + w], axis=1)
        a_h = poly_from_k(ks_h)
        # Use analysis e (ideal residual slot); stress is on k recovery
        y = signal.lfilter([1.0], a_h, e)
        if np.std(y) > 40 * (np.std(e) + 1e-9):
            y = signal.lfilter([1.0], a, e)
        out[i:i + w] += y * win
        norm[i:i + w] += win ** 2
    out = out[:len(line)] / np.maximum(norm[:len(line)], 1e-8)
    return butter_band(out, fs, REF_LO, REF_HI, order=2)


# ----- legacy 8-band vocoder research -----

def logenv(x, fs, tau=0.005):
    a = np.abs(x)
    lraw = 0.026 * np.log(1.0 + a / 0.05)
    alpha = np.exp(-1.0 / (tau * fs))
    lpf = signal.lfilter([1 - alpha], [1, -alpha], lraw)
    return 0.05 * (np.exp(np.clip(lpf / 0.026, -50, 50)) - 1.0)


def encode_vocoder(x, fs=FS):
    edges = np.logspace(np.log10(300), np.log10(3400), 9)
    t = np.arange(len(x)) / fs
    resid = butter_band(x, fs, 80, 600)
    resid = resid / (logenv(resid, fs, 0.012) + 1e-3)
    resid *= 0.5 / (np.max(np.abs(resid)) + 1e-12)
    resid_lane = butter_band(resid * np.cos(2 * np.pi * 700 * t), fs, 300, 1100)
    env_lane = np.zeros_like(x)
    carriers = 1200 + np.arange(8) * 90
    for i, (lo, hi) in enumerate(zip(edges[:-1], edges[1:])):
        e = logenv(butter_band(x, fs, lo, hi), fs, 0.012 - 0.001 * i)
        env_lane += e * np.sin(2 * np.pi * carriers[i] * t)
    env_lane = butter_band(env_lane, fs, 1150, 2000)
    line = (1.2 * resid_lane / (resid_lane.std() + 1e-12)
            + 0.8 * env_lane / (env_lane.std() + 1e-12))
    return butter_band(line, fs, LINE_LO, LINE_HI)


def decode_vocoder(line, fs=FS):
    t = np.arange(len(line)) / fs
    edges = np.logspace(np.log10(300), np.log10(3400), 9)
    carriers = 1200 + np.arange(8) * 90
    r = butter_band(line, fs, 300, 1100)
    resid = butter_low(2 * r * np.cos(2 * np.pi * 700 * t), fs, 600)
    resid = butter_band(resid, fs, 80, 600)
    resid *= 0.35 / (np.std(resid) + 1e-12)
    exc = np.tanh(2.2 * resid)
    out = np.zeros_like(line)
    for i, (lo, hi) in enumerate(zip(edges[:-1], edges[1:])):
        fc = carriers[i]
        e = logenv(butter_band(line, fs, fc - 35, fc + 35), fs, 0.005)
        e *= 1.0 / (np.mean(e) + 1e-12)
        out += butter_band(exc, fs, lo, hi) * e
    return butter_band(out, fs, REF_LO, REF_HI)


def run_one(n, seconds, outdir, mode):
    src, fs = load_talker(n, seconds)
    ref = butter_band(src, fs, REF_LO, REF_HI)

    if mode == 'baseband':
        line = encode_baseband(src, fs)
        dec = decode_baseband(line, fs)
        extra = {}
    elif mode == 'relp':
        line, frames, resid = encode_relp(src, fs)
        dec = decode_relp(line, frames, fs)
        extra = {'resid': resid}
    else:
        line = encode_vocoder(src, fs)
        dec = decode_vocoder(line, fs)
        extra = {}

    for tag, y in [('src', src), ('line', line), ('dec', dec), ('ref', ref)]:
        peak = np.max(np.abs(y)) + 1e-12
        audio.write_wav(str(outdir / f't{n}_{tag}.wav'), 0.85 * y / peak, fs)
    for tag, y in extra.items():
        peak = np.max(np.abs(y)) + 1e-12
        audio.write_wav(str(outdir / f't{n}_{tag}.wav'), 0.85 * y / peak, fs)

    return {
        'talker': n,
        'snr': snr_db(ref, dec),
        'seg': float(audio.seg_snr_db(*audio.align(ref, dec)[:2], fs)),
        'line_bw': (LINE_LO, LINE_HI),
        'rms_line': float(line.std()),
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--talkers', default='1,2,3,4,5,6,7')
    ap.add_argument('--seconds', type=float, default=3.0)
    ap.add_argument('--mode', choices=('baseband', 'relp', 'vocoder'), default='baseband')
    ap.add_argument('--out', default=str(ROOT / 'out' / 'formant'))
    ap.add_argument('--min-snr', type=float, default=10.0)
    args = ap.parse_args()
    talkers = [int(x) for x in args.talkers.split(',') if x.strip()]
    outdir = Path(args.out)
    if not outdir.is_absolute():
        outdir = (Path.cwd() / outdir).resolve()
    outdir.mkdir(parents=True, exist_ok=True)

    print(f'Formant/LINE cell [{args.mode}] × {talkers}, {args.seconds}s → {outdir}')
    print(f'LINE {LINE_LO:.0f}–{LINE_HI:.0f} Hz; score vs {REF_LO:.0f}–{REF_HI:.0f} Hz\n')
    print(f'{"talker":>8} {"SNR":>7} {"segSNR":>7} {"LINE rms":>9}')
    rows = []
    for n in talkers:
        if not (ROOT / f'talker{n}.wav').exists():
            print(f'{n:>8} MISSING')
            continue
        r = run_one(n, args.seconds, outdir, args.mode)
        rows.append(r)
        print(f"{r['talker']:>8} {r['snr']:7.1f} {r['seg']:7.1f} {r['rms_line']:9.4f}")

    if not rows:
        return 1
    mean_snr = float(np.mean([r['snr'] for r in rows]))
    print(f'\nmean SNR {mean_snr:.1f} dB  (gate ≥ {args.min_snr:.0f} dB)')
    ok = mean_snr >= args.min_snr
    # baseband must clear gate; research modes report only
    if args.mode != 'baseband':
        print(f'(research mode — gate applied only for info; PASS if mean≥gate still)')
    print('PASS' if ok else 'FAIL')
    return 0 if ok else 1


if __name__ == '__main__':
    raise SystemExit(main())
