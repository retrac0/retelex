// mainboard -- the passive board at each tap of the ribbon.  mainboard.md.
//
// The cable is common: every tap sees the same conductors.  Three signals a
// block are not -- block h drives HC[h] and HA[h] and answers to /BLK -- and
// they come from three shunts in one silkscreened column, here the SHUNT
// parameter, three bits a position.  Nothing in a block reads its own number.
//
// With the control bus serial, /BLK is not a bus at all: each block decodes
// DST[5:3] on its own '138 and the shunt picks which of those eight lines comes
// back as its /BLK.  So this module is the sixteen highway conductors of cable
// A, and a purely local shunt for each position's select.
`timescale 1ns/1ps
`include "exch_defs.vh"

module mainboard #(
    // Position k's column, three bits each: the default is the obvious one.
    parameter [23:0] SHUNT        = 24'o76543210,
    // Which positions have their three shunts fitted.  A block with no number
    // is simply not heard, and everything it listens to still works.
    parameter [7:0]  SHUNT_FITTED = 8'hFF
)(
    input      [7:0] fill_pull,     // FILL, through 4k7 at the clock card
    input      [7:0] hc_from_block, // each position's HC_OUT driver
    input      [7:0] ha_from_block,
    input     [63:0] blk_dec,       // each position's own '138: eight lines each
    output     [7:0] hc,            // the cable's sixteen highway conductors
    output     [7:0] ha,
    output     [7:0] blk_to_block   // /BLK at each position
);
    // How many positions are shunted onto column c, and which one.  Both are
    // resolved at elaboration: a shunt is wiring, not logic.
    function integer n_drivers(input integer c);
        integer k;
        begin
            n_drivers = 0;
            for (k = 0; k < 8; k = k + 1)
                if (SHUNT_FITTED[k] && SHUNT[k*3 +: 3] == c[2:0]) n_drivers = n_drivers + 1;
        end
    endfunction

    function integer driver_of(input integer c);
        integer k;
        begin
            driver_of = 0;
            for (k = 0; k < 8; k = k + 1)
                if (SHUNT_FITTED[k] && SHUNT[k*3 +: 3] == c[2:0]) driver_of = k;
        end
    endfunction

    genvar c, k;
    generate
        for (c = 0; c < 8; c = c + 1) begin : conductor
            if (n_drivers(c) == 1) begin : driven
                assign hc[c] = hc_from_block[driver_of(c)];
                assign ha[c] = ha_from_block[driver_of(c)];
            end else if (n_drivers(c) == 0) begin : undriven
                // No block, or its shunts left out: pulled to FILL and to
                // ground, so the column reads as CVSD silence and on-hook
                // rather than floating (mainboard.md 2.2, 6).
                assign hc[c] = fill_pull[c];
                assign ha[c] = 1'b0;
            end else begin : contention
                // Two blocks shunted onto one column: two '244s on one
                // conductor.  mainboard.md 6 says this is caught at
                // bring-up; here it reads as what it is.
                assign hc[c] = 1'bx;
                assign ha[c] = 1'bx;
            end
        end
        // /BLK is not a bus any more.  Position k's shunt picks line SHUNT[k]
        // of position k's OWN decoder, so nothing about /BLK crosses positions.
        for (k = 0; k < 8; k = k + 1) begin : position
            assign blk_to_block[k] =
                SHUNT_FITTED[k] ? blk_dec[k*8 + SHUNT[k*3 +: 3]] : 1'b0;
        end
    endgenerate
endmodule
