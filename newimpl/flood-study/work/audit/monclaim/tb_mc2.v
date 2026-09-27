// tb_mc2 -- AUDIT scratch bench: the stale monitor cell, END TO END, at REAL
// timers.  Not part of the tree.
//
// Exchange A (code 2 2) and exchange X (code 1 3), one baseband tie A11-X11:
// A's card faces E, X's faces W.  Phones 20-27 at both.  All timers are the
// board's (T_ARM 16, T_REL 256, HIT 8, ID 128, CLR 256, guard 128, T_CLAIM
// 2000); a dial at 10 pps 60/40.
//
//   A20 keys 1; A seizes A11; A20's next break comes at once -- the guard
//     abandons, and A11 is let go ~10 ms after it was seized, inside T_ARM.
//     X held the seizure, gave it a monitor cell, and writes its hold away
//     (C_UNHOLD) -- the cell stays held, counting.
//   A21 was waiting for A's one register.  It gets it, and keys 1 at once:
//     A seizes A11 again ~200 ms later -- inside the stale cell's CLR.
//   A21 dials 3 2 2 1: exchange 32 (which does not exist), line 21.
//
// Correct: nobody claims; A21 hears cannot-complete 2 s after b.
// Hypothesis: X's stale cell reads the re-seizure as a digit 1 (X's e), then
// 3 as b (X's b) and claims; X's register reads 2 2: A21 is connected to X22.
`timescale 1ns/1ps
`include "exch.vh"

