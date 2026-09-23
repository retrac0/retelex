"""
MF2 end to end: two talkers, real CVSD, over a real line.

MF2's line code is DIFFERENTIAL MANCHESTER (mf2/spec.md §8): the PHY is
mf8-spec.md §9 at the Q3 rate plug -- 256 kbps, 512 kBaud, half-bit 512 kHz.
AMI is kept as a same-bit-rate reference column, not a product option; the
AMI work belongs to MF8 now (mf8/ami.md), where six channels a link return
enough to pay for the receiver's crystal and DPLL.

Closes the noisy-condition half of mf2/sim.md G4.  Bit-level framing is
sim/mf2.py; this module puts a waveform on the wire.

Neither codec is forked here.  DM is mf8_line.rx_dm (fast.dm_encode /
fast.mono_decode, the clockless 0.75-cell classifier of mf8-spec.md §9.4);
AMI is mf8_line.rx_ami.  Both are called with line=256e3.

Chain, per direction:

    2 LibriSpeech talkers -> CVSD 64 kbps -> mf2 frame (4 bits, 64 kHz)
      -> DM @ 512 kBaud -> cable -> impairment -> monostable classifier
      -> mf2 framer -> per-channel CVSD decode -> segSNR and isolation

Usage:  python3 sim/mf2_line.py            everything
        python3 sim/mf2_line.py clean      clean line, DM + AMI ref
        python3 sim/mf2_line.py noise      Gaussian sweep
        python3 sim/mf2_line.py plant      impulse and attenuation
        python3 sim/mf2_line.py span       24 AWG buried pair: the hop length

`span` log: `sim/mf2_span.log`.
"""
import sys, gc, time, numpy as np
import audio, cvsd, fast, mf2, mf8_line, phy

RATE = mf2.RATE
LINE = mf2.LINE                   # 256 kbps
NCH = mf2.NCH
FLEN = mf2.FLEN
OS = 32                           # samples per line bit (same as mf8_line)
CABLE = 1.8e6
SECS = 1.0

# Buried-pair reference (frame-rate.md §3): 12 dB @ 256 kbps over ~1.7 km
SPAN_KM = 5.0
REF_KM = 1.7
REF_DB = 12.0


def _rx_ami(ln, **kw):
    """Same-bit-rate AMI reference — MF8's code now (mf8/ami.md)."""
    return mf8_line.rx_ami(ln, line=LINE, os=OS, cable=CABLE, **kw)


def _rx_dm(ln, **kw):
    """MF2's line code (mf2/spec.md §8): mf8-spec.md §9 at the Q3 plug."""
    return mf8_line.rx_dm(ln, line=LINE, os=OS, cable=CABLE, **kw)


CODES = {'diff Manchester': _rx_dm, 'AMI': _rx_ami}

# Symbol rate a code puts on the pair at LINE bits/s.  The cable charges
# for bandwidth, not for bits: DM is two symbols a bit, AMI one.
BAUD = {'diff Manchester': 2 * LINE, 'AMI': LINE}


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
    print('CLEAN LINE -- two talkers through MF2 + differential Manchester')
    print(f'  {SECS:.1f} s, 64 kbps/ch, 256 kbps line, AMI @ 256 kBaud.')
    print('  PHY: mf8_line.rx_dm(line=256e3) -- mf8-spec.md §9 at the Q3 rate')
    print('  plug.  AMI column is a same-bit-rate reference (mf8/ami.md).\n')
    print(HDR)
    res = {}
    for cn, rx in CODES.items():
        r = measure(ln, rx, src, bits, p, want_iso=True)
        res[cn] = r
        row(cn, r)
    print('\n  Per channel, differential Manchester:\n')
    print(f'  {"channel":9s} ' + ' '.join(f'{j + 1:>8d}' for j in range(NCH)))
    r = res['diff Manchester']
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
    print('GAUSSIAN NOISE -- sd referred to transmitted peak (DM primary)\n')
    print(HDR)
    for cn, rx in CODES.items():
        for sd in (0.0, 0.3, 0.4, 0.5, 0.6, 0.7):
            row(f'{cn}, sd {sd:.1f}', measure(ln, rx, src, bits, p, sd=sd))
        print()


