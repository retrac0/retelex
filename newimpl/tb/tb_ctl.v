// tb_ctl -- the exchange control bus.  mainboard.md 2.3, fabric.md 7 step 3.
//
// One sixteen-bit word on one wire, broadcast to every block; the block whose
// shunt column matches DST[5:3] answers WR.  The guard bit is what makes a
// word a write, and a word without it is an event word that still pulses WR
// and still writes nothing.  CLAIM, bit 0, reaches the card as A_RX: a claimed
// trunk's backward A.  And the serialiser's rate is MEASURED, because the old
// tree's ran four times too fast with every bench green.
`timescale 1ns/1ps
`include "exch.vh"

module tb_ctl;
    integer chk = 0, errs = 0, shown = 0;
    task ck(input cond, input [8*60-1:0] what);
        begin chk = chk + 1;
             if (!cond) begin errs = errs + 1; $display("    FAIL  %0s", what); end
        end
    endtask
    task oops(input [8*60-1:0] what);
        begin errs = errs + 1;
             if (shown < 8) begin shown = shown + 1;
                 $display("    FAIL  %0s  at %0t", what, $time); end
        end
    endtask

    reg clk = 1'b0, rst_n = 1'b0;
    always #122.070 clk = ~clk;

    reg  [63:0] c_tx = 64'd0;
    wire [63:0] c_rx, a_rx, port_busy;
    // 20 ties /ANS low, as a trunk card does, so its A_RX is E + CLAIM and
    // not chopped by the ring cadence.  Nothing above depends on it.
    wire [63:0] ans = ~(64'd1 << 6'o20);
    wire ha_n, hb_n, hw_n, frame_stb, fill, cap_stb, pass_stb;
    wire [2:0] slot, slotq;
    wire [`SCANW-1:0] scan;
    wire s_sdata, s_sclk, s_wr, s_busy;

    reg req = 1'b0, strobe = 1'b1, g = 1'b1;
    reg [`PW-1:0] dst = 6'd0, src = 6'd0;
    reg bsy = 1'b0, clm = 1'b0;

    ctl_write u_ser (
        .clk(clk), .rst_n(rst_n), .req(req), .strobe(strobe), .g(g),
        .dst(dst), .src(src), .bsy(bsy), .clm(clm),
        .busy(s_busy), .sdata(s_sdata), .sclk(s_sclk), .wr(s_wr));

    // Block 2 alone, ports 20 and 21 -- mvp.md 1's exchange exactly.
    exch #(.PORT_FITTED(64'h0000_0000_0003_0000), .BLOCK_FITTED(8'b0000_0100)) u_x (
        .clk(clk), .rst_n(rst_n),
        .c_tx(c_tx), .a_tx(64'd0), .ans_n(ans), .word_n({64{1'b1}}),
        .c_rx(c_rx), .a_rx(a_rx),
        .mute_blk(8'd0), .rbt_in(1'b0),
        .sdata(s_sdata), .sclk(s_sclk), .wr(s_wr), .hw_n(hw_n),
        .hc(), .ha_n(ha_n), .hb_n(hb_n), .tick(), .slot(slot), .slotq(slotq),
        .hclk(), .line_hb(), .cap_stb(cap_stb), .tx_clk(),
        .frame_stb(frame_stb), .clk_8k(), .rx_oct(), .oct_stb(),
        .scan(scan), .pass_stb(pass_stb),
        .fill(fill), .ring_cad_n(), .tick_1k(),
        .port_busy(port_busy));

    // ---- mainboard.md 2.3.2's one rule -------------------------------------
    // WR must not land within a set-up window of an SCLK edge.  Here SCLK is
    // idle through the strobe bit-time, so the check is simply that it never
    // moves while WR is asserted, nor within eight master ticks either side.
    reg sclk_d = 1'b0; integer since_edge = 999;
    always @(posedge clk) begin
        sclk_d <= s_sclk;
        if (s_sclk !== sclk_d) since_edge = 0;
        else if (since_edge < 999) since_edge = since_edge + 1;
        if (s_wr && (since_edge < 8)) oops("WR landed on top of an SCLK edge");
    end

    task send(input [`PW-1:0] d, input [`PW-1:0] s, input b, input c,
              input gd, input st);
        begin
            @(posedge clk);
            dst = d; src = s; bsy = b; clm = c; g = gd; strobe = st;
            req = 1'b1; @(posedge clk); req = 1'b0; @(posedge clk);
            while (s_busy) @(posedge clk);
        end
    endtask

    // count WR pulses, so "an event word still pulses WR" is a measurement
    integer nwr = 0; reg count_wr = 1'b0; reg wr_d = 1'b0;
    always @(posedge clk) begin
        if (count_wr && s_wr && !wr_d) nwr = nwr + 1;
        wr_d <= s_wr;
    end

    // ---- the serialiser's rate: every SCLK period, every word's length ------
    // mainboard.md 2.3: 128 kHz, 32 master ticks a bit, sixteen bits and a
    // strobe bit-time -- 544 ticks, 133 us, a written word.
    integer since_rise = -1, bad_period = 0, n_rise = 0, busy_len = 0;
    integer last_len = 0, bad_rises = 0, words = 0;
    reg s_sclk_d = 1'b0, s_busy_d = 1'b0;
    always @(posedge clk) begin
        s_sclk_d <= s_sclk; s_busy_d <= s_busy;
        if (s_sclk && !s_sclk_d) begin
            if (since_rise >= 0 && since_rise != 32) bad_period = bad_period + 1;
            since_rise = 1; n_rise = n_rise + 1;
        end else if (since_rise >= 0) since_rise = since_rise + 1;
        if (s_busy) busy_len = busy_len + 1;
        if (s_busy_d && !s_busy) begin
            if (n_rise != 16) bad_rises = bad_rises + 1;
            last_len = busy_len; words = words + 1;
            busy_len = 0; n_rise = 0; since_rise = -1;
        end
    end

    reg v0, v1;
    initial begin
        $display("\n  tb_ctl -- one word on one wire, and the guard bit");
        repeat (20) @(posedge clk);
        rst_n = 1'b1; repeat (8) @(posedge clk);

        // ---- 1.  the hotline: fabric.md 7 step 3 ---------------------------
        // Point 20 at 21 and 21 at 20 by hand.  A pattern sent in slot 21
        // comes out of slot 20 one frame later.
        send(6'o20, 6'o21, 1'b1, 1'b0, 1'b1, 1'b1);
        send(6'o21, 6'o20, 1'b1, 1'b0, 1'b1, 1'b1);
        @(posedge frame_stb); c_tx[6'o21] = 1'b1; c_tx[6'o20] = 1'b0;
        @(posedge frame_stb); @(posedge frame_stb); @(posedge clk);
        ck(c_rx[6'o20] === 1'b1, "20 hears 21: a hotline, set up by hand");
        ck(c_rx[6'o21] === 1'b0, "21 hears 20, and the two directions differ");
        @(posedge frame_stb); c_tx[6'o21] = 1'b0; c_tx[6'o20] = 1'b1;
        @(posedge frame_stb); @(posedge frame_stb); @(posedge clk);
        ck(c_rx[6'o20] === 1'b0 && c_rx[6'o21] === 1'b1, "and it follows");

        // ---- 2.  BUSY reached the latch ------------------------------------
        ck(port_busy[6'o20] === 1'b1, "the BSY bit landed in 20's '273");
        ck(port_busy[6'o21] === 1'b1, "and in 21's");

        // ---- 3.  the guard bit ----------------------------------------------
        // A word with G clear cannot write.  It still shifts and still pulses
        // WR -- that is the event word a listener counts.
        nwr = 0; count_wr = 1'b1;
        send(6'o20, 6'o03, 1'b0, 1'b0, 1'b0, 1'b1);     // G = 0
        count_wr = 1'b0;
        ck(nwr == 1, "an event word still pulses WR");
        @(posedge frame_stb); @(posedge frame_stb); @(posedge clk);
        ck(port_busy[6'o20] === 1'b1, "but it wrote nothing: 20 is still busy");
        ck(c_rx[6'o20] === c_tx[6'o21], "and still listening to 21, not to 03");

        // ---- 4.  the probe steer: shift with WR suppressed -------------------
        nwr = 0; count_wr = 1'b1;
        send(6'o50, 6'o00, 1'b0, 1'b0, 1'b1, 1'b0);     // strobe = 0
        count_wr = 1'b0;
        ck(nwr == 0, "a pointing word never pulses WR");
        @(posedge frame_stb); @(posedge frame_stb); @(posedge clk);
        ck(port_busy[6'o20] === 1'b1, "and wrote nothing either");

        // ---- 5.  a word for another block is not ours ------------------------
        send(6'o50, 6'o07, 1'b1, 1'b0, 1'b1, 1'b1);     // block 5, not shunted
        @(posedge frame_stb); @(posedge frame_stb); @(posedge clk);
        ck(port_busy[6'o20] === 1'b1, "a word naming block 5 leaves block 2 alone");

        // ---- 6.  CLAIM is the card's A_RX: a claimed trunk's backward A --------
        send(6'o20, 6'o21, 1'b1, 1'b0, 1'b1, 1'b1);
        @(posedge frame_stb); @(posedge frame_stb); @(posedge clk);
        ck(a_rx[6'o20] === 1'b0, "20 listens to an on-hook 21: no E, and no CLAIM");
        send(6'o20, 6'o21, 1'b1, 1'b1, 1'b1, 1'b1);         // CLM = 1
        @(posedge frame_stb); @(posedge frame_stb); @(posedge clk);
        ck(a_rx[6'o20] === 1'b1, "CLM = 1 lands: A_RX = E + CLAIM, backward A up");
        send(6'o20, 6'o21, 1'b1, 1'b0, 1'b1, 1'b1);         // CLM = 0
        @(posedge frame_stb); @(posedge frame_stb); @(posedge clk);
        ck(a_rx[6'o20] === 1'b0, "and a write without it takes it away");

        // ---- 7.  the rate ----------------------------------------------------
        ck(words >= 8 && bad_period == 0, "every SCLK period is 32 ticks: 128 kHz");
        ck(bad_rises == 0, "every word is sixteen SCLK edges");
        send(6'o21, 6'o20, 1'b1, 1'b0, 1'b1, 1'b1);
        // 17 bit-times of 32 ticks, and one tick more for busy to fall
        ck(last_len == 545, "a written word is 17 bit-times: busy 544 + 1 ticks");
        $display("     a written word took %0d master ticks", last_len);

        // ---- 8.  /RESET ------------------------------------------------------
        // fabric.md 3.3: a port that releases clears its '273 to zeros --
        // highway 0, slot 0 -- and port 00 is never fitted, so it reads FILL.
        // FILL is the 1010 idle pattern, so what a cleared port hears is a bit
        // that changes every frame, not a level.
        rst_n = 1'b0; repeat (4) @(posedge clk); rst_n = 1'b1;
        @(posedge frame_stb); @(posedge frame_stb);
        ck(port_busy[6'o20] === 1'b0 && port_busy[6'o21] === 1'b0,
           "/RESET cleared every latch");
        @(posedge frame_stb); repeat (40) @(posedge clk);
        v0 = c_rx[6'o20];
        @(posedge frame_stb); repeat (40) @(posedge clk);
        v1 = c_rx[6'o20];
        ck(v0 !== v1, "a cleared latch listens to 00 and hears FILL: 1010");

        $display("\n  %0d checks, %0d errors.  %s\n", chk, errs,
                 (errs == 0) ? "PASS" : "FAIL");
        if (errs) $fatal(1);
        $finish;
    end

    initial begin #200_000_000; $display("  TIMEOUT"); $fatal(1); end
endmodule
