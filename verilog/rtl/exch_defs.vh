// exch_defs.vh -- the exchange's fixed geometry.  exch/docs/exch-protocol.md 5.
`ifndef EXCH_DEFS_VH
`define EXCH_DEFS_VH

// 8 highways in space x 8 slots in time = 64 ports.  A port's address IS its
// dialled number `h s`: addr[5:3] = highway, addr[2:0] = slot.
`define NB 8
`define NS 8
`define NP 64

// The master clock is the clock card's own crystal, 4.096 MHz (mf8-spec.md 9.1).
// Eight master ticks to a 512 kHz cell, eight cells to a 64 kHz frame, eight
// frames to an 8 kHz octet.  Everything below is one synchronous domain; the
// 74HC design's separate clocks come out as strobes on this one.
`define TICKS_PER_CELL  8
`define CELLS_PER_FRAME 8
`define FRAMES_PER_OCT  8

// Where in a cell things happen (exch-fabric.md 3.2).  HCLK is high for the
// first half of a cell, so the strobe decoder is enabled from tick 4, and its
// falling edge -- the port's capture clock W -- is the middle of the cell.
`define TICK_SLOTQ 3'd2   // SLOTQ is SLOT a quarter of a cell late
`define TICK_MID   3'd4   // mid-cell: every port's capture flip-flop clocks here

`endif
