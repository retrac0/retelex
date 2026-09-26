// tb_max -- the class marker on one exchange, no network unit.  marker.md 1-5;
// groups.md 2; extensions.md 2.2-2.4, 3.1; features.md 5.
//
// Every port says what it is in its card's word, and the marker reads it
// before it acts:
//   04 a plain line, the operator     05 answers to 04, a second position
//   10 11 outside lines, /ANS low     20 21 22 35  plain lines
//   23 busy-out                       24 restricted, 0 only      25 restricted
//   26 answers to 21                  27 a data line
//   30 a source: a radio, /ANS low    31 call nail to 20
//   32 33 a private line: a tied nail on each, naming the other (extensions.md 3.1)
//   34 a paging amplifier, /ANS low, nailed one way to the radio at 30
//   36 a P line                       17 empty                    37 out of service
// and tone sources at 01 (dial), 02 (busy) and 03 (cannot-complete).  Timers
// scaled by 8 through the straps, as tb_net's; the walk, the hunt and the
// reads are cable timing and do not scale.
//
// THE WALK IS THE ONLY WAY IN: every caller, call nail and CO line is found
// by it, so a lift waits up to a round, 63 x WALK ms, for the marker.  `lift`
// waits for the register rather than for a fixed time.
//
//   1  the private line and the one-way nail made at power-up by the walk, not
//      before it came round; the radio nailed and never written
//   2  20 calls 21: dial tone within a round of the walk, ringing, both ways,
//      release
//   3  21 busy: 22's call goes to 26, which answers to 21
//   4  21 and 26 both busy: busy tone
//   5  busy-out: calling 23 is busy tone; 23 still gets dial tone
//   6  wrong numbers: self, an empty slot, a card out of service, 8, 2 8 --
//      each cannot-complete; 37 lifting gets nothing
//   7  a source: 30 dialled is listened to, never rung, never BUSY
//   8  0: the operator rings; busy, the second position; both busy, busy tone
//   9  9: two outside lines taken in order, a third caller cannot-complete
//  10  restricted: z lets only 0 through; the floor refuses 9
//  11  a data line neither calls nor is called, and off-hook is read once a
//      round by the walk, like every port, and by nothing else
//  12  the call nail: 31 lifting rings 20, no dial tone; 20 busy, busy tone
//  13  a CO line ringing in is routed as 0
//  14  the private line used; one end left off-hook is no caller, and the walk
//      nails both ports again so that it rings the other (extensions.md 3.2);
//      both down, made again
//  15  PWAIT (extensions.md 2.4.1): a round finds 36, a P line, waiting; the
//      register goes to 36 and not to 35 beside it, and to 35 once no P line
//      waits
//  16  a caller hanging up at the connect leaves the called port free
//
// Does not cover: a network unit (a claim, a flood, the unit's reads beside
// the walk's), a card's secondary, a register pool, the console.
`timescale 1ns/1ps
`include "exch.vh"

