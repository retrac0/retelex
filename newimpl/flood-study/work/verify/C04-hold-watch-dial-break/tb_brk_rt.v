// tb_brk -- AUDIT (cableb slice, a hold and its unhold).  The classifier's
// C_HOLD watch writes the hold away on ANY sample of M low inside T_ARM + 2
// ms of the hold -- a dial break as much as a seizure that died.  If the
// caller's first break of e reaches an exchange while that exchange is still
// watching its hold, the hold is written away, the make that follows shows
// M up with BUSY down, and the classifier takes it for a FRESH seizure: a
// second hold and a second monitor, attached after the first pulse of e.
// That monitor counts e short.  The call is dialled 1 3 4 2 1 -- code 3 4,
// which is nobody -- and C (code 2 4) hears 2 4.
//
//     A 2 2  ==11,12==  11,12  B 2 3  13,15  ==11,12==  C 2 4      (tb_chain)
//
// The first break is timed off A's own guard: `tmr` = 16 + off ms after A's
// seizure, so A never abandons.  At scale 8 the guard is 16 ms but the sweep
// is 9 ms real, so C, two hops down, is still watching its hold then.  At
// real timers the same thing needs the hop that is 2-20 ms behind the first
// break -- see the report.
//
//   +offs=N   number of offsets to try, 0..N-1 (default 4), then a control at +60
`timescale 1ns/1ps
`include "exch.vh"

module tb_brk_rt;
    integer chk = 0, errs = 0;
    task ck(input cond, input [8*80-1:0] what);
        begin chk = chk + 1;
             if (!cond) begin errs = errs + 1; $display("    FAIL  %0s", what); end
             else $display("    ok    %0s", what);
        end
    endtask

    reg clk_a = 1'b0, clk_b = 1'b0, clk_c = 1'b0, rst_n = 1'b0;
    always #122.070 clk_a = ~clk_a;
    initial begin #40; forever #122.070 clk_b = ~clk_b; end
    initial begin #90; forever #122.070 clk_c = ~clk_c; end

    localparam [`PW-1:0] P20 = 6'o20, P21 = 6'o21;
    localparam [`PW-1:0] T11 = 6'o11, T12 = 6'o12, T13 = 6'o13, T15 = 6'o15;
    localparam [7:0] WE0 = {2'd2, 1'b0, 3'b010, 2'b11};
    localparam [7:0] WW1 = {2'd3, 1'b1, 3'b010, 2'b11};
    localparam [511:0] TW_A = ({504'd0, WE0} << (8*T11)) | ({504'd0, WE0} << (8*T12));
    localparam [511:0] TW_B = ({504'd0, WW1} << (8*T11)) | ({504'd0, WW1} << (8*T12)) |
                              ({504'd0, WE0} << (8*T13)) | ({504'd0, WE0} << (8*T15));
    localparam [511:0] TW_C = ({504'd0, WW1} << (8*T11)) | ({504'd0, WW1} << (8*T12));

    reg  [63:0] hook_a = 0, tx_a = 0, hook_b = 0, tx_b = 0, hook_c = 0, tx_c = 0;
    wire [63:0] rx_a, e_a, rx_b, e_b, rx_c, e_c, busy_a, busy_b, busy_c;
    wire [63:0] ac, aa, ak, bc, ba, bk, cc, ca, ck_o, up_a, up_b, up_c;
    reg  [63:0] ac_i, aa_i, ak_i, bc_i, ba_i, bk_i, cc_i, ca_i, ck_i;
    wire        fs_a, fs_b, fs_c, t1k_a, t1k_b, t1k_c, rc_a, rc_b, rc_c;
    wire        sd_a, sc_a, wr_a, cl_a, sd_b, sc_b, wr_b, cl_b, sd_c, sc_c, wr_c, cl_c;
    wire        reg_a, reg_b, reg_c, mo_a, mo_b, mo_c, cla_a, cla_b, cla_c;
    wire        hu_a, hu_b, hu_c, uo_a, uo_b, uo_c;
    wire [2:0]  ms_a, ms_b, ms_c;
    wire [3:0]  dirs_a, dirs_b, dirs_c;
    wire [1:0]  res_a, res_b, res_c, mon_a, mon_b, mon_c;
    wire [7:0]  gl_a, gl_b, gl_c, nf_a, nf_b, nf_c;

