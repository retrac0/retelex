"""
What must the encoder's comparator achieve, and can one section of a
general-purpose quad op amp do the job?

The channel card's CVSD encoder compares the band-limited audio with its own
integrator voltage, and a 74HC74 samples that comparison on the frame clock edge
(docs/channel-card.md section 2).  The card draws an LM311 there.  Every other
analog function on the card is an op amp (4 filter sections, 2 integrator
buffers), so an op-amp section in place of the LM311 would leave the card with a
single op-amp type.

Method, part 1: the requirement.  card.py models the encoder at circuit level with
three comparator imperfections:

    cmp_off     input offset, FS
    cmp_hyst    a dead band, full width, FS, inside which the flip-flop keeps its
                previous decision (hysteresis, or an output too slow to reach the
                logic threshold on small overdrive)
    cmp_delay   the decision reflects the inputs a fraction of a bit earlier,
                interpolated along the integrator ramp

Each is swept alone at 16, 32 and 64 kbps on the seven talkers (30 s, nominal
level, decoder nominal), then in combination.  An idle channel (zero input) shows
what each does to CVSD silence: the C-bit pattern, and the decoder output after
audio.reconstruct in dB re nominal speech rms.

Two scores are reported for every speech case, mean and worst talker:

    card.score   the repository metric, as specified
    robust       the same segSNR (reconstruct, gain match, 20 ms frames) with the
                 decoder output's mean removed -- the output transformer passes no
                 DC -- and aligned at the best sub-sample delay within +-1.5
                 samples instead of audio.align's cross-correlation peak.

The second exists because the first was found to be unfit for losses under a few
dB: section 0 shows audio.align choosing a lag one or two samples from the segSNR
optimum on some talkers, which costs those talkers 3-6 dB and moves when a
perturbation shifts the output by a fraction of a sample.  A comparator offset
also puts DC in the decoder output, which card.score counts as error.  The
tolerances and the specification are taken from the robust score.

Method, part 2: an op amp in the loop.  card.py's dead band only stands in for a
slow op amp.  Section 7 swaps the ideal comparator for a behavioural op amp:
single pole (gain-bandwidth GBW, open-loop gain A0), slew limit, output rails on
either side of the flip-flop's logic threshold, an optional overload-recovery dead
time, and an optional gain stage ahead of it (a second section as a difference
amplifier, single pole at GBW / gain).  The integrator ramps linearly across each
bit, the audio is interpolated linearly, and the op amp is integrated at 64
substeps per bit.  That loop is C, compiled at first use from the source in this
file into the temp directory with card_fast.c's flags; made ideal it is
bit-identical to card.encode, which section 7 checks.

Part numbers and datasheet figures in section 7 are representative classes with
their parameters printed beside them.  They are recalled, not measured.

Scale: full scale (FS) = 1 V is the worked example in docs/channel-card.md 2.3;
0.5 V is given as well.

Usage:  python3 card_comparator.py [sweeps|idle|opamp|all]      (default all;
        section 8, the specification, needs all)
"""
import ctypes, hashlib, os, subprocess, sys, tempfile
import multiprocessing as mp
import numpy as np
import audio, card, run

SECS = 30.0                 # every speech number: 30 s clips
IDLE_SECS = 10.0            # idle channel: 10 s, first second discarded
WORKERS = 2                 # shared 8-core machine
NOM_RMS = run.NOMINAL_RMS   # 0.15 FS
OFFS = (0.0, 1e-4, 3e-4, 1e-3, 3e-3, 1e-2, 3e-2)
HYSTS = (0.0, 1e-4, 3e-4, 1e-3, 3e-3, 1e-2, 3e-2)
DELAYS = (0.0, 0.02, 0.05, 0.1, 0.2, 0.3, 0.5)
LIMITS = (0.5, 1.0)         # dB of segSNR loss that defines a tolerance
FSV = (1.0, 0.5)            # full scale in volts
SCORES = ('card.score', 'robust')


def hdr(t):
    print('\n' + '=' * 78 + f'\n{t}\n' + '=' * 78, flush=True)


def step_min(rate):
    return float(card.CardParams(rate).vector()[5])


# ------------------------------------------------------------ robust score
_LAG = 4
_NODES = np.arange(-_LAG, _LAG + 1)


def _lagrange(d):
    """Weights on o[k-4..k+4] that interpolate o at k + d."""
    c = np.ones(len(_NODES))
    for i, a in enumerate(_NODES):
        for b in _NODES:
            if b != a:
                c[i] *= (d - b) / (a - b)
    return c


