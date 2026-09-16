import numpy as np, itertools, audio, cvsd

x0, fs = audio.read_wav('/usr/share/baresip/callwaiting.wav', seconds=3.0)
xb = audio.bandlimit(x0, fs)

def trial(rate, slew, tau_syl, tau_int, run_len, comp):
    p = cvsd.CVSDParams(rate=rate, run_length=run_len, tau_syl=tau_syl,
                        tau_int=tau_int, slew=slew, companding_db=comp)
    x = audio.resample_to(xb, fs, rate)
    b = cvsd.encode(x, p)
    y = audio.reconstruct(cvsd.decode(b, p), rate)
    r, t, _ = audio.align(x, y)
    t = audio.gain_match(r, t)
    return audio.seg_snr_db(r, t, rate), audio.snr_db(r, t)

best = {}
for rate in (32000,):
    for slew, tsyl, tint, rl, comp in itertools.product(
            (6000, 9000, 12000, 16000), (0.003, 0.006, 0.012),
            (0.001, 0.003, 0.008), (3, 4), (30, 40)):
        s, o = trial(rate, slew, tsyl, tint, rl, comp)
        k = (slew, tsyl, tint, rl, comp)
        best[k] = s
for k, v in sorted(best.items(), key=lambda kv: -kv[1])[:12]:
    print(f'slew={k[0]:6d} tau_syl={k[1]:.3f} tau_int={k[2]:.3f} run={k[3]} comp={k[4]}dB  segSNR={v:5.2f}')
