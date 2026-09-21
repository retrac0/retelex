"""
Dual-tone voice-band trunk over a dry two-wire pair (exchange/pots-trunk.md).

Models the hop as speech + idle dual tones through a hybrid, Gaussian noise on
the pair, notches on the receive leg, and a dual-tone AND detector with the
doc's attack/release budget.  Measures what §9 left open: talk-off, pulse
integrity, notch residue, and how noise moves the detector.

    python3 sim/pots_trunk.py            all sections
    python3 sim/pots_trunk.py detect     idle / seize margins vs SNR
    python3 sim/pots_trunk.py talkoff    speech alone as a false idle or seize
    python3 sim/pots_trunk.py pulses     dial-pulse breaks through noise
    python3 sim/pots_trunk.py speech     tandem CVSD segSNR with tones + notches
    python3 sim/pots_trunk.py linkdown   time to unequipped after a cut pair

pots_trunk.log is the full run.
"""
from __future__ import annotations

import math
import sys
import time

import numpy as np
from scipy import signal

import audio
import cvsd
import mf8

RATE = 64000                      # CVSD sample clock
FS = 8000                         # voice-band / detector rate
P = mf8.params(RATE)
NOMINAL = mf8.NOMINAL_RMS         # 0.15

# pots-trunk.md §2.1
PAIR_W = (2400.0, 2600.0)
PAIR_E = (2200.0, 2800.0)
ALL_F = PAIR_W + PAIR_E
TONE_DBFS = -10.0                 # each tone vs codec nominal, approx −10 dBm0
HYBRID_LOSS_DB = 12.0             # mid of the 10–15 dB range
NOTCH_Q = 25.0                    # twin-T-ish; depth measured below

# pots-trunk.md §4
T_IDLE_MS = 16.0                  # both tones present → A = 0
T_SEIZE_MS = 8.0                  # tones absent → A = 1
T_DOWN_MS = 150.0                 # no valid pair → link down
WIN_MS = 20.0                     # Goertzel window
HOP_MS = 5.0                      # detector hop
# Present if each tone is within MARGIN of a clean dual-tone reading.
# (A −10 dB tone lands near −22 dB re NOMINAL² after the Hann window.)
TONE_MARGIN_DB = 6.0              # present if within 6 dB of a clean reading
TONE_TWIST_DB = 6.0               # and the two tones within 6 dB of each other


# ------------------------------------------------------------------ tones / hybrid

def tone_amp():
    return NOMINAL * 10 ** (TONE_DBFS / 20)


def dual_tone(fs, n, pair, amp=None, phase=(0.0, 0.7)):
    a = tone_amp() if amp is None else amp
    t = np.arange(n) / fs
    return (a * np.sin(2 * np.pi * pair[0] * t + phase[0])
            + a * np.sin(2 * np.pi * pair[1] * t + phase[1]))


def notch_sos(fs, freqs=ALL_F, q=NOTCH_Q):
    parts = []
    for f in freqs:
        parts.append(signal.iirnotch(f, q, fs=fs))
    # cascade as SOS: each biquad -> one sos row
    sos = []
    for b, a in parts:
        sos.append([b[0], b[1], b[2], 1.0, a[1], a[2]])
    return np.asarray(sos, float)


def apply_notches(x, fs, sos=None):
    """Zero-phase cascade (filtfilt): a linear-phase stand-in for the card's
    twin-T notches.  Causal IIR notches disperse the speech and the segSNR
    score then measures group-delay mismatch, not the whistle."""
    sos = sos if sos is not None else notch_sos(fs)
    return signal.sosfiltfilt(sos, x)


def hybrid_leak(send, loss_db=HYBRID_LOSS_DB):
    """Near-end send as heard on the local RX leg (trans-hybrid)."""
    return send * 10 ** (-loss_db / 20)


def awgn(n, snr_db, ref_rms, seed):
    """Gaussian noise with SNR referred to ref_rms (tone or speech)."""
    rng = np.random.default_rng(seed)
    if snr_db is None:
        return np.zeros(n)
    n_rms = ref_rms * 10 ** (-snr_db / 20)
    return rng.normal(0.0, n_rms, n)


# ------------------------------------------------------------------ detector

def goertzel_power(x, f, fs):
    """Mean-square of a one-bin Goertzel / DFT at f."""
    n = len(x)
    k = int(round(f * n / fs))
    w = np.hanning(n)
    c = np.abs(np.sum(x * w * np.exp(-2j * np.pi * k * np.arange(n) / n)))
    # power-ish: |X|^2 / n^2, comparable across windows
    return (c / n) ** 2


