// hc_cells.v -- bare 74HC SSI cell models (for techmap targets / JSON BOM).
`timescale 1ns/1ps

module HC00_NAND2 (input A, B, output Y); assign Y = ~(A & B); endmodule
module HC02_NOR2  (input A, B, output Y); assign Y = ~(A | B); endmodule
module HC04_INV   (input A,    output Y); assign Y = ~A;       endmodule
module HC08_AND2  (input A, B, output Y); assign Y =  A & B;   endmodule
module HC32_OR2   (input A, B, output Y); assign Y =  A | B;   endmodule
