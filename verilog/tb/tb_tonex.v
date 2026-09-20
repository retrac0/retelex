// tb_tonex -- the tone card plugged into the exchange.  common/tone-plan.md 4.
//
// One card in block 1 slot 0 serves every tone port: dial tone on its own C_TX
// at port 10, cannot-complete and busy punched onto the C_TX nets of the vacant
// slots at 14 and 11, and the RBT and /RING_CAD conductors off its rear
// connector (tone-plan.md 4.4).  A phone at port 20 is pointed at each in turn.
`timescale 1ns/1ps
`include "exch_defs.vh"

module tb_tonex;
    localparam integer T_RISE = 8, T_FALL = 64, RING_ON = 64, RING_OFF = 128;
    localparam P10 = 6'o10, P11 = 6'o11, P14 = 6'o14, P20 = 6'o20, P21 = 6'o21;

    reg clk = 0, rst_n = 0;
    always #122 clk = ~clk;

    reg  [63:0] ctx = 0, atx = 0, word = {64{1'b1}};
    wire [63:0] c_rx, a_rx;
    wire        frame_stb, fill, ring_cad_n;

    // ---- the control bus, as tb_mvp drives it ------------------------------
    reg         cw_req = 0; reg [5:0] cw_dst = 0, cw_src = 0;
    reg         cw_bsy = 0, cw_clm = 0;
    wire        cw_busy, sdata, sclk, wr;
    ctl_write u_con (.clk(clk), .rst_n(rst_n), .req(cw_req), .strobe(1'b1), .g(1'b1),
                     .dst(cw_dst), .src(cw_src), .bsy(cw_bsy), .clm(cw_clm),
                     .busy(cw_busy), .sdata(sdata), .sclk(sclk), .wr(wr));

    // ---- the tone card -----------------------------------------------------
    wire t_ctx, t_atx, t_ansn, t_rb, t_busy, t_cannot, t_cadn;
    tone_card #(.ROM_FILE("rtl/tone_rom.hex")) u_tone (
        .clk(clk), .frame_stb(frame_stb), .fill(fill),
        .c_tx(t_ctx), .a_tx(t_atx), .ans_n(t_ansn),
        .ringback(t_rb), .busy(t_busy), .cannot(t_cannot), .ring_cad_n(t_cadn));

    // Blocks 1 and 2.  Ports 10, 11, 14 are the tone card's; 20 and 21 are phones.
    exch_top #(.BLOCK_FITTED(8'b0000_0110),
               .PORT_FITTED(64'h0000_0000_0003_1300),
               .PORT_RINGS (64'hFFFF_FFFF_FFFF_ECFF),   // 10, 11, 14 never ring
               .RBT_IS_FILL(1'b0), .TONE_CARD(1'b1),
               .T_RISE(T_RISE), .T_FALL(T_FALL),
               .RING_ON(RING_ON), .RING_OFF(RING_OFF))
    dut (.clk(clk), .rst_n(rst_n),
         .c_tx(ctx), .a_tx(atx), .word(word), .c_rx(c_rx), .a_rx(a_rx),
         .rbt_in(t_rb), .ring_cad_n_in(t_cadn),
         .sdata(sdata), .sclk(sclk), .wr(wr),
         .pb_busy(), .pb_word(), .port_busy(), .slot(), .slotq(), .hclk(), .hb(),
         .tx_clk(), .frame_stb(frame_stb), .tx_oct(), .rx_oct(),
         .fill(fill), .ring_cad_n(ring_cad_n), .tick_1k());

    // the card's four outputs onto the slots they serve
    always @* begin
        ctx[P10] = t_ctx;                 // its own port
        ctx[P14] = t_cannot;              // punched
        ctx[P11] = t_busy;                // punched
    end

    // ---- what a caller at 20 hears, one frame behind the source ------------
    reg src_d = 0;
    reg [2:0] mode = 0;
    integer errs = 0, seen1 = 0, seen0 = 0, chk = 0, i;

    always @(posedge clk) if (frame_stb) begin
        if (mode != 0) begin
            if (c_rx[P20] !== src_d) errs = errs + 1;
            if (src_d) seen1 = seen1 + 1; else seen0 = seen0 + 1;
        end
        case (mode)
            1: src_d <= t_ctx;            // dial tone
            2: src_d <= t_cannot;         // cannot-complete
            3: src_d <= t_rb;             // ringback, off the RBT conductor
            default: src_d <= fill;
        endcase
    end

    task wait_frames(input integer n);
        begin for (i = 0; i < n; i = i + 1) @(posedge frame_stb); end
    endtask

    task wr_latch(input [5:0] pp, input [5:0] aa);
        begin
            @(negedge clk); cw_dst = pp; cw_src = aa; cw_bsy = 0; cw_clm = 0; cw_req = 1;
            @(negedge clk); cw_req = 0;
            while (cw_busy) @(negedge clk);
            wait_frames(2);
        end
    endtask

    task stage(input integer m, input string what);
        begin
            mode = 0; wait_frames(4);
            errs = 0; seen1 = 0; seen0 = 0; mode = m[2:0];
            wait_frames(2000);
            mode = 0;
            chk = chk + 1;
            if (errs == 0 && seen1 > 200 && seen0 > 200)
                $display("     %-52s ok   (%0d/%0d ones)", what, seen1, seen1 + seen0);
            else begin
                $display("     %-52s FAIL (%0d errors, %0d ones of %0d)",
                         what, errs, seen1, seen1 + seen0);
                errs = -1;
            end
        end
    endtask

    integer fails = 0;
    initial begin
        $display("\nTHE TONE CARD IN THE EXCHANGE -- one card, every tone port\n");
        wait_frames(4); rst_n = 1; wait_frames(20);

        $display("  1. A caller pointed at each tone port hears that tone");
        wr_latch(P20, P10); stage(1, "20 -> 10: dial tone, plane A ungated");
        if (errs != 0) fails = fails + 1;
        wr_latch(P20, P14); stage(2, "20 -> 14: cannot-complete, plane B by Q14");
        if (errs != 0) fails = fails + 1;

        $display("\n  2. Ringback comes off the RBT conductor, not a port");
        atx[P20] = 1;                          // 20 lifts
        wr_latch(P20, P21); wr_latch(P21, P20);   // the hotline: 21 is on-hook and rings
        stage(3, "20 -> 21 while 21 rings: the caller hears RBT");
        if (errs != 0) fails = fails + 1;

        $display("\n  3. The card owns /RING_CAD");
        chk = chk + 1;
        if (ring_cad_n === t_cadn)
            $display("     %-52s ok", "the bus conductor is the card's, not the clock card's");
        else begin
            $display("     %-52s FAIL", "the bus conductor is the card's");
            fails = fails + 1;
        end

        $display("\n  %0d checks, %0d failed.  %s\n", chk, fails, fails ? "FAIL" : "PASS");
        if (fails) $fatal(1, "tb_tonex failed");
        $finish;
    end
endmodule
