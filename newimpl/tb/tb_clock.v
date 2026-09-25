// tb_clock -- the divider chain, and the one invariant the design rests on.
//
// fabric.md 7 step 1, with two additions the fold asks for: FILL and SCAN[0]
// must be the same waveform, and SCAN must step on every frame edge with no
// exception whatever.  Since 2026-09-25 the clock card drives neither FILL
// nor TICK, TX_CLK, TX_OCT or RX_OCT: a block makes them from SLOT2 and SCAN
// (frame_decode.v), and the checks that name them check that decode.
`timescale 1ns/1ps
`include "exch.vh"

module tb_clock;
    integer chk = 0, errs = 0, shown = 0;

    task ck(input cond, input [8*56-1:0] what);
        begin
            chk = chk + 1;
            if (!cond) begin
                errs = errs + 1;
                $display("    FAIL  %0s", what);
            end
        end
    endtask

    // A continuous checker fires every master tick, so cap what it prints.
    task oops(input [8*56-1:0] what);
        begin
            errs = errs + 1;
            if (shown < 10) begin
                shown = shown + 1;
                $display("    FAIL  %0s   at %0t", what, $time);
            end
        end
    endtask

    // 4.096 MHz: 244.140625 ns.  The model's one clock.
    reg clk = 1'b0, rst_n = 1'b0;
    always #122.070 clk = ~clk;

    wire [2:0] tick, slot, slotq;
    wire hclk, cap_stb, tx_clk, frame_stb, clk_8k, rx_oct, oct_stb;
    wire [`SCANW-1:0] scan;
    wire pass_stb, fill, ring_cad_n, tick_1k;

    clock_card u_clk (
        .clk(clk), .rst_n(rst_n),
        .tick(tick), .hclk(hclk),
        .slot(slot), .slotq(slotq), .cap_stb(cap_stb),
        .frame_stb(frame_stb), .scan(scan), .ring_cad_n(ring_cad_n));

    // The five lines that left the bus, as a block makes them from SLOT2 and
    // SCAN.  Every check below that names one of them checks this decode.
    frame_decode u_dec (
        .slot2(slot[2]), .frame_stb(frame_stb), .scan(scan),
        .tx_clk(tx_clk), .tx_oct(clk_8k), .rx_oct(rx_oct), .oct_stb(oct_stb),
        .fill(fill), .tick_1k(tick_1k));
    assign pass_stb = tick_1k;

    // A second card with the cadence cut to 8 ms / 16 ms.  Same counter, same
    // 1:2 shape, small enough to watch -- 2.048 s of the real one is 8.4
    // million master ticks and proves nothing the ratio does not.
    wire cad_n;
    clock_card #(.RING_ON_MS(13'd8), .RING_OFF_MS(13'd16)) u_cad (
        .clk(clk), .rst_n(rst_n),
        .tick(), .hclk(), .slot(), .slotq(), .cap_stb(),
        .frame_stb(), .scan(), .ring_cad_n(cad_n));

    reg armed = 1'b0;

    // ---- one sampling block, so nothing races ------------------------------
    reg [`SCANW-1:0] scan_prev; reg scan_seen = 1'b0;
    reg clk8_d = 1'b0;
    integer n_master=0, n_frame=0, n_pass=0, n_tick1k=0, n_oct=0;
    integer n_clk8=0, adv=0;
    integer t0=0, t1=0, f0=0, f1=0, k0=0, k1=0, o0=0, o1=0, c0=0, c1=0;
    integer cad_lo=0, cad_hi=0; reg cad_run = 1'b0;

    always @(posedge clk) if (armed) begin
        n_master = n_master + 1;

        // ---- things that must hold on every single master tick -------------
        // FILL and SCAN[0] are the same divider stage (clocks.md 1).  Invert
        // one of them "locally" and the whole A plane is off by a bit-time.
        if (fill    !== scan[0]) oops("FILL is not SCAN[0]");
        if (hclk    !== ~tick[2]) oops("HCLK is not /tick[2]");
        if (tx_clk  !== ~slot[2]) oops("TX_CLK is not /SLOT[2]");
        if (cap_stb !== (tick == `TICK_MID)) oops("cap_stb is not mid-cell");

        // SLOTQ: the '175 takes SLOT on the tick-2 edge, so it reads the new
        // cell from tick 3 and the previous one at ticks 0, 1 and 2.  That is
        // the quarter cell of fabric.md 3.2, and the reason the strobe
        // decoder's address only ever moves while the decoder is disabled.
        if (tick > `TICK_SLOTQ) begin
            if (slotq !== slot) oops("SLOTQ did not catch up by tick 3");
        end else begin
            if (slotq !== (slot - 3'd1)) oops("SLOTQ moved early");
        end

        // pass_stb only at port 00, and it IS tick_1k -- 64 ports of 64 master
        // ticks is 4096, so the pass boundary and TICK are one edge.  If these
        // two ever come apart, either the scan width or the frame rate moved.
        if (pass_stb && (scan !== {`SCANW{1'b0}})) oops("pass_stb away from port 00");
        if (tick_1k && !frame_stb) oops("TICK off a frame edge");
        if (pass_stb !== tick_1k)  oops("pass_stb and TICK are not the same edge");

        // ---- THE INVARIANT -------------------------------------------------
        // SCAN increments on every frame edge, always, no exception.  Every
        // long bench in this tree carries this assertion.
        if (frame_stb) begin
            if (scan_seen && (scan !== ((scan_prev + 1'b1) & {`SCANW{1'b1}})))
                oops("SCAN did not step across a frame edge");
            scan_prev = scan; scan_seen = 1'b1; adv = adv + 1;

            clk8_d = clk_8k;
            if (rx_oct !== clk8_d) ; // checked below against the previous frame
            n_frame = n_frame + 1;
            if (clk_8k) n_clk8 = n_clk8 + 1;
        end

        if (tick_1k)  n_tick1k = n_tick1k + 1;
        if (oct_stb)  n_oct    = n_oct + 1;

        if (pass_stb) begin
            n_pass = n_pass + 1;
            if (n_pass == 1) begin
                t0 = n_master; f0 = n_frame;
                k0 = n_tick1k; o0 = n_oct;   c0 = n_clk8;
            end
            if (n_pass == 2) t1 = n_master;
            if (n_pass == 9) begin
                f1 = n_frame;
                k1 = n_tick1k; o1 = n_oct;   c1 = n_clk8;
            end
        end

        // the cadence, on the small card
        if (cad_run) begin
            if (!cad_n) cad_lo = cad_lo + 1; else cad_hi = cad_hi + 1;
        end
    end

    // RX_OCT is CLK_8K one frame late.  Checked on its own, one frame apart.
    reg c8_prev = 1'b0; reg c8_seen = 1'b0;
    always @(posedge clk) if (armed && frame_stb) begin
        if (c8_seen && (rx_oct !== c8_prev)) oops("RX_OCT is not CLK_8K a frame late");
        c8_prev = clk_8k; c8_seen = 1'b1;
    end

    initial begin
        $display("\n  tb_clock -- the chain, and that nothing can stop the scanner");
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);
        @(posedge frame_stb);
        @(posedge clk);
        armed = 1'b1;

        // ---- a pass is 4096 master ticks ------------------------------------
        // 8 ticks a cell, 8 cells a frame, 64 frames a pass -- one frame a
        // port, because M and BUSY ride separate conductors.
        wait (n_pass == 10);
        ck(t1 - t0 == 4096, "a pass is 4096 master ticks = 1.000 ms");
        $display("     a pass measured %0d master ticks (1 ms at 4.096 MHz)", t1 - t0);

        // ---- the ratios, over eight whole passes ----------------------------
        // 64 frames a pass IS 64 ports a pass now: one turn, one frame, both
        // planes.  There is no separate port strobe left to count.
        ck(f1 - f0 == 8*64,  "64 frames a pass, one a port");
        ck(k1 - k0 == 8*1,   "TICK once a pass: the pass boundary IS TICK");
        ck(o1 - o0 == 8*8,   "CLK_8K eight times a pass: 8 kHz");
        ck(c1 - c0 == 8*8,   "CLK_8K high for one frame in eight");
        ck(adv == n_frame,   "SCAN stepped on every frame edge, with none held");
        $display("     %0d frame edges, %0d SCAN steps, none held", n_frame, adv);

        // ---- the cadence, 8 ms / 16 ms on the small card ---------------------
        @(negedge cad_n);
        @(posedge clk);
        cad_lo = 0; cad_hi = 0; cad_run = 1'b1;
        @(posedge cad_n);
        @(negedge cad_n);
        cad_run = 1'b0;
        // 1 ms is 4096 master ticks
        ck(cad_lo == 8*4096,  "ring cadence low for 8 ms");
        ck(cad_hi == 16*4096, "ring cadence high for 16 ms");
        $display("     cadence %0d low / %0d high master ticks (8 ms / 16 ms)",
                 cad_lo, cad_hi);

        $display("\n  %0d checks, %0d errors.  %s\n", chk, errs,
                 (errs == 0) ? "PASS" : "FAIL");
        if (errs) $fatal(1);
        $finish;
    end

    initial begin
        #400_000_000;
        $display("  TIMEOUT");
        $fatal(1);
    end
endmodule
