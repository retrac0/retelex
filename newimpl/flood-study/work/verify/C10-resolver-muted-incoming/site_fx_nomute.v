// site_fx -- AUDIT COPY of tb/site_net.v (fwd slice): adds the clock outputs a
// bench-side far local_trunk needs.  Otherwise identical.
// site_net -- one exchange on a network, with its cards: the plant the network
// benches are built from.  For a bench.
//
// top_net, and a card in every socket that has one:
//   PHONES   sockets with a phone on a line card: the bench works hook and
//            tx and reads rx and e.  The card is a stand-in (tb_mini's): word
//            pin grounded, a plain line; /ANS open, it rings
//   01, 03   the tone sources: dial tone sends ones, cannot-complete zeros,
//            and both tie /ANS low so they never ring (tb_mini's)
//   TRUNKS   sockets with a baseband tie card (baseband.md), each with its own
//            word from TWORD -- class trunk, glare, direction -- and its rear
//            connector brought out, for the bench to cable to another site
//   LTU      blocks stuffed as a local eight-channel trunk (local-trunk.md): the
//            unit on the block header, its word from LTWORD, its MUTE_BLK on the
//            block and its link brought out.  All eight sockets of such a block
//            are its; nothing else may be put in them
//
// The block jumpers fitted are the blocks with anything in them.  Nothing in
// here reaches inside a board.
`timescale 1ns/1ps
`include "exch.vh"

