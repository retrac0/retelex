// clock_card -- the crystal, the divider chain, and the scanner.
//
// On the board this is one 4.096 MHz crystal oscillator, a 74HC4040 ripple
// divider, a 74HC163 for SLOT, a 74HC175 on the 1.024 MHz tap for SLOTQ, a
// counter for the ring cadence, and a 74HC244 of drivers onto the bus.
// About ten packages (common/clocks.md §1).
//
// THE SCANNER IS NOT A PART.  SCAN[5:0] is the six divider stages that sit
// between TX_CLK (/64) and TICK (/4096), brought out on six pins.  It has no
// enable, no load, no clear and no reset beyond power-on, so NOTHING IN THE
// EXCHANGE CAN STOP IT.  That is the whole of "the scanner never stops": a
// port the marker could not take comes round again 1 ms later.  Contrast the
// old tree's marker, where the scanner was the marker's own '393 with a count
// enable that the serialiser, the console and a re-point could all clear.
//
// A PASS IS EXACTLY THE TICK PERIOD.  64 ports x 64 master ticks a frame is
// 4096, so the pass boundary and the 1 kHz TICK are one edge: SCAN5's fall.
// With A and BUSY on their own conductors there is no phase bit, so the
// scanner's address is simply a port number.
//
// WHAT THIS CARD NO LONGER DRIVES (Joel, 2026-09-25).  TICK is SCAN5, FILL is
// SCAN0, TX_CLK is /SLOT2, and TX_OCT and RX_OCT are SCAN[2:0] decoded.  None
// of the five has a conductor of its own any more: a block makes them for its
// sockets and a card that wants the 1 ms edge takes it off SCAN
// (frame_decode.v).  The bus carries HCLK, SLOT, SLOTQ and SCAN from here.
//
// Everything is generated from one master clock.  Where the hardware has a
// real clock wire this gives both the waveform -- for a card that wants an
// edge -- and a one-tick strobe, which is what the synchronous RTL uses.
//
//   common/clocks.md §1; bus.md §1, §3; fabric.md §3.1
`timescale 1ns/1ps
`include "exch.vh"

module clock_card #(
    // The ring cadence, in milliseconds.  2.048 s / 4.096 s and not 2 / 4:
    // both are whole multiples of a '4040's 256 ms tap, which is the only
    // honest TTL number, and 2 % is not a thing anyone measures.
    parameter [12:0] RING_ON_MS  = 13'd2048,
    parameter [12:0] RING_OFF_MS = 13'd4096
)(
    input                    clk,          // the 4.096 MHz crystal
    input                    rst_n,        // power-on reset

    // ---- inside a cell ---------------------------------------------------
    output reg [2:0]         tick,         // the eighth of a cell.  A trunk card wants it
    output                   hclk,         // 512 kHz, high for the first half of a cell
    output reg [2:0]         slot,         // the '163: the cell number.  Every commutator
    output reg [2:0]         slotq,        // the '175: SLOT a quarter cell late.  Strobes only
    output                   cap_stb,      // one master tick at mid-cell: every capture clock W

    // ---- the frame --------------------------------------------------------
    output                   frame_stb,    // one master tick at the frame edge: SLOT2's fall

    // ---- the scanner: six stages of the same divider ---------------------
    // SCAN0 is also FILL, the 32 kHz 1010 that is CVSD silence, and SCAN5 is
    // also TICK: its fall is the pass boundary and the 1 ms time base
    output     [`SCANW-1:0]  scan,         // the port whose turn it is, 0..63

    // ---- reference -------------------------------------------------------
    output reg               ring_cad_n    // 2.048 s low / 4.096 s high
);
    // The frame counter.  Six stages: the low three are the octet position
    // that TX_OCT is a decode of, and all six together ARE the scan address.
    reg [`SCANW-1:0] fcnt;
    reg [12:0]       cad;                  // the cadence, in milliseconds

    localparam [12:0] CAD_LAST = RING_ON_MS + RING_OFF_MS - 13'd1;
    localparam [12:0] CAD_ON   = RING_ON_MS;

    // ---- combinational taps ------------------------------------------------
    assign hclk      = ~tick[2];                    // ticks 0-3 high, 4-7 low
    assign cap_stb   = (tick == `TICK_MID);
    assign frame_stb = (tick == 3'd0) && (slot == 3'd0);

    // THE SCANNER.  No enable, no gate, nothing to disturb it.  A port owns
    // ONE bit-time now, on both /HA and /HB at once, so the address is the
    // port number and nothing else.
    assign scan      = fcnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tick <= 3'd0; slot <= 3'd0; slotq <= 3'd0;
            fcnt <= {`SCANW{1'b0}};
            cad  <= 13'd0; ring_cad_n <= 1'b1;
        end else begin
            tick <= tick + 1'b1;

            // the '175, clocked off the 1.024 MHz tap: the strobe decoder's
            // address only ever moves while the decoder is disabled
            if (tick == `TICK_SLOTQ) slotq <= slot;

            if (tick == 3'd7) begin
                slot <= slot + 1'b1;            // the '163, at the start of the next cell
                if (slot == 3'd7) begin         // ... and a frame has gone by
                    fcnt <= fcnt + 1'b1;        // the scan address steps here, always

                    // the cadence, off the 1 kHz tick.  In 74HC this is a
                    // '4040's 256 ms tap and a nibble compare: 8 steps on,
                    // 16 off.
                    if (fcnt[5:0] == 6'd63) begin
                        cad        <= (cad == CAD_LAST) ? 13'd0 : cad + 1'b1;
                        ring_cad_n <= ~(cad < CAD_ON);
                    end
                end
            end
        end
    end
endmodule
