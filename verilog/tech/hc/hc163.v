// 74HC163 -- sync 4-bit binary counter, clock enable, sync reset.
`timescale 1ns/1ps
(* keep_hierarchy *)
module hc163 (
    input        clk,
    input        rst_n,
    input        tick,
    input        mr,         // sync reset to 0
    input        ce,         // count enable (CET·CEP)
    output [3:0] q,
    output       tc          // terminal count (15 and ce)
);
    reg [3:0] c;
    assign q  = c;
    assign tc = (c == 4'd15) && ce;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)      c <= 4'd0;
        else if (tick) begin
            if (mr)      c <= 4'd0;
            else if (ce) c <= c + 1'b1;
        end
    end
endmodule
