// tb_chain -- three exchanges in a chain, and a transit.  network.md 3, 3.1,
// 3.2; common-control.md 4.
//
//     A 2 2  ==11,12==  11,12  B 2 3  13,15  ==11,12==  C 2 4
//            faces E          faces W  faces E           faces W
//
// Each is top_net.  B has trunks both ways, so an incoming seizure from one
// side is passed on into the other: B is a transit, and holds nothing for a
// call it passes but two latches and a resolver until the claim.  The glare
// bit is set at one end of each link, so the two ends hunt it from opposite
// ends of the group.
//
//   1  end to end   A20 dials 1 2 4 2 1: through B to C.  B's monitor lets go
//                   at b, C claims, B's resolver frees itself at the claim,
//                   and B never holds a register
//   2  the far way  C20 dials 1 2 2 2 1: the same, the other way round
//   3  the middle   B20 dials 1 2 2 2 1: B floods BOTH ways; A claims, and B
//                   lets the trunk toward C go AT THE CLAIM, not at the last
//                   digit (network.md 3)
//   4  crossing     A20 and B20 key 1 eight milliseconds apart, so A's seizure
//                   reaches B in the middle of B's own sweep.  B's forward
//                   waits for the sweep; the origin must still seize from it
//
// Timers scaled by 8, as tb_net; the sweeps are not, and two of them lie on
// the flood's way from A to C -- about 40 ms, inside the 100 ms between digits.
//
// Does not cover: a hub (three or four directions and a fan-out of two or
// more legs), a ring and its jumper, glare, or two calls through B at once.
`timescale 1ns/1ps
`include "exch.vh"

