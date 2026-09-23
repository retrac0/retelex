// tb_mini_rate -- mini-marker call-rate sweep: solo and 5-node star.
//
// SHAPE 0  solo, no unit, 8 lines on block 2
// SHAPE 1  star: hub 21 + leaves 22..25 (NDIR=4 hub, one register a site)
//
// IDLE_MEAN sets the mean idle between lift attempts a line (ms).  Shorter
// idle = higher offered rate.  One register a site: dial-tone wait and
// no-dt fraction are the capacity signal.
`timescale 1ns/1ps

module tb_mini_rate #(
    parameter integer SHAPE     = 0,
    parameter integer IDLE_MEAN = 500,
    parameter integer SECS      = 3,
    parameter integer HOLD_MS   = 150,
    parameter integer DT_WAIT   = 800,
    parameter integer LEAVE_PC  = 40,
    parameter integer SEED      = 32'hA11C_E001
);
    // Plusarg overrides so one binary covers every idle point.
    integer idle_mean, secs, leave_pc;
    initial begin
        idle_mean = IDLE_MEAN; secs = SECS; leave_pc = LEAVE_PC;
        if ($value$plusargs("idle=%d", idle_mean)) ;
        if ($value$plusargs("secs=%d", secs)) ;
        if ($value$plusargs("leave=%d", leave_pc)) ;
    end
    localparam integer HIT = 1, ID = 16, CLR = 32;
    localparam integer T_RISE = 64, T_FALL = 2048;
    localparam integer RING_ON = 200, RING_OFF = 400;
    localparam integer NS = 1_000_000;
    localparam integer BRK = 12, MK = 8, PAUSE = 35;
    localparam integer STAR = (SHAPE == 1);
    localparam integer NSITE = STAR ? 5 : 1;
    localparam [1:0] Ndir = 2'd0, Sdir = 2'd1, Edir = 2'd2, Wdir = 2'd3;

    localparam [63:0] LP8 = 64'h0000_0000_00FF_0000;
    localparam [63:0] LP4 = 64'h0000_0000_000F_0000;

    // codes: H=21, A=22, B=23, C=24, D=25
    localparam [2:0] CODE_H = 3'd1, CODE_A = 3'd2, CODE_B = 3'd3,
                     CODE_C = 3'd4, CODE_D = 3'd5;

    reg clk_h = 0, clk_a = 0, clk_b = 0, clk_c = 0, clk_d = 0, rst_n = 0;
    always #122.0703 clk_h = ~clk_h;
    initial begin #40;  forever #122.0703 clk_a = ~clk_a; end
    initial begin #80;  forever #122.0703 clk_b = ~clk_b; end
    initial begin #20;  forever #122.0703 clk_c = ~clk_c; end
    initial begin #60;  forever #122.0703 clk_d = ~clk_d; end

    reg  [63:0] hk [0:4];
    reg  [63:0] tx [0:4];
    wire [63:0] rx [0:4];
    wire [63:0] ln [0:4];
    wire [63:0] pb [0:4];
    wire        rg [0:4], ov [0:4];
    wire [3:0]  dh [0:4];
    wire [3:0]  lo [0:4], lk [0:4];
    wire        fs [0:4];

    integer si;
    initial for (si = 0; si < 5; si = si + 1) begin hk[si] = 0; tx[si] = 0; end

    // ---- sites ----------------------------------------------------------
    generate if (STAR) begin : star
        // Hub 21: W=A E=B N=C S=D
        mini_net_site #(.HAS_NET(1'b1), .NDIR(4), .NRES(2),
                        .OWN_E(3'd2), .OWN_B(CODE_H),
                        .DIR0(Wdir), .G0(1'b1), .DIR1(Edir), .G1(1'b1),
                        .DIR2(Ndir), .G2(1'b1), .DIR3(Sdir), .G3(1'b1),
                        .LINE_PORTS(LP4),
                        .T_RISE(T_RISE), .T_FALL(T_FALL),
                        .RING_ON(RING_ON), .RING_OFF(RING_OFF),
                        .HIT(HIT), .ID(ID), .CLR(CLR), .NODIG(1500),
                        .T_GUARD(16), .T_CLAIM(250))
        H (.clk(clk_h), .rst_n(rst_n),
           .hook(hk[0]), .tx(tx[0]), .rx(rx[0]), .e(ln[0]),
           .line_in({lo[4][0], lo[3][0], lo[2][0], lo[1][0]}),
           .line_out(lo[0]), .locked(lk[0]),
           .frame_stb(fs[0]), .tick_1k(), .ring_cad_n(), .dt_bit(), .ng_bit(),
           .mon_held(), .got_claim(), .dirs_held(dh[0]),
           .port_busy(pb[0]), .reg_busy(rg[0]), .wq_ovf(ov[0]),
           .wr_stb(), .wr_dst(), .wr_src(), .wr_bsy(), .wr_clm());

        mini_net_site #(.HAS_NET(1'b1), .NDIR(1),
                        .OWN_E(3'd2), .OWN_B(CODE_A), .DIR0(Edir), .G0(1'b1),
                        .LINE_PORTS(LP8),
                        .T_RISE(T_RISE), .T_FALL(T_FALL),
                        .RING_ON(RING_ON), .RING_OFF(RING_OFF),
                        .HIT(HIT), .ID(ID), .CLR(CLR), .NODIG(1500),
                        .T_GUARD(16), .T_CLAIM(250))
        A (.clk(clk_a), .rst_n(rst_n),
           .hook(hk[1]), .tx(tx[1]), .rx(rx[1]), .e(ln[1]),
           .line_in({3'b0, lo[0][0]}), .line_out(lo[1]), .locked(lk[1]),
           .frame_stb(fs[1]), .tick_1k(), .ring_cad_n(), .dt_bit(), .ng_bit(),
           .mon_held(), .got_claim(), .dirs_held(dh[1]),
           .port_busy(pb[1]), .reg_busy(rg[1]), .wq_ovf(ov[1]),
           .wr_stb(), .wr_dst(), .wr_src(), .wr_bsy(), .wr_clm());

        mini_net_site #(.HAS_NET(1'b1), .NDIR(1),
                        .OWN_E(3'd2), .OWN_B(CODE_B), .DIR0(Wdir), .G0(1'b1),
                        .LINE_PORTS(LP8),
                        .T_RISE(T_RISE), .T_FALL(T_FALL),
                        .RING_ON(RING_ON), .RING_OFF(RING_OFF),
                        .HIT(HIT), .ID(ID), .CLR(CLR), .NODIG(1500),
                        .T_GUARD(16), .T_CLAIM(250))
        B (.clk(clk_b), .rst_n(rst_n),
           .hook(hk[2]), .tx(tx[2]), .rx(rx[2]), .e(ln[2]),
           .line_in({3'b0, lo[0][1]}), .line_out(lo[2]), .locked(lk[2]),
           .frame_stb(fs[2]), .tick_1k(), .ring_cad_n(), .dt_bit(), .ng_bit(),
           .mon_held(), .got_claim(), .dirs_held(dh[2]),
           .port_busy(pb[2]), .reg_busy(rg[2]), .wq_ovf(ov[2]),
           .wr_stb(), .wr_dst(), .wr_src(), .wr_bsy(), .wr_clm());

        mini_net_site #(.HAS_NET(1'b1), .NDIR(1),
                        .OWN_E(3'd2), .OWN_B(CODE_C), .DIR0(Sdir), .G0(1'b1),
                        .LINE_PORTS(LP8),
                        .T_RISE(T_RISE), .T_FALL(T_FALL),
                        .RING_ON(RING_ON), .RING_OFF(RING_OFF),
                        .HIT(HIT), .ID(ID), .CLR(CLR), .NODIG(1500),
                        .T_GUARD(16), .T_CLAIM(250))
        C (.clk(clk_c), .rst_n(rst_n),
           .hook(hk[3]), .tx(tx[3]), .rx(rx[3]), .e(ln[3]),
           .line_in({3'b0, lo[0][2]}), .line_out(lo[3]), .locked(lk[3]),
           .frame_stb(fs[3]), .tick_1k(), .ring_cad_n(), .dt_bit(), .ng_bit(),
           .mon_held(), .got_claim(), .dirs_held(dh[3]),
           .port_busy(pb[3]), .reg_busy(rg[3]), .wq_ovf(ov[3]),
           .wr_stb(), .wr_dst(), .wr_src(), .wr_bsy(), .wr_clm());

        mini_net_site #(.HAS_NET(1'b1), .NDIR(1),
                        .OWN_E(3'd2), .OWN_B(CODE_D), .DIR0(Ndir), .G0(1'b1),
                        .LINE_PORTS(LP8),
                        .T_RISE(T_RISE), .T_FALL(T_FALL),
                        .RING_ON(RING_ON), .RING_OFF(RING_OFF),
                        .HIT(HIT), .ID(ID), .CLR(CLR), .NODIG(1500),
                        .T_GUARD(16), .T_CLAIM(250))
        D (.clk(clk_d), .rst_n(rst_n),
           .hook(hk[4]), .tx(tx[4]), .rx(rx[4]), .e(ln[4]),
           .line_in({3'b0, lo[0][3]}), .line_out(lo[4]), .locked(lk[4]),
           .frame_stb(fs[4]), .tick_1k(), .ring_cad_n(), .dt_bit(), .ng_bit(),
           .mon_held(), .got_claim(), .dirs_held(dh[4]),
           .port_busy(pb[4]), .reg_busy(rg[4]), .wq_ovf(ov[4]),
           .wr_stb(), .wr_dst(), .wr_src(), .wr_bsy(), .wr_clm());
    end else begin : solo
        mini_net_site #(.HAS_NET(1'b0), .NDIR(1),
                        .OWN_E(3'd2), .OWN_B(3'd2),
                        .LINE_PORTS(LP8),
                        .T_RISE(T_RISE), .T_FALL(T_FALL),
                        .RING_ON(RING_ON), .RING_OFF(RING_OFF),
                        .HIT(HIT), .ID(ID), .CLR(CLR), .NODIG(1500))
        A (.clk(clk_h), .rst_n(rst_n),
           .hook(hk[0]), .tx(tx[0]), .rx(rx[0]), .e(ln[0]),
           .line_in(4'b0), .line_out(lo[0]), .locked(lk[0]),
           .frame_stb(fs[0]), .tick_1k(), .ring_cad_n(), .dt_bit(), .ng_bit(),
           .mon_held(), .got_claim(), .dirs_held(dh[0]),
           .port_busy(pb[0]), .reg_busy(rg[0]), .wq_ovf(ov[0]),
           .wr_stb(), .wr_dst(), .wr_src(), .wr_bsy(), .wr_clm());
        assign fs[1] = 0; assign fs[2] = 0; assign fs[3] = 0; assign fs[4] = 0;
        assign lo[1] = 0; assign lo[2] = 0; assign lo[3] = 0; assign lo[4] = 0;
        assign lk[1] = 4'hF; assign lk[2] = 4'hF;
        assign lk[3] = 4'hF; assign lk[4] = 4'hF;
        assign pb[1] = 0; assign pb[2] = 0; assign pb[3] = 0; assign pb[4] = 0;
        assign rg[1] = 0; assign rg[2] = 0; assign rg[3] = 0; assign rg[4] = 0;
        assign ov[1] = 0; assign ov[2] = 0; assign ov[3] = 0; assign ov[4] = 0;
        assign dh[1] = 0; assign dh[2] = 0; assign dh[3] = 0; assign dh[4] = 0;
        assign ln[1] = 0; assign ln[2] = 0; assign ln[3] = 0; assign ln[4] = 0;
        assign rx[1] = 0; assign rx[2] = 0; assign rx[3] = 0; assign rx[4] = 0;
    end endgenerate

    // ---- 1 ms tick from site 0 ------------------------------------------
    reg [6:0] frc = 0;
    reg       ms_stb = 0;
    always @(posedge clk_h) begin
        ms_stb <= 0;
        if (fs[0]) begin
            if (frc == 7'd63) begin frc <= 0; ms_stb <= 1; end
            else frc <= frc + 1;
        end
    end

    reg [31:0] lcg = SEED;
    function integer urnd(input integer n);
        begin
            lcg = lcg * 32'd1664525 + 32'd1013904223;
            if (n <= 0) urnd = 0;
            else urnd = (lcg >> 16) % n;
        end
    endfunction

    // Agent table: up to 5 sites × 8 lines.
    integer port_of [0:39];
    integer site_of [0:39];
    integer nagt;
    integer ai, pi;
    initial begin
        nagt = 0;
        for (si = 0; si < NSITE; si = si + 1) begin
            for (pi = 16; pi < (si == 0 && STAR ? 20 : 24); pi = pi + 1) begin
                if (nagt < 40) begin
                    site_of[nagt] = si;
                    port_of[nagt] = pi;
                    nagt = nagt + 1;
                end
            end
        end
    end

    localparam S_IDLE=0, S_LIFT=1, S_PULSE=2, S_MAKE=3, S_GAP=4,
               S_WAIT=5, S_TALK=6, S_HANG=7, S_RUNG=8;
    integer st[0:39], tmr[0:39], digs_left[0:39], pulses_left[0:39], dt_waited[0:39];
    integer digit_q[0:39][0:4];
    integer n_try, n_dt, n_nodt, n_conn, n_rung, dt_sum, dt_max, errs;
    integer running, now_ms, i, j, dest_site, dest_port, leave;
    integer codes [0:4];
    initial begin
        codes[0] = CODE_H; codes[1] = CODE_A; codes[2] = CODE_B;
        codes[3] = CODE_C; codes[4] = CODE_D;
    end

    task automatic plan(input integer a);
        integer k, ds, dp;
        begin
            leave = STAR && (urnd(100) < leave_pc);
            if (leave) begin
                do ds = 1 + urnd(4); while (ds == site_of[a] && NSITE > 2);
                dp = 16 + urnd(8);
                digs_left[a] = 5;
                digit_q[a][0] = 1;
                digit_q[a][1] = 2;
                digit_q[a][2] = codes[ds];
                digit_q[a][3] = dp[5:3] ? dp[5:3] : 10;
                digit_q[a][4] = dp[2:0] ? dp[2:0] : 10;
            end else begin
                k = 0;
                do begin
                    dp = port_of[urnd(nagt)];
                    // prefer same-site local when possible
                    for (j = 0; j < nagt; j = j + 1)
                        if (site_of[j] == site_of[a] && port_of[j] != port_of[a])
                            dp = port_of[j];
                    k = k + 1;
                end while (dp == port_of[a] && k < 8);
                digs_left[a] = 2;
                digit_q[a][0] = dp[5:3] ? dp[5:3] : 10;
                digit_q[a][1] = dp[2:0] ? dp[2:0] : 10;
            end
        end
    endtask

    always @(posedge clk_h) if (ms_stb && rst_n) begin
        if (running) now_ms <= now_ms + 1;
        for (i = 0; i < nagt; i = i + 1) begin
            if (tmr[i] > 0) tmr[i] <= tmr[i] - 1;

            case (st[i])
            S_IDLE: begin
                if (!hk[site_of[i]][port_of[i]] && ln[site_of[i]][port_of[i]]) begin
                    st[i] <= S_RUNG; tmr[i] <= urnd(80); n_rung <= n_rung + 1;
                end else if (running && tmr[i] == 0) begin
                    hk[site_of[i]][port_of[i]] <= 1'b1;
                    st[i] <= S_LIFT; tmr[i] <= DT_WAIT;
                    dt_waited[i] <= 0;
                    n_try <= n_try + 1;
                    plan(i);
                end
            end
            S_LIFT: begin
                dt_waited[i] <= dt_waited[i] + 1;
                if (pb[site_of[i]][port_of[i]]) begin
                    n_dt <= n_dt + 1;
                    dt_sum <= dt_sum + dt_waited[i];
                    if (dt_waited[i] > dt_max) dt_max <= dt_waited[i];
                    pulses_left[i] <= digit_q[i][0];
                    hk[site_of[i]][port_of[i]] <= 1'b0;
                    st[i] <= S_PULSE; tmr[i] <= BRK;
                end else if (tmr[i] == 0) begin
                    n_nodt <= n_nodt + 1;
                    hk[site_of[i]][port_of[i]] <= 1'b0;
                    st[i] <= S_HANG; tmr[i] <= CLR + 40;
                end
            end
            S_PULSE: if (tmr[i] == 0) begin
                hk[site_of[i]][port_of[i]] <= 1'b1;
                st[i] <= S_MAKE; tmr[i] <= MK;
            end
            S_MAKE: if (tmr[i] == 0) begin
                if (pulses_left[i] > 1) begin
                    pulses_left[i] <= pulses_left[i] - 1;
                    hk[site_of[i]][port_of[i]] <= 1'b0;
                    st[i] <= S_PULSE; tmr[i] <= BRK;
                end else if (digs_left[i] > 1) begin
                    digs_left[i] <= digs_left[i] - 1;
                    for (j = 0; j < 4; j = j + 1)
                        digit_q[i][j] <= digit_q[i][j+1];
                    st[i] <= S_GAP; tmr[i] <= PAUSE;
                end else begin
                    st[i] <= S_WAIT; tmr[i] <= 400 + urnd(400);
                end
            end
            S_GAP: if (tmr[i] == 0) begin
                pulses_left[i] <= digit_q[i][0];
                hk[site_of[i]][port_of[i]] <= 1'b0;
                st[i] <= S_PULSE; tmr[i] <= BRK;
            end
            S_WAIT: begin
                if (hk[site_of[i]][port_of[i]] && ln[site_of[i]][port_of[i]]) begin
                    n_conn <= n_conn + 1;
                    st[i] <= S_TALK; tmr[i] <= HOLD_MS + urnd(HOLD_MS);
                end else if (tmr[i] == 0) begin
                    hk[site_of[i]][port_of[i]] <= 1'b0;
                    st[i] <= S_HANG; tmr[i] <= CLR + 40;
                end
            end
            S_RUNG: if (tmr[i] == 0) begin
                if (ln[site_of[i]][port_of[i]]) begin
                    hk[site_of[i]][port_of[i]] <= 1'b1;
                    st[i] <= S_TALK; tmr[i] <= HOLD_MS + urnd(HOLD_MS);
                end else st[i] <= S_IDLE;
            end
            S_TALK: if (tmr[i] == 0) begin
                hk[site_of[i]][port_of[i]] <= 1'b0;
                st[i] <= S_HANG; tmr[i] <= CLR + 40;
            end
            S_HANG: if (tmr[i] == 0) begin
                st[i] <= S_IDLE;
                tmr[i] <= (idle_mean / 2) + urnd(idle_mean > 0 ? idle_mean : 1);
            end
            default: st[i] <= S_IDLE;
            endcase
        end
    end

    // Speech noise while off-hook.
    always @(posedge clk_h) if (fs[0])
        for (pi = 0; pi < 64; pi = pi + 1) if (hk[0][pi]) tx[0][pi] <= $random;
    always @(posedge clk_a) if (fs[1])
        for (pi = 0; pi < 64; pi = pi + 1) if (hk[1][pi]) tx[1][pi] <= $random;
    always @(posedge clk_b) if (fs[2])
        for (pi = 0; pi < 64; pi = pi + 1) if (hk[2][pi]) tx[2][pi] <= $random;
    always @(posedge clk_c) if (fs[3])
        for (pi = 0; pi < 64; pi = pi + 1) if (hk[3][pi]) tx[3][pi] <= $random;
    always @(posedge clk_d) if (fs[4])
        for (pi = 0; pi < 64; pi = pi + 1) if (hk[4][pi]) tx[4][pi] <= $random;

    task automatic jam_check;
        integer s, waited;
        reg [63:0] mask;
        begin
            // Stop traffic first so agents do not re-seize during settle.
            for (s = 0; s < 40; s = s + 1) begin
                st[s] = S_IDLE; tmr[s] = 99999;
            end
            for (s = 0; s < NSITE; s = s + 1) hk[s] = 0;
            waited = 0;
            while (waited < 1200) begin
                if (!rg[0] && !rg[1] && !rg[2] && !rg[3] && !rg[4] &&
                    (pb[0] & (STAR ? LP4 : LP8)) == 0 &&
                    (pb[1] & LP8) == 0 && (pb[2] & LP8) == 0 &&
                    (pb[3] & LP8) == 0 && (pb[4] & LP8) == 0 &&
                    dh[0]==0 && dh[1]==0 && dh[2]==0 && dh[3]==0 && dh[4]==0)
                    waited = 1200;
                else begin
                    #(10 * NS);
                    waited = waited + 10;
                end
            end
            for (s = 0; s < NSITE; s = s + 1) begin
                mask = (s == 0 && STAR) ? LP4 : LP8;
                if (rg[s] || |(pb[s] & mask) || dh[s] != 0 || ov[s]) begin
                    $display("  JAM site %0d reg=%0d busy=%h dirs=%h ovf=%0d after %0d ms",
                             s, rg[s], pb[s] & mask, dh[s], ov[s], waited);
                    errs = errs + 1;
                end
            end
        end
    endtask

    real cps, dt_mean, nodt_pct, talk_pct;
    initial begin
        errs = 0; n_try = 0; n_dt = 0; n_nodt = 0; n_conn = 0; n_rung = 0;
        dt_sum = 0; dt_max = 0; running = 0; now_ms = 0;
        for (i = 0; i < 40; i = i + 1) begin
            st[i] = S_IDLE; tmr[i] = 20 + urnd(idle_mean > 0 ? idle_mean : 1); dt_waited[i] = 0;
        end

        $display("MINI-RATE shape=%0s idle_mean=%0d ms secs=%0d lines=%0d",
                 STAR ? "star" : "solo", idle_mean, secs, nagt);

        #4000 rst_n = 1;
        if (STAR) wait (lk[0][0] && lk[1][0] && lk[2][0] && lk[3][0] && lk[4][0]);
        #(50 * NS);

        running = 1;
        #(secs * 1000 * NS);
        running = 0;
        jam_check();

        cps = (secs > 0) ? (1.0 * n_try) / secs : 0.0;
        dt_mean = n_dt ? (1.0 * dt_sum) / n_dt : 0.0;
        nodt_pct = n_try ? (100.0 * n_nodt) / n_try : 0.0;
        talk_pct = n_try ? (100.0 * n_conn) / n_try : 0.0;

        $display("RESULT shape=%0s idle=%0d tries=%0d dt=%0d nodt=%0d talk=%0d rung=%0d",
                 STAR ? "star" : "solo", idle_mean, n_try, n_dt, n_nodt, n_conn, n_rung);
        $display("RESULT cps=%.2f dt_mean_ms=%.1f dt_max_ms=%0d nodt_pct=%.1f talk_pct=%.1f jam=%0s",
                 cps, dt_mean, dt_max, nodt_pct, talk_pct, errs ? "FAIL" : "ok");
        $display("  %0d jam flags. done\n", errs);
        $finish;
    end

    initial begin
        #((longint'(SECS) * 2000 + 15000) * longint'(NS));
        $display("TIMEOUT"); $finish;
    end
endmodule
