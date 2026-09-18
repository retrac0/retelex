"""
Strapping the carrier: can one board cover several line conditions?

The committed build is N = 3 channels, 32 kbps CVSD, 256 kbps line, 8.192 MHz
master (docs/spec.md).  docs/seven-channel.md showed N = 7 is the same design
with one more counter tap.  This script asks the other two questions:

  * can the CHANNEL COUNT be a strap rather than a build option -- down to the
    4-bit frame at N = 1?
  * can the LINE RATE be a strap -- half, or quarter, of 256 kbps -- to buy
    reach on a bad pair?

and, because a strap that can be set wrong is a strap that will be set wrong,

  * what does a MIS-STRAPPED link do?  It must fail safe: the squelch
    pathology of spec 8.1 is what a wrong RC could plausibly produce.

Everything runs the same chain validate.py runs.  N = 3 at 32 kbps is the
control throughout.

Usage:  python3 strap.py [matrix|hw|link|audio|phy|all]
"""
import numpy as np, gc, sys
from scipy import signal
import audio, cvsd, link, run, fast

OSC = 8.192e6              # master crystal, unchanged by any strap
OS = 32                    # simulation samples per line bit
LOF = dict(lof_mode='updown', lof=12, lof_up=2, lof_down=1)
REF_SLEW = 12000.0         # the Iabc trim the channel card is built with
SRC = ('speech30.wav', 'spk_300.wav', 'spk_600.wav', 'spk_900.wav')


def hdr(t):
    print('\n' + '=' * 76 + f'\n{t}\n' + '=' * 76)


def strap(n_ch, r):
    """Strap setting -> every rate on the card.  `r` is the rate divider
    exponent: r=0 is the committed build, r=1 half rate, r=2 quarter."""
    flen = link.frame_len(n_ch)
    k = int(np.log2(flen))
    assert 2 ** k == flen
    half = OSC / 2 ** (4 + r)              # half-bit clock   (biphase transitions)
    line = half / 2                        # line bit clock
    rate = line / flen                     # frame clock == CVSD clock
    return dict(n=n_ch, flen=flen, k=k, r=r, half_rate=half, line_rate=line,
                sym=2 * line, rate=rate, voice=n_ch * rate,
                tap_half=4 + r, tap_line=5 + r, tap_frame=5 + r + k)


# --------------------------------------------------------------- 1. the matrix
def do_matrix():
    hdr('1. STRAP MATRIX  (one 8.192 MHz crystal, one 74HC4040)')
    print(f'  {"N":>2s} {"r":>2s} {"frame":>6s} {"line":>9s} {"baud":>10s} '
          f'{"CVSD/ch":>8s} {"voice":>8s} {"eff":>5s} {"fund":>7s} '
          f'{"cell":>8s} {"mono":>8s} {"Qframe":>7s} {"reach":>6s}')
    base = strap(3, 0)
    for n_ch in (1, 3, 7):
        for r in (0, 1, 2):
            c = strap(n_ch, r)
            cell = 1e6 / c['line_rate']
            reach = np.sqrt(base['line_rate'] / c['line_rate'])       # sqrt(f) skin effect
            print(f'  {c["n"]:2d} {c["r"]:2d} {c["flen"]:5d}b {c["line_rate"]/1e3:8.0f}k '
                  f'{c["sym"]/1e6:9.3f}M {c["rate"]/1e3:7.0f}k {c["voice"]/1e3:7.0f}k '
                  f'{c["n"]/(c["n"]+1):5.0%} {c["line_rate"]/2e3:6.0f}k {cell:7.2f}us '
                  f'{0.75*cell:7.2f}us Q{c["tap_frame"]:<6d} {reach:5.2f}x'
                  + ('   <-- committed build' if (n_ch, r) == (3, 0) else ''))
    print(f'\n  every frame-clock tap fits a 12-stage 4040: '
          f'max Q{max(strap(n,r)["tap_frame"] for n in (1,3,7) for r in (0,1,2))}')
    print('  reach is sqrt(f) analysis from spec 10, NOT a measurement, and it is')
    print('  only valid while the pair is in the skin-effect region (see the doc).')

    hdr('2. WHAT A STRAP COSTS IN PAYLOAD')
    print('  at a fixed line rate the straps trade channels against quality:')
    for r in (0, 1):
        row = [strap(n, r) for n in (1, 3, 7)]
        print(f'   line {row[0]["line_rate"]/1e3:.0f} kbps: ' + ',  '.join(
            f'N={c["n"]} -> {c["rate"]/1e3:.0f} kbps/ch' for c in row))


# --------------------------------------------- 2. one board, three strappings
def hw_board(A, C, n_ch, cbits=4):
    """Literal model of ONE transmitter card with a channel-count strap.

    The frame counter is physically `cbits` stages of the 4040 (enough for
    N = 7).  The strap does exactly two things:
        - masks the counter bits above the frame width to 0 wherever the
          counter is consumed (mux address, S/T select, RX '259 address)
        - picks which tap is the frame clock
    Nothing else on the card changes.  Must equal link.build() bit for bit at
    every strap setting.
    """
    flen = link.frame_len(n_ch)
    k = int(np.log2(flen))
    mask = (1 << k) - 1
    L = A.shape[1]
    out = np.zeros(L * flen, np.uint8)
    for step in range(L * flen):
        cnt = (step & ((1 << cbits) - 1)) & mask      # free-running, then masked
        t = step // flen                              # payload latched by Qframe
        bits = [(cnt >> j) & 1 for j in range(k)]
        mux_in = sum(([A[i, t], C[i, t]] for i in range(n_ch)), []) + [0, 0]
        # S/T select = AND of every counter bit above the LSB, unused inputs
        # of the 3-input gate strapped high
        sel = all(bits[1:]) if k > 1 else True
        out[step] = bits[0] if sel else mux_in[cnt]
    return out


def do_hw():
    hdr('3. ONE BOARD, THREE CHANNEL-COUNT STRAPS')
    rng = np.random.default_rng(0)
    for n_ch in (1, 3, 7):
        L = 300
        A = rng.integers(0, 2, (n_ch, L)).astype(np.uint8)
        C = rng.integers(0, 2, (n_ch, L)).astype(np.uint8)
        ok = np.array_equal(hw_board(A, C, n_ch), link.build(C, A))
        c = strap(n_ch, 0)
        print(f'  N={n_ch}: {c["flen"]:2d}-bit frame, mask 0x{(1<<c["k"])-1:X}, '
              f'frame clock Q{c["tap_frame"]}, S/T select = {max(c["k"]-1,1)}-input AND'
              f'{" (strapped through)" if c["k"]==1 else ""}'
              f'  -- hardware model == link.build(): {ok}')

    hdr('4. ADJACENCY AT EVERY STRAP  (the interleaving rule, spec 2.1)')
    for order in ('interleaved', 'grouped'):
        for n_ch in (1, 2, 3, 7):
            flen = link.frame_len(n_ch)
            if order == 'interleaved':
                nm = sum(([f'A{i+1}', f'C{i+1}'] for i in range(n_ch)), []) + ['S', 'T']
            else:
                nm = [f'C{i+1}' for i in range(n_ch)] + \
                     [f'A{i+1}' for i in range(n_ch)] + ['S', 'T']
            static = {f'A{i+1}' for i in range(n_ch)}
            bad = [k for k in range(1, flen)
                   if nm[(flen - 2 + k) % flen] in static
                   and nm[(flen - 1 + k) % flen] in static]
            print(f'  {order:12s} N={n_ch}: {flen:2d}-bit, {flen-1:2d} wrong alignments, '
                  f'adjacent-static violations {len(bad)}')
        print()



# ------------------------------------------------------- 3. the 4-bit frame
def load(n_ch, rate, secs):
    out = []
    for f in (SRC * 2)[:n_ch]:
        a, fs = audio.read_wav(f, seconds=secs)
        a = audio.bandlimit(a, fs)
        out.append(audio.resample_to(a * (run.NOMINAL_RMS / a.std()), fs, rate))
    L = min(map(len, out))
    return [s[:L] for s in out]


def build_line(n_ch, rate, secs, slew=REF_SLEW, mixed_sig=True):
    p = cvsd.CVSDParams(rate=rate, slew=slew, **run.BASE)
    src = load(n_ch, rate, secs)
    L = len(src[0])
    ch = np.array([cvsd.encode(s, p) for s in src])
    sg = np.array([np.full(L, i % 2, np.uint8) for i in range(n_ch)]) if mixed_sig \
        else np.zeros((n_ch, L), np.uint8)
    r = int(round(np.log2(OSC / (rate * link.frame_len(n_ch))) - 5))
    return dict(p=p, src=src, L=L, ch=ch, sg=sg, line=link.build(ch, sg),
                **strap(n_ch, r))


def do_link(secs=6.0):
    RATE = 32000
    b1 = build_line(1, RATE, secs)      # 4-bit frame, half-rate strap: 128 kbps
    b3 = build_line(3, RATE, secs)      # the committed build: 256 kbps

    hdr('5. FRAMING THE 4-BIT FRAME')
    ok_phase = ok_ber = True
    for k in range(4):
        c, _, st = link.framer(b1['line'], 1, skew=k, **LOF)
        ok_phase &= (st['lock_phase'] == (4 - k % 4) % 4 and not st['false_lock'])
        best = 1.0
        for o in range(400):
            nn = min(len(b1['ch'][0]) - o, len(c[0]))
            if nn < 20000:
                break
            best = min(best, float((c[0][:nn] != b1['ch'][0][o:o + nn]).mean()))
            if best == 0.0:
                break
        ok_ber &= (best == 0.0)
    print(f'  lock to true phase, all 4 skews : {ok_phase}')
    print(f'  bit-exact channel recovery      : {ok_ber}')
    gl = link.build(b1['ch'], b1['sg'], order='grouped')
    gbad = sum(1 for k in range(4)
               if link.framer(gl, 1, skew=k, order='grouped', **LOF)[2]['false_lock'])
    print(f'  grouped-order control           : {gbad}/4 skews false-lock '
          f'(at N=1 the two orderings are the same frame reversed -- no teeth)')

    hdr('6. ACQUISITION')
    for b in (b1, b3):
        ms = [1000.0 * link.framer(b['line'], b['n'], skew=k, **LOF)[2]['lock_bit']
              / b['line_rate'] for k in range(b['flen'])]
        sl = [link.framer(b['line'], b['n'], skew=k, **LOF)[2]['slips']
              for k in range(b['flen'])]
        print(f'  N={b["n"]} at {b["line_rate"]/1e3:.0f} kbps: '
              f'{min(ms):.2f}-{max(ms):.2f} ms (mean {np.mean(ms):.2f}), '
              f'bit slips {min(sl)}-{max(sl)};  '
              f'64 frame periods = {64000/RATE:.2f} ms')

    hdr('7. LOSS OF FRAME, EVERY SLIP SIZE')
    for b in (b1, b3):
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

    hdr('8. SIGNALLING ON THE 4-BIT FRAME  (one channel, idle)')
    sgm = np.zeros((1, b1['L']), np.uint8)
    l1 = link.build(b1['ch'], sgm)
    for ber in (1e-3, 1e-2, 3e-2, 6e-2):
        _, ss, _ = link.framer(link.impair(l1, ber=ber, seed=13), 1, **LOF)
        raw = link.runs_of(ss[0])
        n_as = len(link.runs_of(link.rc_schmitt(ss[0], RATE, tau=2e-3)))
        print(f'  BER {ber:5.0e}: {int(ss[0].sum()):6d} erroneous A bits, longest run '
              f'{(max(raw)/RATE*1000 if len(raw) else 0):.3f} ms, spurious assertions {n_as}')


