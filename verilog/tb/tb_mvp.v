// tb_mvp -- exchange/docs/mvp-ex.md: the minimum that makes calls.
//
// Block 2 alone, port circuits at 20 and 21, no tones, no ringback card, no
// trunks, no marker.  Two things are checked:
//
//   mvp-ex.md 2   everything absent reads as idle -- an absent block, an empty
//                 slot and a cleared latch all give FILL and A = 0
//   mvp-ex.md 6.3 the latches written by hand are a hotline: lift one phone and
//                 the other rings, answer, talk, hang up in either order, and
//                 both latches clear themselves.  A manual board with no marker.
//
// The release detectors and the ring cadence are scaled by 64 so the run is
// seconds and not hours; the ratios are the design's (16:256 ms, 2:4 s).
`timescale 1ns/1ps

module tb_mvp;
    localparam P20 = 6'o20, P21 = 6'o21;
    localparam integer T_RISE = 16, T_FALL = 256;    // 16 ms : 256 ms, /64
    localparam integer RING_ON = 200, RING_OFF = 400;

    reg          clk = 0, rst_n = 0;
    reg  [63:0]  ctx = 0, atx = 0, word = 0;
    wire [63:0]  c_rx, a_rx;

    // The operator's console, on the serial control bus: the same sixteen-bit
    // word the marker sends (exch-mainboard.md 2.3), driven by hand.
    reg        cw_req = 0, cw_bsy = 0, cw_clm = 0;
    reg  [5:0] cw_dst = 0, cw_src = 0;
    wire       cw_busy, sdata, sclk, wr;
    ctl_write u_con (.clk(clk), .rst_n(rst_n), .req(cw_req), .strobe(1'b1), .g(1'b1),
                     .dst(cw_dst), .src(cw_src), .bsy(cw_bsy), .clm(cw_clm),
                     .busy(cw_busy), .sdata(sdata), .sclk(sclk), .wr(wr));
    wire         frame_stb, fill, ring_cad_n;

    integer      errs = 0, fcount = 0, chk = 0;
    reg  [2:0]   mode = 0;
    reg          fill_d = 0;

    // The MVP, exactly as mvp-ex.md 1 fits it.
    exch_top #(.BLOCK_FITTED(8'b0000_0100),
               .PORT_FITTED(64'h0000_0000_0003_0000),
               .PORT_RINGS({64{1'b1}}),          // /ANS open: plain line cards
               .RBT_IS_FILL(1'b1),               // no ringback card
               .T_RISE(T_RISE), .T_FALL(T_FALL),
               .RING_ON(RING_ON), .RING_OFF(RING_OFF))
    dut (.clk(clk), .rst_n(rst_n),
         .c_tx(ctx), .a_tx(atx), .word(word), .c_rx(c_rx), .a_rx(a_rx),
         .sdata(sdata), .sclk(sclk), .wr(wr),
         .pb_busy(), .pb_word(), .port_busy(), .slot(), .slotq(), .hclk(), .hb(),
         .tx_clk(), .frame_stb(frame_stb), .tx_oct(), .rx_oct(),
         .fill(fill), .ring_cad_n(ring_cad_n), .tick_1k());

    always #122 clk = ~clk;

    // The two line cards send fresh speech every frame, and every check is made
    // at the frame edge -- the one place a card ever samples C_RX.
    always @(posedge clk) if (frame_stb) begin
        case (mode)
        1: begin  // 20 pointed at something absent: FILL and A = 0
               if (c_rx[P20] !== fill_d) errs = errs + 1;
               if (a_rx[P20] !== 1'b0)   errs = errs + 1;
               chk = chk + 2;
           end
        2: begin  // 21 being rung: A_RX in cadence, and the caller hears RBT (= FILL)
               if (a_rx[P21] !== ~ring_cad_n) errs = errs + 1;
               if (c_rx[P20] !== fill_d)      errs = errs + 1;
               chk = chk + 2;
           end
        3: begin  // answered: speech both ways, A steady high at both ends
               if (c_rx[P20] !== ctx[P21]) errs = errs + 1;
               if (c_rx[P21] !== ctx[P20]) errs = errs + 1;
               if (a_rx[P20] !== 1'b1)  errs = errs + 1;
               if (a_rx[P21] !== 1'b1)  errs = errs + 1;
               chk = chk + 4;
           end
        5: begin  // 20 being rung instead: the second call goes the other way
               if (a_rx[P20] !== ~ring_cad_n) errs = errs + 1;
               if (c_rx[P21] !== fill_d)      errs = errs + 1;
               chk = chk + 2;
           end
        4: begin  // both released: both latches cleared, so both listen to port 00
               if (c_rx[P20] !== fill_d) errs = errs + 1;
               if (c_rx[P21] !== fill_d) errs = errs + 1;
               if (a_rx[P20] !== 1'b0)   errs = errs + 1;
               if (a_rx[P21] !== 1'b0)   errs = errs + 1;
               chk = chk + 4;
           end
        endcase
        fill_d <= fill;
        ctx[P20] <= $random; ctx[P21] <= $random;
        fcount = fcount + 1;
    end

    task wait_frames(input integer n);
        integer target;
        begin target = fcount + n; while (fcount < target) @(posedge clk); #1; end
    endtask

    task wr_latch(input [5:0] pp, input [5:0] aa);
        begin
            @(posedge clk); #1;
            cw_dst = pp; cw_src = aa; cw_bsy = 1; cw_clm = 0; cw_req = 1;
            @(posedge clk); #1; cw_req = 0;
            wait (cw_busy); wait (!cw_busy);
        end
    endtask

    task stage(input integer n, input [2:0] mm, input string what);
        integer e0;
        begin
            e0 = errs; mode = mm; wait_frames(n); mode = 0;
            $display("     %-52s %s", what, (errs == e0) ? "ok" : "FAIL");
        end
    endtask

    initial begin
        $display("MVP (RTL) -- block 2 alone, ports 20 and 21, no tones, no marker.\n");
        repeat (4) @(posedge clk);
        rst_n = 1;
        wait_frames(4);

        $display("  2. Everything absent reads as idle.");
        wr_latch(P20, 6'o00); wait_frames(3);   // block 0 not fitted
        stage(40, 1, "20 -> 00, an absent block");
        wr_latch(P20, 6'o37); wait_frames(3);   // block 3 not fitted
        stage(40, 1, "20 -> 37, another absent block");
        wr_latch(P20, 6'o25); wait_frames(3);   // fitted block, unpopulated slot
        stage(40, 1, "20 -> 25, an empty slot in block 2");

        $display("\n  6.3 The latches written by hand are a hotline.");
        wr_latch(P20, P21);
        wr_latch(P21, P20);
        wait_frames(4);

        atx[P20] = 1'b1;                        // 20 lifts
        wait_frames(T_RISE + 4);
        stage(2 * (RING_ON + RING_OFF), 2, "20 lifts: 21 rings in cadence, 20 hears RBT");

        atx[P21] = 1'b1;                        // 21 answers
        wait_frames(T_RISE + 4);
        stage(200, 3, "21 answers: speech both ways, ringing stops");

        atx[P21] = 1'b0;                        // 21 hangs up first
        wait_frames(T_FALL + 8);
        stage(100, 4, "21 hangs up: both ports clear their own latch");

        // and again, released caller-first, with 20 still off-hook throughout
        atx[P20] = 1'b0;
        wait_frames(T_FALL + 8);
        wr_latch(P20, P21); wr_latch(P21, P20);
        atx[P21] = 1'b1;                        // 21 lifts this time
        wait_frames(T_RISE + 4);
        stage(2 * (RING_ON + RING_OFF), 5, "21 lifts: 20 rings in cadence, 21 hears RBT");
        atx[P20] = 1'b1;
        wait_frames(T_RISE + 4);
        stage(200, 3, "20 answers: speech both ways");
        atx[P21] = 1'b0;                        // caller hangs up first
        wait_frames(T_FALL + 8);
        stage(100, 4, "caller hangs up first: both latches idle");

        $display("\n  %0d checks, %0d errors.  %s", chk, errs, (errs == 0) ? "PASS" : "FAIL");
        $finish;
    end
endmodule
