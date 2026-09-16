"""Three-channel link tests: isolation, crosstalk under slip, signaling integrity."""
import numpy as np, audio, cvsd, link, run

RATE, NCH = 32000, 3
FLEN = link.frame_len(NCH)
SECS = 8.0
SRC = {'spkA': 'spk_300.wav', 'spkB': 'spk_600.wav', 'spkC': 'spk_900.wav'}
p = run.params(RATE)


def load(path):
    x, fs = audio.read_wav(path, seconds=SECS)
    x = audio.bandlimit(x, fs)
    x = x * (run.NOMINAL_RMS / max(x.std(), 1e-9))
    return audio.resample_to(x, fs, RATE)


srcs = {k: load(v) for k, v in SRC.items()}
L = min(len(v) for v in srcs.values())
srcs = {k: v[:L] for k, v in srcs.items()}
names = list(srcs)
bits = np.array([cvsd.encode(srcs[n], p) for n in names])


def recover(c_bits, ref_len):
    y = audio.reconstruct(cvsd.decode(c_bits, p), RATE)
    return y


def corr_matrix(outs, tag):
    print(f'  {tag}: correlation of each OUTPUT against each SOURCE')
    print('          ' + ''.join(f'{n:>9s}' for n in names))
    for i, o in enumerate(outs):
        row = []
        for n in names:
            a, b, _ = audio.align(srcs[n][:len(o)], o)
            row.append(np.corrcoef(a, b)[0, 1])
        star = ''.join(f'{v:+9.3f}' for v in row)
        print(f'  out ch{i+1} {star}')


# ---------------------------------------------------------------- 6: isolation
print('=== 6. THREE DISTINCT SOURCES, CLEAN LINE: channel isolation ===')
sg = np.zeros((NCH, L), np.uint8)
line = link.build(bits, sg)
c, s, st = link.framer(line, NCH, skew=3)
outs = [recover(c[i], L) for i in range(NCH)]
for i in range(NCH):
    audio.write_wav(f'out/6_clean_ch{i+1}.wav', audio.resample_to(outs[i], RATE, 16000), 16000)
corr_matrix(outs, 'clean')