module site_fx #(
    parameter [63:0]  PHONES   = 64'h0000_0000_0003_0000,     // 20, 21
    parameter [63:0]  TRUNKS   = 64'h0000_0000_0000_0600,     // 11, 12
    parameter [511:0] TWORD    = {64{8'b10_0_010_11}},        // each trunk's primary octet
    parameter [2:0]   OWN_E    = 3'd2,
    parameter [2:0]   OWN_B    = 3'd2,
    parameter [3:0]   STRAP_N  = 4'b0000,
    parameter integer NMON     = 2,
    parameter integer NRES     = 2,
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
    parameter [15:0]  HOLDOFF  = 16'd64,
    parameter [7:0]   LTU      = 8'd0,                        // blocks stuffed as a local trunk
    parameter [63:0]  LTWORD   = {8{8'b10_0_010_11}}          // each such block's word
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

    // ---- each local trunk unit's link, one bit a block --------------------------
    output [7:0]  lt_c_out,
    output [7:0]  lt_a_out,
    output [7:0]  lt_h_out,
    output [7:0]  lt_k_out,
    input  [7:0]  lt_c_in,
    input  [7:0]  lt_a_in,
    input  [7:0]  lt_h_in,
    input  [7:0]  lt_k_in,
    output [7:0]  lt_up,

    // ---- AUDIT (fwd slice): the clocks a bench-side far LTU needs ----------------
    output        o_tx_clk, o_clk_8k, o_fill, o_hclk,

    // ---- what the bench watches ----------------------------------------------
    output        frame_stb,
    output        tick_1k,
    output        ring_cad_n,
    output [63:0] port_busy,
    output        b_sdata, b_sclk, b_wr, b_clash,
    output        reg_busy,
    output [2:0]  mk_state,
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
    localparam [`PW-1:0] DT = 6'o01, NG = 6'o03;
    localparam [63:0] TONES = (64'd1 << DT) | (64'd1 << NG);
    localparam [63:0] LTP   = {{8{LTU[7]}}, {8{LTU[6]}}, {8{LTU[5]}}, {8{LTU[4]}},
                               {8{LTU[3]}}, {8{LTU[2]}}, {8{LTU[1]}}, {8{LTU[0]}}};
    localparam [63:0] PF    = PHONES | TRUNKS | TONES | LTP;
    localparam [7:0]  BF    = {|PF[63:56], |PF[55:48], |PF[47:40], |PF[39:32],
                               |PF[31:24], |PF[23:16], |PF[15:8],  |PF[7:0]};

    wire [63:0] c_rx, a_rx;
    wire [63:0] t_c_tx, t_a_tx, t_word_n, t_ans_n, t_rai_n;
    wire        tx_clk, loop_hb, clk_8k, rx_oct, fill, hclk;
    wire [63:0] l_c_tx, l_a_tx, l_word_n, l_ans_n;
    wire [7:0]  l_mute;
    wire        ha_n, hb_n, hw_n;
    wire [`SCANW-1:0] scan;

    // ---- the sockets: what each card drives -----------------------------------
    // A phone's card: C and M from the bench, word grounded, /ANS open.
    // A tone source: a steady level, /ANS low, no word part.
    // A trunk: its card's four outputs.
    reg [63:0] s_c, s_a, s_word, s_ans;
    integer p;
    always @* begin
        for (p = 0; p < 64; p = p + 1) begin
            s_c[p] = 1'b0; s_a[p] = 1'b0; s_word[p] = 1'b1; s_ans[p] = 1'b1;
            if (PHONES[p]) begin
                s_c[p] = tx[p]; s_a[p] = hook[p]; s_word[p] = 1'b0;
            end
            if (TRUNKS[p]) begin
                s_c[p] = t_c_tx[p]; s_a[p] = t_a_tx[p];
                s_word[p] = t_word_n[p]; s_ans[p] = t_ans_n[p];
            end
            if (LTP[p]) begin
                s_c[p] = l_c_tx[p]; s_a[p] = l_a_tx[p];
                s_word[p] = l_word_n[p]; s_ans[p] = l_ans_n[p];
            end
        end
        s_c[DT] = 1'b1; s_ans[DT] = 1'b0;
        s_c[NG] = 1'b0; s_ans[NG] = 1'b0;
    end

    top_net #(.PORT_FITTED(PF), .BLOCK_FITTED(BF),
              .T_ARM(T_ARM), .T_REL(T_REL),
              .RING_ON_MS(RING_ON), .RING_OFF_MS(RING_OFF),
              .HIT(HIT), .ID(ID), .CLR(CLR), .NODIG(NODIG),
              .OWN_E(OWN_E), .OWN_B(OWN_B), .STRAP_N(STRAP_N),
              .NMON(NMON), .NRES(NRES),
              .T_GUARD0(T_GUARD0), .T_KEY(T_KEY), .T_CLAIM(T_CLAIM)) u_x (
        .clk(clk), .rst_n(rst_n),
        .c_tx(s_c), .a_tx(s_a), .ans_n(s_ans), .word_n(s_word),
        .c_rx(c_rx), .a_rx(a_rx), .mute_blk(8'd0), .rbt_in(1'b0),
        .tx_clk(tx_clk), .loop_hb(loop_hb), .clk_8k(clk_8k), .rx_oct(rx_oct),
        .fill(fill), .hclk(hclk),
        .ha_n(ha_n), .hb_n(hb_n), .hw_n(hw_n), .scan(scan),
        .frame_stb(frame_stb), .tick_1k(tick_1k), .ring_cad_n(ring_cad_n),
        .port_busy(port_busy),
        .b_sdata(b_sdata), .b_sclk(b_sclk), .b_wr(b_wr), .b_clash(b_clash),
        .reg_busy(reg_busy), .caller(), .mk_state(mk_state), .mk_ovf(mk_ovf),
        .dirs_held(dirs_held), .res_busy(res_busy), .mon_held(mon_held),
        .claimed(claimed), .hunting(hunting), .un_ovf(un_ovf),
        .n_glare(n_glare), .n_nofwd(n_nofwd));

    assign rx = c_rx;
    assign o_tx_clk = tx_clk; assign o_clk_8k = clk_8k; assign o_fill = fill; assign o_hclk = hclk;
    assign e  = a_rx;

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

    // ---- a local trunk unit on every block stuffed as one ---------------------
    genvar h;
    generate for (h = 0; h < 8; h = h + 1) begin : blk
        if (LTU[h]) begin : ltu
            local_trunk #(.WORD(LTWORD[h*8 +: 8]), .HOLDOFF(HOLDOFF)) u_ltu (
                .clk(clk), .rst_n(rst_n),
                .c_tx(l_c_tx[h*8 +: 8]), .a_tx(l_a_tx[h*8 +: 8]),
                .word_n(l_word_n[h*8 +: 8]), .ans_n(l_ans_n[h*8 +: 8]),
                .c_rx(c_rx[h*8 +: 8]), .a_rx(a_rx[h*8 +: 8]),
                .tx_clk(tx_clk), .tx_oct(clk_8k), .fill(fill), .hclk(hclk),
                .mute_blk(l_mute[h]),
                .c_out(lt_c_out[h]), .a_out(lt_a_out[h]),
                .hclk_out(lt_h_out[h]), .clk_out(lt_k_out[h]),
                .c_in(lt_c_in[h]), .a_in(lt_a_in[h]),
                .hclk_in(lt_h_in[h]), .clk_in(lt_k_in[h]),
                .link_up(lt_up[h]));
        end else begin : none
            assign l_c_tx[h*8 +: 8] = 8'd0; assign l_a_tx[h*8 +: 8] = 8'd0;
            assign l_word_n[h*8 +: 8] = 8'hFF; assign l_ans_n[h*8 +: 8] = 8'hFF;
            assign l_mute[h] = 1'b0;
            assign lt_c_out[h] = 1'b0; assign lt_a_out[h] = 1'b0;
            assign lt_h_out[h] = 1'b0; assign lt_k_out[h] = 1'b0;
            assign lt_up[h] = 1'b0;
        end
    end endgenerate
endmodule