`define SITE_PARAMS .PHONES(64'h0000_0000_0003_0000), \
        .T_ARM(9'd16), .T_REL(9'd256), .RING_ON(13'd64), .RING_OFF(13'd128), \
        .HIT(9'd8), .ID(9'd128), .CLR(9'd256), .NODIG(16'd10000), \
        .T_GUARD0(16'd16), .T_KEY(16'd5000), .T_CLAIM(16'd2000)

    site_net #(`SITE_PARAMS, .TRUNKS((64'd1 << T11) | (64'd1 << T12)), .TWORD(TW_A),
               .OWN_E(3'd2), .OWN_B(3'd2)) A (
        .clk(clk_a), .rst_n(rst_n), .hook(hook_a), .tx(tx_a), .rx(rx_a), .e(e_a),
        .c_out(ac), .a_out(aa), .clk_out(ak), .c_in(ac_i), .a_in(aa_i), .clk_in(ak_i),
        .link_up(up_a), .frame_stb(fs_a), .tick_1k(t1k_a), .ring_cad_n(rc_a),
        .port_busy(busy_a), .b_sdata(sd_a), .b_sclk(sc_a), .b_wr(wr_a), .b_clash(cl_a),
        .reg_busy(reg_a), .mk_state(ms_a), .mk_ovf(mo_a), .dirs_held(dirs_a),
        .res_busy(res_a), .mon_held(mon_a), .claimed(cla_a), .hunting(hu_a),
        .un_ovf(uo_a), .n_glare(gl_a), .n_nofwd(nf_a));

    site_net #(`SITE_PARAMS,
               .TRUNKS((64'd1 << T11) | (64'd1 << T12) | (64'd1 << T13) | (64'd1 << T15)),
               .TWORD(TW_B), .OWN_E(3'd2), .OWN_B(3'd3)) B (
        .clk(clk_b), .rst_n(rst_n), .hook(hook_b), .tx(tx_b), .rx(rx_b), .e(e_b),
        .c_out(bc), .a_out(ba), .clk_out(bk), .c_in(bc_i), .a_in(ba_i), .clk_in(bk_i),
        .link_up(up_b), .frame_stb(fs_b), .tick_1k(t1k_b), .ring_cad_n(rc_b),
        .port_busy(busy_b), .b_sdata(sd_b), .b_sclk(sc_b), .b_wr(wr_b), .b_clash(cl_b),
        .reg_busy(reg_b), .mk_state(ms_b), .mk_ovf(mo_b), .dirs_held(dirs_b),
        .res_busy(res_b), .mon_held(mon_b), .claimed(cla_b), .hunting(hu_b),
        .un_ovf(uo_b), .n_glare(gl_b), .n_nofwd(nf_b));

    site_net #(`SITE_PARAMS, .TRUNKS((64'd1 << T11) | (64'd1 << T12)), .TWORD(TW_C),
               .OWN_E(3'd2), .OWN_B(3'd4)) C (
        .clk(clk_c), .rst_n(rst_n), .hook(hook_c), .tx(tx_c), .rx(rx_c), .e(e_c),
        .c_out(cc), .a_out(ca), .clk_out(ck_o), .c_in(cc_i), .a_in(ca_i), .clk_in(ck_i),
        .link_up(up_c), .frame_stb(fs_c), .tick_1k(t1k_c), .ring_cad_n(rc_c),
        .port_busy(busy_c), .b_sdata(sd_c), .b_sclk(sc_c), .b_wr(wr_c), .b_clash(cl_c),
        .reg_busy(reg_c), .mk_state(ms_c), .mk_ovf(mo_c), .dirs_held(dirs_c),
        .res_busy(res_c), .mon_held(mon_c), .claimed(cla_c), .hunting(hu_c),
        .un_ovf(uo_c), .n_glare(gl_c), .n_nofwd(nf_c));

    always @* begin
        ac_i = 0; aa_i = 0; ak_i = 0; bc_i = 0; ba_i = 0; bk_i = 0;
        cc_i = 0; ca_i = 0; ck_i = 0;
        ac_i[T11] = bc[T11]; aa_i[T11] = ba[T11]; ak_i[T11] = bk[T11];
        bc_i[T11] = ac[T11]; ba_i[T11] = aa[T11]; bk_i[T11] = ak[T11];
        ac_i[T12] = bc[T12]; aa_i[T12] = ba[T12]; ak_i[T12] = bk[T12];
        bc_i[T12] = ac[T12]; ba_i[T12] = aa[T12]; bk_i[T12] = ak[T12];
        bc_i[T13] = cc[T11]; ba_i[T13] = ca[T11]; bk_i[T13] = ck_o[T11];
        cc_i[T11] = bc[T13]; ca_i[T11] = ba[T13]; ck_i[T11] = bk[T13];
        bc_i[T15] = cc[T12]; ba_i[T15] = ca[T12]; bk_i[T15] = ck_o[T12];
        cc_i[T12] = bc[T15]; ca_i[T12] = ba[T15]; ck_i[T12] = bk[T15];
    end

    integer now = 0;
    always @(posedge clk_a) if (t1k_a) now = now + 1;

    // ---- C's unit, as it acts --------------------------------------------------
    integer c_holds = 0, c_unholds = 0, c_claims = 0, c_moncells = 0, b_unholds = 0;
    reg [1:0] mh_d = 2'd0;
    always @(posedge clk_c) begin
        mh_d <= C.u_x.u_net.m_held;
        if (C.u_x.u_net.w_cls && C.u_x.u_net.cst == 3'd2) begin
            c_holds = c_holds + 1;
            $display("    [%0d ms] C HOLD %o (tmr at A %0d)", now, C.u_x.u_net.cls_port, A.u_x.u_net.tmr);
        end
        if (C.u_x.u_net.w_cls && C.u_x.u_net.cst == 3'd4) begin
            c_unholds = c_unholds + 1;
            $display("    [%0d ms] C UNHOLD %o (tmr at A %0d)", now, C.u_x.u_net.cls_port, A.u_x.u_net.tmr);
        end
        if (C.u_x.u_net.w_claim) begin
            c_claims = c_claims + 1;
            $display("    [%0d ms] C CLAIMS %o", now, C.u_x.u_net.m_want_port);
        end
        if ((C.u_x.u_net.m_held & ~mh_d) != 2'd0) begin
            c_moncells = c_moncells + 1;
            $display("    [%0d ms] C attaches a monitor cell (held %b)", now, C.u_x.u_net.m_held);
        end
    end
    integer ci;
    always @(posedge clk_c)
        for (ci = 0; ci < 2; ci = ci + 1)
            if (C.u_x.u_net.m_held[ci] && C.u_x.u_net.d_stb[ci])
                $display("    [%0d ms] C cell %0d counts %0d (state %0d)", now, ci,
                         C.u_x.u_net.d_cnt[ci*4 +: 4], C.u_x.u_net.m_st[ci*2 +: 2]);
    always @(posedge clk_b)
        if (B.u_x.u_net.w_cls && B.u_x.u_net.cst == 3'd4) begin
            b_unholds = b_unholds + 1;
            $display("    [%0d ms] B UNHOLD %o", now, B.u_x.u_net.cls_port);
        end

    task automatic ms(input integer n); begin repeat (n) @(posedge t1k_a); end endtask
    task automatic pulses(input integer n);
        integer i;
        begin for (i = 0; i < n; i = i + 1) begin hook_a[P20] = 1'b0; ms(60); hook_a[P20] = 1'b1; ms(40); end end
    endtask

    integer hi, lo;
    task automatic rings_c(input [`PW-1:0] p);
        integer i;
        begin hi = 0; lo = 0;
            for (i = 0; i < 600; i = i + 1) begin
                @(posedge t1k_c); if (e_c[p]) hi = hi + 1; else lo = lo + 1;
            end
        end
    endtask

    integer offs, off, k, wrong = 0, holds0, claims0;
    integer offl [0:5];
    initial begin offl[0] = 2; offl[1] = 10; offl[2] = 17; offl[3] = 26; offl[4] = 60; offl[5] = 60; end
    initial begin
        if (!$value$plusargs("offs=%d", offs)) offs = 4;   // offsets offl[0..offs]
        $display("\n  tb_brk_rt -- REAL timers (guard lowered to 16 ms so C is the hop at its edge): a dial break inside the T_ARM watch");
        repeat (20) @(posedge clk_a);
        rst_n = 1'b1;
        ms(30);
        ck(up_a[T11] && up_b[T11] && up_b[T13] && up_c[T11], "links up");

        for (k = 0; k <= offs; k = k + 1) begin
            off = offl[k];
            holds0 = c_holds; claims0 = c_claims;
            $display("  -- attempt: first break of e at A's tmr = 16 + %0d ms", off);
            hook_a[P20] = 1'b1; wait (reg_a); ms(300);
            hook_a[P20] = 1'b0; ms(60); hook_a[P20] = 1'b1;        // key 1
            wait (A.u_x.u_net.nst == 4'd4);                       // N_NET: seized
            wait (A.u_x.u_net.tmr == 16 + off);
            pulses(3); ms(800);                                    // e = 3
            pulses(4); ms(800);                                    // b = 4: code 3 4
            pulses(2); ms(800);                                    // h = 2
            pulses(1);                                             // s = 1
            fork
                rings_c(P21);
            join
            $display("     C holds %0d, C claims %0d, A claimed %0d, C21 hi %0d lo %0d",
                     c_holds - holds0, c_claims - claims0, cla_a, hi, lo);
            if (c_claims != claims0 || hi > 20) wrong = wrong + 1;
            hook_a[P20] = 1'b0;
            ms(1500);
            ck(busy_a == 64'd0 && busy_b == 64'd0 && busy_c == 64'd0 &&
               !reg_a && !reg_b && !reg_c && mon_c == 2'd0 && res_b == 2'd0,
               "idle again after the attempt");
        end
        ck(wrong == 0, "1 3 4 2 1 dials nobody: no exchange claims, no phone rings");
        $display("    wrong-number attempts %0d of %0d; C unholds %0d, B unholds %0d, C monitor cells attached %0d",
                 wrong, offs + 1, c_unholds, b_unholds, c_moncells);
        $display("\n  %0d checks, %0d errors.  %s\n", chk, errs, (errs == 0) ? "PASS" : "FAIL");
        $finish;
    end

    initial begin #120_000_000_000; $display("  WATCHDOG"); $finish; end
endmodule
