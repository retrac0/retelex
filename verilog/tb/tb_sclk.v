// tb_sclk -- mainboard.md §7's SCLK hazard, measured.
//
// A spurious rising edge on SCLK during a shift puts one extra bit into every
// block's '164.  The next WR then writes the wrong port with the wrong source:
// one call broken.  A shift register has no stored phase, so the next clean
// word re-aligns itself -- the damage does not persist.
//
// Idle-time glitches are harmless (sixteen fresh edges refill the register).
// The failure is an extra edge *during* SHIFT, which this bench drives by hand.
`timescale 1ns/1ps

module tb_sclk;
    reg clk = 0, rst_n = 0;
    always #122.0703 clk = ~clk;

    localparam [5:0] P20 = 6'o20, P21 = 6'o21, P30 = 6'o30, P31 = 6'o31;

    // Cable B: ctl_write for clean words; hand-driven for the glitched one.
    reg        cw_req = 0, cw_bsy = 0, cw_clm = 0;
    reg  [5:0] cw_dst = 0, cw_src = 0;
    wire       cw_busy, sdata_ser, sclk_ser, wr_ser;
    reg        use_ser = 1'b1;
    reg        sdata_h = 0, sclk_h = 0, wr_h = 0;
    wire       sdata = use_ser ? sdata_ser : sdata_h;
    wire       sclk  = use_ser ? sclk_ser  : sclk_h;
    wire       wr    = use_ser ? wr_ser    : wr_h;

    ctl_write u_con (.clk(clk), .rst_n(rst_n), .req(cw_req), .strobe(1'b1), .g(1'b1),
                     .dst(cw_dst), .src(cw_src), .bsy(cw_bsy), .clm(cw_clm),
                     .busy(cw_busy), .sdata(sdata_ser), .sclk(sclk_ser), .wr(wr_ser));

    reg  [63:0] ctx = 0, atx = 0, word = 0;
    wire [63:0] c_rx, a_rx, port_busy;
    wire        frame_stb, fill;

    exch_top #(.BLOCK_FITTED(8'hFF), .PORT_FITTED({64{1'b1}}),
               .PORT_RINGS(64'd0),
               .T_RISE(20000), .T_FALL(20000))
    dut (.clk(clk), .rst_n(rst_n),
         .c_tx(ctx), .a_tx(atx), .word(word), .c_rx(c_rx), .a_rx(a_rx),
         .sdata(sdata), .sclk(sclk), .wr(wr),
         .con_n(1'b1), .scan_port(3'd0),
         .pb_busy(), .pb_word(), .port_busy(port_busy),
         .slot(), .slotq(), .hclk(), .line_hb(), .tx_clk(),
         .frame_stb(frame_stb), .tx_oct(), .rx_oct(),
         .fill(fill), .ring_cad_n(), .tick_1k());

    always @(posedge clk) if (frame_stb) begin
        atx[P20] <= 1'b0; atx[P21] <= 1'b1;
        atx[P30] <= 1'b0; atx[P31] <= 1'b1;
        ctx <= {$random, $random};
    end

    integer errs = 0, chk = 0;

    task want(input v, input string what);
        begin
            chk = chk + 1;
            if (!v) begin errs = errs + 1; $display("     %-56s FAIL", what); end
            else $display("     %-56s ok", what);
        end
    endtask

    task wait_frames(input integer n);
        integer i;
        begin for (i = 0; i < n; i = i + 1) @(posedge frame_stb); #1; end
    endtask

    task wr_clean(input [5:0] pp, input [5:0] aa, input b);
        begin
            use_ser = 1'b1;
            @(posedge clk); #1;
            cw_dst = pp; cw_src = aa; cw_bsy = b; cw_clm = 0; cw_req = 1;
            @(posedge clk); #1; cw_req = 0;
            wait (cw_busy); wait (!cw_busy);
            repeat (8) @(posedge clk);
        end
    endtask

    // One bit onto the bus the way ctl_write does: SCLK rises mid-bit.
    task shift_bit(input integer bitv);
        begin
            sdata_h = bitv;
            repeat (3) @(posedge clk);
            sclk_h = 1'b1;
            repeat (4) @(posedge clk);
            sclk_h = 1'b0;
            repeat (1) @(posedge clk);
        end
    endtask

    // A write with ONE EXTRA shift mid-word -- mainboard.md §7 exactly.
    // 17 rising edges before WR; the intended DST/SRC are scrambled.
    task wr_glitched(input [5:0] pp, input [5:0] aa, input b);
        reg [15:0] w;
        integer i;
        begin
            use_ser = 1'b0;
            sclk_h = 0; wr_h = 0;
            w = {1'b1, 1'b0, pp, aa, b, 1'b0};     // G, spare, DST, SRC, BSY, CLM
            for (i = 15; i >= 8; i = i - 1)         // first 8 bits
                shift_bit(w[i]);
            shift_bit(w[7]);                        // EXTRA: duplicate bit 7
            for (i = 7; i >= 0; i = i - 1)          // remaining 8 bits
                shift_bit(w[i]);
            // WR clear of every SCLK edge (2.3.2)
            repeat (2) @(posedge clk);
            wr_h = 1'b1;
            repeat (4) @(posedge clk);
            wr_h = 1'b0;
            repeat (8) @(posedge clk);
            use_ser = 1'b1;
        end
    endtask

    task scrub(input [5:0] centre);
        integer k;
        begin
            for (k = 0; k < 64; k = k + 1)
                if ((k >= (centre & 6'o70) && k < (centre & 6'o70) + 8) ||
                    (k >= 6'o20 && k < 6'o40))
                    wr_clean(k[5:0], 6'o00, 1'b0);
        end
    endtask

    integer nbusy;
    reg     heard31;

    initial begin
        $display("SCLK (RTL) -- mainboard.md 7's spurious-shift hazard.\n");
        repeat (4) @(posedge clk);
        rst_n = 1;
        wait_frames(4);

        $display("  1. A clean write: 20 listens to 21, BUSY.");
        wr_clean(P20, P21, 1'b1);
        wait_frames(3);
        want(port_busy[P20], "20 is BUSY");
        want(a_rx[P20] === atx[P21], "20 hears 21's A");

        $display("\n  2. One spurious SCLK edge during the shift of 30 <- 31.");
        wr_clean(P20, 6'o00, 1'b0);
        wait_frames(2);
        nbusy = $countones(port_busy);
        wr_glitched(P30, P31, 1'b1);
        wait_frames(3);
        heard31 = port_busy[P30] && (a_rx[P30] === atx[P31]);
        want(!heard31,
             "30 did NOT get a clean 31: the write was mangled");
        want($countones(port_busy) <= nbusy + 1,
             "at most one port was written (one call, not a spray)");
        $display("     (BUSY map after glitch: %016h)", port_busy);

        $display("\n  3. The next clean word re-aligns: damage does not persist.");
        scrub(P30);
        wait_frames(2);
        want($countones(port_busy) == 0, "scrubbed: nothing held");
        wr_clean(P30, P31, 1'b1);
        wr_clean(P31, P30, 1'b1);
        wait_frames(3);
        want(port_busy[P30] && port_busy[P31], "30 and 31 both BUSY after clean writes");
        want(a_rx[P30] === atx[P31] && a_rx[P31] === atx[P30],
             "each hears the other: the bus is back in step");

        $display("\n  4. Release both ends; the exchange is idle.");
        wr_clean(P30, 6'o00, 1'b0);
        wr_clean(P31, 6'o00, 1'b0);
        wait_frames(2);
        want($countones(port_busy) == 0, "nothing held");

        $display("\n  5. A spurious edge while the bus is idle costs nothing.");
        use_ser = 1'b0;
        sclk_h = 1'b1; repeat (3) @(posedge clk); sclk_h = 1'b0;
        repeat (16) @(posedge clk);
        use_ser = 1'b1;
        wr_clean(P20, P21, 1'b1);
        wait_frames(3);
        want(port_busy[P20] && a_rx[P20] === atx[P21],
             "a write after an idle glitch still lands on 20 <- 21");
        wr_clean(P20, 6'o00, 1'b0);
        wait_frames(2);
        want($countones(port_busy) == 0, "and clears cleanly");

        $display("\n  %0d checks, %0d errors.  %s", chk, errs,
                 (errs == 0) ? "PASS" : "FAIL");
        if (errs) $fatal(1);
        $finish;
    end

    initial begin #50_000_000; $display("  TIMEOUT"); $finish; end
endmodule
