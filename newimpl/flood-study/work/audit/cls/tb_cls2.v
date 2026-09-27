// tb_cls -- directed audit bench for net_unit's CLASSIFIER and READ PATH.
// Scratch, not part of the test sequence.  One exchange (site_net), code 2 2,
// with every trunk's far end driven by the bench (a_in, c_in, clk_in), so the
// timing of a far seizure, a dial, a link glitch or a blip is exact.
//
// Build-time: +define+SCALE8 scales the timers by 8 (as tb_net); default is
// REAL timers.  +define+POOL8 stuffs NMON = NRES = 8; default is 2 and 2.
//
//   +sc=1  BURST: K W-facing trunks seized at once; each far caller dials
//          E B 2 1 after D ms.  Per trunk: classifier latency, monitor arm
//          time against the first break, the e the monitor counted, whether
//          it claimed, and when its forward's legs rose.  A line (23) lifts
//          3 ms in: how long to its dial tone while the unit sweeps.
//   +sc=2  GLITCH, marker idle: one seizure on 10; the far clock stops for
//          the frames that carry bits 7, 0, 1 of the read both readers make.
//   +sc=3  GLITCH, marker busy: as 2, with 22 holding the register, so only
//          the unit reads; 22 hangs up so the register is free again later.
//   +sc=4  BLIP AT THE CONFIRM: 20 dials 1; a sub-ms far M on 71 (N) seen by
//          the classifier during the sweep's last read, gone by the confirm.
//          Then the far end seizes 71 for real after the guard.
//   +sc=6  RELEASED UNDER A STANDING M: 21 hangs up first; the far caller
//          dials on through the released 10.
//   +sc=5  DIALLING A TRUNK WHOSE LINK IS DOWN: 30 (S) has no far clock; 22
//          dials 3 0; then the link comes up and 22 dials 2 1.
`timescale 1ns/1ps
`include "exch.vh"

module tb_cls;
`ifdef SCALE8
    localparam [8:0]  P_T_ARM = 9'd2,  P_T_REL = 9'd32, P_HIT = 9'd1, P_ID = 9'd16, P_CLR = 9'd32;
    localparam [12:0] P_RON = 13'd64, P_ROFF = 13'd128;
    localparam [15:0] P_NODIG = 16'd1250, P_GUARD = 16'd16, P_KEY = 16'd625, P_CLAIM = 16'd250;
    localparam integer BRK = 12, MKE = 8, DPAUSE = 100, REL = 80;
`else
    localparam [8:0]  P_T_ARM = 9'd16, P_T_REL = 9'd256, P_HIT = 9'd8, P_ID = 9'd128, P_CLR = 9'd256;
    localparam [12:0] P_RON = 13'd2048, P_ROFF = 13'd4096;
    localparam [15:0] P_NODIG = 16'd10000, P_GUARD = 16'd128, P_KEY = 16'd5000, P_CLAIM = 16'd2000;
    localparam integer BRK = 60, MKE = 40, DPAUSE = 400, REL = 640;
`endif
`ifdef POOL8
    localparam integer NM = 8, NR = 8;
