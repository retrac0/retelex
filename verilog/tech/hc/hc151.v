// hc151 -- 74HC151 8:1 multiplexer.  Alias of rtl/mux8 for the HC BOM:
// every mux8 instance counts as one HC151 package.
`timescale 1ns/1ps
module hc151 (input [7:0] d, input [2:0] s, output y);
    assign y = d[s];
endmodule