# ------------------------------------------ 4. what the rate strap does to audio
def do_audio(secs=8.0):
    hdr('9. CVSD RATE VERSUS THE Iabc TRIM')
    print('  step per bit = I*t/C, so the components set SLEW and the bit rate')
    print('  cancels.  A rate strap therefore changes no component on the channel')
    print('  card -- but it does move the optimum trim.  Cost of leaving it alone:\n')
    print(f'  {"CVSD":>6s} {"slew 12000 (untouched)":>24s} {"best slew":>18s} '
          f'{"re-trim buys":>13s}')
    for rate in (16000, 32000, 64000):
        x = load(1, rate, secs)[0]
        res = []
        for slew in (5000., 7000., 9000., 12000., 16000., 20000., 26000.):
            p = cvsd.CVSDParams(rate=rate, slew=slew, **run.BASE)
            y = audio.reconstruct(cvsd.decode(cvsd.encode(x, p), p), rate)
            a, t, _ = audio.align(x, y)
            res.append((slew, audio.seg_snr_db(a, audio.gain_match(a, t), rate)))
        fixed = dict(res)[12000.]
        bs, bv = max(res, key=lambda z: z[1])
        print(f'  {rate//1000:4d}k {fixed:19.2f} dB {bs:10.0f} {bv:6.2f} dB '
              f'{bv-fixed:11.2f} dB')
        print('         sweep: ' + '  '.join(f'{s/1000:.0f}k:{v:.1f}' for s, v in res))


# ------------------------------------------------------------- 5. phy / mis-strap
def lp(x, fc, order, FS):
    b, a = signal.butter(order, min(0.99, 2.0 * fc / FS), btype='low')
    return signal.lfilter(b, a, x)


