"""
MF2 end to end: two talkers, real CVSD, over a real line, AMI primary.

Closes the noisy-condition half of mf2/sim.md G4.  Bit-level framing is
sim/mf2.py; this module puts a waveform on the wire.

AMI encoder/decoder is NOT forked here.  It is mf8_line.rx_ami (and under it
fast.ami_encode / fast.ami_decode — line-codes.md §2.2 option C), called with
line=256e3.  Hardware intent: mf2/ami.md.

Chain, per direction:

    2 LibriSpeech talkers -> CVSD 64 kbps -> mf2 frame (4 bits, 64 kHz)
      -> AMI @ 256 kBaud -> cable -> impairment -> AMI RX (8× DPLL model)
      -> mf2 framer -> per-channel CVSD decode -> segSNR and isolation

DM @ 256 kbps is a reference column only (same bit rate, not a product option).

Measurement rules match mf8_line.py: score inside the longest contiguous
locked run; isolation uses one lag per recovered channel.

Usage:  python3 sim/mf2_line.py            everything
        python3 sim/mf2_line.py clean      clean line, AMI + DM ref
        python3 sim/mf2_line.py noise      Gaussian sweep
        python3 sim/mf2_line.py plant      impulse and attenuation
"""
import sys, gc, time, numpy as np
import audio, cvsd, mf2, mf8_line

RATE = mf2.RATE
LINE = mf2.LINE                   # 256 kbps
NCH = mf2.NCH
FLEN = mf2.FLEN
OS = 32                           # samples per line bit (same as mf8_line)
CABLE = 1.8e6
SECS = 1.0


def _rx_ami(ln, **kw):
    return mf8_line.rx_ami(ln, line=LINE, os=OS, cable=CABLE, **kw)


def _rx_dm(ln, **kw):
    """Same-bit-rate DM reference — not MF2's line code."""
    return mf8_line.rx_dm(ln, line=LINE, os=OS, cable=CABLE, **kw)


CODES = {'AMI': _rx_ami, 'diff Manchester': _rx_dm}


def sources(secs=SECS):
    src, bits = [], []
    p = mf2.params(RATE)
    for j in range(NCH):
        x, fs = audio.read_wav(f'talker{j + 1}.wav', seconds=secs + 0.5)
        x = audio.bandlimit(x, fs)
        x = x * (mf2.NOMINAL_RMS / max(x.std(), 1e-9))
        x = audio.resample_to(x, fs, RATE)[:int(secs * RATE)]
        src.append(x)
        bits.append(cvsd.encode(x, p))
    return src, bits, p


def measure(ln, rx, src, bits, p, want_iso=False, **kw):
    """One cell: PHY, framer, per-channel audio.  Same bookkeeping as mf8_line."""
    t0 = time.time()
    rb = rx(ln, **kw)
    st = mf2.framer(rb)
    out = dict(lof=st['lof_events'], locked=st['lock_bit'] is not None,
               false=bool(st['false_lock']), secs=time.time() - t0)
    g = mf8_line.longest_run(st['pos'], flen=FLEN)
    nfr = len(ln) // FLEN
    out['down'] = 100.0 * (1.0 - st['frames'] / nfr)
    if g is None or len(g) < 4000:
        del rb; gc.collect()
        out.update(seg=[float('nan')] * NCH, dseg=[float('nan')] * NCH,
                   ber=[1.0] * NCH, iso=None,
                   clean=0.0 if g is None else len(g) / RATE)
        return out
    g = g[:len(g) - 2]
    out['clean'] = len(g) / RATE
    got = [rb[g + mf2.CBIT[j]] for j in range(NCH)]
    del rb; gc.collect()
    i0 = int(g[0]) // FLEN
    best = (1.0, i0)
    for d in range(max(0, i0 - 200), i0 + 200):
        n = min(len(got[0]), len(bits[0]) - d)
        if n < 1000:
            break
        e = float((got[0][:n] != bits[0][d:d + n]).mean())
        if e < best[0]:
            best = (e, d)
        if e == 0.0:
            break
    i0 = best[1]
    out['shift'] = i0 - int(g[0]) // FLEN
    ref = [bits[j][i0:i0 + len(got[j])] for j in range(NCH)]
    got = [got[j][:len(ref[j])] for j in range(NCH)]
    out['ber'] = [float((got[j] != ref[j]).mean()) for j in range(NCH)]
    seg, dseg, outs = [], [], []
    for j in range(NCH):
        y = audio.reconstruct(cvsd.decode(got[j], p), RATE)
        a, b, _ = audio.align(src[j][i0:i0 + len(got[j])], y)
        s1 = audio.seg_snr_db(a, audio.gain_match(a, b), RATE)
        yc = audio.reconstruct(cvsd.decode(ref[j], p), RATE)
        a2, b2, _ = audio.align(src[j][i0:i0 + len(got[j])], yc)
        s0 = audio.seg_snr_db(a2, audio.gain_match(a2, b2), RATE)
        seg.append(s1); dseg.append(s1 - s0); outs.append(y)
    out['seg'] = seg; out['dseg'] = dseg
    out['iso'] = (mf8_line.isolation(outs, [src[j][i0:] for j in range(NCH)])
                  if want_iso else None)
    return out


