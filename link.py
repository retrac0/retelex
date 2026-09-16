"""
Line/frame layer for the 2+2N bit carrier.

Frame (interleaved ordering, the one we settled on):

    [A1][C1][A2][C2] ... [AN][CN][S][T]        S=0, T=1
      ^--- signaling and voice alternate so no two adjacent interior bits are
           static; that is what makes the start/stop framer safe.

Also implements the 'grouped' ordering [C1..CN][A1..AN][S][T] so the false-lock
failure mode can be measured rather than argued about.
"""
import numpy as np

ORDERS = ("interleaved", "grouped")


def frame_len(n_ch):
    return 2 + 2 * n_ch


def _payload_map(n_ch, order):
    """Return (sig_pos, chan_pos): frame bit index for each channel's A and C bit."""
    if order == "interleaved":
        sig = [2 * i for i in range(n_ch)]
        chan = [2 * i + 1 for i in range(n_ch)]
    elif order == "grouped":
        chan = list(range(n_ch))
        sig = list(range(n_ch, 2 * n_ch))
    else:
        raise ValueError(order)
    return sig, chan


def build(chan_bits, sig_bits, order="interleaved"):
    """
    chan_bits: (N, L) uint8 CVSD bits
    sig_bits:  (N, L) uint8 signaling levels
    -> (L*(2+2N),) uint8 line bit stream
    """
    chan_bits = np.atleast_2d(chan_bits)
    sig_bits = np.atleast_2d(sig_bits)
    n_ch, L = chan_bits.shape
    flen = frame_len(n_ch)
    sig_pos, chan_pos = _payload_map(n_ch, order)
    f = np.zeros((L, flen), dtype=np.uint8)
    for i in range(n_ch):
        f[:, sig_pos[i]] = sig_bits[i]
        f[:, chan_pos[i]] = chan_bits[i]
    f[:, flen - 2] = 0      # S
    f[:, flen - 1] = 1      # T
    return f.reshape(-1)


def impair(line, ber=0.0, burst_len=0, burst_rate=0.0, seed=1):
    """Random bit errors, and optionally bursts."""
    rng = np.random.default_rng(seed)
    out = line.copy()
    if ber > 0:
        hits = rng.random(out.size) < ber
        out[hits] ^= 1
    if burst_len and burst_rate > 0:
        n_bursts = int(out.size * burst_rate)
        for _ in range(n_bursts):
            s = rng.integers(0, max(1, out.size - burst_len))
            out[s:s + burst_len] ^= 1
    return out


def framer(line, n_ch, order="interleaved", confirm=64, lof=16, skew=0, return_pos=False,
           lof_mode="consecutive", lof_up=1, lof_down=1, emit_always=False,
           confirm_down=0):
    """
    The hardware framer: check S==0 and T==1, slip one LINE bit on failure,
    require `confirm` consecutive good frames to declare lock, and tolerate
    `lof` consecutive bad frames once locked before re-searching.

    `skew` rotates the incoming stream to simulate arbitrary start-up alignment.

    Returns (chan_bits (N,M), sig_bits (N,M), stats)
    """
    if skew:
        line = np.roll(line, -skew)
    flen = frame_len(n_ch)
    sig_pos, chan_pos = _payload_map(n_ch, order)
    true_phase = (flen - (skew % flen)) % flen   # np.roll(-skew) moves the boundary here

    chan_out = [[] for _ in range(n_ch)]
    sig_out = [[] for _ in range(n_ch)]

    i = 0
    confirm_ct = 0
    bad_run = 0
    locked = False
    stats = dict(lock_bit=None, lock_phase=None, slips=0, lof_events=0,
                 bad_frames=0, frames=0, false_lock=False)
    pos_out = []
    N = line.size
    while i + flen <= N:
        f = line[i:i + flen]
        good = (f[flen - 2] == 0) and (f[flen - 1] == 1)
        if not locked:
            if good:
                confirm_ct += 1
                if confirm_ct >= confirm:
                    locked = True
                    stats["lock_bit"] = i
                    stats["lock_phase"] = i % flen
                    stats["false_lock"] = (i % flen) != true_phase
                if emit_always:
                    for c in range(n_ch):
                        chan_out[c].append(f[chan_pos[c]])
                        sig_out[c].append(f[sig_pos[c]])
                    stats["frames"] += 1
                    pos_out.append(i)
                i += flen
            else:
                # confirm_down=0 -> classic "N consecutive good"; >0 -> saturating
                # up/down acquisition counter (bad frames only subtract)
                confirm_ct = 0 if confirm_down == 0 else max(0, confirm_ct - confirm_down)
                stats["slips"] += 1
                if emit_always:
                    # hardware keeps clocking the codecs during the slip
                    for c in range(n_ch):
                        chan_out[c].append(f[chan_pos[c]])
                        sig_out[c].append(f[sig_pos[c]])
                    stats["frames"] += 1
                    pos_out.append(i)
                i += 1
            continue
        # locked
        if lof_mode == "consecutive":
            if good:
                bad_run = 0
            else:
                bad_run += 1
                stats["bad_frames"] += 1
        else:                      # saturating up/down error counter
            if good:
                bad_run = max(0, bad_run - lof_down)
            else:
                bad_run += lof_up
                stats["bad_frames"] += 1
        if True:
            if bad_run >= lof:
                locked = False
                confirm_ct = 0
                bad_run = 0
                stats["lof_events"] += 1
                i += 1
                continue
        for c in range(n_ch):
            chan_out[c].append(f[chan_pos[c]])
            sig_out[c].append(f[sig_pos[c]])
        stats["frames"] += 1
        pos_out.append(i)
        i += flen

    chan = np.array([np.array(c, dtype=np.uint8) for c in chan_out]) if stats["frames"] \
        else np.zeros((n_ch, 0), dtype=np.uint8)
    sig = np.array([np.array(s, dtype=np.uint8) for s in sig_out]) if stats["frames"] \
        else np.zeros((n_ch, 0), dtype=np.uint8)
    stats["pos"] = np.array(pos_out, dtype=np.int64)
    return chan, sig, stats


def slip(line, at, n=1, insert=False, seed=3):
    """
    A DPLL cycle slip: delete (or insert) n line bits at bit index `at`.
    This is what actually forces a re-frame on a real link, and it is the only
    way channel slots can rotate -> crosstalk.
    """
    rng = np.random.default_rng(seed)
    if insert:
        return np.concatenate([line[:at], rng.integers(0, 2, n).astype(np.uint8), line[at:]])
    return np.concatenate([line[:at], line[at + n:]])


def rc_schmitt(bits, fs, tau=2e-3, vt_hi=0.58, vt_lo=0.40):
    """
    Signaling integrator: RC into a 74HC14 Schmitt.  This is the whole per-channel
    signaling filter -- one resistor, one cap, one inverter -- and it is what
    stands between a line bit error and a phone ringing by itself.
    """
    a = 1.0 - np.exp(-1.0 / (fs * tau))
    out = np.zeros(len(bits), dtype=np.uint8)
    v = 0.0
    state = 0
    for i in range(len(bits)):
        v += (float(bits[i]) - v) * a
        if state == 0 and v > vt_hi:
            state = 1
        elif state == 1 and v < vt_lo:
            state = 0
        out[i] = state
    return out


def runs_of(x, val=1):
    """Lengths of consecutive runs equal to `val`."""
    x = np.asarray(x).astype(int)
    d = np.diff(np.concatenate([[0], (x == val).astype(int), [0]]))
    return np.flatnonzero(d == -1) - np.flatnonzero(d == 1)
