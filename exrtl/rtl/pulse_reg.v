// pulse_reg -- the register of register.md 4.  It takes no port and has no
// class: the marker's scanner is its finder, and it reads its caller's hook off
// the M highway through its own probe -- two '151s and a flip-flop, the same
// structure a port uses to listen (exch-marker.md 4).  Its digits go back to
// the marker on a ribbon.
//
// It serves a phone and a claimed trunk alike, because by then the trunk is
// simply a line here (exch-monitor.md 2).
`timescale 1ns/1ps

module pulse_reg #(
    parameter integer HIT = 8, ID = 128, CLR = 256,
    parameter integer NODIG = 12000                 // no first digit in 12 s: give up
)(
    input            clk,
    input            rst_n,
    input      [2:0] slotq,
    input      [2:0] tick,
    input            tick_1k,
    input      [7:0] ha,            // the M highway

    input            attach,        // the marker hands it a port number
    input      [5:0] attach_port,
    input            release_it,
    output reg       busy,
    output reg [5:0] port,

    output reg [3:0] cnt,
    output reg       dig_stb,
    output reg       gone,          // CLR, or no digit at all
    output           brk            // a break just counted (exch-network.md 3's guard)
);
    // the probe: a listener's two selects and a flip-flop, at mid-cell
    reg  m_cap;
    wire w = (tick == 3'd4) && (slotq == port[2:0]);
    always @(posedge clk or negedge rst_n)
        if (!rst_n)   m_cap <= 1'b0;
        else if (w)   m_cap <= ha[port[5:3]];

    wire [3:0] p_cnt;
    wire       p_stb, p_clr, p_counting;
    pulse_rx #(.HIT(HIT), .ID(ID), .CLR(CLR)) u_rx (
        .clk(clk), .rst_n(rst_n), .tick_1k(tick_1k), .arm(busy), .m(m_cap),
        .cnt(p_cnt), .dig_stb(p_stb), .clear(p_clr), .counting(p_counting),
        .brk_stb(brk));

    reg [15:0] idle_ms;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 0; port <= 0; cnt <= 0; dig_stb <= 0; gone <= 0; idle_ms <= 0;
        end else begin
            dig_stb <= 1'b0;
            gone    <= 1'b0;
            if (attach && !busy) begin
                busy <= 1'b1; port <= attach_port; idle_ms <= 0;
            end else if (release_it) begin
                busy <= 1'b0;
            end else if (busy) begin
                if (p_stb) begin cnt <= p_cnt; dig_stb <= 1'b1; idle_ms <= 0; end
                if (p_clr) begin gone <= 1'b1; busy <= 1'b0; end
                if (tick_1k && !p_counting) begin
                    if (idle_ms == NODIG[15:0]) begin gone <= 1'b1; busy <= 1'b0; end
                    else idle_ms <= idle_ms + 1'b1;
                end
            end
        end
    end
endmodule
