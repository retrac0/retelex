// tb_hub -- a HUB with four directions, and the resolvers of network.md 3.2.
//
//                      C  24
//                      |  N
//        22  A ── W ── H ── E ── B  23
//                      |  S
//                      D  25
//
// H is 21, and it has four directions: W to A on block 0, E to B on block 1,
// N to C on block 3, S to D on block 4.  A, B, C and D have one each.
//
// A transit on a chain forwards into its ONE other direction: two latches, and
// it holds nothing.  A hub forwards into THREE, and the caller's pulses go down
// every leg at once -- but the incoming trunk can listen to only one port, and
// which leg will claim is not known until the claim comes back.  Latches cannot
// be read back, so the hub must remember the call until then.  That memory is
// the resolver, and this is what it has to do:
//
//   1. A's 20 dials 1 2 3 2 1     three legs seized at once; B claims; the other
//                                 two are pointed at idle and their links go
//   2. A's 20 dials 1 2 1 2 1     the hub's OWN code: its monitor claims, as any
//                                 owner does, and every leg is pointed at idle
//   3. a second flood, while the   one resolver, so the second seizure takes the
//      first is still unresolved   first direction found and that branch only --
//                                  which completes if the called exchange is
//                                  behind it, and is lost if it is not
`timescale 1ns/1ps

module tb_hub #(
    parameter integer ONLY  = 0,         // 0 = every scenario; 1, 2, 3 = just that one
    parameter         TRACE = 1'b0
) ();
    localparam integer HIT = 1, ID = 16, CLR = 32;
    localparam integer T_RISE = 64, T_FALL = 2048;
    localparam integer RING_ON = 200, RING_OFF = 400;
    localparam integer BRK_NS = 12_000_000, MK_NS = 8_000_000, PAUSE = 60_000_000;
    localparam integer FR = 15625;
    localparam [1:0] N = 2'd0, S = 2'd1, E = 2'd2, W = 2'd3;

    // the trunk channels of the hub's four blocks
    localparam [63:0] HUBT = 64'h0000_00EE_EE00_EEEE;

    reg clk_h=0, clk_a=0, clk_b=0, clk_c=0, clk_d=0, rst_n=0;
    always #122.0703 clk_h = ~clk_h;
    initial begin #40;  forever #122.0703 clk_a = ~clk_a; end
    initial begin #80;  forever #122.0703 clk_b = ~clk_b; end
    initial begin #20;  forever #122.0703 clk_c = ~clk_c; end
    initial begin #60;  forever #122.0703 clk_d = ~clk_d; end


    wire ha_, ah, hb_, bh, hc_, ch, hd_, dh;       // the four links, each way
    wire [3:0] lkh;
    wire lka, lkb, lkc, lkd;
    wire fsh,fsa,fsb,fsc,fsd, rch,rca,rcb,rcc,rcd;
    wire dth,ngh,dta,nga,dtb,ngb,dtc,ngc,dtd,ngd;
    wire mhh,mha,mhb,mhc,mhd, gch,gca,gcb,gcc,gcd;
    wire [3:0] dhh,dha,dhb,dhc,dhd;
    wire [3:0] flh, ruh;
    wire [63:0] pbh, pba, pbb, pbc, pbd;

    // what is seized at the hub, at any instant: a channel a link a call
    wire [31:0] hubchans = $countones(pbh & HUBT);

    reg  [63:0] hk_h = 0, hk_a = 0, hk_b = 0, hk_c = 0, hk_d = 0;
    reg  [63:0] tx_h = 0, tx_a = 0, tx_b = 0, tx_c = 0, tx_d = 0;
    wire [63:0] rx_h, rx_a, rx_b, rx_c, rx_d;
    wire [63:0] ln_h, ln_a, ln_b, ln_c, ln_d;

    // ---- the hub: code 21, four directions, one resolver ----------------
    net_site #(.OWN_E(3'd2), .OWN_B(3'd1), .NRES(1),
               .NDIR(4), .DIR0(W), .G0(1'b1), .DIR1(E), .G1(1'b1),
                         .DIR2(N), .G2(1'b1), .DIR3(S), .G3(1'b1),
               .T_RISE(T_RISE), .T_FALL(T_FALL), .RING_ON(RING_ON), .RING_OFF(RING_OFF),
               .HIT(HIT), .ID(ID), .CLR(CLR), .T_GUARD(16), .T_CLAIM(250))
    H (.clk(clk_h), .rst_n(rst_n),
       .hook(hk_h), .tx(tx_h), .rx(rx_h), .e(ln_h),
       .line_in({dh, ch, bh, ah}), .line_out({hd_, hc_, hb_, ha_}), .locked(lkh),
       .frame_stb(fsh), .ring_cad_n(rch), .dt_bit(dth), .ng_bit(ngh),
       .mon_held(mhh), .got_claim(gch), .dirs_held(dhh),
       .fan_legs(flh), .res_used(ruh), .port_busy(pbh), .regs_busy(), .wq_ovf(), .n_defer(),
       .wr_stb(), .wr_dst(), .wr_src(), .wr_bsy(), .wr_clm());

    // ---- the four leaves, one direction each ----------------------------
    net_site #(.OWN_E(3'd2), .OWN_B(3'd2), .DIR0(E),
               .T_RISE(T_RISE), .T_FALL(T_FALL), .RING_ON(RING_ON), .RING_OFF(RING_OFF),
               .HIT(HIT), .ID(ID), .CLR(CLR), .T_GUARD(16), .T_CLAIM(250))
    A (.clk(clk_a), .rst_n(rst_n),
       .hook(hk_a), .tx(tx_a), .rx(rx_a), .e(ln_a),
       .line_in(ha_), .line_out(ah), .locked(lka),
       .frame_stb(fsa), .ring_cad_n(rca), .dt_bit(dta), .ng_bit(nga),
       .mon_held(mha), .got_claim(gca), .dirs_held(dha),
       .fan_legs(), .res_used(), .port_busy(pba), .regs_busy(), .wq_ovf(), .n_defer(),
       .wr_stb(), .wr_dst(), .wr_src(), .wr_bsy(), .wr_clm());

    net_site #(.OWN_E(3'd2), .OWN_B(3'd3), .DIR0(W),
               .T_RISE(T_RISE), .T_FALL(T_FALL), .RING_ON(RING_ON), .RING_OFF(RING_OFF),
               .HIT(HIT), .ID(ID), .CLR(CLR), .T_GUARD(16), .T_CLAIM(250))
    B (.clk(clk_b), .rst_n(rst_n),
       .hook(hk_b), .tx(tx_b), .rx(rx_b), .e(ln_b),
       .line_in(hb_), .line_out(bh), .locked(lkb),
       .frame_stb(fsb), .ring_cad_n(rcb), .dt_bit(dtb), .ng_bit(ngb),
       .mon_held(mhb), .got_claim(gcb), .dirs_held(dhb),
       .fan_legs(), .res_used(), .port_busy(pbb), .regs_busy(), .wq_ovf(), .n_defer(),
       .wr_stb(), .wr_dst(), .wr_src(), .wr_bsy(), .wr_clm());

    net_site #(.OWN_E(3'd2), .OWN_B(3'd4), .DIR0(S),
               .T_RISE(T_RISE), .T_FALL(T_FALL), .RING_ON(RING_ON), .RING_OFF(RING_OFF),
               .HIT(HIT), .ID(ID), .CLR(CLR), .T_GUARD(16), .T_CLAIM(250))
    C (.clk(clk_c), .rst_n(rst_n),
       .hook(hk_c), .tx(tx_c), .rx(rx_c), .e(ln_c),
       .line_in(hc_), .line_out(ch), .locked(lkc),
       .frame_stb(fsc), .ring_cad_n(rcc), .dt_bit(dtc), .ng_bit(ngc),
       .mon_held(mhc), .got_claim(gcc), .dirs_held(dhc),
       .fan_legs(), .res_used(), .port_busy(pbc), .regs_busy(), .wq_ovf(), .n_defer(),
       .wr_stb(), .wr_dst(), .wr_src(), .wr_bsy(), .wr_clm());

    net_site #(.OWN_E(3'd2), .OWN_B(3'd5), .DIR0(N),
               .T_RISE(T_RISE), .T_FALL(T_FALL), .RING_ON(RING_ON), .RING_OFF(RING_OFF),
               .HIT(HIT), .ID(ID), .CLR(CLR), .T_GUARD(16), .T_CLAIM(250))
    D (.clk(clk_d), .rst_n(rst_n),
       .hook(hk_d), .tx(tx_d), .rx(rx_d), .e(ln_d),
       .line_in(hd_), .line_out(dh), .locked(lkd),
       .frame_stb(fsd), .ring_cad_n(rcd), .dt_bit(dtd), .ng_bit(ngd),
       .mon_held(mhd), .got_claim(gcd), .dirs_held(dhd),
       .fan_legs(), .res_used(), .port_busy(pbd), .regs_busy(), .wq_ovf(), .n_defer(),
       .wr_stb(), .wr_dst(), .wr_src(), .wr_bsy(), .wr_clm());

    reg path_en = 0;
    bitpath p_a20b21 (.src_clk(clk_a), .src_fs(fsa), .src_bit(tx_a[6'o20]),
                      .dst_clk(clk_b), .dst_fs(fsb), .dst_bit(rx_b[6'o21]), .enable(path_en));
    bitpath p_b21a20 (.src_clk(clk_b), .src_fs(fsb), .src_bit(tx_b[6'o21]),
                      .dst_clk(clk_a), .dst_fs(fsa), .dst_bit(rx_a[6'o20]), .enable(path_en));

    always @(posedge clk_a) if (fsa) begin
        if (hk_a[6'o20]) tx_a[6'o20] <= $random; if (hk_a[6'o21]) tx_a[6'o21] <= $random; end
    always @(posedge clk_b) if (fsb) begin
        if (hk_b[6'o20]) tx_b[6'o20] <= $random; if (hk_b[6'o21]) tx_b[6'o21] <= $random; end
    always @(posedge clk_c) if (fsc) begin
        if (hk_c[6'o20]) tx_c[6'o20] <= $random; if (hk_c[6'o21]) tx_c[6'o21] <= $random; end
    always @(posedge clk_d) if (fsd) begin
        if (hk_d[6'o20]) tx_d[6'o20] <= $random; if (hk_d[6'o21]) tx_d[6'o21] <= $random; end
    always @(posedge clk_h) if (fsh) begin
        if (hk_h[6'o20]) tx_h[6'o20] <= $random; if (hk_h[6'o21]) tx_h[6'o21] <= $random; end

    integer errs = 0, chk = 0;

    task want(input v, input string what);
        begin
            chk = chk + 1;
            if (!v) begin errs = errs + 1; $display("     %-54s FAIL", what); end
            else $display("     %-54s ok", what);
        end
    endtask

    task wantn(input v, input integer got, input string what);
        begin
            chk = chk + 1;
            if (!v) begin errs = errs + 1;
                $display("     %-54s FAIL (%0d)", what, got); end
            else $display("     %-54s ok  (%0d)", what, got);
        end
    endtask

    task dial_a(input integer d);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                hk_a[6'o20] = 1'b0; #(BRK_NS); hk_a[6'o20] = 1'b1; #(MK_NS);
            end
            #(PAUSE);
        end
    endtask

    task dial_c(input integer d);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                hk_c[6'o20] = 1'b0; #(BRK_NS); hk_c[6'o20] = 1'b1; #(MK_NS);
            end
            #(PAUSE);
        end
    endtask

    task ring21(input integer n, input string what, input integer which);
        integer i, hi, lo;
        reg ee, cad;
        begin
            hi = 0; lo = 0;
            for (i = 0; i < n; i = i + 1) begin
                #(FR);
                ee  = (which == 0) ? ln_b[6'o21] : (which == 1) ? ln_d[6'o21] : ln_h[6'o21];
                cad = (which == 0) ? rcb  : (which == 1) ? rcd  : rch;
                if (ee && !cad) hi = hi + 1;
                if (!ee && cad) lo = lo + 1;
            end
            chk = chk + 1;
            if (hi > n/4 && lo > n/4) $display("     %-54s ok", what);
            else begin errs = errs + 1;
                $display("     %-54s FAIL (%0d/%0d)", what, hi, lo); end
        end
    endtask

    integer nch;

    // what every exchange is holding, for when a scenario does not behave
    task snap(input string when);
        begin
            if (TRACE) $display("      [%-22s] hub res=%0d legs=%b ch=%0d | A d=%b m=%b c=%b ch=%0d | B m=%b c=%b ch=%0d | C d=%b m=%b c=%b ch=%0d | D m=%b c=%b ch=%0d",
                when, ruh, flh, hubchans,
                dha, mha, gca, $countones(pba & 64'hEE),
                mhb, gcb, $countones(pbb & 64'hEE),
                dhc, mhc, gcc, $countones(pbc & 64'hEE),
                mhd, gcd, $countones(pbd & 64'hEE));
        end
    endtask

    initial begin
        $display("HUB (RTL) -- four directions, a fan-out, and the resolvers of 3.2.\n");
        #4000 rst_n = 1;
        wait (&lkh && lka && lkb && lkc && lkd);
        $display("  0. All five exchanges up; four links locked.\n");
        #(20_000_000);

        // ---- 1. a call through the hub ---------------------------------
        if (ONLY == 0 || ONLY == 1) begin
        $display("  1. A's 20 dials 1 2 3 2 1 -- exchange 23, THROUGH the hub.");
        hk_a[6'o20] = 1; #(40_000_000);
        dial_a(1);
        #(60_000_000);
        want(mhb && mhc && mhd, "B, C and D all caught it: three legs at once");
        wantn(ruh == 4'd1, ruh, "the hub took a resolver");
        nch = hubchans;
        wantn($countones(flh) == 3, $countones(flh), "and it holds three legs");
        wantn(nch == 4, nch, "four trunk channels at the hub: in, and three out");
        dial_a(2);
        dial_a(3);
        #(30_000_000);
        want(gca, "23 claimed, and the claim reached A through the hub");
        wantn(ruh == 4'd0, ruh, "the resolver is free again: the call is two latches");
        #(80_000_000);
        nch = hubchans;
        wantn(nch == 2, nch, "and two channels are left -- C's leg and D's went");
        want(!mhc && !mhd, "C and D let go");
        dial_a(2); dial_a(1);
        #(60_000_000);
        ring21(2 * (RING_ON + RING_OFF), "B's 21 rings, from a caller across the hub", 0);
        hk_b[6'o21] = 1; #(20_000_000);
        want(ln_a[6'o20] && ln_b[6'o21], "answered at B, and A knows");
        path_en = 1; #(6_000_000); path_en = 0;
        p_a20b21.report("speech A20 -> B21, through the hub");
        p_b21a20.report("speech B21 -> A20, through the hub");
        chk = chk + 2;
        if (p_a20b21.best_err != 0 || p_b21a20.best_err != 0) errs = errs + 1;
        hk_b[6'o21] = 0; hk_a[6'o20] = 0; #(140_000_000);
        want(!ln_a[6'o20] && !ln_b[6'o21], "released, and every leg with it");
        nch = hubchans;
        wantn(nch == 0, nch, "nothing held at the hub");
        end

        // ---- 2. the hub is the owner ------------------------------------
        if (ONLY == 0 || ONLY == 2) begin
        $display("\n  2. A's 20 dials 1 2 1 2 1 -- the HUB's own code.");
        hk_a[6'o20] = 1; #(40_000_000);
        dial_a(1);
        #(60_000_000);
        wantn(ruh == 4'd1, ruh, "fanned out again: a resolver, three legs");
        dial_a(2);
        dial_a(1);
        #(40_000_000);
        want(gca, "the hub's own monitor claimed");
        wantn(ruh == 4'd0, ruh, "the resolver freed, every leg pointed at idle");
        #(80_000_000);
        nch = hubchans;
        wantn(nch == 1, nch, "one channel left: the trunk the hub claimed");
        want(!mhb && !mhc && !mhd, "B, C and D all let go");
        dial_a(2); dial_a(1);
        #(60_000_000);
        ring21(2 * (RING_ON + RING_OFF), "the hub's own 21 rings", 2);
        hk_h[6'o21] = 1; #(20_000_000);
        want(ln_a[6'o20] && ln_h[6'o21], "answered at the hub");
        hk_h[6'o21] = 0; hk_a[6'o20] = 0; #(140_000_000);
        nch = hubchans;
        wantn(nch == 0, nch, "released");
        end

        // ---- 3. a second flood while the one resolver is held ------------
        // A resolver is held from the seizure to the claim -- the 2.2-3.2 s it
        // takes to dial e and b.  A second flood arriving inside that window
        // finds none free, and then 3.2 says: "patch into the first direction
        // found, as a chain would: the call reaches that branch only".  In
        // direction order N S E W that is S, D's link -- so C's call completes
        // because 25 is behind it, and would have been lost had C wanted 23.
        if (ONLY == 0 || ONLY == 3) begin
        $display("\n  3. A second flood arrives while the one resolver is held.");
        hk_a[6'o20] = 1; #(40_000_000);
        dial_a(1);                                  // A floods: three legs
        #(60_000_000);
        wantn(ruh == 4'd1, ruh, "A's flood has the resolver");
        snap("A flooded");
        hk_c[6'o20] = 1; #(40_000_000);
        dial_c(1);                                  // C floods: no resolver free
        #(60_000_000);
        wantn(ruh == 4'd1, ruh, "C's flood found none free");
        nch = hubchans;
        wantn(nch == 6, nch, "six channels, not eight: C's took ONE leg");
        snap("C flooded");
        dial_a(2); snap("A dialled e"); dial_c(2); snap("C dialled e");
        dial_a(5); snap("A dialled b"); dial_c(5); snap("C dialled b");
        #(40_000_000);
        snap("both b in");
        want(gca, "A's call, which had the resolver, reached 25");
        want(gcc, "and C's, on its one leg, reached 25 too");
        wantn(ruh == 4'd0, ruh, "the resolver went back when A's call claimed");
        dial_a(2); dial_c(2);                       // h
        dial_a(1); dial_c(0);                       // s: A wants 21, C wants 20
        #(60_000_000);
        ring21(2 * (RING_ON + RING_OFF), "D's 21 rings, from A across the hub", 1);
        hk_d[6'o21] = 1; hk_d[6'o20] = 1; #(20_000_000);
        want(ln_a[6'o20] && ln_d[6'o21], "A is answered at D's 21");
        want(ln_c[6'o20] && ln_d[6'o20], "and C at D's 20: two calls through one hub");
        nch = hubchans;
        wantn(nch == 4, nch, "four channels: two calls, two latches each");
        hk_d[6'o21] = 0; hk_d[6'o20] = 0; hk_a[6'o20] = 0; hk_c[6'o20] = 0; #(160_000_000);
        nch = hubchans;
        wantn(nch == 0, nch, "everything released at the hub");
        end

        $display("\n  %0d checks, %0d errors.  %s", chk, errs, (errs == 0) ? "PASS" : "FAIL");
        $finish;
    end

    initial begin #12_000_000_000; $display("  TIMEOUT"); $finish; end
endmodule
