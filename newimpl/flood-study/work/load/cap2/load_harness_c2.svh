// load_harness.svh -- THE TRAFFIC-LOAD HARNESS for the pulse-flood network.
//
// Included ONCE inside a topology's top module (tb_load2.sv, tb_load2b.sv,
// tb_load3.sv), after the topology has declared
//
//   localparam int NX = <exchanges>;                 at most 8
//   localparam [64*NX-1:0] LD_PHONES = {...};         phone ports, exchange 0 in the low 64 bits
//   localparam [64*NX-1:0] LD_TRUNKS = {...};         trunk ports (link stats, invariants)
//   localparam [3*NX-1:0]  LD_CODE_E = {...};         each exchange's code e b
//   localparam [3*NX-1:0]  LD_CODE_B = {...};
//
// and BEFORE its site instances, which it wires to the nets declared here:
//   `LD_SITE_COMMON(x)   every common port of site_net x (clock, phones, watch outputs)
//   `LD_SITE_TIMERS      the scaled windows and timers, as site_net parameters
//   `LD_PROBE(x, INST)   hierarchical taps into INST.u_x (the marker and the unit)
//   ld_clk[x]            the topology drives it from its own clock regs
//   ld_tup[x*64 +: 64]   link-up of every trunk port (the topology knows the card)
// A new topology writes only its clocks, its sites and its cables.
//
// ---- WHAT A PHONE DOES (one state machine a line, all in one 1 kHz block) ----
//   IDLE     on hook; exponential idle time, mean +idle_ms; then LIFT
//   WAITDT   off hook, waits up to +dt_ms for DIAL TONE (a steady 1: port 01);
//            none -> NODT.  A caller's signature heard here is an incoming call
//            put through as it lifted -> COLLIDE, and it talks as the callee
//   DIAL     +pre_ms, then the digits at the scale's pulse timing (break/make,
//            +idg_ms between digits).  Local: h s.  Network: 1 e b h s
//   POST     after the last break, up to +pd_ms: steady 0 (port 03) is
//            cannot-complete -> BUSY or NOGO; steady 1 -> DTAGAIN; the called
//            phone decoding OUR signature while on hook -> RINGBACK; ANOTHER
//            phone doing so -> WRONG; another phone's signature heard -> WRONG,
//            or JOINED if that phone is itself a caller (residual glare); else
//            SILENT at +pd_ms
//   RINGBACK the callee answers within +ans_ms of its first bell (or never,
//            +noans per mille) -> TALK; +ringmax_ms -> NOANS
//   TALK     about +hold_ms; each side must hear the other's signature (else
//            NOSPEECH) and nobody else's (else XTALK); one side at random hangs
//            up, the other up to +lag_ms later
//   REST     on hook +rest_ms before it may lift again; the CALL line prints here
//   ALERT    a called phone: on hook, hearing a signature and/or ringing (E in
//            cadence on its e output).  A bell with no identifiable caller and
//            no caller dialling this line (now or lately) is a PHANTOM ring
//   +abandon per mille of attempts hang up at a uniform moment between lift and
//   the expected answer -> ABANDON.  At +dur_ms no new call starts; at
//   +dur_ms + +grace_ms every phone hangs up (calls in progress -> CUT); after
//   +drain_ms the INVARIANT lines are checked and the SUMMARY is printed.
//
// ---- SIGNATURES (what a phone sends while off hook, one bit a frame) ----------
//   11 runs, the level toggling at every run edge: a SYNC run of 10 frames,
//   then 9 id bits {exchange[2:0], port[5:0]} MSB first and an odd-parity bit,
//   each a run of 2 frames (0) or 5 frames (1).  A slip (a bit gained or lost)
//   moves one run by one frame: 1-3 read 0, 4-6 read 1, 8-31 is SYNC, 7 is
//   rejected, 32 or more is a TONE.  A word is kept only with good parity and
//   an id that is a fitted phone; an id is HEARD after +sig_k (3) identical
//   words in a row and stays heard while a matching word came within 4 ms.
//   Dial tone (steady 1), cannot-complete (steady 0) and FILL/ringback/idle
//   (1010...) can never decode.  On hook a phone sends 1010... (CVSD idle).
//   A self-test at time 0 decodes every phone's signature at a random phase
//   with a slip in it, and feeds tones and FILL through: SELFTEST lines.
//
// ---- KNOBS (plusargs; ms are simulated ms at the build's scale) ----------------
// Every one is printed at start on a KNOB line.  Defaults: scale 8 / SCALE1.
//   +seed=N          1        every phone's xorshift is seeded from it and its index
//   +dur_ms=N        10000 / 60000   traffic period; no call starts after it
//   +grace_ms=N      0        after dur, let calls run on this long before the hang-up
//   +drain_ms=N      2500 / 20000    after the hang-up, before the INVARIANT check
//   +idle_ms=N       60000 / 300000  mean (exponential) on-hook time between attempts
//   +switch_ms=N +idle2_ms=N  0 (off): from switch_ms after the start the mean is idle2_ms
//                    (a load step: overload, then recovery, or the reverse)
//   +nlines=N        64       only the first N fitted lines of each exchange take part
//   +orig_x=MASK     255      exchanges whose lines originate (bit x = exchange x)
//   +pnet=N          500      per mille of attempts that dial another exchange
//   +dest_mode=N     0        0 uniform: local over own lines, network over all other lines
//                             1 one-way: only exchange +from_x (0) dials the network,
//                               to exchange +to_x (1); every other attempt is local
//                             2 hot spot: everyone dials +hot=Xpp (e.g. +hot=B20)
//                             3 bad code: network attempts dial 1 +bad_e +bad_b h s
//                               (default 2 7, a code nobody has)
//                             4 fixed pairs: +pairs=A24B31,A25Z20,... each listed caller
//                               dials only its partner; Zhs is the bad code then h s;
//                               unlisted lines never originate.  +pair_gap_ms=G (0):
//                               the i-th pair lifts at start + i*G, every npairs*G
//   +dt_ms=N         3000 / 20000    wait this long for dial tone, else NODT
//   +pre_ms=N        60 / 500        dial tone heard -> first break
//   +brk_ms=N +mk_ms=N   12/8 / 60/40  a pulse's break and make
//   +idg_ms=N        100 / 720       make between digits (register.md 2: >= 720 real)
//   +idg_jit_ms=N    0        plus uniform 0..N ms per digit
//   +abandon=N       0        per mille of attempts hang up at a uniform moment between
//                             lift and the expected answer (ABANDON, ab= the phase)
//   +quit_on_tone=0|1  1      a caller hearing cannot-complete mid-dial hangs up then
//   +pd_ms=N         1500 / 12000    after the last break, classify within this (else SILENT)
//   +hup_ms=N        100 / 800       listen this long to a final tone before hanging up
//   +ans_ms=N        300 / 3000      a called phone answers uniformly 0..N ms after its first bell
//   +noans=N         0        per mille of rung phones that never answer
//   +ringmax_ms=N    1500 / 12000    a caller gives up ringing after this (NOANS)
//   +hold_ms=N       1500 / 10000    mean talk time (exponential; +hold_fixed=1: exactly N)
//   +lag_ms=N        50 / 400        the second party hangs up 0..N ms after the first
//   +rest_ms=N       120 / 800       on hook after a call before it may lift again
//   +verify_ms=N     20       after the answer, listening starts this much later
//   +sig_k=N         3        identical words before an id is HEARD
//   +dbg_sig=Xpp:Ypp          Xpp sends Ypp's signature (proves WRONG is seen)
//   +dbg_misdial=Xpp          Xpp dials the next line after its intended one (proves WRONG)
//   +trace=1         0        a TR line at every phone state change
//   +prog_ms=N       2000 / 16000    a PROG line (totals, and this interval's figures)
//   +max_ms=N        0        a hard stop (TIMEOUT line, invariants, summary)
//   watchdog thresholds (STUCK lines), ms held continuously:
//   +wd_port_ms      8*T_REL + RING_ON + RING_OFF   a phone's port BUSY while it is idle
//   +wd_reg_ms       6*NODIG            the register, and the marker out of IDLE
//   +wd_org_ms       T_KEY + T_CLAIM + 3*NODIG   the origin holding a trunk
//   +wd_mon_ms       2*T_KEY + 4*CLR    a monitor
//   +wd_res_ms       2*(T_KEY + T_CLAIM) + 4*T_REL   a resolver
//   +wd_hunt_ms      200                the sweep running
//   +wd_att_ms       NODIG + 100        the unit's att waiting for the marker
//   +phantom_grace_ms 6*T_REL + RING_ON + RING_OFF   a bell this soon after a call to the
//                             line ended is that call's, not a phantom
// Compile-time: +define+SCALE1 (real timers), +define+LD_NMON=n +define+LD_NRES=n
// (the unit's pools; default 2 and 2), +define+LD_SMALL (16 lines an exchange).
//
// ---- OUTPUT (every line starts with its kind; times are sim ms, - = never) -------
//   CALL id= from=Xpp to=Ypp|eb?? kind=L|N|BAD dial=digits lift= dt= key= last= tone=
//        alert= bell= ans= end= rel= out=CLASS why=REASON heard=Zpp rang=Zpp cb= xv= cv= ab= mid=
//     dt   dial tone heard            key   end of the first digit's last break
//     last end of the last break      tone  first steady 0 after the key
//     alert the called phone first decoded this caller   bell  its first bell
//     ans  the called phone went off hook   end  the first of the two hung up
//     rel  the caller hung up         heard a stranger's signature, rang the phone that
//     decoded us (the right one, or not)   cb  the called line at the probe: 1 busy phone,
//     2 BUSY port with an idle phone   xv/cv caller/callee heard the other: 1 yes, 0 no,
//     2 the partner and a stranger, 3 only a stranger, -1 not reached
//     ab  the phase it was abandoned or cut in   mid  a signature heard mid-dial
//   CLASS: OK BUSY NOGO NODT ABANDON NOANS WRONG JOINED DTAGAIN SILENT XTALK
//          NOSPEECH COLLIDE CUT        REASON: see wname()
//   WRONGRING / PHANTOM / IDLEHEAR / DRAINRING t= at=...   safety events at a called line
//   STUCK t= what= ex= idx= held_ms=  (and STUCK-END when it clears); STUCK what=port at=
//   PROG t= totals | iv_ms= started= ok= failed= reg_occ A= B= ...
//   INVARIANT PASS|FAIL <what> ...;  INVARIANT TOTAL pass= fail=
//   SUMMARY run|outcome|attempts|why|safety|carried|dialtone_delay|postdial_alert|
//           postdial_nogo|exchange|link|unit|nogo_written|checks|line ...
//   SELFTEST sig PASS|FAIL;  KNOB name=value;  TOPO ...;  START/STOP/HANGUP/END t=
//
// ---- SCALE ----------------------------------------------------------------------
//   default: the benches' scale 8 (T_ARM 2, T_REL 32, RING 64/128, HIT 1, ID 16,
//   CLR 32, NODIG 1250, T_GUARD0 16, T_KEY 625, T_CLAIM 250; dial 12/8 ms,
//   100 ms between digits, 60 ms before the first).
//   +define+SCALE1: the real values (16, 256, 2048/4096, 8, 128, 256, 10000,
//   128, 5000, 2000; dial 10 pps 60/40, 720 ms between digits (ES 201 187's
//   minimum, register.md 2), 500 ms before the first).  The sweep, word reads,
//   scan and cable B are wiring timing and are the same at both scales.

