#!/usr/bin/env python3
# faults.py -- the proof that the checks can fail.  STYLE.md 7.
#
# Each entry puts one old bug, or one missing rule, back into a COPY of the
# tree under build/fault/, runs the bench that is meant to catch it, and
# reports RED (the bench caught it) or GREEN (it did not).  Every entry should
# be RED, with two exceptions that are the design, not a gap:
#
#   F03  the refusal lands after the CLAIM word for two reasons -- the unit
#        raises `att` only once its word is out, and it outranks the marker on
#        cable B.  Break one and the order holds.  F03b breaks both: RED.
#   F05  a trunk's M is kept from being a call twice over -- the marker reads
#        the card's word, and the unit holds the trunk BUSY within a pass.
#        F05b removes both: RED.
#
#   python3 faults.py            every fault, three at a time (make faults)
#   python3 faults.py F07 ...    only those named
#
# A network build is about 200 MB; each copy is deleted after its run.
import os, re, shutil, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

ROOT = '/home/joel/telco/newimpl'
OUT  = os.path.join(ROOT, 'build', 'fault')

FAULTS = [
 ('F01-release-on-gone-only', 'net', 'rtl/net_unit.v',
  [("wire       o_gone  = r_gone || r_nodig || !r_busy;", "wire       o_gone  = r_gone;")],
  'the unit releases its trunks on the no-digit timeout and on a freed register'),
 ('F02-no-busy-term', 'net', 'rtl/net_unit.v',
  [("wire cls_seen  = (cst == C_IDLE) && sp_fresh && sp_m && !sp_busy &&",
    "wire cls_seen  = (cst == C_IDLE) && sp_fresh && sp_m &&")],
  'the classifier (and so the monitor) ignores a port whose BUSY is set'),
 ('F03-refusal-before-claim', 'net', 'rtl/net_unit.v',
  [("""                push_v <= 5'b00001;
                push_d <= {60'd0, ent(m_want_port, P00, 1'b1, 1'b1)};
                for (u = 0; u < NRES; u = u + 1) if (rs_mine[u]) begin""",
    """                push_v <= 5'b00000;
                for (u = 0; u < NRES; u = u + 1) if (rs_mine[u]) begin"""),
   ("CL_WAIT: if (q_empty && !w_claim) begin att <= 1'b1; cl_st <= CL_ACK; end",
    "CL_WAIT: begin att <= 1'b1; cl_st <= CL_ACK; end"),
   ("CL_ACK:  if (att_ack) begin att <= 1'b0; cl_st <= CL_IDLE; end",
    "CL_ACK:  if (att_ack) begin att <= 1'b0; cl_st <= CL_IDLE; push_v <= 5'b00001; push_d <= {60'd0, ent(att_port, P00, 1'b1, 1'b1)}; end")],
  'the CLAIM word goes out before att, so a refusal lands after it'),
 ('F03b-refusal-first-and-no-rank', 'net', 'rtl/net_unit.v',
  [("""                push_v <= 5'b00001;
                push_d <= {60'd0, ent(m_want_port, P00, 1'b1, 1'b1)};
                for (u = 0; u < NRES; u = u + 1) if (rs_mine[u]) begin""",
    """                push_v <= 5'b00000;
                for (u = 0; u < NRES; u = u + 1) if (rs_mine[u]) begin"""),
   ("CL_WAIT: if (q_empty && !w_claim) begin att <= 1'b1; cl_st <= CL_ACK; end",
    "CL_WAIT: begin att <= 1'b1; cl_st <= CL_ACK; end"),
   ("CL_ACK:  if (att_ack) begin att <= 1'b0; cl_st <= CL_IDLE; end",
    "CL_ACK:  if (att_ack) begin att <= 1'b0; cl_st <= CL_IDLE; push_v <= 5'b00001; push_d <= {60'd0, ent(att_port, P00, 1'b1, 1'b1)}; end"),
   ],
  'the refusal lands after CLAIM -- the handshake broken AND the marker deaf to /UREQ',
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
 ('F17-card-C-dead', 'tie', 'rtl/baseband_card.v',
  [("assign c_tx = c_sync;", "assign c_tx = 1'b0;")],
  'bits cross the tie trunk'),
]

def run(f):
    name, bench, path, reps, claim = f[:5]
    extra = f[5] if len(f) > 5 else []
    d = os.path.join(OUT, name)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    for x in ('rtl', 'tb'):
        shutil.copytree(os.path.join(ROOT, x), os.path.join(d, x))
    shutil.copy(os.path.join(ROOT, 'Makefile'), d)
    p = os.path.join(d, path)
    s = open(p).read()
    for a, b in reps:
        if s.count(a) != 1:
            shutil.rmtree(d, ignore_errors=True)
            return (name, bench, claim, 'NOT APPLIED', [a[:60]])
        s = s.replace(a, b)
    open(p, 'w').write(s)
    for xp, xreps in extra:
        q = os.path.join(d, xp); t = open(q).read()
        for a2, b2 in xreps:
            if t.count(a2) != 1:
                shutil.rmtree(d, ignore_errors=True)
                return (name, bench, claim, 'NOT APPLIED', [a2[:60]])
            t = t.replace(a2, b2)
        open(q, 'w').write(t)
    try:
        r = subprocess.run(['make', 'BUILD=bld', bench], cwd=d, capture_output=True,
                           text=True, timeout=1500)
        out = r.stdout + r.stderr
    except subprocess.TimeoutExpired as e:
        out = (e.stdout or '') + 'TIMEOUT(harness)'
    fails = [l.strip() for l in out.splitlines() if 'FAIL ' in l or 'TIMEOUT' in l]
    summary = [l.strip() for l in out.splitlines() if 'checks,' in l]
    verdict = 'RED' if (fails or 'Error' in out) and not ('checks, 0 errors' in out) else 'GREEN'
    shutil.rmtree(d, ignore_errors=True)
    return (name, bench, claim, verdict, summary + fails[:6])

if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    sel = sys.argv[1:]
    todo = [f for f in FAULTS if not sel or any(f[0].startswith(x) for x in sel)]
    with ThreadPoolExecutor(max_workers=3) as ex:
        for name, bench, claim, verdict, lines in ex.map(run, todo):
            print(f'{verdict:12s} {name:34s} [{bench}]  {claim}', flush=True)
            for l in lines: print(f'               {l}', flush=True)
