// 74HC74 -- dual DFF with async /CLR.  One FF as a named MSI leaf for packs.
`timescale 1ns/1ps
(* keep_hierarchy *)
module hc74_dff (
    input  clk,
    input  rst_n,      // async /CLR
    input  tick,       // clock enable
    input  clr,        // sync clear (OR into clear)
    input  d,
    output q
);
    reg qq;
    assign q = qq;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)      qq <= 1'b0;
        else if (tick) begin
            if (clr)     qq <= 1'b0;
            else         qq <= d;
        end
    end
endmodule
