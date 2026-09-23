// nano_reg -- nano-marker.md §3: the three-bit pulse register.
//
// One board's register.  It is register.md §4's listener with everything the
// nano-marker cannot use taken off:
//
//   * the count is three bits (pulse_rx CNTW=3): half an HC393 and one FF,
//     1..7 then frozen at 0, so a dialled 8, 9 or 0 all read 0.  That is what
//     oct() made of them anyway, and the '163 comes off the board.
//   * the store is six bits in one HC174, wired as a three-bit-wide two-stage
//     shift.  **The store is the called number**: after two digits it holds
//     {h, s} in port order, so the core has no `called` register and there is
//     no parallel mirror of a '670 (the '670 has one addressed read port,
//     which is the only reason pulse_reg carries dig_r).
//   * no SRC latch -- the nano never attaches on a network unit's behalf.
//   * no restart -- no unit, so nothing consumes a prefix.
//
// Digit positions as they fill, which is what lets the store be the number:
//
//       after one digit   q = { 0 0 0 , d0 }      first-key test is q[2:0]
//       after two         q = {  d0   , d1 }      called port is q[5:0]
`timescale 1ns/1ps

module nano_reg #(
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
    input             release_it,
    output            busy,
    output     [5:0]  port,

    output     [1:0]  ndig,
    output     [5:0]  digits,
    output reg        gone,
    output reg        nodig,
    output            brk,
    output            hook
);
    reg busy_r;
    wire [5:0] port_q;
    wire       seize = attach & ~busy_r;

    wire [3:0] p_cnt;
    wire       p_stb, p_clr, p_counting;
    wire       nodig_hit;
    wire       free_e = release_it | (busy_r & (p_clr | nodig_hit));

    // The latch is never cleared, only reloaded on the next seizure.  The core
    // still has to write the caller's own latch after the register has let go
    // -- cannot-complete on the no-digit timer, a pair write after release --
    // and reading the address back off this '174 is what saves it keeping a
    // second copy of the caller.
    hc174 u_port (
        .clk(clk), .rst_n(rst_n), .en(seize), .mr(1'b0),
        .d(attach_port), .q(port_q)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)      busy_r <= 1'b0;
        else if (seize)  busy_r <= 1'b1;
        else if (free_e) busy_r <= 1'b0;
    end
    assign busy = busy_r;
    assign port = port_q;

    // ---- probe of the held line's M (HC151 on HA) ------------------------
    wire ha_bit;
    wire w = (tick == 3'd4) && (slotq == port_q[2:0]);
    mux8 u_probe (.d(ha), .s(port_q[5:3]), .y(ha_bit));
    reg  m_cap;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) m_cap <= 1'b0;
        else if (w) m_cap <= ha_bit;
    assign hook = m_cap;

    pulse_rx #(.HIT(HIT), .ID(ID), .CLR(CLR), .CNTW(3)) u_rx (
        .clk(clk), .rst_n(rst_n), .tick_1k(tick_1k), .arm(busy_r), .m(m_cap),
        .cnt(p_cnt), .dig_stb(p_stb), .clear(p_clr), .counting(p_counting),
        .brk_stb(brk));

    // ---- digit index: two FFs, 0 1 2 ------------------------------------
    // Two is all the nano can dial, so the index saturates there rather than
    // counting on.  Saturating also holds the store still: a third digit
    // arriving while the core is still walking the scanner round to the
    // called port would otherwise shift h out of it.
    reg [1:0] nd_r;
    wire      full  = (nd_r == 2'd2);
    wire      wr_dig = busy_r & p_stb & ~free_e & ~full;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)              nd_r <= 2'd0;
        else if (seize | free_e) nd_r <= 2'd0;
        else if (wr_dig)         nd_r <= nd_r + 1'b1;
    end
    assign ndig = nd_r;

    // ---- the store: one HC174, three bits wide, two deep -----------------
    wire [5:0] dig_q;
    hc174 u_dig (
        .clk(clk), .rst_n(rst_n),
        .en(wr_dig), .mr(seize | free_e),
        .d({dig_q[2:0], p_cnt[2:0]}), .q(dig_q)
    );
    assign digits = dig_q;

    // ---- no-digit timer --------------------------------------------------
    reg [15:0] idle_ms;
    assign nodig_hit = busy_r && tick_1k && !p_counting && (idle_ms == NODIG[15:0]);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) idle_ms <= 16'd0;
        else if (seize | free_e | p_stb) idle_ms <= 16'd0;
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

    wire _unused_cnt = |p_cnt[3];
endmodule
