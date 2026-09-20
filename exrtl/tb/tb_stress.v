// tb_stress -- a FULL exchange under random traffic, looking for a glitch or a
// jam.  One exchange of 48 lines, or a pair of them on a trunk.
//
// Everything else in this suite drives a scenario someone thought of.  This one
// drives forty-eight callers at once and checks invariants that must hold
// whatever they do:
//
//   THE PARTNER INVARIANT.  Every line transmits its own name -- eight ones,
//   then a zero, its exchange and its port -- so every line can say who it is
//   listening to.  Then, continuously:
//     symmetry    i hears j  =>  j hears i.  A one-way patch is a glitch
//     exclusive   i hears j and k hears j, i != k, is TWO CALLERS ON ONE LINE:
//                 the glare of exch-marker.md 3, and the thing a pool of
//                 registers made possible
//     not itself  a port patched to itself is a glitch
//
//   THE JAM INVARIANT.  The traffic runs in ROUNDS: a burst, then everyone on
//   hook and a quiet gap long enough for every release detector to time out.
//   At the end of each gap NOTHING may be held -- no port BUSY, no register
//   busy, no trunk channel seized.  Anything that ratchets up round on round is
//   a leak, and a leak is a jam with a date on it.
//
// The callers do not behave.  One in ten hangs up in the middle of dialling,
// one in ten dials into block 1 -- the network key, and then stops -- one in
// ten dials its own number, one in twenty lifts and never dials at all, one in
// five flashes the hook in the middle of a call, one in ten lifts again before
// its own port has finished releasing, and a third of them dial the same four
// "hot" numbers to make glare likely rather than merely possible.
`timescale 1ns/1ps

module tb_stress #(
    parameter integer PAIR    = 0,        // 1: two exchanges on a trunk
    parameter integer ROUNDS  = 2,        // `make stress` is a regression, not a soak
    parameter integer BURST   = 1800,     // ms of traffic in a round
    parameter integer GAP     = 900,      // ms of quiet after it, longer than any detector
    parameter integer NREG    = 8,
    parameter integer IDLE_LO = 700,      // ms between one call and the next
    parameter integer IDLE_HI = 3000,
    parameter integer DT_WAIT = 1500,     // how long a caller waits for dial tone
    parameter integer PPM     = 0,        // the far exchange's crystal offset
    parameter integer SEED    = 32'h1234_5678,
    parameter         TRACE   = 1'b0
) ();
    localparam integer HIT = 1, ID = 16, CLR = 32;
    localparam integer T_RISE = 64, T_FALL = 2048;
    localparam integer RING_ON = 200, RING_OFF = 400;
    localparam integer NS = 1_000_000;                  // ns in a model ms

    // lines fill blocks 2-7: ports 20-77, dialled as their own h s
    localparam [63:0] LP = 64'hFFFF_FFFF_FFFF_0000;
    localparam integer NLINE = 48;
    localparam [63:0] TR = 64'h0000_0000_0000_00EE;     // the trunk's six channels

    // B runs on its own crystal: mf8-backplane.md 2's plesiochronous case, which
    // is what any two ends of a link are.  A slip should cost a bit, not a call.
    localparam real HALF_B = 122.0703 * (1.0 - PPM / 1000000.0);
    reg clk_a = 0, clk_b = 0, rst_n = 0;
    always #122.0703 clk_a = ~clk_a;
    initial begin #40; forever #(HALF_B) clk_b = ~clk_b; end

    reg  [63:0] hk_a = 0, tx_a = 0, hk_b = 0, tx_b = 0;
    wire [63:0] rx_a, ln_a, rx_b, ln_b, pb_a, pb_b;
    wire [NREG-1:0] rg_a, rg_b;
    wire        ov_a, ov_b;
    wire [15:0] df_a, df_b;
    wire        ws_a, ws_b, wb_a, wb_b, wc_a, wc_b;
    wire [5:0]  wd_a, wd_b, wr_a, wr_b;
    wire        a2b, b2a, lk_a, lk_b, fs_a, fs_b, rc_a, rc_b;

    // A is 22 and faces E; B is 23 and faces W.  With PAIR = 0 B is not there
    // and A's trunk card sees no carrier, so its six channels read unequipped
    // and the key `1` finds nothing to seize: the standalone exchange.
    net_site #(.OWN_E(3'd2), .OWN_B(3'd2), .DIR0(2'd2), .LINE_PORTS(LP),
               .T_RISE(T_RISE), .T_FALL(T_FALL), .RING_ON(RING_ON), .RING_OFF(RING_OFF),
               .HIT(HIT), .ID(ID), .CLR(CLR), .T_GUARD(16), .T_CLAIM(250),
               .NREG(NREG))
    A (.clk(clk_a), .rst_n(rst_n),
       .hook(hk_a), .tx(tx_a), .rx(rx_a), .e(ln_a),
       .line_in(b2a), .line_out(a2b), .locked(lk_a),
       .frame_stb(fs_a), .ring_cad_n(rc_a), .dt_bit(), .ng_bit(),
       .mon_held(), .got_claim(), .dirs_held(),
       .fan_legs(), .res_used(), .port_busy(pb_a),
       .regs_busy(rg_a), .wq_ovf(ov_a), .n_defer(df_a),
       .wr_stb(ws_a), .wr_dst(wd_a), .wr_src(wr_a), .wr_bsy(wb_a), .wr_clm(wc_a));

    generate if (PAIR) begin : two
        net_site #(.OWN_E(3'd2), .OWN_B(3'd3), .DIR0(2'd3), .G0(1'b1), .LINE_PORTS(LP),
                   .T_RISE(T_RISE), .T_FALL(T_FALL), .RING_ON(RING_ON), .RING_OFF(RING_OFF),
                   .HIT(HIT), .ID(ID), .CLR(CLR), .T_GUARD(16), .T_CLAIM(250),
                   .NREG(NREG))
        B (.clk(clk_b), .rst_n(rst_n),
           .hook(hk_b), .tx(tx_b), .rx(rx_b), .e(ln_b),
           .line_in(a2b), .line_out(b2a), .locked(lk_b),
           .frame_stb(fs_b), .ring_cad_n(rc_b), .dt_bit(), .ng_bit(),
           .mon_held(), .got_claim(), .dirs_held(),
           .fan_legs(), .res_used(), .port_busy(pb_b),
           .regs_busy(rg_b), .wq_ovf(ov_b), .n_defer(df_b),
           .wr_stb(ws_b), .wr_dst(wd_b), .wr_src(wr_b), .wr_bsy(wb_b), .wr_clm(wc_b));
    end else begin : one
        assign b2a = 1'b0;
        assign rx_b = 64'd0; assign ln_b = 64'd0; assign pb_b = 64'd0;
        assign rg_b = {NREG{1'b0}}; assign ov_b = 1'b0; assign df_b = 16'd0;
        assign ws_b = 1'b0; assign wd_b = 6'd0; assign wr_b = 6'd0;
        assign wb_b = 1'b0; assign wc_b = 1'b0;
        assign lk_b = 1'b1; assign fs_b = 1'b0; assign rc_b = 1'b1;
    end endgenerate

    // ---- who each line is listening to ----------------------------------
    // Every line sends 8 ones and then {0, exchange, port}: an eight-run cannot
    // appear in the data, so the sync is unambiguous, and FILL is 1010 so an
    // idle path never fakes one.  A partner counts only when the same name
    // arrives twice running.
    localparam [7:0] NONE = 8'hFF;

    reg  [3:0] txbit [0:127];            // which bit of its frame each line is on
    reg [15:0] shift [0:127];
    reg  [7:0] heard [0:127];            // 0xFF: nobody
    reg  [7:0] cand  [0:127];
    reg  [7:0] hage  [0:127];            // frames since the last good name

    function [7:0] name(input integer x, input integer port);
        name = {1'b0, x[0], port[5:0]};
    endfunction

    integer q;
    always @(posedge clk_a) if (fs_a) begin
        for (q = 16; q < 64; q = q + 1) begin
            // transmit
            txbit[q] <= txbit[q] + 4'd1;
            tx_a[q]  <= (txbit[q] < 4'd8) ? 1'b1 : name(0, q) >> (4'd15 - txbit[q]);
            // receive
            shift[q] <= {shift[q][14:0], rx_a[q]};
            if (shift[q][15:8] == 8'hFF && !shift[q][7]) begin
                if (cand[q] == shift[q][7:0]) begin heard[q] <= shift[q][7:0]; hage[q] <= 0; end
                cand[q] <= shift[q][7:0];
            end
            if (hage[q] == 8'd200) heard[q] <= NONE;
            else hage[q] <= hage[q] + 8'd1;
        end
    end

    integer qq;
    always @(posedge clk_b) if (fs_b && PAIR) begin
        for (qq = 16; qq < 64; qq = qq + 1) begin
            txbit[64+qq] <= txbit[64+qq] + 4'd1;
            tx_b[qq]     <= (txbit[64+qq] < 4'd8) ? 1'b1
                                                 : name(1, qq) >> (4'd15 - txbit[64+qq]);
            shift[64+qq] <= {shift[64+qq][14:0], rx_b[qq]};
            if (shift[64+qq][15:8] == 8'hFF && !shift[64+qq][7]) begin
                if (cand[64+qq] == shift[64+qq][7:0]) begin
                    heard[64+qq] <= shift[64+qq][7:0]; hage[64+qq] <= 0;
                end
                cand[64+qq] <= shift[64+qq][7:0];
            end
            if (hage[64+qq] == 8'd200) heard[64+qq] <= NONE;
            else hage[64+qq] <= hage[64+qq] + 8'd1;
        end
    end

    // ---- the millisecond both sides are stepped on ----------------------
    reg [6:0] frc = 0;
    reg       ms_stb = 1'b0;
    always @(posedge clk_a) begin
        ms_stb <= 1'b0;
        if (fs_a) begin
            if (frc == 7'd63) begin frc <= 0; ms_stb <= 1'b1; end
            else frc <= frc + 7'd1;
        end
    end

    // ---- the random stream, the tb's own so both simulators agree --------
    reg [31:0] lcg = SEED;
    function integer urnd(input integer n);          // 0 .. n-1
        begin
            lcg = lcg * 32'd1664525 + 32'd1013904223;
            urnd = (lcg >> 16) % n;
        end
    endfunction

    // ---- one caller a line ------------------------------------------------
    localparam integer S_IDLE=0, S_LIFT=1, S_BRK=2, S_MK=3, S_PAUSE=4,
                       S_WAIT=5, S_TALK=6, S_HANG=7, S_RUNG=8;

    integer st   [0:127];
    integer tmr  [0:127];
    integer np   [0:127];                // pulses left in this digit
    integer dig  [0:127];                // digits left after this one
    integer dq   [0:127];                // the digits still to dial, 4 bits each
    integer kind [0:127];
    integer ehi  [0:127];                // ms of steady E while off-hook
    integer flash[0:127];                // ms left of a hook flash

    // what happened
    integer n_try = 0, n_conn = 0, n_gaveup = 0, n_rung = 0, n_nodt = 0;
    integer was_try = 0, was_conn = 0, was_gave = 0, was_rung = 0, was_nodt = 0;
    integer n_sym = 0, n_glare = 0, n_self = 0, n_stuck = 0;
    integer errs = 0, chk = 0;
    reg     running = 1'b0;

    integer i, j, p, d, x, hot;

    task want(input v, input string what);
        begin
            chk = chk + 1;
            if (!v) begin errs = errs + 1; $display("     %-52s FAIL", what); end
            else $display("     %-52s ok", what);
        end
    endtask

    task wantn(input v, input integer got, input string what);
        begin
            chk = chk + 1;
            if (!v) begin errs = errs + 1;
                $display("     %-52s FAIL (%0d)", what, got); end
            else $display("     %-52s ok  (%0d)", what, got);
        end
    endtask

    // a line index 0-127 is exchange x, port p
    function integer lx(input integer x, input integer p); lx = x*64 + p; endfunction
    function        hook_of(input integer n); hook_of = n[6] ? hk_b[n[5:0]] : hk_a[n[5:0]]; endfunction
    function        e_of(input integer n);    e_of    = n[6] ? ln_b[n[5:0]] : ln_a[n[5:0]]; endfunction
    // Dial tone, as far as a testbench can see it: the marker has written this
    // port with the tone as its source, so its BUSY is up.  A caller who dials
    // before this is dialling into a register nobody gave them.
    function        dt_of(input integer n);   dt_of   = n[6] ? pb_b[n[5:0]] : pb_a[n[5:0]]; endfunction

    task set_hook(input integer n, input v);
        begin if (n[6]) hk_b[n[5:0]] = v; else hk_a[n[5:0]] = v; end
    endtask

    // Queue the digits of a call.  dq holds them four bits each, least
    // significant first; a dialled 0 is ten pulses.
    task plan(input integer n);
        integer tgt, x2, p2, r;
        begin
            kind[n] = urnd(100);
            x2 = (PAIR && kind[n] < 25) ? (n[6] ? 0 : 1) : (n[6] ? 1 : 0);
            hot = urnd(100);
            if (hot < 30) p2 = 6'o20 + 8 * (hot % 4);          // a few hot numbers
            else          p2 = 16 + urnd(48);
            r = urnd(100);
            if      (r < 10) p2 = n[5:0];                       // its own number
            else if (r < 20) p2 = 6'o10 + urnd(8);              // block 1: not a line
            tgt = p2;
            if (x2 == n[6]) begin                               // a local call: h s
                dq[n]  = ((tgt & 6'o07) << 4) | ((tgt >> 3) & 7);
                dig[n] = 2;
            end else begin                                      // 1 e b h s
                dq[n]  = (((tgt & 6'o07) << 16) | (((tgt >> 3) & 7) << 12)
                          | ((x2 ? 3 : 2) << 8) | (2 << 4) | 1);
                dig[n] = 5;
            end
            np[n]  = 0;
        end
    endtask

    // Hanging up.  ONE IN TEN does not stay on hook long enough for its own
    // port to release: 256 ms of M low is what the detector wants, and a
    // shorter break is a flash, not a release (exch-marker.md 7).  The caller
    // then finds their own port still busy and gets no dial tone at all.
    task hang_up(input integer n);
        begin
            st[n] = S_HANG; set_hook(n, 1'b0);
            tmr[n] = (urnd(100) < 10) ? 5 + urnd(20) : 120 + urnd(400);
        end
    endtask

    task next_digit(input integer n);
        begin
            if (dig[n] == 0) begin st[n] = S_WAIT;  tmr[n] = 400 + urnd(600); end
            else begin
                d = dq[n] & 4'hF;
                dq[n] = dq[n] >> 4;
                dig[n] = dig[n] - 1;
                np[n] = (d == 0) ? 10 : d;
                st[n] = S_BRK; tmr[n] = 12;
                set_hook(n, 1'b0);
            end
        end
    endtask

    always @(posedge clk_a) if (rst_n && ms_stb) begin
        for (i = 0; i < 128; i = i + 1)
          if ((i < 64 || PAIR) && i[5:0] >= 16) begin
            if (tmr[i] > 0) tmr[i] = tmr[i] - 1;

            // E steady while off-hook means the far end answered
            if (hook_of(i) && e_of(i)) ehi[i] = ehi[i] + 1;
            else if (hook_of(i))       ehi[i] = 0;

            case (st[i])
            S_IDLE: begin
                // Nobody lifts during the quiet gap, not even to answer: the
                // gap is there to prove that what is left is the exchange's
                // doing and not the traffic's.
                if (running && e_of(i)) begin             // being rung
                    st[i] = S_RUNG; tmr[i] = urnd(250); n_rung = n_rung + 1;
                end else if (running && tmr[i] == 0) begin
                    n_try = n_try + 1;
                    plan(i);
                    set_hook(i, 1'b1);
                    st[i] = S_LIFT; tmr[i] = DT_WAIT; ehi[i] = 0;
                end
            end
            S_LIFT: begin
                // wait for dial tone, as a caller does: registers are a pool
                // and a caller who finds none free is not refused, dial tone
                // is late (exch-marker.md 6)
                if (dt_of(i)) begin
                    if (kind[i] < 5) begin                // lifts and never dials
                        st[i] = S_WAIT; tmr[i] = 300 + urnd(700);
                    end else begin
                        st[i] = S_PAUSE; tmr[i] = 10 + urnd(40);
                    end
                end else if (tmr[i] == 0) begin
                    n_nodt = n_nodt + 1;
                    hang_up(i);
                end
            end
            S_BRK: if (tmr[i] == 0) begin
                set_hook(i, 1'b1); st[i] = S_MK; tmr[i] = 8;
            end
            S_MK: if (tmr[i] == 0) begin
                np[i] = np[i] - 1;
                if (np[i] > 0) begin set_hook(i, 1'b0); st[i] = S_BRK; tmr[i] = 12; end
                else if (kind[i] >= 5 && kind[i] < 15 && dig[i] > 0)
                    hang_up(i);                           // hangs up mid-number
                else begin st[i] = S_PAUSE; tmr[i] = 60 + urnd(80); end
            end
            S_PAUSE: if (tmr[i] == 0) next_digit(i);
            S_WAIT: begin
                if (ehi[i] > 20) begin                    // answered
                    n_conn = n_conn + 1;
                    st[i] = S_TALK; tmr[i] = 150 + urnd(600);
                end else if (tmr[i] == 0) begin
                    n_gaveup = n_gaveup + 1;
                    hang_up(i);
                end
            end
            S_RUNG: if (tmr[i] == 0) begin
                if (!running) st[i] = S_IDLE;
                else if (e_of(i) || ehi[i] > 0) begin
                    set_hook(i, 1'b1);
                    st[i] = S_TALK; tmr[i] = 150 + urnd(600); ehi[i] = 0;
                end else st[i] = S_IDLE;                  // it stopped ringing
            end
            S_TALK: begin
                // A hook FLASH in the middle of a call: a break shorter than a
                // release must not take the call down (exch-marker.md 7 --
                // "breaks <= 103 ms against a release >= 204 ms").
                if (flash[i] > 0) begin
                    flash[i] = flash[i] - 1;
                    set_hook(i, flash[i] == 0);
                end else if (tmr[i] == 40 && kind[i] >= 80) begin
                    flash[i] = 4 + urnd(8); set_hook(i, 1'b0);
                end else if (tmr[i] == 0
                             || (hook_of(i) && ehi[i] == 0 && tmr[i] < 400))
                    hang_up(i);
            end
            S_HANG: if (tmr[i] == 0) begin
                st[i] = S_IDLE;
                tmr[i] = IDLE_LO + urnd(IDLE_HI - IDLE_LO);
            end
            default: st[i] = S_IDLE;
            endcase
        end
    end

    // ---- the partner invariant, every millisecond -------------------------
    integer a, b2, persist [0:127];
    reg [7:0] hp;
    always @(posedge clk_a) if (rst_n && ms_stb) begin
        for (a = 0; a < 128; a = a + 1)
          if ((a < 64 || PAIR) && a[5:0] >= 16) begin
            hp = heard[a];
            if (hp == NONE) persist[a] = 0;
            else persist[a] = persist[a] + 1;
            // A patch is not symmetric for a few ms while it is being made or
            // torn down; 40 ms is longer than any write takes.
            if (hp != NONE && persist[a] > 40) begin
                b2 = {hp[6], hp[5:0]};
                if (b2 == a) begin
                    n_self = n_self + 1;
                    if (n_self < 4) $display("     GLITCH: %0d.%0o hears ITSELF",
                                             a[6], a[5:0]);
                end else if (heard[b2] != name(a[6], a[5:0])
                             && heard[b2] != NONE) begin
                    n_sym = n_sym + 1;
                    if (n_sym < 4)
                        $display("     GLITCH: %0d.%0o hears %0d.%0o, which hears %0d.%0o",
                                 a[6], a[5:0], b2[6], b2[5:0],
                                 heard[b2][6], heard[b2][5:0]);
                end
                for (j = a + 1; j < 128; j = j + 1)
                    if ((j < 64 || PAIR) && j[5:0] >= 16
                        && heard[j] == hp && persist[j] > 40) begin
                        n_glare = n_glare + 1;
                        if (n_glare < 4)
                            $display("     GLITCH: %0d.%0o AND %0d.%0o both hear %0d.%0o",
                                     a[6], a[5:0], j[6], j[5:0], hp[6], hp[5:0]);
                    end
            end
        end
    end

    // ---- a port held with nothing on it ------------------------------------
    // A jam does not wait for the end of a round to exist.  A port whose line
    // is on hook, whose E has been low far longer than any ring cadence, and
    // which is still BUSY, is holding something nobody asked for.
    // A WRITE THAT CANNOT BE UNDONE.  A port releases on the FALL of one of its
    // two detectors (exch-fabric.md 3.5).  Write one BUSY while both are
    // already low -- its line long on hook, and a source that will never raise
    // its E -- and there is no edge left to come: the port is out of service
    // until something writes it again.  This catches the write itself rather
    // than waiting 300 ms to notice the result.
    integer n_noedge = 0;
    function dead_src(input integer x, input integer src);
        begin
            if (src < 8)        dead_src = 1'b1;          // port 00, or a trunk channel
            else if (src < 16)  dead_src = 1'b1;          // a tone: "a source never answers"
            else                dead_src = x ? !hk_b[src] : !hk_a[src];
        end
    endfunction

    // the last latch write each port got, and the hook at that moment
    integer lw_src [0:127], lw_bsy [0:127], lw_st [0:127], lw_on [0:127], lw_clm [0:127];
    integer lw_son [0:127];              // the SOURCE's line, on hook how long
    real    lw_t [0:127];
    always @(posedge clk_a) if (ws_a) begin
        if (wb_a && !wc_a && wd_a >= 16 && onhk[wd_a] > 40 && elow[wd_a] > 40
            && dead_src(0, wr_a)) begin
            n_noedge = n_noedge + 1;
            if (n_noedge < 6)
                $display("     NO EDGE: 0.%0o written BUSY at %0.1f ms with src %0o -- its line has been on hook %0d ms and its E dead %0d ms, so neither detector can fall",
                         wd_a, $realtime / NS, wr_a, onhk[wd_a], elow[wd_a]);
        end
        lw_src[wd_a] = wr_a; lw_bsy[wd_a] = wb_a; lw_clm[wd_a] = wc_a;
        lw_t[wd_a] = $realtime;
        lw_st[wd_a] = st[wd_a]; lw_on[wd_a] = hk_a[wd_a] ? 0 : onhk[wd_a];
        lw_son[wd_a] = (wr_a < 16) ? -1 : (hk_a[wr_a] ? 0 : onhk[wr_a]);
    end
    always @(posedge clk_b) if (ws_b && PAIR) begin
        if (wb_b && !wc_b && wd_b >= 16 && onhk[64+wd_b] > 40 && elow[64+wd_b] > 40
            && dead_src(1, wr_b)) begin
            n_noedge = n_noedge + 1;
            if (n_noedge < 6)
                $display("     NO EDGE: 1.%0o written BUSY at %0.1f ms with src %0o -- its line has been on hook %0d ms and its E dead %0d ms, so neither detector can fall",
                         wd_b, $realtime / NS, wr_b, onhk[64+wd_b], elow[64+wd_b]);
        end
        lw_src[64+wd_b] = wr_b; lw_bsy[64+wd_b] = wb_b; lw_clm[64+wd_b] = wc_b;
        lw_t[64+wd_b] = $realtime;
        lw_st[64+wd_b] = st[64+wd_b]; lw_on[64+wd_b] = hk_b[wd_b] ? 0 : onhk[64+wd_b];
        lw_son[64+wd_b] = (wr_b < 16) ? -1 : (hk_b[wr_b] ? 0 : onhk[64+wr_b]);
    end

    integer onhk [0:127], elow [0:127], stuck [0:127], bsyms [0:127];
    integer n_held = 0, n_stuck_ms = 0, longest = 0;
    integer z;
    reg     bsy;
    always @(posedge clk_a) if (rst_n && ms_stb) begin
        for (z = 0; z < 128; z = z + 1)
          if ((z < 64 || PAIR) && z[5:0] >= 16) begin
            if (hook_of(z)) onhk[z] = 0; else onhk[z] = onhk[z] + 1;
            if (e_of(z))    elow[z] = 0; else elow[z] = elow[z] + 1;
            bsy = z[6] ? pb_b[z[5:0]] : pb_a[z[5:0]];
            // BUSY for 300 ms as well, or this fires the instant a port is
            // written to ring: the line has been on hook and its E dead since
            // long before the write, and the cadence takes a few ms to appear.
            if (bsy) bsyms[z] = bsyms[z] + 1; else bsyms[z] = 0;
            if (onhk[z] > 300 && elow[z] > 300 && bsyms[z] > 300) begin
                if (stuck[z] == 0 && n_held < 8)
                    $display("     HELD: %0d.%0o at %0.1f ms.  Last write %0.1f ms ago: src %0o bsy %0d; the SOURCE's line was on hook %0d ms then, and is %0s now",
                             z[6], z[5:0], $realtime / NS,
                             ($realtime - lw_t[z]) / NS, lw_src[z], lw_bsy[z],
                             lw_son[z],
                             (lw_src[z] >= 16 && (z[6] ? hk_b[lw_src[z]] : hk_a[lw_src[z]]))
                                 ? "OFF hook" : "on hook");
                stuck[z] = stuck[z] + 1;
                n_stuck_ms = n_stuck_ms + 1;
            end else if (stuck[z] > 0) begin
                n_held = n_held + 1;
                if (stuck[z] > longest) longest = stuck[z];
                if (n_held < 8)
                    $display("           ... cleared after %0d ms", stuck[z] + 300);
                stuck[z] = 0;
            end
        end
    end

    // ---- what is held ------------------------------------------------------
    wire [31:0] busy_a = $countones(pb_a);
    wire [31:0] busy_b = $countones(pb_b);
    integer peak = 0;
    always @(posedge clk_a) if (busy_a + busy_b > peak) peak <= busy_a + busy_b;

    integer r2, leak, t2;

    task quiesce(input integer ms);
        integer t;
        begin
            running = 1'b0;
            for (t = 0; t < 128; t = t + 1) begin
                if (t < 64) hk_a[t[5:0]] = 1'b0;
                else        hk_b[t[5:0]] = 1'b0;
                st[t] = S_IDLE; tmr[t] = urnd(IDLE_HI); ehi[t] = 0;
            end
            #(ms * NS);
        end
    endtask

    initial begin
        for (i = 0; i < 128; i = i + 1) begin
            st[i] = S_IDLE; tmr[i] = (i * 137) % IDLE_HI; np[i] = 0; dig[i] = 0; dq[i] = 0;
            kind[i] = 50; ehi[i] = 0; flash[i] = 0; heard[i] = NONE; cand[i] = NONE;
            onhk[i] = 0; elow[i] = 0; stuck[i] = 0; bsyms[i] = 0;
            lw_src[i] = 0; lw_bsy[i] = 0; lw_st[i] = 0; lw_on[i] = 0;
            lw_son[i] = 0; lw_clm[i] = 0; lw_t[i] = 0.0;
            shift[i] = 0; txbit[i] = i[3:0]; hage[i] = 0; persist[i] = 0;
        end

        if (PAIR) $display("STRESS (RTL) -- TWO exchanges on a trunk %0d ppm apart, 48 lines each.\n", PPM);
        else      $display("STRESS (RTL) -- ONE exchange, 48 lines, random traffic.\n");
        #4000 rst_n = 1;
        if (PAIR) wait (lk_a && lk_b);
        #(50 * NS);
        $display("  Ports fitted: %0d lines, 2 tones, 6 trunk channels an exchange.",
                 NLINE);
        $display("  %0d registers, %0d monitor cells a trunk block.\n", NREG, 2);

        leak = 0;
        for (r2 = 0; r2 < ROUNDS; r2 = r2 + 1) begin
            running = 1'b1;
            #(BURST * NS);
            quiesce(GAP);
            $display("  round %0d: %0d lifted, %0d waited out dial tone, %0d talked, %0d gave up, %0d answered;  peak %0d ports",
                     r2 + 1, n_try - was_try, n_nodt - was_nodt, n_conn - was_conn,
                     n_gaveup - was_gave, n_rung - was_rung, peak);
            // A jam is a round that stops making calls, not one that makes
            // fewer.  Every round must get some through.
            chk = chk + 1;
            if (n_conn - was_conn < 1) begin
                errs = errs + 1;
                $display("     JAM: not one call was completed in this round");
            end
            was_try = n_try; was_nodt = n_nodt; was_conn = n_conn;
            was_gave = n_gaveup; was_rung = n_rung; peak = 0;
            // NOTHING may be held once every detector has timed out
            chk = chk + 1;
            if ($countones(pb_a) != 0 || $countones(pb_b) != 0) begin
                errs = errs + 1; leak = leak + 1;
                $display("     JAM: %0d ports still BUSY after %0d ms with every line on hook",
                         $countones(pb_a) + $countones(pb_b), GAP);
                for (t2 = 0; t2 < 128; t2 = t2 + 1)
                  if ((t2 < 64 || PAIR) && (t2[6] ? pb_b[t2[5:0]] : pb_a[t2[5:0]]))
                    $display("          %0d.%0o, last written %0.1f ms ago: src %0o bsy %0d clm %0d",
                             t2[6], t2[5:0], ($realtime - lw_t[t2]) / NS,
                             lw_src[t2], lw_bsy[t2], lw_clm[t2]);
            end
            chk = chk + 1;
            if (rg_a != 0 || (PAIR && rg_b != 0)) begin
                errs = errs + 1;
                $display("     JAM: a register is still busy  (A %b, B %b)", rg_a, rg_b);
            end
        end

        $display("");
        // Every round must get SOME call through -- that is the per-round check
        // above.  How many is traffic, not correctness: the overload run is
        // meant to leave most callers waiting for dial tone.
        wantn(n_conn >= ROUNDS, n_conn, "calls went through from end to end");
        wantn(n_glare == 0, n_glare, "no line was heard by two callers at once");
        wantn(n_sym == 0, n_sym, "every patch was symmetric");
        wantn(n_self == 0, n_self, "no port was patched to itself");
        wantn(leak == 0, leak, "every round ended with nothing held");
        wantn(n_noedge == 0, n_noedge,
              "no port was written BUSY with no edge left to release it");
        wantn(n_held == 0, n_held,
              "no port was left BUSY with its line on hook and E dead");
        if (n_held > 0)
            $display("     (%0d ms in all, the longest %0d ms)", n_stuck_ms, longest + 300);
        want(!ov_a && !ov_b, "the marker's write queue never overran");
        $display("     (a claim and a caller wanted the port bus in one cycle %0d times",
                 df_a + df_b);
        $display("      -- each one a wrong number, before the marker took to deferring)");
        wantn($countones(pb_a & TR) == 0, $countones(pb_a & TR),
              "no trunk channel left seized");

        $display("\n  %0d checks, %0d errors.  %s", chk, errs, (errs == 0) ? "PASS" : "FAIL");
        $finish;
    end

    initial begin #300_000_000_000; $display("  TIMEOUT"); $finish; end
endmodule