module tb_mc2;
    integer chk = 0, errs = 0;
    task ck(input cond, input [8*80-1:0] what);
        begin chk = chk + 1;
             if (!cond) begin errs = errs + 1; $display("    FAIL  %0s", what); end
             else $display("    ok    %0s", what);
        end
    endtask

    reg clk_a = 1'b0, clk_x = 1'b0, rst_n = 1'b0;
    always #122.070 clk_a = ~clk_a;
    initial begin #40; forever #(122.070 * 1.00005) clk_x = ~clk_x; end

    localparam [`PW-1:0] T11 = 6'o11, P20 = 6'o20, P21 = 6'o21, P22 = 6'o22;
    localparam [7:0] WE = {2'd2, 1'b0, 3'b010, 2'b11};
    localparam [7:0] WW = {2'd3, 1'b0, 3'b010, 2'b11};

    reg  [63:0] hook_a = 64'd0, tx_a = 64'd0, hook_x = 64'd0, tx_x = 64'd0;
    wire [63:0] rx_a, e_a, rx_x, e_x, busy_a, busy_x;
    wire [63:0] ac_out, aa_out, ak_out, xc_out, xa_out, xk_out, up_a, up_x;
    wire        fs_a, fs_x, t1k_a, t1k_x, rc_a, rc_x, cl_a, cl_x;
    wire        reg_a, reg_x, mko_a, mko_x, cla_a, cla_x, uno_a, uno_x;
    wire [2:0]  mks_a, mks_x;
    wire [3:0]  dirs_a, dirs_x;
    wire [1:0]  res_a, res_x, mon_a, mon_x;
    wire [7:0]  gl_a, gl_x, nf_a, nf_x;
    wire [7:0]  lz8 = 8'd0;
    wire [63:0] ac_in = {54'd0, xc_out[T11], 9'd0}, aa_in = {54'd0, xa_out[T11], 9'd0},
                ak_in = {54'd0, xk_out[T11], 9'd0};
    wire [63:0] xc_in = {54'd0, ac_out[T11], 9'd0}, xa_in = {54'd0, aa_out[T11], 9'd0},
                xk_in = {54'd0, ak_out[T11], 9'd0};

    site_net #(.PHONES(64'h0000_0000_00FF_0000), .TRUNKS(64'd1 << T11),
               .TWORD({504'd0, WE} << (8*T11)), .OWN_E(3'd2), .OWN_B(3'd2)) A (
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

    wire [5:0]  a_caller = A.u_x.u_mk.caller;
    wire [1:0]  xm_held  = X.u_x.u_net.m_held;
    wire [11:0] xm_port  = X.u_x.u_net.m_port;
    wire [3:0]  xm_st    = X.u_x.u_net.m_st;
    wire [3:0]  a_nst    = A.u_x.u_net.nst;
    reg [63:0] tr_d = 64'd0;
    wire [63:0] tr = {busy_a[T11], busy_x[T11], xa_out[T11], aa_out[T11], xm_held, xm_port, xm_st,
                      reg_a, mks_a, a_caller, a_nst, cla_a, reg_x, mks_x, busy_x[23:16]};
    always @(posedge clk_a) begin
        tr_d <= tr;
        if (rst_n && tr != tr_d)
            $display("  [%5d ms] A11 busy=%b X11 busy=%b | X11 bkA=%b A11 M-in=%b | X cells held=%b port=%o/%o st=%0d/%0d | A reg=%b mk=%0d caller=%o origin=%0d claimed=%b | X reg=%b mk=%0d X2x busy=%b",
                     now, busy_a[T11], busy_x[T11], xa_out[T11], aa_out[T11], xm_held,
                     xm_port[11:6], xm_port[5:0], xm_st[3:2], xm_st[1:0],
                     reg_a, mks_a, a_caller, a_nst, cla_a, reg_x, mks_x, busy_x[23:16]);
    end

    task ms(input integer n); begin repeat (n) @(posedge t1k_a); end endtask
    task dial_a(input [`PW-1:0] p, input integer d);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                hook_a[p] = 1'b0; ms(60);
                hook_a[p] = 1'b1; ms(40);
            end
            ms(800);
        end
    endtask

    integer j; reg s0, s1;
    task hear_a(input [`PW-1:0] p);
        begin s0 = 1'b0; s1 = 1'b0;
            for (j = 0; j < 16; j = j + 1) begin
                @(posedge fs_a); @(posedge clk_a);
                if (rx_a[p]) s1 = 1'b1; else s0 = 1'b1;
            end
        end
    endtask

    integer t_drop, t_reseize;
    initial begin
        $display("\n  tb_mc2 -- the stale cell end to end, real timers: A (22) -- X (13)");
        repeat (20) @(posedge clk_a);
        rst_n = 1'b1;
        ms(30);
        ck(up_a[T11] && up_x[T11], "the link is up");

        hook_a[P20] = 1'b1; ms(20);
        hook_a[P21] = 1'b1;                                  // waits for the register
        ms(200);
        ck(reg_a && a_caller == P20, "A20 has A's register; A21 waits");
        // A20 keys 1
        hook_a[P20] = 1'b0; ms(60); hook_a[P20] = 1'b1;
        while (busy_a[T11] !== 1'b1) @(posedge clk_a);       // A seizes A11
        ms(5);                                               // X sees ~6 ms of M: enough to hold it
        hook_a[P20] = 1'b0; ms(20); hook_a[P20] = 1'b1;      // a break inside the guard
        while (busy_a[T11] !== 1'b0 || dirs_a != 4'd0) @(posedge clk_a);
        t_drop = now;
        $display("    A let A11 go at %0d ms (the guard)", now);
        ms(30);
        ck(busy_x[T11] === 1'b0, "X wrote its hold on the short seizure away (C_UNHOLD)");
        ck((xm_held[0] && xm_port[5:0] == T11) || (xm_held[1] && xm_port[11:6] == T11),
           "OBSERVE: X's cell given to that seizure is still held");
        hook_a[P20] = 1'b0;                                  // A20 gives up
        // A21 gets the register and keys 1 at once
        while (!(reg_a && a_caller == P21)) @(posedge clk_a);
        $display("    A21 has the register at %0d ms", now);
        hook_a[P21] = 1'b0; ms(60); hook_a[P21] = 1'b1;
        while (busy_a[T11] !== 1'b1) @(posedge clk_a);
        t_reseize = now;
        $display("    A seized A11 again at %0d ms, %0d ms after it let it go", now, now - t_drop);
        ms(20);
        ck(xm_held == 2'b11, "OBSERVE: two X cells now watch X11");
        ms(780);
        dial_a(P21, 3);                                      // e: exchange 3x
        ck(xa_out[T11] === 1'b0 && !cla_a, "SAFETY: X (13) does not claim a call to exchange 32");
        dial_a(P21, 2);                                      // b
        dial_a(P21, 2); dial_a(P21, 1); ms(100);             // h s
        ck(busy_x[P22] === 1'b0, "SAFETY: X22 is not rung by a caller who dialled 1 3 2 2 1");
        hook_x[P22] = 1'b1; ms(100);                         // if it rings, answer it
        tx_x[P22] = 1'b1; ms(5);
        $display("    A21 hears X22 go 1: %b", rx_a[P21]);
        tx_x[P22] = 1'b0; ms(5);
        $display("    A21 hears X22 go 0: %b", rx_a[P21]);
        ck(!(busy_x[P22] && rx_a[P21] === 1'b0), "SAFETY: A21 is not talking to X22");
        hook_a[P21] = 1'b0; hook_x[P22] = 1'b0;
        ms(1000);
        ck(busy_a == 64'd0 && busy_x == 64'd0 && !reg_a && !reg_x && mon_x == 2'd0,
           "and afterwards both exchanges are idle");
        $display("\n  %0d checks, %0d errors.  %s\n", chk, errs, (errs == 0) ? "PASS" : "FAIL");
        $finish;
    end

    initial begin #40_000_000_000; $display("  TIMEOUT"); $finish; end
    wire _unused = &{1'b0, e_a, e_x, rx_x, fs_x, t1k_x, rc_a, rc_x, cl_a, cl_x, mko_a, mko_x,
                     cla_x, uno_a, uno_x, dirs_x, res_a, res_x, mon_a, gl_a, gl_x, nf_a, nf_x,
                     tx_a, hook_x, mks_x, 1'b0};
endmodule
