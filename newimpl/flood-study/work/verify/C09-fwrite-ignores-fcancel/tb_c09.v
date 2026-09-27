// tb_c09 -- VERIFY C09 (F_WRITE ignores f_cancel) with a real far end and
// REAL TIMERS throughout (site_net defaults: T_ARM 16, T_REL 256, HIT 8,
// ID 128, CLR 256, NODIG 10000, T_GUARD0 128, T_KEY 5000, T_CLAIM 2000).
//
//     A 2 2  A11 ======== B77  B 2 3  B13 ==== silent far end (link up, A=0)
//            faces E          faces W        faces E
//
// The seizure that dies is a real one: A20 dials 1 (60/40 ms), A floods on
// A11 listening to A20, B holds 77 and forwards it on 13 (one leg).  A20 then
// HANGS UP (a conforming subscriber) while B's forward is in CONFIRM, so B77's
// first low sample is CONFIRM's last (port 77), the tick of h_done.
//
//   stage 1   after the hang-up: B77, B13 not BUSY and no resolver held
//   stage 2   A20 calls B21 (1 2 3 2 1): B must claim (A's origin sees the claim)
//   stage 3   all idle after A20 hangs up
//
// +k=<n>   hang up when B's scan reaches n in the CONFIRM pass (default 4)
`timescale 1ns/1ps
`include "exch.vh"

module blog9 #(parameter [7:0] NAME = "A") (
    input clk, input t1k, input sd, input sc, input wr, input moe, input uoe);
    reg [15:0] sh = 16'd0; reg sc_d = 1'b0, wr_d = 1'b0;
    integer msn = 0;
    always @(posedge clk) begin
        if (t1k) msn = msn + 1;
        sc_d <= sc; wr_d <= wr;
        if (sc && !sc_d) sh <= {sh[14:0], sd};
        if (wr && !wr_d)
            $display("    [%0d ms] %c cableB %s G%0d dst %o src %o bsy %0d clm %0d",
                     msn, NAME, uoe ? "UNIT  " : (moe ? "MARKER" : "??    "),
                     sh[15], sh[13:8], sh[7:2], sh[1], sh[0]);
    end
endmodule