// ============================================================================
// SCALE
// ============================================================================
`ifdef SCALE1
localparam int LD_SCALE = 1;
localparam int LD_T_ARM = 16,  LD_T_REL = 256, LD_RING_ON = 2048, LD_RING_OFF = 4096;
localparam int LD_HIT = 8,     LD_ID = 128,    LD_CLR = 256,      LD_NODIG = 10000;
localparam int LD_T_GUARD0 = 128, LD_T_KEY = 5000, LD_T_CLAIM = 2000;
localparam int LD_D_BRK = 60, LD_D_MK = 40, LD_D_IDG = 720, LD_D_PRE = 500;
localparam int LD_D_IDLE = 300000, LD_D_DT = 20000, LD_D_PD = 12000, LD_D_ANS = 3000;
localparam int LD_D_HOLD = 10000, LD_D_LAG = 400, LD_D_REST = 800, LD_D_RINGMAX = 12000;
localparam int LD_D_HUP = 800, LD_D_DUR = 60000, LD_D_DRAIN = 20000;
`else
localparam int LD_SCALE = 8;
localparam int LD_T_ARM = 2,   LD_T_REL = 32,  LD_RING_ON = 64,   LD_RING_OFF = 128;
localparam int LD_HIT = 1,     LD_ID = 16,     LD_CLR = 32,       LD_NODIG = 1250;
localparam int LD_T_GUARD0 = 16, LD_T_KEY = 625, LD_T_CLAIM = 250;
localparam int LD_D_BRK = 12, LD_D_MK = 8, LD_D_IDG = 100, LD_D_PRE = 60;
localparam int LD_D_IDLE = 60000, LD_D_DT = 3000, LD_D_PD = 1500, LD_D_ANS = 300;
localparam int LD_D_HOLD = 1500, LD_D_LAG = 50, LD_D_REST = 120, LD_D_RINGMAX = 1500;
localparam int LD_D_HUP = 100, LD_D_DUR = 10000, LD_D_DRAIN = 2500;
`endif

`ifndef LD_NMON
`define LD_NMON 2
`endif
`ifndef LD_NRES
`define LD_NRES 2
`endif
localparam int LD_NMON = `LD_NMON;
localparam int LD_NRES = `LD_NRES;

`define LD_SITE_TIMERS .T_ARM(9'(LD_T_ARM)), .T_REL(9'(LD_T_REL)), \
        .RING_ON(13'(LD_RING_ON)), .RING_OFF(13'(LD_RING_OFF)), \
        .HIT(9'(LD_HIT)), .ID(9'(LD_ID)), .CLR(9'(LD_CLR)), .NODIG(16'(LD_NODIG)), \
        .T_GUARD0(16'(LD_T_GUARD0)), .T_KEY(16'(LD_T_KEY)), .T_CLAIM(16'(LD_T_CLAIM)), \
        .NMON(LD_NMON), .NRES(LD_NRES)

localparam int NG = NX * 64;

// ============================================================================
// THE NETS A TOPOLOGY WIRES ITS SITES TO
// ============================================================================
wire [NX-1:0]          ld_clk;
reg                    ld_rst_n = 1'b0;
reg  [NG-1:0]          ld_hook  = '0;
wire [NG-1:0]          ld_tx;
wire [NG-1:0]          ld_rx, ld_e, ld_busy, ld_tup;
wire [NX-1:0]          ld_fs, ld_t1k, ld_rc, ld_sd, ld_sc, ld_wr, ld_cl;
wire [NX-1:0]          ld_reg, ld_mko, ld_cla, ld_hunt, ld_uno;
wire [3*NX-1:0]        ld_mks;
wire [4*NX-1:0]        ld_dirs;
wire [LD_NRES*NX-1:0]  ld_res;
wire [LD_NMON*NX-1:0]  ld_mon;
wire [8*NX-1:0]        ld_gl, ld_nf;

`define LD_SITE_COMMON(X) \
    .clk(ld_clk[X]), .rst_n(ld_rst_n), \
    .hook(ld_hook[(X)*64 +: 64]), .tx(ld_tx[(X)*64 +: 64]), \
    .rx(ld_rx[(X)*64 +: 64]), .e(ld_e[(X)*64 +: 64]), \
    .frame_stb(ld_fs[X]), .tick_1k(ld_t1k[X]), .ring_cad_n(ld_rc[X]), \
    .port_busy(ld_busy[(X)*64 +: 64]), \
    .b_sdata(ld_sd[X]), .b_sclk(ld_sc[X]), .b_wr(ld_wr[X]), .b_clash(ld_cl[X]), \
    .reg_busy(ld_reg[X]), .mk_state(ld_mks[(X)*3 +: 3]), .mk_ovf(ld_mko[X]), \
    .dirs_held(ld_dirs[(X)*4 +: 4]), .res_busy(ld_res[(X)*LD_NRES +: LD_NRES]), \
    .mon_held(ld_mon[(X)*LD_NMON +: LD_NMON]), .claimed(ld_cla[X]), \
    .hunting(ld_hunt[X]), .un_ovf(ld_uno[X]), \
    .n_glare(ld_gl[(X)*8 +: 8]), .n_nofwd(ld_nf[(X)*8 +: 8])

// ---- hierarchical taps: the bench looks inside to say WHY ------------------------
wire [4*NX-1:0]  ld_p_nst;              // net_unit origin state
wire [2*NX-1:0]  ld_p_oafter;
wire [NX-1:0]    ld_p_guard, ld_p_rbrk, ld_p_f1, ld_p_f2, ld_p_flood, ld_p_nogo, ld_p_local, ld_p_done;
wire [3*NX-1:0]  ld_p_rndig;
wire [NX-1:0]    ld_p_seize, ld_p_nomon, ld_p_nfbusy, ld_p_nfempty, ld_p_claimw, ld_p_unhold;
wire [NX-1:0]    ld_p_evg, ld_p_evn, ld_p_att, ld_p_uqe, ld_p_mqe, ld_p_uoe, ld_p_moe;
wire [3*NX-1:0]  ld_p_cst;
wire [2*NX-1:0]  ld_p_fst, ld_p_clst;
wire [2*NX-1:0]  ld_p_mpv;             // mini marker's push to its queue
wire [30*NX-1:0] ld_p_mpd;
wire [NX-1:0]    ld_p_mref, ld_p_mtake, ld_p_mctx, ld_p_mnodig;
wire [6*NX-1:0]  ld_p_mcalled;

`define LD_PROBE(X, S) \
    assign ld_p_nst[(X)*4 +: 4]    = S.u_x.u_net.nst; \
    assign ld_p_oafter[(X)*2 +: 2] = S.u_x.u_net.o_after; \
    assign ld_p_guard[X]  = S.u_x.u_net.guarding; \
    assign ld_p_rbrk[X]   = S.u_x.u_net.r_brk; \
    assign ld_p_f1[X]     = S.u_x.u_net.f1; \
    assign ld_p_f2[X]     = S.u_x.u_net.f2; \
    assign ld_p_rndig[(X)*3 +: 3] = S.u_x.u_net.r_ndig; \
    assign ld_p_flood[X]  = S.u_x.u_net.flood_go; \
    assign ld_p_nogo[X]   = S.u_x.u_net.nogo; \
    assign ld_p_local[X]  = S.u_x.u_net.local_go; \
    assign ld_p_done[X]   = S.u_x.u_net.done; \
    assign ld_p_seize[X]  = S.u_x.u_net.w_cls && (S.u_x.u_net.cst == 3'd2); \
    assign ld_p_nomon[X]  = S.u_x.u_net.w_cls && (S.u_x.u_net.cst == 3'd2) && !S.u_x.u_net.m_free_any; \
    assign ld_p_unhold[X] = S.u_x.u_net.w_cls && (S.u_x.u_net.cst == 3'd4); \
    assign ld_p_nfbusy[X] = S.u_x.u_net.nf_busy; \
    assign ld_p_nfempty[X] = S.u_x.u_net.nf_empty; \
    assign ld_p_claimw[X] = S.u_x.u_net.w_claim; \
    assign ld_p_evg[X]    = S.u_x.u_net.w_ev && S.u_x.u_net.ev_glare; \
    assign ld_p_evn[X]    = S.u_x.u_net.w_ev && !S.u_x.u_net.ev_glare; \
    assign ld_p_att[X]    = S.u_x.u_net.att; \
    assign ld_p_uqe[X]    = S.u_x.u_net.q_empty; \
    assign ld_p_uoe[X]    = S.u_x.u_net.b_oe; \
    assign ld_p_cst[(X)*3 +: 3]  = S.u_x.u_net.cst; \
    assign ld_p_fst[(X)*2 +: 2]  = S.u_x.u_net.fst; \
    assign ld_p_clst[(X)*2 +: 2] = S.u_x.u_net.cl_st; \
    assign ld_p_mqe[X]    = S.u_x.u_mk.q_empty; \
    assign ld_p_moe[X]    = S.u_x.u_mk.b_oe; \
    assign ld_p_mpv[(X)*2 +: 2]   = S.u_x.u_mk.push_v; \
    assign ld_p_mpd[(X)*30 +: 30] = S.u_x.u_mk.push_d; \
    assign ld_p_mref[X]   = S.u_x.u_mk.att_refuse && (S.u_x.u_mk.room >= 5'd1) && \
                            !(S.u_x.u_mk.u_local || S.u_x.u_mk.u_done || S.u_x.u_mk.u_nogo); \
    assign ld_p_mtake[X]  = S.u_x.u_mk.att_take; \
    assign ld_p_mctx[X]   = S.u_x.u_mk.ctx_clm; \
    assign ld_p_mnodig[X] = S.u_x.u_mk.r_nodig; \
    assign ld_p_mcalled[(X)*6 +: 6] = S.u_x.u_mk.called

// ============================================================================
// CONSTANTS
// ============================================================================
// phone states
localparam int P_OFF = 0, P_IDLE = 1, P_WAITDT = 2, P_DIAL = 3, P_POST = 4, P_RINGBACK = 5,
               P_TALK = 6, P_HUP = 7, P_REST = 8, P_ALERT = 9, P_DRAINED = 10;
// outcome classes
localparam int O_NONE = 0, O_OK = 1, O_BUSY = 2, O_NOGO = 3, O_NODT = 4, O_ABANDON = 5,
               O_NOANS = 6, O_WRONG = 7, O_JOINED = 8, O_DTAGAIN = 9, O_SILENT = 10,
               O_XTALK = 11, O_NOSPEECH = 12, O_COLLIDE = 13, O_CUT = 14, NO = 15;
// why a call failed, where the bench can see it
localparam int W_NONE = 0, W_LBUSY = 1, W_LNODIG = 2, W_LSVC = 3, W_LTRUNK = 4,
               W_NNOTRUNK = 5, W_NGUARD = 6, W_NTKEY = 7, W_NTCLAIM = 8, W_NSVC = 9,
               W_NNODIG = 10, W_FREFUSE = 11, W_FBUSY = 12, W_FNODIG = 13, W_FSVC = 14,
               W_FOTHER = 15, W_WATCH = 16, W_OTHER = 17, NW = 18;
// kinds of call
localparam int K_LOCAL = 0, K_NET = 1, K_BAD = 2;
// signature code
localparam int SG_SYNC = 10, SG_Z = 2, SG_O = 5, SG_NB = 10;
localparam int SG_TONE = 32;           // a run this long is a tone, never a code
localparam int LD_TONE_FR = 128;       // frames of one level (2 ms) before the bench calls it a TONE
localparam int LD_SIG_AGE = 256;       // frames a heard id stays heard without a new word
localparam int LD_HBINS = 32768;       // delay histograms, 1 ms bins

function automatic string oname(int o);
    case (o)
    O_NONE: return "NONE";      O_OK: return "OK";           O_BUSY: return "BUSY";
    O_NOGO: return "NOGO";      O_NODT: return "NODT";       O_ABANDON: return "ABANDON";
    O_NOANS: return "NOANS";    O_WRONG: return "WRONG";     O_JOINED: return "JOINED";
    O_DTAGAIN: return "DTAGAIN"; O_SILENT: return "SILENT";  O_XTALK: return "XTALK";
    O_NOSPEECH: return "NOSPEECH"; O_COLLIDE: return "COLLIDE"; O_CUT: return "CUT";
    default: return "?";
    endcase
endfunction
function automatic string wname(int w);
    case (w)
    W_NONE: return "-";            W_LBUSY: return "L_BUSY";     W_LNODIG: return "L_NODIG";
    W_LSVC: return "L_SVC";        W_LTRUNK: return "L_TRUNK";   W_NNOTRUNK: return "N_NOTRUNK";
    W_NGUARD: return "N_GUARD";    W_NTKEY: return "N_TKEY";     W_NTCLAIM: return "N_TCLAIM";
    W_NSVC: return "N_SVC";        W_NNODIG: return "N_NODIG";   W_FREFUSE: return "F_REFUSE";
    W_FBUSY: return "F_BUSY";      W_FNODIG: return "F_NODIG";   W_FSVC: return "F_SVC";
    W_FOTHER: return "F_OTHER";    W_WATCH: return "WATCH";      W_OTHER: return "OTHER";
    default: return "?";
    endcase
endfunction
function automatic string sname(int s);
    case (s)
    P_OFF: return "OFF"; P_IDLE: return "IDLE"; P_WAITDT: return "WAITDT"; P_DIAL: return "DIAL";
    P_POST: return "POST"; P_RINGBACK: return "RINGBACK"; P_TALK: return "TALK"; P_HUP: return "HUP";
    P_REST: return "REST"; P_ALERT: return "ALERT"; P_DRAINED: return "DRAINED";
    default: return "?";
    endcase
endfunction
// A port by name: exchange letter and the port in octal, as dialled.  "-" for none.
function automatic string pn(int g);
    if (g < 0 || g >= NG) return "-";
    return $sformatf("%c%0o%0o", 8'd65 + 8'(g / 64), (g % 64) / 8, g % 8);
endfunction
function automatic string xn(int x);
    return $sformatf("%c", 8'd65 + 8'(x));
endfunction

// ============================================================================
// KNOBS
// ============================================================================
int k_seed, k_dur, k_idle, k_dt, k_pnet, k_mode, k_idg, k_idgjit, k_brk, k_mk, k_pre;
int k_abandon, k_pd, k_ans, k_noans, k_hold, k_lag, k_rest, k_ringmax, k_hup, k_grace;
int k_drain, k_nlines, k_origx, k_fromx, k_tox, k_hot, k_bade, k_badb, k_sigk;
int k_trace, k_prog, k_verify, k_wdport, k_wdreg, k_wdorg, k_wdmon, k_wdres, k_wdhunt, k_wdatt;
int k_dbgsig_from, k_dbgsig_as, k_dbgmis, k_phgrace, k_maxms, k_quit, k_pgap, k_holdfix;
int k_switch, k_idle2;
string k_pairs;

// ============================================================================
// STATE: one entry a port, index g = exchange*64 + port.  Entry NG is scratch.
// ============================================================================
// the signature each phone sends, two words (both polarities of SYNC)
reg  [127:0] sig_v   [0:NG];
int          sig_len [0:NG];
int          sig_as  [0:NG];      // the id it sends (itself, but for +dbg_sig)
int          sig_pos [0:NG];
// its decoder, fed by its exchange's frame block
bit          dec_last [0:NG];
int          dec_run  [0:NG];
bit          dec_sy   [0:NG];
int          dec_nb   [0:NG];
int          dec_w    [0:NG];
int          dec_cand [0:NG];
int          dec_cc   [0:NG];
int          dec_id   [0:NG];
int          dec_age  [0:NG];
int          dec_nw   [0:NG];      // words decoded (any id), for the self-test
// the phone
int          ph_st [0:NG-1], ph_t0 [0:NG-1], ph_dl [0:NG-1];
int          ph_nd [0:NG-1], ph_di [0:NG-1], ph_pc [0:NG-1], ph_ph [0:NG-1];
int          ph_dg [0:NG*5-1];
bit [31:0]   ph_rng [0:NG-1];
bit          ph_orig [0:NG-1], ph_line [0:NG-1];
int          ph_pdest [0:NG-1];    // a fixed destination (dest_mode 4), else -1
int          ph_rf [0:NG-1];       // the phone ringing for THIS caller (it decoded us), else -1
int          ph_partner [0:NG-1], ph_role [0:NG-1], ph_hang [0:NG-1];
int          ph_hok [0:NG-1], ph_hbad [0:NG-1], ph_hfirst [0:NG-1];
int          ph_ansat [0:NG-1], ph_alby [0:NG-1], ph_alt [0:NG-1], ph_bellt [0:NG-1];
int          ph_lastbell [0:NG-1], ph_lastsig [0:NG-1], ph_phj [0:NG-1];
int          ph_idle_wd [0:NG-1];  // ms the port has been BUSY while the phone is idle
int          ph_hupo [0:NG-1];     // the outcome a HUP will record
int          ph_pidx [0:NG-1];     // its place in the pair list, or -1
int          n_pairs = 0;
// the call this phone is making (as caller), and what happened to it
int          c_id [0:NG-1], c_dest [0:NG-1], c_kind [0:NG-1];
int          c_lift [0:NG-1], c_dt [0:NG-1], c_key [0:NG-1], c_last [0:NG-1];
int          c_alert [0:NG-1], c_bell [0:NG-1], c_ans [0:NG-1], c_end [0:NG-1], c_rel [0:NG-1];
int          c_out [0:NG-1], c_why [0:NG-1], c_heard [0:NG-1], c_cb [0:NG-1];
int          c_cv [0:NG-1], c_xv [0:NG-1], c_abt [0:NG-1], c_abph [0:NG-1], c_tone [0:NG-1];
int          c_rang [0:NG-1], c_midsig [0:NG-1], c_live [0:NG-1], c_lastend [0:NG-1];
int          rs_why [0:NG-1];      // the reason the bench saw, this attempt
int          c_jb [0:NG-1];        // another caller heard THIS one: joined to it
// per line
int          ln_att [0:NG-1], ln_ok [0:NG-1], ln_rung [0:NG-1], ln_ans [0:NG-1];
int          ln_cls [0:NG*NO-1];
// lists
int          xl_ph [0:NG-1];       // the lines of each exchange, x*64 + k
int          xl_n  [0:NX-1];
int          all_ph [0:NG-1];
int          all_n;

// ---- run-wide counters ----------------------------------------------------------
int now_ms = 0, t_start = -1, t_stop = -1, t_hup = -1, t_end = -1;
int phase = 0;                      // 0 reset, 1 links, 2 traffic, 3 grace, 4 drain, 5 done
int n_calls = 0;
int n_cls [0:NO-1];
int n_cls_x [0:NX*NO-1];            // by the caller's exchange
int n_cls_k [0:3*NO-1];             // by kind
int n_why [0:NW-1];                 // per failed call
longint talk_ms = 0;
int hist [0:3*LD_HBINS-1];          // three delay histograms: 0 dial tone, 1 post-dial alert, 2 post-dial tone
int n_dt = 0, n_pdd = 0, n_pdn = 0, mx_dt = 0, mx_pdd = 0, mx_pdn = 0;
longint s_dt = 0, s_pdd = 0, s_pdn = 0;
int n_middial = 0, n_idlehear = 0;
int n_phantom = 0, n_wrongring = 0, n_drainring = 0, n_alert_nobell = 0, n_stuck = 0, n_ringanon = 0;
int n_selftest_fail = 0;
// per exchange, sampled every ms of the traffic period
int ms_samp = 0;
int iv_start = 0, iv_ok = 0, iv_fail = 0, iv_ms = 0;
int iv_reg [0:NX-1];
int x_reg [0:NX-1], x_regmax [0:NX-1], x_regrun [0:NX-1], x_wait [0:NX-1], x_waitmax [0:NX-1], x_off [0:NX-1];
int x_org [0:NX-1], x_hunt [0:NX-1], x_mon [0:NX-1], x_monmax [0:NX-1];
int x_res [0:NX-1], x_resmax [0:NX-1];
int x_trk [0:NX*8-1], x_trkmax [0:NX*8-1];
int x_glare [0:NX-1], x_glprev [0:NX-1];
// per exchange, counted at the exchange's own clock
int ev_nt [0:NX-1], ev_gl [0:NX-1], ev_ot [0:NX-1], clash [0:NX-1];
bit uno_seen [0:NX-1], mko_seen [0:NX-1];
longint bus_ticks [0:NX-1];
int cnt_seize [0:NX-1], cnt_nomon [0:NX-1], cnt_nfb [0:NX-1], cnt_nfe [0:NX-1];
int cnt_claim [0:NX-1], cnt_unhold [0:NX-1], cnt_flood [0:NX-1], cnt_local [0:NX-1];
int cnt_done [0:NX-1], cnt_nogo [0:NX-1], cnt_take [0:NX-1], cnt_ref [0:NX-1];
// cap2: the marker's state at each refusal and take; the register's time by what holds it
int c2_refst [0:NX*16-1], c2_takest [0:NX*16-1];
int c2_regy [0:NX-1], c2_regc [0:NX-1], c2_att [0:NX-1];
int cnt_evg [0:NX-1], cnt_evn [0:NX-1], cnt_sweep [0:NX-1], cnt_refunattr [0:NX-1];
int x_why [0:NX*NW-1];              // every NOGO written, by its reason and exchange
int net_why [0:NX-1];
// watchdog runs (ms held continuously) and whether reported
int wd_reg [0:NX-1], wd_org [0:NX-1], wd_hunt [0:NX-1], wd_att [0:NX-1], wd_mk [0:NX-1];
int wd_mon [0:NX*8-1], wd_res [0:NX*8-1];

// ============================================================================
// RANDOM: a xorshift32 a phone, seeded from +seed
// ============================================================================
function automatic int unsigned rnd(int g);
    bit [31:0] s;
    s = ph_rng[g];
    s ^= s << 13; s ^= s >> 17; s ^= s << 5;
    ph_rng[g] = s;
    return s;
endfunction
function automatic int urand(int g, int n);          // 0 .. n-1
    if (n <= 1) return 0;
    return int'(rnd(g) % n);
endfunction
function automatic int erand(int g, int mean);       // exponential, mean ms
    real u;
    u = (real'(rnd(g)) + 1.0) / 4294967297.0;
    return $rtoi(-real'(mean) * $ln(u)) + 1;
endfunction
function automatic bit chance(int g, int permille);
    return urand(g, 1000) < permille;
endfunction

// ============================================================================
// THE SIGNATURE CODEC
// ============================================================================
function automatic bit id_ok(int id);
    return (id > 0) && (id < NG) && LD_PHONES[id];
endfunction

task automatic sig_build(input int g, input int as_id);
    int runs [0:10];
    int k, j, pos, lvl, w;
    bit [8:0] id9;
    bit par;
    id9 = 9'(as_id);
    par = ~(^id9);                    // odd parity over the ten
    runs[0] = SG_SYNC;
    for (k = 0; k < 9; k++) runs[k + 1] = id9[8 - k] ? SG_O : SG_Z;
    runs[10] = par ? SG_O : SG_Z;
    sig_v[g] = '0; pos = 0; lvl = 1;
    for (w = 0; w < 2; w++)
        for (k = 0; k < 11; k++) begin
            for (j = 0; j < runs[k]; j++) begin sig_v[g][pos] = lvl[0]; pos++; end
            lvl = 1 - lvl;
        end
    sig_len[g] = pos;
    sig_pos[g] = 0;
    sig_as[g]  = as_id;
endtask

task automatic dec_reset(input int g);
    dec_last[g] = 0; dec_run[g] = 0; dec_sy[g] = 0; dec_nb[g] = 0; dec_w[g] = 0;
    dec_cand[g] = -1; dec_cc[g] = 0; dec_id[g] = -1; dec_age[g] = 1 << 20; dec_nw[g] = 0;
endtask

// a run of L frames has ended
task automatic dec_run_end(input int g, input int L);
    int bitv, id;
    if (L >= SG_TONE) begin dec_sy[g] = 0; dec_cc[g] = 0; end
    else if (L >= 8)  begin dec_sy[g] = 1; dec_nb[g] = 0; dec_w[g] = 0; end
    else if (dec_sy[g]) begin
        if (L <= 3)      bitv = 0;
        else if (L <= 6) bitv = 1;
        else begin dec_sy[g] = 0; dec_cc[g] = 0; return; end
        dec_w[g] = (dec_w[g] << 1) | bitv;
        dec_nb[g] = dec_nb[g] + 1;
        if (dec_nb[g] == SG_NB) begin
            dec_sy[g] = 0;
            id = dec_w[g] >> 1;
            if (($countones(dec_w[g]) % 2 == 1) && id_ok(id)) begin
                dec_nw[g] = dec_nw[g] + 1;
                if (id == dec_cand[g]) dec_cc[g] = dec_cc[g] + 1;
                else begin dec_cand[g] = id; dec_cc[g] = 1; end
                if (dec_cc[g] >= k_sigk) begin
                    dec_id[g] = id; dec_age[g] = 0;
                end
            end else dec_cc[g] = 0;
        end
    end
endtask

// one frame's bit
task automatic dec_bit(input int g, input bit b);
    if (b == dec_last[g]) begin
        if (dec_run[g] < 1000000) dec_run[g] = dec_run[g] + 1;
    end else begin
        dec_run_end(g, dec_run[g]);
        dec_run[g] = 1; dec_last[g] = b;
    end
    if (dec_age[g] < (1 << 20)) dec_age[g] = dec_age[g] + 1;
endtask

// what phone g hears now: an id, or -1
function automatic int heard(int g);
    if (dec_id[g] >= 0 && dec_age[g] <= LD_SIG_AGE) return dec_id[g];
    return -1;
endfunction
function automatic bit tone0(int g); return !dec_last[g] && dec_run[g] >= LD_TONE_FR; endfunction
function automatic bit tone1(int g); return  dec_last[g] && dec_run[g] >= LD_TONE_FR; endfunction

// ---- the self-test: every signature decodes, at any phase, through a slip -------
task automatic sig_selftest;
    int g, i, n, ph, slip, kind, bad, good, k, fr, lim;
    bit b;
    bad = 0; good = 0;
    for (i = 0; i < all_n; i++) begin
        g = all_ph[i];
        for (kind = 0; kind < 3; kind++) begin      // 0 clean, 1 a bit lost, 2 a bit doubled
            dec_reset(NG);
            ph = urand(0, sig_len[g]);
            slip = 40 + urand(0, 200);
            // lead in with FILL for a while, then the signature
            for (fr = 0; fr < 100; fr++) dec_bit(NG, fr[0]);
            n = 0;
            for (fr = 0; fr < 600; fr++) begin
                b = sig_v[g][(ph + fr) % sig_len[g]];
                if (fr == slip && kind == 1) continue;
                dec_bit(NG, b);
                if (fr == slip && kind == 2) dec_bit(NG, b);
            end
            if (dec_id[NG] == sig_as[g] && dec_age[NG] <= LD_SIG_AGE) good++;
            else begin
                bad++;
                if (bad <= 5) $display("SELFTEST FAIL sig %s kind=%0d heard=%0d", pn(g), kind, dec_id[NG]);
            end
        end
    end
    // tones and FILL must never decode, nor turn into each other
    for (kind = 0; kind < 4; kind++) begin
        dec_reset(NG);
        for (fr = 0; fr < 4000; fr++) begin
            case (kind)
            0: b = 1'b1;                           // dial tone
            1: b = 1'b0;                           // cannot-complete
            2: b = fr[0];                          // FILL, ringback, an idle phone
            default: b = (fr % 700 < 350) ? fr[0] : fr[9];   // FILL broken by tone
            endcase
            dec_bit(NG, b);
        end
        if (dec_nw[NG] != 0 || dec_id[NG] >= 0) begin
            bad++; $display("SELFTEST FAIL tone kind=%0d decoded %0d words", kind, dec_nw[NG]);
        end else good++;
    end
    n_selftest_fail = bad;
    $display("SELFTEST sig %s  ok=%0d fail=%0d  (every phone at a random phase: clean, a bit lost, a bit doubled; tones and FILL)",
             bad == 0 ? "PASS" : "FAIL", good, bad);
endtask

// ============================================================================
// DIALLING
// ============================================================================
function automatic int pulses(int d); return (d == 0) ? 10 : d; endfunction

function automatic string digstr(int g);
    string s; int i;
    s = "";
    for (i = 0; i < ph_nd[g]; i++) s = {s, $sformatf("%0d", ph_dg[g*5 + i])};
    return s;
endfunction

function automatic int dial_ms(int g);          // how long the digits take to dial
    int i, t;
    t = k_pre;
    for (i = 0; i < ph_nd[g]; i++) t += pulses(ph_dg[g*5 + i]) * (k_brk + k_mk) + k_idg;
    return t;
endfunction

// pick a line uniformly from exchange x's lines, not g
function automatic int pick_on(int g, int x);
    int k, d, tries;
    for (tries = 0; tries < 64; tries++) begin
        d = xl_ph[x*64 + urand(g, xl_n[x])];
        if (d != g && ph_line[d]) return d;
    end
    return -1;
endfunction
// pick a line uniformly over every other exchange's lines
function automatic int pick_net(int g, int tox);
    int x, tot, r, y, tries;
    if (tox >= 0) return pick_on(g, tox);
    x = g / 64; tot = 0;
    for (y = 0; y < NX; y++) if (y != x) tot += xl_n[y];
    if (tot == 0) return -1;
    for (tries = 0; tries < 64; tries++) begin
        r = urand(g, tot);
        for (y = 0; y < NX; y++) if (y != x) begin
            if (r < xl_n[y]) begin
                if (ph_line[xl_ph[y*64 + r]]) return xl_ph[y*64 + r];
                break;
            end
            r -= xl_n[y];
        end
    end
    return -1;
endfunction

// choose where this attempt goes, and the digits for it
task automatic choose(input int g);
    int x, d, kind, y, p, i;
    x = g / 64; d = -1; kind = K_LOCAL;
    case (k_mode)
    1: begin                                         // network traffic one way only
        if (x == k_fromx && chance(g, k_pnet)) begin kind = K_NET; d = pick_net(g, k_tox); end
        else d = pick_on(g, x);
    end
    2: begin                                         // everyone dials the hot line
        if (g != k_hot) begin d = k_hot; kind = (k_hot / 64 == x) ? K_LOCAL : K_NET; end
        else if (chance(g, k_pnet)) begin kind = K_NET; d = pick_net(g, -1); end
        else d = pick_on(g, x);
    end
    3: begin                                         // network calls to a code nobody has
        if (chance(g, k_pnet)) begin kind = K_BAD; d = pick_on(g, x); end
        else d = pick_on(g, x);
    end
    4: begin                                         // the fixed pair list
        d = ph_pdest[g];
        if (d <= -1000) begin kind = K_BAD; d = x*64 + (-1000 - d); end
        else kind = (d / 64 == x) ? K_LOCAL : K_NET;
    end
    default: begin
        if (NX > 1 && chance(g, k_pnet)) begin kind = K_NET; d = pick_net(g, -1); end
        else d = pick_on(g, x);
    end
    endcase
    if (d < 0 && kind != K_BAD) begin d = pick_on(g, x); kind = K_LOCAL; end
    c_dest[g] = (kind == K_BAD) ? -2 : d;
    c_kind[g] = kind;
    // the digits: what is DIALLED
    p = d % 64;
    if (g == k_dbgmis) begin
        // debug: DIAL the next line of that exchange, but RECORD the intended
        // one, so a correct exchange must make this a WRONG
        y = d / 64;
        for (i = 0; i < xl_n[y]; i++) if (xl_ph[y*64 + i] == d) break;
        p = xl_ph[y*64 + (i + 1) % xl_n[y]];
        if (p == g) p = xl_ph[y*64 + (i + 2) % xl_n[y]];
        p = p % 64;
    end
    if (kind == K_LOCAL) begin
        ph_nd[g] = 2; ph_dg[g*5 + 0] = p / 8; ph_dg[g*5 + 1] = p % 8;
    end else begin
        y = d / 64;
        ph_nd[g] = 5; ph_dg[g*5 + 0] = 1;
        if (kind == K_BAD) begin ph_dg[g*5 + 1] = k_bade; ph_dg[g*5 + 2] = k_badb; end
        else begin
            ph_dg[g*5 + 1] = LD_CODE_E[y*3 +: 3];
            ph_dg[g*5 + 2] = LD_CODE_B[y*3 +: 3];
        end
        ph_dg[g*5 + 3] = p / 8; ph_dg[g*5 + 4] = p % 8;
    end
endtask

// ============================================================================
// A CALL RECORD
// ============================================================================
function automatic string tms(int t); return (t < 0) ? "-" : $sformatf("%0d", t); endfunction
function automatic string kname(int k);
    case (k) K_LOCAL: return "L"; K_NET: return "N"; default: return "BAD"; endcase
endfunction

task automatic call_print(input int g);
    int o, x, d;
    string dn;
    o = c_out[g];
    // fold the callee's verdict into a call that was otherwise good
    // the callee's verdict: 1 heard us, 0 heard nobody, 2 us and a stranger,
    // 3 only a stranger
    if (o == O_OK) begin
        if (c_cv[g] == 3) o = O_WRONG;
        else if (c_cv[g] == 2) o = O_XTALK;
        else if (c_cv[g] == 0 || c_xv[g] == 0) o = O_NOSPEECH;
    end
    // another caller heard this one: whatever this caller made of it, the two
    // were joined (residual glare puts both through, one may hang up first)
    if (c_jb[g] >= 0 && o != O_JOINED && o != O_WRONG && o != O_XTALK && o != O_ABANDON) begin
        o = O_JOINED; if (c_heard[g] < 0) c_heard[g] = c_jb[g];
    end
    c_out[g] = o;
    x = g / 64; d = c_dest[g];
    dn = (c_kind[g] == K_BAD) ? $sformatf("%0d%0d??", k_bade, k_badb) : pn(d);
    $display("CALL id=%0d from=%s to=%s kind=%s dial=%s lift=%s dt=%s key=%s last=%s tone=%s alert=%s bell=%s ans=%s end=%s rel=%s out=%s why=%s heard=%s rang=%s cb=%0d xv=%0d cv=%0d ab=%s mid=%s",
             c_id[g], pn(g), dn, kname(c_kind[g]),
             digstr(g), tms(c_lift[g]), tms(c_dt[g]), tms(c_key[g]), tms(c_last[g]), tms(c_tone[g]),
             tms(c_alert[g]), tms(c_bell[g]), tms(c_ans[g]), tms(c_end[g]), tms(c_rel[g]),
             oname(o), wname(c_why[g]), pn(c_heard[g]), pn(c_rang[g]), c_cb[g], c_xv[g], c_cv[g],
             (c_abph[g] > 0) ? sname(c_abph[g]) : "-", pn(c_midsig[g]));
    // the tallies
    n_cls[o]++;
    n_cls_x[x*NO + o]++;
    n_cls_k[c_kind[g]*NO + o]++;
    ln_cls[g*NO + o]++;
    if (o == O_OK) begin ln_ok[g]++; iv_ok++; end
    else if (o != O_CUT) iv_fail++;
    if (o != O_OK && c_why[g] != W_NONE) n_why[c_why[g]]++;
    if (c_dt[g] >= 0) begin
        n_dt++; s_dt += c_dt[g] - c_lift[g];
        hist[0*LD_HBINS + ((c_dt[g] - c_lift[g] < LD_HBINS) ? c_dt[g] - c_lift[g] : LD_HBINS - 1)]++;
        if (c_dt[g] - c_lift[g] > mx_dt) mx_dt = c_dt[g] - c_lift[g];
    end
    if (c_alert[g] >= 0 && c_last[g] >= 0 && c_alert[g] >= c_last[g]) begin
        n_pdd++; s_pdd += c_alert[g] - c_last[g];
        hist[1*LD_HBINS + ((c_alert[g] - c_last[g] < LD_HBINS) ? c_alert[g] - c_last[g] : LD_HBINS - 1)]++;
        if (c_alert[g] - c_last[g] > mx_pdd) mx_pdd = c_alert[g] - c_last[g];
    end
    if ((o == O_NOGO || o == O_BUSY) && c_tone[g] >= 0 && c_last[g] < 0) n_middial++;
    if ((o == O_NOGO || o == O_BUSY) && c_tone[g] >= 0 && c_last[g] >= 0) begin
        n_pdn++; s_pdn += (c_tone[g] > c_last[g]) ? c_tone[g] - c_last[g] : 0;
        hist[2*LD_HBINS + ((c_tone[g] > c_last[g]) ? ((c_tone[g] - c_last[g] < LD_HBINS) ? c_tone[g] - c_last[g] : LD_HBINS - 1) : 0)]++;
        if (c_tone[g] - c_last[g] > mx_pdn) mx_pdn = c_tone[g] - c_last[g];
    end
    if (c_ans[g] >= 0 && c_end[g] > c_ans[g]) talk_ms += c_end[g] - c_ans[g];
    c_live[g] = 0;
    c_lastend[g] = now_ms;
endtask

// ============================================================================
// THE PHONE
// ============================================================================
task automatic hook_set(input int g, input bit v);
    ld_hook[g] <= v;
endtask

task automatic go(input int g, input int st);
    ph_st[g] = st; ph_t0[g] = now_ms;
    if (k_trace) $display("TR t=%0d %s -> %s", now_ms, pn(g), sname(st));
endtask

// the attempt is over: record it, hang up (now, or after hup_ms of hearing it)
task automatic finish(input int g, input int o, input bit later);
    c_out[g] = o;
    if (later) begin ph_dl[g] = now_ms + k_hup; go(g, P_HUP); end
    else begin
        hook_set(g, 1'b0); c_rel[g] = now_ms;
        if (c_end[g] < 0) c_end[g] = now_ms;
        ph_dl[g] = now_ms + k_rest; go(g, P_REST);
    end
endtask

task automatic start_attempt(input int g);
    int span;
    n_calls++; iv_start++;
    c_id[g] = n_calls;
    choose(g);
    c_lift[g] = now_ms; c_dt[g] = -1; c_key[g] = -1; c_last[g] = -1; c_alert[g] = -1;
    c_bell[g] = -1; c_ans[g] = -1; c_end[g] = -1; c_rel[g] = -1; c_out[g] = O_NONE;
    c_why[g] = W_NONE; c_heard[g] = -1; c_cb[g] = 0; c_cv[g] = -1; c_xv[g] = -1;
    c_abt[g] = -1; c_abph[g] = 0; c_tone[g] = -1; c_rang[g] = -1; c_midsig[g] = -1; c_live[g] = 1;
    rs_why[g] = W_NONE; ph_rf[g] = -1; ph_role[g] = 0; ph_partner[g] = -1; c_jb[g] = -1;
    ph_hok[g] = 0; ph_hbad[g] = -1; ph_hfirst[g] = -1; ph_hang[g] = -1;
    ln_att[g]++;
    if (chance(g, k_abandon)) begin
        span = 5 + dial_ms(g) + 50 + k_ans;
        c_abt[g] = now_ms + 1 + urand(g, span);
    end
    hook_set(g, 1'b1);
    ph_dl[g] = now_ms + k_dt;
    go(g, P_WAITDT);
endtask

// when may this phone next lift?  An exponential idle, or with +pair_gap_ms a
// fixed schedule: the i-th pair at start + i*gap, every n_pairs*gap after
function automatic int next_start(int g);
    int t0, per, k;
    if (k_mode == 4 && k_pgap > 0 && ph_pidx[g] >= 0) begin
        t0 = t_start + ph_pidx[g] * k_pgap; per = n_pairs * k_pgap;
        if (now_ms <= t0) return t0;
        k = (now_ms - t0 + per) / per;
        return t0 + k * per;
    end
    if (k_mode == 4 && t_start == now_ms) return now_ms + urand(g, 1 + k_idle / 4);
    // +switch_ms: from that long after the start, the idle mean is +idle2_ms
    if (k_switch > 0 && now_ms - t_start >= k_switch) return now_ms + erand(g, k_idle2);
    return now_ms + erand(g, k_idle);
endfunction

// the callee answers: both ends learn when the talk ends and who goes first
task automatic answer(input int g);
    int y, hold, first, lag;
    y = ph_alby[g];
    hook_set(g, 1'b1);
    ph_role[g] = 1; ph_partner[g] = y;
    ph_hok[g] = 0; ph_hbad[g] = -1; ph_hfirst[g] = -1;
    hold = k_holdfix ? k_hold : erand(g, k_hold);
    // long enough for both to hear each other: verify_ms, then a few words
    if (hold < k_verify + 30) hold = k_verify + 30;
    lag  = urand(g, k_lag + 1);
    first = urand(g, 2);                               // 0: the caller hangs up first
    ph_hang[g] = now_ms + hold + ((first == 0) ? lag : 0);
    ln_ans[g]++;
    if (y >= 0 && y < NG && c_live[y] && ph_role[y] == 0 &&
        (ph_st[y] == P_POST || ph_st[y] == P_RINGBACK)) begin
        ph_hang[y] = now_ms + hold + ((first == 0) ? 0 : lag);
    end
    go(g, P_TALK);
endtask

// cannot-complete: BUSY when the bench saw why (the called line, here or far)
// or, with no reason seen, when the called phone was busy at the probe
function automatic int nogo_class(int g);
    if (rs_why[g] == W_LBUSY || rs_why[g] == W_FBUSY ||
        (rs_why[g] == W_NONE && (c_cb[g] & 1))) return O_BUSY;
    return O_NOGO;
endfunction

// is phone y making a call right now (a caller between lift and hang-up)?
function automatic bit calling(int y);
    return (y >= 0) && (y < NG) && c_live[y] && ph_role[y] == 0 &&
           (ph_st[y] == P_WAITDT || ph_st[y] == P_DIAL || ph_st[y] == P_POST ||
            ph_st[y] == P_RINGBACK || ph_st[y] == P_HUP);
endfunction
// has anyone dialled g lately (a call still up, or ended within the grace)?
function automatic bit wanted(int g);
    int i, y;
    for (i = 0; i < all_n; i++) begin
        y = all_ph[i];
        if (c_dest[y] == g && (c_live[y] || (now_ms - c_lastend[y] <= k_phgrace))) return 1;
    end
    return 0;
endfunction

// ---- one millisecond of one phone -------------------------------------------------
task automatic ph_step(input int g);
    int h, st, d, z;
    bit t0, t1, bell;
    h = heard(g); t0 = tone0(g); t1 = tone1(g); bell = ld_e[g];
    st = ph_st[g];
    if (h >= 0) ph_lastsig[g] = now_ms;

    // abandon, wherever the caller has got to before an answer
    if (c_live[g] && ph_role[g] == 0 && c_abt[g] >= 0 && now_ms >= c_abt[g] &&
        (st == P_WAITDT || st == P_DIAL || st == P_POST || st == P_RINGBACK)) begin
        c_abph[g] = st;
        finish(g, O_ABANDON, 0);
        return;
    end

    case (st)
    P_IDLE: begin
        if (bell || h >= 0) begin
            // being called
            if (h >= 0 && !(calling(h) && c_dest[h] == g)) begin
                // an on-hook line with a stranger's voice on it
                n_idlehear++;
                $display("IDLEHEAR t=%0d at=%s heard=%s calling=%0d dialled=%s bell=%0d", now_ms, pn(g),
                         pn(h), calling(h), pn(c_dest[h]), bell);
            end
            ph_alby[g] = h; ph_alt[g] = now_ms; ph_bellt[g] = -1; ph_lastbell[g] = -1;
            ph_ansat[g] = -1; ph_phj[g] = 0;
            if (h >= 0) ph_rf[h] = g;
            if (bell) begin ph_bellt[g] = now_ms; ph_lastbell[g] = now_ms; end
            ln_rung[g]++;
            go(g, P_ALERT);
        end else if (phase == 2 && ph_orig[g] && now_ms >= ph_dl[g]) begin
            start_attempt(g);
        end
        // the port BUSY while its phone sits idle: nothing should hold it
        if (ld_busy[g]) ph_idle_wd[g]++; else ph_idle_wd[g] = 0;
        if (ph_idle_wd[g] == k_wdport) begin
            n_stuck++;
            $display("STUCK t=%0d what=port at=%s held_ms=%0d phone=IDLE (BUSY with nobody on it)", now_ms, pn(g), k_wdport);
        end
    end

    P_WAITDT: begin
        if (t1) begin
            c_dt[g] = now_ms;
            ph_di[g] = 0; ph_ph[g] = 0; ph_dl[g] = now_ms + k_pre;
            go(g, P_DIAL);
        end else if (h >= 0) begin
            // lifted into an incoming call: answer it as its callee
            c_heard[g] = h;
            if (calling(h) && c_dest[h] == g) begin
                c_out[g] = O_COLLIDE; c_rel[g] = now_ms; c_end[g] = now_ms;
                call_print(g);
                ph_alby[g] = h; ph_rf[h] = g; ph_alt[g] = now_ms; ph_bellt[g] = -1;
                ln_rung[g]++;
                answer(g);
            end else begin
                c_heard[g] = h;
                finish(g, calling(h) ? O_JOINED : O_WRONG, 1);
            end
        end else if (now_ms >= ph_dl[g]) finish(g, O_NODT, 0);
    end

    P_DIAL: begin
        if (h >= 0 && c_midsig[g] < 0 && h != g) c_midsig[g] = h;
        // cannot-complete while still dialling (after the first digit): note
        // it, and with +quit_on_tone hang up as a subscriber would
        if (ph_di[g] >= 1 && t0 && c_tone[g] < 0) begin
            c_tone[g] = now_ms;
            if (k_quit) begin
                c_why[g] = rs_why[g];
                finish(g, nogo_class(g), 1);
                return;
            end
        end
        if (now_ms >= ph_dl[g]) begin
            case (ph_ph[g])
            0: begin                                   // a pause ends: the digit begins
                ph_pc[g] = pulses(ph_dg[g*5 + ph_di[g]]);
                hook_set(g, 1'b0); ph_ph[g] = 1; ph_dl[g] = now_ms + k_brk;
            end
            1: begin                                   // a break ends
                hook_set(g, 1'b1);
                ph_pc[g] = ph_pc[g] - 1;
                if (ph_pc[g] > 0) begin ph_ph[g] = 2; ph_dl[g] = now_ms + k_mk; end
                else begin
                    if (ph_di[g] == 0) c_key[g] = now_ms;
                    ph_di[g] = ph_di[g] + 1;
                    if (ph_di[g] >= ph_nd[g]) begin
                        c_last[g] = now_ms;
                        ph_dl[g] = now_ms + k_pd;
                        go(g, P_POST);
                    end else begin
                        ph_ph[g] = 0;
                        ph_dl[g] = now_ms + k_idg + ((k_idgjit > 0) ? urand(g, k_idgjit + 1) : 0);
                    end
                end
            end
            default: begin                             // a make ends
                hook_set(g, 1'b0); ph_ph[g] = 1; ph_dl[g] = now_ms + k_brk;
            end
            endcase
        end
    end

    P_POST, P_RINGBACK: begin
        d = c_dest[g];
        // was the dialled line busy when the marker looked at it?  It looks ID
        // after the last break, plus a read and a probe: sample until then.
        // 1: its phone off hook, in a call, ringing or just hung up;
        // 2: its port BUSY with the phone idle (a port nothing should hold)
        if (d >= 0 && now_ms <= c_last[g] + LD_ID) begin
            if (ld_hook[d] || ph_st[d] != P_IDLE) c_cb[g] |= 1;
            else if (ld_busy[d]) c_cb[g] |= 2;
        end
        if (d >= 0 && ph_st[d] == P_TALK && ph_role[d] == 1 &&
            (ph_partner[d] == g || (ph_partner[d] < 0 && ph_alt[d] >= c_last[g]))) begin
            // answered (by a callee that heard us, or could not tell who we were)
            if (ph_partner[d] < 0) ph_partner[d] = g;
            c_ans[g] = ph_t0[d]; ph_role[g] = 0; ph_partner[g] = d;
            ph_hok[g] = 0; ph_hbad[g] = -1; ph_hfirst[g] = -1;
            if (c_alert[g] < 0) c_alert[g] = ph_alt[d];
            if (c_bell[g] < 0) c_bell[g] = ph_bellt[d];
            if (ph_hang[g] < 0) ph_hang[g] = now_ms + k_hold;
            go(g, P_TALK);
        end else if (h >= 0 && h != d) begin
            // somebody else: another caller (residual glare) or a wrong party.
            // Our own voice back is a WRONG too (heard= names us)
            c_heard[g] = h;
            if (calling(h) && h != g) begin
                if (c_jb[h] < 0) c_jb[h] = g;
                finish(g, O_JOINED, 1);
            end else finish(g, O_WRONG, 1);
        end else if (h >= 0 && h == d && ld_hook[d] && ph_st[d] != P_WAITDT &&
                     !(ph_st[d] == P_TALK && ph_partner[d] == g)) begin
            // the line dialled, heard -- but it is talking to, or dialling,
            // somebody else: put through onto a busy line
            c_heard[g] = h;
            finish(g, O_XTALK, 1);
        end else if (ph_rf[g] >= 0 && ph_rf[g] != d) begin
            c_rang[g] = ph_rf[g];
            finish(g, O_WRONG, 1);
        end else if (t0) begin
            if (c_tone[g] < 0) c_tone[g] = now_ms;
            c_why[g] = rs_why[g];
            finish(g, nogo_class(g), 1);
        end else if (t1) finish(g, O_DTAGAIN, 1);
        else if (st == P_POST) begin
            if (ph_rf[g] == d && d >= 0) begin
                c_alert[g] = ph_alt[d]; c_rang[g] = d;
                ph_dl[g] = now_ms + k_ringmax;
                go(g, P_RINGBACK);
            end else if (now_ms >= ph_dl[g]) finish(g, O_SILENT, 0);
        end else begin
            if (c_bell[g] < 0 && ph_st[d] == P_ALERT && ph_bellt[d] >= 0) c_bell[g] = ph_bellt[d];
            if (now_ms >= ph_dl[g]) finish(g, O_NOANS, 0);
        end
    end

    P_TALK: begin
        z = ph_partner[g];
        // listen while both are on the line: from verify_ms after the answer
        // until the first of the two hangs up
        if (now_ms >= ph_t0[g] + k_verify &&
            (z < 0 || (ph_st[z] == P_TALK && (ph_hang[z] < 0 || now_ms < ph_hang[z])))) begin
            if (h >= 0 && h == z) begin
                ph_hok[g]++;
                if (ph_hfirst[g] < 0) ph_hfirst[g] = now_ms;
            end else if (h >= 0 && ph_hbad[g] < 0) ph_hbad[g] = h;
        end
        // the partner is gone (gave up, or hung up first): follow within the lag
        if (z >= 0 && ph_st[z] != P_TALK && ph_hang[g] > now_ms + k_lag)
            ph_hang[g] = now_ms + urand(g, k_lag + 1);
        if (now_ms >= ph_hang[g]) begin
            hook_set(g, 1'b0);
            if (ph_role[g] == 1) begin
                // the callee's verdict goes into its caller's record
                if (z >= 0 && c_live[z]) begin
                    c_cv[z] = (ph_hbad[g] >= 0) ? ((ph_hok[g] > 0) ? 2 : 3) : (ph_hok[g] > 0) ? 1 : 0;
                    if (c_end[z] < 0) c_end[z] = now_ms;
                end
                ph_dl[g] = now_ms + k_rest; go(g, P_REST);
            end else begin
                c_xv[g] = (ph_hok[g] > 0) ? 1 : 0;
                if (ph_hbad[g] >= 0) begin
                    c_heard[g] = ph_hbad[g];
                    c_out[g] = (ph_hok[g] > 0) ? O_XTALK : O_WRONG;
                end else c_out[g] = O_OK;
                if (c_end[g] < 0) c_end[g] = now_ms;
                c_rel[g] = now_ms;
                ph_dl[g] = now_ms + k_rest; go(g, P_REST);
            end
        end
    end

    P_HUP: if (now_ms >= ph_dl[g]) begin
        hook_set(g, 1'b0); c_rel[g] = now_ms;
        if (c_end[g] < 0) c_end[g] = now_ms;
        ph_dl[g] = now_ms + k_rest; go(g, P_REST);
    end

    P_REST: if (h >= 0 && calling(h) && c_dest[h] == g && !(c_live[g] && ph_role[g] == 0)) begin
        // a new call put through while this phone rests after its last one
        ph_alby[g] = h; ph_alt[g] = now_ms; ph_bellt[g] = -1; ph_lastbell[g] = -1;
        ph_ansat[g] = -1; ph_phj[g] = 0; ph_rf[h] = g; ph_role[g] = 0;
        ln_rung[g]++;
        go(g, P_ALERT);
    end else if (now_ms >= ph_dl[g]) begin
        if (c_live[g] && ph_role[g] == 0) call_print(g);
        ph_role[g] = 0;
        ph_dl[g] = next_start(g);
        ph_idle_wd[g] = 0;
        go(g, P_IDLE);
    end

    P_ALERT: begin
        if (bell) begin
            if (ph_bellt[g] < 0) ph_bellt[g] = now_ms;
            ph_lastbell[g] = now_ms;
        end
        if (h >= 0 && ph_alby[g] < 0) begin ph_alby[g] = h; ph_rf[h] = g; end
        // who rang?  judged once, 8 ms after the first bell
        if (ph_bellt[g] >= 0 && !ph_phj[g] && now_ms >= ph_bellt[g] + 8) begin
            ph_phj[g] = 1;
            if (ph_alby[g] >= 0 && !(c_dest[ph_alby[g]] == g && calling(ph_alby[g]))) begin
                // a bell, and the voice on it is somebody who did not dial us
                n_wrongring++;
                $display("WRONGRING t=%0d at=%s caller=%s dialled=%s calling=%0d", now_ms, pn(g),
                         pn(ph_alby[g]), pn(c_dest[ph_alby[g]]), calling(ph_alby[g]));
            end else if (ph_alby[g] < 0 && wanted(g)) begin
                n_ringanon++;
                if (k_trace) $display("TR t=%0d %s rings, dialled, caller not heard", now_ms, pn(g));
            end else if (ph_alby[g] < 0) begin
                if (phase >= 4) begin
                    if (now_ms - t_hup > k_phgrace) begin
                        n_drainring++;
                        $display("DRAINRING t=%0d at=%s (a bell %0d ms after everyone hung up)", now_ms, pn(g), now_ms - t_hup);
                    end
                end else begin
                    n_phantom++;
                    $display("PHANTOM t=%0d at=%s (a bell, no caller heard, nobody dialled it)", now_ms, pn(g));
                end
            end
            // shall we answer?
            if (phase <= 3 && !chance(g, k_noans)) ph_ansat[g] = ph_bellt[g] + urand(g, k_ans + 1);
        end
        if (ph_ansat[g] >= 0 && now_ms >= ph_ansat[g] && phase <= 3) answer(g);
        else begin
            // the call went away: no bell for a whole cadence and nobody heard
            if ((ph_lastbell[g] < 0 ? now_ms - ph_alt[g] : now_ms - ph_lastbell[g]) >
                    LD_RING_ON + LD_RING_OFF + 32 &&
                now_ms - ph_lastsig[g] > 40) begin
                if (ph_bellt[g] < 0) n_alert_nobell++;
                ph_dl[g] = now_ms + k_rest; go(g, P_REST);
            end
        end
    end

    default: ;
    endcase
endtask

// ============================================================================
// SETUP: knobs, phones, signatures
// ============================================================================
function automatic int parse_port(string s, int i);    // "A24" at i -> g, or -1
    int x, h, p;
    if (i + 3 > s.len()) return -1;
    x = s.getc(i) - 8'd65;
    h = s.getc(i + 1) - 8'd48;
    p = s.getc(i + 2) - 8'd48;
    if (x < 0 || x >= NX || h < 0 || h > 7 || p < 0 || p > 7) return -1;
    return x*64 + h*8 + p;
endfunction

task automatic knob(input string name, inout int v, input int dflt);
    if (!$value$plusargs({name, "=%d"}, v)) v = dflt;
    $display("KNOB %s=%0d", name, v);
endtask

task automatic setup;
    int g, x, p, k, i, a, b;
    string s;
    knob("seed", k_seed, 1);
    knob("dur_ms", k_dur, LD_D_DUR);
    knob("idle_ms", k_idle, LD_D_IDLE);
    knob("dt_ms", k_dt, LD_D_DT);
    knob("pnet", k_pnet, 500);
    knob("dest_mode", k_mode, 0);
    knob("brk_ms", k_brk, LD_D_BRK);
    knob("mk_ms", k_mk, LD_D_MK);
    knob("idg_ms", k_idg, LD_D_IDG);
    knob("idg_jit_ms", k_idgjit, 0);
    knob("pre_ms", k_pre, LD_D_PRE);
    knob("abandon", k_abandon, 0);
    knob("pd_ms", k_pd, LD_D_PD);
    knob("ans_ms", k_ans, LD_D_ANS);
    knob("noans", k_noans, 0);
    knob("hold_ms", k_hold, LD_D_HOLD);
    knob("lag_ms", k_lag, LD_D_LAG);
    knob("rest_ms", k_rest, LD_D_REST);
    knob("ringmax_ms", k_ringmax, LD_D_RINGMAX);
    knob("hup_ms", k_hup, LD_D_HUP);
    knob("grace_ms", k_grace, 0);
    knob("drain_ms", k_drain, LD_D_DRAIN);
    knob("nlines", k_nlines, 64);
    knob("orig_x", k_origx, 255);
    knob("from_x", k_fromx, 0);
    knob("to_x", k_tox, 1);
    knob("bad_e", k_bade, 2);
    knob("bad_b", k_badb, 7);
    knob("sig_k", k_sigk, 3);
    knob("verify_ms", k_verify, 20);
    knob("trace", k_trace, 0);
    knob("prog_ms", k_prog, 2000 * (9 - LD_SCALE));
    knob("wd_port_ms", k_wdport, 8 * LD_T_REL + LD_RING_ON + LD_RING_OFF);
    knob("wd_reg_ms", k_wdreg, 6 * LD_NODIG);
    knob("wd_org_ms", k_wdorg, LD_T_KEY + LD_T_CLAIM + 3 * LD_NODIG);
    knob("wd_mon_ms", k_wdmon, 2 * LD_T_KEY + 4 * LD_CLR);
    knob("wd_res_ms", k_wdres, 2 * (LD_T_KEY + LD_T_CLAIM) + 4 * LD_T_REL);
    knob("wd_hunt_ms", k_wdhunt, 200);
    knob("wd_att_ms", k_wdatt, LD_NODIG + 100);
    knob("phantom_grace_ms", k_phgrace, 6 * LD_T_REL + LD_RING_ON + LD_RING_OFF);
    knob("max_ms", k_maxms, 0);
    knob("quit_on_tone", k_quit, 1);
    knob("pair_gap_ms", k_pgap, 0);
    knob("hold_fixed", k_holdfix, 0);
    knob("switch_ms", k_switch, 0);
    knob("idle2_ms", k_idle2, LD_D_IDLE);
    if (!$value$plusargs("pairs=%s", k_pairs)) k_pairs = "";
    $display("KNOB pairs=%s", k_pairs);
    if (!$value$plusargs("hot=%s", s)) s = "";
    k_hot = (s.len() >= 3) ? parse_port(s, 0) : -1;
    $display("KNOB hot=%s", pn(k_hot));
    if (!$value$plusargs("dbg_misdial=%s", s)) s = "";
    k_dbgmis = (s.len() >= 3) ? parse_port(s, 0) : -1;
    $display("KNOB dbg_misdial=%s", pn(k_dbgmis));
    k_dbgsig_from = -1; k_dbgsig_as = -1;
    if ($value$plusargs("dbg_sig=%s", s) && s.len() >= 7) begin
        k_dbgsig_from = parse_port(s, 0); k_dbgsig_as = parse_port(s, 4);
    end
    $display("KNOB dbg_sig=%s:%s", pn(k_dbgsig_from), pn(k_dbgsig_as));
    $display("KNOB scale=%0d NX=%0d NMON=%0d NRES=%0d T_ARM=%0d T_REL=%0d RING=%0d/%0d HIT=%0d ID=%0d CLR=%0d NODIG=%0d T_GUARD0=%0d T_KEY=%0d T_CLAIM=%0d",
             LD_SCALE, NX, LD_NMON, LD_NRES, LD_T_ARM, LD_T_REL, LD_RING_ON, LD_RING_OFF,
             LD_HIT, LD_ID, LD_CLR, LD_NODIG, LD_T_GUARD0, LD_T_KEY, LD_T_CLAIM);

    // the lines, the phones and their dice
    all_n = 0;
    for (x = 0; x < NX; x++) begin
        xl_n[x] = 0;
        $display("TOPO ex=%s code=%0d%0d lines=%0d", xn(x), LD_CODE_E[x*3 +: 3], LD_CODE_B[x*3 +: 3],
                 $countones(LD_PHONES[x*64 +: 64]));
    end
    for (g = 0; g < NG; g++) begin
        x = g / 64;
        ph_st[g] = P_OFF; ph_line[g] = 0; ph_orig[g] = 0; ph_pdest[g] = -1; ph_pidx[g] = -1;
        ph_rng[g] = 32'h9E3779B9 ^ (32'(k_seed) * 32'h85EBCA6B) ^ (32'(g + 1) * 32'hC2B2AE35);
        if (ph_rng[g] == 0) ph_rng[g] = 1;
        for (k = 0; k < 8; k++) void'(rnd(g));
        c_live[g] = 0; c_dest[g] = -1; c_lastend[g] = -1000000; ph_rf[g] = -1; ph_role[g] = 0; c_jb[g] = -1;
        ph_partner[g] = -1; ph_hang[g] = -1; ph_lastsig[g] = -1000000; ph_idle_wd[g] = 0;
        ln_att[g] = 0; ln_ok[g] = 0; ln_rung[g] = 0; ln_ans[g] = 0;
        for (k = 0; k < NO; k++) ln_cls[g*NO + k] = 0;
        dec_reset(g);
        if (LD_PHONES[g] && xl_n[x] < k_nlines) begin
            ph_line[g] = 1;
            ph_orig[g] = k_origx[x] && (k_mode != 4);
            xl_ph[x*64 + xl_n[x]] = g; xl_n[x]++;
            all_ph[all_n] = g; all_n++;
            ph_st[g] = P_IDLE;
        end
        sig_build(g, g);
    end
    dec_reset(NG);
    if (k_dbgsig_from >= 0 && k_dbgsig_as >= 0) sig_build(k_dbgsig_from, k_dbgsig_as);
    // the pair list: "A24B31,A25A26" -- each caller dials only its partner
    i = 0;
    while (i + 6 <= k_pairs.len()) begin
        a = parse_port(k_pairs, i); b = parse_port(k_pairs, i + 3);
        if (a >= 0 && k_pairs.getc(i + 3) == "Z") begin
            // Z: a code nobody has (+bad_e +bad_b), then the digits given
            b = (k_pairs.getc(i + 4) - 8'd48) * 8 + (k_pairs.getc(i + 5) - 8'd48);
            ph_pdest[a] = -1000 - b; ph_orig[a] = 1; ph_pidx[a] = n_pairs; n_pairs++;
            $display("TOPO pair %s -> code %0d%0d, then %0o", pn(a), k_bade, k_badb, b);
        end else if (a >= 0 && b >= 0 && ph_line[a] && ph_line[b]) begin
            ph_pdest[a] = b; ph_orig[a] = 1; ph_pidx[a] = n_pairs; n_pairs++;
            $display("TOPO pair %s -> %s", pn(a), pn(b));
        end else $display("TOPO pair at %0d not understood", i);
        i += 7;
    end
    for (x = 0; x < NO; x++) n_cls[x] = 0;
    for (x = 0; x < NX*NO; x++) n_cls_x[x] = 0;
    for (x = 0; x < 3*NO; x++) n_cls_k[x] = 0;
    for (x = 0; x < NW; x++) n_why[x] = 0;
    for (x = 0; x < NX*NW; x++) x_why[x] = 0;
    for (x = 0; x < 3*LD_HBINS; x++) hist[x] = 0;
    for (x = 0; x < NX; x++) begin
        x_reg[x] = 0; x_regmax[x] = 0; x_regrun[x] = 0; x_org[x] = 0; x_hunt[x] = 0;
        x_wait[x] = 0; x_waitmax[x] = 0; x_off[x] = 0; iv_reg[x] = 0;
        x_mon[x] = 0; x_monmax[x] = 0; x_res[x] = 0; x_resmax[x] = 0; x_glare[x] = 0; x_glprev[x] = 0;
        ev_nt[x] = 0; ev_gl[x] = 0; ev_ot[x] = 0; clash[x] = 0; uno_seen[x] = 0; mko_seen[x] = 0;
        bus_ticks[x] = 0; cnt_seize[x] = 0; cnt_nomon[x] = 0; cnt_nfb[x] = 0; cnt_nfe[x] = 0;
        cnt_claim[x] = 0; cnt_unhold[x] = 0; cnt_flood[x] = 0; cnt_local[x] = 0; cnt_done[x] = 0;
        cnt_nogo[x] = 0; cnt_take[x] = 0; cnt_ref[x] = 0; cnt_evg[x] = 0; cnt_evn[x] = 0;
        cnt_sweep[x] = 0; cnt_refunattr[x] = 0; net_why[x] = W_NONE;
        wd_reg[x] = 0; wd_org[x] = 0; wd_hunt[x] = 0; wd_att[x] = 0; wd_mk[x] = 0;
        for (k = 0; k < 8; k++) begin
            x_trk[x*8 + k] = 0; x_trkmax[x*8 + k] = 0; wd_mon[x*8 + k] = 0; wd_res[x*8 + k] = 0;
        end
    end
    sig_selftest;
endtask

// ============================================================================
// PER EXCHANGE, AT ITS OWN CLOCK: the phones' speech, the ears, cable B, the whys
// ============================================================================
genvar ldx;
generate for (ldx = 0; ldx < NX; ldx = ldx + 1) begin : ld_xf
    reg [63:0] txr = '0;
    bit        idl = 1'b0;
    assign ld_tx[ldx*64 +: 64] = txr;

    // ---- a frame: every phone says one bit and hears one ---------------------
    always @(posedge ld_clk[ldx]) if (ld_fs[ldx]) begin : fr
        int q, gg;
        idl <= ~idl;
        for (q = 0; q < 64; q++) begin
            gg = ldx*64 + q;
            if (LD_PHONES[gg]) begin
                if (ld_hook[gg]) begin
                    txr[q] <= sig_v[gg][sig_pos[gg]];
                    sig_pos[gg] = (sig_pos[gg] + 1 >= sig_len[gg]) ? 0 : sig_pos[gg] + 1;
                end else txr[q] <= idl;
                dec_bit(gg, ld_rx[gg]);
            end
        end
    end

    // ---- cable B, as a counter card hears it; the watch lines ------------------
    reg [15:0] bsh = '0;
    reg        bsc_d = 1'b0, bwr_d = 1'b0, hunt_d = 1'b0;
    // what the marker decided on the last edge, and in which state
    int  pm_state = 0;
    bit  pm_ref = 0, pm_ctx = 0, pm_nodig = 0;
    int  pm_called = 0;
    // the origin's state on the last edge
    int  pn_nst = 0;
    bit  pn_guard = 0, pn_brk = 0, pn_f1 = 0, pn_f2 = 0;
    int  pn_ndig = 0;
    always @(posedge ld_clk[ldx]) begin : cb
        int code, k, dst, why, gd, y, cand, ncand, w, i;
        bsc_d <= ld_sc[ldx]; bwr_d <= ld_wr[ldx];
        if (ld_sc[ldx] && !bsc_d) bsh <= {bsh[14:0], ld_sd[ldx]};
        if (ld_wr[ldx] && !bwr_d && !bsh[15]) begin
            code = bsh[7:2];
            if      (code == 6'o10) ev_nt[ldx]++;
            else if (code == 6'o04) ev_gl[ldx]++;
            else                    ev_ot[ldx]++;
        end
        if (ld_cl[ldx])  clash[ldx]++;
        if (ld_uno[ldx]) uno_seen[ldx] = 1;
        if (ld_mko[ldx]) mko_seen[ldx] = 1;
        if (phase == 2 && (ld_p_uoe[ldx] || ld_p_moe[ldx])) bus_ticks[ldx]++;
        // the unit's events
        if (ld_p_seize[ldx])   cnt_seize[ldx]++;
        if (ld_p_nomon[ldx])   cnt_nomon[ldx]++;
        if (ld_p_unhold[ldx])  cnt_unhold[ldx]++;
        if (ld_p_nfbusy[ldx])  cnt_nfb[ldx]++;
        if (ld_p_nfempty[ldx]) cnt_nfe[ldx]++;
        if (ld_p_claimw[ldx])  cnt_claim[ldx]++;
        if (ld_p_flood[ldx])   cnt_flood[ldx]++;
        if (ld_p_local[ldx])   cnt_local[ldx]++;
        if (ld_p_done[ldx])    cnt_done[ldx]++;
        if (ld_p_nogo[ldx])    cnt_nogo[ldx]++;
        if (ld_p_mtake[ldx])   cnt_take[ldx]++;
        if (ld_p_evg[ldx])     cnt_evg[ldx]++;
        if (ld_p_evn[ldx])     cnt_evn[ldx]++;
        if (ld_hunt[ldx] && !hunt_d) cnt_sweep[ldx]++;
        hunt_d <= ld_hunt[ldx];

        // ---- why the origin gave up: its state before it went to DROP or END ----
        k = ld_p_nst[ldx*4 +: 4];
        if ((k == 7 || k == 8) && k != pn_nst && ld_p_oafter[ldx*2 +: 2] == 2'd1 &&
            (pn_nst == 2 || pn_nst == 4 || pn_nst == 5)) begin
            if (pn_nst == 2)                         why = W_NNOTRUNK;
            else if (pn_guard && pn_brk)             why = W_NGUARD;
            else if (pn_nst == 5)                    why = W_NTCLAIM;
            else if ((!pn_f1 && pn_ndig >= 1) || (pn_f1 && !pn_f2 && pn_ndig >= 2)) why = W_NSVC;
            else                                     why = W_NTKEY;
            net_why[ldx] = why;
        end
        pn_nst = k; pn_guard = ld_p_guard[ldx]; pn_brk = ld_p_rbrk[ldx];
        pn_f1 = ld_p_f1[ldx]; pn_f2 = ld_p_f2[ldx]; pn_ndig = ld_p_rndig[ldx*3 +: 3];

        // ---- every cannot-complete the marker writes, and why --------------------
        for (w = 0; w < 2; w++)
            if (ld_p_mpv[ldx*2 + w] && ld_p_mpd[ldx*30 + w*15 + 14] &&
                ld_p_mpd[ldx*30 + w*15 + 6 +: 6] == 6'o03) begin
                dst = ld_p_mpd[ldx*30 + w*15 +: 6];
                if (pm_ref) why = W_FREFUSE;
                else case (pm_state)
                    2: why = pm_ctx ? W_FBUSY : W_LBUSY;                 // PROBE: M or BUSY
                    1: why = pm_nodig ? (pm_ctx ? W_FNODIG : W_LNODIG)   // COLLECT
                                      : (pm_ctx ? W_FSVC : W_LSVC);
                    4: why = pm_ctx ? W_FOTHER : W_LTRUNK;               // READ: a trunk dialled
                    6: why = pm_nodig ? W_NNODIG : net_why[ldx];         // YIELD: the unit's
                    7: why = W_WATCH;
                    default: why = W_OTHER;
                endcase
                x_why[ldx*NW + why]++;
                gd = ldx*64 + dst;
                if (LD_PHONES[gd] && c_live[gd] && rs_why[gd] == W_NONE) rs_why[gd] = why;
                else if (!LD_PHONES[gd]) begin
                    // a trunk: the far end's refusal.  Whose call?  The one dialling
                    // the called line here, or, for a refused claim, the one caller
                    // dialling this exchange just now
                    cand = -1; ncand = 0;
                    for (i = 0; i < all_n; i++) begin
                        y = all_ph[i];
                        if (c_live[y] && ph_role[y] == 0 && c_kind[y] == K_NET &&
                            (ph_st[y] == P_DIAL || ph_st[y] == P_POST) && c_dest[y] / 64 == ldx &&
                            (why == W_FREFUSE || why == W_FNODIG || c_dest[y] == ldx*64 + pm_called)) begin
                            cand = y; ncand++;
                        end
                    end
                    if (ncand == 1 && rs_why[cand] == W_NONE) rs_why[cand] = why;
                    else if (why == W_FREFUSE) cnt_refunattr[ldx]++;
                end
            end
        if (ld_p_mref[ldx] && !ld_p_mtake[ldx]) begin
            cnt_ref[ldx]++;
            c2_refst[ldx*16 + ld_mks[ldx*3 +: 3]*2 + ld_p_mctx[ldx]]++;
            $display("C2REF t=%0d ex=%s st=%0d ctx=%0d", now_ms, xn(ldx), ld_mks[ldx*3 +: 3], ld_p_mctx[ldx]);
        end
        if (ld_p_mtake[ldx]) begin
            c2_takest[ldx*16 + ld_mks[ldx*3 +: 3]*2 + ld_p_mctx[ldx]]++;
            $display("C2TAKE t=%0d ex=%s st=%0d ctx=%0d", now_ms, xn(ldx), ld_mks[ldx*3 +: 3], ld_p_mctx[ldx]);
        end
        pm_state = ld_mks[ldx*3 +: 3]; pm_ref = ld_p_mref[ldx] && !ld_p_mtake[ldx];
        pm_ctx = ld_p_mctx[ldx]; pm_nodig = ld_p_mnodig[ldx];
        pm_called = ld_p_mcalled[ldx*6 +: 6];
    end
end endgenerate

// ============================================================================
// THE 1 kHz BLOCK: every phone, the stats, the watchdog, the drain
// ============================================================================
task automatic sample_ms;
    int x, k, n, b, m;
    iv_ms++;
    for (x = 0; x < NX; x++) if (ld_reg[x]) iv_reg[x]++;
    for (x = 0; x < NX; x++) begin
        // n_glare is eight bits: count its steps
        k = ld_gl[x*8 +: 8];
        x_glare[x] += (k - x_glprev[x] + 256) % 256; x_glprev[x] = k;
        if (phase != 2) continue;
        if (ld_reg[x]) begin x_reg[x]++; x_regrun[x]++; if (x_regrun[x] > x_regmax[x]) x_regmax[x] = x_regrun[x]; end
        else x_regrun[x] = 0;
        if (ld_reg[x] && ld_mks[x*3 +: 3] == 3'd6) c2_regy[x]++;
        else if (ld_reg[x] && ld_p_mctx[x]) c2_regc[x]++;
        if (ld_p_att[x]) c2_att[x]++;
        if (ld_dirs[x*4 +: 4] != 0) x_org[x]++;
        if (ld_hunt[x]) x_hunt[x]++;
        n = $countones(ld_mon[x*LD_NMON +: LD_NMON]); x_mon[x] += n; if (n > x_monmax[x]) x_monmax[x] = n;
        n = $countones(ld_res[x*LD_NRES +: LD_NRES]); x_res[x] += n; if (n > x_resmax[x]) x_resmax[x] = n;
        for (b = 0; b < 8; b++) begin
            n = $countones(ld_busy[x*64 + b*8 +: 8] & LD_TRUNKS[x*64 + b*8 +: 8]);
            x_trk[x*8 + b] += n; if (n > x_trkmax[x*8 + b]) x_trkmax[x*8 + b] = n;
        end
    end
    if (phase == 2) begin
        ms_samp++;
        for (x = 0; x < NX; x++) begin
            n = 0; m = 0;
            for (k = 0; k < xl_n[x]; k++) begin
                if (ph_st[xl_ph[x*64 + k]] == P_WAITDT) n++;
                if (ld_hook[xl_ph[x*64 + k]]) m++;
            end
            x_wait[x] += n; if (n > x_waitmax[x]) x_waitmax[x] = n;
            x_off[x] += m;
        end
    end
endtask

task automatic wd_run(inout int run, input bit held, input int lim, input string what, input int x, input int idx);
    if (held) begin
        run++;
        if (run == lim) begin
            n_stuck++;
            $display("STUCK t=%0d what=%s ex=%s idx=%0d held_ms=%0d", now_ms, what, xn(x), idx, lim);
        end
    end else begin
        if (run >= lim) $display("STUCK-END t=%0d what=%s ex=%s idx=%0d held_ms=%0d", now_ms, what, xn(x), idx, run);
        run = 0;
    end
endtask

task automatic watchdog;
    int x, k;
    for (x = 0; x < NX; x++) begin
        wd_run(wd_reg[x],  ld_reg[x], k_wdreg, "register", x, 0);
        wd_run(wd_mk[x],   ld_mks[x*3 +: 3] != 0, k_wdreg, "marker_state", x, 0);
        wd_run(wd_org[x],  ld_dirs[x*4 +: 4] != 0, k_wdorg, "origin", x, 0);
        wd_run(wd_hunt[x], ld_hunt[x], k_wdhunt, "hunting", x, 0);
        wd_run(wd_att[x],  ld_p_att[x], k_wdatt, "att", x, 0);
        for (k = 0; k < LD_NMON; k++) wd_run(wd_mon[x*8 + k], ld_mon[x*LD_NMON + k], k_wdmon, "monitor", x, k);
        for (k = 0; k < LD_NRES; k++) wd_run(wd_res[x*8 + k], ld_res[x*LD_NRES + k], k_wdres, "resolver", x, k);
    end
endtask

// a histogram's percentile
function automatic int pctl(int which, int n, int pc);
    int i, acc, lim;
    if (n == 0) return -1;
    lim = (n * pc + 99) / 100; acc = 0;
    for (i = 0; i < LD_HBINS; i++) begin acc += hist[which*LD_HBINS + i]; if (acc >= lim) return i; end
    return LD_HBINS - 1;
endfunction

task automatic force_hangup;
    int i, g;
    for (i = 0; i < all_n; i++) begin
        g = all_ph[i];
        if (c_live[g] && ph_role[g] == 0) begin
            case (ph_st[g])
            P_TALK: begin
                c_xv[g] = (ph_hok[g] > 0) ? 1 : 0;
                c_out[g] = (ph_hbad[g] >= 0) ? ((ph_hok[g] > 0) ? O_XTALK : O_WRONG) : O_OK;
                if (ph_hbad[g] >= 0) c_heard[g] = ph_hbad[g];
            end
            P_HUP, P_REST: ;                             // decided already
            default: begin c_out[g] = O_CUT; c_abph[g] = ph_st[g]; end
            endcase
            if (c_end[g] < 0) c_end[g] = now_ms;
            if (c_rel[g] < 0) c_rel[g] = now_ms;
            call_print(g);
        end
        ld_hook[g] <= 1'b0;
        ph_st[g] = P_DRAINED; ph_t0[g] = now_ms;
    end
endtask

// ---- the end: invariants and summary ------------------------------------------------
int inv_pass = 0, inv_fail = 0;
task automatic inv(input bit ok, input string what);
    if (ok) inv_pass++; else inv_fail++;
    $display("INVARIANT %s %s", ok ? "PASS" : "FAIL", what);
endtask

task automatic check_invariants;
    int x, p, g, nb;
    string s;
    for (x = 0; x < NX; x++) begin
        s = ""; nb = 0;
        for (p = 0; p < 64; p++) begin
            g = x*64 + p;
            if (ld_busy[g]) begin
                nb++; s = {s, " ", pn(g)};
                if (p == 1 || p == 3) s = {s, "(tone)"};
            end
        end
        inv(nb == 0, $sformatf("ports_idle ex=%s busy=%0d%s", xn(x), nb, s));
        inv(!ld_reg[x], $sformatf("register_free ex=%s", xn(x)));
        inv(ld_mks[x*3 +: 3] == 0, $sformatf("marker_idle ex=%s state=%0d", xn(x), ld_mks[x*3 +: 3]));
        inv(ld_dirs[x*4 +: 4] == 0, $sformatf("origin_free ex=%s dirs_held=%b", xn(x), ld_dirs[x*4 +: 4]));
        inv(ld_mon[x*LD_NMON +: LD_NMON] == 0, $sformatf("monitors_free ex=%s mon_held=%b", xn(x), ld_mon[x*LD_NMON +: LD_NMON]));
        inv(ld_res[x*LD_NRES +: LD_NRES] == 0, $sformatf("resolvers_free ex=%s res_busy=%b", xn(x), ld_res[x*LD_NRES +: LD_NRES]));
        inv(!ld_hunt[x], $sformatf("sweep_idle ex=%s", xn(x)));
        inv(ld_p_nst[x*4 +: 4] == 0 && ld_p_cst[x*3 +: 3] == 0 && ld_p_fst[x*2 +: 2] == 0 &&
            ld_p_clst[x*2 +: 2] == 0 && !ld_p_att[x],
            $sformatf("unit_idle ex=%s origin=%0d classifier=%0d forwarder=%0d claim=%0d att=%0d",
                      xn(x), ld_p_nst[x*4 +: 4], ld_p_cst[x*3 +: 3], ld_p_fst[x*2 +: 2],
                      ld_p_clst[x*2 +: 2], ld_p_att[x]));
        inv(ld_p_uqe[x] && ld_p_mqe[x], $sformatf("queues_empty ex=%s", xn(x)));
        inv(clash[x] == 0, $sformatf("no_b_clash ex=%s clash_ticks=%0d", xn(x), clash[x]));
        inv(!uno_seen[x] && !mko_seen[x], $sformatf("no_queue_overflow ex=%s un_ovf=%0d mk_ovf=%0d", xn(x), uno_seen[x], mko_seen[x]));
        inv((ld_tup[x*64 +: 64] & LD_TRUNKS[x*64 +: 64]) == LD_TRUNKS[x*64 +: 64],
            $sformatf("links_up ex=%s", xn(x)));
    end
    nb = 0; s = "";
    for (p = 0; p < all_n; p++) if (ld_e[all_ph[p]] || ld_hook[all_ph[p]]) begin nb++; s = {s, " ", pn(all_ph[p])}; end
    inv(nb == 0, $sformatf("phones_quiet (none ringing or off hook)%s", s));
    inv(n_selftest_fail == 0, "signature_selftest");
    $display("INVARIANT TOTAL pass=%0d fail=%0d", inv_pass, inv_fail);
endtask

function automatic string c2sn(int k);
    case (k) 0: return "IDLE"; 1: return "COLLECT"; 2: return "PROBE"; 3: return "DRAIN";
    4: return "READ"; 5: return "TAKE"; 6: return "YIELD"; 7: return "WATCH"; default: return "?"; endcase
endfunction
task automatic summary;
    int x, o, w, b, g, i, tot, na;
    real T;
    T = real'(ms_samp > 0 ? ms_samp : 1);
    $display("SUMMARY run scale=%0d seed=%0d traffic_ms=%0d sim_ms=%0d phones=%0d calls=%0d",
             LD_SCALE, k_seed, ms_samp, now_ms, all_n, n_calls);
    tot = 0; for (o = 0; o < NO; o++) tot += n_cls[o];
    $write("SUMMARY outcome total=%0d", tot);
    for (o = 1; o < NO; o++) $write(" %s=%0d", oname(o), n_cls[o]);
    $write("\n");
    for (b = 0; b < 3; b++) begin
        na = 0; for (o = 0; o < NO; o++) na += n_cls_k[b*NO + o];
        $write("SUMMARY outcome kind=%s total=%0d", kname(b), na);
        for (o = 1; o < NO; o++) if (n_cls_k[b*NO + o]) $write(" %s=%0d", oname(o), n_cls_k[b*NO + o]);
        $write("\n");
    end
    for (x = 0; x < NX; x++) begin
        na = 0; for (o = 0; o < NO; o++) na += n_cls_x[x*NO + o];
        $write("SUMMARY attempts ex=%s total=%0d per_s=%.3f", xn(x), na, real'(na) * 1000.0 / T);
        for (o = 1; o < NO; o++) if (n_cls_x[x*NO + o]) $write(" %s=%0d", oname(o), n_cls_x[x*NO + o]);
        $write("\n");
    end
    $write("SUMMARY why");
    for (w = 1; w < NW; w++) if (n_why[w]) $write(" %s=%0d", wname(w), n_why[w]);
    $write("\n");
    $display("SUMMARY safety wrong=%0d joined=%0d xtalk=%0d nospeech=%0d dtagain=%0d silent=%0d phantom=%0d wrongring=%0d idlehear=%0d ring_anon=%0d drainring=%0d alert_nobell=%0d stuck=%0d",
             n_cls[O_WRONG], n_cls[O_JOINED], n_cls[O_XTALK], n_cls[O_NOSPEECH], n_cls[O_DTAGAIN],
             n_cls[O_SILENT], n_phantom, n_wrongring, n_idlehear, n_ringanon, n_drainring, n_alert_nobell, n_stuck);
    $display("SUMMARY carried erlangs=%.3f talk_ms=%0d traffic_ms=%0d", real'(talk_ms) / T, talk_ms, ms_samp);
    $display("SUMMARY dialtone_delay n=%0d mean=%.1f p50=%0d p99=%0d max=%0d",
             n_dt, n_dt ? real'(s_dt) / n_dt : 0.0, pctl(0, n_dt, 50), pctl(0, n_dt, 99), mx_dt);
    $display("SUMMARY postdial_alert n=%0d mean=%.1f p50=%0d p99=%0d max=%0d",
             n_pdd, n_pdd ? real'(s_pdd) / n_pdd : 0.0, pctl(1, n_pdd, 50), pctl(1, n_pdd, 99), mx_pdd);
    $display("SUMMARY postdial_nogo n=%0d mean=%.1f p50=%0d p99=%0d max=%0d (and %0d heard before the last digit)",
             n_pdn, n_pdn ? real'(s_pdn) / n_pdn : 0.0, pctl(2, n_pdn, 50), pctl(2, n_pdn, 99), mx_pdn, n_middial);
    for (x = 0; x < NX; x++) begin
        $display("SUMMARY exchange ex=%s reg_occ=%.3f reg_maxrun_ms=%0d dt_wait_mean=%.2f dt_wait_max=%0d offhook_mean=%.2f origin_occ=%.3f hunting_occ=%.3f sweeps=%0d mon_mean=%.3f mon_max=%0d res_mean=%.3f res_max=%0d busB_occ=%.4f",
                 xn(x), x_reg[x] / T, x_regmax[x], x_wait[x] / T, x_waitmax[x], x_off[x] / T,
                 x_org[x] / T, x_hunt[x] / T, cnt_sweep[x],
                 x_mon[x] / T, x_monmax[x], x_res[x] / T, x_resmax[x], real'(bus_ticks[x]) / (T * 4096.0));
        for (b = 0; b < 8; b++) if (LD_TRUNKS[x*64 + b*8 +: 8] != 0)
            $display("SUMMARY link ex=%s blk=%0d channels=%0d busy_mean=%.3f busy_max=%0d",
                     xn(x), b, $countones(LD_TRUNKS[x*64 + b*8 +: 8]), x_trk[x*8 + b] / T, x_trkmax[x*8 + b]);
        $display("SUMMARY unit ex=%s floods=%0d local=%0d done=%0d nogo=%0d seized_in=%0d nomon=%0d unhold=%0d nofwd_busy=%0d nofwd_empty=%0d n_nofwd=%0d claims=%0d att_take=%0d att_refuse=%0d refuse_unattributed=%0d n_glare=%0d ev_glare_q=%0d ev_notrunk_q=%0d cableB_EV_GLARE=%0d cableB_EV_NOTRUNK=%0d cableB_other=%0d",
                 xn(x), cnt_flood[x], cnt_local[x], cnt_done[x], cnt_nogo[x], cnt_seize[x], cnt_nomon[x],
                 cnt_unhold[x], cnt_nfb[x], cnt_nfe[x], ld_nf[x*8 +: 8], cnt_claim[x], cnt_take[x], cnt_ref[x],
                 cnt_refunattr[x], x_glare[x], cnt_evg[x], cnt_evn[x], ev_gl[x], ev_nt[x], ev_ot[x]);
        $write("SUMMARY nogo_written ex=%s", xn(x));
        for (w = 1; w < NW; w++) if (x_why[x*NW + w]) $write(" %s=%0d", wname(w), x_why[x*NW + w]);
        $write("\n");
        $display("SUMMARY checks ex=%s un_ovf=%0d mk_ovf=%0d b_clash_ticks=%0d", xn(x), uno_seen[x], mko_seen[x], clash[x]);
        $display("SUMMARY c2reg ex=%s reg_occ=%.4f yield=%.4f claimed=%.4f other=%.4f att_occ=%.4f",
                 xn(x), x_reg[x] / T, c2_regy[x] / T, c2_regc[x] / T, (x_reg[x] - c2_regy[x] - c2_regc[x]) / T, c2_att[x] / T);
        $write("SUMMARY c2refst ex=%s", xn(x));
        for (w = 0; w < 16; w++) if (c2_refst[x*16 + w]) begin
            if (w % 2) $write(" %s/c=%0d", c2sn(w / 2), c2_refst[x*16 + w]); else $write(" %s=%0d", c2sn(w / 2), c2_refst[x*16 + w]);
        end
        $write("\n");
        $write("SUMMARY c2takest ex=%s", xn(x));
        for (w = 0; w < 16; w++) if (c2_takest[x*16 + w]) begin
            if (w % 2) $write(" %s/c=%0d", c2sn(w / 2), c2_takest[x*16 + w]); else $write(" %s=%0d", c2sn(w / 2), c2_takest[x*16 + w]);
        end
        $write("\n");
    end
    for (i = 0; i < all_n; i++) begin
        g = all_ph[i];
        $write("SUMMARY line %s att=%0d ok=%0d rung=%0d answered=%0d", pn(g), ln_att[g], ln_ok[g], ln_rung[g], ln_ans[g]);
        for (o = 2; o < NO; o++) if (ln_cls[g*NO + o]) $write(" %s=%0d", oname(o), ln_cls[g*NO + o]);
        $write("\n");
    end
endtask

// ---- the clock of it all ----------------------------------------------------------------
always @(posedge ld_clk[0]) if (ld_t1k[0] && phase > 0) begin : ms
    int i, g, x, lim;
    now_ms++;
    if (phase == 1) begin
        if ((((ld_tup & LD_TRUNKS) == LD_TRUNKS) && now_ms > 20) || now_ms > 300) begin
            if ((ld_tup & LD_TRUNKS) != LD_TRUNKS) $display("WARN links not all up at start");
            t_start = now_ms; t_stop = t_start + k_dur; phase = 2;
            for (i = 0; i < all_n; i++) begin
                g = all_ph[i];
                ph_dl[g] = next_start(g);
            end
            $display("START t=%0d traffic until %0d", t_start, t_stop);
        end
    end else begin
        if (phase == 2 && now_ms >= t_stop) begin
            phase = 3; $display("STOP t=%0d no new calls", now_ms);
        end
        if (phase == 3 && now_ms >= t_stop + k_grace) begin
            phase = 4; t_hup = now_ms;
            force_hangup;
            $display("HANGUP t=%0d every phone on hook; drain %0d ms", now_ms, k_drain);
        end
        for (i = 0; i < all_n; i++) ph_step(all_ph[i]);
        sample_ms;
        watchdog;
        if (k_prog > 0 && now_ms % k_prog == 0) begin
            // totals so far, then this interval's: attempts started, ended OK,
            // ended otherwise (CUT aside), and each register's occupancy
            $write("PROG t=%0d calls=%0d ok=%0d busy=%0d nogo=%0d nodt=%0d wrong=%0d joined=%0d stuck=%0d | iv_ms=%0d started=%0d ok=%0d failed=%0d reg_occ",
                   now_ms, n_calls, n_cls[O_OK], n_cls[O_BUSY], n_cls[O_NOGO], n_cls[O_NODT],
                   n_cls[O_WRONG], n_cls[O_JOINED], n_stuck, iv_ms, iv_start, iv_ok, iv_fail);
            for (x = 0; x < NX; x++) begin
                $write(" %s=%.2f", xn(x), iv_ms ? real'(iv_reg[x]) / iv_ms : 0.0);
                iv_reg[x] = 0;
            end
            $write("\n");
            iv_ms = 0; iv_start = 0; iv_ok = 0; iv_fail = 0;
            $fflush();
        end
        if (phase == 4 && now_ms >= t_hup + k_drain) begin
            phase = 5;
            // a drained phone still rung, or a port still held: say which
            check_invariants;
            summary;
            $display("END t=%0d", now_ms);
            $finish;
        end
        if (k_maxms > 0 && now_ms >= k_maxms) begin
            $display("TIMEOUT t=%0d (+max_ms)", now_ms);
            check_invariants; summary; $finish;
        end
    end
end

// ---- during the drain, a bell anywhere is noted --------------------------------------
always @(posedge ld_clk[0]) if (ld_t1k[0] && phase == 4) begin : drainwatch
    int i, g;
    for (i = 0; i < all_n; i++) begin
        g = all_ph[i];
        if (ld_e[g] && now_ms - t_hup > k_phgrace && ph_st[g] == P_DRAINED) begin
            n_drainring++;
            ph_st[g] = P_OFF;                            // report each line once
            $display("DRAINRING t=%0d at=%s (%0d ms after everyone hung up)", now_ms, pn(g), now_ms - t_hup);
        end
    end
end

initial begin
    setup;
    repeat (20) @(posedge ld_clk[0]);
    ld_rst_n = 1'b1;
    phase = 1;
end
