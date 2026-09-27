// tb_c20r -- VERIFY scratch bench for C20 finding release-margin-thin, REAL
// timers.  Derived from work/verify/C03-stale-monitor-cell/tb_c03r.v.  Not
// part of the tree.
//
// Exchange A (code 2 2) and exchange X (code 1 3), one baseband tie: A's
// port TA (`TA, default 11; its card faces E) to X11 (faces W).  A also has
// A12 and A13 facing W, whose far ends are the BENCH (a western exchange Y).
// Phones 20-27 at both.
//
// A's port detectors have T_REL = `TRELA (the RC, nominal 256); X's are
// nominal.  +fd=<us> delays every FALL of A on the wire A->X (TA to X11) by
// that much and no rise: a carrier that shortens breaks (network.md 1.1 lets
// a pots tie do 5-10 ms a hop, MF8 0.5).
//
// One attempt: A20 keys 1, A seizes TA (E) and A12 (W); A20 hangs up +hu ms
// after the seizure (inside A's guard, after T_ARM) and A abandons, dropping
// TA, which stays BUSY at A until its fE falls, TRELA after the break.  Y
// seizes A13 +rs ms after the break; A forwards it east on TA, the moment the
// sweep finds TA free.
//
// FULL mode (default): Y's caller dials 1 3 2 2 -- exchange X, line 22.
// Correct: X claims (Y sees backward A on A13) and X22 rings.
// SCAN mode (+scan=1): no dialling; attempts with rs = +rs0 .. +rs1, each
// measuring when X11 frees at X against when the re-seizure's M reaches X11.
`timescale 1ns/1ps
`include "exch.vh"

