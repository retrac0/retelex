// clock_card -- the exchange's one clock source.  fabric.md 2, and the
// signal list of mainboard.md 2.1.  In 74HC this is a 4.096 MHz crystal,
// a '4040, a '163 for SLOT and a '175 on the 1.024 MHz tap for SLOTQ.
//
// Everything here is generated from one master clock.  Where the hardware has a
// real clock wire -- TX_CLK, CLK_8K (socket TX_OCT) -- this gives both the
// waveform (for inspection and for a card that wants an edge) and a one-tick
// strobe, which is what the synchronous RTL actually uses.
`timescale 1ns/1ps
`include "exch_defs.vh"

module clock_card #(
    // The ring cadence, in frames at 64 kHz: 2 s on, 4 s off (low true).
    parameter integer RING_ON  = 128000,
    parameter integer RING_OFF = 256000,
    // TICK, 1 kHz: one frame in 64.
    parameter integer TICK_DIV = 64
)(
    input                    clk,        // 4.096 MHz
    input                    rst_n,

    output reg [2:0]         tick,       // where we are in the cell
    output                   hclk,       // 512 kHz, high for the first half of a cell
    output                   hb,         // 1.024 MHz, mf8-spec.md 9.1's half-bit clock
    output reg [2:0]         slot,       // the cell number: addresses every commutator
    output reg [2:0]         slotq,      // the same count a quarter cell late: strobes only
    output                   cap_stb,    // mid-cell: every port's capture clock W

    output                   tx_clk,     // 64 kHz frame clock
    output                   frame_stb,  // one tick at the frame edge, where every card samples
    output                   tx_oct,     // CLK_8K: 8 kHz (socket TX_OCT / a3)
    output                   rx_oct,     // CLK_8K one frame late (fabric.md 3.4)
    output reg               fill,       // 1010 at 32 kHz: CVSD silence
    output reg               ring_cad_n, // 2 s / 4 s, LOW while ringing
    output                   tick_1k     // the marker's and the registers' time base
);
    reg [2:0]  frame_in_oct;
    reg [18:0] cad;
    reg [6:0]  ms;
    localparam [6:0]  MS_LAST  = 7'(TICK_DIV - 1);
    localparam [18:0] CAD_LAST = 19'(RING_ON + RING_OFF - 1);
    localparam [18:0] CAD_ON   = 19'(RING_ON);

    assign hclk      = ~tick[2];                       // ticks 0-3 high, 4-7 low
    assign hb        = tick[1];                        // 4.096 / 4 = 1.024 MHz: mf8-spec.md 9.1's HB
    assign cap_stb   = (tick == `TICK_MID);
    assign frame_stb = (tick == 3'd0) && (slot == 3'd0);
    assign tx_clk    = ~slot[2];                       // high for the first half of the frame
    assign tx_oct    = (frame_in_oct == 3'd7);
    assign rx_oct    = (frame_in_oct == 3'd0);         // one frame later
    assign tick_1k   = frame_stb && (ms == 0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tick <= 0; slot <= 0; slotq <= 0; frame_in_oct <= 0;
            fill <= 0; cad <= 0; ring_cad_n <= 1'b1; ms <= 0;
        end else begin
            tick <= tick + 1'b1;
            if (tick == `TICK_SLOTQ) slotq <= slot;    // the '175: the address only ever moves
                                                       // while the strobe decoder is disabled
            if (tick == 3'd7) begin
                slot <= slot + 1'b1;                   // the '163, at the start of the next cell
                if (slot == 3'd7) begin                // ... and a frame has gone by
                    fill         <= ~fill;             // FILL is TX_CLK / 2
                    frame_in_oct <= frame_in_oct + 1'b1;
                    ms           <= (ms == MS_LAST) ? 7'd0 : ms + 1'b1;
                    cad          <= (cad == CAD_LAST) ? 19'd0 : cad + 1'b1;
                    ring_cad_n   <= ~(cad < CAD_ON);
                end
            end
        end
    end
endmodule
