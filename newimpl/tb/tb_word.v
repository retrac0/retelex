// tb_word -- reading a card's word off /HW, named by a select on /WS.
// fabric.md §4; card-word.md §2, §3; bus.md §2.1.
//
// A reader pulls /WS in a port's own bit-time; the block that owns the port
// latches the slot and puts that card on /HW, and the reader takes the eight
// frames that follow (word_rx.v, block.v).  Fitted: eight baseband trunks, one
// in every slot of block 1 (10-17), each jumpered with a different glare and
// direction, 11 facing east with glare; a plain line card at 20 (its word pin
// grounded); an empty port circuit at 21; and nothing at all on block 5.
//
// What it proves: a trunk reads its own class, glare and direction; each of
// eight trunks, one a slot, reads its own word -- and since a port's slot
// fixes the octet phase its read starts at, that is every phase; a plain line
// reads all ones; an empty socket, an unfitted block, a card still held off
// by its power-up RC and a trunk whose link is cut all read ALL ZEROS -- /HW
// fails safe; a read selects once, in its port's own bit-time, and has its
// word eight frames later; a read moves no SCLK and makes no WR; two readers
// selecting one port in one bit-time both take its word; a reader whose port
// comes round inside another's eight frames lets it go and takes it a pass
// later; and a write passing on cable B during a read changes nothing on /HW.
//
// Two faults on the wire, each paired with the check it is for, so the check
// is shown able to fail in the same run: /HW one frame late into the reader,
// and /HW read at its wire level rather than inverted.
//
// Does not cover: the secondary byte (the socket cannot mark sixteen frames),
// a select made inside another read's window (word_rx cannot make one, so
// only a faulty card could), or any card but these three.
`timescale 1ns/1ps
`include "exch.vh"

