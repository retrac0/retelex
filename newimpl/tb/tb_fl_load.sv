// tb_fl_load -- TRAFFIC LOAD as a regression: two exchanges on a local
// eight-channel trunk, every line a random subscriber, every call classified
// by what its two ends heard.  flood-study/REPORT.md §4, §6.7.
//
//     A 2 2  blk 1 ========== blk 1  B 2 3
//            faces E                 faces W, glare          B's crystal +100 ppm
//
// tb_lfull's wiring, filled with phones: each exchange is site_net (the mini
// marker with its line register and its claim register, a network unit),
// tone sources at 01 and 03, a local trunk unit on block 1 of each, and
// phones on blocks 2-7 of both -- 48 lines each, 20-77.  The harness
// (tb_fl_load_harness.svh) is the flood study's, ported to the claim
// register; this file is only the wiring and the run's knobs.
//
// What it proves, at scale 8 over LD_DEF_DUR of random traffic and a drain:
//   - SAFETY: no wrong number, no joined callers, no third party on a call,
//     no phantom or wrong ring, no idle line hearing a caller;
//   - LIVENESS: every caller hears something after dialling, nothing is
//     held past its watchdog, and after the drain every port, the line
//     register and the claim register, the marker and its claim sequencer,
//     the origin, the monitors, the resolvers, the sweep, the queues and the
//     hunt hold-off are idle;
//   - that it was real traffic: at least LD_MIN_OK calls carried, LD_MIN_NOK
//     of them between the exchanges, and LD_MIN_TAKE claims taken.
// The knobs below are its defaults; any of them, and every other knob in the
// harness, can be given as a plusarg to run it as a load study instead (the
// SUMMARY lines have the figures; flood-study/work/load/cap2/parse.py reads them).
//
// The load: about 1.7 attempts a second an exchange, half of them to the
// other exchange, 5 % abandoned at a random moment between lift and answer.
// Each line register is busy about 55 % of the time and each claim register
// 20-30 %; claims cross and about one in ten is refused -- past the old
// knee (REPORT §2.1: 0.75 attempts/s at 100 % network), short of saturation.
// 9 s of traffic is about 30 calls.  About 11.5 s simulated: 4-5 minutes on
// an idle machine, 8-10 with two other benches running.
//
// A claim register attached late -- faults.py's F55, the claim waiting for
// the line register -- misses the start of h s: in this run A76 dials
// 1 2 3 7 4 at 7.3 s and B44 rings, a wrong number.  The run must cover it.
`timescale 1ns/1ps
`include "exch.vh"

module tb_fl_load;
    localparam int NX = 2;
    localparam [63:0] PH = 64'hFFFF_FFFF_FFFF_0000;          // 20-77
    localparam [63:0] LT = 64'h0000_0000_0000_FF00;          // block 1: the trunk
    localparam [64*NX-1:0] LD_PHONES = {PH, PH};
    localparam [64*NX-1:0] LD_TRUNKS = {LT, LT};
    localparam [3*NX-1:0]  LD_CODE_E = {3'd2, 3'd2};
    localparam [3*NX-1:0]  LD_CODE_B = {3'd3, 3'd2};

    // the regression's run, and what it must carry
    localparam int LD_DEF_SEED = 11, LD_DEF_DUR = 9000, LD_DEF_IDLE = 30000;
    localparam int LD_DEF_PNET = 500, LD_DEF_ABANDON = 50, LD_DEF_DRAIN = 2500;
    localparam int LD_MIN_OK = 12, LD_MIN_NOK = 6, LD_MIN_TAKE = 6;   // half of what it carries (24, 11, 11)

// from the tree root, where make runs every bench
`include "tb/tb_fl_load_harness.svh"

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