def row(label, r):
    if not r['locked'] or np.isnan(r['seg'][0]):
        tag = 'no lock' if not r['locked'] else 'chopped'
        print(f'  {label:26s} {tag:>9s} {r["down"]:8.2f}% {r["lof"]:>5d}'
              f'  {"-":>6s} {"-":>7s}  {"-":>8s} {1000 * r["clean"]:7.0f}ms',
              flush=True)
        return
    worst = min(r['dseg']); mean = float(np.mean(r['dseg']))
    mb = max(r['ber'])
    print(f'  {label:26s} {np.mean(r["seg"]):8.2f}dB {r["down"]:8.2f}% {r["lof"]:>5d}'
          f'  {mean:+6.2f} {worst:+7.2f}  {mb:8.1e} {1000 * r["clean"]:7.0f}ms',
          flush=True)


HDR = (f'  {"condition":26s} {"segSNR":>10s} {"down":>9s} {"LOF":>5s}'
       f'  {"d mean":>6s} {"d worst":>7s}  {"max BER":>8s} {"clean":>9s}')


def clean():
    src, bits, p = sources()
    A = [np.zeros(len(bits[0]), np.uint8) for _ in range(NCH)]
    ln = mf2.build(bits, A)
    print('CLEAN LINE -- two talkers through MF2 + AMI')
    print(f'  {SECS:.1f} s, 64 kbps/ch, 256 kbps line, AMI @ 256 kBaud.')
    print('  PHY: mf8_line.rx_ami(line=256e3).  DM column is same-bit-rate ref.\n')
    print(HDR)
    res = {}
    for cn, rx in CODES.items():
        r = measure(ln, rx, src, bits, p, want_iso=True)
        res[cn] = r
        row(cn, r)
    print('\n  Per channel, AMI:\n')
    print(f'  {"channel":9s} ' + ' '.join(f'{j + 1:>8d}' for j in range(NCH)))
    r = res['AMI']
    print(f'  {"segSNR":9s} ' + ' '.join(f'{v:8.2f}' for v in r['seg']))
    print(f'  {"vs codec":9s} ' + ' '.join(f'{v:+8.2f}' for v in r['dseg']))
    print(f'  {"bit BER":9s} ' + ' '.join(f'{v:8.0e}' for v in r['ber']))
    n = min(len(x) for x in src)
    fl = abs(np.corrcoef(src[0][:n], src[1][:n])[0, 1])
    print(f'\n  Source-correlation floor on this {SECS:.1f} s window: {fl:.3f}')
    for cn in CODES:
        cm = res[cn]['iso']
        if cm is None:
            continue
        off = np.abs(cm - np.diag(np.diag(cm))).max()
        print(f'  Isolation, {cn:16s} diagonal min {np.min(np.diag(cm)):.3f}, '
              f'off-diagonal max {off:.3f}, excess over floor {off - fl:+.3f}')


def noise():
    src, bits, p = sources()
    A = [np.zeros(len(bits[0]), np.uint8) for _ in range(NCH)]
    ln = mf2.build(bits, A)
    print('GAUSSIAN NOISE -- sd referred to transmitted peak (AMI primary)\n')
    print(HDR)
    for cn, rx in CODES.items():
        for sd in (0.0, 0.3, 0.4, 0.5, 0.6, 0.7):
            row(f'{cn}, sd {sd:.1f}', measure(ln, rx, src, bits, p, sd=sd))
        print()


def plant():
    src, bits, p = sources()
    A = [np.zeros(len(bits[0]), np.uint8) for _ in range(NCH)]
    ln = mf2.build(bits, A)
    print('IMPULSE NOISE -- damped rings 0.5-3x peak, Poisson (AMI primary)\n')
    print(HDR)
    for cn, rx in CODES.items():
        for imp in (0.0, 1.0, 10.0, 100.0, 1000.0):
            row(f'{cn}, {imp:.0f}/s', measure(ln, rx, src, bits, p, imp=imp))
        print()
    print('ATTENUATION -- signal scaled, sd 0.10 floor, 0.05 hyst in slicer path\n')
    print(HDR)
    for cn, rx in CODES.items():
        for at in (1.0, 0.5, 0.25, 0.12):
            row(f'{cn}, atten {at:.2f}',
                measure(ln, rx, src, bits, p, atten=at, sd=0.10))
        print()


TARGETS = {'clean': clean, 'noise': noise, 'plant': plant}

if __name__ == '__main__':
    for k in (sys.argv[1:] or list(TARGETS)):
        TARGETS[k]()
        print()
