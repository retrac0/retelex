"""
End-to-end emulation of the 2+2N bit CVSD carrier.

Experiments
  1  rate sweep            16 / 32 / 64 kbps, speech and music
  2  line bit noise        BER sweep: CVSD resilience AND framer desync
  3  burst errors
  4  clock model           perfect / DPLL-recovered / gapped-burst (the rejected one)
  5  frame bit ordering    interleaved vs grouped -> the false-lock failure
"""
import os, sys, numpy as np
import audio, cvsd, link

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'out')
os.makedirs(OUT, exist_ok=True)

# per-rate step-size tuning (the external components are picked for the clock rate)
SLEW = {16000: 7000.0, 32000: 11000.0, 64000: 16000.0}
BASE = dict(run_length=3, tau_syl=0.006, tau_int=0.003, companding_db=30.0)

SOURCES = {
    'speech': ('speech30.wav',        0, 0.0,  30.0),
    'music':  ('/home/joel/tek.wav',  0, 40.0, 30.0),
}
NOMINAL_RMS = 0.15      # nominal line level; CVSD step sizes are tuned for it
LINK_SECONDS = 10.0     # shorter clips for the link experiments (framer is a Python loop)


def params(rate):
    return cvsd.CVSDParams(rate=rate, slew=SLEW[rate], **BASE)


def load(name, rate, seconds=None):
    path, ch, off, dur = SOURCES[name]
    x, fs = audio.read_wav(path, channel=ch, seconds=seconds or dur, offset=off)
    x = audio.bandlimit(x, fs)
    x = x * (NOMINAL_RMS / max(x.std(), 1e-9))          # level-normalise
    return audio.resample_to(x, fs, rate)


def score(ref, dec, rate):
    y = audio.reconstruct(dec, rate)
    r, t, _ = audio.align(ref, y)
    t = audio.gain_match(r, t)
    return audio.seg_snr_db(r, t, rate), audio.snr_db(r, t), t, r


def save(tag, y, rate):
    audio.write_wav(os.path.join(OUT, f'{tag}.wav'), y * 0.9 / max(np.abs(y).max(), 1e-9),
                    8000 if rate >= 8000 else rate) if False else None
    audio.write_wav(os.path.join(OUT, f'{tag}.wav'),
                    audio.resample_to(y, rate, 16000), 16000)


# ------------------------------------------------------------------ experiment 1
def exp_rates():
    print('\n=== 1. RATE SWEEP (clean line, 1 channel) ===')
    print(f'{"source":8s} {"rate":>6s} {"segSNR":>8s} {"SNR":>8s}')
    for name in SOURCES:
        for rate in (16000, 32000, 64000):
            p = params(rate)
            x = load(name, rate)
            bits = cvsd.encode(x, p)
            dec = cvsd.decode(bits, p)
            seg, ov, t, r = score(x, dec, rate)
            print(f'{name:8s} {rate//1000:4d}k {seg:8.2f} {ov:8.2f}')
            save(f'1_{name}_{rate//1000}k', t, rate)
        save(f'1_{name}_reference', load(name, 32000), 32000)


