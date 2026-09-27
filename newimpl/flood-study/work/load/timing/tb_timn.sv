// tb_timn -- TIMING STUDY: a chain of TIM_NX (default 8, at most 8) exchanges on
// local eight-channel trunks, with the timing probes (tim_probe.svh).
//
//   x0 blk1 == blk1 x1 blk3 == blk1 x2 blk3 == blk1 x3 ... x(N-1)
//   (blk1 faces W with g, blk3 faces E; x0's blk1 faces E)
//
// Codes: e b = 2 2, 2 3, 2 4, 2 5, 2 6, 2 7, then 3 2, 3 3.  Phones: 4 an
// exchange, 20-23 (only callers and called lines are needed).  Clocks: x0 at
// 0 ppm, then +A, -A, +A ... with +ppm_amp=A (default 100).
`timescale 1ns/1ps
`include "exch.vh"

`ifndef TIM_NX
`define TIM_NX 8
`endif

module tb_timn;
    localparam int NX = `TIM_NX;
    localparam [63:0] PH   = 64'h0000_0000_000F_0000;
    localparam [63:0] LT1  = 64'h0000_0000_0000_FF00;
    localparam [63:0] LT13 = 64'h0000_0000_FF00_FF00;
    function automatic [64*NX-1:0] mk_ph();
        for (int x = 0; x < NX; x++) mk_ph[x*64 +: 64] = PH;
    endfunction
    function automatic [64*NX-1:0] mk_tr();
        for (int x = 0; x < NX; x++) mk_tr[x*64 +: 64] = (x == 0 || x == NX-1) ? LT1 : LT13;
    endfunction
    function automatic [2:0] code_e(int x); return (x < 6) ? 3'd2 : 3'd3; endfunction
    function automatic [2:0] code_b(int x); return (x < 6) ? 3'(2 + x) : 3'(2 + x - 6); endfunction
    function automatic [3*NX-1:0] mk_ce();
        for (int x = 0; x < NX; x++) mk_ce[x*3 +: 3] = code_e(x);
    endfunction
    function automatic [3*NX-1:0] mk_cb();
        for (int x = 0; x < NX; x++) mk_cb[x*3 +: 3] = code_b(x);
    endfunction
    localparam [64*NX-1:0] LD_PHONES = mk_ph();
    localparam [64*NX-1:0] LD_TRUNKS = mk_tr();
    localparam [3*NX-1:0]  LD_CODE_E = mk_ce();
    localparam [3*NX-1:0]  LD_CODE_B = mk_cb();

`include "tim_harness.svh"

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

    int ppm_amp = 100;
    initial begin
        if (!$value$plusargs("ppm_amp=%d", ppm_amp)) ppm_amp = 100;
        $display("KNOB ppm_amp=%0d", ppm_amp);
    end

    localparam [7:0] WE = {2'd2, 1'b0, 3'b010, 2'b11};
    localparam [7:0] WW = {2'd3, 1'b1, 3'b010, 2'b11};

    wire [7:0] lc [0:NX-1];
    wire [7:0] la [0:NX-1];
    wire [7:0] lh [0:NX-1];
    wire [7:0] lk [0:NX-1];
    wire [7:0] up [0:NX-1];

    genvar gx;
    generate for (gx = 0; gx < NX; gx = gx + 1) begin : xs
        reg  ck = 1'b0;
        real hp = 122.070;
        initial begin
            int ppm;
            #0;
            ppm = (gx == 0) ? 0 : ((gx % 2) ? ppm_amp : -ppm_amp);
            hp = 122.070 / (1.0 + real'(ppm) * 1.0e-6);
            #(1 + gx * 13);
            forever #(hp) ck = ~ck;
        end
        assign ld_clk[gx] = ck;

        localparam int P1 = (gx == 0) ? 1 : ((gx == 1) ? 0 : gx - 1);   // who blk1 faces
        localparam int B1 = (gx <= 1) ? 1 : 3;                          // and on which block
        localparam bit HAS3 = (gx >= 1) && (gx < NX - 1);
        localparam int P3 = HAS3 ? gx + 1 : 0;
        localparam [7:0]  LTU_X  = HAS3 ? 8'b0000_1010 : 8'b0000_0010;
        localparam [63:0] LTW_X  = (gx == 0) ? {56'd0, WE, 8'd0} :
                                   HAS3      ? {32'd0, WE, 8'd0, WW, 8'd0} : {56'd0, WW, 8'd0};
        wire [7:0] ci = {4'd0, HAS3 ? lc[P3][1] : 1'b0, 1'b0, lc[P1][B1], 1'b0};
        wire [7:0] ai = {4'd0, HAS3 ? la[P3][1] : 1'b0, 1'b0, la[P1][B1], 1'b0};
        wire [7:0] hi = {4'd0, HAS3 ? lh[P3][1] : 1'b0, 1'b0, lh[P1][B1], 1'b0};
        wire [7:0] ki = {4'd0, HAS3 ? lk[P3][1] : 1'b0, 1'b0, lk[P1][B1], 1'b0};

        site_net #(`LD_SITE_TIMERS, .PHONES(PH), .TRUNKS(64'd0), .OWN_E(code_e(gx)), .OWN_B(code_b(gx)),
                   .LTU(LTU_X), .LTWORD(LTW_X)) u_s (
            `LD_SITE_COMMON(gx),
            .c_out(), .a_out(), .clk_out(), .c_in(64'd0), .a_in(64'd0), .clk_in(64'd0), .link_up(),
            .lt_c_out(lc[gx]), .lt_a_out(la[gx]), .lt_h_out(lh[gx]), .lt_k_out(lk[gx]),
            .lt_c_in(ci), .lt_a_in(ai), .lt_h_in(hi), .lt_k_in(ki), .lt_up(up[gx]));

        assign ld_tup[gx*64 +: 64] = {32'd0, HAS3 ? {8{up[gx][3]}} : 8'd0, 8'd0, {8{up[gx][1]}}, 8'd0};

        `LD_PROBE(gx, u_s);
        `TIM_TAP(gx, u_s);
`ifdef TIM_FIX
        `TIM_TAP_FIX(gx, u_s);
`endif
    end endgenerate
endmodule
