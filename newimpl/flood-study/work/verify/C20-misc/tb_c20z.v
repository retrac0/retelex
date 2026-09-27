// tb_c20z -- VERIFY scratch bench for C20 finding port00-must-be-unfitted, REAL
// timers.  Not part of the tree.
//
// Exchange A (code 2 2) and exchange X (code 1 3), one baseband tie A11-X11
// (A's card faces E, X's faces W).  A12 faces W, its far end the BENCH (a
// western exchange Y, code 3 4, which never gets to claim here).  Phones 20-27
// at both -- and, the FAULT, a phone fitted at X's port 00 (numbering.md 2:
// "00 idle, never fitted"), which goes off-hook and stays there.
//
// Observed, not judged: whether X's idle phones are rung with no call; what
// A's origin does with a flood dialled 1 3 4 2 1 (exchange 3 4 = Y, west):
// does X's hold (listening to 00) look like a claim, is Y's direction dropped,
// where does A20 end up connected, and does anything at X claim or ring a
// line because of the call (a WRONG NUMBER would be a line rung or a register
// attached by the call).
`timescale 1ns/1ps
`include "exch.vh"

module tb_c20z;
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

    localparam [`PW-1:0] T11 = 6'o11, T12 = 6'o12, P00 = 6'o00, P20 = 6'o20, P21 = 6'o21;
    localparam [7:0] WE = {2'd2, 1'b0, 3'b010, 2'b11};
    localparam [7:0] WW = {2'd3, 1'b0, 3'b010, 2'b11};
    localparam [63:0] TRA = (64'd1 << T11) | (64'd1 << T12);
    localparam [511:0] TWA = ({504'd0, WE} << (8*T11)) | ({504'd0, WW} << (8*T12));

    reg  [63:0] hook_a = 64'd0, tx_a = 64'd0, hook_x = 64'd0, tx_x = 64'd0;
    reg  [63:0] far_m = 64'd0;                           // Y's M on A12
    wire [63:0] rx_a, e_a, rx_x, e_x, busy_a, busy_x;
    wire [63:0] ac_out, aa_out, ak_out, xc_out, xa_out, xk_out, up_a, up_x;
    wire        fs_a, fs_x, t1k_a, t1k_x, rc_a, rc_x, cl_a, cl_x;
    wire        reg_a, reg_x, mko_a, mko_x, cla_a, cla_x, uno_a, uno_x;
    wire [2:0]  mks_a, mks_x;
    wire [3:0]  dirs_a, dirs_x;
    wire [1:0]  res_a, res_x, mon_a, mon_x;
    wire [7:0]  gl_a, gl_x, nf_a, nf_x;
    wire [7:0]  lz8 = 8'd0;
    wire [63:0] ac_in = ({63'd0, xc_out[T11]} << T11);
    wire [63:0] aa_in = ({63'd0, xa_out[T11]} << T11) | (far_m & (64'd1 << T12));
    wire [63:0] ak_in = ({63'd0, xk_out[T11]} << T11) | (ak_out & (64'd1 << T12));
    wire [63:0] xc_in = ({63'd0, ac_out[T11]} << T11);
    wire [63:0] xa_in = ({63'd0, aa_out[T11]} << T11);
    wire [63:0] xk_in = ({63'd0, ak_out[T11]} << T11);

    site_net #(.PHONES(64'h0000_0000_00FF_0000), .TRUNKS(TRA), .TWORD(TWA),
               .OWN_E(3'd2), .OWN_B(3'd2)) A (
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

    // THE FAULT: PHONES bit 0 -- a phone at X00
    site_net #(.PHONES(64'h0000_0000_00FF_0001), .TRUNKS(64'd1 << T11),
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

    wire       x21_rb   = X.u_x.u_exch.pos[2].u_blk.rb[1];     // X21 being rung
    wire [5:0] a20_addr = A.u_x.u_exch.pos[2].u_blk.u_port0.addr;
    wire       x_att    = X.u_x.u_net.att;
    wire [5:0] x_attp   = X.u_x.u_net.att_port;
    wire [3:0] a_nst    = A.u_x.u_net.nst;
    wire [5:0] a_trunk  = A.u_x.u_net.trunk;

    // anything at X claiming, or any line at X rung, because of the call
    integer n_xatt = 0, x_rung_mask = 0;
    reg x_att_d = 1'b0;
    always @(posedge clk_x) begin
        x_att_d <= x_att;
        if (rst_n && x_att && !x_att_d) begin
            n_xatt = n_xatt + 1;
            $display("  [%5d ms] X's unit asks for its register: claimed trunk port %o", now, x_attp);
        end
    end
    reg [3:0] a_nst_d = 4'd0;
    reg [7:0] gl_a_d = 8'd0;
    reg [3:0] dirs_a_d = 4'd0;
    always @(posedge clk_a) begin
        a_nst_d <= a_nst; gl_a_d <= gl_a; dirs_a_d <= dirs_a;
        if (rst_n && a_nst != a_nst_d) $display("  [%5d ms] A origin state %0d -> %0d (claimed=%b trunk %o dirs=%b glare#=%0d)",
                                                now, a_nst_d, a_nst, cla_a, a_trunk, dirs_a, gl_a);
        if (rst_n && dirs_a != dirs_a_d) $display("  [%5d ms] A's origin holds directions %b", now, dirs_a);
    end

    task ms(input integer n); begin repeat (n) @(posedge t1k_a); end endtask
    task adial(input integer d);        // A20, 10 pps 60/40, 800 ms pause after
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                hook_a[P20] = 1'b0; ms(60);
                hook_a[P20] = 1'b1; ms(40);
            end
            ms(800);
        end
    endtask

    integer seen_rb, k, t_seize, heard;
    reg [63:0] rung_x;
    initial begin
        $display("\n  tb_c20z -- a phone fitted at X00 and off-hook; A20 dials 1 3 4 2 1 (Y, west)");
        repeat (20) @(posedge clk_a);
        rst_n = 1'b1;
        ms(30);
        ck(up_a[T11] && up_x[T11] && up_a[T12], "the links are up");
        tx_x[P00] = 1'b1;                                   // X00 sends ones: recognisable
        hook_x[P00] = 1'b1;                                 // THE FAULT: X00 lifts
        ms(50);
        seen_rb = 0;
        for (k = 0; k < 50; k = k + 1) begin ms(1); if (x21_rb) seen_rb = seen_rb + 1; end
        $display("    X21 (idle, on-hook, no call anywhere) marked being-rung in %0d of 50 ms", seen_rb);
        ck(seen_rb == 0, "OBSERVE: X21 is not rung with no call (expected to FAIL under the fault)");

        hook_a[P20] = 1'b1; ms(400);
        ck(reg_a, "A20 has A's register");
        hook_a[P20] = 1'b0; ms(60); hook_a[P20] = 1'b1;     // keys 1
        while (busy_a[T11] !== 1'b1) @(posedge clk_a);
        t_seize = now;
        $display("    A seized A11 (E, to X) at %0d ms", now);
        ms(30);
        $display("    30 ms after the seizure: A claimed=%b trunk %o glare#=%0d dirs=%b", cla_a, a_trunk, gl_a, dirs_a);
        ck(!cla_a, "OBSERVE: no claim before a digit is dialled (expected to FAIL under the fault)");
        ms(570);
        adial(3); adial(4);                                  // e b = 3 4: Y, to the west
        adial(2); adial(1); ms(200);                         // h s
        $display("    after 1 3 4 2 1: A origin state %0d, A20 listens to %o, A20 hears %b, X00 sends 1",
                 a_nst, a20_addr, rx_a[P20]);
        ck(a20_addr != T11, "OBSERVE: A20 is not connected to the trunk to X (expected to FAIL)");
        rung_x = busy_x & 64'h0000_0000_00FF_0000;
        $display("    X lines 20-27 busy=%b; X unit register requests=%0d", busy_x[23:16], n_xatt);
        ck(n_xatt == 0, "WRONG NUMBER?: X's unit never claims the call (e b = 3 4)");
        ck(rung_x == 64'd0, "WRONG NUMBER?: no X line 20-27 is seized by the call");
        ck(!cl_a && !cl_x && !mko_a && !mko_x && !uno_a && !uno_x, "no bus clash, no queue refusal (last sample)");
        $display("\n  %0d checks, %0d errors.  %s\n", chk, errs, (errs == 0) ? "PASS" : "FAIL");
        $finish;
    end

    initial begin #40_000_000_000; $display("  TIMEOUT"); $finish; end
    wire _unused = &{1'b0, e_a, e_x, rx_x, fs_a, fs_x, t1k_x, rc_a, rc_x, cla_x, dirs_x,
                     res_a, res_x, nf_a, nf_x, tx_a, mks_a, mks_x, up_x, mon_a, mon_x, x_rung_mask, 1'b0};
endmodule
