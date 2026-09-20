// tb_pool -- two callers at once, which needs a pool of everything.
//
// Both of A's lines dial exchange 23 IN LOCKSTEP, pulse for pulse.  That puts
// two registers to work at A, queues two hunts for the one scanner, lands two
// seizures on one block at B, makes both cells of B's monitor pool decide on
// the same 1 kHz tick, and has two of B's registers reading h s side by side.
// It is the end-to-end test exch-monitor.md 4's sizing argument never had.
//
//   1  20 dials 1 2 3 2 0 while 21 dials 1 2 3 2 1   -> two calls, two channels
//   2  20 AND 21 both dial 1 2 3 2 1                 -> one number, one winner:
//      both registers at B reach the same line inside one scan, and the second
//      must find it taken -- not write over the first
`timescale 1ns/1ps

module tb_pool;
    localparam integer HIT = 1, ID = 16, CLR = 32;
    localparam integer T_RISE = 64, T_FALL = 2048;
    localparam integer RING_ON = 200, RING_OFF = 400;
    localparam integer BRK_NS = 12_000_000, MK_NS = 8_000_000, PAUSE = 60_000_000;

    reg clk_a = 0, clk_b = 0, rst_n = 0;
    always #122.0703 clk_a = ~clk_a;
    initial begin #40; forever #122.0703 clk_b = ~clk_b; end

    reg  h20a=0, h21a=0, h20b=0, h21b=0;
    reg  t20a=0, t21a=0, t20b=0, t21b=0;
    wire r20a, r21a, r20b, r21b, e20a, e21a, e20b, e21b;
    wire ab, ba, lka, lkb, fsa, fsb, rca, rcb, dta, nga, dtb, ngb, mha, mhb, gca, gcb;
    wire [3:0] dha, dhb;

    net_site #(.OWN_E(3'd2), .OWN_B(3'd2), .DIR0(2'd2),
               .T_RISE(T_RISE), .T_FALL(T_FALL), .RING_ON(RING_ON), .RING_OFF(RING_OFF),
               .HIT(HIT), .ID(ID), .CLR(CLR), .T_GUARD(16), .T_CLAIM(250))
    A (.clk(clk_a), .rst_n(rst_n), .hook20(h20a), .hook21(h21a),
       .tx20(t20a), .tx21(t21a), .rx20(r20a), .rx21(r21a), .e20(e20a), .e21(e21a),
       .line_in(ba), .line_out(ab), .locked(lka),
       .frame_stb(fsa), .ring_cad_n(rca), .dt_bit(dta), .ng_bit(nga),
       .mon_held(mha), .got_claim(gca), .dirs_held(dha),
       .fan_legs(), .res_used(), .port_busy());

    net_site #(.OWN_E(3'd2), .OWN_B(3'd3), .DIR0(2'd3), .G0(1'b1),
               .T_RISE(T_RISE), .T_FALL(T_FALL), .RING_ON(RING_ON), .RING_OFF(RING_OFF),
               .HIT(HIT), .ID(ID), .CLR(CLR), .T_GUARD(16), .T_CLAIM(250))
    B (.clk(clk_b), .rst_n(rst_n), .hook20(h20b), .hook21(h21b),
       .tx20(t20b), .tx21(t21b), .rx20(r20b), .rx21(r21b), .e20(e20b), .e21(e21b),
       .line_in(ab), .line_out(ba), .locked(lkb),
       .frame_stb(fsb), .ring_cad_n(rcb), .dt_bit(dtb), .ng_bit(ngb),
       .mon_held(mhb), .got_claim(gcb), .dirs_held(dhb),
       .fan_legs(), .res_used(), .port_busy());

    reg pe = 0;
    bitpath p_2020 (.src_clk(clk_a), .src_fs(fsa), .src_bit(t20a),
                    .dst_clk(clk_b), .dst_fs(fsb), .dst_bit(r20b), .enable(pe));
    bitpath p_2121 (.src_clk(clk_a), .src_fs(fsa), .src_bit(t21a),
                    .dst_clk(clk_b), .dst_fs(fsb), .dst_bit(r21b), .enable(pe));
    bitpath p_2021 (.src_clk(clk_a), .src_fs(fsa), .src_bit(t20a),
                    .dst_clk(clk_b), .dst_fs(fsb), .dst_bit(r21b), .enable(pe));
    // B's cannot-complete card, as heard back at A
    bitpath p_ng20 (.src_clk(clk_b), .src_fs(fsb), .src_bit(ngb),
                    .dst_clk(clk_a), .dst_fs(fsa), .dst_bit(r20a), .enable(pe));
    bitpath p_ng21 (.src_clk(clk_b), .src_fs(fsb), .src_bit(ngb),
                    .dst_clk(clk_a), .dst_fs(fsa), .dst_bit(r21a), .enable(pe));

    always @(posedge clk_a) if (fsa) begin
        if (h20a) t20a <= $random; if (h21a) t21a <= $random; end
    always @(posedge clk_b) if (fsb) begin
        if (h20b) t20b <= $random; if (h21b) t21b <= $random; end

    integer errs = 0, chk = 0;
    task want(input v, input string what);
        begin
            chk = chk + 1;
            if (!v) begin errs = errs + 1; $display("     %-56s FAIL", what); end
            else $display("     %-56s ok", what);
        end
    endtask

    // both of A's lines dial, pulse for pulse: d20 on 20, d21 on 21
    task dial2(input integer d20, input integer d21);
        integer n20, n21, i, nmax;
        begin
            n20 = (d20 == 0) ? 10 : d20;  n21 = (d21 == 0) ? 10 : d21;
            nmax = (n20 > n21) ? n20 : n21;
            for (i = 0; i < nmax; i = i + 1) begin
                if (i < n20) h20a = 1'b0;  if (i < n21) h21a = 1'b0;  #(BRK_NS);
                h20a = 1'b1; h21a = 1'b1;  #(MK_NS);
            end
            #(PAUSE);
        end
    endtask

    initial begin
        $display("POOL (RTL) -- two callers at once: two registers, two monitor cells, one scanner.\n");
        #4000 rst_n = 1;
        wait (lka && lkb);
        #(20_000_000);

        // ---- 1. two calls at once ---------------------------------------
        $display("  1. 20 dials 1 2 3 2 0 while 21 dials 1 2 3 2 1, pulse for pulse.");
        h20a = 1; h21a = 1;                          // both lift together
        #(60_000_000);
        dial2(1, 1);                                 // two keys: two hunts, one scanner
        #(40_000_000);
        want(dha != 4'd0 && mhb, "trunks seized toward B, and B's monitor pool is counting");
        dial2(2, 2); dial2(3, 3);                    // e b: both of B's cells decide together
        #(40_000_000);
        want(gca, "claims came back");
        dial2(2, 2); dial2(0, 1);                    // h s: 2 0 and 2 1
        #(80_000_000);
        begin : rung
            // both of B's lines must actually RING: E high while still on-hook,
            // at some point in a full cadence period
            integer i; reg s20, s21;
            s20 = 0; s21 = 0;
            for (i = 0; i < 700; i = i + 1) begin
                #(15625);
                if (e20b) s20 = 1;  if (e21b) s21 = 1;
            end
            want(s20 && s21, "both of B's lines ring, from two callers at once");
        end
        h20b = 1; h21b = 1;                          // both answer
        #(30_000_000);
        want(e20a && e21a && e20b && e21b, "both calls answered, at both ends");
        pe = 1; #(6_000_000); pe = 0;
        p_2020.report("speech A20 -> B20");
        p_2121.report("speech A21 -> B21");
        chk = chk + 2;
        if (p_2020.best_err != 0) errs = errs + 1;
        if (p_2121.best_err != 0) errs = errs + 1;
        h20a = 0; h21a = 0; h20b = 0; h21b = 0;
        #(150_000_000);
        want(!e20a && !e21a && !e20b && !e21b, "both released");

        // ---- 2. one number, two callers, one scan -----------------------
        $display("\n  2. 20 AND 21 both dial 1 2 3 2 1: one line, and only one may have it.");
        h20a = 1; h21a = 1;
        #(60_000_000);
        dial2(1, 1); dial2(2, 2); dial2(3, 3); dial2(2, 2); dial2(1, 1);
        #(80_000_000);
        h21b = 1;                                    // B's 21 answers whoever won
        #(30_000_000);
        p_2021.clear; p_2121.clear; p_ng20.clear; p_ng21.clear;
        pe = 1; #(6_000_000); pe = 0;
        $display("       A20->B21: %0d wrong   A21->B21: %0d wrong   (of %0d)",
                 p_2021.best_errs(), p_2121.best_errs(), p_2121.nbits);
        want((p_2021.best_errs() == 0) ^ (p_2121.best_errs() == 0),
             "exactly one caller is talking to B's 21");
        want((p_ng20.best_errs() == 0) ^ (p_ng21.best_errs() == 0),
             "and exactly one hears B's cannot-complete, across the trunk");
        want((p_2021.best_errs() == 0) != (p_ng20.best_errs() == 0),
             "the loser is the one who is not connected");
        h20a = 0; h21a = 0; h21b = 0;
        #(150_000_000);
        want(!e20a && !e21a && !e21b, "everything released");

        $display("\n  %0d checks, %0d errors.  %s", chk, errs, (errs == 0) ? "PASS" : "FAIL");
        $finish;
    end

    initial begin #6_000_000_000; $display("  TIMEOUT"); $finish; end
endmodule
