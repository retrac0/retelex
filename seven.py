"""
Seven independent talkers, 30 s, all seven channels in parallel through the
complete N=7 chain, swept for noise resistance.

    CVSD x7 -> 16-bit frame -> differential Manchester -> cable -> noise
            -> slicer -> monostable -> framer -> demux -> CVSD x7 -> audio

This is the measurement docs/seven-channel.md could not make: with seven
different speakers the source-correlation floor collapses, so channel
isolation becomes directly readable instead of having to be inferred as an
excess over a 0.110 floor.

Usage: python3 seven.py [os_check|sweep|all] [--secs S] [--os N]
"""
import numpy as np, gc, sys, time
from scipy import signal
import audio, cvsd, link, run, fast

RATE, NCH, FLEN = 32000, 7, 16
LINE = RATE * FLEN                    # 512 kbps
SYM = 2 * LINE                        # 1.024 Mbaud
LOF = dict(lof_mode='updown', lof=12, lof_up=2, lof_down=1)
CABLE_FC = 1.7578 * SYM               # 1.8 MHz: same fc/symbol-rate as the 3-ch build
p = run.params(RATE)
TALKERS = [f'talker{i+1}.wav' for i in range(NCH)]


def load(secs):
    out = []
    for f in TALKERS:
        a, fs = audio.read_wav(f, seconds=secs)
        a = audio.bandlimit(a, fs)
        out.append(audio.resample_to(a * (run.NOMINAL_RMS / a.std()), fs, RATE))
    L = min(map(len, out))
    return [s[:L] for s in out]


def lp(x, fc, order, FS):
    b, a = signal.butter(order, min(0.99, 2.0 * fc / FS), btype='low')
    return signal.lfilter(b, a, x)


