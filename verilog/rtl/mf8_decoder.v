// mf8_decoder -- the receiver of mf8-spec.md 9.4: no PLL, and no lock to lose.
//
//   on each transition from the comparator:
//       if less than DEAD since the last ACCEPTED transition:  ignore it
//       otherwise accept it:
//           if more than 0.75 cell since the previous accepted: emit 1, clear MID
//           else if MID is set:                                 emit 0, clear MID
//           else:                                               set MID
//
// A 1 has no mid-cell transition, so its gap is a full cell; a 0 gives two
// half-cell gaps and the MID flip-flop pairs them.  Any full-cell gap clears
// MID, so the state self-heals within a couple of bits.
//
// **The hardware has no clock at all on this path** -- it times the two
// intervals with a non-retriggerable and a retriggerable one-shot, and its
// tolerance is +-13% of a cell.  Here the intervals are counted in the
// RECEIVING exchange's own master clock, which is a different crystal from the
// sender's.  A line bit is four ticks of 4.096 MHz (1024 kbps), so the
// resolution is a quarter of a cell and a 100 ppm offset is still four orders
// of magnitude below it.  Same function, different timebase.
`timescale 1ns/1ps

module mf8_decoder #(
    parameter integer DEAD   = 1,    // 0.25 cell, non-retriggerable
    parameter integer THRESH = 3,    // 0.75 cell, the classifier
    parameter integer CD_GAP = 12    // no transition for three cells: no carrier
)(
    input            clk,
    input            rst_n,
    input            line,
    output reg       bit_stb,
    output reg       bit_val,
    output reg       cd
);
    reg       s0, s1, s2;            // two stages of synchroniser, then the edge
    reg [7:0] gap;
    reg       mid;
    wire      trans = s1 ^ s2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s0 <= 0; s1 <= 0; s2 <= 0; gap <= 0; mid <= 0;
            bit_stb <= 0; bit_val <= 0; cd <= 0;
        end else begin
            s0 <= line; s1 <= s0; s2 <= s1;
            bit_stb <= 1'b0;
            if (gap != 8'hFF) gap <= gap + 1'b1;
            cd <= (gap < CD_GAP[7:0]);
            if (trans && gap >= DEAD[7:0]) begin
                gap <= 8'd0;
                if (gap >= THRESH[7:0]) begin bit_val <= 1'b1; bit_stb <= 1'b1; mid <= 1'b0; end
                else if (mid)           begin bit_val <= 1'b0; bit_stb <= 1'b1; mid <= 1'b0; end
                else                          mid     <= 1'b1;
            end
        end
    end
endmodule
