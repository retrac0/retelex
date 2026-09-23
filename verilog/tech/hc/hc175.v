// 74HC175 -- quad DFF, common clock and common /MR.
`timescale 1ns/1ps
(* keep_hierarchy *)
module hc175 (
    input        clk,
    input        rst_n,      // async /MR
    input        tick,       // clock enable
    input        mr,         // sync clear (optional board OR into /MR)
    input  [3:0] d,
    output [3:0] q
);
    reg [3:0] qq;
    assign q = qq;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)      qq <= 4'd0;
        else if (tick) begin
            if (mr)      qq <= 4'd0;
            else         qq <= d;
        end
    end
endmodule
