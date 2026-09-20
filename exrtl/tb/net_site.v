// net_site -- a whole exchange: fabric, trunks, tones, marker, registers, seekers.
//
//   block 0   an MF8 trunk group, six channels at 01-03, 05-07, facing DIR0
//   block 1   dial tone at 10 and cannot-complete at 14, and -- from NDIR = 2 --
//             a SECOND trunk group at 11-13, 15-17 facing DIR1.  That is
//             exactly how exch-protocol.md 5 lays block 1 out: the two tones sit
//             at slots 0 and 4, which are F and S on the wire, and the six
//             channels sit where they are on the wire either side of them
//   block 2   two line cards, 20 and 21
//   block 3   a third trunk group, facing DIR2   (NDIR = 3)
//   block 4   a fourth, facing DIR3              (NDIR = 4)
//   common    one marker, a pool of registers, and a monitor pool on each
//             trunk block -- "a flood reaches a hub on one block"
//
// An exchange with one direction is an end of a chain; with two it is a transit,
// and its marker forwards a seizure from one into the other; with three or four
// it is a HUB, and a seizure is fanned out into every other direction at once
// and held in a resolver until one of them claims (exch-network.md 3.2).
`timescale 1ns/1ps

module net_site #(
    parameter [2:0]   OWN_E = 3'd2,
    parameter [2:0]   OWN_B = 3'd2,
    // How many directions this exchange has, and for each its direction, its
    // glare bit and its strap, as the card's word carries them
    // (ex-extensions.md 2.2).  N=0 S=1 E=2 W=3.
    parameter integer NDIR = 1,
    parameter [1:0]   DIR0 = 2'd2,
    parameter         G0 = 1'b0,
    parameter         N0 = 1'b0,
    parameter [1:0]   DIR1 = 2'd3,
    parameter         G1 = 1'b0,
    parameter         N1 = 1'b0,
    parameter [1:0]   DIR2 = 2'd0,
    parameter         G2 = 1'b0,
    parameter         N2 = 1'b0,
    parameter [1:0]   DIR3 = 2'd1,
    parameter         G3 = 1'b0,
    parameter         N3 = 1'b0,
    parameter integer T_RISE = 64, T_FALL = 2048,
    parameter integer RING_ON = 200, RING_OFF = 400,
    parameter integer T_A = 4,
    parameter integer HIT = 1, ID = 16, CLR = 32,
    parameter integer T_GUARD = 16, T_CLAIM = 250,
    parameter integer NMON = 2,                  // cells in each block's pool (4)
    parameter integer NREG = 2,                  // registers in the pool
    parameter integer NRES = 2                   // resolvers: a forward is held until it resolves (3.2)
)(
    input         clk,
    input         rst_n,
    input         hook20, hook21,
    input         tx20, tx21,
    output        rx20, rx21,
    output        e20, e21,
    // one MF8 line pair a direction
    input  [NDIR-1:0] line_in,
    output [NDIR-1:0] line_out,
    output [NDIR-1:0] locked,
    output        frame_stb,
    output        ring_cad_n,
    output        dt_bit, ng_bit,
    output        mon_held,
    output        got_claim,
    output [3:0]  dirs_held,     // which directions a call of OURS still holds a trunk in
    output [3:0]  fan_legs,      // which directions a fan-out THROUGH here is holding
    output [3:0]  res_used,      // resolvers in use
    output [63:0] port_busy      // every port's BUSY: what is seized, and where
);
    localparam P20 = 6'o20, P21 = 6'o21, PDT = 6'o10, PNG = 6'o14;

    // Which block each direction's trunk group sits on: 0, 1, then 3 and 4,
    // because block 2 is the lines.
    localparam [7:0] WORD0 = {1'b0, N0, G0, DIR0, 3'b101};   // class 101: tie trunk
    localparam [7:0] WORD1 = {1'b0, N1, G1, DIR1, 3'b101};
    localparam [7:0] WORD2 = {1'b0, N2, G2, DIR2, 3'b101};
    localparam [7:0] WORD3 = {1'b0, N3, G3, DIR3, 3'b101};

    // The channel slots a trunk card drives: 1-3 and 5-7, where they are on the
    // wire.  Slots 0 and 4 are F and S and are NOT ports -- on block 1 they are
    // the two tone cards, and on a trunk block nothing at all, which is what
    // keeps port 00 unfitted for "a cleared latch listens to 00" (mvp-ex.md 2).
    localparam [63:0] TRUNKS = 64'h0000_0000_0000_00EE
                             | ((NDIR >= 2) ? 64'h0000_0000_0000_EE00 : 64'd0)
                             | ((NDIR >= 3) ? 64'h0000_0000_EE00_0000 : 64'd0)
                             | ((NDIR >= 4) ? 64'h0000_00EE_0000_0000 : 64'd0);
    localparam [63:0] PF = 64'h0000_0000_0003_0000     // the two lines
                         | 64'h0000_0000_0000_1100     // the two tones
                         | TRUNKS;
    localparam [7:0]  BF = 8'b0000_0111
                         | ((NDIR >= 3) ? 8'b0000_1000 : 8'd0)
                         | ((NDIR >= 4) ? 8'b0001_0000 : 8'd0);

    wire [63:0] c_tx, a_tx, word, c_rx, a_rx;
    wire [2:0]  slot, slotq, tick;
    wire        tx_oct, tick_1k, fill, pb_busy, pb_word;
    wire [7:0]  ha;
    wire [63:0] pbusy;
    wire        sdata, sclk, wr;
    wire [31:0] t_c_tx, t_a_tx, t_word;          // eight slots a direction
    wire        oct_stb = frame_stb & tx_oct;

    assign port_busy = pbusy;

    exch_top #(.BLOCK_FITTED(BF),
               .PORT_FITTED (PF),
               // ONLY the lines ring: block 2 and nothing else.  A trunk port
               // that rings chops its own forward A into the ring cadence
               // (exch-fabric.md 3.5's A_RX gate), so a third and fourth
               // direction up at ports 24-47 would flood a cadence instead of
               // the caller's dial pulses.
               .PORT_RINGS  (64'h0000_0000_00FF_0000),
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

    // ---- the tones, on block 1 -------------------------------------------
    source_card #(.SEED(16'hACE1)) u_dt (.clk(clk), .frame_stb(frame_stb),
        .tx_oct(tx_oct), .c_tx(c_tx[PDT]), .a_tx(a_tx[PDT]),
        .word_pin(word[PDT]), .ans_n());
    source_card #(.SEED(16'h1234)) u_ng (.clk(clk), .frame_stb(frame_stb),
        .tx_oct(tx_oct), .c_tx(c_tx[PNG]), .a_tx(a_tx[PNG]),
        .word_pin(word[PNG]), .ans_n());
    assign dt_bit = c_tx[PDT];
    assign ng_bit = c_tx[PNG];

    // ---- the lines, on block 2 -------------------------------------------
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

    // ---- one MF8 trunk card a direction ----------------------------------
    wire [3:0]     mc_v, mh_v;
    wire [4*6-1:0] mp_v;
    wire [3:0]     mack_v;

    genvar g, k;
    generate for (g = 0; g < 4; g = g + 1) begin : dir
        if (g < NDIR) begin : fitted
            localparam integer B = (g == 0) ? 0 : (g == 1) ? 1 : (g == 2) ? 3 : 4;
            localparam [7:0] W = (g == 0) ? WORD0 : (g == 1) ? WORD1 :
                                 (g == 2) ? WORD2 : WORD3;

            mf8_trunk_card #(.T_A(T_A), .WORD(W)) u_trunk (
                .clk(clk), .rst_n(rst_n),
                .slot(slot), .tick(tick), .frame_stb(frame_stb),
                .tx_oct(tx_oct), .fill(fill),
                .port_c_rx(c_rx[B*8 +: 8]), .port_a_rx(a_rx[B*8 +: 8]),
                .port_c_tx(t_c_tx[g*8 +: 8]), .port_a_tx(t_a_tx[g*8 +: 8]),
                .port_word(t_word[g*8 +: 8]),
                .line_out(line_out[g]), .line_in(line_in[g]),
                .locked(locked[g]), .mute(), .cd());

            for (k = 0; k < 8; k = k + 1) if (TRUNKS[B*8+k]) begin : chan
                assign c_tx[B*8+k] = t_c_tx[g*8+k];
                assign a_tx[B*8+k] = t_a_tx[g*8+k];
                assign word[B*8+k] = t_word[g*8+k];
            end

            // A monitor pool on each block that holds trunks (exch-monitor.md 4).
            monitor #(.NMON(NMON), .OWN_E(OWN_E), .OWN_B(OWN_B), .BLOCK(B[2:0]),
                      .HIT(HIT), .ID(ID), .CLR(CLR)) u_mon (
                .clk(clk), .rst_n(rst_n), .oct_stb(oct_stb), .tick_1k(tick_1k),
                .m(t_a_tx[g*8 +: 8]), .busy(pbusy[B*8 +: 8]),
                .chan_mask(8'b1110_1110),
                .claim(mc_v[g]), .claim_port(mp_v[g*6 +: 6]),
                .claim_ack(mack_v[g]), .held(mh_v[g]), .all_busy(), .cells());
        end else begin : absent
            assign mc_v[g] = 1'b0;
            assign mp_v[g*6 +: 6] = 6'd0;
            assign mh_v[g] = 1'b0;
            assign t_c_tx[g*8 +: 8] = 8'h00;
            assign t_a_tx[g*8 +: 8] = 8'h00;
            assign t_word[g*8 +: 8] = 8'h00;
        end
    end endgenerate

    // every slot no card drives: C pulled to FILL, A and the word to 0
    genvar q;
    generate for (q = 0; q < 64; q = q + 1)
        if (!TRUNKS[q] && q != P20 && q != P21 && q != PDT && q != PNG) begin : empty
            assign c_tx[q] = fill; assign a_tx[q] = 1'b0; assign word[q] = 1'b0;
        end
    endgenerate

    // ---- common control --------------------------------------------------
    // The registers: a pool, found by the marker's scanner (exch-marker.md 4, 6).
    wire [NREG-1:0]    r_busy, r_gone, r_brk, r_attach, r_release, r_restart;
    wire [3*NREG-1:0]  r_ndig;
    wire [16*NREG-1:0] r_digits;
    wire [5:0]         r_port;

    genvar gr;
    generate for (gr = 0; gr < NREG; gr = gr + 1) begin : regs
        pulse_reg #(.HIT(HIT), .ID(ID), .CLR(CLR), .NODIG(2000)) u_reg (
            .clk(clk), .rst_n(rst_n), .slotq(slotq), .tick(tick), .tick_1k(tick_1k),
            .ha(ha), .attach(r_attach[gr]), .attach_port(r_port),
            .release_it(r_release[gr]), .restart(r_restart[gr]),
            .busy(r_busy[gr]), .port(),
            .ndig(r_ndig[gr*3 +: 3]), .digits(r_digits[gr*16 +: 16]),
            .gone(r_gone[gr]), .brk(r_brk[gr]));
    end endgenerate

    // Up to four pools, one marker.  The selection is REGISTERED and holds
    // until the pool it names drops its request, because the marker reads
    // mon_port one cycle before it answers: a selection that moved in between
    // would acknowledge the wrong pool, and a claim is a call this exchange
    // owned (exch-monitor.md 3.4).
    wire       mack;
    reg  [3:0] sel, ask;
    integer    z;
    always @* begin
        ask = 4'd0;
        for (z = 0; z < 4; z = z + 1)
            if (mc_v[z] && ask == 4'd0) ask[z] = 1'b1;
    end
    always @(posedge clk or negedge rst_n)
        if (!rst_n) sel <= 4'd0;
        else if ((sel & mc_v) == 4'd0) sel <= ask;

    wire       mclaim = |(mc_v & sel);
    reg  [5:0] mport;
    always @* begin
        mport = 6'd0;
        for (z = 0; z < 4; z = z + 1) if (sel[z]) mport = mp_v[z*6 +: 6];
    end
    assign mack_v  = {4{mack}} & sel;
    assign mon_held = |mh_v;

    marker #(.NREG(NREG), .NRES(NRES), .OWN_E(OWN_E), .OWN_B(OWN_B),
             .DIALTONE(PDT), .NOGO(PNG),
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
        .mon_claim(mclaim), .mon_port(mport), .mon_ack(mack),
        .any_claimed(got_claim), .dirs_held(dirs_held),
        .fan_legs(fan_legs), .res_used(res_used));
endmodule
