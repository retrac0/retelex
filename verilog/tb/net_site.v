// net_site -- a whole exchange: fabric, trunks, tones, marker, registers, seekers.
//
//   block 0   dial tone at 01, busy at 02 (optional), cannot-complete at 03;
//             04-07 the operator bank when fitted.  Never an MF8 trunk group.
//   block 1   first MF8 trunk group at 11-13/15-17 facing DIR0 -- block
//             adapter on the block header (mf8-unit.md 1).  Port 00 is silence for
//             a cleared latch; 04 is an operator seat on a tone-less map.
//   block 2   line cards: 20 and 21 by default, and LINE_PORTS may fill
//             whole blocks with them for a stress run
//   block 3   a second trunk group, facing DIR1   (NDIR = 2)
//   block 4   a third, facing DIR2                (NDIR = 3)
//   block 5   a fourth, facing DIR3               (NDIR = 4)
//   common    one marker, a pool of registers, and a monitor pool on each
//             trunk block -- "a flood reaches a hub on one block"
//
// An exchange with one direction is an end of a chain; with two it is a transit,
// and its network unit forwards a seizure from one into the other; with three or four
// it is a HUB, and a seizure is fanned out into every other direction at once
// and held in a resolver until one of them claims (network.md 3.2, common-control.md).
`timescale 1ns/1ps

module net_site #(
    parameter [2:0]   OWN_E = 3'd2,
    parameter [2:0]   OWN_B = 3'd2,
    // How many directions this exchange has, and for each its direction, its
    // glare bit (in the card's word) and its no-forward jumper (STRAP_N on the
    // marker, not in the word).  N=0 S=1 E=2 W=3.
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
    // Which ports hold line cards.  The default is the two of mvp.md 1;
    // a stress run fills whole blocks with them.
    parameter [63:0]  LINE_PORTS = 64'h0000_0000_0003_0000,
    // Per-port line words (extensions.md 2.2).
    // Default all-ones = grounded plain line.
    // Class: {ppp, ccc, 2'b11}; answers {hs, 2'b01}; call nail {hs, 2'b10}; tied nail {hs, 2'b00}.
    parameter [15:0]  LINE_WORD_04 = 16'hFFFF,
    parameter [15:0]  LINE_WORD_20 = 16'hFFFF,
    parameter [15:0]  LINE_WORD_21 = 16'hFFFF,
    parameter [15:0]  LINE_WORD_22 = 16'hFFFF,
    parameter [15:0]  LINE_WORD_23 = 16'hFFFF,
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
    output        tick_1k,
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
    // counters.md 9: five counter cards on the ribbon, jumpered for the
    // marker's event words.  { glare, nodig, notrunk, waitreg, any }
    output [79:0] ev_cnt
);
    localparam PDT = 6'o01, PBSY = 6'o02, PNG = 6'o03;   // dial, busy, cannot-complete

    // Which block each direction's trunk group sits on: 1, then 3, 4 and 5 —
    // block 0 is tones + the operator bank; block 2 is the lines.
    // Class form + tagged secondary (extensions.md 2.2):
    // primary 11 101 000; tag 10; payload {DIR, G, 000}.
    // WORD = {DIR, G, 3'b000, 2'b10, 3'b000, 3'b101, 2'b11}
    localparam [15:0] WORD0 = {DIR0, G0, 3'b000, 2'b10, 3'b000, 3'b101, 2'b11};
    localparam [15:0] WORD1 = {DIR1, G1, 3'b000, 2'b10, 3'b000, 3'b101, 2'b11};
    localparam [15:0] WORD2 = {DIR2, G2, 3'b000, 2'b10, 3'b000, 3'b101, 2'b11};
    localparam [15:0] WORD3 = {DIR3, G3, 3'b000, 2'b10, 3'b000, 3'b101, 2'b11};
    localparam [3:0] STRAP_N = ({3'b000, N0} << DIR0) | ({3'b000, N1} << DIR1)
                             | ({3'b000, N2} << DIR2) | ({3'b000, N3} << DIR3);

    // Six trunk channels a block (slots 1-3, 5-7).  Port 00 stays unfitted
    // ("a cleared latch listens to 00", mvp.md 2); tones are 01-03; slots
    // 0 and 4 of a trunk block are free.
    localparam [63:0] TRUNKS = 64'h0000_0000_0000_EE00
                             | ((NDIR >= 2) ? 64'h0000_0000_EE00_0000 : 64'd0)
                             | ((NDIR >= 3) ? 64'h0000_00EE_0000_0000 : 64'd0)
                             | ((NDIR >= 4) ? 64'h0000_EE00_0000_0000 : 64'd0);
    localparam [63:0] PF = LINE_PORTS
                         | 64'h0000_0000_0000_000E     // tones at 01, 02, 03
                         | TRUNKS;
    // A block is fitted if anything in it is.
    localparam [7:0]  BF = {|PF[63:56], |PF[55:48], |PF[47:40], |PF[39:32],
                            |PF[31:24], |PF[23:16], |PF[15:8],  |PF[7:0]};

    wire [63:0] c_tx, a_tx, word, c_rx, a_rx;
    wire [2:0]  slot, slotq, tick;
    wire        tx_oct, fill, pb_busy, pb_word;
    wire [7:0]  ha;
    wire [63:0] pbusy;
    wire        sdata, sclk, wr;
    wire [31:0] t_c_tx, t_a_tx, t_word;          // eight slots a direction
    wire        oct_stb = frame_stb & tx_oct;
    wire [2:0]  scan_port;

    assign port_busy = pbusy;

    exch_top #(.BLOCK_FITTED(BF),
               .PORT_FITTED (PF),
               // ONLY the lines ring.  A trunk port that rings chops its own
               // forward A into the ring cadence (fabric.md 3.5's A_RX
               // gate), so it would flood the cadence down the link instead of
               // the caller's dial pulses and nothing beyond could read a digit.
               .PORT_RINGS  (LINE_PORTS),
               .RBT_IS_FILL(1'b1),
               .T_RISE(T_RISE), .T_FALL(T_FALL),
               .RING_ON(RING_ON), .RING_OFF(RING_OFF))
    u_exch (.clk(clk), .rst_n(rst_n),
            .c_tx(c_tx), .a_tx(a_tx), .word(word), .c_rx(c_rx), .a_rx(a_rx),
            .sdata(sdata), .sclk(sclk), .wr(wr),
            .con_n(1'b1), .scan_port(scan_port),
            .pb_busy(pb_busy), .pb_word(pb_word), .port_busy(pbusy),
            .hc(), .ha(ha),
            .slot(slot), .slotq(slotq), .tick(tick), .hclk(), .line_hb(), .tx_clk(),
            .frame_stb(frame_stb), .tx_oct(tx_oct), .rx_oct(),
            .fill(fill), .ring_cad_n(ring_cad_n), .tick_1k(tick_1k));

    // ---- the tones, on block 0 -------------------------------------------
    source_card #(.SEED(16'hACE1)) u_dt (.clk(clk), .frame_stb(frame_stb),
        .tx_oct(tx_oct), .c_tx(c_tx[PDT]), .a_tx(a_tx[PDT]),
        .word_pin(word[PDT]), .ans_n());
    source_card #(.SEED(16'hBEEF)) u_bs (.clk(clk), .frame_stb(frame_stb),
        .tx_oct(tx_oct), .c_tx(c_tx[PBSY]), .a_tx(a_tx[PBSY]),
        .word_pin(word[PBSY]), .ans_n());
    source_card #(.SEED(16'h1234)) u_ng (.clk(clk), .frame_stb(frame_stb),
        .tx_oct(tx_oct), .c_tx(c_tx[PNG]), .a_tx(a_tx[PNG]),
        .word_pin(word[PNG]), .ans_n());
    assign dt_bit = c_tx[PDT];
    assign ng_bit = c_tx[PNG];

    // ---- the lines --------------------------------------------------------
    genvar p;
    generate for (p = 0; p < 64; p = p + 1) begin : line
        if (LINE_PORTS[p]) begin : fitted
            line_card #(.WORD(
                (p == 6'o04) ? LINE_WORD_04 :
                (p == 6'o20) ? LINE_WORD_20 :
                (p == 6'o21) ? LINE_WORD_21 :
                (p == 6'o22) ? LINE_WORD_22 :
                (p == 6'o23) ? LINE_WORD_23 : 16'hFFFF
            )) u_c (
                           .clk(clk), .frame_stb(frame_stb), .tx_oct(tx_oct),
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
            localparam integer B = (g == 0) ? 1 : (g == 1) ? 3 : (g == 2) ? 4 : 5;
            localparam [15:0] W = (g == 0) ? WORD0 : (g == 1) ? WORD1 :
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

            // A monitor pool on each block that holds trunks (monitor.md 4).
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
        if (!TRUNKS[q] && !LINE_PORTS[q] && q != PDT && q != PBSY && q != PNG) begin : empty
            assign c_tx[q] = fill; assign a_tx[q] = 1'b0; assign word[q] = 1'b0;
        end
    endgenerate

    // ---- common control --------------------------------------------------
    // The registers: a pool, found by the marker's scanner (marker.md 4, 6).
    wire [NREG-1:0]    r_busy, r_gone, r_brk, r_attach, r_release, r_restart;
    wire [NREG-1:0]    r_nodig;
    wire [3*NREG-1:0]  r_ndig;
    wire [20*NREG-1:0] r_digits;
    wire [6*NREG-1:0]  r_held;
    wire [5:0]         r_port, r_src;
    assign regs_busy = r_busy;

    genvar gr;
    generate for (gr = 0; gr < NREG; gr = gr + 1) begin : regs
        pulse_reg #(.HIT(HIT), .ID(ID), .CLR(CLR), .NODIG(2000)) u_reg (
            .clk(clk), .rst_n(rst_n), .slotq(slotq), .tick(tick), .tick_1k(tick_1k),
            .ha(ha), .attach(r_attach[gr]), .attach_port(r_port), .attach_src(r_src),
            .release_it(r_release[gr]), .restart(r_restart[gr]),
            .busy(r_busy[gr]), .port(), .src(r_held[gr*6 +: 6]),
            .ndig(r_ndig[gr*3 +: 3]), .digits(r_digits[gr*20 +: 20]),
            .gone(r_gone[gr]), .nodig(r_nodig[gr]), .brk(r_brk[gr]), .hook());
    end endgenerate

    // Up to four pools, one marker.  The selection is REGISTERED and holds
    // until the pool it names drops its request, because the marker reads
    // mon_port one cycle before it answers: a selection that moved in between
    // would acknowledge the wrong pool, and a claim is a call this exchange
    // owned (monitor.md 3.4).
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

    // ---- counter cards, counters.md 1 and 9 --------------------------
    // Cards that only listen: sdata, sclk, wr and nothing else.  The event
    // jumper is BSY = 0 with CLM = 1, which no latch write ever carries, and the
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
    // all four directions at once: the two low bits jumpered to Pi
    stats #(.SRC(6'o10), .BSY(1'b0), .CLM(1'b1),
            .SRC_ANY(6'o03), .BSY_ANY(1'b0), .CLM_ANY(1'b0)) u_ev_ntrk (
        .clk(clk), .rst_n(rst_n), .sdata(sdata), .sclk(sclk), .wr(wr),
        .clr(1'b0), .count(ev_ntrk_c), .match());

    wire [5:0]  pr_port;
    wire        pr_visit, pr_valid, pr_m, pr_busy;
    wire [15:0] pr_word;
    wire [NREG-1:0] flood_go, net_restart, net_done, net_nogo, net_local;
    wire [6*NREG-1:0] flood_caller;
    wire        net_att;
    wire [5:0]  net_att_port;
    wire [3:0]  net_nw;
    wire [8*6-1:0] net_wdst, net_wsrc;
    wire [7:0]  net_wbsy, net_wclm, net_wev;

    marker #(.NREG(NREG),
             .DIALTONE(PDT), .NOGO(PNG),
             .HAS_NET(1'b1)) u_mk (
        .clk(clk), .rst_n(rst_n),
        .slotq(slotq), .tick(tick), .frame_stb(frame_stb),
        .oct_stb(oct_stb), .tick_1k(tick_1k),
        .ha(ha), .pb_busy(pb_busy), .pb_word(pb_word),
        .sdata(sdata), .sclk(sclk), .wr(wr),
        .reg_attach(r_attach), .reg_port(r_port), .reg_src(r_src), .reg_busy(r_busy),
        .reg_ndig(r_ndig), .reg_digits(r_digits), .reg_held(r_held),
        .reg_restart(r_restart),
        .reg_gone(r_gone), .reg_nodig(r_nodig), .reg_brk(r_brk),
        .reg_release(r_release),
        .probe_port(pr_port), .scan_port(scan_port),
        .probe_visit(pr_visit), .probe_valid(pr_valid),
        .probe_m(pr_m), .probe_busy(pr_busy), .probe_word(pr_word),
        .flood_go(flood_go), .flood_caller(flood_caller),
        .net_restart(net_restart), .net_done(net_done),
        .net_nogo(net_nogo), .net_local(net_local),
        .net_att(net_att), .net_att_port(net_att_port),
        .net_nw(net_nw), .net_wdst(net_wdst), .net_wsrc(net_wsrc),
        .net_wbsy(net_wbsy), .net_wclm(net_wclm), .net_wev(net_wev),
        .wq_ovf(wq_ovf),
        .n_defer(n_defer), .wr_stb(wr_stb), .wr_dst(wr_dst),
        .wr_src(wr_src), .wr_bsy(wr_bsy), .wr_clm(wr_clm),
        .con_n(1'b1), .bus_oe());

    net_unit #(.NREG(NREG), .NRES(NRES), .OWN_E(OWN_E), .OWN_B(OWN_B),
               .NOGO(PNG), .STRAP_N(STRAP_N),
               .T_GUARD(T_GUARD), .T_CLAIM(T_CLAIM)) u_net (
        .clk(clk), .rst_n(rst_n), .tick_1k(tick_1k),
        .visit(pr_visit), .p_valid(pr_valid), .p_port(pr_port),
        .p_m(pr_m), .p_busy(pr_busy), .p_word(pr_word),
        .flood_go(flood_go), .flood_caller(flood_caller),
        .reg_gone(r_gone), .reg_brk(r_brk),
        .reg_ndig(r_ndig), .reg_digits(r_digits),
        .restart(net_restart), .go_local(net_local),
        .done(net_done), .nogo(net_nogo),
        .mon_claim(mclaim), .mon_port(mport), .mon_ack(mack),
        .att_req(net_att), .att_port(net_att_port),
        .nw(net_nw), .wdst(net_wdst), .wsrc(net_wsrc),
        .wbsy(net_wbsy), .wclm(net_wclm), .wev(net_wev),
        .any_claimed(got_claim), .dirs_held(dirs_held),
        .fan_legs(fan_legs), .res_used(res_used));
endmodule
