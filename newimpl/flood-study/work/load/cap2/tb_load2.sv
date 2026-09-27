// tb_load2 -- TRAFFIC LOAD on two exchanges joined by a LOCAL EIGHT-CHANNEL
// TRUNK.  The harness is load_harness.svh; this file is only the wiring.
//
//     A 2 2  blk 1 ========== blk 1  B 2 3
//            faces E                 faces W, glare          B's crystal +100 ppm
//
// tb_lfull's wiring: each exchange is site_net (top_net: the mini marker with
// its one register, a network unit), tone sources at 01 and 03, a local trunk
// unit on block 1 of each.  Phones on blocks 2-7 of both: 48 lines each,
// 20-77 (+define+LD_SMALL: blocks 2-3 only, 16 lines, 20-37).
//
// Build (from newimpl/build/flood):
//   ./sim.sh bash -c 'verilator --binary --timing -j 2 -Irtl -Iwork/load -Wno-fatal \
//        --top-module tb_load2 --Mdir work/load/obj_load2 -o tb_load2 \
//        $(cat work/RTL.list) tb/site_net.v work/load/tb_load2.sv > work/load/vl_load2.log 2>&1'
// add +define+SCALE1 for the real timers (and a separate --Mdir).
`timescale 1ns/1ps
`include "exch.vh"

module tb_load2;
    localparam int NX = 2;
`ifdef LD_SMALL
    localparam [63:0] PH = 64'h0000_0000_FFFF_0000;          // 20-37
`else
    localparam [63:0] PH = 64'hFFFF_FFFF_FFFF_0000;          // 20-77
`endif
    localparam [63:0] LT = 64'h0000_0000_0000_FF00;          // block 1: the trunk
    localparam [64*NX-1:0] LD_PHONES = {PH, PH};
    localparam [64*NX-1:0] LD_TRUNKS = {LT, LT};
    localparam [3*NX-1:0]  LD_CODE_E = {3'd2, 3'd2};
    localparam [3*NX-1:0]  LD_CODE_B = {3'd3, 3'd2};

`include "load_harness_c2.svh"

    // ---- the crystals: A nominal, B 100 ppm fast ------------------------------
    reg clk_a = 1'b0, clk_b = 1'b0;
    always #122.070 clk_a = ~clk_a;
    initial begin #40; forever #(122.070 / 1.0001) clk_b = ~clk_b; end
    assign ld_clk = {clk_b, clk_a};

    localparam [7:0] WE = {2'd2, 1'b0, 3'b010, 2'b11};      // facing E, no glare
    localparam [7:0] WW = {2'd3, 1'b1, 3'b010, 2'b11};      // facing W, glare

    wire [7:0] lc_a, la_a, lh_a, lk_a, lc_b, la_b, lh_b, lk_b, lup_a, lup_b;
    wire [7:0] lc_ai = {6'd0, lc_b[1], 1'b0}, la_ai = {6'd0, la_b[1], 1'b0};
    wire [7:0] lh_ai = {6'd0, lh_b[1], 1'b0}, lk_ai = {6'd0, lk_b[1], 1'b0};
    wire [7:0] lc_bi = {6'd0, lc_a[1], 1'b0}, la_bi = {6'd0, la_a[1], 1'b0};
    wire [7:0] lh_bi = {6'd0, lh_a[1], 1'b0}, lk_bi = {6'd0, lk_a[1], 1'b0};

    site_net #(`LD_SITE_TIMERS, .PHONES(PH), .TRUNKS(64'd0), .OWN_E(3'd2), .OWN_B(3'd2),
               .LTU(8'b0000_0010), .LTWORD({56'd0, WE, 8'd0})) A (
        `LD_SITE_COMMON(0),
        .c_out(), .a_out(), .clk_out(), .c_in(64'd0), .a_in(64'd0), .clk_in(64'd0), .link_up(),
        .lt_c_out(lc_a), .lt_a_out(la_a), .lt_h_out(lh_a), .lt_k_out(lk_a),
        .lt_c_in(lc_ai), .lt_a_in(la_ai), .lt_h_in(lh_ai), .lt_k_in(lk_ai), .lt_up(lup_a));

    site_net #(`LD_SITE_TIMERS, .PHONES(PH), .TRUNKS(64'd0), .OWN_E(3'd2), .OWN_B(3'd3),
               .LTU(8'b0000_0010), .LTWORD({56'd0, WW, 8'd0})) B (
        `LD_SITE_COMMON(1),
        .c_out(), .a_out(), .clk_out(), .c_in(64'd0), .a_in(64'd0), .clk_in(64'd0), .link_up(),
        .lt_c_out(lc_b), .lt_a_out(la_b), .lt_h_out(lh_b), .lt_k_out(lk_b),
        .lt_c_in(lc_bi), .lt_a_in(la_bi), .lt_h_in(lh_bi), .lt_k_in(lk_bi), .lt_up(lup_b));

    assign ld_tup = {48'd0, {8{lup_b[1]}}, 8'd0, 48'd0, {8{lup_a[1]}}, 8'd0};

    `LD_PROBE(0, A);
    `LD_PROBE(1, B);
endmodule
