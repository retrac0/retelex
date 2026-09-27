// tb_c03r -- VERIFY scratch bench for C03 finding rc-tolerance-reseize, REAL
// timers.  A variant of tb_c03g.  Not part of the tree.
//
// A's port release detectors are built with T_REL = TRELA (default 200 ms, an
// RC 22% short of its 256 ms nominal); X's are nominal, and X's monitor cells
// count CLR = 256 ms exactly.  A20 keys 1, A seizes A11/A12, and A20 hangs up
// HU ms after the seizure (inside A's guard, after T_ARM): A abandons and drops
// A11, which stays BUSY at A until its fE falls, TRELA after the break.  Y
// seizes A13 RS ms after the break; A forwards it east on A11, the moment
// A11 is free -- before X's port and X's cell have let the old seizure go.
// Y's caller dials 3 2 2 1.  Correct: X does not claim.
//
// Below: the original tb_c03g header.
//
// tb_c03g -- VERIFY scratch bench for C03 (the stale monitor cell), with a
// CONFORMING trigger and REAL timers.  Not part of the tree.
//
// Exchange A (code 2 2) and exchange X (code 1 3, a backbone code by
// numbering.md 5's convention), one baseband tie A11-X11 (A's card faces E,
// X's faces W).  A also has A12 and A13 facing W, whose far ends are the
// BENCH, standing for a western exchange Y.  Phones 20-27 at both.
//
//   A20 keys 1 with ordinary timing.  A's origin seizes A11 (E) and A12 (W).
//   GLARE: Y seizes the same channel of A12 GL ms after A did (it swept the
//     channel free just before A's M reached it).  A takes Y's M as the claim
//     (counted as glare) and drops A11 at once.  A11 stood a millisecond or
//     two: X holds it, gives it a monitor cell, and writes the hold away
//     inside T_ARM (C_UNHOLD); the cell stays.
//   RE-SEIZURE: RS ms later Y forwards an unrelated flood to A on A13.  A
//     forwards it east on the lowest free trunk -- A11 again.
//   The far caller of that flood dials 3 2 2 1 with a conforming dial
//     (10 pps 60/40, 800 ms between digits, first break +PAUSE0 after the
//     seizure): exchange 32 (not present), line 21.
//
// Correct: X does not claim; nothing at X rings.
// Hypothesis (C03): X's stale cell counts the gap as one pulse and the
// re-seizure's make as the digit 1 -- X's e -- then hears 3 as X's b and
// claims; X's register reads 2 2 and X22 rings.
//
// +gl=N (default 2) +rs=N (default 60) +p0=N (default 600)
`timescale 1ns/1ps
`include "exch.vh"

