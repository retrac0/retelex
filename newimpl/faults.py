#!/usr/bin/env python3
# faults.py -- the proof that the checks can fail.  STYLE.md 7.
#
# Each entry puts one old bug, or one missing rule, back into a COPY of the
# tree under build/fault/, runs the bench that is meant to catch it, and gives
# it one verdict:
#
#   RED          a named check failed: the bench caught it
#   GREEN        the bench counted its checks and passed: nothing caught it
#   TIMEOUT      no check failed, and the bench's watchdog or this harness
#                ran out of time
#   BROKEN       the copy did not build, or the bench died before its count
#   NOT-APPLIED  an anchor is not in the tree exactly once: the entry is stale
#
# ONLY RED PROVES A CHECK.  A bench that hangs or does not build proves
# nothing.  Every entry must be RED, with one exception, which is the design
# and not a gap (CONTRACT, below):
#
#   F03  the refusal lands after the CLAIM word for two reasons -- the unit
#        raises `att` only once its word is out, and it outranks the marker on
#        the bus.  Break one and the order holds.  F03b breaks both: RED.
#
# The run exits non-zero unless every verdict is the contract's.
#
#   python3 faults.py               every fault, three at a time (make faults)
#   python3 faults.py F07 F1 ...    only those whose name starts so
#   python3 faults.py --check       apply every anchor in place, run nothing
#                                   (make faults-check)
#   python3 faults.py -j 2          two at a time
#   python3 faults.py --timeout N   seconds one bench may take (3000; a loaded
#                                   tb_net has taken 2176)
#
# The tree is the one this file is in, or FAULTS_ROOT.  Each bench runs under
# a 3 GB memory ceiling (systemd-run) with TMPDIR in build/: /tmp is a small
# tmpfs with a per-user quota.  A network build is about 200 MB, and each copy
# is deleted after its run.
import argparse, os, re, shutil, signal, subprocess, sys
from concurrent.futures import ThreadPoolExecutor, as_completed

ROOT = os.path.abspath(os.environ.get('FAULTS_ROOT') or
                       os.path.dirname(os.path.abspath(__file__)))
OUT  = os.path.join(ROOT, 'build', 'fault')
TMP  = os.path.join(ROOT, 'build', 'tmp')
CAP  = ['systemd-run', '--user', '--scope', '-q',
        '-p', 'MemoryMax=3G', '-p', 'MemorySwapMax=0']

# The verdict each fault must have; every fault not named here must be RED.
CONTRACT = {'F03': 'GREEN'}

