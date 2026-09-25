// tb_mini -- the minimum that makes calls.  mvp.md 3, mini-marker.md 4 and 5.
//
// Two phones on block 2.  20 lifts, is given the register within one 1 ms
// pass, dials 2 1, 21 rings, 21 answers, and either may hang up first -- the
// ports release themselves and nobody is in charge of the call.  Then the
// wrong numbers.
//
// Fitted: line cards at 20 and 21, and source cards at 01 (dial tone) and 03
// (cannot-complete) so that WHICH tone a caller was pointed at is observable.
// A source ties its /ANS low -- it answers at once and must never ring -- and
// never raises M, so it is never a caller.
`timescale 1ns/1ps
`include "exch.vh"

module tb_mini;
    integer chk = 0, errs = 0;
    task ck(input cond, input [8*64-1:0] what);
        begin chk = chk + 1;
             if (!cond) begin errs = errs + 1; $display("    FAIL  %0s", what); end
        end
    endtask

    reg clk = 1'b0, rst_n = 1'b0;
    always #122.070 clk = ~clk;

    localparam [`PW-1:0] A = 6'o20, B = 6'o21, DT = 6'o01, NG = 6'o03;

    reg  [63:0] c_tx  = 64'd0;
    reg  [63:0] a_tx  = 64'd0;
    reg  [63:0] ans_n = {64{1'b1}};
    wire [63:0] c_rx, a_rx, port_busy;
    wire ha_n, hb_n, hw_n, fill, tick_1k, pass_stb, ring_cad_n, frame_stb;
    wire pr_fresh;
    wire [`SCANW-1:0] scan;
    wire [`PW-1:0] mk_caller, mk_called, pr_port;
    wire [1:0] mk_state;
    wire r_busy; wire [2:0] r_ndig; wire [15:0] r_digits;

    // The cadence is cut to 64 ms on / 128 ms off.  Same counter and the same
    // 1:2 shape as the real 2.048 s / 4.096 s; watching six seconds of the
    // real one proves nothing the ratio does not.
    top_min #(.PORT_FITTED(64'h0000_0000_0003_000A),   // 01, 03, 20, 21
              .SHUNT_FITTED(8'b0000_0101),             // blocks 0 and 2
              .RING_ON_MS(13'd64), .RING_OFF_MS(13'd128),
              .NODIG(16'd1000)) u_top (
        .clk(clk), .rst_n(rst_n),
        .c_tx(c_tx), .a_tx(a_tx), .ans_n(ans_n), .word_n(64'd0),
        .c_rx(c_rx), .a_rx(a_rx),
        .mute_blk(8'd0), .rbt_in(1'b0),
        .hc(), .ha_n(ha_n), .hb_n(hb_n), .scan(scan), .frame_stb(frame_stb),
        .pass_stb(pass_stb),
        .tick_1k(tick_1k), .fill(fill), .ring_cad_n(ring_cad_n),
        .port_busy(port_busy), .hw_n(hw_n),
        .probe_port(pr_port), .probe_m(), .probe_busy(),
        .probe_fresh(pr_fresh),
        .reg_busy(r_busy), .reg_ndig(r_ndig), .reg_digits(r_digits),
        .caller(mk_caller), .called(mk_called), .mk_state(mk_state));

    task ms(input integer n); begin repeat (n) #1_000_000; end endtask

    task dial(input integer p, input integer pulses);
        integer i;
        begin
            for (i = 0; i < pulses; i = i + 1) begin
                a_tx[p] = 1'b0; ms(60);
                a_tx[p] = 1'b1; ms(40);
            end
            ms(200);                       // the interdigit make, past ID
        end
    endtask

    // What is this port hearing?  A steady level is a source card; FILL's
    // 1010 alternates every frame, and so does the ringback bus when no
    // ringback card is fitted (mainboard.md 2.1: RBT is pulled to FILL).
    integer j; reg s0, s1;
    task sample(input integer p, input integer n);
        begin
            s0 = 1'b0; s1 = 1'b0;
            for (j = 0; j < n; j = j + 1) begin
                @(posedge frame_stb); @(posedge clk);
                if (c_rx[p]) s1 = 1'b1; else s0 = 1'b1;
            end
        end
    endtask

    integer t_lift, t_seize;
    reg [31:0] msc = 32'd0;
    always @(posedge tick_1k) msc = msc + 1;

    integer ring_hi, ring_lo;
    reg watch_ring = 1'b0;
    always @(posedge tick_1k) if (watch_ring) begin
        if (a_rx[B]) ring_hi = ring_hi + 1; else ring_lo = ring_lo + 1;
    end

    initial begin
        $display("\n  tb_mini -- two phones, two digits, and nobody in charge");
        // the two sources: 01 sends all ones, 03 sends all zeros, and both
        // tie /ANS low so they never ring
        c_tx[DT] = 1'b1; c_tx[NG] = 1'b0;
        ans_n[DT] = 1'b0; ans_n[NG] = 1'b0;

        repeat (20) @(posedge clk);
        rst_n = 1'b1; ms(10);

        // ================= 1.  a call, 20 to 21 =========================
        t_lift = msc;
        a_tx[A] = 1'b1;                                   // 20 lifts
        @(posedge clk);
        while (mk_state == 2'd0) @(posedge clk);
        t_seize = msc;
        // One pass is 1 ms, and the probe publishes at the frame edge after
        // the capture, so the worst case is one pass plus a bit-time.  This is
        // ONE SAMPLE at 1 ms resolution against a 2 ms bound -- it does not
        // pin the worst phase, and tb_ha's sweep is what measures that.
        ck((t_seize - t_lift) <= 2, "the scanner offers 20 within one 1 ms pass");
        $display("     seized %0d ms after the lift (a pass is 1 ms)",
                 t_seize - t_lift);
        ms(5);
        ck(mk_caller === A, "the marker took 20 as the caller");
        ck(r_busy === 1'b1, "and gave it the register");
        ck(c_rx[A] === 1'b1, "20 is listening to 01: dial tone");

        dial(A, 2);                                        // first digit 2
        ms(5);
        ck(r_ndig >= 3'd1, "the first digit is in");
        sample(A, 8);
        ck(s0 && s1, "dial tone is dropped: 20 is on 00 and hears FILL");

        dial(A, 1);                                        // second digit 1
        ms(20);
        ck(mk_state === 2'd0, "the marker is done and back to IDLE");
        ck(r_busy === 1'b0, "and the register is free again");
        ck(port_busy[A] === 1'b1 && port_busy[B] === 1'b1, "both ports are busy");

        // ---- while 21 is rung, 20 hears RBT and NOT 21's card -------------
        // fabric.md 3.1 and 3.5: RB = ON . E puts the ringback bus into 21's
        // highway cell through the block's '157.  With no ringback card
        // fitted RBT is pulled to FILL, so what the caller gets is silence --
        // mvp.md 2's documented behaviour, and it alternates.
        c_tx[B] = 1'b1;
        sample(A, 8);
        ck(s0 && s1, "20 hears ringback, not 21's card: the '157 substituted");

        // ---- 21 rings, in cadence ---------------------------------------
        ring_hi = 0; ring_lo = 0; watch_ring = 1'b1;
        ms(400);
        watch_ring = 1'b0;
        ck(ring_hi > 50 && ring_lo > 50,
           "21 is being rung: A_RX chopped by the cadence, on and off");
        $display("     21 rang %0d ms on, %0d ms off in 400 ms (64/128 cadence)",
                 ring_hi, ring_lo);

        // ---- 21 answers ---------------------------------------------------
        a_tx[B] = 1'b1;
        ms(40);
        ring_hi = 0; ring_lo = 0; watch_ring = 1'b1;
        ms(400);
        watch_ring = 1'b0;
        ck(ring_lo == 0, "21 answered: the ringing stopped at once");
        ck(a_rx[A] === 1'b1, "and 20 has E: the call is up both ways");

        // ---- and now the substitution is off, so the voice path is real ----
        c_tx[B] = 1'b1; ms(2); ck(c_rx[A] === 1'b1, "20 hears 21's card");
        c_tx[B] = 1'b0; ms(2); ck(c_rx[A] === 1'b0, "and follows it");
        c_tx[A] = 1'b1; ms(2); ck(c_rx[B] === 1'b1, "21 hears 20: the other direction");
        c_tx[A] = 1'b0; ms(2); ck(c_rx[B] === 1'b0, "and it is a separate square");

        // ---- either may hang up first.  21 goes first. ---------------------
        // A port's BUSY OUTLIVES ITS LATCH, deliberately: marker.md 5.2's
        // stale-release guard holds it busy while either detector is still
        // timing out, so a port that has just dropped a call cannot be handed
        // a new one in the same breath.  The latch clears at 256 ms; BUSY
        // follows when the detectors have run down.
        a_tx[B] = 1'b0;
        ms(200);
        ck(port_busy[B] === 1'b1, "21 is still busy 200 ms after hanging up");
        ms(120);
        sample(B, 8);
        ck(s0 && s1, "at 256 ms 21's own latch cleared: it hears 00, which is FILL");
        ms(500);
        ck(port_busy[B] === 1'b0, "and its detectors ran down: 21 is idle");

        // 20 is still off-hook with an idle latch: that is a new call request
        ck(mk_state !== 2'd0 || r_busy === 1'b1,
           "20 still off-hook with a clear latch is a new call request");
        a_tx[A] = 1'b0; ms(700);
        ck(port_busy[A] === 1'b0 && port_busy[B] === 1'b0,
           "every latch idle and every BUSY clear at the end");

        // ================= 2.  wrong numbers ============================
        // mini-marker.md 5.  0, 8 and 9 all fold to 0 by the digit rule.
        a_tx[A] = 1'b1; ms(10);
        dial(A, 10);                                       // dialled 0
        ms(20);
        sample(A, 8);
        ck(s0 && !s1, "dialling 0 gives cannot-complete: 20 hears 03, steady 0");
        ck(mk_state === 2'd0, "and the marker has left");
        a_tx[A] = 1'b0; ms(400);

        // its own number
        a_tx[A] = 1'b1; ms(10);
        dial(A, 2); dial(A, 10);                           // 2 then 0 -> 20
        ms(20);
        sample(A, 8);
        ck(s0 && !s1, "dialling its own number gives cannot-complete");
        a_tx[A] = 1'b0; ms(400);

        // an empty slot -- 25 has no port circuit.  mini-marker.md 5: this
        // marker treats it as free and points the caller at it, which is why
        // the class marker reads the card's word.
        a_tx[A] = 1'b1; ms(10);
        dial(A, 2); dial(A, 5);
        ms(20);
        ck(port_busy[A] === 1'b1, "25 is an empty slot: the caller is pointed at it");
        a_tx[A] = 1'b0; ms(400);
        ck(port_busy[A] === 1'b0, "and gets it back when it hangs up");

        // abandon mid-dial: no latch left pointing at 03
        a_tx[A] = 1'b1; ms(10);
        dial(A, 2);
        a_tx[A] = 1'b0; ms(400);
        ck(port_busy[A] === 1'b0, "hang up mid-dial and the port is free");
        ck(r_busy === 1'b0, "and the register let go");

        // off-hook and nothing dialled: the no-digit timeout (cut to 1 s)
        a_tx[A] = 1'b1; ms(1200);
        sample(A, 8);
        ck(s0 && !s1, "no digits: cannot-complete after the timeout");
        a_tx[A] = 1'b0; ms(400);
        ck(port_busy[A] === 1'b0, "and the port frees itself");

        $display("\n  %0d checks, %0d errors.  %s\n", chk, errs,
                 (errs == 0) ? "PASS" : "FAIL");
        if (errs) $fatal(1);
        $finish;
    end

    initial begin #60_000_000_000; $display("  TIMEOUT"); $fatal(1); end
endmodule
