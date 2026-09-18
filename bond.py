"""
Bonding two channels into one 64 kbps G.711 PCM channel.

    frame  [A1][C1][A2][C2][A3][C3][S][T]
            |   |___|___ bonded pair: 2 bits/frame = 64 kbps
            |   multiframe of 4 frames = one 8-bit sample = 8 kHz
            A2 freed up (the pair needs only one signalling bit)

Four questions, in the order they decide the answer:
  1 does the rate arithmetic close?          (yes, and cleanly)
  2 is it actually better than CVSD at 64k?  (yes, on a clean line)
  3 what does it do under line errors?       (this is the problem)
  4 what does it do to the framer?           (this is the other problem)

Usage: python3 bond.py [rate|quality|errors|framer|multiframe|all]
"""
import numpy as np, sys
import audio, cvsd, link, run, g711

RATE = 32000            # frame rate
PCM_FS = 8000
LOF = dict(lof_mode='updown', lof=12, lof_up=2, lof_down=1)
SECS = 8.0


def load(path, fs_out, secs=SECS, offset=0.0):
    a, fs = audio.read_wav(path, seconds=secs, offset=offset)
    a = audio.bandlimit(a, fs)
    return audio.resample_to(a * (run.NOMINAL_RMS / a.std()), fs, fs_out)


def hdr(t):
    print('\n' + '=' * 74 + f'\n{t}\n' + '=' * 74)


def seg(ref, test):
    r, t, _ = audio.align(ref, test)
    return audio.seg_snr_db(r, audio.gain_match(r, t), PCM_FS)


# ------------------------------------------------------------------ 1. rate
def do_rate():
    hdr('1. RATE ARITHMETIC')
    print(f'  frame rate                 {RATE} Hz')
    print(f'  bonded pair                2 C bits per frame = {2*RATE/1000:.0f} kbps')
    print(f'  G.711 sample               8 bits')
    print(f'  frames per sample          {8//2} -> sample rate {RATE//4} Hz')
    print(f'  matches G.711 8 kHz        {RATE//4 == PCM_FS}')
    print(f'  multiframe divider         /4, binary: one more 4040 tap')
    print()
    print('  So the arithmetic closes exactly, with no new crystal and no')
    print('  decoded modulus.  On a 16-bit frame (N=7) three pairs bond and one')
    print('  channel is left over; on the 8-bit frame (N=3) one pair bonds and')
    print('  one CVSD channel is left over.')


# --------------------------------------------------------------- 2. quality
def do_quality():
    hdr('2. QUALITY ON A CLEAN LINE (64 kbps each way)')
    rows = []
    for name in ('speech30.wav', 'spk_300.wav', 'spk_600.wav'):
        ref = load(name, PCM_FS)
        out = {}
        for nm, (enc, dec) in g711.CODECS.items():
            out[nm] = seg(ref, dec(enc(ref)))
        for r in (64000, 32000):
            p = run.params(r)
            x = load(name, r)
            y = audio.reconstruct(cvsd.decode(cvsd.encode(x, p), p), r)
            out[f'cvsd{r//1000}'] = seg(ref, audio.resample_to(y, r, PCM_FS))
        rows.append((name, out))
    ks = ['cvsd32', 'cvsd64', 'ulaw', 'alaw']
    print(f'  {"source":14s} ' + ' '.join(f'{k:>9s}' for k in ks))
    for name, o in rows:
        print(f'  {name:14s} ' + ' '.join(f'{o[k]:9.2f}' for k in ks))
    m = {k: np.mean([o[k] for _, o in rows]) for k in ks}
    print(f'  {"mean":14s} ' + ' '.join(f'{m[k]:9.2f}' for k in ks))
    print(f'\n  G.711 buys {m["ulaw"]-m["cvsd64"]:+.1f} dB over CVSD at the same 64 kbps,')
    print(f'  and {m["ulaw"]-m["cvsd32"]:+.1f} dB over the 32 kbps CVSD channel it replaces.')


