#!/usr/bin/env python3
"""tek.wav through MF2 channel 1 (AMI) → recovered WAV.

Usage:
    python3 sim/mf2_tek.py
    python3 sim/mf2_tek.py --km 3 --imp 10 --secs 30
    python3 sim/mf2_tek.py --km 3 --imp 100 --secs 30
"""
import argparse, gc, os, sys, time
import numpy as np
from scipy import signal
import audio, cvsd, fast, mf2, phy

RATE = mf2.RATE
LINE = mf2.LINE
FLEN = mf2.FLEN
OSB = 32
FS = LINE * OSB
CABLE = 1.8e6
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'out')
WAV_FS = 8000
CHUNK_BITS = 256000                 # 1 s of line bits per PHY chunk


def stream_ami(ln, sd=0.0, atten=1.0, seed=1, cable_km=None,
               imp=0.0, imp_amp=(1.0, 5.0), imp_tau=(8e-6, 80e-6),
               imp_ring=(20e3, 120e3)):
    """Chunked AMI PHY at MF2 rate (mf8_line.rx_ami rules + optional 24 AWG)."""
    b_r, a_r = signal.butter(2, min(0.99, 2 * LINE / FS), btype='low')
    zi_r = signal.lfilter_zi(b_r, a_r) * 0.0
    sym = fast.ami_encode(ln)
    acc, scale = [], None
    # Cable in bit-time chunks then upsample — keeps RAM bounded for 30 s @ 3–5 km.
    # √f is applied at FS on each upsampled chunk (independent FFT; ~ms edge error).
    for ci, s0 in enumerate(range(0, len(sym), CHUNK_BITS)):
        chunk = sym[s0:s0 + CHUNK_BITS]
        x = np.repeat(chunk, OSB).astype(np.float64)
        if cable_km is not None:
            x = phy.pair_24awg(x, FS, length_km=cable_km)
        else:
            b_c, a_c = signal.butter(1, min(0.99, 2 * CABLE / FS), btype='low')
            x = signal.lfilter(b_c, a_c, x)
        if scale is None:
            scale = 1.0 / max(np.abs(x).max(), 1e-12)
        x *= scale * atten
        if imp:
            x += phy.plant_noise(len(x), FS, rate_hz=imp, amp=imp_amp,
                                 tau_s=imp_tau, ring_hz=imp_ring,
                                 seed=seed * 7919 + ci)
        if sd:
            x += np.random.default_rng(seed * 100003 + ci).normal(0, sd, len(x))
        x, zi_r = signal.lfilter(b_r, a_r, x, zi=zi_r)
        acc.append(x[::4].astype(np.float32))
        del x
        gc.collect()
    del sym
    gc.collect()
    w = np.concatenate(acc)
    del acc
    gc.collect()
    rb = fast.ami_decode(w.astype(np.float64), OSB // 4, thresh=0.5)
    del w
    gc.collect()
    return rb


def place_channel(rb, st, c1, x, p):
    """Rebuild audio for channel 1 with mute outside locked runs (mf8_render style)."""
    nfr = len(c1)
    fill = (np.arange(nfr) & 1).astype(np.uint8)
    out_bits = fill.copy()
    live = np.zeros(nfr, bool)
    pos = st['pos']
    if len(pos) == 0:
        return np.zeros(len(x)), 1.0, 100.0
    segs = np.split(pos, np.flatnonzero(np.diff(pos) != FLEN) + 1)
    shift = None
    for g in segs:
        if len(g) < 66:
            continue
        g = g[:len(g) - 2]
        c0 = int(g[0]) // FLEN
        got = rb[g + mf2.CBIT[0]]
        if shift is None:
            best = (1.0, c0)
            for d in range(max(0, c0 - 64), min(c0 + 6000, nfr - 1000)):
                n = min(len(got), nfr - d, 4096)
                if n < 500:
                    break
                e = float((got[:n] != c1[d:d + n]).mean())
                if e < best[0]:
                    best = (e, d)
                if e == 0.0:
                    break
            shift = best[1] - c0
        d0 = c0 + shift
        if d0 < 0 or d0 >= nfr:
            continue
        n = min(len(got), nfr - d0)
        if n < 16:
            continue
        out_bits[d0:d0 + n] = got[:n]
        live[d0:d0 + n] = True
    live_n = int(live.sum())
    ber = float((out_bits[live] != c1[live]).mean()) if live_n else 1.0
    down = 100.0 * (1.0 - st['frames'] / max(nfr, 1))
    y = audio.reconstruct(cvsd.decode(out_bits, p), RATE)[:len(x)]
    out = np.where(live[:len(y)], y, 0.0)
    if len(out) < len(x):
        out = np.pad(out, (0, len(x) - len(out)))
    return out[:len(x)], ber, down


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--src', default='/home/joel/tek.wav')
    ap.add_argument('--secs', type=float, default=30.0)
    ap.add_argument('--offset', type=float, default=30.0,
                    help='start time in the source WAV (seconds)')
    ap.add_argument('--km', type=float, default=None,
                    help='24 AWG buried length (√f law); default short cable LP')
    ap.add_argument('--imp', type=float, default=0.0, help='impulses per second')
    ap.add_argument('--out', default=None)
    ap.add_argument('--src-out', default=None)
    args = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    if args.out is None:
        tag = 'clean' if not args.km and not args.imp else (
            f'{args.km:g}km' + (f'_imp{args.imp:g}' if args.imp else ''))
        args.out = os.path.join(OUT, f'mf2_tek_rx_{tag}.wav')
    if args.src_out is None:
        args.src_out = os.path.join(OUT, 'mf2_tek_src.wav')

    print(f'loading {args.secs:.0f}s from {args.src} @ t={args.offset:.0f}s')
    x, fs = audio.read_wav(args.src, channel=0, seconds=args.secs + 0.5,
                           offset=args.offset)
    x = audio.bandlimit(x, fs)
    x = x * (mf2.NOMINAL_RMS / max(x.std(), 1e-9))
    x = audio.resample_to(x, fs, RATE)[:int(args.secs * RATE)]
    p = mf2.params(RATE)
    c1 = cvsd.encode(x, p)
    c2 = cvsd.encode(np.zeros_like(x), p)
    A = [np.zeros(len(c1), np.uint8), np.zeros(len(c1), np.uint8)]
    ln = mf2.build([c1, c2], A)
    print(f'  {len(x)/RATE:.1f}s audio, {len(ln)} line bits @ {LINE} bps AMI')
    if args.km:
        loss = 12.0 * (args.km / 1.7) * (LINE / 256e3) ** 0.5
        print(f'  cable {args.km:g} km 24 AWG (√f), {loss:.1f} dB @ 256 kHz + AGC')
    if args.imp:
        print(f'  impulse {args.imp:g}/s (urban spikes, post-AGC)')

    t0 = time.time()
    rb = stream_ami(ln, cable_km=args.km, imp=args.imp)
    print(f'  PHY done in {time.time()-t0:.1f}s, {len(rb)} recovered bits')
    st = mf2.framer(rb)
    nfr = len(ln) // FLEN
    print(f'  framer: locked={st["lock_bit"] is not None}  '
          f'lof={st["lof_events"]} ({st["lof_events"]/args.secs:.2f}/s)  '
          f'frames={st["frames"]}  down={100*(1-st["frames"]/nfr):.2f}%')

    out, ber, down = place_channel(rb, st, c1, x, p)
    print(f'  channel-1 BER {ber:.3e}  (timeline mute outside lock)')

    src8 = audio.resample_to(x, RATE, WAV_FS)
    out8 = audio.resample_to(out, RATE, WAV_FS)
    # shared peak so levels are comparable across impulse runs
    peak = max(np.abs(src8).max(), np.abs(out8).max(), 1e-9)
    src8 = 0.85 * src8 / peak
    out8 = 0.85 * out8 / peak
    if not os.path.exists(args.src_out) or args.imp == 0 and args.km is None:
        audio.write_wav(args.src_out, src8, WAV_FS)
        print(f'wrote {args.src_out}')
    audio.write_wav(args.out, out8, WAV_FS)
    print(f'wrote {args.out}')


if __name__ == '__main__':
    main()
