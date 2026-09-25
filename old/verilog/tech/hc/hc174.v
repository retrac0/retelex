// 74HC174 -- hex DFF, common clock and common /MR.
`timescale 1ns/1ps
(* keep_hierarchy *)
module hc174 (
    input        clk,
    input        rst_n,
    input        en,          // clock enable
    input        mr,          // sync clear
    input  [5:0] d,
    output [5:0] q
);
    reg [5:0] qq;
    assign q = qq;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)     qq <= 6'd0;
        else if (mr)    qq <= 6'd0;
        else if (en)    qq <= d;
    end
endmodule
