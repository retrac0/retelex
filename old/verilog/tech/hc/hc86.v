// 74HC86 -- quad XOR2.  One gate used as a module for the BOM.
`timescale 1ns/1ps
(* keep_hierarchy *)
module hc86_xor2 (
    input  a, b,
    output y
);
    assign y = a ^ b;
endmodule
