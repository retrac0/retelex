// ctl_write -- the cable B serialiser.  Two 74HC165 and a little sequencing.
//
// The marker's whole output is ONE SIXTEEN-BIT WORD ON ONE WIRE, broadcast to
// every block at once.  Every block shifts it into its own two '164s; the one
// whose shunt column matches DST[5:3] answers WR.  Nothing reads a block's
// shift register until WR, which is why there is no output latch and no '595,
// and why a word may be shifted with WR suppressed purely to steer /BLK.
//
//   bit 15  G      guard, always 1.  ANDed into WR at every block, so a word
//                  without it cannot write -- but it still shifts and still
//                  pulses WR, which is the EVENT WORD a listener can count
//   bit 14  -      spare; parity over 13-0 if a bench ever asks
//   13-11   DST[5:3]   the block, into its own '138
//   10-8    DST[2:0]   the port in it, into the write decoder
//   7-2     SRC[5:0]   the source port, as dialled
//   1       BSY
//   0       CLM    a claimed trunk's backward A
//
// BITS 7-0 ARE THE PORT'S '273 VERBATIM.  That is why sixteen was the number
// to aim at, and it is why `PW = 6 and a 16-bit word are one decision.
//
//   mainboard.md 2.3, 2.3.1, 2.3.2
`timescale 1ns/1ps
`include "exch.vh"

module ctl_write #(
    // Master clocks a bit-time.  4.096 MHz / 32 = 128 kHz, which is SCLK
    // (clocks.md 1) and the same rate as the card option word's shift clock.
    parameter integer DIV = 32
)(
    input                  clk,
    input                  rst_n,

    input                  req,      // one tick: send this word
    input                  strobe,   // 1 = pulse WR at the end; 0 = shift only
    input                  g,        // the guard bit.  0 makes it an event word
    input      [`PW-1:0]   dst,
    input      [`PW-1:0]   src,
    input                  bsy,
    input                  clm,

    output reg             busy,     // a word is in flight
    output                 sdata,    // the '165's QH: the top stage, continuously
    output reg             sclk,
    output reg             wr
);
    localparam [1:0] IDLE = 2'd0, SHIFT = 2'd1, STROBE = 2'd2;

    // Where inside a bit-time SCLK moves.  High for the middle half, so the
    // rising edge a block shifts on is a quarter of a bit-time after SDATA
    // settled and three quarters before it moves again: 1.95 us either side
    // at 128 kHz, against 18 ns of cable skew (mainboard.md 5.2).
    localparam integer T_RISE = DIV / 4;
    localparam integer T_FALL = (3 * DIV) / 4;
    localparam integer T_LAST = DIV - 1;

    reg [1:0]          st;
    reg [`CWW-1:0]     w;
    reg [4:0]          n;        // bits left
    reg [7:0]          d;        // position inside the bit-time
    reg                do_wr;

    // A '165 presents its top stage on QH the moment it is loaded, so SDATA
    // is the register itself and not a copy of it.
    assign sdata = w[`CWW-1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= IDLE; w <= {`CWW{1'b0}}; n <= 5'd0; d <= 8'd0;
            do_wr <= 1'b0; busy <= 1'b0; sclk <= 1'b0; wr <= 1'b0;
        end else begin
            case (st)
            IDLE: begin
                sclk <= 1'b0; wr <= 1'b0;
                if (req) begin
                    // the '165s take the word in parallel; QH is bit 15 at once
                    w     <= {g, 1'b0, dst, src, bsy, clm};
                    n     <= 5'd16;
                    d     <= 8'd0;
                    do_wr <= strobe;
                    busy  <= 1'b1;
                    st    <= SHIFT;
                end else busy <= 1'b0;
            end

            SHIFT: begin
                if (d == T_RISE[7:0]) sclk <= 1'b1;
                if (d == T_FALL[7:0]) sclk <= 1'b0;
                if (d == T_LAST[7:0]) begin
                    d     <= 8'd0;
                    w     <= {w[`CWW-2:0], 1'b0};
                    n     <= n - 1'b1;
                    if (n == 5'd1) st <= do_wr ? STROBE : IDLE;
                end else d <= d + 1'b1;
            end

            STROBE: begin
                // SCLK is idle through this bit-time, so WR meets
                // mainboard.md 2.3.2's rule by construction: it lands nowhere
                // near an edge.  On the jumper that free-runs SCLK off
                // HCLK/4 the marker must place it in the middle of a half
                // period instead, which is where this puts it anyway.
                if (d == T_RISE[7:0]) wr <= 1'b1;
                if (d == T_FALL[7:0]) wr <= 1'b0;
                if (d == T_LAST[7:0]) begin d <= 8'd0; st <= IDLE; end
                else d <= d + 1'b1;
            end

            default: st <= IDLE;
            endcase
        end
    end
endmodule
