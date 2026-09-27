// tb_load2b -- TRAFFIC LOAD on two exchanges joined by TWO BASEBAND TIE CARDS:
// a tight trunk bottleneck.  The harness is load_harness.svh; this is wiring.
//
//     A 2 2  11 ------ 11  B 2 3
//            12 ------ 12
//            faces E        faces W, glare             B's crystal +100 ppm
//
// tb_net's wiring (its A25 loop is not fitted): a baseband card in sockets 11
// and 12 of each exchange, each card's word saying trunk, glare, direction.
// Phones on blocks 2-7 of both: 48 lines each, 20-77 (+define+LD_SMALL: 20-37).
// tb_net ran its two crystals at one frequency; here B runs 100 ppm fast, as
// tb_load2's, so the cards' re-timing slips (baseband.md 3.2).
//
// Build: as tb_load2, with --top-module tb_load2b and work/load/tb_load2b.sv.
`timescale 1ns/1ps
`include "exch.vh"

module tb_load2b;
    localparam int NX = 2;
`ifdef LD_SMALL
    localparam [63:0] PH = 64'h0000_0000_FFFF_0000;
`else
    localparam [63:0] PH = 64'hFFFF_FFFF_FFFF_0000;
`endif
    localparam [`PW-1:0] T11 = 6'o11, T12 = 6'o12;
    localparam [63:0] TR = (64'd1 << T11) | (64'd1 << T12);
    localparam [64*NX-1:0] LD_PHONES = {PH, PH};
    localparam [64*NX-1:0] LD_TRUNKS = {TR, TR};
    localparam [3*NX-1:0]  LD_CODE_E = {3'd2, 3'd2};
    localparam [3*NX-1:0]  LD_CODE_B = {3'd3, 3'd2};

`include "load_harness_c2.svh"

    reg clk_a = 1'b0, clk_b = 1'b0;
    always #122.070 clk_a = ~clk_a;
    initial begin #40; forever #(122.070 / 1.0001) clk_b = ~clk_b; end
    assign ld_clk = {clk_b, clk_a};

    localparam [7:0] WE = {2'd2, 1'b0, 3'b010, 2'b11};
    localparam [7:0] WW = {2'd3, 1'b1, 3'b010, 2'b11};
    localparam [511:0] TW_A = ({504'd0, WE} << (8*T11)) | ({504'd0, WE} << (8*T12));
    localparam [511:0] TW_B = ({504'd0, WW} << (8*T11)) | ({504'd0, WW} << (8*T12));

    wire [63:0] ac_out, aa_out, ak_out, bc_out, ba_out, bk_out, up_a, up_b;
    wire [63:0] ac_in = {bc_out[63:0] & TR}, aa_in = {ba_out & TR}, ak_in = {bk_out & TR};
    wire [63:0] bc_in = {ac_out & TR},       ba_in = {aa_out & TR}, bk_in = {ak_out & TR};

    site_net #(`LD_SITE_TIMERS, .PHONES(PH), .TRUNKS(TR), .TWORD(TW_A),
               .OWN_E(3'd2), .OWN_B(3'd2)) A (
        `LD_SITE_COMMON(0),
        .c_out(ac_out), .a_out(aa_out), .clk_out(ak_out),
        .c_in(ac_in), .a_in(aa_in), .clk_in(ak_in), .link_up(up_a),
        .lt_c_out(), .lt_a_out(), .lt_h_out(), .lt_k_out(),
        .lt_c_in(8'd0), .lt_a_in(8'd0), .lt_h_in(8'd0), .lt_k_in(8'd0), .lt_up());

    site_net #(`LD_SITE_TIMERS, .PHONES(PH), .TRUNKS(TR), .TWORD(TW_B),
               .OWN_E(3'd2), .OWN_B(3'd3)) B (
        `LD_SITE_COMMON(1),
        .c_out(bc_out), .a_out(ba_out), .clk_out(bk_out),
        .c_in(bc_in), .a_in(ba_in), .clk_in(bk_in), .link_up(up_b),
        .lt_c_out(), .lt_a_out(), .lt_h_out(), .lt_k_out(),
        .lt_c_in(8'd0), .lt_a_in(8'd0), .lt_h_in(8'd0), .lt_k_in(8'd0), .lt_up());

    assign ld_tup = {up_b, up_a};

    `LD_PROBE(0, A);
    `LD_PROBE(1, B);
endmodule
