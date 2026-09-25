// tb_debug -- the debugger card: one lamp a fault, and no lamp without one.
//
// The bench sits between the exchange and the debugger and mangles ONE
// signal at a time, so each check is proved two ways: the fault it is for
// lights it, and nothing else does.  A quiet exchange, and a clean write,
// light nothing at all -- that is the check that matters most, because a
// lamp that lights on a working exchange is worse than no lamp.
//
// It is also the SCLK-hazard bench this tree did not have.  mainboard.md 7
// says one extra SCLK edge loses the write and the next clean word heals it,
// and verilog/ measured that with `make sclk`.  Here the glitch goes to the
// exchange AND the debugger: the lamp lights, the write misses its port, and
// the clean word after it lands.
`timescale 1ns/1ps
`include "exch.vh"

module tb_debug;
    integer chk = 0, errs = 0;
    task ck(input cond, input [8*64-1:0] what);
        begin chk = chk + 1;
             if (!cond) begin errs = errs + 1; $display("    FAIL  %0s", what); end
        end
    endtask

    reg clk = 1'b0, rst_n = 1'b0, clr_n = 1'b1;
    always #122.070 clk = ~clk;

    // ---- the exchange: ports 20-27 on block 2 --------------------------------
    reg  [63:0] a_tx = 64'd0;
    wire [63:0] port_busy;
    wire [2:0]  slot, slotq;
    wire ha_n, hb_n, hw_n, cap_stb, frame_stb, fill, pass_stb, tick_1k;
    wire [`SCANW-1:0] scan;

    // ---- the serialiser, driven by hand ---------------------------------------
    reg              req = 1'b0;
    reg  [`PW-1:0]   dst = 6'd0, src = 6'd0;
    reg              bsy = 1'b0;
    wire             s_busy, s_sdata, s_sclk, s_wr;
    ctl_write u_ser (
        .clk(clk), .rst_n(rst_n), .req(req), .strobe(1'b1), .g(1'b1),
        .dst(dst), .src(src), .bsy(bsy), .clm(1'b0),
        .busy(s_busy), .sdata(s_sdata), .sclk(s_sclk), .wr(s_wr));

    // ---- the faults, one at a time ---------------------------------------------
    reg f_stall = 1'b0;      // freeze SCAN (and FILL with it: same stage)
    reg f_fill  = 1'b0;      // invert FILL against SCAN[0]
    reg f_slotq = 1'b0;      // flip SLOTQ's low bit
    reg f_ha_p00 = 1'b0, f_hb_p00 = 1'b0;      // pull the wire in port 00's turn
    reg f_ha_stuck = 1'b0, f_hb_stuck = 1'b0;  // hold the wire down
    reg f_sclk = 1'b0;       // an extra SCLK pulse, into the exchange too
    reg f_wr   = 1'b0;       // a WR pulse, into the debugger only

    // the cable-B bus as both the exchange and the debugger see it
    wire bus_sclk = s_sclk | f_sclk;
    wire dbg_wr   = s_wr   | f_wr;

    exch #(.PORT_FITTED(64'h0000_0000_00FF_0000), .BLOCK_FITTED(8'b0000_0100)) u_x (
        .clk(clk), .rst_n(rst_n),
        .c_tx(64'd0), .a_tx(a_tx), .ans_n({64{1'b1}}), .word_n({64{1'b1}}),
        .c_rx(), .a_rx(), .mute_blk(8'd0), .rbt_in(1'b0),
        .sdata(s_sdata), .sclk(bus_sclk), .wr(s_wr), .hw_n(hw_n),
        .hc(), .ha_n(ha_n), .hb_n(hb_n), .tick(), .slot(slot), .slotq(slotq),
        .hclk(), .line_hb(), .cap_stb(cap_stb), .tx_clk(),
        .frame_stb(frame_stb), .clk_8k(), .rx_oct(), .oct_stb(),
        .scan(scan), .pass_stb(pass_stb),
        .fill(fill), .ring_cad_n(), .tick_1k(tick_1k), .port_busy(port_busy));

    // what the debugger sees, after the faults
    reg [`SCANW-1:0] scan_held; reg fill_held;
    always @(posedge clk) if (!f_stall) begin scan_held <= scan; fill_held <= fill; end

    wire [`SCANW-1:0] dbg_scan  = f_stall ? scan_held : scan;
    wire              dbg_fill  = f_stall ? fill_held : (fill ^ f_fill);
    wire [2:0]        dbg_slotq = slotq ^ {2'b00, f_slotq};
    wire              dbg_ha_n  = ha_n & ~(f_ha_p00 && (scan == {`SCANW{1'b0}})) & ~f_ha_stuck;
    wire              dbg_hb_n  = hb_n & ~(f_hb_p00 && (scan == {`SCANW{1'b0}})) & ~f_hb_stuck;

    wire [11:0] led;
    debugger #(.REG_WAIT_PASSES(16), .WR_GUARD(8)) u_dbg (
        .clk(clk), .rst_n(rst_n), .clr_n(clr_n),
        .slot(slot), .slotq(dbg_slotq), .cap_stb(cap_stb), .frame_stb(frame_stb),
        .scan(dbg_scan), .ha_n(dbg_ha_n), .hb_n(dbg_hb_n), .fill(dbg_fill),
        .pass_stb(pass_stb),
        .sdata(s_sdata), .sclk(bus_sclk), .wr(dbg_wr),
        .led(led));

    localparam [11:0] L_SCAN_STALL = 12'd1 << 0,  L_FILL_SCAN0 = 12'd1 << 1,
                      L_SLOTQ_LATE = 12'd1 << 2,  L_HA_P00     = 12'd1 << 3,
                      L_HB_P00     = 12'd1 << 4,  L_HA_STUCK   = 12'd1 << 5,
                      L_HB_STUCK   = 12'd1 << 6,  L_SCLK_COUNT = 12'd1 << 7,
                      L_WR_EDGE    = 12'd1 << 8,  L_SELF_POINT = 12'd1 << 9,
                      L_WR_P00     = 12'd1 << 10, L_REG_WAIT   = 12'd1 << 11;

    task passes(input integer n);
        begin repeat (n) @(posedge pass_stb); @(posedge clk); @(posedge clk); end
    endtask

    task clear;
        begin
            @(posedge clk); clr_n = 1'b0;
            @(posedge clk); @(posedge clk); clr_n = 1'b1;
            @(posedge clk);
        end
    endtask

    task lamps(input [11:0] mask, input [8*64-1:0] what);
        begin
            ck(led === mask, what);
            if (led !== mask) $display("           led = %b, wanted %b", led, mask);
        end
    endtask

    task send(input [`PW-1:0] d, input [`PW-1:0] s, input b);
        begin
            @(posedge clk); dst = d; src = s; bsy = b;
            req = 1'b1; @(posedge clk); req = 1'b0; @(posedge clk);
            while (s_busy) @(posedge clk);
            @(posedge clk); @(posedge clk);
        end
    endtask

    initial begin
        $display("\n  tb_debug -- twelve lamps, twelve faults, and a quiet exchange");
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        repeat (8) @(posedge clk);

        // ---- 0.  nothing lights on a working exchange -------------------------
        passes(4);
        lamps(12'd0, "four quiet passes light nothing");
        send(6'o22, 6'o23, 1'b1);
        passes(2);
        lamps(12'd0, "a clean write lights nothing");
        ck(port_busy[6'o22] === 1'b1, "and the clean write landed");

        // ---- 1.  CLOCK CARD -----------------------------------------------------
        f_stall = 1'b1; repeat (3) @(posedge frame_stb); @(posedge clk);
        f_stall = 1'b0; @(posedge clk); @(posedge clk);
        lamps(L_SCAN_STALL, "SCAN_STALL: the scanner froze for three frames");
        clear();

        @(posedge frame_stb); @(posedge clk);
        f_fill = 1'b1; @(posedge frame_stb); @(posedge clk);
        f_fill = 1'b0; @(posedge clk); @(posedge clk);
        lamps(L_FILL_SCAN0, "FILL_SCAN0: FILL inverted against SCAN[0]");
        clear();

        @(posedge frame_stb); @(posedge clk);
        f_slotq = 1'b1; @(posedge frame_stb); @(posedge clk);
        f_slotq = 1'b0; @(posedge clk); @(posedge clk);
        lamps(L_SLOTQ_LATE, "SLOTQ_LATE: SLOTQ off by one at the captures");
        clear();

        // ---- 2.  THE PLANE --------------------------------------------------------
        f_ha_p00 = 1'b1; passes(2); f_ha_p00 = 1'b0; passes(1);
        lamps(L_HA_P00, "HA_P00: /HA pulled in port 00's turn, and only that");
        clear();

        f_hb_p00 = 1'b1; passes(2); f_hb_p00 = 1'b0; passes(1);
        lamps(L_HB_P00, "HB_P00: /HB pulled in port 00's turn, and only that");
        clear();

        // stuck: held from just after a pass boundary through two whole passes,
        // which is short of REG_WAIT.  It lights the P00 lamp as well, and must
        @(posedge pass_stb); @(posedge clk);
        f_ha_stuck = 1'b1; passes(2); f_ha_stuck = 1'b0; passes(1);
        lamps(L_HA_STUCK | L_HA_P00, "HA_STUCK: a drain held on for two passes");
        clear();

        @(posedge pass_stb); @(posedge clk);
        f_hb_stuck = 1'b1; passes(2); f_hb_stuck = 1'b0; passes(1);
        lamps(L_HB_STUCK | L_HB_P00, "HB_STUCK: the same on /HB");
        clear();

        // ---- 3.  CABLE B ------------------------------------------------------------
        // mainboard.md 7: one extra SCLK edge, mid-word, into the exchange too
        @(posedge clk); dst = 6'o25; src = 6'o12; bsy = 1'b1;
        req = 1'b1; @(posedge clk); req = 1'b0;
        repeat (5) @(posedge bus_sclk);
        @(negedge bus_sclk); repeat (4) @(posedge clk);
        f_sclk = 1'b1; repeat (4) @(posedge clk); f_sclk = 1'b0;
        while (s_busy) @(posedge clk);
        passes(1);
        lamps(L_SCLK_COUNT, "SCLK_COUNT: seventeen edges at WR");
        ck(port_busy[6'o25] === 1'b0, "and the glitched write MISSED its port");
        clear();
        send(6'o25, 6'o12, 1'b1);
        passes(1);
        lamps(12'd0, "the next clean word lights nothing");
        ck(port_busy[6'o25] === 1'b1, "and it LANDED: the '164s have no stored phase");

        // mainboard.md 2.3.2: a WR right on an SCLK edge, into the debugger only
        @(posedge clk); dst = 6'o22; src = 6'o23; bsy = 1'b1;
        req = 1'b1; @(posedge clk); req = 1'b0;
        // three ticks after the sixteenth rise: inside the eight-tick guard,
        // and clear of the edge's own tick so the count has taken it
        repeat (16) @(posedge bus_sclk);
        repeat (3) @(posedge clk); f_wr = 1'b1; repeat (4) @(posedge clk); f_wr = 1'b0;
        while (s_busy) @(posedge clk);
        passes(1);
        lamps(L_WR_EDGE, "WR_EDGE: WR three ticks after an SCLK edge");
        clear();

        // ---- 4.  THE MARKER ---------------------------------------------------------
        send(6'o23, 6'o23, 1'b1);
        passes(1);
        lamps(L_SELF_POINT, "SELF_POINT: a port told to listen to itself");
        clear();

        send(6'o00, 6'o23, 1'b1);
        passes(1);
        lamps(L_WR_P00, "WR_P00: a write to the port that is never fitted");
        clear();

        // a phone lifts and there is no marker in this bench to take it
        a_tx[6'o20] = 1'b1;
        passes(16 + 2);
        lamps(L_REG_WAIT, "REG_WAIT: lifted, unserved, sixteen passes");
        a_tx[6'o20] = 1'b0;
        clear();
        passes(3);
        lamps(12'd0, "and on-hook again, nothing");

        $display("\n  %0d checks, %0d errors.  %s\n", chk, errs,
                 (errs == 0) ? "PASS" : "FAIL");
        if (errs) $fatal(1);
        $finish;
    end

    initial begin #400_000_000; $display("  TIMEOUT"); $fatal(1); end
endmodule