# ------------------------------------------------------------------ experiment 2
def exp_noise(rate=32000, n_ch=4):
    print(f'\n=== 2. LINE BIT NOISE ({rate//1000} kbps, {n_ch} ch, {link.frame_len(n_ch)}-bit frame) ===')
    p = params(rate)
    x = load('speech', rate, LINK_SECONDS)
    L = len(x)
    bits = cvsd.encode(x, p)
    # other channels: music + idle, so the line carries realistic mixed content
    m = load('music', rate, LINK_SECONDS)[:L]
    mb = cvsd.encode(m, p)
    idle = cvsd.encode(np.zeros(L), p)
    ch = np.array([bits, mb, idle, idle[::-1]])
    sg = np.array([np.zeros(L, np.uint8), np.ones(L, np.uint8),
                   np.zeros(L, np.uint8), np.ones(L, np.uint8)])
    line = link.build(ch, sg)
    print(f'{"BER":>8s} {"segSNR":>8s} {"lock@ms":>8s} {"slips":>7s} {"LOF":>5s} {"badfr":>7s} {"false":>6s}')
    for ber in (0.0, 1e-4, 1e-3, 3e-3, 1e-2, 3e-2, 1e-1):
        noisy = link.impair(line, ber=ber, seed=7)
        c, s, st = link.framer(noisy, n_ch, skew=3)
        if st['frames'] < 100:
            print(f'{ber:8.1e} {"--":>8s} {"NO LOCK":>8s} {st["slips"]:7d} {"-":>5s} {"-":>7s} {"-":>6s}')
            continue
        dec = cvsd.decode(c[0], p)
        seg, ov, t, r = score(x[-len(dec):], dec, rate)
        lock_ms = 1000 * st['lock_bit'] / (rate * link.frame_len(n_ch))
        print(f'{ber:8.1e} {seg:8.2f} {lock_ms:8.2f} {st["slips"]:7d} {st["lof_events"]:5d} '
              f'{st["bad_frames"]:7d} {str(st["false_lock"]):>6s}')
        save(f'2_ber{ber:.0e}', t, rate)


# ------------------------------------------------------------------ experiment 3
def exp_bursts(rate=32000, n_ch=4):
    print(f'\n=== 3. BURST ERRORS ({rate//1000} kbps, {n_ch} ch) ===')
    p = params(rate)
    x = load('speech', rate, LINK_SECONDS)
    L = len(x)
    ch = np.array([cvsd.encode(x, p)] * n_ch)
    sg = np.zeros((n_ch, L), np.uint8)
    line = link.build(ch, sg)
    print(f'{"burst":>7s} {"rate/bit":>10s} {"segSNR":>8s} {"LOF":>5s} {"badfr":>7s}')
    for blen, brate in ((8, 1e-5), (8, 1e-4), (32, 1e-5), (32, 1e-4), (128, 1e-5)):
        noisy = link.impair(line, burst_len=blen, burst_rate=brate, seed=11)
        c, s, st = link.framer(noisy, n_ch, skew=3)
        if st['frames'] < 100:
            print(f'{blen:7d} {brate:10.0e} {"NO LOCK":>8s}')
            continue
        dec = cvsd.decode(c[0], p)
        seg, ov, t, r = score(x[-len(dec):], dec, rate)
        print(f'{blen:7d} {brate:10.0e} {seg:8.2f} {st["lof_events"]:5d} {st["bad_frames"]:7d}')
        save(f'3_burst{blen}_{brate:.0e}', t, rate)