def score_robust(x, y, rate):
    """segSNR as audio.seg_snr_db computes it (20 ms frames, -45 dB silence gate,
    clip -10..35 dB, one least-squares gain), on audio.reconstruct(y) with its mean
    removed, at the sub-sample delay in [-1.5, 1.5] that maximises it.  The shifted
    output is a 9-point Lagrange interpolation (error below -50 dB at 3.4 kHz and
    16 kbps), so per-frame sums of integer-shifted products give the score at any
    delay without refiltering.  Returns (segSNR, delay in samples)."""
    o = audio.reconstruct(y, rate)
    o = o - o.mean()
    m = len(_NODES)
    w = int(rate * 0.02)
    nf = (min(len(x), len(o)) - 2 * _LAG) // w
    n = nf * w
    r = x[_LAG:_LAG + n]
    B = [o[_LAG + j:_LAG + j + n] for j in _NODES]
    fsum = lambda v: v.reshape(nf, w).sum(1)
    P = fsum(r * r)
    X = np.array([fsum(r * b) for b in B]).T
    G = np.empty((nf, m, m))
    for i in range(m):
        for j in range(i, m):
            G[:, i, j] = G[:, j, i] = fsum(B[i] * B[j])
    Xs, Gs = X.sum(0), G.sum(0)
    act = 10 * np.log10(P / w + 1e-20) > -45.0
    Pa, Xa, Ga = P[act], X[act], G[act]

    def seg(d):
        c = _lagrange(d)
        g = (Xs @ c) / max(c @ Gs @ c, 1e-20)
        pe = Pa - 2 * g * (Xa @ c) + g * g * np.einsum('i,fij,j->f', c, Ga, c)
        return float(np.clip(10 * np.log10(Pa / np.maximum(pe, 1e-20)), -10, 35).mean())

    grid = np.arange(-1.5, 1.5001, 0.1)
    best = float(grid[int(np.argmax([seg(d) for d in grid]))])
    for step in (0.05, 0.025, 0.0125):
        best = max((best - step, best, best + step), key=seg)
    return seg(best), best


# ------------------------------------------------------------ behavioural op amp
OPAMP_C = r'''
#include <stdint.h>
#include <math.h>
/* card_fast.c's encoder with the comparator replaced by a behavioural op amp.
 * prm: 0 rate  1 run  2 tau_syl  3 tau_int  4 step_max  5 step_min
 *      6 FS volts  7 2*pi*GBW (<=0: ideal comparator)  8 slew V/s
 *      9 rail above threshold V  10 rail below threshold V (negative)
 *      11 Vos V (input referred)  12 overload recovery s  13 substeps per bit
 *      14 A0 (0: infinite)
 *      15 gain stage gain (<=1: none)  16 its 2*pi*GBW  17 its rail, +-V
 * The integrator ramps linearly from its value at the previous edge to its value
 * at this edge; the audio is interpolated linearly between samples.  The op amp
 * output v is volts about the logic threshold; the flip-flop takes v >= 0. */
void c_opamp_encode(const double *x, long n, const double *p,
                    uint8_t *bits, double *vout) {
    double dt = 1.0 / p[0];
    int run = (int)p[1];
    unsigned mask = (1u << run) - 1u;
    double a_syl = 1.0 - exp(-dt / p[2]);
    double a_int = exp(-dt / p[3]);
    double k = dt * p[0];
    double fs = p[6], wt = p[7], sr = p[8], vhi = p[9], vlo = p[10], vos = p[11];
    double trec = p[12], a0 = p[14], ga = p[15], prail = p[17];
    int M = (int)p[13];
    double h = dt / M;
    double apre = ga > 1 ? 1.0 - exp(-h * p[16] / ga) : 1.0;
    double y = 0.0, yprev = 0.0, xprev = x[0], syl = 0.0, v = 0.0, stuck = 0.0, pre = 0.0;
    unsigned hist = 0;
    for (long i = 0; i < n; i++) {
        int b;
        if (wt <= 0) {
            b = x[i] - y - vos / fs >= 0;
        } else {
            double ua = fs * (xprev - yprev) - vos;
            double du = (fs * (x[i] - y) - vos - ua) / M;
            for (int j = 0; j < M; j++) {
                double um = ua + (j + 0.5) * du;
                if (ga > 1) {
                    double dp = (ga * um - pre) * apre, lim = sr * h;
                    if (dp > lim) dp = lim; else if (dp < -lim) dp = -lim;
                    pre += dp;
                    if (pre > prail) pre = prail; else if (pre < -prail) pre = -prail;
                    um = pre;
                }
                double dv = wt * (um - (a0 > 0 ? v / a0 : 0.0));
                if (dv > sr) dv = sr; else if (dv < -sr) dv = -sr;
                if ((v >= vhi && dv >= 0) || (v <= vlo && dv <= 0)) { stuck = trec; continue; }
                if (stuck > 0 && (v >= vhi || v <= vlo)) { stuck -= h; continue; }
                v += dv * h;
                if (v > vhi) v = vhi; else if (v < vlo) v = vlo;
            }
            b = v >= 0;
        }
        bits[i] = (uint8_t)b;
        hist = ((hist << 1) | (unsigned)b) & mask;
        double coin = (hist == 0 || hist == mask) ? 1.0 : 0.0;
        syl += (coin - syl) * a_syl;
        double g = 1.0 * syl + 0.0;
        if (g < 0) g = 0;
        double s = p[5] + g * (p[4] - p[5]);
        if (s < 0) s = 0;
        yprev = y;
        y = (y + (b ? s * (k * 1.0) : -s * (k * 1.0))) * a_int;
        xprev = x[i];
        if (vout) vout[i] = v;
    }
}
'''
_OPAMP = None


