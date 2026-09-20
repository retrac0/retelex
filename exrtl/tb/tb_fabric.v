// tb_fabric -- the RTL against `python3 exch/exch.py fabric`.
//
// The bare crosspoint: every source to every listener, bit-exact, one frame.
// Supervision is configured out of the way rather than switched off -- every
// /ANS is tied low (a card that answers at once, which never rings), and the
// two release detectors are set longer than the run, so no port clears its own
// latch while the fabric is being measured.  That is what exch.py's `highway()`
// models: the fabric with nobody in charge of anything.
`timescale 1ns/1ps

module tb_fabric;
    localparam integer NF_MAP = 24;         // frames to watch each map for

    reg          clk = 0, rst_n = 0;
    reg  [63:0]  ctx = 0, atx = 0;
    reg  [63:0]  word = 0;
    wire [63:0]  c_rx, a_rx;

    // The operator's console, on the serial control bus: the same sixteen-bit
    // word the marker sends (exch-mainboard.md 2.3), driven by hand.
    reg        cw_req = 0, cw_bsy = 0, cw_clm = 0;
    reg  [5:0] cw_dst = 0, cw_src = 0;
    wire       cw_busy, sdata, sclk, wr;
    ctl_write u_con (.clk(clk), .rst_n(rst_n), .req(cw_req), .strobe(1'b1),
                     .dst(cw_dst), .src(cw_src), .bsy(cw_bsy), .clm(cw_clm),
                     .busy(cw_busy), .sdata(sdata), .sclk(sclk), .wr(wr));
    wire         frame_stb, fill;

    reg  [5:0]   map [0:63];                // each port's latch, as the TB believes it
    reg          checking = 0;
    integer      errs = 0, pairs = 0, bits = 0, fcount = 0;
    integer      m, p;

    exch_top #(.BLOCK_FITTED(8'hFF), .PORT_FITTED({64{1'b1}}),
               .PORT_RINGS(64'd0),          // every /ANS low: nothing rings
               .T_RISE(20000), .T_FALL(20000))
    dut (.clk(clk), .rst_n(rst_n),
         .c_tx(ctx), .a_tx(atx), .word(word), .c_rx(c_rx), .a_rx(a_rx),
         .sdata(sdata), .sclk(sclk), .wr(wr),
         .pb_busy(), .pb_word(), .slot(), .slotq(), .hclk(), .hb(),
         .tx_clk(), .frame_stb(frame_stb), .tx_oct(), .rx_oct(),
         .fill(fill), .ring_cad_n(), .tick_1k());

    always #122 clk = ~clk;                 // 4.096 MHz

    // The cards: each changes its bit at the frame edge, as on the MF8 backplane.
    // A frame later, every listener is checked against what its source sent --
    // the one-frame delay that is the same for every pair of ports.
    always @(posedge clk) if (frame_stb) begin
        if (checking) begin
            for (p = 0; p < 64; p = p + 1) begin
                if (c_rx[p] !== ctx[map[p]]) errs = errs + 1;
                if (a_rx[p] !== atx[map[p]]) errs = errs + 1;
                bits = bits + 2;
            end
        end
        ctx <= {$random, $random};
        atx <= {$random, $random};
        fcount = fcount + 1;
    end

    task wait_frames(input integer n);
        integer target;
        begin
            target = fcount + n;
            while (fcount < target) @(posedge clk);
            #1;
        end
    endtask

    task wr_latch(input [5:0] pp, input [5:0] aa);
        begin
            @(posedge clk); #1;
            cw_dst = pp; cw_src = aa; cw_bsy = 0; cw_clm = 0; cw_req = 1;
            @(posedge clk); #1; cw_req = 0;
            wait (cw_busy); wait (!cw_busy);
            map[pp] = aa;
        end
    endtask

    task point_all(input integer off);      // port p listens to p + off (mod 64)
        begin
            for (p = 0; p < 64; p = p + 1) wr_latch(p[5:0], (p + off) % 64);
        end
    endtask

    task watch(input integer nf);
        begin
            wait_frames(2);                 // let the new map settle
            checking = 1;
            wait_frames(nf);
            checking = 0;
        end
    endtask

    initial begin
        $display("FABRIC (RTL) -- 8 highways x 8 slots, 4.096 MHz master, %0d frames a map.\n", NF_MAP);
        repeat (4) @(posedge clk);
        rst_n = 1;
        wait_frames(2);

        // 1. every source slot to every listening slot
        for (m = 0; m < 64; m = m + 1) begin
            point_all(m);
            watch(NF_MAP);
            pairs = pairs + 64;
        end
        $display("  1. Every source slot to every listening slot: 64 maps, port p listens to p+m.");
        $display("     %0d (source, listener) pairs, C and A: %0d bit errors in %0d bits,", pairs, errs, bits);
        $display("     at a delay of exactly 1 frame.");

        // 3. fan-out
        errs = 0; bits = 0;
        for (p = 0; p < 64; p = p + 1) wr_latch(p[5:0], 6'o25);
        watch(NF_MAP);
        $display("\n  3. Fan-out: all 64 ports listening to port 25: %0d errors in %0d bits.", errs, bits);

        // 4. a cleared latch listens to port 00
        errs = 0; bits = 0;
        rst_n = 0; repeat (4) @(posedge clk); rst_n = 1;
        for (p = 0; p < 64; p = p + 1) map[p] = 6'o00;
        watch(NF_MAP);
        $display("\n  4. /RESET: every latch cleared, so every port listens to port 00.");
        $display("     %0d errors in %0d bits.", errs, bits);

        $display("\n  %s", (errs == 0) ? "PASS" : "FAIL");
        $finish;
    end
endmodule