FAULTS = [
 ('F01-release-on-gone-only', 'net', 'rtl/net_unit.v',
  [("wire       o_gone  = r_gone || r_nodig || !r_busy;", "wire       o_gone  = r_gone;")],
  'the unit releases its trunks on the no-digit timeout and on a freed register'),
 ('F02-no-busy-term', 'net', 'rtl/net_unit.v',
  [("wire cls_seen  = (cst == C_IDLE) && sp_fresh && sp_m && !sp_busy &&",
    "wire cls_seen  = (cst == C_IDLE) && sp_fresh && sp_m &&")],
  'the classifier (and so the monitor) ignores a port whose BUSY is set'),
 # F03 raises `att` at the claim decision, with the CLAIM word still queued;
 # /UREQ is low by then, so the rank alone keeps the refusal behind it, by the
 # whole WAIT.  (The old three-patch form held by one master tick: any writer
 # quicker than today's queue turned it red.  REFACTOR.md §1.8.)
 ('F03-refusal-before-claim', 'net', 'rtl/net_unit.v',
  [("CL_WAIT: if (q_empty && !w_claim) begin att <= 1'b1; cl_st <= CL_ACK; end",
    "CL_WAIT: begin att <= 1'b1; cl_st <= CL_ACK; end")],
  'the unit raises att only once its CLAIM word is out, so a refusal lands after it'),
 ('F03b-refusal-first-and-no-rank', 'net', 'rtl/net_unit.v',
  [("CL_WAIT: if (q_empty && !w_claim) begin att <= 1'b1; cl_st <= CL_ACK; end",
    "CL_WAIT: begin att <= 1'b1; cl_st <= CL_ACK; end")],
  'the refusal lands after CLAIM -- att raised early AND the marker deaf to /UREQ',
  [('rtl/mini_marker.v', [(".go(ureq_n), .pending(q_pending), .empty(q_empty),",
                           ".go(1'b1), .pending(q_pending), .empty(q_empty),")])]),
 ('F04-even-stride', 'net', 'rtl/net_unit.v',
  [("localparam [`PW-1:0] STRIDE     = 6'd9;", "localparam [`PW-1:0] STRIDE     = 6'd8;")],
  'the sweep visits every port: an odd stride'),
 ('F05-trunk-M-as-caller', 'net', 'rtl/mini_marker.v',
  [("state <= (rd_trunk || (rd_word == 8'd0)) ? S_IDLE : S_TAKE;", "state <= S_TAKE;")],
  'the marker never takes a flood trunk\'s M as a call'),
 ('F05b-trunk-M-as-caller-and-no-hold', 'net', 'rtl/mini_marker.v',
  [("state <= (rd_trunk || (rd_word == 8'd0)) ? S_IDLE : S_TAKE;", "state <= S_TAKE;")],
  'the marker never takes a flood trunk\'s M as a call -- its own read AND the unit\'s hold removed',
  [('rtl/net_unit.v', [("wire cls_seen  = (cst == C_IDLE) && sp_fresh && sp_m && !sp_busy &&",
                        "wire cls_seen  = 1'b0 && (cst == C_IDLE) && sp_fresh && sp_m && !sp_busy &&")])]),
 ('F06-others-never-dropped', 'chain', 'rtl/net_unit.v',
  [("dmo <= d_held & ~(4'd1 << j2);", "dmo <= 4'd0;")],
  'the origin drops the other trunks at the claim'),
 ('F07-no-5s-rule', 'net', 'rtl/net_unit.v',
  [("end else if (!f2 && (tmr >= T_KEY)) begin", "end else if (1'b0) begin")],
  'the 5 s rule: b not in 5 s after the key'),
 ('F08-claim-wait-from-last-digit', 'net', 'rtl/net_unit.v',
  [("else if (!claimed && (tmr >= T_CLAIM)) begin o_after <= O_NOGO; nst <= N_DROP; end",
    "else if (!claimed && (r_ndig >= 3'd4) && (tmr >= T_CLAIM)) begin o_after <= O_NOGO; nst <= N_DROP; end")],
  'the 2 s claim wait runs from b'),
 ('F09-second-digit-folds', 'mini', 'rtl/mini_marker.v',
  [("wire       svc1 = (c1 == 4'd8) || (c1 == 4'd9) || (c1 > 4'd10);", "wire       svc1 = 1'b0;")],
  '8 or 9 as the second digit is cannot-complete'),
 ('F10-stale-sample-counts', 'net', 'rtl/pulse_reg.v',
  [(".arm(busy && seen), .m(p_m),", ".arm(busy), .m(p_m),")],
  'the register ignores its probe until the probe has the caller'),
 ('F11-no-guard', 'net', 'rtl/net_unit.v',
  [("else if (guarding && r_brk) begin", "else if (1'b0 && r_brk) begin")],
  'the origin guard abandons on a break inside it'),
 ('F12-no-wait', 'net', 'rtl/net_unit.v',
  [("parameter [11:0]  WAIT    = 12'd640", "parameter [11:0]  WAIT    = 12'd1")],
  'the unit waits out the marker\'s transaction: no clash on cable B'),
 ('F13-word-not-gated-by-link', 'word', 'rtl/baseband_card.v',
  [("assign word_n = !(sh[0] && link_up && settled);", "assign word_n = !(sh[0] && settled);")],
  'a trunk whose link is down reads NONE'),
 ('F14-key1-ignores-net', 'mini', 'rtl/mini_marker.v',
  [("if ((d0 == 3'd1) && net && !r_digits[3]) begin", "if ((d0 == 3'd1) && !r_digits[3]) begin")],
  'with no unit fitted key 1 is highway 1'),
 ('F15-old-serialiser-rate', 'ctl', 'rtl/ctl_write.v',
  [("parameter integer DIV = 32", "parameter integer DIV = 8")],
  'the serialiser runs at 128 kHz'),
 ('F16-clm-tied-off', 'net', 'rtl/ctl_queue.v',
  [("s_g <= head[14]; s_clm <= head[13]; s_bsy <= head[12];",
    "s_g <= head[14]; s_clm <= 1'b0; s_bsy <= head[12];")],
  'CLAIM reaches the latch: the old tie-off'),
 ('F18-no-unhold', 'net', 'rtl/net_unit.v',
  [("if (sp_fresh && (sp_port == cls_port) && !sp_m) cst <= C_UNHOLD;",
    "if (1'b0) cst <= C_UNHOLD;")],
  'a hold on a seizure that dies before the port arms is written away'),
 ('F19-origin-reads-shared-sweep', 'chain', 'rtl/net_unit.v',
  [("d_held <= o_ok; d_trunk <= o_cand; tmr <= 16'd0;", "d_held <= h_ok; d_trunk <= h_cand; tmr <= 16'd0;"),
   ("push_d[j2*15 +: 15] <= ent(o_cand[j2*`PW +: `PW], caller, 1'b1, 1'b0);",
    "push_d[j2*15 +: 15] <= ent(h_cand[j2*`PW +: `PW], caller, 1'b1, 1'b0);"),
   ("for (j2 = 0; j2 < 4; j2 = j2 + 1) if (o_ok[j2]) begin\n                        push_v[j2] <= 1'b1;".replace('\\n','\n'),
    "for (j2 = 0; j2 < 4; j2 = j2 + 1) if (h_ok[j2]) begin\n                        push_v[j2] <= 1'b1;".replace('\\n','\n')),
   ("N_SEIZE: cnt_orig = popc(o_ok);", "N_SEIZE: cnt_orig = popc(h_ok);")],
  'the origin seizes from its own copy of the sweep, not the shared result'),
 ('F20-no-seen-memory', 'net', 'rtl/net_unit.v',
  [("(sp_port != P00) && !st[sp_port];", "(sp_port != P00);")],
  'a port is read once while M stands: no phantom, no starved sweep'),
 ('F21-second-key-refloods', 'net', 'rtl/mini_marker.v',
  [("if (ctx_clm || keyed) begin", "if (ctx_clm) begin")],
  'after its own code a call\'s 1 is no second key'),
 ('F22-one-key-waits-for-four', 'net', 'rtl/net_unit.v',
  [("if (claimed && o_last && (dmo == 4'd0)) nst <= N_DONE;",
    "if (claimed && (r_ndig >= 3'd4) && (dmo == 4'd0)) nst <= N_DONE;")],
  'a one-key number after the code is connected at three digits'),
 ('F23-tie-a-not-gated', 'tie', 'rtl/baseband_card.v',
  [("assign a_tx = a_s2 && link_up && settled;", "assign a_tx = a_s2;")],
  'a cut link reads A = 0 whatever the receiver says'),
 ('F24-pointer-is-dst', 'word', 'rtl/block.v',
  [("assign hw_pd = sel_v && word_com[sel_slot];", "assign hw_pd = !blk_n && word_com[cw[10:8]];")],
  'the select names the card on /HW: DST no longer steers it'),
 ('F25-every-block-answers', 'word', 'rtl/block.v',
  [("sel_v    <= JUMPERED && (scan[5:3] == BLOCK);", "sel_v    <= JUMPERED;")],
  'only the block that owns the selected port answers on /HW'),
 ('F26-select-inside-a-window', 'word', 'rtl/word_rx.v',
  [("if (frame_stb) ws_pd <= want && (scan == at) && (win == 4'd0);",
    "if (frame_stb) ws_pd <= want && (scan == at);")],
  'a reader waits out another read\'s eight frames before it selects'),
 ('F27-sweep-takes-busy-trunk', 'net', 'rtl/net_unit.v',
  [("if (!h_m && !h_b && is_trunk(rd_word[4:0]) && h_mask[rdir]) begin",
    "if (is_trunk(rd_word[4:0]) && h_mask[rdir]) begin")],
  'the sweep takes only a trunk that was free at its select'),
 ('F31-ltu-frame-not-found', 'ltu', 'rtl/local_trunk.v',
  [("wire       r_first = clk_in && !rq;", "wire       r_first = 1'b0;")],
  'the receiver finds cell 0 by the far TX_CLK, so each channel lands on its own port'),
 ('F32-ltu-a-not-gated', 'ltu', 'rtl/local_trunk.v',
  [("assign a_tx     = live ? x_a : 8'd0;", "assign a_tx     = x_a;")],
  'a cut group drops every A, so every call releases'),
 ('F33-ltu-no-mute', 'ltu', 'rtl/local_trunk.v',
  [("assign mute_blk = !live;", "assign mute_blk = 1'b0;")],
  'a cut group busies all eight ports through MUTE_BLK'),
 ('F34-ltu-word-not-gated', 'ltu', 'rtl/local_trunk.v',
  [("assign word_n = {8{!(sh[0] && live)}};", "assign word_n = {8{!(sh[0] && settled)}};")],
  'a cut group reads NONE on every channel'),
 ('F35-glare-held-as-incoming', 'lfull', 'rtl/net_unit.v',
  [("!mine && (sp_port != P00)", "(sp_port != P00)")],
  'in glare the classifier leaves the channel to the origin: the two callers are joined'),
 ('F36-nodig-paused-by-a-digit', 'dial', 'rtl/pulse_reg.v',
  [("if (tick_1k && !nodig && !restart && !dig_stb) begin",
    "if (tick_1k && !counting && !nodig && !restart && !dig_stb) begin")],
  'a line that pulses and never ends a digit still times out'),
 ('F37-no-watch-after-connect', 'mini', 'rtl/mini_marker.v',
  [("                        state     <= S_WATCH;",
    "                        r_release <= 1'b1;\n                        state     <= S_DRAIN;")],
  'a caller gone inside T_ARM of the connect does not leave the called port BUSY'),
 ('F38-watch-on-hook-alone', 'mini', 'rtl/pulse_reg.v',
  [("assign settled = busy && steady && (nd_t >= {7'd0, SETTLE});",
    "assign settled = busy && steady;")],
  'the watch counts from the connect, not from the last digit\'s make'),
 ('F39-watch-on-timer-alone', 'mini', 'rtl/pulse_reg.v',
  [("assign settled = busy && steady && (nd_t >= {7'd0, SETTLE});",
    "assign settled = busy && (nd_t >= {7'd0, SETTLE});")],
  'the watch waits for the caller off-hook, not only for time to pass'),
 ('F40-busy-is-cannot-complete', 'max', 'rtl/marker.v',
  [("ent(caller, (h_ans && own_busy) ? BUSYTONE : NOGO,", "ent(caller, NOGO,")],
  'a busy line gets busy tone, not cannot-complete'),
 ('F41-no-answers-to-hunt', 'max', 'rtl/marker.v',
  [("(h_ans ? (d_ans && (d_hs == h_num)) : d_out)", "(h_ans ? 1'b0 : d_out)")],
  'a number that fails is hunted among the ports that answer to it'),
 ('F42-hunt-takes-a-busy-port', 'max', 'rtl/marker.v',
  [("if (!s_m && !s_b && (h_p != caller) &&", "if ((h_p != caller) &&")],
  'a hunt takes only a port that was free at its select'),
 ('F43-walk-takes-a-busy-port', 'max', 'rtl/marker.v',
  [("wire w_ask   = s_m && !s_b;", "wire w_ask   = s_m;")],
  'the walk takes a caller only if it was free at its select'),
 ('F44-restricted-floor-open', 'max', 'rtl/marker.v',
  [("lim_local <= d_rest && !d_zonly;", "lim_local <= 1'b0;")],
  'a restricted card without z is local only: 9 refused'),
 ('F45-z-ignored', 'max', 'rtl/marker.v',
  [("lim_z     <= d_zonly;", "lim_z     <= 1'b0;")],
  'restricted z lets only 0 through'),
 ('F46-data-line-is-voice', 'max', 'rtl/word_dec.v',
  [("assign voice  = (line && !data) || rest || ans || cnail;", "assign voice  = line || rest || ans || cnail;"),
   ("assign caller = (line && !data) || rest || ans || tone;", "assign caller = line || rest || ans || tone;")],
  'a data line neither calls nor is called'),
 ('F47-no-pwait', 'max', 'rtl/marker.v',
  [("((d_caller && (d_pri || !pwait)) || d_cnail || d_out)", "(d_caller || d_cnail || d_out)")],
  'under PWAIT the register goes to the P line waiting, not the plain line'),
 ('F48-no-watch-after-connect', 'max', 'rtl/marker.v',
  [("S_WATCH: if (!bus_idle) reg_restart <= 1'b1;",
    "S_WATCH: if (1'b1) begin reg_release <= 1'b1; state <= S_DRAIN; end")],
  'a caller gone at the connect does not leave the called port BUSY'),
 ('F49-nail-writes-its-dest', 'max', 'rtl/marker.v',
  [("push_v <= 2'b01;\n                push_d <= {15'd0, ent(nail_p, nail_d, 1'b1, 1'b0)};   // the nail's one write",
    "push_v <= 2'b11;\n                push_d <= {ent(nail_d, nail_p, 1'b1, 1'b0), ent(nail_p, nail_d, 1'b1, 1'b0)};")],
  'a tied nail is one way: it writes its own port, never its dest'),
 ('F50-type-bits-the-old-way', 'max', 'rtl/word_dec.v',
  [("assign ans   = (typ == 2'b10);", "assign ans   = (typ == 2'b01);"),
   ("assign cnail = (typ == 2'b01);", "assign cnail = (typ == 2'b10);")],
  'answers-to and call nail are read in wire order'),
 ('F51-source-not-listened', 'max', 'rtl/marker.v',
  [("end else if ((called != caller) && d_src) begin", "end else if (1'b0) begin")],
  'a source dialled is listened to'),
 ('F52-no-nail-walk', 'max', 'rtl/marker.v',
  [("if (w_nail) begin nail_v <= 1'b1;", "if (1'b0) begin nail_v <= 1'b1;")],
  'the walk makes a tied nail'),
 ('F53-pwait-never-clears', 'max', 'rtl/marker.v',
  [("pwait      <= pwait_seen || (w_pline && !w_take);",
    "pwait      <= pwait || pwait_seen || (w_pline && !w_take);")],
  'a round that finds no P line waiting clears PWAIT'),
 ('F17-card-C-dead', 'tie', 'rtl/baseband_card.v',
  [("assign c_tx = c_sync;", "assign c_tx = 1'b0;")],
  'bits cross the tie trunk'),
]

