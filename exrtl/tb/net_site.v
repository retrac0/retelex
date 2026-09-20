// net_site -- a whole exchange: fabric, trunk, tones, marker, register, seeker.
//
//   block 0   an MF8 trunk card: six tie-trunk channels at 01-03, 05-07
//   block 1   dial tone at 10, cannot-complete at 14 (exch-protocol.md 5)
//   block 2   two line cards, 20 and 21
//   common    one marker, one register, one monitor on the trunk block
//
// Which is mvp-ex.md 1 plus a network card's worth of sequence.  The exchange's
// own code e b is two jumpers on the marker and the monitor, and is the only
// thing in the whole exchange that says who it is.
`timescale 1ns/1ps

module net_site #(
    parameter [2:0]   OWN_E = 3'd2,
    parameter [2:0]   OWN_B = 3'd2,
    parameter integer T_RISE = 64, T_FALL = 2048,
    parameter integer RING_ON = 200, RING_OFF = 400,
    parameter integer T_A = 4,
    parameter integer HIT = 1, ID = 16, CLR = 32,
    parameter integer T_GUARD = 16, T_CLAIM = 250
)(
    input         clk,
    input         rst_n,
    input         hook20, hook21,
    input         tx20, tx21,
    output        rx20, rx21,
    output        e20, e21,
    input         line_in,
    output        line_out,
    output        locked,
    output        frame_stb,
    output        ring_cad_n,
    output        dt_bit, ng_bit,      // what the two tone cards are sending
    output        mon_held,
    output        got_claim      // the origin's trunk claimed
);
    localparam P20 = 6'o20, P21 = 6'o21, PDT = 6'o10, PNG = 6'o14;

    wire [63:0] c_tx, a_tx, word, c_rx, a_rx;
    wire [2:0]  slot, slotq, tick;
    wire        tx_oct, tick_1k, fill, pb_busy, pb_word;
    wire [7:0]  ha;
    wire        sdata, sclk, wr;
    wire [7:0]  tk_c_tx, tk_a_tx, tk_word;
    wire        oct_stb = frame_stb & tx_oct;

    exch_top #(.BLOCK_FITTED(8'b0000_0111),                 // blocks 0, 1, 2
               .PORT_FITTED (64'h0000_0000_0003_11EE),      // trunks, tones, lines
               .PORT_RINGS  (64'hFFFF_FFFF_FFFF_0000),      // only the lines ring
               .RBT_IS_FILL(1'b1),
               .T_RISE(T_RISE), .T_FALL(T_FALL),
               .RING_ON(RING_ON), .RING_OFF(RING_OFF))
    u_exch (.clk(clk), .rst_n(rst_n),
            .c_tx(c_tx), .a_tx(a_tx), .word(word), .c_rx(c_rx), .a_rx(a_rx),
            .sdata(sdata), .sclk(sclk), .wr(wr),
            .pb_busy(pb_busy), .pb_word(pb_word), .hc(), .ha(ha),
            .slot(slot), .slotq(slotq), .tick(tick), .hclk(), .hb(), .tx_clk(),
            .frame_stb(frame_stb), .tx_oct(tx_oct), .rx_oct(),
            .fill(fill), .ring_cad_n(ring_cad_n), .tick_1k(tick_1k));

    mf8_trunk_card #(.T_A(T_A)) u_trunk (
        .clk(clk), .rst_n(rst_n),
        .slot(slot), .tick(tick), .frame_stb(frame_stb), .tx_oct(tx_oct), .fill(fill),
        .port_c_rx(c_rx[7:0]), .port_a_rx(a_rx[7:0]),
        .port_c_tx(tk_c_tx), .port_a_tx(tk_a_tx), .port_word(tk_word),
        .line_out(line_out), .line_in(line_in),
        .locked(locked), .mute(), .cd());

    assign c_tx[7:0] = tk_c_tx;
    assign a_tx[7:0] = tk_a_tx;
    assign word[7:0] = tk_word;

    source_card #(.SEED(16'hACE1)) u_dt (.clk(clk), .frame_stb(frame_stb), .tx_oct(tx_oct),
        .c_tx(c_tx[PDT]), .a_tx(a_tx[PDT]), .word_pin(word[PDT]), .ans_n());
    source_card #(.SEED(16'h1234)) u_ng (.clk(clk), .frame_stb(frame_stb), .tx_oct(tx_oct),
        .c_tx(c_tx[PNG]), .a_tx(a_tx[PNG]), .word_pin(word[PNG]), .ans_n());
    assign dt_bit = c_tx[PDT];
    assign ng_bit = c_tx[PNG];

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
        if (q != P20 && q != P21 && q != PDT && q != PNG) begin : empty
            assign c_tx[q] = fill; assign a_tx[q] = 1'b0; assign word[q] = 1'b0;
        end
    endgenerate

    // ---- common control -------------------------------------------------
    wire       r_busy, r_stb, r_gone, r_brk, r_attach, r_release;
    wire [3:0] r_cnt;
    wire [5:0] r_port;
    wire       mclaim;
    wire [5:0] mport;

    pulse_reg #(.HIT(HIT), .ID(ID), .CLR(CLR), .NODIG(2000)) u_reg (
        .clk(clk), .rst_n(rst_n), .slotq(slotq), .tick(tick), .tick_1k(tick_1k),
        .ha(ha), .attach(r_attach), .attach_port(r_port), .release_it(r_release),
        .busy(r_busy), .port(), .cnt(r_cnt), .dig_stb(r_stb), .gone(r_gone), .brk(r_brk));

    monitor #(.OWN_E(OWN_E), .OWN_B(OWN_B), .BLOCK(3'd0),
              .HIT(HIT), .ID(ID), .CLR(CLR)) u_mon (
        .clk(clk), .rst_n(rst_n), .oct_stb(oct_stb), .tick_1k(tick_1k),
        .m(tk_a_tx), .chan_mask(8'b1110_1110),
        .claim(mclaim), .claim_port(mport), .held(mon_held));

    marker #(.OWN_E(OWN_E), .OWN_B(OWN_B), .DIALTONE(PDT), .NOGO(PNG),
             .HAS_NET(1'b1), .T_GUARD(T_GUARD), .T_CLAIM(T_CLAIM)) u_mk (
        .clk(clk), .rst_n(rst_n),
        .slotq(slotq), .tick(tick), .frame_stb(frame_stb),
        .oct_stb(oct_stb), .tick_1k(tick_1k),
        .ha(ha), .pb_busy(pb_busy), .pb_word(pb_word),
        .sdata(sdata), .sclk(sclk), .wr(wr),
        .reg_attach(r_attach), .reg_port(r_port), .reg_busy(r_busy),
        .reg_cnt(r_cnt), .reg_dig_stb(r_stb), .reg_gone(r_gone), .reg_brk(r_brk),
        .reg_release(r_release),
        .mon_claim(mclaim), .mon_port(mport));

    assign got_claim = u_mk.claimed;
endmodule
