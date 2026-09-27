// tb_tim5 -- TIMING STUDY: a chain of FIVE exchanges on local eight-channel
// trunks, with the timing probes (tim_probe.svh).
//
//   A 2 2 blk1 == blk1 B 2 3 blk3 == blk1 C 2 4 blk3 == blk1 D 2 5 blk3 == blk1 E 2 6
//         faces E      faces W, g  E     W, g      E     W, g      E     W, g
//
// Phones: 16 an exchange, blocks 2 and 4 (20-27, 40-47).  Clock offsets are
// knobs: +ppm_a .. +ppm_e (defaults 0, +100, -100, +50, -50).
`timescale 1ns/1ps
`include "exch.vh"

module tb_tim5;
    localparam int NX = 5;
    localparam [63:0] PH   = 64'h0000_00FF_00FF_0000;
    localparam [63:0] LT1  = 64'h0000_0000_0000_FF00;        // block 1
    localparam [63:0] LT13 = 64'h0000_0000_FF00_FF00;        // blocks 1 and 3
    localparam [64*NX-1:0] LD_PHONES = {PH, PH, PH, PH, PH};
    localparam [64*NX-1:0] LD_TRUNKS = {LT1, LT13, LT13, LT13, LT1};
    localparam [3*NX-1:0]  LD_CODE_E = {3'd2, 3'd2, 3'd2, 3'd2, 3'd2};
    localparam [3*NX-1:0]  LD_CODE_B = {3'd6, 3'd5, 3'd4, 3'd3, 3'd2};

`include "tim_harness.svh"

    // the far end of trunk channel g: A blk1 = B blk1; x blk3 = x+1 blk1
    function automatic int tim_far(int g);
        int x, p, b, k;
        x = g / 64; p = g % 64; b = p / 8; k = p % 8;
        if (x == 0 && b == 1) return 1*64 + 8 + k;
        if (x == 1 && b == 1) return 0*64 + 8 + k;
        if (x >= 2 && b == 1) return (x-1)*64 + 24 + k;
        if (x >= 1 && x < NX-1 && b == 3) return (x+1)*64 + 8 + k;
        return -1;
    endfunction
`include "tim_probe.svh"

    reg clk_a = 1'b0, clk_b = 1'b0, clk_c = 1'b0, clk_d = 1'b0, clk_e = 1'b0;
    real hp_a = 122.070, hp_b = 122.070, hp_c = 122.070, hp_d = 122.070, hp_e = 122.070;
    initial begin
        int pa, pb, pc, pd, pe;
        if (!$value$plusargs("ppm_a=%d", pa)) pa = 0;
        if (!$value$plusargs("ppm_b=%d", pb)) pb = 100;
        if (!$value$plusargs("ppm_c=%d", pc)) pc = -100;
        if (!$value$plusargs("ppm_d=%d", pd)) pd = 50;
        if (!$value$plusargs("ppm_e=%d", pe)) pe = -50;
        hp_a = 122.070 / (1.0 + real'(pa) * 1.0e-6);
        hp_b = 122.070 / (1.0 + real'(pb) * 1.0e-6);
        hp_c = 122.070 / (1.0 + real'(pc) * 1.0e-6);
        hp_d = 122.070 / (1.0 + real'(pd) * 1.0e-6);
        hp_e = 122.070 / (1.0 + real'(pe) * 1.0e-6);
        $display("KNOB ppm_a=%0d ppm_b=%0d ppm_c=%0d ppm_d=%0d ppm_e=%0d", pa, pb, pc, pd, pe);
    end
    initial begin #1;  forever #(hp_a) clk_a = ~clk_a; end
    initial begin #40; forever #(hp_b) clk_b = ~clk_b; end
    initial begin #90; forever #(hp_c) clk_c = ~clk_c; end
    initial begin #20; forever #(hp_d) clk_d = ~clk_d; end
    initial begin #70; forever #(hp_e) clk_e = ~clk_e; end
    assign ld_clk = {clk_e, clk_d, clk_c, clk_b, clk_a};

    localparam [7:0] WE = {2'd2, 1'b0, 3'b010, 2'b11};
    localparam [7:0] WW = {2'd3, 1'b1, 3'b010, 2'b11};

    wire [7:0] lc_a, la_a, lh_a, lk_a, lc_b, la_b, lh_b, lk_b, lc_c, la_c, lh_c, lk_c;
    wire [7:0] lc_d, la_d, lh_d, lk_d, lc_e, la_e, lh_e, lk_e;
    wire [7:0] up_a, up_b, up_c, up_d, up_e;
    // A blk1 <- B blk1
    wire [7:0] lc_ai = {6'd0, lc_b[1], 1'b0}, la_ai = {6'd0, la_b[1], 1'b0};
    wire [7:0] lh_ai = {6'd0, lh_b[1], 1'b0}, lk_ai = {6'd0, lk_b[1], 1'b0};
    // B blk1 <- A blk1, B blk3 <- C blk1
    wire [7:0] lc_bi = {4'd0, lc_c[1], 1'b0, lc_a[1], 1'b0}, la_bi = {4'd0, la_c[1], 1'b0, la_a[1], 1'b0};
    wire [7:0] lh_bi = {4'd0, lh_c[1], 1'b0, lh_a[1], 1'b0}, lk_bi = {4'd0, lk_c[1], 1'b0, lk_a[1], 1'b0};
    // C blk1 <- B blk3, C blk3 <- D blk1
    wire [7:0] lc_ci = {4'd0, lc_d[1], 1'b0, lc_b[3], 1'b0}, la_ci = {4'd0, la_d[1], 1'b0, la_b[3], 1'b0};
    wire [7:0] lh_ci = {4'd0, lh_d[1], 1'b0, lh_b[3], 1'b0}, lk_ci = {4'd0, lk_d[1], 1'b0, lk_b[3], 1'b0};
    // D blk1 <- C blk3, D blk3 <- E blk1
    wire [7:0] lc_di = {4'd0, lc_e[1], 1'b0, lc_c[3], 1'b0}, la_di = {4'd0, la_e[1], 1'b0, la_c[3], 1'b0};
    wire [7:0] lh_di = {4'd0, lh_e[1], 1'b0, lh_c[3], 1'b0}, lk_di = {4'd0, lk_e[1], 1'b0, lk_c[3], 1'b0};
    // E blk1 <- D blk3
    wire [7:0] lc_ei = {6'd0, lc_d[3], 1'b0}, la_ei = {6'd0, la_d[3], 1'b0};
    wire [7:0] lh_ei = {6'd0, lh_d[3], 1'b0}, lk_ei = {6'd0, lk_d[3], 1'b0};

    site_net #(`LD_SITE_TIMERS, .PHONES(PH), .TRUNKS(64'd0), .OWN_E(3'd2), .OWN_B(3'd2),
               .LTU(8'b0000_0010), .LTWORD({56'd0, WE, 8'd0})) A (
        `LD_SITE_COMMON(0),
        .c_out(), .a_out(), .clk_out(), .c_in(64'd0), .a_in(64'd0), .clk_in(64'd0), .link_up(),
        .lt_c_out(lc_a), .lt_a_out(la_a), .lt_h_out(lh_a), .lt_k_out(lk_a),
        .lt_c_in(lc_ai), .lt_a_in(la_ai), .lt_h_in(lh_ai), .lt_k_in(lk_ai), .lt_up(up_a));

    site_net #(`LD_SITE_TIMERS, .PHONES(PH), .TRUNKS(64'd0), .OWN_E(3'd2), .OWN_B(3'd3),
               .LTU(8'b0000_1010), .LTWORD({32'd0, WE, 8'd0, WW, 8'd0})) B (
        `LD_SITE_COMMON(1),
        .c_out(), .a_out(), .clk_out(), .c_in(64'd0), .a_in(64'd0), .clk_in(64'd0), .link_up(),
        .lt_c_out(lc_b), .lt_a_out(la_b), .lt_h_out(lh_b), .lt_k_out(lk_b),
        .lt_c_in(lc_bi), .lt_a_in(la_bi), .lt_h_in(lh_bi), .lt_k_in(lk_bi), .lt_up(up_b));

    site_net #(`LD_SITE_TIMERS, .PHONES(PH), .TRUNKS(64'd0), .OWN_E(3'd2), .OWN_B(3'd4),
               .LTU(8'b0000_1010), .LTWORD({32'd0, WE, 8'd0, WW, 8'd0})) C (
        `LD_SITE_COMMON(2),
        .c_out(), .a_out(), .clk_out(), .c_in(64'd0), .a_in(64'd0), .clk_in(64'd0), .link_up(),
        .lt_c_out(lc_c), .lt_a_out(la_c), .lt_h_out(lh_c), .lt_k_out(lk_c),
        .lt_c_in(lc_ci), .lt_a_in(la_ci), .lt_h_in(lh_ci), .lt_k_in(lk_ci), .lt_up(up_c));

    site_net #(`LD_SITE_TIMERS, .PHONES(PH), .TRUNKS(64'd0), .OWN_E(3'd2), .OWN_B(3'd5),
               .LTU(8'b0000_1010), .LTWORD({32'd0, WE, 8'd0, WW, 8'd0})) D (
        `LD_SITE_COMMON(3),
        .c_out(), .a_out(), .clk_out(), .c_in(64'd0), .a_in(64'd0), .clk_in(64'd0), .link_up(),
        .lt_c_out(lc_d), .lt_a_out(la_d), .lt_h_out(lh_d), .lt_k_out(lk_d),
        .lt_c_in(lc_di), .lt_a_in(la_di), .lt_h_in(lh_di), .lt_k_in(lk_di), .lt_up(up_d));

    site_net #(`LD_SITE_TIMERS, .PHONES(PH), .TRUNKS(64'd0), .OWN_E(3'd2), .OWN_B(3'd6),
               .LTU(8'b0000_0010), .LTWORD({56'd0, WW, 8'd0})) E (
        `LD_SITE_COMMON(4),
        .c_out(), .a_out(), .clk_out(), .c_in(64'd0), .a_in(64'd0), .clk_in(64'd0), .link_up(),
        .lt_c_out(lc_e), .lt_a_out(la_e), .lt_h_out(lh_e), .lt_k_out(lk_e),
        .lt_c_in(lc_ei), .lt_a_in(la_ei), .lt_h_in(lh_ei), .lt_k_in(lk_ei), .lt_up(up_e));

    assign ld_tup = {48'd0, {8{up_e[1]}}, 8'd0,
                     32'd0, {8{up_d[3]}}, 8'd0, {8{up_d[1]}}, 8'd0,
                     32'd0, {8{up_c[3]}}, 8'd0, {8{up_c[1]}}, 8'd0,
                     32'd0, {8{up_b[3]}}, 8'd0, {8{up_b[1]}}, 8'd0,
                     48'd0, {8{up_a[1]}}, 8'd0};

    `LD_PROBE(0, A);
    `LD_PROBE(1, B);
    `LD_PROBE(2, C);
    `LD_PROBE(3, D);
    `LD_PROBE(4, E);
    `TIM_TAP(0, A);
    `TIM_TAP(1, B);
    `TIM_TAP(2, C);
    `TIM_TAP(3, D);
    `TIM_TAP(4, E);
endmodule