def _opamp_lib():
    global _OPAMP
    if _OPAMP is None:
        tag = hashlib.sha1(OPAMP_C.encode()).hexdigest()[:12]
        so = os.path.join(tempfile.gettempdir(), f'card_comparator_{tag}.so')
        if not os.path.exists(so):
            src = so[:-3] + f'.{os.getpid()}.c'
            with open(src, 'w') as f:
                f.write(OPAMP_C)
            tmp = so + f'.{os.getpid()}'
            subprocess.check_call(['gcc', '-O3', '-march=native', '-ffp-contract=off', '-shared',
                                   '-fPIC', '-o', tmp, src, '-lm'])
            os.replace(tmp, so)
            os.remove(src)
        lib = ctypes.CDLL(so)
        lib.c_opamp_encode.argtypes = [np.ctypeslib.ndpointer(np.float64), ctypes.c_long,
                                       np.ctypeslib.ndpointer(np.float64),
                                       np.ctypeslib.ndpointer(np.uint8), ctypes.c_void_p]
        _OPAMP = lib
    return _OPAMP


def opamp_encode(x, rate, gbw=0.0, sr=13e6, vhi=2.5, vlo=-2.5, vos=0.0, fsv=1.0,
                 trec=0.0, a0=1e5, pre=0.0, pre_gbw=None, pre_rail=2.5, m=64):
    """Audio at `rate` -> bits, with the comparator an op amp.  gbw in Hz (0 is an
    ideal comparator), sr in V/s, rails vhi/vlo in volts about the logic
    threshold, vos in volts, fsv = volts per FS, trec overload recovery in s,
    pre = gain of a stage ahead of it (same GBW and slew unless pre_gbw given)."""
    cp = card.CardParams(rate).vector()
    prm = np.array([cp[0], cp[1], cp[2], cp[3], cp[4], cp[5], fsv, 2 * np.pi * gbw, sr,
                    vhi, vlo, vos, trec, m, a0, pre,
                    2 * np.pi * (gbw if pre_gbw is None else pre_gbw), pre_rail], np.float64)
    x = np.ascontiguousarray(x, np.float64)
    bits = np.empty(len(x), np.uint8)
    _opamp_lib().c_opamp_encode(x, len(x), prm, bits, None)
    return bits


def encoder(kind, rate, prm):
    if kind == 'card':
        return lambda x: card.encode(x, card.CardParams(rate, **prm))
    return lambda x: opamp_encode(x, rate, **prm)


# -------------------------------------------------------------- speech trials
_X = {}


def talker(rate, ti):
    if (rate, ti) not in _X:
        _X[(rate, ti)] = card.load_talker(card.TALKERS[ti], rate, SECS)
    return _X[(rate, ti)]


def trial(job):
    kind, rate, ti, prm = job
    x = talker(rate, ti)
    bits = encoder(kind, rate, dict(prm))(x)
    y = card.decode(bits, card.CardParams(rate))
    s, d = score_robust(x, y, rate)
    return card.score(x, y, rate), s, d


_MEMO, _POOL = {}, None


def evaluate(cases):
    """cases: (kind, rate, prm dict).  Returns, per case, a 3 x 7 array: row 0
    card.score, row 1 robust, row 2 robust's delay; one column per talker."""
    global _POOL
    keys = [(k, r, tuple(sorted(p.items()))) for k, r, p in cases]
    todo = sorted({(k, r, ti, pp) for k, r, pp in keys for ti in range(len(card.TALKERS))}
                  - _MEMO.keys(), key=lambda j: (-j[1], j[0], j[3], j[2]))
    if todo:
        if _POOL is None:
            _opamp_lib()                                  # compile once, before forking
            _POOL = mp.get_context('fork').Pool(WORKERS)
        for j, res in zip(todo, _POOL.imap(trial, todo, chunksize=1)):
            _MEMO[j] = res
    return [np.array([_MEMO[(k, r, ti, pp)] for ti in range(len(card.TALKERS))]).T
            for k, r, pp in keys]


def losses(a, nom, m):
    """(mean, worst, mean loss, worst loss) of score row m against the nominal."""
    mean, worst = float(a[m].mean()), float(a[m].min())
    return mean, worst, float(nom[m].mean()) - mean, float(nom[m].min()) - worst


def cells(a, nom):
    out = []
    for m in (0, 1):
        mean, worst, lm, lw = losses(a, nom, m)
        out.append(f'{mean:6.2f} {worst:6.2f} {lm:5.2f}/{lw:5.2f}')
    return '  '.join(out) + f'  {a[2].mean():+5.2f}'


CELL_HEAD = (f'{"mean":>6s} {"worst":>6s} {"loss m/w":>11s}  {"mean":>6s} {"worst":>6s} '
             f'{"loss m/w":>11s}  {"delay":>5s}')
CELL_TOP = f'{"-- card.score --":^26s}  {"-- robust --":^26s}'


def binding(a, nom, m=1):
    """The larger of the mean loss and the worst-talker loss."""
    _, _, lm, lw = losses(a, nom, m)
    return max(lm, lw)


