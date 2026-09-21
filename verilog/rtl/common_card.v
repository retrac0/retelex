// common_card -- the seventeenth card: the only one in the stack that is not a
// lamp card.  hookbusy.md 3.
//
// It is observers.md 3's shared parts, moved one board back and used sixteen
// ways instead of eight times over:
//
//   2 x 74HC164    the sixteen-bit word off cable B, exactly as at a block
//   1 x 74HC138    DST[5:3], /E1 = HCLK, /E2 = INH.  Its eight active-low
//                  outputs ARE the LEB lines, so no lamp card carries a gate
//   1/2 x 74HC123  INH: high while SCLK is moving and for a cell after it
//
// BOTH '164 ARE NEEDED although only three bits are read.  DST[5:3] is bits
// 13-11 of the word (mainboard.md 2.3.1), so the second register exists
// to push them to the end.
//
// THE SHIFT REGISTER HAS NO PHASE, ONLY CONTENT.  Its sixteen bits are right
// whenever the marker has driven sixteen good bits in a row, so this card
// counts nothing and needs no frame reference -- the same argument the blocks
// and the counter card use, applied here to the ROW.  The block that drives
// PB0 is the block DST[5:3] names, and this decodes the same three bits out of
// the same broadcast, so whatever is on PB0 in cell s belongs to port
// (DST[5:3], s) BY CONSTRUCTION.  The field cannot be wrong about whose bit it
// has (observers.md 3).
//
// WHY THE INHIBIT.  Mid-word the '164 holds rippling garbage and the row it
// names walks about.  The DATA stays honest, because the block's own /BLK
// decoder is rippling with it and the block driving PB is the one being
// written to; what is not honest is the HAND-OVER, where one block's '244 is
// turning off and the next is turning on and PB is briefly undriven.  PB is
// pulled LOW at the marker (mainboard.md 6), so an undriven instant reads
// NOT BUSY -- and a '259 is transparent while addressed, so a lamp could be
// wrongly cleared and hold that until its block's next visit, up to a scan
// later.  INH costs half a package and removes the question.  A word is 31 us
// at 512 kHz and the field is blind for it; the lamp it would have written is
// written on the next frame, 15.6 us later.
//
// INH_EN = 0 is the CONTROL, not an option: the same stack with the one-shot
// left out, so a bench can measure the fault the inhibit exists to prevent.
`timescale 1ns/1ps

module common_card #(
    parameter integer INH_TICKS = 12,   // a cell and a half of the master clock
    parameter         INH_EN    = 1'b1  // 0: the control.  See hookbusy.md 7
)(
    input             clk,
    input             rst_n,

    // the tap on cable B
    input             sdata,
    input             sclk,
    // and on cable A
    input             hclk,

    output     [7:0]  leb_n,            // up the 26-way to every busy card
    output     [2:0]  dst_blk           // the word's DST[5:3], as a block's shunt sees it
);
    // ---- the two '164 -------------------------------------------------
    // G, bit 15, IS NOT READ -- there is no guard gate here because nothing
    // here writes a latch.  So an EVENT word (counters.md 9, G = 0) steers
    // this field's row exactly as a write does, just as it steers /BLK at
    // every block.  The row simply moves to the port the event is about; the
    // data stays honest, because the block driving PB0 moved with it.
    /* verilator lint_off UNUSEDSIGNAL */
    reg [15:0] cw;
    /* verilator lint_on UNUSEDSIGNAL */
    reg        sclk_d;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin cw <= 16'd0; sclk_d <= 1'b0; end
        else begin
            sclk_d <= sclk;
            if (sclk && !sclk_d) cw <= {cw[14:0], sdata};
        end

    assign dst_blk = cw[13:11];

    // ---- half a '123: retriggerable, about a cell ----------------------
    // Any SCLK edge reloads it, so INH stands through a whole word however
    // the marker clocks it -- 64 kHz to 512 kHz, gated or free-running.
    reg [7:0] osh;
    always @(posedge clk or negedge rst_n)
        if (!rst_n)                        osh <= 8'd0;
        else if (sclk != sclk_d)           osh <= INH_TICKS[7:0];
        else if (osh != 8'd0)              osh <= osh - 1'b1;

    wire inh = INH_EN && (osh != 8'd0);

    // ---- the '138: /E1 = HCLK, /E2 = INH -------------------------------
    // Enabled only in the second half of a cell, and only when the word is
    // still.  Its eight outputs are the busy cards' /LE, already gated.
    genvar h;
    generate for (h = 0; h < 8; h = h + 1) begin : row
        assign leb_n[h] = ~((cw[13:11] == h[2:0]) && !hclk && !inh);
    end endgenerate
endmodule