# ------------------------------------------------------- 7: slip -> crosstalk
print('\n=== 7. FORCED BIT SLIP -> CROSSTALK ===')
print(f'{"LOF thr":>8s} {"slip bits":>10s} {"misaligned frames":>18s} {"crosstalk ms":>13s} {"lost ms":>9s}')
slip_at = (L // 2) * FLEN
for lof in (4, 16, 64):
    for nslip in (2,):
        ln = link.slip(line, slip_at, n=nslip)
        c2, s2, st2 = link.framer(ln, NCH, skew=3, lof=lof)
        pos = st2['pos']
        # a frame is correctly aligned iff its read position maps to a true boundary
        true_phase = np.where(pos < slip_at, pos % FLEN, (pos + nslip) % FLEN)
        ref = true_phase[0]
        mis = int((true_phase != ref).sum())
        after = pos[pos > slip_at - FLEN * 4]
        lost = (st2['frames'])
        print(f'{lof:8d} {nslip:10d} {mis:18d} {1000*mis/RATE:13.3f} '
              f'{1000*(L-st2["frames"])/RATE:9.2f}')
    if lof == 16:
        o2 = [recover(c2[i], L) for i in range(NCH)]
        for i in range(NCH):
            audio.write_wav(f'out/7_slip_ch{i+1}.wav', audio.resample_to(o2[i], RATE, 16000), 16000)

# high BER + slip: does it ever false-lock to a rotated phase?
print('\n  high BER with slip, phase integrity:')
print(f'{"BER":>8s} {"locked":>8s} {"LOF ev":>7s} {"misaligned frames":>18s} {"segSNR ch1":>11s}')
for ber in (1e-3, 1e-2, 3e-2):
    ln = link.impair(link.slip(line, slip_at, n=2), ber=ber, seed=5)
    c3, s3, st3 = link.framer(ln, NCH, skew=3)
    if st3['frames'] < 100:
        print(f'{ber:8.1e} {"NO LOCK":>8s}'); continue
    pos = st3['pos']
    tp = np.where(pos < slip_at, pos % FLEN, (pos + 2) % FLEN)
    mis = int((tp != tp[0]).sum())
    y = recover(c3[0], L)
    a, b, _ = audio.align(srcs['spkA'][:len(y)], y)
    print(f'{ber:8.1e} {"yes":>8s} {st3["lof_events"]:7d} {mis:18d} '
          f'{audio.seg_snr_db(a, audio.gain_match(a,b), RATE):11.2f}')


# --------------------------------------------- 8: A bit / false ring triggering
print('\n=== 8. A-BIT INTEGRITY: would noise ring a phone? ===')
print('  ch1 idle (A=0 throughout), ch2 off-hook (A=1), ch3 idle')
sg = np.array([np.zeros(L, np.uint8), np.ones(L, np.uint8), np.zeros(L, np.uint8)])
line2 = link.build(bits, sg)
print(f'{"BER":>8s} {"raw A=1 bits":>13s} {"raw longest":>12s} {"RC+Schmitt asserts":>19s} {"RC longest":>11s}')
for ber in (0.0, 1e-4, 1e-3, 1e-2, 3e-2, 6e-2):
    c4, s4, st4 = link.framer(link.impair(line2, ber=ber, seed=13), NCH, skew=3)
    if st4['frames'] < 100:
        print(f'{ber:8.1e} {"NO LOCK":>13s}'); continue
    a_raw = s4[0]                                   # channel 1: should be 0 forever
    rawruns = link.runs_of(a_raw)
    filt = link.rc_schmitt(a_raw, RATE, tau=2e-3)
    fruns = link.runs_of(filt)
    print(f'{ber:8.1e} {int(a_raw.sum()):13d} {1000*(rawruns.max() if len(rawruns) else 0)/RATE:11.3f}ms '
          f'{len(fruns):19d} {1000*(fruns.max() if len(fruns) else 0)/RATE:10.3f}ms')

# sanity: the off-hook channel must stay asserted
c5, s5, st5 = link.framer(link.impair(line2, ber=1e-2, seed=13), NCH, skew=3)
f2 = link.rc_schmitt(s5[1], RATE, tau=2e-3)
print(f'  ch2 (true off-hook) at BER 1e-2: asserted {100*f2.mean():.2f}% of the time, '
      f'{len(link.runs_of(1-f2))} dropouts')


# ------------------------------------------------ 9: dial pulse fidelity
print('\n=== 9. DIAL PULSE FIDELITY (10 pps, 40ms break / 60ms make) ===')
t = np.arange(L) / RATE
pulse = np.zeros(L, np.uint8)
for k in range(int(SECS * 10) - 2):          # 10 pps pulse train
    a0 = int((k * 0.100 + 0.20) * RATE); a1 = a0 + int(0.060 * RATE)
    if a1 < L: pulse[a0:a1] = 1
sg = np.array([pulse, np.zeros(L, np.uint8), np.zeros(L, np.uint8)])
line3 = link.build(bits, sg)
print(f'{"BER":>8s} {"pulses tx":>10s} {"pulses rx":>10s} {"make mean":>10s} {"make sd":>8s} {"ratio err":>10s}')
tx_runs = link.runs_of(pulse)
for ber in (0.0, 1e-3, 1e-2, 3e-2):
    c6, s6, st6 = link.framer(link.impair(line3, ber=ber, seed=21), NCH, skew=3)
    if st6['frames'] < 100:
        print(f'{ber:8.1e} {"NO LOCK":>10s}'); continue
    f = link.rc_schmitt(s6[0], RATE, tau=2e-3)
    rx = link.runs_of(f) / RATE * 1000.0
    rx = rx[rx > 5]
    print(f'{ber:8.1e} {len(tx_runs):10d} {len(rx):10d} {rx.mean():9.2f}ms {rx.std():7.2f}ms '
          f'{100*abs(rx.mean()-60)/60:9.2f}%')
