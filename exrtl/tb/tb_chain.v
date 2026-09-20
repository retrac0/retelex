// tb_chain -- three exchanges in a chain, and a call that TRANSITS one.
//
//     22 ═══ 23 ═══ 24
//      A      B      C
//
// A faces E and has one direction.  B faces W toward A and E toward C, so it is
// a transit: a seizure arriving on one is patched onward into the other, two
// latches, and the exchange forgets it -- no register, no digits, nothing that
// knows where the call is going.  C faces W and has one direction.
//
// This is exch-network.md 3.1's worked example, one exchange shorter:
//
//   A's 20 dials 1 2 4 2 1     the key seizes toward B; B patches onward to C;
//                              every monitor hears e then b; B's b is 3 and it
//                              lets go, C's is 4 and it CLAIMS.  Backward A
//                              rises through the patch at B and reaches A
//   B's 20 dials 1 2 4 2 1     from the MIDDLE: B seizes in BOTH directions at
//                              once, A hears a b that is not its own and lets
//                              go, C claims, and B releases the trunk it was
//                              holding toward A
`timescale 1ns/1ps

module tb_chain;
    localparam integer HIT = 1, ID = 16, CLR = 32;
    localparam integer T_RISE = 64, T_FALL = 2048;
    localparam integer RING_ON = 200, RING_OFF = 400;
    localparam integer BRK_NS = 12_000_000, MK_NS = 8_000_000, PAUSE = 60_000_000;
    localparam integer FR = 15625;
    localparam [1:0] N = 2'd0, S = 2'd1, E = 2'd2, W = 2'd3;

    reg clk_a = 0, clk_b = 0, clk_c = 0, rst_n = 0;
    always #122.0703 clk_a = ~clk_a;
    initial begin #40;  forever #122.0703 clk_b = ~clk_b; end
    initial begin #80;  forever #122.0703 clk_c = ~clk_c; end

    reg  h20a=0,h21a=0,h20b=0,h21b=0,h20c=0,h21c=0;
    reg  t20a=0,t21a=0,t20b=0,t21b=0,t20c=0,t21c=0;
    wire r20a,r21a,r20b,r21b,r20c,r21c, e20a,e21a,e20b,e21b,e20c,e21c;
    wire ab, ba, bc, cb;                       // the two links, each way
    wire lka, lkb0, lkb1, lkc, fsa, fsb, fsc, rca, rcb, rcc;
    wire dta,nga,dtb,ngb,dtc,ngc, mha,mhb,mhc, gca,gcb,gcc;
    wire [3:0] dha, dhb, dhc;

    // A: code 22, one direction, facing E toward B
    net_site #(.OWN_E(3'd2), .OWN_B(3'd2), .DIR0(E),
               .T_RISE(T_RISE), .T_FALL(T_FALL), .RING_ON(RING_ON), .RING_OFF(RING_OFF),
               .HIT(HIT), .ID(ID), .CLR(CLR), .T_GUARD(16), .T_CLAIM(250))
    A (.clk(clk_a), .rst_n(rst_n), .hook20(h20a), .hook21(h21a),
       .tx20(t20a), .tx21(t21a), .rx20(r20a), .rx21(r21a), .e20(e20a), .e21(e21a),
       .line_in(ba), .line_out(ab), .locked(lka),
       .frame_stb(fsa), .ring_cad_n(rca), .dt_bit(dta), .ng_bit(nga),
       .mon_held(mha), .got_claim(gca), .dirs_held(dha),
       .fan_legs(), .res_used(), .port_busy());

    // B: code 23, a transit.  W toward A on block 0, E toward C on block 1.
    // The glare bit is set at one end of each link, here B's W side and C's.
    net_site #(.OWN_E(3'd2), .OWN_B(3'd3), .NDIR(2), .DIR0(W), .G0(1'b1),
               .DIR1(E),
               .T_RISE(T_RISE), .T_FALL(T_FALL), .RING_ON(RING_ON), .RING_OFF(RING_OFF),
               .HIT(HIT), .ID(ID), .CLR(CLR), .T_GUARD(16), .T_CLAIM(250))
    B (.clk(clk_b), .rst_n(rst_n), .hook20(h20b), .hook21(h21b),
       .tx20(t20b), .tx21(t21b), .rx20(r20b), .rx21(r21b), .e20(e20b), .e21(e21b),
       .line_in({cb, ab}), .line_out({bc, ba}), .locked({lkb1, lkb0}),
       .frame_stb(fsb), .ring_cad_n(rcb), .dt_bit(dtb), .ng_bit(ngb),
       .mon_held(mhb), .got_claim(gcb), .dirs_held(dhb),
       .fan_legs(), .res_used(), .port_busy());

    // C: code 24, one direction, facing W toward B
    net_site #(.OWN_E(3'd2), .OWN_B(3'd4), .DIR0(W), .G0(1'b1),
               .T_RISE(T_RISE), .T_FALL(T_FALL), .RING_ON(RING_ON), .RING_OFF(RING_OFF),
               .HIT(HIT), .ID(ID), .CLR(CLR), .T_GUARD(16), .T_CLAIM(250))
    C (.clk(clk_c), .rst_n(rst_n), .hook20(h20c), .hook21(h21c),
       .tx20(t20c), .tx21(t21c), .rx20(r20c), .rx21(r21c), .e20(e20c), .e21(e21c),
       .line_in(bc), .line_out(cb), .locked(lkc),
       .frame_stb(fsc), .ring_cad_n(rcc), .dt_bit(dtc), .ng_bit(ngc),
       .mon_held(mhc), .got_claim(gcc), .dirs_held(dhc),
       .fan_legs(), .res_used(), .port_busy());

    reg path_en = 0;
    bitpath p_a20c21 (.src_clk(clk_a), .src_fs(fsa), .src_bit(t20a),
                      .dst_clk(clk_c), .dst_fs(fsc), .dst_bit(r21c), .enable(path_en));
    bitpath p_c21a20 (.src_clk(clk_c), .src_fs(fsc), .src_bit(t21c),
                      .dst_clk(clk_a), .dst_fs(fsa), .dst_bit(r20a), .enable(path_en));
    bitpath p_b20c21 (.src_clk(clk_b), .src_fs(fsb), .src_bit(t20b),
                      .dst_clk(clk_c), .dst_fs(fsc), .dst_bit(r21c), .enable(path_en));

    always @(posedge clk_a) if (fsa) begin
        if (h20a) t20a <= $random; if (h21a) t21a <= $random; end
    always @(posedge clk_b) if (fsb) begin
        if (h20b) t20b <= $random; if (h21b) t21b <= $random; end
    always @(posedge clk_c) if (fsc) begin
        if (h20c) t20c <= $random; if (h21c) t21c <= $random; end

    integer errs = 0, chk = 0;

    task want(input v, input string what);
        begin
            chk = chk + 1;
            if (!v) begin errs = errs + 1; $display("     %-52s FAIL", what); end
            else $display("     %-52s ok", what);
        end
    endtask

    task dial_a(input integer d);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                h20a = 1'b0; #(BRK_NS); h20a = 1'b1; #(MK_NS);
            end
            #(PAUSE);
        end
    endtask

    task dial_b(input integer d);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                h20b = 1'b0; #(BRK_NS); h20b = 1'b1; #(MK_NS);
            end
            #(PAUSE);
        end
    endtask

    task ring_c21(input integer n, input string what);
        integer i, hi, lo;
        begin
            hi = 0; lo = 0;
            for (i = 0; i < n; i = i + 1) begin
                #(FR);
                if (e21c && !rcc) hi = hi + 1;
                if (!e21c && rcc) lo = lo + 1;
            end
            chk = chk + 1;
            if (hi > n/4 && lo > n/4) $display("     %-52s ok", what);
            else begin errs = errs + 1;
                $display("     %-52s FAIL (%0d/%0d)", what, hi, lo); end
        end
    endtask

    initial begin
        $display("CHAIN (RTL) -- 22 = 23 = 24, and a call that transits 23.\n");
        #4000 rst_n = 1;
        wait (lka && lkb0 && lkb1 && lkc);
        $display("  0. All three framers locked; two links up.\n");
        #(20_000_000);

        // ---- 1. a call across two hops ---------------------------------
        $display("  1. A's 20 dials 1 2 4 2 1 -- exchange 24, two hops away.");
        h20a = 1; #(40_000_000);
        dial_a(1);
        #(60_000_000);              // a hop is a scan at each exchange
        want(mhb && mhc, "B and C both caught the seizure: it was forwarded");
        dial_a(2);
        dial_a(4);
        #(30_000_000);
        want(gca, "the claim came back to A, through B's patch");
        want(!mhb, "B's monitor let go: 4 is not its b");
        dial_a(2); dial_a(1);
        #(60_000_000);
        ring_c21(2 * (RING_ON + RING_OFF), "C's 21 rings, from a caller two hops away");
        h21c = 1; #(20_000_000);
        want(e20a && e21c, "answered at C, and A knows");
        path_en = 1; #(6_000_000); path_en = 0;
        p_a20c21.report("speech A20 -> C21, two hops");
        p_c21a20.report("speech C21 -> A20, two hops");
        chk = chk + 2;
        if (p_a20c21.best_err != 0 || p_c21a20.best_err != 0) errs = errs + 1;
        h21c = 0; h20a = 0; #(120_000_000);
        want(!e20a && !e21c, "release runs the whole way back");

        // ---- 2. from the middle: seize in every direction ---------------
        $display("\n  2. B's 20 dials 1 2 4 2 1 -- from the MIDDLE of the chain.");
        h20b = 1; #(40_000_000);
        dial_b(1);
        #(60_000_000);
        want(dhb == 4'b1100 || dhb[2] && dhb[3],
             "B seized in BOTH its directions at once");
        want(mha && mhc, "A and C both heard it");
        dial_b(2); dial_b(4);
        #(30_000_000);
        want(gcb, "C claimed; the claim reached B");
        want(!mha, "A's monitor let go: 4 is not its b");
        dial_b(2); dial_b(1);
        #(60_000_000);
        ring_c21(2 * (RING_ON + RING_OFF), "C's 21 rings, from B");
        h21c = 1; #(20_000_000);
        want(e20b && e21c, "answered");
        want($countones(dhb) <= 1, "B released the trunk that did not claim");
        p_b20c21.clear;
        path_en = 1; #(6_000_000); path_en = 0;
        p_b20c21.report("speech B20 -> C21, one hop");
        chk = chk + 1; if (p_b20c21.best_err != 0) errs = errs + 1;
        h21c = 0; h20b = 0; #(120_000_000);

        $display("\n  %0d checks, %0d errors.  %s", chk, errs, (errs == 0) ? "PASS" : "FAIL");
        $finish;
    end

    initial begin #6_000_000_000; $display("  TIMEOUT"); $finish; end
endmodule
