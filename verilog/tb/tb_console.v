// tb_console -- two masters on cable B: the marker and the operator's console.
// ex-console.md.
//
// exch-mainboard.md 2.3 calls the control bus multi-master and gives the
// console one line, /CON -- "the marker's drivers go high-impedance.  One '244
// enable".  exch-marker.md 8 lists a second master as not modelled.  This is
// the model, and the things the console is FOR:
//
//   1  ARBITRATION UNDER TRAFFIC.  Sixteen lines calling each other at random
//      while the console writes a word every few milliseconds -- hundreds of
//      times an operator's rate, and two in three of them AIMED at a word the
//      marker is already shifting.  A listener on the bus checks every word either master
//      believes it sent against what the blocks actually saw
//   2  what a console word costs: its tenure, and the scan it lands in
//   3  FORCED RELEASE: one end, then the other; and a port held by nothing
//   4  make-busy by a latch write, and how long it lasts
//   5  SERVICE OBSERVING: a sink pointed at each party of a call, the call
//      checked bit for bit across the writes; the observation ending itself
//   6  HOLD: the marker stopped, and a call carrying on without it
//
// NAIVE = 1 builds /CON as first written -- a '244 enable and nothing else --
// runs part 1 only, and is there to be measured against (`make console-naive`).
`timescale 1ns/1ps

module tb_console #(
    parameter         NAIVE      = 1'b0,
    parameter integer TRAFFIC_MS = 5000,     // each of part 1's two runs
    parameter integer SEED       = 32'h1234_5678
) ();
    localparam real    NS = 1_000_000.0;                 // ns in a model ms -- real: 5000 of them overflow an integer
    localparam integer T_RISE = 64, T_FALL = 2048;       // 1 ms and 32 ms: an eighth of real
    localparam integer BRK = 12, MK = 8, PAUSE = 60;     // ms: a dial, at the same eighth
    localparam integer DT_WAIT = 600;
    localparam [5:0]   PDT = 6'o10, PNG = 6'o14, SK0 = 6'o76, SK1 = 6'o77;

    reg clk = 0, rst_n = 0;
    always #122.0703 clk = ~clk;

    reg  [63:0] hook = 0, tx = 0;
    wire [63:0] rx, e, pbusy;
    wire [1:0]  sink_rx;
    reg         key_write = 0, key_release = 0, key_hold = 0, key_arm = 0;
    reg  [5:0]  sw_dst = 0, sw_src = 0;
    reg         sw_bsy = 0, sw_clm = 0;
    wire        con_busy, con_done, w_bsy, w_clm, w_seen;
    wire [5:0]  w_src;
    wire        b_sdata, b_sclk, b_wr, con_n, con_oe, mk_drv, fs, tick_1k, dt_bit, ng_bit;
    localparam integer NREG = 6;                         // enough that dial tone is never waiting for a register
    wire [NREG-1:0] regs;
    wire        wq_ovf, wr_stb, wr_bsy, wr_clm;
    wire [5:0]  wr_dst, wr_src;

    con_site #(.NAIVE(NAIVE), .T_RISE(T_RISE), .T_FALL(T_FALL), .NREG(NREG)) S (
        .clk(clk), .rst_n(rst_n), .hook(hook), .tx(tx), .rx(rx), .e(e),
        .sink_rx(sink_rx),
        .key_write(key_write), .key_release(key_release),
        .key_hold(key_hold), .key_arm(key_arm),
        .sw_dst(sw_dst), .sw_src(sw_src), .sw_bsy(sw_bsy), .sw_clm(sw_clm),
        .con_busy(con_busy), .con_done(con_done),
        .watch_src(w_src), .watch_bsy(w_bsy), .watch_clm(w_clm), .watch_seen(w_seen),
        .b_sdata(b_sdata), .b_sclk(b_sclk), .b_wr(b_wr),
        .con_n(con_n), .con_oe(con_oe), .mk_drv(mk_drv),
        .frame_stb(fs), .tick_1k(tick_1k), .dt_bit(dt_bit), .ng_bit(ng_bit),
        .port_busy(pbusy), .regs_busy(regs), .wq_ovf(wq_ovf),
        .wr_stb(wr_stb), .wr_dst(wr_dst), .wr_src(wr_src),
        .wr_bsy(wr_bsy), .wr_clm(wr_clm));

    // ---- who each port is listening to -----------------------------------
    // tb_stress's trick: every line sends eight ones and then its own name, so
    // anything that hears a line can say WHICH line.  The two sinks send
    // nothing and are decoded the same way.
    localparam [7:0] NONE = 8'hFF;
    reg  [3:0] txbit [0:63];
    reg [15:0] shift [0:63];
    reg  [7:0] heard [0:63], cand [0:63], hage [0:63];

    function [7:0] nm(input integer port); nm = {2'b00, port[5:0]}; endfunction
    function       is_line(input integer q); is_line = (q >= 16 && q < 32); endfunction
    function       is_sink(input integer q); is_sink = (q == 62 || q == 63); endfunction

    // A name counts when it arrives twice running, and lapses 200 frames after
    // the last good one.  ONE assignment to `hage` a pass: written as a reset
    // inside the match and an increment after it, the increment is the later
    // non-blocking assignment and wins, the age never resets, and `heard`
    // drops to NONE for a name's length every 200 frames -- which a persistence
    // test then never gets past.
    integer q;
    reg     rxb, hit;
    always @(posedge clk) if (fs) begin
        for (q = 16; q < 64; q = q + 1) if (is_line(q) || is_sink(q)) begin
            if (is_line(q)) begin
                txbit[q] <= txbit[q] + 4'd1;
                tx[q]    <= (txbit[q] < 4'd8) ? 1'b1 : nm(q) >> (4'd15 - txbit[q]);
            end
            rxb = is_sink(q) ? sink_rx[q - 62] : rx[q];
            shift[q] <= {shift[q][14:0], rxb};
            hit = 1'b0;
            if (shift[q][15:8] == 8'hFF && !shift[q][7]) begin
                hit = (cand[q] == shift[q][7:0]);
                cand[q] <= shift[q][7:0];
            end
            if (hit)                    begin heard[q] <= shift[q][7:0]; hage[q] <= 8'd0; end
            else if (hage[q] == 8'd200) heard[q] <= NONE;
            else                        hage[q] <= hage[q] + 8'd1;
        end
    end

    reg [6:0] frc = 0;
    reg       ms_stb = 1'b0;
    always @(posedge clk) begin
        ms_stb <= 1'b0;
        if (fs) begin
            if (frc == 7'd63) begin frc <= 0; ms_stb <= 1'b1; end
            else frc <= frc + 7'd1;
        end
    end

    // ---- a listener on cable B: what the BLOCKS saw ----------------------
    // Two '164 and nothing else, as any block has.  Every word either master
    // believes it sent is checked against this.
    reg [15:0] lsr = 0, mk_word = 0, cn_word = 0, cn_expect = 0;
    reg        sclk_d = 0, wr_d = 0, conn_d = 1;
    integer    wr_len = 0, mk_since = 0, cn_since = 0;
    integer    n_mk_said = 0, n_mk_lost = 0, n_mk_mangled = 0;
    integer    n_cn_said = 0, n_cn_bad = 0;
    integer    n_runt = 0, n_contend = 0, n_mid = 0, n_mid_wr = 0;
    integer    lw_src [0:63], lw_bsy [0:63];
    real       lw_t [0:63];
    real       t_con = 0, ten_max = 0, ten_min = 1e12;

    always @(posedge clk) if (rst_n) begin
        sclk_d <= b_sclk; wr_d <= b_wr; conn_d <= con_n;
        if (b_sclk && !sclk_d) lsr <= {lsr[14:0], b_sdata};
        if (b_wr && !wr_d) begin
            if (con_oe) begin cn_word = lsr; cn_since = cn_since + 1; end
            else        begin mk_word = lsr; mk_since = mk_since + 1; end
            if (lsr[15]) begin
                lw_src[lsr[13:8]] = lsr[7:2]; lw_bsy[lsr[13:8]] = lsr[1];
                lw_t[lsr[13:8]] = $realtime;
            end
        end
        if (b_wr) wr_len = wr_len + 1;
        else begin
            if (wr_d && wr_len < 4) n_runt = n_runt + 1;       // the marker's WR is four clocks
            wr_len = 0;
        end
        if (mk_drv && con_oe) n_contend = n_contend + 1;        // two '244s on one wire

        if (wr_stb) begin
            n_mk_said = n_mk_said + 1;
            if (mk_since == 0) n_mk_lost = n_mk_lost + 1;
            else if (mk_word != {1'b1, 1'b0, wr_dst, wr_src, wr_bsy, wr_clm})
                n_mk_mangled = n_mk_mangled + 1;
            mk_since = 0;
        end
        if (con_done) begin
            n_cn_said = n_cn_said + 1;
            if (cn_since == 0 || cn_word != cn_expect) n_cn_bad = n_cn_bad + 1;
            cn_since = 0;
        end

        // /CON falling INSIDE a word of the marker's: the case that matters
        if (conn_d && !con_n) begin
            t_con = $realtime;
            if (S.u_mk.ser_busy || S.u_mk.ser_req) begin
                n_mid = n_mid + 1;
                if (S.u_mk.ser_strobe) n_mid_wr = n_mid_wr + 1;
            end
        end
        if (!conn_d && con_n && !key_hold) begin
            if ($realtime - t_con > ten_max) ten_max = $realtime - t_con;
            if ($realtime - t_con < ten_min) ten_min = $realtime - t_con;
        end
    end

    // ---- the scan, timed ---------------------------------------------------
    reg [5:0] scan_d = 0;
    real      t_wrap = 0, sp;
    real      sp_max [0:2], sp_sum [0:2];
    integer   sp_n [0:2], meas = 0;
    always @(posedge clk) if (rst_n) begin
        scan_d <= S.u_mk.scan;
        if (S.u_mk.scan == 6'd0 && scan_d == 6'd63) begin
            sp = $realtime - t_wrap; t_wrap = $realtime;
            if (sp > sp_max[meas]) sp_max[meas] = sp;
            sp_sum[meas] = sp_sum[meas] + sp; sp_n[meas] = sp_n[meas] + 1;
        end
    end

    // ---- random streams: the tb's own, so both simulators agree ----------
    reg [31:0] lcg = SEED, lcg2 = 32'h0BAD_5EED;
    function integer urnd(input integer n);
        begin lcg = lcg * 32'd1664525 + 32'd1013904223; urnd = (lcg >> 16) % n; end
    endfunction
    function integer urnd2(input integer n);
        begin lcg2 = lcg2 * 32'd1664525 + 32'd1013904223; urnd2 = (lcg2 >> 16) % n; end
    endfunction

    // ---- sixteen callers ---------------------------------------------------
    localparam integer S_IDLE=0, S_LIFT=1, S_BRK=2, S_MK=3, S_PAUSE=4,
                       S_WAIT=5, S_TALK=6, S_HANG=7, S_RUNG=8;
    integer st [0:63], tmr [0:63], np [0:63], dig [0:63], dq [0:63], ehi [0:63];
    integer n_try = 0, n_dt = 0, n_conn = 0, n_nodt = 0, n_gave = 0;
    integer n_sym = 0, n_glare = 0;
    integer dt_sum = 0, dt_max = 0;          // ms from the lift to dial tone
    reg     running = 1'b0;
    integer i, j, d, tgt;

    task hang_up(input integer n);
        begin st[n] = S_HANG; hook[n] = 1'b0; tmr[n] = 120 + urnd(200); end
    endtask

    always @(posedge clk) if (rst_n && ms_stb && running) begin
        for (i = 16; i < 32; i = i + 1) begin
            if (tmr[i] > 0) tmr[i] = tmr[i] - 1;
            if (hook[i] && e[i]) ehi[i] = ehi[i] + 1;
            else if (hook[i])    ehi[i] = 0;

            case (st[i])
            S_IDLE:
                if (e[i]) begin st[i] = S_RUNG; tmr[i] = 5 + urnd(60); end
                else if (tmr[i] == 0) begin
                    n_try = n_try + 1;
                    tgt = 16 + urnd(16);
                    dq[i] = ((tgt & 7) << 4) | ((tgt >> 3) & 7); dig[i] = 2;
                    hook[i] = 1'b1; st[i] = S_LIFT; tmr[i] = DT_WAIT; ehi[i] = 0;
                end
            S_LIFT:
                if (pbusy[i]) begin
                    n_dt = n_dt + 1; st[i] = S_PAUSE;
                    dt_sum = dt_sum + (DT_WAIT - tmr[i]);
                    if (DT_WAIT - tmr[i] > dt_max) dt_max = DT_WAIT - tmr[i];
                    tmr[i] = 10 + urnd(30);
                end
                else if (tmr[i] == 0) begin n_nodt = n_nodt + 1; hang_up(i); end
            S_PAUSE: if (tmr[i] == 0) begin
                if (dig[i] == 0) begin st[i] = S_WAIT; tmr[i] = 300 + urnd(400); end
                else begin
                    d = dq[i] & 15; dq[i] = dq[i] >> 4; dig[i] = dig[i] - 1;
                    np[i] = (d == 0) ? 10 : d;
                    st[i] = S_BRK; tmr[i] = BRK; hook[i] = 1'b0;
                end
            end
            S_BRK: if (tmr[i] == 0) begin hook[i] = 1'b1; st[i] = S_MK; tmr[i] = MK; end
            S_MK:  if (tmr[i] == 0) begin
                np[i] = np[i] - 1;
                if (np[i] > 0) begin hook[i] = 1'b0; st[i] = S_BRK; tmr[i] = BRK; end
                else begin st[i] = S_PAUSE; tmr[i] = PAUSE + urnd(40); end
            end
            S_WAIT:
                if (ehi[i] > 20) begin n_conn = n_conn + 1; st[i] = S_TALK; tmr[i] = 150 + urnd(400); end
                else if (tmr[i] == 0) begin n_gave = n_gave + 1; hang_up(i); end
            S_RUNG: if (tmr[i] == 0) begin
                if (e[i] || ehi[i] > 0) begin
                    hook[i] = 1'b1; st[i] = S_TALK; tmr[i] = 150 + urnd(400); ehi[i] = 0;
                end else st[i] = S_IDLE;
            end
            S_TALK: if (tmr[i] == 0 || (ehi[i] == 0 && tmr[i] < 300)) hang_up(i);
            S_HANG: if (tmr[i] == 0) begin st[i] = S_IDLE; tmr[i] = 1000 + urnd(2000); end
            default: st[i] = S_IDLE;
            endcase
        end
    end

    // the partner invariant, a line at a time: i hears j  =>  j hears i, and
    // nobody else hears j.  The sinks hear lines on purpose and are not lines.
    integer a, b2, persist [0:63];
    always @(posedge clk) if (rst_n && ms_stb && running) begin
        for (a = 16; a < 32; a = a + 1) begin
            if (heard[a] == NONE) persist[a] = 0; else persist[a] = persist[a] + 1;
            if (heard[a] != NONE && persist[a] > 40) begin
                b2 = heard[a][5:0];
                if (is_line(b2) && heard[b2] != nm(a) && heard[b2] != NONE) begin
                    n_sym = n_sym + 1;
                    if (n_sym < 4) $display("     GLITCH: %0o hears %0o, which hears %0o", a, b2, heard[b2][5:0]);
                end
                for (j = a + 1; j < 32; j = j + 1)
                    if (heard[j] == heard[a] && persist[j] > 40) begin
                        n_glare = n_glare + 1;
                        if (n_glare < 4) $display("     GLITCH: %0o AND %0o both hear %0o", a, j, b2);
                    end
            end
        end
    end

    // ---- the operator -----------------------------------------------------
    task con_word(input rel, input [5:0] dst, input [5:0] src, input bsy);
        begin
            @(negedge clk);
            sw_dst = dst; sw_src = src; sw_bsy = bsy; sw_clm = 1'b0;
            cn_expect = {1'b1, 1'b0, dst, rel ? 8'h00 : {src, bsy, 1'b0}};
            if (rel) key_release = 1'b1; else key_write = 1'b1;
            @(negedge clk);
            key_release = 1'b0; key_write = 1'b0;
            @(posedge con_done);
            @(negedge clk);
        end
    endtask

    // Hundreds of times an operator's rate, and two in three of them timed to
    // land inside a word the marker has already begun.
    reg hammer = 1'b0;
    integer n_aimed = 0;
    initial begin : hammer_proc
        integer g, k;
        forever begin
            wait (hammer);
            g = 2 + urnd2(28);
            repeat (g) #(NS);               // a constant delay: Verilator schedules a variable one as a possible #0
            k = urnd2(3);
            if (k != 0) begin
                // 1: any word of the marker's, which is mostly the probe being
                // steered.  2: a latch WRITE, which is the one that can be lost.
                @(posedge S.u_mk.ser_busy);
                if (k == 2) while (!S.u_mk.ser_strobe) @(posedge S.u_mk.ser_busy);
                k = urnd2(140);
                repeat (k) @(posedge clk);
                n_aimed = n_aimed + 1;
            end
            if (hammer) begin
                if (urnd2(3) == 0) con_word(1'b1, urnd2(2) ? SK0 : SK1, 6'd0, 1'b0);
                else               con_word(1'b0, urnd2(2) ? SK0 : SK1, 6'd16 + urnd2(16), 1'b1);
            end
        end
    end

    // ---- scripted callers -------------------------------------------------
    integer errs = 0, chk = 0;
    task want(input v, input string what);
        begin
            chk = chk + 1;
            if (!v) begin errs = errs + 1; $display("     %-62s FAIL", what); end
            else $display("     %-62s ok", what);
        end
    endtask

    task dial(input [5:0] p, input integer dg);
        integer n, k;
        begin
            n = (dg == 0) ? 10 : dg;
            for (k = 0; k < n; k = k + 1) begin
                hook[p] = 1'b0; #(BRK * NS); hook[p] = 1'b1; #(MK * NS);
            end
            #(PAUSE * NS);
        end
    endtask

    task lift(input [5:0] p);                 // and wait for dial tone
        integer t;
        begin
            hook[p] = 1'b1;
            for (t = 0; t < 400 && !pbusy[p]; t = t + 1) #(NS);
        end
    endtask

    task call(input [5:0] from, input [5:0] to);      // dialled, rung and answered
        integer t;
        begin
            lift(from);
            #(20 * NS);
            dial(from, to[5:3]); dial(from, to[2:0]);
            for (t = 0; t < 200 && !e[to]; t = t + 1) #(NS);
            hook[to] = 1'b1;
            #(40 * NS);
        end
    endtask

    task all_down(input integer ms);
        begin hook = 64'd0; repeat (ms) #(NS); end
    endtask

    reg pe = 1'b0;
    bitpath p_ab (.src_clk(clk), .src_fs(fs), .src_bit(tx[6'o20]),
                  .dst_clk(clk), .dst_fs(fs), .dst_bit(rx[6'o21]), .enable(pe));
    bitpath p_ba (.src_clk(clk), .src_fs(fs), .src_bit(tx[6'o21]),
                  .dst_clk(clk), .dst_fs(fs), .dst_bit(rx[6'o20]), .enable(pe));
    reg pse = 1'b0;
    bitpath p_s0 (.src_clk(clk), .src_fs(fs), .src_bit(tx[6'o20]),
                  .dst_clk(clk), .dst_fs(fs), .dst_bit(sink_rx[0]), .enable(pse));
    bitpath p_s1 (.src_clk(clk), .src_fs(fs), .src_bit(tx[6'o21]),
                  .dst_clk(clk), .dst_fs(fs), .dst_bit(sink_rx[1]), .enable(pse));

    task paths_ok(input integer hold);
        begin
            if (hold) begin p_ab.report("through the hold, 20 -> 21"); p_ba.report("through the hold, 21 -> 20"); end
            else      begin p_ab.report("across the writes, 20 -> 21"); p_ba.report("across the writes, 21 -> 20"); end
            chk = chk + 2;
            if (p_ab.best_err != 0) errs = errs + 1;
            if (p_ba.best_err != 0) errs = errs + 1;
            p_ab.clear; p_ba.clear;
        end
    endtask

    task traffic(input integer which, input string what);
        integer t0_try, t0_dt, t0_conn, t0_nodt, t0_gave;
        begin
            t0_try = n_try; t0_dt = n_dt; t0_conn = n_conn; t0_nodt = n_nodt; t0_gave = n_gave;
            for (i = 16; i < 32; i = i + 1) begin st[i] = S_IDLE; tmr[i] = (i * 53) % 400; ehi[i] = 0; end
            lcg = SEED; dt_sum = 0; dt_max = 0;
            meas = which; running = 1'b1;
            #(TRAFFIC_MS * NS);
            running = 1'b0; meas = 0;
            $display("     %-17s %3d lifted  %3d answered  %3d not (busy, or themselves)  %3d no dial tone in %0d ms",
                     what, n_try - t0_try, n_conn - t0_conn,
                     n_gave - t0_gave, n_nodt - t0_nodt, DT_WAIT);
            $display("     %-17s dial tone %0d ms after the lift, mean; %0d worst", "",
                     (n_dt - t0_dt) ? dt_sum / (n_dt - t0_dt) : 0, dt_max);
            all_down(150);
        end
    endtask

    real t0, t1;
    integer k;

    initial begin
        for (i = 0; i < 64; i = i + 1) begin
            st[i] = S_IDLE; tmr[i] = 0; np[i] = 0; dig[i] = 0; dq[i] = 0; ehi[i] = 0;
            heard[i] = NONE; cand[i] = NONE; hage[i] = 0; shift[i] = 0; txbit[i] = i[3:0];
            persist[i] = 0; lw_src[i] = 0; lw_bsy[i] = 0; lw_t[i] = 0.0;
        end
        for (i = 0; i < 3; i = i + 1) begin sp_max[i] = 0; sp_sum[i] = 0; sp_n[i] = 0; end

        if (NAIVE) $display("CONSOLE (RTL) -- THE CONTROL: /CON as one '244 enable, no yield, no silence.\n");
        else       $display("CONSOLE (RTL) -- two masters on cable B: /CON, forced release, service observing.\n");
        #4000 rst_n = 1;
        #(30 * NS);

        // ---- 1. arbitration under traffic ------------------------------
        $display("  1. Sixteen lines calling at random; then the same with the console writing every");
        $display("     2-30 ms, two in three of its words aimed inside a word the marker has begun.");
        traffic(1, "console quiet:");
        hammer = 1'b1;
        traffic(2, "console writing:");
        hammer = 1'b0;
        #(5 * NS);
        // The hammer leaves each sink pointed wherever its last word put it, and
        // a sink pointed at an idle line waits for ever (part 5).  Let them go.
        con_word(1'b1, SK0, 6'd0, 1'b0);
        con_word(1'b1, SK1, 6'd0, 1'b0);
        $display("     the console sent %0d words, %0d of them aimed; /CON fell inside a marker word %0d times,",
                 n_cn_said, n_aimed, n_mid);
        $display("     %0d of those a latch WRITE.  The marker sent %0d writes.", n_mid_wr, n_mk_said);
        $display("     marker writes the blocks never saw: %0d   saw mangled: %0d   runt WR pulses: %0d",
                 n_mk_lost, n_mk_mangled, n_runt);
        $display("     console words the blocks saw wrong: %0d   clocks with both '244s on: %0d",
                 n_cn_bad, n_contend);
        $display("     one-way patches: %0d   two callers on one line: %0d", n_sym, n_glare);
        if (NAIVE) begin
            $display("\n  The control: nothing above is asserted.  Compare `make console`.");
            $finish;
            #(NS);                          // under Verilator, $finish ends the time step and not the process
        end
        want(n_mid_wr > 0,                     "the case was exercised: /CON fell inside a marker WRITE");
        want(n_mk_lost == 0 && n_mk_mangled == 0, "every write the marker sent reached the blocks intact");
        want(n_cn_bad == 0,                    "every word the console sent reached the blocks intact");
        want(n_contend == 0 && n_runt == 0,    "never two drivers on the bus, never a runt WR");
        want(n_sym == 0 && n_glare == 0,       "no one-way patch, no two callers on one line");
        want(pbusy == 64'd0 && regs == {NREG{1'b0}} && !wq_ovf, "and afterwards nothing is held");

        // ---- 2. what a console word costs -------------------------------
        $display("\n  2. What a console word costs the marker.");
        $display("     tenure, /CON low: %0.0f - %0.0f us   (32 silent + 16 bits + WR, at 64 kHz)",
                 ten_min / 1000.0, ten_max / 1000.0);
        $display("     a scan of 64 ports: quiet %0.2f ms mean, %0.2f worst;  console writing %0.2f mean, %0.2f worst",
                 sp_sum[1] / sp_n[1] / NS, sp_max[1] / NS, sp_sum[2] / sp_n[2] / NS, sp_max[2] / NS);
        want(ten_max < 1.0 * NS, "a tenure is under a millisecond: less than the scanner gives one block");

        // ---- 3. forced release -------------------------------------------
        $display("\n  3. Forced release.  The watch is armed on 20, then 20 calls 21.");
        @(negedge clk); sw_dst = 6'o20; key_arm = 1; @(negedge clk); key_arm = 0;
        call(6'o20, 6'o21);
        want(heard[6'o20] == nm(6'o21) && heard[6'o21] == nm(6'o20), "20 and 21 are talking");
        want(w_seen && w_src == 6'o21 && w_bsy, "the watch shows who 20 listens to: 21");
        $display("     RELEASE 20 -- one end only.");
        t0 = $realtime;
        con_word(1'b1, 6'o20, 6'd0, 1'b0);
        #(10 * NS);
        want(heard[6'o20] != nm(6'o21), "20 no longer hears 21");
        for (k = 0; k < 200 && !(lw_src[6'o20] == PDT && lw_t[6'o20] > t0); k = k + 1) #(NS);
        $display("     20 has dial tone again %0.0f ms after the key  (the release time is %0d ms here)",
                 (lw_t[6'o20] - t0) / NS, T_FALL / 64);
        want(lw_src[6'o20] == PDT && pbusy[6'o20], "20 is an idle off-hook port, which is a call request");
        #(60 * NS);
        want(heard[6'o21] == nm(6'o20) && pbusy[6'o21],
             "BUT 21 still listens to 20: no write at 20 can drop 21's E");
        $display("     RELEASE 21 -- the other end, read off the watch.");
        t0 = $realtime;
        con_word(1'b1, 6'o21, 6'd0, 1'b0);
        for (k = 0; k < 200 && !(lw_src[6'o21] == PDT && lw_t[6'o21] > t0); k = k + 1) #(NS);
        want(heard[6'o21] != nm(6'o20) && lw_src[6'o21] == PDT, "21 hears 20 no more, and has dial tone");
        all_down(150);
        want(pbusy == 64'd0 && regs == {NREG{1'b0}}, "both hang up: nothing is held");

        $display("     A port held by nothing: 22 written BUSY by hand, both phones on hook.");
        con_word(1'b0, 6'o22, 6'o23, 1'b1);
        #(150 * NS);
        want(pbusy[6'o22], "150 ms later it is still held: nothing will ever fall to clear it");
        con_word(1'b1, 6'o22, 6'd0, 1'b0);
        #(5 * NS);
        want(!pbusy[6'o22], "RELEASE 22: one word, and it is free");
        lift(6'o22);
        want(pbusy[6'o22] && lw_src[6'o22] == PDT, "and 22 lifting gets dial tone");
        all_down(150);

        // ---- 4. make-busy by a latch write ---------------------------------
        $display("\n  4. Make-busy by a latch write: 22 <- 00 with BUSY set.");
        con_word(1'b0, 6'o22, 6'o00, 1'b1);
        #(5 * NS);
        lift(6'o20); #(20 * NS); dial(6'o20, 2); dial(6'o20, 2);
        #(30 * NS);
        want(lw_src[6'o20] == PNG, "while it lasts, a caller to 22 gets cannot-complete");
        all_down(150);
        want(pbusy[6'o22], "and it outlasts that call");
        hook[6'o22] = 1'b1; #(50 * NS); hook[6'o22] = 1'b0;
        #(100 * NS);
        want(!pbusy[6'o22], "but 22 lifting and replacing CLEARS it: the port releases itself");

        // ---- 5. service observing ------------------------------------------
        $display("\n  5. Service observing.  20 calls 21; a sink is pointed at each.");
        call(6'o20, 6'o21);
        p_ab.clear; p_ba.clear; pe = 1'b1;
        #(5 * NS);
        con_word(1'b0, SK0, 6'o20, 1'b1);
        con_word(1'b0, SK1, 6'o21, 1'b1);
        #(2 * NS);                          // a sink hears from the frame after its write
        pse = 1'b1;
        #(30 * NS);
        pe = 1'b0; pse = 1'b0;
        paths_ok(0);
        p_s0.report("sink 76 <- 20");  p_s1.report("sink 77 <- 21");
        chk = chk + 2;
        if (p_s0.best_err != 0) errs = errs + 1;
        if (p_s1.best_err != 0) errs = errs + 1;
        want(heard[SK0] == nm(6'o20) && heard[SK1] == nm(6'o21), "one party in each ear");
        want(pbusy[6'o20] && pbusy[6'o21] && heard[6'o20] == nm(6'o21) && heard[6'o21] == nm(6'o20),
             "and the call has not noticed");
        hook[6'o20] = 1'b0;
        #(100 * NS);
        want(!pbusy[SK0] && heard[SK0] == NONE, "20 hangs up: its sink clears ITSELF, on E falling");
        want(pbusy[SK1] && heard[SK1] == nm(6'o21), "21 is still off hook, and its sink still hears it");
        hook[6'o21] = 1'b0;
        #(100 * NS);
        want(!pbusy[SK1], "21 hangs up: so does that one");

        $display("     A sink armed on an idle line, and a sink dialled.");
        con_word(1'b0, SK0, 6'o22, 1'b1);
        #(150 * NS);
        want(pbusy[SK0], "pointed at 22 on hook, it waits: E never rose, so nothing falls");
        lift(6'o22); #(60 * NS);
        want(heard[SK0] == nm(6'o22), "22 lifts, and is heard");
        hook[6'o22] = 1'b0; #(100 * NS);
        want(!pbusy[SK0], "22 hangs up, and the observation ends with the call");
        lift(6'o20); #(20 * NS); dial(6'o20, 7); dial(6'o20, 6);
        #(30 * NS);
        want(lw_src[6'o20] == PNG && !pbusy[SK0], "dialling 76 gets cannot-complete: a sink has no word");
        all_down(150);

        // ---- 6. HOLD -------------------------------------------------------
        $display("\n  6. HOLD: the console keeps the bus, and the marker is stopped.");
        call(6'o20, 6'o21);
        key_hold = 1'b1;
        #(5 * NS);
        p_ab.clear; p_ba.clear; pe = 1'b1;
        hook[6'o24] = 1'b1;
        #(150 * NS);
        want(!pbusy[6'o24], "24 lifts and gets nothing: no scan, no register, no dial tone");
        con_word(1'b0, SK0, 6'o20, 1'b1);
        #(10 * NS);
        want(heard[SK0] == nm(6'o20), "the console still writes, with no silence: the bus is already its own");
        pe = 1'b0;
        paths_ok(1);
        t0 = $realtime;
        key_hold = 1'b0;
        for (k = 0; k < 200 && !pbusy[6'o24]; k = k + 1) #(NS);
        $display("     HOLD dropped: 24 has dial tone %0.0f ms later", ($realtime - t0) / NS);
        want(pbusy[6'o24] && lw_src[6'o24] == PDT, "the marker picks up where it was");
        all_down(200);
        want(pbusy == 64'd0 && regs == {NREG{1'b0}} && !wq_ovf, "everything released, nothing held");
        want(n_mk_lost == 0 && n_mk_mangled == 0 && n_cn_bad == 0 && n_contend == 0 && n_runt == 0,
             "and over the whole run the bus never carried a wrong word");

        $display("\n  %0d checks, %0d errors.  %s", chk, errs, (errs == 0) ? "PASS" : "FAIL");
        $finish;
    end

    initial begin #40_000_000_000; $display("  TIMEOUT"); $finish; end
endmodule