module tb_max;
    integer chk = 0, errs = 0;
    task ck(input cond, input [8*72-1:0] what);
        begin chk = chk + 1;
             if (!cond) begin errs = errs + 1; $display("    FAIL  %0s", what); end
        end
    endtask

    reg clk = 1'b0, rst_n = 1'b0;
    always #122.070 clk = ~clk;

    localparam [`PW-1:0] P04 = 6'o04, P05 = 6'o05, P10 = 6'o10, P11 = 6'o11,
                         P20 = 6'o20, P21 = 6'o21, P22 = 6'o22, P23 = 6'o23,
                         P24 = 6'o24, P25 = 6'o25, P26 = 6'o26, P27 = 6'o27,
                         P30 = 6'o30, P31 = 6'o31, P32 = 6'o32, P33 = 6'o33, P34 = 6'o34,
                         P35 = 6'o35, P36 = 6'o36, P37 = 6'o37, P17 = 6'o17;

    // the card words, wire order read as WORD[7:0] (extensions.md 2.2)
    localparam [7:0] W_PLAIN = 8'hFF,
                     W_BOUT  = 8'h4F,                    // line, b
                     W_PRI   = 8'h2F,                    // line, P
                     W_DATA  = 8'h8F,                    // line, D
                     W_RZ    = 8'h3F,                    // restricted, z
                     W_REST  = 8'h1F,                    // restricted, nothing
                     W_OUT   = 8'h17,                    // outside line
                     W_SRC   = 8'h07,                    // source
                     W_RSVD  = 8'h13;                    // the reserved class: OOS
    // port forms: the six bits h s, then the type -- 00 tied nail, answers-to
    // 01 and call nail 10 in wire order, so WORD[1:0] = 2'b10 and 2'b01
    localparam [7:0] W_ANS04 = {P04, 2'b10}, W_ANS21 = {P21, 2'b10},
                     W_CN20  = {P20, 2'b01}, W_TN32  = {P32, 2'b00},
                     W_TN33  = {P33, 2'b00}, W_TN30  = {P30, 2'b00};

    localparam [63:0] PH = (64'd1 << P04) | (64'd1 << P05) | (64'd1 << P10) |
                           (64'd1 << P11) | (64'd1 << P20) | (64'd1 << P21) |
                           (64'd1 << P22) | (64'd1 << P23) | (64'd1 << P24) |
                           (64'd1 << P25) | (64'd1 << P26) | (64'd1 << P27) |
                           (64'd1 << P30) | (64'd1 << P31) | (64'd1 << P32) |
                           (64'd1 << P33) | (64'd1 << P34) | (64'd1 << P35) | (64'd1 << P36) |
                           (64'd1 << P37);
    localparam [63:0] ANSLOW = (64'd1 << P10) | (64'd1 << P11) | (64'd1 << P30) |
                               (64'd1 << P34);
    localparam [63:0] NAILED = (64'd1 << P32) | (64'd1 << P33) | (64'd1 << P34);

    function [511:0] wset(input [511:0] acc, input [`PW-1:0] p, input [7:0] w);
        begin wset = acc; wset[p*8 +: 8] = w; end
    endfunction
    localparam [511:0] W0 = {64{W_PLAIN}};
    localparam [511:0] W1 = wset(wset(wset(wset(W0, P05, W_ANS04), P10, W_OUT), P11, W_OUT), P23, W_BOUT);
    localparam [511:0] W2 = wset(wset(wset(wset(W1, P24, W_RZ), P25, W_REST), P26, W_ANS21), P27, W_DATA);
    localparam [511:0] W3 = wset(wset(wset(wset(W2, P30, W_SRC), P31, W_CN20), P32, W_TN33), P33, W_TN32);
    localparam [511:0] PW = wset(wset(wset(W3, P34, W_TN30), P36, W_PRI), P37, W_RSVD);

    reg  [63:0] hook = 64'd0, tx = {64{1'b1}};
    wire [63:0] rx, e, busy;

    // ---- the radio at 30: two frames up, two down, its own process ------------
    reg [1:0] rph = 2'd0; reg rbit = 1'b0;
    wire [63:0] txs = (tx & ~(64'd1 << P30)) | ({63'd0, rbit} << P30);
    wire        fs, t1k, wsn, rcad, sd, sc, wr, clash, rbusy, pwait, ovf;
    wire [`PW-1:0] caller, called;
    wire [3:0]  mks;

    // the walk's pace, as top_max's: a round of the 63 ports is 63 x WALK ms
    localparam [4:0]  WALK  = 5'd4;
    localparam integer ROUND = 63 * WALK;

    site_max #(.PHONES(PH), .PWORD(PW), .PANS(ANSLOW), .UNIT(1'b0), .WALK(WALK),
               .T_ARM(9'd2), .T_REL(9'd32), .RING_ON(13'd64), .RING_OFF(13'd128),
               .HIT(9'd1), .ID(9'd16), .CLR(9'd32), .NODIG(16'd1250)) X (
        .clk(clk), .rst_n(rst_n), .hook(hook), .tx(txs), .rx(rx), .e(e),
        .c_out(), .a_out(), .clk_out(), .c_in(64'd0), .a_in(64'd0), .clk_in(64'd0),
        .link_up(),
        .frame_stb(fs), .tick_1k(t1k), .ws_sel_n(wsn), .ring_cad_n(rcad), .port_busy(busy),
        .b_sdata(sd), .b_sclk(sc), .b_wr(wr), .b_clash(clash),
        .reg_busy(rbusy), .caller(caller), .called(called), .mk_state(mks),
        .mk_pwait(pwait), .mk_ovf(ovf),
        .dirs_held(), .res_busy(), .mon_held(), .claimed(), .hunting(),
        .un_ovf(), .n_glare(), .n_nofwd());

    always @(posedge fs) begin rph <= rph + 2'd1; rbit <= rph[1]; end

    // ---- selects on /WS: every reader's, the marker's walk included ----------
    reg wsn_d = 1'b1; integer nsel = 0;
    always @(posedge clk) begin wsn_d <= wsn; if (wsn_d && !wsn) nsel = nsel + 1; end

    // ---- the bench's hands -------------------------------------------------------
    task ms(input integer n); begin repeat (n) @(posedge t1k); end endtask

    task dial(input [`PW-1:0] p, input integer d);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                hook[p] = 1'b0; ms(12);
                hook[p] = 1'b1; ms(8);
            end
            ms(100);
        end
    endtask

    // What is this port hearing?  Sixteen frames of it.  Dial tone is ones and
    // cannot-complete zeros; busy tone changes every four frames, the radio
    // every two, and FILL -- silence, on 00 -- every frame.  A phone left
    // alone by the bench sends ones.
    localparam [2:0] H_OTHER = 3'd0, H_ONE = 3'd1, H_ZERO = 3'd2, H_BUSY = 3'd3,
                     H_RADIO = 3'd4, H_FILL = 3'd5;
    integer tj, n1, ntr; reg last; reg [2:0] heard;
    task tone(input [`PW-1:0] p);
        begin n1 = 0; ntr = 0; last = 1'b0;
            for (tj = 0; tj < 16; tj = tj + 1) begin
                @(posedge fs); @(posedge clk);
                if (rx[p]) n1 = n1 + 1;
                if ((tj > 0) && (rx[p] != last)) ntr = ntr + 1;
                last = rx[p];
            end
            heard = (n1 == 16) ? H_ONE  : (n1 == 0)  ? H_ZERO :
                    (ntr >= 12) ? H_FILL : (ntr >= 6) ? H_RADIO :
                    (ntr >= 2)  ? H_BUSY : H_OTHER;
        end
    endtask

    // Does port a hear port b?  b's speech taken low and high, a's ear follows.
    reg x0, x1;
    task hears(input [`PW-1:0] a, input [`PW-1:0] b);
        begin
            tx[b] = 1'b0; ms(4); x0 = rx[a];
            tx[b] = 1'b1; ms(4); x1 = rx[a];
        end
    endtask

    // Is port p being rung?  Its E, on-hook, in the cadence: 250 ms of it.
    reg r0, r1; integer ri;
    task rung(input [`PW-1:0] p);
        begin r0 = 1'b0; r1 = 1'b0;
            for (ri = 0; ri < 250; ri = ri + 1) begin
                ms(1); if (e[p]) r1 = 1'b1; else r0 = 1'b1;
            end
        end
    endtask

    // Lift p as a caller and wait for the walk to give it the register: within
    // a round.  lt is how long that took, in ms.
    integer lt;
    task lift(input [`PW-1:0] p);
        begin
            hook[p] = 1'b1; lt = 0;
            while (!(busy[p] && rbusy) && lt < 2 * ROUND) begin ms(1); lt = lt + 1; end
            ms(10);
        end
    endtask

    task idle(input [8*72-1:0] what);
        begin
            hook = 64'd0; ms(150);
            ck(!rbusy && (mks == 4'd0) && ((busy & ~NAILED) == 64'd0), what);
        end
    endtask

    integer t;
    initial begin
        #1_000; rst_n = 1'b1;
        $display("  tb_max -- the class marker: what a port's card says, and what it gets");

        // ================= 1.  the tied nail at power-up =========================
        ms(40);
        ck(!busy[P32] && !busy[P33], "at 40 ms the walk has not reached 32: no nail yet");
        t = 0; while (!(busy[P32] && busy[P33] && busy[P34]) && t < 1000) begin ms(1); t = t + 1; end
        ck(busy[P32] && busy[P33], "the walk made the private line: both ends nailed, both BUSY");
        hears(P32, P33); ck(!x0 && x1, "32 hears 33");
        hears(P33, P32); ck(!x0 && x1, "and 33 hears 32");
        ck(busy[P34], "and the one-way nail 34 onto the radio");
        tone(P34); ck(heard == H_RADIO, "34 hears the radio");
        ck(!busy[P30], "and the radio was never written: a nail is one way");
        ck(!rbusy, "a nail took no register");

        // ================= 2.  a plain call ======================================
        $display("  2. 20 dials 2 1");
        ck(!pwait, "PWAIT is clear on an idle exchange");
        lift(P20);
        ck(busy[P20] && rbusy && (lt <= ROUND + 4), "20 has the register within a round of the walk");
        tone(P20); ck(heard == H_ONE, "and hears dial tone");
        dial(P20, 2);
        tone(P20); ck(heard != H_ONE, "dial tone went at the first digit");
        dial(P20, 1); ms(10);
        ck(busy[P21], "21 was connected");
        rung(P21); ck(r0 && r1, "21 rings in cadence");
        ck(!rbusy, "the register was let go after the watch");
        hook[P21] = 1'b1; ms(10);
        hears(P20, P21); ck(!x0 && x1, "20 hears 21");
        hears(P21, P20); ck(!x0 && x1, "21 hears 20");
        idle("released: nothing BUSY but the nail, the register free");

        // ================= 3/4.  answers-to, then busy tone ====================
        $display("  3. 21 busy: 22 reaches 26; 4. both busy: busy tone");
        lift(P20); dial(P20, 2); dial(P20, 1); ms(10);
        hook[P21] = 1'b1; ms(10);
        lift(P22); dial(P22, 2); dial(P22, 1); ms(150);
        ck(busy[P26], "21 busy: the hunt found 26, which answers to 21");
        rung(P26); ck(r0 && r1, "and 26 rings");
        hook[P26] = 1'b1; ms(10);
        hears(P22, P26); ck(!x0 && x1, "22 hears 26");
        lift(P25); dial(P25, 2); dial(P25, 1); ms(150);
        tone(P25); ck(heard == H_BUSY, "21 and 26 both busy: 25 hears BUSY tone");
        idle("all four calls released");

        // ================= 5.  busy-out ===========================================
        $display("  5. busy-out");
        lift(P22); dial(P22, 2); dial(P22, 3); ms(150);
        ck(!busy[P23], "23 is busy-out: it was not connected");
        tone(P22); ck(heard == H_BUSY, "and its caller hears busy tone");
        hook[P22] = 1'b0; ms(150);
        lift(P23);
        tone(P23); ck(busy[P23] && heard == H_ONE, "23 lifting still gets dial tone");
        idle("released");

        // ================= 6.  wrong numbers ======================================
        $display("  6. wrong numbers");
        lift(P22); dial(P22, 2); dial(P22, 2); ms(150);
        tone(P22); ck(heard == H_ZERO, "22 dialling itself: cannot-complete");
        hook[P22] = 1'b0; ms(150);
        lift(P22); dial(P22, 1); dial(P22, 7); ms(150);
        tone(P22); ck(heard == H_ZERO, "an empty slot, 17: cannot-complete");
        hook[P22] = 1'b0; ms(150);
        lift(P22); dial(P22, 3); dial(P22, 7); ms(150);
        tone(P22); ck(heard == H_ZERO, "37, out of service: cannot-complete");
        ck(!busy[P37], "and 37 was never written");
        hook[P22] = 1'b0; ms(150);
        lift(P22); dial(P22, 8); ms(20);
        tone(P22); ck(heard == H_ZERO, "8 first: cannot-complete");
        hook[P22] = 1'b0; ms(150);
        lift(P22); dial(P22, 2); dial(P22, 8); ms(20);
        tone(P22); ck(heard == H_ZERO && !busy[P20], "2 8: cannot-complete, not 20");
        hook[P22] = 1'b0; ms(150);
        hook[P37] = 1'b1; ms(ROUND + 20);
        ck(!busy[P37] && !rbusy, "37 lifting, out of service, is no call request");
        idle("released");

        // ================= 7.  a source ============================================
        $display("  7. a source");
        lift(P22); dial(P22, 3); dial(P22, 0); ms(20);
        tone(P22); ck(heard == H_RADIO, "22 dialled 30 and hears the radio");
        ck(!busy[P30], "a source is listened to, never written");
        rung(P30); ck(!r1, "and never rung");
        ck(!rbusy, "the register is free: one write, no watch");
        idle("released");

        // ================= 8.  0 ================================================
        $display("  8. 0, the operator");
        lift(P22); dial(P22, 0); ms(20);
        ck(busy[P04], "0 connected the operator, 04");
        rung(P04); ck(r0 && r1, "and 04 rings");
        hook[P22] = 1'b0; ms(150);
        lift(P04); dial(P04, 2); dial(P04, 1); ms(10);
        hook[P21] = 1'b1; ms(10);
        lift(P22); dial(P22, 0); ms(150);
        ck(busy[P05], "04 busy: 0 reached 05, which answers to 04");
        rung(P05); ck(r0 && r1, "and 05 rings");
        hook[P05] = 1'b1; ms(10);
        hears(P22, P05); ck(!x0 && x1, "22 hears the second position");
        lift(P25); dial(P25, 0); ms(150);
        tone(P25); ck(heard == H_BUSY, "both positions busy: busy tone");
        idle("released");

        // ================= 9.  9 =====================================================
        $display("  9. 9, outside lines");
        lift(P22); dial(P22, 9); ms(150);
        ck(busy[P10], "9 took the first outside line, 10");
        hears(P22, P10); ck(!x0 && x1, "and 22 hears the CO on it");
        lift(P20); dial(P20, 9); ms(150);
        ck(busy[P11], "a second 9 took 11");
        lift(P21); dial(P21, 9); ms(150);
        tone(P21); ck(heard == H_ZERO, "a third, with none free: cannot-complete");
        idle("released");

        // ================= 10.  restricted ========================================
        $display("  10. restricted");
        lift(P24); dial(P24, 2); ms(20);
        tone(P24); ck(heard == H_ZERO && !busy[P21], "z: 2 first is cannot-complete");
        hook[P24] = 1'b0; ms(150);
        lift(P24); dial(P24, 0); ms(20);
        ck(busy[P04], "z: 0 reaches the operator");
        hook[P24] = 1'b0; ms(150);
        lift(P25); dial(P25, 9); ms(20);
        tone(P25); ck(heard == H_ZERO && !busy[P10], "the floor: 9 is cannot-complete");
        hook[P25] = 1'b0; ms(150);
        lift(P25); dial(P25, 2); dial(P25, 1); ms(20);
        ck(busy[P21], "the floor: a local number is connected");
        idle("released");

        // ================= 11.  a data line =========================================
        $display("  11. a data line");
        hook[P27] = 1'b1; ms(ROUND + 20);
        ck(!busy[P27] && !rbusy, "27, a data line, lifting gets no register");
        // two rounds with the marker idle: the walk's reads and nothing else.
        // A read of whoever lifts would add one every other pass
        t = nsel; ms(2 * ROUND);
        ck(nsel - t <= 2 * 63 + 4, "and is read once a round, by the walk, and by nothing else");
        lift(P22); dial(P22, 2); dial(P22, 7); ms(150);
        tone(P22); ck(heard == H_ZERO, "and 27 dialled is cannot-complete");
        idle("released");

        // ================= 12.  the call nail =======================================
        $display("  12. the call nail");
        hook[P31] = 1'b1;
        t = 0; while (!busy[P20] && t < 2 * ROUND) begin ms(1); t = t + 1; end
        ms(10);
        ck(busy[P20], "31 lifting connected 20, its call nail, when the walk came to it");
        tone(P31); ck(heard == H_FILL, "with no dial tone: 31 hears ringback, FILL here");
        rung(P20); ck(r0 && r1, "and 20 rings");
        hook[P20] = 1'b1; ms(10);
        hears(P31, P20); ck(!x0 && x1, "31 hears 20");
        hears(P20, P31); ck(!x0 && x1, "20 hears 31");
        hook = 64'd0; ms(150);
        lift(P20); dial(P20, 2); dial(P20, 1); ms(10);
        hook[P21] = 1'b1; ms(10);
        hook[P31] = 1'b1; ms(ROUND + 150);
        tone(P31); ck(heard == H_BUSY, "20 busy: the call nail hears busy tone");
        idle("released");

        // ================= 13.  a CO line ringing in ====================================
        $display("  13. a CO line ringing in");
        hook[P10] = 1'b1;
        t = 0; while (!busy[P04] && t < 2 * ROUND) begin ms(1); t = t + 1; end
        ms(10);
        ck(busy[P04] && busy[P10], "10 ringing in was routed as 0: 04 connected");
        rung(P04); ck(r0 && r1, "and the operator rings");
        hook[P04] = 1'b1; ms(10);
        hears(P04, P10); ck(!x0 && x1, "04 answers and hears the CO");
        idle("released");

        // ================= 14.  the private line ====================================
        $display("  14. the private line, used and made again");
        hook[P32] = 1'b1; ms(10);
        rung(P33); ck(r0 && r1, "32 lifting rings 33: a private line is a hotline");
        hook[P33] = 1'b1; ms(10);
        hears(P33, P32); ck(!x0 && x1, "33 answers and hears 32");
        hears(P32, P33); ck(!x0 && x1, "and 32 hears 33");
        // 33 hangs up and 32 stays off-hook.  Both latches let go; 32 sends a
        // nail, so it is no caller, and the walk nails both ports again
        hook[P33] = 1'b0;
        t = 0; while (busy[P33] && t < 20000) begin @(posedge fs); t = t + 1; end
        ck(!busy[P33], "33 hung up: both latches let go");
        t = 0; while (!(busy[P32] && busy[P33]) && t < 2 * ROUND) begin ms(1); t = t + 1; end
        ck(busy[P32] && busy[P33] && !rbusy, "the walk nailed both ends again, and 32 got no dial tone");
        rung(P33); ck(r0 && r1, "so 32, still off-hook, rings 33 again (extensions.md 3.2)");
        hook[P32] = 1'b0;
        t = 0; while (busy[P32] && t < 20000) begin @(posedge fs); t = t + 1; end
        t = 0; while (!(busy[P32] && busy[P33]) && t < 2 * ROUND) begin ms(1); t = t + 1; end
        ck(busy[P32] && busy[P33], "32 hung up too: the walk made the private line again");
        idle("nothing else BUSY");

        // ================= 15.  PWAIT =================================================
        $display("  15. PWAIT");
        lift(P22);                                     // 22 holds the one register
        hook[P35] = 1'b1; hook[P36] = 1'b1;
        t = 0; while (!pwait && t < 3 * ROUND) begin ms(1); t = t + 1; end
        ck(pwait, "a round of the walk found 36, a P line, waiting: PWAIT set at 77");
        ck(!busy[P35] && !busy[P36], "neither has the register: 22 has it");
        dial(P22, 2); dial(P22, 1); ms(10);
        ck(busy[P21], "22's call went through, and the register is free");
        t = 0; while (!(busy[P35] || busy[P36]) && t < 2 * ROUND) begin ms(1); t = t + 1; end
        ck(busy[P36] && !busy[P35], "the register went to 36, the P line, not to 35 beside it");
        hook[P36] = 1'b0;
        t = 0; while (!busy[P35] && t < 4 * ROUND) begin ms(1); t = t + 1; end
        ck(busy[P35], "35 got it once no P line was waiting");
        ck(!pwait, "and PWAIT is clear");
        idle("released");

        // ================= 16.  a caller gone at the connect ==========================
        $display("  16. a caller gone at the connect");
        lift(P20); dial(P20, 2);
        hook[P20] = 1'b0; ms(12); hook[P20] = 1'b1;       // the last digit, 1
        t = 0; while (!busy[P21] && t < 100000) begin @(posedge fs); t = t + 1; end
        hook[P20] = 1'b0;                                 // gone at the connect
        ms(100);
        ck(!busy[P21], "the called port was written free: nothing left it BUSY");
        ck(!e[P21], "and it is not ringing");
        idle("released");

        // ================= all down =================================================
        ck(!ovf, "the marker's queue never refused a write");
        ck(!clash, "one master on cable B");

        $display("\n  %0d checks, %0d errors.  %s\n", chk, errs,
                 (errs == 0) ? "PASS" : "FAIL");
        if (errs) $fatal(1);
        $finish;
    end

    initial begin #40_000_000_000; $display("TIMEOUT"); $fatal(1); end
endmodule
