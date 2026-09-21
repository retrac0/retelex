// mf8_trunk_card -- the MF8 exchange unit in a block.
// network.md 1, mf8-spec.md 9-11, mf8-unit.md 5, fabric.md 1.1.
//
// It occupies one block and appears as eight cards on that block's T face.
// The block's highway is this group's eight channels after conversion: the
// unit drives C_TX[n]/A_TX[n] at 64 kHz, and the block's '151 still makes
// HC[h]/HA[h] as eight slots of 512 kbps NRZ.  The MF8 line is a different
// stream -- 16 bits at 1024 kbps, F at 0, S at 8, eight C and six overhead
// (mf8-unit.md 4.2).  SLOT is the highway cell.  It is not the line mux.
//
//     T's C_RX, A_RX  ------------------->  line (16-bit mux, F/S/P/R/K)
//     T's C_TX, A_TX  <-------------------  line (16-bit demux, then hold)
//
// To the fabric it is eight cards, and it decides nothing.  A call across it
// is the hotline rule of fabric.md 3.5 running through a pair untouched.
//
// Transmit is in the unit's own 4.096 MHz (Q1 -> HB 2.048 MHz).  This model
// shares the exchange crystal, which is the same divide.  Receive is its own
// clock domain: mf8-backplane.md 2's crossing is the two '174s that re-sample
// the eight C bits on the local frame edge.  That is where the plesiochronous
// slip happens, once per channel per 156 ms at 100 ppm.
`timescale 1ns/1ps

module mf8_trunk_card #(
    parameter [7:0]   WORD = 8'b0001_0111,   // class trunk 101, type 11, dir N
    parameter integer T_A  = 128             // the A lead's RC and Schmitt: 2 ms in frames
)(
    input            clk,
    input            rst_n,

    // from the clock card, through the block -- payload domain, not the line
    input      [2:0] slot,
    input      [2:0] tick,
    input            frame_stb,
    input            tx_oct,
    input            fill,

    // the block's eight ports.  Slot n is channel Cn.  All eight are payload.
    input      [7:0] port_c_rx,
    input      [7:0] port_a_rx,
    output     [7:0] port_c_tx,
    output     [7:0] port_a_tx,
    output     [7:0] port_word,

    // the line
    output           line_out,
    input            line_in,

    output           locked,
    output           mute,
    output           cd
);
    // ---------------- transmit: 64 kHz hold, 16-bit line mux ---------------
    // Two line bits sit in each highway cell (SLOT, 512 kHz).  The line bit
    // address is {slot, tick[2]}: F, C0, C1, C2, C3, C4, C5, C6, S, C7, P, R,
    // K0..K3.  C0..C6 are bits 1..7; C7 is bit 9, not bit 8 -- S is opposite F.
    // That packing is the conversion.  The highway never sees F or S.
    reg [7:0] c_lat, a_lat;
    reg [3:0] sfc;

    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin c_lat <= 8'd0; a_lat <= 8'd0; sfc <= 4'd0; end
        else if (frame_stb) begin
            c_lat <= port_c_rx;              // every card samples C_RX at the frame edge
            a_lat <= port_a_rx;
            sfc   <= sfc + 1'b1;             // 16-frame superframe; TX_OCT is the word, not this
        end

    wire [3:0] lbit  = {slot, tick[2]};
    wire       f_bit = (sfc != 4'd15);       // 1111111111111110
    wire       s_bit = (sfc == 4'd0) ? 1'b0 :
                       (sfc == 4'd8) ? 1'b1 :
                       (sfc == 4'd9) ? a_lat[7] :
                       (sfc >= 4'd1 && sfc <= 4'd7) ? a_lat[sfc - 1] :
                       1'b0;                 // states 10-15: spare (SS0)
    wire       r_bit = mute;                 // RAI: 1 while this end is muted
    wire       p_bit = ^{f_bit, c_lat, s_bit, r_bit};   // even parity of the other 15; K = 0

    wire tx_bit = (lbit == 4'd0)  ? f_bit :
                  (lbit == 4'd1)  ? c_lat[0] :
                  (lbit == 4'd2)  ? c_lat[1] :
                  (lbit == 4'd3)  ? c_lat[2] :
                  (lbit == 4'd4)  ? c_lat[3] :
                  (lbit == 4'd5)  ? c_lat[4] :
                  (lbit == 4'd6)  ? c_lat[5] :
                  (lbit == 4'd7)  ? c_lat[6] :
                  (lbit == 4'd8)  ? s_bit :
                  (lbit == 4'd9)  ? c_lat[7] :
                  (lbit == 4'd10) ? p_bit :
                  (lbit == 4'd11) ? r_bit :
                  1'b0;                      // K0-K3

    mf8_encoder u_enc (.clk(clk), .rst_n(rst_n), .tick(tick),
                       .bit_in(tx_bit), .line(line_out));

    // ---------------- receive -------------------------------------------
    wire       bit_stb, bit_val;
    wire [7:0] rx_c, rx_a;

    mf8_decoder u_dec (.clk(clk), .rst_n(rst_n), .line(line_in),
                       .bit_stb(bit_stb), .bit_val(bit_val), .cd(cd));

    mf8_framer u_frm (.clk(clk), .rst_n(rst_n),
                      .bit_stb(bit_stb), .bit_val(bit_val), .cd(cd),
                      .locked(locked), .rx_c(rx_c), .rx_a(rx_a));

    assign mute = ~locked;

    // The crossing.  The eight C bits are written by the recovered strobes and
    // re-sampled here on the local frame edge: two '174s, and one slip a
    // channel per 156 ms at 100 ppm (mf8-backplane.md 2, 7).
    reg [7:0] c_local;
    always @(posedge clk or negedge rst_n)
        if (!rst_n)          c_local <= 8'b1010_1010;
        else if (frame_stb)  c_local <= rx_c;

    // The A leads: an RC and a Schmitt each, as error filter and debounce
    // (mf8-spec.md 14).  Here, N frames of agreement.  A arrives at 4 kHz
    // (one bit a channel a 16-frame superframe); the filter is still in frames.
    reg [7:0]  a_filt;
    reg [7:0]  a_cnt [0:7];
    integer    k;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_filt <= 8'd0;
            for (k = 0; k < 8; k = k + 1) a_cnt[k] <= 8'd0;
        end else if (frame_stb) begin
            for (k = 0; k < 8; k = k + 1) begin
                if (rx_a[k] == a_filt[k])        a_cnt[k] <= 8'd0;
                else if (a_cnt[k] >= T_A[7:0]-1) begin a_cnt[k] <= 8'd0; a_filt[k] <= rx_a[k]; end
                else                             a_cnt[k] <= a_cnt[k] + 1'b1;
            end
        end
    end

    // The word is still eight bits on TX_OCT, independent of the 16-state
    // superframe.  One '165 to all eight appearances; none while the link is
    // down -- a dead trunk reads unequipped and is never hunted (network.md 1).
    reg [7:0] wsr;
    always @(posedge clk or negedge rst_n)
        if (!rst_n)         wsr <= WORD;
        else if (frame_stb) wsr <= tx_oct ? WORD : {1'b0, wsr[7:1]};

    genvar g;
    generate for (g = 0; g < 8; g = g + 1) begin : chan
        assign port_c_tx[g]  = mute ? fill : c_local[g];
        assign port_a_tx[g]  = mute ? 1'b0 : a_filt[g];
        assign port_word[g]  = mute ? 1'b0 : wsr[0];
    end endgenerate

endmodule