`ifndef TRELA
`define TRELA 200
`endif
module tb_c03r;
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

    localparam [`PW-1:0] T11 = 6'o11, T12 = 6'o12, T13 = 6'o13,
                         P20 = 6'o20, P21 = 6'o21, P22 = 6'o22;
    localparam [7:0] WE = {2'd2, 1'b0, 3'b010, 2'b11};
    localparam [7:0] WW = {2'd3, 1'b0, 3'b010, 2'b11};
    localparam [63:0] TRA = (64'd1 << T11) | (64'd1 << T12) | (64'd1 << T13);
    localparam [511:0] TWA = ({504'd0, WE} << (8*T11)) | ({504'd0, WW} << (8*T12)) |
                             ({504'd0, WW} << (8*T13));

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
    // A11 <-> X11 cabled; A12, A13 to the bench (their own clock looped back)
    wire [63:0] ac_in = {54'd0, xc_out[T11], 9'd0};
    wire [63:0] aa_in = ({54'd0, xa_out[T11], 9'd0}) | (far_m & ((64'd1 << T12) | (64'd1 << T13)));
    wire [63:0] ak_in = ({54'd0, xk_out[T11], 9'd0}) | (ak_out & ((64'd1 << T12) | (64'd1 << T13)));
    wire [63:0] xc_in = {54'd0, ac_out[T11], 9'd0}, xa_in = {54'd0, aa_out[T11], 9'd0},
                xk_in = {54'd0, ak_out[T11], 9'd0};

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

    wire [1:0]  xm_held  = X.u_x.u_net.m_held;
    wire [11:0] xm_port  = X.u_x.u_net.m_port;
    wire [3:0]  xm_st    = X.u_x.u_net.m_st;
    wire [7:0]  xd_cnt   = X.u_x.u_net.d_cnt;
    wire [2:0]  x_cst    = X.u_x.u_net.cst;
    wire [3:0]  a_nst    = A.u_x.u_net.nst;
    wire [1:0]  a_fst    = A.u_x.u_net.fst;
    wire [127:0] tr = {busy_a[T13:T11], busy_x[T11], xa_out[T11], aa_out[T13:T11], xm_held, xm_port,
                       xm_st, xd_cnt, x_cst, a_nst, a_fst, res_a, cla_a, gl_a, reg_x, mks_x,
                       busy_x[23:16], far_m[T13:T12]};
    reg [127:0] tr_d = 128'd0;
    always @(posedge clk_a) begin
        tr_d <= tr;
        if (rst_n && tr != tr_d)
            $display("  [%5d ms] A busy13..11=%b X11 busy=%b bkA=%b | A a_out13..11=%b Y M13,12=%b | X cells held=%b port=%o/%o st=%0d/%0d cnt=%0d/%0d cls=%0d | A origin=%0d claimed=%b glare#=%0d fwd=%0d res=%b | X reg=%b mk=%0d X2x busy=%b",
                     now, busy_a[T13:T11], busy_x[T11], xa_out[T11], aa_out[T13:T11], far_m[T13:T12],
                     xm_held, xm_port[11:6], xm_port[5:0], xm_st[3:2], xm_st[1:0],
                     xd_cnt[7:4], xd_cnt[3:0], x_cst,
                     a_nst, cla_a, gl_a, a_fst, res_a, reg_x, mks_x, busy_x[23:16]);
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

    integer gl, rs, p0, t_seize, t_drop, t_rs, saw_cell, bk13, rng;
    // did X ever hand a cell to X11 during the glare seizure, and keep it
    always @(posedge clk_x) if (rst_n && saw_cell == 0 &&
        ((xm_held[0] && xm_port[5:0] == T11) || (xm_held[1] && xm_port[11:6] == T11))) saw_cell = now;

    initial begin
        saw_cell = 0;
        if (!$value$plusargs("gl=%d", gl)) gl = 50;
        if (!$value$plusargs("rs=%d", rs)) rs = `TRELA + 2;
        if (!$value$plusargs("p0=%d", p0)) p0 = 600;
        $display("\n  tb_c03r -- abandon after T_ARM, A's T_REL=%0d, re-seizure by a transit forward, real timers: hu=%0d rs=%0d p0=%0d", `TRELA, gl, rs, p0);
        repeat (20) @(posedge clk_a);
        rst_n = 1'b1;
        ms(30);
        ck(up_a[T11] && up_x[T11] && up_a[T12] && up_a[T13], "the links are up");

        hook_a[P20] = 1'b1; ms(400);                       // dial tone, a human pause
        ck(reg_a, "A20 has A's register");
        hook_a[P20] = 1'b0; ms(60); hook_a[P20] = 1'b1;     // keys 1
        while (busy_a[T11] !== 1'b1) @(posedge clk_a);     // A's seizure of A11 is written
        t_seize = now;
        $display("    A seized A11/A12 at %0d ms", now);
        ms(gl);                                            // +gl: here, the hang-up time
        hook_a[P20] = 1'b0;                                // A20 hangs up inside the guard
        t_drop = now;
        $display("    A20 hung up at %0d ms (%0d ms after the seizure)", now, now - t_seize);
        while (busy_a[T11] !== 1'b0) @(posedge clk_a);
        $display("    A11 free at A at %0d ms (%0d ms after the break)", now, now - t_drop);
        ck((xm_held[0] && xm_port[5:0] == T11) || (xm_held[1] && xm_port[11:6] == T11),
           "OBSERVE: X's cell on X11 still counting when A11 frees at A");
        ck(busy_x[T11] === 1'b1, "OBSERVE: X11 still held when A11 frees at A");
        while (now < t_drop + rs) @(posedge clk_a);
        far_m[T13] = 1'b1;                                 // Y forwards another flood to A
        while (busy_a[T11] !== 1'b1) @(posedge clk_a);
        t_rs = now;
        $display("    A re-seized A11 (forward of A13) at %0d ms, %0d ms after the break", now, now - t_drop);
        ms(20);
        $display("    X cells held=%b ports %o/%o, X11 busy=%b", xm_held, xm_port[11:6], xm_port[5:0], busy_x[T11]);
        ms(p0 - 20);
        fdial(3);                                          // e = 3: exchange 3x
        bk13 = aa_out[T13];
        ck(xa_out[T11] === 1'b0 && bk13 == 0, "SAFETY: X (13) does not claim a flood dialled to exchange 3x");
        ck(!reg_x, "SAFETY: X's register is not attached");
        fdial(2);                                          // b = 2
        fdial(2); fdial(1); ms(100);                       // h s = 2 1
        rng = busy_x[P22] && !hook_x[P22];
        $display("    X2x busy=%b (X22 is bit 2)", busy_x[23:16]);
        ck(!rng, "SAFETY: X22 is not rung by a flood dialled 1 3 2 2 1");
        far_m[T13] = 1'b0; far_m[T12] = 1'b0; hook_a[P20] = 1'b0;
        ms(1500);
        ck(busy_a == 64'd0 && busy_x == 64'd0 && !reg_a && !reg_x && mon_x == 2'd0 && mon_a == 2'd0,
           "and afterwards both exchanges are idle");
        ck(!cl_a && !cl_x && !mko_a && !mko_x && !uno_a && !uno_x, "no bus clash, no queue refusal (last sample)");
        $display("\n  %0d checks, %0d errors.  %s\n", chk, errs, (errs == 0) ? "PASS" : "FAIL");
        $finish;
    end

    initial begin #40_000_000_000; $display("  TIMEOUT"); $finish; end
    wire _unused = &{1'b0, e_a, e_x, rx_a, rx_x, fs_a, fs_x, t1k_x, rc_a, rc_x, cla_x, dirs_a, dirs_x,
                     res_x, gl_x, nf_a, nf_x, tx_a, tx_x, mks_x, up_x, 1'b0};
endmodule
