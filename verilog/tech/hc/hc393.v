// 74HC393 -- dual binary counter (4+4).  Clocked on tick (CE) at posedge clk;
// the fabric's TICK is a one-cycle strobe, so this is the board-level use.
`timescale 1ns/1ps
(* keep_hierarchy *)
module hc393 (
    input        clk,
    input        rst_n,     // async master clear (both halves), active low
    input        tick,      // count enable (board TICK)
    input        mr1,       // sync master reset half-1
    input        mr2,       // sync master reset half-2
    input        ce1,       // count enable half-1 (with tick)
    input        ce2,       // count enable half-2
    output [3:0] q1,
    output [3:0] q2
);
    reg [3:0] c1, c2;
    assign q1 = c1;
    assign q2 = c2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            c1 <= 4'd0; c2 <= 4'd0;
        end else if (tick) begin
            if (mr1)      c1 <= 4'd0;
            else if (ce1) c1 <= c1 + 1'b1;
            if (mr2)      c2 <= 4'd0;
            else if (ce2) c2 <= c2 + 1'b1;
        end
    end
endmodule
