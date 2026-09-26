// tb_lnet -- two exchanges on a local eight-channel trunk, and calls that are
// DIALLED across it.  trunks.md §3; network.md §1, §4.1.
//
// Exchange A is code 2 2 and exchange B is code 2 3, each top_net with phones
// on block 2 and tone sources at 01 and 03, as tb_net's.  Their only link is
// a local trunk unit on block 1 of each: eight channels, A's facing east and
// B's facing west with glare, all eight reading their unit's one word.  B's
// crystal runs 100 ppm fast, so every call here crosses a plesiochronous link
// and slips about once in 156 ms a channel.
//
//   1  flood     A20 dials 1 2 3 2 1: the key seizes A10, the lowest channel;
//                B claims, B21 rings, voice both ways, release
//   2  two calls A20 up on B21 through A10; A22 dials 1 2 3 2 0 meanwhile and
//                the key takes A11, the busy A10 passed by: two channels at once
//   3  back      B21 dials 1 2 2 2 1: B's word has glare, so its key hunts from
//                the top and takes B17, facing west; A21 rings
//   4  cut       the cable pulled: MUTE_BLK busies all eight ports at both
//                ends, so A20's key finds no trunk and hears cannot-complete
//
// Timers scaled by 8 through the straps, as tb_net's.  Does not cover: glare,
// a transit through a local trunk, a call on all eight channels at once, or a
// cut during a call (tb_ltu drops every A on a cut, patched by hand).
`timescale 1ns/1ps
`include "exch.vh"