module tb_c09;
    integer chk = 0, errs = 0;
    task ck(input cond, input [8*80-1:0] what);
        begin chk = chk + 1;
             if (!cond) begin errs = errs + 1; $display("    FAIL  %0s", what); end
             else $display("    ok    %0s", what);
        end
    endtask

    reg clk_a = 1'b0, clk_b = 1'b0, rst_n = 1'b0;
    always #122.070 clk_a = ~clk_a;
    initial begin #40; forever #122.070 clk_b = ~clk_b; end

    localparam [`PW-1:0] P20 = 6'o20, P21 = 6'o21;
    localparam [`PW-1:0] T11 = 6'o11, T13 = 6'o13, T77 = 6'o77;
    localparam [7:0] WE0 = {2'd2, 1'b0, 3'b010, 2'b11};     // facing E
    localparam [7:0] WW1 = {2'd3, 1'b1, 3'b010, 2'b11};     // facing W, glare
    localparam [511:0] TW_A = ({504'd0, WE0} << (8*T11));
    localparam [511:0] TW_B = ({504'd0, WW1} << (8*T77)) | ({504'd0, WE0} << (8*T13));

    reg  [63:0] hook_a = 0, tx_a = 0, hook_b = 0, tx_b = 0;
    wire [63:0] rx_a, e_a, rx_b, e_b, busy_a, busy_b;
    wire [63:0] ac, aa, ak, bc, ba, bk, up_a, up_b;
    reg  [63:0] ac_i, aa_i, ak_i, bc_i, ba_i, bk_i;
    wire        fs_a, fs_b, t1k_a, t1k_b, rc_a, rc_b;
    wire        sd_a, sc_a, wr_a, cl_a, sd_b, sc_b, wr_b, cl_b;
    wire        reg_a, reg_b, mo_a, mo_b, cla_a, cla_b, hu_a, hu_b, uo_a, uo_b;
    wire [2:0]  ms_a, ms_b;
    wire [3:0]  dirs_a, dirs_b;
    wire [1:0]  res_a, res_b, mon_a, mon_b;
    wire [7:0]  gl_a, gl_b, nf_a, nf_b;

    site_net #(.TRUNKS(64'd1 << T11), .TWORD(TW_A), .OWN_E(3'd2), .OWN_B(3'd2)) A (
        .clk(clk_a), .rst_n(rst_n), .hook(hook_a), .tx(tx_a), .rx(rx_a), .e(e_a),
        .c_out(ac), .a_out(aa), .clk_out(ak), .c_in(ac_i), .a_in(aa_i), .clk_in(ak_i),
        .link_up(up_a), .frame_stb(fs_a), .tick_1k(t1k_a), .ring_cad_n(rc_a),
        .port_busy(busy_a), .b_sdata(sd_a), .b_sclk(sc_a), .b_wr(wr_a), .b_clash(cl_a),
        .reg_busy(reg_a), .mk_state(ms_a), .mk_ovf(mo_a), .dirs_held(dirs_a),
        .res_busy(res_a), .mon_held(mon_a), .claimed(cla_a), .hunting(hu_a),
        .un_ovf(uo_a), .n_glare(gl_a), .n_nofwd(nf_a));

    site_net #(.TRUNKS((64'd1 << T77) | (64'd1 << T13)), .TWORD(TW_B),
               .OWN_E(3'd2), .OWN_B(3'd3)) B (
        .clk(clk_b), .rst_n(rst_n), .hook(hook_b), .tx(tx_b), .rx(rx_b), .e(e_b),
        .c_out(bc), .a_out(ba), .clk_out(bk), .c_in(bc_i), .a_in(ba_i), .clk_in(bk_i),
        .link_up(up_b), .frame_stb(fs_b), .tick_1k(t1k_b), .ring_cad_n(rc_b),
        .port_busy(busy_b), .b_sdata(sd_b), .b_sclk(sc_b), .b_wr(wr_b), .b_clash(cl_b),
        .reg_busy(reg_b), .mk_state(ms_b), .mk_ovf(mo_b), .dirs_held(dirs_b),
        .res_busy(res_b), .mon_held(mon_b), .claimed(cla_b), .hunting(hu_b),
        .un_ovf(uo_b), .n_glare(gl_b), .n_nofwd(nf_b));

    // ---- the cables: A11-B77; B13 to a far end that is up and never seizes ----
    always @* begin
        ac_i = 0; aa_i = 0; ak_i = 0; bc_i = 0; ba_i = 0; bk_i = 0;
        ac_i[T11] = bc[T77]; aa_i[T11] = ba[T77]; ak_i[T11] = bk[T77];
        bc_i[T77] = ac[T11]; ba_i[T77] = aa[T11]; bk_i[T77] = ak[T11];
        bc_i[T13] = bc[T13]; ba_i[T13] = 1'b0;    bk_i[T13] = bk[T13];
    end

    blog9 #(.NAME("B")) LB (.clk(clk_b), .t1k(t1k_b), .sd(sd_b), .sc(sc_b), .wr(wr_b),
                            .moe(B.u_x.m_oe), .uoe(B.u_x.u_oe));

    integer now = 0;
    always @(posedge clk_a) if (t1k_a) now = now + 1;

    integer clash = 0;
    always @(posedge clk_a) if (cl_a) clash = clash + 1;
    always @(posedge clk_b) if (cl_b) clash = clash + 1;

    // B's unit, as it decides
    wire b77_m = B.u_x.u_exch.pos[7].u_blk.u_port7.m;
    reg  b77_m_d = 1'b0;
    always @(posedge clk_b) begin
        b77_m_d <= b77_m;
        if (b77_m != b77_m_d)
            $display("    [%0d ms] B77's M -> %0d at B scan %0d (hst %0d fst %0d)", now, b77_m,
                     B.scan, B.u_x.u_net.hst, B.u_x.u_net.fst);
        if (B.u_x.u_net.h_done)
            $display("    [%0d ms] B sweep done (h_done), owner %0d h_ok %b, last CONFIRM visit %o, fst %0d",
                     now, B.u_x.u_net.h_owner, B.u_x.u_net.h_ok, B.u_x.u_net.sp_port, B.u_x.u_net.fst);
        if (B.u_x.u_net.w_cls && B.u_x.u_net.cst == 3'd4)
            $display("    [%0d ms] B UNHOLD pushed for %o; fst %0d f_in %o", now,
                     B.u_x.u_net.cls_port, B.u_x.u_net.fst, B.u_x.u_net.f_in);
        if (B.u_x.u_net.w_cls && B.u_x.u_net.cst == 3'd2)
            $display("    [%0d ms] B HOLD pushed for %o", now, B.u_x.u_net.cls_port);
        if (B.u_x.u_net.w_fwd)
            $display("    [%0d ms] B FORWARD pushed: f_in %o f_ok %b f_cancel %0d", now,
                     B.u_x.u_net.f_in, B.u_x.u_net.f_ok, B.u_x.u_net.f_cancel);
    end

    task ms(input integer n); begin repeat (n) @(posedge t1k_a); end endtask

    // 10 pps, 60/40, then the 720 ms minimum pause
    task dial(input [`PW-1:0] p, input integer d);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                hook_a[p] = 1'b0; ms(60); hook_a[p] = 1'b1; ms(40);
            end
            ms(720);
        end
    endtask

    integer k, t0;
    wire [`PW-1:0] b77_addr = B.u_x.u_exch.pos[7].u_blk.u_port7.addr;
    wire           b77_bsy  = B.u_x.u_exch.pos[7].u_blk.u_port7.bsy;
    wire           b77_fm   = B.u_x.u_exch.pos[7].u_blk.u_port7.fm;
    wire [`PW-1:0] b13_addr = B.u_x.u_exch.pos[1].u_blk.u_port3.addr;
    wire           b13_bsy  = B.u_x.u_exch.pos[1].u_blk.u_port3.bsy;

    initial begin
        if (!$value$plusargs("k=%d", k)) k = 4;
        $display("\n  tb_c09 -- A20 hangs up in B's CONFIRM, real timers, k %0d", k);
        repeat (20) @(posedge clk_a);
        rst_n = 1'b1;
        ms(200);
        ck(up_a[T11] && up_b[T77] && up_b[T13], "links up");

        // ================= 1. the seizure that dies ==========================
        hook_a[P20] = 1'b1; ms(300);
        $display("    [%0d ms] A20 dials 1", now);
        hook_a[P20] = 1'b0; ms(60); hook_a[P20] = 1'b1;
        wait (B.u_x.u_net.hst == 3'd2 && B.u_x.u_net.h_owner == 1'b1);   // B's forward in CONFIRM
        $display("    [%0d ms] B's forward in CONFIRM; B77 fM %0d", now, b77_fm);
        wait (B.scan == k[5:0]);
        hook_a[P20] = 1'b0; t0 = now;
        $display("    [%0d ms] A20 hangs up (B scan %0d)", now, B.scan);
        ms(20);
        $display("    [%0d ms] B77 addr %o bsy %0d fM %0d; B13 addr %o bsy %0d; res_b %b mon_b %b",
                 now, b77_addr, b77_bsy, b77_fm, b13_addr, b13_bsy, res_b, mon_b);
        ms(3000);
        $display("    [%0d ms] 3 s on: B77 addr %o bsy %0d BUSY %0d; B13 addr %o bsy %0d BUSY %0d; res_b %b mon_b %b; A busy %h",
                 now, b77_addr, b77_bsy, busy_b[T77], b13_addr, b13_bsy, busy_b[T13], res_b, mon_b, busy_a);
        ck(busy_b[T77] === 1'b0, "1: B77, whose seizure died, is not BUSY 3 s on");
        ck(busy_b[T13] === 1'b0, "1: B13, the leg forwarded from it, is not BUSY");
        ck(res_b == 2'd0, "1: no resolver held at B");

        // ================= 2. the next call from A to B ======================
        $display("    [%0d ms] A20 calls B21: 1 2 3 2 1", now);
        hook_a[P20] = 1'b1; ms(300);
        dial(P20, 1);
        $display("    [%0d ms] after key 1: A dirs %b, B77 BUSY %0d, B mon %b res %b", now,
                 dirs_a, busy_b[T77], mon_b, res_b);
        dial(P20, 2); dial(P20, 3);
        ms(200);
        $display("    [%0d ms] after b: A claimed %0d, B reg %0d, B mon %b", now, cla_a, reg_b, mon_b);
        ck(cla_a === 1'b1 && reg_b === 1'b1, "2: B claimed A20's call to it");
        dial(P20, 2); dial(P20, 1);
        ms(500);
        $display("    [%0d ms] after h s: A claimed %0d, B reg %0d, A reg %0d", now, cla_a, reg_b, reg_a);
        hook_a[P20] = 1'b0;

        // ================= 3. all idle ========================================
        ms(1500);
        $display("    [%0d ms] 1.5 s after A20 hangs up: B77 addr %o bsy %0d; B13 addr %o bsy %0d; res_b %b; busy_a %h busy_b %h",
                 now, b77_addr, b77_bsy, b13_addr, b13_bsy, res_b, busy_a, busy_b);
        ck(busy_a == 64'd0 && busy_b == 64'd0 && res_b == 2'd0 && !reg_a && !reg_b,
           "3: A and B idle after the second call");
        ck(clash == 0 && !mo_a && !mo_b && !uo_a && !uo_b, "no clash, no overflow");
        $display("\n  %0d checks, %0d errors.  %s\n", chk, errs, (errs == 0) ? "PASS" : "FAIL");
        $finish;
    end

    initial begin #30_000_000_000; $display("  WATCHDOG"); $finish; end

    wire _unused = &{1'b0, rx_a, rx_b, e_a, fs_a, fs_b, rc_a, t1k_b, sd_a, sc_a, wr_a,
                     ms_a, ms_b, hu_a, hu_b, res_a, mon_a, dirs_b, gl_a, gl_b, nf_a, nf_b,
                     cla_b, tx_b, hook_b, 1'b0};
endmodule
