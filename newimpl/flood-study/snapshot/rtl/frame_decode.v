// frame_decode -- what a block makes for itself from SLOT2 and SCAN.
//
// FIVE LINES LEFT THE BUS (Joel, 2026-09-25).  Each was another bus signal
// under another name, or one gate away from one:
//
//   TX_CLK = /SLOT2              a '04 section.  Socket a1
//   TX_OCT = SCAN[2:0] == 7      a third of a '11: one frame in eight.  Socket a3
//   RX_OCT = TX_OCT a frame late half a '74 on TX_CLK.  Socket a8.  NOT a
//                                decode of SCAN == 0 on the board: the clock
//                                card's '4040 ripples, and on its way from 1
//                                to 2 and from 3 to 4 it passes through 000
//                                for a few nanoseconds.  TX_OCT's decode
//                                cannot glitch -- a ripple up-count clears
//                                bits before it sets the last one
//   FILL   = SCAN0               a wire.  Socket a4, and an unfitted port's C.
//                                The trap README 2 named -- FILL inverted
//                                "locally" against SCAN0 -- has nothing left
//                                to invert
//   TICK   = SCAN5               a wire: the /4096 stage.  Its fall is the pass
//                                boundary, as it always was
//
// So each block carries about one package for its sockets and its unfitted
// ports, and a common-control card that wants the 1 ms edge takes it off
// SCAN.  The model has no ripple, so RX_OCT here is the decode the clock card
// used before, the same signal without the glitch.  exch computes this once
// for all eight blocks, because the eight copies on the boards are identical.
//
// The strobes are the RTL's (STYLE.md 6): frame_stb is SLOT2's fall, which is
// TX_CLK's rise, and tick_1k is SCAN5's fall.
//
//   clocks.md 1, fabric.md 3.4, common-cards.md 1.1
`timescale 1ns/1ps
`include "exch.vh"

module frame_decode (
    input                   slot2,        // SLOT[2]
    input                   frame_stb,    // one master tick: SLOT2's fall, the frame edge
    input      [`SCANW-1:0] scan,

    output                  tx_clk,       // socket a1
    output                  tx_oct,       // socket a3, the exchange's CLK_8K
    output                  rx_oct,       // socket a8
    output                  oct_stb,      // one master tick: the frame edge that opens frame 7
    output                  fill,         // socket a4, and what an unfitted port sends
    output                  tick_1k       // one master tick at SCAN5's fall: the pass boundary
);
    assign tx_clk  = ~slot2;
    assign tx_oct  = (scan[2:0] == 3'd7);
    assign rx_oct  = (scan[2:0] == 3'd0);
    assign oct_stb = frame_stb && (scan[2:0] == 3'd7);
    assign fill    = scan[0];
    assign tick_1k = frame_stb && (scan == {`SCANW{1'b0}});
endmodule
