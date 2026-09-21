// mux8 -- a 74HC151.  The whole fabric is this one part used three ways:
// to put eight ports on a wire in turn, to choose a wire, and to choose a
// moment (fabric.md 1.1).
`timescale 1ns/1ps
module mux8 (input [7:0] d, input [2:0] s, output y);
    assign y = d[s];
endmodule
