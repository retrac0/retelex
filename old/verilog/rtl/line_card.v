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
    // extensions.md 2.2: 16-bit word at 128 kHz.  All ones is the constant
    // *plain line* (pin tied to ground, no part).  Class forms put the primary
    // in bits 7–0; bits 15–8 are FF when the secondary chip is absent.
    parameter [15:0] WORD  = 16'hFFFF,  // plain line: grounded pin reads all ones
    parameter        RINGS = 1'b1       // /ANS left open: this port rings
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

    // 16-bit word: parallel-load every TX_OCT, then LSB-first at 128 kHz
    // (bit-time 0 = WORD[0] — extensions.md 2.2).  4.096 MHz / 32.
    reg [15:0] sr = WORD;
    reg [4:0]  div = 5'd0;
    always @(posedge clk) begin
        if (frame_stb && tx_oct) begin
            sr  <= WORD;
            div <= 5'd0;
        end else if (div == 5'd31) begin
            sr  <= {1'b0, sr[15:1]};
            div <= 5'd0;
        end else
            div <= div + 1'b1;
    end
    assign word_pin = sr[0];
endmodule
