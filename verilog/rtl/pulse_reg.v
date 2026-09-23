// pulse_reg -- register.md §4 as 74HC MSI: probe, pulse_rx, digit store.
//
// Store is one HC670 (four digits × four bits).  Digit index is half an
// HC393.  Port / SRC sit in an HC174 each.  Count saturates at 15.
// The no-digit timer is a 16-bit count on TICK (two HC4040s of binary width
// in the BOM; the RTL uses one vector so NODIG parameters stay freestyle).
`timescale 1ns/1ps

module pulse_reg #(
    parameter integer HIT = 8, ID = 128, CLR = 256,
    parameter integer NODIG = 12000
)(
    input             clk,
    input             rst_n,
    input      [2:0]  slotq,
    input      [2:0]  tick,
    input             tick_1k,
    input      [7:0]  ha,

    input             attach,
    input      [5:0]  attach_port,
    input      [5:0]  attach_src,
    input             release_it,
    input             restart,
    output            busy,
    output     [5:0]  port,
    output     [5:0]  src,

    output     [2:0]  ndig,
    output     [15:0] digits,
    output reg        gone,
    output reg        nodig,
    output            brk,
    output            hook
);
    reg busy_r;
    wire [5:0] port_q, src_q;
    wire       seize = attach & ~busy_r;

    wire [3:0] p_cnt;
    wire       p_stb, p_clr, p_counting;
    wire       nodig_hit;
    wire       free_e = release_it | (busy_r & (p_clr | nodig_hit));

    hc174 u_port (
        .clk(clk), .rst_n(rst_n), .en(seize), .mr(free_e),
        .d(attach_port), .q(port_q)
    );
    hc174 u_src (
        .clk(clk), .rst_n(rst_n), .en(seize), .mr(free_e),
        .d(attach_src), .q(src_q)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)      busy_r <= 1'b0;
        else if (seize)  busy_r <= 1'b1;
        else if (free_e) busy_r <= 1'b0;
    end
    assign busy = busy_r;
    assign port = port_q;
    assign src  = src_q;

    wire ha_bit;
    wire w = (tick == 3'd4) && (slotq == port_q[2:0]);
    mux8 u_probe (.d(ha), .s(port_q[5:3]), .y(ha_bit));
    reg  m_cap;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) m_cap <= 1'b0;
        else if (w) m_cap <= ha_bit;
    assign hook = m_cap;

    pulse_rx #(.HIT(HIT), .ID(ID), .CLR(CLR)) u_rx (
        .clk(clk), .rst_n(rst_n), .tick_1k(tick_1k), .arm(busy_r), .m(m_cap),
        .cnt(p_cnt), .dig_stb(p_stb), .clear(p_clr), .counting(p_counting),
        .brk_stb(brk));

    wire [3:0] n_q1, n_q2;
    wire n_clr = seize | free_e | (restart & ~p_stb);
    wire n_ce  = busy_r & p_stb & ~free_e;
    hc393 u_n (
        .clk(clk), .rst_n(rst_n), .tick(1'b1),
        .mr1(n_clr), .ce1(n_ce & ~n_clr), .q1(n_q1),
        .mr2(1'b1), .ce2(1'b0), .q2(n_q2)
    );
    assign ndig = (n_q1 > 4'd4) ? 3'd4 : n_q1[2:0];

    wire       wr = busy_r & p_stb & ~free_e;
    wire [1:0] wa_w = (restart && p_stb) ? 2'd0 : n_q1[1:0];
    wire [3:0] dig_rd;
    hc670 u_store (
        .clk(clk), .rst_n(rst_n),
        .we(wr), .wa(wa_w), .wd(p_cnt),
        .ra(wa_w), .rd(dig_rd)
    );

    reg [15:0] dig_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) dig_r <= 16'd0;
        else if (seize | free_e | (restart & ~p_stb)) dig_r <= 16'd0;
        else if (restart & p_stb) dig_r <= {12'd0, p_cnt};
        else if (wr && (n_q1 < 4)) dig_r[n_q1*4 +: 4] <= p_cnt;
    end
    assign digits = dig_r;

    // Idle timer: two HC4040s cascaded as a 24-bit binary count via CE carry
    // is awkward; a 16-bit vector is the same length as two '4040s for BOM
    // when pulse_reg is packed as a unit.  Match behavioral equality check.
    reg [15:0] idle_ms;
    assign nodig_hit = busy_r && tick_1k && !p_counting && (idle_ms == NODIG[15:0]);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) idle_ms <= 16'd0;
        else if (seize | free_e | p_stb | restart) idle_ms <= 16'd0;
        else if (busy_r && tick_1k && !p_counting && !nodig_hit)
            idle_ms <= idle_ms + 1'b1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gone <= 1'b0; nodig <= 1'b0;
        end else begin
            gone  <= 1'b0;
            nodig <= 1'b0;
            if (busy_r && p_clr) begin
                gone <= 1'b1;
            end else if (nodig_hit) begin
                gone  <= 1'b1;
                nodig <= 1'b1;
            end
        end
    end

    wire _unused = |{n_q2, dig_rd};
endmodule
