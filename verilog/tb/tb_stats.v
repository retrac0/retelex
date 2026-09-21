// tb_stats -- the counter card against the marker's real write patterns.
//
// The card is a passive listener on cable B, so it can be tested the way the
// blocks are: drive ctl_write with the exact sequence of words the marker
// pushes for a call, and see what each strap field counts.  The sequences
// below are marker.v's own push() calls, in order, for five calls:
//
//   A  a local call that connects          1 dial tone, 1 off, a connect PAIR
//   B  a local call that does not          1 dial tone, 1 off, 1 cannot-complete
//   C  an outbound network call            dial tone, off, 2 seizures, 1 let go,
//                                          and ONE write when the claim returns
//   D  an inbound call claimed here        CLAIM, off, a connect PAIR
//   E  an inbound call with no register    1 cannot-complete, CLM set
//
// Then counters.md 9's EVENT WORD: a word with G = 0, which writes to no
// block at all, carrying an event code in SRC with BSY = 0 and CLM = 1.  The
// card cannot see G -- bits 15-8 fall out of the end unread -- so it counts one
// exactly as it counts a write, and the question this bench answers is whether
// a strap can be sure which it counted.  It can: no latch write the marker
// makes carries CLM without BSY.
//
// The interesting negative result is C against D: the write that completes an
// OUTBOUND call (marker.v 562) and the second write of an INBOUND one
// (marker.v 555) are the same sixteen bits -- DST a line, SRC a trunk, BSY 1,
// CLM 0.  No pattern over one word tells them apart, so the trunk strap counts
// calls completed over a trunk in BOTH directions.  counters.md 3.
`timescale 1ns/1ps

module tb_stats;
    // the exchange's own crystal, 4.096 MHz
    reg clk = 0, rst_n = 0;
    always #122.0703 clk = ~clk;

    localparam [5:0] DIALTONE = 6'o01, NOGO = 6'o03;
    localparam [2:0] TRUNK_BLK = 3'd5;

    // ---- the marker's serialiser, driven by hand ------------------------
    reg        w_req = 0, w_bsy = 0, w_clm = 0, w_g = 1;
    reg  [5:0] w_dst = 0, w_src = 0;
    wire       ser_busy, sdata, sclk, wr;
    integer    nwrite = 0, nevent = 0;

    ctl_write u_ser (.clk(clk), .rst_n(rst_n), .req(w_req), .strobe(1'b1),
                     .g(w_g),
                     .dst(w_dst), .src(w_src), .bsy(w_bsy), .clm(w_clm),
                     .busy(ser_busy), .sdata(sdata), .sclk(sclk), .wr(wr));

    reg clr = 0;

    // ---- six cards on the ribbon, one strap field each -------------------
    wire [15:0] c_cc, c_dt, c_let, c_trk, c_clm, c_all;

    // cannot-complete given: SRC = NOGO, BSY, CLM either way
    stats #(.SRC(NOGO), .BSY(1'b1), .CLM(1'b0),
            .SRC_ANY(6'o00), .BSY_ANY(1'b0), .CLM_ANY(1'b1)) u_cc (
        .clk(clk), .rst_n(rst_n), .sdata(sdata), .sclk(sclk), .wr(wr),
        .clr(clr), .count(c_cc), .match());

    // dial tone given: one a call that originates here
    stats #(.SRC(DIALTONE), .BSY(1'b1), .CLM(1'b0),
            .SRC_ANY(6'o00), .BSY_ANY(1'b0), .CLM_ANY(1'b0)) u_dt (
        .clk(clk), .rst_n(rst_n), .sdata(sdata), .sclk(sclk), .wr(wr),
        .clr(clr), .count(c_dt), .match());

    // trunks let go: the flood's teardown
    stats #(.SRC(6'o00), .BSY(1'b0), .CLM(1'b0),
            .SRC_ANY(6'o00), .BSY_ANY(1'b0), .CLM_ANY(1'b0)) u_let (
        .clk(clk), .rst_n(rst_n), .sdata(sdata), .sclk(sclk), .wr(wr),
        .clr(clr), .count(c_let), .match());

    // calls completed over a trunk: SRC on the trunk block, its slot any
    stats #(.SRC({TRUNK_BLK, 3'd0}), .BSY(1'b1), .CLM(1'b0),
            .SRC_ANY(6'o07), .BSY_ANY(1'b0), .CLM_ANY(1'b0)) u_trk (
        .clk(clk), .rst_n(rst_n), .sdata(sdata), .sclk(sclk), .wr(wr),
        .clr(clr), .count(c_trk), .match());

    // claims: TWO a call, the claim and the dial-tone-off that follows it
    stats #(.SRC(6'o00), .BSY(1'b1), .CLM(1'b1),
            .SRC_ANY(6'o00), .BSY_ANY(1'b0), .CLM_ANY(1'b0)) u_clm (
        .clk(clk), .rst_n(rst_n), .sdata(sdata), .sclk(sclk), .wr(wr),
        .clr(clr), .count(c_clm), .match());

    // every write: the marker's occupancy.  All eight straps on Pi.
    stats #(.SRC_ANY(6'o77), .BSY_ANY(1'b1), .CLM_ANY(1'b1)) u_all (
        .clk(clk), .rst_n(rst_n), .sdata(sdata), .sclk(sclk), .wr(wr),
        .clr(clr), .count(c_all), .match());

    // ---- and four more, strapped for counters.md 9's event words ------
    wire [15:0] c_ev, c_wait, c_ntrk, c_glare;

    // ANY event: BSY = 0 with CLM = 1, the code left don't-care
    stats #(.SRC(6'o00), .BSY(1'b0), .CLM(1'b1),
            .SRC_ANY(6'o77), .BSY_ANY(1'b0), .CLM_ANY(1'b0)) u_ev (
        .clk(clk), .rst_n(rst_n), .sdata(sdata), .sclk(sclk), .wr(wr),
        .clr(clr), .count(c_ev), .match());

    // a caller waited for a register
    stats #(.SRC(6'o01), .BSY(1'b0), .CLM(1'b1),
            .SRC_ANY(6'o00), .BSY_ANY(1'b0), .CLM_ANY(1'b0)) u_wait (
        .clk(clk), .rst_n(rst_n), .sdata(sdata), .sclk(sclk), .wr(wr),
        .clr(clr), .count(c_wait), .match());

    // all trunks busy -- ALL FOUR directions on one card, the two low bits on Pi
    stats #(.SRC(6'o10), .BSY(1'b0), .CLM(1'b1),
            .SRC_ANY(6'o03), .BSY_ANY(1'b0), .CLM_ANY(1'b0)) u_ntrk (
        .clk(clk), .rst_n(rst_n), .sdata(sdata), .sclk(sclk), .wr(wr),
        .clr(clr), .count(c_ntrk), .match());

    // glare
    stats #(.SRC(6'o04), .BSY(1'b0), .CLM(1'b1),
            .SRC_ANY(6'o00), .BSY_ANY(1'b0), .CLM_ANY(1'b0)) u_glare (
        .clk(clk), .rst_n(rst_n), .sdata(sdata), .sclk(sclk), .wr(wr),
        .clr(clr), .count(c_glare), .match());

    // ---- checking --------------------------------------------------------
    integer errs = 0, chk = 0;

    task want(input [15:0] got, input [15:0] exp, input string what);
        begin
            chk = chk + 1;
            if (got !== exp) begin
                errs = errs + 1;
                $display("     %-48s FAIL  got %0d want %0d", what, got, exp);
            end else $display("     %-48s ok  %0d", what, got);
        end
    endtask

    // one word on cable B, exactly as the marker pushes it
    task mword(input g, input [5:0] dst, input [5:0] src, input b, input c);
        begin
            @(posedge clk);
            w_g <= g; w_dst <= dst; w_src <= src; w_bsy <= b; w_clm <= c;
            w_req <= 1'b1;
            @(posedge clk); w_req <= 1'b0;
            @(posedge clk);
            while (ser_busy) @(posedge clk);
            repeat (16) @(posedge clk);
        end
    endtask

    task mwrite(input [5:0] dst, input [5:0] src, input b, input c);
        begin mword(1'b1, dst, src, b, c); nwrite = nwrite + 1; end
    endtask

    // an EVENT word: G = 0, so no block writes; the code in SRC, BSY 0, CLM 1
    task mevent(input [5:0] port, input [5:0] code);
        begin mword(1'b0, port, code, 1'b0, 1'b1); nevent = nevent + 1; end
    endtask

    integer i;
    initial begin
        repeat (8) @(posedge clk);
        rst_n = 1;
        repeat (8) @(posedge clk);

        $display("");
        $display("  tb_stats -- the counter card, counters.md");
        $display("");

        // ---- A: a local call that connects ---------------------------
        mwrite(6'o20, DIALTONE, 1'b1, 1'b0);   // a caller wanting service
        mwrite(6'o20, 6'o00,    1'b1, 1'b0);   // dial tone off, first digit in
        mwrite(6'o20, 6'o21,    1'b1, 1'b0);   // the connect pair
        mwrite(6'o21, 6'o20,    1'b1, 1'b0);

        // ---- B: a local call that does not ---------------------------
        mwrite(6'o22, DIALTONE, 1'b1, 1'b0);
        mwrite(6'o22, 6'o00,    1'b1, 1'b0);
        mwrite(6'o22, NOGO,     1'b1, 1'b0);   // cannot-complete

        // ---- C: an outbound network call -----------------------------
        mwrite(6'o23, DIALTONE, 1'b1, 1'b0);
        mwrite(6'o23, 6'o00,    1'b1, 1'b0);   // the `1` key consumed
        mwrite(6'o50, 6'o23,    1'b1, 1'b0);   // seize a trunk, direction 0
        mwrite(6'o51, 6'o23,    1'b1, 1'b0);   // and direction 1
        mwrite(6'o50, 6'o00,    1'b0, 1'b0);   // 51 claimed: let 50 go
        mwrite(6'o23, 6'o51,    1'b1, 1'b0);   // point the caller at the trunk

        // ---- D: an inbound call claimed here --------------------------
        mwrite(6'o52, 6'o00,    1'b1, 1'b1);   // CLAIM: backward A rises
        mwrite(6'o52, 6'o00,    1'b1, 1'b1);   // dial tone off -- the SAME word
        mwrite(6'o52, 6'o24,    1'b1, 1'b1);   // the connect pair
        mwrite(6'o24, 6'o52,    1'b1, 1'b0);

        // ---- E: an inbound call with no register free -----------------
        mwrite(6'o53, NOGO,     1'b1, 1'b1);   // claimed, cannot complete

        $display("  after five calls and %0d writes:", nwrite);
        want(c_dt,  16'd3,  "dial tone given -- calls originating here");
        want(c_cc,  16'd2,  "cannot-complete given (B and E)");
        want(c_let, 16'd1,  "trunks let go");
        want(c_trk, 16'd2,  "calls completed over a trunk (C and D)");
        want(c_clm, 16'd2,  "claims -- TWO a call, read from bit 1");
        want(c_all, nwrite[15:0], "every write -- the marker's occupancy");
        $display("");
        $display("     C's completion and D's are the same sixteen bits:");
        $display("       outbound  DST=o23 SRC=o51 BSY=1 CLM=0");
        $display("       inbound   DST=o24 SRC=o52 BSY=1 CLM=0");
        $display("     -- one strap cannot separate them.  counters.md 3.");
        $display("");

        // ---- the event words, counters.md 9 -----------------------
        // What no write says, because nothing is written when it happens.
        mevent(6'o25, 6'o01);                  // 25 lifted and found no register
        mevent(6'o26, 6'o01);                  // and so did 26
        mevent(6'o00, 6'o10);                  // all trunks busy, direction 0
        mevent(6'o00, 6'o13);                  // ... and direction 3
        mevent(6'o27, 6'o02);                  // 27 dialled nothing for 10 s
        mevent(6'o51, 6'o04);                  // glare on trunk 51
        mevent(6'o00, 6'o03);                  // the write queue overran

        $display("");
        $display("  and %0d event words -- G = 0, so no block wrote anything:", nevent);
        want(c_ev,    16'd7, "every event (BSY 0, CLM 1, any code)");
        want(c_wait,  16'd2, "a caller waited for a register");
        want(c_ntrk,  16'd2, "all trunks busy -- four directions, one card");
        want(c_glare, 16'd1, "glare");

        $display("");
        $display("     and NOT ONE of them reached a strap meant for a call:");
        want(c_dt,  16'd3,  "dial tone given -- unchanged");
        want(c_cc,  16'd2,  "cannot-complete given -- unchanged");
        want(c_let, 16'd1,  "trunks let go -- unchanged");
        want(c_trk, 16'd2,  "calls completed over a trunk -- unchanged");
        want(c_clm, 16'd2,  "claims -- unchanged");
        $display("");
        $display("     The occupancy strap is the one exception, and it is");
        $display("     honest: it asks for every word and gets every word.");
        want(c_all, (nwrite + nevent), "every word on the bus");
        $display("");

        // ---- the reset key ------------------------------------------
        @(posedge clk); clr = 1; repeat (4) @(posedge clk); clr = 0;
        repeat (4) @(posedge clk);
        want(c_all, 16'd0, "the reset key clears it, with the bus quiet");

        // ---- and it is sixteen bits, not eight -----------------------
        for (i = 0; i < 300; i = i + 1) mwrite(6'o30, DIALTONE, 1'b1, 1'b0);
        want(c_dt, 16'd300, "300 counts: the chain is wider than a '161");

        $display("");
        if (errs == 0) $display("  tb_stats: %0d checks, all ok", chk);
        else           $display("  tb_stats: %0d checks, %0d FAILED", chk, errs);
        $display("");
        if (errs) $fatal(1);
        $finish;
    end
endmodule
