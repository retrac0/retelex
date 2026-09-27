// tb_c08lt -- VERIFY C08 at REAL timers: one open A conductor on a LOCAL TRUNK.
// Scratch; not part of the tree.
//
//     A 2 2  ==LTU block 1 (10-17)==  B 2 3  22,23 ==baseband==  11,12  C 2 4
//            faces E                   faces W     faces E        faces W, g
//
// The A conductor of the eight-channel highway from A into B reads 1 (a
// failsafe-high receiver on an open line, as tb_lnet/tb_ltu model a cut),
// while HCLK and TX_CLK run, so the link stays up.  Real timers (T_ARM 16,
// T_REL 256, CLR 256, T_KEY 5000, T_CLAIM 2000).  Observe what B and C hold.
`timescale 1ns/1ps
`include "exch.vh"

module tb_c08lt;
    integer chk = 0, errs = 0;
    task ck(input cond, input [8*88-1:0] what);
        begin chk = chk + 1;
             if (!cond) begin errs = errs + 1; $display("    FAIL  %0s", what); end
             else $display("    ok    %0s", what);
        end
    endtask

    reg clk_a = 1'b0, clk_b = 1'b0, clk_c = 1'b0, rst_n = 1'b0;
    always #122.070 clk_a = ~clk_a;
    initial begin #40; forever #122.070 clk_b = ~clk_b; end
    initial begin #90; forever #122.070 clk_c = ~clk_c; end

    localparam [`PW-1:0] P20 = 6'o20, T22 = 6'o22, T23 = 6'o23, T11 = 6'o11, T12 = 6'o12;
    localparam [7:0] WE0 = {2'd2, 1'b0, 3'b010, 2'b11};     // facing E
    localparam [7:0] WW1 = {2'd3, 1'b1, 3'b010, 2'b11};     // facing W, glare
    localparam [511:0] TW_B = ({504'd0, WE0} << (8*T22)) | ({504'd0, WE0} << (8*T23));
    localparam [511:0] TW_C = ({504'd0, WW1} << (8*T11)) | ({504'd0, WW1} << (8*T12));

    reg  [63:0] hook_a = 0, tx_a = 0, hook_b = 0, tx_b = 0, hook_c = 0, tx_c = 0;
    wire [63:0] rx_a, e_a, rx_b, e_b, rx_c, e_c, busy_a, busy_b, busy_c;
    wire [63:0] bc, ba, bk, cc, ca, ck_o, up_b, up_c;
    reg  [63:0] bc_i, ba_i, bk_i, cc_i, ca_i, ck_i;
    wire [7:0]  lc_a, la_a, lh_a, lk_a, lc_b, la_b, lh_b, lk_b, lup_a, lup_b;
    wire        fs_a, fs_b, fs_c, t1k_a, t1k_b, t1k_c, rc_a, rc_b, rc_c;
    wire        sd_a, sc_a, wr_a, cl_a, sd_b, sc_b, wr_b, cl_b, sd_c, sc_c, wr_c, cl_c;
    wire        reg_a, reg_b, reg_c, mo_a, mo_b, mo_c, cla_a, cla_b, cla_c;
    wire        hu_a, hu_b, hu_c, uo_a, uo_b, uo_c;
    wire [2:0]  ms_a, ms_b, ms_c;
    wire [3:0]  dirs_a, dirs_b, dirs_c;
    wire [1:0]  res_a, res_b, res_c, mon_a, mon_b, mon_c;
    wire [7:0]  gl_a, gl_b, gl_c, nf_a, nf_b, nf_c;

    reg stuck = 1'b0;
    wire [7:0] lc_ai = {6'd0, lc_b[1], 1'b0}, la_ai = {6'd0, la_b[1], 1'b0};
    wire [7:0] lh_ai = {6'd0, lh_b[1], 1'b0}, lk_ai = {6'd0, lk_b[1], 1'b0};
    wire [7:0] lc_bi = {6'd0, lc_a[1], 1'b0}, la_bi = {6'd0, stuck | la_a[1], 1'b0};
    wire [7:0] lh_bi = {6'd0, lh_a[1], 1'b0}, lk_bi = {6'd0, lk_a[1], 1'b0};

`define RT .T_ARM(9'd16), .T_REL(9'd256), .RING_ON(13'd2048), .RING_OFF(13'd4096), \
        .HIT(9'd8), .ID(9'd128), .CLR(9'd256), .NODIG(16'd10000), \
        .T_GUARD0(16'd128), .T_KEY(16'd5000), .T_CLAIM(16'd2000)

    site_net #(`RT, .PHONES(64'd1 << P20), .TRUNKS(64'd0), .LTU(8'b0000_0010),
               .LTWORD({56'd0, WE0, 8'd0}), .OWN_E(3'd2), .OWN_B(3'd2)) A (
        .clk(clk_a), .rst_n(rst_n), .hook(hook_a), .tx(tx_a), .rx(rx_a), .e(e_a),
        .c_out(), .a_out(), .clk_out(), .c_in(64'd0), .a_in(64'd0), .clk_in(64'd0),
        .link_up(),
        .lt_c_out(lc_a), .lt_a_out(la_a), .lt_h_out(lh_a), .lt_k_out(lk_a),
        .lt_c_in(lc_ai), .lt_a_in(la_ai), .lt_h_in(lh_ai), .lt_k_in(lk_ai), .lt_up(lup_a),
        .frame_stb(fs_a), .tick_1k(t1k_a), .ring_cad_n(rc_a), .port_busy(busy_a),
        .b_sdata(sd_a), .b_sclk(sc_a), .b_wr(wr_a), .b_clash(cl_a),
        .reg_busy(reg_a), .mk_state(ms_a), .mk_ovf(mo_a), .dirs_held(dirs_a),
        .res_busy(res_a), .mon_held(mon_a), .claimed(cla_a), .hunting(hu_a),
        .un_ovf(uo_a), .n_glare(gl_a), .n_nofwd(nf_a));

    site_net #(`RT, .PHONES(64'd1 << P20), .TRUNKS((64'd1 << T22) | (64'd1 << T23)), .TWORD(TW_B),
               .LTU(8'b0000_0010), .LTWORD({56'd0, WW1, 8'd0}), .OWN_E(3'd2), .OWN_B(3'd3)) B (
        .clk(clk_b), .rst_n(rst_n), .hook(hook_b), .tx(tx_b), .rx(rx_b), .e(e_b),
        .c_out(bc), .a_out(ba), .clk_out(bk), .c_in(bc_i), .a_in(ba_i), .clk_in(bk_i),
        .link_up(up_b),
        .lt_c_out(lc_b), .lt_a_out(la_b), .lt_h_out(lh_b), .lt_k_out(lk_b),
        .lt_c_in(lc_bi), .lt_a_in(la_bi), .lt_h_in(lh_bi), .lt_k_in(lk_bi), .lt_up(lup_b),
        .frame_stb(fs_b), .tick_1k(t1k_b), .ring_cad_n(rc_b), .port_busy(busy_b),
        .b_sdata(sd_b), .b_sclk(sc_b), .b_wr(wr_b), .b_clash(cl_b),
        .reg_busy(reg_b), .mk_state(ms_b), .mk_ovf(mo_b), .dirs_held(dirs_b),
        .res_busy(res_b), .mon_held(mon_b), .claimed(cla_b), .hunting(hu_b),
        .un_ovf(uo_b), .n_glare(gl_b), .n_nofwd(nf_b));

    site_net #(`RT, .PHONES(64'd1 << P20), .TRUNKS((64'd1 << T11) | (64'd1 << T12)), .TWORD(TW_C),
               .OWN_E(3'd2), .OWN_B(3'd4)) C (
        .clk(clk_c), .rst_n(rst_n), .hook(hook_c), .tx(tx_c), .rx(rx_c), .e(e_c),
        .c_out(cc), .a_out(ca), .clk_out(ck_o), .c_in(cc_i), .a_in(ca_i), .clk_in(ck_i),
        .link_up(up_c),
        .lt_c_out(), .lt_a_out(), .lt_h_out(), .lt_k_out(),
        .lt_c_in(8'd0), .lt_a_in(8'd0), .lt_h_in(8'd0), .lt_k_in(8'd0), .lt_up(),
        .frame_stb(fs_c), .tick_1k(t1k_c), .ring_cad_n(rc_c), .port_busy(busy_c),
        .b_sdata(sd_c), .b_sclk(sc_c), .b_wr(wr_c), .b_clash(cl_c),
        .reg_busy(reg_c), .mk_state(ms_c), .mk_ovf(mo_c), .dirs_held(dirs_c),
        .res_busy(res_c), .mon_held(mon_c), .claimed(cla_c), .hunting(hu_c),
        .un_ovf(uo_c), .n_glare(gl_c), .n_nofwd(nf_c));

    // B22-C11, B23-C12
    always @* begin
        bc_i = 0; ba_i = 0; bk_i = 0; cc_i = 0; ca_i = 0; ck_i = 0;
        bc_i[T22] = cc[T11]; ba_i[T22] = ca[T11]; bk_i[T22] = ck_o[T11];
        bc_i[T23] = cc[T12]; ba_i[T23] = ca[T12]; bk_i[T23] = ck_o[T12];
        cc_i[T11] = bc[T22]; ca_i[T11] = ba[T22]; ck_i[T11] = bk[T22];
        cc_i[T12] = bc[T23]; ca_i[T12] = ba[T23]; ck_i[T12] = bk[T23];
    end

    task ms(input integer n); begin repeat (n) @(posedge t1k_b); end endtask

    real t0;
    reg [1:0] mb_d = 0, rb_d = 0, mc_d = 0; reg [7:0] hb_d = 0;
    always @(posedge clk_b) begin
        mb_d <= mon_b; rb_d <= res_b; mc_d <= mon_c; hb_d <= busy_b[15:8];
        if (stuck && mon_b != mb_d)        $display("  T %8.3f ms: B mon %b", ($realtime - t0)/1e6, mon_b);
        if (stuck && res_b != rb_d)        $display("  T %8.3f ms: B res %b", ($realtime - t0)/1e6, res_b);
        if (stuck && mon_c != mc_d)        $display("  T %8.3f ms: C mon %b", ($realtime - t0)/1e6, mon_c);
        if (stuck && busy_b[15:8] != hb_d) $display("  T %8.3f ms: B 10-17 busy %b", ($realtime - t0)/1e6, busy_b[15:8]);
    end

    task show(input [8*24-1:0] tag);
        $display("  OBS %0s: B 10-17 busy %b mon %b res %b nofwd %0d B22/23 busy %b | C mon %b C11/12 busy %b | A mon %b 10-17 busy %b",
                 tag, busy_b[15:8], mon_b, res_b, nf_b, {busy_b[T23], busy_b[T22]}, mon_c,
                 {busy_c[T12], busy_c[T11]}, mon_a, busy_a[15:8]);
    endtask

    initial begin
        $display("\n  tb_c08lt -- one open A conductor on a local trunk, real timers");
        repeat (20) @(posedge clk_a);
        rst_n = 1'b1;
        ms(300);
        ck(lup_b[1] && lup_a[1] && up_b[T22] && up_b[T23] && up_c[T11] && up_c[T12], "all links up");
        show("idle");
        t0 = $realtime; stuck = 1'b1;
        ms(400);
        show("400 ms after");
        ck(lup_b[1], "the local trunk still reads UP (only HCLK is watched)");
        ms(600);
        show("1 s after");
        ck(res_b == 2'b11 && mon_b == 2'b11, "B: both resolvers and both monitors taken by phantoms");
        ck(mon_c == 2'b11 && busy_c[T11] && busy_c[T12], "C: both monitors and both channels held by two phantom floods");
        $display("\n  %0d checks, %0d errors.  (checks state the AUDITOR'S claim; ok = claim reproduced)\n", chk, errs);
        $finish;
    end
    initial begin #20_000_000_000; $display("  TIMEOUT"); $finish; end

    wire _unused = &{1'b0, rc_a, rc_b, rc_c, t1k_a, t1k_c, fs_a, fs_b, fs_c, sd_a, sc_a, wr_a, cl_a,
                     sd_b, sc_b, wr_b, cl_b, sd_c, sc_c, wr_c, cl_c, reg_a, reg_b, reg_c, mo_a, mo_b, mo_c,
                     cla_a, cla_b, cla_c, hu_a, hu_b, hu_c, uo_a, uo_b, uo_c, ms_a, ms_b, ms_c,
                     dirs_a, dirs_b, dirs_c, res_a, res_c, gl_a, gl_b, gl_c, nf_a, nf_c, rx_a, rx_b, rx_c,
                     e_a, e_b, e_c, lc_a, lh_a, lk_a, lup_a, 1'b0};
endmodule