def fid(name):
    return name.split('-')[0]

def want(name):
    return CONTRACT.get(fid(name), 'RED')

def edits(f):
    # every file this fault touches, with its (anchor, replacement) pairs
    return [(f[2], f[3])] + (f[5] if len(f) > 5 else [])

def put_back(f, base, write):
    # Apply the fault's anchors to the tree at `base`, in order, writing the
    # files only if `write` and every anchor was there exactly once.  Returns
    # the anchors that were not.
    missing, done = [], []
    for path, reps in edits(f):
        s = open(os.path.join(base, path)).read()
        for a, b in reps:
            n = s.count(a)
            if n != 1:
                missing.append(f'{path}: found {n}x: {a.strip()[:60]}')
                continue
            s = s.replace(a, b)
        done.append((path, s))
    if write and not missing:
        for path, s in done:
            open(os.path.join(base, path), 'w').write(s)
    return missing

def verdict(out, timed_out):
    lines = [l.strip() for l in out.splitlines()]
    fails = [l for l in lines if l.startswith('FAIL ')]
    count = re.search(r'(\d+) checks, (\d+) errors', out)
    if fails or (count and int(count.group(2)) > 0):
        return 'RED', ([count.group(0)] if count else []) + fails[:6]
    if timed_out or 'TIMEOUT' in lines:
        return 'TIMEOUT', ['the harness gave up' if timed_out else "the bench's watchdog fired"]
    if count and re.search(r'checks, 0 errors\.\s+PASS', out):
        return 'GREEN', [count.group(0)]
    return 'BROKEN', [l for l in lines if 'rror' in l or 'Killed' in l][:6] or lines[-3:]

