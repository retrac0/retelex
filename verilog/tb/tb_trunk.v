// tb_trunk -- two exchanges tied by one MF8 link, with calls across it.
//
// Each exchange has a trunk block (block 1: six channels at 11-13 / 15-17,
// the trunk card tapping that highway) and a block of lines (block 2: ports
// 20 and 21).  One MF8 pair each way carries the six channels.  There is
// no marker, so the console patches the latches by hand at both ends --
// which is mvp.md 6.3's manual board with a trunk in the middle of it, and
// network.md 1's tie trunk exactly: a pair of ports, back to back, holding
// no digits and deciding nothing.
//
// What this exercises: the 8 x 8 fabric at both ends, an MF8 trunk card
// fusing the highway with the 8-bit / six-channel frame, differential
// Manchester in and out, the framer acquiring and tracking, the
// crossing between two exchanges' clocks, and the hotline and release rules of
// fabric.md 3.5 running through the trunk pair untouched.
`timescale 1ns/1ps

module tb_trunk;
    parameter integer PPM = 0;               // crystal offset of exchange B

    localparam integer T_RISE = 16, T_FALL = 256;
    localparam integer RING_ON = 200, RING_OFF = 400, T_A = 4;
    localparam real    PA = 122.0703125;
    localparam real    PB = 122.0703125 * (1.0 - PPM / 1000000.0);
    localparam integer FR = 15625;           // one frame, ns

    reg clk_a = 0, clk_b = 0, rst_n = 0;
    always #(PA) clk_a = ~clk_a;
    initial begin #40; forever #(PB) clk_b = ~clk_b; end

    // a console at each exchange, on its own serial control bus
    reg        rqa = 0, rqb = 0;
    reg  [5:0] dsta = 0, srca = 0, dstb = 0, srcb = 0;
    wire       bsya, bsyb, sda, scka, wr_a, sdb, sckb, wr_b;
    ctl_write ca (.clk(clk_a), .rst_n(rst_n), .req(rqa), .strobe(1'b1), .g(1'b1),
                  .dst(dsta), .src(srca), .bsy(1'b1), .clm(1'b0),
                  .busy(bsya), .sdata(sda), .sclk(scka), .wr(wr_a));
    ctl_write cb (.clk(clk_b), .rst_n(rst_n), .req(rqb), .strobe(1'b1), .g(1'b1),
                  .dst(dstb), .src(srcb), .bsy(1'b1), .clm(1'b0),
                  .busy(bsyb), .sdata(sdb), .sclk(sckb), .wr(wr_b));

    // the subscribers
    reg  h20a = 0, h21a = 0, h20b = 0, h21b = 0;
    reg  t20a = 0, t21a = 0, t20b = 0, t21b = 0;
    wire r20a, r21a, r20b, r21b, e20a, e21a, e20b, e21b;

    // the link, with a switch in it
    reg  cut = 0;
    wire la_out, lb_out;
    wire la_in = cut ? 1'b0 : lb_out;
    wire lb_in = cut ? 1'b0 : la_out;
    wire lock_a, lock_b, cd_a, cd_b, fs_a, fs_b, fill_a, fill_b, rc_a, rc_b;

    trunk_site #(.T_RISE(T_RISE), .T_FALL(T_FALL), .RING_ON(RING_ON),
                 .RING_OFF(RING_OFF), .T_A(T_A))
    A (.clk(clk_a), .rst_n(rst_n), .sdata(sda), .sclk(scka), .wr(wr_a), .hook20(h20a), .hook21(h21a),
       .tx20(t20a), .tx21(t21a), .rx20(r20a), .rx21(r21a), .e20(e20a), .e21(e21a),
       .line_in(la_in), .line_out(la_out), .locked(lock_a), .cd(cd_a),
       .frame_stb(fs_a), .fill(fill_a), .ring_cad_n(rc_a));

    trunk_site #(.T_RISE(T_RISE), .T_FALL(T_FALL), .RING_ON(RING_ON),
                 .RING_OFF(RING_OFF), .T_A(T_A))
    B (.clk(clk_b), .rst_n(rst_n), .sdata(sdb), .sclk(sckb), .wr(wr_b), .hook20(h20b), .hook21(h21b),
       .tx20(t20b), .tx21(t21b), .rx20(r20b), .rx21(r21b), .e20(e20b), .e21(e21b),
       .line_in(lb_in), .line_out(lb_out), .locked(lock_b), .cd(cd_b),
       .frame_stb(fs_b), .fill(fill_b), .ring_cad_n(rc_b));

    reg  path_en = 0;
    bitpath p_a20b20 (.src_clk(clk_a), .src_fs(fs_a), .src_bit(t20a),
                      .dst_clk(clk_b), .dst_fs(fs_b), .dst_bit(r20b), .enable(path_en));
    bitpath p_b20a20 (.src_clk(clk_b), .src_fs(fs_b), .src_bit(t20b),
                      .dst_clk(clk_a), .dst_fs(fs_a), .dst_bit(r20a), .enable(path_en));
    bitpath p_a21b21 (.src_clk(clk_a), .src_fs(fs_a), .src_bit(t21a),
                      .dst_clk(clk_b), .dst_fs(fs_b), .dst_bit(r21b), .enable(path_en));
    bitpath p_b21a21 (.src_clk(clk_b), .src_fs(fs_b), .src_bit(t21b),
                      .dst_clk(clk_a), .dst_fs(fs_a), .dst_bit(r21a), .enable(path_en));

    // speech: a fresh bit every frame from whoever is off-hook
    always @(posedge clk_a) if (fs_a) begin
        if (h20a) t20a <= $random; if (h21a) t21a <= $random;
    end
    always @(posedge clk_b) if (fs_b) begin
        if (h20b) t20b <= $random; if (h21b) t21b <= $random;
    end

    integer errs = 0, chk = 0;

    task wf(input integer n); begin #(n * FR); end endtask

    // The console, writing one latch on one exchange.  BUSY is set with it,
    // which is what the marker would do.
    task patch_a(input [5:0] p, input [5:0] s);
        begin
            @(posedge clk_a); #1; dsta = p; srca = s; rqa = 1;
            @(posedge clk_a); #1; rqa = 0;
            wait (bsya); wait (!bsya);
        end
    endtask
    task patch_b(input [5:0] p, input [5:0] s);
        begin
            @(posedge clk_b); #1; dstb = p; srcb = s; rqb = 1;
            @(posedge clk_b); #1; rqb = 0;
            wait (bsyb); wait (!bsyb);
        end
    endtask

    task want(input v, input string what);
        begin
            chk = chk + 1;
            if (!v) begin errs = errs + 1;
                $display("     %-52s FAIL", what);
            end else
                $display("     %-52s ok", what);
        end
    endtask

    // Ringing: E at the called line follows the cadence, and it is the only
    // thing that does.  Watched over more than one full 2 s / 4 s period.
    task watch_cadence(input integer n, input string what);
        integer i, hi, lo;
        begin
            hi = 0; lo = 0;
            for (i = 0; i < n; i = i + 1) begin
                #(FR);
                if (e20b && !rc_b) hi = hi + 1;
                if (!e20b && rc_b) lo = lo + 1;
            end
            chk = chk + 1;
            if (hi > n/4 && lo > n/4)
                $display("     %-52s ok", what);
            else begin errs = errs + 1;
                $display("     %-52s FAIL (%0d/%0d)", what, hi, lo);
            end
        end
    endtask

    // The same, watching BOTH of A's lines: each must follow A's own cadence.
    task ring_a(input integer n, input string what);
        integer i, hi, lo;
        begin
            hi = 0; lo = 0;
            for (i = 0; i < n; i = i + 1) begin
                #(FR);
                if (e20a && e21a && !rc_a) hi = hi + 1;
                if (!e20a && !e21a && rc_a) lo = lo + 1;
            end
            chk = chk + 1;
            if (hi > n/4 && lo > n/4) $display("     %-52s ok", what);
            else begin errs = errs + 1;
                $display("     %-52s FAIL (%0d/%0d)", what, hi, lo); end
        end
    endtask

    integer t0;
    initial begin
        $display("TRUNK (RTL) -- two exchanges, one MF8 link, calls across it.");
        $display("  Exchange B's crystal is %0d ppm from A's.\n", PPM);
        #4000 rst_n = 1;

        // ---- 1. the link comes up -----------------------------------------
        t0 = $time;
        wait (lock_a && lock_b);
        $display("  1. The link.");
        $display("     both framers locked %0d frames after reset      ok",
                 ($time - t0) / FR);
        want(cd_a && cd_b, "carrier detected at both ends");
        wf(20);

        // ---- 2. a call from a line on A to a line on B ---------------------
        // Trunk traffic seats are slots 1-3/5-7 (ports 11-13/15-17).  Slot 0/4
        // are F and S on the wire -- not channels (mf8_trunk_card, trunk_site).
        $display("\n  2. A's line 20 calls B's line 20, over trunk channel 11.");
        patch_a(6'o20, 6'o11); patch_a(6'o11, 6'o20);   // A: line 20 <-> trunk 11
        patch_b(6'o11, 6'o20); patch_b(6'o20, 6'o11);   // B: trunk 11 <-> line 20
        wf(10);
        h20a = 1;                                       // A's 20 lifts
        wf(T_RISE + 20);
        want(!e20a, "A20 gets no answer signal yet");
        watch_cadence(2 * (RING_ON + RING_OFF), "B20 rings, in cadence, from a lift on A");

        h20b = 1;                                       // B's 20 answers
        wf(T_RISE + 20);
        want(e20a && e20b, "answer: E steady at both ends, ringing stopped");
        path_en = 1; wf(400); path_en = 0;
        p_a20b20.report("speech A20 -> B20");
        p_b20a20.report("speech B20 -> A20");
        if (p_a20b20.best_err != 0 || p_b20a20.best_err != 0) errs = errs + 1;
        chk = chk + 2;

        // ---- 3. release, from the far end ---------------------------------
        h20b = 0;                                       // B's 20 hangs up
        wf(T_FALL + 60);
        want(!e20a && !e20b, "B hangs up: both ends released through the trunk");
        h20a = 0;
        wf(T_FALL + 60);

        // ---- 4. the other way, and a second call at the same time ---------
        $display("\n  4. B's 20 calls A's 20 on channel 11, and B's 21 calls A's 21 on channel 12.");
        patch_a(6'o20, 6'o11); patch_a(6'o11, 6'o20);
        patch_b(6'o11, 6'o20); patch_b(6'o20, 6'o11);
        patch_a(6'o21, 6'o12); patch_a(6'o12, 6'o21);
        patch_b(6'o12, 6'o21); patch_b(6'o21, 6'o12);
        wf(10);
        h20b = 1; h21b = 1;                             // both of B's lines lift
        wf(T_RISE + 20);
        ring_a(2 * (RING_ON + RING_OFF), "A20 and A21 both ring, in cadence, from B");
        h20a = 1; h21a = 1;                             // both of A's lines answer
        wf(T_RISE + 20);
        want(e20a && e20b && e21a && e21b, "both calls answered at once");
        p_a20b20.clear; p_b20a20.clear; p_a21b21.clear; p_b21a21.clear;
        path_en = 1; wf(400); path_en = 0;
        p_b20a20.report("speech B20 -> A20, channel 11");
        p_a20b20.report("speech A20 -> B20, channel 11");
        p_b21a21.report("speech B21 -> A21, channel 12");
        p_a21b21.report("speech A21 -> B21, channel 12");
        chk = chk + 4;
        if (p_b20a20.best_err || p_a20b20.best_err ||
            p_b21a21.best_err || p_a21b21.best_err) errs = errs + 1;
        want(p_a20b20.best_d == p_a21b21.best_d,
             "both channels cross with the same delay: no crosstalk");

        // ---- 5. the link fails --------------------------------------------
        $display("\n  5. The link fails, with two calls up on it.");
        cut = 1;
        wf(40);
        want(!cd_a && !cd_b, "no carrier: squelch at both ends");
        want(!lock_a && !lock_b, "both framers unlocked");
        wf(T_FALL + 80);
        want(!e20a && !e21a && !e20b && !e21b,
             "every call on the trunk released itself");
        h20a = 0; h21a = 0; h20b = 0; h21b = 0;

        cut = 0;                                        // and it comes back
        t0 = $time;
        wait (lock_a && lock_b);
        $display("     link restored: re-locked in %0d frames             ok",
                 ($time - t0) / FR);

        $display("\n  %0d checks, %0d errors.  %s", chk, errs, (errs == 0) ? "PASS" : "FAIL");
        if (errs) $fatal(1);
        $finish;
    end

    initial begin #500000000; $display("  TIMEOUT"); $finish; end
endmodule
