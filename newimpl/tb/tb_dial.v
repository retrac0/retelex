// tb_dial -- the register, reading a rotary dial THROUGH THE 1 kHz A PLANE.
//
// This bench has no counterpart in verilog/, and it is the one the fold owes.
// In the old tree a register read its caller's hook off HA[h] once a frame,
// which is 64 kHz and effectively continuous.  Here it reads it off /HA once
// a pass, which is 1 kHz, and every edge it measures is quantised to 1 ms.
//
// register.md §1's windows are HIT >= 8 ms, ID >= 128 ms, CLR >= 256 ms, and
// dialling.md §3.1's measured envelope is 7 to 20 pps at 56 to 72 % break.
// The corners of that envelope are what this dials:
//
//   7 pps 56 %   make  62.9 ms   the LONGEST make inside a digit, against ID
//   7 pps 72 %   break 102.9 ms  the LONGEST break, against CLR
//  12 pps 56 %   break  46.7 ms  the shortest break at the low rates
//  20 pps 56 %   break  28.0 ms  the shortest break an IDEAL dial sends
//
// NOTE WHAT THIS BENCH DOES NOT DO.  28.0 ms is the corner of the NOMINAL
// envelope; dialling.md §3.1 MEASURED breaks as short as 18 ms at 20 pps, once
// the line card's 6.1 ms and the dial's jitter are in.  18 ms is eighteen
// samples against an eight-sample HIT window, so it holds -- but nothing here
// drives it, and the bench should not be read as proving the measured corner.
`timescale 1ns/1ps
`include "exch.vh"

