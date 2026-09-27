// tb_c12 -- C12 VERIFIER scratch bench: what the origin takes as the claim.
// Not part of the tree.  REAL timers (site_net's defaults: HIT 8, ID 128,
// CLR 256, T_ARM 16, T_REL 256, guard 128, T_CLAIM 2000), dial 10 pps 60/40,
// 800 ms pauses.
//
//   Y (3 1) --- A11  A (2 2)  A12 --- X (1 3)
//
// A20 dials 1 3 1 2 1: the call is Y's (e 3, b 1), line 21.  The flood seizes
// A11 toward Y and A12 toward X.  X's monitor lets go at e (3 is not 1).
//
//   S1  control: nothing injected.  Y claims, A keeps A11, Y21 rings.
//   S2  finding claim-on-one-sample: ~1 ms of A = 1 on the X->A wire of A12
//       (a carrier glitch; the 2-FF sync makes it 8 frames, one or two of
//       A12's 1 ms turns), 300 ms after e ends -- outside the guard, before b.
//   S3  finding origin-accepts-early-claim, stand-alone: A = 1 held on the
//       X->A wire of A12 from 300 ms after e until A20 hangs up -- what a
//       monitor claiming on a wrong count before b (C03's stale cell, (1,e))
//       looks like at the origin.
`timescale 1ns/1ps
`include "exch.vh"

