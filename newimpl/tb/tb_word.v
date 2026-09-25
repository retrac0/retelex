// tb_word -- reading a card's word off /HW.  extensions.md 2.2, baseband.md 3.5.
//
// A master points at a port with a word on cable B (WR suppressed) and reads
// the eight frames that follow.  Fitted: a plain line card at 20 (its word
// pin grounded), an empty port circuit at 21, a baseband trunk at 11 facing
// east with glare, and nothing at all on block 5.
//
// What it proves: a trunk reads its own class, glare and direction; a plain
// line reads all ones; an empty socket, an unfitted block, a card still held
// off by its power-up RC and a trunk whose fifth conductor is cut all read
// ALL ZEROS -- /HW fails safe; a read at any phase of the octet reads the same
// word; a read writes nothing; and a read holds cable B about 250 us.
//
// Two faults on the wire, each paired with the check it is for, so the check
// is shown able to fail in the same run: /HW one frame late into the reader,
// and /HW read at its wire level rather than inverted.
//
// Does not cover: the secondary byte (the socket cannot mark sixteen frames),
// two masters on the bus (tb_net), or any card but these three.
`timescale 1ns/1ps
`include "exch.vh"

module tb_word;
    integer chk = 0, errs = 0;
    task ck(input cond, input [8*64-1:0] what);
        begin chk = chk + 1;
             if (!cond) begin errs = errs + 1; $display("    FAIL  %0s", what); end
        end
    endtask

    reg clk = 1'b0, rst_n = 1'b0;
    always #122.070 clk = ~clk;

    localparam [`PW-1:0] T = 6'o11, L = 6'o20, E = 6'o21, U = 6'o50;
    // the trunk's jumpers: direction E (2), glare, class trunk
    localparam [7:0] TW = {2'd2, 1'b1, 3'b010, 2'b11};

    // ---- the exchange ----------------------------------------------------------
    wire [63:0] c_rx, a_rx, port_busy;
    wire ha_n, hb_n, hw_n, frame_stb, fill, cap_stb, tick_1k, tx_clk, clk_8k, rx_oct;
    wire [2:0] slot, slotq;
    wire [`SCANW-1:0] scan;
    wire b_sdata, b_sclk, b_wr, b_oe;

    reg  [63:0] word_n = {64{1'b1}};
    reg  [63:0] ans_n  = {64{1'b1}};
    wire        t_word_n, t_ans_n;
    always @* begin
        word_n    = {64{1'b1}};
        word_n[L] = 1'b0;            // a plain line: its word pin grounded
        word_n[T] = t_word_n;        // the trunk's '165
        ans_n     = {64{1'b1}};
        ans_n[T]  = t_ans_n;
    end

    exch #(.PORT_FITTED(64'h0000_0000_0003_0200),     // 11, 20, 21
           .BLOCK_FITTED(8'b0000_0110)) u_x (            // blocks 1 and 2
        .clk(clk), .rst_n(rst_n),
        .c_tx(64'd0), .a_tx(64'd0), .ans_n(ans_n), .word_n(word_n),
        .c_rx(c_rx), .a_rx(a_rx),
        .mute_blk(8'd0), .rbt_in(1'b0),
        .sdata(b_oe && b_sdata), .sclk(b_oe && b_sclk), .wr(b_oe && b_wr),
        .hw_n(hw_n),
        .hc(), .ha_n(ha_n), .hb_n(hb_n), .tick(), .slot(slot), .slotq(slotq),
        .hclk(), .cap_stb(cap_stb), .tx_clk(tx_clk),
        .frame_stb(frame_stb), .clk_8k(clk_8k), .rx_oct(rx_oct), .oct_stb(),
        .scan(scan), .pass_stb(), .fill(fill), .ring_cad_n(), .tick_1k(tick_1k),
        .port_busy(port_busy));

    // ---- the trunk card at 11, its link looped to a bench clock -------------
    // Only the fifth conductor matters here: while it runs the far end is
    // alive.  HOLDOFF cut to 64 frames (1 ms) so the bench does not sit
    // through the real 100 ms.
    reg  far_alive = 1'b1;
    wire t_c_tx, t_a_tx, t_rai_n, t_c_out, t_a_out, t_clk_out, t_up;
    baseband_card #(.WORD(TW), .HOLDOFF(16'd64)) u_trunk (
        .clk(clk), .rst_n(rst_n),
        .tx_clk(tx_clk), .loop_hb(~slot[1]), .tx_oct(clk_8k), .fill(fill),
        .c_tx(t_c_tx), .a_tx(t_a_tx),
        .rx_clk(tx_clk), .rx_oct(rx_oct),
        .c_rx(c_rx[T]), .a_rx(a_rx[T]), .mute(1'b0),
        .word_n(t_word_n), .ans_n(t_ans_n), .rai_n(t_rai_n),
        .c_out(t_c_out), .a_out(t_a_out), .clk_out(t_clk_out),
        .c_in(1'b0), .a_in(1'b0), .clk_in(far_alive && tx_clk),
        .link_up(t_up));

    // ---- two faults on /HW between the mainboard and the reader -------------
    reg f_late = 1'b0, f_level = 1'b0;
    reg [63:0] hw_dly = {64{1'b1}};
    always @(posedge clk) hw_dly <= {hw_dly[62:0], hw_n};
    wire hw_seen = f_late  ? hw_dly[63]      // one frame late: 64 master ticks
                 : f_level ? ~hw_n           // the wire's level taken as the bit
                 :           hw_n;

    // ---- the master: one ctl_queue, alone on the bus -------------------------
    reg            rd_req = 1'b0;
    reg  [`PW-1:0] rd_port = 6'd0;
    wire           rd_done, rd_busy, q_ovf, q_pend, q_empty, q_sent;
    wire [7:0]     rd_word;
    wire [4:0]     q_room;
    ctl_queue #(.DEPTH(4), .NP(1)) u_m (
        .clk(clk), .rst_n(rst_n), .slotq(slotq), .cap_stb(cap_stb), .scan(scan),
        .sdata(b_sdata), .sclk(b_sclk), .wr(b_wr), .oe(b_oe), .hw_n(hw_seen),
        .go(1'b1), .pending(q_pend), .empty(q_empty),
        .push_v(1'b0), .push_d(15'd0), .room(q_room), .ovf(q_ovf),
        .rd_req(rd_req), .rd_port(rd_port), .rd_busy(rd_busy),
        .rd_done(rd_done), .rd_word(rd_word), .sent(q_sent));

    // count WR pulses: a read must never make one
    integer nwr = 0; reg wr_d = 1'b0;
    always @(posedge clk) begin
        if (b_oe && b_wr && !wr_d) nwr = nwr + 1;
        wr_d <= b_oe && b_wr;
    end

    reg [7:0] got; integer t0, took;
    task rd(input [`PW-1:0] p);
        begin
            @(posedge clk); rd_port = p; rd_req = 1'b1; t0 = $time;
            @(posedge clk); rd_req = 1'b0;
            while (!rd_done) @(posedge clk);
            got = rd_word; took = ($time - t0) / 244;
        end
    endtask

    task ms(input integer n); begin repeat (n) @(posedge tick_1k); end endtask

    integer ph, bad;
    initial begin
        $display("\n  tb_word -- a card's word off /HW, eight frames, fail-safe");
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        @(posedge frame_stb); repeat (8) @(posedge frame_stb);

        // ---- the power-up RC ----------------------------------------------
        rd(T);
        ck(got === 8'h00, "a trunk still held off by its RC reads NONE: all zeros");

        ms(3);
        rd(T);
        ck(got === TW, "a trunk reads its own class, glare and direction");
        $display("     11 reads %b: family 01 member 0, g=%0b, direction %0d",
                 got, got[5], got[7:6]);
        ck(took <= 1100, "and a read holds cable B about a quarter of a pass");
        $display("     the read took %0d master ticks (a pass is 4096)", took);

        rd(L);  ck(got === 8'hFF, "a plain line's grounded pin reads all ones");
        rd(E);  ck(got === 8'h00, "a port circuit with no card reads NONE");
        rd(U);  ck(got === 8'h00, "a port on an unfitted block reads NONE");

        // ---- any phase of the octet ---------------------------------------
        // The '259 is wired rotated by one, so eight consecutive frames from
        // anywhere hold the whole octet.
        bad = 0;
        for (ph = 0; ph < 8; ph = ph + 1) begin
            @(posedge frame_stb); repeat (ph * 64 + 3) @(posedge clk);
            rd(T); if (got !== TW) bad = bad + 1;
        end
        ck(bad == 0, "the same word at all eight phases of the octet");

        ck(nwr == 0, "no read made a WR: a pointing word writes nothing");
        ck(port_busy === 64'd0, "and no port was written");

        // ---- the fifth conductor ------------------------------------------
        far_alive = 1'b0;
        repeat (4) @(posedge frame_stb);
        rd(T);
        ck(!t_up && got === 8'h00, "a cut link reads NONE: the word is gated by link-up");
        far_alive = 1'b1;
        repeat (4) @(posedge frame_stb);
        rd(T);
        ck(got === TW, "and reads its word again when the far end comes back");

        // ---- the faults, each against the check it is for ------------------
        f_late = 1'b1;
        rd(T);
        ck(got !== TW, "/HW a frame late misreads the trunk: alignment is checked");
        f_late = 1'b0;

        f_level = 1'b1;
        rd(E);
        ck(got === 8'hFF, "read at the wire's level, an empty port is a plain line");
        f_level = 1'b0;
        rd(E);
        ck(got === 8'h00, "and read low-true it is NONE again: the fail-safe is the inversion");

        ck(!q_ovf, "the master's queue never refused a write");

        $display("\n  %0d checks, %0d errors.  %s\n", chk, errs,
                 (errs == 0) ? "PASS" : "FAIL");
        if (errs) $fatal(1);
        $finish;
    end

    initial begin #200_000_000; $display("  TIMEOUT"); $fatal(1); end

    wire _unused = &{1'b0, ha_n, hb_n, t_c_tx, t_a_tx, t_rai_n, t_c_out, t_a_out,
                     t_clk_out, rd_busy, q_pend, q_empty, q_sent, q_room, 1'b0};
endmodule
