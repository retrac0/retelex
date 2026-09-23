// su_dial -- su-1.md §4: the Autovon pad and the pulse sequencer, as 74HC MSI.
//
// The set's dialer, shared by the behavioural set model (su1.v) and the board
// (su_d.v) the way pulse_rx is shared by pulse_reg and nano_reg -- so the
// timebase, the debounce and the one-deep queue stay in one place.
//
// It is pulse-gen.md §5's sequencer with that card's two adjustable sources
// taken off.  SU-1 has no shelf TX_OCT and no RC/DIP pot: TICK is the
// recovered downstream clock divided (su-1.md §5), so PPS and the break ratio
// are wiring, not a jumper field.
//
// Sixteen keys encode to a four-bit value v = count - 1 on two cascaded '148s,
// which is why a pad that must reach sixteen pulses still fits four bits:
// the sequencer emits a break, then compares, so it sends v + 1 = 1..16.
//
//   IDLE --off-hook--> WAIT --T_OH--> READY --key--> BRK <-> MK --> IDP
//                                       ^                            |
//                                       +-------------T_ID-----------+
`timescale 1ns/1ps

module su_dial #(
    parameter integer PPS       = 10,     // pulses per second
    parameter integer BREAK_PCT = 60,     // break as a percentage of the period
    parameter integer T_OH      = 500,    // seize wait, ms of TICK
    parameter integer T_ID      = 700,    // interdigit pause, ms
    parameter integer DEBOUNCE  = 20      // key stable time, ms
)(
    input            clk,
    input            rst_n,
    input            tick_1k,             // 1 kHz, recovered 64 kHz / 64 (§5)

    input            off_hook,
    input     [15:0] key_n,               // pad, active low; [0]=1 .. [15]=P

    output           seized,              // off-hook and past reset
    output           brk,                 // dial break: the line sends 1100
    output           off_normal           // train out or queued -- MUTE
);
    localparam integer PERIOD = 1000 / PPS;
    localparam integer BRK_MS = (PERIOD * BREAK_PCT) / 100;
    localparam integer MK_MS  = PERIOD - BRK_MS;

    localparam [2:0] ST_IDLE  = 3'd0, ST_WAIT = 3'd1, ST_READY = 3'd2,
                     ST_BRK   = 3'd3, ST_MK   = 3'd4, ST_IDP   = 3'd5;

    reg [2:0] st;

    // ---- the pad: two '148s, sixteen keys to v = count - 1 ---------------
    wire [2:0] hi_a_n, lo_a_n;
    wire       hi_gs_n, hi_eo_n, lo_gs_n, lo_eo_n;
    hc148 u_khi (.ei_n(1'b0),      .i_n(key_n[15:8]),
                 .a_n(hi_a_n), .gs_n(hi_gs_n), .eo_n(hi_eo_n));
    hc148 u_klo (.ei_n(hi_eo_n), .i_n(key_n[7:0]),
                 .a_n(lo_a_n), .gs_n(lo_gs_n), .eo_n(lo_eo_n));

    // Active-low outputs of a cascade tie together: A = /(hi & lo), and the
    // fourth bit is the high group's GS.
    wire [3:0] key_v  = { ~hi_gs_n, ~(hi_a_n & lo_a_n) };
    wire       key_dn = ~(hi_gs_n & lo_gs_n);          // some key is down

    // ---- debounce: one '393, both halves cascaded (20 ms needs five bits)
    wire [3:0] db1, db2;
    wire [7:0] db = {db2, db1};
    reg  [3:0] v_seen;
    wire       same   = (key_v == v_seen) & key_dn;
    wire       db_mr  = ~(off_hook & same);
    wire       db_top = (db == DEBOUNCE[7:0] - 8'd1);
    reg        armed;
    wire       db_ce  = off_hook & same & ~db_top & ~armed;
    hc393 u_db (
        .clk(clk), .rst_n(rst_n), .tick(tick_1k),
        .mr1(db_mr), .ce1(db_ce),               .q1(db1),
        .mr2(db_mr), .ce2(db_ce & (db1 == 4'd15)), .q2(db2)
    );

    wire key_stb = tick_1k & off_hook & same & db_top & ~armed;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v_seen <= 4'd0; armed <= 1'b0;
        end else if (!off_hook) begin
            v_seen <= 4'd0; armed <= 1'b0;
        end else if (tick_1k) begin
            if (!key_dn)          begin v_seen <= 4'd0; armed <= 1'b0; end
            else if (!same)       begin v_seen <= key_v; armed <= 1'b0; end
            else if (key_stb)     armed <= 1'b1;        // one-key lockout
        end
    end

    // ---- one-deep queue: five bits of an '174 (value + valid) ------------
    wire [5:0] qd, qq;
    wire       q_valid = qq[4];
    wire [3:0] q_v     = qq[3:0];
    wire       start   = (st == ST_READY) & q_valid;
    wire       q_load  = key_stb & ~q_valid;
    assign     qd      = {1'b0, ~start | q_load, q_load ? key_v : q_v};
    hc174 u_q (
        .clk(clk), .rst_n(rst_n),
        .en(tick_1k & (q_load | start)), .mr(~off_hook),
        .d(qd), .q(qq)
    );

    // ---- pulse count: one '163, 0..15 against v --------------------------
    wire [3:0] cq;
    wire       ctc;
    reg  [3:0] v_out;                                 // v of the train out
    wire       last = (cq == v_out);
    wire       adv_mk;                                // end of a make
    hc163 u_cnt (
        .clk(clk), .rst_n(rst_n), .tick(tick_1k),
        .mr(start), .ce(adv_mk & ~last), .q(cq), .tc(ctc)
    );

    // ---- the millisecond timer: one '4040 on TICK ------------------------
    wire [11:0] tq;
    wire        t_mr;
    hc4040 u_tmr (
        .clk(clk), .rst_n(rst_n), .tick(tick_1k),
        .mr(t_mr), .ce(1'b1), .q(tq)
    );
    wire at_oh  = tick_1k & (st == ST_WAIT) & (tq == T_OH[11:0]  - 12'd1);
    wire at_brk = tick_1k & (st == ST_BRK ) & (tq == BRK_MS[11:0] - 12'd1);
    wire at_mk  = tick_1k & (st == ST_MK  ) & (tq == MK_MS[11:0]  - 12'd1);
    wire at_id  = tick_1k & (st == ST_IDP ) & (tq == T_ID[11:0]  - 12'd1);

    assign adv_mk = at_mk;
    assign t_mr   = at_oh | at_brk | at_mk | at_id |
                    (tick_1k & (start | (st == ST_IDLE)));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)           st <= ST_IDLE;
        else if (!off_hook)   st <= ST_IDLE;
        else case (st)
            ST_IDLE:                 st <= ST_WAIT;
            ST_WAIT:  if (at_oh)     st <= ST_READY;
            ST_READY: if (tick_1k && q_valid) st <= ST_BRK;
            ST_BRK:   if (at_brk)    st <= ST_MK;
            ST_MK:    if (at_mk)     st <= last ? ST_IDP : ST_BRK;
            ST_IDP:   if (at_id)     st <= ST_READY;
            default:                 st <= ST_IDLE;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)         v_out <= 4'd0;
        else if (start)     v_out <= q_v;
    end

    assign seized     = (st != ST_IDLE);
    assign brk        = (st == ST_BRK);
    // Off-normal covers the queued digit too: the mute must already be on
    // when the first break leaves, or the make before it carries speech
    // (su-1.md §2, register.md §1.1).
    assign off_normal = (st == ST_BRK) | (st == ST_MK) | (st == ST_IDP) |
                        (seized & q_valid);

    wire _unused = |{ctc, qq[5], lo_eo_n, tq[11:10]};
endmodule