def tone_db(x, f, fs):
    p = goertzel_power(x, f, fs)
    return 10 * np.log10(p / (NOMINAL ** 2) + 1e-30)


def expected_tone_db(fs=FS, win_ms=WIN_MS):
    n = int(fs * win_ms / 1000)
    x = dual_tone(fs, n, PAIR_W)
    return 0.5 * (tone_db(x, PAIR_W[0], fs) + tone_db(x, PAIR_W[1], fs))


def pair_thresh_db(fs=FS):
    return expected_tone_db(fs) - TONE_MARGIN_DB


def pair_present(x, pair, fs, thresh_db=None):
    thr = pair_thresh_db(fs) if thresh_db is None else thresh_db
    dbs = [tone_db(x, f, fs) for f in pair]
    if min(dbs) < thr:
        return False
    return abs(dbs[0] - dbs[1]) <= TONE_TWIST_DB


def detect_stream(x, pair, fs, hop_ms=HOP_MS, win_ms=WIN_MS,
                  t_idle_ms=T_IDLE_MS, t_seize_ms=T_SEIZE_MS,
                  thresh_db=None):
    """
    Sliding dual-tone AND detector → A level (1 = seize / tones absent).

    Raw: both tones above thresh with limited twist ⇒ idle candidate.
    Schmitt: need idle for t_idle to drop A, need absent for t_seize to raise A.
    """
    thr = pair_thresh_db(fs) if thresh_db is None else thresh_db
    hop = max(1, int(fs * hop_ms / 1000))
    win = max(hop, int(fs * win_ms / 1000))
    n_idle = max(1, int(round(t_idle_ms / hop_ms)))
    n_seize = max(1, int(round(t_seize_ms / hop_ms)))
    a = np.zeros(len(x), dtype=np.uint8)
    state = 1                                 # start seized until we see idle
    idle_run = seize_run = 0
    last = 0
    for i0 in range(0, len(x) - win + 1, hop):
        present = pair_present(x[i0:i0 + win], pair, fs, thr)
        if present:
            idle_run += 1
            seize_run = 0
            if state == 1 and idle_run >= n_idle:
                state = 0
        else:
            seize_run += 1
            idle_run = 0
            if state == 0 and seize_run >= n_seize:
                state = 1
        a[last:i0 + hop] = state
        last = i0 + hop
    a[last:] = state
    return a


def link_down(x, pair, fs, t_down_ms=T_DOWN_MS, thresh_db=None):
    """First time a no-pair run lasts t_down_ms; None if never."""
    thr = pair_thresh_db(fs) if thresh_db is None else thresh_db
    hop = max(1, int(fs * HOP_MS / 1000))
    win = max(hop, int(fs * WIN_MS / 1000))
    need = max(1, int(round(t_down_ms / HOP_MS)))
    run = 0
    for i0 in range(0, len(x) - win + 1, hop):
        if pair_present(x[i0:i0 + win], pair, fs, thr):
            run = 0
        else:
            run += 1
            if run >= need:
                return (i0 + win) / fs
    return None


# ------------------------------------------------------------------ speech helper

def speech(secs, seed=0, level=None):
    """Band-limited noise shaped a little like speech; independent of talker files."""
    rng = np.random.default_rng(seed)
    n = int(secs * FS)
    x = rng.normal(0, 1, n)
    # gentle 300–3400 emphasis via bandlimit
    x = audio.bandlimit(x, FS)
    # syllabic-ish envelope
    env = np.abs(signal.lfilter([1 - 0.99], [1, -0.99], x))
    env = env / (env.mean() + 1e-12)
    x = x * np.clip(env, 0.2, 3.0)
    rms = level if level is not None else NOMINAL
    return x * (rms / (x.std() + 1e-12))


def speech64(secs, seed=0):
    """Upsample speech helper to the CVSD rate."""
    x8 = speech(secs, seed=seed)
    return audio.resample_to(x8, FS, RATE)


# ------------------------------------------------------------------ sections

