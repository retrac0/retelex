// mvp_site -- one whole exchange as mvp.md 1 fits it: the exchange logic,
// two line cards and two subscribers on the simplified interface.  It carries
// its own checker because it has its own crystal, and two sites do not share a
// frame edge.
`timescale 1ns/1ps

module mvp_site #(
    parameter integer T_RISE = 16, T_FALL = 256,
    parameter integer RING_ON = 200, RING_OFF = 400
)(
    input             clk,
    input             rst_n,
    // the console, on cable B (serial)
    input             sdata,
    input             sclk,
    input             wr,
    // the two subscribers
    input             hook20,
    input             hook21,
    // what to check this instant
    input      [2:0]  mode,
    output reg [31:0] errs = 0,
    output reg [31:0] chk  = 0,
    output            frame_stb,
    output            ring_cad_n
);
    localparam P20 = 6'o20, P21 = 6'o21;

    wire [63:0] c_tx, a_tx, word, c_rx, a_rx;
    wire        fill, tx_oct;
    reg         tx20 = 0, tx21 = 0;
    wire        rx20, rx21, e20, e21;
    reg         fill_d = 0;

    exch_top #(.BLOCK_FITTED(8'b0000_0100),
               .PORT_FITTED(64'h0000_0000_0003_0000),
               .RBT_IS_FILL(1'b1),
               .T_RISE(T_RISE), .T_FALL(T_FALL),
               .RING_ON(RING_ON), .RING_OFF(RING_OFF))
    u_exch (.clk(clk), .rst_n(rst_n),
            .c_tx(c_tx), .a_tx(a_tx), .word(word), .c_rx(c_rx), .a_rx(a_rx),
            .sdata(sdata), .sclk(sclk), .wr(wr),
            .con_n(1'b1), .scan_port(3'd0),
            .pb_busy(), .pb_word(), .port_busy(), .hc(), .ha(),
            .slot(), .slotq(), .hclk(), .line_hb(), .tx_clk(),
            .frame_stb(frame_stb), .tx_oct(tx_oct), .rx_oct(),
            .fill(fill), .ring_cad_n(ring_cad_n), .tick_1k());

    // Two plain line cards, in slots 0 and 1 of block 2.
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

    // Every slot that holds no card: C pulled to FILL, A and the word to ground.
    genvar q;
    generate for (q = 0; q < 64; q = q + 1)
        if (q != P20 && q != P21) begin : empty
            assign c_tx[q] = fill; assign a_tx[q] = 1'b0; assign word[q] = 1'b0;
        end
    endgenerate

    always @(posedge clk) if (frame_stb) begin
        case (mode)
        1: begin  // one subscriber being rung: E in cadence, the caller hears RBT
               if (e21   !== ~ring_cad_n) errs = errs + 1;
               if (rx20  !== fill_d)      errs = errs + 1;  chk = chk + 2;
           end
        2: begin  // answered: speech both ways, E steady at both ends
               if (rx20 !== tx21) errs = errs + 1;
               if (rx21 !== tx20) errs = errs + 1;
               if (e20  !== 1'b1) errs = errs + 1;
               if (e21  !== 1'b1) errs = errs + 1;          chk = chk + 4;
           end
        3: begin  // released: both latches cleared, so both listen to port 00
               if (rx20 !== fill_d) errs = errs + 1;
               if (rx21 !== fill_d) errs = errs + 1;
               if (e20  !== 1'b0)   errs = errs + 1;
               if (e21  !== 1'b0)   errs = errs + 1;        chk = chk + 4;
           end
        endcase
        fill_d <= fill;
        if (hook20) tx20 <= $random;
        if (hook21) tx21 <= $random;
    end
endmodule
