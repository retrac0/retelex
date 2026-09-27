// tb_lchain -- three exchanges on two local eight-channel trunks, and calls
// that TRANSIT the middle one across both units.  trunks.md §3; network.md
// §1, §3.5, §4.
//
//     A 2 2  blk 1 ======== blk 1  B 2 3  blk 3 ======== blk 1  C 2 4
//            faces E        faces W, g    faces E        faces W, g
//
// tb_chain's chain, with every link a local trunk instead of baseband cards:
// each link is eight channels on one cable, and every channel of a group reads
// its unit's one word.  B has phones on 20-27; A and C on 20 and 21.  B runs
// 100 ppm fast and C 100 ppm slow, so each hop crosses a plesiochronous link
// and slips.
//
//   1  transit     A20 dials 1 2 4 2 1: A10, B10 held and forwarded to B30,
//                  the lowest channel facing E, C10.  B's monitor lets go at
//                  b, C claims, B's resolver frees itself, B holds no register
//   2  two at once A21 dials 1 2 4 2 0 with the first call up: A11, B11, B31,
//                  C11 -- two transits through B, each on its own channels,
//                  each carrying only its own pair
//   3  local at B  with both transits standing, B20 dials 2 2, B21 2 3 and
//                  B24 2 6: three two-digit calls among six of B's lines,
//                  each pair hearing only itself, and the transits untouched
//   4  back        C21 dials 1 2 2 2 1: C's glare hunts from the top, C17; B
//                  forwards west from the top of its glare group, B17; the
//                  call lands on A17 and A21 rings
//   5  the middle  B20 dials 1 2 4 2 0: B floods both ways, B17 west and B30
//                  east; C claims and B lets the west channel go at the claim
//
// Timers scaled by 8, as tb_chain; the sweeps are not.  Does not cover: a hub,
// a ring, glare (tb_lfull), or a transit's forward refused because every
// onward channel is busy.
`timescale 1ns/1ps
`include "exch.vh"

module tb_lchain;
    integer chk = 0, errs = 0;
    task ck(input cond, input [8*72-1:0] what);
        begin chk = chk + 1;
             if (!cond) begin errs = errs + 1; $display("    FAIL  %0s", what); end
        end
    endtask

    reg clk_a = 1'b0, clk_b = 1'b0, clk_c = 1'b0, rst_n = 1'b0;
    always #122.070 clk_a = ~clk_a;
    initial begin #40; forever #(122.070 * 1.0001) clk_b = ~clk_b; end
    initial begin #90; forever #(122.070 * 0.9999) clk_c = ~clk_c; end

    localparam [`PW-1:0] P20 = 6'o20, P21 = 6'o21, P22 = 6'o22, P23 = 6'o23;
    localparam [`PW-1:0] P24 = 6'o24, P26 = 6'o26;
    localparam [7:0] WE = {2'd2, 1'b0, 3'b010, 2'b11};      // facing E, no glare
    localparam [7:0] WW = {2'd3, 1'b1, 3'b010, 2'b11};      // facing W, glare

    reg  [63:0] hook_a = 0, tx_a = 0, hook_b = 0, tx_b = 0, hook_c = 0, tx_c = 0;
    wire [63:0] rx_a, e_a, rx_b, e_b, rx_c, e_c, busy_a, busy_b, busy_c;
    wire [7:0]  lc_a, la_a, lh_a, lk_a, lc_b, la_b, lh_b, lk_b, lc_c, la_c, lh_c, lk_c;
    wire [7:0]  up_a, up_b, up_c;
    wire        fs_a, fs_b, fs_c, t1k_a, t1k_b, t1k_c, rc_a, rc_b, rc_c;
    wire        sd_a, sc_a, wr_a, cl_a, sd_b, sc_b, wr_b, cl_b, sd_c, sc_c, wr_c, cl_c;
    wire        reg_a, reg_b, reg_c, mo_a, mo_b, mo_c, cla_a, cla_b, cla_c;
    wire        creg_a, creg_b, creg_c;   // the claim registers
    wire        hu_a, hu_b, hu_c, uo_a, uo_b, uo_c;
    wire [2:0]  ms_a, ms_b, ms_c;
    wire [3:0]  dirs_a, dirs_b, dirs_c;
    wire [1:0]  res_a, res_b, res_c, mon_a, mon_b, mon_c;
    wire [7:0]  gl_a, gl_b, gl_c, nf_a, nf_b, nf_c;

    // ---- the cables: A blk 1 to B blk 1, B blk 3 to C blk 1 ---------------------
    wire [7:0] lc_ai = {6'd0, lc_b[1], 1'b0}, la_ai = {6'd0, la_b[1], 1'b0};
    wire [7:0] lh_ai = {6'd0, lh_b[1], 1'b0}, lk_ai = {6'd0, lk_b[1], 1'b0};
    wire [7:0] lc_bi = {4'd0, lc_c[1], 1'b0, lc_a[1], 1'b0}, la_bi = {4'd0, la_c[1], 1'b0, la_a[1], 1'b0};
    wire [7:0] lh_bi = {4'd0, lh_c[1], 1'b0, lh_a[1], 1'b0}, lk_bi = {4'd0, lk_c[1], 1'b0, lk_a[1], 1'b0};
    wire [7:0] lc_ci = {6'd0, lc_b[3], 1'b0}, la_ci = {6'd0, la_b[3], 1'b0};
    wire [7:0] lh_ci = {6'd0, lh_b[3], 1'b0}, lk_ci = {6'd0, lk_b[3], 1'b0};

