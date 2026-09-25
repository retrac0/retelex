// 74HC4040 -- 12-bit binary ripple counter.  Qn = 2^(n-1): Q4=8, Q8=128, Q9=256.
// Clocked on tick at posedge clk (fabric TICK strobe).
`timescale 1ns/1ps
(* keep_hierarchy *)
module hc4040 (
    input         clk,
    input         rst_n,
    input         tick,
    input         mr,        // sync master reset
    input         ce,        // count enable
    output [11:0] q
);
    reg [11:0] c;
    assign q = c;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)      c <= 12'd0;
        else if (tick) begin
            if (mr)      c <= 12'd0;
            else if (ce) c <= c + 1'b1;
        end
    end
endmodule
