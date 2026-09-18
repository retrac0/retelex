"""
G.711 mu-law and A-law, for the "bond two channels into 64 kbps PCM" question.

Vectorised transcriptions of the reference g711.c (Sun / ITU-T G.711), checked
against the exhaustive 16-bit round trip in __main__, plus the bit packing a
bonded pair would use:

    64 kbps = 8 kHz x 8 bits = 2 bits per frame at a 32 kHz frame rate
    8 bits / 2 bits per frame = 4 frames per sample  ->  32 kHz / 4 = 8 kHz
"""
import numpy as np

_SEG_U = np.array([0x3F, 0x7F, 0xFF, 0x1FF, 0x3FF, 0x7FF, 0xFFF, 0x1FFF])
_SEG_A = np.array([0x1F, 0x3F, 0x7F, 0xFF, 0x1FF, 0x3FF, 0x7FF, 0xFFF])


def _search(val, table):
    """First i with val <= table[i], else len(table)."""
    return np.searchsorted(table, val, side='left')


def _to_i16(x):
    return np.clip(np.round(np.asarray(x, np.float64) * 32768.0), -32768, 32767).astype(np.int64)


# ------------------------------------------------------------------- mu-law
def ulaw_encode(x):
    """float [-1,1) -> uint8 mu-law.  Silence encodes to 0xFF = 11111111."""
    p = _to_i16(x) >> 2
    mask = np.where(p < 0, 0x7F, 0xFF)
    p = np.minimum(np.abs(p), 8159) + 33
    seg = _search(p, _SEG_U)
    uval = (seg << 4) | ((p >> (seg + 1)) & 0x0F)
    return np.where(seg >= 8, 0x7F ^ mask, uval ^ mask).astype(np.uint8)


def ulaw_decode(b):
    u = (~b.astype(np.int64)) & 0xFF
    t = ((u & 0x0F) << 3) + 0x84
    t = t << ((u & 0x70) >> 4)
    return np.where(u & 0x80, 0x84 - t, t - 0x84).astype(np.float64) / 32768.0


# -------------------------------------------------------------------- A-law
def alaw_encode(x):
    """float [-1,1) -> uint8 A-law.  Silence encodes to 0xD5 = 11010101."""
    p = _to_i16(x) >> 3
    mask = np.where(p >= 0, 0xD5, 0x55)
    p = np.where(p >= 0, p, -p - 1)
    seg = _search(p, _SEG_A)
    s = np.clip(seg, 0, 7)
    aval = (s << 4) | np.where(s < 2, (p >> 1) & 0x0F, (p >> s) & 0x0F)
    return np.where(seg >= 8, 0x7F ^ mask, aval ^ mask).astype(np.uint8)


def alaw_decode(b):
    a = b.astype(np.int64) ^ 0x55
    seg = (a & 0x70) >> 4
    t = (a & 0x0F) << 4
    t = np.where(seg == 0, t + 8,
                 np.where(seg == 1, t + 0x108, (t + 0x108) << np.maximum(seg - 1, 0)))
    return np.where(a & 0x80, t, -t).astype(np.float64) / 32768.0


CODECS = dict(ulaw=(ulaw_encode, ulaw_decode), alaw=(alaw_encode, alaw_decode))
IDLE = dict(ulaw=0xFF, alaw=0xD5)


# ------------------------------------------------- bonded-pair bit packing
def pack_pair(codes):
    """
    (L,) uint8 sample codes -> (2, 4L) C-bit streams for the bonded pair.

    Frame f of each 4-frame multiframe carries two bits, MSB first:
        f=0: b7,b6   f=1: b5,b4   f=2: b3,b2   f=3: b1,b0
    """
    c = codes.astype(np.uint8)
    hi = np.stack([(c >> (7 - 2 * f)) & 1 for f in range(4)], 1).reshape(-1)
    lo = np.stack([(c >> (6 - 2 * f)) & 1 for f in range(4)], 1).reshape(-1)
    return np.stack([hi, lo]).astype(np.uint8)


def unpack_pair(c0, c1, phase=0):
    """Inverse of pack_pair.  `phase` is the multiframe alignment, 0-3; getting
    it wrong is the failure this whole question turns on."""
    c0, c1 = c0[phase:], c1[phase:]
    n = min(len(c0), len(c1)) // 4 * 4
    hi = c0[:n].reshape(-1, 4).astype(np.uint8)
    lo = c1[:n].reshape(-1, 4).astype(np.uint8)
    out = np.zeros(n // 4, np.uint8)
    for f in range(4):
        out |= (hi[:, f] << (7 - 2 * f)) | (lo[:, f] << (6 - 2 * f))
    return out


if __name__ == '__main__':
    allv = np.arange(-32768, 32768) / 32768.0
    for nm, (enc, dec) in CODECS.items():
        c = enc(allv)
        r = dec(c)
        err = np.abs(r - allv)
        # quantisation error must stay inside the codec's own step size
        step = np.abs(np.diff(np.sort(np.unique(dec(np.arange(256, dtype=np.uint8)))))).max()
        print(f'  {nm}: {len(np.unique(c)):3d}/256 codes used, max |err| {err.max():.5f} '
              f'(largest decode step {step:.5f}), rms err {err.std():.6f}')
        # idempotence: decode -> encode must return the same code
        cc = enc(dec(np.arange(256, dtype=np.uint8)))
        same = int((cc == np.arange(256)).sum())
        print(f'         decode->encode idempotent on {same}/256 codes')
    print(f'  mu-law silence code 0x{IDLE["ulaw"]:02X} = {IDLE["ulaw"]:08b}')
    print(f'  A-law  silence code 0x{IDLE["alaw"]:02X} = {IDLE["alaw"]:08b}')
    rng = np.random.default_rng(0)
    codes = rng.integers(0, 256, 5000).astype(np.uint8)
    p = pack_pair(codes)
    print('  pack/unpack round-trip:', np.array_equal(unpack_pair(p[0], p[1]), codes))
