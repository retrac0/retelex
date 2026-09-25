// tb_nano -- nano-marker.md: two-digit local calls on a three-bit register,
// and digit 1 as a hunt over one strapped block of uplink trunks.
//
// The trunk block is gappy on purpose: MF2 at 10 (10, 11) and MF2 at 14
// (14, 15), with 12, 13, 16, 17 open.  An open slot reads free on M and BUSY,
// so the hunt has to tell it apart by the card word being all zeros.
//
// The checks that matter for the three-bit count are the "operator on 0" and
// "8 and 9 fold onto 0" groups: the register cannot tell 0, 8 and 9 apart, so
// all three have to reach the operator, and a second key of 8 or 9 has to
// reach the same port a second key of 0 does.
//
// OP_EN = 0 runs the same plant with the operator hunt strapped off, where 0,
// 8 and 9 are all cannot-complete again (`make nano-noop`).
`timescale 1ns/1ps

module tb_nano #(
    parameter OP_EN = 1'b1
);
    localparam integer HIT = 1, ID = 16, CLR = 32, NODIG = 500;
    localparam integer T_RISE = 64, T_FALL = 2048;
    localparam integer RING_ON = 200, RING_OFF = 400;
    localparam integer BRK_NS = 12_000_000, MK_NS = 8_000_000;
    localparam integer PAUSE  = 60_000_000;
    localparam [5:0] DIALTONE = 6'o01, NOGO = 6'o03;
    localparam [5:0] P04 = 6'o04, P05 = 6'o05, P06 = 6'o06, P07 = 6'o07;
    localparam [5:0] P10 = 6'o10, P11 = 6'o11, P14 = 6'o14, P15 = 6'o15;
    localparam [5:0] P12 = 6'o12, P13 = 6'o13, P16 = 6'o16, P17 = 6'o17;
    localparam [5:0] P20 = 6'o20, P21 = 6'o21, P22 = 6'o22, P25 = 6'o25;

    reg clk = 0, rst_n = 0;
    always #122.0703 clk = ~clk;

    reg  [63:0] hook = 0, tx = 0;
    wire [63:0] rx, e, port_busy;
    wire        reg_busy;
    wire        wr_stb, wr_bsy, wr_clm;
    wire [5:0]  wr_dst, wr_src;
    wire        frame_stb, fill, ring_cad_n, dt_bit, ng_bit;

    nano_site #(.T_RISE(T_RISE), .T_FALL(T_FALL),
                .RING_ON(RING_ON), .RING_OFF(RING_OFF),
                .HIT(HIT), .ID(ID), .CLR(CLR), .NODIG(NODIG),
                .LEAF(1'b1), .UP_BLK(3'd1), .OP_EN(OP_EN), .OP_BLK(3'd0))
    S (.clk(clk), .rst_n(rst_n),
       .hook(hook), .tx(tx), .rx(rx), .e(e),
       .frame_stb(frame_stb), .tick_1k(), .fill(fill), .ring_cad_n(ring_cad_n),
       .dt_bit(dt_bit), .ng_bit(ng_bit),
       .port_busy(port_busy), .reg_busy(reg_busy),
       .wr_stb(wr_stb), .wr_dst(wr_dst), .wr_src(wr_src),
       .wr_bsy(wr_bsy), .wr_clm(wr_clm));

    reg [5:0] last_dt = 6'h3f, last_ng = 6'h3f, last_off = 6'h3f;
    always @(posedge clk) begin
        if (wr_stb && wr_bsy && wr_src == DIALTONE) last_dt <= wr_dst;
        if (wr_stb && wr_bsy && wr_src == NOGO)     last_ng <= wr_dst;
        if (wr_stb && wr_bsy && wr_src == 6'o00)    last_off <= wr_dst;
    end

    integer errs = 0, chk = 0;
    task want(input v, input string what);
        begin
            chk = chk + 1;
            if (!v) begin errs = errs + 1; $display("     %-56s FAIL", what); end
            else $display("     %-56s ok", what);
            $fflush();
        end
    endtask

    task dial(input [5:0] p, input integer d);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                hook[p] = 1'b0; #BRK_NS;
                hook[p] = 1'b1; #MK_NS;
            end
            #PAUSE;
        end
    endtask

    task await_dt(input [5:0] who);
        integer t;
        begin
            last_dt = 6'h3f; t = 0;
            while (last_dt !== who && t < 200) begin #1_000_000; t = t + 1; end
        end
    endtask

    task await_ng(input [5:0] who);
        integer t;
        begin
            t = 0;
            while (last_ng !== who && t < 800) begin #1_000_000; t = t + 1; end
        end
    endtask

    task hang_all;
        begin
            hook = 0; tx = 0; #400_000_000;
        end
    endtask

    integer t;
    reg seen_ring, all_home, all_real;

    initial begin
        $display("NANO (RTL) -- nano-marker.md: one board, three-bit register.");
        $display("             operator hunt on 0: %s\n", OP_EN ? "on" : "strapped off");
        #4000 rst_n = 1;
        #50_000_000;

        // ---- 20 dials 21: ring, answer, speech, hang up both ----
        $display("  20 calls 21");
        hook[P20] = 1'b1;
        await_dt(P20);
        want(last_dt === P20 && reg_busy, "20 got dial tone");
        dial(P20, 2); dial(P20, 1);
        #100_000_000;
        want(port_busy[P20] && port_busy[P21] && !reg_busy,
             "20 dials 21: both busy, register free");

        seen_ring = 0;
        for (t = 0; t < 80 && !seen_ring; t = t + 1) begin
            if (e[P21] === 1'b1) seen_ring = 1;
            #1_000_000;
        end
        want(seen_ring, "21 rings");
        hook[P21] = 1'b1;
        #20_000_000;
        tx[P20] = 1'b1; tx[P21] = 1'b0;
        #5_000_000;
        want(rx[P21] === 1'b1 && rx[P20] === 1'b0, "answered: speech 20 -> 21");
        tx[P20] = 1'b0; tx[P21] = 1'b1;
        #5_000_000;
        want(rx[P20] === 1'b1 && rx[P21] === 1'b0, "answered: speech 21 -> 20");
        hang_all;
        want(port_busy == 64'd0 && !reg_busy, "both hang up: nothing held");

        // ---- 21 dials 20, caller hangs up first ----
        $display("  21 calls 20, caller first");
        hook[P21] = 1'b1;
        await_dt(P21);
        want(last_dt === P21, "21 got dial tone");
        dial(P21, 2); dial(P21, 0);          // ten pulses: the second key is 0
        #100_000_000;
        want(port_busy[P20] && port_busy[P21], "21 dials 2 0 connects to 20");
        hook[P20] = 1'b1;
        #20_000_000;
        last_dt = 6'h3f;
        hook[P21] = 1'b0;                    // caller hangs up first
        #400_000_000;
        want(!port_busy[P21], "caller released");
        t = 0;
        while (last_dt !== P20 && t < 200) begin #1_000_000; t = t + 1; end
        want(last_dt === P20 && reg_busy, "20 left off-hook gets dial tone");
        hang_all;
        want(port_busy == 64'd0 && !reg_busy, "then 20 hangs up: idle");

        // ---- the three-bit fold: 8 and 9 as a second key are 0 ----
        // The count freezes at 0 on the eighth break, so 2 8 and 2 9 reach
        // port 20 exactly as 2 0 does.  oct() folded them the same way.
        $display("  second key 8 and 9 fold onto 0");
        hook[P21] = 1'b1;
        await_dt(P21);
        dial(P21, 2); dial(P21, 8);
        #100_000_000;
        want(port_busy[P20] && port_busy[P21], "21 dials 2 8 -> port 20");
        hang_all;

        hook[P21] = 1'b1;
        await_dt(P21);
        dial(P21, 2); dial(P21, 9);
        #100_000_000;
        want(port_busy[P20] && port_busy[P21], "21 dials 2 9 -> port 20");
        hang_all;

        // ---- busy ----
        $display("  busy");
        hook[P20] = 1'b1;
        await_dt(P20);
        dial(P20, 2); dial(P20, 1);
        #100_000_000;
        want(port_busy[P21], "setup: 21 busy");
        hook[P22] = 1'b1;
        await_dt(P22);
        last_ng = 6'h3f;
        dial(P22, 2); dial(P22, 1);
        await_ng(P22);
        want(last_ng === P22, "22 dials busy 21 -> cannot-complete");
        hang_all;

        // ---- self ----
        $display("  self");
        hook[P20] = 1'b1;
        await_dt(P20);
        last_ng = 6'h3f;
        dial(P20, 2); dial(P20, 0);
        await_ng(P20);
        want(last_ng === P20, "20 dials itself -> cannot-complete");
        hang_all;

        // ---- empty number ----
        // No port circuit at 25.  It reads free on M and BUSY, so only the
        // absent card word makes this cannot-complete rather than a patch
        // into nothing.
        $display("  empty");
        hook[P20] = 1'b1;
        await_dt(P20);
        last_ng = 6'h3f;
        dial(P20, 2); dial(P20, 5);
        await_ng(P20);
        want(last_ng === P20, "20 dials unequipped 25 -> cannot-complete");
        want(!port_busy[P25], "the empty latch was never written");
        want(port_busy[P20] && !reg_busy,
             "caller left busy at 03, register free");
        hang_all;

        // ---- first key 0: the operator, or cannot-complete ----
        if (OP_EN) begin
            $display("  operator on 0");
            hook[P20] = 1'b1;
            await_dt(P20);
            dial(P20, 0);
            #200_000_000;
            want(port_busy[P20] && port_busy[P04] && !reg_busy,
                 "0 hunted the operator: 20 patched to 04");
            hang_all;

            // 8 and 9 count as 0, so they reach the operator too.  Not
            // optional -- the register cannot tell the three keys apart.
            hook[P20] = 1'b1;
            await_dt(P20);
            dial(P20, 8);
            #200_000_000;
            want(port_busy[P20] && port_busy[P04], "8 reaches the operator");
            hang_all;

            hook[P20] = 1'b1;
            await_dt(P20);
            dial(P20, 9);
            #200_000_000;
            want(port_busy[P20] && port_busy[P04], "9 reaches the operator");
            hang_all;

            // Fixed order from 04: the hunt holds off until 04 comes round,
            // so 04 answers from any scanner phase -- not whichever operator
            // the scanner happened to be nearest.
            $display("  operator hunt is fixed order from 04");
            all_home = 1'b1;
            for (t = 0; t < 4; t = t + 1) begin
                #(3_000_000 * t);
                hook[P20] = 1'b1;
                await_dt(P20);
                dial(P20, 0);
                #200_000_000;
                if (!port_busy[P04]) all_home = 1'b0;
                hang_all;
            end
            want(all_home, "0 lands on 04 from any scanner phase");

            // 04 held, so the walk carries on to 05
            hook[P20] = 1'b1;
            await_dt(P20);
            dial(P20, 0);
            #200_000_000;
            want(port_busy[P04], "setup: 04 taken");
            hook[P21] = 1'b1;
            await_dt(P21);
            dial(P21, 0);
            #200_000_000;
            want(port_busy[P21] && port_busy[P05],
                 "04 held, so the next 0 takes 05");
            hang_all;

            // every operator busy
            // 06 and 07 are open slots: the hunt must not mistake them for
            // free operators once 04 and 05 are taken.
            hook[P20] = 1'b1;
            await_dt(P20);
            hook[P04] = 1'b1; hook[P05] = 1'b1;
            last_ng = 6'h3f;
            dial(P20, 0);
            await_ng(P20);
            want(last_ng === P20,
                 "04 and 05 busy, 06/07 open -> cannot-complete");
            want(!port_busy[P06] && !port_busy[P07],
                 "no open operator slot was patched");
            hang_all;
        end else begin
            $display("  first keys, operator strapped off");
            hook[P20] = 1'b1;
            await_dt(P20);
            last_ng = 6'h3f;
            dial(P20, 0);
            await_ng(P20);
            want(last_ng === P20, "0 -> cannot-complete");
            hang_all;

            hook[P20] = 1'b1;
            await_dt(P20);
            last_ng = 6'h3f;
            dial(P20, 8);
            await_ng(P20);
            want(last_ng === P20, "8 -> cannot-complete");
            hang_all;

            hook[P20] = 1'b1;
            await_dt(P20);
            last_ng = 6'h3f;
            dial(P20, 9);
            await_ng(P20);
            want(last_ng === P20, "9 -> cannot-complete");
            hang_all;
        end

        // ---- digit 1 hunts the strapped uplink block ----
        $display("  uplink hunt");
        hook[P20] = 1'b1;
        await_dt(P20);
        last_off = 6'h3f;
        dial(P20, 1);
        #200_000_000;
        want(last_off === P20, "1 dropped dial tone");
        want(port_busy[P20] && port_busy[P10] && !reg_busy,
             "1 hunted the first free trunk: 20 patched to 10");
        // hold that pair up and hunt again: the next caller takes 11
        hook[P21] = 1'b1;
        await_dt(P21);
        dial(P21, 1);
        #200_000_000;
        want(port_busy[P21] && port_busy[P11] && !reg_busy,
             "10 held, so the next 1 takes 11");
        hang_all;

        // ---- the gap between the two MF2 cards ----
        // Both channels of the MF2 at 10 taken.  12 and 13 are open slots and
        // read free on M and BUSY, so only the card word keeps the hunt off
        // them.  Run it at several scanner phases: the hunt starts wherever
        // the scanner is, so a phase-dependent bug shows up here and nowhere
        // else.
        $display("  MF2 at 10 and MF2 at 14, 12 and 13 open");
        all_real = 1'b1;
        for (t = 0; t < 4; t = t + 1) begin
            #(3_000_000 * t);
            hook[P20] = 1'b1;
            await_dt(P20);
            hook[P10] = 1'b1; hook[P11] = 1'b1;
            #20_000_000;
            dial(P20, 1);
            #300_000_000;
            if (!(port_busy[P14] || port_busy[P15])) all_real = 1'b0;
            if (port_busy[P12] || port_busy[P13])    all_real = 1'b0;
            hang_all;
        end
        want(all_real,
             "10 and 11 held: hunt skips the open 12, 13 and takes the MF2 at 14");

        // ---- every uplink busy ----
        // Hold all four real channels.  The four open slots in the block must
        // not answer, so this is cannot-complete and not silence.
        $display("  uplink exhausted");
        hook[P20] = 1'b1;
        await_dt(P20);
        hook[P10] = 1'b1; hook[P11] = 1'b1; hook[P14] = 1'b1; hook[P15] = 1'b1;
        last_ng = 6'h3f;
        dial(P20, 1);
        await_ng(P20);
        want(last_ng === P20, "no free trunk -> cannot-complete");
        want(!port_busy[P12] && !port_busy[P13] &&
             !port_busy[P16] && !port_busy[P17],
             "no open trunk slot was patched");
        // The register is let go, and the eight off-hook trunks are now
        // ordinary call requests -- an incoming seizure on a leaf is a port
        // raising M like any other.  The next dial tone goes to one of them,
        // which is what proves the register was released.
        t = 0;
        while (last_dt[5:3] !== 3'd1 && t < 200) begin #1_000_000; t = t + 1; end
        want(last_dt[5:3] === 3'd1,
             "register released: an off-hook trunk is served next");
        hang_all;

        // ---- abandon mid-dial ----
        $display("  abandon");
        hook[P20] = 1'b1;
        await_dt(P20);
        dial(P20, 2);
        hook[P20] = 1'b0;
        #400_000_000;
        want(!reg_busy && !port_busy[P20], "hang up mid-dial: register and port free");

        // ---- no-digit timeout ----
        $display("  nodig");
        hook[P20] = 1'b1;
        await_dt(P20);
        last_ng = 6'h3f;
        await_ng(P20);
        want(last_ng === P20 && !reg_busy, "nothing dialled -> cannot-complete, register free");
        want(port_busy[P20], "port stays busy until hung up");
        hang_all;
        want(port_busy == 64'd0 && !reg_busy, "final idle");

        $display("");
        if (errs) begin
            $display("NANO: %0d of %0d failed", errs, chk);
            $fatal(1);
        end
        $display("NANO: %0d checks ok", chk);
        $finish;
    end
endmodule