module tb_word;
    integer chk = 0, errs = 0;
    task ck(input cond, input [8*72-1:0] what);
        begin chk = chk + 1;
             if (!cond) begin errs = errs + 1; $display("    FAIL  %0s", what); end
        end
    endtask

    reg clk = 1'b0, rst_n = 1'b0;
    always #122.070 clk = ~clk;

    localparam [`PW-1:0] T = 6'o11, L = 6'o20, E = 6'o21, U = 6'o50;
    // The trunks' jumpers: class trunk in every one, and glare and direction
    // from (slot + 4) mod 8, so the eight words all differ.  Slot 1 -- port
    // 11 -- faces east (2) with glare: TW, the word most checks name.
    function [7:0] tw(input integer s);
        reg [2:0] c;
        begin c = s + 4; tw = {c[2:1], c[0], 3'b010, 2'b11}; end
    endfunction
    localparam [7:0] TW = {2'd2, 1'b1, 3'b010, 2'b11};

    // ---- the exchange ----------------------------------------------------------
    wire [63:0] c_rx, a_rx, port_busy;
    wire ha_n, hb_n, hw_n, ws_n, frame_stb, fill, cap_stb, tick_1k, tx_clk, clk_8k, rx_oct;
    wire [2:0] slot, slotq;
    wire [`SCANW-1:0] scan;
    wire b_sdata, b_sclk, b_wr, b_oe;

    wire [7:0]  t_word_n, t_ans_n;
    reg  [63:0] word_n, ans_n;
    always @* begin
        word_n       = {64{1'b1}};
        word_n[L]    = 1'b0;             // a plain line: its word pin grounded
        word_n[15:8] = t_word_n;         // the trunks' '165s, block 1
        ans_n        = {64{1'b1}};
        ans_n[15:8]  = t_ans_n;
    end

    exch #(.PORT_FITTED(64'h0000_0000_0003_FF00),     // 10-17, 20, 21
           .BLOCK_FITTED(8'b0000_0110)) u_x (            // blocks 1 and 2
        .clk(clk), .rst_n(rst_n),
        .c_tx(64'd0), .a_tx(64'd0), .ans_n(ans_n), .word_n(word_n),
        .c_rx(c_rx), .a_rx(a_rx),
        .mute_blk(8'd0), .rbt_in(1'b0),
        .sdata(b_oe && b_sdata), .sclk(b_oe && b_sclk), .wr(b_oe && b_wr),
        .ws_n(ws_n), .hw_n(hw_n),
        .hc(), .ha_n(ha_n), .hb_n(hb_n), .tick(), .slot(slot), .slotq(slotq),
        .hclk(), .cap_stb(cap_stb), .tx_clk(tx_clk),
        .frame_stb(frame_stb), .clk_8k(clk_8k), .rx_oct(rx_oct), .oct_stb(),
        .scan(scan), .pass_stb(), .fill(fill), .ring_cad_n(), .tick_1k(tick_1k),
        .port_busy(port_busy));

    // ---- eight trunk cards, one in every slot of block 1 ---------------------
    // Their links looped to a bench clock: only the fifth conductor matters
    // here, and while it runs the far end is alive.  HOLDOFF cut to 256 frames
    // (4 ms) so the bench does not sit through the real 100 ms -- and no
    // shorter, because a read may wait a whole pass for its port's turn, and
    // the first read must still find the cards held off.
    reg  far_alive = 1'b1;
    wire [7:0] t_c_tx, t_a_tx, t_rai_n, t_c_out, t_a_out, t_clk_out, t_up;
    genvar s;
    generate for (s = 0; s < 8; s = s + 1) begin : trunk
        baseband_card #(.WORD(tw(s)), .HOLDOFF(16'd256)) u_card (
            .clk(clk), .rst_n(rst_n),
            .tx_clk(tx_clk), .loop_hb(~slot[1]), .tx_oct(clk_8k), .fill(fill),
            .c_tx(t_c_tx[s]), .a_tx(t_a_tx[s]),
            .rx_clk(tx_clk), .rx_oct(rx_oct),
            .c_rx(c_rx[8+s]), .a_rx(a_rx[8+s]), .mute(1'b0),
            .word_n(t_word_n[s]), .ans_n(t_ans_n[s]), .rai_n(t_rai_n[s]),
            .c_out(t_c_out[s]), .a_out(t_a_out[s]), .clk_out(t_clk_out[s]),
            .c_in(1'b0), .a_in(1'b0), .clk_in(far_alive && tx_clk),
            .link_up(t_up[s]));
    end endgenerate

    // ---- two faults on /HW between the mainboard and reader 1 ----------------
    reg f_late = 1'b0, f_level = 1'b0;
    reg [63:0] hw_dly = {64{1'b1}};
    always @(posedge clk) hw_dly <= {hw_dly[62:0], hw_n};
    wire hw_seen = f_late  ? hw_dly[63]      // one frame late: 64 master ticks
                 : f_level ? ~hw_n           // the wire's level taken as the bit
                 :           hw_n;

    // ---- two readers on /WS, and a writer alone on cable B --------------------
    // Reader 1 takes /HW through the faults, reader 2 straight off the wire.
    reg            rq1 = 1'b0, rq2 = 1'b0;
    reg  [`PW-1:0] rp1 = 6'd0, rp2 = 6'd0;
    wire           dn1, dn2, bz1, bz2, pd1, pd2;
    wire [7:0]     w1, w2;
    assign ws_n = ~(pd1 | pd2);            // the pull-up at the clock card, two drains
    word_rx u_r1 (
        .clk(clk), .rst_n(rst_n), .slotq(slotq), .cap_stb(cap_stb),
        .frame_stb(frame_stb), .scan(scan), .hw_n(hw_seen), .ws_n(ws_n), .ws_pd(pd1),
        .rd_req(rq1), .rd_port(rp1), .busy(bz1), .done(dn1), .word(w1));
    word_rx u_r2 (
        .clk(clk), .rst_n(rst_n), .slotq(slotq), .cap_stb(cap_stb),
        .frame_stb(frame_stb), .scan(scan), .hw_n(hw_n), .ws_n(ws_n), .ws_pd(pd2),
        .rd_req(rq2), .rd_port(rp2), .busy(bz2), .done(dn2), .word(w2));

    reg  [0:0]  pn = 1'b0;
    reg  [14:0] pdat = 15'd0;
    wire        q_ovf, q_pend, q_empty, q_sent;
    wire [4:0]  q_room;
    ctl_queue #(.DEPTH(4), .NP(1)) u_m (
        .clk(clk), .rst_n(rst_n),
        .sdata(b_sdata), .sclk(b_sclk), .wr(b_wr), .oe(b_oe),
        .go(1'b1), .pending(q_pend), .empty(q_empty),
        .push_v(pn), .push_d(pdat), .room(q_room), .ovf(q_ovf), .sent(q_sent));

    // ---- what the wires did ---------------------------------------------------
    // Every select -- the port it named and when -- and every SCLK edge and
    // WR on cable B.  A select inside another read's eight frames is counted.
    wire a_stb = cap_stb && (slotq == `CELL_A);
    integer nsel = 0, nsclk = 0, nwr = 0, near = 0, frames = 0, last_sel = -99;
    realtime sel_at = 0;
    reg [`PW-1:0] sel_port = 6'd0;
    reg sclk_d = 1'b0, wr_d = 1'b0;
    always @(posedge clk) begin
        if (frame_stb) frames = frames + 1;
        if (a_stb && !ws_n) begin
            if (frames - last_sel < 9) near = near + 1;
            last_sel = frames; nsel = nsel + 1; sel_port = scan; sel_at = $realtime;
        end
        if (b_oe && b_sclk && !sclk_d) nsclk = nsclk + 1;
        if (b_oe && b_wr && !wr_d) nwr = nwr + 1;
        sclk_d <= b_oe && b_sclk;
        wr_d   <= b_oe && b_wr;
    end

    localparam real TICK_NS = 244.140625;
    reg [7:0] got; integer took, n0, bad, k;
    // Done times are taken here, in the waiting loops, and not by the monitor:
    // a check made on the edge a word arrives would read the monitor's copy
    // before the monitor had written it.
    realtime t0, t_dn, t_dn1, t_dn2;
    reg      got1, got2;
    task rd(input [`PW-1:0] p);             // reader 1, alone
        begin
            @(posedge clk); rp1 = p; rq1 = 1'b1; t0 = $realtime; n0 = nsel;
            @(posedge clk); rq1 = 1'b0;
            while (!dn1) @(posedge clk);
            t_dn = $realtime;
            got = w1; took = $rtoi((t_dn - t0) / TICK_NS);
        end
    endtask

    task ms(input integer n); begin repeat (n) @(posedge tick_1k); end endtask

    initial begin
        $display("\n  tb_word -- a card's word off /HW, named by a select on /WS");
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        @(posedge frame_stb); repeat (8) @(posedge frame_stb);

        // ---- the power-up RC ----------------------------------------------
        rd(T);
        ck(got === 8'h00, "a trunk still held off by its RC reads NONE: all zeros");

        ms(5);
        rd(T);
        ck(got === TW, "a trunk reads its own class, glare and direction");
        $display("     11 reads %b: family 01 member 0, g=%0b, direction %0d",
                 got, got[5], got[7:6]);
        ck(nsel == n0 + 1 && sel_port === T, "the read made one select, and it named 11");
        $display("     select to word: %0d master ticks", $rtoi((t_dn - sel_at) / TICK_NS));
        ck($rtoi((t_dn - sel_at) / TICK_NS) >= 512 && $rtoi((t_dn - sel_at) / TICK_NS) <= 516,
           "and had its word eight frames after the select");
        ck(took <= 4096 + 9*64 + 64, "a read waits at most a pass for its turn, then nine frames");
        $display("     the read took %0d master ticks from the request (a pass is 4096)", took);

        rd(L);  ck(got === 8'hFF, "a plain line's grounded pin reads all ones");
        rd(E);  ck(got === 8'h00, "a port circuit with no card reads NONE");
        rd(U);  ck(got === 8'h00, "a port on an unfitted block reads NONE");

        // ---- every slot, so every phase of the octet ------------------------
        // A read starts where its port's turn falls, so the octet phase it
        // starts at is the port's slot; one trunk a slot reads all eight.
        bad = 0;
        for (k = 0; k < 8; k = k + 1) begin
            rd(6'o10 + k[5:0]); if (got !== tw(k)) bad = bad + 1;
        end
        ck(bad == 0, "eight trunks, one a slot, each read its own word: all eight octet phases");

        ck(nsclk == 0, "no read moved SCLK: cable B carries no pointing word");
        ck(nwr == 0, "and none made a WR");
        ck(port_busy === 64'd0, "and no port was written");

        // ---- two readers, one port, one bit-time ------------------------------
        n0 = nsel;
        @(posedge clk); rp1 = T; rp2 = T; rq1 = 1'b1; rq2 = 1'b1;
        @(posedge clk); rq1 = 1'b0; rq2 = 1'b0;
        @(posedge clk); while (bz1 || bz2) @(posedge clk);
        ck(w1 === TW && w2 === TW, "two readers selecting one port in one bit-time both take its word");
        ck(nsel == n0 + 1, "on the one select: they named the same port, and nothing collided");

        // ---- a turn that falls inside another read ------------------------------
        // Asked for just after 12's turn, so 11 comes round first and 12 one
        // frame later, inside 11's eight: reader 2 must let it go by.
        @(posedge clk); while (!(frame_stb && (scan == 6'o13))) @(posedge clk);
        n0 = nsel;
        rp1 = T; rp2 = 6'o12; rq1 = 1'b1; rq2 = 1'b1;
        @(posedge clk); rq1 = 1'b0; rq2 = 1'b0;
        got1 = 1'b0; got2 = 1'b0;
        while (!(got1 && got2)) begin
            @(posedge clk);
            if (dn1) begin got1 = 1'b1; t_dn1 = $realtime; end
            if (dn2) begin got2 = 1'b1; t_dn2 = $realtime; end
        end
        ck(w1 === TW && w2 === tw(2), "11 and 12, one frame apart: each read its own word");
        ck(nsel == n0 + 2 && near == 0, "on two selects, and 12's waited out 11's eight frames");
        $display("     11's word to 12's: %0d master ticks", $rtoi((t_dn2 - t_dn1) / TICK_NS));
        ck($rtoi((t_dn2 - t_dn1) / TICK_NS) >= 4096, "12 was taken a pass later, at its next turn");

        // ---- a write passing during a read ------------------------------------
        // The pointer is the select latch, not DST: a write naming 20 while
        // 11's word is on /HW moves nothing.  The bus used to be held across a
        // whole read for fear of exactly this.
        @(posedge clk); rp1 = T; rq1 = 1'b1;
        @(posedge clk); rq1 = 1'b0;
        while (!(a_stb && !ws_n)) @(posedge clk);
        @(posedge clk); pn = 1'b1; pdat = {1'b1, 1'b0, 1'b1, E, L};   // 20 hears 21, BUSY
        @(posedge clk); pn = 1'b0;
        while (!dn1) @(posedge clk);
        ck(nsclk >= 8, "the write was shifting while the read took its word");
        ck(w1 === TW, "and a write passing on cable B during a read changes nothing on /HW");
        while (!q_empty) @(posedge clk);
        @(posedge frame_stb); @(posedge frame_stb);
        ck(port_busy[L] === 1'b1, "and the write landed on its own port");

        // ---- the link ------------------------------------------------------
        far_alive = 1'b0;
        repeat (4) @(posedge frame_stb);
        rd(T);
        ck(!t_up[1] && got === 8'h00, "a cut link reads NONE: the word is gated by link-up");
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

        ck(!q_ovf, "the writer's queue never refused a write");

        $display("\n  %0d checks, %0d errors.  %s\n", chk, errs,
                 (errs == 0) ? "PASS" : "FAIL");
        if (errs) $fatal(1);
        $finish;
    end

    initial begin #200_000_000; $display("  TIMEOUT"); $fatal(1); end

    wire _unused = &{1'b0, ha_n, hb_n, t_c_tx, t_a_tx, t_rai_n, t_c_out, t_a_out, t_clk_out,
                     q_pend, q_sent, q_room, rx_oct, 1'b0};
endmodule