def line_wave(line, sym, FS, sigma=0.0, fc=None, seed=0):
    fc = fc if fc is not None else 1.7578 * sym
    rng = np.random.default_rng(seed)
    x = np.repeat(fast.dm_encode(line).astype(np.float64) * 2 - 1, OS // 2)
    x = lp(x, fc, 1, FS)
    x /= np.abs(x).max()
    if sigma:
        x += rng.normal(0, sigma, len(x))
    w = fast.slice_hyst(lp(x, sym, 2, FS), 0.05)
    del x
    gc.collect()
    return w


def chan_ber(c, ref, hi=2000):
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


def do_phy(secs=3.0):
    RATE = 32000
    b3 = build_line(3, RATE, secs, mixed_sig=False)
    b1 = build_line(1, RATE, secs, mixed_sig=False)
    FS3, FS1 = RATE * 8 * OS, RATE * 4 * OS

    hdr('10. CABLE BANDWIDTH AT N = 1  (does the requirement track the rate?)')
    FCS = (20e3, 30e3, 40e3, 60e3, 80e3, 125e3)
    r = []
    for fc in FCS:
        w = line_wave(b1['line'], b1['sym'], FS1, fc=fc)
        c, _, st = link.framer(fast.mono_decode(w, OS), 1, skew=3, **LOF)
        r.append(chan_ber(c[0], b1['ch'][0]) if st['frames'] > 300 else 1.0)
        del w
        gc.collect()
    ok = [f for f, e in zip(FCS, r) if e == 0.0]
    print('  cable fc (kHz)   ' + ' '.join(f'{f/1e3:7.0f}' for f in FCS))
    print('  N=1 BER          ' + ' '.join(('  0    ' if e == 0 else f'{e:7.0e}') for e in r))
    print(f'  error-free from {min(ok)/1e3:.0f} kHz = {min(ok)/b1["sym"]:.2f} x symbol rate '
          f'(N=3 and N=7 both give 0.12x)')

    hdr('11. MONOSTABLE WINDOW  (sd = 0.4, the stated design limit)')
    for b, FS in ((b1, FS1), (b3, FS3)):
        w = line_wave(b['line'], b['sym'], FS, sigma=0.4, seed=1)
        win = [t for t in (0.55, 0.60, 0.65, 0.70, 0.75, 0.80, 0.85, 0.90, 0.95)
               if (lambda z: z[2]['frames'] > 300 and chan_ber(z[0][0], b['ch'][0]) < 1e-3)
               (link.framer(fast.mono_decode(w, OS, thr=t), b['n'], skew=3, **LOF))]
        del w
        gc.collect()
        m = min(abs(min(win) - 0.75), abs(max(win) - 0.75)) / 0.75
        cell = 1e9 / b['line_rate']
        print(f'  N={b["n"]} at {b["line_rate"]/1e3:3.0f} kbps: {min(win):.2f}-{max(win):.2f} '
              f'of a cell, +-{m:.0%} about 0.75; cell {cell:.0f} ns -> monostable '
              f'{0.75*cell:.0f} +-{m*0.75*cell:.0f} ns')

    hdr('12. MIS-STRAPPED LINK  (RX monostable RC set for the wrong line rate)')
    print('  TX is the committed build: N=3, 256 kbps, 512 kbaud.')
    print('  The RX monostable is an RC; a wrong strap scales it by 2 either way.\n')
    print('  Levels are what the codec emits WITH THE MUTE DEFEATED (emit_always),')
    print('  the same way spec 8.1 measured the squelch pathology.\n')
    w = line_wave(b3['line'], b3['sym'], FS3, sigma=0.05, seed=1)
    EM = dict(LOF, emit_always=True)
    ref_rms = None
    print(f'  {"RX monostable set for":22s} {"bits out":>9s} {"locked":>7s} '
          f'{"1-run":>7s} {"rms dB":>8s} {"peak dB":>8s}')
    for spb, name in ((OS, '256 kbps (correct)'), (OS * 2, '128 kbps (half)'),
                      (OS // 2, '512 kbps (double)')):
        rb = fast.mono_decode(w, spb)
        c, _, st = link.framer(rb, 3, **EM)
        locked = st['lock_bit'] is not None
        y = audio.reconstruct(cvsd.decode(c[0], b3['p']), RATE) \
            if st['frames'] > 50 else np.zeros(0)
        if ref_rms is None:
            ref_rms = y.std()
        rms = 20 * np.log10(max(y.std(), 1e-12) / ref_rms) if len(y) else float('-inf')
        pk = 20 * np.log10(max(np.abs(y).max(), 1e-12) / ref_rms) if len(y) \
            else float('-inf')
        runs = link.runs_of(rb, 1)
        print(f'  {name:22s} {len(rb):9d} {str(locked):>7s} '
              f'{(runs.mean() if len(runs) else 0):7.1f} {rms:8.1f} {pk:8.1f}')
    del w
    gc.collect()
    print('\n  (bits out is what the monostable emitted; the correct strap emits one')
    print('   per line bit.  1-run is the mean run of 1s -- 1289 bits was the')
    print('   signature of the spec 8.1 pathology, 1.00 is a healthy line.)')


# ------------------------------------------- 6. channel-count strap mismatch
def do_mismatch(secs=4.0):
    RATE = 32000
    hdr('13. CHANNEL-COUNT MIS-STRAP  (clean line, both ends on the same crystal)')
    print('  The rate strap and the channel strap fail differently.  Here the line')
    print('  rate matches and only the frame width is set wrong, so the receiver')
    print('  sees perfectly good biphase and no RC is out of tolerance.\n')

    b3 = build_line(3, RATE, secs, mixed_sig=False)
    b1 = build_line(1, 64000, secs, mixed_sig=False)   # 4-bit frame at 256 kbps
    EM = dict(LOF, emit_always=True)

    # reference level: the correct 3-channel link
    c, _, st = link.framer(b3['line'], 3, **EM)
    ref = audio.reconstruct(cvsd.decode(c[0], b3['p']), RATE)
    ref_rms = ref.std()

    b7 = build_line(7, 16000, secs, mixed_sig=False)   # 16-bit frame at 256 kbps
    for tx, rx, ln, p_dec in (('N=1 (4-bit) ', 3, b1['line'], b3['p']),
                              ('N=3 (8-bit) ', 1, b3['line'], b1['p']),
                              ('N=1 (4-bit) ', 7, b1['line'], b7['p']),
                              ('N=3 (8-bit) ', 7, b3['line'], b7['p']),
                              ('N=7 (16-bit)', 3, b7['line'], b3['p'])):
        c, sg, st = link.framer(ln, rx, **EM)
        print(f'  TX strapped {tx}, RX strapped N={rx}:  '
              f'locked={st["lock_bit"] is not None}, '
              f'lock phase {st["lock_phase"]}, LOF events {st["lof_events"]}, '
              f'{st["frames"]} frames')
        for slot in range(rx if st['lock_bit'] is not None else 1):
            runs = link.runs_of(c[slot], 1)
            y = audio.reconstruct(cvsd.decode(c[slot], p_dec), RATE)
            rms = 20 * np.log10(max(y.std(), 1e-12) / ref_rms)
            pk = 20 * np.log10(max(np.abs(y).max(), 1e-12) / ref_rms)
            const = max(float(c[slot].mean()), 1 - float(c[slot].mean()))
            print(f'      slot {slot+1}: mean 1-run {(runs.mean() if len(runs) else 0):7.1f} '
                  f'bits, {const:5.1%} one value, rms {rms:+6.1f} dB, peak {pk:+6.1f} dB')
        print()

    hdr('14. CAN A STRAPPED FRAMING PATTERN BREAK THE FALSE LOCK?')
    print('  Every frame length in the family is a power of two, so the shorter')
    print('  frame always divides the longer one.  The obvious fix is to give')
    print('  alternate family members (S,T) = (1,0) instead of (0,1) -- one XOR')
    print('  in the S/T path, strapped with the frame width.  Tested, not assumed:\n')

    def st10(line, flen):
        f = line.reshape(-1, flen).copy()
        f[:, flen - 2] = 1
        f[:, flen - 1] = 0
        return f.reshape(-1)

    L = b1['L']
    for hook, nm in ((0, 'ch 1 on-hook '), (1, 'ch 1 off-hook')):
        ln = st10(link.build(b1['ch'], np.full((1, L), hook, np.uint8)), 4)
        for rx in (3, 7):
            st = link.framer(ln, rx, **LOF)[2]
            print(f'  N=1 with (S,T)=(1,0), {nm}, into an N={rx} receiver '
                  f'expecting (0,1): locks={st["lock_bit"] is not None}')

    print('\n  Exhaustive adjacency, both patterns, both hook states.  An alignment')
    print('  is UNGATED if the receiver sees two static bits that match what it is')
    print('  looking for -- that is a lock it can never lose.\n')
    for pat in ((0, 1), (1, 0)):
        for hook in (0, 1):
            for n_ch in (1, 3, 7):
                flen = link.frame_len(n_ch)
                val = {}
                for i in range(n_ch):
                    val[2 * i] = hook          # A bits, static
                    val[2 * i + 1] = None      # C bits, random
                val[flen - 2], val[flen - 1] = pat
                ungated = [k for k in range(1, flen)
                           if val[(flen - 2 + k) % flen] == pat[0]
                           and val[(flen - 1 + k) % flen] == pat[1]]
                print(f'  (S,T)={pat}  A={hook}  N={n_ch}: ungated wrong alignments '
                      f'{len(ungated)} {ungated if ungated else ""}')
            print()


# ---------------------------------- 7. a half-frame monitor that would catch it
def do_monitor(secs=6.0):
    RATE = 32000
    hdr('15. A HALF-FRAME MONITOR  (would it discriminate, and how fast?)')
    print('  A mis-strapped narrow TX presents a valid S/T at the receiver\'s own')
    print('  framing positions AND at the half-frame position.  A genuine stream')
    print('  has the payload there, so it matches only sometimes.  Measured: the')
    print('  longest run of consecutive frames for which the half-frame position')
    print('  reads (0,1) on real speech, worst case (that channel on-hook).\n')
    for n_ch in (3, 7):
        b = build_line(n_ch, RATE, secs, mixed_sig=False)   # all A bits 0 = worst case
        flen = b['flen']
        f = b['line'].reshape(-1, flen)
        h = flen // 2
        good = (f[:, h - 2] == 0) & (f[:, h - 1] == 1)
        runs = link.runs_of(good.astype(np.uint8), 1)
        print(f'  N={n_ch}, genuine stream: half-frame check matches '
              f'{good.mean():.1%} of frames, longest run {int(runs.max())} frames '
              f'({1000*int(runs.max())/RATE:.2f} ms)')
    b1 = build_line(1, 64000, secs, mixed_sig=False)
    for rx in (3, 7):
        c, _, st = link.framer(b1['line'], rx, **dict(LOF, emit_always=True))
        flen = link.frame_len(rx)
        f = b1['line'][:(len(b1['line']) // flen) * flen].reshape(-1, flen)
        h = flen // 2
        good = (f[:, h - 2] == 0) & (f[:, h - 1] == 1)
        print(f'  N=1 TX into an N={rx} receiver: half-frame check matches '
              f'{good.mean():.1%} of frames -- never clears')
    print('\n  Trip at 64 consecutive matches (the acquisition counter already in')
    print('  the design) and the margin is the ratio of those two columns.')


# ------------------------------------------------- 8. the mode list, and merit
def modes_for(osc, nmin=16000, nmax=64000, taps=12):
    """Every (N, r) a board with this crystal can be strapped to, keeping the
    CVSD rate in the useful range and the frame-clock tap on one 74HC4040."""
    out = []
    for n_ch in (1, 3, 7):
        flen = link.frame_len(n_ch)
        k = int(np.log2(flen))
        for r in range(0, 6):
            half = osc / 2 ** (4 + r)     # Q(4+r) is the half-bit clock
            line = half / 2               # Q(5+r) is the line bit clock
            rate = line / flen
            tap = 5 + r + k               # Q(5+r+k) is the frame clock
            if nmin <= rate <= nmax and tap <= taps:
                out.append(dict(n=n_ch, r=r, flen=flen, line=line, rate=rate,
                                tap=tap, sym=2 * line))
    return sorted(out, key=lambda m: (-m['line'], m['n']))


def do_modes():
    SEG = {16000: 10.80, 32000: 17.40, 64000: 23.28}       # family.md 3, 7 talkers
    WORST = {16000: 9.02, 32000: 14.91, 64000: 19.69}
    hdr('16. EVERY MODE ONE RECEIVER BOARD CAN BE STRAPPED TO')
    for osc in (8.192e6, 16.384e6):
        ms = modes_for(osc)
        print(f'\n  crystal {osc/1e6:6.3f} MHz -- {len(ms)} usable modes\n')
        print(f'  {"mode":11s} {"line":>8s} {"baud":>9s} {"CVSD":>6s} {"ch":>3s} '
              f'{"voice":>7s} {"segSNR":>7s} {"worst":>6s} {"cell":>8s} '
              f'{"monostable":>11s} {"Qframe":>7s} {"reach":>6s}')
        for m in ms:
            cell = 1e6 / m['line']
            reach = np.sqrt(256e3 / m['line'])
            print(f'  N={m["n"]} @ {m["rate"]/1e3:2.0f}k {m["line"]/1e3:7.0f}k '
                  f'{m["sym"]/1e6:8.3f}M {m["rate"]/1e3:5.0f}k {m["n"]:3d} '
                  f'{m["n"]*m["rate"]/1e3:6.0f}k {SEG[m["rate"]]:6.1f}dB '
                  f'{WORST[m["rate"]]:5.1f} {cell:7.2f}us {0.75*cell*1000:8.0f}ns '
                  f'Q{m["tap"]:<6d} {reach:5.2f}x')
    print('\n  Modes sharing a line rate share the pair, driver, transformer,')
    print('  protection, slicer, monostable RC and reach: only the frame width')
    print('  and the frame-clock tap differ.  Those are the strap groups.')


def do_robust(secs=4.0):
    """Does a lower rate actually buy robustness, or only reach?"""
    RATE_OF = {1: 64000, 3: 32000, 7: 16000}     # the 256 kbps group
    hdr('17. GRACEFUL DEGRADATION  (the 256 kbps group: one PHY, three straps)')
    print('  Same line, same errors, same reach.  Channel 1 only.\n')
    print(f'  {"mode":12s} {"clean":>8s} {"1e-4":>8s} {"1e-3":>8s} '
          f'{"3e-3":>8s} {"1e-2":>8s} {"3e-2":>8s}   LOF events')
    for n_ch in (1, 3, 7):
        rate = RATE_OF[n_ch]
        b = build_line(n_ch, rate, secs, slew=run.SLEW[rate], mixed_sig=False)
        row, lofs = [], []
        for ber in (0, 1e-4, 1e-3, 3e-3, 1e-2, 3e-2):
            c, _, st = link.framer(link.impair(b['line'], ber=ber, seed=7), n_ch,
                                   **dict(LOF, emit_always=True))
            if st['frames'] < 100:
                row.append(float('nan'))
                lofs.append(st['lof_events'])
                continue
            y = audio.reconstruct(cvsd.decode(c[0], b['p']), rate)
            a, t, _ = audio.align(b['src'][0], y)
            row.append(audio.seg_snr_db(a, audio.gain_match(a, t), rate))
            lofs.append(st['lof_events'])
        print(f'  N={n_ch} @ {rate//1000:2d}k   ' +
              ' '.join(f'{v:6.2f}dB' for v in row) + f'   {lofs}')

    hdr('18. COLD-START ACQUISITION UNDER ERRORS  (can it even get in?)')
    print('  64 consecutive good frames, and any bad frame slips a bit and')
    print('  restarts.  P(good frame) = (1-p)^2 at every N, so what differs is')
    print('  how long an attempt takes: 64 frames, and a frame is flen bits.\n')
    BERS = (1e-3, 3e-3, 1e-2, 2e-2, 3e-2, 5e-2)
    print(f'  {"mode":12s} {"frame":>7s} ' + ' '.join(f'{b:>9.0e}' for b in BERS))
    for n_ch in (1, 3, 7):
        rate = RATE_OF[n_ch]
        b = build_line(n_ch, rate, secs, slew=run.SLEW[rate], mixed_sig=False)
        cells = []
        for ber in BERS:
            ts = []
            for seed in (11, 12, 13):
                st = link.framer(link.impair(b['line'], ber=ber, seed=seed),
                                 n_ch, skew=3, **LOF)[2]
                ts.append(1000.0 * st['lock_bit'] / b['line_rate']
                          if st['lock_bit'] is not None else float('nan'))
            cells.append(np.nanmean(ts) if not all(np.isnan(ts)) else float('nan'))
        print(f'  N={n_ch} @ {rate//1000:2d}k   {b["flen"]:4d}b  ' +
              ' '.join(('     none' if np.isnan(v) else f'{v:8.2f}m') for v in cells))
    print('\n  (mean lock time in ms over 3 error seeds; "none" = never locked in')
    print(f'   the {secs:.0f} s clip.  Tracking survives far past acquisition -- see')
    print('   spec 9 -- so this is the cold-start ceiling, not the link ceiling.)')


# --------------------------------------------- 9. the 512 kbps group, measured
def do_fastgroup(secs=2.5):
    """N=3 @ 64k and N=7 @ 32k are the SAME waveform on the wire: 512 kbps,
    1.024 Mbaud, 16.384 MHz master.  Only the frame width and the codec rate
    differ.  n7.py measured the N=7 @ 32k member end to end; N=3 @ 64k has
    never been run, and the codec has never been run at 64 kbps over a link."""
    hdr('19. THE 512 kbps GROUP  (16.384 MHz crystal, 1.024 Mbaud)')
    MODES = ((3, 64000), (7, 32000))
    OSFS = 512_000 * OS                 # 16.384 MHz, the real master clock

    print('  Identical on the wire:')
    for n_ch, rate in MODES:
        c = dict(line=rate * link.frame_len(n_ch))
        print(f'    N={n_ch} @ {rate//1000}k -> line {c["line"]/1e3:.0f} kbps, '
              f'{2*c["line"]/1e6:.3f} Mbaud, cell {1e6/c["line"]:.2f} us, '
              f'monostable {0.75e9/c["line"]:.0f} ns')

    hdr('19.1 LINK LAYER AT N = 3 @ 64 kbps  (the member never run)')
    b = build_line(3, 64000, 4.0, slew=run.SLEW[64000], mixed_sig=True)
    ok_phase = ok_ber = True
    for k in range(8):
        c, _, st = link.framer(b['line'], 3, skew=k, **LOF)
        ok_phase &= (st['lock_phase'] == (8 - k % 8) % 8 and not st['false_lock'])
        best = 1.0
        for o in range(400):
            nn = min(len(b['ch'][0]) - o, len(c[0]))
            if nn < 20000:
                break
            best = min(best, float((c[0][:nn] != b['ch'][0][o:o + nn]).mean()))
            if best == 0.0:
                break
        ok_ber &= (best == 0.0)
    ms = [1000.0 * link.framer(b['line'], 3, skew=k, **LOF)[2]['lock_bit'] / b['line_rate']
          for k in range(8)]
    ln = link.build(b['ch'], np.zeros((3, b['L']), np.uint8))
    at = (b['L'] // 2) * 8
    worst = 0.0
    for k in range(1, 8):
        st = link.framer(link.slip(ln, at, n=k), 3, **LOF)[2]
        pos = st['pos']
        tp = np.where(pos < at, pos % 8, (pos + k) % 8)
        worst = max(worst, 1000 * int((tp != tp[0]).sum()) / 64000)
    fr = [link.framer(link.impair(ln, ber=x, seed=5), 3, **LOF)[2]['lof_events']
          for x in (1e-3, 1e-2, 3e-2)]
    print(f'  lock to true phase, all 8 skews : {ok_phase}')
    print(f'  bit-exact channel recovery      : {ok_ber}')
    print(f'  acquisition                     : {min(ms):.2f}-{max(ms):.2f} ms '
          f'(64 frame periods = {64000/64000:.2f} ms)')
    print(f'  worst LOF detection, all 7 slips: {worst:.2f} ms')
    print(f'  false reframes @ 1e-3/1e-2/3e-2 : {fr}')

    hdr('19.2 THROUGH THE FULL CHAIN AT 1.024 Mbaud')
    print(f'  {"mode":12s} {"codec alone":>12s} {"over the link":>14s} {"delta":>8s} '
          f'{"clean BER":>10s}')
    for n_ch, rate in MODES:
        b = build_line(n_ch, rate, secs, slew=run.SLEW[rate], mixed_sig=True)
        w = line_wave(b['line'], b['sym'], OSFS)
        c, _, st = link.framer(fast.mono_decode(w, OS), n_ch, skew=3, **LOF)
        del w
        gc.collect()
        ber = chan_ber(c[0], b['ch'][0]) if st['frames'] > 300 else 1.0
        y = audio.reconstruct(cvsd.decode(c[0], b['p']), rate)
        solo = audio.reconstruct(cvsd.decode(cvsd.encode(b['src'][0], b['p']), b['p']), rate)
        a1, x1, _ = audio.align(b['src'][0], solo)
        s1 = audio.seg_snr_db(a1, audio.gain_match(a1, x1), rate)
        a2, x2, _ = audio.align(b['src'][0], y)
        s2 = audio.seg_snr_db(a2, audio.gain_match(a2, x2), rate)
        print(f'  N={n_ch} @ {rate//1000:2d}k    {s1:9.2f} dB {s2:11.2f} dB '
              f'{s2-s1:+7.2f} {ber:10.1e}')
        del b
        gc.collect()

    hdr('19.3 RECEIVER MARGIN ON THE SHARED PHY')
    for n_ch, rate in MODES:
        b = build_line(n_ch, rate, secs, slew=run.SLEW[rate], mixed_sig=True)
        res = []
        for sigma in (0.4, 0.5, 0.6, 0.7):
            w = line_wave(b['line'], b['sym'], OSFS, sigma=sigma, seed=1)
            c, _, st = link.framer(fast.mono_decode(w, OS), n_ch, skew=3, **LOF)
            res.append((sigma, chan_ber(c[0], b['ch'][0]) if st['frames'] > 300 else 1.0))
            del w
            gc.collect()
        w = line_wave(b['line'], b['sym'], OSFS, sigma=0.4, seed=1)
        win = [t for t in (0.55, 0.60, 0.65, 0.70, 0.75, 0.80, 0.85, 0.90, 0.95)
               if (lambda z: z[2]['frames'] > 300 and chan_ber(z[0][0], b['ch'][0]) < 1e-3)
               (link.framer(fast.mono_decode(w, OS, thr=t), n_ch, skew=3, **LOF))]
        del w
        gc.collect()
        m = min(abs(min(win) - 0.75), abs(max(win) - 0.75)) / 0.75 if win else 0
        clean = [s for s, e in res if e == 0.0]
        print(f'  N={n_ch} @ {rate//1000:2d}k: error-free to sd = '
              f'{(max(clean) if clean else 0):.1f}   '
              + ' '.join(f'{s:.1f}:{"ok" if e==0 else f"{e:.0e}"}' for s, e in res)
              + f'   window {min(win):.2f}-{max(win):.2f} (+-{m:.0%}), '
                f'{0.75*1e9/b["line_rate"]:.0f} +-{m*0.75e9/b["line_rate"]:.0f} ns')
        del b
        gc.collect()

    hdr('19.4 WHAT THE TWO MODES COST IN HARDWARE')
    print(f'  {"":26s} {"N=3 @ 64k":>12s} {"N=7 @ 32k":>12s} {"N=3 @ 32k (committed)":>22s}')
    rows = [('line rate', '512 kbps', '512 kbps', '256 kbps'),
            ('symbol rate', '1.024 Mbaud', '1.024 Mbaud', '512 kbaud'),
            ('oscillator', '16.384 MHz', '16.384 MHz', '8.192 MHz'),
            ('frame clock tap', 'Q8', 'Q9', 'Q8'),
            ('ripple Q1->Qframe', '~100 ns', '~110 ns', '~100 ns'),
            ('half-cell', '977 ns', '977 ns', '1953 ns'),
            ('150 ns edge', '15.4%', '15.4%', '7.7%'),
            ('payload mux', '1 x 74HC151', '2 x 74HC151', '1 x 74HC151'),
            ('S/T select', '2-input AND', '3-input AND', '2-input AND'),
            ('TX packages', '~6', '7-8', '~6'),
            ('channels', '3', '7', '3'),
            ('segSNR/ch (7 talkers)', '23.28 dB', '17.40 dB', '17.40 dB'),
            ('estimated reach', '1.2 km', '1.2 km', '1.7 km')]
    for r in rows:
        print(f'  {r[0]:26s} {r[1]:>12s} {r[2]:>12s} {r[3]:>22s}')


# ------------------------------------------ 10. why is the crystal so fast?
def do_crystal():
    """The fastest signal the transmitter generates is the half-bit clock, which
    IS the baud rate, and the receiver has no clock at all.  So what sets the
    crystal-to-half-bit ratio?  Nothing but which crystals exist."""
    hdr('20. WHAT ACTUALLY NEEDS THE CRYSTAL FREQUENCY')
    print('  Every clocked node on the transmitter card, committed build:\n')
    for name, f in (('crystal', 8.192e6), ('Q1', 4.096e6), ('Q2', 2.048e6),
                    ('Q3', 1.024e6), ('Q4 half-bit clock', 512e3),
                    ('Q5 line bit clock / H', 256e3), ('Q6:Q8 frame counter', 256e3),
                    ('Q8 frame clock', 32e3), ('biphase JK', 512e3)):
        need = {'Q4 half-bit clock': 'the biphase T flip-flop and the H divider',
                'Q5 line bit clock / H': 'half-cell phase into the encoder NAND',
                'Q6:Q8 frame counter': 'mux address and S/T select',
                'Q8 frame clock': 'CVSD clock to the channel cards',
                'biphase JK': 'the line output itself'}.get(name, '')
        print(f'    {name:24s} {f/1e6:8.3f} MHz   {need}')
    print('\n  The fastest node with a JOB is the half-bit clock at 512 kHz.')
    print('  Q1-Q3 exist only to get from the crystal down to it.')

    hdr('21. WHICH CRYSTALS REACH WHICH MODES')
    print('  half-bit clock = baud rate = 2 x line rate; it must be crystal/2^a')
    print('  with a >= 1 (a raw Pierce output is not 50% duty, and the divider')
    print('  chain wants a clean edge).  Frame clock tap = Q(a+1+log2 flen).\n')
    cands = (1.024e6, 2.048e6, 4.096e6, 8.192e6, 16.384e6)
    want = [(3, 32000), (1, 64000), (7, 16000), (3, 16000), (1, 32000),
            (1, 16000), (3, 64000), (7, 32000)]
    print(f'  {"crystal":>10s} {"modes":>6s} {"top tap":>8s} {"half-bit tap":>13s}  '
          f'{"reaches 512 kbps group":>22s}')
    for f in cands:
        ok, taps, halftaps, fast_ok = [], [], [], False
        for n_ch, rate in want:
            flen = link.frame_len(n_ch)
            k = int(np.log2(flen))
            h = 2.0 * rate * flen                 # half-bit clock = baud
            a = np.log2(f / h)
            if abs(a - round(a)) > 1e-9 or round(a) < 1:
                continue
            a = int(round(a))
            tap = a + 1 + k
            if tap > 12:
                continue
            ok.append((n_ch, rate))
            taps.append(tap)
            halftaps.append(a)
            fast_ok |= (rate * flen == 512000)
        print(f'  {f/1e6:8.3f}M {len(ok):6d} {("Q"+str(max(taps))) if taps else "-":>8s} '
              f'{("Q"+str(min(halftaps))) if halftaps else "-":>13s}  '
              f'{str(fast_ok):>22s}')

    hdr('22. WHAT THE COMMITTED CHOICE COSTS')
    print('  The skews that matter are all BELOW the half-bit clock and are the')
    print('  same at every crystal: within the frame counter (log2 flen stages,')
    print('  what S/T select and the mux address decode across) and half-bit to')
    print('  frame counter.  The extra stages a fast crystal adds sit ABOVE the')
    print('  half-bit clock, and nothing decodes across them.  So ripple is NOT')
    print('  an argument either way -- only frequency and current are.\n')
    print(f'  {"crystal":>10s} {"top node":>10s} {"stages above":>13s} '
          f'{"frame-counter skew":>19s} {"clock-chain MHz":>16s}')
    for f in (2.048e6, 4.096e6, 8.192e6, 16.384e6):
        a = int(round(np.log2(f / 512e3)))         # to the committed 512 kHz half-bit
        if a < 1:
            continue
        load = sum(f / 2 ** i for i in range(a + 1)) / 1e6
        print(f'  {f/1e6:8.3f}M {f/1e6:8.3f}M {a:13d} {12.0*3:16.0f} ns '
              f'{load:15.2f}')
    print('\n  ("stages above" is how many flip-flops run faster than the half-bit')
    print('   clock.  Clock-chain MHz is the sum of toggling frequencies at and')
    print('   above the half-bit clock -- what CMOS CV^2f actually charges.)')


# ------------------------------- 11. every mode off ONE clock chain, tap by tap
def tapmap(osc, n_ch, rate):
    """Exact tap assignment for one mode on a single ripple chain from `osc`.
    Matches line-transmitter.md 4 at 8.192 MHz / N=3 / 32k: Q4 Q5 Q6:Q8 Q8."""
    flen = link.frame_len(n_ch)
    k = int(np.log2(flen))
    half = 2.0 * rate * flen                  # half-bit clock == baud rate
    a = np.log2(osc / half)
    if abs(a - round(a)) > 1e-9 or round(a) < 1:
        return None
    a = int(round(a))
    return dict(n=n_ch, rate=rate, flen=flen, k=k, line=rate * flen, half=half,
                a=a, q_half=a, q_line=a + 1, q_lsb=a + 2, q_frame=a + 1 + k,
                mask=(1 << k) - 1, mono=0.75e9 / (rate * flen))


WANT = [(3, 64000), (7, 32000), (1, 64000), (3, 32000), (7, 16000),
        (1, 32000), (3, 16000), (1, 16000)]


def do_tapmap(osc=2.048e6):
    hdr(f'23. EVERY MODE OFF ONE {osc/1e6:.3f} MHz CHAIN')
    ms = [m for m in (tapmap(osc, n, r) for n, r in WANT) if m]
    rates = sorted({m['line'] for m in ms}, reverse=True)
    print(f'  {"mode":10s} {"line":>7s} {"baud":>9s} | {"r":>1s} {"half-bit":>12s} '
          f'{"H":>4s} {"frame ctr":>10s} {"f.clk":>6s} {"=":>7s} | '
          f'{"mask":>4s} {"monostable":>11s}')
    for lr in rates:
        for m in [x for x in ms if x['line'] == lr]:
            star = '   <-- committed' if (m['n'], m['rate']) == (3, 32000) else ''
            print(f'  N={m["n"]} @ {m["rate"]//1000:2d}k {m["line"]/1e3:6.0f}k '
                  f'{2*m["line"]/1e6:8.3f}M | {m["a"]-1:1d} '
                  f'Q{m["q_half"]:<2d}{m["half"]/1e6:7.3f}M  Q{m["q_line"]:<3d}'
                  f'Q{m["q_lsb"]}:Q{m["q_frame"]:<7} Q{m["q_frame"]:<5d}'
                  f'{m["rate"]/1e3:5.0f}k | 0x{m["mask"]:X}  {m["mono"]:8.0f} ns'
                  + star)
        print()
    top = max(m['q_frame'] for m in ms)
    print(f'  Highest tap used: Q{top}.  A 74HC4040 has 12 stages; the whole family')
    print(f'  fits in {top}, which is also a 74HC4024 (7-stage, 14-pin).')

    hdr('24. THE SAME MAP ON THE COMMITTED 8.192 MHz CRYSTAL')
    ms8 = [m for m in (tapmap(8.192e6, n, r) for n, r in WANT) if m]
    for m in ms8:
        print(f'  N={m["n"]} @ {m["rate"]//1000:2d}k  line {m["line"]/1e3:6.0f}k  '
              f'half-bit Q{m["q_half"]} ({m["half"]/1e6:.3f} MHz), H Q{m["q_line"]}, '
              f'frame counter Q{m["q_lsb"]}:Q{m["q_frame"]}, frame clock Q{m["q_frame"]}')
    print(f'\n  Highest tap Q{max(m["q_frame"] for m in ms8)} of 12 -- also fits, but every '
          f'tap is two higher and\n  three flip-flops run above the half-bit clock '
          f'instead of one.')

    hdr('25. WHAT A STRAPPABLE CLOCK CHAIN COSTS IN PACKAGES')
    for ln in [
        'The two straps move different things, and that decides the topology.',
        '',
        'The rate strap moves WHICH TAP is the half-bit clock, so on a single',
        'ripple chain it also moves where the frame counter sits -- the counter',
        'LSB is Q(a+2).  Muxing k moving taps is expensive.  Re-clocking is not:',
        'give the frame counter its own package fed by the selected line-bit',
        'clock and its bits sit on fixed pins at every strap.',
        '',
        '  crystal -> [prescaler, 4 stages] -> 4:1 mux -> half-bit clock',
        '                                    (rate strap)      |',
        '                                                     ./2 -> H',
        '                                                      |',
        '                          [frame counter, 4 stages] -> 4:1 mux -> frame clock',
        '                                    |              (channel strap)',
        "                                  mask -> mux addr, S/T select, '259 addr",
        '',
        '  one fixed mode (committed)     1 package    74HC4040, taps only',
        '  channel strap only             ~1.5         4040 + half a 74HC153 + gates',
        '  both straps, all 8 modes       3            4024 + 74HC393 + 74HC153',
        '',
        'Two extra packages on the TX card and two on the RX card buys the whole',
        'table.  The frame content is unaffected: section 3 verified the generator',
        'against link.build() from the counter VALUE alone, and re-clocking a',
        'counter does not change what it counts.']:
        print('  ' + ln)


# --------------------------- 12. the full 3x3 grid, strapped on line rate x N
GRID = [(n, r) for n in (1, 3, 7) for r in (16000, 32000, 64000)]


def do_grid(osc=4.096e6):
    hdr(f'26. THE 3 x 3 GRID OFF ONE {osc/1e6:.3f} MHz CRYSTAL')
    print('  Strap on LINE RATE and CHANNEL COUNT, not on codec rate.  Line')
    print('  conditions set one, local needs set the other, and the codec rate')
    print('  falls out as line / frame length.  The two selectors are then')
    print('  independent -- which they are not if you strap on the codec rate.\n')
    ms = []
    for n_ch, rate in GRID:
        m = tapmap(osc, n_ch, rate)
        if m is None:
            print(f'  N={n_ch} @ {rate//1000}k: NOT REACHABLE from this crystal')
            continue
        ms.append(m)
    print(f'  {"mode":11s} {"line":>7s} {"baud":>9s} {"half-bit":>14s} {"H":>4s} '
          f'{"frame ctr":>10s} {"f.clk":>6s} {"mask":>5s} {"mono":>9s} {"reach":>6s}')
    for m in sorted(ms, key=lambda x: (-x['line'], x['n'])):
        star = '  <-- committed' if (m['n'], m['rate']) == (3, 32000) else ''
        print(f'  N={m["n"]} @ {m["rate"]//1000:2d}k {m["line"]/1e3:6.0f}k '
              f'{2*m["line"]/1e6:8.3f}M  Q{m["q_half"]:<2d}{m["half"]/1e6:8.3f}M '
              f'Q{m["q_line"]:<3d} Q{m["q_lsb"]}:Q{m["q_frame"]:<6} Q{m["q_frame"]:<5d} '
              f'0x{m["mask"]:X}  {m["mono"]:7.0f}ns {np.sqrt(256e3/m["line"]):5.2f}x'
              + star)
    print(f'\n  Taps used: Q{min(m["q_half"] for m in ms)}..Q{max(m["q_frame"] for m in ms)} '
          f'-- one 74HC4040 with {12-max(m["q_frame"] for m in ms)} stages spare.')

    hdr('27. THE TWO STRAP FIELDS ARE INDEPENDENT')
    print('  Rate strap picks the half-bit tap from the LINE RATE alone:\n')
    for line in (1024e3, 512e3, 256e3, 128e3, 64e3):
        a = int(round(np.log2(osc / (2 * line))))
        print(f'    line {line/1e3:5.0f} kbps -> half-bit {2*line/1e6:6.3f} MHz = '
              f'Q{a},  H = Q{a+1},  monostable {0.75e9/line:6.0f} ns')
    print('\n  Channel strap picks the mask and which frame-counter stage is the')
    print('  frame clock, from N alone:\n')
    for n_ch in (1, 3, 7):
        k = int(np.log2(link.frame_len(n_ch)))
        print(f'    N={n_ch} -> {2+2*n_ch:2d}-bit frame, mask 0x{(1<<k)-1:X}, '
              f'frame clock = counter stage {k}, S/T select = AND of {k-1} bit(s)')

    hdr('28. THE STRAP MATRIX  (5 line rates x 3 channel counts)')
    print(f'  {"line":>8s} ' + ' '.join(f'{"N="+str(n):>14s}' for n in (1, 3, 7)))
    for line in (1024e3, 512e3, 256e3, 128e3, 64e3):
        cells = []
        for n_ch in (1, 3, 7):
            cr = line / link.frame_len(n_ch)
            if cr > 64000:
                cells.append('-- above 64k')
            elif cr < 16000:
                cells.append('-- below 16k')
            else:
                cells.append(f'{cr/1e3:.0f} kbps')
        print(f'  {line/1e3:6.0f}k  ' + ' '.join(f'{c:>14s}' for c in cells))
    print('\n  Nine valid settings of fifteen.  The six others are not hazardous --')
    print('  they produce a working link with a codec outside its characterised')
    print('  range, silly rather than dangerous.  Contrast section 13, where the')
    print('  two ENDS disagree: that one locks and is dangerous.')


# ------------------------------------ 13. the new corner: N=7 @ 64k, 2.048 Mbaud
def do_corner(secs=1.5):
    """The 3x3 grid adds one mode no document has ever simulated: N=7 @ 64 kbps,
    1024 kbps line, 2.048 Mbaud, 488 ns half-cell.  family.md 6 calls it past
    the practical corner on analysis alone.  Measure it."""
    hdr('29. THE NEW CORNER: N = 7 @ 64 kbps, 2.048 Mbaud')
    n_ch, rate = 7, 64000
    b = build_line(n_ch, rate, secs, slew=run.SLEW[rate], mixed_sig=True)
    FS = b['line_rate'] * OS                       # 32.768 MHz
    print(f'  line {b["line_rate"]/1e3:.0f} kbps, {b["sym"]/1e6:.3f} Mbaud, '
          f'cell {1e9/b["line_rate"]:.0f} ns, half-cell {1e9/b["sym"]:.0f} ns, '
          f'monostable {0.75e9/b["line_rate"]:.0f} ns')
    print(f'  simulation at OS={OS} is {FS/1e6:.3f} MHz\n')

    c, _, st = link.framer(b['line'], n_ch, skew=5, **LOF)
    ms = [1000.0 * link.framer(b['line'], n_ch, skew=k, **LOF)[2]['lock_bit']
          / b['line_rate'] for k in range(16)]
    ok = all(not link.framer(b['line'], n_ch, skew=k, **LOF)[2]['false_lock']
             for k in range(16))
    print(f'  link layer: lock to true phase all 16 skews {ok}, '
          f'acquisition {min(ms):.2f}-{max(ms):.2f} ms')

    w = line_wave(b['line'], b['sym'], FS)
    c, _, st = link.framer(fast.mono_decode(w, OS), n_ch, skew=3, **LOF)
    del w
    gc.collect()
    ber = chan_ber(c[0], b['ch'][0]) if st['frames'] > 300 else 1.0
    y = audio.reconstruct(cvsd.decode(c[0], b['p']), rate)
    solo = audio.reconstruct(cvsd.decode(cvsd.encode(b['src'][0], b['p']), b['p']), rate)
    a1, x1, _ = audio.align(b['src'][0], solo)
    s1 = audio.seg_snr_db(a1, audio.gain_match(a1, x1), rate)
    a2, x2, _ = audio.align(b['src'][0], y)
    s2 = audio.seg_snr_db(a2, audio.gain_match(a2, x2), rate)
    print(f'  full chain: clean BER {ber:.1e}, codec alone {s1:.2f} dB, '
          f'over the link {s2:.2f} dB, delta {s2-s1:+.2f} dB')

    res = []
    for sigma in (0.4, 0.5, 0.6, 0.7):
        w = line_wave(b['line'], b['sym'], FS, sigma=sigma, seed=1)
        c2, _, st2 = link.framer(fast.mono_decode(w, OS), n_ch, skew=3, **LOF)
        res.append((sigma, chan_ber(c2[0], b['ch'][0]) if st2['frames'] > 300 else 1.0))
        del w
        gc.collect()
    clean = [s for s, e in res if e == 0.0]
    print(f'  noise margin: error-free to sd = {(max(clean) if clean else 0):.1f}   '
          + ' '.join(f'{s:.1f}:{"ok" if e==0 else f"{e:.0e}"}' for s, e in res))

    w = line_wave(b['line'], b['sym'], FS, sigma=0.4, seed=1)
    win = [t for t in (0.55, 0.60, 0.65, 0.70, 0.75, 0.80, 0.85, 0.90, 0.95)
           if (lambda z: z[2]['frames'] > 300 and chan_ber(z[0][0], b['ch'][0]) < 1e-3)
           (link.framer(fast.mono_decode(w, OS, thr=t), n_ch, skew=3, **LOF))]
    del w
    gc.collect()
    m = min(abs(min(win) - 0.75), abs(max(win) - 0.75)) / 0.75 if win else 0
    cell = 1e9 / b['line_rate']
    print(f'  monostable window: {min(win):.2f}-{max(win):.2f} of a cell, +-{m:.0%}, '
          f'{0.75*cell:.0f} +-{m*0.75*cell:.0f} ns')
    print(f'\n  Edge rate: the 150 ns specified for 256 kbps is '
          f'{150/(1e9/b["sym"]):.0%} of this half-cell.')
    print(f'  At 75 ns it is {75/(1e9/b["sym"]):.0%}.  This is the mode where the')
    print('  output stage has to be re-specified rather than inherited.')


# ------------------------------------- 14. all nine modes under noise, two ways
def ber_small(c, ref, probe=15000, hi=800):
    best = 1.0
    bo = None
    for o in range(hi):
        if o + probe > len(ref) or probe > len(c):
            break
        e = float((c[:probe] != ref[o:o + probe]).mean())
        if e < best:
            bo, best = o, e
        if best == 0.0:
            break
    if bo is None:
        return 1.0
    n = min(len(ref) - bo, len(c))
    return float((c[:n] != ref[bo:bo + n]).mean())


def do_noise(secs=1.2):
    """Two different questions, routinely conflated.

    (a) RELATIVE margin: cable bandwidth and noise scaled with the symbol rate,
        the convention n7.py and validate.py use.  Asks 'is any mode intrinsically
        worse?'  Every mode should look the same.

    (b) ABSOLUTE margin: ONE physical cable, ONE noise floor, each receiver
        filtering at its own symbol rate -- the compare.py fairness rules.
        Asks 'on the pair I actually have, which mode survives?'  This is the
        one that decides a strap setting, and it has never been run.
    """
    SIG = (0.3, 0.4, 0.5, 0.6, 0.7, 0.8)
    ms = []
    for n_ch, rate in GRID:
        m = tapmap(4.096e6, n_ch, rate)
        if m:
            ms.append((n_ch, rate, m['line']))
    ms.sort(key=lambda x: -x[2])

    hdr('30. (a) RELATIVE MARGIN  (cable and noise scaled with the symbol rate)')
    print(f'  {"mode":11s} {"line":>7s} ' + ' '.join(f'{s:>6.1f}' for s in SIG)
          + '   error-free to')
    for n_ch, rate, line in ms:
        b = build_line(n_ch, rate, secs, slew=run.SLEW[rate], mixed_sig=False)
        FS = line * OS
        row = []
        for sigma in SIG:
            w = line_wave(b['line'], b['sym'], FS, sigma=sigma, seed=1)
            c, _, st = link.framer(fast.mono_decode(w, OS), n_ch, skew=3, **LOF)
            row.append(ber_small(c[0], b['ch'][0]) if st['frames'] > 200 else 1.0)
            del w
            gc.collect()
        clean = [s for s, e in zip(SIG, row) if e == 0.0]
        print(f'  N={n_ch} @ {rate//1000:2d}k {line/1e3:6.0f}k ' +
              ' '.join(('    ok' if e == 0 else f'{e:6.0e}') for e in row) +
              f'   sd = {(max(clean) if clean else 0):.1f}')
        del b
        gc.collect()

    hdr('31. (b) ABSOLUTE MARGIN  (one cable, one noise floor, 1.0 MHz 3 dB)')
    print('  Simulated at a common 32.768 MHz so a given sd is the same noise')
    print('  power spectral density for every mode.  Each receiver low-passes at')
    print('  its OWN symbol rate, which is what makes a slower mode quieter.\n')
    FSC, FCC = 32.768e6, 1.0e6
    SIG2 = (0.4, 0.6, 0.8, 1.0, 1.4, 2.0, 2.8)
    print(f'  {"mode":11s} {"line":>7s} {"baud":>8s} ' +
          ' '.join(f'{s:>6.1f}' for s in SIG2) + '   error-free to')
    res = {}
    for n_ch, rate, line in ms:
        b = build_line(n_ch, rate, secs, slew=run.SLEW[rate], mixed_sig=False)
        spb = FSC / line                       # samples per line bit
        row = []
        for sigma in SIG2:
            rng = np.random.default_rng(1)
            x = np.repeat(fast.dm_encode(b['line']).astype(np.float64) * 2 - 1,
                          int(spb // 2))
            x = lp(x, FCC, 1, FSC)             # ONE cable, absolute Hz
            x /= np.abs(x).max()
            x += rng.normal(0, sigma, len(x))  # ONE noise floor, same PSD
            w = fast.slice_hyst(lp(x, b['sym'], 2, FSC), 0.05)   # own symbol rate
            del x
            gc.collect()
            c, _, st = link.framer(fast.mono_decode(w, spb), n_ch, skew=3, **LOF)
            row.append(ber_small(c[0], b['ch'][0]) if st['frames'] > 200 else 1.0)
            del w
            gc.collect()
        clean = [s for s, e in zip(SIG2, row) if e == 0.0]
        lim = max(clean) if clean else 0
        res[(n_ch, rate)] = lim
        print(f'  N={n_ch} @ {rate//1000:2d}k {line/1e3:6.0f}k {b["sym"]/1e6:7.3f}M ' +
              ' '.join(('    ok' if e == 0 else f'{e:6.0e}') for e in row) +
              f'   sd = {lim:.1f}')
        del b
        gc.collect()
    base = res.get((3, 32000), 1.0)
    print(f'\n  Relative to the committed build (sd = {base:.1f}), in dB of tolerable')
    print('  noise:  ' + ',  '.join(
        f'N={n}@{r//1000}k {20*np.log10(v/base):+.1f} dB'
        for (n, r), v in sorted(res.items(), key=lambda kv: -kv[1])))


# ------------------------------- 15. if the codec rate is fixed at 64k: PCM?
def pack8(codes):
    """One 8-bit sample per 8 frames, MSB first -- one C-bit slot at 64 kbps
    carries a 64 kbps PCM channel with no bonding at all."""
    c = codes.astype(np.uint8)
    return np.stack([(c >> (7 - f)) & 1 for f in range(8)], 1).reshape(-1).astype(np.uint8)


def unpack8(bits, phase=0):
    b = bits[phase:]
    n = len(b) // 8 * 8
    g = b[:n].reshape(-1, 8).astype(np.uint8)
    out = np.zeros(n // 8, np.uint8)
    for f in range(8):
        out |= g[:, f] << (7 - f)
    return out


def do_pcm(secs=8.0):
    import g711
    hdr('32. AT A FIXED 64 kbps PER CHANNEL, IS PCM AN OPTION?')
    print('  The rate arithmetic is exact and needs no bonding: one C-bit slot at')
    print('  64 kbps is 8 kHz x 8 bits.  One slot, one PCM channel.  What that')
    print('  costs is a SAMPLE BOUNDARY, which CVSD does not have.\n')

    x8, fs = audio.read_wav('speech30.wav', seconds=secs)
    x8 = audio.bandlimit(x8, fs)
    x8 = x8 * (run.NOMINAL_RMS / x8.std())
    x8 = audio.resample_to(x8, fs, 8000)
    x64 = audio.resample_to(x8, 8000, 64000)
    p64 = cvsd.CVSDParams(rate=64000, slew=run.SLEW[64000], **run.BASE)

    def score8(ref, test):
        a, t, _ = audio.align(ref, test)
        return audio.seg_snr_db(a, audio.gain_match(a, t), 8000)

    hdr('32.1 CLEAN, AND UNDER LINE ERRORS')
    print(f'  {"BER":>8s} {"mu-law PCM":>12s} {"A-law PCM":>12s} {"CVSD 64k":>11s}'
          f'  {"PCM advantage":>14s}')
    for ber in (0.0, 1e-5, 1e-4, 1e-3, 3e-3, 1e-2):
        row = []
        for nm in ('ulaw', 'alaw'):
            enc, dec = g711.CODECS[nm]
            bits = pack8(enc(x8))
            bits = link.impair(bits, ber=ber, seed=4) if ber else bits
            y = dec(unpack8(bits))
            row.append(score8(x8, audio.reconstruct(y, 8000)))
        cb = cvsd.encode(x64, p64)
        cb = link.impair(cb, ber=ber, seed=4) if ber else cb
        yc = audio.resample_to(audio.reconstruct(cvsd.decode(cb, p64), 64000), 64000, 8000)
        sc = score8(x8, yc)
        print(f'  {ber:8.0e} {row[0]:9.2f} dB {row[1]:9.2f} dB {sc:8.2f} dB'
              f'  {row[0]-sc:+11.2f} dB')

    hdr('32.2 WHY -- WHICH BIT THE ERROR LANDS IN')
    enc, dec = g711.CODECS['ulaw']
    codes = enc(x8)
    clean = dec(codes)
    print(f'  {"bit":>5s} {"weight":>8s} {"segSNR with that bit flipped at 1e-3":>38s}')
    for bit in range(8):
        rng = np.random.default_rng(9)
        c2 = codes.copy()
        hit = rng.random(len(c2)) < 1e-3 * 8       # same total error rate, one bit
        c2[hit] ^= (1 << (7 - bit))
        y = dec(c2)
        print(f'  {bit:5d} {"MSB" if bit==0 else ("LSB" if bit==7 else f"2^{7-bit}"):>8s} '
              f'{score8(x8, audio.reconstruct(y, 8000)):32.2f} dB')

    hdr('32.3 THE SAMPLE BOUNDARY: MULTIFRAME PHASE')
    print('  The S/T framer gives BIT alignment.  PCM needs SAMPLE alignment too.')
    print('  All 8 phases of the 8-frame multiframe, clean line:\n')
    bits = pack8(enc(x8))
    for ph in range(8):
        y = dec(unpack8(bits, phase=ph))
        n = min(len(x8), len(y))
        print(f'    phase {ph}: {score8(x8[:n], audio.reconstruct(y[:n], 8000)):7.2f} dB'
              + ('   <-- correct' if ph == 0 else ''))
    print('\n  Nothing in the existing framer distinguishes these.  A multiframe')
    print('  alignment layer is not optional and it is not free.')


# ------------------- 16. a transparent 64 kbps slot, and bonding two 32k slots
def scramble(bits, taps=(4, 7), seed_ones=True):
    """Self-synchronising (multiplicative) scrambler, x^7 + x^4 + 1.
    out[n] = in[n] ^ out[n-4] ^ out[n-7];  the descrambler needs no alignment,
    it self-syncs in 7 bits.  Costs x3 error multiplication.

    The shift register MUST be seeded nonzero: with a zero state an all-zero
    input passes straight through as all zeros (section 40).  Seeded, an
    all-zero input yields the period-127 m-sequence.  A residual lockup remains
    -- if the state happens to be zero when the input goes all-zero, ~2^-7 per
    idle onset -- which is the known weakness of multiplicative scramblers."""
    n = len(bits)
    hist = [1 if seed_ones else 0] * 7
    out = np.zeros(n, np.uint8)
    for i in range(n):
        v = int(bits[i])
        for t in taps:
            v ^= hist[-t]
        hist = hist[1:] + [v]
        out[i] = v
    return out


def descramble(bits, taps=(4, 7)):
    n = len(bits)
    out = np.zeros(n, np.uint8)
    for i in range(n):
        v = int(bits[i])
        for t in taps:
            if i >= t:
                v ^= int(bits[i - t])
        out[i] = v
    return out


def _worst_pass(line, flen):
    """Worst wrong-alignment pass rate: the fraction of frames at which some
    WRONG alignment satisfies S==0,T==1.  1.000 means a lock that never breaks."""
    n = len(line) // flen * flen
    f = line[:n].reshape(-1, flen)
    worst = 0.0
    for k in range(1, flen):
        r = np.roll(line[:n], -k).reshape(-1, flen)
        worst = max(worst, float(((r[:, flen-2] == 0) & (r[:, flen-1] == 1)).mean()))
    return worst


def do_pipe(secs=6.0):
    import g711
    hdr('33. A TRANSPARENT 64 kbps SLOT  (no multiframe, carrier stays CVSD)')
    print('  The carrier never learns what rides in a C-bit slot.  What it does')
    print('  care about is the slot\'s STATISTICS: spec 2.1 needs every wrong')
    print('  alignment gated by an effectively random bit.  CVSD provides that')
    print('  for free.  A 64 kbps pipe does not necessarily.\n')

    rate, n_ch, flen = 64000, 3, 8
    L = int(rate * secs)
    x8, fs = audio.read_wav('speech30.wav', seconds=secs)
    x8 = audio.bandlimit(x8, fs)
    x8 = audio.resample_to(x8 * (run.NOMINAL_RMS / x8.std()), fs, 8000)
    p = cvsd.CVSDParams(rate=rate, slew=run.SLEW[rate], **run.BASE)
    x64 = audio.resample_to(x8, 8000, rate)
    cv = cvsd.encode(x64, p)

    def slot_stream(kind):
        if kind == 'cvsd':
            return cv[:L]
        if kind.startswith('idle'):
            code = g711.IDLE['ulaw' if 'u' in kind else 'alaw']
            return pack8(np.full(L // 8 + 1, code, np.uint8))[:L]
        enc = g711.CODECS['ulaw' if 'u' in kind else 'alaw'][0]
        return pack8(enc(x8))[:L]

    KINDS = [('cvsd', 'CVSD (the control)'), ('ulaw', 'mu-law, active speech'),
             ('idle-u', 'mu-law, IDLE (0xFF)'), ('alaw', 'A-law, active speech'),
             ('idle-a', 'A-law, IDLE (0xD5)')]
    print(f'  {"slot payload":26s} {"P(1)":>6s} {"longest run":>12s} '
          f'{"worst wrong-align":>18s}  framer')
    for kind, nm in KINDS:
        for scr in (False, True):
            b = slot_stream(kind)
            b = scramble(b) if scr else b
            M = len(b)
            ch = np.zeros((n_ch, M), np.uint8)
            ch[0] = b
            ch[1] = cv[:M]
            ch[2] = cv[:M]
            ln = link.build(ch, np.zeros((n_ch, M), np.uint8))
            wp = _worst_pass(ln, flen)
            runs = link.runs_of(b, 1)
            lab = nm + (' + scrambler' if scr else '')
            print(f'  {lab:26s} {b.mean():6.3f} {(int(runs.max()) if len(runs) else 0):12d} '
                  f'{wp:18.3f}  {"FALSE LOCK" if wp > 0.999 else "ok"}')
        print()

    hdr('34. THE SCRAMBLER COSTS x3 ERRORS AND NOTHING ELSE')
    b = slot_stream('idle-u')[:200000]
    sc = scramble(b)
    print(f'  round trip bit-exact: {np.array_equal(descramble(sc), b)}')
    for ber in (1e-4, 1e-3, 1e-2):
        imp = link.impair(sc, ber=ber, seed=3)
        got = descramble(imp)
        n = min(len(got), len(b))
        print(f'  BER {ber:.0e} on the line -> {float((got[:n]!=b[:n]).mean()):.2e} '
              f'out of the descrambler  ({float((got[:n]!=b[:n]).mean())/ber:.1f}x)')
    print('\n  Self-synchronising, so it needs no alignment and adds no state to')
    print('  recover: 7 flip-flops and 2 XORs per direction per pipe.')


def do_bond(secs=4.0):
    hdr('35. BONDING TWO 32 kbps SLOTS INTO ONE 64 kbps PIPE')
    print('  bond.py bonds two slots and teaches the carrier G.711, which needs a')
    print('  4-frame multiframe, a marker on A2 and a second framer.  If the')
    print('  carrier stays out of the PCM business the multiframe disappears:')
    print('  slot ORDER is already established by the S/T framer, so C1 is the')
    print('  even bit and C2 the odd one, deterministically, forever.\n')
    RATE, n_ch, flen = 32000, 3, 8
    rng = np.random.default_rng(5)
    L = int(RATE * secs)
    pipe = rng.integers(0, 2, 2 * L).astype(np.uint8)      # a 64 kbps bit pipe
    ch = np.zeros((n_ch, L), np.uint8)
    ch[0] = pipe[0::2]
    ch[1] = pipe[1::2]
    x = audio.resample_to(audio.bandlimit(*audio.read_wav('speech30.wav', seconds=secs)[::1]),
                          48000, RATE) if False else None
    src, fs = audio.read_wav('speech30.wav', seconds=secs)
    src = audio.resample_to(audio.bandlimit(src, fs) * 0.15, fs, RATE)[:L]
    p = run.params(RATE)
    ch[2] = cvsd.encode(src, p)[:L]
    ln = link.build(ch, np.zeros((n_ch, L), np.uint8))
    ok = True
    for k in range(flen):
        c, _, st = link.framer(ln, n_ch, skew=k, **LOF)
        if st['false_lock']:
            ok = False
            continue
        m = min(len(c[0]), len(c[1]))
        rec = np.empty(2 * m, np.uint8)
        rec[0::2], rec[1::2] = c[0][:m], c[1][:m]
        best = min(float((rec[:20000] != pipe[o:o + 20000]).mean())
                   for o in range(0, 600, 2) if o + 20000 <= len(pipe))
        ok &= (best == 0.0)
    print(f'  bit-exact 64 kbps pipe recovered at all {flen} start-up skews: {ok}')
    print(f'  extra state needed: none.  extra packages: none.')
    print(f'  what it costs: two slots and one of the two A bits goes spare.')
    print('\n  The pipe is bit-transparent and synchronous, clocked by the frame')
    print('  clock.  It is NOT octet-aligned -- anything needing octets finds its')
    print('  own phase, which is the end equipment\'s job, not the carrier\'s.')
    print('  Statistics are the end equipment\'s responsibility too, or the')
    print('  scrambler of 34 makes them the carrier\'s and costs one package.')


# ------------------- 17. does a data slot actually need scrambling?
def do_dataslot(secs=6.0):
    """Two different questions I ran together last time, wrongly.

      (a) does a constant slot break an ESTABLISHED lock?
      (b) does it break ACQUISITION?

    and if (b), is it the payload that is at fault or the ADJACENCY?
    """
    RATE, n_ch, flen = 32000, 3, 8
    src, fs = audio.read_wav('speech30.wav', seconds=secs)
    src = audio.resample_to(audio.bandlimit(src, fs) * 0.15, fs, RATE)
    p = run.params(RATE)
    cv = cvsd.encode(src, p)
    L = len(cv)

    def build(slot, const, a_of_slot, hooks):
        ch = np.array([cv.copy() for _ in range(n_ch)])
        sg = np.zeros((n_ch, L), np.uint8)
        for i in range(n_ch):
            sg[i] = hooks[i]
        if const is not None:
            ch[slot] = np.full(L, const, np.uint8)
        sg[slot] = a_of_slot
        return link.build(ch, sg)

    hdr('36. (a) DOES A CONSTANT SLOT BREAK AN ESTABLISHED LOCK?')
    print('  Lock on normal traffic, then the data slot goes hard to a constant')
    print('  half way through.  Worst case: slot 1 constant 1, its A bit on-hook.\n')
    for const in (0, 1):
        ch = np.array([cv.copy() for _ in range(n_ch)])
        ch[0][L // 2:] = const
        ln = link.build(ch, np.zeros((n_ch, L), np.uint8))
        c, _, st = link.framer(ln, n_ch, **LOF)
        ph = st['pos'] % flen
        print(f'  slot 1 -> constant {const} at half way: locked={st["lock_bit"] is not None}, '
              f'lock phase {st["lock_phase"]}, LOF events {st["lof_events"]}, '
              f'phase stable {bool((ph == ph[0]).all())}')
    print('\n  An established lock is untouched.  The S and T bits are unaffected by')
    print('  what a payload slot does, so there is nothing for the framer to lose.')

    hdr('36. (b) DOES IT BREAK ACQUISITION?')
    print('  Cold start from all 8 skews.  "false" = locked to a WRONG alignment,')
    print('  which at a 1.000 pass rate is permanent.\n')
    print(f'  {"data slot":>10s} {"payload":>9s} {"its A bit":>10s} {"other A bits":>13s}'
          f'  false locks')
    for slot in (0, 2):
        for const in (0, 1):
            for a_slot in (0, 1):
                for other in (0, 1):
                    hooks = [other] * n_ch
                    ln = build(slot, const, a_slot, hooks)
                    bad = sum(1 for k in range(flen)
                              if link.framer(ln, n_ch, skew=k, **LOF)[2]['false_lock'])
                    nm = f'slot {slot+1}' + (' (last)' if slot == n_ch - 1 else '')
                    print(f'  {nm:>10s} {"all " + str(const):>9s} {a_slot:>10d} '
                          f'{other:>13d}  {bad}/8' + ('   <-- FALSE LOCK' if bad else ''))
        print()

    hdr('37. WHY -- IT IS THE ADJACENCY, NOT THE PAYLOAD')
    print('  The framer checks ONE adjacent pair per alignment, and looks for')
    print('  (0,1).  A constant C bit is only dangerous when its neighbour makes')
    print('  that exact pattern static.  Exhaustive, C_j constant, A bits static:\n')
    for n in (3, 7):
        fl = link.frame_len(n)
        for slot in range(n):
            for const in (0, 1):
                bad = []
                for a_slot in (0, 1):
                    for other in (0, 1):
                        val = {}
                        for i in range(n):
                            val[2 * i] = a_slot if i == slot else other
                            val[2 * i + 1] = const if i == slot else None
                        val[fl - 2], val[fl - 1] = 0, 1
                        ung = [k for k in range(1, fl)
                               if val[(fl - 2 + k) % fl] == 0 and val[(fl - 1 + k) % fl] == 1]
                        if ung:
                            bad.append((a_slot, other))
                if slot in (0, n - 1) or n == 3:
                    tag = ('SAFE at every hook state' if not bad
                           else 'unsafe when (its A, others A) = ' +
                                ', '.join(f'({x},{y})' for x, y in bad))
                    print(f'  N={n}, data slot {slot+1}{" (last)" if slot==n-1 else "":7s}, '
                          f'all {const}: {tag}')
        print()

    hdr('38. A MERELY BIASED PAYLOAD, NOT A CONSTANT ONE')
    print('  A constant is the worst case but not the only one: a persistently')
    print('  biased slot gives a pass rate below 1.0, and the +2/-1 counter needs')
    print('  only 2/3 of frames good to never trip.  Worst adjacency (slot 1,')
    print('  all-1s bias, its A bit on-hook), cold start from 8 skews:\n')
    rng = np.random.default_rng(7)
    print(f'  {"P(1)":>6s} {"false locks":>12s} {"wrong-align pass rate":>23s}')
    for bias in (0.5, 0.7, 0.9, 0.95, 0.99, 1.0):
        ch = np.array([cv.copy() for _ in range(n_ch)])
        ch[0] = (rng.random(L) < bias).astype(np.uint8)
        ln = link.build(ch, np.zeros((n_ch, L), np.uint8))
        bad = sum(1 for k in range(flen)
                  if link.framer(ln, n_ch, skew=k, **LOF)[2]['false_lock'])
        print(f'  {bias:6.2f} {bad:9d}/8 {_worst_pass(ln, flen):23.3f}')


# ------------- 19. toggling BOTH framing bits: (0,1) / (1,0) on alternate frames
def build_st_toggle(chan_bits, sig_bits):
    """Framing pair alternates (S,T) = (0,1), (1,0), (0,1), ...
    In counter terms the framing bit becomes `LSB XOR toggle` instead of `LSB`:
    at count flen-2 (LSB=0) it is the toggle, at flen-1 (LSB=1) its complement.
    One flip-flop dividing the frame clock and one XOR."""
    ln = link.build(chan_bits, sig_bits)
    flen = link.frame_len(np.atleast_2d(chan_bits).shape[0])
    f = ln.reshape(-1, flen)
    tog = (np.arange(len(f)) & 1).astype(np.uint8)
    f[:, flen - 2] = tog
    f[:, flen - 1] = 1 - tog
    return f.reshape(-1)


def framer_st(line, n_ch, confirm=64, skew=0, lof=12, lof_up=2, lof_down=1):
    """good := (S != T)  AND  (S changed since the last frame).

    The first test gates a CVSD bit at ~50% exactly as the present framer does.
    The second kills anything STATIC in the S position -- which is what an A bit
    is, and what a constant data slot is.  Both are needed: (S != T) alone is
    weaker than the present check, and 'both changed' alone lets the (C_N, S)
    pair through at ~95%."""
    if skew:
        line = np.roll(line, -skew)
    flen = link.frame_len(n_ch)
    sig_pos = [2 * i for i in range(n_ch)]
    chan_pos = [2 * i + 1 for i in range(n_ch)]
    true_phase = (flen - (skew % flen)) % flen
    chan_out = [[] for _ in range(n_ch)]
    sig_out = [[] for _ in range(n_ch)]
    i = 0
    confirm_ct = err = 0
    locked = False
    last_s = None
    st = dict(lock_bit=None, lock_phase=None, slips=0, lof_events=0, frames=0,
              false_lock=False)
    pos = []
    N = line.size
    while i + flen <= N:
        f = line[i:i + flen]
        sb, tb = int(f[flen - 2]), int(f[flen - 1])
        differ = (sb != tb)
        good = differ and (last_s is None or sb != last_s)
        last_s = sb if differ else None
        if not locked:
            if good:
                confirm_ct += 1
                if confirm_ct >= confirm:
                    locked = True
                    st['lock_bit'] = i
                    st['lock_phase'] = i % flen
                    st['false_lock'] = (i % flen) != true_phase
                i += flen
            else:
                confirm_ct = 0
                st['slips'] += 1
                last_s = None
                i += 1
            continue
        err = max(0, err - lof_down) if good else err + lof_up
        if err >= lof:
            locked = False
            confirm_ct = err = 0
            last_s = None
            st['lof_events'] += 1
            i += 1
            continue
        for c in range(n_ch):
            chan_out[c].append(f[chan_pos[c]])
            sig_out[c].append(f[sig_pos[c]])
        st['frames'] += 1
        pos.append(i)
        i += flen
    ch = np.array([np.array(c, np.uint8) for c in chan_out]) if st['frames'] \
        else np.zeros((n_ch, 0), np.uint8)
    sg = np.array([np.array(x, np.uint8) for x in sig_out]) if st['frames'] \
        else np.zeros((n_ch, 0), np.uint8)
    st['pos'] = np.array(pos, np.int64)
    return ch, sg, st


# ------------------- 18. a toggling T: making static payload impossible to mimic
def build_toggle(chan_bits, sig_bits):
    """Frame as link.build, but T alternates 0,1,0,1 frame by frame instead of
    being a constant 1.  S stays 0.  In counter terms the framing bit becomes
    `LSB AND toggle` instead of `LSB`: one flip-flop dividing the frame clock
    and one gate."""
    ln = link.build(chan_bits, sig_bits)
    flen = link.frame_len(np.atleast_2d(chan_bits).shape[0])
    f = ln.reshape(-1, flen)
    f[:, flen - 1] = (np.arange(len(f)) & 1).astype(np.uint8)
    return f.reshape(-1)


def framer_toggle(line, n_ch, confirm=64, skew=0, lof=12, lof_up=2, lof_down=1,
                  emit_always=False):
    """link.framer with one change: the stop bit is checked as a TRANSITION as
    well as the start bit as a level:

        good := (bit[flen-2] == 0) AND (bit[flen-1] != its value last frame)

    The T register is invalid for one frame after a slip, so the first frame at
    any new alignment is scored on S alone.  A static T therefore scores at most
    one good frame before failing, against the 64 consecutive that acquisition
    needs.  Costs one flip-flop and one XOR."""
    if skew:
        line = np.roll(line, -skew)
    flen = link.frame_len(n_ch)
    sig_pos = [2 * i for i in range(n_ch)]
    chan_pos = [2 * i + 1 for i in range(n_ch)]
    true_phase = (flen - (skew % flen)) % flen
    chan_out = [[] for _ in range(n_ch)]
    sig_out = [[] for _ in range(n_ch)]
    i = 0
    confirm_ct = 0
    err = 0
    locked = False
    last_t = None
    st = dict(lock_bit=None, lock_phase=None, slips=0, lof_events=0, frames=0,
              false_lock=False)
    pos = []
    N = line.size
    while i + flen <= N:
        f = line[i:i + flen]
        t = int(f[flen - 1])
        s_ok = (f[flen - 2] == 0)
        # T register invalid for one frame after a slip: score on S alone then
        good = s_ok and (last_t is None or t != last_t)
        last_t = t if s_ok else None
        if not locked:
            if good:
                confirm_ct += 1
                if confirm_ct >= confirm:
                    locked = True
                    st['lock_bit'] = i
                    st['lock_phase'] = i % flen
                    st['false_lock'] = (i % flen) != true_phase
                i += flen
            else:
                confirm_ct = 0
                st['slips'] += 1
                last_t = None
                i += 1
            continue
        err = max(0, err - lof_down) if good else err + lof_up
        if err >= lof:
            locked = False
            confirm_ct = 0
            err = 0
            last_t = None
            st['lof_events'] += 1
            i += 1
            continue
        for c in range(n_ch):
            chan_out[c].append(f[chan_pos[c]])
            sig_out[c].append(f[sig_pos[c]])
        st['frames'] += 1
        pos.append(i)
        i += flen
    ch = np.array([np.array(c, np.uint8) for c in chan_out]) if st['frames'] \
        else np.zeros((n_ch, 0), np.uint8)
    sg = np.array([np.array(x, np.uint8) for x in sig_out]) if st['frames'] \
        else np.zeros((n_ch, 0), np.uint8)
    st['pos'] = np.array(pos, np.int64)
    return ch, sg, st


def do_toggle(secs=6.0):
    RATE = 32000
    hdr('39. A TOGGLING STOP BIT  -- PROPOSED, MEASURED, REJECTED')
    print('  The idea: a false lock needs a STATIC (0,1) pair, so make the stop')
    print('  bit alternate and check it as a TRANSITION, and no static pair can')
    print('  mimic it -- any payload, any slot, all channels equal.')
    print('  It fixes the constant-payload case and the section 10.2 mis-strap,')
    print('  and it is WORSE OVERALL.  Section 39.4 is why.\n')
    print('    TX:  framing bit = LSB AND toggle     (1 flip-flop + 1 gate)')
    print('    RX:  good := (S == 0) AND (T changed) (1 flip-flop + 1 XOR)\n')

    src, fs = audio.read_wav('speech30.wav', seconds=secs)
    src = audio.resample_to(audio.bandlimit(src, fs) * 0.15, fs, RATE)
    p = run.params(RATE)
    cv = cvsd.encode(src, p)
    L = len(cv)

    hdr('39.1 DOES IT STILL FRAME AT ALL?')
    for n_ch in (1, 3, 7):
        flen = link.frame_len(n_ch)
        ch = np.array([np.roll(cv, 977 * i) for i in range(n_ch)])
        sg = np.array([np.full(L, i % 2, np.uint8) for i in range(n_ch)])
        ln = build_toggle(ch, sg)
        okp = okb = True
        ms = []
        for k in range(flen):
            c, _, st = framer_toggle(ln, n_ch, skew=k)
            okp &= (st['lock_bit'] is not None and not st['false_lock'])
            if st['lock_bit'] is not None:
                ms.append(1000.0 * st['lock_bit'] / (RATE * flen))
            best = 1.0
            for o in range(400):
                nn = min(len(ch[0]) - o, len(c[0]))
                if nn < 20000:
                    break
                best = min(best, float((c[0][:nn] != ch[0][o:o + nn]).mean()))
                if best == 0.0:
                    break
            okb &= (best == 0.0)
        lnq = build_toggle(ch, np.zeros((n_ch, L), np.uint8))
        at = (L // 2) * flen
        worst = 0.0
        for k in range(1, flen):
            stt = framer_toggle(link.slip(lnq, at, n=k), n_ch)[2]
            pp = stt['pos']
            tp = np.where(pp < at, pp % flen, (pp + k) % flen)
            worst = max(worst, 1000 * int((tp != tp[0]).sum()) / RATE)
        fr = [framer_toggle(link.impair(lnq, ber=x, seed=5), n_ch)[2]['lof_events']
              for x in (1e-3, 1e-2, 3e-2)]
        print(f'  N={n_ch}: lock all {flen} skews {okp}, bit-exact {okb}, '
              f'acquisition {min(ms):.2f}-{max(ms):.2f} ms, worst LOF {worst:.2f} ms, '
              f'false reframes {fr}')

    hdr('39.2 A CONSTANT DATA SLOT, IN EVERY SEAT, AT EVERY HOOK STATE')
    print('  Old framer vs toggling T, false locks out of flen start-up skews.')
    print('  Only rows where either framer fails are listed.\n')
    print(f'  {"N":>2s} {"slot":>5s} {"payload":>8s} {"its A":>6s} {"others":>7s} '
          f'{"old":>7s} {"toggling T":>11s}')
    tot_old = tot_new = tested = 0
    for n_ch in (3, 7):
        flen = link.frame_len(n_ch)
        slots = range(n_ch) if n_ch == 3 else (0, 1, n_ch - 1)
        for slot in slots:
            for const in (0, 1):
                for a_slot in (0, 1):
                    for other in (0, 1):
                        ch = np.array([np.roll(cv, 977 * i) for i in range(n_ch)])
                        ch[slot] = np.full(L, const, np.uint8)
                        sg = np.full((n_ch, L), other, np.uint8)
                        sg[slot] = a_slot
                        old = sum(1 for k in range(flen)
                                  if link.framer(link.build(ch, sg), n_ch, skew=k,
                                                 **LOF)[2]['false_lock'])
                        new = sum(1 for k in range(flen)
                                  if framer_toggle(build_toggle(ch, sg), n_ch,
                                                   skew=k)[2]['false_lock'])
                        tested += 1
                        tot_old += old
                        tot_new += new
                        if old or new:
                            print(f'  {n_ch:2d} {slot+1:5d} {"all "+str(const):>8s} '
                                  f'{a_slot:6d} {other:7d} {old:4d}/{flen:<2d} '
                                  f'{new:6d}/{flen:<2d}'
                                  + ('   STILL BAD' if new else '   fixed'))
    print(f'\n  {tested} configurations: old framer false-locked in {tot_old} '
          f'skew-cases, toggling T in {tot_new}.')
    print('  (N=7 sampled at slots 1, 2 and 7; N=3 exhaustive.)')

    hdr('39.3 DOES IT ALSO FIX THE CHANNEL-COUNT MIS-STRAP?  (section 10.2)')
    print('  A narrow TX presents a valid S/T to a wide RX because the shorter')
    print('  frame divides the longer one.  But a wide RX samples the narrow T')
    print('  every OTHER narrow frame, so it always sees the SAME toggle phase --')
    print('  a constant.  The transition check should reject it.\n')
    print(f'  {"TX":>12s} {"RX":>4s} {"old framer":>12s} {"toggling T":>12s}')
    for tx_n, rx_n in ((1, 3), (1, 7), (3, 7), (3, 1), (7, 3)):
        ch = np.array([np.roll(cv, 977 * i) for i in range(tx_n)])
        sg = np.zeros((tx_n, L), np.uint8)
        old_locked = link.framer(link.build(ch, sg), rx_n, **LOF)[2]['lock_bit'] is not None
        new_locked = framer_toggle(build_toggle(ch, sg), rx_n)[2]['lock_bit'] is not None
        print(f'  {"N="+str(tx_n):>12s} {"N="+str(rx_n):>4s} '
              f'{("LOCKS" if old_locked else "mutes"):>12s} '
              f'{("LOCKS" if new_locked else "mutes"):>12s}'
              + ('   <-- fixed' if old_locked and not new_locked else ''))
    print('\n  The dangerous direction of section 10.2 is narrow-TX into wide-RX.')

    hdr('39.4 WHY IT IS REJECTED: CVSD IDLE IS A PERFECT ALTERNATION')
    alt = (cv[1:] != cv[:-1]).astype(int)
    r = link.runs_of(alt, 1)
    sil = cvsd.encode(np.zeros(20000), p)
    print(f'  a real CVSD stream alternates on {alt.mean():.1%} of bit pairs')
    print(f'  longest continuous alternation in {secs:.0f} s of speech: '
          f'{int(r.max())} bits = {1000*int(r.max())/RATE:.0f} ms')
    print(f'  CVSD encoding pure silence: {"".join(map(str, sil[:24]))} ...  '
          f'({float((sil[1:] != sil[:-1]).mean()):.0%} alternating)')
    print()
    print('  A delta modulator tracking a constant emits 1010... forever, so a')
    print('  CVSD bit TRANSITIONS almost every frame.  The transition check does')
    print('  not distinguish the stop bit from a payload bit -- it MATCHES it.')
    print('  Paired with a static A bit at 0, an idle voice channel passes the')
    print('  new check ~95% of frames and 100% during silence, which is far more')
    print('  than the 64 consecutive that acquisition needs.')
    print()
    print('  The existing check works for the mirror-image reason: CVSD is random')
    print('  in LEVEL (50/50) and nearly deterministic in TRANSITION.  Checking')
    print('  levels is gated; checking transitions is not.')
    print()
    print('  General form: the framing pattern is distinguishable from payload')
    print('  only if it is either STATIC -- which any static payload can mimic --')
    print('  or TEMPORAL, which needs its own phase, i.e. a multiframe.  There is')
    print('  no third option, so the constant-payload case must be fixed in the')
    print('  PAYLOAD, not in the framer.')


# ------------------ 20. is a cheaper transform than a scrambler enough?
def do_transforms(secs=2.0):
    """Alternate-bit inversion, NRZI and the LFSR scrambler, each applied to a
    data slot, against the present framer, over constant AND periodic payloads.
    Every seat x every hook state x all 8 skews; false locks summed."""
    import framing_review as fr
    hdr('40. PAYLOAD TRANSFORMS AGAINST THE PRESENT FRAMER')
    cv, sil = fr.load(secs); L = len(cv); n = 3; flen = 8
    S0 = fr.SCHEMES['S0 static (0,1)']
    tog = (np.arange(L) & 1).astype(np.uint8)

    def nrzi(d):
        o = np.zeros(len(d), np.uint8); a = 0
        for i, b in enumerate(d):
            a ^= int(b); o[i] = a
        return o
    XF = {'none': lambda d: d,
          'alternate-bit inverter': lambda d: (d ^ tog).astype(np.uint8),
          'NRZI (differential)': nrzi,
          'LFSR x^7+x^4+1, seed 0': lambda d: scramble(d, seed_ones=False),
          'LFSR x^7+x^4+1, seed 1': lambda d: scramble(d, seed_ones=True)}
    PAY = {'all 0': np.zeros(L, np.uint8), 'all 1': np.ones(L, np.uint8),
           '1010': tog.copy(), '0101': (1 - tog).astype(np.uint8),
           '0x7E flags': np.tile(np.array([0, 1, 1, 1, 1, 1, 1, 0], np.uint8), L // 8 + 1)[:L]}
    print(f'  {"transform":>26s} ' + ' '.join(f'{p:>10s}' for p in PAY) + '   RX needs phase?')
    PH = {'none': '-', 'alternate-bit inverter': 'YES (parity)', 'NRZI (differential)': 'no',
          'LFSR x^7+x^4+1, seed 0': 'no', 'LFSR x^7+x^4+1, seed 1': 'no'}
    for xn, xf in XF.items():
        row = []
        for pn, pay in PAY.items():
            tot = 0
            for slot in range(n):
                for a_s in (0, 1):
                    for oth in (0, 1):
                        ch = np.array([np.roll(cv, 977 * j) for j in range(n)]); ch[slot] = xf(pay)
                        sg = np.full((n, L), oth, np.uint8); sg[slot] = a_s
                        ln = fr.gbuild(ch, sg, S0)
                        tot += sum(1 for k in range(flen)
                                   if fr.gframer(ln, n, S0, skew=k)[1]['false_lock'])
            row.append(tot)
        print(f'  {xn:>26s} ' + ' '.join(f'{r:>7d}/96' for r in row) + f'   {PH[xn]}')
    print()
    print('  Every 1-2 bit linear transform has a period-<=2 input that maps to a')
    print('  constant; a 7-stage LFSR pushes that to a specific 127-bit sequence,')
    print('  but a zero state with zero input is a lockup -- seed it.')


if __name__ == '__main__':
    what = sys.argv[1] if len(sys.argv) > 1 else 'all'
    if what in ('matrix', 'all'):
        do_matrix()
    if what in ('hw', 'all'):
        do_hw()
    if what in ('link', 'all'):
        do_link()
    if what in ('audio', 'all'):
        do_audio()
    if what in ('phy', 'all'):
        do_phy()
    if what in ('mismatch', 'all'):
        do_mismatch()
    if what in ('monitor', 'all'):
        do_monitor()
    if what in ('modes', 'all'):
        do_modes()
    if what in ('robust', 'all'):
        do_robust()
    if what in ('fast512', 'all'):
        do_fastgroup()
    if what in ('crystal', 'all'):
        do_crystal()
    if what in ('taps', 'all'):
        do_tapmap()
    if what in ('grid', 'all'):
        do_grid()
    if what in ('corner', 'all'):
        do_corner()
    if what in ('noise', 'all'):
        do_noise()
    if what in ('pcm', 'all'):
        do_pcm()
    if what in ('pipe', 'all'):
        do_pipe()
    if what in ('bond', 'all'):
        do_bond()
    if what in ('dataslot', 'all'):
        do_dataslot()
    if what in ('toggle', 'all'):
        do_toggle()
    if what in ('transforms', 'all'):
        do_transforms()