module tb_lnet;
    integer chk = 0, errs = 0;
    task ck(input cond, input [8*72-1:0] what);
        begin chk = chk + 1;
             if (!cond) begin errs = errs + 1; $display("    FAIL  %0s", what); end
        end
    endtask

    // 100 ppm apart: the unit's crossing slips, as it will between two racks
    reg clk_a = 1'b0, clk_b = 1'b0, rst_n = 1'b0;
    always #122.070 clk_a = ~clk_a;
    initial begin #40; forever #(122.070 * 1.0001) clk_b = ~clk_b; end

    localparam [`PW-1:0] P20 = 6'o20, P21 = 6'o21, P22 = 6'o22;
    localparam [`PW-1:0] L10 = 6'o10, L11 = 6'o11, L17 = 6'o17;
    localparam [7:0] WE = {2'd2, 1'b0, 3'b010, 2'b11};      // facing E, no glare
    localparam [7:0] WW = {2'd3, 1'b1, 3'b010, 2'b11};      // facing W, glare

    // ---- the two sites -------------------------------------------------------
    reg  [63:0] hook_a = 64'd0, tx_a = 64'd0, hook_b = 64'd0, tx_b = 64'd0;
    wire [63:0] rx_a, e_a, rx_b, e_b, busy_a, busy_b;
    wire [7:0]  lc_a, la_a, lh_a, lk_a, lc_b, la_b, lh_b, lk_b, lup_a, lup_b;
    wire        fs_a, fs_b, t1k_a, t1k_b, rc_a, rc_b;
    wire        sd_a, sc_a, wr_a, cl_a, sd_b, sc_b, wr_b, cl_b;
    wire        reg_a, reg_b, mko_a, mko_b, cla_a, cla_b, hunt_a, hunt_b, uno_a, uno_b;
    wire [2:0]  mks_a, mks_b;
    wire [3:0]  dirs_a, dirs_b;
    wire [1:0]  res_a, res_b, mon_a, mon_b;
    wire [7:0]  gl_a, gl_b, nf_a, nf_b;

    // ---- the cable: block 1 to block 1, and a cut in it ------------------------
    // A cut is receivers whose failsafe reads 1 on an open line.
    reg cut = 1'b0;
    wire [7:0] lc_ai = {6'd0, cut | lc_b[1], 1'b0}, la_ai = {6'd0, cut | la_b[1], 1'b0};
    wire [7:0] lh_ai = {6'd0, cut | lh_b[1], 1'b0}, lk_ai = {6'd0, cut | lk_b[1], 1'b0};
    wire [7:0] lc_bi = {6'd0, cut | lc_a[1], 1'b0}, la_bi = {6'd0, cut | la_a[1], 1'b0};
    wire [7:0] lh_bi = {6'd0, cut | lh_a[1], 1'b0}, lk_bi = {6'd0, cut | lk_a[1], 1'b0};

    site_net #(.PHONES(64'h0000_0000_0007_0000), .TRUNKS(64'd0),
               .LTU(8'b0000_0010), .LTWORD({56'd0, WE, 8'd0}),
               .OWN_E(3'd2), .OWN_B(3'd2),
               .T_ARM(9'd2), .T_REL(9'd32), .RING_ON(13'd64), .RING_OFF(13'd128),
               .HIT(9'd1), .ID(9'd16), .CLR(9'd32), .NODIG(16'd1250),
               .T_GUARD0(16'd16), .T_KEY(16'd625), .T_CLAIM(16'd250)) A (
        .clk(clk_a), .rst_n(rst_n), .hook(hook_a), .tx(tx_a), .rx(rx_a), .e(e_a),
        .c_out(), .a_out(), .clk_out(), .c_in(64'd0), .a_in(64'd0), .clk_in(64'd0),
        .link_up(),
        .lt_c_out(lc_a), .lt_a_out(la_a), .lt_h_out(lh_a), .lt_k_out(lk_a),
        .lt_c_in(lc_ai), .lt_a_in(la_ai), .lt_h_in(lh_ai), .lt_k_in(lk_ai), .lt_up(lup_a),
        .frame_stb(fs_a), .tick_1k(t1k_a), .ring_cad_n(rc_a), .port_busy(busy_a),
        .b_sdata(sd_a), .b_sclk(sc_a), .b_wr(wr_a), .b_clash(cl_a),
        .reg_busy(reg_a), .mk_state(mks_a), .mk_ovf(mko_a), .dirs_held(dirs_a),
        .res_busy(res_a), .mon_held(mon_a), .claimed(cla_a), .hunting(hunt_a),
        .un_ovf(uno_a), .n_glare(gl_a), .n_nofwd(nf_a));

    site_net #(.PHONES(64'h0000_0000_0003_0000), .TRUNKS(64'd0),
               .LTU(8'b0000_0010), .LTWORD({56'd0, WW, 8'd0}),
               .OWN_E(3'd2), .OWN_B(3'd3),
               .T_ARM(9'd2), .T_REL(9'd32), .RING_ON(13'd64), .RING_OFF(13'd128),
               .HIT(9'd1), .ID(9'd16), .CLR(9'd32), .NODIG(16'd1250),
               .T_GUARD0(16'd16), .T_KEY(16'd625), .T_CLAIM(16'd250)) B (
        .clk(clk_b), .rst_n(rst_n), .hook(hook_b), .tx(tx_b), .rx(rx_b), .e(e_b),
        .c_out(), .a_out(), .clk_out(), .c_in(64'd0), .a_in(64'd0), .clk_in(64'd0),
        .link_up(),
        .lt_c_out(lc_b), .lt_a_out(la_b), .lt_h_out(lh_b), .lt_k_out(lk_b),
        .lt_c_in(lc_bi), .lt_a_in(la_bi), .lt_h_in(lh_bi), .lt_k_in(lk_bi), .lt_up(lup_b),
        .frame_stb(fs_b), .tick_1k(t1k_b), .ring_cad_n(rc_b), .port_busy(busy_b),
        .b_sdata(sd_b), .b_sclk(sc_b), .b_wr(wr_b), .b_clash(cl_b),
        .reg_busy(reg_b), .mk_state(mks_b), .mk_ovf(mko_b), .dirs_held(dirs_b),
        .res_busy(res_b), .mon_held(mon_b), .claimed(cla_b), .hunting(hunt_b),
        .un_ovf(uno_b), .n_glare(gl_b), .n_nofwd(nf_b));

    // ---- two '244s on one wire, at either exchange ------------------------------
    integer clash = 0;
    always @(posedge clk_a) if (cl_a) clash = clash + 1;
    always @(posedge clk_b) if (cl_b) clash = clash + 1;

    // ---- the bench's hands: tb_net's --------------------------------------------
    task ms(input integer n); begin repeat (n) @(posedge t1k_a); end endtask

    task dial_a(input [`PW-1:0] p, input integer d);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                hook_a[p] = 1'b0; ms(12);
                hook_a[p] = 1'b1; ms(8);
            end
            ms(100);
        end
    endtask
    task dial_b(input [`PW-1:0] p, input integer d);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                hook_b[p] = 1'b0; ms(12);
                hook_b[p] = 1'b1; ms(8);
            end
            ms(100);
        end
    endtask

    integer j; reg s0, s1;
    task hear_a(input [`PW-1:0] p);
        begin s0 = 1'b0; s1 = 1'b0;
            for (j = 0; j < 8; j = j + 1) begin
                @(posedge fs_a); @(posedge clk_a);
                if (rx_a[p]) s1 = 1'b1; else s0 = 1'b1;
            end
        end
    endtask

    integer hi, lo;
    task rings_b(input [`PW-1:0] p);
        integer i;
        begin hi = 0; lo = 0;
            for (i = 0; i < 400; i = i + 1) begin
                @(posedge t1k_b); if (e_b[p]) hi = hi + 1; else lo = lo + 1;
            end
        end
    endtask
    task rings_a(input [`PW-1:0] p);
        integer i;
        begin hi = 0; lo = 0;
            for (i = 0; i < 400; i = i + 1) begin
                @(posedge t1k_a); if (e_a[p]) hi = hi + 1; else lo = lo + 1;
            end
        end
    endtask

    task idle_all(input [8*72-1:0] what);
        begin
            ms(400);
            ck(busy_a == 64'd0 && busy_b == 64'd0 && !reg_a && !reg_b &&
               mks_a == 3'd0 && mks_b == 3'd0 && dirs_a == 4'd0 && dirs_b == 4'd0 &&
               res_a == 2'd0 && res_b == 2'd0, what);
        end
    endtask

    initial begin
        $display("\n  tb_lnet -- two exchanges, a local eight-channel trunk, calls that are dialled");
        repeat (20) @(posedge clk_a);
        rst_n = 1'b1;
        ms(20);
        ck(lup_a[1] && lup_b[1], "both units see the far HCLK: the link is up");
        ck(busy_a[15:8] === 8'd0 && busy_b[15:8] === 8'd0, "and all sixteen channels are free");

        // ================= 1.  the flood, across the unit ======================
        $display("  1. A20 dials 1 2 3 2 1");
        hook_a[P20] = 1'b1; ms(10);
        dial_a(P20, 1);
        ck(busy_a[L10] === 1'b1 && busy_a[15:9] === 7'd0 && dirs_a == 4'b0100,
           "the key seized one channel, the lowest facing E: A10");
        ck(busy_b[L10] === 1'b1, "B holds the seizure on its channel 0: B10 is BUSY");
        ck(reg_b === 1'b0, "and B's marker did not take the channel's M as a call");
        dial_a(P20, 2); dial_a(P20, 3);
        ck(cla_a === 1'b1, "the claim came back across the unit: backward A at the origin");
        ck(reg_b === 1'b1, "B gave the claimed channel its register");
        dial_a(P20, 2); dial_a(P20, 1); ms(20);
        rings_b(P21); ck(hi > 50 && lo > 50, "B21 rings, from a caller on A");
        hook_b[P21] = 1'b1; ms(20);
        tx_a[P20] = 1'b1; ms(4); ck(rx_b[P21] === 1'b1, "B21 hears A20 through the unit");
        tx_a[P20] = 1'b0; ms(4); ck(rx_b[P21] === 1'b0, "and follows it");
        tx_b[P21] = 1'b1; ms(4); ck(rx_a[P20] === 1'b1, "A20 hears B21: the other way");
        tx_b[P21] = 1'b0; ms(4); ck(rx_a[P20] === 1'b0, "and follows it");
        hook_b[P21] = 1'b0; ms(150);
        hook_a[P20] = 1'b0;
        idle_all("1: release ran through every patch, both exchanges idle");

        // ================= 2.  two channels at once ==========================
        $display("  2. A20 up on B21 through A10; then A22 dials 1 2 3 2 0");
        hook_a[P20] = 1'b1; ms(10);
        dial_a(P20, 1); dial_a(P20, 2); dial_a(P20, 3); dial_a(P20, 2); dial_a(P20, 1);
        ms(20); hook_b[P21] = 1'b1; ms(20);
        ck(busy_a[L10] === 1'b1 && reg_a === 1'b0,
           "the first call is up through A10, and A's register is free again");
        hook_a[P22] = 1'b1; ms(10);
        dial_a(P22, 1);
        ck(busy_a[L11] === 1'b1 && dirs_a == 4'b0100,
           "the second key seized A11: the busy A10 was read and passed by");
        dial_a(P22, 2); dial_a(P22, 3);
        ck(cla_a === 1'b1, "and B claimed the second call, on its 11");
        dial_a(P22, 2); dial_a(P22, 0); ms(20);
        rings_b(P20); ck(hi > 50 && lo > 50, "B20 rings: two calls on two channels at once");
        hook_b[P20] = 1'b1; ms(20);
        tx_a[P22] = 1'b1; ms(4); ck(rx_b[P20] === 1'b1, "B20 hears A22 on channel 1");
        tx_a[P22] = 1'b0; ms(4); ck(rx_b[P20] === 1'b0, "and follows it");
        tx_a[P20] = 1'b1; ms(4); ck(rx_b[P21] === 1'b1, "while B21 still hears A20 on channel 0");
        tx_a[P20] = 1'b0; ms(4); ck(rx_b[P21] === 1'b0, "and follows it");
        hook_a[P20] = 1'b0; hook_a[P22] = 1'b0; hook_b[P20] = 1'b0; hook_b[P21] = 1'b0;
        idle_all("2: both calls released, both exchanges idle");

        // ================= 3.  the other way ================================
        $display("  3. B21 dials 1 2 2 2 1");
        hook_b[P21] = 1'b1; ms(10);
        dial_b(P21, 1);
        ck(busy_b[L17] === 1'b1 && busy_b[14:8] === 7'd0 && dirs_b == 4'b1000,
           "B's word has glare, so its key hunts from the top: B17, facing W");
        ck(busy_a[L17] === 1'b1 && busy_a[14:8] === 7'd0,
           "and the call arrives on A17, the far end of the group from A's own hunt");
        dial_b(P21, 2); dial_b(P21, 2);
        ck(cla_b === 1'b1, "A claimed");
        dial_b(P21, 2); dial_b(P21, 1); ms(20);
        rings_a(P21); ck(hi > 50 && lo > 50, "A21 rings, from a caller on B");
        hook_a[P21] = 1'b1; ms(20);
        tx_b[P21] = 1'b1; ms(4); ck(rx_a[P21] === 1'b1, "A21 hears B21");
        tx_a[P21] = 1'b1; ms(4); ck(rx_b[P21] === 1'b1, "and B21 hears A21");
        tx_a[P21] = 1'b0; tx_b[P21] = 1'b0;
        hook_b[P21] = 1'b0; hook_a[P21] = 1'b0;
        idle_all("3: idle again");

        // ================= 4.  the cable pulled ===============================
        $display("  4. the cable pulled");
        cut = 1'b1; ms(5);
        ck(!lup_a[1] && !lup_b[1], "both units read the link down");
        ck(busy_a[15:8] === 8'hFF && busy_b[15:8] === 8'hFF,
           "MUTE_BLK: all eight channels BUSY at both ends");
        hook_a[P20] = 1'b1; ms(10);
        dial_a(P20, 1); ms(40);
        ck(dirs_a == 4'd0, "the key seized nothing");
        hear_a(P20); ck(s0 && !s1, "and A20 hears cannot-complete");
        hook_a[P20] = 1'b0;
        cut = 1'b0; ms(20);
        ck(lup_a[1] && lup_b[1] && busy_a[15:8] === 8'd0 && busy_b[15:8] === 8'd0,
           "mended: the link comes up and the group is free again");
        idle_all("4: idle again");

        // ================= throughout ===========================================
        ck(clash == 0, "cable B never had two masters driving at once");
        ck(!mko_a && !mko_b && !uno_a && !uno_b, "no queue on either exchange refused a write");

        $display("\n  %0d checks, %0d errors.  %s\n", chk, errs,
                 (errs == 0) ? "PASS" : "FAIL");
        if (errs) $fatal(1);
        $finish;
    end

    initial begin #30_000_000_000; $display("  TIMEOUT"); $fatal(1); end

    wire _unused = &{1'b0, rc_a, rc_b, fs_b, t1k_b, sd_a, sc_a, wr_a, sd_b, sc_b, wr_b,
                     hunt_a, hunt_b, mon_a, mon_b, gl_a, gl_b, nf_a, nf_b,
                     lc_a, la_a, lh_a, lk_a, lc_b, la_b, lh_b, lk_b, lup_a, lup_b,
                     e_a, e_b, 1'b0};
endmodule
