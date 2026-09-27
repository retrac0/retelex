// tb_c03b -- SKEPTIC scratch bench for C03 rc-tolerance-reseize, REAL timers.
// Not part of the tree.  A variant of the verifier's tb_c03r.
//
// Question: does the RC path need an OWN_E = 1 exchange (the verifier's claim)?
// Hypothesis: no.  A flood abandoned AFTER X's e has matched leaves X's cell in
// M_WANT_B with done set; the abandon's break counts cnt = 1, the re-seizure's
// make is a digit 1 = X's b, and X claims ID after the re-seizure, before the
// new caller dials anything.  The new call then reaches X's line e' b'.
//
// Exchange A (code 2 2, every port's T_REL = TRELA, default 200: an RC 22%
// short) and X (code 2 1, nominal), one baseband tie A11-X11.  A12 and A13 face
// W to the bench (a western exchange Y).  A is a TRANSIT only: no origin call.
//
//   Y floods on A13; A forwards it east on A11.  Y's caller dials 2 (X's e,
//     A's e too) with a conforming dial, then hangs up 300 ms into the pause.
//   A13 and A11 release at A after TRELA; A's resolver drops the leg.
//   RS ms after the hang-up Y floods again, on A12; A forwards it east on the
//     lowest free trunk -- A11 again -- while X11 is still held (X's fM is
//     nominal) and X's cell still counts (CLR is a counter: 256).
//   Y's second caller dials 2 5 3 4 (exchange 25, not present).
// Correct: X does not claim; X25 does not ring.
//
// +rs=N (default TRELA+2) +p0=N (default 700)
`timescale 1ns/1ps
`include "exch.vh"

