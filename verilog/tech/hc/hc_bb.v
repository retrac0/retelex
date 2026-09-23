// Blackbox port shells for synth-hc (bodies live in the sim models).
// Yosys `read_verilog -lib` marks these as blackboxes.
`timescale 1ns/1ps
module hc393 (input clk, rst_n, tick, mr1, mr2, ce1, ce2, output [3:0] q1, q2); endmodule
module hc4040 (input clk, rst_n, tick, mr, ce, output [11:0] q); endmodule
module hc163 (input clk, rst_n, tick, mr, ce, output [3:0] q, output tc); endmodule
module hc175 (input clk, rst_n, tick, mr, input [3:0] d, output [3:0] q); endmodule
module hc670 (input clk, rst_n, we, input [1:0] wa, input [3:0] wd, input [1:0] ra, output [3:0] rd); endmodule
module hc174 (input clk, rst_n, en, mr, input [5:0] d, output [5:0] q); endmodule
module hc74_dff (input clk, rst_n, tick, clr, d, output q); endmodule
module hc86_xor2 (input a, b, output y); endmodule
module hc157 (input [3:0] a, b, input s, g_n, output [3:0] y); endmodule
module hc138 (input e1, e2, e3_n, input [2:0] a, output [7:0] y_n); endmodule
module mux8 (input [7:0] d, input [2:0] s, output y); endmodule
module ctl_write (input clk, rst_n, req, strobe, g, input [5:0] dst, src, input bsy, clm,
                  output busy, sdata, sclk, wr); endmodule
module mini_core #(
    parameter [5:0] DIALTONE = 6'o01, NOGO = 6'o03,
    parameter HAS_NET = 0, LEAF = 0,
    parameter [63:0] TRUNK_MASK = 0, UPLINK_MASK = 0
)(
    input clk, rst_n,
    input [2:0] slotq, tick,
    input frame_stb, oct_stb, tick_1k,
    input [7:0] ha, input pb_busy,
    input r_busy, r_gone, r_nodig, r_hook,
    input [2:0] r_ndig, input [19:0] r_digits,
    output r_attach, r_release, r_restart_loc, output [5:0] r_aport,
    input ser_busy, output ser_req, ser_strobe,
    output [5:0] ser_dst, ser_src, output ser_bsy, ser_clm, ser_g,
    output [5:0] probe_port, output [2:0] scan_port,
    output probe_visit, probe_valid, probe_m, probe_busy,
    output flood_go, output [5:0] flood_caller,
    input net_restart, net_done, net_nogo, net_local, net_att,
    input [5:0] net_att_port, input [3:0] net_nw,
    input [47:0] net_wdst, net_wsrc,
    input [7:0] net_wbsy, net_wclm, net_wev,
    output wq_ovf, wr_stb, output [5:0] wr_dst, wr_src, output wr_bsy, wr_clm
); endmodule
module pulse_reg #(
    parameter integer HIT = 8, ID = 128, CLR = 256, NODIG = 12000
)(
    input clk, rst_n, input [2:0] slotq, tick, input tick_1k, input [7:0] ha,
    input attach, input [5:0] attach_port, attach_src,
    input release_it, restart,
    output busy, output [5:0] port, src,
    output [2:0] ndig, output [19:0] digits,
    output gone, nodig, brk, hook
); endmodule