def line_wave(line, OS, sigma=0.0, fc=CABLE_FC, seed=0):
    """Cable, noise and slicer.  Built in place where possible: at 30 s and
    OS=16 the waveform is ~2 GB and a careless copy doubles that."""
    FS = LINE * OS
    x = np.repeat(fast.dm_encode(line).astype(np.float64) * 2 - 1, OS // 2)
    x = lp(x, fc, 1, FS)
    x /= np.abs(x).max()
    if sigma:
        rng = np.random.default_rng(seed)
        step = 1 << 22
        for i in range(0, len(x), step):        # chunked, to avoid a 2 GB temporary
            x[i:i + step] += rng.normal(0, sigma, len(x[i:i + step]))
    x = lp(x, SYM, 2, FS)
    w = fast.slice_hyst(x, 0.05)
    del x
    gc.collect()
    return w


def chan_ber(c, ref, hi=3000):
    probe, bo, be = 50_000, None, 1.0
    for o in range(hi):
        if o + probe > len(ref) or probe > len(c):
            break
        e = float((c[:probe] != ref[o:o + probe]).mean())
        if e < be:
            bo, be = o, e
        if be == 0.0:
            break
    if bo is None:
        return 1.0, 0
    n = min(len(ref) - bo, len(c))
    return float((c[:n] != ref[bo:bo + n]).mean()), bo


def run_chain(line, ch, src, OS, sigma, seed=1, score_audio=True):
    t0 = time.time()
    w = line_wave(line, OS, sigma=sigma, seed=seed)
    rb = fast.mono_decode(w, OS)
    del w
    gc.collect()
    c, s, st = link.framer(rb, NCH, skew=3, **LOF)
    del rb
    gc.collect()
    res = dict(sigma=sigma, frames=st['frames'], lof=st['lof_events'],
               locked=st['lock_bit'] is not None, false_lock=st['false_lock'],
               secs=time.time() - t0)
    if st['frames'] < 300:
        res.update(ber=[1.0] * NCH, seg=[float('nan')] * NCH, cm=None)
        return res
    res['ber'] = [chan_ber(c[i], ch[i])[0] for i in range(NCH)]
    if score_audio:
        outs = [audio.reconstruct(cvsd.decode(c[i], p), RATE) for i in range(NCH)]
        segs = []
        for i in range(NCH):
            a, b, _ = audio.align(src[i], outs[i])
            segs.append(audio.seg_snr_db(a, audio.gain_match(a, b), RATE))
        res['seg'] = segs
        res['cm'] = isolation(outs, src)
    return res


def isolation(outs, src):
    """
    Channel isolation matrix.

    A channel has ONE delay, so the lag is found once per recovered channel
    against its own source and then applied to every column.  Re-running
    audio.align() for each (i,j) pair instead maximises the correlation over
    ~8192 candidate lags before measuring it, which cannot come out at zero for
    two unrelated speech signals: it inflated the off-diagonal from 0.018 to
    0.072 on a run whose BER was identically zero.
    """
    n = len(outs)
    cm = np.zeros((n, n))
    for i in range(n):
        _, _, lag = audio.align(src[i][:len(outs[i])], outs[i])
        lag = int(lag)
        for j in range(n):
            o, s = outs[i], src[j]
            if lag > 0:
                oo, ss = o[lag:], s[:len(o) - lag]
            elif lag < 0:
                oo, ss = o[:len(o) + lag], s[-lag:]
            else:
                oo, ss = o, s[:len(o)]
            m = min(len(oo), len(ss))
            cm[i, j] = np.corrcoef(oo[:m], ss[:m])[0, 1]
    return cm


def hdr(t):
    print('\n' + '=' * 78 + f'\n{t}\n' + '=' * 78)


# ------------------------------------------------------- OS validation
def do_os_check(secs=5.0):
    hdr('0. OVERSAMPLING CHECK  (does OS=16 change the answer vs OS=32?)')
    print('  The 30 s sweep needs OS=16 to fit in memory.  Before trusting it,')
    print('  check it against the OS=32 setting validate.py uses, on a short clip.')
    src = load(secs)
    ch = np.array([cvsd.encode(s, p) for s in src])
    sg = np.array([np.full(len(src[0]), i % 2, np.uint8) for i in range(NCH)])
    line = link.build(ch, sg)
    print(f'\n  {secs:.0f} s, {line.size} line bits')
    print(f'  {"OS":>4s} {"sigma":>6s} {"worst BER":>11s} {"worst segSNR":>13s} {"LOF":>5s} {"s":>6s}')
    for OS in (32, 16):
        for sigma in (0.0, 0.4, 0.6):
            r = run_chain(line, ch, src, OS, sigma)
            print(f'  {OS:>4d} {sigma:6.1f} {max(r["ber"]):11.1e} '
                  f'{min(r["seg"]):13.2f} {r["lof"]:5d} {r["secs"]:6.1f}')


# ------------------------------------------------------------- sweep
def do_sweep(secs=30.0, OS=32, segs=3):
    hdr(f'1. SEVEN TALKERS, {secs:.0f} s, ALL CHANNELS IN PARALLEL')
    src = load(secs)
    L = len(src[0])
    print(f'  {L/RATE:.1f} s per channel, {NCH} channels, {FLEN}-bit frame')
    t0 = time.time()
    ch = np.array([cvsd.encode(s, p) for s in src])
    sg = np.array([np.full(L, i % 2, np.uint8) for i in range(NCH)])
    line = link.build(ch, sg)
    print(f'  CVSD encode {time.time()-t0:.1f} s; line {line.size} bits '
          f'= {line.size/LINE:.1f} s at {LINE/1000:.0f} kbps')
    print(f'  cable fc {CABLE_FC/1e6:.2f} MHz, OS={OS} (sim FS {LINE*OS/1e6:.3f} MHz)')

    # source floor, the thing that made the old measurement unreadable
    fl = np.zeros((NCH, NCH))
    for i in range(NCH):
        for j in range(NCH):
            a, b, _ = audio.align(src[i], src[j])
            fl[i, j] = np.corrcoef(a, b)[0, 1]
    floor = max(abs(fl[i, j]) for i in range(NCH) for j in range(NCH) if i != j)
    print(f'  source-correlation floor: {floor:.4f}  (4-file set gave 0.110)')

    hdr('2. NOISE RESISTANCE')
    rows = []
    for sigma in (0.0, 0.2, 0.4, 0.5, 0.6, 0.7, 0.8):
        r = run_chain(line, ch, src, OS, sigma)
        rows.append(r)
        pk = 20 * np.log10(1 / sigma) if sigma else float('inf')
        print(f'  sd={sigma:.1f} ({pk:5.1f} dB pk-SNR): locked={str(r["locked"]):5s} '
              f'LOF={r["lof"]:<4d} worst BER {max(r["ber"]):.1e}  '
              f'segSNR min {min(r["seg"]):6.2f} / mean {np.mean(r["seg"]):6.2f} dB '
              f'[{r["secs"]:.0f}s]')
        gc.collect()

    hdr('3. PER-CHANNEL DETAIL')
    print(f'  {"sd":>4s} ' + ' '.join(f'{"ch"+str(i+1):>8s}' for i in range(NCH)))
    for r in rows:
        print(f'  {r["sigma"]:4.1f} ' + ' '.join(f'{v:8.2f}' for v in r['seg']))
    print('  (segSNR dB per channel; nan = framer never locked)')
    print()
    print(f'  {"sd":>4s} ' + ' '.join(f'{"ch"+str(i+1):>8s}' for i in range(NCH)))
    for r in rows:
        print(f'  {r["sigma"]:4.1f} ' + ' '.join(
            ('     0  ' if b == 0 else f'{b:8.1e}') for b in r['ber']))
    print('  (channel BER)')

    hdr('4. ISOLATION, ABSOLUTE  (7 independent talkers, no floor to subtract)')
    for r in rows:
        if r['cm'] is None:
            continue
        cm = r['cm']
        pairs = [(i, j) for i in range(NCH) for j in range(NCH) if i != j]
        off = max(abs(cm[i, j]) for i, j in pairs)
        print(f'  sd={r["sigma"]:.1f}: diagonal >= {min(cm[i,i] for i in range(NCH)):.3f}, '
              f'off-diagonal <= {off:.3f}  over {len(pairs)} pairs')
    if rows[0]['cm'] is not None:
        print('\n  clean-line matrix (rows = recovered channel, cols = source):')
        cm = rows[0]['cm']
        print('        ' + ' '.join(f'{"src"+str(j+1):>7s}' for j in range(NCH)))
        for i in range(NCH):
            print(f'  out{i+1}  ' + ' '.join(f'{cm[i,j]:7.3f}' for j in range(NCH)))




# ------------------------------------------------- segmented 30 s at OS=32
def do_seg_sweep(secs=30.0, OS=32, nseg=3):
    """
    OS=16 failed its own validation (os_check): at sd=0.4 it reported BER 4.1e-2
    where OS=32 is error-free, because a 16-sample cell quantises the 0.75-cell
    monostable threshold to 6.25% of a cell -- comparable to the +-13% window
    being measured.  So the sweep runs at OS=32, in segments, to fit memory.

    Each segment is an independent acquisition; at ~2.4 ms to lock against a
    10 s segment that costs 0.024% of the data.
    """
    hdr(f'SEVEN TALKERS, {secs:.0f} s, OS={OS}, {nseg} x {secs/nseg:.0f} s segments')
    src_full = load(secs)
    L = len(src_full[0])
    seg_len = L // nseg
    print(f'  {L/RATE:.1f} s x {NCH} channels, {FLEN}-bit frame, '
          f'cable fc {CABLE_FC/1e6:.2f} MHz, sim FS {LINE*OS/1e6:.3f} MHz')
    fl = isolation(src_full, src_full)      # same estimator as the link matrix
    print(f'  source-correlation floor {max(abs(fl[i,j]) for i in range(NCH) for j in range(NCH) if i!=j):.4f}'
          f'   (measured with the same single-lag estimator)')

    sigmas = (0.0, 0.2, 0.4, 0.5, 0.6, 0.7)
    agg = {s: dict(ber=[], seg=[], lof=0, off=[], diag=[]) for s in sigmas}
    for k in range(nseg):
        src = [x[k * seg_len:(k + 1) * seg_len] for x in src_full]
        ch = np.array([cvsd.encode(x, p) for x in src])
        sg = np.array([np.full(seg_len, i % 2, np.uint8) for i in range(NCH)])
        line = link.build(ch, sg)
        for sigma in sigmas:
            r = run_chain(line, ch, src, OS, sigma, seed=100 + k)
            a = agg[sigma]
            a['ber'].append(r['ber'])
            a['seg'].append(r['seg'])
            a['lof'] += r['lof']
            if r['cm'] is not None:
                cm = r['cm']
                a['off'].append(max(abs(cm[i, j]) for i in range(NCH)
                                    for j in range(NCH) if i != j))
                a['diag'].append(min(cm[i, i] for i in range(NCH)))
            print(f'    seg {k+1}/{nseg} sd={sigma:.1f}: worst BER {max(r["ber"]):.1e}, '
                  f'segSNR min {min(r["seg"]):.2f}, LOF {r["lof"]}  [{r["secs"]:.0f}s]',
                  flush=True)
        del line, ch
        gc.collect()

    hdr('NOISE RESISTANCE  (aggregated over segments)')
    print(f'  {"sd":>5s} {"pk SNR":>8s} {"worst BER":>11s} {"mean BER":>11s} '
          f'{"segSNR min":>11s} {"segSNR mean":>12s} {"LOF":>5s} {"isolation":>10s}')
    for s in sigmas:
        a = agg[s]
        ber = np.array(a['ber'])
        sgs = np.array(a['seg'])
        pk = f'{20*np.log10(1/s):.1f}' if s else 'inf'
        iso = f'{max(a["off"]):.3f}' if a['off'] else '-'
        print(f'  {s:5.1f} {pk:>8s} {ber.max():11.1e} {ber.mean():11.1e} '
              f'{np.nanmin(sgs):11.2f} {np.nanmean(sgs):12.2f} {a["lof"]:5d} {iso:>10s}')

    hdr('PER-CHANNEL segSNR (dB), mean over segments')
    print(f'  {"sd":>5s} ' + ' '.join(f'{"ch"+str(i+1):>8s}' for i in range(NCH)))
    for s in sigmas:
        m = np.array(agg[s]['seg']).mean(axis=0)
        print(f'  {s:5.1f} ' + ' '.join(f'{v:8.2f}' for v in m))


if __name__ == '__main__':
    args = sys.argv[1:]
    what = args[0] if args and not args[0].startswith('--') else 'all'
    secs = float(args[args.index('--secs') + 1]) if '--secs' in args else 30.0
    OS = int(args[args.index('--os') + 1]) if '--os' in args else 32
    nseg = int(args[args.index('--segs') + 1]) if '--segs' in args else 3
    if what in ('os_check', 'all'):
        do_os_check()
    if what in ('sweep', 'all'):
        do_seg_sweep(secs, OS, nseg)
