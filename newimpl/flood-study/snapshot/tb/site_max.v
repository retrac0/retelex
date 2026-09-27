// site_max -- one maximal exchange, with its cards: the plant the class
// marker's benches are built from.  For a bench.
//
// top_max, and a card in every socket that has one:
//   PHONES   sockets with something the bench works by hand: hook and tx in,
//            rx and e out.  Each card's word is PWORD's octet for it, on one
//            '165 -- FF is the grounded pin of a plain line, the constant a
//            card with no word parts reads -- and PANS ties its /ANS low: an
//            outside line, a source, anything that must answer at once
//   01-03    the tone sources: dial tone sends ones, busy tone four ones and
//            four zeros, cannot-complete zeros.  Each ties /ANS low and has no
//            word part: tones are addresses (features.md 2)
//   TRUNKS   baseband tie cards, each with its word from TWORD and its rear
//            connector brought out, as site_net's
//
// The block jumpers fitted are the blocks with anything in them.  Nothing in
// here reaches inside a board.
`timescale 1ns/1ps
`include "exch.vh"

module site_max #(
    parameter [63:0]  PHONES   = 64'h0000_0000_0003_0000,     // 20, 21
    parameter [511:0] PWORD    = {64{8'hFF}},                 // each phone card's octet
    parameter [63:0]  PANS     = 64'd0,                       // phones with /ANS low
    parameter [63:0]  TRUNKS   = 64'd0,
    parameter [511:0] TWORD    = {64{8'b10_0_010_11}},        // each trunk's octet
    parameter         UNIT     = 1'b0,                        // the network unit fitted
    parameter [2:0]   OWN_E    = 3'd2,
    parameter [2:0]   OWN_B    = 3'd2,
    parameter [3:0]   STRAP_N  = 4'b0000,
    parameter integer NMON     = 2,
    parameter integer NRES     = 2,
    parameter [4:0]   WALK     = 5'd4,
    // the windows and timers, scaled by the bench
    parameter [8:0]   T_ARM    = 9'd16,
    parameter [8:0]   T_REL    = 9'd256,
    parameter [12:0]  RING_ON  = 13'd2048,
    parameter [12:0]  RING_OFF = 13'd4096,
    parameter [8:0]   HIT      = 9'd8,
    parameter [8:0]   ID       = 9'd128,
    parameter [8:0]   CLR      = 9'd256,
    parameter [15:0]  NODIG    = 16'd10000,
    parameter [15:0]  T_GUARD0 = 16'd128,
    parameter [15:0]  T_KEY    = 16'd5000,
    parameter [15:0]  T_CLAIM  = 16'd2000,
    parameter [15:0]  HOLDOFF  = 16'd64
)(
    input         clk,
    input         rst_n,

    // ---- the phones: hook and speech, a bit a frame ------------------------
    input  [63:0] hook,
    input  [63:0] tx,
    output [63:0] rx,
    output [63:0] e,

    // ---- the trunk cards' rear connectors, one set a socket ------------------
    output [63:0] c_out,
    output [63:0] a_out,
    output [63:0] clk_out,
    input  [63:0] c_in,
    input  [63:0] a_in,
    input  [63:0] clk_in,
    output [63:0] link_up,

    // ---- what the bench watches ----------------------------------------------
    output        frame_stb,
    output        tick_1k,
    output        ws_sel_n,      // /WS: every reader's select, for a bench that counts them
    output        ring_cad_n,
    output [63:0] port_busy,
    output        b_sdata, b_sclk, b_wr, b_clash,
    output        reg_busy,
    output [`PW-1:0] caller,
    output [`PW-1:0] called,
    output [3:0]  mk_state,
    output        mk_pwait,
    output        mk_ovf,
    output [3:0]  dirs_held,
    output [NRES-1:0] res_busy,
    output [NMON-1:0] mon_held,
    output        claimed,
    output        hunting,
    output        un_ovf,
    output [7:0]  n_glare,
    output [7:0]  n_nofwd
);
    localparam [`PW-1:0] DT = 6'o01, BT = 6'o02, NG = 6'o03;
    localparam [63:0] TONES = (64'd1 << DT) | (64'd1 << BT) | (64'd1 << NG);
    localparam [63:0] PF    = PHONES | TRUNKS | TONES;
    localparam [7:0]  BF    = {|PF[63:56], |PF[55:48], |PF[47:40], |PF[39:32],
                               |PF[31:24], |PF[23:16], |PF[15:8],  |PF[7:0]};

    wire [63:0] c_rx, a_rx;
    wire [63:0] t_c_tx, t_a_tx, t_word_n, t_ans_n, t_rai_n;
    wire        tx_clk, loop_hb, clk_8k, rx_oct, fill, hclk;
    wire        ha_n, hb_n, hw_n, ws_n;
    wire [`SCANW-1:0] scan;

    // ---- the frame edge, and each phone card's '165 --------------------------
    // SH/LD is TX_OCT . TX_CLK and it shifts on TX_CLK's rise, as the trunk
    // card's does (baseband_card.v): frame 7 carries bit 0.
    reg        tx_d;
    wire       frame_edge = tx_clk && !tx_d;
    wire       ld = clk_8k && tx_clk;
    reg [511:0] wsh;
    reg [2:0]  bt_ph;                  // the busy tone: four frames up, four down
    integer    k;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin tx_d <= 1'b0; wsh <= {64{8'hFF}}; bt_ph <= 3'd0; end
        else begin
            tx_d <= tx_clk;
            for (k = 0; k < 64; k = k + 1) begin
                if (ld)              wsh[k*8 +: 8] <= PWORD[k*8 +: 8];
                else if (frame_edge) wsh[k*8 +: 8] <= {1'b1, wsh[k*8+1 +: 7]};
            end
            if (frame_edge) bt_ph <= bt_ph + 3'd1;
        end
    end

    // ---- the sockets: what each card drives -----------------------------------
    reg [63:0] s_c, s_a, s_word, s_ans;
    integer p;
    always @* begin
        for (p = 0; p < 64; p = p + 1) begin
            s_c[p] = 1'b0; s_a[p] = 1'b0; s_word[p] = 1'b1; s_ans[p] = 1'b1;
            if (PHONES[p]) begin
                s_c[p] = tx[p]; s_a[p] = hook[p];
                s_word[p] = !wsh[p*8];
                s_ans[p]  = !PANS[p];
            end
            if (TRUNKS[p]) begin
                s_c[p] = t_c_tx[p]; s_a[p] = t_a_tx[p];
                s_word[p] = t_word_n[p]; s_ans[p] = t_ans_n[p];
            end
        end
        s_c[DT] = 1'b1;     s_ans[DT] = 1'b0;
        s_c[BT] = bt_ph[2]; s_ans[BT] = 1'b0;
        s_c[NG] = 1'b0;     s_ans[NG] = 1'b0;
    end

    top_max #(.PORT_FITTED(PF), .BLOCK_FITTED(BF),
              .T_ARM(T_ARM), .T_REL(T_REL),
              .RING_ON_MS(RING_ON), .RING_OFF_MS(RING_OFF),
              .HIT(HIT), .ID(ID), .CLR(CLR), .NODIG(NODIG), .WALK(WALK),
              .UNIT_FITTED(UNIT), .OWN_E(OWN_E), .OWN_B(OWN_B), .STRAP_N(STRAP_N),
              .NMON(NMON), .NRES(NRES),
              .T_GUARD0(T_GUARD0), .T_KEY(T_KEY), .T_CLAIM(T_CLAIM)) u_x (
        .clk(clk), .rst_n(rst_n),
        .c_tx(s_c), .a_tx(s_a), .ans_n(s_ans), .word_n(s_word),
        .c_rx(c_rx), .a_rx(a_rx), .mute_blk(8'd0), .rbt_in(1'b0),
        .tx_clk(tx_clk), .loop_hb(loop_hb), .clk_8k(clk_8k), .rx_oct(rx_oct),
        .fill(fill), .hclk(hclk),
        .ha_n(ha_n), .hb_n(hb_n), .hw_n(hw_n), .ws_n(ws_n), .scan(scan),
        .frame_stb(frame_stb), .tick_1k(tick_1k), .ring_cad_n(ring_cad_n),
        .port_busy(port_busy),
        .b_sdata(b_sdata), .b_sclk(b_sclk), .b_wr(b_wr), .b_clash(b_clash),
        .reg_busy(reg_busy), .caller(caller), .called(called),
        .mk_state(mk_state), .mk_pwait(mk_pwait), .mk_ovf(mk_ovf),
        .dirs_held(dirs_held), .res_busy(res_busy), .mon_held(mon_held),
        .claimed(claimed), .hunting(hunting), .un_ovf(un_ovf),
        .n_glare(n_glare), .n_nofwd(n_nofwd));

    assign rx = c_rx;
    assign e  = a_rx;
    assign ws_sel_n = ws_n;

    // ---- a baseband card in every trunk socket --------------------------------
    genvar q;
    generate for (q = 0; q < 64; q = q + 1) begin : sock
        if (TRUNKS[q]) begin : trunk
            baseband_card #(.WORD(TWORD[q*8 +: 8]), .HOLDOFF(HOLDOFF)) u_card (
                .clk(clk), .rst_n(rst_n),
                .tx_clk(tx_clk), .loop_hb(loop_hb), .tx_oct(clk_8k), .fill(fill),
                .c_tx(t_c_tx[q]), .a_tx(t_a_tx[q]),
                .rx_clk(tx_clk), .rx_oct(rx_oct),
                .c_rx(c_rx[q]), .a_rx(a_rx[q]), .mute(1'b0),
                .word_n(t_word_n[q]), .ans_n(t_ans_n[q]), .rai_n(t_rai_n[q]),
                .c_out(c_out[q]), .a_out(a_out[q]), .clk_out(clk_out[q]),
                .c_in(c_in[q]), .a_in(a_in[q]), .clk_in(clk_in[q]),
                .link_up(link_up[q]));
        end else begin : empty
            assign t_c_tx[q] = 1'b0; assign t_a_tx[q] = 1'b0;
            assign t_word_n[q] = 1'b1; assign t_ans_n[q] = 1'b1; assign t_rai_n[q] = 1'b1;
            assign c_out[q] = 1'b0; assign a_out[q] = 1'b0; assign clk_out[q] = 1'b0;
            assign link_up[q] = 1'b0;
        end
    end endgenerate

    wire _unused = &{1'b0, loop_hb, rx_oct, fill, hclk, ha_n, hb_n, hw_n,
                     scan, t_rai_n, 1'b0};
endmodule
