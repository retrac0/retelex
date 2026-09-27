// tb_tim3 -- TIMING STUDY: tb_load3's chain (A 2 2 = B 2 3 = C 2 4, two local
// trunks) with the timing probes (tim_probe.svh) and the clocks' offsets as
// knobs: +ppm_a=N +ppm_b=N +ppm_c=N (defaults 0, +100, -100 as tb_load3).
// Phones as tb_load3 (LD_SMALL: 16 an exchange).
`timescale 1ns/1ps
`include "exch.vh"

module tb_tim3;
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

`include "tim_harness.svh"

    // the far end of trunk channel g: A blk1 = B blk1; B blk3 = C blk1
    function automatic int tim_far(int g);
        int x, p, b, k;
        x = g / 64; p = g % 64; b = p / 8; k = p % 8;
        if (x == 0 && b == 1) return 1*64 + 8 + k;
        if (x == 1 && b == 1) return 0*64 + 8 + k;
        if (x == 1 && b == 3) return 2*64 + 8 + k;
        if (x == 2 && b == 1) return 1*64 + 24 + k;
        return -1;
    endfunction
`include "tim_probe.svh"

    reg clk_a = 1'b0, clk_b = 1'b0, clk_c = 1'b0;
    real hp_a = 122.070, hp_b = 122.070, hp_c = 122.070;
    initial begin
        int pa, pb, pc;
        if (!$value$plusargs("ppm_a=%d", pa)) pa = 0;
        if (!$value$plusargs("ppm_b=%d", pb)) pb = 100;
        if (!$value$plusargs("ppm_c=%d", pc)) pc = -100;
        hp_a = 122.070 / (1.0 + real'(pa) * 1.0e-6);
        hp_b = 122.070 / (1.0 + real'(pb) * 1.0e-6);
        hp_c = 122.070 / (1.0 + real'(pc) * 1.0e-6);
        $display("KNOB ppm_a=%0d ppm_b=%0d ppm_c=%0d", pa, pb, pc);
    end
    initial begin #1;  forever #(hp_a) clk_a = ~clk_a; end
    initial begin #40; forever #(hp_b) clk_b = ~clk_b; end
    initial begin #90; forever #(hp_c) clk_c = ~clk_c; end
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
    `TIM_TAP(0, A);
    `TIM_TAP(1, B);
    `TIM_TAP(2, C);
endmodule
