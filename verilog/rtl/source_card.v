// source_card -- a card that talks and never listens: dial tone at 01,
// busy at 02, cannot-complete at 03, or a radio or a clock anyone may dial
// (features.md 6, fabric.md 3.5's class "source").
//
// It needs no port circuit in the full design -- a source never listens -- and
// it ties /ANS low so its port never rings.  In hardware the bits are a tuned
// oscillator through a CVSD encoder, or a ROM; here they are a short LFSR, so
// that a testbench can tell dial tone from cannot-complete and prove which one
// a caller was given.
`timescale 1ns/1ps

module source_card #(
    parameter [7:0]  WORD = 8'h06,            // class 011 source, form 0
    parameter [15:0] SEED = 16'hACE1
)(
    input        clk,
    input        frame_stb,
    input        tx_oct,
    output       c_tx,
    output       a_tx,
    output       word_pin,
    output       ans_n
);
    reg [15:0] lfsr = SEED;
    always @(posedge clk) if (frame_stb)
        lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};

    assign c_tx  = lfsr[15];
    assign a_tx  = 1'b0;                      // a source never answers
    assign ans_n = 1'b0;                      // and never rings

    reg [7:0] sr = WORD;
    always @(posedge clk) if (frame_stb)
        sr <= tx_oct ? WORD : {1'b0, sr[7:1]};
    assign word_pin = sr[0];
endmodule