`ifndef TRELA
`define TRELA 256
`endif
`ifndef TA
`define TA 6'o11
`endif
module tb_c20r;
    integer chk = 0, errs = 0;
    task ck(input cond, input [8*88-1:0] what);
        begin chk = chk + 1;
             if (!cond) begin errs = errs + 1; $display("    FAIL  %0s", what); end
             else $display("    ok    %0s", what);
        end
    endtask

    reg clk_a = 1'b0, clk_x = 1'b0, rst_n = 1'b0;
    always #122.070 clk_a = ~clk_a;
    initial begin #40; forever #(122.070 * 1.00005) clk_x = ~clk_x; end

    localparam [`PW-1:0] TA = `TA, T11 = 6'o11, T12 = 6'o12, T13 = 6'o13,
                         P20 = 6'o20, P21 = 6'o21, P22 = 6'o22;
    localparam [7:0] WE = {2'd2, 1'b0, 3'b010, 2'b11};
    localparam [7:0] WW = {2'd3, 1'b0, 3'b010, 2'b11};
    localparam [63:0] TRA = (64'd1 << TA) | (64'd1 << T12) | (64'd1 << T13);
    localparam [511:0] TWA = ({504'd0, WE} << (8*TA)) | ({504'd0, WW} << (8*T12)) |
                             ({504'd0, WW} << (8*T13));
    localparam [63:0] YM = (64'd1 << T12) | (64'd1 << T13);

    reg  [63:0] hook_a = 64'd0, tx_a = 64'd0, hook_x = 64'd0, tx_x = 64'd0;
    reg  [63:0] far_m = 64'd0;                           // Y's M on A12, A13
    wire [63:0] rx_a, e_a, rx_x, e_x, busy_a, busy_x;
    wire [63:0] ac_out, aa_out, ak_out, xc_out, xa_out, xk_out, up_a, up_x;
    wire        fs_a, fs_x, t1k_a, t1k_x, rc_a, rc_x, cl_a, cl_x;
    wire        reg_a, reg_x, mko_a, mko_x, cla_a, cla_x, uno_a, uno_x;
    wire [2:0]  mks_a, mks_x;
    wire [3:0]  dirs_a, dirs_x;
    wire [1:0]  res_a, res_x, mon_a, mon_x;
    wire [7:0]  gl_a, gl_x, nf_a, nf_x;
    wire [7:0]  lz8 = 8'd0;

    // ---- the tie, with an optional fall delay on A -> X ----------------------
    integer fd_us = 0, fd_t = 0;
    integer lowcnt = 32'h7fffffff;
    wire a2x_raw = aa_out[TA];
    always @(posedge clk_a) begin
        if (a2x_raw) lowcnt <= 0;
        else if (lowcnt != 32'h7fffffff) lowcnt <= lowcnt + 1;
    end
    wire a2x_a = a2x_raw || (lowcnt < fd_t);

    wire [63:0] ac_in = ({63'd0, xc_out[T11]} << TA);
    wire [63:0] aa_in = ({63'd0, xa_out[T11]} << TA) | (far_m & YM);
    wire [63:0] ak_in = ({63'd0, xk_out[T11]} << TA) | (ak_out & YM);
    wire [63:0] xc_in = ({63'd0, ac_out[TA]} << T11);
    wire [63:0] xa_in = ({63'd0, a2x_a} << T11);
    wire [63:0] xk_in = ({63'd0, ak_out[TA]} << T11);

    site_net #(.PHONES(64'h0000_0000_00FF_0000), .TRUNKS(TRA), .TWORD(TWA),
               .OWN_E(3'd2), .OWN_B(3'd2), .T_REL(`TRELA)) A (
        .clk(clk_a), .rst_n(rst_n), .hook(hook_a), .tx(tx_a), .rx(rx_a), .e(e_a),
        .c_out(ac_out), .a_out(aa_out), .clk_out(ak_out),
        .c_in(ac_in), .a_in(aa_in), .clk_in(ak_in), .link_up(up_a),
        .lt_c_out(), .lt_a_out(), .lt_h_out(), .lt_k_out(),
        .lt_c_in(lz8), .lt_a_in(lz8), .lt_h_in(lz8), .lt_k_in(lz8), .lt_up(),
        .frame_stb(fs_a), .tick_1k(t1k_a), .ring_cad_n(rc_a), .port_busy(busy_a),
        .b_sdata(), .b_sclk(), .b_wr(), .b_clash(cl_a),
        .reg_busy(reg_a), .mk_state(mks_a), .mk_ovf(mko_a), .dirs_held(dirs_a),
        .res_busy(res_a), .mon_held(mon_a), .claimed(cla_a), .hunting(),
        .un_ovf(uno_a), .n_glare(gl_a), .n_nofwd(nf_a));

    site_net #(.PHONES(64'h0000_0000_00FF_0000), .TRUNKS(64'd1 << T11),
               .TWORD({504'd0, WW} << (8*T11)), .OWN_E(3'd1), .OWN_B(3'd3)) X (
        .clk(clk_x), .rst_n(rst_n), .hook(hook_x), .tx(tx_x), .rx(rx_x), .e(e_x),
        .c_out(xc_out), .a_out(xa_out), .clk_out(xk_out),
        .c_in(xc_in), .a_in(xa_in), .clk_in(xk_in), .link_up(up_x),
        .lt_c_out(), .lt_a_out(), .lt_h_out(), .lt_k_out(),
        .lt_c_in(lz8), .lt_a_in(lz8), .lt_h_in(lz8), .lt_k_in(lz8), .lt_up(),
        .frame_stb(fs_x), .tick_1k(t1k_x), .ring_cad_n(rc_x), .port_busy(busy_x),
        .b_sdata(), .b_sclk(), .b_wr(), .b_clash(cl_x),
        .reg_busy(reg_x), .mk_state(mks_x), .mk_ovf(mko_x), .dirs_held(dirs_x),
        .res_busy(res_x), .mon_held(mon_x), .claimed(cla_x), .hunting(),
        .un_ovf(uno_x), .n_glare(gl_x), .n_nofwd(nf_x));

    integer now = 0;
    always @(posedge t1k_a) now = now + 1;

    // ---- what X sees ---------------------------------------------------------
    wire        x11_m    = X.s_a[T11];                   // X11's M, at the socket
    wire [2:0]  x_cst    = X.u_x.u_net.cst;
    wire [5:0]  x_clsp   = X.u_x.u_net.cls_port;
    wire [1:0]  xm_held  = X.u_x.u_net.m_held;
    wire [11:0] xm_port  = X.u_x.u_net.m_port;
    wire [3:0]  a_nst    = A.u_x.u_net.nst;
    wire [1:0]  a_fst    = A.u_x.u_net.fst;
    // A's classifier, forwarder and sweep, for the log
    wire [2:0]  a_cst    = A.u_x.u_net.cst;
    wire [5:0]  a_clsp   = A.u_x.u_net.cls_port;
    wire [2:0]  a_hst    = A.u_x.u_net.hst;
    wire [3:0]  a_hok    = A.u_x.u_net.h_ok;
    wire [1:0]  a_rsb    = A.u_x.u_net.rs_busy;
    reg  [2:0]  a_cst_d = 3'd0, a_hst_d = 3'd0;
    reg  [1:0]  a_fst_d = 2'd0;
    reg  [7:0]  nf_a_d = 8'd0;
    always @(posedge clk_a) begin
        a_cst_d <= a_cst; a_hst_d <= a_hst; a_fst_d <= a_fst; nf_a_d <= nf_a;
        if (rst_n && (a_cst != a_cst_d || a_hst != a_hst_d || a_fst != a_fst_d || nf_a != nf_a_d))
            $display("  [%5d ms] A cls %0d(port %o) fwd %0d sweep %0d h_ok=%b res=%b nofwd=%0d TA busy=%b A13 busy=%b",
                     now, a_cst, a_clsp, a_fst, a_hst, a_hok, a_rsb, nf_a, busy_a[TA], busy_a[T13]);
    end
    // X's classifier writing a hold on X11 (C_ACT -> C_HOLD with cls_port 11)
    integer n_hold_x11 = 0;
    reg [2:0] x_cst_d = 3'd0;
    always @(posedge clk_x) begin
        x_cst_d <= x_cst;
        if (rst_n && x_cst == 3'd3 && x_cst_d != 3'd3 && x_clsp == T11) begin
            n_hold_x11 = n_hold_x11 + 1;
            $display("  [%5d ms] X holds X11 as a fresh seizure (hold #%0d)", now, n_hold_x11);
        end
    end
    // edges, in ns
    realtime t_xfree = 0, t_xm = 0, t_aseize = 0, t_afree = 0;
    reg busy_x11_d = 1'b0, x11_m_d = 1'b0, busy_a_ta_d = 1'b0;
    always @(posedge clk_x) begin
        busy_x11_d <= busy_x[T11]; x11_m_d <= x11_m;
        if (rst_n && busy_x11_d && !busy_x[T11]) begin
            t_xfree = $realtime; $display("  [%5d ms] X11 free at X", now);
        end
        if (rst_n && !x11_m_d && x11_m) begin
            t_xm = $realtime; $display("  [%5d ms] X11 M rises (X11 busy=%b)", now, busy_x[T11]);
        end
        if (rst_n && x11_m_d && !x11_m) $display("  [%5d ms] X11 M falls", now);
    end
    always @(posedge clk_a) begin
        busy_a_ta_d <= busy_a[TA];
        if (rst_n && busy_a_ta_d && !busy_a[TA]) begin
            t_afree = $realtime; $display("  [%5d ms] A's TA free at A", now);
        end
        if (rst_n && !busy_a_ta_d && busy_a[TA]) begin
            t_aseize = $realtime; $display("  [%5d ms] A's TA seized", now);
        end
    end

    task ms(input integer n); begin repeat (n) @(posedge t1k_a); end endtask
    // the far caller of Y's flood, on A13, as Y's trunk puts it on the wire
    task fdial(input integer d);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                far_m[T13] = 1'b0; ms(60);
                far_m[T13] = 1'b1; ms(40);
            end
            ms(800);
        end
    endtask

    integer hu, rs, rs0, rs1, p0, scan, t_seize, t_drop, bk13, rng, tries, nn;
    realtime mg;
    // one abandoned seizure of TA: returns with t_drop set
    task abandon;
        begin
            hook_a[P20] = 1'b1; ms(400);                       // dial tone, a human pause
            ck(reg_a, "A20 has A's register");
            hook_a[P20] = 1'b0; ms(60); hook_a[P20] = 1'b1;     // keys 1
            while (busy_a[TA] !== 1'b1) @(posedge clk_a);      // A's seizure of TA is written
            t_seize = now;
            $display("    A seized TA/A12 at %0d ms", now);
            ms(hu);
            hook_a[P20] = 1'b0;                                // A20 hangs up inside the guard
            t_drop = now;
            $display("    A20 hung up at %0d ms (%0d ms after the seizure)", now, now - t_seize);
        end
    endtask

    initial begin
        if (!$value$plusargs("hu=%d", hu)) hu = 50;
        if (!$value$plusargs("rs=%d", rs)) rs = `TRELA + 2;
        if (!$value$plusargs("p0=%d", p0)) p0 = 600;
        if (!$value$plusargs("scan=%d", scan)) scan = 0;
        if (!$value$plusargs("rs0=%d", rs0)) rs0 = `TRELA - 12;
        if (!$value$plusargs("rs1=%d", rs1)) rs1 = `TRELA + 2;
        if (!$value$plusargs("fd=%d", fd_us)) fd_us = 0;
        fd_t = (fd_us * 4096) / 1000;
        $display("\n  tb_c20r -- drop then re-seize, real timers: TA=%o A T_REL=%0d fd=%0d us hu=%0d rs=%0d scan=%0d",
                 TA, `TRELA, fd_us, hu, rs, scan);
        repeat (20) @(posedge clk_a);
        rst_n = 1'b1;
        ms(30);
        ck(up_a[TA] && up_x[T11] && up_a[T12] && up_a[T13], "the links are up");

        if (scan == 0) begin
            abandon;
            while (now < t_drop + rs) @(posedge clk_a);
            far_m[T13] = 1'b1;                                 // Y forwards another flood to A
            nn = 0;
            while (busy_a[TA] !== 1'b1 && nn < 40) begin ms(1); nn = nn + 1; end
            $display("    A re-seized TA (forward of A13): %0s, %0d ms after the break; X11 busy=%b",
                     busy_a[TA] ? "yes" : "NO", now - t_drop, busy_x[T11]);
            ms(p0 - nn);
            fdial(1);                                          // e = 1
            fdial(3);                                          // b = 3: exchange 1 3 = X
            bk13 = aa_out[T13];
            ck(bk13 == 1, "X claims the flood dialled to it: Y sees backward A on A13");
            ck(reg_x, "X's register is attached");
            fdial(2); fdial(2); ms(100);                       // h s = 2 2
            rng = busy_x[P22] && !hook_x[P22];
            $display("    X2x busy=%b (X22 is bit 2); X holds of X11 as fresh=%0d", busy_x[23:16], n_hold_x11);
            ck(rng, "X22 is rung by the flood dialled 1 3 2 2");
            far_m[T13] = 1'b0; far_m[T12] = 1'b0; hook_a[P20] = 1'b0;
            ms(1500);
            ck(busy_a == 64'd0 && busy_x == 64'd0 && !reg_a && !reg_x && mon_x == 2'd0 && mon_a == 2'd0,
               "and afterwards both exchanges are idle");
        end else begin
            for (tries = rs0; tries <= rs1; tries = tries + 1) begin
                t_xfree = 0; t_xm = 0; t_aseize = 0; t_afree = 0;
                abandon;
                while (now < t_drop + tries) @(posedge clk_a);
                far_m[T13] = 1'b1;
                nn = 0;
                // a NEW seizure of TA: after it freed (TA may still be BUSY from the
                // abandoned call when Y's M rises)
                while (!(busy_a[TA] === 1'b1 && t_afree > 0 && t_aseize > t_afree) && nn < 40) begin
                    ms(1); nn = nn + 1;
                end
                ms(30);                                        // Y's M stands past T_ARM
                if (!(t_afree > 0 && t_aseize > t_afree))
                    $display("  SCAN rs=%0d: NOT re-seized", tries);
                else if (t_xfree > t_xm || t_xfree == 0)
                    $display("  SCAN rs=%0d: COLLISION: re-seizure M at X11 %.3f ms BEFORE X11 freed (A free->seize %.3f ms)",
                             tries, (t_xfree == 0 ? 0.0 : (t_xfree - t_xm) / 1.0e6), (t_aseize - t_afree) / 1.0e6);
                else
                    $display("  SCAN rs=%0d: safe, margin %.3f ms (X11 free -> re-seizure M at X11); A free->seize %.3f ms; X free - A free %.3f ms",
                             tries, (t_xm - t_xfree) / 1.0e6, (t_aseize - t_afree) / 1.0e6, (t_xfree - t_afree) / 1.0e6);
                far_m[T13] = 1'b0; far_m[T12] = 1'b0;
                ms(900);
                nn = 0;
                while ((busy_a != 64'd0 || busy_x != 64'd0 || reg_a || reg_x || mon_x != 2'd0) && nn < 2000) begin
                    ms(1); nn = nn + 1;
                end
                if (nn >= 2000) $display("  SCAN: not idle after the attempt: busy_a=%h busy_x=%h", busy_a, busy_x);
            end
        end
        ck(!cl_a && !cl_x && !mko_a && !mko_x && !uno_a && !uno_x, "no bus clash, no queue refusal (last sample)");
        $display("\n  %0d checks, %0d errors.  %s\n", chk, errs, (errs == 0) ? "PASS" : "FAIL");
        $finish;
    end

    initial begin #120_000_000_000; $display("  TIMEOUT"); $finish; end
    wire _unused = &{1'b0, e_a, e_x, rx_a, rx_x, fs_a, fs_x, t1k_x, rc_a, rc_x, cla_x, dirs_a, dirs_x,
                     res_x, gl_x, nf_a, nf_x, tx_a, tx_x, mks_x, up_x, xm_held, xm_port, a_nst, a_fst,
                     cla_a, gl_a, res_a, mks_a, 1'b0};
endmodule
