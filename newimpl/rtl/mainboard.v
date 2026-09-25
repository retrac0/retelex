// mainboard -- the passive board at each ribbon tap: the cables' headers, the
// block's connector, and the BLOCK SHUNT.  No logic, and no part that does
// anything but connect.  mainboard.md 1.
//
// A ribbon is a bus of identical conductors and every connector crimped along
// it sees the same signals.  Almost all of this bus wants exactly that.  TWO
// things do not: block h drives highway HC[h], and answers to /BLK line h.
// That is the whole of a block's identity, and it is two shunts in two
// labelled columns rather than six packages of decoding at every block.
//
// THE SHUNT FIELD IS TWO COLUMNS NOW, NOT THREE.  HA[0..7] are gone, so there
// is no HA_OUT to shunt: the supervision planes are conductors that every port
// in the exchange pulls down in its own turn, and no block owns them.
//
// THREE WIRED-ORs, one mechanism.  /HA carries M and /HB carries BUSY, both
// addressed by SCAN, so a reader takes both facts about one port out of one
// bit-time.  /HW carries the card option word of whichever port the marker
// last pointed at.  All three idle HIGH on a 4.7 k pull-up at the clock card,
// all three are sampled at the same instant in cell 4, and all three read
// "nobody is pulling" the same way -- which is what makes an absent block, an
// unfitted port and a missing shunt one fault signature instead of four.
`timescale 1ns/1ps
`include "exch.vh"

module mainboard #(
    // Three bits a position, octal: which HC conductor and which /BLK line
    // this position's shunts pick.  76543210 is the natural wiring.
    parameter [23:0] SHUNT        = 24'o76543210,
    parameter [7:0]  SHUNT_FITTED = 8'b1111_1111
)(
    input             fill,                 // what an undriven HC conductor is pulled to
    input      [7:0]  hc_from_block,        // each position's HC_OUT
    input      [7:0]  ha_pd_from_block,     // each position's M drains, already ORed
    input      [7:0]  hb_pd_from_block,     // and its BUSY drains
    input      [63:0] blk_dec,              // eight lines out of each position's '138
    input      [7:0]  hw_pd_from_block,     // MAXIMAL: the pointed card's word

    output     [7:0]  hc,                   // the eight conductors as they end up
    output            ha_n,                 // /HA: a 4.7 k pull-up and 64 open drains
    output            hb_n,                 // /HB: the same again, for BUSY
    output     [7:0]  blk_n,                // /BLK back to each position
    output            hw_n                  // MAXIMAL: /HW, the card word bus
);
    // ---- the eight HC conductors -------------------------------------------
    // One driver a wire.  A conductor with no driver -- an unfitted block, or
    // a missing shunt -- is pulled to FILL through 4.7 k at the clock card, so
    // it reads as CVSD silence rather than as noise.  Two positions shunted
    // onto one column is two '244s on one wire, and it reads here as what it
    // is.
    //
    // drv[c] is which positions have a shunt in column c.  Every bit of it is
    // a constant expression of the parameters, so the whole shunt field
    // resolves at elaboration and none of this is logic on the board -- it is
    // a 2 x 8 header with a jumper in it.
    // A generate, because this is ONE header repeated eight times, and the
    // eight hand-unrolled lines it replaces were four hundred characters each
    // and could not be diffed.  Nothing in it is a signal: `c` and `p` are
    // genvars, C is a localparam, and every term is a constant expression of
    // SHUNT and SHUNT_FITTED -- so it is still a jumper, not a mux.
    genvar c, p;
    generate
        for (c = 0; c < 8; c = c + 1) begin : col
            localparam [2:0] C = c;
            // drv[p]: position p has its jumper in this column
            wire [7:0] drv;
            for (p = 0; p < 8; p = p + 1) begin : pos
                assign drv[p] = SHUNT_FITTED[p] && (SHUNT[p*3 +: 3] == C);
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

    // ---- /BLK: each position's own '138, through its shunt column ----------
    // The decoder moved from the marker's end of the wire to the block's, and
    // nothing learned its own name on the way.  A position with no shunts
    // answers to nothing.
    assign blk_n[0] = SHUNT_FITTED[0] ? ~blk_dec[0*8 + SHUNT[0*3 +: 3]] : 1'b1;
    assign blk_n[1] = SHUNT_FITTED[1] ? ~blk_dec[1*8 + SHUNT[1*3 +: 3]] : 1'b1;
    assign blk_n[2] = SHUNT_FITTED[2] ? ~blk_dec[2*8 + SHUNT[2*3 +: 3]] : 1'b1;
    assign blk_n[3] = SHUNT_FITTED[3] ? ~blk_dec[3*8 + SHUNT[3*3 +: 3]] : 1'b1;
    assign blk_n[4] = SHUNT_FITTED[4] ? ~blk_dec[4*8 + SHUNT[4*3 +: 3]] : 1'b1;
    assign blk_n[5] = SHUNT_FITTED[5] ? ~blk_dec[5*8 + SHUNT[5*3 +: 3]] : 1'b1;
    assign blk_n[6] = SHUNT_FITTED[6] ? ~blk_dec[6*8 + SHUNT[6*3 +: 3]] : 1'b1;
    assign blk_n[7] = SHUNT_FITTED[7] ? ~blk_dec[7*8 + SHUNT[7*3 +: 3]] : 1'b1;

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
