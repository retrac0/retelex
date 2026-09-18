"""
The 7-channel variant: 16-bit frame, 512 kbps line.

    frame  [A1][C1][A2][C2] ... [A7][C7][S][T]   16 bits @ 32 kHz
           512 kbps line, 1.024 Mbaud biphase, 16.384 MHz master

N = 7 is the last member of the binary family: 2+2N is a power of two only at
N = 1, 3, 7, 15, and N = 15 leaves twisted pair behind.  This script runs the
same chain validate.py runs, at N = 7, and compares against N = 3 wherever the
comparison is the point.

Two measurement traps are controlled for explicitly, because both produce
plausible-looking numbers that mean nothing:

  * only four speech extracts exist, so channels 5-7 reuse the speakers of
    1-3 at a different offset.  The SOURCES therefore correlate, and raw
    off-diagonal isolation must be read against that floor, not against zero.
  * absolute segSNR is set by the source clip -- one extract has a crest
    factor of 17 and codes at 10.8 dB with no link at all.  What the carrier
    costs is the DELTA against the codec running alone.

Usage:  python3 n7.py [link|phy|audio|hw|all]
"""
import numpy as np, gc, sys
from scipy import signal
import audio, cvsd, link, run, fast

RATE, OS = 32000, 32
LOF = dict(lof_mode='updown', lof=12, lof_up=2, lof_down=1)
p = run.params(RATE)

# seven distinct extracts from four files
SRC = [('speech30.wav', 0.0), ('spk_300.wav', 0.0), ('spk_600.wav', 0.0),
       ('spk_900.wav', 0.0), ('speech30.wav', 15.0), ('spk_300.wav', 15.0),
       ('spk_600.wav', 15.0)]


def cfg(n):
    flen = link.frame_len(n)
    return dict(n=n, flen=flen, LINE=RATE * flen, SYM=2 * RATE * flen,
                FS=RATE * flen * OS, osc=32 * RATE * flen)


def load(n, secs):
    out = []
    for f, off in SRC[:n]:
        a, fs = audio.read_wav(f, seconds=secs, offset=off)
        a = audio.bandlimit(a, fs)
        out.append(audio.resample_to(a * (run.NOMINAL_RMS / a.std()), fs, RATE))
    L = min(map(len, out))
    return [s[:L] for s in out]


def lp(x, fc, order, FS):
    b, a = signal.butter(order, min(0.99, 2.0 * fc / FS), btype='low')
    return signal.lfilter(b, a, x)


