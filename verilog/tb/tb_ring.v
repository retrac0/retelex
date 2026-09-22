// tb_ring -- four exchanges in a RING, and the jumper that keeps a flood from
// going round in circles.  network.md 3.3.
//
//        22  A ══ E/W ══ B  23
//            ║             ║
//           W/E           E/W          the link 25 ══ 22 is STRAPPED, at both ends
//            ║             ║
//        25  D ══ W/E ══ C  24
//
// The no-forward jumper is one plug a compass direction on the network unit
// (extensions.md 2.2, STRAP_N), set on every channel of one link, at both ends:
//
//   a seizure is never forwarded INTO a jumpered link, and a seizure that
//   arrives ON one is never forwarded onward.  An origin may still seize it,
//   and the far end may still claim.
//
//   1. A dials 1 2 4 2 1     24 is two hops either way.  The short way claims;
//                            the long way and the jumpered link are released,
//                            and 24 must clear its OWN onward patch toward 25
//   2. A dials 1 2 5 2 1     25 is the far end of the jumpered link, and the
//                            call reaches it TWICE -- once on the link, once the
//                            long way round.  Both claim; no caller hears the
//                            second; and which one the origin keeps is decided
//                            by its SCANNER, not by which claimed first
//   3. `make ring-open`      the same ring with the jumper OUT: the flood comes
//                            back to the exchange that made it, which forwards
//                            it again, and the call eats a channel of every
//                            link at each turn until the links are full
`timescale 1ns/1ps

module tb_ring #(
    parameter         JUMPER = 1'b1,      // 0: take the jumper out and watch it circle
    parameter         TRACE = 1'b0
) ();
    localparam integer HIT = 1, ID = 16, CLR = 32;
    localparam integer T_RISE = 64, T_FALL = 2048;
    localparam integer RING_ON = 200, RING_OFF = 400;
    localparam integer BRK_NS = 12_000_000, MK_NS = 8_000_000, PAUSE = 60_000_000;
    localparam integer FR = 15625;
    localparam [1:0] N = 2'd0, S = 2'd1, E = 2'd2, W = 2'd3;

    // the six channels of each of an exchange's two trunk blocks (1 and 3)
    localparam [63:0] TR = 64'h0000_0000_EE00_EE00;

    reg clk_a=0, clk_b=0, clk_c=0, clk_d=0, rst_n=0;
    always #122.0703 clk_a = ~clk_a;
    initial begin #40;  forever #122.0703 clk_b = ~clk_b; end
    initial begin #80;  forever #122.0703 clk_c = ~clk_c; end
    initial begin #20;  forever #122.0703 clk_d = ~clk_d; end


    wire a2b, b2a, b2c, c2b, c2d, d2c, d2a, a2d;   // the four links, each way
    wire [1:0] lka, lkb, lkc, lkd;
    wire fsa,fsb,fsc,fsd, rca,rcb,rcc,rcd;
    wire dta,nga,dtb,ngb,dtc,ngc,dtd,ngd;
    wire mha,mhb,mhc,mhd, gca,gcb,gcc,gcd;
    wire [3:0] dha,dhb,dhc,dhd, fla,flb,flc,fld, rua,rub,ruc,rud;
    wire [63:0] pba, pbb, pbc, pbd;

    // every trunk channel seized anywhere in the ring: one a link a call, or
    // one a link a TURN if nothing breaks the loop
    wire [31:0] ringchans = $countones(pba & TR) + $countones(pbb & TR)
                          + $countones(pbc & TR) + $countones(pbd & TR);

    reg  [63:0] hk_a = 0, hk_b = 0, hk_c = 0, hk_d = 0;
    reg  [63:0] tx_a = 0, tx_b = 0, tx_c = 0, tx_d = 0;
    wire [63:0] rx_a, rx_b, rx_c, rx_d;
    wire [63:0] ln_a, ln_b, ln_c, ln_d;

    // A: 22.  Block 1 E toward B; block 3 W toward D -- the jumpered link.
    net_site #(.OWN_E(3'd2), .OWN_B(3'd2), .NDIR(2),
               .DIR0(E), .G0(1'b1), .DIR1(W), .N1(JUMPER),
               .T_RISE(T_RISE), .T_FALL(T_FALL), .RING_ON(RING_ON), .RING_OFF(RING_OFF),
               .HIT(HIT), .ID(ID), .CLR(CLR), .T_GUARD(16), .T_CLAIM(250))
    A (.clk(clk_a), .rst_n(rst_n),
       .hook(hk_a), .tx(tx_a), .rx(rx_a), .e(ln_a),
       .line_in({d2a, b2a}), .line_out({a2d, a2b}), .locked(lka),
       .frame_stb(fsa), .ring_cad_n(rca), .dt_bit(dta), .ng_bit(nga),
       .mon_held(mha), .got_claim(gca), .dirs_held(dha),
       .fan_legs(fla), .res_used(rua), .port_busy(pba), .regs_busy(), .wq_ovf(), .n_defer(),
       .wr_stb(), .wr_dst(), .wr_src(), .wr_bsy(), .wr_clm());

    // B: 23.  Block 1 W toward A; block 3 E toward C.
    net_site #(.OWN_E(3'd2), .OWN_B(3'd3), .NDIR(2),
               .DIR0(W), .DIR1(E), .G1(1'b1),
               .T_RISE(T_RISE), .T_FALL(T_FALL), .RING_ON(RING_ON), .RING_OFF(RING_OFF),
               .HIT(HIT), .ID(ID), .CLR(CLR), .T_GUARD(16), .T_CLAIM(250))
    B (.clk(clk_b), .rst_n(rst_n),
       .hook(hk_b), .tx(tx_b), .rx(rx_b), .e(ln_b),
       .line_in({c2b, a2b}), .line_out({b2c, b2a}), .locked(lkb),
       .frame_stb(fsb), .ring_cad_n(rcb), .dt_bit(dtb), .ng_bit(ngb),
       .mon_held(mhb), .got_claim(gcb), .dirs_held(dhb),
       .fan_legs(flb), .res_used(rub), .port_busy(pbb), .regs_busy(), .wq_ovf(), .n_defer(),
       .wr_stb(), .wr_dst(), .wr_src(), .wr_bsy(), .wr_clm());

    // C: 24.  Block 1 W toward B; block 3 E toward D.
    net_site #(.OWN_E(3'd2), .OWN_B(3'd4), .NDIR(2),
               .DIR0(W), .DIR1(E), .G1(1'b1),
               .T_RISE(T_RISE), .T_FALL(T_FALL), .RING_ON(RING_ON), .RING_OFF(RING_OFF),
               .HIT(HIT), .ID(ID), .CLR(CLR), .T_GUARD(16), .T_CLAIM(250))
    C (.clk(clk_c), .rst_n(rst_n),
       .hook(hk_c), .tx(tx_c), .rx(rx_c), .e(ln_c),
       .line_in({d2c, b2c}), .line_out({c2d, c2b}), .locked(lkc),
       .frame_stb(fsc), .ring_cad_n(rcc), .dt_bit(dtc), .ng_bit(ngc),
       .mon_held(mhc), .got_claim(gcc), .dirs_held(dhc),
       .fan_legs(flc), .res_used(ruc), .port_busy(pbc), .regs_busy(), .wq_ovf(), .n_defer(),
       .wr_stb(), .wr_dst(), .wr_src(), .wr_bsy(), .wr_clm());

    // D: 25.  Block 1 W toward C; block 3 E toward A -- the jumpered link.
    net_site #(.OWN_E(3'd2), .OWN_B(3'd5), .NDIR(2),
               .DIR0(W), .DIR1(E), .G1(1'b1), .N1(JUMPER),
               .T_RISE(T_RISE), .T_FALL(T_FALL), .RING_ON(RING_ON), .RING_OFF(RING_OFF),
               .HIT(HIT), .ID(ID), .CLR(CLR), .T_GUARD(16), .T_CLAIM(250))
    D (.clk(clk_d), .rst_n(rst_n),
       .hook(hk_d), .tx(tx_d), .rx(rx_d), .e(ln_d),
       .line_in({a2d, c2d}), .line_out({d2a, d2c}), .locked(lkd),
       .frame_stb(fsd), .ring_cad_n(rcd), .dt_bit(dtd), .ng_bit(ngd),
       .mon_held(mhd), .got_claim(gcd), .dirs_held(dhd),
       .fan_legs(fld), .res_used(rud), .port_busy(pbd), .regs_busy(), .wq_ovf(), .n_defer(),
       .wr_stb(), .wr_dst(), .wr_src(), .wr_bsy(), .wr_clm());

    reg path_en = 0;
    bitpath p_a20c21 (.src_clk(clk_a), .src_fs(fsa), .src_bit(tx_a[6'o20]),
                      .dst_clk(clk_c), .dst_fs(fsc), .dst_bit(rx_c[6'o21]), .enable(path_en));
    bitpath p_a20d21 (.src_clk(clk_a), .src_fs(fsa), .src_bit(tx_a[6'o20]),
                      .dst_clk(clk_d), .dst_fs(fsd), .dst_bit(rx_d[6'o21]), .enable(path_en));

    always @(posedge clk_a) if (fsa) begin
        if (hk_a[6'o20]) tx_a[6'o20] <= $random; if (hk_a[6'o21]) tx_a[6'o21] <= $random; end
    always @(posedge clk_c) if (fsc) begin
        if (hk_c[6'o20]) tx_c[6'o20] <= $random; if (hk_c[6'o21]) tx_c[6'o21] <= $random; end
    always @(posedge clk_d) if (fsd) begin
        if (hk_d[6'o20]) tx_d[6'o20] <= $random; if (hk_d[6'o21]) tx_d[6'o21] <= $random; end

    integer errs = 0, chk = 0, peak = 0;

    // the high-water mark of everything seized in the ring
    always @(posedge clk_a) if (ringchans > peak) peak <= ringchans;

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

    task snap(input string when);
        begin
            if (TRACE) $display("      [%-14s] ring=%0d | A d=%b r=%0d n=%0d | B r=%0d n=%0d | C r=%0d n=%0d | D r=%0d n=%0d",
                when, ringchans,
                dha, rua, $countones(pba & TR), rub, $countones(pbb & TR),
                ruc, $countones(pbc & TR), rud, $countones(pbd & TR));
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

    task ring21(input integer n, input string what, input integer which);
        integer i, hi, lo;
        reg ee, cad;
        begin
            hi = 0; lo = 0;
            for (i = 0; i < n; i = i + 1) begin
                #(FR);
                ee  = (which == 0) ? ln_c[6'o21] : ln_d[6'o21];
                cad = (which == 0) ? rcc  : rcd;
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

    initial begin
        if (JUMPER) $display("RING (RTL) -- 22 = 23 = 24 = 25 = 22, jumpered on 25 = 22.\n");
        else       $display("RING (RTL) -- the SAME ring with the jumper OUT.\n");
        #4000 rst_n = 1;
        wait (&lka && &lkb && &lkc && &lkd);
        $display("  0. Four exchanges, four links, all locked.\n");
        #(20_000_000);

        if (JUMPER) begin
        // ---- 1. two hops either way: the short way claims -----------------
        $display("  1. A's 20 dials 1 2 4 2 1 -- 24 is two hops either way round.");
        hk_a[6'o20] = 1; #(40_000_000);
        dial_a(1);
        #(80_000_000);
        snap("A flooded");
        wantn($countones(dha) == 2, $countones(dha),
              "A seized both ways: an origin may seize a jumpered link");
        want(mhb && mhc && mhd, "B, C and D all heard it");
        nch = ringchans;
        wantn(nch == 8, nch, "eight trunk ends: one a link, and ONE turn only");
        dial_a(2);
        dial_a(4);
        #(40_000_000);
        want(gca, "24 claimed, the short way");
        #(120_000_000);
        snap("claimed");
        nch = $countones(pbc & TR);
        wantn(nch == 1, nch, "24 cleared its own onward patch toward 25");
        dial_a(2); dial_a(1);
        #(80_000_000);
        nch = ringchans;
        wantn(nch == 4, nch, "four left: A = B = C, two ports a link");
        ring21(2 * (RING_ON + RING_OFF), "24's 21 rings, two hops from A", 0);
        hk_c[6'o21] = 1; #(20_000_000);
        want(ln_a[6'o20] && ln_c[6'o21], "answered at 24");
        path_en = 1; #(6_000_000); path_en = 0;
        p_a20c21.report("speech A20 -> C21, the short way round");
        chk = chk + 1; if (p_a20c21.best_err != 0) errs = errs + 1;
        hk_c[6'o21] = 0; hk_a[6'o20] = 0; #(200_000_000);
        nch = ringchans;
        wantn(nch == 0, nch, "everything released");

        // ---- 2. the far end of the jumpered link, reached twice -----------
        $display("\n  2. A's 20 dials 1 2 5 2 1 -- 25, the far end of the JUMPER.");
        hk_a[6'o20] = 1; #(40_000_000);
        dial_a(1);
        #(80_000_000);
        snap("A flooded");
        nch = $countones(pbd & TR);
        wantn(nch == 2, nch, "25 got the call TWICE: on the jumper, and the long way");
        dial_a(2);
        dial_a(5);
        #(40_000_000);
        want(gca, "25 claimed");
        dial_a(2); dial_a(1);
        #(240_000_000);
        snap("set up");
        nch = $countones(pba & TR);
        wantn(nch == 1, nch, "A kept ONE claim and let the other go");
        // 3.3: the direct copy wins, "a hop away against many".  Both claims
        // land in one scanner visit; under the settled map A's jumpered link
        // is block 3 and the long way is block 1.  Block 3 is the higher
        // ports, but the claim on the jumper is the one that stayed -- the
        // short way is one link, as 3.3 wants.
        nch = ringchans;
        wantn(nch == 2, nch,
              "and it is the SHORT way: the jumper's 1 link -- see 3.3");
        nch = $countones(pba[31:24] & 8'hFF);
        wantn(nch == 1, nch, "A's held trunk is the jumpered one toward 25");
        ring21(2 * (RING_ON + RING_OFF), "25's 21 rings, from the far end of the jumper", 1);
        hk_d[6'o21] = 1; #(20_000_000);
        want(ln_a[6'o20] && ln_d[6'o21], "answered, and no caller heard the second claim");
        p_a20d21.clear;
        path_en = 1; #(6_000_000); path_en = 0;
        p_a20d21.report("speech A20 -> D21, over the jumper");
        chk = chk + 1; if (p_a20d21.best_err != 0) errs = errs + 1;
        hk_d[6'o21] = 0; hk_a[6'o20] = 0; #(200_000_000);
        nch = ringchans;
        wantn(nch == 0, nch, "everything released");

        end else begin
        // ---- 3. the jumper out: the flood goes round and round -------------
        $display("  1. A's 20 dials 1 2 4 ... with nothing to break the loop.");
        hk_a[6'o20] = 1; #(40_000_000);
        dial_a(1);
        #(80_000_000);
        snap("one turn");
        dial_a(2);
        snap("e");
        dial_a(4);
        #(200_000_000);
        snap("b, and round");
        #(400_000_000);
        snap("settled");
        nch = ringchans;
        $display("     ONE call: high-water mark %0d of the ring's 48 trunk channels,", peak);
        $display("     and %0d still held once it is up -- the jumpered ring held 4.", nch);
        wantn(peak >= 40, peak, "the flood went round until the links were full");
        wantn(nch >= 8, nch, "and it settles at a channel on EVERY link, both ways");
        hk_a[6'o20] = 0; #(600_000_000);
        nch = ringchans;
        wantn(nch == 0, nch, "and all of it releases when the caller hangs up");
        end

        $display("\n  %0d checks, %0d errors.  %s", chk, errs, (errs == 0) ? "PASS" : "FAIL");
        if (errs) $fatal(1);
        $finish;
    end

    initial begin #12_000_000_000; $display("  TIMEOUT"); $finish; end
endmodule
