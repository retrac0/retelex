// tb_tr3 -- COPY of work/load/tb_load3.sv for the transit study: tr_harness.svh
// (dest_mode 5, pair period/jitter) and the transit probe (TP lines, TPSUM).
// tb_load3 -- TRAFFIC LOAD on the chain of three exchanges, two local trunks.
// The harness is load_harness.svh; this file is only the wiring.
//
//     A 2 2  blk 1 ======== blk 1  B 2 3  blk 3 ======== blk 1  C 2 4
//            faces E        faces W, g    faces E        faces W, g
//                                  B +100 ppm                   C -100 ppm
//
// tb_lchain's wiring.  Phones: A and C on blocks 2-7 (48 lines, 20-77); B on
// blocks 2, 4-7 (40 lines: 20-27, 40-77), block 3 being its east trunk.
// +define+LD_SMALL: A and C on 20-37, B on 20-27 and 40-47 (16 each).
//
// Build: as tb_load2, with --top-module tb_load3 and work/load/tb_load3.sv.
`timescale 1ns/1ps
`include "exch.vh"

module tb_tr3;
    localparam int NX = 3;
`ifdef LD_SMALL
    localparam [63:0] PH_AC = 64'h0000_0000_FFFF_0000;
    localparam [63:0] PH_B  = 64'h0000_00FF_00FF_0000;
`else
    localparam [63:0] PH_AC = 64'hFFFF_FFFF_FFFF_0000;
    localparam [63:0] PH_B  = 64'hFFFF_FFFF_00FF_0000;
`endif
    localparam [63:0] LT1  = 64'h0000_0000_0000_FF00;        // block 1
    localparam [63:0] LT13 = 64'h0000_0000_FF00_FF00;        // blocks 1 and 3
    localparam [64*NX-1:0] LD_PHONES = {PH_AC, PH_B, PH_AC};
    localparam [64*NX-1:0] LD_TRUNKS = {LT1, LT13, LT1};
    localparam [3*NX-1:0]  LD_CODE_E = {3'd2, 3'd2, 3'd2};
    localparam [3*NX-1:0]  LD_CODE_B = {3'd4, 3'd3, 3'd2};

`include "tr_harness.svh"
`include "tr_probe_common.svh"

    reg clk_a = 1'b0, clk_b = 1'b0, clk_c = 1'b0;
    always #122.070 clk_a = ~clk_a;
    initial begin #40; forever #(122.070 / 1.0001) clk_b = ~clk_b; end
    initial begin #90; forever #(122.070 / 0.9999) clk_c = ~clk_c; end
    assign ld_clk = {clk_c, clk_b, clk_a};

    localparam [7:0] WE = {2'd2, 1'b0, 3'b010, 2'b11};
    localparam [7:0] WW = {2'd3, 1'b1, 3'b010, 2'b11};

    wire [7:0] lc_a, la_a, lh_a, lk_a, lc_b, la_b, lh_b, lk_b, lc_c, la_c, lh_c, lk_c;
    wire [7:0] up_a, up_b, up_c;
    // A blk 1 <-> B blk 1, B blk 3 <-> C blk 1
    wire [7:0] lc_ai = {6'd0, lc_b[1], 1'b0}, la_ai = {6'd0, la_b[1], 1'b0};
    wire [7:0] lh_ai = {6'd0, lh_b[1], 1'b0}, lk_ai = {6'd0, lk_b[1], 1'b0};
    wire [7:0] lc_bi = {4'd0, lc_c[1], 1'b0, lc_a[1], 1'b0}, la_bi = {4'd0, la_c[1], 1'b0, la_a[1], 1'b0};
    wire [7:0] lh_bi = {4'd0, lh_c[1], 1'b0, lh_a[1], 1'b0}, lk_bi = {4'd0, lk_c[1], 1'b0, lk_a[1], 1'b0};
    wire [7:0] lc_ci = {6'd0, lc_b[3], 1'b0}, la_ci = {6'd0, la_b[3], 1'b0};
    wire [7:0] lh_ci = {6'd0, lh_b[3], 1'b0}, lk_ci = {6'd0, lk_b[3], 1'b0};

    site_net #(`LD_SITE_TIMERS, .PHONES(PH_AC), .TRUNKS(64'd0), .OWN_E(3'd2), .OWN_B(3'd2),
               .LTU(8'b0000_0010), .LTWORD({56'd0, WE, 8'd0})) A (
        `LD_SITE_COMMON(0),
        .c_out(), .a_out(), .clk_out(), .c_in(64'd0), .a_in(64'd0), .clk_in(64'd0), .link_up(),
        .lt_c_out(lc_a), .lt_a_out(la_a), .lt_h_out(lh_a), .lt_k_out(lk_a),
        .lt_c_in(lc_ai), .lt_a_in(la_ai), .lt_h_in(lh_ai), .lt_k_in(lk_ai), .lt_up(up_a));

    site_net #(`LD_SITE_TIMERS, .PHONES(PH_B), .TRUNKS(64'd0), .OWN_E(3'd2), .OWN_B(3'd3),
               .LTU(8'b0000_1010), .LTWORD({32'd0, WE, 8'd0, WW, 8'd0})) B (
        `LD_SITE_COMMON(1),
        .c_out(), .a_out(), .clk_out(), .c_in(64'd0), .a_in(64'd0), .clk_in(64'd0), .link_up(),
        .lt_c_out(lc_b), .lt_a_out(la_b), .lt_h_out(lh_b), .lt_k_out(lk_b),
        .lt_c_in(lc_bi), .lt_a_in(la_bi), .lt_h_in(lh_bi), .lt_k_in(lk_bi), .lt_up(up_b));

    site_net #(`LD_SITE_TIMERS, .PHONES(PH_AC), .TRUNKS(64'd0), .OWN_E(3'd2), .OWN_B(3'd4),
               .LTU(8'b0000_0010), .LTWORD({56'd0, WW, 8'd0})) C (
        `LD_SITE_COMMON(2),
        .c_out(), .a_out(), .clk_out(), .c_in(64'd0), .a_in(64'd0), .clk_in(64'd0), .link_up(),
        .lt_c_out(lc_c), .lt_a_out(la_c), .lt_h_out(lh_c), .lt_k_out(lk_c),
        .lt_c_in(lc_ci), .lt_a_in(la_ci), .lt_h_in(lh_ci), .lt_k_in(lk_ci), .lt_up(up_c));

    assign ld_tup = {48'd0, {8{up_c[1]}}, 8'd0,
                     32'd0, {8{up_b[3]}}, 8'd0, {8{up_b[1]}}, 8'd0,
                     48'd0, {8{up_a[1]}}, 8'd0};

    `LD_PROBE(0, A);
    `LD_PROBE(1, B);
    `LD_PROBE(2, C);

`define TPX 0
`define TPS A
`include "tr_probe_unit.svh"
`undef TPX
`undef TPS
`define TPX 1
`define TPS B
`include "tr_probe_unit.svh"
`undef TPX
`undef TPS
`define TPX 2
`define TPS C
`include "tr_probe_unit.svh"
`undef TPX
`undef TPS
endmodule
