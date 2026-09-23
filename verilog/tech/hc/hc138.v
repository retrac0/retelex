// 74HC138 -- 3:8 decoder.
`timescale 1ns/1ps
(* keep_hierarchy *)
module hc138 (
    input        e1, e2, e3_n,   // enable: e1·e2·/e3
    input  [2:0] a,
    output [7:0] y_n             // active-low outputs
);
    wire en = e1 & e2 & ~e3_n;
    assign y_n = en ? ~(8'b1 << a) : 8'hFF;
endmodule
