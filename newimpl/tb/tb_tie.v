// tb_tie -- two exchanges and a baseband tie trunk, patched by hand.
// baseband.md 1, 3; network.md 1.
//
// Exchange A and exchange B each have a baseband card at 11 and phones at 20
// and 21, and run on two crystals.  Nothing here dials: each exchange's
// latches are written by hand over its own cable B -- A's 20 to its 11, B's 11
// to its 21 -- which is fabric.md 7's hotline, stretched across a link.
//
// What it proves: each end reads its own card's word (class, glare,
// direction); bits cross both ways, in order, a bit a frame; A's 20 lifting is
// M at B's 11; the far end's A crosses the link; and a cut cable reads NONE at
// both ends and drops A, so a call in progress releases.
//
// Does not cover: dialling (tb_net), the one-clock jumper, or a slip -- the
// two crystals are at the same frequency here, 40 ns apart.
`timescale 1ns/1ps
`include "exch.vh"

module tb_tie;
    integer chk = 0, errs = 0;
    task ck(input cond, input [8*64-1:0] what);
        begin chk = chk + 1;
             if (!cond) begin errs = errs + 1; $display("    FAIL  %0s", what); end
        end
    endtask

    reg clk_a = 1'b0, clk_b = 1'b0, rst_n = 1'b0;
    always #122.070 clk_a = ~clk_a;
    initial begin #40; forever #122.070 clk_b = ~clk_b; end

    localparam [`PW-1:0] T = 6'o11, P = 6'o20, Q = 6'o21;
    localparam [7:0] WA = {2'd2, 1'b0, 3'b010, 2'b11};   // A's card faces E
    localparam [7:0] WB = {2'd3, 1'b1, 3'b010, 2'b11};   // B's faces W, with glare

    // ---- the cable, and a cut in it ------------------------------------------
    // A cut is modelled as receivers whose failsafe reads 1 on an open line:
    // the worst case for A, which the card must read as 0 all the same.
    reg  cut = 1'b0;
    wire a_c_out, a_a_out, a_clk_out, b_c_out, b_a_out, b_clk_out;

    // ---- one exchange: exch, a master on its cable B, a card at 11 ----------
    // Written out twice rather than as a generate: two exchanges on two
    // clocks are two things, not eight identical ones.
    reg  [63:0] a_ctx = 64'd0, a_atx = 64'd0, b_ctx = 64'd0, b_atx = 64'd0;
    wire [63:0] a_crx, a_arx, a_busy, b_crx, b_arx, b_busy;
    wire a_hw_n, a_fs, a_cap, a_txclk, a_oct, a_rxoct, a_fill, a_t1k;
    wire b_hw_n, b_fs, b_cap, b_txclk, b_oct, b_rxoct, b_fill, b_t1k;
    wire [2:0] a_slot, a_slotq, b_slot, b_slotq;
    wire [`SCANW-1:0] a_scan, b_scan;
    wire a_sd, a_sc, a_wr, a_oe, b_sd, b_sc, b_wr, b_oe;
    wire a_t_ctx, a_t_atx, a_t_word, a_t_ans, a_t_rai, a_up;
    wire b_t_ctx, b_t_atx, b_t_word, b_t_ans, b_t_rai, b_up;

    // The sockets: the phones' pins by hand, the card's at 11.  The phones'
    // word pins are grounded, a plain line; /ANS open, they ring.
    reg [63:0] a_c_in, a_a_in, b_c_in, b_a_in, a_word, b_word, a_ans, b_ans;
    always @* begin
        a_c_in = a_ctx; a_c_in[T] = a_t_ctx;   a_a_in = a_atx; a_a_in[T] = a_t_atx;
        b_c_in = b_ctx; b_c_in[T] = b_t_ctx;   b_a_in = b_atx; b_a_in[T] = b_t_atx;
        a_word = {64{1'b1}}; a_word[P] = 1'b0; a_word[Q] = 1'b0; a_word[T] = a_t_word;
        b_word = {64{1'b1}}; b_word[P] = 1'b0; b_word[Q] = 1'b0; b_word[T] = b_t_word;
        a_ans  = {64{1'b1}}; a_ans[T] = a_t_ans;
        b_ans  = {64{1'b1}}; b_ans[T] = b_t_ans;
    end

    exch #(.PORT_FITTED(64'h0000_0000_0003_0200), .BLOCK_FITTED(8'b0000_0110)) u_a (
        .clk(clk_a), .rst_n(rst_n),
        .c_tx(a_c_in), .a_tx(a_a_in), .ans_n(a_ans), .word_n(a_word),
        .c_rx(a_crx), .a_rx(a_arx), .mute_blk(8'd0), .rbt_in(1'b0),
        .sdata(a_oe && a_sd), .sclk(a_oe && a_sc), .wr(a_oe && a_wr), .hw_n(a_hw_n),
        .hc(), .ha_n(), .hb_n(), .tick(), .slot(a_slot), .slotq(a_slotq),
        .hclk(), .line_hb(), .cap_stb(a_cap), .tx_clk(a_txclk),
        .frame_stb(a_fs), .clk_8k(a_oct), .rx_oct(a_rxoct), .oct_stb(),
        .scan(a_scan), .pass_stb(), .fill(a_fill), .ring_cad_n(), .tick_1k(a_t1k),
        .port_busy(a_busy));

    exch #(.PORT_FITTED(64'h0000_0000_0003_0200), .BLOCK_FITTED(8'b0000_0110)) u_b (
        .clk(clk_b), .rst_n(rst_n),
        .c_tx(b_c_in), .a_tx(b_a_in), .ans_n(b_ans), .word_n(b_word),
        .c_rx(b_crx), .a_rx(b_arx), .mute_blk(8'd0), .rbt_in(1'b0),
        .sdata(b_oe && b_sd), .sclk(b_oe && b_sc), .wr(b_oe && b_wr), .hw_n(b_hw_n),
        .hc(), .ha_n(), .hb_n(), .tick(), .slot(b_slot), .slotq(b_slotq),
        .hclk(), .line_hb(), .cap_stb(b_cap), .tx_clk(b_txclk),
        .frame_stb(b_fs), .clk_8k(b_oct), .rx_oct(b_rxoct), .oct_stb(),
        .scan(b_scan), .pass_stb(), .fill(b_fill), .ring_cad_n(), .tick_1k(b_t1k),
        .port_busy(b_busy));

    // HOLDOFF cut to 64 frames so the bench does not sit through 100 ms
    baseband_card #(.WORD(WA), .HOLDOFF(16'd64)) u_ta (
        .clk(clk_a), .rst_n(rst_n),
        .tx_clk(a_txclk), .loop_hb(~a_slot[1]), .tx_oct(a_oct), .fill(a_fill),
        .c_tx(a_t_ctx), .a_tx(a_t_atx), .rx_clk(a_txclk), .rx_oct(a_rxoct),
        .c_rx(a_crx[T]), .a_rx(a_arx[T]), .mute(1'b0),
        .word_n(a_t_word), .ans_n(a_t_ans), .rai_n(a_t_rai),
        .c_out(a_c_out), .a_out(a_a_out), .clk_out(a_clk_out),
        .c_in(cut ? 1'b1 : b_c_out), .a_in(cut ? 1'b1 : b_a_out),
        .clk_in(cut ? 1'b1 : b_clk_out), .link_up(a_up));

    baseband_card #(.WORD(WB), .HOLDOFF(16'd64)) u_tb (
        .clk(clk_b), .rst_n(rst_n),
        .tx_clk(b_txclk), .loop_hb(~b_slot[1]), .tx_oct(b_oct), .fill(b_fill),
        .c_tx(b_t_ctx), .a_tx(b_t_atx), .rx_clk(b_txclk), .rx_oct(b_rxoct),
        .c_rx(b_crx[T]), .a_rx(b_arx[T]), .mute(1'b0),
        .word_n(b_t_word), .ans_n(b_t_ans), .rai_n(b_t_rai),
        .c_out(b_c_out), .a_out(b_a_out), .clk_out(b_clk_out),
        .c_in(cut ? 1'b1 : a_c_out), .a_in(cut ? 1'b1 : a_a_out),
        .clk_in(cut ? 1'b1 : a_clk_out), .link_up(b_up));

    // ---- a master on each cable B, driven by hand ----------------------------
    reg  [1:0]  a_pn = 2'b00, b_pn = 2'b00;
    reg  [29:0] a_pd = 30'd0, b_pd = 30'd0;
    reg         a_rq = 1'b0, b_rq = 1'b0;
    reg  [`PW-1:0] a_rp = 6'd0, b_rp = 6'd0;
    wire        a_rd, b_rd, a_ovf, b_ovf, a_emp, b_emp;
    wire [7:0]  a_rw, b_rw;
    wire [4:0]  a_room, b_room;
    wire        a_pend, b_pend, a_rbusy, b_rbusy, a_sent, b_sent;

    ctl_queue #(.DEPTH(4), .NP(2)) u_ma (
        .clk(clk_a), .rst_n(rst_n), .slotq(a_slotq), .cap_stb(a_cap), .scan(a_scan),
        .sdata(a_sd), .sclk(a_sc), .wr(a_wr), .oe(a_oe), .hw_n(a_hw_n),
        .go(1'b1), .pending(a_pend), .empty(a_emp),
        .push_v(a_pn), .push_d(a_pd), .room(a_room), .ovf(a_ovf),
        .rd_req(a_rq), .rd_port(a_rp), .rd_busy(a_rbusy), .rd_done(a_rd),
        .rd_word(a_rw), .sent(a_sent));
    ctl_queue #(.DEPTH(4), .NP(2)) u_mb (
        .clk(clk_b), .rst_n(rst_n), .slotq(b_slotq), .cap_stb(b_cap), .scan(b_scan),
        .sdata(b_sd), .sclk(b_sc), .wr(b_wr), .oe(b_oe), .hw_n(b_hw_n),
        .go(1'b1), .pending(b_pend), .empty(b_emp),
        .push_v(b_pn), .push_d(b_pd), .room(b_room), .ovf(b_ovf),
        .rd_req(b_rq), .rd_port(b_rp), .rd_busy(b_rbusy), .rd_done(b_rd),
        .rd_word(b_rw), .sent(b_sent));

    function [14:0] ent(input [`PW-1:0] d, input [`PW-1:0] s);
        ent = {1'b1, 1'b0, 1'b1, s, d};          // G, no CLAIM, BSY
    endfunction

    task patch_a(input [`PW-1:0] x, input [`PW-1:0] y);
        begin
            @(posedge clk_a); a_pn = 2'b11; a_pd = {ent(y, x), ent(x, y)};
            @(posedge clk_a); a_pn = 2'b00;
            @(posedge clk_a); while (!a_emp) @(posedge clk_a);
        end
    endtask
    task patch_b(input [`PW-1:0] x, input [`PW-1:0] y);
        begin
            @(posedge clk_b); b_pn = 2'b11; b_pd = {ent(y, x), ent(x, y)};
            @(posedge clk_b); b_pn = 2'b00;
            @(posedge clk_b); while (!b_emp) @(posedge clk_b);
        end
    endtask
    reg [7:0] got;
    task read_a(input [`PW-1:0] p);
        begin
            @(posedge clk_a); a_rp = p; a_rq = 1'b1; @(posedge clk_a); a_rq = 1'b0;
            while (!a_rd) @(posedge clk_a); got = a_rw;
        end
    endtask
    task read_b(input [`PW-1:0] p);
        begin
            @(posedge clk_b); b_rp = p; b_rq = 1'b1; @(posedge clk_b); b_rq = 1'b0;
            while (!b_rd) @(posedge clk_b); got = b_rw;
        end
    endtask

    // ---- bits across: a pattern a bit a frame, compared at the far socket ----
    // Each end keeps the last 64 bits it sent and the last 64 it received,
    // and a match is looked for at every delay up to 16 frames.
    reg [63:0] sent_ab = 64'd0, rcvd_ab = 64'd0, sent_ba = 64'd0, rcvd_ba = 64'd0;
    reg [15:0] pat = 16'hACE1;
    reg        drive = 1'b0;
    always @(posedge clk_a) if (a_fs) begin
        if (drive) begin
            pat <= {pat[14:0], pat[15] ^ pat[13] ^ pat[12] ^ pat[10]};
            a_ctx[P] <= pat[0];
        end
        sent_ab <= {sent_ab[62:0], a_ctx[P]};
        rcvd_ba <= {rcvd_ba[62:0], a_crx[P]};
    end
    reg [15:0] patb = 16'h1D2B;
    always @(posedge clk_b) if (b_fs) begin
        if (drive) begin
            patb <= {patb[14:0], patb[15] ^ patb[13] ^ patb[12] ^ patb[10]};
            b_ctx[Q] <= patb[0];
        end
        sent_ba <= {sent_ba[62:0], b_ctx[Q]};
        rcvd_ab <= {rcvd_ab[62:0], b_crx[Q]};
    end
    // A bit sent d frames before another arrives d frames before it, so the
    // received window [39:8] is the sent window [d+39:d+8] for some d.
    integer d; reg hit_ab, hit_ba;
    task match;
        begin
            hit_ab = 1'b0; hit_ba = 1'b0;
            for (d = 0; d <= 16; d = d + 1) begin
                if (rcvd_ab[39:8] == sent_ab[d+8 +: 32]) hit_ab = 1'b1;
                if (rcvd_ba[39:8] == sent_ba[d+8 +: 32]) hit_ba = 1'b1;
            end
        end
    endtask

    task ms(input integer n); begin repeat (n) @(posedge a_t1k); end endtask

    initial begin
        $display("\n  tb_tie -- two exchanges, a baseband tie trunk, patched by hand");
        repeat (20) @(posedge clk_a);
        rst_n = 1'b1;
        ms(3);

        read_a(T); ck(got === WA, "A reads its own trunk's word: facing E, no glare");
        read_b(T); ck(got === WB, "B reads its own: facing W, with glare");
        ck(a_up && b_up, "both fifth conductors running: the link is up");

        // the hotline across the link: A 20 <-> A 11 ~~ B 11 <-> B 21
        patch_a(P, T);
        patch_b(T, Q);
        ck(a_busy[P] && a_busy[T] && b_busy[T] && b_busy[Q], "four latches written, BUSY at each");

        drive = 1'b1; ms(3);
        @(posedge a_fs); @(posedge a_fs);
        match;
        ck(hit_ab, "A's 20 to B's 21: 32 bits in order, a bit a frame");
        ck(hit_ba, "B's 21 to A's 20: and the other way");
        drive = 1'b0;

        // ---- A across the link: A's 20 lifts, and that is M at B's 11 --------
        a_atx[P] = 1'b1; ms(4);
        ck(b_t_atx === 1'b1, "A's 20 off-hook is M at B's 11, through the link");
        a_atx[P] = 1'b0; ms(4);
        ck(b_t_atx === 1'b0, "and on-hook is M low there again");
        b_atx[Q] = 1'b1; ms(4);
        ck(a_t_atx === 1'b1, "B's 21 off-hook is M at A's 11: the other way");

        // ---- the trunk never rings: /ANS is tied low on the card -------------
        ck(a_t_ans === 1'b0 && b_t_ans === 1'b0, "both cards tie /ANS low: a trunk never rings");

        // ---- a cut cable ----------------------------------------------------
        cut = 1'b1; ms(2);
        ck(!a_up && !b_up, "a cut cable: both link-down detectors let go");
        ck(a_t_atx === 1'b0, "and A falls at A's 11, though B's 21 is still off-hook");
        read_a(T); ck(got === 8'h00, "A's trunk now reads NONE: no hunt will take it");
        read_b(T); ck(got === 8'h00, "and so does B's");
        cut = 1'b0; ms(2);
        read_a(T); ck(got === WA, "mended, A's trunk reads its word again");

        ck(!a_ovf && !b_ovf, "neither master's queue refused a write");

        $display("\n  %0d checks, %0d errors.  %s\n", chk, errs,
                 (errs == 0) ? "PASS" : "FAIL");
        if (errs) $fatal(1);
        $finish;
    end

    initial begin #400_000_000; $display("  TIMEOUT"); $fatal(1); end

    wire _unused = &{1'b0, a_t_rai, b_t_rai, a_room, b_room, a_pend, b_pend,
                     a_rbusy, b_rbusy, a_sent, b_sent, a_arx, b_arx, a_scan, b_scan,
                     a_rxoct, b_rxoct, 1'b0};
endmodule
