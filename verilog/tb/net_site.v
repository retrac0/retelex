// net_site -- a whole exchange: fabric, trunks, tones, marker, registers, seekers.
//
//   block 0   an MF8 trunk group, six channels at 01-03, 05-07, facing DIR0
//   block 1   dial tone at 10 and cannot-complete at 14, and -- from NDIR = 2 --
//             a SECOND trunk group at 11-13, 15-17 facing DIR1.  That is
//             exactly how exch-protocol.md 5 lays block 1 out: the two tones sit
//             at slots 0 and 4, which are F and S on the wire, and the six
//             channels sit where they are on the wire either side of them
//   block 2   line cards: 20 and 21 by default, and LINE_PORTS may fill
//             whole blocks with them for a stress run
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
    // Which ports hold line cards.  The default is the two of mvp-ex.md 1;
    // a stress run fills whole blocks with them.
    parameter [63:0]  LINE_PORTS = 64'h0000_0000_0003_0000,
    parameter integer NMON = 2,                  // cells in each block's pool (4)
    parameter integer NREG = 2,                  // registers in the pool
    parameter integer NRES = 2                   // resolvers: a forward is held until it resolves (3.2)
)(
    input         clk,
    input         rst_n,
    // one bit a port: the four wires a line card's subscriber side has
    input  [63:0] hook,
    input  [63:0] tx,
    output [63:0] rx,
    output [63:0] e,
    // one MF8 line pair a direction
    input  [NDIR-1:0] line_in,
    output [NDIR-1:0] line_out,
    output [NDIR-1:0] locked,
    output        frame_stb,
    output        ring_cad_n,
    output        dt_bit, ng_bit,
    output        mon_held,
    output [3:0]  mon_busy,     // per direction: at least one cell of its pool held
    output [3:0]  mon_full,     // per direction: EVERY cell held -- a seizure now goes unwatched
    output        got_claim,
    output [3:0]  dirs_held,     // which directions a call of OURS still holds a trunk in
    output [3:0]  fan_legs,      // which directions a fan-out THROUGH here is holding
    output [3:0]  res_used,      // resolvers in use
    output [63:0] port_busy,     // every port's BUSY: what is seized, and where
    output [NREG-1:0] regs_busy, // which registers are held
    output        wq_ovf,        // the marker's write queue overran (a model part)
    output [15:0] n_defer,       // callers put off a scan by a claim in the same cycle
    output        wr_stb,        // the last latch write the marker sent
    output [5:0]  wr_dst, wr_src,
    output        wr_bsy, wr_clm,
    // ex-counters.md 9: five counter cards on the ribbon, strapped for the
    // marker's event words.  { glare, nodig, notrunk, waitreg, any }
    output [79:0] ev_cnt
);
    localparam PDT = 6'o10, PNG = 6'o14;        // dial tone, cannot-complete

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
    localparam [63:0] PF = LINE_PORTS
                         | 64'h0000_0000_0000_1100     // the two tones
                         | TRUNKS;
    // A block is fitted if anything in it is.
    localparam [7:0]  BF = {|PF[63:56], |PF[55:48], |PF[47:40], |PF[39:32],
                            |PF[31:24], |PF[23:16], |PF[15:8],  |PF[7:0]};

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
               // ONLY the lines ring.  A trunk port that rings chops its own
               // forward A into the ring cadence (exch-fabric.md 3.5's A_RX
               // gate), so it would flood the cadence down the link instead of
               // the caller's dial pulses and nothing beyond could read a digit.
               .PORT_RINGS  (LINE_PORTS),
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

    // ---- the lines --------------------------------------------------------
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

    // ---- one MF8 trunk card a direction ----------------------------------
    wire [3:0]     mc_v, mh_v, mf_v;
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
                .claim_ack(mack_v[g]), .held(mh_v[g]), .all_busy(mf_v[g]), .cells());
        end else begin : absent
            assign mc_v[g] = 1'b0;
            assign mp_v[g*6 +: 6] = 6'd0;
            assign mh_v[g] = 1'b0;
            assign mf_v[g] = 1'b0;
            assign t_c_tx[g*8 +: 8] = 8'h00;
            assign t_a_tx[g*8 +: 8] = 8'h00;
            assign t_word[g*8 +: 8] = 8'h00;
        end
    end endgenerate

    // every slot no card drives: C pulled to FILL, A and the word to 0
    genvar q;
    generate for (q = 0; q < 64; q = q + 1)
        if (!TRUNKS[q] && !LINE_PORTS[q] && q != PDT && q != PNG) begin : empty
            assign c_tx[q] = fill; assign a_tx[q] = 1'b0; assign word[q] = 1'b0;
        end
    endgenerate

    // ---- common control --------------------------------------------------
    // The registers: a pool, found by the marker's scanner (exch-marker.md 4, 6).
    wire [NREG-1:0]    r_busy, r_gone, r_brk, r_attach, r_release, r_restart;
    wire [NREG-1:0]    r_nodig;
    wire [3*NREG-1:0]  r_ndig;
    wire [16*NREG-1:0] r_digits;
    wire [5:0]         r_port;
    assign regs_busy = r_busy;

    genvar gr;
    generate for (gr = 0; gr < NREG; gr = gr + 1) begin : regs
        pulse_reg #(.HIT(HIT), .ID(ID), .CLR(CLR), .NODIG(2000)) u_reg (
            .clk(clk), .rst_n(rst_n), .slotq(slotq), .tick(tick), .tick_1k(tick_1k),
            .ha(ha), .attach(r_attach[gr]), .attach_port(r_port),
            .release_it(r_release[gr]), .restart(r_restart[gr]),
            .busy(r_busy[gr]), .port(),
            .ndig(r_ndig[gr*3 +: 3]), .digits(r_digits[gr*16 +: 16]),
            .gone(r_gone[gr]), .nodig(r_nodig[gr]), .brk(r_brk[gr]));
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
    assign mon_busy = mh_v;
    assign mon_full = mf_v;

    // ---- counter cards, ex-counters.md 1 and 9 --------------------------
    // Cards that only listen: sdata, sclk, wr and nothing else.  The event
    // strap is BSY = 0 with CLM = 1, which no latch write ever carries, and the
    // code is in SRC.  The card cannot see G and does not need to.
    wire [15:0] ev_any_c, ev_wait_c, ev_ntrk_c, ev_ndig_c, ev_glare_c;
    assign ev_cnt = {ev_glare_c, ev_ndig_c, ev_ntrk_c, ev_wait_c, ev_any_c};

    stats #(.SRC(6'o00), .BSY(1'b0), .CLM(1'b1),
            .SRC_ANY(6'o77), .BSY_ANY(1'b0), .CLM_ANY(1'b0)) u_ev_any (
        .clk(clk), .rst_n(rst_n), .sdata(sdata), .sclk(sclk), .wr(wr),
        .clr(1'b0), .count(ev_any_c), .match());
    stats #(.SRC(6'o01), .BSY(1'b0), .CLM(1'b1),
            .SRC_ANY(6'o00), .BSY_ANY(1'b0), .CLM_ANY(1'b0)) u_ev_wait (
        .clk(clk), .rst_n(rst_n), .sdata(sdata), .sclk(sclk), .wr(wr),
        .clr(1'b0), .count(ev_wait_c), .match());
    stats #(.SRC(6'o02), .BSY(1'b0), .CLM(1'b1),
            .SRC_ANY(6'o00), .BSY_ANY(1'b0), .CLM_ANY(1'b0)) u_ev_ndig (
        .clk(clk), .rst_n(rst_n), .sdata(sdata), .sclk(sclk), .wr(wr),
        .clr(1'b0), .count(ev_ndig_c), .match());
    stats #(.SRC(6'o04), .BSY(1'b0), .CLM(1'b1),
            .SRC_ANY(6'o00), .BSY_ANY(1'b0), .CLM_ANY(1'b0)) u_ev_glare (
        .clk(clk), .rst_n(rst_n), .sdata(sdata), .sclk(sclk), .wr(wr),
        .clr(1'b0), .count(ev_glare_c), .match());
    // all four directions at once: the two low bits strapped to Pi
    stats #(.SRC(6'o10), .BSY(1'b0), .CLM(1'b1),
            .SRC_ANY(6'o03), .BSY_ANY(1'b0), .CLM_ANY(1'b0)) u_ev_ntrk (
        .clk(clk), .rst_n(rst_n), .sdata(sdata), .sclk(sclk), .wr(wr),
        .clr(1'b0), .count(ev_ntrk_c), .match());

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
        .reg_gone(r_gone), .reg_nodig(r_nodig), .reg_brk(r_brk),
        .reg_release(r_release),
        .mon_claim(mclaim), .mon_port(mport), .mon_ack(mack),
        .any_claimed(got_claim), .dirs_held(dirs_held),
        .fan_legs(fan_legs), .res_used(res_used), .wq_ovf(wq_ovf),
        .n_defer(n_defer), .wr_stb(wr_stb), .wr_dst(wr_dst),
        .wr_src(wr_src), .wr_bsy(wr_bsy), .wr_clm(wr_clm));
endmodule