# ---------------------------------------------------------------- idle channel
def idle(kind, rate, prm, lead=False):
    """Zero input for IDLE_SECS; the first second is discarded.  lead=True puts
    1 s of talker1 in front, so the encoder falls silent from speech rather than
    starting from rest; that second is discarded too."""
    n = int(IDLE_SECS * rate)
    x = np.zeros(n)
    sk = rate
    if lead:
        x = np.concatenate([card.load_talker(card.TALKERS[0], rate, 1.0)[:rate], x])
        sk += rate
    bits = encoder(kind, rate, prm)(x)
    y = card.decode(bits, card.CardParams(rate))
    b = bits[sk:].astype(np.int8)
    alt = float(np.mean(b[1:] != b[:-1]))
    edges = np.flatnonzero(np.diff(b) != 0)
    longest = int(np.diff(edges).max()) if len(edges) > 1 else len(b)
    o = audio.reconstruct(y, rate)[sk:]
    ac = o - o.mean()
    vb = audio.bandlimit(ac, rate)                       # 300-3400 Hz
    db = lambda v: 20 * np.log10(max(v, 1e-12) / NOM_RMS)
    spec = np.abs(np.fft.rfft(ac * np.hanning(len(ac))))
    f = np.fft.rfftfreq(len(ac), 1.0 / rate)
    band = (f >= 5.0) & (f <= 4000.0)
    period = next((p for p in range(2, 9) if np.array_equal(b[p:], b[:-p])), 0)
    word = ''.join(map(str, b[:period]))
    word = max(word[i:] + word[:i] for i in range(period)) if period else '-'
    return dict(alt=alt, longest=longest, duty=float(b.mean()), dc=float(o.mean()),
                total=db(np.sqrt(np.mean(o ** 2))), ac=db(ac.std()), vband=db(vb.std()),
                tone=float(f[band][np.argmax(spec[band])]), period=period, word=word)


def idle_row(label, d):
    tone = f'{d["tone"]:7.0f}' if d['vband'] > -60 else '      -'
    return (f'  {label:>10s}  {d["word"]:>8s} {d["alt"]:6.4f} {d["longest"]:4d} {d["duty"]:6.3f} '
            f'{d["dc"]:+9.5f} {d["total"]:7.1f} {d["ac"]:7.1f} {d["vband"]:7.1f} {tone}')


IDLE_HEAD = (f'  {"":>10s}  {"cycle":>8s} {"toggle":>6s} {"run":>4s} {"duty":>6s} '
             f'{"DC, FS":>9s} {"total":>7s} {"AC":>7s} {"band":>7s} {"tone Hz":>7s}')


# -------------------------------------------------------------- tolerances
def tolerance(vals, loss, limit):
    """The swept value at which `loss` first reaches `limit` dB, interpolated in
    log(value).  vals[0] is 0, the nominal card.  Returns (value, qualifier): '<'
    or '>' when the grid does not bracket it."""
    for i in range(1, len(vals)):
        if loss[i] >= limit:
            if i == 1:
                return vals[1], '<'
            a, b = np.log(vals[i - 1]), np.log(vals[i])
            f = (limit - loss[i - 1]) / (loss[i] - loss[i - 1])
            return float(np.exp(a + min(max(f, 0.0), 1.0) * (b - a))), ''
    return vals[-1], '>'


def fmt_tol(t, unit=1.0, fmt='{:.2g}'):
    return t[1] + fmt.format(t[0] * unit)


# ------------------------------------------------------------------ sections
RES = {}


def nominal():
    return dict(zip(card.RATES, evaluate([('card', r, {}) for r in card.RATES])))


def do_nominal():
    hdr('0. NOMINAL CARD, AND THE TWO SCORES  (ideal comparator, 30 s, decoder nominal)')
    nom = nominal()
    print('  per talker 1..7.  lag = audio.align\'s choice inside card.score; robust is')
    print('  aligned at its best delay, printed in samples (0 = no shift).')
    for r in card.RATES:
        x = [talker(r, ti) for ti in range(7)]
        p = card.CardParams(r)
        lags = [audio.align(xi, audio.reconstruct(card.decode(card.encode(xi, p), p), r))[2]
                for xi in x]
        a = nom[r]
        print(f'\n  {r // 1000} kbps          mean  worst    ' + '  '.join(f'{t + 1:>5d}' for t in range(7)))
        print(f'  card.score     {a[0].mean():6.2f} {a[0].min():6.2f}    ' + '  '.join(f'{s:5.2f}' for s in a[0]))
        print(f'  lag            {"":13s}    ' + '  '.join(f'{l:5d}' for l in lags))
        print(f'  robust         {a[1].mean():6.2f} {a[1].min():6.2f}    ' + '  '.join(f'{s:5.2f}' for s in a[1]))
        print(f'  robust delay   {"":13s}    ' + '  '.join(f'{d:+5.2f}' for d in a[2]))
    print('\n  slew 12000 at every rate; spec 11.1 quotes run.SLEW per rate, so its figures differ.')


def sweep(name, field, vals, note):
    hdr(name)
    print(note)
    print('  loss = nominal minus value, dB, mean / worst talker.  delay = mean robust delay, samples.')
    nom = nominal()
    out = evaluate([('card', r, {field: v} if v else {}) for r in card.RATES for v in vals])
    RES[field] = {}
    for ri, r in enumerate(card.RATES):
        rows = out[ri * len(vals):(ri + 1) * len(vals)]
        print(f'\n  {r // 1000} kbps     {CELL_TOP}')
        print(f'  {field:>9s}  {CELL_HEAD}')
        for v, a in zip(vals, rows):
            print(f'  {v:>9g}  {cells(a, nom[r])}')
        bind = {m: [binding(a, nom[r], m) for a in rows] for m in (0, 1)}
        RES[field][r] = bind
        print('  reaches ' + ';  '.join(
            f'{lim:g} dB at {fmt_tol(tolerance(vals, bind[1], lim))} robust, '
            f'{fmt_tol(tolerance(vals, bind[0], lim))} card.score' for lim in LIMITS)
              + '  (larger of mean and worst loss)')


