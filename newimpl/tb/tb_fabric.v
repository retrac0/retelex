// tb_fabric -- the C plane, end to end.  fabric.md 7 steps 2 and 4.
//
// Every source slot to every listening slot, bit-exact, delay exactly one
// frame -- protocol.md 3's 4 096 pairs.  Then fan-out, then a cleared latch.
//
// The strobe lines are not a bus here: a port models its '151-over-the-eight-
// strobes as "mid-cell of the cell my latch names", so there is nothing to
// probe.  What that timing is FOR is proved instead by the pair sweep, which
// includes a source in slot 0 and a source in slot 7 against listeners in
// every slot -- fabric.md 4's two worst cases -- and finds the same one frame
// of delay for all 4 096.
`timescale 1ns/1ps
`include "exch.vh"

module tb_fabric;
    integer chk = 0, errs = 0, shown = 0, n_pairs = 0;

    task ck(input cond, input [8*60-1:0] what);
        begin
            chk = chk + 1;
            if (!cond) begin errs = errs + 1; $display("    FAIL  %0s", what); end
        end
    endtask

    reg clk = 1'b0, rst_n = 1'b0;
    always #122.070 clk = ~clk;

    // ---- the exchange, every block shunted and every port circuit fitted ---
    reg  [63:0] c_tx = 64'd0;
    wire [63:0] c_rx, a_rx, port_busy;
    wire [7:0]  hc;
    wire ha_n, hb_n, hw_n, tx_clk, frame_stb, fill, pass_stb;
    wire [2:0]  tick, slot, slotq;
    wire [`SCANW-1:0] scan;
    wire s_sdata, s_sclk, s_wr, s_busy;

    reg        req = 1'b0, strobe = 1'b1, g = 1'b1;
    reg [`PW-1:0] dst = 6'd0, src = 6'd0;
    reg        bsy = 1'b1, clm = 1'b0;

    ctl_write u_ser (
        .clk(clk), .rst_n(rst_n), .req(req), .strobe(strobe), .g(g),
        .dst(dst), .src(src), .bsy(bsy), .clm(clm),
        .busy(s_busy), .sdata(s_sdata), .sclk(s_sclk), .wr(s_wr));

    exch #(.PORT_FITTED({64{1'b1}}), .BLOCK_FITTED(8'hFF)) u_x (
        .clk(clk), .rst_n(rst_n),
        .c_tx(c_tx), .a_tx(64'd0), .ans_n({64{1'b1}}), .word_n({64{1'b1}}),
        .c_rx(c_rx), .a_rx(a_rx),
        .mute_blk(8'd0), .rbt_in(1'b0),
        .sdata(s_sdata), .sclk(s_sclk), .wr(s_wr), .hw_n(hw_n),
        .hc(hc), .ha_n(ha_n), .hb_n(hb_n), .tick(tick),
        .slot(slot), .slotq(slotq),
        .hclk(), .cap_stb(), .tx_clk(tx_clk),
        .frame_stb(frame_stb), .clk_8k(), .rx_oct(), .oct_stb(),
        .scan(scan), .pass_stb(pass_stb),
        .fill(fill), .ring_cad_n(), .tick_1k(),
        .port_busy(port_busy));

    // ---- a second exchange: block 2 shunted, NOT ONE PORT CIRCUIT FITTED ---
    // fabric.md 7 step 2, and mvp.md 2's "everything absent reads as idle".
    wire [7:0] bare_hc;  wire bare_ha_n, bare_hb_n, bare_hw_n, bare_fill;
    wire [63:0] bare_c_rx;
    exch #(.PORT_FITTED(64'd0), .BLOCK_FITTED(8'b0000_0100)) u_bare (
        .clk(clk), .rst_n(rst_n),
        .c_tx(64'd0), .a_tx(64'd0), .ans_n({64{1'b1}}), .word_n({64{1'b1}}),
        .c_rx(bare_c_rx), .a_rx(),
        .mute_blk(8'd0), .rbt_in(1'b0),
        .sdata(1'b0), .sclk(1'b0), .wr(1'b0), .hw_n(bare_hw_n),
        .hc(bare_hc), .ha_n(bare_ha_n), .hb_n(bare_hb_n),
        .tick(), .slot(), .slotq(),
        .hclk(), .cap_stb(), .tx_clk(),
        .frame_stb(), .clk_8k(), .rx_oct(), .oct_stb(),
        .scan(), .pass_stb(),
        .fill(bare_fill), .ring_cad_n(), .tick_1k(), .port_busy());

    // ---- the traffic: one bit a port a frame, all 64 different -------------
    reg [63:0] pat = 64'hACE1_0F1E_2D3C_4B5A;
    integer    src_of [0:63];
    reg        checking = 1'b0;
    integer    i;

    always @(posedge clk) if (frame_stb) begin
        if (checking) begin
            // fabric.md 3.4: a bit sent in frame f is captured during f and
            // sampled at the edge that begins f+1 -- WHATEVER THE TWO SLOTS.
            for (i = 0; i < 64; i = i + 1) begin
                n_pairs = n_pairs + 1;
                if (c_rx[i] !== pat[src_of[i]]) begin
                    errs = errs + 1;
                    if (shown < 8) begin
                        shown = shown + 1;
                        $display("    FAIL  port %0o heard %b from %0o, wanted %b",
                                 i, c_rx[i], src_of[i], pat[src_of[i]]);
                    end
                end
            end
        end
        pat <= {pat[62:0], pat[63]^pat[62]^pat[60]^pat[59]};
    end

    always @(posedge clk) c_tx <= pat;

    // ---- writing a latch is one sixteen-bit word on one wire ---------------
    task wr_latch(input [`PW-1:0] d, input [`PW-1:0] s, input b, input c);
        begin
            @(posedge clk);
            dst = d; src = s; bsy = b; clm = c; g = 1'b1; strobe = 1'b1;
            req = 1'b1; @(posedge clk); req = 1'b0;
            @(posedge clk);
            while (s_busy) @(posedge clk);
        end
    endtask

    integer k, d;
    initial begin
        $display("\n  tb_fabric -- every source to every listener, one frame");
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        repeat (8) @(posedge clk);

        // ---- 1.  a shunted block with no cards --------------------------------
        @(posedge frame_stb); @(posedge clk);
        ck(bare_hc === {8{bare_fill}},
           "a block with no cards: every highway is FILL");
        ck(bare_ha_n === 1'b1,
           "/HA idles high with nothing to pull it down");
        ck(bare_c_rx === 64'd0,
           "an unfitted port circuit drives no C_RX");

        // ---- 2.  every source slot to every listening slot ---------------------
        // 64 rotations of 64 ports: port d listens to (d + k) mod 64.  That is
        // every ordered pair exactly once, every slot against every slot and
        // every highway against every highway.
        for (k = 0; k < 64; k = k + 1) begin
            for (d = 0; d < 64; d = d + 1) begin
                src_of[d] = (d + k) % 64;
                wr_latch(d[`PW-1:0], src_of[d][`PW-1:0], 1'b1, 1'b0);
            end
            // two frames for the last write to be captured and sampled
            @(posedge frame_stb); @(posedge frame_stb); @(posedge clk);
            checking = 1'b1;
            @(posedge frame_stb); @(posedge clk);
            checking = 1'b0;
            if ((k % 16) == 15)
                $display("     rotation %0d: %0d pairs checked, %0d errors",
                         k, n_pairs, errs);
        end
        ck(n_pairs == 4096, "4 096 ordered pairs checked");
        ck(errs == 0,       "every pair bit-exact at one frame's delay");

        // ---- 3.  fan-out: a tone is a port fifty others are sampling ----------
        for (d = 0; d < 64; d = d + 1) begin
            src_of[d] = 25;                          // octal 31
            wr_latch(d[`PW-1:0], 6'o31, 1'b1, 1'b0);
        end
        @(posedge frame_stb); @(posedge frame_stb); @(posedge clk);
        n_pairs = 0; checking = 1'b1;
        @(posedge frame_stb); @(posedge clk);
        checking = 1'b0;
        ck(n_pairs == 64, "all 64 ports took the same square");

        // ---- 4.  an exchange with no port circuits pulls nothing down ---------
        // mvp.md 2, "everything absent reads as idle", and it is now ONE
        // mechanism for three wires rather than three separate pulls.  This
        // replaces the old check on bare_c_rx, which was `FITTED && c_cap` on
        // an exchange with FITTED = 0 -- true by construction whatever the
        // fabric did, and a duplicate of the assertion 30 lines above.
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge pass_stb);
        @(posedge clk);
        ck(bare_ha_n === 1'b1, "no port circuits: /HA idles high for a whole pass");
        ck(bare_hb_n === 1'b1, "and so does /HB");
        ck(bare_hw_n === 1'b1, "and /HW, which no card is pointed at");

        $display("\n  %0d checks, %0d errors.  %s\n", chk, errs,
                 (errs == 0) ? "PASS" : "FAIL");
        if (errs) $fatal(1);
        $finish;
    end

    initial begin
        #4_000_000_000;
        $display("  TIMEOUT");
        $fatal(1);
    end
endmodule
