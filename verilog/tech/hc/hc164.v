// hc164 -- 74HC164 8-bit serial-in parallel-out shift register.
// Blackbox for HC package counting; not used by the RTL yet (blocks use
// behavioural shift).  Kept so pack.py / future techmap can name the part.
`timescale 1ns/1ps
(* keep_hierarchy *)
module hc164 (
    input            clk,
    input            rst_n,   // /MR, asynchronous
    input            a,       // serial data A (ANDed with B on the real part)
    input            b,
    output reg [7:0] q
);
    always @(posedge clk or negedge rst_n)
        if (!rst_n) q <= 8'd0;
        else        q <= {q[6:0], a & b};
endmodule