def do_sweeps():
    do_nominal()
    sweep('1. COMPARATOR OFFSET  cmp_off, FS', 'cmp_off', OFFS,
          '  a DC error at the comparator input.')
    sweep('2. DEAD BAND / HYSTERESIS  cmp_hyst, FS full width', 'cmp_hyst', HYSTS,
          '  inside the band the flip-flop keeps its previous decision.')
    sweep('3. DECISION DELAY  cmp_delay, fraction of a bit', 'cmp_delay', DELAYS,
          '  the decision reflects the inputs this much of a bit before the clock edge.')

    hdr('4. COMBINED CORNERS  (7 talkers, 30 s)')
    lim64 = {f: tolerance(v, RES[f][64000][1], 0.5)[0]
             for f, v in (('cmp_off', OFFS), ('cmp_hyst', HYSTS), ('cmp_delay', DELAYS))}
    corners = [('A  1e-3 / 1e-3 / 0.1', dict(cmp_off=1e-3, cmp_hyst=1e-3, cmp_delay=0.1)),
               ('B  3e-3 / 3e-3 / 0.2', dict(cmp_off=3e-3, cmp_hyst=3e-3, cmp_delay=0.2)),
               ('B- -3e-3 / 3e-3 / 0.2', dict(cmp_off=-3e-3, cmp_hyst=3e-3, cmp_delay=0.2)),
               ('C  1e-2 / 3e-3 / 0.2', dict(cmp_off=1e-2, cmp_hyst=3e-3, cmp_delay=0.2)),
               ('D  3e-3 / 1e-2 / 0.3', dict(cmp_off=3e-3, cmp_hyst=1e-2, cmp_delay=0.3)),
               ('E  3e-3 / 1e-3 / 0.1', dict(cmp_off=3e-3, cmp_hyst=1e-3, cmp_delay=0.1)),
               ('F  64k 0.5 dB limits together', dict(lim64))]
    print('  corner = offset FS / dead band FS / delay bit.  F = ' +
          ', '.join(f'{k} {v:.3g}' for k, v in lim64.items()) +
          '\n  (each at the value where its own robust loss reaches 0.5 dB at 64k; offset capped by the grid)')
    nom = nominal()
    out = evaluate([('card', r, prm) for _, prm in corners for r in card.RATES])
    print(f'\n  {"":24s} {"":5s}  {CELL_TOP}')
    print(f'  {"corner":24s} {"rate":>5s}  {CELL_HEAD}')
    for ci, (name, prm) in enumerate(corners):
        for ri, r in enumerate(card.RATES):
            a = out[ci * len(card.RATES) + ri]
            print(f'  {name if ri == 0 else "":24.24s} {r // 1000:4d}k  {cells(a, nom[r])}')
    RES['corners'] = corners


def do_idle():
    hdr('5. IDLE CHANNEL  (zero input, 10 s, first second discarded, decoder nominal)')
    print('  cycle = the repeating bit word when the pattern is periodic (period <= 8), else -.')
    print('  toggle = fraction of bits differing from the one before; run = longest run of')
    print('  equal bits; duty = fraction of ones.  Decoder output after audio.reconstruct,')
    print('  dB re nominal speech rms (0.15 FS): total includes DC, AC has the mean removed,')
    print('  band is AC through 300-3400 Hz.  tone = strongest line 5 Hz-4 kHz in AC, shown')
    print('  when band > -60 dB.')
    for field, vals, title in (('cmp_off', OFFS, 'offset, FS'),
                               ('cmp_hyst', HYSTS, 'dead band, FS'),
                               ('cmp_delay', DELAYS, 'delay, bit')):
        print(f'\n  --- {title} ---')
        for r in card.RATES:
            sm = step_min(r)
            print(f'\n  {r // 1000} kbps   step_min {sm:.5f} FS' +
                  (f';  if the offset tone is the leak-driven sawtooth: f = off x rate / '
                   f'(slew tau_int / 31.6) = off x {r / 1.1386:.0f} Hz' if field == 'cmp_off' else ''))
            print(IDLE_HEAD)
            for v in vals:
                print(idle_row(f'{v:g}', idle('card', r, {field: v} if v else {})))
    print('\n  offset at which idle stops being 1010 (bisection on the bit pattern):')
    RES['idle_off'] = {}
    for r in card.RATES:
        lo, hi = 1e-5, 5e-2
        for _ in range(24):
            mid = np.sqrt(lo * hi)
            if idle('card', r, dict(cmp_off=mid))['alt'] > 0.99999:
                lo = mid
            else:
                hi = mid
        sm = step_min(r)
        a = np.exp(-1.0 / (r * card.CardParams(r).tau_int))
        RES['idle_off'][r] = lo
        print(f'    {r // 1000:2d}k  {lo:.5f} FS = {lo / sm:.3f} step_min'
              f'   (the 1010 swing about zero, step_min a/(1+a), is {sm * a / (1 + a):.5f})'
              f'   = {lo * 1e3:.2f} mV at FS 1 V, {lo * 500:.2f} mV at 0.5 V')
    print('\n  after speech: 1 s of talker1, then silence (dead band and delay at their grid values):')
    print(IDLE_HEAD)
    for r in card.RATES:
        for field, v in (('', 0), ('cmp_off', 1e-3), ('cmp_hyst', 3e-3), ('cmp_delay', 0.2)):
            d = idle('card', r, {field: v} if field else {}, lead=True)
            print(idle_row(f'{r // 1000}k {field[4:] or "nom"} {v:g}'[:10], d))


