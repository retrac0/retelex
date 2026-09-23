// tb_su1 -- su-1.md: the pad, the two line patterns, mute, the talk UI,
// the loop-timed clock and its LED, ring trip and glare, and a local call.
`timescale 1ns/1ps

module tb_su1;
    integer errs = 0, chk = 0;

    task want(input v, input string what);
        begin
            chk = chk + 1;
            if (!v) begin errs = errs + 1; $display("     %-52s FAIL", what); end
            else $display("     %-52s ok", what);
            $fflush();
        end
    endtask

    // ---- unit: the set runs on a recovered 64 kHz strobe, nothing else ----
    // bit_stb every 10 clks, TICK_DIV 10, so TICK is still one per 100 clks
    // and the millisecond numbers below read as they always did.
    reg clk = 0, rst_n = 0, u_bit = 0, g_carrier = 1;
    always #5 clk = ~clk;
    reg [6:0] bdiv = 0;
    always @(posedge clk) begin
        u_bit <= 1'b0;
        if (bdiv == 7'd9) begin bdiv <= 0; u_bit <= g_carrier; end
        else bdiv <= bdiv + 1'b1;
    end

    reg        g_hook = 0;
    reg [15:0] g_key = 16'hFFFF;
    reg        g_e = 0;
    reg        g_cv = 0;
    reg        g_rx = 0;
    reg        g_spk = 0, g_pttm = 0, g_ptt = 0;
    wire       g_m, g_tx, g_ring, g_mute, g_bdec, g_offn;
    wire       g_micen, g_earm, g_spken, g_led, g_tick;
    wire [3:0] rx_cnt;
    wire       rx_stb;

    su1 #(.T_OH(10), .T_ID(200), .DEBOUNCE(2),
          .TICK_DIV(10), .LED_DIV(64)) u_g (
        .clk(clk), .rst_n(rst_n), .bit_stb(u_bit), .carrier(g_carrier),
        .hook_sw(g_hook), .key_n(g_key),
        .spk_sw(g_spk), .ptt_mode(g_pttm), .ptt(g_ptt),
        .rx(g_rx), .e(g_e), .cv_bit(g_cv),
        .m(g_m), .tx(g_tx), .ring(g_ring), .mute(g_mute),
        .bit_dec(g_bdec), .off_normal(g_offn),
        .mic_en(g_micen), .ear_mute(g_earm), .spk_en(g_spken),
        .led(g_led), .tick_1k(g_tick));

    pulse_rx #(.HIT(8), .ID(128), .CLR(256)) u_rx (
        .clk(clk), .rst_n(rst_n), .tick_1k(g_tick), .arm(g_hook), .m(g_m),
        .cnt(rx_cnt), .dig_stb(rx_stb), .clear(), .counting(), .brk_stb());

    task utick(input integer n);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                @(posedge clk);
                while (!g_tick) @(posedge clk);
            end
        end
    endtask

    task ubit(input integer n);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                @(posedge clk);
                while (!u_bit) @(posedge clk);
            end
        end
    endtask

    // The exchange's own test: X = Q ^ Q[n-2] is constantly 1 under 1100 and
    // constantly 0 under 1010 (subscriber-line.md §2).  Sample the line the
    // way the hook detector does and count both ways.
    integer x_one, x_zero;
    task sample_line(input integer n);
        reg [2:0] h;
        integer i;
        begin
            x_one = 0; x_zero = 0; h = 3'd0;
            for (i = 0; i < n; i = i + 1) begin
                ubit(1);
                h = {h[1:0], g_tx};
                if (i >= 2) begin
                    if (h[2] != h[0]) x_one = x_one + 1;
                    else              x_zero = x_zero + 1;
                end
            end
        end
    endtask

    task expect_dig(input [3:0] n, input string what);
        integer guard;
        begin
            guard = 0;
            while (!rx_stb && guard < 4000) begin
                @(posedge clk);
                if (g_tick) guard = guard + 1;
            end
            want(rx_stb && rx_cnt == n, what);
            @(posedge clk);
        end
    endtask

    // Hold pin n (1..16) long enough for debounce.  FO=13, F=14, I=15, P=16.
    task press(input [4:0] n);
        begin
            g_key = ~(16'b1 << (n - 1));
            utick(8);
            g_key = 16'hFFFF;
            utick(4);
        end
    endtask

    reg        g_lastm = 1'b0;
    reg [9:0]  g_wcnt = 0, g_brk = 0, g_mk = 0;
    always @(posedge clk) if (g_tick) begin
        if (g_lastm != g_m) begin
            if (!g_lastm && g_m) g_brk <= g_wcnt;
            if ( g_lastm && !g_m) g_mk  <= g_wcnt;
            g_wcnt <= 0;
        end else if (g_wcnt != 10'h3FF) g_wcnt <= g_wcnt + 1'b1;
        g_lastm <= g_m;
    end

    // ---- originate: net_site, scaled windows ----
    localparam integer HIT = 1, ID = 16, CLR = 32;
    localparam integer T_RISE = 64, T_FALL = 2048;
    localparam integer RING_ON = 200, RING_OFF = 400;
    localparam integer FR = 15625;

    reg clk_a = 0, clk_b = 0, rst_net = 0;
    always #122.0703 clk_a = ~clk_a;
    initial begin #40; forever #122.0703 clk_b = ~clk_b; end

    wire la_out, lb_out, lock_a, lock_b, fs_a, rc_a, rc_b;
    wire dt_a, ng_a, mh_b, gc_a;
    wire [63:0] ln_a, ln_b, rx_a, rx_b;

    wire       su_m, su_tx;
    reg        n_hook = 0;
    reg [15:0] n_key = 16'hFFFF;
    reg        ans_a21 = 0;
    wire [63:0] hk_a = {46'd0, ans_a21, su_m, 16'd0};
    wire [63:0] hk_b = {47'd0, 1'b0, 16'd0};
    wire [63:0] tx_a = {47'd0, su_tx, 16'd0};

    wire       tick_a, fs_net;
    net_site #(.OWN_E(3'd2), .OWN_B(3'd2), .T_RISE(T_RISE), .T_FALL(T_FALL),
               .RING_ON(RING_ON), .RING_OFF(RING_OFF),
               .HIT(HIT), .ID(ID), .CLR(CLR), .T_GUARD(16), .T_CLAIM(250))
    A (.clk(clk_a), .rst_n(rst_net),
       .hook(hk_a), .tx(tx_a), .rx(rx_a), .e(ln_a),
       .line_in(lb_out), .line_out(la_out), .locked(lock_a),
       .frame_stb(fs_net), .tick_1k(tick_a), .ring_cad_n(rc_a), .dt_bit(dt_a), .ng_bit(ng_a),
       .mon_held(), .got_claim(gc_a), .dirs_held(),
       .fan_legs(), .res_used(), .port_busy(), .regs_busy(), .wq_ovf(), .n_defer(),
       .wr_stb(), .wr_dst(), .wr_src(), .wr_bsy(), .wr_clm());

    net_site #(.OWN_E(3'd2), .OWN_B(3'd3), .DIR0(2'd3), .G0(1'b1),
               .T_RISE(T_RISE), .T_FALL(T_FALL),
               .RING_ON(RING_ON), .RING_OFF(RING_OFF),
               .HIT(HIT), .ID(ID), .CLR(CLR), .T_GUARD(16), .T_CLAIM(250))
    B (.clk(clk_b), .rst_n(rst_net),
       .hook(hk_b), .tx(64'd0), .rx(rx_b), .e(ln_b),
       .line_in(la_out), .line_out(lb_out), .locked(lock_b),
       .frame_stb(fs_a), .ring_cad_n(rc_b), .dt_bit(), .ng_bit(),
       .mon_held(mh_b), .got_claim(), .dirs_held(),
       .fan_legs(), .res_used(), .port_busy(), .regs_busy(), .wq_ovf(), .n_defer(),
       .wr_stb(), .wr_dst(), .wr_src(), .wr_bsy(), .wr_clm());

    // Loop-timed off the exchange's own 64 kHz frame strobe: the set has no
    // crystal, so the site's clock is the set's clock (su-1.md §5).
    su1 #(.PPS(50), .BREAK_PCT(60), .T_OH(40), .T_ID(60), .DEBOUNCE(2),
          .TICK_DIV(64), .LED_DIV(1024)) u_net (
        .clk(clk_a), .rst_n(rst_net), .bit_stb(fs_net), .carrier(1'b1),
        .hook_sw(n_hook), .key_n(n_key),
        .spk_sw(1'b0), .ptt_mode(1'b0), .ptt(1'b0),
        .rx(rx_a[6'o20]), .e(ln_a[6'o20]), .cv_bit(1'b0),
        .m(su_m), .tx(su_tx), .ring(), .mute(), .bit_dec(), .off_normal(),
        .mic_en(), .ear_mute(), .spk_en(), .led(), .tick_1k());

    task npress(input [4:0] n);
        begin
            n_key = ~(16'b1 << (n - 1));
            #(30_000_000);
            n_key = 16'hFFFF;
            #(20_000_000);
        end
    endtask

    task ring_a21(input integer n, input string what);
        integer i, hi, lo;
        begin
            hi = 0; lo = 0;
            for (i = 0; i < n; i = i + 1) begin
                #(FR);
                if (ln_a[6'o21] && !rc_a) hi = hi + 1;
                if (!ln_a[6'o21]) lo = lo + 1;
            end
            chk = chk + 1;
            if (hi > 0 && lo > 0)
                $display("     %-52s ok", what);
            else begin errs = errs + 1;
                $display("     %-52s FAIL (%0d/%0d)", what, hi, lo); end
            $fflush();
        end
    endtask

    integer bdec_hi, bdec_lo, led_hi, led_lo, i;

    initial begin
        $display("SU-1 (RTL) -- su-1.md: pad, line patterns, talk UI, LED, a call.\n");
        $fflush();
        #200 rst_n = 1;
        utick(5);

        // ---- 1. the line on-hook is 1100, the mute pattern is 1010 ----
        $display("  1. The two held patterns (subscriber-line.md §2)."); $fflush();
        g_hook = 0; ubit(4);
        sample_line(40);
        want(x_one == 38 && x_zero == 0,
             "on-hook: Q^Q[n-2] is 1 throughout -- 1100");

        // ---- 2. 10 pps 60/40, digit 5, and 1100 under the breaks ----
        $display("  2. Loop-timed 10 pps 60/40, digit 5."); $fflush();
        g_hook = 1; utick(12);
        press(5'd5);
        expect_dig(4'd5, "register counts 5");
        want(g_brk >= 58 && g_brk <= 62, "break is 60 ticks");
        want(g_mk  >= 38 && g_mk  <= 42, "make is 40 ticks");
        g_hook = 0; utick(30);

        // ---- 3. Autovon map: 0 * # FO F I P (register saturates at 15) ----
        $display("  3. Autovon map: 0 * # FO F I P."); $fflush();
        g_hook = 1; utick(12);
        press(5'd10); expect_dig(4'd10, "0 is 10 pulses");
        press(5'd11); expect_dig(4'd11, "* is 11 pulses");
        press(5'd12); expect_dig(4'd12, "# is 12 pulses");
        press(5'd13); expect_dig(4'd13, "FO is 13 pulses");
        press(5'd14); expect_dig(4'd14, "F is 14 pulses");
        press(5'd15); expect_dig(4'd15, "I is 15 pulses");
        press(5'd16); expect_dig(4'd15, "P is 16 pulses, register saturates at 15");
        g_hook = 0; utick(30);

        // ---- 4. mute while off-normal: the makes carry 1010 ----
        $display("  4. Mute while dial off-normal (register.md §1.1)."); $fflush();
        g_hook = 1; g_cv = 1'b1; utick(12);
        want(!g_mute && g_tx == 1'b1, "talking: unmute, cv_bit on tx");
        press(5'd3);
        begin : wait_mute
            integer guard;
            guard = 0;
            while (!(g_mute && !g_m) && guard < 500) begin utick(1); guard = guard + 1; end
            want(g_mute, "mute asserts for the train");
        end
        sample_line(8);
        want(x_one == 6 && x_zero == 0, "a break still carries 1100");
        while (!g_m) utick(1);                   // into the make
        sample_line(8);
        want(x_zero == 6 && x_one == 0, "the make carries 1010, not speech");
        expect_dig(4'd3, "digit 3 still counted");
        g_hook = 0; g_cv = 0; utick(30);

        // ---- 5. ring, decoder 1010, ring trip and glare ----
        $display("  5. Ring, ring trip, and glare (subscriber-line.md §7)."); $fflush();
        g_rx = 1'b1;
        g_hook = 0; g_e = 1; utick(4);
        want(g_ring, "RING · ON-HOOK arms the sounder");
        want(g_spken && g_earm && !g_micen, "ringing: speaker on, ear muted, mic shut");
        bdec_hi = 0; bdec_lo = 0;
        for (i = 0; i < 20; i = i + 1) begin
            ubit(1);
            if (g_bdec) bdec_hi = bdec_hi + 1;
            else        bdec_lo = bdec_lo + 1;
        end
        want(bdec_hi > 0 && bdec_lo > 0, "bit_dec is 1010 while ringing");
        // Glare: the hook closes inside the burst, before the exchange has
        // switched its transmitter.  The set must leave 1010 at once.
        g_hook = 1; @(posedge clk);
        want(!g_ring && g_bdec == g_rx, "lift trips the ringer and drops 1010 at once");
        g_e = 0; g_hook = 0; g_rx = 0; utick(10);

        // ---- 6. the talk UI (§3.2) ----
        $display("  6. HANDSET / SPEAKER, LIVE / PTT."); $fflush();
        g_hook = 1; g_spk = 0; g_pttm = 0; g_ptt = 0; utick(4);
        want(g_micen && !g_earm && !g_spken, "HANDSET + LIVE: mic open, ear live");
        g_spk = 1; utick(1);
        want(g_micen && g_earm && g_spken, "SPEAKER: ear muted, loudspeaker on");
        g_pttm = 1; utick(1);
        want(!g_micen, "PTT mode, button up: mic shut");
        g_ptt = 1; utick(1);
        want(g_micen, "PTT held: mic open");
        g_ptt = 0; g_pttm = 0; g_spk = 0;
        press(5'd2);
        while (!g_mute) utick(1);
        want(!g_micen, "dial MUTE overrides LIVE");
        g_hook = 0; utick(30);

        // ---- 7. the loop-timed clock and its LED (§5) ----
        $display("  7. Loop timing: no downstream, no clock."); $fflush();
        led_hi = 0; led_lo = 0;
        for (i = 0; i < 256; i = i + 1) begin
            ubit(1);
            if (g_led) led_hi = led_hi + 1; else led_lo = led_lo + 1;
        end
        want(led_hi > 0 && led_lo > 0, "LED blinks off the recovered clock");
        g_carrier = 0;
        repeat (400) @(posedge clk);
        want(!g_led, "carrier lost: LED dark");
        g_hook = 1;
        repeat (4000) @(posedge clk);
        want(!g_m, "no strobe, no seizure -- the set has no crystal");
        g_hook = 0; g_carrier = 1; utick(20);

        // ---- 8. local call: 20 dials 2 1 ----
        $display("  8. SU-1 originates: 20 dials 2 1.");
        $fflush();
        rst_net = 1;
        #(20_000_000);
        want(lock_a && lock_b, "link up");
        n_hook = 1;
        #(80_000_000);
        npress(5'd2);
        #(150_000_000);
        npress(5'd1);
        #(80_000_000);
        ring_a21(2 * (RING_ON + RING_OFF),
                  "A's 21 rings, originated from SU-1");
        ans_a21 = 1;
        #(20_000_000);
        want(ln_a[6'o20] && ln_a[6'o21], "answered: E steady at both");
        ans_a21 = 0; n_hook = 0;
        #(80_000_000);
        want(!ln_a[6'o20] && !ln_a[6'o21], "both released");

        $display("\n  %0d checks, %0d errors.  %s", chk, errs, (errs == 0) ? "PASS" : "FAIL");
        if (errs) $fatal(1);
        $finish;
    end
endmodule
