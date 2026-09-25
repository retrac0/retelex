// 74HC148 -- 8-line to 3-line priority encoder, active low in and out.
// Input 7 has the highest priority.  Two cascade into a 16-key encoder with
// EO of the high part driving EI of the low part (pulse-gen.md §5, su-1.md §4).
`timescale 1ns/1ps
(* keep_hierarchy *)
module hc148 (
    input        ei_n,        // enable input
    input  [7:0] i_n,         // data inputs, active low
    output [2:0] a_n,         // encoded output, active low
    output       gs_n,        // group select: low when enabled and some input low
    output       eo_n         // enable output: low when enabled and no input low
);
    wire       en  = ~ei_n;
    wire       any = |(~i_n);
    reg  [2:0] a;
    integer    k;
    always @* begin
        a = 3'd0;
        for (k = 0; k < 8; k = k + 1)
            if (!i_n[k]) a = k[2:0];      // last match wins: highest priority
    end
    assign a_n  = (en && any) ? ~a : 3'b111;
    assign gs_n = ~(en &&  any);
    assign eo_n = ~(en && !any);
endmodule