def do_scale():
    hdr('6. SCALE  (smallest step, and the tolerances in volts and seconds)')
    print(f'  {"rate":>5s} {"bit":>9s} {"step_min FS":>12s} {"@1 V":>9s} {"@0.5 V":>9s}'
          f' {"step_max FS":>12s}')
    for r in card.RATES:
        v = card.CardParams(r).vector()
        print(f'  {r // 1000:4d}k {1e6 / r:7.2f}us {v[5]:12.5f} {v[5] * 1e3:7.2f}mV '
              f'{v[5] * 500:7.2f}mV {v[4]:12.4f}')
    if 'cmp_off' not in RES:
        return
    print('\n  speech tolerances: where the larger of mean and worst-talker loss reaches the limit')
    print(f'  {"":22s} {"rate":>5s} {"0.5 dB":>8s} {"@1 V":>9s} {"@0.5 V":>9s} '
          f'{"1 dB":>8s} {"@1 V":>9s} {"@0.5 V":>9s}   step_min at 0.5 dB')
    for field, vals, m, label in (('cmp_off', OFFS, 1, 'offset, robust'),
                                  ('cmp_off', OFFS, 0, 'offset, card.score'),
                                  ('cmp_hyst', HYSTS, 1, 'dead band, robust'),
                                  ('cmp_hyst', HYSTS, 0, 'dead band, card.score')):
        for r in card.RATES:
            t = [tolerance(vals, RES[field][r][m], lim) for lim in LIMITS]
            row = '  '.join(f'{fmt_tol(x):>8s} {fmt_tol(x, 1e3, "{:.2f}") + "mV":>9s} '
                            f'{fmt_tol(x, 5e2, "{:.2f}") + "mV":>9s}' for x in t)
            print(f'  {label if r == 16000 else "":22s} {r // 1000:4d}k {row}   '
                  f'{fmt_tol(t[0], 1 / step_min(r), "{:.2f}")}')
    for m, label in ((1, 'delay, robust'), (0, 'delay, card.score')):
        for r in card.RATES:
            t = [tolerance(DELAYS, RES['cmp_delay'][r][m], lim) for lim in LIMITS]
            row = '  '.join(f'{fmt_tol(x):>8s} {fmt_tol(x, 1e6 / r, "{:.2f}") + "us":>9s} {"":>9s}'
                            for x in t)
            print(f'  {label if r == 16000 else "":22s} {r // 1000:4d}k {row}')
    if 'idle_off' in RES:
        print('\n  idle: offset at which silence stops being 1010 (section 5):')
        for r in card.RATES:
            o = RES['idle_off'][r]
            print(f'    {r // 1000:2d}k  {o:.5f} FS = {o * 1e3:.2f} mV at 1 V, {o * 500:.2f} mV at 0.5 V')


# name, gbw Hz, slew V/s, rail above, rail below (V about the logic threshold),
# Vos typ, Vos max (mV; recalled datasheet figures), gain stage, note
CLASSES = [
    ('LM311 comparator (ref)', 400e6, 100e6, 2.5, -2.5, 2.0, 7.5, 0,
     '200 ns at 5 mV overdrive ~ 400 MHz equivalent'),
    ('LM324-class, 5 V', 1.2e6, 0.5e6, 1.0, -2.5, 2.0, 7.0, 0,
     'output high ~3.5 V against a 2.5 V threshold'),
    ('TL074-class, +-5 V', 3e6, 13e6, 3.5, -3.5, 3.0, 10.0, 0,
     'divider centres the swing on the HC threshold'),
    ('TL074-class, +-12 V', 3e6, 13e6, 10.5, -10.5, 3.0, 10.0, 0, 'same, +-10.5 V swing'),
    ('5 MHz 20 V/us, +-5 V', 5e6, 20e6, 3.5, -3.5, 1.0, 4.0, 0, 'TL074H / MC34074 class'),
    ('10 MHz CMOS RRIO, 5 V', 10e6, 6.5e6, 2.5, -2.5, 0.3, 1.6, 0, 'TLV9064 class, drives HC'),
    ('TL074 x10 + TL074, +-5 V', 3e6, 13e6, 3.5, -3.5, 3.0, 10.0, 10,
     'two sections: difference amp, then comparator'),
    ('10 MHz x10 + 10 MHz, 5 V', 10e6, 6.5e6, 2.5, -2.5, 0.3, 1.6, 10, 'two sections'),
]
GBWS = (0.3e6, 1e6, 3e6, 10e6, 30e6, 100e6, 300e6)


def cls_prm(c, fsv=1.0, **kw):
    name, g, s, hi, lo, vt, vm, pre, note = c
    prm = dict(gbw=g, sr=s, vhi=hi, vlo=lo, fsv=fsv, pre=float(pre), pre_rail=min(hi, -lo))
    prm.update(kw)
    return prm