def run(f, timeout, cap):
    name, bench, claim = f[0], f[1], f[4]
    d = os.path.join(OUT, name)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    try:
        for x in ('rtl', 'tb'):
            shutil.copytree(os.path.join(ROOT, x), os.path.join(d, x))
        shutil.copy(os.path.join(ROOT, 'Makefile'), d)
        missing = put_back(f, d, write=True)
        if missing:
            return name, bench, claim, 'NOT-APPLIED', missing
        # Its own process group, so a timeout takes the simulation with it
        # and not only `make`.
        p = subprocess.Popen(cap + ['make', 'BUILD=bld', bench], cwd=d,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             env=dict(os.environ, TMPDIR=TMP), start_new_session=True)
        try:
            out, timed_out = p.communicate(timeout=timeout)[0], False
        except subprocess.TimeoutExpired:
            os.killpg(p.pid, signal.SIGKILL)
            out, timed_out = p.communicate()[0], True
        v, lines = verdict(out.decode(errors='replace'), timed_out)
        return name, bench, claim, v, lines
    finally:
        shutil.rmtree(d, ignore_errors=True)

def report(name, bench, claim, v, lines):
    mark = '' if v == want(name) else f'   <-- the contract says {want(name)}'
    print(f'{v:12s} {name:34s} [{bench}]  {claim}{mark}', flush=True)
    for l in lines:
        print(f'               {l}', flush=True)

