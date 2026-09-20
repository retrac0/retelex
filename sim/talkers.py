"""
Build 7 genuinely independent 30 s talkers from LibriSpeech dev-clean.

The N=7 isolation measurement in docs/seven-channel.md could not produce an
absolute number because only four speech extracts existed and channels 5-7
reused the speakers of 1-3: the SOURCES correlated at 0.110, which swamped the
carrier's own contribution.  This fixes the test material.

Selection rule: 7 different speaker IDs, balanced across the corpus's sex
labels where possible, each speaker's utterances concatenated in order to
exactly 30.0 s.  LibriSpeech is 16 kHz mono FLAC; the wavs are written at
16 kHz rather than upsampled, because inventing bandwidth would be dishonest
and the whole chain band-limits to 300-3400 Hz anyway.
"""
import numpy as np, os, subprocess, sys, glob

DEV = None          # set by --root
OUT = os.path.dirname(os.path.abspath(__file__))
SECS = 30.0
FS = 16000
N = 7


def read_flac(path):
    """Decode a FLAC to float64 mono via ffmpeg (no soundfile dependency)."""
    p = subprocess.run(
        ['ffmpeg', '-v', 'quiet', '-i', path, '-f', 's16le', '-ac', '1',
         '-ar', str(FS), '-'], capture_output=True, check=True)
    return np.frombuffer(p.stdout, '<i2').astype(np.float64) / 32768.0


def speaker_sex(root):
    """speaker id -> 'M'/'F' from the corpus SPEAKERS.TXT."""
    out = {}
    f = os.path.join(root, 'LibriSpeech', 'SPEAKERS.TXT')
    if not os.path.exists(f):
        return out
    for line in open(f):
        if line.startswith(';'):
            continue
        parts = [x.strip() for x in line.split('|')]
        if len(parts) >= 2:
            out[parts[0]] = parts[1]
    return out


def build(root):
    base = os.path.join(root, 'LibriSpeech', 'dev-clean')
    spks = sorted(os.listdir(base), key=int)
    sex = speaker_sex(root)
    print(f'corpus: {len(spks)} speakers in dev-clean')

    # collect speakers that have >= SECS of audio, keeping sex balance
    pool = []
    for s in spks:
        files = sorted(glob.glob(os.path.join(base, s, '*', '*.flac')))
        if not files:
            continue
        pool.append((s, sex.get(s, '?'), files))

    chosen, nf, nm = [], 0, 0
    for s, sx, files in pool:
        if len(chosen) >= N:
            break
        if sx == 'F' and nf >= (N + 1) // 2:
            continue
        if sx == 'M' and nm >= (N + 1) // 2:
            continue
        acc, total = [], 0.0
        for fp in files:
            a = read_flac(fp)
            acc.append(a)
            total += len(a) / FS
            if total >= SECS + 1.0:
                break
        if total < SECS:
            continue
        x = np.concatenate(acc)[:int(SECS * FS)]
        chosen.append((s, sx, x))
        nf += (sx == 'F')
        nm += (sx == 'M')

    assert len(chosen) == N, f'only found {len(chosen)} suitable speakers'
    for i, (s, sx, x) in enumerate(chosen):
        path = os.path.join(OUT, f'talker{i+1}.wav')
        import audio
        audio.write_wav(path, x / max(np.abs(x).max(), 1e-9) * 0.9, FS)
        act = float((np.abs(x) > 0.02).mean())
        print(f'  talker{i+1}.wav  speaker {s:>4s} ({sx})  {len(x)/FS:.1f} s  '
              f'rms {x.std():.4f}  active {act:.1%}')
    return [f'talker{i+1}.wav' for i in range(N)]


def verify():
    """The point of the exercise: the sources must not correlate."""
    import audio, run
    xs = []
    for i in range(N):
        a, fs = audio.read_wav(os.path.join(OUT, f'talker{i+1}.wav'))
        a = audio.bandlimit(a, fs)
        xs.append(audio.resample_to(a * (run.NOMINAL_RMS / a.std()), fs, 32000))
    L = min(map(len, xs))
    xs = [x[:L] for x in xs]
    cm = np.zeros((N, N))
    for i in range(N):
        for j in range(N):
            a, b, _ = audio.align(xs[i], xs[j])
            cm[i, j] = np.corrcoef(a, b)[0, 1]
    off = [abs(cm[i, j]) for i in range(N) for j in range(N) if i != j]
    print(f'\nsource-to-source correlation floor: max {max(off):.4f}, '
          f'mean {np.mean(off):.4f}  over {len(off)} pairs')
    print('(the old 4-file set gave 0.110; anything below ~0.02 makes the')
    print(' carrier\'s own crosstalk directly readable)')
    return max(off)


if __name__ == '__main__':
    root = sys.argv[1] if len(sys.argv) > 1 else '.'
    build(root)
    verify()
