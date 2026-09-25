// mainboard -- the passive board at each ribbon tap: the cables' headers and
// the block's connector.  No logic, no jumper, and no part that does anything
// but connect.  mainboard.md 1.
//
// A ribbon is a bus of identical conductors and every connector crimped along
// it sees the same signals -- and NOW EVERY CONDUCTOR ON IT IS THAT.  The two
// that were not, which highway a block drives and which /BLK line it answers
// to, were a shunt field here: two jumper columns a position.  Both moved to
// the block's own header, where one jumper routes HC_OUT and a '148 reads the
// same jumper as the block's number.  What this module still does is what a
// ribbon does: eight blocks' HC_OUT land on eight highways, and the eight
// positions' open drains land on three wired-OR conductors.
//
// THE PARAMETERS HERE ARE NOT ON THIS BOARD.  BLOCK_NUM and BLOCK_FITTED are
// the eight block headers' jumpers, passed down from exch so that this model
// of the ribbon knows which highway each connector's HC_OUT pin lands on.
// The board itself knows nothing.
//
// THREE WIRED-ORs, one mechanism.  /HA carries M and /HB carries BUSY, both
// addressed by SCAN, so a reader takes both facts about one port out of one
// bit-time.  /HW carries the card option word of whichever port the marker
// last pointed at.  All three idle HIGH on a 4.7 k pull-up at the clock card,
// all three are sampled at the same instant in cell 4, and all three read
// "nobody is pulling" the same way -- which is what makes an absent block, an
// unfitted port and a missing jumper one fault signature instead of four.
`timescale 1ns/1ps
`include "exch.vh"

module mainboard #(
    // Three bits a position, octal: the highway each block header's jumper
    // routes its HC_OUT onto.  76543210 is the natural setting.
    parameter [23:0] BLOCK_NUM    = 24'o76543210,
    parameter [7:0]  BLOCK_FITTED = 8'hFF
)(
    input             fill,                 // what an undriven HC conductor is pulled to
    input      [7:0]  hc_from_block,        // each position's HC_OUT
    input      [7:0]  ha_pd_from_block,     // each position's M drains, already ORed
    input      [7:0]  hb_pd_from_block,     // and its BUSY drains
    input      [7:0]  hw_pd_from_block,     // MAXIMAL: the pointed card's word

    output     [7:0]  hc,                   // the eight conductors as they end up
    output            ha_n,                 // /HA: a 4.7 k pull-up and 64 open drains
    output            hb_n,                 // /HB: the same again, for BUSY
    output            hw_n                  // MAXIMAL: /HW, the card word bus
);
    // ---- the eight HC conductors -------------------------------------------
    // One driver a wire.  A conductor with no driver -- no block in any
    // position jumpered onto it -- is pulled to FILL through 4.7 k at the
    // clock card, so it reads as CVSD silence rather than as noise.  Two
    // blocks jumpered onto one highway is two '244s on one wire, and it reads
    // here as what it is.
    //
    // A generate, because this is one connector repeated eight times.  Nothing
    // in it is a signal: `c` and `p` are genvars, C is a localparam, and every
    // term is a constant expression of the jumpers -- so it is copper, not a
    // mux.  drv[p] is "position p's block routes its HC_OUT onto this wire".
    genvar c, p;
    generate
        for (c = 0; c < 8; c = c + 1) begin : col
            localparam [2:0] C = c;
            wire [7:0] drv;
            for (p = 0; p < 8; p = p + 1) begin : pos
                assign drv[p] = BLOCK_FITTED[p] && (BLOCK_NUM[p*3 +: 3] == C);
            end
            assign hc[c] = (drv == 8'd0)                 ? fill
                         : ((drv & (drv - 8'd1)) != 0) ? 1'bx
                         : |(hc_from_block & drv);
        end
    endgenerate

    // ---- /HA and /HB: TWO CONDUCTORS, OPEN COLLECTOR, IDLE HIGH ------------
    // A 4.7 k pull-up here on each, sixty-four 2N7002 open drains out there on
    // each, and no driver that ever pulls either up.  THE POLARITY IS AN
    // INVERSION OF mainboard.md 2.2, which has HA "pulled to ground: on-hook"
    // -- an open-collector wire cannot be, and one inverted receiver anywhere
    // leaves the whole exchange reading permanently off-hook.
    //
    // Port p owns bit-time p on BOTH wires, so M and BUSY of one port arrive
    // together and a reader needs no phase bit and no held half-sample.  A pass
    // is 64 bit-times, 1 ms, and a port refreshes at 1 kHz.
    //
    // What it buys: absent reads as idle with no part at all.  An unstuffed
    // slot, an unstuffed block, a pulled card and a cut cable all read M 0 and
    // BUSY 0, which is the whole of mvp.md 2's table out of one mechanism
    // instead of four separate pulls.
    assign ha_n = ~(|ha_pd_from_block);
    assign hb_n = ~(|hb_pd_from_block);


    // ---- MAXIMAL: /HW, the card word bus -----------------------------------
    // The third wired-OR, and the same part as the other two: one 4.7 k
    // pull-up here and an open drain at every card.  It is NOT scanned -- the
    // marker points at a port with a word whose DST names it, and that one
    // card drives /HW for the next sixteen frames.
    //
    // It idles HIGH like /HA and /HB, so a pointed port that is empty, pulled,
    // or on an unfitted block reads all ones -- and all ones is what
    // extensions.md 2.2 already calls unconditional, which is wrong for an
    // absent card.  THE MARKER MUST NOT TAKE A WORD IT DID NOT SEE ARRIVE:
    // pair every read with the BUSY it already has off /HB, and treat
    // "no drain on any of sixteen frames" as unequipped rather than as FF.
    // This is option-word-rev2.md 2's FF-fails-open bug, which is live in the
    // old tree; the pull-up makes it reachable here too if it is ignored.
    assign hw_n = ~(|hw_pd_from_block);
endmodule
