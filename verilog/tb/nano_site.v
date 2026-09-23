// nano_site -- one exchange as nano-marker.md fits it: block 0 tones and the
// operator group at 04-07, block 1 uplink trunks, block 2 lines, the
// nanomarker with its register inside.
// No network unit, no console, no card-word decode, no write queue.
//
// The plant is deliberately gappy, because that is the hard case: an MF2 at 10
// (slots 10, 11) and a second MF2 at 14 (slots 14, 15), with 12, 13, 16 and 17
// open; two operators at 04 and 05 with 06 and 07 open.  An open slot reads
// M = 0 and BUSY = 0, exactly like a free trunk, so the hunt tells them apart
// by the card word instead: all zeros is none/OOS and an open pin floats to it
// (extensions.md 2.2).
`timescale 1ns/1ps

module nano_site #(
    parameter integer T_RISE  = 64,
    parameter integer T_FALL  = 2048,
    parameter integer RING_ON = 200,
    parameter integer RING_OFF = 400,
    parameter integer HIT     = 1,
    parameter integer ID      = 16,
    parameter integer CLR     = 32,
    parameter integer NODIG   = 500,
    parameter         LEAF    = 1'b1,
    parameter [2:0]   UP_BLK  = 3'd1,
    parameter         OP_EN   = 1'b1,
    parameter [2:0]   OP_BLK  = 3'd0,
    // operators 04, 05; MF2 at 10 (10, 11) and MF2 at 14 (14, 15); lines
    // 20, 21, 22.  06, 07, 12, 13, 16, 17 are open slots.
    parameter [63:0]  LINE_PORTS = 64'h0000_0000_0007_3330
)(
    input         clk,
    input         rst_n,
    input  [63:0] hook,
    input  [63:0] tx,
    output [63:0] rx,
    output [63:0] e,
    output        frame_stb,
    output        tick_1k,
    output        fill,
    output        ring_cad_n,
    output        dt_bit, ng_bit,
    output [63:0] port_busy,
    output        reg_busy,
    output        wr_stb,
    output [5:0]  wr_dst, wr_src,
    output        wr_bsy, wr_clm
);
    localparam PDT = 6'o01, PNG = 6'o03;
    localparam [63:0] PF = LINE_PORTS | 64'h0000_0000_0000_000A;
    localparam [7:0]  BF = 8'b0000_0111;

    wire [63:0] c_tx, a_tx, word, c_rx, a_rx;
    wire [2:0]  slotq, tick;
    wire        tx_oct, pb_busy, pb_word, sdata, sclk, wr;
    wire [7:0]  ha;
    wire        oct_stb = frame_stb & tx_oct;
    wire [2:0]  scan_port;

    exch_top #(.BLOCK_FITTED(BF), .PORT_FITTED(PF),
               .PORT_RINGS(LINE_PORTS),
               .RBT_IS_FILL(1'b1),
               .T_RISE(T_RISE), .T_FALL(T_FALL),
               .RING_ON(RING_ON), .RING_OFF(RING_OFF))
    u_exch (.clk(clk), .rst_n(rst_n),
            .c_tx(c_tx), .a_tx(a_tx), .word(word), .c_rx(c_rx), .a_rx(a_rx),
            .sdata(sdata), .sclk(sclk), .wr(wr),
            .con_n(1'b1), .scan_port(scan_port),
            .pb_busy(pb_busy), .pb_word(pb_word), .port_busy(port_busy),
            .hc(), .ha(ha),
            .slot(), .slotq(slotq), .tick(tick), .hclk(), .line_hb(), .tx_clk(),
            .frame_stb(frame_stb), .tx_oct(tx_oct), .rx_oct(),
            .fill(fill), .ring_cad_n(ring_cad_n), .tick_1k(tick_1k));

    source_card #(.SEED(16'hACE1)) u_dt (.clk(clk), .frame_stb(frame_stb),
        .tx_oct(tx_oct), .c_tx(c_tx[PDT]), .a_tx(a_tx[PDT]),
        .word_pin(word[PDT]), .ans_n());
    source_card #(.SEED(16'h1234)) u_ng (.clk(clk), .frame_stb(frame_stb),
        .tx_oct(tx_oct), .c_tx(c_tx[PNG]), .a_tx(a_tx[PNG]),
        .word_pin(word[PNG]), .ans_n());
    assign dt_bit = c_tx[PDT];
    assign ng_bit = c_tx[PNG];

    genvar p;
    generate for (p = 0; p < 64; p = p + 1) begin : line
        if (LINE_PORTS[p]) begin : fitted
            line_card u_c (.clk(clk), .frame_stb(frame_stb), .tx_oct(tx_oct),
                           .tx(tx[p]), .rx(rx[p]), .m(hook[p]), .e(e[p]),
                           .c_tx(c_tx[p]), .a_tx(a_tx[p]),
                           .c_rx(c_rx[p]), .a_rx(a_rx[p]),
                           .word_pin(word[p]), .ans_n());
        end else begin : absent
            assign rx[p] = 1'b0;
            assign e[p]  = 1'b0;
        end
    end endgenerate

    genvar q;
    generate for (q = 0; q < 64; q = q + 1)
        if (!LINE_PORTS[q] && q != PDT && q != PNG) begin : empty
            assign c_tx[q] = fill; assign a_tx[q] = 1'b0; assign word[q] = 1'b0;
        end
    endgenerate

    nano_marker #(.HIT(HIT), .ID(ID), .CLR(CLR), .NODIG(NODIG),
                  .DIALTONE(PDT), .NOGO(PNG),
                  .LEAF(LEAF), .UP_BLK(UP_BLK),
                  .OP_EN(OP_EN), .OP_BLK(OP_BLK))
    u_mk (.clk(clk), .rst_n(rst_n),
          .slotq(slotq), .tick(tick),
          .oct_stb(oct_stb), .tick_1k(tick_1k),
          .ha(ha), .pb_busy(pb_busy), .pb_word(pb_word),
          .sdata(sdata), .sclk(sclk), .wr(wr),
          .scan_port(scan_port),
          .reg_busy(reg_busy), .reg_gone(), .reg_nodig(), .reg_brk(),
          .reg_ndig(), .reg_digits(),
          .wr_stb(wr_stb), .wr_dst(wr_dst), .wr_src(wr_src),
          .wr_bsy(wr_bsy), .wr_clm(wr_clm));
endmodule
