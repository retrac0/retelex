// 74HC157 -- quad 2:1 multiplexer (one bit shown as a leaf for the BOM).
`timescale 1ns/1ps
(* keep_hierarchy *)
module hc157 (
    input  [3:0] a, b,
    input        s,       // 0=a, 1=b
    input        g_n,     // /G output enable (active low); 1 → 0
    output [3:0] y
);
    assign y = g_n ? 4'd0 : (s ? b : a);
endmodule
