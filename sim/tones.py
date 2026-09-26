"""
Call-progress tones as a looped CVSD bit stream, and what generates them.

A tone in this exchange is a C bit stream like any other (features.md §1),
so it can come from an analog oscillator through a CVSD encoder, or from a ROM
played on repeat.  This script measures the ROM route and sizes it, compares the
tone plans it could carry, and checks the two things that decide the analog
card: whether a cheap switch can make a warble, and where a cadence seam lands.

Five measurements, all against mf8-spec.md 12.1's law at 64 kbps:

    loops       the shortest seamless loop per tone, and what looping costs
                against an encoder that runs for ever
    rom         loop length vs frequency accuracy: what ROM depth buys
    plans       six historical tone plans and the proposed one, scored on
                CVSD quality, ROM planes, and analog oscillator count
    warble      the Australian three-line warble, five ways of making it.
                The result that matters is negative: gating the encoder's
                input with a square, which is how common/tones.md §5.1 makes a
                CADENCE, splatters when run at a WARBLE rate
    cadence     the cadence tick as a binary divide off TX_CLK, and the
                tone-to-FILL seam

A loop must be a whole number of bits AND a whole number of cycles of every
component, so with an N-bit loop every frequency must be a multiple of 64000/N.
An 8192-bit loop is 128 ms and puts every tone on a 7.8125 Hz grid.

tones.log is the run.  common/tones.md is what it decided.
"""
import math, sys
import numpy as np
import audio, cvsd, mf8

RATE = 64000
P = mf8.params(RATE)
N8K = 8192                        # a 27C64: 8192 addresses, so an 8192-bit plane
GRID = RATE / N8K                 # 7.8125 Hz
SKIP = int(0.2 * RATE)


# ------------------------------------------------------------------ tone algebra

def add(*fs):
    """Independent oscillators summed."""
    return ('sum', fs, [(f, 1.0) for f in fs])


def am(carrier, mod, depth=1.0, grid=None):
    """One carrier times one modulator: carrier * (1 + depth*2*cos(mod)).

    At depth 1.0 the three lines are equal, which is the Australian warble:
    cos(a-b) + cos(a) + cos(a+b) == cos(a) * (1 + 2*cos(b)).

    CARRIER AND MODULATION ARE SNAPPED TO THE GRID, NOT THE SIDEBANDS.  A warble
    is three EQUALLY SPACED lines; rounding each sideband on its own breaks the
    spacing and it stops being one tone.  25 Hz is not a multiple of 7.8125, so
    the nearest equal spacing is 3 steps = 23.4375 Hz, and that is what is burned.
    """
    g = grid or GRID
    c, m = round(carrier / g) * g, round(mod / g) * g
    return ('AM', (carrier, mod), [(c - m, depth), (c, 1.0), (c + m, depth)])


def on_grid(comps, n=N8K):
    g = RATE / n
    return [(round(f / g) * g, a) for f, a in comps]


def render(comps, secs, rms=None):
    t = np.arange(int(secs * RATE)) / RATE
    x = sum(a * np.sin(2 * np.pi * f * t) for f, a in comps)
    crest = 20 * math.log10(max(abs(x)) / x.std())
    return x * ((rms or mf8.NOMINAL_RMS) / x.std()), crest


def tone_snr(y, comps):
    """Power in the wanted components over everything else, 300-3400 Hz."""
    y = audio.bandlimit(y, RATE)[SKIP:]
    t = (np.arange(len(y)) + SKIP) / RATE
    A = np.column_stack([f(2 * np.pi * fr * t) for fr, _ in comps for f in (np.sin, np.cos)])
    c, *_ = np.linalg.lstsq(A, y, rcond=None)
    fit = A @ c
    return 10 * np.log10((fit ** 2).sum() / max(((y - fit) ** 2).sum(), 1e-30))


def loop_quality(comps, n=N8K, cuts=4, settle=1.5):
    """Cut `cuts` loops out of a settled encoder and play each on repeat.

    The encode must be long enough that base + 2n still lands inside it, or a
    long loop silently runs off the end and tiles a short array.
    """
    comps = on_grid(comps, n)
    if not any(300 <= f <= 3400 for f, _ in comps):
        return None, None, None
    x, crest = render(comps, (int(settle * RATE) + 2 * n + 16) / RATE)
    bits = cvsd.encode(x, P)
    base = int(settle * RATE) // n * n
    ss = []
    for k in range(cuts):
        o = base + k * n // cuts
        reps = int(1.2 * RATE) // n + 1
        ss.append(tone_snr(cvsd.decode(np.tile(bits[o:o + n], reps), P), comps))
    return max(ss), min(ss), crest


