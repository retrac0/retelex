// net_site -- a whole exchange: fabric, trunks, tones, marker, register, seeker.
//
//   block 0   an MF8 trunk group, six channels at 01-03, 05-07, facing DIR0
//   block 1   dial tone at 10 and cannot-complete at 14, and -- when HAS_TRUNK1
//             -- a SECOND trunk group at 11-13, 15-17 facing DIR1.  That is
//             exactly how exch-protocol.md 5 lays block 1 out: the two tones sit
//             at slots 0 and 4, which are F and S on the wire, and the six
//             channels sit where they are on the wire either side of them
//   block 2   two line cards, 20 and 21
//   common    one marker, one register, and a monitor on each trunk block
//
// An exchange with one direction is an end of a chain; with two it is a transit,
// and its marker forwards a seizure from one into the other.
`timescale 1ns/1ps

module net_site #(
    parameter [2:0]   OWN_E = 3'd2,
    parameter [2:0]   OWN_B = 3'd2,
    // Each trunk group's direction, glare bit and strap, as the card's word
    // carries them (ex-extensions.md 2.2).  N=0 S=1 E=2 W=3.
    parameter [1:0]   DIR0 = 2'd2,
    parameter         G0 = 1'b0,
    parameter         N0 = 1'b0,
    parameter         HAS_TRUNK1 = 1'b0,
    parameter [1:0]   DIR1 = 2'd3,
    parameter         G1 = 1'b0,
    parameter         N1 = 1'b0,
    parameter integer T_RISE = 64, T_FALL = 2048,
    parameter integer RING_ON = 200, RING_OFF = 400,
    parameter integer T_A = 4,
    parameter integer HIT = 1, ID = 16, CLR = 32,
    parameter integer T_GUARD = 16, T_CLAIM = 250,
    parameter integer NMON = 2                   // cells in each block's pool (4)
)(
    input         clk,
    input         rst_n,
    input         hook20, hook21,
    input         tx20, tx21,
    output        rx20, rx21,
    output        e20, e21,
    input         line_in,  output line_out,  output locked,
    input         line_in1, output line_out1, output locked1,
    output        frame_stb,
    output        ring_cad_n,
    output        dt_bit, ng_bit,
    output        mon_held,
    output        got_claim,
    output [3:0]  dirs_held      // which directions this call still holds a trunk in
);
    localparam P20 = 6'o20, P21 = 6'o21, PDT = 6'o10, PNG = 6'o14;
    localparam [7:0]  WORD0 = {1'b0, N0, G0, DIR0, 3'b101};   // class 101: tie trunk
    localparam [7:0]  WORD1 = {1'b0, N1, G1, DIR1, 3'b101};
    localparam [63:0] PF = HAS_TRUNK1 ? 64'h0000_0000_0003_FFEE
                                      : 64'h0000_0000_0003_11EE;

    wire [63:0] c_tx, a_tx, word, c_rx, a_rx;
    wire [2:0]  slot, slotq, tick;
    wire        tx_oct, tick_1k, fill, pb_busy, pb_word;
    wire [7:0]  ha;
    wire [63:0] pbusy;
    wire        sdata, sclk, wr;
    wire [7:0]  tk_c_tx, tk_a_tx, tk_word;
    wire [7:0]  t1_c_tx, t1_a_tx, t1_word;
    wire        oct_stb = frame_stb & tx_oct;

    exch_top #(.BLOCK_FITTED(8'b0000_0111),
               .PORT_FITTED (PF),
               .PORT_RINGS  (64'hFFFF_FFFF_FFFF_0000),   // only the lines ring
               .RBT_IS_FILL(1'b1),
               .T_RISE(T_RISE), .T_FALL(T_FALL),
               .RING_ON(RING_ON), .RING_OFF(RING_OFF))
    u_exch (.clk(clk), .rst_n(rst_n),
            .c_tx(c_tx), .a_tx(a_tx), .word(word), .c_rx(c_rx), .a_rx(a_rx),
            .sdata(sdata), .sclk(sclk), .wr(wr),
            .pb_busy(pb_busy), .pb_word(pb_word), .port_busy(pbusy),
            .hc(), .ha(ha),
            .slot(slot), .slotq(slotq), .tick(tick), .hclk(), .hb(), .tx_clk(),
            .frame_stb(frame_stb), .tx_oct(tx_oct), .rx_oct(),
            .fill(fill), .ring_cad_n(ring_cad_n), .tick_1k(tick_1k));

    // ---- block 0: the first direction -----------------------------------
    mf8_trunk_card #(.T_A(T_A), .WORD(WORD0)) u_trunk (
        .clk(clk), .rst_n(rst_n),
        .slot(slot), .tick(tick), .frame_stb(frame_stb), .tx_oct(tx_oct), .fill(fill),
        .port_c_rx(c_rx[7:0]), .port_a_rx(a_rx[7:0]),
        .port_c_tx(tk_c_tx), .port_a_tx(tk_a_tx), .port_word(tk_word),
        .line_out(line_out), .line_in(line_in),
        .locked(locked), .mute(), .cd());
    assign c_tx[7:0] = tk_c_tx;
    assign a_tx[7:0] = tk_a_tx;
    assign word[7:0] = tk_word;

    // ---- block 1: the two tones, and optionally a second direction ------
    source_card #(.SEED(16'hACE1)) u_dt (.clk(clk), .frame_stb(frame_stb),
        .tx_oct(tx_oct), .c_tx(c_tx[PDT]), .a_tx(a_tx[PDT]),
        .word_pin(word[PDT]), .ans_n());
    source_card #(.SEED(16'h1234)) u_ng (.clk(clk), .frame_stb(frame_stb),
        .tx_oct(tx_oct), .c_tx(c_tx[PNG]), .a_tx(a_tx[PNG]),
        .word_pin(word[PNG]), .ans_n());
    assign dt_bit = c_tx[PDT];
    assign ng_bit = c_tx[PNG];

    genvar k;
    generate
    if (HAS_TRUNK1) begin : dir1
        mf8_trunk_card #(.T_A(T_A), .WORD(WORD1)) u_trunk1 (
            .clk(clk), .rst_n(rst_n),
            .slot(slot), .tick(tick), .frame_stb(frame_stb), .tx_oct(tx_oct), .fill(fill),
            .port_c_rx(c_rx[15:8]), .port_a_rx(a_rx[15:8]),
            .port_c_tx(t1_c_tx), .port_a_tx(t1_a_tx), .port_word(t1_word),
            .line_out(line_out1), .line_in(line_in1),
            .locked(locked1), .mute(), .cd());
        // only the six channel slots; 0 and 4 belong to the tone cards
        for (k = 0; k < 8; k = k + 1) if (k != 0 && k != 4) begin : chan
            assign c_tx[8+k] = t1_c_tx[k];
            assign a_tx[8+k] = t1_a_tx[k];
            assign word[8+k] = t1_word[k];
        end
    end else begin : nodir1
        assign t1_c_tx = 8'h00; assign t1_a_tx = 8'h00; assign t1_word = 8'h00;
        assign line_out1 = 1'b0; assign locked1 = 1'b0;
        for (k = 0; k < 8; k = k + 1) if (k != 0 && k != 4) begin : empty1
            assign c_tx[8+k] = fill;
            assign a_tx[8+k] = 1'b0;
            assign word[8+k] = 1'b0;
        end
    end
    endgenerate

    // ---- block 2: the lines ---------------------------------------------
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
    generate for (q = 16; q < 64; q = q + 1)
        if (q != P20 && q != P21) begin : empty
            assign c_tx[q] = fill; assign a_tx[q] = 1'b0; assign word[q] = 1'b0;
        end
    endgenerate

    // ---- common control --------------------------------------------------
    wire        r_busy, r_gone, r_brk, r_attach, r_release, r_restart;
    wire [2:0]  r_ndig;
    wire [15:0] r_digits;
    wire [5:0] r_port;
    wire       mc0, mc1, mh0, mh1;
    wire [5:0] mp0, mp1;

    pulse_reg #(.HIT(HIT), .ID(ID), .CLR(CLR), .NODIG(2000)) u_reg (
        .clk(clk), .rst_n(rst_n), .slotq(slotq), .tick(tick), .tick_1k(tick_1k),
        .ha(ha), .attach(r_attach), .attach_port(r_port), .release_it(r_release),
        .restart(r_restart), .busy(r_busy), .port(),
        .ndig(r_ndig), .digits(r_digits), .gone(r_gone), .brk(r_brk));

    // Two pools, one marker.  Present block 0's request while it has one, and
    // acknowledge only the pool that was presented, so a request on the other
    // waits its turn rather than being dropped.
    wire       mack;
    wire       mclaim = mc0 | mc1;
    wire [5:0] mport  = mc0 ? mp0 : mp1;
    wire       ack0   = mack &  mc0;
    wire       ack1   = mack & ~mc0;

    // A monitor pool on each block that holds trunks (exch-monitor.md 4).
    monitor #(.NMON(NMON), .OWN_E(OWN_E), .OWN_B(OWN_B), .BLOCK(3'd0),
              .HIT(HIT), .ID(ID), .CLR(CLR)) u_mon0 (
        .clk(clk), .rst_n(rst_n), .oct_stb(oct_stb), .tick_1k(tick_1k),
        .m(tk_a_tx), .busy(pbusy[7:0]), .chan_mask(8'b1110_1110),
        .claim(mc0), .claim_port(mp0), .claim_ack(ack0), .held(mh0), .all_busy());

    generate if (HAS_TRUNK1) begin : mon1
        monitor #(.NMON(NMON), .OWN_E(OWN_E), .OWN_B(OWN_B), .BLOCK(3'd1),
                  .HIT(HIT), .ID(ID), .CLR(CLR)) u_mon1 (
            .clk(clk), .rst_n(rst_n), .oct_stb(oct_stb), .tick_1k(tick_1k),
            .m(t1_a_tx), .busy(pbusy[15:8]), .chan_mask(8'b1110_1110),
            .claim(mc1), .claim_port(mp1), .claim_ack(ack1), .held(mh1), .all_busy());
    end else begin : nomon1
        assign mc1 = 1'b0; assign mp1 = 6'd0; assign mh1 = 1'b0;
    end endgenerate

    assign mon_held = mh0 | mh1;

    marker #(.OWN_E(OWN_E), .OWN_B(OWN_B), .DIALTONE(PDT), .NOGO(PNG),
             .HAS_NET(1'b1), .T_GUARD(T_GUARD), .T_CLAIM(T_CLAIM)) u_mk (
        .clk(clk), .rst_n(rst_n),
        .slotq(slotq), .tick(tick), .frame_stb(frame_stb),
        .oct_stb(oct_stb), .tick_1k(tick_1k),
        .ha(ha), .pb_busy(pb_busy), .pb_word(pb_word),
        .sdata(sdata), .sclk(sclk), .wr(wr),
        .reg_attach(r_attach), .reg_port(r_port), .reg_busy(r_busy),
        .reg_ndig(r_ndig), .reg_digits(r_digits), .reg_restart(r_restart),
        .reg_gone(r_gone), .reg_brk(r_brk),
        .reg_release(r_release),
        .mon_claim(mclaim), .mon_port(mport), .mon_ack(mack));

    assign got_claim  = u_mk.claimed;
    assign dirs_held  = u_mk.d_held;
endmodule
