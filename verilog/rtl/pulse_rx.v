// pulse_rx -- register.md §4's windows, as 74HC MSI.
//
// One HC4040 on TICK, reset by RST (edge delayed one tick: sample-then-retrigger).
// HIT / ID / CLR latches set when the count reaches the window (board defaults
// are Q4=8, Q8=128, Q9=256).  Parameters remain so scaled benches keep working.
//
// Pulse count is one HC163, saturates at 15 (register.md §4).  STB = rising
// ID · /BRK · (count ≠ 0).
//
// CNTW = 3 is the nano-marker's register instead (nano-marker.md §3): half an
// HC393 and one FF, counting 1..7, with the eighth break wrapping to 0 and
// freezing there.  8, 9 and 0 then all read 0, which is what oct() made of
// them anyway, and the '163 comes off the board.
`timescale 1ns/1ps

module pulse_rx #(
    parameter integer HIT = 8,
    parameter integer ID  = 128,
    parameter integer CLR = 256,
    parameter integer CNTW = 4
)(
    input            clk,
    input            rst_n,
    input            tick_1k,
    input            arm,
    input            m,
    output reg [3:0] cnt,
    output reg       dig_stb,
    output reg       clear,
    output reg       counting,
    output reg       brk_stb
);
    // ---- HC175: H→D1→D2→D3, D4≤EDGE; EDGE=D2⊕D3; BRK=/D2 (D2 is make) ----
    // After /arm the chain is zero; an already-off-hook line shifting 1s in
    // looks like a make edge.  Hold RST and inhibit count for four TICKs
    // after arm so the '175 can flush (register.md: held clear until seized).
    reg  [3:0] arm_d;
    always @(posedge clk or negedge rst_n)
        if (!rst_n)                         arm_d <= 4'd0;
        else if (tick_1k)                   arm_d <= {arm_d[2:0], arm};
    wire       flush   = arm & ~&arm_d;              // arm high, pipe not full

    wire [3:0] syn_q;
    wire       edge_e;
    hc86_xor2 u_xor (.a(syn_q[1]), .b(syn_q[2]), .y(edge_e));  // D2 ⊕ D3
    wire [3:0] syn_d  = { edge_e, syn_q[1], syn_q[0], m };
    hc175 u_syn (
        .clk(clk), .rst_n(rst_n), .tick(tick_1k), .mr(!arm),
        .d(syn_d), .q(syn_q)
    );
    wire make_s  = syn_q[1];                           // D2
    wire brk     = ~make_s;
    wire rst_tmr = syn_q[3] | !arm | flush;            // D4 = RST, plus flush

    // ---- HC4040 timer ---------------------------------------------------
    wire [11:0] tq;
    wire t_ce = arm & ~rst_tmr;
    hc4040 u_tmr (
        .clk(clk), .rst_n(rst_n), .tick(tick_1k),
        .mr(rst_tmr), .ce(t_ce), .q(tq)
    );
    wire reach_hit = t_ce && brk  && (tq == HIT[11:0] - 12'd1);
    wire reach_id  = t_ce && ~brk && (tq == ID[11:0]  - 12'd1);
    wire reach_clr = t_ce && brk  && (tq == CLR[11:0] - 12'd1);

    wire hit_q, id_q, clr_q, id_d;
    hc74_dff u_hit (.clk(clk), .rst_n(rst_n),
        .tick(tick_1k && (reach_hit || rst_tmr)), .clr(rst_tmr), .d(1'b1), .q(hit_q));
    hc74_dff u_id  (.clk(clk), .rst_n(rst_n),
        .tick(tick_1k && (reach_id  || rst_tmr)), .clr(rst_tmr), .d(1'b1), .q(id_q));
    hc74_dff u_clr (.clk(clk), .rst_n(rst_n),
        .tick(tick_1k && (reach_clr || rst_tmr)), .clr(rst_tmr), .d(1'b1), .q(clr_q));
    hc74_dff u_idp (.clk(clk), .rst_n(rst_n),
        .tick(tick_1k), .clr(!arm), .d(id_q), .q(id_d));

    // ---- the count: CNTW=4 an HC163, CNTW=3 half an HC393 ----------------
    wire cnt_en = edge_e & ~brk & hit_q & ~clr_q & arm & ~flush;
    wire [3:0] cq;
    wire       at_max, cnt_nz;
    wire       stb_raw = id_q & ~id_d & ~brk & cnt_nz & arm & ~flush;
    wire       c_mr    = stb_raw | !arm;

    generate if (CNTW == 3) begin : cnt3
        // 1..7, freeze at 0.  The wrap FF is what tells a dialled 0 (which
        // has left the count at 0) from a digit nobody dialled: cnt_nz keeps
        // the strobe, so the register still stores a digit worth 0.
        wire [3:0] q1, q2;
        wire       wrapped;
        hc393 u_cnt (
            .clk(clk), .rst_n(rst_n), .tick(tick_1k),
            .mr1(c_mr), .ce1(cnt_en & ~wrapped), .q1(q1),
            .mr2(1'b1), .ce2(1'b0), .q2(q2)
        );
        hc74_dff u_wrap (.clk(clk), .rst_n(rst_n),
            .tick(tick_1k && (c_mr || (cnt_en && (q1[2:0] == 3'd7)))),
            .clr(c_mr), .d(1'b1), .q(wrapped));
        assign cq     = {1'b0, q1[2:0]};
        assign at_max = wrapped;
        assign cnt_nz = |q1[2:0] | wrapped;
        wire   _unused_q2 = |{q2, q1[3]};
    end else begin : cnt4
        wire ctc;
        hc163 u_cnt (
            .clk(clk), .rst_n(rst_n), .tick(tick_1k),
            .mr(c_mr), .ce(cnt_en & ~at_max), .q(cq), .tc(ctc)
        );
        assign at_max = &cq;
        assign cnt_nz = |cq;
        wire   _unused_tc = ctc;
    end endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= 4'd0; dig_stb <= 1'b0; clear <= 1'b0;
            counting <= 1'b0; brk_stb <= 1'b0;
        end else begin
            dig_stb  <= 1'b0;
            clear    <= 1'b0;
            brk_stb  <= 1'b0;
            counting <= cnt_nz & arm;
            if (tick_1k && arm) begin
                if (stb_raw) begin
                    cnt     <= cq;                 // 1..15, or 1..7 then 0
                    dig_stb <= 1'b1;
                end
                if (cnt_en) brk_stb <= 1'b1;
                if (clr_q && brk) clear <= 1'b1;
            end
        end
    end

    wire _unused_max = at_max;
endmodule