def in_band_lines(y, floor_db=-40.0, n=N8K):
    seg = audio.bandlimit(y, RATE)[SKIP:SKIP + n]
    S = np.abs(np.fft.rfft(seg * np.hanning(n)))
    f = np.fft.rfftfreq(n, 1 / RATE)
    m = (f >= 250) & (f <= 3400)
    S, f = S[m], f[m]
    thr = S.max() * 10 ** (floor_db / 20)
    idx = [i for i in range(1, len(S) - 1) if S[i] > S[i - 1] and S[i] > S[i + 1] and S[i] > thr]
    return len(idx), [f[i] for i in idx]


# ------------------------------------------------------------------ the plans

def P4(dial, ringback, busy, cannot):
    return dict(zip(('dial', 'ringback', 'busy', 'cannot-connect'), (dial, ringback, busy, cannot)))


PLANS = {
    'Bell, pre-1976':      (P4((am(600, 120), None), (am(420, 40), (400, 200, 400, 2000)),
                               (am(600, 120), (500, 500)), (am(600, 120), (250, 250))), 'low'),
    'North American':      (P4((add(350, 440), None), (add(440, 480), (2000, 4000)),
                               (add(480, 620), (500, 500)), (add(480, 620), (250, 250))), 'high'),
    'British, old GPO':    (P4((add(33, 50), None), (add(400, 450), (400, 200, 400, 2000)),
                               (add(400), (375, 375)), (add(400), None)), 'low'),
    'Australian, old':     (P4((am(400, 25), None), (am(400, 25), (400, 200, 400, 2000)),
                               (add(400), (375, 375)), (add(400), (200, 200))), 'low'),
    'Australian, modern':  (P4((add(413, 438), None), (am(425, 25), (400, 200, 400, 2000)),
                               (add(425), (375, 375)), (add(425), (375, 375))), 'med'),
    'Japanese, NTT':       (P4((add(400), None), (am(400, 16), (1000, 2000)),
                               (add(400), (500, 500)), (add(400), (250, 250))), 'med'),
    'ETSI / CEPT':         (P4((add(425), None), (add(425), (1000, 4000)),
                               (add(425), (500, 500)), (add(425), (250, 250))), 'high'),
    'TENTATIVE STANDARD':  (P4((am(425, 25), None), (am(425, 25), (400, 200, 400, 2000)),
                               (am(600, 120), (500, 500)), (am(600, 120), (250, 250))), 'this'),
}


def best_tick(ms, lo=8, hi=17):
    """Best binary divide off TX_CLK: each interval becomes round(I/tick) ticks."""
    best = None
    for n in range(lo, hi + 1):
        T = 2 ** n / RATE
        ks = [max(1, round(v / 1000 / T)) for v in ms]
        err = max(abs(k * T - v / 1000) / (v / 1000) for k, v in zip(ks, ms))
        if best is None or err < best[0]:
            best = (err, n, T, ks)
    err, n, T, ks = best
    return err * 100, n, T, ks


# ------------------------------------------------------------------ sections

