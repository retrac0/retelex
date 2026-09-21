// mini_site -- one exchange as mini-marker.md fits it: block 0 tones, block 2
// lines, the mini-marker with its register inside.  No network, no console,
// no card-word decode.
`timescale 1ns/1ps

module mini_site #(
    parameter integer T_RISE  = 64,
    parameter integer T_FALL  = 2048,
    parameter integer RING_ON = 200,
    parameter integer RING_OFF = 400,
    parameter integer HIT     = 1,
    parameter integer ID      = 16,
    parameter integer CLR     = 32,
    parameter integer NODIG   = 500
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
    output        wq_ovf,
    output        wr_stb,
    output [5:0]  wr_dst, wr_src,
    output        wr_bsy, wr_clm
);
    localparam PDT = 6'o01, PNG = 6'o03;
    // lines 20, 21, 22; tones 01 and 03
    localparam [63:0] LINE_PORTS = 64'h0000_0000_0007_0000;
    localparam [63:0] PF = LINE_PORTS | 64'h0000_0000_0000_000A;
    localparam [7:0]  BF = 8'b0000_0101;

    wire [63:0] c_tx, a_tx, word, c_rx, a_rx;
    wire [2:0]  slotq, tick;
    wire        tx_oct, pb_busy, sdata, sclk, wr;
    wire [7:0]  ha;
    wire        oct_stb = frame_stb & tx_oct;

    exch_top #(.BLOCK_FITTED(BF), .PORT_FITTED(PF),
               .PORT_RINGS(LINE_PORTS),
               .RBT_IS_FILL(1'b1),
               .T_RISE(T_RISE), .T_FALL(T_FALL),
               .RING_ON(RING_ON), .RING_OFF(RING_OFF))
    u_exch (.clk(clk), .rst_n(rst_n),
            .c_tx(c_tx), .a_tx(a_tx), .word(word), .c_rx(c_rx), .a_rx(a_rx),
            .sdata(sdata), .sclk(sclk), .wr(wr),
            .pb_busy(pb_busy), .pb_word(), .port_busy(port_busy),
            .hc(), .ha(ha),
            .slot(), .slotq(slotq), .tick(tick), .hclk(), .hb(), .tx_clk(),
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

    mini_marker #(.HIT(HIT), .ID(ID), .CLR(CLR), .NODIG(NODIG),
                  .DIALTONE(PDT), .NOGO(PNG))
    u_mk (.clk(clk), .rst_n(rst_n),
          .slotq(slotq), .tick(tick), .frame_stb(frame_stb),
          .oct_stb(oct_stb), .tick_1k(tick_1k),
          .ha(ha), .pb_busy(pb_busy),
          .sdata(sdata), .sclk(sclk), .wr(wr),
          .reg_busy(reg_busy), .wq_ovf(wq_ovf),
          .wr_stb(wr_stb), .wr_dst(wr_dst), .wr_src(wr_src),
          .wr_bsy(wr_bsy), .wr_clm(wr_clm));
endmodule
