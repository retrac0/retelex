"""
Reference model for the 4-bit / two-channel MF2 frame (mf2/spec.md).

Frame, 4 bits at a 64 kHz frame rate (256 kbps line):

    [ F ][ C1 ][ S ][ C2 ]

Superframe, 8 frames = 125 us (octet counter kept):

    state   0   1   2   3   4   5   6   7
    F       1   1   1   1   1   1   1   0
    S       0  A1   -   -   1  A2   -   -     guard at 0,4; A at 1 and 5
                                              (mf2/spec.md §14 sketch)

Framer rules match mf8.py (32-frame acquire, +2/-1 F and guard counters).
Line PHY for noisy runs is sim/mf2_line.py, which calls mf8_line.rx_ami
at line=256e3 — do not fork the AMI decode rule (mf2/ami.md).

Usage:  python3 sim/mf2.py            smoke: build + clean framer lock
        (full word/guard/seats battery: mf2/sim.md — still to port)
"""
import sys
import numpy as np
import audio, cvsd

RATE = 64000
NCH = 2
FLEN = 4
SF = 8
LINE = FLEN * RATE                # 256 kbps
NOMINAL_RMS = 0.15
SLEW = {16000: 7000.0, 32000: 12000.0, 64000: 16000.0}
BASE = dict(run_length=3, tau_syl=0.005, tau_int=0.001, companding_db=34.2)

SBIT = 2                          # half a frame from F (L=4 → s=2)
CBIT = [1, 3]                     # C1, C2
FIXED = {0: 0, 4: 1}              # S guard
# A_n at superframe states 1 and 5 (spec §14 sketch; freeze vs 1&3 later)
SLOT = {1: 0, 5: 1}


def params(rate=RATE):
    return cvsd.CVSDParams(rate=rate, slew=SLEW[rate], **BASE)


def fword(k, word=0xFE):
    return (word >> (7 - k)) & 1


def build(C, A, word=0xFE, sbit=None):
    """Pack NCH channel bitstreams and A bits into an MF2 line bit vector."""
    sbit = SBIT if sbit is None else sbit
    cb = [b for b in range(FLEN) if b not in (0, sbit)]
    nf = min(len(c) for c in C)
    f = np.arange(nf)
    sfc = f & 7
    line = np.zeros((nf, FLEN), np.uint8)
    line[:, 0] = np.array([fword(k, word) for k in range(8)], np.uint8)[sfc]
    s = np.zeros(nf, np.uint8)
    for st, ch in SLOT.items():
        s[sfc == st] = A[ch][sfc == st]
    for st, v in FIXED.items():
        s[sfc == st] = v
    line[:, sbit] = s
    for j in range(NCH):
        line[:, cb[j]] = C[j][:nf]
    return line.reshape(-1)


def framer(line, skew=0, confirm=32, up=2, dn=1, trip=12, gtrip=12, word=0xFE,
           sbit=None):
    """MF2 receiver — same acquire/track rules as mf8.framer, FLEN=4."""
    sbit = SBIT if sbit is None else sbit
    if skew:
        line = np.roll(line, -skew)
    true = (FLEN - skew % FLEN) % FLEN
    exp = np.array([fword(k, word) for k in range(8)], np.uint8)
    i = cc = wait = err = gerr = sfc = 0
    locked = False
    st = dict(lock_bit=None, false_lock=False, sf_offset=None,
              lof_events=0, guard_lof=0, frames=0, off_phase=0, release=None)
    pos = []
    N = line.size
    while i + FLEN <= N:
        f_bit = int(line[i]); s_bit = int(line[i + sbit])

        if not locked and cc == 0:
            if f_bit == 0:
                sfc = 7
                cc = 1; wait = 0
                i += FLEN; sfc = 0
            else:
                wait += 1
                if wait >= SF:
                    wait = 0; i += 1
                else:
                    i += FLEN
            continue

        good_f = (f_bit == exp[sfc])
        good_g = (sfc not in FIXED) or (s_bit == FIXED[sfc])
        good = good_f and good_g

        if not locked:
            if good:
                cc += 1
                if cc >= confirm:
                    locked = True; gerr = 0
                    if st['lock_bit'] is None:
                        st['lock_bit'] = i
                        st['false_lock'] = (i % FLEN) != true
                        st['sf_offset'] = (sfc - ((i + skew) // FLEN)) & 7
                i += FLEN; sfc = (sfc + 1) & 7
            else:
                cc = 0; wait = 0; i += 1
            continue

        err = max(0, err - dn) if good else err + up
        if gtrip and sfc in FIXED:
            gerr = max(0, gerr - dn) if good_g else gerr + up
        if err >= trip or (gtrip and gerr >= gtrip):
            if gtrip and gerr >= gtrip:
                st['guard_lof'] += 1
            if st['false_lock'] and st['release'] is None and (i % FLEN) != true:
                st['release'] = (i - st['lock_bit']) // FLEN
            locked = False; cc = err = gerr = wait = 0
            st['lof_events'] += 1
            i += 1
            continue
        st['frames'] += 1
        if (i % FLEN) != true:
            st['off_phase'] += 1
        pos.append(i)
        i += FLEN; sfc = (sfc + 1) & 7
    st['pos'] = np.array(pos, np.int64)
    return st


def smoke():
    """Build a short clean frame and confirm the framer locks on-phase."""
    p = params()
    nf = 8000
    z = np.zeros(nf, np.uint8)
    src, fs = audio.read_wav('talker1.wav', seconds=nf / RATE + 0.5)
    x = audio.resample_to(audio.bandlimit(src, fs) * NOMINAL_RMS, fs, RATE)[:nf]
    c0 = cvsd.encode(x, p)[:nf]
    c1 = cvsd.encode(np.roll(x, 17), p)[:nf]
    ln = build([c0, c1], [z, z])
    st = framer(ln)
    ok = (st['lock_bit'] is not None and not st['false_lock']
          and st['lof_events'] == 0 and st['frames'] > nf // 2)
    print(f'MF2 smoke: lock_bit={st["lock_bit"]} false={st["false_lock"]} '
          f'lof={st["lof_events"]} frames={st["frames"]} '
          f'{"PASS" if ok else "FAIL"}')
    return ok


TARGETS = {'smoke': smoke}

if __name__ == '__main__':
    for k in (sys.argv[1:] or list(TARGETS)):
        TARGETS[k]()
