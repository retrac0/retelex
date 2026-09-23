// tb_mini_load -- mini-marker under load, several exchange shapes.
//
// MODE:
//   0  solo, no network unit; 8 lines on block 2
//   1  solo, no unit; 16 lines on blocks 2+3
//   2  two mini+unit exchanges on one link; 8 lines each; local+flood mix
//   3  chain 22=23=24; 8 lines on ends, 4 on the transit
//
// One register a site.  Burst rounds then a quiet gap (jam check).
// Dial-tone wait uses port_busy as the attach proxy (same as tb_stress).
`timescale 1ns/1ps

module tb_mini_load #(
    parameter integer MODE     = 0,
    parameter integer ROUNDS   = 2,
    parameter integer BURST    = 1000,
    parameter integer GAP      = 700,
    parameter integer IDLE_LO  = 150,
    parameter integer IDLE_HI  = 700,
    parameter integer DT_WAIT  = 800,
    parameter integer HOLD_MS  = 150,
    parameter integer SEED     = 32'hC0FF_EE01,
    parameter integer FLOOD_PC = 20
);
    localparam integer HIT = 1, ID = 16, CLR = 32;
    localparam integer T_RISE = 64, T_FALL = 2048;
    localparam integer RING_ON = 200, RING_OFF = 400;
    localparam integer NS = 1_000_000;
    localparam integer BRK = 12, MK = 8, PAUSE = 35;

    localparam [63:0] LP8  = 64'h0000_0000_00FF_0000;
    localparam [63:0] LP16 = 64'h0000_0000_FFFF_0000;
    localparam [63:0] LP4  = 64'h0000_0000_000F_0000;
    localparam [63:0] LP_A = (MODE == 1) ? LP16 : LP8;
    localparam integer PAIR  = (MODE >= 2);
    localparam integer CHAIN = (MODE == 3);

    // Watchdog: keep the multiply in 64-bit (ROUNDS*(BURST+GAP)*NS overflows 32).
    localparam longint unsigned WD_NS =
        (longint'(ROUNDS) * longint'(BURST + GAP) + 3000) * longint'(NS);

    reg clk_a = 0, clk_b = 0, clk_c = 0, rst_n = 0;
    always #122.0703 clk_a = ~clk_a;
    initial begin #40; forever #122.0703 clk_b = ~clk_b; end
    initial begin #80; forever #122.0703 clk_c = ~clk_c; end

    reg  [63:0] hk_a = 0, tx_a = 0, hk_b = 0, tx_b = 0, hk_c = 0, tx_c = 0;
    wire [63:0] rx_a, ln_a, pb_a, rx_b, ln_b, pb_b, rx_c, ln_c, pb_c;
    wire        rg_a, rg_b, rg_c, ov_a, ov_b, ov_c;
    wire [3:0]  dh_a, dh_b, dh_c;
    wire [3:0]  a_lo, a_lk, b_lo, b_lk, c_lo, c_lk;
    wire        fs_a, fs_b, fs_c;
    wire        ws_a, wb_a, wc_a, mh_a;
    wire [5:0]  wd_a, wr_a;

    mini_net_site #(.HAS_NET(MODE >= 2), .NDIR(1),
                    .OWN_E(3'd2), .OWN_B(3'd2), .DIR0(2'd2),
                    .LINE_PORTS(LP_A),
                    .T_RISE(T_RISE), .T_FALL(T_FALL),
                    .RING_ON(RING_ON), .RING_OFF(RING_OFF),
                    .HIT(HIT), .ID(ID), .CLR(CLR), .NODIG(1500),
                    .T_GUARD(16), .T_CLAIM(250))
    A (.clk(clk_a), .rst_n(rst_n),
       .hook(hk_a), .tx(tx_a), .rx(rx_a), .e(ln_a),
       .line_in({3'b0, b_lo[0]}),
       .line_out(a_lo), .locked(a_lk),
       .frame_stb(fs_a), .tick_1k(), .ring_cad_n(), .dt_bit(), .ng_bit(),
       .mon_held(mh_a), .got_claim(), .dirs_held(dh_a),
       .port_busy(pb_a), .reg_busy(rg_a), .wq_ovf(ov_a),
       .wr_stb(ws_a), .wr_dst(wd_a), .wr_src(wr_a), .wr_bsy(wb_a), .wr_clm(wc_a));

    generate if (MODE == 2) begin : pair2
        mini_net_site #(.HAS_NET(1'b1), .NDIR(1),
                        .OWN_E(3'd2), .OWN_B(3'd3), .DIR0(2'd3), .G0(1'b1),
                        .LINE_PORTS(LP8),
                        .T_RISE(T_RISE), .T_FALL(T_FALL),
                        .RING_ON(RING_ON), .RING_OFF(RING_OFF),
                        .HIT(HIT), .ID(ID), .CLR(CLR), .NODIG(1500),
                        .T_GUARD(16), .T_CLAIM(250))
        B (.clk(clk_b), .rst_n(rst_n),
           .hook(hk_b), .tx(tx_b), .rx(rx_b), .e(ln_b),
           .line_in({3'b0, a_lo[0]}), .line_out(b_lo), .locked(b_lk),
           .frame_stb(fs_b), .tick_1k(), .ring_cad_n(), .dt_bit(), .ng_bit(),
           .mon_held(), .got_claim(), .dirs_held(dh_b),
           .port_busy(pb_b), .reg_busy(rg_b), .wq_ovf(ov_b),
           .wr_stb(), .wr_dst(), .wr_src(), .wr_bsy(), .wr_clm());
        assign rx_c = 0; assign ln_c = 0; assign pb_c = 0;
        assign rg_c = 0; assign ov_c = 0; assign dh_c = 0;
        assign c_lo = 0; assign c_lk = 4'b1111; assign fs_c = 0;
    end else if (MODE == 3) begin : chain3
        // 23: DIR0=W toward 22, DIR1=E toward 24
        mini_net_site #(.HAS_NET(1'b1), .NDIR(2), .NRES(2),
                        .OWN_E(3'd2), .OWN_B(3'd3),
                        .DIR0(2'd3), .G0(1'b1), .DIR1(2'd2), .G1(1'b0),
                        .LINE_PORTS(LP4),
                        .T_RISE(T_RISE), .T_FALL(T_FALL),
                        .RING_ON(RING_ON), .RING_OFF(RING_OFF),
                        .HIT(HIT), .ID(ID), .CLR(CLR), .NODIG(1500),
                        .T_GUARD(16), .T_CLAIM(250))
        B (.clk(clk_b), .rst_n(rst_n),
           .hook(hk_b), .tx(tx_b), .rx(rx_b), .e(ln_b),
           .line_in({2'b0, c_lo[0], a_lo[0]}), .line_out(b_lo), .locked(b_lk),
           .frame_stb(fs_b), .tick_1k(), .ring_cad_n(), .dt_bit(), .ng_bit(),
           .mon_held(), .got_claim(), .dirs_held(dh_b),
           .port_busy(pb_b), .reg_busy(rg_b), .wq_ovf(ov_b),
           .wr_stb(), .wr_dst(), .wr_src(), .wr_bsy(), .wr_clm());

        mini_net_site #(.HAS_NET(1'b1), .NDIR(1),
                        .OWN_E(3'd2), .OWN_B(3'd4), .DIR0(2'd3), .G0(1'b1),
                        .LINE_PORTS(LP8),
                        .T_RISE(T_RISE), .T_FALL(T_FALL),
                        .RING_ON(RING_ON), .RING_OFF(RING_OFF),
                        .HIT(HIT), .ID(ID), .CLR(CLR), .NODIG(1500),
                        .T_GUARD(16), .T_CLAIM(250))
        C (.clk(clk_c), .rst_n(rst_n),
           .hook(hk_c), .tx(tx_c), .rx(rx_c), .e(ln_c),
           .line_in({3'b0, b_lo[1]}), .line_out(c_lo), .locked(c_lk),
           .frame_stb(fs_c), .tick_1k(), .ring_cad_n(), .dt_bit(), .ng_bit(),
           .mon_held(), .got_claim(), .dirs_held(dh_c),
           .port_busy(pb_c), .reg_busy(rg_c), .wq_ovf(ov_c),
           .wr_stb(), .wr_dst(), .wr_src(), .wr_bsy(), .wr_clm());
    end else begin : solo
        assign b_lo = 0; assign b_lk = 4'b1111; assign fs_b = 0;
        assign rx_b = 0; assign ln_b = 0; assign pb_b = 0;
        assign rg_b = 0; assign ov_b = 0; assign dh_b = 0;
        assign c_lo = 0; assign c_lk = 4'b1111; assign fs_c = 0;
        assign rx_c = 0; assign ln_c = 0; assign pb_c = 0;
        assign rg_c = 0; assign ov_c = 0; assign dh_c = 0;
    end endgenerate

    reg [6:0] frc = 0;
    reg       ms_stb = 0;
    always @(posedge clk_a) begin
        ms_stb <= 0;
        if (fs_a) begin
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

    integer ports[0:31];
    integer nports;
    integer pi;
    initial begin
        nports = 0;
        for (pi = 0; pi < 64; pi = pi + 1)
            if (LP_A[pi] && nports < 32) begin
                ports[nports] = pi;
                nports = nports + 1;
            end
    end

    localparam S_IDLE=0, S_LIFT=1, S_PULSE=2, S_MAKE=3, S_GAP=4,
               S_WAIT=5, S_TALK=6, S_HANG=7, S_RUNG=8;
    integer st[0:31], tmr[0:31], digs_left[0:31], pulses_left[0:31];
    integer digit_q[0:31][0:4];
    integer n_try, n_conn, n_nodt, n_rung, errs, r, i, j, dest, leave;
    reg quiet;

    task automatic plan_call(input integer ci);
        integer k;
        begin
            leave = (MODE >= 2) && (urnd(100) < FLOOD_PC);
            if (leave && MODE == 2) begin
                dest = ports[urnd(nports)];
                digs_left[ci] = 5;
                digit_q[ci][0] = 1;
                digit_q[ci][1] = 2;
                digit_q[ci][2] = 3;
                digit_q[ci][3] = dest[5:3] ? dest[5:3] : 10;
                digit_q[ci][4] = dest[2:0] ? dest[2:0] : 10;
            end else if (leave && MODE == 3) begin
                dest = ports[urnd(nports)];
                digs_left[ci] = 5;
                digit_q[ci][0] = 1;
                digit_q[ci][1] = 2;
                digit_q[ci][2] = 4;
                digit_q[ci][3] = dest[5:3] ? dest[5:3] : 10;
                digit_q[ci][4] = dest[2:0] ? dest[2:0] : 10;
            end else begin
                k = 0;
                do begin dest = ports[urnd(nports)]; k = k + 1;
                end while (dest == ports[ci] && k < 10);
                digs_left[ci] = 2;
                digit_q[ci][0] = dest[5:3] ? dest[5:3] : 10;
                digit_q[ci][1] = dest[2:0] ? dest[2:0] : 10;
            end
        end
    endtask

    always @(posedge clk_a) if (ms_stb && rst_n) begin
        if (quiet) begin
            hk_a <= 0;
            for (i = 0; i < nports; i = i + 1) begin
                st[i] <= S_IDLE; tmr[i] <= 0;
            end
        end else for (i = 0; i < nports; i = i + 1) begin
            if (tmr[i] > 0) tmr[i] <= tmr[i] - 1;

            case (st[i])
            S_IDLE: begin
                // Answer if rung; else lift after idle timer.
                if (!hk_a[ports[i]] && ln_a[ports[i]]) begin
                    st[i] <= S_RUNG; tmr[i] <= urnd(80);
                    n_rung <= n_rung + 1;
                end else if (tmr[i] == 0) begin
                    hk_a[ports[i]] <= 1'b1;
                    st[i] <= S_LIFT; tmr[i] <= DT_WAIT;
                    n_try <= n_try + 1;
                    plan_call(i);
                end
            end
            S_LIFT: begin
                // port_busy means the scanner attached (dial tone).
                if (pb_a[ports[i]]) begin
                    pulses_left[i] <= digit_q[i][0];
                    hk_a[ports[i]] <= 1'b0;
                    st[i] <= S_PULSE; tmr[i] <= BRK;
                end else if (tmr[i] == 0) begin
                    n_nodt <= n_nodt + 1;
                    hk_a[ports[i]] <= 1'b0;
                    st[i] <= S_HANG; tmr[i] <= CLR + 40;
                end
            end
            S_PULSE: begin
                if (tmr[i] == 0) begin
                    hk_a[ports[i]] <= 1'b1;
                    st[i] <= S_MAKE; tmr[i] <= MK;
                end
            end
            S_MAKE: begin
                if (tmr[i] == 0) begin
                    if (pulses_left[i] > 1) begin
                        pulses_left[i] <= pulses_left[i] - 1;
                        hk_a[ports[i]] <= 1'b0;
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
            end
            S_GAP: begin
                if (tmr[i] == 0) begin
                    pulses_left[i] <= digit_q[i][0];
                    hk_a[ports[i]] <= 1'b0;
                    st[i] <= S_PULSE; tmr[i] <= BRK;
                end
            end
            S_WAIT: begin
                // Connected when E is steady while we stay off-hook.
                if (hk_a[ports[i]] && ln_a[ports[i]]) begin
                    n_conn <= n_conn + 1;
                    st[i] <= S_TALK; tmr[i] <= HOLD_MS + urnd(HOLD_MS);
                end else if (tmr[i] == 0) begin
                    hk_a[ports[i]] <= 1'b0;
                    st[i] <= S_HANG; tmr[i] <= CLR + 40;
                end
            end
            S_RUNG: begin
                if (tmr[i] == 0) begin
                    if (ln_a[ports[i]]) begin
                        hk_a[ports[i]] <= 1'b1;
                        st[i] <= S_TALK; tmr[i] <= HOLD_MS + urnd(HOLD_MS);
                    end else st[i] <= S_IDLE;
                end
            end
            S_TALK: begin
                if (tmr[i] == 0) begin
                    hk_a[ports[i]] <= 1'b0;
                    st[i] <= S_HANG; tmr[i] <= CLR + 40;
                end
            end
            S_HANG: begin
                if (tmr[i] == 0) begin
                    st[i] <= S_IDLE;
                    tmr[i] <= IDLE_LO + urnd(IDLE_HI - IDLE_LO + 1);
                end
            end
            default: st[i] <= S_IDLE;
            endcase
        end
    end

    always @(posedge clk_a) if (fs_a)
        for (i = 0; i < 64; i = i + 1) if (hk_a[i]) tx_a[i] <= $random;
    always @(posedge clk_b) if (fs_b && PAIR)
        for (i = 0; i < 64; i = i + 1) if (hk_b[i]) tx_b[i] <= $random;
    always @(posedge clk_c) if (fs_c && CHAIN)
        for (i = 0; i < 64; i = i + 1) if (hk_c[i]) tx_c[i] <= $random;

    // Far-end phones answer when rung.
    integer qi;
    always @(posedge clk_b) if (ms_stb && PAIR && !quiet) begin
        for (qi = 16; qi < 64; qi = qi + 1)
            if (!hk_b[qi] && ln_b[qi]) hk_b[qi] <= 1'b1;
            else if (hk_b[qi] && !ln_b[qi] && !pb_b[qi]) hk_b[qi] <= 1'b0;
    end
    always @(posedge clk_c) if (ms_stb && CHAIN && !quiet) begin
        for (qi = 16; qi < 64; qi = qi + 1)
            if (!hk_c[qi] && ln_c[qi]) hk_c[qi] <= 1'b1;
            else if (hk_c[qi] && !ln_c[qi] && !pb_c[qi]) hk_c[qi] <= 1'b0;
    end

    // Last write per port (for jam diagnosis).
    integer last_ms [0:63];
    reg [5:0] last_src [0:63];
    reg       last_bsy [0:63], last_clm [0:63];
    integer   now_ms;
    integer   wi;
    initial begin
        now_ms = 0;
        for (wi = 0; wi < 64; wi = wi + 1) begin
            last_ms[wi] = -1; last_src[wi] = 0;
            last_bsy[wi] = 0; last_clm[wi] = 0;
        end
    end
    always @(posedge clk_a) if (ms_stb && rst_n) now_ms <= now_ms + 1;
    always @(posedge clk_a) if (ws_a) begin
        last_ms[wd_a]  <= now_ms;
        last_src[wd_a] <= wr_a;
        last_bsy[wd_a] <= wb_a;
        last_clm[wd_a] <= wc_a;
    end

    task automatic check_jam(input string tag);
        integer waited, p;
        begin
            waited = 0;
            while (waited < GAP &&
                   (rg_a || |(pb_a & LP_A) || dh_a != 0 || mh_a ||
                    (PAIR && (rg_b || |(pb_b & LP8) || dh_b != 0)) ||
                    (CHAIN && (rg_c || |(pb_c & LP8) || dh_c != 0)))) begin
                #(10 * NS);
                waited = waited + 10;
            end
            if (rg_a || |(pb_a & LP_A) || dh_a != 0 || mh_a) begin
                $display("     JAM A %s reg=%0d busy=%h dirs=%h mon=%0d ovf=%0d after %0d ms FAIL",
                         tag, rg_a, pb_a & LP_A, dh_a, mh_a, ov_a, waited);
                $display("          full pb=%h", pb_a);
                for (p = 0; p < 64; p = p + 1)
                    if (pb_a[p])
                        $display("          port %0o stuck, last wr %0d ms ago: src %0o bsy %0d clm %0d",
                                 p, (last_ms[p] < 0) ? -1 : now_ms - last_ms[p],
                                 last_src[p], last_bsy[p], last_clm[p]);
                errs = errs + 1;
            end else $display("     jam-clear A %s (%0d ms) ok", tag, waited);
            if (ov_a) begin $display("     wq_ovf A FAIL"); errs = errs + 1; end
            if (PAIR) begin
                if (rg_b || |(pb_b & LP8) || dh_b != 0 || ov_b) begin
                    $display("     JAM B %s reg=%0d busy=%h dirs=%h FAIL",
                             tag, rg_b, pb_b & LP8, dh_b);
                    errs = errs + 1;
                end else $display("     jam-clear B %s ok", tag);
            end
            if (CHAIN) begin
                if (rg_c || |(pb_c & LP8) || dh_c != 0 || ov_c) begin
                    $display("     JAM C %s FAIL", tag); errs = errs + 1;
                end else $display("     jam-clear C %s ok", tag);
            end
        end
    endtask

    initial begin
        errs = 0; n_try = 0; n_conn = 0; n_nodt = 0; n_rung = 0; quiet = 1;
        for (i = 0; i < 32; i = i + 1) begin st[i] = S_IDLE; tmr[i] = 0; end

        case (MODE)
        0: $display("MINI-LOAD 0 -- solo, no unit, 8 lines on block 2\n");
        1: $display("MINI-LOAD 1 -- solo, no unit, 16 lines on blocks 2+3\n");
        2: $display("MINI-LOAD 2 -- pair mini+unit, 8+8 lines, flood mix\n");
        3: $display("MINI-LOAD 3 -- chain 22=23=24 mini+unit under load\n");
        endcase

        #4000 rst_n = 1;
        if (MODE >= 2) wait (a_lk[0] && b_lk[0]);
        if (MODE == 3) wait (c_lk[0]);
        #(80 * NS);

        for (r = 0; r < ROUNDS; r = r + 1) begin
            $display("  round %0d (%0d ms)", r, BURST);
            quiet = 0;
            for (i = 0; i < nports; i = i + 1)
                tmr[i] = 10 + urnd(IDLE_HI);
            #(BURST * NS);
            quiet = 1;
            hk_a = 0; hk_b = 0; hk_c = 0;
            check_jam($sformatf("r%0d", r));
        end

        $display("\n  tries=%0d talk=%0d no-dt=%0d rung=%0d",
                 n_try, n_conn, n_nodt, n_rung);
        $display("  (single register: no-dt rises with offered load)");
        $display("  %0d errors. %s\n", errs, errs ? "FAIL" : "PASS");
        if (errs) $fatal(1);
        $finish;
    end

    initial begin
        #WD_NS;
        $display("TIMEOUT"); $finish;
    end
endmodule