# ---------------------------------------------------------------- 3. errors
def do_errors():
    hdr('3. BIT ERRORS -- the reason this is not a free upgrade')
    ref = load('speech30.wav', PCM_FS)
    bers = (0, 1e-5, 1e-4, 1e-3, 3e-3, 1e-2)
    res = {k: [] for k in ('cvsd64', 'ulaw', 'alaw')}
    for ber in bers:
        p = run.params(64000)
        x = load('speech30.wav', 64000)
        b = link.impair(cvsd.encode(x, p), ber=ber, seed=3)
        y = audio.reconstruct(cvsd.decode(b, p), 64000)
        res['cvsd64'].append(seg(ref, audio.resample_to(y, 64000, PCM_FS)))
        for nm, (enc, dec) in g711.CODECS.items():
            codes = enc(ref)
            bits = np.unpackbits(codes.reshape(-1, 1), axis=1).reshape(-1).astype(np.uint8)
            bits = link.impair(bits, ber=ber, seed=3)
            got = np.packbits(bits.reshape(-1, 8), axis=1).reshape(-1).astype(np.uint8)
            res[nm].append(seg(ref, dec(got)))
    print('  BER        ' + ' '.join(f'{b:>9.0e}' for b in bers))
    for k in ('cvsd64', 'ulaw', 'alaw'):
        print(f'  {k:10s} ' + ' '.join(f'{v:9.2f}' for v in res[k]))
    print('\n  (segSNR in dB.  The spec\'s design target is 1e-4 for full quality,')
    print('   1e-3 as the usable floor.)')

    # where the damage comes from: which bit position hurts
    hdr('3.1 WHICH BIT POSITION HURTS  (single forced error per sample)')
    codes = g711.ulaw_encode(ref)
    print(f'  {"bit":>4s} {"role":18s} {"mu-law":>9s} {"A-law":>9s}')
    for bit in range(7, -1, -1):
        row = []
        for nm, (enc, dec) in g711.CODECS.items():
            c = enc(ref).copy()
            rng = np.random.default_rng(11)
            hit = rng.random(len(c)) < 0.01           # 1% of samples
            c[hit] ^= (1 << bit)
            row.append(seg(ref, dec(c)))
        role = {7: 'sign', 6: 'exponent MSB', 5: 'exponent', 4: 'exponent LSB'}.get(
            bit, f'mantissa b{bit}')
        print(f'  {bit:>4d} {role:18s} {row[0]:9.2f} {row[1]:9.2f}')
    print('\n  A 1% error rate is applied to one bit position at a time, so the')
    print('  rows are directly comparable: the spread across bit positions is')
    print('  what CVSD does not have, because every CVSD bit carries one step.')


# ---------------------------------------------------------------- 4. framer
def _passrate(line, flen):
    """Fraction of frames passing S==0 and T==1 at every alignment."""
    n = len(line) // flen * flen
    out = []
    for k in range(flen):
        f = np.roll(line, -k)[:n].reshape(-1, flen)
        out.append(float(((f[:, flen - 2] == 0) & (f[:, flen - 1] == 1)).mean()))
    return out


