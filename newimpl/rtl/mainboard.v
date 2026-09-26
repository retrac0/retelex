// mainboard -- the bus between the eight block positions: one 2 x 25 header
// at every position, a ribbon, bridges or direct mating (bus.md §2), and the
// clock card's pull-ups.  No logic, no jumper, and no part that does anything
// but connect.  The name is the old tree's, which had a passive board here.
//
// A bus is identical conductors and every position along it sees the same
// signals -- and NOW EVERY CONDUCTOR ON IT IS THAT.  The two that were not,
// which highway a block drives and which /BLK line it answers to, were a
// shunt field on the old mainboard: two jumper columns a position
// (exchange/decisions.md).  Both moved to the block's own header, where HC
// ROUTE routes HC_OUT and NUMBER gives the block's number (block-stack.md
// §4).  What this module still does is what the bus does: eight blocks'
// HC_OUT land on eight highways, and each position's one drain a plane lands
// on three wired-OR conductors.
//
// THE PARAMETERS HERE ARE NOT ON THE BUS.  BLOCK_NUM and BLOCK_FITTED are
// the eight block headers' jumpers, passed down from exch so that this model
// of the bus knows which highway each position's HC_OUT pin lands on.  The
// bus itself knows nothing.
//
// THREE WIRED-ORs, one mechanism.  /HA carries M and /HB carries BUSY, both
// addressed by SCAN, so a reader takes both facts about one port out of one
// bit-time.  /HW carries the card option word of whichever port a reader last
// SELECTED, by pulling /WS in that port's bit-time.  /WS is a fourth open
// drain on the same bus, but its drains are the readers' -- cards beside the
// exchange -- so it arrives at exch already resolved and is not ORed here.
// All three idle HIGH on a 4.7 k pull-up at the clock card,
// all three are sampled at the same instant in cell 4, and all three read
// "nobody is pulling" the same way -- which is what makes an absent block, an
// unfitted port and a missing jumper one fault signature instead of four.
`timescale 1ns/1ps
`include "exch.vh"

module mainboard #(
    // Three bits a position, octal: the highway each block header's HC ROUTE
    // jumper routes its HC_OUT onto.  76543210 is the natural setting.
    parameter [23:0] BLOCK_NUM    = 24'o76543210,
    parameter [7:0]  BLOCK_FITTED = 8'hFF
)(
    input             fill,                 // what an undriven HC conductor is pulled to
    input      [7:0]  hc_from_block,        // each position's HC_OUT
    input      [7:0]  ha_pd_from_block,     // each position's M drains, already ORed
    input      [7:0]  hb_pd_from_block,     // and its BUSY drains
    input      [7:0]  hw_pd_from_block,     // MAXIMAL: the selected card's word

    output     [7:0]  hc,                   // the eight conductors as they end up
    output            ha_n,                 // /HA: a 4.7 k pull-up and one open drain a block
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
    // A 4.7 k pull-up at the clock card on each, one open drain a block on
    // each -- the block ORs its eight ports' drains (block-stack.md §2.3) --
    // and no driver that ever pulls either up.  IDLE HIGH, AND A PULLED PLANE
    // IS A ONE (bus.md §1, fabric.md §3.2).  The old tree had HA "pulled to
    // ground: on-hook" (exchange/decisions.md) -- an open-collector wire cannot
    // be pulled to its active state, and one inverted receiver anywhere would
    // leave the whole exchange reading permanently off-hook.
    //
    // Port p owns bit-time p on BOTH wires, so M and BUSY of one port arrive
    // together and a reader needs no phase bit and no held half-sample.  A pass
    // is 64 bit-times, 1 ms, and a port refreshes at 1 kHz.
    //
    // What it buys: absent reads as idle with no part at all.  An unstuffed
    // slot, an unstuffed block, a pulled card and a cut cable all read M 0 and
    // BUSY 0, which is the whole of bus.md §6.1's table out of one mechanism
    // instead of four separate pulls.
    assign ha_n = ~(|ha_pd_from_block);
    assign hb_n = ~(|hb_pd_from_block);


    // ---- MAXIMAL: /HW, the card word bus -----------------------------------
    // The third wired-OR, and the same part as the other two: one 4.7 k
    // pull-up and one open drain a block, driven for the card a reader
    // selected (fabric.md §4).  It is NOT scanned -- a
    // reader selects a port in its own bit-time, and that one card drives /HW
    // until the next select (block.v).
    //
    // It idles HIGH like /HA and /HB, and a card pulls it low for a 1
    // (card-word.md §2).  So a selected port that is empty, pulled, or on an
    // unfitted block reads ALL ZEROS -- "none / OOS" -- and an absent card
    // fails SAFE (word_rx.v).  THE TRAP IS FOR A READER THAT TAKES THE WIRE'S
    // LEVEL AS THE BIT: it reads the same absence as all ones, which the word
    // table calls unconditional.  That is the old tree's FF-fails-open bug,
    // and the pull-up would make it reachable here too.
    assign hw_n = ~(|hw_pd_from_block);
endmodule