def do_opamp():
    hdr('7. AN OP AMP IN THE LOOP  (behavioural model, 64 substeps per bit, 30 s)')
    print('  7a. check: ideal op amp against card.encode, talker1')
    for r in card.RATES:
        x = talker(r, 0)
        same = [bool(np.array_equal(card.encode(x, card.CardParams(r, cmp_off=o)),
                                    opamp_encode(x, r, gbw=0.0, vos=o))) for o in (0.0, 1e-3)]
        print(f'    {r // 1000:2d}k  bit-identical: offset 0 {same[0]}, offset 1 mV {same[1]}')

    nom = nominal()
    base = dict(sr=13e6, vhi=2.5, vlo=-2.5, fsv=1.0)
    print('\n  7b. GBW sweep.  FS 1 V, rails +-2.5 V about the threshold, slew 13 V/us, A0 1e5,')
    print('  Vos 0.  t_step = time to swing from a rail to the threshold on a step of step_min')
    print('  overdrive, 2.5 V / (2 pi GBW step_min), in bits.  The model depends on')
    print('  GBW x FS / swing, so at FS 0.5 V or a +-5 V swing read the GBW column as half.')
    print('  Idle: from rest / after 1 s of speech; cycle word, band dB.')
    out = evaluate([('opamp', r, dict(base, gbw=g)) for r in card.RATES for g in GBWS])
    RES['gbw'] = {}
    for ri, r in enumerate(card.RATES):
        sm = step_min(r)
        print(f'\n  {r // 1000} kbps          {CELL_TOP}')
        print(f'  {"GBW MHz":>7s} {"t_step":>6s}  {CELL_HEAD}   {"idle, rest":>14s} {"after speech":>14s}')
        ideal = [idle('card', r, {}), idle('card', r, {}, lead=True)]
        print(f'  {"ideal":>7s} {0:6.2f}  {cells(nom[r], nom[r])}   '
              + ' '.join(f'{d["word"]:>8s} {d["vband"]:5.0f}' for d in ideal))
        bind = []
        for gi, g in enumerate(GBWS):
            a = out[ri * len(GBWS) + gi]
            ids = [idle('opamp', r, dict(base, gbw=g)), idle('opamp', r, dict(base, gbw=g), lead=True)]
            bind.append(binding(a, nom[r]))
            print(f'  {g / 1e6:7g} {2.5 / (2 * np.pi * g * sm) * r:6.2f}  {cells(a, nom[r])}   '
                  + ' '.join(f'{d["word"]:>8s} {d["vband"]:5.0f}' for d in ids))
        req = {}
        for lim in LIMITS:
            ok = [i for i in range(len(GBWS)) if all(l < lim for l in bind[i:])]
            if not ok:
                req[lim] = (GBWS[-1], '>')
            elif ok[0] == 0:
                req[lim] = (GBWS[0], '<')
            else:
                i = ok[0]
                f = (bind[i - 1] - lim) / (bind[i - 1] - bind[i])
                req[lim] = (float(GBWS[i - 1] * (GBWS[i] / GBWS[i - 1]) ** f), '')
        RES['gbw'][r] = req
        print('  GBW for robust loss under ' + ',  '.join(
            f'{lim:g} dB: {req[lim][1]}{req[lim][0] / 1e6:.3g} MHz'
            f' (t_step {2.5 / (2 * np.pi * req[lim][0] * sm) * 1e6:.2f} us)' for lim in LIMITS))

    print('\n  7c. scaling check, 64k: GBW 20 MHz at FS 0.5 V against 10 MHz at FS 1 V (+-2.5 V)')
    a, b = evaluate([('opamp', 64000, dict(base, gbw=20e6, fsv=0.5)),
                     ('opamp', 64000, dict(base, gbw=10e6, fsv=1.0))])
    print(f'    robust mean {a[1].mean():.3f} / {b[1].mean():.3f} dB,  worst {a[1].min():.3f} / {b[1].min():.3f} dB')

    print('\n  7d. representative parts.  Parameters are recalled datasheet figures, not')
    print('  measurements.  Vos 0 here (offset: sections 1, 5, 7f).  Each cell: robust loss,')
    print('  larger of mean and worst (dB) / idle band dB after speech.')
    RES['classes'] = {}
    for fsv in FSV:
        print(f'\n  FS = {fsv:g} V')
        print(f'  {"class":26s} {"GBW":>5s} {"slew":>5s} {"swing":>9s}  '
              + '  '.join(f'{r // 1000:>5d}k' + ' ' * 5 for r in card.RATES))
        out = evaluate([('opamp', r, cls_prm(c, fsv)) for c in CLASSES for r in card.RATES])
        for ci, c in enumerate(CLASSES):
            row = []
            for ri, r in enumerate(card.RATES):
                a = out[ci * len(card.RATES) + ri]
                d = idle('opamp', r, cls_prm(c, fsv), lead=True)
                RES['classes'][(c[0], fsv, r)] = (binding(a, nom[r]), d)
                row.append(f'{binding(a, nom[r]):5.2f}/{d["vband"]:4.0f}')
            print(f'  {c[0]:26s} {c[1] / 1e6:4.3g}M {c[2] / 1e6:5.3g} {c[3]:+4.1f}/{c[4]:+4.1f}  '
                  + '  '.join(f'{x:>11s}' for x in row))
    print('\n  notes: ' + '\n         '.join(f'{c[0]}: {c[8]}; Vos {c[5]:g} typ / {c[6]:g} max mV'
                                           for c in CLASSES))

    picks = [c for c in CLASSES if c[0].startswith(('TL074-class, +-5', '10 MHz CMOS', 'TL074 x10',
                                                    '10 MHz x10'))]
    n64 = nom[64000]
    print('\n  7e. gain stage ahead of a TL074-class comparator, 64k, FS 1 V, +-5 V:')
    print('  robust loss (larger of mean/worst) / idle band dB after speech')
    gains = (0, 3, 10, 30)
    tl = CLASSES[2]
    out = evaluate([('opamp', 64000, cls_prm(tl, pre=float(g))) for g in gains])
    print('    ' + '   '.join(f'gain {g if g else "none"}: {binding(a, n64):5.2f}/'
                               f'{idle("opamp", 64000, cls_prm(tl, pre=float(g)), lead=True)["vband"]:4.0f}'
                               for g, a in zip(gains, out)))

    print('\n  7f. overload recovery, 64k, FS 1 V: the output stays at a rail for t_rec after')
    print('  the input reverses.  Robust loss / idle band dB after speech.')
    trecs = (0.0, 1e-6, 3e-6, 10e-6)
    print(f'  {"class":26s} ' + ' '.join(f'{t * 1e6:>9g} us' for t in trecs))
    out = evaluate([('opamp', 64000, cls_prm(c, trec=t)) for c in picks for t in trecs])
    for ci, c in enumerate(picks):
        row = [f'{binding(out[ci * len(trecs) + ti], n64):5.2f}/'
               f'{idle("opamp", 64000, cls_prm(c, trec=t), lead=True)["vband"]:4.0f}'
               for ti, t in enumerate(trecs)]
        print(f'  {c[0]:26s} ' + ' '.join(f'{x:>12s}' for x in row))

    print('\n  7g. offset with the op amp, 64k, FS 1 V.  Robust loss / idle band dB after speech / cycle.')
    offs = (0.0, 1e-3, 3e-3, 1e-2)
    print(f'  {"class":26s} ' + ' '.join(f'{o * 1e3:>12g} mV' for o in offs))
    out = evaluate([('opamp', 64000, cls_prm(c, vos=o)) for c in picks for o in offs])
    for ci, c in enumerate(picks):
        row = []
        for oi, o in enumerate(offs):
            d = idle('opamp', 64000, cls_prm(c, vos=o), lead=True)
            row.append(f'{binding(out[ci * len(offs) + oi], n64):5.2f}/{d["vband"]:4.0f}/{d["word"]}')
        print(f'  {c[0]:26s} ' + ' '.join(f'{x:>15s}' for x in row))