def do_framer():
    hdr('4. WHAT PCM DOES TO THE FRAMER  (spec 2.1 adjacency rule)')
    print('  The rule works because the C bits are effectively random, so every')
    print('  wrong alignment fails ~half its frames.  That is a property of the')
    print('  PAYLOAD, not of the frame, and G.711 does not have it.\n')
    L = int(SECS * RATE)
    act = load('speech30.wav', PCM_FS)
    sil = np.zeros(len(act))
    p32 = run.params(32000)

    def bonded_line(kind, content):
        """ch1+ch2 bonded, ch3 CVSD speech.  Returns the line bit stream."""
        src = act if content == 'active' else sil
        if kind == 'cvsd':
            x = load('speech30.wav', 32000) if content == 'active' else np.zeros(L)
            c01 = cvsd.encode(x, p32)
            pair = np.stack([c01[:L], np.roll(c01, 7)[:L]])
        else:
            codes = g711.CODECS[kind][0](src)
            pr = g711.pack_pair(codes)
            pair = np.stack([pr[0][:L], pr[1][:L]])
        x3 = load('spk_300.wav', 32000)[:L]
        ch = np.vstack([pair, cvsd.encode(x3, p32)[:L][None, :]])
        sg = np.zeros((3, ch.shape[1]), np.uint8)      # all on-hook: the worst case
        return link.build(ch, sg)

    print(f'  {"payload":22s} {"worst wrong-alignment pass rate":>34s}  {"framer":>12s}')
    for kind in ('cvsd', 'ulaw', 'alaw'):
        for content in ('active', 'silence'):
            ln = bonded_line(kind, content)
            pr = _passrate(ln, 8)
            worst = max(pr[1:])
            st = link.framer(ln, 3, skew=3, **LOF)[2]
            verdict = 'FALSE LOCK' if st['false_lock'] else 'ok'
            print(f'  {kind + " " + content:22s} {worst:34.3f}  {verdict:>12s}')
    print('\n  A wrong alignment that passes 1.000 of its frames holds forever:')
    print('  64 consecutive good frames is then guaranteed, not improbable.')

    # per-bit-position staticness of the payload streams
    hdr('4.1 WHY -- the C-bit streams themselves')
    print(f'  {"payload":18s} {"P(bit=1)":>10s} {"longest run of 1s":>19s} {"of 0s":>9s}')
    for kind in ('cvsd', 'ulaw', 'alaw'):
        for content in ('active', 'silence'):
            if kind == 'cvsd':
                x = load('speech30.wav', 32000) if content == 'active' else np.zeros(L)
                s = cvsd.encode(x, p32)
            else:
                s = g711.pack_pair(g711.CODECS[kind][0](act if content == 'active' else sil))[0]
            r1, r0 = link.runs_of(s, 1), link.runs_of(s, 0)
            print(f'  {kind + " " + content:18s} {s.mean():10.3f} '
                  f'{(max(r1) if len(r1) else 0):19d} {(max(r0) if len(r0) else 0):9d}')


# ----------------------------------------------------------- 5. multiframe
def do_multiframe():
    hdr('5. THE NEW ALIGNMENT PROBLEM')
    print('  CVSD has no sample boundary -- any bit alignment decodes.  G.711')
    print('  has one, and the existing framer does not find it: locking the')
    print('  8-bit frame leaves the 4-frame multiframe phase unknown.\n')
    ref = load('speech30.wav', PCM_FS)
    codes = g711.ulaw_encode(ref)
    pr = g711.pack_pair(codes)
    print(f'  {"multiframe phase":18s} {"segSNR":>9s}')
    for ph in range(4):
        got = g711.unpack_pair(pr[0], pr[1], phase=ph)
        print(f'  {ph:<18d} {seg(ref, g711.ulaw_decode(got)):9.2f}')
    print('\n  Three of the four phases are unusable, and nothing in the frame')
    print('  distinguishes them.  A multiframe marker is mandatory.\n')

    print('  The spare A bit is the obvious carrier.  A bonded pair has two')
    print('  signalling bits and needs one, so A2 is free:\n')
    print('      A2 = 0,0,1,1 repeating over the 4-frame multiframe')
    print()
    L = int(SECS * RATE)
    marker = np.tile(np.array([0, 0, 1, 1], np.uint8), L // 4)
    # unique rotation? check the pattern cannot alias to itself
    rots = [np.array_equal(marker[:400], np.roll(marker, -k)[:400]) for k in range(4)]
    print(f'  self-alias check over 4 rotations: {rots}  '
          f'-> unique phase = {sum(rots) == 1}')
    print(f'  P(bit=1) = {marker.mean():.3f}, longest run = '
          f'{max(link.runs_of(marker,1))}  (never static, so it also satisfies 2.1)')
    print()
    print('  Cost: a 2-bit counter and a 4-state comparator per bonded pair at')
    print('  each end, plus its own acquisition and loss-of-multiframe policy.')
    print('  That is a second framer, subordinate to the first.')


if __name__ == '__main__':
    what = sys.argv[1] if len(sys.argv) > 1 else 'all'
    for nm, fn in (('rate', do_rate), ('quality', do_quality), ('errors', do_errors),
                   ('framer', do_framer), ('multiframe', do_multiframe)):
        if what in (nm, 'all'):
            fn()