module tb_dial;
    integer chk = 0, errs = 0;
    task ck(input cond, input [8*60-1:0] what);
        begin chk = chk + 1;
             if (!cond) begin errs = errs + 1; $display("    FAIL  %0s", what); end
        end
    endtask

    reg clk = 1'b0, rst_n = 1'b0;
    always #122.070 clk = ~clk;

    localparam [`PW-1:0] P = 6'o20;      // the caller

    reg [63:0] a_tx = 64'd0;
    wire ha_n, hb_n, hw_n, cap_stb, frame_stb, tick_1k, pass_stb;
    wire [2:0] slotq;
    wire [`SCANW-1:0] scan;

    exch #(.PORT_FITTED(64'h0000_0000_0003_0000),
           .BLOCK_FITTED(8'b0000_0100)) u_x (
        .clk(clk), .rst_n(rst_n),
        .c_tx(64'd0), .a_tx(a_tx), .ans_n({64{1'b1}}), .word_n(64'd0),
        .c_rx(), .a_rx(), .mute_blk(8'd0), .rbt_in(1'b0),
        .sdata(1'b0), .sclk(1'b0), .wr(1'b0), .ws_n(1'b1), .hw_n(hw_n),
        .hc(), .ha_n(ha_n), .hb_n(hb_n), .tick(), .slot(), .slotq(slotq),
        .hclk(), .cap_stb(cap_stb), .tx_clk(),
        .frame_stb(frame_stb), .clk_8k(), .rx_oct(), .oct_stb(),
        .scan(scan), .pass_stb(pass_stb),
        .fill(), .ring_cad_n(), .tick_1k(tick_1k), .port_busy());

    reg attach = 1'b0, release_it = 1'b0;
    wire r_busy, r_gone, r_nodig, r_brk, r_counting, r_hook;
    wire [2:0] r_ndig; wire [15:0] r_digits; wire [`PW-1:0] r_port;

    pulse_reg #(.NODIG(16'd12000)) u_reg (
        .clk(clk), .rst_n(rst_n),
        .slotq(slotq), .cap_stb(cap_stb), .frame_stb(frame_stb),
        .scan(scan), .ha_n(ha_n), .hb_n(hb_n), .tick_1k(tick_1k),
        .attach(attach), .attach_port(P),
        .release_it(release_it), .restart(1'b0),
        .busy(r_busy), .port(r_port), .ndig(r_ndig), .digits(r_digits),
        .gone(r_gone), .nodig(r_nodig), .brk(r_brk), .counting(r_counting),
        .hook(r_hook));

    // A second register with a short NODIG, so the no-digit checks below do not
    // have to sit through the real ten seconds.  It watches the same port.
    reg nd_attach = 1'b0, nd_release = 1'b0;
    wire nd_nodig, nd_counting;
    wire [2:0] nd_ndig;

    pulse_reg #(.NODIG(16'd800)) u_nd (
        .clk(clk), .rst_n(rst_n),
        .slotq(slotq), .cap_stb(cap_stb), .frame_stb(frame_stb),
        .scan(scan), .ha_n(ha_n), .hb_n(hb_n), .tick_1k(tick_1k),
        .attach(nd_attach), .attach_port(P),
        .release_it(nd_release), .restart(1'b0),
        .busy(), .port(), .ndig(nd_ndig), .digits(),
        .gone(), .nodig(nd_nodig), .brk(), .counting(nd_counting),
        .hook());

    task ms(input integer n); begin repeat (n) #1_000_000; end endtask

    // A rotary dial: `pulses` breaks at `pps`, with `brk` percent break.
    task dial(input integer pulses, input integer pps, input integer brk);
        integer i, period, tb, tm;
        begin
            period = 1000 / pps;
            tb     = (period * brk) / 100;
            tm     = period - tb;
            for (i = 0; i < pulses; i = i + 1) begin
                a_tx[P] = 1'b0; ms(tb);
                a_tx[P] = 1'b1; ms(tm);
            end
        end
    endtask

    integer want;
    reg     chatter = 1'b0;
    task one(input integer pulses, input integer pps, input integer brk);
        begin
            want = pulses;
            // a fresh register, and the store empty when it is handed over
            @(posedge clk); release_it = 1'b1; @(posedge clk); release_it = 1'b0;
            a_tx[P] = 1'b0; ms(20);
            @(posedge clk); attach = 1'b1; @(posedge clk); attach = 1'b0;
            ck(r_ndig == 3'd0 && r_digits == 16'd0,
               "the store is empty when the register is handed over");
            a_tx[P] = 1'b1; ms(60);              // lift
            dial(pulses, pps, brk);
            ms(200);                              // the interdigit make, past ID
            ck(r_ndig == 3'd1, "one digit collected");
            ck(r_digits[3:0] == pulses[3:0], "and it is the right pulse count");
            if (r_digits[3:0] != pulses[3:0] || r_ndig != 3'd1)
                $display("       %0d pps %0d%% break, dialled %0d: got ndig %0d, count %0d",
                         pps, brk, pulses, r_ndig, r_digits[3:0]);
            else
                $display("     %2d pps %0d%% break, dialled %2d: counted %2d",
                         pps, brk, pulses, r_digits[3:0]);
        end
    endtask

    initial begin
        $display("\n  tb_dial -- a rotary dial through a 1 kHz sampler");
        repeat (20) @(posedge clk);
        rst_n = 1'b1; ms(5);

        // nominal
        one(1,  10, 60);
        one(5,  10, 60);
        one(10, 10, 60);          // ten pulses: the marker's digit rule makes it 0

        // the corners of dialling.md §3.1's envelope
        one(5,  7,  56);          // longest make inside a digit, 62.9 ms vs ID 128
        one(5,  7,  72);          // longest break, 102.9 ms vs CLR 256
        one(5,  12, 56);          // 46.7 ms break
        one(5,  20, 56);          // 28 ms break -- 28 samples at 1 kHz,
                                  // against an 8-sample HIT window

        // ---- CLR: a break past 256 ms is a hang-up, not a pulse ------------
        @(posedge clk); release_it = 1'b1; @(posedge clk); release_it = 1'b0;
        a_tx[P] = 1'b0; ms(20);
        @(posedge clk); attach = 1'b1; @(posedge clk); attach = 1'b0;
        a_tx[P] = 1'b1; ms(60);
        dial(2, 10, 60);
        ms(200);
        ck(r_digits[3:0] == 4'd2, "two pulses counted before the hang-up");
        a_tx[P] = 1'b0; ms(300);
        ck(r_gone === 1'b1, "266 ms of break is CLR: the caller went away");

        // ---- release --------------------------------------------------------
        @(posedge clk); release_it = 1'b1; @(posedge clk); release_it = 1'b0;
        a_tx[P] = 1'b0; ms(20);
        ck(r_busy === 1'b0, "released");
        ck(r_digits == 16'd0 && r_ndig == 3'd0, "and the store is empty again");

        // ---- the no-digit timeout, from seizure AND from the last digit -----
        // The timeout is `nodig`, beside `gone` (register.md §3), and the
        // timer counts whenever the register is attached, so it runs from the
        // last digit as well as from seizure (register.md §1).  Run on u_nd,
        // whose NODIG is 800 ms, so the bench does not
        // sit through the real ten seconds twice.
        // Case (b) is the one that used to hang: gating the timer on ndig == 0
        // froze it the instant a digit landed, so a caller who dialled one
        // digit and stopped held the exchange's only register until he hung up.

        // (a) off-hook, nothing dialled at all
        @(posedge clk); nd_attach = 1'b1; @(posedge clk); nd_attach = 1'b0;
        a_tx[P] = 1'b1;
        ms(700);
        ck(nd_nodig === 1'b0, "no-digit has not fired at 700 ms of silence");
        ms(200);
        ck(nd_nodig === 1'b1, "no-digit fires at 800 ms off-hook, nothing dialled");

        // (b) ONE digit, then silence -- the partial dial
        @(posedge clk); nd_release = 1'b1; @(posedge clk); nd_release = 1'b0;
        a_tx[P] = 1'b0; ms(20);
        @(posedge clk); nd_attach = 1'b1; @(posedge clk); nd_attach = 1'b0;
        a_tx[P] = 1'b1; ms(60);
        dial(1, 10, 60);
        ms(200);                              // past ID: the digit is in
        ck(nd_ndig === 3'd1, "one digit collected");
        ck(nd_nodig === 1'b0, "and the timer has not fired yet");
        ck(nd_counting === 1'b0, "`counting' falls between digits (register.md §2)");
        ms(500);
        ck(nd_nodig === 1'b0, "still not fired 700 ms after the digit");
        ms(200);
        ck(nd_nodig === 1'b1, "PARTIAL DIAL: it fires 800 ms after the LAST digit");
        ck(nd_ndig === 3'd1, "and the one digit is still in the store");

        // (c) a line that pulses and never ends a digit -- 40 ms break, 40 ms
        // make, for ever.  Every break is past HIT and every make short of ID,
        // so a digit is part way in from the first break on and none is ever
        // strobed.  The timer used to pause while `counting`, and this line held
        // the exchange's only register until it hung up (F36).
        @(posedge clk); nd_release = 1'b1; @(posedge clk); nd_release = 1'b0;
        a_tx[P] = 1'b0; ms(20);
        a_tx[P] = 1'b1; ms(20);
        @(posedge clk); nd_attach = 1'b1; @(posedge clk); nd_attach = 1'b0;
        chatter = 1'b1;
        fork
            while (chatter) begin a_tx[P] = 1'b0; ms(40); a_tx[P] = 1'b1; ms(40); end
            begin
                ms(700);
                ck(nd_counting === 1'b1 && nd_ndig === 3'd0,
                   "a pulsing line is part way into a digit, and none is in");
                ck(nd_nodig === 1'b0, "no-digit has not fired at 700 ms");
                ms(200);
                ck(nd_nodig === 1'b1, "PULSING: it fires 800 ms after seizure all the same");
                chatter = 1'b0;
            end
        join
        a_tx[P] = 1'b0;

        $display("\n  %0d checks, %0d errors.  %s\n", chk, errs,
                 (errs == 0) ? "PASS" : "FAIL");
        if (errs) $fatal(1);
        $finish;
    end

    initial begin #40_000_000_000; $display("  TIMEOUT"); $fatal(1); end
endmodule