module tb_c12;
    integer chk = 0, errs = 0;
    task ck(input cond, input [8*96-1:0] what);
        begin chk = chk + 1;
             if (!cond) begin errs = errs + 1; $display("    FAIL  %0s", what); end
             else $display("    ok    %0s", what);
        end
    endtask

    reg clk_a = 1'b0, clk_x = 1'b0, clk_y = 1'b0, rst_n = 1'b0;
    always #122.070 clk_a = ~clk_a;
    initial begin #40; forever #(122.070 * 1.00005) clk_x = ~clk_x; end
    initial begin #77; forever #(122.070 * 0.99997) clk_y = ~clk_y; end

    localparam [`PW-1:0] T11 = 6'o11, T12 = 6'o12, P20 = 6'o20, P21 = 6'o21;
    localparam [7:0] WE = {2'd2, 1'b0, 3'b010, 2'b11};
    localparam [7:0] WW = {2'd3, 1'b0, 3'b010, 2'b11};

    reg  [63:0] hook_a = 64'd0, hook_x = 64'd0, hook_y = 64'd0;
    wire [63:0] tx0 = 64'd0;
    wire [63:0] rx_a, rx_x, rx_y, busy_a, busy_x, busy_y, up_a, up_x, up_y;
    wire [63:0] ac, aa, ak, xc, xa, xk, yc, ya, yk;
    wire        fs_a, t1k_a, reg_a, reg_x, reg_y, cla_a;
    wire [3:0]  dirs_a;
    wire [1:0]  mon_x, mon_y;
    wire [7:0]  lz8 = 8'd0;
    reg         inj = 1'b0;                       // A = 1 injected on X -> A12

    // A11 (bit 9) <-> Y11 (bit 9); A12 (bit 10) <-> X12 (bit 10)
    wire [63:0] ac_in = {53'd0, xc[T12], yc[T11], 9'd0};
    wire [63:0] aa_in = {53'd0, xa[T12] | inj, ya[T11], 9'd0};
    wire [63:0] ak_in = {53'd0, xk[T12], yk[T11], 9'd0};
    wire [63:0] yc_in = {54'd0, ac[T11], 9'd0}, ya_in = {54'd0, aa[T11], 9'd0}, yk_in = {54'd0, ak[T11], 9'd0};
    wire [63:0] xc_in = {53'd0, ac[T12], 10'd0}, xa_in = {53'd0, aa[T12], 10'd0}, xk_in = {53'd0, ak[T12], 10'd0};

    site_net #(.PHONES(64'h0000_0000_00FF_0000), .TRUNKS((64'd1 << T11) | (64'd1 << T12)),
               .TWORD(({504'd0, WE} << (8*T11)) | ({504'd0, WW} << (8*T12))),
               .OWN_E(3'd2), .OWN_B(3'd2)) A (
        .clk(clk_a), .rst_n(rst_n), .hook(hook_a), .tx(tx0), .rx(rx_a), .e(),
        .c_out(ac), .a_out(aa), .clk_out(ak), .c_in(ac_in), .a_in(aa_in), .clk_in(ak_in), .link_up(up_a),
        .lt_c_out(), .lt_a_out(), .lt_h_out(), .lt_k_out(),
        .lt_c_in(lz8), .lt_a_in(lz8), .lt_h_in(lz8), .lt_k_in(lz8), .lt_up(),
        .frame_stb(fs_a), .tick_1k(t1k_a), .ring_cad_n(), .port_busy(busy_a),
        .b_sdata(), .b_sclk(), .b_wr(), .b_clash(),
        .reg_busy(reg_a), .mk_state(), .mk_ovf(), .dirs_held(dirs_a),
        .res_busy(), .mon_held(), .claimed(cla_a), .hunting(),
        .un_ovf(), .n_glare(), .n_nofwd());

    site_net #(.PHONES(64'h0000_0000_00FF_0000), .TRUNKS(64'd1 << T12),
               .TWORD({504'd0, WE} << (8*T12)), .OWN_E(3'd1), .OWN_B(3'd3)) X (
        .clk(clk_x), .rst_n(rst_n), .hook(hook_x), .tx(tx0), .rx(rx_x), .e(),
        .c_out(xc), .a_out(xa), .clk_out(xk), .c_in(xc_in), .a_in(xa_in), .clk_in(xk_in), .link_up(up_x),
        .lt_c_out(), .lt_a_out(), .lt_h_out(), .lt_k_out(),
        .lt_c_in(lz8), .lt_a_in(lz8), .lt_h_in(lz8), .lt_k_in(lz8), .lt_up(),
        .frame_stb(), .tick_1k(), .ring_cad_n(), .port_busy(busy_x),
        .b_sdata(), .b_sclk(), .b_wr(), .b_clash(),
        .reg_busy(reg_x), .mk_state(), .mk_ovf(), .dirs_held(),
        .res_busy(), .mon_held(mon_x), .claimed(), .hunting(),
        .un_ovf(), .n_glare(), .n_nofwd());

    site_net #(.PHONES(64'h0000_0000_00FF_0000), .TRUNKS(64'd1 << T11),
               .TWORD({504'd0, WW} << (8*T11)), .OWN_E(3'd3), .OWN_B(3'd1)) Y (
        .clk(clk_y), .rst_n(rst_n), .hook(hook_y), .tx(tx0), .rx(rx_y), .e(),
        .c_out(yc), .a_out(ya), .clk_out(yk), .c_in(yc_in), .a_in(ya_in), .clk_in(yk_in), .link_up(up_y),
        .lt_c_out(), .lt_a_out(), .lt_h_out(), .lt_k_out(),
        .lt_c_in(lz8), .lt_a_in(lz8), .lt_h_in(lz8), .lt_k_in(lz8), .lt_up(),
        .frame_stb(), .tick_1k(), .ring_cad_n(), .port_busy(busy_y),
        .b_sdata(), .b_sclk(), .b_wr(), .b_clash(),
        .reg_busy(reg_y), .mk_state(), .mk_ovf(), .dirs_held(),
        .res_busy(), .mon_held(mon_y), .claimed(), .hunting(),
        .un_ovf(), .n_glare(), .n_nofwd());

    integer now = 0;
    always @(posedge t1k_a) now = now + 1;

    // the origin's events, counted
    wire        a_done = A.u_x.u_net.done, a_nogo = A.u_x.u_net.nogo;
    wire [3:0]  a_nst  = A.u_x.u_net.nst;
    wire [`PW-1:0] a_trunk = A.u_x.u_net.trunk;
    integer n_done = 0, n_nogo = 0, n_yreg = 0;
    reg [`PW-1:0] done_trunk = 6'o00;
    reg reg_y_d = 1'b0, cla_d = 1'b0;
    reg [3:0] nst_d = 4'd0;
    always @(posedge clk_a) begin
        if (a_done) begin n_done = n_done + 1; done_trunk = a_trunk;
            $display("  [%5d ms] A done: A20 <-> trunk %o", now, a_trunk); end
        if (a_nogo) begin n_nogo = n_nogo + 1; $display("  [%5d ms] A nogo", now); end
        if (cla_a && !cla_d) $display("  [%5d ms] A claimed: trunk %o, origin state %0d, dirs %b", now, a_trunk, a_nst, dirs_a);
        if (a_nst != nst_d) $display("  [%5d ms] A origin state %0d -> %0d (dirs %b)", now, nst_d, a_nst, dirs_a);
        cla_d <= cla_a; nst_d <= a_nst;
    end
    always @(posedge clk_y) begin
        if (reg_y && !reg_y_d) begin n_yreg = n_yreg + 1; $display("  [%5d ms] Y's register taken (claim)", now); end
        reg_y_d <= reg_y;
    end

    task ms(input integer n); begin repeat (n) @(posedge t1k_a); end endtask
    task dial_a(input [`PW-1:0] p, input integer d, input integer pause);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                hook_a[p] = 1'b0; ms(60);
                hook_a[p] = 1'b1; ms(40);
            end
            ms(pause);
        end
    endtask

    integer y21, sc, nd0, nn0, ny0;
    task call(input integer mode);             // 0 none, 1 glitch, 2 held
        begin
            nd0 = n_done; nn0 = n_nogo; ny0 = n_yreg; y21 = 0;
            hook_a[P20] = 1'b1;
            while (!(reg_a && A.u_x.u_mk.caller == P20)) @(posedge clk_a);
            ms(300);
            dial_a(P20, 1, 800);                  // the key
            dial_a(P20, 3, 300);                  // e
            $display("  [%5d ms] e ended 300 ms ago; origin state %0d, dirs %b", now, a_nst, dirs_a);
            if (mode == 1) begin inj = 1'b1; #1_000_000; inj = 1'b0;
                $display("  [%5d ms] 1 ms of A = 1 on A12's receive wire", now); end
            if (mode == 2) begin inj = 1'b1; $display("  [%5d ms] A = 1 held on A12's receive wire", now); end
            ms(500);
            dial_a(P20, 1, 800);                  // b
            dial_a(P20, 2, 800);                  // h
            dial_a(P20, 1, 200);                  // s
            repeat (3000) begin @(posedge t1k_a); if (busy_y[P21]) y21 = 1; end
            hook_a[P20] = 1'b0; inj = 1'b0;
            ms(1500);
        end
    endtask

    initial begin
        if (!$value$plusargs("sc=%d", sc)) sc = 0;
        $display("\n  tb_c12 -- what the origin takes as the claim, real timers: Y (31) - A (22) - X (13)");
        repeat (20) @(posedge clk_a);
        rst_n = 1'b1;
        ms(300);
        ck(up_a[T11] && up_a[T12] && up_x[T12] && up_y[T11], "the links are up");

        if (sc == 0 || sc == 1) begin
            $display("\n  S1 control: A20 dials 1 3 1 2 1");
            call(0);
            ck(n_done == nd0 + 1 && done_trunk == T11, "S1: A connects A20 to A11 (toward Y)");
            ck(n_yreg == ny0 + 1, "S1: Y claims and takes its register");
            ck(y21 == 1, "S1: Y21 rings");
            ck(busy_a == 64'd0 && busy_x == 64'd0 && busy_y == 64'd0 && !reg_a && !reg_x && !reg_y,
               "S1: afterwards all three exchanges are idle");
        end
        if (sc == 0 || sc == 2) begin
            $display("\n  S2 one-sample glitch on A12's A between e and b: A20 dials 1 3 1 2 1");
            call(1);
            ck(n_done == nd0 + 1 && done_trunk == T11, "S2: A connects A20 to A11 (toward Y), not A12");
            ck(n_yreg == ny0 + 1, "S2: Y claims and takes its register");
            ck(y21 == 1, "S2: Y21 rings");
            ck(busy_a == 64'd0 && busy_x == 64'd0 && busy_y == 64'd0 && !reg_a && !reg_x && !reg_y,
               "S2: afterwards all three exchanges are idle");
        end
        if (sc == 0 || sc == 3) begin
            $display("\n  S3 A = 1 standing on A12 from 300 ms after e: A20 dials 1 3 1 2 1");
            call(2);
            ck(!(n_done == nd0 + 1 && done_trunk == T12), "S3 SAFETY: A does not connect A20 to A12 (X claimed nothing)");
            ck(n_done == nd0 + 1 || n_nogo == nn0 + 1, "S3: A connects to Y or gives cannot-complete");
            ck(busy_a == 64'd0 && busy_x == 64'd0 && busy_y == 64'd0 && !reg_a && !reg_x && !reg_y,
               "S3: afterwards all three exchanges are idle");
        end
        $display("\n  %0d checks, %0d errors.  %s\n", chk, errs, (errs == 0) ? "PASS" : "FAIL");
        $finish;
    end

    initial begin #60_000_000_000; $display("  TIMEOUT"); $finish; end
    wire _unused = &{1'b0, rx_a, rx_x, rx_y, fs_a, mon_x, mon_y, hook_x, hook_y, 1'b0};
endmodule
