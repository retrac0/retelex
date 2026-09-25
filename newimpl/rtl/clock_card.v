// clock_card -- the crystal, the divider chain, and the scanner.
//
// On the board this is one 4.096 MHz crystal oscillator, a 74HC4040 ripple
// divider, a 74HC163 for SLOT, a 74HC175 on the 1.024 MHz tap for SLOTQ, a
// counter for the ring cadence, and a 74HC244 of drivers into cable A.
// About ten packages (fabric.md 5).
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
// 4096, so the pass boundary and TICK are one edge -- pass_stb is not a ninth
// tap, it IS tick_1k, and the divider is not one stage longer than the chain
// clocks.md 1 already had.  With A and BUSY on their own conductors there is
// no phase bit, so the scanner's address is simply a port number.
//
// Everything is generated from one master clock.  Where the hardware has a
// real clock wire this gives both the waveform -- for a card that wants an
// edge -- and a one-tick strobe, which is what the synchronous RTL uses.
//
//   common/clocks.md 1, mainboard.md 2.1, fabric.md 2
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
    output                   line_hb,      // 1.024 MHz LINE_HB (mf8-spec.md 9.1)
    output reg [2:0]         slot,         // the '163: the cell number.  Every commutator
    output reg [2:0]         slotq,        // the '175: SLOT a quarter cell late.  Strobes only
    output                   cap_stb,      // one master tick at mid-cell: every capture clock W

    // ---- the frame and above --------------------------------------------
    output                   tx_clk,       // 64 kHz frame clock = /SLOT[2].  Socket a1
    output                   frame_stb,    // one master tick at the frame edge
    output                   clk_8k,       // 8 kHz, one frame wide.  Socket a3 (TX_OCT)
    output                   rx_oct,       // CLK_8K one frame late (fabric.md 3.4).  Socket a8
    output                   oct_stb,      // one master tick, the octet's last frame edge

    // ---- the scanner: six stages of the same divider ---------------------
    output     [`SCANW-1:0]  scan,         // the port whose turn it is, 0..63
    output                   pass_stb,     // 1 kHz: the pass boundary.  Replaces START.
                                           // The SAME EDGE as tick_1k, and the same
                                           // conductor on cable A -- named twice
                                           // because it is two facts, not two pins

    // ---- references ------------------------------------------------------
    output                   fill,         // 32 kHz 1010 = CVSD silence.  IS scan[0]
    output reg               ring_cad_n,   // 2.048 s low / 4.096 s high
    output                   tick_1k       // 1 kHz, one master tick.  The RCs, the registers
);
    // The frame counter.  Six stages: the low three are the octet position
    // that CLK_8K is a decode of, and all six together ARE the scan address.
    reg [`SCANW-1:0] fcnt;
    reg [12:0]       cad;                  // the cadence, in milliseconds

    localparam [12:0] CAD_LAST = RING_ON_MS + RING_OFF_MS - 13'd1;
    localparam [12:0] CAD_ON   = RING_ON_MS;

    // ---- combinational taps ------------------------------------------------
    assign hclk      = ~tick[2];                    // ticks 0-3 high, 4-7 low
    assign line_hb   = tick[1];                     // 4.096 / 4 = 1.024 MHz
    assign cap_stb   = (tick == `TICK_MID);
    assign tx_clk    = ~slot[2];                    // high for the first half of the frame
    assign frame_stb = (tick == 3'd0) && (slot == 3'd0);

    assign clk_8k    = (fcnt[2:0] == 3'd7);         // one frame wide, superframe state 7
    assign rx_oct    = (fcnt[2:0] == 3'd0);         // the same, one frame later
    assign oct_stb   = frame_stb && (fcnt[2:0] == 3'd7);

    // THE SCANNER.  No enable, no gate, nothing to disturb it.  A port owns
    // ONE bit-time now, on both /HA and /HB at once, so the address is the
    // port number and nothing else.
    assign scan      = fcnt;

    // FILL and SCAN[0] ARE STILL THE SAME DIVIDER STAGE -- fcnt[0] is now the
    // port number's low bit rather than an A/BUSY phase, but it is the same
    // /128 stage at 32 kHz.  Convenient, and a trap if anyone ever inverts one
    // of them "locally": the scan would then be off by a port and every reader
    // would take its neighbour's hook.  clocks.md 1 has FILL as TX_CLK / 2,
    // which is exactly fcnt[0].
    assign fill      = fcnt[0];

    // TICK: 64 frames is 1 ms -- and 64 frames is also one whole pass, so
    // these two are one decode and one conductor.
    assign tick_1k   = frame_stb && (fcnt == {`SCANW{1'b0}});
    assign pass_stb  = tick_1k;

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