`ifndef TRELA
`define TRELA 200
`endif
module tb_c03b;
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
                         P25 = 6'o25;
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
               .TWORD({504'd0, WW} << (8*T11)), .OWN_E(3'd2), .OWN_B(3'd1)) X (
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
    wire [1:0]  a_fst    = A.u_x.u_net.fst;
    wire [127:0] tr = {busy_a[T13:T11], busy_x[T11], xa_out[T11], aa_out[T13:T11], xm_held, xm_port,
                       xm_st, xd_cnt, x_cst, a_fst, res_a, reg_x, mks_x,
                       busy_x[23:16], far_m[T13:T12]};
    reg [127:0] tr_d = 128'd0;
    always @(posedge clk_a) begin
        tr_d <= tr;
        if (rst_n && tr != tr_d)
            $display("  [%5d ms] A busy13..11=%b X11 busy=%b bkA=%b | A a_out13..11=%b Y M13,12=%b | X cells held=%b port=%o/%o st=%0d/%0d cnt=%0d/%0d cls=%0d | A fwd=%0d res=%b | X reg=%b mk=%0d X2x busy=%b",
                     now, busy_a[T13:T11], busy_x[T11], xa_out[T11], aa_out[T13:T11], far_m[T13:T12],
                     xm_held, xm_port[11:6], xm_port[5:0], xm_st[3:2], xm_st[1:0],
                     xd_cnt[7:4], xd_cnt[3:0], x_cst,
                     a_fst, res_a, reg_x, mks_x, busy_x[23:16]);
    end

    task ms(input integer n); begin repeat (n) @(posedge t1k_a); end endtask
    // a far caller's dial on one of Y's trunks into A: 10 pps 60/40, 800 ms pause
    task fdial(input integer p, input integer d);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                far_m[p] = 1'b0; ms(60);
                far_m[p] = 1'b1; ms(40);
            end
        end
    endtask

    integer rs, p0, t_drop, t_rs, t_claim, rng, stB;
    always @(posedge clk_x) if (rst_n && t_rs > 0 && t_claim == 0 && xa_out[T11] === 1'b1) t_claim = now;

    initial begin
        t_rs = 0; t_claim = 0;
        if (!$value$plusargs("rs=%d", rs)) rs = `TRELA + 2;
        if (!$value$plusargs("p0=%d", p0)) p0 = 700;
        $display("\n  tb_c03b -- abandon after X's e matched, A's T_REL=%0d, re-seizure by a transit forward, real timers: rs=%0d p0=%0d", `TRELA, rs, p0);
        repeat (20) @(posedge clk_a);
        rst_n = 1'b1;
        ms(30);
        ck(up_a[T11] && up_x[T11] && up_a[T12] && up_a[T13], "the links are up");

        // ---- flood 1: Y on A13, forwarded east on A11 ----------------------------
        far_m[T13] = 1'b1;
        while (busy_a[T11] !== 1'b1) @(posedge clk_a);
        $display("    A forwarded A13 onto A11 at %0d ms", now);
        ms(p0);
        fdial(T13, 2);                                     // e = 2: X's e (and A's)
        ms(300);                                           // into the pause: e resolved at X
        stB = (xm_held[0] && xm_port[5:0] == T11 && xm_st[1:0] == 2'd2) ||
              (xm_held[1] && xm_port[11:6] == T11 && xm_st[3:2] == 2'd2);
        ck(stB, "OBSERVE: X's cell on X11 has matched e and waits for b");
        far_m[T13] = 1'b0;                                 // Y's first caller hangs up
        t_drop = now;
        $display("    Y's first caller hung up at %0d ms", now);
        while (busy_a[T11] !== 1'b0) @(posedge clk_a);
        $display("    A11 free at A at %0d ms (%0d ms after the break)", now, now - t_drop);
        ck(busy_x[T11] === 1'b1, "OBSERVE: X11 still held when A11 frees at A");

        // ---- flood 2: Y on A12, forwarded east on A11 again ---------------------
        while (now < t_drop + rs) @(posedge clk_a);
        far_m[T12] = 1'b1;
        while (busy_a[T11] !== 1'b1) @(posedge clk_a);
        t_rs = now;
        $display("    A re-seized A11 (forward of A12) at %0d ms, %0d ms after the break", now, now - t_drop);
        ms(300);
        ck(xa_out[T11] === 1'b0 && aa_out[T12] === 1'b0,
           "SAFETY: X (21) does not claim a flood nobody has dialled a digit on");
        if (t_claim > 0) $display("    X claimed at %0d ms, %0d ms after the re-seizure", t_claim, t_claim - t_rs);
        ck(!reg_x, "SAFETY: X's register is not attached");
        ms(p0 - 300);
        fdial(T12, 2); ms(800);                            // e = 2
        fdial(T12, 5); ms(800);                            // b = 5: exchange 25
        fdial(T12, 3); ms(800);
        fdial(T12, 4); ms(300);
        rng = busy_x[P25] && !hook_x[P25];
        $display("    X2x busy=%b (X25 is bit 5)", busy_x[23:16]);
        ck(!rng, "SAFETY: X25 is not rung by a flood dialled 1 2 5 3 4");
        far_m[T13] = 1'b0; far_m[T12] = 1'b0;
        ms(1500);
        ck(busy_a == 64'd0 && busy_x == 64'd0 && !reg_a && !reg_x && mon_x == 2'd0 && mon_a == 2'd0,
           "and afterwards both exchanges are idle");
        ck(!cl_a && !cl_x && !mko_a && !mko_x && !uno_a && !uno_x, "no bus clash, no queue refusal (last sample)");
        $display("\n  %0d checks, %0d errors.  %s\n", chk, errs, (errs == 0) ? "PASS" : "FAIL");
        $finish;
    end

    initial begin #40_000_000_000; $display("  TIMEOUT"); $finish; end
    wire _unused = &{1'b0, e_a, e_x, rx_a, rx_x, fs_a, fs_x, t1k_x, rc_a, rc_x, cla_a, cla_x, dirs_a, dirs_x,
                     res_x, gl_a, gl_x, nf_a, nf_x, tx_a, tx_x, mks_x, up_x, reg_a, 1'b0};
endmodule
