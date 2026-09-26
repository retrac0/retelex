// Stub part models for pcb/tools/selftest, used only when pcb/models is absent
// (or with run.py --stub).  Same module and port names as pcb/models/74hc.v,
// same conventions: pins are ports named after the datasheet, a tri-state
// output is <port> + <port>_oe, an open drain's port is 1 while pulling low,
// no z anywhere, delays procedural (Verilator ignores 'assign #d').
`timescale 1ns/1ps

module stub_dly #(parameter integer W = 1, parameter integer D = 1) (input wire [W-1:0] a, output reg [W-1:0] y);
    initial y = {W{1'b0}};
    always @(a) y <= #D a;
endmodule

module hc151 #(parameter integer TPD = 1) (
    input wire I3, input wire I2, input wire I1, input wire I0,
    output wire Y, output wire Y_n, input wire E_n,
    input wire S2, input wire S1, input wire S0,
    input wire I7, input wire I6, input wire I5, input wire I4
);
    wire [7:0] i = {I7, I6, I5, I4, I3, I2, I1, I0};
    wire y = !E_n && i[{S2, S1, S0}];
    stub_dly #(2, TPD) u (.a({!y, y}), .y({Y_n, Y}));
endmodule

module hc14 #(parameter integer TPD = 1) (
    input wire A1, output wire Y1, input wire A2, output wire Y2, input wire A3, output wire Y3,
    output wire Y4, input wire A4, output wire Y5, input wire A5, output wire Y6, input wire A6
);
    stub_dly #(6, TPD) u (.a(~{A6, A5, A4, A3, A2, A1}), .y({Y6, Y5, Y4, Y3, Y2, Y1}));
endmodule

module hc125 #(parameter integer TPD = 1) (
    input wire OE1_n, input wire A1, output wire Y1, output wire Y1_oe,
    input wire OE2_n, input wire A2, output wire Y2, output wire Y2_oe,
    output wire Y3, output wire Y3_oe, input wire A3, input wire OE3_n,
    output wire Y4, output wire Y4_oe, input wire A4, input wire OE4_n
);
    stub_dly #(8, TPD) u (.a({A4, A3, A2, A1, ~{OE4_n, OE3_n, OE2_n, OE1_n}}),
                          .y({Y4, Y3, Y2, Y1, Y4_oe, Y3_oe, Y2_oe, Y1_oe}));
endmodule

module fet_2n7002 (input wire G, output wire pd);
    assign pd = G;
endmodule

// port.v's detector counter on the simulation-only tick_1k (pcb/models' rc_det)
module rc_det #(parameter [8:0] T_ARM = 9'd16, parameter [8:0] T_REL = 9'd256) (
    input wire clk, input wire rst_n, input wire tick_1k,
    input wire IN, output wire OUT, output wire OUT_n
);
    reg f; reg [8:0] n;
    wire [8:0] thr = IN ? T_ARM : T_REL;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin f <= 1'b0; n <= 9'd0; end
        else if (tick_1k) begin
            if (IN == f) n <= 9'd0;
            else if (n >= thr - 9'd1) begin n <= 9'd0; f <= IN; end
            else n <= n + 1'b1;
        end
    stub_dly #(2, 1) u (.a({~f, f}), .y({OUT_n, OUT}));
endmodule
