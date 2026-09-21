// trunk_site -- one exchange with a trunk block and a block of lines.
//
//   block 0   an MF8 trunk card: six tie-trunk channels at ports 01-03, 05-07,
//             where they are on the wire.  Ports 00 and 04 are F and S on the
//             line and are not fitted here -- 00 is the silence a cleared latch
//             listens to, and 04 would be the operator.
//   block 2   two line cards, ports 20 and 21.
//
// Everything else absent, as mvp.md has it.  No marker: the console patches
// latches by hand, which is mvp.md 6.3's manual board, now with a trunk in
// the middle of it.
`timescale 1ns/1ps

module trunk_site #(
    parameter integer T_RISE = 16, T_FALL = 256,
    parameter integer RING_ON = 200, RING_OFF = 400,
    parameter integer T_A = 4
)(
    input         clk,
    input         rst_n,
    // the console, on cable B (serial)
    input         sdata,
    input         sclk,
    input         wr,
    // the two subscribers, on the simplified interface
    input         hook20, hook21,
    input         tx20,   tx21,
    output        rx20,   rx21,
    output        e20,    e21,
    // the MF8 line
    input         line_in,
    output        line_out,
    output        locked, cd,
    // for the testbench
    output        frame_stb,
    output        fill,
    output        ring_cad_n
);
    localparam P20 = 6'o20, P21 = 6'o21;

    wire [63:0] c_tx, a_tx, word, c_rx, a_rx;
    wire [2:0]  slot, tick;
    wire        tx_oct;
    wire [7:0]  tk_c_tx, tk_a_tx, tk_word;

    exch_top #(.BLOCK_FITTED(8'b0000_0101),                 // blocks 0 and 2
               .PORT_FITTED (64'h0000_0000_0003_00EE),      // 01-03, 05-07, 20, 21
               .PORT_RINGS  (64'hFFFF_FFFF_FFFF_FF00),      // trunks tie /ANS low
               .RBT_IS_FILL(1'b1),
               .T_RISE(T_RISE), .T_FALL(T_FALL),
               .RING_ON(RING_ON), .RING_OFF(RING_OFF))
    u_exch (.clk(clk), .rst_n(rst_n),
            .c_tx(c_tx), .a_tx(a_tx), .word(word), .c_rx(c_rx), .a_rx(a_rx),
            .sdata(sdata), .sclk(sclk), .wr(wr),
            .pb_busy(), .pb_word(), .port_busy(), .hc(), .ha(),
            .slot(slot), .slotq(), .tick(tick), .hclk(), .hb(), .tx_clk(),
            .frame_stb(frame_stb), .tx_oct(tx_oct), .rx_oct(),
            .fill(fill), .ring_cad_n(ring_cad_n), .tick_1k());

    // The trunk card taps its own block's ports and drives their card pins.
    mf8_trunk_card #(.T_A(T_A)) u_trunk (
        .clk(clk), .rst_n(rst_n),
        .slot(slot), .tick(tick), .frame_stb(frame_stb), .tx_oct(tx_oct), .fill(fill),
        .port_c_rx(c_rx[7:0]), .port_a_rx(a_rx[7:0]),
        .port_c_tx(tk_c_tx), .port_a_tx(tk_a_tx), .port_word(tk_word),
        .line_out(line_out), .line_in(line_in),
        .locked(locked), .mute(), .cd(cd));

    assign c_tx[7:0] = tk_c_tx;
    assign a_tx[7:0] = tk_a_tx;
    assign word[7:0] = tk_word;

    line_card u_c20 (.clk(clk), .frame_stb(frame_stb), .tx_oct(tx_oct),
                     .tx(tx20), .rx(rx20), .m(hook20), .e(e20),
                     .c_tx(c_tx[P20]), .a_tx(a_tx[P20]),
                     .c_rx(c_rx[P20]), .a_rx(a_rx[P20]),
                     .word_pin(word[P20]), .ans_n());
    line_card u_c21 (.clk(clk), .frame_stb(frame_stb), .tx_oct(tx_oct),
                     .tx(tx21), .rx(rx21), .m(hook21), .e(e21),
                     .c_tx(c_tx[P21]), .a_tx(a_tx[P21]),
                     .c_rx(c_rx[P21]), .a_rx(a_rx[P21]),
                     .word_pin(word[P21]), .ans_n());

    genvar q;
    generate for (q = 8; q < 64; q = q + 1)
        if (q != P20 && q != P21) begin : empty
            assign c_tx[q] = fill; assign a_tx[q] = 1'b0; assign word[q] = 1'b0;
        end
    endgenerate
endmodule