module tb_chain;
    integer chk = 0, errs = 0;
    task ck(input cond, input [8*72-1:0] what);
        begin chk = chk + 1;
             if (!cond) begin errs = errs + 1; $display("    FAIL  %0s", what); end
        end
    endtask

    reg clk_a = 1'b0, clk_b = 1'b0, clk_c = 1'b0, rst_n = 1'b0;
    always #122.070 clk_a = ~clk_a;
    initial begin #40; forever #122.070 clk_b = ~clk_b; end
    initial begin #90; forever #122.070 clk_c = ~clk_c; end

    localparam [`PW-1:0] P20 = 6'o20, P21 = 6'o21;
    localparam [`PW-1:0] T11 = 6'o11, T12 = 6'o12, T13 = 6'o13, T15 = 6'o15;
    localparam [7:0] WE0 = {2'd2, 1'b0, 3'b010, 2'b11};     // facing E
    localparam [7:0] WW1 = {2'd3, 1'b1, 3'b010, 2'b11};     // facing W, glare
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
        .T_ARM(9'd2), .T_REL(9'd32), .RING_ON(13'd64), .RING_OFF(13'd128), \
        .HIT(9'd1), .ID(9'd16), .CLR(9'd32), .NODIG(16'd1250), \
        .T_GUARD0(16'd16), .T_KEY(16'd625), .T_CLAIM(16'd250)

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

    // ---- the cables: A11-B11, A12-B12, B13-C11, B15-C12 -----------------------
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

    integer clash = 0;
    always @(posedge clk_a) if (cl_a) clash = clash + 1;
    always @(posedge clk_b) if (cl_b) clash = clash + 1;
    always @(posedge clk_c) if (cl_c) clash = clash + 1;

    // ---- a register at B, ever -----------------------------------------------
    // A transit holds nothing but latches and a resolver; if B's register is
    // ever busy during scenarios 1 and 2, B took a trunk's M as a call.
    reg watch_b = 1'b0; integer b_reg_seen = 0;
    always @(posedge clk_b) if (watch_b && reg_b) b_reg_seen = b_reg_seen + 1;

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

    integer hi, lo, i;
    task rings(input integer x, input [`PW-1:0] p);
        begin hi = 0; lo = 0;
            for (i = 0; i < 400; i = i + 1) begin
                @(posedge t1k_a);
                if ((x == 0 && e_a[p]) || (x == 1 && e_b[p]) || (x == 2 && e_c[p]))
                     hi = hi + 1;
                else lo = lo + 1;
            end
        end
    endtask

    task idle_all(input [8*72-1:0] what);
        begin
            ms(400);
            ck(busy_a == 0 && busy_b == 0 && busy_c == 0 && !reg_a && !reg_b && !reg_c &&
               dirs_a == 0 && dirs_b == 0 && dirs_c == 0 && res_b == 0, what);
        end
    endtask

    initial begin
        $display("\n  tb_chain -- three exchanges, a transit, and a call from the middle");
        repeat (20) @(posedge clk_a);
        rst_n = 1'b1;
        ms(20);
        ck(up_a[T11] && up_b[T13] && up_c[T12], "all four links are up");

        // ================= 1.  A to C, through B ================================
        $display("  1. A20 dials 1 2 4 2 1");
        watch_b = 1'b1;
        hook_a[P20] = 1'b1; ms(10);
        dial(0, P20, 1);
        ck(dirs_a == 4'b0100, "A seized one trunk, toward E");
        ck(busy_b[T11] === 1'b1 && res_b != 2'd0, "B holds it and a resolver carries the forward");
        ck(busy_b[T13] === 1'b1 && busy_c[T11] === 1'b1, "B passed it on: its 13, C's 11, the lowest E");
        ck(mon_b != 2'd0 && mon_c != 2'd0, "a monitor listens at B and at C");
        dial(0, P20, 2);                                     // e: everyone's
        ck(mon_b != 2'd0 && mon_c != 2'd0, "e is 2, everyone's: both read on");
        dial(0, P20, 4);                                     // b: C's
        ck(mon_b == 2'd0, "b is 4: B's monitor lets go");
        ck(reg_c === 1'b1, "C claimed and gave the trunk its register");
        ck(res_b == 2'd0, "B's resolver saw the claim come back and freed itself");
        ck(cla_a === 1'b1, "and backward A reached A through B's two latches");
        dial(0, P20, 2); dial(0, P20, 1); ms(20);
        rings(2, P21); ck(hi > 50 && lo > 50, "C21 rings, from a caller on A");
        hook_c[P21] = 1'b1; ms(20);
        tx_a[P20] = 1'b1; ms(4); ck(rx_c[P21] === 1'b1, "C21 hears A20, two links away");
        tx_a[P20] = 1'b0; ms(4); ck(rx_c[P21] === 1'b0, "and follows it");
        tx_c[P21] = 1'b1; ms(4); ck(rx_a[P20] === 1'b1, "A20 hears C21");
        tx_c[P21] = 1'b0; ms(4); ck(rx_a[P20] === 1'b0, "and follows it");
        hook_a[P20] = 1'b0; hook_c[P21] = 1'b0;
        idle_all("1: release ran back through B; all three idle");

        // ================= 2.  C to A ==========================================
        $display("  2. C20 dials 1 2 2 2 1");
        hook_c[P20] = 1'b1; ms(10);
        dial(2, P20, 1); dial(2, P20, 2); dial(2, P20, 2); dial(2, P20, 2); dial(2, P20, 1);
        ms(20);
        rings(0, P21); ck(hi > 50 && lo > 50, "A21 rings, from a caller on C");
        ck(b_reg_seen == 0, "B never held a register for a call it passed");
        watch_b = 1'b0;
        hook_c[P20] = 1'b0;
        idle_all("2: all three idle");

        // ================= 3.  from the middle =================================
        $display("  3. B20 dials 1 2 2 2 1");
        hook_b[P20] = 1'b1; ms(10);
        dial(1, P20, 1);
        ck(dirs_b == 4'b1100, "the key seized a trunk BOTH ways, W and E");
        ck(busy_a[T12] === 1'b1, "toward A the highest W trunk, 12: B's end has glare");
        ck(busy_c[T11] === 1'b1, "toward C the lowest E trunk");
        dial(1, P20, 2); dial(1, P20, 2);                    // A's code
        ck(cla_b === 1'b1 && reg_a === 1'b1, "A claimed, and A's register has the trunk");
        ck(dirs_b == 4'b1000, "B let the trunk toward C go AT THE CLAIM");
        ms(60);
        ck(busy_c[T11] === 1'b0, "and C released it");
        dial(1, P20, 2); dial(1, P20, 1); ms(20);
        rings(0, P21); ck(hi > 50 && lo > 50, "A21 rings, from a caller in the middle");
        hook_b[P20] = 1'b0;
        idle_all("3: all three idle");

        // ================= 4.  two floods cross at B ===========================
        $display("  4. A20 and B20 key 1, 8 ms apart");
        hook_a[P20] = 1'b1; hook_b[P20] = 1'b1; ms(10);
        fork
            begin hook_a[P20] = 1'b0; repeat (12) @(posedge t1k_a); hook_a[P20] = 1'b1; end
            begin repeat (8) @(posedge t1k_a);
                  hook_b[P20] = 1'b0; repeat (12) @(posedge t1k_a); hook_b[P20] = 1'b1; end
        join
        ms(100);
        ck(dirs_b == 4'b1100, "B's origin seized both ways, though A's seizure came mid-sweep");
        ck(busy_c[T12] === 1'b1, "and B passed A's seizure on toward C on its other trunk");
        hook_a[P20] = 1'b0; hook_b[P20] = 1'b0;
        idle_all("4: all three idle");

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
                     ms_a, ms_b, ms_c, cla_c, hu_a, hu_b, hu_c, res_a, res_c, mon_a,
                     dirs_c, gl_a, gl_b, gl_c, nf_a, nf_b, nf_c, e_b, rx_b, 1'b0};
endmodule
