// mf8_trunk_card -- an MF8 trunk card in a block of an exchange.
// network.md 1, mf8-spec.md 9-11, fabric.md 1.1.
//
// It makes six ports of its block into a tie trunk: a pair of ports, one in
// each exchange, back to back.  What a trunk port hears from its own fabric
// goes out on the line; what comes in off the line is what that port's "card"
// says.  network.md 1:
//
//     T's C_RX, A_RX  ------------------->  T's C_TX, A_TX   (the far end's)
//     T's C_TX, A_TX  <-------------------  T's C_RX, A_RX
//
// To the fabric it is a card like any other, and it decides nothing.  A call
// across it is the hotline rule of fabric.md 3.5 running through the pair
// untouched: the far line rings because its port sees E, and the caller hears
// ringback because the far port substitutes RBT into its own highway cell.
//
// Transmit is in THIS exchange's clock -- the card takes HCLK, LINE_HB, SLOT and
// TX_OCT from the clock card instead of owning a crystal (a jumper).  Receive is
// its own clock domain: mf8-backplane.md 2's crossing moves here, and is the
// two '174s that re-sample the six C bits on the local frame edge.  That is
// where the plesiochronous slip happens, once per channel per 156 ms at 100 ppm.
`timescale 1ns/1ps

module mf8_trunk_card #(
    parameter [15:0]  WORD = 16'b11111111_00_0_010_11,
        // secondary FF; primary: dd=00 (N), g=0, class trunk 010, type 11
    parameter integer T_A  = 128             // the A lead's RC and Schmitt: 2 ms in frames
)(
    input            clk,
    input            rst_n,

    // from the clock card, through the block
    input      [2:0] slot,
    input      [2:0] tick,
    input            frame_stb,
    input            tx_oct,
    input            fill,

    // the block's eight ports.  Channels are slots 1-3 and 5-7, where they are
    // on the wire; slots 0 and 4 are F and S and are ports of their own.
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
    // ---------------- transmit ------------------------------------------
    reg [7:0] c_lat, a_lat;
    reg [2:0] sfc;

    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin c_lat <= 8'd0; a_lat <= 8'd0; sfc <= 3'd0; end
        else if (frame_stb) begin
            c_lat <= port_c_rx;              // every card samples C_RX at the frame edge
            a_lat <= port_a_rx;
            sfc   <= tx_oct ? 3'd0 : sfc + 1'b1;
        end

    // The header: F is the word 11111110, zero only at state 7 -- one 3-input
    // gate off the superframe counter.  S is the guard at states 0 and 4, and
    // channel n's A bit at the state that mirrors its seat (mf8-spec.md 2, 3).
    wire f_bit = (sfc != 3'd7);
    wire s_bit = (sfc == 3'd0) ? 1'b0 :
                 (sfc == 3'd4) ? 1'b1 : a_lat[sfc];

    wire tx_bit = (slot == 3'd0) ? f_bit :
                  (slot == 3'd4) ? s_bit : c_lat[slot];

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

    // The crossing.  The six C bits are written by the recovered strobes and
    // re-sampled here on the local frame edge: two '174s, and one slip a
    // channel per 156 ms at 100 ppm (mf8-backplane.md 2, 7).
    reg [7:0] c_local;
    always @(posedge clk or negedge rst_n)
        if (!rst_n)          c_local <= 8'b1010_1010;
        else if (frame_stb)  c_local <= rx_c;

    // The A leads: an RC and a Schmitt each, as error filter and debounce
    // (mf8-spec.md 14).  Here, N frames of agreement.
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

    reg [15:0] wsr;
    reg [4:0]  wdiv;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            wsr <= WORD; wdiv <= 5'd0;
        end else begin
            if (frame_stb && tx_oct) begin
                wsr  <= WORD;
                wdiv <= 5'd0;
            end else if (wdiv == 5'd31) begin
                wsr  <= {1'b0, wsr[15:1]};
                wdiv <= 5'd0;
            end else
                wdiv <= wdiv + 1'b1;
        end
    // What the six ports' cards say.  Not locked: mute -- every channel reads
    // CVSD silence and on-hook, so calls on it release themselves and a caller
    // hears nothing (mf8-spec.md 13).  Slots 0 and 4 are not this card's.
    genvar g;
    generate for (g = 0; g < 8; g = g + 1) begin : chan
        if (g == 0 || g == 4) begin : header
            assign port_c_tx[g]  = fill;
            assign port_a_tx[g]  = 1'b0;
            assign port_word[g]  = 1'b0;
        end else begin : channel
            assign port_c_tx[g]  = mute ? fill : c_local[g];
            assign port_a_tx[g]  = mute ? 1'b0 : a_filt[g];
            // Two '165 daisy-chained send one 16-bit word to all six channels,
            // and send none while
            // the link is down -- so a dead trunk reads unequipped and is never
            // hunted (network.md 1).
            assign port_word[g]  = mute ? 1'b0 : wsr[0];
        end
    end endgenerate

endmodule