# ------------------------------------------------------------------ experiment 4
def exp_clock(rate=32000, n_ch=4):
    print(f'\n=== 4. DECODER CLOCK MODEL ({rate//1000} kbps, {link.frame_len(n_ch)}-bit frame) ===')
    p = params(rate)
    x = load('speech', rate, LINK_SECONDS)
    n = len(x)
    flen = link.frame_len(n_ch)
    bits = cvsd.encode(x, p)
    models = {
        'perfect': cvsd.dt_uniform(n, rate),
        'DPLL 32x, 100ppm': cvsd.dt_dpll(n, rate, oversample=32, frame_bits=flen, ppm=100),
        'DPLL 16x, 200ppm': cvsd.dt_dpll(n, rate, oversample=16, frame_bits=flen, ppm=200),
        'DPLL 8x, 200ppm': cvsd.dt_dpll(n, rate, oversample=8, frame_bits=flen, ppm=200),
        'gapped burst x8': cvsd.dt_burst(n, rate, frame_bits=8 * flen // 2, burst_len=8),
    }
    print(f'{"clock":22s} {"segSNR":>8s} {"gain":>7s} {"dt spread":>11s}')
    for name, dt in models.items():
        dec = cvsd.decode(bits, p, dt=dt)
        y = audio.reconstruct(dec, rate)
        r, t, _ = audio.align(x, y)
        g = np.dot(r, t) / max(np.dot(t, t), 1e-20)
        seg = audio.seg_snr_db(r, t * g, rate)
        spread = (dt.max() - dt.min()) / (1.0 / rate)
        print(f'{name:22s} {seg:8.2f} {g:7.3f} {spread:10.3f}x')
        save(f'4_{name.replace(" ","_").replace(",","")}', t * g, rate)


# ------------------------------------------------------------------ experiment 5
def exp_ordering(rate=32000):
    print(f'\n=== 5. FRAME BIT ORDERING (2 ch, 6-bit frame, ch1 on-hook / ch2 off-hook) ===')
    p = params(rate)
    xl = load('music', rate, LINK_SECONDS)
    xr_raw, fs = audio.read_wav('/home/joel/tek.wav', channel=1, seconds=LINK_SECONDS, offset=40.0)
    xr = audio.bandlimit(xr_raw, fs); xr = xr * (NOMINAL_RMS/max(xr.std(),1e-9))
    xr = audio.resample_to(xr, fs, rate)
    L = min(len(xl), len(xr))
    xl, xr = xl[:L], xr[:L]
    ch = np.array([cvsd.encode(xl, p), cvsd.encode(xr, p)])
    sg = np.array([np.zeros(L, np.uint8), np.ones(L, np.uint8)])   # A1=0, A2=1: the killer pair
    print(f'{"order":13s} {"skew":>5s} {"locked phase":>13s} {"true":>5s} {"false":>6s} {"segSNR ch1":>11s}')
    for order in ('interleaved', 'grouped'):
        line = link.build(ch, sg, order=order)
        for skew in (0, 1, 2, 3):
            c, s, st = link.framer(line, 2, order=order, skew=skew)
            true = (6 - skew % 6) % 6
            if st['frames'] < 100:
                print(f'{order:13s} {skew:5d} {"NO LOCK":>13s} {true:5d}')
                continue
            dec = cvsd.decode(c[0], p)
            seg, ov, t, r = score(xl[-len(dec):], dec, rate)
            print(f'{order:13s} {skew:5d} {st["lock_phase"]:13d} {true:5d} '
                  f'{str(st["false_lock"]):>6s} {seg:11.2f}')
            save(f'5_{order}_skew{skew}', t, rate)


if __name__ == '__main__':
    which = sys.argv[1:] or ['1', '2', '3', '4', '5']
    fns = {'1': exp_rates, '2': exp_noise, '3': exp_bursts, '4': exp_clock, '5': exp_ordering}
    for w in which:
        fns[w]()
    print(f'\nWAVs written to {OUT}/')


def exp_burst_gated(rate=32000, n_ch=4):
    """The gapped-clock case, both ways: integrator free-running vs gated off."""
    print(f'\n=== 4b. GAPPED CODEC CLOCK, integrator free vs gated ===')
    p = params(rate)
    x = load('speech', rate, LINK_SECONDS)
    n = len(x)
    flen = link.frame_len(n_ch)
    bits = cvsd.encode(x, p)
    dt = cvsd.dt_burst(n, rate, frame_bits=8 * flen // 2, burst_len=8)
    cases = {
        'uniform clock (ref)': (cvsd.dt_uniform(n, rate), None),
        'burst, integrator free': (dt, None),
        'burst, integrator gated': (dt, dt.min() * rate),
    }
    print(f'{"case":26s} {"segSNR":>8s} {"gain":>7s}')
    for name, (d, ss) in cases.items():
        dec = cvsd.decode(bits, p, dt=d, step_scale=ss)
        y = audio.reconstruct(dec, rate)
        r, t, _ = audio.align(x, y)
        g = np.dot(r, t) / max(np.dot(t, t), 1e-20)
        print(f'{name:26s} {audio.seg_snr_db(r, t * g, rate):8.2f} {g:7.3f}')
        save(f'4b_{name.split(",")[-1].strip().replace(" ","_")}', t * g, rate)