`else
    localparam integer NM = 2, NR = 2;
`endif

    integer chk = 0, errs = 0;
    task ck(input cond, input [8*80-1:0] what);
        begin chk = chk + 1;
             if (!cond) begin errs = errs + 1; $display("    FAIL  %0s", what); end
             else $display("    ok    %0s", what);
        end
    endtask

    reg clk = 1'b0, rst_n = 1'b0;
    always #122.070 clk = ~clk;

    // ---- ports (decimal indices; octal names) ------------------------------
    localparam integer P20 = 16, P21 = 17, P22 = 18, P23 = 19, P32 = 26;
    localparam integer TS = 24;          // o30, faces S
    localparam integer TN = 57;          // o71, faces N
    // W trunks o10-o17 = 8..15, E trunks o40-o47 = 32..39
    function [7:0] tw(input [1:0] dir); tw = {dir, 1'b0, 3'b010, 2'b11}; endfunction
    function [511:0] words(input integer dummy);
        integer q;
        begin
            words = 512'd0;
            for (q = 8; q < 16; q = q + 1)  words[q*8 +: 8] = tw(2'd3);
            for (q = 32; q < 40; q = q + 1) words[q*8 +: 8] = tw(2'd2);
            words[TS*8 +: 8] = tw(2'd1);
            words[TN*8 +: 8] = tw(2'd0);
        end
    endfunction
    localparam [63:0] PH = (64'd1 << P20) | (64'd1 << P21) | (64'd1 << P22) |
                           (64'd1 << P23) | (64'd1 << P32);
    localparam [63:0] TR = 64'h0000_00FF_0000_FF00 | (64'd1 << TS) | (64'd1 << TN);

    reg  [63:0] hook = 64'd0, tx = 64'd0;
    wire [63:0] rx, e, busy, c_out, a_out, k_out, up;
    reg  [63:0] fa = 64'd0, fc = 64'd0, kill = 64'd0;
    wire [63:0] k_in = k_out & ~kill;
    wire        fs, t1k, rcad, sd, sclk_b, wrb, clash, rbusy, mko, cla, hunt, uno;
    wire [2:0]  mks;
    wire [3:0]  dirs;
    wire [NR-1:0] resb;
    wire [NM-1:0] monh;
    wire [7:0]  ngl, nnf;

    site_net #(.PHONES(PH), .TRUNKS(TR), .TWORD(words(0)), .OWN_E(3'd2), .OWN_B(3'd2),
               .NMON(NM), .NRES(NR),
               .T_ARM(P_T_ARM), .T_REL(P_T_REL), .RING_ON(P_RON), .RING_OFF(P_ROFF),
               .HIT(P_HIT), .ID(P_ID), .CLR(P_CLR), .NODIG(P_NODIG),
               .T_GUARD0(P_GUARD), .T_KEY(P_KEY), .T_CLAIM(P_CLAIM)) S (
        .clk(clk), .rst_n(rst_n), .hook(hook), .tx(tx), .rx(rx), .e(e),
        .c_out(c_out), .a_out(a_out), .clk_out(k_out),
        .c_in(fc), .a_in(fa), .clk_in(k_in), .link_up(up),
        .lt_c_in(8'd0), .lt_a_in(8'd0), .lt_h_in(8'd0), .lt_k_in(8'd0),
        .lt_c_out(), .lt_a_out(), .lt_h_out(), .lt_k_out(), .lt_up(),
        .frame_stb(fs), .tick_1k(t1k), .ring_cad_n(rcad), .port_busy(busy),
        .b_sdata(sd), .b_sclk(sclk_b), .b_wr(wrb), .b_clash(clash),
        .reg_busy(rbusy), .mk_state(mks), .mk_ovf(mko), .dirs_held(dirs),
        .res_busy(resb), .mon_held(monh), .claimed(cla), .hunting(hunt),
        .un_ovf(uno), .n_glare(ngl), .n_nofwd(nnf));

`define N  S.u_x.u_net
`define MK S.u_x.u_mk

    // ---- time --------------------------------------------------------------
    function real now_ms(input integer dummy); now_ms = $realtime / 1.0e6; endfunction
    task ms(input integer n); begin repeat (n) @(posedge t1k); end endtask
    task frames(input integer n); begin repeat (n) @(posedge fs); end endtask

    // ---- the event log -----------------------------------------------------
    integer verbose = 1;
    real    t_seen [0:63], t_hold [0:63], t_arm [0:63], t_fwd [0:63], t_leg [0:63];
    integer ecnt [0:63], nseen [0:63], nhold [0:63], nunhold [0:63], nclaim [0:63];
    integer fwd_of_leg [0:63];
    reg [NM-1:0] marm_d = {NM{1'b0}};
    reg [63:0]   aout_d = 64'd0;
    integer g, q, n_claims = 0, n_cls_clash = 0;
    initial for (q = 0; q < 64; q = q + 1) begin
        t_seen[q] = -1.0; t_hold[q] = -1.0; t_arm[q] = -1.0; t_fwd[q] = -1.0; t_leg[q] = -1.0;
        ecnt[q] = -1; nseen[q] = 0; nhold[q] = 0; nunhold[q] = 0; nclaim[q] = 0; fwd_of_leg[q] = -1;
    end

    always @(posedge clk) if (rst_n) begin
        if (`N.cls_seen) begin
            nseen[`N.sp_port] = nseen[`N.sp_port] + 1;
            if (t_seen[`N.sp_port] < 0.0) t_seen[`N.sp_port] = now_ms(0);
            if (verbose) $display("  %9.3f  cls_seen  %o  (cst %0d, rd_free %0d)", now_ms(0), `N.sp_port,
                                  `N.cst, `N.rd_free);
        end
        if (`N.w_cls && (`N.cst == 3'd2)) begin
            nhold[`N.cls_port] = nhold[`N.cls_port] + 1;
            if (t_hold[`N.cls_port] < 0.0) t_hold[`N.cls_port] = now_ms(0);
            if (verbose) $display("  %9.3f  HOLD      %o  dir %0d  mine %0d  nst %0d", now_ms(0), `N.cls_port,
                                  `N.cls_dir, `N.mine, `N.nst);
        end
        if (`N.w_cls && (`N.cst == 3'd4)) begin
            nunhold[`N.cls_port] = nunhold[`N.cls_port] + 1;
            if (verbose) $display("  %9.3f  UNHOLD    %o  nst %0d d_held %b", now_ms(0), `N.cls_port, `N.nst, `N.d_held);
        end
        if ((`N.cst == 3'd1) && `N.rd_done && !`N.rd_own && verbose)
            $display("  %9.3f  cls read  %o  word %b  trunk %0d", now_ms(0), `N.cls_port, `N.rd_word,
                     `N.rd_word[4:0] == 5'b01011);
        for (g = 0; g < NM; g = g + 1) begin
            if (`N.m_armed[g] && !marm_d[g]) begin
                if (t_arm[`N.m_port[g*6 +: 6]] < 0.0) t_arm[`N.m_port[g*6 +: 6]] = now_ms(0);
                if (verbose) $display("  %9.3f  mon%0d arm  %o", now_ms(0), g, `N.m_port[g*6 +: 6]);
            end
            if (`N.d_stb[g] && `N.m_held[g]) begin
                if (`N.m_st[g*2 +: 2] == 2'd1) ecnt[`N.m_port[g*6 +: 6]] = `N.d_cnt[g*4 +: 4];
                if (verbose) $display("  %9.3f  mon%0d %o digit %0d (%s)", now_ms(0), g, `N.m_port[g*6 +: 6],
                                      `N.d_cnt[g*4 +: 4], (`N.m_st[g*2 +: 2] == 2'd1) ? "as e" : "as b");
            end
        end
        marm_d = `N.m_armed;
        if (`N.w_claim) begin
            n_claims = n_claims + 1; nclaim[`N.m_want_port] = nclaim[`N.m_want_port] + 1;
            if (verbose) $display("  %9.3f  CLAIM     %o", now_ms(0), `N.m_want_port);
        end
        if (`N.w_fwd) begin
            if (t_fwd[`N.f_in] < 0.0) t_fwd[`N.f_in] = now_ms(0);
            for (g = 0; g < 4; g = g + 1) if (`N.f_ok[g]) fwd_of_leg[`N.f_cand[g*6 +: 6]] = `N.f_in;
            if (verbose) $display("  %9.3f  FWD       %o -> ok %b cand %o %o %o %o", now_ms(0), `N.f_in, `N.f_ok,
                                  `N.f_cand[5:0], `N.f_cand[11:6], `N.f_cand[17:12], `N.f_cand[23:18]);
        end
        if (`N.nf_busy && verbose) $display("  %9.3f  NOFWD(busy) %o", now_ms(0), `N.cls_port);
        if (`N.nf_empty && verbose) $display("  %9.3f  NOFWD(empty) %o", now_ms(0), `N.f_in);
        for (q = 0; q < 64; q = q + 1)
            if (TR[q] && a_out[q] && !aout_d[q] && (t_leg[q] < 0.0)) t_leg[q] = now_ms(0);
        aout_d = a_out;
        if (`MK.push_v == 2'b11 && verbose)
            $display("  %9.3f  MK CONNECT caller %o called %o", now_ms(0), `MK.caller, `MK.called);
        if (`MK.r_attach && verbose)
            $display("  %9.3f  MK register -> %o", now_ms(0), `MK.r_port);
        if (`MK.state == 3'd4 && `MK.rd_done && verbose)
            $display("  %9.3f  MK read    %o  word %b  (%s)", now_ms(0), `MK.rd_port, `MK.rd_word,
                     `MK.rd_caller ? "caller?" : "called");
        if (`N.u_rd.ws_pd && `MK.u_rd.ws_pd && (`N.u_rd.at != `MK.u_rd.at)) n_cls_clash = n_cls_clash + 1;
    end

    // ---- a far caller, several in lockstep -----------------------------------
    task far_dial(input [63:0] mask, input integer d, input integer pause);
        integer n, i;
        begin n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                fa = fa & ~mask; ms(BRK); fa = fa | mask; ms(MKE);
            end
            ms(pause);
        end
    endtask
    task dial(input integer p, input integer d);
        integer n, i;
        begin n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                hook[p] = 1'b0; ms(BRK); hook[p] = 1'b1; ms(MKE);
            end
            ms(DPAUSE);
        end
    endtask

    // being rung: the port's own RB = ON . E (the block sends it ringback)
    wire rb21 = S.u_x.u_exch.pos[2].u_blk.u_port1.rb;
    wire rb32 = S.u_x.u_exch.pos[3].u_blk.u_port2.rb;
    integer hi, lo;
    task rings(input integer p, input integer n);
        integer i;
        begin hi = 0; lo = 0;
            for (i = 0; i < n; i = i + 1) begin @(posedge t1k);
                if ((p == P21) ? rb21 : rb32) hi = hi + 1; else lo = lo + 1; end
        end
    endtask
    // breaks going out on 30's link
    integer nbrk30 = 0; reg cnt30 = 1'b0, a30_d = 1'b0;
    always @(posedge clk) begin a30_d <= a_out[TS]; if (cnt30 && a30_d && !a_out[TS]) nbrk30 = nbrk30 + 1; end
    integer j; reg s0, s1;
    task hear(input integer p);
        begin s0 = 1'b0; s1 = 1'b0;
            for (j = 0; j < 8; j = j + 1) begin
                @(posedge fs); @(posedge clk);
                if (rx[p]) s1 = 1'b1; else s0 = 1'b1;
            end
        end
    endtask

    task idle_check(input [8*80-1:0] what);
        begin
            ck(busy == 64'd0 && !rbusy && mks == 3'd0 && dirs == 4'd0 && resb == {NR{1'b0}} &&
               monh == {NM{1'b0}} && !hunt && `N.cst == 3'd0 && `N.fst == 2'd0 && `N.nst == 4'd0, what);
            if (busy != 64'd0) $display("      busy ports %h", busy);
            $display("      reg %0d mk %0d dirs %b res %b mon %b hunt %0d cst %0d fst %0d nst %0d",
                     rbusy, mks, dirs, resb, monh, hunt, `N.cst, `N.fst, `N.nst);
        end
    endtask

    // ---- the link glitch: stop the far clock of port p for the frames that
    // carry bits 7, 0 and 1 of the read whose select is at p's turn.  Waits
    // for a select of p by EITHER reader.
    task glitch_read(input integer p);
        begin
            @(posedge clk);
            while (!(((`N.u_rd.ws_pd) || (`MK.u_rd.ws_pd)) && (S.u_x.scan == p[5:0]))) @(posedge clk);
            $display("  %9.3f  select of %o (unit %0d marker %0d): glitching its link", now_ms(0), p[5:0],
                     `N.u_rd.ws_pd, `MK.u_rd.ws_pd);
            frames(3); repeat (2) @(posedge clk); kill[p] = 1'b1;   // no far edge after frame y+3's
            frames(5); repeat (40) @(posedge clk); kill[p] = 1'b0;  // the next is frame y+9's
        end
    endtask

    integer sc, K, D, E, B, PZ, maxms;
    integer k, n_late, n_wrong, nq6;
    real    t0, tb0, t_dt;
    reg [63:0] m;
    reg [5:0]  lat_o71;
    reg        bsy_o71;

    initial begin
        if (!$value$plusargs("sc=%d", sc)) sc = 1;
        if (!$value$plusargs("K=%d", K)) K = 8;
        if (!$value$plusargs("D=%d", D)) D = P_GUARD;
        if (!$value$plusargs("E=%d", E)) E = 3;
        if (!$value$plusargs("B=%d", B)) B = 2;
        if (!$value$plusargs("pause=%d", PZ)) PZ = DPAUSE;
        if (!$value$plusargs("v=%d", verbose)) verbose = 1;
        $display("\n  tb_cls sc=%0d K=%0d D=%0d E=%0d B=%0d pause=%0d  NMON=%0d NRES=%0d  T_ARM=%0d guard=%0d",
                 sc, K, D, E, B, PZ, NM, NR, P_T_ARM, P_GUARD);
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        ms(20);
        ck((up & TR) == TR, "every trunk's link is up");

        case (sc)
        // ======================================================================
        1: begin
            m = 64'd0;
            for (k = 0; k < K; k = k + 1) m[8 + k] = 1'b1;
            @(posedge t1k); repeat (100) @(posedge clk);
            t0 = now_ms(0);
            fa = fa | m;                                   // K seizures at once
            $display("  %9.3f  %0d far seizures on W trunks", t0, K);
            fork
                begin ms(3); hook[P23] = 1'b1; t_dt = -1.0;
                      while (busy[P23] !== 1'b1) @(posedge clk);
                      t_dt = now_ms(0);
                      $display("  %9.3f  23 BUSY (dial tone) %.3f ms after its lift", t_dt, t_dt - t0 - 3.0);
                      ms(40); hook[P23] = 1'b0; end
                begin ms(D); tb0 = now_ms(0);
                      far_dial(m, E, PZ); far_dial(m, B, PZ); far_dial(m, 2, PZ); far_dial(m, 1, PZ); end
            join
            ms(200);
            rings(P21, 600);
            $display("  21 ringing: hi %0d lo %0d", hi, lo);
            rings(P32, 10);
            $display("\n  port  seen    hold    arm     fwd     e-cnt  claims  nseen nhold nunhold   (ms after the seizure; first break at +%0.1f)",
                     tb0 - t0);
            n_late = 0; n_wrong = 0;
            for (k = 0; k < K; k = k + 1) begin
                q = 8 + k;
                $display("  %o    %6.1f  %6.1f  %6.1f  %6.1f  %3d    %0d       %0d     %0d     %0d",
                         q[5:0], t_seen[q] - t0, t_hold[q] - t0, (t_arm[q] < 0.0) ? -1.0 : t_arm[q] - t0,
                         (t_fwd[q] < 0.0) ? -1.0 : t_fwd[q] - t0, ecnt[q], nclaim[q], nseen[q], nhold[q], nunhold[q]);
                if (t_arm[q] > tb0) n_late = n_late + 1;
                if (nclaim[q] != 0) n_wrong = n_wrong + 1;
            end
            for (q = 0; q < 64; q = q + 1)
                if (TR[q] && (fwd_of_leg[q] >= 0))
                    $display("  leg %o carried %o: its far end saw M rise at +%6.1f (%s the first break)",
                             q[5:0], fwd_of_leg[q][5:0], t_leg[q] - t0, (t_leg[q] > tb0) ? "AFTER" : "before");
            $display("  n_nofwd %0d, monitors armed after the first break %0d, trunks that claimed %0d (dialled %0d %0d, own 2 2)",
                     nnf, n_late, n_wrong, E, B);
            fa = 64'd0;
            ms(REL * 2);
            idle_check("sc1: every far caller gone: nothing held");
        end
        // ======================================================================
        2, 3: begin
            if (sc == 3) begin
                hook[P22] = 1'b1; ms(10);
                dial(P22, 2);                              // 22 holds the register
                ck(rbusy === 1'b1, "sc3: 22 holds the one register");
            end
            @(posedge t1k); repeat (100) @(posedge clk);
            t0 = now_ms(0);
            fa[8] = 1'b1;
            $display("  %9.3f  far seizure on 10", t0);
            glitch_read(8);
            if (sc == 3) begin ms(5); hook[P22] = 1'b0; end  // register free again at CLR
            ms(D - ((sc == 3) ? 5 : 0) - 3);
            tb0 = now_ms(0);
            far_dial(64'd1 << 8, E, PZ); far_dial(64'd1 << 8, B, PZ);
            far_dial(64'd1 << 8, 2, PZ); far_dial(64'd1 << 8, 1, PZ);
            ms(100);
            rings(P21, 600); $display("  21 ringing: hi %0d lo %0d", hi, lo);
            k = hi;
            rings(P32, 600); $display("  32 ringing: hi %0d lo %0d", hi, lo);
            $display("  10: seen %0d held %0d unheld %0d claimed %0d, e counted %0d; marker caller %o",
                     nseen[8], nhold[8], nunhold[8], nclaim[8], ecnt[8], `MK.caller);
            ck(k == 0 && hi == 0, "a far caller dialling 3 2 2 1 rings nobody at exchange 2 2");
            fa = 64'd0;
            ms(REL * 2 + 300);
            idle_check("sc2/3: far caller gone: nothing held");
        end
        // ======================================================================
        4: begin
            hook[P20] = 1'b1; ms(10);
            // the key: one pulse, and watch the sweep
            fork
                dial(P20, 1);
                begin
                    while (!((`N.hst == 3'd1) && (`N.h_n == 7'd63) && `N.h_reading)) @(posedge clk);
                    $display("  %9.3f  sweep's last read in flight (h_idx %o, scan %o): far blip on 71",
                             now_ms(0), `N.h_idx, S.u_x.scan);
                    fa[TN] = 1'b1; frames(50); fa[TN] = 1'b0;
                    $display("  %9.3f  blip over", now_ms(0));
                end
            join
            ms(5);
            lat_o71 = S.u_x.u_exch.pos[7].u_blk.u_port1.addr;
            bsy_o71 = S.u_x.u_exch.pos[7].u_blk.u_port1.bsy;
            $display("  %9.3f  origin: nst %0d dirs_held %b d_trunk %o %o %o %o; 71 latch -> %o bsy %0d",
                     now_ms(0), `N.nst, `N.d_held, `N.d_trunk[5:0], `N.d_trunk[11:6], `N.d_trunk[17:12],
                     `N.d_trunk[23:18], lat_o71, bsy_o71);
            ck(!(`N.d_held[0] && (`N.d_trunk[5:0] == 6'o71)) || (lat_o71 == 6'o20 && bsy_o71),
               "sc4: a trunk the origin holds listens to its caller");
            // a far exchange now takes the channel our end has silently let go
            ms(200);
            // the far end hunts its end of the channel only if it looks free
            // from there: no M on it, which is our a_out
            if (a_out[TN] === 1'b0) begin
                fc[TN] = 1'b1; fa[TN] = 1'b1;
                $display("  %9.3f  71 looks free from the far end: it seizes it (a flood of its own), talking 1s", now_ms(0));
            end else
                $display("  %9.3f  the far end sees our M on 71: it would not hunt it", now_ms(0));
            ms(20);
            $display("  %9.3f  origin claimed %0d trunk %o glare %0d", now_ms(0), cla, `N.trunk, ngl);
            dial(P20, 5); dial(P20, 5); dial(P20, 2); dial(P20, 1);
            ms(50);
            hear(P20);
            $display("  %9.3f  20 hears ones %0d zeros %0d; 20's latch -> %o", now_ms(0), s1, s0,
                     S.u_x.u_exch.pos[2].u_blk.u_port0.addr);
            ck(!(s1 && !s0 && (S.u_x.u_exch.pos[2].u_blk.u_port0.addr == 6'o71)),
               "sc4: 20, who dialled 1 5 5 2 1, is not connected to a stranger's seizure on 71");
            hook[P20] = 1'b0; fa[TN] = 1'b0; fc[TN] = 1'b0;
            ms(REL * 2 + 300);
            idle_check("sc4: everyone gone: nothing held");
        end
        // ======================================================================
        5: begin
            kill[TS] = 1'b1; ms(5);
            ck(!up[TS], "sc5: 30's link is down");
            hook[P22] = 1'b1; ms(10);
            dial(P22, 3); dial(P22, 0); ms(20);
            $display("  %9.3f  30 busy %0d latch -> %o; 22 latch -> %o", now_ms(0), busy[TS],
                     S.u_x.u_exch.pos[3].u_blk.u_port0.addr, S.u_x.u_exch.pos[2].u_blk.u_port2.addr);
            hear(P22); $display("  22 hears ones %0d zeros %0d", s1, s0);
            ck(!(busy[TS] && S.u_x.u_exch.pos[3].u_blk.u_port0.addr == 6'o22),
               "sc5: a trunk port is never connected to a dialling line");
            kill[TS] = 1'b0; ms(5);
            $display("  %9.3f  link up %0d: a_out of 30 = %0d (the far end sees M)", now_ms(0), up[TS], a_out[TS]);
            cnt30 = 1'b1; dial(P22, 2); dial(P22, 1); cnt30 = 1'b0;
            $display("  breaks sent on 30's link while 22 dialled 2 1: %0d", nbrk30);
            hook[P22] = 1'b0;
            ms(REL * 2 + 300);
            idle_check("sc5: 22 gone: nothing held");
        end
        // ======================================================================
        6: begin
            // a far caller dials 2 2 2 1 on 10: we claim, 21 rings and answers;
            // 21 hangs up FIRST; 10 releases under the far caller's standing M;
            // the far caller, still off-hook, dials 3 2 2 1
            @(posedge t1k); repeat (100) @(posedge clk);
            t0 = now_ms(0);
            fa[8] = 1'b1;
            ms(D);
            far_dial(64'd1 << 8, 2, PZ); far_dial(64'd1 << 8, 2, PZ);
            far_dial(64'd1 << 8, 2, PZ); far_dial(64'd1 << 8, 1, PZ);
            ms(100);
            ck(rb21 === 1'b1, "sc6: 2 2 2 1 from the far caller rings 21");
            hook[P21] = 1'b1; ms(300);
            hook[P21] = 1'b0;                              // the called party goes first
            ms(P_T_REL + 40);
            $display("  %9.3f  10 latch -> %o bsy %0d busy %0d, far M still up; st[10] %0d",
                     now_ms(0), S.u_x.u_exch.pos[1].u_blk.u_port0.addr, S.u_x.u_exch.pos[1].u_blk.u_port0.bsy,
                     busy[8], `N.st[8]);
            k = n_claims;
            nq6 = nseen[8];
            far_dial(64'd1 << 8, 3, PZ); far_dial(64'd1 << 8, 2, PZ);
            far_dial(64'd1 << 8, 2, PZ); far_dial(64'd1 << 8, 1, PZ);
            ms(100);
            $display("  after the far caller dialled on: classified %0d more times, claims %0d more",
                     nseen[8] - nq6, n_claims - k);
            rings(P21, 600); $display("  21 ringing: hi %0d lo %0d", hi, lo);
            ck(nseen[8] == nq6, "sc6: a released trunk under a standing far M is not taken again mid-dial");
            fa = 64'd0;
            ms(REL * 2 + 300);
            idle_check("sc6: far caller gone: nothing held");
        end
        default: ;
        endcase

        ck(!clash && !mko && !uno, "no cable-B clash, no queue refused a write");
        $display("  readers selecting different ports in one bit-time: %0d", n_cls_clash);
        $display("\n  %0d checks, %0d errors.  %s\n", chk, errs, (errs == 0) ? "PASS" : "FAIL");
        $finish;
    end

    initial begin
        if (!$value$plusargs("maxms=%d", maxms)) maxms = 8000;
        #(maxms * 1.0e6); $display("  WATCHDOG at %0d ms", maxms); $finish;
    end

    wire _unused = &{1'b0, rcad, sd, sclk_b, wrb, c_out, rx, tx, 1'b0};
endmodule
