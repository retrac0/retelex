// tb_cls3 -- cls slice, round 2 (the traffic view).  Scratch, not part of the
// test sequence.  The plant is tb_cls2's: one exchange (site_net), code 2 2,
// every trunk's far end driven by the bench (a_in, c_in, clk_in).
//
// Build-time: +define+SCALE8 scales the timers by 8 (default REAL timers);
// +define+POOL8 stuffs NMON = NRES = 8 (default 2 and 2).
//
//   +sc=7   SCAN-ORDER PRIORITY: E trunk 47 is seized 5 ms after W trunk 10 and
//           before six more W seizures (11-16) that arrive every ~20 ms; each
//           C_HOLD ends on the 1 ms tick (scan 00), so the next seizure taken
//           is the LOWEST waiting port, not the oldest.  47's far caller dials
//           3 2 2 1 with its first break 128 ms after its rise.
//   +sc=8   DIRECTION MISREAD: a link glitch clears bits 6-7 of the classifier's
//           read of W trunk 10 (the frames that carry them only): 11001011 ->
//           00001011, a trunk facing N.  Where does the forward go?
//   +sc=9   NO SECOND CHOICE: 20 keys 1; after the origin sweep has read W
//           trunk 10 free, the far end seizes 10 for real.  CONFIRM drops the W
//           candidate; W 11-17 are free.  Which directions does the origin hold?
//   +sc=10  LOAD: Poisson floods (+lam per 1000 s) on the W and E groups, each
//           on the lowest trunk free from the far end; each far caller dials
//           e b (h s if e b is ours) with its first break +t1lo..+t1hi ms after
//           the rise; +pexp per mille dial 3 2 (one pulse above us), +pown 2 2,
//           the rest 4-7 4-7.  Four phones lift at random (+loc mean idle ms),
//           dial 0 (cannot-complete) or, +pnet per mille, 1 5 5 2 1.  One SZ
//           line a seizure, one LC line a local lift, a SUMMARY at the end.
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
    localparam [63:0] TR  = 64'h0000_00FF_0000_FF00 | (64'd1 << TS) | (64'd1 << TN);
    localparam [63:0] TRX = 64'h0000_00FF_0000_FF00;       // the load's far callers

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
    task automatic ms(input integer n); begin repeat (n) @(posedge t1k); end endtask
    task automatic frames(input integer n); begin repeat (n) @(posedge fs); end endtask

    // ---- a deterministic generator (xorshift64) -----------------------------
    reg [63:0] rs = 64'h9E3779B97F4A7C15;
    function [30:0] rnd(input integer dummy);
        begin rs = rs ^ (rs << 13); rs = rs ^ (rs >> 7); rs = rs ^ (rs << 17); rnd = rs[40:10]; end
    endfunction
    function integer uni(input integer lo, input integer hi);   // lo..hi inclusive
        uni = lo + (rnd(0) % (hi - lo + 1));
    endfunction
    function integer expo(input integer mean);                  // exponential, ms
        real u;
        begin u = ((rnd(0) % 1000000) + 1) / 1000000.0; expo = $rtoi(-1.0 * mean * $ln(u)) + 1; end
    endfunction

    // ======================================================================
    // PER-PORT RECORDS -- one far seizure at a time a port
    // ======================================================================
    integer verbose = 1;
    reg  [63:0] act = 64'd0, alive = 64'd0;      // a far seizure is on; its caller still off hook
    integer sid [0:63], se [0:63], sb [0:63], st1 [0:63], sback [0:63];
    real    t_rise [0:63], t_fb [0:63], t_seen [0:63], t_hold [0:63], t_arm [0:63];
    integer n_seen [0:63], n_hold [0:63], n_unh [0:63], n_cell [0:63], e_first [0:63],
            e_min [0:63], n_claim [0:63], n_wrong [0:63], n_late [0:63], n_unh_live [0:63];
    integer ix, gx;
    task clear_rec(input integer q);
        begin
            t_rise[q] = -1.0; t_fb[q] = 1.0e9; t_seen[q] = -1.0; t_hold[q] = -1.0; t_arm[q] = -1.0;
            n_seen[q] = 0; n_hold[q] = 0; n_unh[q] = 0; n_cell[q] = 0; e_first[q] = -1; e_min[q] = 99;
            n_claim[q] = 0; n_wrong[q] = 0; n_late[q] = 0; n_unh_live[q] = 0;
        end
    endtask
    initial for (ix = 0; ix < 64; ix = ix + 1) begin clear_rec(ix); sid[ix] = -1; end

    // ---- totals -------------------------------------------------------------
    integer T_sz = 0, T_blk = 0, T_wrong = 0, T_claim_ok = 0, T_late = 0, T_unh_live = 0,
            T_reclass = 0, T_trunk_caller = 0, T_refuse = 0, T_origin_claim = 0, T_rleg = 0,
            T_mk_rd_trunk = 0, T_mk_rd_line = 0, T_nocell = 0, T_hold_after_fb = 0;
    integer T_lift = 0, T_nodt = 0;
    integer n_sweep = 0; real sw_sum = 0.0, sw_max = 0.0, t_sw0 = 0.0;
    integer n_mrd = 0; real mrd_sum = 0.0, mrd_max = 0.0, t_mreq = 0.0;
    integer n_crd = 0; real crd_sum = 0.0, crd_max = 0.0, t_creq = 0.0;
    integer cls_busy_ms = 0, tot_ms = 0, back_now = 0, back_max = 0, back_sum = 0;
    integer hist_rh [0:9];          // rise -> hold: <2, <5, <20, <40, <60, <100, <150, <250, <500, more
    integer hist_rh_w [0:9], hist_rh_e [0:9];
    integer hist_dt [0:9];          // dial tone: <5, <10, <20, <50, <100, <250, <500, <1000, <3000, none
    initial for (ix = 0; ix < 10; ix = ix + 1) begin hist_rh[ix] = 0; hist_rh_w[ix] = 0; hist_rh_e[ix] = 0; hist_dt[ix] = 0; end
    function integer bin_rh(input real d);
        bin_rh = (d < 2.0) ? 0 : (d < 5.0) ? 1 : (d < 20.0) ? 2 : (d < 40.0) ? 3 : (d < 60.0) ? 4 :
                 (d < 100.0) ? 5 : (d < 150.0) ? 6 : (d < 250.0) ? 7 : (d < 500.0) ? 8 : 9;
    endfunction
    function integer bin_dt(input real d);
        bin_dt = (d < 5.0) ? 0 : (d < 10.0) ? 1 : (d < 20.0) ? 2 : (d < 50.0) ? 3 : (d < 100.0) ? 4 :
                 (d < 250.0) ? 5 : (d < 500.0) ? 6 : (d < 1000.0) ? 7 : 8;
    endfunction

    // ======================================================================
    // THE PROBES -- hierarchical, read only
    // ======================================================================
    reg [NM-1:0] marm_d = {NM{1'b0}};
    reg          hunt_d = 1'b0, mreq_p = 1'b0, creq_p = 1'b0, cla_d = 1'b0;
    reg [5:0]    q6;
    always @(posedge clk) if (rst_n) begin
        if (`N.cls_seen) begin
            q6 = `N.sp_port;
            if (act[q6]) begin
                if (n_hold[q6] > 0) begin
                    T_reclass = T_reclass + 1;
                    if (verbose) $display("  %9.3f  RECLASS  %o (held %0d times already; far alive %0d)", now_ms(0), q6, n_hold[q6], alive[q6]);
                end
                n_seen[q6] = n_seen[q6] + 1;
                if (t_seen[q6] < 0.0) t_seen[q6] = now_ms(0);
            end
            if (verbose > 1) $display("  %9.3f  cls_seen  %o  (rd_free %0d)", now_ms(0), q6, `N.rd_free);
        end
        if (`N.w_cls && (`N.cst == 3'd2)) begin
            q6 = `N.cls_port;
            if (act[q6]) begin
                n_hold[q6] = n_hold[q6] + 1;
                if (t_hold[q6] < 0.0) begin
                    t_hold[q6] = now_ms(0);
                    if (t_hold[q6] > t_fb[q6]) T_hold_after_fb = T_hold_after_fb + 1;
                end
            end
            if (verbose) $display("  %9.3f  HOLD      %o  dir %0d  mine %0d  nst %0d  word-dir", now_ms(0), q6, `N.cls_dir, `N.mine, `N.nst);
        end
        if (`N.w_cls && (`N.cst == 3'd4)) begin
            q6 = `N.cls_port;
            if (act[q6]) begin
                n_unh[q6] = n_unh[q6] + 1;
                if (alive[q6]) begin n_unh_live[q6] = n_unh_live[q6] + 1; T_unh_live = T_unh_live + 1; end
            end
            if (verbose) $display("  %9.3f  UNHOLD    %o  far alive %0d  nst %0d d_held %b", now_ms(0), q6, alive[q6], `N.nst, `N.d_held);
        end
        if ((`N.cst == 3'd1) && `N.rd_done && !`N.rd_own && verbose)
            $display("  %9.3f  cls read  %o  word %b  trunk %0d", now_ms(0), `N.cls_port, `N.rd_word,
                     `N.rd_word[4:0] == 5'b01011);
        for (gx = 0; gx < NM; gx = gx + 1) begin
            q6 = `N.m_port[gx*6 +: 6];
            if (`N.m_armed[gx] && !marm_d[gx] && act[q6]) begin
                n_cell[q6] = n_cell[q6] + 1;
                if (t_arm[q6] < 0.0) t_arm[q6] = now_ms(0);
                if (now_ms(0) > t_fb[q6]) begin n_late[q6] = n_late[q6] + 1; T_late = T_late + 1; end
                if (verbose) $display("  %9.3f  mon%0d arm  %o%s", now_ms(0), gx, q6, (now_ms(0) > t_fb[q6]) ? "  AFTER THE FIRST BREAK" : "");
            end
            if (`N.d_stb[gx] && `N.m_held[gx] && (`N.m_st[gx*2 +: 2] == 2'd1) && act[q6]) begin
                if (e_first[q6] < 0) e_first[q6] = `N.d_cnt[gx*4 +: 4];
                if (`N.d_cnt[gx*4 +: 4] < e_min[q6]) e_min[q6] = `N.d_cnt[gx*4 +: 4];
                if (verbose > 1) $display("  %9.3f  mon%0d %o e=%0d", now_ms(0), gx, q6, `N.d_cnt[gx*4 +: 4]);
            end
        end
        marm_d = `N.m_armed;
        if (`N.w_claim) begin
            q6 = `N.m_want_port;
            if (act[q6]) begin
                n_claim[q6] = n_claim[q6] + 1;
                if (!((se[q6] == 2) && (sb[q6] == 2))) begin
                    n_wrong[q6] = n_wrong[q6] + 1; T_wrong = T_wrong + 1;
                    $display("  %9.3f  WRONG CLAIM on %o: far caller dialled %0d %0d", now_ms(0), q6, se[q6], sb[q6]);
                end else T_claim_ok = T_claim_ok + 1;
            end else $display("  %9.3f  CLAIM on %o with no far seizure on it", now_ms(0), q6);
            if (verbose) $display("  %9.3f  CLAIM     %o", now_ms(0), q6);
        end
        if (`N.w_fwd && verbose)
            $display("  %9.3f  FWD       %o -> ok %b cand %o %o %o %o", now_ms(0), `N.f_in, `N.f_ok,
                     `N.f_cand[5:0], `N.f_cand[11:6], `N.f_cand[17:12], `N.f_cand[23:18]);
        if (`N.w_res && verbose > 1) $display("  %9.3f  RES act", now_ms(0));
        for (gx = 0; gx < NR; gx = gx + 1)
            if (`N.w_res && `N.rs_act1[gx] && (`N.rs_act[gx*2 +: 2] == 2'd1)) begin
                T_rleg = T_rleg + 1;
                $display("  %9.3f  RESOLVER %0d takes M on leg %0d as a claim (in %o)", now_ms(0), gx,
                         `N.rs_cl[gx*2 +: 2], `N.rs_in[gx*6 +: 6]);
            end
        if (cla && !cla_d) begin
            T_origin_claim = T_origin_claim + 1;
            $display("  %9.3f  ORIGIN takes M on its trunk %o as the claim (the bench never claims)", now_ms(0), `N.trunk);
        end
        cla_d = cla;
        // the marker
        if (`MK.r_attach) begin
            // r_attach and att_ack are set on the same edge by a claim's attach
            if (TR[`MK.r_port] && !`MK.att_ack) begin
                T_trunk_caller = T_trunk_caller + 1;
                $display("  %9.3f  MARKER TAKES TRUNK %o AS A CALLER", now_ms(0), `MK.r_port);
            end
            if (verbose) $display("  %9.3f  MK register -> %o%s", now_ms(0), `MK.r_port, `MK.att_ack ? " (claim)" : "");
        end
        if (`MK.att_refuse && (`MK.room >= 5'd1) && !(`MK.u_local || `MK.u_done || `MK.u_nogo)) begin
            T_refuse = T_refuse + 1;
            if (verbose) $display("  %9.3f  MK refuses the claim on %o", now_ms(0), `MK.u_att_port);
        end
        if ((`MK.state == 3'd4) && `MK.rd_done) begin
            if (TR[`MK.rd_port]) T_mk_rd_trunk = T_mk_rd_trunk + 1; else T_mk_rd_line = T_mk_rd_line + 1;
            if (verbose > 1) $display("  %9.3f  MK read    %o  word %b", now_ms(0), `MK.rd_port, `MK.rd_word);
        end
        // the sweep's length
        if (hunt && !hunt_d) t_sw0 = now_ms(0);
        if (!hunt && hunt_d) begin
            n_sweep = n_sweep + 1; sw_sum = sw_sum + (now_ms(0) - t_sw0);
            if (now_ms(0) - t_sw0 > sw_max) sw_max = now_ms(0) - t_sw0;
        end
        hunt_d = hunt;
        // the readers: request to select
        if (`MK.u_rd.rd_req) begin t_mreq = now_ms(0); mreq_p = 1'b1; end
        if (mreq_p && `MK.u_rd.ws_pd && `MK.u_rd.a_stb) begin
            mreq_p = 1'b0; n_mrd = n_mrd + 1; mrd_sum = mrd_sum + (now_ms(0) - t_mreq);
            if (now_ms(0) - t_mreq > mrd_max) mrd_max = now_ms(0) - t_mreq;
        end
        if (`N.u_rd.rd_req && !`N.rd_own) begin t_creq = now_ms(0); creq_p = 1'b1; end
        if (`N.u_rd.rd_req &&  `N.rd_own) creq_p = 1'b0;
        if (creq_p && `N.u_rd.ws_pd && `N.u_rd.a_stb) begin
            creq_p = 1'b0; n_crd = n_crd + 1; crd_sum = crd_sum + (now_ms(0) - t_creq);
            if (now_ms(0) - t_creq > crd_max) crd_max = now_ms(0) - t_creq;
        end
    end
    // once a millisecond: the classifier's occupancy and the backlog of
    // seizures showing M with BUSY clear that no hold has reached yet
    integer bq;
    always @(posedge t1k) if (rst_n) begin
        tot_ms = tot_ms + 1;
        if (`N.cst != 3'd0) cls_busy_ms = cls_busy_ms + 1;
        back_now = 0;
        for (bq = 0; bq < 64; bq = bq + 1)
            if (act[bq] && alive[bq] && (n_hold[bq] == 0)) back_now = back_now + 1;
        back_sum = back_sum + back_now;
        if (back_now > back_max) back_max = back_now;
    end

    // ---- dialling -------------------------------------------------------------
    task automatic fdial(input integer q, input integer d, input integer pause);
        integer n, i;
        begin n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                fa[q] = 1'b0; ms(BRK); fa[q] = 1'b1; ms(MKE);
            end
            ms(pause);
        end
    endtask
    task automatic dial(input integer p, input integer d);
        integer n, i;
        begin n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                hook[p] = 1'b0; ms(BRK); hook[p] = 1'b1; ms(MKE);
            end
            ms(DPAUSE);
        end
    endtask

    // ---- one far seizure, whole -----------------------------------------------
    // The report line is printed once the port and the monitors have let go.
    task automatic far_call(input integer q, input integer t1, input integer ee, input integer bb,
                            input integer id, input integer hold_on);
        begin
            clear_rec(q);
            sid[q] = id; se[q] = ee; sb[q] = bb; st1[q] = t1; sback[q] = back_now;
            act[q] = 1'b1; alive[q] = 1'b1;
            t_rise[q] = now_ms(0);
            fa[q] = 1'b1;
            ms(t1);
            t_fb[q] = now_ms(0);
            // ee = 0: a copy its origin drops at t1 (claimed elsewhere), no digits
            if (ee != 0) begin
                fdial(q, ee, DPAUSE); fdial(q, bb, DPAUSE);
                if ((ee == 2) && (bb == 2)) begin fdial(q, 2, DPAUSE); fdial(q, 1, 1000); end
                else ms(hold_on);
            end
            fa[q] = 1'b0; alive[q] = 1'b0;
            ms(P_T_REL + 40);
            $display("SZ id=%0d q=%o dir=%s t1=%0d e=%0d b=%0d back=%0d seen=%.1f hold=%.1f arm=%.1f nseen=%0d nhold=%0d nunh=%0d nunhlive=%0d ncell=%0d nlate=%0d efirst=%0d emin=%0d claim=%0d wrong=%0d",
                     id, q[5:0], (q < 16) ? "W" : "E", t1, ee, bb, sback[q],
                     (t_seen[q] < 0.0) ? -1.0 : t_seen[q] - t_rise[q],
                     (t_hold[q] < 0.0) ? -1.0 : t_hold[q] - t_rise[q],
                     (t_arm[q] < 0.0) ? -1.0 : t_arm[q] - t_rise[q],
                     n_seen[q], n_hold[q], n_unh[q], n_unh_live[q], n_cell[q], n_late[q],
                     e_first[q], (e_min[q] == 99) ? -1 : e_min[q], n_claim[q], n_wrong[q]);
            if (t_hold[q] >= 0.0) begin
                hist_rh[bin_rh(t_hold[q] - t_rise[q])] = hist_rh[bin_rh(t_hold[q] - t_rise[q])] + 1;
                if (q < 16) hist_rh_w[bin_rh(t_hold[q] - t_rise[q])] = hist_rh_w[bin_rh(t_hold[q] - t_rise[q])] + 1;
                else        hist_rh_e[bin_rh(t_hold[q] - t_rise[q])] = hist_rh_e[bin_rh(t_hold[q] - t_rise[q])] + 1;
            end
            if (n_cell[q] == 0) T_nocell = T_nocell + 1;
            act[q] = 1'b0;
        end
    endtask

    // ---- the load's far callers: one process a trunk, started by a request ----
    reg  [63:0] req = 64'd0;
    integer rq_t1 [0:63], rq_e [0:63], rq_b [0:63], rq_id [0:63], rq_ho [0:63];
    genvar gq;
    generate for (gq = 0; gq < 64; gq = gq + 1) begin : far
        if (TRX[gq]) begin : on
            initial forever begin
                @(posedge t1k);
                if (req[gq]) begin
                    far_call(gq, rq_t1[gq], rq_e[gq], rq_b[gq], rq_id[gq], rq_ho[gq]);
                    req[gq] = 1'b0;
                end
            end
        end
    end endgenerate

    // ---- the load's phones ----------------------------------------------------
    integer loc_mean = 8000, pnet = 300, lc_dur = 0;
    reg     load_on = 1'b0;
    task automatic phone_life(input integer p);
        real t0l, tdt;
        integer w, net;
        begin
            forever begin
                ms(expo(loc_mean));
                if (load_on) begin
                    hook[p] = 1'b1; t0l = now_ms(0); tdt = -1.0; T_lift = T_lift + 1;
                    w = 0;
                    while ((busy[p] !== 1'b1) && (w < 3000)) begin @(posedge t1k); w = w + 1; end
                    if (busy[p] === 1'b1) begin
                        tdt = now_ms(0) - t0l;
                        hist_dt[bin_dt(tdt)] = hist_dt[bin_dt(tdt)] + 1;
                    end else begin T_nodt = T_nodt + 1; hist_dt[9] = hist_dt[9] + 1; end
                    net = (uni(0, 999) < pnet);
                    $display("LC p=%o t=%.1f dt=%.2f net=%0d", p[5:0], t0l, tdt, net);
                    if (tdt >= 0.0) begin
                        ms(300);
                        if (net) begin dial(p, 1); dial(p, 5); dial(p, 5); dial(p, 2); dial(p, 1); ms(2500); end
                        else begin dial(p, 0); ms(1000); end
                    end
                    hook[p] = 1'b0;
                    ms(600);
                end
            end
        end
    endtask
    initial begin #1; fork phone_life(P20); phone_life(P22); phone_life(P23); phone_life(P32); join_none end

    // ---- the link glitch for sc8: the far clock stops so that the link is
    // down at the capture of frames y+5 and y+6 after a select at p's turn (y),
    // which carry bits 6 and 7 of p's octet when p's slot is 0 ------------------
    task glitch_bits67(input integer p);
        begin
            @(posedge clk);
            while (!(`N.u_rd.ws_pd && (S.u_x.scan == p[5:0]))) @(posedge clk);
            $display("  %9.3f  unit select of %o (marker %0d): glitching bits 6-7", now_ms(0), p[5:0], `MK.u_rd.ws_pd);
            frames(2); repeat (2) @(posedge clk); kill[p] = 1'b1;
            frames(4); repeat (50) @(posedge clk); kill[p] = 1'b0;
        end
    endtask

    integer mode, sc, maxms, lam, dur, t1lo, t1hi, pexp, pown, hold_on, seed, id, qq, dirp, ee, bb, k;
    real    t0;
    reg     found;

    initial begin
        if (!$value$plusargs("sc=%d", sc)) sc = 7;
        if (!$value$plusargs("v=%d", verbose)) verbose = 1;
        if (!$value$plusargs("lam=%d", lam)) lam = 4000;
        if (!$value$plusargs("dur=%d", dur)) dur = 20000;
        if (!$value$plusargs("t1lo=%d", t1lo)) t1lo = 60;
        if (!$value$plusargs("t1hi=%d", t1hi)) t1hi = 700;
        if (!$value$plusargs("pexp=%d", pexp)) pexp = 500;
        if (!$value$plusargs("pown=%d", pown)) pown = 100;
        if (!$value$plusargs("hold=%d", hold_on)) hold_on = 60;
        if (!$value$plusargs("loc=%d", loc_mean)) loc_mean = 8000;
        if (!$value$plusargs("pnet=%d", pnet)) pnet = 300;
        if (!$value$plusargs("seed=%d", seed)) seed = 1;
        if (!$value$plusargs("mode=%d", mode)) mode = 0;
        rs = rs ^ {32'd0, seed[31:0]} ^ ({32'd0, seed[31:0]} << 29);
        $display("\n  tb_cls3 sc=%0d NMON=%0d NRES=%0d T_ARM=%0d guard=%0d  lam=%0d/1000s dur=%0d t1=%0d..%0d pexp=%0d pown=%0d loc=%0d pnet=%0d seed=%0d mode=%0d",
                 sc, NM, NR, P_T_ARM, P_GUARD, lam, dur, t1lo, t1hi, pexp, pown, loc_mean, pnet, seed, mode);
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        ms(20);
        ck((up & TR) == TR, "every trunk's link is up");

        case (sc)
        // ======================================================================
        7: begin
            @(posedge t1k); repeat (100) @(posedge clk);
            t0 = now_ms(0);
            fork
                begin fa[8] = 1'b1; $display("  %9.3f  far seizure on 10", now_ms(0)); end
                begin ms(5); se[39] = 3; sb[39] = 2; act[39] = 1'b1; alive[39] = 1'b1; t_rise[39] = now_ms(0);
                      fa[39] = 1'b1; $display("  %9.3f  far seizure on 47 (dials 3 2 2 1, first break +128)", now_ms(0));
                      ms(128); t_fb[39] = now_ms(0);
                      fdial(39, 3, DPAUSE); fdial(39, 2, DPAUSE); fdial(39, 2, DPAUSE); fdial(39, 1, DPAUSE); end
                begin ms(10);  fa[9]  = 1'b1; $display("  %9.3f  far seizure on 11", now_ms(0));
                      ms(15);  fa[10] = 1'b1; $display("  %9.3f  far seizure on 12", now_ms(0));
                      ms(20);  fa[11] = 1'b1; $display("  %9.3f  far seizure on 13", now_ms(0));
                      ms(20);  fa[12] = 1'b1; $display("  %9.3f  far seizure on 14", now_ms(0));
                      ms(20);  fa[13] = 1'b1; $display("  %9.3f  far seizure on 15", now_ms(0));
                      ms(20);  fa[14] = 1'b1; $display("  %9.3f  far seizure on 16", now_ms(0)); end
            join
            ms(200);
            $display("  47: rise %.1f  seen +%.1f  hold +%.1f  cell +%.1f (first break at +%.1f)  e counted %0d  claims %0d",
                     t_rise[39], t_seen[39] - t_rise[39], t_hold[39] - t_rise[39],
                     (t_arm[39] < 0.0) ? -1.0 : t_arm[39] - t_rise[39], t_fb[39] - t_rise[39], e_first[39], n_claim[39]);
            ck(t_hold[39] - t_rise[39] < 30.0, "sc7: 47, seized second, is held within two watches of its rise");
            ck(n_claim[39] == 0, "sc7: a far caller dialling 3 2 2 1 is not claimed by exchange 2 2");
            fa = 64'd0; alive[39] = 1'b0;
            ms(REL * 2 + 300);
            act[39] = 1'b0;
        end
        // ======================================================================
        8: begin
            @(posedge t1k); repeat (100) @(posedge clk);
            fa[8] = 1'b1;
            $display("  %9.3f  far seizure on 10 (faces W)", now_ms(0));
            glitch_bits67(8);
            ms(40);
            $display("  %9.3f  classifier dir %0d; legs: W 11 a_out %0d, N 71 a_out %0d, S 30 a_out %0d, E 40 a_out %0d",
                     now_ms(0), `N.cls_dir, a_out[9], a_out[TN], a_out[TS], a_out[32]);
            ck(a_out[9] === 1'b0, "sc8: the flood is not sent back west, the way it came");
            ck(a_out[TN] === 1'b1, "sc8: the flood is sent north");
            fa = 64'd0;
            ms(REL * 2 + 300);
        end
        // ======================================================================
        9: begin
            hook[P20] = 1'b1; ms(10);
            fork
                dial(P20, 1);
                begin
                    while (!((`N.hst == 3'd1) && (`N.h_idx == 6'd17))) @(posedge clk);
                    fa[8] = 1'b1;
                    $display("  %9.3f  the sweep has read W 10 free: the far end seizes 10 (h_n %0d)", now_ms(0), `N.h_n);
                end
            join
            ms(20);
            $display("  %9.3f  origin nst %0d holds dirs %b trunks N %o S %o E %o W %o; W 11-17 busy %b",
                     now_ms(0), `N.nst, `N.d_held, `N.d_trunk[5:0], `N.d_trunk[11:6], `N.d_trunk[17:12],
                     `N.d_trunk[23:18], busy[15:9]);
            ck(`N.d_held[3] === 1'b1, "sc9: the origin seizes a W trunk while 7 of 8 are free");
            hook[P20] = 1'b0; fa = 64'd0;
            ms(REL * 2 + 300);
        end
        // ======================================================================
        10: begin
            id = 0;
            load_on = 1'b1;
            t0 = now_ms(0);
            while (now_ms(0) - t0 < dur) begin
                ms(expo(1000000 / lam));
                dirp = uni(0, 1);
                found = 1'b0;
                for (k = 0; (k < 16) && !found; k = k + 1) begin
                    // the far end hunts highest first: our words set no glare, so
                    // this unit hunts lowest first, and the two ends meet last
                    qq = ((k < 8) ? ((dirp == 0) ? 8 : 32) : ((dirp == 0) ? 32 : 8)) + 7 - (k % 8);
                    if (!act[qq] && !req[qq] && !busy[qq] && !a_out[qq]) found = 1'b1;
                end
                if (!found) begin T_blk = T_blk + 1; end
                else begin
                    k = uni(0, 999);
                    if (k < pexp)             begin ee = 3; bb = 2; end
                    else if (k < pexp + pown) begin ee = 2; bb = 2; end
                    else if (mode == 1)       begin ee = 0; bb = 0; end
                    else                      begin ee = uni(4, 7); bb = uni(4, 7); end
                    rq_t1[qq] = uni(t1lo, t1hi); rq_e[qq] = ee; rq_b[qq] = bb; rq_id[qq] = id; rq_ho[qq] = hold_on;
                    req[qq] = 1'b1; act[qq] = 1'b1; id = id + 1; T_sz = T_sz + 1;
                end
            end
            load_on = 1'b0;
            // drain: every far call ends, every phone hangs up
            while (req != 64'd0) @(posedge t1k);
            while (hook != 64'd0) @(posedge t1k);
            ms(5000);
            $display("\nSUMMARY floods=%0d blocked=%0d wrong_claims=%0d ok_claims=%0d late_cells=%0d hold_after_first_break=%0d unhold_live=%0d reclass=%0d trunk_as_caller=%0d refusals=%0d origin_claims=%0d resolver_leg_claims=%0d seizures_without_cell=%0d n_nofwd=%0d",
                     T_sz, T_blk, T_wrong, T_claim_ok, T_late, T_hold_after_fb, T_unh_live, T_reclass, T_trunk_caller,
                     T_refuse, T_origin_claim, T_rleg, T_nocell, nnf);
            $display("SUMMARY cls_busy=%0d/%0d ms backlog_mean=%.3f backlog_max=%0d mk_reads trunk=%0d line=%0d",
                     cls_busy_ms, tot_ms, back_sum * 1.0 / tot_ms, back_max, T_mk_rd_trunk, T_mk_rd_line);
            $display("SUMMARY sweeps=%0d mean=%.2f max=%.2f ms; marker read req->select n=%0d mean=%.2f max=%.2f ms; cls read req->select n=%0d mean=%.2f max=%.2f ms",
                     n_sweep, (n_sweep > 0) ? sw_sum / n_sweep : 0.0, sw_max, n_mrd, (n_mrd > 0) ? mrd_sum / n_mrd : 0.0, mrd_max,
                     n_crd, (n_crd > 0) ? crd_sum / n_crd : 0.0, crd_max);
            $display("SUMMARY lifts=%0d nodt=%0d", T_lift, T_nodt);
            $display("HIST rise->hold  <2 <5 <20 <40 <60 <100 <150 <250 <500 more: all %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",
                     hist_rh[0], hist_rh[1], hist_rh[2], hist_rh[3], hist_rh[4], hist_rh[5], hist_rh[6], hist_rh[7], hist_rh[8], hist_rh[9]);
            $display("HIST rise->hold W(low ports)  %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",
                     hist_rh_w[0], hist_rh_w[1], hist_rh_w[2], hist_rh_w[3], hist_rh_w[4], hist_rh_w[5], hist_rh_w[6], hist_rh_w[7], hist_rh_w[8], hist_rh_w[9]);
            $display("HIST rise->hold E(high ports) %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",
                     hist_rh_e[0], hist_rh_e[1], hist_rh_e[2], hist_rh_e[3], hist_rh_e[4], hist_rh_e[5], hist_rh_e[6], hist_rh_e[7], hist_rh_e[8], hist_rh_e[9]);
            $display("HIST dialtone <5 <10 <20 <50 <100 <250 <500 <1000 <3000 none: %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",
                     hist_dt[0], hist_dt[1], hist_dt[2], hist_dt[3], hist_dt[4], hist_dt[5], hist_dt[6], hist_dt[7], hist_dt[8], hist_dt[9]);
            ck(T_wrong == 0 && T_trunk_caller == 0 && T_origin_claim == 0, "sc10: no wrong claim, no trunk taken as a caller, no stranger as an origin's claim");
            ck(busy == 64'd0 && !rbusy && mks == 3'd0 && dirs == 4'd0 && resb == {NR{1'b0}} &&
               monh == {NM{1'b0}} && !hunt && `N.cst == 3'd0 && `N.fst == 2'd0 && `N.nst == 4'd0,
               "sc10: after the drain nothing is held");
            if (busy != 64'd0) $display("      busy ports %h", busy);
            $display("      reg %0d mk %0d dirs %b res %b mon %b hunt %0d cst %0d fst %0d nst %0d",
                     rbusy, mks, dirs, resb, monh, hunt, `N.cst, `N.fst, `N.nst);
        end
        // ======================================================================
        11: begin
            // a sub-HIT dip of the far M (3 ms, a link hit) 8 ms after the
            // rise, inside the C_HOLD watch; then the far caller dials OUR code
            // 2 2 and h s = 2 1.  One call: one claim, no refusal, 21 rings.
            @(posedge t1k); repeat (100) @(posedge clk);
            se[8] = 2; sb[8] = 2; act[8] = 1'b1; alive[8] = 1'b1; t_rise[8] = now_ms(0);
            fa[8] = 1'b1;
            $display("  %9.3f  far seizure on 10", now_ms(0));
            ms(8); fa[8] = 1'b0; ms(3); fa[8] = 1'b1;
            $display("  %9.3f  3 ms dip over", now_ms(0));
            ms(117); t_fb[8] = now_ms(0);
            fdial(8, 2, DPAUSE); fdial(8, 2, DPAUSE); fdial(8, 2, DPAUSE); fdial(8, 1, DPAUSE);
            ms(300);
            $display("  %9.3f  10: held %0d times, unheld %0d, cells %0d, claims %0d; refusals %0d; 10 latch -> %o; 21 rung %0d",
                     now_ms(0), n_hold[8], n_unh[8], n_cell[8], n_claim[8], T_refuse,
                     S.u_x.u_exch.pos[1].u_blk.u_port0.addr, S.u_x.u_exch.pos[2].u_blk.u_port1.rb);
            ck(n_claim[8] <= 1, "sc11: one call, one claim");
            ck(T_refuse == 0, "sc11: the owner does not refuse the call it took");
            fa = 64'd0; alive[8] = 1'b0;
            ms(REL * 2 + 300);
            act[8] = 1'b0;
        end
        default: ;
        endcase

        ck(!clash && !mko && !uno, "no cable-B clash, no queue refused a write");
        $display("\n  %0d checks, %0d errors.  %s\n", chk, errs, (errs == 0) ? "PASS" : "FAIL");
        $finish;
    end

    initial begin
        if (!$value$plusargs("maxms=%d", maxms)) maxms = 8000;
        #(maxms * 1.0e6); $display("  WATCHDOG at %0d ms", maxms); $finish;
    end

    wire _unused = &{1'b0, rcad, sd, sclk_b, wrb, c_out, rx, tx, e, ngl, 1'b0};
endmodule
