"""
CVSD codec model (MC3417/3418 / HC-55516 class).

The integrator is analog: its step per bit is I*t/C, i.e. PROPORTIONAL TO THE
ACTUAL BIT INTERVAL.  The syllabic filter and the integrator leak are likewise
real-time RC networks.  Every routine here therefore takes an explicit per-bit
interval array `dt`, so clock jitter, frequency offset and gapped clocking all
fall out of the model rather than having to be bolted on.
"""
import numpy as np
from dataclasses import dataclass, field


@dataclass
class CVSDParams:
    rate: float                  # nominal bit rate, Hz (== sample rate; CVSD is 1 bit/sample)
    run_length: int = 3          # coincidence window: 3 (MC3417) or 4 (MC3418)
    tau_syl: float = 0.005       # syllabic filter time constant, s
    tau_int: float = 0.003       # principal integrator leak, s
    slew: float = 11000.0        # max tracking slew rate, full-scale units/s
    companding_db: float = 36.0  # step_max / step_min, FULL SCALE (100 % coincidence
                                 # over 0 %); MIL-STD-188-113 quotes 30 % over 0 %
    step_max: float = field(init=False)
    step_min: float = field(init=False)

    def __post_init__(self):
        # max step per nominal bit period, chosen so peak slew = self.slew
        self.step_max = self.slew / self.rate
        self.step_min = self.step_max / (10.0 ** (self.companding_db / 20.0))


def _coeffs(p, dt):
    """Per-bit time-dependent coefficients."""
    k = dt * p.rate                        # step scaling: 1.0 at nominal interval
    a_syl = 1.0 - np.exp(-dt / p.tau_syl)  # syllabic filter step
    a_int = np.exp(-dt / p.tau_int)        # integrator leak
    return k, a_syl, a_int


def encode(x, p, dt=None):
    """Audio (sampled at p.rate) -> CVSD bit stream."""
    n = len(x)
    if dt is None:
        dt = np.full(n, 1.0 / p.rate)
    k, a_syl, a_int = _coeffs(p, dt)
    bits = np.zeros(n, dtype=np.uint8)
    mask = (1 << p.run_length) - 1
    span = p.step_max - p.step_min
    smin = p.step_min
    y = 0.0
    syl = 0.0
    hist = 0
    for i in range(n):
        b = 1 if x[i] >= y else 0
        bits[i] = b
        hist = ((hist << 1) | b) & mask
        coin = 1.0 if (hist == 0 or hist == mask) else 0.0
        syl += (coin - syl) * a_syl[i]
        step = smin + syl * span
        y = (y + (step if b else -step) * k[i]) * a_int[i]
    return bits


def decode(bits, p, dt=None, step_scale=None):
    """
    CVSD bit stream -> audio (at p.rate).  Mirror of the encoder loop.

    `step_scale` overrides the step-size time weighting independently of `dt`.
    dt still drives the integrator leak and the syllabic filter (they are
    real-time RC networks), so step_scale=const models an integrator whose
    steering current is GATED OFF during a clock stall, versus the default
    where it keeps integrating.
    """
    n = len(bits)
    if dt is None:
        dt = np.full(n, 1.0 / p.rate)
    k, a_syl, a_int = _coeffs(p, dt)
    if step_scale is not None:
        k = np.broadcast_to(np.asarray(step_scale, dtype=float), (n,)).copy()
    out = np.zeros(n)
    mask = (1 << p.run_length) - 1
    span = p.step_max - p.step_min
    smin = p.step_min
    y = 0.0
    syl = 0.0
    hist = 0
    for i in range(n):
        b = int(bits[i])
        hist = ((hist << 1) | b) & mask
        coin = 1.0 if (hist == 0 or hist == mask) else 0.0
        syl += (coin - syl) * a_syl[i]
        step = smin + syl * span
        y = (y + (step if b else -step) * k[i]) * a_int[i]
        out[i] = y
    return out


# ---------------------------------------------------------------- clock models

def dt_uniform(n, rate):
    """Perfect clock."""
    return np.full(n, 1.0 / rate)


def dt_dpll(n, rate, oversample=32, frame_bits=10, ppm=100.0, seed=0):
    """
    Recovered clock from an oversampling DPLL.

    The codec clock is the frame clock.  The DPLL's sample phase is quantised to
    oversample ticks of a LINE bit, so one tick is 1/(oversample*frame_bits) of a
    frame period.  Phase does a bounded random walk, biased by the TX/RX crystal
    offset, and each phase movement shows up as one short or long frame interval.
    """
    rng = np.random.default_rng(seed)
    T = 1.0 / rate
    tick = T / (oversample * frame_bits)
    # a ppm offset forces one tick of correction every N frames
    frames_per_tick = (oversample * frame_bits) / (ppm * 1e-6 * oversample * frame_bits) \
        if ppm else np.inf
    frames_per_tick = 1.0 / (ppm * 1e-6) / (oversample * frame_bits) if ppm else np.inf
    p_drift = 1.0 / frames_per_tick if np.isfinite(frames_per_tick) else 0.0
    p_noise = 0.02                       # random hunting of the loop
    phase = 0
    dphase = np.zeros(n, dtype=np.int8)
    for i in range(n):
        d = 0
        if rng.random() < p_drift:
            d += 1
        if rng.random() < p_noise:
            d += rng.choice([-1, 1])
        newphase = int(np.clip(phase + d, -2, 2))
        dphase[i] = newphase - phase
        phase = newphase
    return T + dphase * tick


def dt_burst(n, rate, frame_bits, burst_len):
    """
    The architecture we rejected: a channel's bits delivered as a BURST at the
    line bit rate, then a stall for the rest of the frame, instead of at a smooth
    codec clock.  Average rate is identical; only the instantaneous spacing differs.
    """
    t_line = 1.0 / (rate * frame_bits / burst_len)   # one line bit time
    T_group = burst_len / rate                       # time budget for the burst
    dt = np.empty(n)
    for i in range(n):
        if (i % burst_len) == burst_len - 1:
            dt[i] = T_group - (burst_len - 1) * t_line   # the stall
        else:
            dt[i] = t_line
    return dt