def plant():
    src, bits, p = sources()
    A = [np.zeros(len(bits[0]), np.uint8) for _ in range(NCH)]
    ln = mf2.build(bits, A)
    print('IMPULSE NOISE -- damped rings 0.5-3x peak, Poisson (DM primary)\n')
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


def _span_loss_db(km=SPAN_KM, hz=LINE):
    return REF_DB * (km / REF_KM) * (hz / 256e3) ** 0.5


def span(secs=2.0, seeds=(1, 2, 3),
         distances_km=(0.8, 1.2, 1.7, 2.5, 3.0), urban_imp=40.0,
         codes=None):
    """Buried 24 AWG section length, both codes — the hop the repeater sets.

    MF2's code is differential Manchester (mf2/spec.md §8).  AMI is carried as
    a same-bit-rate reference so the kilometres traded for the simpler repeater
    are on the record rather than inferred.

    The cable charges for BANDWIDTH, not for bits: DM is two symbols a bit and
    AMI one, so at 256 kb/s DM occupies 512 kBaud against AMI's 256 and loses
    sqrt(2) more dB on a sqrt(f) pair.  The loss column is quoted at each code's
    own symbol rate for that reason.

    Two model caveats, both optimistic, both code-independent, and both left
    alone here so the two codes are compared under identical rules:

      * phy.pair_24awg is a ZERO-PHASE filter -- amplitude tilt only, no group
        delay, and no asymmetric tail.  Real skin effect is minimum-phase.
      * impulses are added AFTER the AGC normalisation, so impulse-to-signal
        ratio is held constant with distance; in the plant a mid-section
        impulse travels less cable than the signal does.

    Fixing either moves every distance below.  Do it as its own before/after
    run, not inside a code comparison.
    """
    codes = CODES if codes is None else codes
    print(f'MF2 section length @ {LINE / 1e3:.0f} kbps -- 24 AWG buried pair')
    print(f'  sqrt(f) law ref: {REF_DB:.0f} dB @ 256 kHz / {REF_KM} km '
          f'(frame-rate.md §3); ideal AGC after the cable')
    print(f'  loss quoted at each code\'s own symbol rate: '
          + ', '.join(f'{c} {BAUD[c] / 1e3:.0f} kBaud' for c in codes))
    print(f'  urban impulse: {urban_imp:.0f}/s, amp 1-5x peak, '
          f'tau 8-80 us, ring 20-120 kHz')
    print(f'  window: {secs:.1f} s x {len(seeds)} seeds\n')
    print('  MODEL CAVEATS (both optimistic, see docstring): zero-phase cable,')
    print('  impulses injected after AGC.  Ranking is sound; kilometres are not')
    print('  a bench number.\n')

    src, bits, p = sources(secs=secs)
    A = [np.zeros(len(bits[0]), np.uint8) for _ in range(NCH)]
    ln = mf2.build(bits, A)

    def rx_factory(cn, km, imp_rate, seed):
        base = CODES[cn]

        def rx(line, **kw):
            return base(line, cable_km=km, imp=imp_rate, seed=seed,
                        imp_amp=(1.0, 5.0), imp_tau=(8e-6, 80e-6),
                        imp_ring=(20e3, 120e3), **kw)
        return rx

    def summarise(cn, km, imp_rate, label):
        loss = _span_loss_db(km, BAUD[cn])
        bers, downs, lofs, cleans, locked_n, acquired = [], [], [], [], 0, 0
        for sd in seeds:
            r = measure(ln, rx_factory(cn, km, imp_rate, sd), src, bits, p)
            bers.append(float(np.nanmean(r['ber'])))
            downs.append(r['down'])
            lofs.append(r['lof'])
            cleans.append(r['clean'])
            ok = bool(r['locked'] and not np.isnan(r['seg'][0]))
            locked_n += int(ok)
            acquired += int(r['locked'])
        ber = float(np.mean(bers))
        down = float(np.mean(downs))
        lof_s = float(np.mean(lofs)) / secs
        clean = float(np.mean(cleans))
        print(f'    {label:28s} {loss:5.1f} dB  {acquired}/{len(seeds)} acq  '
              f'BER {ber:9.3e}  {lof_s:6.2f} LOF/s  {down:6.2f}% down  '
              f'{1000 * clean:6.0f} ms clean', flush=True)
        return dict(code=cn, km=km, imp=imp_rate, loss_db=loss, ber=ber,
                    down=down, lof_per_s=lof_s, clean=clean,
                    locked=locked_n, acquired=acquired)

    rows = []
    for cn in codes:
        print(f'  {cn.upper()} -- {BAUD[cn] / 1e3:.0f} kBaud on the pair')
        for km in distances_km:
            rows.append(summarise(cn, km, 0.0, f'{km:g} km, quiet'))
            rows.append(summarise(cn, km, urban_imp,
                                  f'{km:g} km, urban {urban_imp:.0f}/s'))
        print()

    # Two different limits, and they must not be conflated.  The QUIET section
    # is set by the cable -- loss and dispersion -- and moves with distance.
    # The IMPULSE verdict is a property of the code and, as the rows above
    # show, barely moves with distance at all, so no section length buys it
    # back.
    print('  SECTION LENGTH -- quiet: the longest distance with BER = 0,')
    print('  0 LOF/s and every seed acquired\n')
    qbest = {}
    for cn in codes:
        got = None
        for km in distances_km:
            q = next(r for r in rows if r['code'] == cn and r['km'] == km
                     and r['imp'] == 0.0)
            if (q['ber'] == 0.0 and q['lof_per_s'] == 0.0
                    and q['acquired'] == len(seeds)):
                got = km
        qbest[cn] = got
        edge = '   (not bounded by this sweep)' if got == distances_km[-1] else ''
        print(f'    {cn:20s} '
              + (f'{got:g} km{edge}' if got else 'under the shortest tested'))

    print(f'\n  IMPULSE -- LOF/s at {urban_imp:.0f} impulses/s, against distance\n')
    print(f'    {"code":20s} ' + ' '.join(f'{km:g} km'.rjust(9)
                                          for km in distances_km))
    for cn in codes:
        vals = [next(r for r in rows if r['code'] == cn and r['km'] == km
                     and r['imp'] == urban_imp)['lof_per_s']
                for km in distances_km]
        print(f'    {cn:20s} ' + ' '.join(f'{v:9.2f}' for v in vals))

    a, b = qbest.get('diff Manchester'), qbest.get('AMI')
    if a and b:
        print(f'\n  Quiet reach, DM / AMI = {a / b:.2f}x, where the sqrt(f)')
        print(f'  arithmetic predicts {1 / 2 ** 0.5:.2f}x the other way because DM')
        print('  occupies twice the band.  The arithmetic measures the wrong')
        print('  thing: with ideal AGC the section is closed by DISPERSION, not')
        print('  by flat loss.  The monostable classifier decides on transition')
        print('  timing RATIOS (0.75 cell), which a tilted channel scales without')
        print('  breaking; AMI decides on amplitude against a peak-derived')
        print('  threshold, which is what dispersion attacks.')
    print('\n  The two limits are independent.  DM buys section length and pays')
    print('  in impulse: about 5-6x AMI\'s breaks per second, and that ratio is')
    print('  FLAT with distance, so no shorter section buys it back.  This is')
    print('  line-codes.md §4 (AMI ~1/6 the breaks) reproduced at MF2\'s rate on')
    print('  the buried pair for the first time.')
    return rows


