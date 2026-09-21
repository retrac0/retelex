// pulse_rx -- register.md 2's three windows, off one timer on the 1 kHz tick.
//
//   is this break a pulse?        break >= 8 ms     HIT
//   does this make end the digit? make  >= 128 ms   ID
//   is this the caller hanging up? break >= 256 ms  CLR
//
// In 74HC they are Q4, Q8 and Q9 of one '4040 reset by the edge, and the pulse
// count is five bits, saturating at 16, so keypad D counts (pulse-gen.md 4).
// Ten pulses is a dialled 0, and 8 and 9 are service digits the marker
// catches before they are ever an address (protocol.md 5).
//
// Both the register and the trunk monitor count with this, which is the point:
// a monitor reads a digit it was not sent, with the register's own windows.
`timescale 1ns/1ps

module pulse_rx #(
    parameter integer HIT = 8,
    parameter integer ID  = 128,
    parameter integer CLR = 256
)(
    input            clk,
    input            rst_n,
    input            tick_1k,
    input            arm,           // held low, the timer is reset: nothing before
                                    // the register was attached, or before the
                                    // monitor saw the seizure rise, may be counted
    input            m,             // the hook: 1 is off-hook, a make
    output reg [4:0] cnt,           // the digit just ended, in pulses (1-16)
    output reg       dig_stb,
    output reg       clear,         // 256 ms of break: hung up, or a cut pair
    output reg       counting,      // a digit is part-counted
    output reg       brk_stb        // a break just counted: the origin's 128 ms guard
);
    reg [9:0] brk_ms, mk_ms;
    reg [4:0] n;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            brk_ms <= 0; mk_ms <= 0; n <= 0;
            cnt <= 0; dig_stb <= 0; clear <= 0; counting <= 0; brk_stb <= 0;
        end else begin
            dig_stb <= 1'b0;
            clear   <= 1'b0;
            brk_stb <= 1'b0;
            if (!arm) begin
                brk_ms <= 0; mk_ms <= 0; n <= 0; counting <= 1'b0;
            end else if (tick_1k) begin
                if (!m) begin                                  // a break
                    mk_ms <= 0;
                    if (brk_ms != 10'h3FF) brk_ms <= brk_ms + 1'b1;
                    if (brk_ms == CLR[9:0] - 1) begin          // CLR: the caller is gone
                        clear <= 1'b1; n <= 0; counting <= 1'b0;
                    end
                end else begin                                 // a make
                    if (brk_ms >= HIT[9:0]) begin              // the break just ended, and counted
                        if (n != 5'd16) n <= n + 1'b1;         // saturate: D is 16 (pulse-gen.md 4)
                        counting <= 1'b1; brk_stb <= 1'b1;
                    end
                    brk_ms <= 0;
                    if (mk_ms != 10'h3FF) mk_ms <= mk_ms + 1'b1;
                    if (mk_ms == ID[9:0] - 1 && n != 0) begin  // ID: the digit is in
                        cnt <= n; dig_stb <= 1'b1; n <= 0; counting <= 1'b0;
                    end
                end
            end
        end
    end
endmodule
