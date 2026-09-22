// mf8_encoder -- differential Manchester, mf8-spec.md 9.2.
//
// A transition at every cell boundary, and one more at mid-cell for a 0.  In
// 74HC it is a JK wired J = K = EN, clocked by the half-bit clock HB, with
// EN = H OR NOT(bit) -- one gate and one flip-flop.  HB's two falling edges in
// a cell are tick 0 (the boundary, where H was 1 and EN is 1 whatever the bit)
// and tick 4 (mid-cell, where H is 0 and EN is NOT the bit).
`timescale 1ns/1ps

module mf8_encoder (
    input            clk,
    input            rst_n,
    input      [2:0] tick,
    input            bit_in,      // the frame bit for this cell
    output reg       line
);
    always @(posedge clk or negedge rst_n)
        if (!rst_n)                          line <= 1'b0;
        else if (tick == 3'd0)               line <= ~line;   // boundary: always
        else if (tick == 3'd4 && !bit_in)    line <= ~line;   // mid-cell: a 0
endmodule