def line_wave(line, SYM, FS, sigma=0.0, fc=None, seed=0):
    """Cable as a first-order lowpass, then noise, then the slicer.  Default fc
    tracks the symbol rate so the two builds are compared on equal terms."""
    fc = fc if fc is not None else 1.7578 * SYM      # 900 kHz at 512 kbaud
    rng = np.random.default_rng(seed)
    x = np.repeat(fast.dm_encode(line).astype(np.float64) * 2 - 1, OS // 2)
    x = lp(x, fc, 1, FS)
    x /= np.abs(x).max()
    if sigma:
        x += rng.normal(0, sigma, len(x))
    w = fast.slice_hyst(lp(x, SYM, 2, FS), 0.05)
    del x
    gc.collect()
    return w


def chan_ber(c, ref, hi=2000):
    """BER with an explicit offset search; recovered alignment is unknown."""
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
        return 1.0
    n = min(len(ref) - bo, len(c))
    return float((c[:n] != ref[bo:bo + n]).mean())


def build(n, secs):
    src = load(n, secs)
    L = len(src[0])
    ch = np.array([cvsd.encode(s, p) for s in src])
    sg = np.array([np.full(L, i % 2, np.uint8) for i in range(n)])   # mixed hook states
    return dict(src=src, L=L, ch=ch, sg=sg, line=link.build(ch, sg), **cfg(n))


def hdr(t):
    print('\n' + '=' * 76 + f'\n{t}\n' + '=' * 76)


# ----------------------------------------------------------------- link layer
def do_link(secs=6.0):
    hdr('1. FRAME AND ADJACENCY')
    for n in (3, 7):
        flen = link.frame_len(n)
        nm = sum(([f'A{i+1}', f'C{i+1}'] for i in range(n)), []) + ['S', 'T']
        static = {f'A{i+1}' for i in range(n)}
        bad = [k for k in range(1, flen)
               if nm[(flen - 2 + k) % flen] in static and nm[(flen - 1 + k) % flen] in static]
        print(f'  N={n}: {flen:2d}-bit frame, {flen-1:2d} wrong alignments, '
              f'adjacent-static violations {len(bad)}')

    b7, b3 = build(7, secs), build(3, secs)
    ok_phase = ok_ber = True
    for k in range(16):
        c, _, st = link.framer(b7['line'], 7, skew=k, **LOF)
        ok_phase &= (st['lock_phase'] == (16 - k % 16) % 16 and not st['false_lock'])
        best = 1.0
        for o in range(400):
            nn = min(len(b7['ch'][0]) - o, len(c[0]))
            if nn < 20000:
                break
            best = min(best, float((c[0][:nn] != b7['ch'][0][o:o + nn]).mean()))
            if best == 0.0:
                break
        ok_ber &= (best == 0.0)
    print(f'\n  lock to true phase, all 16 skews : {ok_phase}')
    print(f'  bit-exact channel recovery       : {ok_ber}')
    gl = link.build(b7['ch'], b7['sg'], order='grouped')
    gbad = sum(1 for k in range(16)
               if link.framer(gl, 7, skew=k, order='grouped', **LOF)[2]['false_lock'])
    print(f'  grouped-order control            : {gbad}/16 skews false-lock')

    hdr('2. ACQUISITION  (64 consecutive good frames)')
    for b in (b3, b7):
        ms = [1000.0 * link.framer(b['line'], b['n'], skew=k, **LOF)[2]['lock_bit']
              / b['LINE'] for k in range(b['flen'])]
        sl = [link.framer(b['line'], b['n'], skew=k, **LOF)[2]['slips'] for k in range(b['flen'])]
        print(f'  N={b["n"]}: {min(ms):.2f}-{max(ms):.2f} ms (mean {np.mean(ms):.2f}), '
              f'bit slips {min(sl)}-{max(sl)}')

    hdr('3. LOSS OF FRAME  (every slip size)')
    for b in (b3, b7):
        n, fl = b['n'], b['flen']
        ln = link.build(b['ch'], np.zeros((n, b['L']), np.uint8))
        at = (b['L'] // 2) * fl
        up, cons = [], []
        for k in range(1, fl):
            for mode, out in ((LOF, up), (dict(lof_mode='consecutive', lof=16), cons)):
                st = link.framer(link.slip(ln, at, n=k), n, **mode)[2]
                pos = st['pos']
                tp = np.where(pos < at, pos % fl, (pos + k) % fl)
                out.append(1000 * int((tp != tp[0]).sum()) / RATE)
        print(f'  N={n}: worst detection  +2/-1 trip 12 = {max(up):.2f} ms, '
              f'16-consecutive = {max(cons):.0f} ms')
        fr = [link.framer(link.impair(ln, ber=x, seed=5), n, **LOF)[2]['lof_events']
              for x in (1e-3, 1e-2, 3e-2)]
        print(f'        false reframes @ 1e-3 / 1e-2 / 3e-2 BER: {fr}')

    hdr('4. SIGNALLING  (7 channels, ch1 idle, others off-hook)')
    sgm = np.zeros((7, b7['L']), np.uint8)
    sgm[1:] = 1
    l7 = link.build(b7['ch'], sgm)
    for ber in (1e-3, 1e-2, 3e-2, 6e-2):
        _, ss, _ = link.framer(link.impair(l7, ber=ber, seed=13), 7, **LOF)
        raw = link.runs_of(ss[0])
        n_as = len(link.runs_of(link.rc_schmitt(ss[0], RATE, tau=2e-3)))
        print(f'  BER {ber:5.0e}: {int(ss[0].sum()):6d} erroneous A bits, longest run '
              f'{(max(raw)/RATE*1000 if len(raw) else 0):.3f} ms, spurious assertions {n_as}')


# ----------------------------------------------------------------- phy
def do_phy(secs=3.0):
    b3, b7 = build(3, secs), build(7, secs)

    hdr('5. CABLE BANDWIDTH  (clean; where the first-order model finally bites)')
    FCS = (40e3, 60e3, 80e3, 100e3, 125e3, 150e3, 200e3, 300e3)
    print('  cable fc (kHz)   ' + ' '.join(f'{f/1e3:7.0f}' for f in FCS))
    for b in (b3, b7):
        r = []
        for fc in FCS:
            w = line_wave(b['line'], b['SYM'], b['FS'], fc=fc)
            c, _, st = link.framer(fast.mono_decode(w, OS), b['n'], skew=3, **LOF)
            r.append(chan_ber(c[0], b['ch'][0]) if st['frames'] > 300 else 1.0)
            del w
            gc.collect()
        ok = [f for f, e in zip(FCS, r) if e == 0.0]
        print(f'  N={b["n"]} BER         ' + ' '.join(('  0    ' if e == 0 else f'{e:7.0e}') for e in r))
        print(f'      error-free from {min(ok)/1e3:.0f} kHz = {min(ok)/b["SYM"]:.2f} x symbol rate')

    hdr('6. NOISE MARGIN  (cable fc scaled to 1.76 x symbol rate)')
    for b in (b3, b7):
        r = []
        for sigma in (0.0, 0.2, 0.4, 0.5, 0.6, 0.7):
            w = line_wave(b['line'], b['SYM'], b['FS'], sigma=sigma, seed=1)
            c, _, st = link.framer(fast.mono_decode(w, OS), b['n'], skew=3, **LOF)
            r.append((sigma, chan_ber(c[0], b['ch'][0]) if st['frames'] > 300 else 1.0))
            del w
            gc.collect()
        cl = max(s for s, e in r if e == 0.0)
        print(f'  N={b["n"]}: error-free to sd = {cl:.1f}  ({20*np.log10(1/cl):.1f} dB peak SNR)   '
              + ' '.join(f'{s:.1f}:{"ok" if e==0 else f"{e:.0e}"}' for s, e in r))

    hdr('7. MONOSTABLE RC WINDOW  (at sd = 0.4, the stated design limit)')
    for b in (b3, b7):
        w = line_wave(b['line'], b['SYM'], b['FS'], sigma=0.4, seed=1)
        win = [t for t in (0.55, 0.60, 0.65, 0.70, 0.75, 0.80, 0.85, 0.90, 0.95)
               if (lambda r: r[2]['frames'] > 300 and chan_ber(r[0][0], b['ch'][0]) < 1e-3)
               (link.framer(fast.mono_decode(w, OS, thr=t), b['n'], skew=3, **LOF))]
        del w
        gc.collect()
        m = min(abs(min(win) - 0.75), abs(max(win) - 0.75)) / 0.75
        cell = 1e9 / b['LINE']
        print(f'  N={b["n"]}: {min(win):.2f}-{max(win):.2f} of a cell, +-{m:.0%} about 0.75; '
              f'cell {cell:.0f} ns -> monostable {0.75*cell:.0f} +-{m*0.75*cell:.0f} ns')


# ----------------------------------------------------------------- audio
def do_audio(secs=3.0):
    b = build(7, secs)
    src = b['src']
    w = line_wave(b['line'], b['SYM'], b['FS'])
    c, _, _ = link.framer(fast.mono_decode(w, OS), 7, skew=3, **LOF)
    del w
    gc.collect()
    outs = [audio.reconstruct(cvsd.decode(c[i], p), RATE) for i in range(7)]
    solo = [audio.reconstruct(cvsd.decode(cvsd.encode(src[i], p), p), RATE) for i in range(7)]

    hdr('8. AUDIO  (baselined against the codec running alone)')
    print(f'  {"ch":3s} {"source":14s} {"codec alone":>12s} {"over the link":>14s} {"delta":>8s}')
    d = []
    for i in range(7):
        a1, x1, _ = audio.align(src[i], solo[i])
        s1 = audio.seg_snr_db(a1, audio.gain_match(a1, x1), RATE)
        a2, x2, _ = audio.align(src[i], outs[i])
        s2 = audio.seg_snr_db(a2, audio.gain_match(a2, x2), RATE)
        d.append(s2 - s1)
        print(f'  {i+1:<3d} {SRC[i][0]:14s} {s1:9.2f} dB {s2:11.2f} dB {s2-s1:+7.2f}')
    print(f'  worst degradation attributable to the 7-channel carrier: {min(d):+.2f} dB')

    hdr('9. ISOLATION  (excess over the source-correlation floor)')
    cm = np.zeros((7, 7))
    fl = np.zeros((7, 7))
    for i in range(7):
        for j in range(7):
            aa, bb, _ = audio.align(src[j][:len(outs[i])], outs[i])
            cm[i, j] = np.corrcoef(aa, bb)[0, 1]
            a2, b2, _ = audio.align(src[i], src[j])
            fl[i, j] = np.corrcoef(a2, b2)[0, 1]
    pairs = [(i, j) for i in range(7) for j in range(7) if i != j]
    exc = max(abs(cm[i, j]) - abs(fl[i, j]) for i, j in pairs)
    print(f'  diagonal (wanted)              >= {min(cm[i,i] for i in range(7)):.3f}')
    print(f'  off-diagonal raw               <= {max(abs(cm[i,j]) for i,j in pairs):.3f}')
    print(f'  off-diagonal source floor      <= {max(abs(fl[i,j]) for i,j in pairs):.3f}')
    print(f'  off-diagonal EXCESS over floor <= {exc:+.3f}  '
          f'({sum(1 for i,j in pairs if abs(cm[i,j])-abs(fl[i,j]) > 0.02)}/42 pairs above 0.02)')

    hdr('10. DEGRADATION WITH LINE ERRORS')
    for ber in (0, 1e-4, 1e-3, 1e-2):
        cc, _, st = link.framer(link.impair(b['line'], ber=ber, seed=7), 7, **LOF)
        o = audio.reconstruct(cvsd.decode(cc[0], p), RATE)
        a1, x1, _ = audio.align(src[0], o)
        print(f'  BER {ber:6.0e}: segSNR {audio.seg_snr_db(a1, audio.gain_match(a1,x1), RATE):6.2f} dB, '
              f'loss-of-frame events {st["lof_events"]}')

    hdr('11. CROSSTALK AFTER A 2-BIT SLIP')
    lq = link.build(b['ch'], np.zeros((7, b['L']), np.uint8))
    at = (b['L'] // 2) * 16
    for pol, nm in ((LOF, '+2/-1 trip 12'), (dict(lof_mode='consecutive', lof=16), '16 consecutive')):
        cc, _, st = link.framer(link.slip(lq, at, n=2), 7, **pol)
        o0 = audio.reconstruct(cvsd.decode(cc[0], p), RATE)
        aa, bb, _ = audio.align(src[1][:len(o0)], o0)      # ch1 OUT vs ch2 SOURCE
        pos = st['pos']
        tp = np.where(pos < at, pos % 16, (pos + 2) % 16)
        print(f'  {nm:16s}: misaligned {1000*int((tp!=tp[0]).sum())/RATE:8.2f} ms, '
              f'ch1-out vs ch2-src correlation {abs(np.corrcoef(aa,bb)[0,1]):.3f}')

    hdr('12. SQUELCH  (noise-only line must never lock)')
    for sigma in (0.05, 0.2, 0.5, 1.0):
        rng = np.random.default_rng(1)
        nw = fast.slice_hyst(lp(rng.normal(0, sigma, b['line'].size * OS // 2),
                                b['SYM'], 2, b['FS']), 0.05)
        rr = fast.mono_decode(nw, OS)
        st = link.framer(rr, 7, **LOF)[2] if len(rr) > 100 else dict(lock_bit=None)
        runs = link.runs_of(rr, 1)
        print(f'  sd={sigma:4.2f}: locks={st["lock_bit"] is not None}, bit rate '
              f'{len(rr)/b["line"].size:.3f}x nominal, mean 1-run '
              f'{runs.mean() if len(runs) else 0:.0f} bits')
        del nw
        gc.collect()


# ----------------------------------------------------------------- hardware
def hw_frame_gen(A, C, n):
    """Literal hardware model: free-running binary counter, payload mux addressed
    by the counter taps with no offset, S/T override decoded from the top taps
    with the counter LSB as the data.  Must equal link.build() bit for bit."""
    flen = link.frame_len(n)
    abits = int(np.log2(flen))
    assert 2 ** abits == flen, 'frame length not a power of two'
    out = np.zeros(A.shape[1] * flen, np.uint8)
    for t in range(A.shape[1]):
        mux_in = sum(([A[i, t], C[i, t]] for i in range(n)), []) + [0, 0]
        for cnt in range(flen):
            bits = [(cnt >> k) & 1 for k in range(abits)]
            out[t * flen + cnt] = bits[0] if all(bits[1:]) else mux_in[cnt]
    return out


def do_hw():
    hdr('13. COUNTER IDENTITIES')
    rng = np.random.default_rng(0)
    for n in (1, 3, 7):
        flen, L = link.frame_len(n), 400
        A = rng.integers(0, 2, (n, L)).astype(np.uint8)
        C = rng.integers(0, 2, (n, L)).astype(np.uint8)
        ok = np.array_equal(hw_frame_gen(A, C, n), link.build(C, A))
        print(f'  N={n}: {flen:2d}-bit frame, {int(np.log2(flen))}-bit counter, '
              f'hardware model == link.build(): {ok}')

    hdr('14. CLOCK CHAIN AND PACKAGES')
    for n in (3, 7):
        c = cfg(n)
        ab = int(np.log2(c['flen']))
        top = 5 + ab
        div = c['osc'] // RATE
        print(f'  N={n}: osc {c["osc"]/1e6:6.3f} MHz, total divide {div} = 2^{int(np.log2(div))}')
        print(f'        Q4 = {c["SYM"]/1e6:.3f} MHz half-bit, Q5 = {c["LINE"]/1e3:.0f} kHz line bit, '
              f'Q6:Q{top} = mod-{c["flen"]} frame counter, Q{top} = 32 kHz frame clock')
        print(f'        highest 4040 tap Q{top} of 12: {"fits" if top <= 12 else "DOES NOT FIT"}')
        print(f'        payload mux {2*n} inputs -> {int(np.ceil(2*n/8))} x 74HC151, '
              f'S/T select = {ab-1}-input AND')
        print(f'        RX demux: {n} A + {n} C bits -> 74HC259 x2, '
              f'{8-n} outputs spare each')
        print(f'        cell {1e6/c["LINE"]:.2f} us, half-cell {1e9/c["SYM"]:.0f} ns, '
              f'150 ns edge = {150/(1e9/c["SYM"]):.0%} of a half-cell')

    hdr('15. WHY THE FAMILY STOPS AT N = 7')
    for n in (1, 3, 7, 15):
        c = cfg(n)
        print(f'  N={n:2d}: {c["flen"]:2d}-bit frame, {c["LINE"]/1e3:7.0f} kbps, '
              f'{c["SYM"]/1e6:6.3f} Mbaud, osc {c["osc"]/1e6:6.3f} MHz, '
              f'half-cell {1e9/c["SYM"]:4.0f} ns, fundamental {c["LINE"]/2e3:5.0f} kHz, '
              f'{"1" if n <= 7 else "2"} x 74HC259 per bit type')


if __name__ == '__main__':
    what = sys.argv[1] if len(sys.argv) > 1 else 'all'
    if what in ('link', 'all'):
        do_link()
    if what in ('phy', 'all'):
        do_phy()
    if what in ('audio', 'all'):
        do_audio()
    if what in ('hw', 'all'):
        do_hw()