if __name__ == '__main__':
    ap = argparse.ArgumentParser(description='put each fault back and run its bench')
    ap.add_argument('only', nargs='*', help='run only the faults whose name starts so')
    ap.add_argument('-j', type=int, default=3, help='faults at a time (3)')
    ap.add_argument('--timeout', type=int, default=3000, help='seconds one bench may take')
    ap.add_argument('--check', action='store_true', help='apply every anchor in place, run nothing')
    a = ap.parse_args()
    todo = [f for f in FAULTS if not a.only or any(f[0].startswith(x) for x in a.only)]
    if not todo:
        sys.exit(f'no fault starts with {" or ".join(a.only)}')

    if a.check:
        stale = 0
        for f in todo:
            missing = put_back(f, ROOT, write=False)
            if missing:
                stale += 1
                report(f[0], f[1], f[4], 'NOT-APPLIED', missing)
        print(f'\n  {len(todo)} faults, {stale} not applied.  {"FAIL" if stale else "PASS"}')
        sys.exit(1 if stale else 0)

    os.makedirs(OUT, exist_ok=True)
    os.makedirs(TMP, exist_ok=True)
    cap = CAP if subprocess.run(CAP + ['true'], capture_output=True).returncode == 0 else []
    if not cap:
        print('  (no systemd-run: the benches run without a memory ceiling)', flush=True)
    got = {}
    with ThreadPoolExecutor(max_workers=a.j) as ex:
        jobs = [ex.submit(run, f, a.timeout, cap) for f in todo]
        for j in as_completed(jobs):
            r = j.result()
            got[r[0]] = r[3]
            report(*r)
    off = [n for n in (f[0] for f in todo) if got[n] != want(n)]
    tally = ', '.join(f'{sum(v == k for v in got.values())} {k}'
                      for k in ('RED', 'GREEN', 'TIMEOUT', 'BROKEN', 'NOT-APPLIED')
                      if any(v == k for v in got.values()))
    print(f'\n  {len(todo)} faults: {tally}.  The contract is ' +
          ('met.  PASS' if not off else
           'NOT met: ' + ', '.join(f'{fid(n)} {got[n]}' for n in off) + '.  FAIL'))
    sys.exit(1 if off else 0)
