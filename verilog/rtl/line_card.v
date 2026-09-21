// line_card -- a subscriber card, simplified to the four signals that matter.
//
// The real card is channel-cards.md's FXS card or subscriber-line.md's CVSD line
// card: transformers, a 48 V phantom feed, a 128 kBaud differential-Manchester
// driver and a hook detector.  None of that changes a single bit that reaches
// the exchange, so for simulation the subscriber side is four wires:
//
//     tx   CVSD bits from the subscriber          -> the slot's C_TX
//     rx   CVSD bits to the subscriber            <- the slot's C_RX
//     m    off-hook                               -> the slot's A_TX
//     e    supervision back from the exchange     <- the slot's A_RX
//          (the ring cadence while the port rings, steady while the far end
//           is off-hook -- the port's gates have already done that work)
//
// M and E are the names fabric.md 3.5 uses throughout, and they are also
// the E&M leads of mf8-spec.md 12.1's card, so an E&M trunk plugs into the same
// four wires.  The card's own two pins say what the port is (extensions.md 2).
`timescale 1ns/1ps

module line_card #(
    // protocol.md 5 has a plain line card tie its word pin to ground, "which
    // reads all ones" -- but fabric.md 3.5's table gives LINE as 001, so the
    // two cannot both be right.  Until that is settled the card sends an explicit
    // word.  See the README.
    // (was: ties its word pin to ground, which reads all ones at
    // the block and means "a line, no options" (protocol.md 5) -- no part
    // and no jumper.  A card with options shifts a word out of a '165.
    parameter [7:0] WORD  = 8'h01,      // class 001: a line, no options
    parameter       RINGS = 1'b1      // /ANS left open: this port rings
)(
    input        clk,
    input        frame_stb,
    input        tx_oct,

    // the subscriber
    input        tx,
    output       rx,
    input        m,
    output       e,

    // the channel slot (mf8-backplane.md 8)
    output       c_tx,
    output       a_tx,
    input        c_rx,
    input        a_rx,
    output       word_pin,
    output       ans_n
);
    assign c_tx  = tx;
    assign a_tx  = m;
    assign rx    = c_rx;
    assign e     = a_rx;
    assign ans_n = ~RINGS;            // a phone leaves it open; a trunk ties it low

    // The word, one bit a frame, re-loaded every octet.
    reg [7:0] sr = WORD;
    always @(posedge clk) if (frame_stb)
        sr <= tx_oct ? WORD : {1'b0, sr[7:1]};
    assign word_pin = sr[0];
endmodule
