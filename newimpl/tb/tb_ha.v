// tb_ha -- the supervision plane on its own.
//
// TWO open-collector conductors at 64 kbps, /HA and /HB, both addressed by
// SCAN.  In bit-time p, port p pulls /HA for its M and /HB for its BUSY, so a
// pass is 64 bit-times = 1 ms and every port refreshes at 1 kHz.  There is
// nothing else on either wire; the card option word is /HW, which a reader
// selects on /WS and which no test here touches.
//
// THE MAP IS THE POINT.  One bit-time carries both facts about one port, so
// there is no phase bit, and no way for a reader to pair a port's M with its
// neighbour's BUSY -- which is the failure the interleaved single wire could
// produce if FILL and SCAN[0] were ever inverted against each other.
//
// This bench has no counterpart in verilog/, because until now A was eight
// 512 kbps highways with a '151 a block and there was no such thing as an A
// plane to test.
`timescale 1ns/1ps
`include "exch.vh"

module tb_ha;
    integer chk = 0, errs = 0, shown = 0;

    task ck(input cond, input [8*60-1:0] what);
        begin
            chk = chk + 1;
            if (!cond) begin chk = chk; errs = errs + 1; $display("    FAIL  %0s", what); end
        end
    endtask
    task oops(input [8*60-1:0] what);
        begin
            errs = errs + 1;
            if (shown < 8) begin shown = shown + 1;
                $display("    FAIL  %0s  at %0t", what, $time); end
        end
    endtask

    reg clk = 1'b0, rst_n = 1'b0;
    always #122.070 clk = ~clk;

    reg  [63:0] a_tx  = 64'd0;
    reg  [63:0] ans_n = {64{1'b1}};
    wire [63:0] c_rx, a_rx, port_busy;
    wire ha_n, hb_n, hw_n, cap_stb, frame_stb, fill, pass_stb, tick_1k;
    wire [2:0] slot, slotq;
    wire [`SCANW-1:0] scan;
    wire s_sdata, s_sclk, s_wr, s_busy;

    reg req = 1'b0; reg [`PW-1:0] dst = 6'd0, src = 6'd0;
    reg bsy = 1'b1, clm = 1'b0;

    ctl_write u_ser (
        .clk(clk), .rst_n(rst_n), .req(req), .g(1'b1),
        .dst(dst), .src(src), .bsy(bsy), .clm(clm),
        .busy(s_busy), .sdata(s_sdata), .sclk(s_sclk), .wr(s_wr));

    exch #(.PORT_FITTED({64{1'b1}}), .BLOCK_FITTED(8'hFF)) u_x (
        .clk(clk), .rst_n(rst_n),
        .c_tx(64'd0), .a_tx(a_tx), .ans_n(ans_n), .word_n({64{1'b1}}),
        .c_rx(c_rx), .a_rx(a_rx),
        .mute_blk(8'd0), .rbt_in(1'b0),
        .sdata(s_sdata), .sclk(s_sclk), .wr(s_wr), .ws_n(1'b1), .hw_n(hw_n),
        .hc(), .ha_n(ha_n), .hb_n(hb_n), .tick(), .slot(slot), .slotq(slotq),
        .hclk(), .cap_stb(cap_stb), .tx_clk(),
        .frame_stb(frame_stb), .clk_8k(), .rx_oct(), .oct_stb(),
        .scan(scan), .pass_stb(pass_stb),
        .fill(fill), .ring_cad_n(), .tick_1k(tick_1k),
        .port_busy(port_busy));

    // ---- a bare exchange: shunted, but not one port circuit fitted ---------
    wire bare_ha_n, bare_hb_n;
    exch #(.PORT_FITTED(64'd0), .BLOCK_FITTED(8'b0000_0100)) u_bare (
        .clk(clk), .rst_n(rst_n),
        .c_tx(64'd0), .a_tx({64{1'b1}}), .ans_n({64{1'b1}}), .word_n({64{1'b1}}),
        .c_rx(), .a_rx(), .mute_blk(8'd0), .rbt_in(1'b0),
        .sdata(1'b0), .sclk(1'b0), .wr(1'b0), .ws_n(1'b1), .hw_n(),
        .hc(), .ha_n(bare_ha_n), .hb_n(bare_hb_n), .tick(), .slot(), .slotq(),
        .hclk(), .cap_stb(), .tx_clk(),
        .frame_stb(), .clk_8k(), .rx_oct(), .oct_stb(),
        .scan(), .pass_stb(),
        .fill(), .ring_cad_n(), .tick_1k(), .port_busy());

    // The capture instant, as every port and every probe computes it.
    wire a_stb = cap_stb && (slotq == `CELL_A);

    // ---- a permuted exchange: every jumper reversed, position p on highway 7-p
    // A PORT'S NUMBER IS ITS HIGHWAY AND SLOT, not its position and slot, and
    // both planes must say so.  The socket in position 2, slot 3 is port 53
    // here.  Its M must appear in bit-time 53 and nowhere else -- in
    // particular not in 23, which is where a port that took its number from
    // its position would put it, and where exch.v used to put it.
    reg  [63:0] perm_a_tx = 64'd0;
    wire        perm_ha_n;
    exch #(.PORT_FITTED({64{1'b1}}), .BLOCK_NUM(24'o01234567), .BLOCK_FITTED(8'hFF)) u_perm (
        .clk(clk), .rst_n(rst_n),
        .c_tx(64'd0), .a_tx(perm_a_tx), .ans_n({64{1'b1}}), .word_n({64{1'b1}}),
        .c_rx(), .a_rx(), .mute_blk(8'd0), .rbt_in(1'b0),
        .sdata(1'b0), .sclk(1'b0), .wr(1'b0), .ws_n(1'b1), .hw_n(),
        .hc(), .ha_n(perm_ha_n), .hb_n(), .tick(), .slot(), .slotq(),
        .hclk(), .cap_stb(), .tx_clk(),
        .frame_stb(), .clk_8k(), .rx_oct(), .oct_stb(),
        .scan(), .pass_stb(),
        .fill(), .ring_cad_n(), .tick_1k(), .port_busy());

    // sampled at u_x's capture instant: every exchange in this bench shares
    // one clock and one reset, so their scanners are in lock-step
    reg        perm_watch = 1'b0;
    reg [63:0] perm_low   = 64'd0;
    always @(posedge clk)
        if (perm_watch && a_stb && !perm_ha_n) perm_low[scan] <= 1'b1;

    // ---- watch the wire ----------------------------------------------------
    reg  armed = 1'b0, bare_watch = 1'b0;
    integer n_stb = 0, n_pass = 0, tick_in_frame = 0, off_meas = -1;
    reg [`SCANW-1:0] stb_prev; reg stb_seen = 1'b0;
    reg [63:0] seen_a = 64'd0, seen_b = 64'd0;

    always @(posedge clk) begin
        if (frame_stb) tick_in_frame = 0; else tick_in_frame = tick_in_frame + 1;

        if (armed) begin
            if (bare_watch && (bare_ha_n !== 1'b1))
                oops("/HA pulled down by an exchange with no port circuits");
            if (bare_watch && (bare_hb_n !== 1'b1))
                oops("/HB pulled down by an exchange with no port circuits");

            if (a_stb) begin
                // where in the frame the capture lands
                if (off_meas < 0) off_meas = tick_in_frame;
                else if (tick_in_frame != off_meas) oops("the A capture moved in the frame");

                // exactly one bit-time a frame, and they step in order
                if (stb_seen && (scan !== ((stb_prev + 1'b1) & {`SCANW{1'b1}})))
                    oops("a bit-time was skipped on /HA");
                stb_prev = scan; stb_seen = 1'b1;
                n_stb = n_stb + 1;

                // THE MAP: in bit-time p, /HA is port p's M and /HB is port
                // p's BUSY -- the SAME port, the SAME instant.  Both are low
                // true: an open drain pulls down for a one.
                //
                // Checking them together is the whole point of the second
                // conductor.  If either plane were off by a port, or if the
                // two ever disagreed about whose turn it is, this fires.
                if ((~ha_n) !== a_tx[scan])
                    oops("/HA in bit-time p is not port p's M");
                if ((~hb_n) !== port_busy[scan])
                    oops("/HB in bit-time p is not port p's BUSY");
                seen_a[scan] = 1'b1;
                seen_b[scan] = 1'b1;
            end
            if (pass_stb) n_pass = n_pass + 1;
        end
    end

    task wr_latch(input [`PW-1:0] d, input [`PW-1:0] s, input b);
        begin
            @(posedge clk); dst = d; src = s; bsy = b; clm = 1'b0;
            req = 1'b1; @(posedge clk); req = 1'b0; @(posedge clk);
            while (s_busy) @(posedge clk);
        end
    endtask

    // ---- how long until a listener hears a hook change ---------------------
    integer t_start, t_delay, worst, best, trial;
    reg [31:0] mticks = 32'd0;
    always @(posedge clk) mticks <= mticks + 1'b1;

    integer i;
    initial begin
        $display("\n  tb_ha -- two wires, 64 ports, M and BUSY together, 1 kHz");
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        repeat (8) @(posedge clk);

        // a spread of hooks and a spread of BUSY, so the map is not trivially
        // satisfied by everything reading zero
        @(posedge frame_stb);
        a_tx = 64'h0F1E_2D3C_4B5A_6978;
        for (i = 0; i < 16; i = i + 1) wr_latch(i[`PW-1:0]*6'd3, 6'o05, 1'b1);

        @(posedge pass_stb); @(posedge clk);
        armed = 1'b1; bare_watch = 1'b1;

        // ---- four whole passes -------------------------------------------
        wait (n_pass == 5);
        ck(off_meas == 36,
           "the A capture is 36 master ticks into the frame (8.79 us)");
        ck(n_stb >= 4*64, "one bit-time a frame, none skipped");
        ck(seen_a == {64{1'b1}}, "all 64 ports put their M on /HA");
        ck(seen_b == {64{1'b1}}, "all 64 ports put their BUSY on /HB");
        $display("     %0d bit-times over %0d passes, capture at tick %0d of the frame",
                 n_stb, n_pass - 1, off_meas);

        // ---- a pass is 64 bit-times = 1 ms ---------------------------------
        @(posedge pass_stb); t_start = mticks;
        @(posedge pass_stb); t_delay = mticks - t_start;
        ck(t_delay == 4096, "a pass is 4096 master ticks = 1.000 ms");

        bare_watch = 1'b0;

        // ---- E across the wire: how stale can a hook be? -------------------
        // Port 30 listens to port 31.  30's /ANS is tied low so it does not
        // ring and its A_RX is E as it stands -- otherwise the cadence would
        // chop what we are trying to measure (fabric.md §5.2).
        armed = 1'b0;
        ans_n[6'o30] = 1'b0;
        wr_latch(6'o30, 6'o31, 1'b0);
        @(posedge frame_stb);
        a_tx = 64'd0;
        repeat (40) @(posedge frame_stb);

        worst = 0; best = 1000000;
        for (trial = 0; trial < 8; trial = trial + 1) begin
            // start at a different phase of the pass each time
            repeat (trial * 7 + 3) @(posedge frame_stb);
            @(posedge clk);
            t_start = mticks;
            a_tx[6'o31] = 1'b1;
            @(posedge a_rx[6'o30]);
            t_delay = mticks - t_start;
            if (t_delay > worst) worst = t_delay;
            if (t_delay < best)  best  = t_delay;
            // let it go again, well short of the 16 ms the detector needs
            @(posedge frame_stb);
            a_tx[6'o31] = 1'b0;
            repeat (200) @(posedge frame_stb);   // ~3 ms, and e is 0 again
            if (a_rx[6'o30] !== 1'b0) oops("E did not fall again");
        end
        // 4096 master ticks is one pass, 1.000 ms.  The allowance is one
        // bit-time: the probe publishes at the frame edge after the capture.
        ck(worst <= 4096 + 64, "a hook change reaches a listener within one pass");
        ck(best  <  4096,      "and sooner than that when the phase is kind");
        $display("     E followed M in %0d to %0d master ticks (%0d us to %0d us)",
                 best, worst, (best * 61) / 250, (worst * 61) / 250);

        // ---- the RC detectors are untouched by any of this -----------------
        // THE DETECTOR UNDER TEST IS PORT 30's fE, not port 31's fM.  Port 30's
        // latch points at 31 (the wr_latch above), so 31's M crosses /HA and
        // becomes 30's E; hold it up past T_ARM = 16 ms and 30's fE arms, which
        // shows in 30's BUSY.  Port 31's OWN busy would not move: port.v's term
        // is `fm && !m`, the hung-up guard, so a port holding M high never
        // raises its own BUSY through the detector.
        //
        // Sampled before, short of the window, and past it, so the check is the
        // ARMING and not the end state.  This replaces a disjunction whose
        // second term was constant-true in this bench's state -- it counted
        // toward the total and could not fail.
        //
        // The eight trials above only ever held M for about a pass, so 30's fE
        // has never armed and its latch was written with BSY clear.
        ck(port_busy[6'o30] === 1'b0, "30 is idle before its E detector arms");

        a_tx[6'o31] = 1'b1;
        repeat (800) @(posedge frame_stb);        // ~12.5 ms: short of T_ARM
        ck(port_busy[6'o30] === 1'b0,
           "at 12.5 ms of held E the 16 ms detector has NOT armed yet");
        repeat (400) @(posedge frame_stb);        // ~18.8 ms total: past T_ARM
        ck(port_busy[6'o30] === 1'b1,
           "and past 16 ms it has, off a 1 kHz staircase rather than a level");

        // ---- the permuted exchange: a port's number follows the shunt ------
        perm_a_tx[2*8 + 3] = 1'b1;               // the socket: position 2, slot 3
        @(posedge pass_stb); @(posedge clk);
        perm_watch = 1'b1;
        @(posedge pass_stb); @(posedge clk);
        perm_watch = 1'b0;
        ck(perm_low[6'o53] === 1'b1, "reversed shunt: socket (2,3) is port 53 on /HA");
        ck(perm_low[6'o23] === 1'b0, "and not 23, where its position would put it");
        ck(perm_low === (64'd1 << 6'o53), "and in no other bit-time");
        perm_a_tx = 64'd0;

        $display("\n  %0d checks, %0d errors.  %s\n", chk, errs,
                 (errs == 0) ? "PASS" : "FAIL");
        if (errs) $fatal(1);
        $finish;
    end

    initial begin
        #2_000_000_000;
        $display("  TIMEOUT");
        $fatal(1);
    end
endmodule
