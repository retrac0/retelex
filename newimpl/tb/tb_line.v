// tb_line -- the CVSD subscriber line card on a socket, with a phone on its
// two pairs.  channel-cards.md §2 and subscriber-line.md §2 to §5, measured.
//
// The socket's bus side is driven by hand: a clock card for the clocks, C_RX
// and A_RX from the bench, MUTE from the bench.  The line side is a
// subscriber model worked by its buttons.  Nothing reaches inside either.
//
// What it measures, in the documents' own numbers: 1100 reads on-hook and
// speech reads off-hook; the 4 ms RC's asymmetry -- a 60 ms dial break
// arrives about 6 ms short (subscriber-line.md §5); A_RX rings an on-hook
// phone and only an on-hook phone; a cut pair reads ON-HOOK, not off; MUTE
// puts 1010 on an off-hook line; and bits cross both ways in order.
`timescale 1ns/1ps
`include "exch.vh"

module tb_line;
    integer chk = 0, errs = 0;
    task ck(input cond, input [8*64-1:0] what);
        begin chk = chk + 1;
             if (!cond) begin errs = errs + 1; $display("    FAIL  %0s", what); end
        end
    endtask

    reg clk = 1'b0, rst_n = 1'b0;
    always #122.070 clk = ~clk;

    // ---- the socket's clocks: a clock card, and LOOP_HB made from /SLOT[1]
    //      as the block makes it (common-cards.md §1.1) ---------------------
    wire [2:0] tick, slot, slotq;
    wire hclk, cap_stb, tx_clk, frame_stb, clk_8k, rx_oct, oct_stb;
    wire [`SCANW-1:0] scan;
    wire pass_stb, fill, ring_cad_n, tick_1k;
    clock_card u_clk (
        .clk(clk), .rst_n(rst_n),
        .tick(tick), .hclk(hclk),
        .slot(slot), .slotq(slotq), .cap_stb(cap_stb),
        .frame_stb(frame_stb), .scan(scan), .ring_cad_n(ring_cad_n));
    frame_decode u_dec (
        .slot2(slot[2]), .frame_stb(frame_stb), .scan(scan),
        .tx_clk(tx_clk), .tx_oct(clk_8k), .rx_oct(rx_oct), .oct_stb(oct_stb),
        .fill(fill), .tick_1k(tick_1k));
    assign pass_stb = tick_1k;
    wire loop_hb = ~slot[1];

    // ---- the bus side of the socket, by hand ------------------------------
    reg  c_rx = 1'b0, a_rx = 1'b0, mute = 1'b0;
    wire c_tx, a_tx, word_n, ans_n, rai_n;

    // ---- the pairs, with a bench-operated cut in the upstream one -----------
    wire line_dn, ph_line_up;
    reg  cut = 1'b0;
    wire line_up = cut ? 1'b1 : ph_line_up;

    cvsd_line_card u_card (
        .clk(clk), .rst_n(rst_n),
        .tx_clk(tx_clk), .loop_hb(loop_hb), .tx_oct(clk_8k), .fill(fill),
        .c_tx(c_tx), .a_tx(a_tx),
        .rx_clk(tx_clk), .rx_oct(rx_oct),
        .c_rx(c_rx), .a_rx(a_rx), .mute(mute),
        .word_n(word_n), .ans_n(ans_n), .rai_n(rai_n),
        .line_dn(line_dn), .line_up(line_up));

    // ---- the phone, worked by its buttons --------------------------------------
    reg  off_hook = 1'b0, dial_on = 1'b0;
    wire ph_ring, ph_q, ph_q_stb;
    localparam [15:0] VOICE = 16'hAAAF;
    subscriber #(.CELL(64), .VOICE(VOICE)) u_ph (
        .clk(clk), .rst_n(rst_n),
        .line_dn(line_dn), .line_up(ph_line_up),
        .off_hook(off_hook), .dial_on(dial_on),
        .ringing(ph_ring), .q(ph_q), .q_stb(ph_q_stb));

    task ms(input integer n); begin repeat (n) @(posedge tick_1k); end endtask

    // one loop-disconnect digit at 10 pps, 60 % break, the codec muted
    task dial_digit(input integer d);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            dial_on = 1'b1;
            for (i = 0; i < n; i = i + 1) begin
                off_hook = 1'b0; ms(60);
                off_hook = 1'b1; ms(40);
            end
            dial_on = 1'b0;
        end
    endtask

    // ---- a downstream pattern onto C_RX, a bit a frame ----------------------
    localparam [15:0] DOWN = 16'h3C96;
    reg [3:0] di = 4'd0;
    reg       drive_down = 1'b0;
    always @(posedge clk) if (frame_stb) begin
        c_rx <= drive_down ? DOWN[di] : 1'b0;
        di   <= di + 4'd1;
    end

    // ---- captures: what leaves on C_TX, what the phone decodes --------------
    reg [47:0] cap_up = 48'd0, cap_dn = 48'd0;
    reg        cap_on = 1'b0;
    always @(posedge clk) begin
        if (cap_on && frame_stb) cap_up <= {c_tx, cap_up[47:1]};
        if (cap_on && ph_q_stb) cap_dn <= {ph_q, cap_dn[47:1]};
    end
    // the pattern, at some alignment, twice over
    function found(input [47:0] cap, input [15:0] pat);
        integer j;
        begin
            found = 1'b0;
            for (j = 0; j < 16; j = j + 1)
                if (cap[j +: 16] == pat && cap[j+16 +: 16] == pat) found = 1'b1;
        end
    endfunction

    // how often the phone's decoded bit flips: 1010 flips every bit
    integer q_seen = 0, q_flips = 0;
    reg     q_d = 1'b0;
    always @(posedge clk) if (ph_q_stb) begin
        q_seen = q_seen + 1;
        if (ph_q != q_d) q_flips = q_flips + 1;
        q_d = ph_q;
    end

    // dial breaks as A_TX shows them, in whole milliseconds
    integer brk_n = 0, brk_len = 0, brk_min = 9999, brk_max = 0;
    reg     brk_arm = 1'b0;
    always @(posedge tick_1k) if (brk_arm) begin
        if (!a_tx) brk_len = brk_len + 1;
        else if (brk_len != 0) begin
            brk_n = brk_n + 1;
            if (brk_len < brk_min) brk_min = brk_len;
            if (brk_len > brk_max) brk_max = brk_len;
            brk_len = 0;
        end
    end

    initial begin
        $display("\n  tb_line -- a CVSD line card, a phone on two pairs, and the numbers");
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        ms(2);

        // ---- 0.  the declarations --------------------------------------------
        ck(word_n === 1'b0, "a12 tied to ground: all ones, a plain line");
        ck(ans_n  === 1'b1, "a13 open: this port rings");
        ck(rai_n  === 1'b1, "a14 open");

        // ---- 1.  on-hook -------------------------------------------------------
        ms(10);
        ck(a_tx === 1'b0,    "on-hook: the phone's 1100 reads ON_HOOK, A_TX low");
        ck(ph_ring === 1'b0, "and the phone is not ringing");
        q_flips = 0; q_seen = 0; ms(4);
        ck(q_flips * 10 >= q_seen * 9, "the phone hears FILL's 1010 while on-hook");

        // ---- 2.  lift: the 4 ms RC falls from 1 to 0.70 -------------------------
        off_hook = 1'b1; ms(1);
        ck(a_tx === 1'b0, "1 ms after the lift the RC has not reached 0.70");
        ms(2);
        ck(a_tx === 1'b1, "3 ms after the lift: OFF_HOOK, A_TX high");

        // ---- 3.  voice, both ways ------------------------------------------------
        ms(2); cap_on = 1'b1; repeat (48) @(posedge frame_stb); @(posedge clk); cap_on = 1'b0;
        ck(found(cap_up, VOICE), "the phone's bits reach C_TX, in order");

        drive_down = 1'b1; ms(2);
        cap_on = 1'b1; repeat (60) @(posedge ph_q_stb); @(posedge clk); cap_on = 1'b0;
        ck(found(cap_dn, DOWN), "C_RX reaches the phone, in order");

        // ---- 4.  A_RX while off-hook is supervision, not ringing ---------------
        a_rx = 1'b1; ms(20);
        ck(ph_ring === 1'b0, "A_RX while off-hook: the phone does not ring");
        cap_on = 1'b1; repeat (60) @(posedge ph_q_stb); @(posedge clk); cap_on = 1'b0;
        ck(found(cap_dn, DOWN), "and it still hears C_RX");
        a_rx = 1'b0; drive_down = 1'b0;

        // ---- 5.  a dial: subscriber-line.md §5's breaks, 6 ms short -----------
        ms(5); brk_arm = 1'b1;
        dial_digit(3);
        ms(30); brk_arm = 1'b0;
        ck(brk_n == 3, "three breaks counted for a 3");
        ck(brk_min >= 51 && brk_max <= 57, "each 60 ms break arrives about 6 ms short");
        $display("     dialled 3: %0d breaks, %0d to %0d ms, for 60 sent", brk_n, brk_min, brk_max);
        ck(a_tx === 1'b1, "and still off-hook after the digit");

        // ---- 6.  hang up ---------------------------------------------------------
        off_hook = 1'b0; ms(10);
        ck(a_tx === 1'b0, "hang-up: ON_HOOK again within 10 ms");

        // ---- 7.  ring: A_RX to an on-hook phone is all-zeros downstream --------
        a_rx = 1'b1; ms(12);
        ck(ph_ring === 1'b1, "A_RX while on-hook: the phone rings");
        a_rx = 1'b0; ms(6);
        ck(ph_ring === 1'b0, "A_RX dropped: it stops");

        // ---- 8.  a cut pair reads on-hook, not off --------------------------------
        off_hook = 1'b1; ms(5);
        ck(a_tx === 1'b1, "off-hook again");
        cut = 1'b1; ms(10);
        ck(a_tx === 1'b0, "the pair cut: no carrier, no transitions, reads ON_HOOK");
        cut = 1'b0; ms(5);
        ck(a_tx === 1'b1, "the pair back: off-hook again, the receiver self-healed");

        // ---- 9.  MUTE: an off-hook phone hears 1010 through an outage ------------
        drive_down = 1'b1; mute = 1'b1; ms(3);
        q_flips = 0; q_seen = 0; ms(4);
        ck(q_flips * 10 >= q_seen * 9, "MUTE: the off-hook phone hears 1010, not C_RX");
        mute = 1'b0; ms(3);
        cap_on = 1'b1; repeat (60) @(posedge ph_q_stb); @(posedge clk); cap_on = 1'b0;
        ck(found(cap_dn, DOWN), "MUTE released: C_RX again");

        $display("\n  %0d checks, %0d errors.  %s\n", chk, errs,
                 (errs == 0) ? "PASS" : "FAIL");
        if (errs) $fatal(1);
        $finish;
    end

    initial begin #2_000_000_000; $display("  TIMEOUT"); $fatal(1); end
endmodule
