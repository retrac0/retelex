// stats -- the counter card.  counters.md.
//
// A card that only listens.  The control bus is a BROADCAST (mainboard.md
// 2.3): the marker's whole output is one sixteen-bit word shifted out on SDATA
// and strobed by WR, and every tap on the ribbon sees it.  So a counter needs
// no connection to the marker, no shunt column, no /BLK, no probe and no clock
// -- three of the cable's thirty-eight signals and nothing else:
//
//     15    G        guard              7-2   SRC   the source port, as dialled
//     14    -        spare              1     BSY
//     13-8  DST      the block, the port in it   0  CLM
//
// ONE '164, NOT TWO.  A pattern counter tests SRC, BSY and CLM, and those are
// bits 7-0 -- the whole of the SECOND shift register in a block's pair, and
// exactly eight bits, which is one '688.  Bits 15-8 fall out of the end
// unread, so this card cannot ask DST and cannot check G: it counts words the
// blocks themselves may have rejected on a bad guard.  For a counter that is
// tolerable.  For a route it would not be.
//
// THE STRAP FIELD IS THE '688's Q SIDE.  A '688 compares eight bits and has no
// mask input, but a don't-care costs nothing: strap Qi to Pi and that bit
// always matches.  Three ways a bit -- ground, Vcc, or Pi -- and one package
// is any pattern over SRC+BSY+CLM.  Here that is (PAT, ANY): ANY[i] set is
// the strap left on Pi.
//
// CLOCKED BY WR.  The '688's answer is stable through the whole pulse, because
// mainboard.md 2.3.2's one rule already keeps WR clear of every SCLK edge
// -- the same rule that makes a block's write decoder work.  So WR is the
// counter chain's clock and the match is its ENP/ENT, and the card needs no
// synchroniser and no clock off the cable.
//
// '161 AND NOT '163.  The monitor's '163 has a SYNCHRONOUS clear, which needs
// a clock edge to take effect -- and the reset key gets pressed when the bus
// is quiet.  '161's clear is asynchronous and works with no traffic at all.
`timescale 1ns/1ps

module stats #(
    // The strap field: the pattern, and which straps are left on Pi.
    parameter [5:0] SRC     = 6'o03,        // NOGO: cannot-complete given
    parameter       BSY     = 1'b1,
    parameter       CLM     = 1'b0,
    parameter [5:0] SRC_ANY = 6'o00,        // 1 = that bit is don't-care
    parameter       BSY_ANY = 1'b0,
    parameter       CLM_ANY = 1'b1
)(
    input             clk,
    input             rst_n,

    // cable B, and nothing else
    input             sdata,
    input             sclk,
    input             wr,

    input             clr,                  // the reset key, into both '161 /CLR
    output     [15:0] count,                // the sixteen LEDs, 4 x '161
    output            match                 // the '688's answer, for a testbench
);
    // One '164: SRC[5:0], BSY, CLM.  As in a block, the register has no phase,
    // only content -- nothing reads it until WR.
    reg  [7:0] sr;
    reg        sclk_d, wr_d;
    reg [15:0] cnt;

    wire [7:0] pat = {SRC,     BSY,     CLM};
    wire [7:0] any = {SRC_ANY, BSY_ANY, CLM_ANY};

    // the '688, with the don't-care straps: equal, or strapped to itself
    assign match = &((sr ~^ pat) | any);
    assign count = cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sr <= 8'd0; sclk_d <= 1'b0; wr_d <= 1'b0; cnt <= 16'd0;
        end else begin
            sclk_d <= sclk;
            if (sclk && !sclk_d) sr <= {sr[6:0], sdata};

            // the '161 chain: WR on the clock, the match on ENP/ENT
            wr_d <= wr;
            if (clr)                            cnt <= 16'd0;
            else if (wr && !wr_d && match)      cnt <= cnt + 1'b1;
        end
    end
endmodule
