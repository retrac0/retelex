// word_rx -- the card word reader: /HW into eight bits.  NETWORK.
//
// Whatever reads a card's option word -- the mini marker before it takes a
// caller, the network unit before it holds or hunts a trunk -- points at the
// port with a word on cable B whose DST names it (WR suppressed), and that one
// card drives /HW a bit a frame.  This board takes the eight frames that
// follow and hands back the PRIMARY OCTET: class, options, or a whole port.
// About two packages: a '259 and half a '161.
//
// THE CARD SETS THE BIT ORDER, NOT THIS READER.  A trunk card's '165 is loaded
// in frame 7 of every octet and shifted at each frame edge after it
// (baseband_card.v; baseband.md 3.5), so frame 7 carries bit 0, frame 0 bit 1,
// and frame f bit f+1 mod 8.  The octet position is SCAN[2:0] -- the same
// divider stages TX_OCT is decoded from -- so the reader needs no alignment:
// ANY eight consecutive frames hold all eight bits, and the '259's outputs are
// wired rotated by one so each lands in its own place.  Waiting for frame 7
// instead would cost up to a whole octet on every read.
//
// A ONE IS A PULLED-DOWN FRAME.  extensions.md 2.2: "the pin is low for a 1".
// /HW idles high, so a port with no card, a card held off by its power-up RC,
// and a trunk whose link is down all read ALL ZEROS -- which the word table
// calls "none / OOS".  An absent card fails SAFE.  The trap is only for a
// reader that takes the wire's level as the bit, which reads the same absence
// as all ones, a plain line.  newimpl/README.md 1 said otherwise; it is
// corrected there.
//
// ONLY THE PRIMARY OCTET.  A sixteen-bit word at 64 kHz needs its card to load
// every sixteen frames, and the socket carries no strobe that marks sixteen
// (TX_OCT marks eight).  Everything a trunk says -- class, glare, direction --
// is in the primary.  The secondary is the class marker's problem, recorded
// as open in newimpl/README.md 6.
//
//   extensions.md 2.2, baseband.md 3.5, newimpl/README.md 1
`timescale 1ns/1ps
`include "exch.vh"

module word_rx (
    input                   clk,
    input                   rst_n,

    // ---- cable A -----------------------------------------------------------
    input      [2:0]        slotq,
    input                   cap_stb,
    input      [`SCANW-1:0] scan,

    // ---- cable B -----------------------------------------------------------
    input                   hw_n,        // /HW.  IDLE HIGH.  Low is a one

    // ---- this card's own serialiser ---------------------------------------
    input                   arm,         // one tick: the pointing word is fully shifted
    output reg              busy,        // collecting: the reader still owns cable B
    output reg              done,        // one tick: `word` is the pointed card's octet
    output reg [7:0]        word
);
    // The capture instant is the planes' own: strobe line 4's falling edge,
    // mid-cell 4, 8.79 us into the frame.  /HW is sampled with /HA and /HB and
    // shares their settling budget (exch.vh).
    wire a_stb = cap_stb && (slotq == `CELL_A);

    // 74HC259 -- eight addressable latches, addressed by SCAN[2:0].  Its
    // output Qk is WIRED as bit (k+1) mod 8: layout, not an adder.
    wire [2:0] place = scan[2:0] + 3'd1;

    reg [3:0] n;      // half a '161: frames still to take

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0; done <= 1'b0; word <= 8'd0; n <= 4'd0;
        end else begin
            done <= 1'b0;
            if (arm) begin
                // A new read clears the latch first: a bit this read never
                // took must not be left over from the last port.
                busy <= 1'b1; n <= 4'd8; word <= 8'd0;
            end else if (busy && a_stb) begin
                word[place] <= ~hw_n;
                if (n == 4'd1) begin busy <= 1'b0; done <= 1'b1; end
                n <= n - 4'd1;
            end
        end
    end

    // the octet position is all this board needs of the scan
    wire _unused = &{1'b0, scan[`SCANW-1:3], 1'b0};
endmodule
