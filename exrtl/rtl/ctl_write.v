// ctl_write -- the serialiser for cable B.  exch-mainboard.md 2.3.
//
// The marker's whole output is one sixteen-bit word, broadcast to every block
// at once, MSB first:
//
//   15    G        guard, always 1; ANDed into WR at every block
//   14    -        spare
//   13-8  DST      where to write: the block, then the port in it
//   7-0   SRC,BSY,CLM   what to write -- the port's '273 verbatim
//
// Both the marker and the operator's console drive one of these; the bus is
// multi-master and the word is the same either way.
//
// `strobe` low shifts the word and does NOT pulse WR.  That is how the marker
// steers the PROBE: /BLK is the block's own '138 decoding DST[5:3], so the
// block that answers PB is the block the shift register names, and the marker
// keeps a word there naming the block its scanner is visiting.  Nothing reads
// the outputs until WR, so a word shifted only to point the probe is harmless.
//
// WR is pulsed in the middle of an SCLK half-period, which is 2.3.2's one rule.
`timescale 1ns/1ps

module ctl_write #(
    parameter integer DIV = 8          // master clocks an SCLK period: 512 kHz
)(
    input            clk,
    input            rst_n,
    input            req,              // one pulse: send this word
    input            strobe,           // pulse WR at the end (0 = point the probe only)
    input      [5:0] dst,
    input      [5:0] src,
    input            bsy,
    input            clm,
    output reg       busy,
    output reg       sdata,
    output reg       sclk,
    output reg       wr
);
    localparam IDLE = 2'd0, SHIFT = 2'd1, STROBE = 2'd2;
    localparam [2:0] DLAST = DIV[2:0] - 3'd1;      // the last master clock of a bit

    reg [1:0]  st;
    reg [15:0] w;
    reg [4:0]  n;
    reg [2:0]  d;
    reg        do_wr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= IDLE; busy <= 0; sdata <= 0; sclk <= 0; wr <= 0;
            w <= 0; n <= 0; d <= 0; do_wr <= 0;
        end else case (st)
        IDLE: begin
            sclk <= 1'b0; wr <= 1'b0;
            if (req) begin
                w     <= {1'b1, 1'b0, dst, src, bsy, clm};
                sdata <= 1'b1;                       // G, the MSB, goes out first
                n     <= 5'd16; d <= 3'd0;
                do_wr <= strobe; busy <= 1'b1; st <= SHIFT;
            end else busy <= 1'b0;
        end
        SHIFT: begin
            d <= d + 1'b1;
            if (d == 3'd3) sclk <= 1'b1;             // the shifting edge, mid-bit
            if (d == DLAST) begin
                sclk  <= 1'b0;
                w     <= {w[14:0], 1'b0};
                sdata <= w[14];
                n     <= n - 1'b1;
                if (n == 5'd1) begin d <= 3'd0; st <= do_wr ? STROBE : IDLE; end
            end
        end
        STROBE: begin                                 // WR clear of every SCLK edge
            d <= d + 1'b1;
            if (d == 3'd1) wr <= 1'b1;
            if (d == 3'd5) begin wr <= 1'b0; st <= IDLE; end
        end
        default: st <= IDLE;
        endcase
    end
endmodule
