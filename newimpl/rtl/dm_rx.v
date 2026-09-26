// dm_rx -- the differential-Manchester receiver of mf8-spec.md 9.4: no PLL,
// and no lock to lose.  '86, '221, '123, '74 -- four packages, and the same
// four at both ends of every line in the family.
//
//   on each transition from the line comparator:
//       if less than DEAD since the last ACCEPTED transition:  ignore it
//       otherwise accept it:
//           if more than 0.75 cell since the previous accepted: a 1, clear MID
//           else if MID is set:                                 a 0, clear MID
//           else:                                               set MID
//
// A 1 has no mid-cell transition, so its gap is a full cell; a 0 gives two
// half-cell gaps and the MID flip-flop pairs them.  Any full-cell gap clears
// MID, so the state self-heals within a couple of bits.
//
// THE HARDWARE HAS NO CLOCK ON THIS PATH.  It times the intervals with a
// non-retriggerable and a retriggerable one-shot ('221, '123) and its
// tolerance is +-13 % of a cell.  Here the intervals are counted in the
// receiving end's own master clock, which is a different crystal from the
// sender's: at 64 kbps a cell is 64 ticks, so the resolution is a sixty-
// fourth of a cell and a 100 ppm offset is four orders of magnitude below
// it.  Same function, different timebase.
//
// Two more things come out than a trunk needs, because subscriber-line.md §3
// builds the hook detector on them: LONG and MID at the accepted edge, and
// the violation -- a half-cell with no partner, or a boundary that never
// came.  Valid differential Manchester never does either; a dead pair with
// noise on it does both constantly.
//
//   mf8-spec.md 9.4, 9.6, 9.7; subscriber-line.md §3
`timescale 1ns/1ps

module dm_rx #(
    // master ticks a cell.  The rate plug of mf8-spec.md 9.7: the trunk's
    // 512 kbps is 8, the subscriber line's 64 kbps is 64.  Everything else
    // is a fraction of it.
    parameter integer CELL     = 64,
    parameter integer DEAD     = CELL / 5,        // 0.2 cell, non-retriggerable
    parameter integer THRESH   = (3 * CELL) / 4,  // 0.75 cell, the classifier
    parameter integer VIOL_GAP = (5 * CELL) / 4,  // 1.25 cells: a boundary missed
    parameter integer CD_GAP   = 2 * CELL,        // 2 cells: no carrier
    parameter integer HOLD     = 16 * CELL        // a violation is held 16 cells
)(
    input            clk,
    input            rst_n,
    input            line,        // the comparator's output, as received

    output reg       q,           // the data latch
    output reg       q_stb,       // one tick: q is a new bit
    output           carrier,     // a transition within the last two cells
    output           viol         // a violation is being held
);
    // two stages of synchroniser, then the edge
    reg        s0, s1, s2;
    wire       trans = s1 ^ s2;

    reg [15:0] gap;               // ticks since the last accepted transition
    reg        mid;
    reg [15:0] hold;

    wire       accept = trans && (gap >= DEAD[15:0]);
    wire       long_g = (gap >= THRESH[15:0]);

    // the two violation terms: a full-cell gap arriving with MID still set is
    // a half-cell that never got its partner; a gap past 1.25 cells is a
    // boundary transition that never came.
    wire       viol_now = (accept && long_g && mid) || (gap > VIOL_GAP[15:0]);

    assign carrier = (gap < CD_GAP[15:0]);
    assign viol    = (hold != 16'd0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s0 <= 1'b0; s1 <= 1'b0; s2 <= 1'b0;
            gap <= 16'd0; mid <= 1'b0; hold <= 16'd0;
            q <= 1'b1; q_stb <= 1'b0;             // the latch idles at 1
        end else begin
            s0 <= line; s1 <= s0; s2 <= s1;
            q_stb <= 1'b0;

            if (gap != 16'hFFFF) gap <= gap + 1'b1;

            if (accept) begin
                gap <= 16'd0;
                if (long_g)   begin q <= 1'b1; q_stb <= 1'b1; mid <= 1'b0; end
                else if (mid) begin q <= 1'b0; q_stb <= 1'b1; mid <= 1'b0; end
                else                                            mid <= 1'b1;
            end

            // the '123: retriggered by every violation, HOLD long
            if (viol_now)         hold <= HOLD[15:0];
            else if (hold != 0)   hold <= hold - 1'b1;
        end
    end
endmodule