def sec_loops(log):
    log('LOOPS -- the shortest seamless loop, and what looping costs')
    log('  A loop must be whole bits and whole cycles: N = 64000 / gcd(f.., 64000).')
    log('  "live" is an encoder running for ever; "loop" is N bits cut from its steady state.\n')
    log(f'  {"tone":22s} {"N bits":>7s} {"bytes":>6s} {"ms":>6s} {"live":>6s}   {"best":>6s} {"med":>6s} {"worst":>6s}  periodic?')
    for name, fs in [('1000 Hz', (1000,)), ('400 Hz', (400,)), ('425 Hz', (425,)),
                     ('440+480', (440, 480)), ('480+620', (480, 620)), ('350+440', (350, 440))]:
        g = 0
        for f in fs:
            g = math.gcd(g, int(f))
        g = math.gcd(g, RATE)
        n = RATE // g
        comps = [(f, 1.0) for f in fs]
        x, _ = render(comps, 3.0)
        bits = cvsd.encode(x, P)
        live = tone_snr(cvsd.decode(bits[:int(1.2 * RATE)], P), comps)
        base = int(2.0 * RATE) // n * n
        diff = int((bits[base:base + n] != bits[base + n:base + 2 * n]).sum())
        res = []
        for k in range(8):
            o = base + k * n // 8
            res.append(tone_snr(cvsd.decode(np.tile(bits[o:o + n], int(1.2 * RATE) // n + 1), P), comps))
        res.sort(reverse=True)
        log(f'  {name:22s} {n:7d} {n // 8:6d} {1000 * n / RATE:6.1f} {live:6.1f}   '
            f'{res[0]:6.1f} {res[len(res) // 2]:6.1f} {res[-1]:6.1f}  '
            + ('yes' if diff == 0 else f'no, {diff} bits differ'))
    log('\n  Looping costs nothing: a median cut equals the live encoder, and the best cut')
    log('  beats it, because the luckiest period the encoder ever made is played for ever.\n')


def sec_rom(log):
    log('ROM -- what depth buys.  One byte an address, 8 planes, counter on TX_CLK.')
    log('  A plane is as many bits as the part has bytes: at 64 kHz that is 128 ms per kB.\n')
    log(f'  {"N bits":>7s} {"part":>16s} {"plane":>9s} {"grid Hz":>8s} {"worst freq err":>15s} {"SNR b/w":>13s}')
    want = {'dial': (350, 440), 'ringback': (440, 480), 'busy': (480, 620)}
    for n, part in [(2048, '-'), (4096, '-'), (8192, '27C64, 8 kB'), (16384, '27C128, 16 kB'),
                    (32768, '27C256, 32 kB'), (65536, '27C512, 64 kB')]:
        g = RATE / n
        errs, ss = [], []
        for fs in want.values():
            comps = [(f, 1.0) for f in fs]
            errs += [100 * (round(f / g) * g - f) / f for f, _ in comps]
            b, w, _ = loop_quality(comps, n=n, cuts=3)
            ss += [b, w]
        log(f'  {n:7d} {part:>16s} {1000 * n / RATE:8.0f}ms {g:8.3f} '
            f'{max(errs, key=abs):+14.2f} % {max(ss):6.1f} /{min(ss):5.1f}')
    log('\n  Depth buys FREQUENCY ACCURACY and nothing else: SNR is flat over a 32x range,')
    log('  because a loop only has to contain the encoder\'s limit cycle and that settles fast.\n')


def sec_plans(log):
    log('PLANS -- six historical, and the one this exchange proposes.')
    log(f'  Tones on the {GRID:.4f} Hz grid of an 8 kB part.  "plane" letters show which')
    log('  categories share a ROM plane -- that count, not the four categories, is what costs.\n')
    rows = []
    for plan, (cats, conf) in PLANS.items():
        planes, osc = {}, set()
        log(f'  {plan}   [{conf} confidence]' if conf != 'this' else f'  {plan}')
        log(f'    {"category":15s} {"tone":14s} {"burned lines":22s} {"cadence":22s} {"pl":3s} {"SNR b/w":>13s} {"crest":>7s}')
        for cat in ('dial', 'ringback', 'busy', 'cannot-connect'):
            (kind, spec, comps), cad = cats[cat]
            key = tuple(on_grid(comps))
            if key not in planes:
                planes[key] = chr(ord('A') + len(planes))
            osc |= {spec[0]} if kind == 'AM' else set(spec)
            tone = f'{spec[0]:g}~{spec[1]:g}' if kind == 'AM' else '+'.join(f'{f:g}' for f in spec)
            burned = '+'.join(f'{f:.0f}' for f, _ in on_grid(comps))
            b, w, crest = loop_quality(comps)
            cs = 'continuous' if cad is None else '/'.join(f'{v / 1000:g}' for v in cad) + ' s'
            q = '  OUT OF BAND' if b is None else f'{b:6.1f} /{w:5.1f}'
            log(f'    {cat:15s} {tone:14s} {burned:22s} {cs:22s} {planes[key]:3s} {q:>13s} '
                + ('' if crest is None else f'{crest:5.1f}dB'))
        ms = [v for cat in cats.values() if cat[1] for v in cat[1]]
        err, n, T, ks = best_tick(ms)
        rows.append((plan, len(planes), len(osc), err, n, 1000 * T))
        log('')
    log(f'  {"plan":22s} {"ROM planes":>10s} {"analog osc":>10s} {"best cadence tick":>18s} {"worst err":>9s}')
    for plan, np_, no, err, n, T in rows:
        log(f'  {plan:22s} {np_:10d} {no:10d} {f"2^{n} = {T:.0f} ms":>18s} {err:8.1f} %')
    log('\n  Cadence divisibility separates nothing: every plan lands under 1 % on some binary')
    log('  tick, because the tick need only DIVIDE each interval, not equal their GCD.\n')


def sec_warble(log):
    log('WARBLE -- five ways to make the Australian three-line tone.')
    fc, fm = 54 * GRID, 3 * GRID
    log(f'  Grid-native: carrier {fc:.4f} Hz (nominal 425, {100 * (fc - 425) / 425:+.2f} %), '
        f'warble {fm:.4f} Hz (nominal 25, {100 * (fm - 25) / 25:+.2f} %)')
    log(f'  Lines at {fc - fm:.1f} / {fc:.1f} / {fc + fm:.1f} Hz.  25 Hz is not a multiple of the')
    log(f'  {GRID:.4f} Hz grid, so the nearest EQUAL spacing is 3 steps -- and equal it must be.\n')
    t = np.arange(int(1.6 * RATE)) / RATE

    def rc(x, tau):
        a = 1 - math.exp(-1 / (RATE * tau))
        y = np.zeros_like(x)
        v = 0.0
        for i, s in enumerate(x):
            v += (s - v) * a
            y[i] = v
        return y

    sq = np.sign(np.cos(2 * np.pi * fm * t)) * 0.5 + 0.5
    variants = [
        ('three lines, equal',      np.cos(2 * np.pi * (fc - fm) * t) + np.cos(2 * np.pi * fc * t) + np.cos(2 * np.pi * (fc + fm) * t)),
        ('carrier x (1+2cos)',      np.cos(2 * np.pi * fc * t) * (1 + 2 * np.cos(2 * np.pi * fm * t))),
        ('sine AM, depth 0.5',      np.cos(2 * np.pi * fc * t) * (1 + 0.5 * np.cos(2 * np.pi * fm * t))),
        ('SQUARE gate at 23 Hz',    np.cos(2 * np.pi * fc * t) * sq),
        ('square gate, RC 4 ms',    np.cos(2 * np.pi * fc * t) * rc(sq, 0.004)),
        ('steady carrier',          np.cos(2 * np.pi * fc * t)),
    ]
    comps = [(fc - fm, 1.0), (fc, 1.0), (fc + fm, 1.0)]
    log(f'  {"variant":24s} {"crest":>7s} {"SNR b/w":>13s} {"lines":>6s}  in-band lines above -40 dB')
    for name, x in variants:
        x = x * (mf8.NOMINAL_RMS / x.std())
        crest = 20 * math.log10(max(abs(x)) / x.std())
        bits = cvsd.encode(x, P)
        base = int(1.2 * RATE) // N8K * N8K
        ss = [tone_snr(cvsd.decode(np.tile(bits[base + k * N8K // 4:base + k * N8K // 4 + N8K], 10), P), comps)
              for k in range(4)]
        nl, ll = in_band_lines(cvsd.decode(np.tile(bits[base:base + N8K], 10), P))
        log(f'  {name:24s} {crest:6.1f}dB {max(ss):6.1f} /{min(ss):5.1f} {nl:6d}  '
            + ' '.join(f'{f:.0f}' for f in ll[:7]))
    log('\n  The negative result is the one that matters.  common/tones.md §5.1 makes a CADENCE by')
    log('  muting the encoder\'s input, which is right at 2 Hz.  At a WARBLE rate the same square')
    log('  splatters: 50-odd lines and 23 dB lost.  An analog card needs a true four-quadrant')
    log('  multiplier -- the LM13700 of mf8-spec.md 12.1 -- and may not use a switch.\n')


def sec_cadence(log):
    log('CADENCE -- the tick as a binary divide off TX_CLK, and the seam.\n')
    sets = {
        'UK/AU/NZ double ring':        (400, 200, 400, 2000),
        'proposed: ring + busy + cc':  (400, 200, 400, 2000, 375, 375, 250, 250),
        'North American, all four':    (2000, 4000, 500, 500, 250, 250),
        'ETSI, all four':              (1000, 4000, 500, 500, 250, 250),
    }
    log(f'  {"cadence set":30s} {"tick":>9s} {"2^n":>7s} {"worst err":>10s}  ticks')
    for name, ms in sets.items():
        err, n, T, ks = best_tick(ms)
        log(f'  {name:30s} {1000 * T:7.1f}ms {f"2^{n}":>7s} {err:9.1f} %  {"/".join(map(str, ks))}')
    log('\n  The proposed set at 2^12 = 64 ms, which is bit 12 of the ROM address counter:')
    T = 4096 / RATE
    for label, v in [('ring burst', 400), ('ring gap', 200), ('ring silence', 2000),
                     ('busy on/off', 375), ('cannot-complete', 250)]:
        k = round(v / 1000 / T)
        log(f'    {label:16s} {v:5d} ms -> {k:2d} ticks = {1000 * k * T:7.1f} ms  ({100 * (k * T - v / 1000) / (v / 1000):+5.1f} %)')
    log(f'    {"ring period":16s} {3000:5d} ms -> {6 + 3 + 6 + 31:2d} ticks = {1000 * 46 * T:7.1f} ms'
        f'  ({100 * (46 * T - 3.0) / 3.0:+5.1f} %)   mod-46')

    fc, fm = 54 * GRID, 3 * GRID
    comps = [(fc, 1.0)]
    x, _ = render(comps, 3.0)
    bits = cvsd.encode(x, P)
    loop = bits[int(2.0 * RATE) // N8K * N8K:][:N8K]
    fill = np.tile(np.array([1, 0], dtype=np.uint8), RATE // 4)
    run = np.tile(loop, 80)
    ref = audio.bandlimit(cvsd.decode(run, P), RATE)[SKIP:].std()
    pk = []
    for k in range(32):
        cut = 40 * N8K + k * N8K // 32
        s = np.concatenate([run[:cut], fill, run[:RATE // 4]])
        y = audio.bandlimit(cvsd.decode(s, P), RATE)
        a = cut + int(0.010 * RATE)
        pk.append(np.abs(y[a:a + int(0.05 * RATE)]).max() / ref)
    log(f'\n  Tone -> FILL, cut at 32 points in the loop, residue 10-60 ms after the cut, re tone rms:')
    log(f'    worst {20 * math.log10(max(pk)):.1f} dB, median {20 * math.log10(float(np.median(pk))):.1f} dB.')
    log('  The 1 ms integrator is its own soft stop: gating against FILL needs no synchronisation.\n')


TICK = 4096                       # 64 ms, bit 12 of the ROM address counter


def cadenced(loop, cad, secs):
    """A free-running ROM gated against FILL by a cadence on the 64 ms tick.

    The address counter never stops, so the tone resumes at whatever phase the
    counter reached -- which is what the hardware does, and why the seam has to
    be measured at every cut (sec_cadence).
    """
    n = int(secs * RATE)
    run = np.tile(loop, n // len(loop) + 2)[:n]
    fill = np.tile(np.array([1, 0], dtype=np.uint8), n // 2 + 1)[:n]
    if cad is None:
        return run
    gate = np.zeros(n, dtype=bool)
    i, j = 0, 0
    while i < n:
        k = round(cad[j % len(cad)] / 1000 * RATE / TICK) * TICK
        if j % 2 == 0:
            gate[i:i + k] = True
        i += k
        j += 1
    return np.where(gate, run, fill).astype(np.uint8)


def best_loop(comps, n=N8K, cuts=8, settle=2.0):
    """The best cut of a settled encoder -- what a real image would be burned from."""
    g = on_grid(comps, n)
    x, _ = render(g, (int(settle * RATE) + 2 * n + 16) / RATE)
    bits = cvsd.encode(x, P)
    base = int(settle * RATE) // n * n
    best, off = None, base
    for k in range(cuts):
        o = base + k * n // cuts
        sn = tone_snr(cvsd.decode(np.tile(bits[o:o + n], 10), P), g)
        if best is None or sn > best:
            best, off = sn, o
    return bits[off:off + n], best


def sec_image(log):
    """Burn the plan into verilog/rtl/tone_rom.hex -- one byte an address."""
    import os
    log('IMAGE -- the ROM, as the card holds it.')
    log('  8192 addresses, one byte each.  Bit 0 is plane A, bit 1 plane B, the rest spare.')
    log('  A plane is the same image for two tones; what separates them is the cadence gate,')
    log('  which is a counter tap and not in the ROM at all (common/tones.md §4.1).\n')
    planes = [('A', 'dial and ringback', am(425, 25)),
              ('B', 'busy and cannot-complete', am(600, 120))]
    img = np.zeros(N8K, dtype=int)
    log(f'  {"bit":>3s} {"plane":5s} {"serves":26s} {"burned lines":24s} {"SNR":>6s} {"ones":>10s}')
    for i, (name, serves, (kind, spec, comps)) in enumerate(planes):
        loop, sn = best_loop(comps)
        img |= loop.astype(int) << i
        g = on_grid(comps)
        log(f'  {i:3d} {name:5s} {serves:26s} '
            f'{"+".join(f"{f:.0f}" for f, _ in g):24s} {sn:5.1f}  {int(loop.sum()):5d}/{N8K}')
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(here, os.pardir, 'verilog', 'rtl', 'tone_rom.hex')
    with open(out, 'w') as f:
        f.write('// tone_rom.hex -- generated by sim/tones.py image.  Do not edit.\n')
        f.write('// bit 0 = plane A (425~25), bit 1 = plane B (600~120).\n')
        for v in img:
            f.write(f'{v:02x}\n')
    log(f'\n  {N8K} bytes -> verilog/rtl/tone_rom.hex')
    log('  Each plane is DC balanced to within a bit, so nothing in the decoder drifts:')
    for i, (name, _, _) in enumerate(planes):
        ones = int(((img >> i) & 1).sum())
        log(f'    plane {name}: {ones} ones of {N8K}  ({200.0 * ones / N8K - 100:+.2f} % from balance)')
    log('')


def sec_render(log):
    log('RENDER -- the tentative standard, and the alternatives, as 8 kHz wavs in sim/out/.')
    log('  Each is the ROM loop the card would hold, gated as the card would gate it, through')
    log('  a real decoder.  Written at a common gain so the four are comparable by ear.\n')
    import os
    d = audio.here('out')
    os.makedirs(d, exist_ok=True)
    SECS, GAIN = 9.0, 3.0
    items = [
        ('dial',           am(425, 25),   None,                     'Australian warble, continuous'),
        ('ringback',       am(425, 25),   (400, 200, 400, 2000),    'Australian warble, double ring'),
        ('busy',           am(600, 120),  (500, 500),               'North American old style, 60 IPM'),
        ('cannot-connect', am(600, 120),  (250, 250),               'North American old style, 120 IPM'),
        ('alt-dial-etsi',  add(425),      None,                     'for comparison: a steady 425'),
        ('alt-busy-na',    add(480, 620), (500, 500),               'for comparison: the modern NA busy'),
    ]
    log(f'  {"file":28s} {"tone":14s} {"burned lines":24s} {"cadence":22s} {"SNR":>6s}')
    for name, (kind, spec, comps), cad, note in items:
        g = on_grid(comps)
        x, _ = render(g, 3.0)
        bits = cvsd.encode(x, P)
        base = int(2.0 * RATE) // N8K * N8K
        best, off = None, 0
        for k in range(8):                      # burn the best cut, as a real image would
            o = base + k * N8K // 8
            s = tone_snr(cvsd.decode(np.tile(bits[o:o + N8K], 10), P), g)
            if best is None or s > best:
                best, off = s, o
        loop = bits[off:off + N8K]
        y = cvsd.decode(cadenced(loop, cad, SECS), P)
        y = audio.resample_to(audio.bandlimit(y, RATE), RATE, 8000) * GAIN
        audio.write_wav(os.path.join(d, f'tone_{name}.wav'), y, 8000)
        tone = f'{spec[0]:g}~{spec[1]:g}' if kind == 'AM' else '+'.join(f'{f:g}' for f in spec)
        cs = 'continuous' if cad is None else '/'.join(f'{v / 1000:g}' for v in cad) + ' s'
        log(f'  tone_{name + ".wav":23s} {tone:14s} {"+".join(f"{f:.0f}" for f, _ in g):24s} {cs:22s} {best:5.1f}   {note}')
    log(f'\n  {SECS:.0f} s each at 8 kHz, gain {GAIN:g}.  sim/out/ is not committed.\n')


def main():
    out = open(audio.here('tones.log'), 'w')

    def log(s=''):
        print(s, flush=True)
        out.write(s + '\n')
        out.flush()

    log('TONES -- call-progress tones as looped CVSD, and what generates them')
    log(f'  64 kbps, mf8-spec.md 12.1 law, level = NOMINAL_RMS {mf8.NOMINAL_RMS}, 8 kB ROM grid'
        f' = {GRID:.4f} Hz\n')
    want = sys.argv[1:] or ['loops', 'rom', 'plans', 'warble', 'cadence', 'image', 'render']
    for name in want:
        {'loops': sec_loops, 'rom': sec_rom, 'plans': sec_plans,
         'warble': sec_warble, 'cadence': sec_cadence, 'image': sec_image,
         'render': sec_render}[name](log)
        log('-' * 100 + '\n')
    out.close()


if __name__ == '__main__':
    main()
