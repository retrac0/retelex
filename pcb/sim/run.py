#!/usr/bin/env python3
"""run.py -- the newimpl benches on the boards: block.v swapped for the block
stack (out/gen/block_stack.v, made by mkstack.py over the three boards' netlists).

    run.py [--ref | --lockstep] [--live] [--refresh] [--timeout S] BENCH ...
                                        e.g. run.py fabric ha word
    run.py --list

The benches and the rest of the RTL come from a SNAPSHOT of newimpl at git
HEAD (pcb/out/nimpl), not the live tree: other sessions edit newimpl, and a
check against a moving tree measures nothing.  --live uses the live tree.
--ref runs the same snapshot with newimpl's own block.v, as the baseline.
--lockstep runs BOTH, block.v driving the exchange and the boards shadowing
it, every output compared at every mid-cell (lockstep.v).

Every build and run goes through ../tools/capped (a cgroup with a memory
ceiling): a netlist that runs away is killed alone.
"""
import os
import functools
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
PCB = HERE.parent
REPO = PCB.parent
OUT = PCB / 'out' / 'netcheck'
SNAP = PCB / 'out' / 'nimpl'
CAPPED = PCB / 'tools' / 'capped'
GEN = PCB / 'out' / 'gen'
MODELS = PCB / 'models' / '74hc.v'
TMP = REPO / 'newimpl' / 'build' / 'tmp'
# the three boards' modules and the parts they are made of (sim/gen.sh makes them)
BOARDS = [str(GEN / f) for f in ('blkhdr_bus_RevA_net.v', 'blkhdr_logic_RevA_net.v', 'portcard_net.v')] + [str(MODELS)]


def snapshot():
    head = subprocess.run(['git', '-C', str(REPO), 'rev-parse', 'HEAD'], capture_output=True, text=True).stdout.strip()
    stamp = SNAP / '.head'
    # The snapshot is refreshed ONLY on --refresh: another session may commit
    # while a queue of benches is building from it.
    if stamp.exists() and ('--refresh' not in sys.argv or stamp.read_text().strip() == head):
        return SNAP, stamp.read_text().strip()
    if SNAP.exists():
        shutil.rmtree(SNAP)
    SNAP.mkdir(parents=True)
    arc = subprocess.run(['git', '-C', str(REPO), 'archive', 'HEAD', 'newimpl/rtl', 'newimpl/tb', 'newimpl/Makefile'],
                         capture_output=True, check=True).stdout
    subprocess.run(['tar', '-x', '-C', str(SNAP), '--strip-components=1'], input=arc, check=True)
    stamp.write_text(head + '\n')
    return SNAP, head


def makefile_vars(root):
    text = (root / 'Makefile').read_text().replace('\\\n', ' ')
    rtl = re.search(r'^RTL\s*:=\s*(.*)$', text, re.M).group(1).split()
    tbs = {m.group(1): m.group(2).split() for m in re.finditer(r'^TB_(\w+)\s*:=\s*(.*)$', text, re.M)}
    return rtl, tbs


print = functools.partial(print, flush=True)   # the summary is read while a queue runs


def main(argv):
    ref = '--ref' in argv
    live = '--live' in argv
    timeout = 3600
    if '--timeout' in argv:
        timeout = int(argv[argv.index('--timeout') + 1])
    benches = [a for a in argv if not a.startswith('--') and not a.isdigit()]
    if live:
        root, head = REPO / 'newimpl', 'live tree'
    else:
        root, head = snapshot()
    rtl, tbs = makefile_vars(root)
    if '--list' in argv:
        print(' '.join(sorted(tbs)))
        return 0
    OUT.mkdir(parents=True, exist_ok=True)
    TMP.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, TMPDIR=str(TMP))
    lock = '--lockstep' in argv
    if ref:
        srcs = rtl
        tag = 'ref'
    elif lock:
        # block.v renamed block_ref, block_stack.v renamed block_boards, and
        # lockstep.v's `block` holding both
        LK = OUT / 'lockstep_src'
        LK.mkdir(parents=True, exist_ok=True)
        (LK / 'block_ref.v').write_text(re.sub(r'\bmodule\s+block\b', 'module block_ref',
                                               (root / 'rtl' / 'block.v').read_text(), count=1))
        (LK / 'block_boards.v').write_text(re.sub(r'\bmodule\s+block\b', 'module block_boards',
                                                  (GEN / 'block_stack.v').read_text(), count=1))
        srcs = [r for r in rtl if Path(r).name != 'block.v'] + [
            str(LK / 'block_ref.v'), str(LK / 'block_boards.v'), str(HERE / 'lockstep.v')] + BOARDS
        tag = 'lock'
    else:
        srcs = [r for r in rtl if Path(r).name != 'block.v'] + [str(GEN / 'block_stack.v')] + BOARDS
        tag = 'stack'
    rc = 0
    print(f"  newimpl {head[:10] if head != 'live tree' else head}, block = "
          f"{'block.v' if ref else 'block.v with the boards in lockstep' if lock else 'the boards'}")
    for b in benches:
        if b not in tbs:
            print(f"  {b}: no such bench")
            rc = 1
            continue
        md = OUT / f"{tag}_{b}"
        t0 = time.time()
        # Small C++ files: a 64-port exchange of netlists is hundreds of MB of
        # C++, and g++'s memory goes with the size of each file, not the total.
        cmd = [str(CAPPED), 'verilator', '--binary', '--timing', '-j', '2', '-Irtl', '-Wno-fatal',
               '--output-split', '3000', '--output-split-cfuncs', '3000', '--output-groups', '0',
               '--top-module', f'tb_{b}', '--Mdir', str(md), '-o', f'tb_{b}'] + srcs + tbs[b]
        r = subprocess.run(cmd, cwd=root, env=env, capture_output=True, text=True)
        (OUT / f"{tag}_{b}.build.log").write_text(r.stdout + r.stderr)
        if r.returncode:
            errs = [l for l in (r.stdout + r.stderr).splitlines() if '%Error' in l]
            print(f"  {b:8s} BUILD FAILED ({r.returncode})")
            print('\n'.join('    ' + e for e in errs[:12]))
            rc = 1
            continue
        tb = time.time() - t0
        t0 = time.time()
        log = OUT / f"{tag}_{b}.run.log"          # written as it runs: tail -f it
        with open(log, 'w') as fh:
            p = subprocess.Popen([str(CAPPED), 'stdbuf', '-oL', str(md / f'tb_{b}')], cwd=root, env=env,
                                 stdout=fh, stderr=subprocess.STDOUT)
            try:
                code = p.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                p.kill()
                code = 'timeout'
        out = log.read_text(errors='replace')
        tr = time.time() - t0
        summary = [l.strip() for l in out.splitlines() if re.search(r'checks?,.*errors?', l)]
        fails = [l.strip() for l in out.splitlines() if ('FAIL' in l and 'checks' not in l) or 'BLOCK-STACK' in l]
        verdict = summary[-1] if summary else f'no summary (exit {code})'
        print(f"  {b:8s} build {tb:5.0f}s  run {tr:6.1f}s  {verdict}")
        for f in fails[:10]:
            print('    ' + f)
        if 'BLOCK-STACK' in out:
            print(f"  {b:8s} the stack's own check failed (BLOCK-STACK lines above)")
        if code != 0 or not summary or 'PASS' not in verdict or 'BLOCK-STACK' in out:
            rc = 1
    return rc


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