`define SITE_PARAMS .TRUNKS(64'd0), .OWN_E(3'd2), \
        .T_ARM(9'd2), .T_REL(9'd32), .RING_ON(13'd64), .RING_OFF(13'd128), \
        .HIT(9'd1), .ID(9'd16), .CLR(9'd32), .NODIG(16'd1250), \
        .T_GUARD0(16'd16), .T_KEY(16'd625), .T_CLAIM(16'd250)

    site_net #(`SITE_PARAMS, .PHONES(64'h0000_0000_0003_0000), .OWN_B(3'd2),
               .STRAP_N(4'b1011),                     // a leaf: N S W strapped
               .LTU(8'b0000_0010), .LTWORD({56'd0, WE, 8'd0})) A (
        .clk(clk_a), .rst_n(rst_n), .hook(hook_a), .tx(tx_a), .rx(rx_a), .e(e_a),
        .c_out(), .a_out(), .clk_out(), .c_in(64'd0), .a_in(64'd0), .clk_in(64'd0),
        .link_up(),
        .lt_c_out(lc_a), .lt_a_out(la_a), .lt_h_out(lh_a), .lt_k_out(lk_a),
        .lt_c_in(lc_ai), .lt_a_in(la_ai), .lt_h_in(lh_ai), .lt_k_in(lk_ai), .lt_up(up_a),
        .frame_stb(fs_a), .tick_1k(t1k_a), .ring_cad_n(rc_a),
        .port_busy(busy_a), .b_sdata(sd_a), .b_sclk(sc_a), .b_wr(wr_a), .b_clash(cl_a),
        .reg_busy(reg_a), .creg_busy(creg_a), .mk_state(ms_a), .mk_ovf(mo_a), .dirs_held(dirs_a),
        .res_busy(res_a), .mon_held(mon_a), .claimed(cla_a), .hunting(hu_a),
        .un_ovf(uo_a), .n_glare(gl_a), .n_nofwd(nf_a));

    site_net #(`SITE_PARAMS, .PHONES(64'h0000_0000_00FF_0000), .OWN_B(3'd3),
               .LTU(8'b0000_1010), .LTWORD({32'd0, WE, 8'd0, WW, 8'd0})) B (
        .clk(clk_b), .rst_n(rst_n), .hook(hook_b), .tx(tx_b), .rx(rx_b), .e(e_b),
        .c_out(), .a_out(), .clk_out(), .c_in(64'd0), .a_in(64'd0), .clk_in(64'd0),
        .link_up(),
        .lt_c_out(lc_b), .lt_a_out(la_b), .lt_h_out(lh_b), .lt_k_out(lk_b),
        .lt_c_in(lc_bi), .lt_a_in(la_bi), .lt_h_in(lh_bi), .lt_k_in(lk_bi), .lt_up(up_b),
        .frame_stb(fs_b), .tick_1k(t1k_b), .ring_cad_n(rc_b),
        .port_busy(busy_b), .b_sdata(sd_b), .b_sclk(sc_b), .b_wr(wr_b), .b_clash(cl_b),
        .reg_busy(reg_b), .creg_busy(creg_b), .mk_state(ms_b), .mk_ovf(mo_b), .dirs_held(dirs_b),
        .res_busy(res_b), .mon_held(mon_b), .claimed(cla_b), .hunting(hu_b),
        .un_ovf(uo_b), .n_glare(gl_b), .n_nofwd(nf_b));

    site_net #(`SITE_PARAMS, .PHONES(64'h0000_0000_0003_0000), .OWN_B(3'd4),
               .STRAP_N(4'b0111),                     // a leaf: N S E strapped
               .LTU(8'b0000_0010), .LTWORD({56'd0, WW, 8'd0})) C (
        .clk(clk_c), .rst_n(rst_n), .hook(hook_c), .tx(tx_c), .rx(rx_c), .e(e_c),
        .c_out(), .a_out(), .clk_out(), .c_in(64'd0), .a_in(64'd0), .clk_in(64'd0),
        .link_up(),
        .lt_c_out(lc_c), .lt_a_out(la_c), .lt_h_out(lh_c), .lt_k_out(lk_c),
        .lt_c_in(lc_ci), .lt_a_in(la_ci), .lt_h_in(lh_ci), .lt_k_in(lk_ci), .lt_up(up_c),
        .frame_stb(fs_c), .tick_1k(t1k_c), .ring_cad_n(rc_c),
        .port_busy(busy_c), .b_sdata(sd_c), .b_sclk(sc_c), .b_wr(wr_c), .b_clash(cl_c),
        .reg_busy(reg_c), .creg_busy(creg_c), .mk_state(ms_c), .mk_ovf(mo_c), .dirs_held(dirs_c),
        .res_busy(res_c), .mon_held(mon_c), .claimed(cla_c), .hunting(hu_c),
        .un_ovf(uo_c), .n_glare(gl_c), .n_nofwd(nf_c));

    integer clash = 0;
    always @(posedge clk_a) if (cl_a) clash = clash + 1;
    always @(posedge clk_b) if (cl_b) clash = clash + 1;
    always @(posedge clk_c) if (cl_c) clash = clash + 1;

    // ---- a register at B while only transits pass ------------------------------
    reg watch_b = 1'b0; integer b_reg_seen = 0;
    always @(posedge clk_b) if (watch_b && (reg_b || creg_b)) b_reg_seen = b_reg_seen + 1;

    task ms(input integer n); begin repeat (n) @(posedge t1k_a); end endtask

    // one dial for all three: which exchange's phone is chosen by `x`
    task dial(input integer x, input [`PW-1:0] p, input integer d);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                if (x == 0) hook_a[p] = 1'b0; else if (x == 1) hook_b[p] = 1'b0; else hook_c[p] = 1'b0;
                ms(12);
                if (x == 0) hook_a[p] = 1'b1; else if (x == 1) hook_b[p] = 1'b1; else hook_c[p] = 1'b1;
                ms(8);
            end
            ms(100);
        end
    endtask

    // does it ring within 250 ms?  A cadence is 64 on, 128 off, scaled
    reg rang;
    task ring(input integer x, input [`PW-1:0] p);
        integer i;
        begin rang = 1'b0;
            for (i = 0; i < 250; i = i + 1) begin
                @(posedge t1k_a);
                if ((x == 0 && e_a[p]) || (x == 1 && e_b[p]) || (x == 2 && e_c[p])) rang = 1'b1;
            end
        end
    endtask

    task idle_all(input [8*72-1:0] what);
        begin
            ms(400);
            ck(busy_a == 0 && busy_b == 0 && busy_c == 0 && !reg_a && !reg_b && !reg_c && !creg_a && !creg_b && !creg_c &&
               dirs_a == 0 && dirs_b == 0 && dirs_c == 0 &&
               res_a == 0 && res_b == 0 && res_c == 0 &&
               mon_a == 0 && mon_b == 0 && mon_c == 0, what);
        end
    endtask

    integer n_ok;
    reg [63:0] bset;

    initial begin
        $display("\n  tb_lchain -- three exchanges, two local trunks, transits across both units");
        repeat (20) @(posedge clk_a);
        rst_n = 1'b1;
        ms(20);
        ck(up_a[1] && up_b[1] && up_b[3] && up_c[1], "both links are up, at both ends");
        ck(busy_a[15:8] == 0 && busy_b[15:8] == 0 && busy_b[31:24] == 0 && busy_c[15:8] == 0,
           "and all thirty-two channels are free");

        // ================= 1.  A to C, through B's two units ======================
        $display("  1. A20 dials 1 2 4 2 1");
        watch_b = 1'b1;
        hook_a[P20] = 1'b1; ms(10);
        dial(0, P20, 1);
        ck(busy_a[15:8] === 8'h01 && dirs_a == 4'b0100, "A's key took A10, the lowest channel facing E");
        ck(busy_b[6'o10] === 1'b1 && res_b != 2'd0, "B holds B10 and a resolver carries the forward");
        ck(busy_b[31:24] === 8'h01 && busy_c[15:8] === 8'h01,
           "B passed it on through its other unit: B30, the lowest facing E, to C10");
        ck(mon_b != 2'd0 && mon_c != 2'd0, "a monitor listens at B and at C");
        dial(0, P20, 2);
        ck(mon_b != 2'd0 && mon_c != 2'd0, "e is 2, everyone's: both read on");
        dial(0, P20, 4);
        ck(mon_b == 2'd0, "b is 4: B's monitor lets go");
        ck(creg_c === 1'b1, "C claimed and gave the channel its claim register");
        ck(res_b == 2'd0, "B's resolver saw the claim come back and freed itself");
        ck(cla_a === 1'b1, "and backward A reached A across both units");
        dial(0, P20, 2); dial(0, P20, 1); ms(20);
        ring(2, P21); ck(rang, "C21 rings, from a caller on A, two local trunks away");
        hook_c[P21] = 1'b1; ms(20);
        tx_a[P20] = 1'b1; ms(4); ck(rx_c[P21] === 1'b1, "C21 hears A20");
        tx_a[P20] = 1'b0; ms(4); ck(rx_c[P21] === 1'b0, "and follows it");
        tx_c[P21] = 1'b1; ms(4); ck(rx_a[P20] === 1'b1, "A20 hears C21");
        tx_c[P21] = 1'b0; ms(4); ck(rx_a[P20] === 1'b0, "and follows it");

        // ================= 2.  a second transit, with the first up =================
        $display("  2. A21 dials 1 2 4 2 0, the first call standing");
        hook_a[P21] = 1'b1; ms(10);
        dial(0, P21, 1);
        ck(busy_a[15:8] === 8'h03 && busy_b[15:8] === 8'h03, "the second key took A11: A10 passed by");
        ck(busy_b[31:24] === 8'h03 && busy_c[15:8] === 8'h03, "and B forwarded it on B31 to C11");
        dial(0, P21, 2); dial(0, P21, 4);
        ck(creg_c === 1'b1 && res_b == 2'd0, "C claimed the second; B's resolver freed itself again");
        dial(0, P21, 2); dial(0, P21, 0); ms(20);
        ring(2, P20); ck(rang, "C20 rings: two transits through B at once");
        hook_c[P20] = 1'b1; ms(20);
        n_ok = 0;
        tx_a[P20] = 1'b1; ms(4); if (rx_c[P21] === 1'b1 && rx_c[P20] === 1'b0) n_ok = n_ok + 1; tx_a[P20] = 1'b0;
        tx_a[P21] = 1'b1; ms(4); if (rx_c[P20] === 1'b1 && rx_c[P21] === 1'b0) n_ok = n_ok + 1; tx_a[P21] = 1'b0;
        tx_c[P21] = 1'b1; ms(4); if (rx_a[P20] === 1'b1 && rx_a[P21] === 1'b0) n_ok = n_ok + 1; tx_c[P21] = 1'b0;
        tx_c[P20] = 1'b1; ms(4); if (rx_a[P21] === 1'b1 && rx_a[P20] === 1'b0) n_ok = n_ok + 1; tx_c[P20] = 1'b0;
        ms(4);
        ck(n_ok == 4, "each transit carries its own pair both ways, and not the other's");
        ck(b_reg_seen == 0, "B never held a register for the calls it passed");
        watch_b = 1'b0;

        // ================= 3.  local calls at B beside them ========================
        $display("  3. B20 dials 2 2, B21 2 3, B24 2 6, with both transits up");
        hook_b[P20] = 1'b1; ms(10); dial(1, P20, 2); dial(1, P20, 2); ms(20);
        ring(1, P22); ck(rang, "B22 rings");
        hook_b[P22] = 1'b1; ms(20);
        hook_b[P21] = 1'b1; ms(10); dial(1, P21, 2); dial(1, P21, 3); ms(20);
        ring(1, P23); ck(rang, "B23 rings");
        hook_b[P23] = 1'b1; ms(20);
        hook_b[P24] = 1'b1; ms(10); dial(1, P24, 2); dial(1, P24, 6); ms(20);
        ring(1, P26); ck(rang, "B26 rings");
        hook_b[P26] = 1'b1; ms(20);
        ck(busy_b[15:8] === 8'h03 && busy_b[31:24] === 8'h03, "no channel was touched by the local calls");
        bset = (64'd1 << P20) | (64'd1 << P21) | (64'd1 << P22) | (64'd1 << P23) |
               (64'd1 << P24) | (64'd1 << P26);
        n_ok = 0;
        tx_b[P20] = 1'b1; ms(4); if ((rx_b & bset) === (64'd1 << P22)) n_ok = n_ok + 1; tx_b[P20] = 1'b0;
        tx_b[P22] = 1'b1; ms(4); if ((rx_b & bset) === (64'd1 << P20)) n_ok = n_ok + 1; tx_b[P22] = 1'b0;
        tx_b[P21] = 1'b1; ms(4); if ((rx_b & bset) === (64'd1 << P23)) n_ok = n_ok + 1; tx_b[P21] = 1'b0;
        tx_b[P23] = 1'b1; ms(4); if ((rx_b & bset) === (64'd1 << P21)) n_ok = n_ok + 1; tx_b[P23] = 1'b0;
        tx_b[P24] = 1'b1; ms(4); if ((rx_b & bset) === (64'd1 << P26)) n_ok = n_ok + 1; tx_b[P24] = 1'b0;
        tx_b[P26] = 1'b1; ms(4); if ((rx_b & bset) === (64'd1 << P24)) n_ok = n_ok + 1; tx_b[P26] = 1'b0;
        ms(4);
        ck(n_ok == 6, "each of B's six lines is heard by its partner and no one else");
        tx_a[P20] = 1'b1; ms(4); ck(rx_c[P21] === 1'b1 && (rx_b & bset) === 64'd0,
                                    "and the first transit still carries A20 to C21, past them");
        tx_a[P20] = 1'b0; ms(4);
        hook_a = 0; hook_b = 0; hook_c = 0;
        idle_all("1-3: every call released, all three idle");

        // ================= 4.  C to A, from the glare end ========================
        $display("  4. C21 dials 1 2 2 2 1");
        watch_b = 1'b1;
        hook_c[P21] = 1'b1; ms(10);
        dial(2, P21, 1);
        ck(busy_c[15:8] === 8'h80 && dirs_c == 4'b1000, "C's word has glare: its key took C17, facing W");
        ck(busy_b[31:24] === 8'h80, "the seizure arrived on B37");
        ck(busy_b[15:8] === 8'h80 && busy_a[15:8] === 8'h80,
           "B forwarded from the top of its own glare group, B17, and A17 holds it");
        dial(2, P21, 2); dial(2, P21, 2);
        ck(creg_a === 1'b1 && cla_c === 1'b1, "A claimed, and backward A reached C");
        dial(2, P21, 2); dial(2, P21, 1); ms(20);
        ring(0, P21); ck(rang, "A21 rings, from a caller on C");
        hook_a[P21] = 1'b1; ms(20);
        tx_c[P21] = 1'b1; ms(4); ck(rx_a[P21] === 1'b1, "A21 hears C21");
        tx_a[P21] = 1'b1; ms(4); ck(rx_c[P21] === 1'b1, "and C21 hears A21");
        tx_a[P21] = 1'b0; tx_c[P21] = 1'b0;
        ck(b_reg_seen == 0, "B held no register for it");
        watch_b = 1'b0;
        hook_a = 0; hook_c = 0;
        idle_all("4: all three idle");

        // ================= 5.  from the middle ====================================
        $display("  5. B20 dials 1 2 4 2 0");
        hook_b[P20] = 1'b1; ms(10);
        dial(1, P20, 1);
        ck(dirs_b == 4'b1100, "B's key seized a channel both ways, W and E");
        ck(busy_b[15:8] === 8'h80 && busy_a[15:8] === 8'h80, "toward A the highest, B17: B's west end has glare");
        ck(busy_b[31:24] === 8'h01 && busy_c[15:8] === 8'h01, "toward C the lowest, B30");
        dial(1, P20, 2); dial(1, P20, 4);
        ck(cla_b === 1'b1 && creg_c === 1'b1, "C claimed, and C's claim register has the channel");
        ms(5);
        ck(dirs_b == 4'b0000 && reg_b === 1'b0,
           "B let the west channel go AT THE CLAIM, and connected: its register is free");
        ms(60);
        ck(busy_a[15:8] === 8'h00, "and A released A17");
        dial(1, P20, 2); dial(1, P20, 0); ms(20);
        ring(2, P20); ck(rang, "C20 rings, from a caller in the middle");
        hook_b = 0;
        idle_all("5: all three idle");

        // a leaf strapped on its absent directions forwards nothing, so it
        // never sweeps for nothing either, and n_nofwd means a lost flood
        // (network.md §10)
        ck(nf_a == 8'd0 && nf_c == 8'd0, "the strapped leaves A and C never swept for nothing");
        ck(clash == 0, "no cable B had two masters driving at once");
        ck(!mo_a && !mo_b && !mo_c && !uo_a && !uo_b && !uo_c,
           "no queue on any exchange refused a write");

        $display("\n  %0d checks, %0d errors.  %s\n", chk, errs,
                 (errs == 0) ? "PASS" : "FAIL");
        if (errs) $fatal(1);
        $finish;
    end

    initial begin #60_000_000_000; $display("  TIMEOUT"); $fatal(1); end

    wire _unused = &{1'b0, rc_a, rc_b, rc_c, t1k_b, t1k_c, fs_a, fs_b, fs_c,
                     sd_a, sc_a, wr_a, sd_b, sc_b, wr_b, sd_c, sc_c, wr_c,
                     ms_a, ms_b, ms_c, hu_a, hu_b, hu_c, gl_a, gl_b, gl_c,
                     nf_b, e_b, up_a, up_b, up_c, 1'b0};
endmodule