def _dm_chain(ln, hops, km, sd=0.0, imp=0.0, seed=1, hyst=0.05,
              imp_amp=(1.0, 5.0), imp_tau=(8e-6, 80e-6), imp_ring=(20e3, 120e3)):
    """N non-reclocking repeaters on a span of N+1 sections.

    A biphase repeater is a comparator and a driver.  There is no timing
    element in the hut: nothing to set per rate beyond the input filter, no
    clock to slip against, and nothing to drift.  fast.slice_hyst IS that
    repeater -- it takes the received waveform and returns two levels, which
    is exactly what the driver re-launches.

    What it restores: amplitude, completely, every section.
    What it does not: edge timing.  The comparator fires where the sloped,
    dispersed edge crosses its threshold, and that displacement is re-launched
    as a real edge for the next section to add to.  The budget is the §9.4
    classifier's +/-13% of a cell; this function measures what is spent.

    Returns (final two-level waveform, ideal waveform).
    """
    fs = LINE * OS
    rng = np.random.default_rng(seed)
    ideal = fast.dm_encode(ln)
    x = np.repeat(ideal.astype(np.float64) * 2 - 1, OS // 2)
    w = None
    for h in range(hops + 1):
        x = phy.pair_24awg(x, fs, length_km=km)
        pk = np.abs(x).max()
        if pk > 0:
            x /= pk
        if sd:
            x += rng.normal(0, sd, len(x))
        if imp:
            x += phy.plant_noise(len(x), fs, rate_hz=imp, amp=imp_amp,
                                 tau_s=imp_tau, ring_hz=imp_ring,
                                 seed=seed * 7919 + h)
        x = mf8_line._lp_at(x, 2 * LINE, fs, 2)
        w = fast.slice_hyst(x, hyst)
        if h < hops:
            x = w.astype(np.float64) * 2 - 1        # the driver re-launches
    return w, np.repeat(ideal, OS // 2).astype(np.uint8)


def _edges(w):
    return np.flatnonzero(np.diff(w.astype(np.int8)) != 0)


def _displacement(w, ref, tol=None):
    """Edge displacement against the ideal grid.

    Edges are matched to the NEAREST ideal edge, not paired by index: one
    invented or swallowed transition would otherwise shift every later
    pairing and swamp the measurement.  The chain's bulk delay (one input
    filter a section) is estimated first and removed, because a constant
    delay is not distortion.

    Returns (displacements in samples, stray actual edges, swallowed ideal
    edges).
    """
    tol = OS // 2 if tol is None else tol            # half a cell
    a, b = _edges(w), _edges(ref)
    if len(a) < 64 or len(b) < 64:
        return None

    def match(off):
        i = np.clip(np.searchsorted(b, a - off), 1, len(b) - 1)
        left, right = b[i - 1], b[i]
        near = np.where((a - off - left) <= (right - (a - off)), left, right)
        return (a - off - near).astype(np.float64), near

    # coarse search for the bulk delay: the offset that puts the most edges
    # on top of an ideal edge.
    probe = np.arange(-4 * OS, 4 * OS + 1)
    score = [int((np.abs(match(o)[0]) <= 2).sum()) for o in probe]
    off = int(probe[int(np.argmax(score))])
    d, near = match(off)
    ok = np.abs(d) <= tol
    hit = np.unique(near[ok])
    return d[ok], int((~ok).sum()), int(len(b) - len(hit))


def _rep_row(ln, bits, km, n, seeds, secs, urban_imp, cell_ns):
    """One (section length, repeater count) point, averaged over seeds."""
    rms = p2p = 0.0
    stray = lost = 0
    bers, lofs, lockeds = [], [], []
    for sd in seeds:
        w, ref = _dm_chain(ln, n, km, imp=urban_imp, seed=sd)
        disp = _displacement(w, ref)
        if disp is not None:
            d, ns_, nl = disp
            # centred: a residual constant delay is not distortion
            rms += float(d.std()) / len(seeds)
            p2p += float(d.max() - d.min()) / len(seeds)
            stray += ns_
            lost += nl
        b = fast.mono_decode(w, OS, thr=0.75, dead=0.25)
        st = mf2.framer(b)
        lofs.append(st['lof_events'])
        lockeds.append(100.0 * st['frames'] / max(len(b) // FLEN, 1))
        if st['pos'].size:
            got = b[st['pos'] + mf2.CBIT[0]]
            m = min(len(got), len(bits[0])) - 64
            e = min(float((got[:m] != bits[0][i0:i0 + m]).mean())
                    for i0 in range(64)) if m > 0 else 1.0
            bers.append(e)
        else:
            bers.append(1.0)
    samp_ns = 1e9 / (LINE * OS)
    return dict(km=km, hops=n, span=(n + 1) * km,
                rms_ns=rms * samp_ns, p2p_ns=p2p * samp_ns,
                pct=100 * p2p * samp_ns / cell_ns,
                stray=stray, lost=lost,
                ber=float(np.mean(bers)),
                locked=float(np.mean(lockeds)),
                lof_per_s=float(np.mean(lofs)) / secs)


def repeater(secs=1.0, seeds=(1, 2, 3), sections=(1.0, 1.5, 2.0),
             hops=(0, 1, 2, 3, 4, 6, 8, 12, 16, 24, 32), urban_imp=0.0):
    """How many non-reclocking repeaters a biphase span carries.

    A biphase repeater is a comparator and a driver -- no clock, no one-shots,
    nothing per-rate but the input filter, and no timing element in the hut to
    drift or to slip against.  It restores amplitude completely and edge
    timing not at all, so the span is bounded by accumulated edge
    displacement rather than by loss.  This measures where that runs out.
    """
    cell_ns = 1e9 / LINE
    print('MF2 REPEATERED SPAN -- non-reclocking regenerators')
    print('  A biphase repeater is a comparator and a driver: no clock, no')
    print('  one-shots, nothing per-rate but the input filter, nothing in the')
    print('  hut to drift and no clock to slip against.  It restores amplitude')
    print('  completely and edge timing not at all.')
    print(f'  Cell {cell_ns:.0f} ns.  The §9.4 classifier rounds a gap against')
    print(f'  0.75 cell with +/-13% tolerance measured (mf8-spec.md §9.4), so')
    print(f'  the peak-to-peak budget for displacement is about '
          f'{0.26 * cell_ns:.0f} ns.')
    print(f'  Window {secs:.1f} s x {len(seeds)} seeds'
          + (f', {urban_imp:.0f} impulses/s a section' if urban_imp else ', quiet')
          + '.\n')

    src, bits, p = sources(secs=secs)
    A = [np.zeros(len(bits[0]), np.uint8) for _ in range(NCH)]
    ln = mf2.build(bits, A)
    rows, limits = [], {}
    hdr = (f'  {"repeaters":>9s} {"span":>8s} {"edge sd":>10s} {"edge p2p":>10s}'
           f' {"% of cell":>10s} {"stray":>7s} {"lost":>8s} {"locked":>8s}'
           f' {"BER":>10s}')
    for km in sections:
        print(f'  {km:g} km a section\n')
        print(hdr)
        limits[km] = None
        fails = 0
        for n in hops:
            r = _rep_row(ln, bits, km, n, seeds, secs, urban_imp, cell_ns)
            rows.append(r)
            print(f'  {n:>9d} {r["span"]:>7.1f}k {r["rms_ns"]:>9.0f}n '
                  f'{r["p2p_ns"]:>9.0f}n {r["pct"]:>9.1f}% {r["stray"]:>7d} '
                  f'{r["lost"]:>8d} {r["locked"]:>7.1f}% {r["ber"]:>10.2e}',
                  flush=True)
            if r['ber'] < 1e-4 and r['lost'] < 16 and r['locked'] > 95.0:
                limits[km] = n
                fails = 0
            else:
                fails += 1
                if fails >= 2:        # two past the wall is enough
                    print(f'  {"":>9s} (stopped: {km:g} km is done at '
                          f'{limits[km]} repeaters)')
                    break
        print()

    print('  SPAN LIMIT -- the last hop count that still decodes\n')
    print(f'    {"section":>9s} {"repeaters":>10s} {"total span":>12s}')
    for km, n in limits.items():
        print(f'    {km:>8g}k {("none" if n is None else str(n)):>10s} '
              + (f'{(n + 1) * km:>11.1f}k' if n is not None else f'{"-":>12s}'))

    print('\n  "locked" is the fraction of the clip the framer held, and BER is')
    print('  scored INSIDE that -- so read the two together: a high BER with a')
    print('  low locked% is a chain that broke, and so is a low BER with one.')
    print('  The span limit below requires locked > 95% as well as BER = 0.')
    print('\n  Edges are matched to the nearest ideal edge within half a cell,')
    print('  after the chain\'s bulk delay -- one input filter a section -- is')
    print('  removed, because a constant delay is not distortion.  "stray" is')
    print('  an edge the chain invented and "lost" one it swallowed; either is')
    print('  what a biphase slip is made of.')
    print('\n  The displacement accumulates as a BIAS, not a random walk: each')
    print('  section\'s comparator fires a little late or a little early on the')
    print('  same side every time, and the next section re-launches that as a')
    print('  real edge.  So the lever is where the slicing level sits -- DC')
    print('  restore and threshold centring -- not gain, and not more sections.')
    return rows


TARGETS = {'clean': clean, 'noise': noise, 'plant': plant,
           'span': span, 'repeater': repeater}

if __name__ == '__main__':
    for k in (sys.argv[1:] or list(TARGETS)):
        TARGETS[k]()
        print()
