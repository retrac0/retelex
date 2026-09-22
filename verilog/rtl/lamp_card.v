// lamp_card -- ONE CARD of the hook/busy display.  hookbusy.md 2.
//
// One 74HC259, eight LEDs, eight resistors, two shunt columns and a mode
// block.  Sixteen of these stand at 0.4 inch on four stacking headers --
// HA, LEB, PWR, and control -- and a seventeenth -- the interface card
// (common_card) -- carries the word decode, the LEB decode, the control
// buffer and the tap on the two cables.  ONE PCB IN SIXTEEN COPIES:
// the card knows nothing, and two shunts and a jumper say what it is.  That
// is mainboard.md 2.1's bargain one level down -- "the cable is common, the
// board is position-wired, and the card knows nothing" -- and it is why any
// card works in any position and one spare covers eight.
//
//   BLK   a 2x8 shunt column, silkscreen 0-7, TWO shunts in one position:
//         HA[h] -> the hook D, and LEB[h] -> the busy /LE
//   MODE  three poles, hook or busy:
//
//            D        /LE       /CLR        refreshed        no marker
//     HOOK   HA[h]    HCLK      Vcc         every 15.6 us    WORKS
//     BUSY   PB0      LEB[h]    /RESET      once a scan      freezes
//
// THE TWO HALVES COME OFF DIFFERENT CABLES AND FAIL DIFFERENTLY, which is the
// whole of observers.md 1.  HA is on cable A and every tap sees all eight
// highways at once, so a hook card is eight packages of nothing and is fitted
// at bring-up step 2, before a marker exists.  BUSY is not on the cable at all:
// a block commutates its eight ports' BUSY onto PB0, eight blocks share that
// one wire, and only the block /BLK names drives it (mainboard.md 2.2,
// "only the marker reads them, so eight blocks share two wires").  So a busy
// card sees a moving EIGHT-PORT WINDOW, positioned by whatever the last
// sixteen-bit word named, and what moves it is the marker's attention.
//
// The card carries NO GATE.  Its busy /LE arrives already gated, because the
// common card's '138 does that with its own enables (hookbusy.md 3).
`timescale 1ns/1ps

module lamp_card #(
    parameter [2:0] BLK  = 3'd0,      // the shunt column: which block
    parameter       HOOK = 1'b1       // the mode block: 1 = hook, 0 = busy
)(
    input             clk,
    // ---- four buses through the stack (hookbusy.md 4.2) ----------------
    // HA       ha[7:0]
    // LEB      leb_n[7:0]
    // PWR      (implied)
    // control  slotq, hclk, pb0, reset_n
    input      [2:0]  slotq,          // control: the '259 address, both modes
    input             hclk,           // control: the hook /LE
    input      [7:0]  ha,             // HA bus: all eight highways
    input             pb0,            // control: the selected block's BUSY
    input      [7:0]  leb_n,          // LEB bus: the interface card's '138 outputs
    input             reset_n,        // control: busy /CLR.  NOT a power-on
                                      // reset -- a '164 has no clear at all

    output     [7:0]  lamp            // eight LEDs, green or orange by stuffing
);
    // The BLK shunt column.  Two shunts in one position, so the block number
    // is set once and MODE picks which of the two the '259 sees.
    wire d_hook    = ha[BLK];
    wire le_busy_n = leb_n[BLK];

    // The MODE block, three poles.
    wire d     = HOOK ? d_hook    : pb0;
    wire le_n  = HOOK ? hclk      : le_busy_n;
    wire clr_n = HOOK ? 1'b1      : reset_n;

    hc259 u_lamp (.clk(clk), .clr_n(clr_n), .le_n(le_n),
                  .a(slotq), .d(d), .q(lamp));
endmodule
