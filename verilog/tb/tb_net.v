// tb_net -- two exchanges, one MF8 link, and calls that are DIALLED.
//
// Exchange A is code 2 2, exchange B is code 2 3.  Each has a marker, one
// register and one monitor, and knows its own code from two jumpers and
// nothing else: no route table, no translation, nothing that says where
// anything is.
//
//   local     20 dials 2 1            -- no trunk is touched
//   network   20 dials 1 2 3 2 1      -- exch-network.md 3's pulse flood:
//             the key seizes a trunk pointed at the caller, the caller's own
//             pulses go down it live, B's monitor hears e then b, claims, and
//             B's marker gives a register the trunk -- which is a line there now
//   own code  20 dials 1 2 2 2 1      -- the trunk is released and the call
//             carries on locally
//   nobody    20 dials 1 2 4 2 1      -- no exchange claims: cannot-complete
`timescale 1ns/1ps

module tb_net;
    // The register's windows, and the dial, scaled by 8 from register.md 2 so a
    // run is seconds: HIT 1 ms, ID 16 ms, CLR 32 ms, and a dial at 50 pps 60/40.
    localparam integer HIT = 1, ID = 16, CLR = 32;
    localparam integer T_RISE = 64, T_FALL = 2048;     // 1 ms and 32 ms, in frames
    localparam integer RING_ON = 200, RING_OFF = 400;
    localparam integer BRK_NS = 12_000_000, MK_NS = 8_000_000;   // 50 pps, 60 % break
    localparam integer PAUSE  = 60_000_000;            // between digits
    localparam integer FR = 15625;

    reg clk_a = 0, clk_b = 0, rst_n = 0;
    always #122.0703 clk_a = ~clk_a;
    initial begin #40; forever #122.0703 clk_b = ~clk_b; end

    wire la_out, lb_out, lock_a, lock_b, fs_a, fs_b, rc_a, rc_b;
    wire dt_a, ng_a, dt_b, ng_b, mh_a, mh_b, gc_a, gc_b;

    reg  [63:0] hk_a = 0, hk_b = 0;
    reg  [63:0] tx_a = 0, tx_b = 0;
    wire [63:0] rx_a, rx_b;
    wire [63:0] ln_a, ln_b;

    net_site #(.OWN_E(3'd2), .OWN_B(3'd2), .T_RISE(T_RISE), .T_FALL(T_FALL),
               .RING_ON(RING_ON), .RING_OFF(RING_OFF),
               .HIT(HIT), .ID(ID), .CLR(CLR), .T_GUARD(16), .T_CLAIM(250))
    A (.clk(clk_a), .rst_n(rst_n),
       .hook(hk_a), .tx(tx_a), .rx(rx_a), .e(ln_a),
       .line_in(lb_out), .line_out(la_out), .locked(lock_a),
       .frame_stb(fs_a), .ring_cad_n(rc_a), .dt_bit(dt_a), .ng_bit(ng_a),
       .mon_held(mh_a), .got_claim(gc_a), .dirs_held(),
       .fan_legs(), .res_used(), .port_busy(), .regs_busy(), .wq_ovf(), .n_defer(),
       .wr_stb(), .wr_dst(), .wr_src(), .wr_bsy(), .wr_clm());

    net_site #(.OWN_E(3'd2), .OWN_B(3'd3), .DIR0(2'd3), .G0(1'b1),
               .T_RISE(T_RISE), .T_FALL(T_FALL),
               .RING_ON(RING_ON), .RING_OFF(RING_OFF),
               .HIT(HIT), .ID(ID), .CLR(CLR), .T_GUARD(16), .T_CLAIM(250))
    B (.clk(clk_b), .rst_n(rst_n),
       .hook(hk_b), .tx(tx_b), .rx(rx_b), .e(ln_b),
       .line_in(la_out), .line_out(lb_out), .locked(lock_b),
       .frame_stb(fs_b), .ring_cad_n(rc_b), .dt_bit(dt_b), .ng_bit(ng_b),
       .mon_held(mh_b), .got_claim(gc_b), .dirs_held(),
       .fan_legs(), .res_used(), .port_busy(), .regs_busy(), .wq_ovf(), .n_defer(),
       .wr_stb(), .wr_dst(), .wr_src(), .wr_bsy(), .wr_clm());

    reg path_en = 0;
    bitpath p_a20b21 (.src_clk(clk_a), .src_fs(fs_a), .src_bit(tx_a[6'o20]),
                      .dst_clk(clk_b), .dst_fs(fs_b), .dst_bit(rx_b[6'o21]), .enable(path_en));
    bitpath p_b21a20 (.src_clk(clk_b), .src_fs(fs_b), .src_bit(tx_b[6'o21]),
                      .dst_clk(clk_a), .dst_fs(fs_a), .dst_bit(rx_a[6'o20]), .enable(path_en));
    bitpath p_a20a21 (.src_clk(clk_a), .src_fs(fs_a), .src_bit(tx_a[6'o20]),
                      .dst_clk(clk_a), .dst_fs(fs_a), .dst_bit(rx_a[6'o21]), .enable(path_en));
    // which tone card is the caller listening to?  Found, not assumed.
    reg tone_en = 0;
    bitpath p_dt (.src_clk(clk_a), .src_fs(fs_a), .src_bit(dt_a),
                  .dst_clk(clk_a), .dst_fs(fs_a), .dst_bit(rx_a[6'o20]), .enable(tone_en));
    bitpath p_ng (.src_clk(clk_a), .src_fs(fs_a), .src_bit(ng_a),
                  .dst_clk(clk_a), .dst_fs(fs_a), .dst_bit(rx_a[6'o20]), .enable(tone_en));

    always @(posedge clk_a) if (fs_a) begin
        if (hk_a[6'o20]) tx_a[6'o20] <= $random; if (hk_a[6'o21]) tx_a[6'o21] <= $random; end
    always @(posedge clk_b) if (fs_b) begin
        if (hk_b[6'o20]) tx_b[6'o20] <= $random; if (hk_b[6'o21]) tx_b[6'o21] <= $random; end

    integer errs = 0, chk = 0;


    task want(input v, input string what);
        begin
            chk = chk + 1;
            if (!v) begin errs = errs + 1; $display("     %-52s FAIL", what); end
            else $display("     %-52s ok", what);
        end
    endtask

    // A's line 20 dials one digit: n breaks, ten for a 0.
    task dial(input integer d);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                hk_a[6'o20] = 1'b0; #(BRK_NS);
                hk_a[6'o20] = 1'b1; #(MK_NS);
            end
            #(PAUSE);
        end
    endtask

    // Is the caller listening to a given tone card?  bitpath finds the delay.
    task hears(input integer which, input string what);
        begin
            p_dt.clear; p_ng.clear;
            tone_en = 1; #(3_000_000); tone_en = 0;
            chk = chk + 1;
            if ((which == 0 && p_dt.best_errs() == 0 && p_ng.best_errs() != 0) ||
                (which == 1 && p_ng.best_errs() == 0 && p_dt.best_errs() != 0))
                $display("     %-52s ok", what);
            else begin
                errs = errs + 1;
                $display("     %-52s FAIL  (dial tone %0d wrong, cannot-complete %0d wrong, of %0d)",
                         what, p_dt.best_errs(), p_ng.best_errs(), p_dt.nbits);
            end
        end
    endtask

    task ring_b21(input integer n, input string what);
        integer i, hi, lo;
        begin
            hi = 0; lo = 0;
            for (i = 0; i < n; i = i + 1) begin
                #(FR);
                if (ln_b[6'o21] && !rc_b) hi = hi + 1;
                if (!ln_b[6'o21] && rc_b) lo = lo + 1;
            end
            chk = chk + 1;
            if (hi > n/4 && lo > n/4) $display("     %-52s ok", what);
            else begin errs = errs + 1;
                $display("     %-52s FAIL (%0d/%0d)", what, hi, lo); end
        end
    endtask

    task ring_a21(input integer n, input string what);
        integer i, hi, lo;
        begin
            hi = 0; lo = 0;
            for (i = 0; i < n; i = i + 1) begin
                #(FR);
                if (ln_a[6'o21] && !rc_a) hi = hi + 1;
                if (!ln_a[6'o21] && rc_a) lo = lo + 1;
            end
            chk = chk + 1;
            if (hi > n/4 && lo > n/4) $display("     %-52s ok", what);
            else begin errs = errs + 1;
                $display("     %-52s FAIL (%0d/%0d)", what, hi, lo); end
        end
    endtask

    initial begin
        $display("NET (RTL) -- exchange 22 and exchange 23, one MF8 link, dialled calls.\n");
        #4000 rst_n = 1;
        wait (lock_a && lock_b);
        $display("  0. The link is up; both exchanges idle.\n");

        // ---- 1. a local call, dialled ---------------------------------
        $display("  1. A's 20 dials 2 1 -- a local call, no trunk touched.");
        hk_a[6'o20] = 1;                                    // lift
        #(40_000_000);
        hears(0, "20 is given a register and hears dial tone");
        dial(2); dial(1);
        #(60_000_000);
        ring_a21(2 * (RING_ON + RING_OFF), "A's 21 rings, in cadence");
        hk_a[6'o21] = 1;                                    // 21 answers
        #(20_000_000);
        want(ln_a[6'o20] && ln_a[6'o21], "answered: E steady at both");
        path_en = 1; #(6_000_000); path_en = 0;
        p_a20a21.report("speech 20 -> 21, inside A");
        chk = chk + 1; if (p_a20a21.best_err != 0) errs = errs + 1;
        hk_a[6'o21] = 0; hk_a[6'o20] = 0; #(80_000_000);
        want(!ln_a[6'o20] && !ln_a[6'o21], "both released");

        // ---- 2. a network call, dialled -------------------------------
        $display("\n  2. A's 20 dials 1 2 3 2 1 -- the pulse flood to exchange 23.");
        hk_a[6'o20] = 1;
        #(40_000_000);
        dial(1);                                     // the key: seize and flood
        #(4_000_000);
        want(mh_b, "B's monitor caught the seizure (it saw the rise)");
        dial(2);                                     // e
        dial(3);                                     // b -- B's own: CLAIM
        #(4_000_000);
        want(gc_a, "the claim came back: backward A at the origin");
        dial(2); dial(1);                            // h s, read by B's register
        #(80_000_000);
        ring_b21(2 * (RING_ON + RING_OFF), "B's 21 rings, from a caller on A");
        hk_b[6'o21] = 1;                                    // B's 21 answers
        #(20_000_000);
        want(ln_b[6'o21], "answered at B");
        p_a20b21.clear; p_b21a20.clear;
        path_en = 1; #(6_000_000); path_en = 0;
        p_a20b21.report("speech A20 -> B21, over the trunk");
        p_b21a20.report("speech B21 -> A20, over the trunk");
        chk = chk + 2;
        if (p_a20b21.best_err != 0 || p_b21a20.best_err != 0) errs = errs + 1;
        hk_b[6'o21] = 0; hk_a[6'o20] = 0; #(80_000_000);
        want(!ln_a[6'o20] && !ln_b[6'o21], "release runs through every patch at once");

        // ---- 3. our own code ------------------------------------------
        $display("\n  3. A's 20 dials 1 2 2 2 1 -- its OWN code: the trunk is released.");
        hk_a[6'o20] = 1; #(40_000_000);
        dial(1); dial(2); dial(2);
        #(20_000_000);
        want(!mh_b, "B's monitor heard e b, not its own, and let go");
        dial(2); dial(1);
        #(60_000_000);
        ring_a21(2 * (RING_ON + RING_OFF), "A's own 21 rings: the call went local");
        hk_a[6'o21] = 1; #(20_000_000);
        want(ln_a[6'o20] && ln_a[6'o21], "answered locally");
        hk_a[6'o21] = 0; hk_a[6'o20] = 0; #(80_000_000);

        // ---- 4. a code nobody has -------------------------------------
        $display("\n  4. A's 20 dials 1 2 4 2 1 -- no exchange 24 exists.");
        hk_a[6'o20] = 1; #(40_000_000);
        dial(1); dial(2); dial(4); dial(2); dial(1);
        #(300_000_000);                              // past the origin's claim timeout
        hears(1, "no claim: the caller gets cannot-complete");
        hk_a[6'o20] = 0; #(80_000_000);
        want(!ln_a[6'o20], "and the port released itself");

        $display("\n  %0d checks, %0d errors.  %s", chk, errs, (errs == 0) ? "PASS" : "FAIL");
        $finish;
    end

    initial begin #4_000_000_000; $display("  TIMEOUT"); $finish; end
endmodule
