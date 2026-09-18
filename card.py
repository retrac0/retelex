"""
The channel card's CVSD engine at circuit level.

cvsd.py is the codec as an idea.  This is the codec as two populated engines on
two different cards: each has its own step currents, syllabic and integrator
networks, and (encoder only) a real comparator.  The loop runs in C
(card_fast.c); with every imperfection at zero it is bit-identical to cvsd.py.

    CardParams(rate)                    the card as designed (slew 12000, 30 dB)
    CardParams(rate, i_min_scale=1.1)   one card's I_min 10% high
    encode(x, p) -> bits                decode(bits, p) -> integrator voltage, FS

Imperfections, each a field of CardParams:

    slew_scale    I_max and I_min together (C_int, the Iabc trim)   -> gain
    i_min_scale   I_min alone                                        -> companding ratio
    ks, off       syllabic path gain and offset in syllabic units;
                  off < 0 is a dead zone (an Iabc pin sitting above the node)
    asym          up/down step current mismatch
    tau_*_scale   the two RC networks
    cmp_off, cmp_hyst   comparator offset and hysteresis, FS
    cmp_delay     comparator decision delay, fraction of a bit

Build:  gcc -O3 -march=native -ffp-contract=off -shared -fPIC -o libcardfast.so card_fast.c -lm
Check:  python3 card.py
"""
import ctypes, os
import numpy as np
from dataclasses import dataclass, replace
import cvsd, run

_L = ctypes.CDLL(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'libcardfast.so'))
_dp = np.ctypeslib.ndpointer(np.float64)
_u8 = np.ctypeslib.ndpointer(np.uint8)
_L.c_card_encode.argtypes = [_dp, ctypes.c_long, _dp, _u8, ctypes.c_void_p, ctypes.c_void_p]
_L.c_card_decode.argtypes = [_u8, ctypes.c_long, _dp, _dp, ctypes.c_void_p]

SLEW = 12000.0          # the one trim, full-scale units per second, every rate


@dataclass
class CardParams:
    rate: float
    slew: float = SLEW
    companding_db: float = run.BASE['companding_db']
    run_length: int = run.BASE['run_length']
    tau_syl: float = run.BASE['tau_syl']
    tau_int: float = run.BASE['tau_int']
    slew_scale: float = 1.0
    i_min_scale: float = 1.0
    ks: float = 1.0
    off: float = 0.0
    asym: float = 0.0
    tau_syl_scale: float = 1.0
    tau_int_scale: float = 1.0
    cmp_off: float = 0.0
    cmp_hyst: float = 0.0
    cmp_delay: float = 0.0

    def vector(self):
        step_max = self.slew * self.slew_scale / self.rate
        step_min = step_max / (10.0 ** (self.companding_db / 20.0)) * self.i_min_scale
        return np.array([self.rate, self.run_length,
                         self.tau_syl * self.tau_syl_scale, self.tau_int * self.tau_int_scale,
                         step_max, step_min, self.ks, self.off, self.asym,
                         self.cmp_off, self.cmp_hyst, self.cmp_delay], np.float64)

    def perturb(self, **kw):
        return replace(self, **kw)


def _ptr(a):
    return None if a is None else a.ctypes.data_as(ctypes.c_void_p)


def encode(x, p, internals=False):
    """Audio at p.rate -> bits.  internals=True also returns the encoder's
    integrator and syllabic node voltages."""
    x = np.ascontiguousarray(x, np.float64)
    n = len(x)
    bits = np.empty(n, np.uint8)
    y = np.empty(n) if internals else None
    s = np.empty(n) if internals else None
    _L.c_card_encode(x, n, p.vector(), bits, _ptr(y), _ptr(s))
    return (bits, y, s) if internals else bits


def decode(bits, p, internals=False):
    """Bits -> decoder integrator voltage, FS.  internals=True also returns the
    syllabic node."""
    bits = np.ascontiguousarray(bits, np.uint8)
    n = len(bits)
    y = np.empty(n)
    s = np.empty(n) if internals else None
    _L.c_card_decode(bits, n, p.vector(), y, _ptr(s))
    return (y, s) if internals else y


TALKERS = [f'talker{i}.wav' for i in range(1, 8)]
RATES = (16000, 32000, 64000)


def load_talker(path, rate, secs=30.0, level_db=0.0):
    """One talker, band-limited, at nominal level (run.NOMINAL_RMS) plus
    level_db, resampled to the CVSD rate.  The same preparation as seven.py."""
    import audio
    a, fs = audio.read_wav(path, seconds=secs)
    a = audio.bandlimit(a, fs)
    a = a * (run.NOMINAL_RMS / a.std()) * 10.0 ** (level_db / 20.0)
    return audio.resample_to(a, fs, rate)


def score(ref, y, rate, recon=None):
    """segSNR of decoder output y against source ref, the repository's metric:
    reconstruction filter, integer-lag alignment, least-squares gain match.
    recon defaults to audio.reconstruct (8th-order Butterworth, zero phase)."""
    import audio
    out = (recon or audio.reconstruct)(y, rate)
    r, t, _ = audio.align(ref, out)
    return audio.seg_snr_db(r, audio.gain_match(r, t), rate)


def selftest():
    import audio
    for rate in RATES:
        x = load_talker('talker1.wav', rate, secs=6.0)
        ref = cvsd.CVSDParams(rate=rate, slew=SLEW, **run.BASE)
        rb = cvsd.encode(x, ref)
        ry = cvsd.decode(rb, ref)
        cp = CardParams(rate)
        cb = encode(x, cp)
        cy = decode(cb, cp)
        same_bits = bool(np.array_equal(rb, cb))
        same_y = bool(np.array_equal(ry, cy))
        print(f'{rate // 1000:3d}k  bits identical: {same_bits}   decoder output identical: {same_y}')
        assert same_bits and same_y


if __name__ == '__main__':
    selftest()
