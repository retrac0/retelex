// tb_inprog -- the calls-in-progress display against a real exchange.
//
// TWO STIMULI, DELIBERATELY.
//
//   DIRECTED  a synthetic scanner drives u_dir, so the decode, the range, the
//             overflow, the de-dup and the /CON freeze are exercised at values
//             a real exchange will not conveniently produce.
//
//   REAL      u_dut taps net_site's OWN scan_port, pb_busy and oct_stb --
//             hierarchically, as tb_console.v:207 taps the marker's scanner --
//             and every check compares the display against $countones() of
//             net_site's port_busy, which is the ports' actual latches.  The
//             stimulus is NOT synthesised from the card's own assumption about
//             how the probe is commutated.  That is the mistake tb_panel.v:73
//             makes on the busy half of the hook/busy panel, where `pb0` is
//             built as busy_state[{dst_blk, slot}] and no `block` is
//             instantiated at all, so the bench and the design agree with each
//             other and neither agrees with block.v.
//
// A NAIVE CONTROL runs beside the real one: the same PB0, counted on every
// visit with no de-dup.  It is what this card would be without ADVANCE, and
// the gap between the two is the measurement that justifies the conductor.
//
// THE ERR CHECKS ARE THE POINT OF SECTION 8.  The card's six-bit check
// counter never feeds its data path; it exists only to disagree with
// SCAN/ADVANCE/START.  So the bench drives each of the three ways they can
// disagree, and -- the check that matters more -- asserts ERR stays dark
// through every other section, including thousands of real visits where the
// marker is dirtying its own probe.
`timescale 1ns/1ps

module tb_inprog #(
    // Icarus is ~100x slower and section 7 is most of the model time, so the
    // reference run takes the directed checks and the off-hook ones and
    // leaves the dialling to Verilator.  Both simulators see the same card.
    parameter integer CALLS = 1
) ();
    localparam integer HIT = 1, ID = 16, CLR = 32;
    localparam integer T_RISE = 64, T_FALL = 2048;
    localparam integer RING_ON = 200, RING_OFF = 400;
    localparam integer BRK_NS = 12_000_000, MK_NS = 8_000_000;
    localparam integer PAUSE  = 60_000_000;

    integer chk = 0, errs = 0;
    task want(input v, input string what);
        begin
            chk = chk + 1;
            if (!v) errs = errs + 1;
            $display("     %-56s %s", what, v ? "ok" : "FAIL");
        end
    endtask
    task wantn(input v, input string what, input integer got);
        begin
            chk = chk + 1;
            if (!v) errs = errs + 1;
            $display("     %-56s %s  %0d", what, v ? "ok" : "FAIL", got);
        end
    endtask

    reg clk = 0, rst_n = 0;
    always #122.0703 clk = ~clk;

    // =====================================================================
    // 1. The directed scanner
    // =====================================================================
    reg       d_oct = 0, d_pb0 = 0, d_con_n = 1, d_clr = 0;
    reg       d_adv = 0, d_start = 0;
    reg [2:0] d_scan = 3'd0;

    wire [2:0] d_hi, d_lo;
    wire [6:0] d_seg_hi, d_seg_lo;
    wire       d_ovf, d_frozen, d_err, d_pass;
    wire [6:0] d_count;

    inprog u_dir (
        .clk(clk), .rst_n(rst_n),
        .oct_stb(d_oct), .scan_port(d_scan),
        .scan_adv(d_adv), .scan_start(d_start),
        .pb0(d_pb0), .con_n(d_con_n), .clr(d_clr),
        .dig_hi(d_hi), .dig_lo(d_lo), .seg_hi(d_seg_hi), .seg_lo(d_seg_lo),
        .ovf(d_ovf), .frozen(d_frozen), .err(d_err),
        .pass_stb(d_pass), .count(d_count));

    // One visit.  ADVANCE low is a repeated visit: the scanner stood still.
    task visit(input [2:0] p, input b, input adv, input st);
        begin
            @(negedge clk);
            d_scan = p; d_pb0 = b; d_adv = adv; d_start = st; d_oct = 1'b1;
            @(negedge clk); d_oct = 1'b0; d_adv = 1'b0;
        end
    endtask

    // One complete pass of 64 ports, the first `nbusy` of them busy.
    // `rep` repeats slot 0 of every block, as a dirtied probe does: the same
    // SCAN again, with no ADVANCE.
    task dpass(input integer nbusy, input rep);
        integer b, s, n;
        begin
            n = 0;
            for (b = 0; b < 8; b = b + 1)
                for (s = 0; s < 8; s = s + 1) begin
                    if (rep && s == 0)
                        visit(s[2:0], (n < nbusy), 1'b0, (b == 0 && s == 0));
                    visit(s[2:0], (n < nbusy), 1'b1, (b == 0 && s == 0));
                    n = n + 1;
                end
        end
    endtask

    // =====================================================================
    // 2. A real exchange
    // =====================================================================
    reg  [63:0] hook = 0, tx = 0;
    wire [63:0] rx, e, port_busy;

    // Sixteen line cards: 20-27 and 30-37.
    net_site #(.OWN_E(3'd2), .OWN_B(3'd2), .DIR0(2'd2),
               .LINE_PORTS(64'h0000_0000_FFFF_0000),
               .T_RISE(T_RISE), .T_FALL(T_FALL),
               .RING_ON(RING_ON), .RING_OFF(RING_OFF),
               .HIT(HIT), .ID(ID), .CLR(CLR), .T_GUARD(16), .T_CLAIM(250),
               .NREG(4), .NMON(1), .NRES(1))
    S (.clk(clk), .rst_n(rst_n),
       .hook(hook), .tx(tx), .rx(rx), .e(e),
       .line_in(1'b0), .line_out(), .locked(),
       .frame_stb(), .ring_cad_n(), .dt_bit(), .ng_bit(),
       .mon_held(), .got_claim(), .dirs_held(),
       .fan_legs(), .res_used(), .port_busy(port_busy), .regs_busy(),
       .wq_ovf(), .n_defer(),
       .wr_stb(), .wr_dst(), .wr_src(), .wr_bsy(), .wr_clm());

    wire [2:0] r_hi, r_lo;
    wire       r_ovf, r_frozen, r_err, r_pass;
    wire [6:0] r_count;

    inprog u_dut (
        .clk(clk), .rst_n(rst_n),
        .oct_stb(S.oct_stb), .scan_port(S.scan_port),
        .scan_adv(S.u_mk.scan_adv), .scan_start(S.u_mk.scan_start),
        .pb0(S.pb_busy), .con_n(1'b1), .clr(1'b0),
        .dig_hi(r_hi), .dig_lo(r_lo), .seg_hi(), .seg_lo(),
        .ovf(r_ovf), .frozen(r_frozen), .err(r_err),
        .pass_stb(r_pass), .count(r_count));

    // ---- the naive control: every visit, no de-dup ----------------------
    integer visits = 0, nacc = 0;
    integer visits_pass = 0, naive = 0, npass = 0;
    always @(posedge clk) begin
        if (!rst_n) begin visits <= 0; nacc <= 0; end
        else begin
            if (S.oct_stb) begin
                visits <= visits + 1;
                nacc   <= nacc + (S.pb_busy ? 1 : 0);
            end
            if (r_pass) begin
                visits_pass <= visits; visits <= 0;
                naive       <= nacc;   nacc   <= 0;
                npass       <= npass + 1;
            end
        end
    end

    // Wait for a whole pass to be latched, then read.
    task settle(input integer n);
        integer i;
        begin for (i = 0; i < n; i = i + 1) @(posedge r_pass); #1; end
    endtask

    integer truth;

    initial begin
        $display("INPROG (RTL) -- the calls-in-progress display, inprogress.md.\n");
        $display("  Two octal digits, one a scan.  Port 00 is never fitted, so the");
        $display("  largest the exchange can make is 63 -- 77 octal -- and the two");
        $display("  digits hold the whole range.\n");
        #4000 rst_n = 1;
        #20_000;

        // ---- 1. the range, and both digits ------------------------------
        $display("  1. Every octal digit, in both positions:");
        begin : dec
            integer k; reg okl, okh;
            okl = 1'b1; okh = 1'b1;
            for (k = 0; k < 8; k = k + 1) begin
                dpass(k, 1'b0); dpass(k, 1'b0);
                if (d_lo !== k[2:0] || d_hi !== 3'd0) okl = 1'b0;
            end
            want(okl, "0-7 read as 00-07, the low digit alone");
            for (k = 0; k < 8; k = k + 1) begin
                dpass(k * 8, 1'b0); dpass(k * 8, 1'b0);
                if (d_hi !== k[2:0] || d_lo !== 3'd0) okh = 1'b0;
            end
            want(okh, "0,8,16..56 read as 00,10,20..70: the high digit");
        end

        dpass(63, 1'b0); dpass(63, 1'b0);
        want(d_hi === 3'o7 && d_lo === 3'o7, "63 busy reads 77, the top of the range");
        want(d_ovf === 1'b0, "and 77 is not an overflow");
        want(d_seg_hi === 7'b000_0111 && d_seg_lo === 7'b000_0111,
             "both '4511 show a 7: segments a, b, c");

        dpass(0, 1'b0); dpass(0, 1'b0);
        want(d_hi === 3'd0 && d_lo === 3'd0, "an idle exchange reads 00");
        want(d_seg_lo === 7'b011_1111, "and a 0 is six segments, not blank");
        want(d_err === 1'b0, "and ERR has stayed dark through all of it");

        // ---- 2. the overflow --------------------------------------------
        $display("\n  2. Sixty-four, which two octal digits cannot hold:");
        dpass(64, 1'b0); dpass(64, 1'b0);
        want(d_ovf === 1'b1, "64 busy lights OVF");
        want({d_hi, d_lo} === 6'd0, "and the digits roll to 00, which OVF is there to deny");

        // ---- 3. the de-dup ----------------------------------------------
        $display("\n  3. A dirtied probe repeats a visit (marker.v:485).  It must not count twice:");
        dpass(20, 1'b0); dpass(20, 1'b0);
        begin : dd
            reg [6:0] clean;
            clean = d_count;
            dpass(20, 1'b1); dpass(20, 1'b1);
            wantn(d_count === clean,
                  "the same traffic with every block's slot 0 repeated", d_count);
            $display("       clean %0d, with repeats %0d -- 72 visits, 64 counted",
                     clean, d_count);
        end

        // ---- 4. /CON ------------------------------------------------------
        $display("\n  4. The console takes the bus: SCAN no longer names what is on PB0:");
        dpass(12, 1'b0); dpass(12, 1'b0);
        begin : con
            reg [6:0] held;
            held = d_count;
            d_con_n = 1'b0;
            dpass(40, 1'b0);                        // nonsense while /CON is low
            want(d_count === held, "the display holds the last complete pass");
            want(d_frozen === 1'b1, "and lights FROZEN");
            d_con_n = 1'b1;
            dpass(12, 1'b0);
            want(d_frozen === 1'b1, "still FROZEN through the pass it re-aligns on");
            dpass(12, 1'b0); dpass(12, 1'b0);
            want(d_frozen === 1'b0 && d_count === 7'd12,
                 "a whole pass later it is live again, and right");
            want(d_err === 1'b0,
                 "and /CON is not reported as an error: it was expected");
        end

        // ---- 4a. the three signals check each other ----------------------
        $display("\n  4a. SCAN, ADVANCE and START are redundant.  Break each in turn:");
        begin : xcheck
            // (i) a jump inside a block: ADVANCE with the wrong SCAN
            d_clr = 1'b1; @(negedge clk); d_clr = 1'b0;
            dpass(4, 1'b0); dpass(4, 1'b0);
            want(d_err === 1'b0, "clean again after the reset key");
            visit(3'd0, 1'b0, 1'b1, 1'b1);            // port 00, a pass opens
            visit(3'd4, 1'b0, 1'b1, 1'b0);            // ... and SCAN jumps to 4
            want(d_err === 1'b1, "SCAN jumping inside a block lights ERR");

            // (ii) a jump of eight: the low three bits cannot see it, so the
            //      pass comes up short and START lands at the wrong count
            d_clr = 1'b1; @(negedge clk); d_clr = 1'b0;
            dpass(4, 1'b0); dpass(4, 1'b0);
            want(d_err === 1'b0, "clean again");
            begin : short
                integer b, sl;
                visit(3'd0, 1'b0, 1'b1, 1'b1);
                for (b = 0; b < 7; b = b + 1)
                    for (sl = 0; sl < 8; sl = sl + 1)
                        if (!(b == 0 && sl == 0))
                            visit(sl[2:0], 1'b0, 1'b1, 1'b0);
                visit(3'd0, 1'b0, 1'b1, 1'b1);        // START after 56, not 64
            end
            want(d_err === 1'b1, "a pass of 56 ADVANCEs lights ERR: START is early");

            // (iii) SCAN moving with no ADVANCE -- the probe moved, the
            //       scanner did not
            d_clr = 1'b1; @(negedge clk); d_clr = 1'b0;
            dpass(4, 1'b0); dpass(4, 1'b0);
            want(d_err === 1'b0, "clean again");
            visit(3'd0, 1'b0, 1'b1, 1'b1);
            visit(3'd1, 1'b0, 1'b1, 1'b0);
            visit(3'd5, 1'b0, 1'b0, 1'b0);            // repeat, but SCAN moved
            want(d_err === 1'b1, "SCAN moving with no ADVANCE lights ERR");

            d_clr = 1'b1; @(negedge clk); d_clr = 1'b0;
            want(d_err === 1'b0, "the reset key clears ERR");
            dpass(9, 1'b0); dpass(9, 1'b0);
            want(d_err === 1'b0 && d_count === 7'd9,
                 "and the card counts correctly afterwards");
        end

        // ---- 4b. a conductor dead before the card ever armed --------------
        $display("\n  4b. A conductor dead from reset -- the silent failure:");
        begin : dead
            integer k;
            d_clr = 1'b1; @(negedge clk); d_clr = 1'b0;
            want(d_frozen === 1'b1,
                 "straight after the reset key FROZEN is lit, not dark");

            // ADVANCE stuck low.  Visits arrive, PB0 says busy, nothing steps.
            for (k = 0; k < 140; k = k + 1)
                visit(k[2:0], 1'b1, 1'b0, (k % 64 == 0));
            want(d_count === 7'd0 && d_frozen === 1'b1,
                 "ADVANCE dead: blank, and FROZEN says the blank is not news");
            want(d_err === 1'b1,
                 "... and two passes later ERR lights rather than reading 00");

            // START stuck low.  The scanner runs; no pass ever opens.
            d_clr = 1'b1; @(negedge clk); d_clr = 1'b0;
            for (k = 0; k < 140; k = k + 1)
                visit(k[2:0], 1'b1, 1'b1, 1'b0);
            want(d_count === 7'd0 && d_frozen === 1'b1,
                 "START dead: blank and FROZEN");
            want(d_err === 1'b1, "... and ERR lights");

            // and the reset key does not turn a lit lamp into a silent 00
            d_clr = 1'b1; @(negedge clk); d_clr = 1'b0;
            for (k = 0; k < 140; k = k + 1)
                visit(k[2:0], 1'b1, 1'b1, 1'b0);
            want(d_err === 1'b1 && d_frozen === 1'b1,
                 "the reset key does not hide it: ERR comes back");

            d_clr = 1'b1; @(negedge clk); d_clr = 1'b0;
            dpass(5, 1'b0); dpass(5, 1'b0);
            want(d_err === 1'b0 && d_frozen === 1'b0 && d_count === 7'd5,
                 "cable good again: it arms, clears both lamps and counts");
        end

        // ---- 5. a real exchange ------------------------------------------
        $display("\n  5. Against net_site: the display, and the ports' own latches.");
        #60_000_000;
        settle(2);
        truth = $countones(port_busy);
        wantn(r_count === truth[6:0] && truth == 0,
              "idle exchange: the display and port_busy are both 0", r_count);

        // Four callers off-hook.  A caller on dial tone is a written latch.
        hook[6'o20] = 1'b1; hook[6'o30] = 1'b1;
        #150_000_000;
        settle(2);
        truth = $countones(port_busy);
        wantn(r_count === truth[6:0], "two off-hook: display == port_busy", r_count);

        hook[6'o21] = 1'b1; hook[6'o31] = 1'b1;
        #150_000_000;
        settle(2);
        truth = $countones(port_busy);
        wantn(r_count === truth[6:0], "four off-hook: display == port_busy", r_count);

        // ---- 6. the repeats are real, and the naive control over-reads ----
        $display("\n  6. What the conductor buys, measured on the same PB0:");
        settle(1);
        wantn(visits_pass > 64,
              "the marker really does repeat visits: more than 64 a pass", visits_pass);
        wantn(naive >= r_count,
              "a naive counter can only ever read high", naive);
        $display("       %0d visits a pass, 64 counted;  de-duped %0d, naive %0d",
                 visits_pass, r_count, naive);
        begin : bias
            integer i, over;
            over = 0;
            for (i = 0; i < 8; i = i + 1) begin
                settle(1);
                if (naive > r_count) over = over + 1;
                if (naive < r_count) errs = errs + 1;
            end
            wantn(over > 0,
                  "and over eight passes it does read high, at least once", over);
        end
        want(r_err === 1'b0,
             "and ERR is dark: the real marker's three signals agree");
        want(r_frozen === 1'b0,
             "and FROZEN is dark: the display is a pass, not a reset value");

        // ---- 7. two calls connected --------------------------------------
        if (CALLS) begin
        $display("\n  7. Calls up, and calls down:");
        hook = 0; #200_000_000;
        hook[6'o20] = 1'b1; #120_000_000;
        dial_from(6'o20, 2); dial_from(6'o20, 1);
        #150_000_000;
        hook[6'o21] = 1'b1;                       // 21 answers
        #120_000_000;
        settle(2);
        truth = $countones(port_busy);
        wantn(r_count === truth[6:0] && truth >= 2,
              "20 calls 21, both answered: display == port_busy", r_count);

        hook[6'o30] = 1'b1; #120_000_000;
        dial_from(6'o30, 3); dial_from(6'o30, 1);
        #150_000_000;
        hook[6'o31] = 1'b1;
        #120_000_000;
        settle(2);
        truth = $countones(port_busy);
        wantn(r_count === truth[6:0] && truth >= 4,
              "a second call: display == port_busy", r_count);

        hook = 0;
        #400_000_000;
        settle(3);
        truth = $countones(port_busy);
        wantn(r_count === truth[6:0] && truth == 0,
              "everybody on hook: the display comes back to 0", r_count);
        want(r_err === 1'b0,
             "ERR still dark, after every call this bench has made");
        $display("       a release is not a word (counters.md 4) -- this came");
        $display("       down off the ports' own latches, on the probe.");
        end else
            $display("\n  7. Calls up and down: skipped (CALLS=0).");

        $display("\n  tb_inprog: %0d checks, %0d errors.  %s",
                 chk, errs, (errs == 0) ? "PASS" : "FAIL");
        if (errs) $fatal(1);
        $finish;
    end

    task dial_from(input [5:0] p, input integer d);
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

    initial begin #40_000_000_000; $display("  TIMEOUT"); $fatal(1); end
endmodule