def sec_notch(log):
    log('NOTCHES -- depth of the cascaded W+E notches at each signalling frequency\n')
    sos = notch_sos(FS)
    n = int(1.0 * FS)
    log(f'  {"freq":>6s} {"alone dB":>10s} {"through notch dB":>16s} {"depth dB":>10s}')
    for f in ALL_F:
        t = np.arange(n) / FS
        x = tone_amp() * np.sin(2 * np.pi * f * t)
        y = apply_notches(x, FS, sos)
        # mid third — filtfilt edge transient
        a, b = n // 3, 2 * n // 3
        din = 20 * math.log10(x[a:b].std() + 1e-20)
        dout = 20 * math.log10(y[a:b].std() + 1e-20)
        depth = min(din - dout, 80.0)
        log(f'  {f:6.0f} {din:10.1f} {dout:16.1f} {depth:10.1f}')
    log(f'\n  Q={NOTCH_Q:g}, target ≥ 40 dB (pots-trunk.md §3). '
        f'Depth capped at 80 in the print.\n')


def sec_detect(log):
    log('DETECT -- far idle pair through hybrid leak of the near send pair, vs SNR\n')
    log('  SNR referred to one tone\'s rms.  Idle = both far tones above thresh;')
    log(f'  thresh = clean−{TONE_MARGIN_DB:.0f} dB '
        f'(≈ {pair_thresh_db():.1f} dB re NOMINAL²), '
        f'twist ≤ {TONE_TWIST_DB:.0f} dB, window {WIN_MS:.0f} ms.\n')
    secs = 1.0
    n = int(secs * FS)
    # EAST listens for W; WEST is sending W (idle); EAST also leaks its own E
    far = dual_tone(FS, n, PAIR_W)
    near_leak = hybrid_leak(dual_tone(FS, n, PAIR_E, phase=(0.3, 1.1)))
    log(f'  {"SNR dB":>8s} {"raw present %":>14s} {"A=0 (idle) %":>14s} {"false seize %":>14s}')
    for snr in [None, 30, 20, 15, 10, 6, 3, 0, -3, -6, -10]:
        rows = []
        for seed in range(8):
            x = far + near_leak + awgn(n, snr, tone_amp(), seed)
            # detector listens before notches (taps the hybrid RX)
            raw = sum(pair_present(x[i:i + int(FS * WIN_MS / 1000)], PAIR_W, FS)
                      for i in range(0, n - int(FS * WIN_MS / 1000), int(FS * HOP_MS / 1000)))
            hops = max(1, (n - int(FS * WIN_MS / 1000)) // int(FS * HOP_MS / 1000))
            a = detect_stream(x, PAIR_W, FS)
            idle = 100 * (a == 0).mean()
            seize = 100 * (a == 1).mean()
            rows.append((100 * raw / hops, idle, seize))
        raw_m = np.mean([r[0] for r in rows])
        idle_m = np.mean([r[1] for r in rows])
        seize_m = np.mean([r[2] for r in rows])
        tag = 'clean' if snr is None else f'{snr:+d}'
        log(f'  {tag:>8s} {raw_m:14.1f} {idle_m:14.1f} {seize_m:14.1f}')
    log('\n  Want: idle ≈ 100 % down to a few dB SNR; false seize is 100−idle.\n')


def sec_talkoff(log):
    log('TALK-OFF -- speech alone (no far tones) into the W detector\n')
    log('  Synthetic speech here is flat in-band, so it is a harsh talk-off')
    log('  source (real speech has formants).  Stuck ms is the worst A=0 run.\n')
    secs = 4.0
    n = int(secs * FS)
    near_leak = hybrid_leak(dual_tone(FS, n, PAIR_E))
    log(f'  {"condition":36s} {"false idle %":>12s} {"A stuck idle ms":>16s}')
    for name, extra, seed0 in (
        ('speech alone', np.zeros(n), 1),
        ('speech + near E leak', near_leak, 2),
        ('speech + E leak + SNR 20', near_leak, 3),
        ('1 kHz tone at nominal', None, 4),
    ):
        false = []
        stuck = []
        for k in range(6):
            if name.startswith('1 kHz'):
                t = np.arange(n) / FS
                sp = NOMINAL * np.sqrt(2) * np.sin(2 * np.pi * 1000 * t)
            else:
                sp = speech(secs, seed=seed0 + k)
            x = sp + (extra if extra is not None else 0)
            if 'SNR 20' in name:
                x = x + awgn(n, 20, NOMINAL, seed0 + 20 + k)
            a = detect_stream(x, PAIR_W, FS)
            false.append(100 * (a == 0).mean())
            idle = (a == 0).astype(int)
            padded = np.concatenate([[0], idle, [0]])
            edges = np.diff(padded)
            starts = np.where(edges == 1)[0]
            ends = np.where(edges == -1)[0]
            longest = max((ends - starts).max() if len(starts) else 0, 0)
            stuck.append(1000 * longest / FS)
        log(f'  {name:36s} {np.mean(false):12.2f} {np.mean(stuck):16.1f}')
    log('\n')


def sec_pulses(log):
    log('PULSES -- dial breaks as tone restore, through noise\n')
    log('  Digit 5: five 60 ms breaks / 40 ms makes after a 200 ms seize.')
    log('  A break ≥ 8 ms must survive (network.md §1.1).\n')
    # Build A_tx at WEST: 1 during seize/make, 0 during break → tones on during break
    def dial_a(fs, digit=5, break_ms=60.0, make_ms=40.0, pre_ms=200.0, post_ms=100.0):
        parts = [np.ones(int(fs * pre_ms / 1000), np.uint8)]
        for _ in range(digit):
            parts.append(np.zeros(int(fs * break_ms / 1000), np.uint8))
            parts.append(np.ones(int(fs * make_ms / 1000), np.uint8))
        parts.append(np.ones(int(fs * post_ms / 1000), np.uint8))
        return np.concatenate(parts)

    a_tx = dial_a(FS)
    n = len(a_tx)
    t = np.arange(n) / FS
    # WEST sends W when A=0
    carrier = dual_tone(FS, n, PAIR_W)
    send = carrier * (a_tx == 0)
    near_leak = hybrid_leak(dual_tone(FS, n, PAIR_E) * 0)  # far end seized: no E
    # truth at far: A should follow a_tx (high when tones absent)
    log(f'  {"SNR dB":>8s} {"breaks seen":>12s} {"min break ms":>13s} {"mean break ms":>14s} {"OK":>4s}')
    for snr in [None, 20, 15, 10, 6, 3, 0]:
        ok_rows = []
        for seed in range(5):
            x = send + awgn(n, snr, tone_amp(), seed)
            a_rx = detect_stream(x, PAIR_W, FS)
            # find A=0 runs after the pre-seize
            idle = (a_rx == 0).astype(int)
            padded = np.concatenate([[0], idle, [0]])
            edges = np.diff(padded)
            starts = np.where(edges == 1)[0]
            ends = np.where(edges == -1)[0]
            # drop any idle in the first 150 ms (startup)
            keep = starts > int(0.15 * FS)
            starts, ends = starts[keep], ends[keep]
            lengths = (ends - starts) / FS * 1000
            # count breaks ≥ 8 ms
            good = lengths[lengths >= 8.0]
            ok_rows.append((len(good), good.min() if len(good) else 0,
                            good.mean() if len(good) else 0, len(good) == 5))
        tag = 'clean' if snr is None else f'{snr:+d}'
        seen = np.mean([r[0] for r in ok_rows])
        mn = np.mean([r[1] for r in ok_rows])
        mean = np.mean([r[2] for r in ok_rows])
        ok = all(r[3] for r in ok_rows)
        log(f'  {tag:>8s} {seen:12.1f} {mn:13.1f} {mean:14.1f} {"yes" if ok else "no":>4s}')
    log('\n')


def sec_speech(log):
    log('SPEECH -- CVSD tandem on the 8 kHz line, with far idle tones and notches\n')
    log('  Path: encode → decode (near) → [8 kHz] → tones? → notches? → bandlimit')
    log('  → encode → decode (far).')
    log('  segSNR against a *notched* clean path so the score is the whistle,')
    log('  not the spectral holes the notches cut in the reference.\n')
    secs = 2.5
    src = speech64(secs, seed=9)
    trim = int(0.1 * RATE)

    def score(ref, test):
        r, t, _ = audio.align(ref[trim:-trim], test[trim:-trim], max_lag=8000)
        t = audio.gain_match(r, t)
        return audio.seg_snr_db(r, t, RATE)

    def hop(notches_on, tones_on, snr):
        y = cvsd.decode(cvsd.encode(src, P), P)
        y = audio.reconstruct(y, RATE)
        y8 = audio.resample_to(y, RATE, FS)
        n = len(y8)
        line = y8.copy()
        if tones_on:
            line = line + dual_tone(FS, n, PAIR_W)
            line = line + hybrid_leak(dual_tone(FS, n, PAIR_E))
        if snr is not None:
            line = line + awgn(n, snr, NOMINAL, 44)
        if notches_on:
            line = apply_notches(line, FS)
        line = audio.bandlimit(line, FS)
        y64 = audio.resample_to(line, FS, RATE)
        z = cvsd.decode(cvsd.encode(y64, P), P)
        return audio.reconstruct(z, RATE)

    def tone_residue_db(notches_on, tones_on):
        """Mean Goertzel power of W at the far encoder input, dB re tone_amp."""
        y = cvsd.decode(cvsd.encode(src, P), P)
        y = audio.reconstruct(y, RATE)
        y8 = audio.resample_to(y, RATE, FS)
        n = len(y8)
        line = y8.copy()
        if tones_on:
            line = line + dual_tone(FS, n, PAIR_W)
            line = line + hybrid_leak(dual_tone(FS, n, PAIR_E))
        if notches_on:
            line = apply_notches(line, FS)
        mid = slice(n // 3, 2 * n // 3)
        dbs = [tone_db(line[mid], f, FS) for f in PAIR_W]
        clean = expected_tone_db(FS)
        return 0.5 * sum(dbs) - clean

    y_plain = hop(False, False, None)
    y_notch = hop(True, False, None)
    log(f'  plain path vs itself:     segSNR {score(y_plain, y_plain):5.1f} dB')
    log(f'  notched vs plain:         segSNR {score(y_plain, y_notch):5.1f} dB '
        f'(spectral holes — not a fault)')
    log(f'  notched vs notched:       segSNR {score(y_notch, y_notch):5.1f} dB\n')

    log(f'  {"condition":40s} {"segSNR dB":>10s} {"W residue dB":>13s}')
    for name, notches, tones, snr, ref in (
        ('tones + leak, no notches', False, True, None, y_plain),
        ('tones + leak + notches', True, True, None, y_notch),
        ('tones + notches + SNR 20', True, True, 20, y_notch),
        ('tones + notches + SNR 10', True, True, 10, y_notch),
        ('notches only (no tones)', True, False, None, y_notch),
    ):
        y = hop(notches, tones, snr)
        s = score(ref, y)
        res = tone_residue_db(notches, tones)
        log(f'  {name:40s} {s:10.1f} {res:13.1f}')
    log('\n  Residue is mean W-bin level re a clean dual tone; notches should')
    log('  drive it deep negative.  segSNR uses the notched clean path as ref')
    log('  whenever notches are on, so a dead whistle reads near the ceiling.\n')


def sec_linkdown(log):
    log('LINK DOWN -- cut the far tones, time to unequipped\n')
    log(f'  Target {T_DOWN_MS:.0f} ms (pots-trunk.md §5).\n')
    secs = 0.8
    n = int(secs * FS)
    far = dual_tone(FS, n, PAIR_W)
    # cut at 200 ms
    cut = int(0.2 * FS)
    far[cut:] = 0
    x = far + hybrid_leak(dual_tone(FS, n, PAIR_E))
    t = link_down(x, PAIR_W, FS)
    log(f'  cut at 200 ms → link-down at {1000 * t:.1f} ms absolute, '
        f'{1000 * (t - 0.2):.1f} ms after the cut' if t else '  never declared')
    # noise floor only
    t2 = link_down(awgn(n, 0, tone_amp(), 5), PAIR_W, FS)
    log(f'  noise only, SNR 0 dB → link-down at {1000 * t2:.1f} ms' if t2
        else '  noise only, SNR 0 dB → never (bad)')
    log('\n')


SECTIONS = {
    'notch': sec_notch,
    'detect': sec_detect,
    'talkoff': sec_talkoff,
    'pulses': sec_pulses,
    'speech': sec_speech,
    'linkdown': sec_linkdown,
}


def main():
    keys = sys.argv[1:] or list(SECTIONS)
    out = open(audio.here('pots_trunk.log'), 'w')

    def log(msg=''):
        print(msg, flush=True)
        out.write(msg + '\n')

    log('pots_trunk.py -- exchange/pots-trunk.md')
    log(f'  pairs W={PAIR_W} E={PAIR_E}; tone {TONE_DBFS:.0f} dB re NOMINAL; '
        f'hybrid −{HYBRID_LOSS_DB:.0f} dB; detector {T_IDLE_MS:.0f}/{T_SEIZE_MS:.0f} ms\n')
    for k in keys:
        t0 = time.time()
        SECTIONS[k](log)
        log(f'  [{k}: {time.time() - t0:.1f} s]\n')
    out.close()
    print(f'wrote {audio.here("pots_trunk.log")}', flush=True)


if __name__ == '__main__':
    main()
