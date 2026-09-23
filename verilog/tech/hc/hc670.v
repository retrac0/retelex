// 74HC670 -- 4×4 register file (one write port, one read port).
`timescale 1ns/1ps
(* keep_hierarchy *)
module hc670 (
    input        clk,
    input        rst_n,
    input        we,          // write enable (level)
    input  [1:0] wa,          // write address
    input  [3:0] wd,          // write data
    input  [1:0] ra,          // read address
    output [3:0] rd
);
    reg [3:0] mem [0:3];
    assign rd = mem[ra];
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 4; i = i + 1) mem[i] <= 4'd0;
        end else if (we)
            mem[wa] <= wd;
    end
endmodule