def do_spec():
    hdr('8. WHAT THE COMPARATOR MUST MEET  (64 kbps binds; from sections 1-7, robust score)')
    r = 64000
    sm = step_min(r)
    T = 1e6 / r
    hy = tolerance(HYSTS, RES['cmp_hyst'][r][1], 0.5)
    de = tolerance(DELAYS, RES['cmp_delay'][r][1], 0.5)
    of = tolerance(OFFS, RES['cmp_off'][r][1], 0.5)
    g = RES['gbw'][r][0.5]
    io = RES['idle_off'][r]
    for fsv in FSV:
        print(f'\n  FS = {fsv:g} V   (step_min at 64k = {sm * fsv * 1e3:.2f} mV)')
        print(f'    offset, total at the comparator, for a 1010 idle:  <= {io * fsv * 1e3:.2f} mV')
        print(f'    offset, speech loss 0.5 dB:                         {fmt_tol(of, fsv * 1e3, "{:.0f}")} mV')
        print(f'    dead band (hysteresis + non-resolution), 0.5 dB:  <= {fmt_tol(hy, fsv * 1e3, "{:.2f}")} mV'
              f'  ({fmt_tol(hy, 1 / sm, "{:.2f}")} step_min)')
        print(f'    decision delay, 0.5 dB:                            <= {fmt_tol(de, T, "{:.2f}")} us'
              f'  ({fmt_tol(de, 1, "{:.2f}")} bit)')
        gf = g[0] / fsv
        print(f'    as an op amp with a +-2.5 V swing: GBW >= {g[1]}{gf / 1e6:.3g} MHz, i.e. a rail-to-threshold'
              f' step response within {2.5 / (2 * np.pi * gf * sm * fsv) * 1e6:.2f} us at {sm * fsv * 1e3:.2f} mV')
    print('\n  measured margins at 64k, FS 1 V (robust loss dB against the 0.5 dB limit; idle band dB):')
    for c in CLASSES:
        loss, d = RES['classes'][(c[0], 1.0, r)]
        print(f'    {c[0]:26s} loss {loss:5.2f} dB  {"meets" if loss < 0.5 else "fails"}'
              f'   idle {d["word"]:>5s} {d["vband"]:5.0f} dB   Vos max {c[6]:g} mV against {io * 1e3:.2f} mV')


if __name__ == '__main__':
    what = sys.argv[1] if len(sys.argv) > 1 else 'all'
    if what in ('sweeps', 'all'):
        do_sweeps()
    if what in ('idle', 'all'):
        do_idle()
    if what in ('sweeps', 'idle', 'all'):
        do_scale()
    if what in ('opamp', 'all'):
        do_opamp()
    if what == 'all':
        do_spec()
    if _POOL is not None:
        _POOL.close()
