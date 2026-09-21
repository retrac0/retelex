// con_site -- a standalone exchange with TWO masters on cable B: the marker and
// the operator's console.  console.md.
//
//   block 0   dial tone at 01, cannot-complete at 03; OPERATOR'S PHONE at 04
//             on a plain line card (00 never fitted; 02 busy optional; 05-07
//             more of the four-line bank when fitted)
//   blocks 2-3  sixteen line cards, 20-37
//   block 7   a RING SOURCE at 75: the sink's converse.  A_TX tied HIGH, no
//             word, /ANS low -- an off-hook port that is not a caller, because
//             the marker seizes nothing that sends no class.  A port pointed at
//             it RINGS (on-hook with E up is the ring condition) and, once
//             answered, is HELD: its E never falls, so it never releases itself
//   block 7   two SINKS at 76 and 77: a port with nothing to say.  M tied low,
//             /ANS low, NO WORD -- so to the marker it is an empty slot, never
//             hunted, never a call request, and cannot-complete if dialled;
//             to the fabric it is a port with a latch, and only the console
//             ever writes it.  What it hears is the observer's headphones
//   common    one marker (no network card), a pool of registers, the console
//
// Cable B is tri-state in 74HC and pulled low at every block
// (mainboard.md 6); here it is an AND-OR of whoever's '244 is on.
//
// NAIVE = 1 is mainboard.md 2.3's /CON as first written -- "the marker's
// drivers go high-impedance.  One '244 enable" -- and nothing more: the marker
// is cut off the instant /CON falls, does not know it, and the console does
// not wait.  It is here to be measured against.
`timescale 1ns/1ps

module con_site #(
    parameter         NAIVE = 1'b0,
    parameter integer T_RISE = 64, T_FALL = 2048,
    parameter integer RING_ON = 200, RING_OFF = 400,
    parameter integer HIT = 1, ID = 16, CLR = 32, NODIG = 2000,
    parameter integer NREG = 3,
    parameter integer CON_DIV = 64,              // the console shifts at 64 kHz
    parameter integer CON_WAIT = 32
)(
    input         clk,
    input         rst_n,
    // the sixteen lines' subscriber sides, indexed by port
    input  [63:0] hook,
    input  [63:0] tx,
    output [63:0] rx,
    output [63:0] e,
    // what the two sinks hear
    output [1:0]  sink_rx,

    // the console's panel
    input         key_write, key_release, key_probe, key_hold, key_arm,
    input         sw_both,
    input  [5:0]  sw_dst, sw_src,
    input         sw_bsy, sw_clm,
    output        con_busy, con_done,
    output [5:0]  watch_src,
    output        watch_bsy, watch_clm, watch_seen,
    output        hook_dst, hook_src,
    output        sup_busy_dst, sup_busy_src,
    output [7:0]  sup_word_dst, sup_word_src,
    output        sup_seen,

    // for a testbench: cable B as a listener sees it, and who is driving
    output        b_sdata, b_sclk, b_wr,
    output        con_n, con_oe, mk_drv,
    output        frame_stb, tick_1k,
    output        dt_bit, ng_bit,
    output [63:0] port_busy,
    output [NREG-1:0] regs_busy,
    output        wq_ovf,
    output        wr_stb,
    output [5:0]  wr_dst, wr_src,
    output        wr_bsy, wr_clm
);
    localparam PDT = 6'o01, PNG = 6'o03;
    localparam PS0 = 6'o76, PS1 = 6'o77, PRS = 6'o75;
    localparam POP = 6'o04;                              // the operator's phone
    localparam [63:0] LINE_PORTS = 64'h0000_0000_FFFF_0000 | (64'd1 << POP);
    localparam [63:0] SINKS      = 64'hC000_0000_0000_0000;
    localparam [63:0] RSRC       = 64'd1 << PRS;
    localparam [63:0] PF = LINE_PORTS | SINKS | RSRC | 64'h0000_0000_0000_000A; // 01, 03
    localparam [7:0]  BF = 8'b1000_1101;                 // blocks 0, 2, 3, 7

    wire [63:0] c_tx, a_tx, word, c_rx, a_rx;
    wire [2:0]  slot, slotq, tick;
    wire        tx_oct, fill, pb_busy, pb_word;
    wire [7:0]  ha;
    wire        oct_stb = frame_stb & tx_oct;

    // ---- cable B, and its two masters ------------------------------------
    wire mk_sdata, mk_sclk, mk_wr, mk_oe;
    wire cn_sdata, cn_sclk, cn_wr;
    assign mk_drv  = NAIVE ? con_n : mk_oe;
    assign b_sdata = (mk_drv & mk_sdata) | (con_oe & cn_sdata);
    assign b_sclk  = (mk_drv & mk_sclk)  | (con_oe & cn_sclk);
    assign b_wr    = (mk_drv & mk_wr)    | (con_oe & cn_wr);

    exch_top #(.BLOCK_FITTED(BF), .PORT_FITTED(PF),
               .PORT_RINGS(LINE_PORTS),          // a sink never rings: /ANS low
               .RBT_IS_FILL(1'b1),
               .T_RISE(T_RISE), .T_FALL(T_FALL),
               .RING_ON(RING_ON), .RING_OFF(RING_OFF))
    u_exch (.clk(clk), .rst_n(rst_n),
            .c_tx(c_tx), .a_tx(a_tx), .word(word), .c_rx(c_rx), .a_rx(a_rx),
            .sdata(b_sdata), .sclk(b_sclk), .wr(b_wr),
            .pb_busy(pb_busy), .pb_word(pb_word), .port_busy(port_busy),
            .hc(), .ha(ha),
            .slot(slot), .slotq(slotq), .tick(tick), .hclk(), .hb(), .tx_clk(),
            .frame_stb(frame_stb), .tx_oct(tx_oct), .rx_oct(),
            .fill(fill), .ring_cad_n(), .tick_1k(tick_1k));

    // ---- the tones ---------------------------------------------------------
    source_card #(.SEED(16'hACE1)) u_dt (.clk(clk), .frame_stb(frame_stb),
        .tx_oct(tx_oct), .c_tx(c_tx[PDT]), .a_tx(a_tx[PDT]),
        .word_pin(word[PDT]), .ans_n());
    source_card #(.SEED(16'h1234)) u_ng (.clk(clk), .frame_stb(frame_stb),
        .tx_oct(tx_oct), .c_tx(c_tx[PNG]), .a_tx(a_tx[PNG]),
        .word_pin(word[PNG]), .ans_n());
    assign dt_bit = c_tx[PDT];
    assign ng_bit = c_tx[PNG];

    // ---- the lines ---------------------------------------------------------
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

    // ---- the sinks: half a card.  Nothing to send, no hook, no word --------
    assign c_tx[PS0] = fill;  assign a_tx[PS0] = 1'b0;  assign word[PS0] = 1'b0;
    assign c_tx[PS1] = fill;  assign a_tx[PS1] = 1'b0;  assign word[PS1] = 1'b0;
    assign sink_rx   = {c_rx[PS1], c_rx[PS0]};

    // ---- the ring source: three ties -------------------------------------
    // A_TX high, /ANS low (PORT_RINGS clears it), and no word.  The card's own
    // C_TX is FILL in an exchange -- silence, or a looping "please hold"
    // (features.md 3); here the testbench drives it with a pattern, so
    // that a party parked on it can be told apart from a party hearing nothing.
    assign c_tx[PRS] = tx[PRS];  assign a_tx[PRS] = 1'b1;  assign word[PRS] = 1'b0;

    // every slot no card drives: C pulled to FILL, A and the word to 0
    genvar q;
    generate for (q = 0; q < 64; q = q + 1)
        if (!LINE_PORTS[q] && !SINKS[q] && !RSRC[q] && q != PDT && q != PNG) begin : empty
            assign c_tx[q] = fill; assign a_tx[q] = 1'b0; assign word[q] = 1'b0;
        end
    endgenerate

    // ---- common control ----------------------------------------------------
    wire [NREG-1:0]    r_busy, r_gone, r_brk, r_attach, r_release, r_restart;
    wire [NREG-1:0]    r_nodig;
    wire [3*NREG-1:0]  r_ndig;
    wire [16*NREG-1:0] r_digits;
    wire [6*NREG-1:0]  r_held;
    wire [5:0]         r_port, r_src;
    assign regs_busy = r_busy;

    genvar gr;
    generate for (gr = 0; gr < NREG; gr = gr + 1) begin : regs
        pulse_reg #(.HIT(HIT), .ID(ID), .CLR(CLR), .NODIG(NODIG)) u_reg (
            .clk(clk), .rst_n(rst_n), .slotq(slotq), .tick(tick), .tick_1k(tick_1k),
            .ha(ha), .attach(r_attach[gr]), .attach_port(r_port), .attach_src(r_src),
            .release_it(r_release[gr]), .restart(r_restart[gr]),
            .busy(r_busy[gr]), .port(), .src(r_held[gr*6 +: 6]),
            .ndig(r_ndig[gr*3 +: 3]), .digits(r_digits[gr*16 +: 16]),
            .gone(r_gone[gr]), .nodig(r_nodig[gr]), .brk(r_brk[gr]));
    end endgenerate

    marker #(.NREG(NREG), .NRES(1), .DIALTONE(PDT), .NOGO(PNG),
             .HAS_NET(1'b0), .HAS_CON(!NAIVE)) u_mk (
        .clk(clk), .rst_n(rst_n),
        .slotq(slotq), .tick(tick), .frame_stb(frame_stb),
        .oct_stb(oct_stb), .tick_1k(tick_1k),
        .ha(ha), .pb_busy(pb_busy), .pb_word(pb_word),
        .sdata(mk_sdata), .sclk(mk_sclk), .wr(mk_wr),
        .reg_attach(r_attach), .reg_port(r_port), .reg_src(r_src),
        .reg_busy(r_busy),
        .reg_ndig(r_ndig), .reg_digits(r_digits), .reg_held(r_held),
        .reg_restart(r_restart),
        .reg_gone(r_gone), .reg_nodig(r_nodig), .reg_brk(r_brk), .reg_release(r_release),
        .mon_claim(1'b0), .mon_port(6'd0), .mon_ack(),
        .any_claimed(), .dirs_held(), .fan_legs(), .res_used(),
        .wq_ovf(wq_ovf), .n_defer(),
        .wr_stb(wr_stb), .wr_dst(wr_dst), .wr_src(wr_src),
        .wr_bsy(wr_bsy), .wr_clm(wr_clm),
        .con_n(con_n), .bus_oe(mk_oe));

    console #(.DIV(CON_DIV), .WAIT(NAIVE ? 0 : CON_WAIT)) u_con (
        .clk(clk), .rst_n(rst_n),
        .key_write(key_write), .key_release(key_release), .key_probe(key_probe),
        .key_hold(key_hold), .key_arm(key_arm), .sw_both(sw_both),
        .sw_dst(sw_dst), .sw_src(sw_src), .sw_bsy(sw_bsy), .sw_clm(sw_clm),
        .busy(con_busy), .done(con_done),
        .con_n(con_n), .oe(con_oe),
        .sdata(cn_sdata), .sclk(cn_sclk), .wr(cn_wr),
        .bus_sdata(b_sdata), .bus_sclk(b_sclk), .bus_wr(b_wr),
        .watch_src(watch_src), .watch_bsy(watch_bsy),
        .watch_clm(watch_clm), .watch_seen(watch_seen),
        // cable A, and the probe bus: what the console can read
        .ha(ha), .slotq(slotq), .tick(tick),
        .frame_stb(frame_stb), .tx_oct(tx_oct),
        .hook_dst(hook_dst), .hook_src(hook_src),
        .pb_busy(pb_busy), .pb_word(pb_word),
        .sup_busy_dst(sup_busy_dst), .sup_busy_src(sup_busy_src),
        .sup_word_dst(sup_word_dst), .sup_word_src(sup_word_src),
        .sup_seen(sup_seen));
endmodule
