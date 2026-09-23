// mini_net_site -- mini-marker exchange, optional network unit or LEAF uplink.
//
// HAS_NET=0, LEAF=0: solo / highway-1 (no trunks, no unit).
// HAS_NET=1: pulse flood with a jumpered trunk mask.  NDIR=1 leaf; NDIR=2 transit; NDIR=4 hub.
// LEAF=1 (HAS_NET=0): digit 1 hunts block-1 trunks toward a tone-offering parent.
// Trunks on blocks 1,3,4,5 (same map as net_site).  One register inside.
`timescale 1ns/1ps

module mini_net_site #(
    parameter         HAS_NET = 1'b1,
    parameter         LEAF    = 1'b0,
    parameter integer NDIR    = 1,
    parameter integer NRES    = 1,
    parameter [2:0]   OWN_E = 3'd2,
    parameter [2:0]   OWN_B = 3'd2,
    parameter [1:0]   DIR0  = 2'd2,
    parameter         G0    = 1'b0,
    parameter         N0    = 1'b0,
    parameter [1:0]   DIR1  = 2'd3,
    parameter         G1    = 1'b0,
    parameter         N1    = 1'b0,
    parameter [1:0]   DIR2  = 2'd0,
    parameter         G2    = 1'b0,
    parameter         N2    = 1'b0,
    parameter [1:0]   DIR3  = 2'd1,
    parameter         G3    = 1'b0,
    parameter         N3    = 1'b0,
    // TONEn: the trunk is class tone trunk, not class trunk (leaf-uplink.md 3).
    parameter         TONE0 = 1'b0,
    parameter         TONE1 = 1'b0,
    parameter         TONE2 = 1'b0,
    parameter         TONE3 = 1'b0,
    parameter integer T_RISE = 64, T_FALL = 2048,
    parameter integer RING_ON = 200, RING_OFF = 400,
    parameter integer T_A = 4,
    parameter integer HIT = 1, ID = 16, CLR = 32,
    parameter integer T_GUARD = 16, T_CLAIM = 250,
    parameter [63:0]  LINE_PORTS = 64'h0000_0000_0003_0000,
    parameter integer NMON = 2,
    parameter integer NODIG = 2000
)(
    input         clk,
    input         rst_n,
    input  [63:0] hook,
    input  [63:0] tx,
    output [63:0] rx,
    output [63:0] e,
    input  [3:0]  line_in,
    output [3:0]  line_out,
    output [3:0]  locked,
    output        frame_stb,
    output        tick_1k,
    output        ring_cad_n,
    output        dt_bit, ng_bit,
    output        mon_held,
    output        got_claim,
    output [3:0]  dirs_held,
    output [63:0] port_busy,
    output        reg_busy,
    output        wq_ovf,
    output        wr_stb,
    output [5:0]  wr_dst, wr_src,
    output        wr_bsy, wr_clm
);
    localparam PDT = 6'o01, PBSY = 6'o02, PNG = 6'o03;
    // Offers-tone is a class now: tone trunk 110, options MBZ -- it is no
    // flood seat, so it faces no direction and carries no glare.  A flood
    // trunk is class 010 with G at frame 5 and DIR at frames 6-7.
    localparam [15:0] WORD0 = TONE0 ? {8'hFF, 3'b000, 3'b110, 2'b11}
                                    : {8'hFF, DIR0, G0, 3'b010, 2'b11};
    localparam [15:0] WORD1 = TONE1 ? {8'hFF, 3'b000, 3'b110, 2'b11}
                                    : {8'hFF, DIR1, G1, 3'b010, 2'b11};
    localparam [15:0] WORD2 = TONE2 ? {8'hFF, 3'b000, 3'b110, 2'b11}
                                    : {8'hFF, DIR2, G2, 3'b010, 2'b11};
    localparam [15:0] WORD3 = TONE3 ? {8'hFF, 3'b000, 3'b110, 2'b11}
                                    : {8'hFF, DIR3, G3, 3'b010, 2'b11};
    localparam [3:0]  STRAP_N = ({3'b000, N0} << DIR0) | ({3'b000, N1} << DIR1)
                              | ({3'b000, N2} << DIR2) | ({3'b000, N3} << DIR3);

    localparam         FIT_TRUNK0 = HAS_NET || LEAF || TONE0;
    localparam [63:0] TRUNKS = FIT_TRUNK0
        ? (64'h0000_0000_0000_EE00
           | ((HAS_NET && NDIR >= 2) ? 64'h0000_0000_EE00_0000 : 64'd0)
           | ((HAS_NET && NDIR >= 3) ? 64'h0000_00EE_0000_0000 : 64'd0)
           | ((HAS_NET && NDIR >= 4) ? 64'h0000_EE00_0000_0000 : 64'd0))
        : 64'd0;
    // Flood mask: fitted trunks that are NOT offers-tone (tone seats are callers).
    // Parent with TONE0 and no HAS_NET: FLOOD_TRUNKS=0 so mini treats trunks as callers.
    localparam [63:0] FLOOD_TRUNKS = HAS_NET
        ? ( (TONE0 ? 64'd0 : 64'h0000_0000_0000_EE00)
          | ((NDIR >= 2 && !TONE1) ? 64'h0000_0000_EE00_0000 : 64'd0)
          | ((NDIR >= 3 && !TONE2) ? 64'h0000_00EE_0000_0000 : 64'd0)
          | ((NDIR >= 4 && !TONE3) ? 64'h0000_EE00_0000_0000 : 64'd0))
        : 64'd0;
    localparam [63:0] UPLINK = LEAF ? 64'h0000_0000_0000_EE00 : 64'd0;
    localparam [63:0] PF = LINE_PORTS | 64'h0000_0000_0000_000E | TRUNKS;
    localparam [7:0]  BF = {|PF[63:56], |PF[55:48], |PF[47:40], |PF[39:32],
                            |PF[31:24], |PF[23:16], |PF[15:8],  |PF[7:0]};

    // Direction a trunk port (mini has no card word).  Blocks 1,3,4,5.
    function automatic [127:0] dir_bits(input [1:0] d, input integer b0);
        dir_bits = ({{126{1'b0}}, d} << ((b0+1)*2)) | ({{126{1'b0}}, d} << ((b0+2)*2)) |
                   ({{126{1'b0}}, d} << ((b0+3)*2)) | ({{126{1'b0}}, d} << ((b0+5)*2)) |
                   ({{126{1'b0}}, d} << ((b0+6)*2)) | ({{126{1'b0}}, d} << ((b0+7)*2));
    endfunction
    localparam [127:0] TRUNK_DIR =
        (FIT_TRUNK0            ? dir_bits(DIR0,  8) : 128'd0) |
        ((HAS_NET && NDIR>=2) ? dir_bits(DIR1, 24) : 128'd0) |
        ((HAS_NET && NDIR>=3) ? dir_bits(DIR2, 32) : 128'd0) |
        ((HAS_NET && NDIR>=4) ? dir_bits(DIR3, 40) : 128'd0);

    wire [63:0] c_tx, a_tx, word, c_rx, a_rx;
    wire [2:0]  slot, slotq, tick;
    wire        tx_oct, fill, pb_busy;
    wire [7:0]  ha;
    wire [63:0] pbusy;
    wire        sdata, sclk, wr;
    wire [31:0] t_c_tx, t_a_tx, t_word;
    wire        oct_stb = frame_stb & tx_oct;
    wire [2:0]  scan_port;

    assign port_busy = pbusy;

    exch_top #(.BLOCK_FITTED(BF),
               .PORT_FITTED (PF),
               .PORT_RINGS  (LINE_PORTS),
               .RBT_IS_FILL(1'b1),
               .T_RISE(T_RISE), .T_FALL(T_FALL),
               .RING_ON(RING_ON), .RING_OFF(RING_OFF))
    u_exch (.clk(clk), .rst_n(rst_n),
            .c_tx(c_tx), .a_tx(a_tx), .word(word), .c_rx(c_rx), .a_rx(a_rx),
            .sdata(sdata), .sclk(sclk), .wr(wr),
            .con_n(1'b1), .scan_port(scan_port),
            .pb_busy(pb_busy), .pb_word(), .port_busy(pbusy),
            .hc(), .ha(ha),
            .slot(slot), .slotq(slotq), .tick(tick), .hclk(), .line_hb(), .tx_clk(),
            .frame_stb(frame_stb), .tx_oct(tx_oct), .rx_oct(),
            .fill(fill), .ring_cad_n(ring_cad_n), .tick_1k(tick_1k));

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

    genvar p;
    generate for (p = 0; p < 64; p = p + 1) begin : line
        if (LINE_PORTS[p]) begin : fitted
            line_card u_c (
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

    wire [3:0]     mc_v, mh_v;
    wire [4*6-1:0] mp_v;
    wire [3:0]     mack_v;

    genvar g, k;
    generate for (g = 0; g < 4; g = g + 1) begin : dir
        if ((g == 0 && FIT_TRUNK0) || (HAS_NET && g < NDIR && g > 0)) begin : fitted
            localparam integer B = (g == 0) ? 1 : (g == 1) ? 3 : (g == 2) ? 4 : 5;
            localparam [15:0] W = (g == 0) ? WORD0 : (g == 1) ? WORD1 :
                                 (g == 2) ? WORD2 : WORD3;
            localparam         DO_MON = HAS_NET && !(g == 0 ? TONE0 : g == 1 ? TONE1 :
                                                     g == 2 ? TONE2 : TONE3);

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

            if (DO_MON) begin : mon
                monitor #(.NMON(NMON), .OWN_E(OWN_E), .OWN_B(OWN_B), .BLOCK(B[2:0]),
                          .HIT(HIT), .ID(ID), .CLR(CLR)) u_mon (
                    .clk(clk), .rst_n(rst_n), .oct_stb(oct_stb), .tick_1k(tick_1k),
                    .m(t_a_tx[g*8 +: 8]), .busy(pbusy[B*8 +: 8]),
                    .chan_mask(8'b1110_1110),
                    .claim(mc_v[g]), .claim_port(mp_v[g*6 +: 6]),
                    .claim_ack(mack_v[g]), .held(mh_v[g]), .all_busy(), .cells());
            end else begin : nomon
                assign mc_v[g] = 1'b0;
                assign mp_v[g*6 +: 6] = 6'd0;
                assign mh_v[g] = 1'b0;
            end
        end else begin : absent
            assign mc_v[g] = 1'b0;
            assign mp_v[g*6 +: 6] = 6'd0;
            assign mh_v[g] = 1'b0;
            assign line_out[g] = 1'b0;
            assign locked[g] = 1'b1;
            assign t_c_tx[g*8 +: 8] = 8'h00;
            assign t_a_tx[g*8 +: 8] = 8'h00;
            assign t_word[g*8 +: 8] = 8'h00;
        end
    end endgenerate

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
    assign mack_v   = {4{mack}} & sel;
    assign mon_held = |mh_v;

    genvar q;
    generate for (q = 0; q < 64; q = q + 1)
        if (!TRUNKS[q] && !LINE_PORTS[q] && q != PDT && q != PBSY && q != PNG) begin : empty
            assign c_tx[q] = fill; assign a_tx[q] = 1'b0; assign word[q] = 1'b0;
        end
    endgenerate

    wire [5:0]  pr_port;
    wire        pr_visit, pr_valid, pr_m, pr_busy;
    wire [15:0] pr_word;
    wire        flood_go, net_restart, net_done, net_nogo, net_local;
    wire [5:0]  flood_caller;
    wire        net_att;
    wire [5:0]  net_att_port;
    wire [3:0]  net_nw;
    wire [47:0] net_wdst, net_wsrc;
    wire [7:0]  net_wbsy, net_wclm, net_wev;
    wire        r_gone, r_brk;
    wire [2:0]  r_ndig;
    wire [15:0] r_digits;

    mini_marker #(.HIT(HIT), .ID(ID), .CLR(CLR), .NODIG(NODIG),
                  .DIALTONE(PDT), .NOGO(PNG),
                  .HAS_NET(HAS_NET), .LEAF(LEAF),
                  .TRUNK_MASK(FLOOD_TRUNKS), .UPLINK_MASK(UPLINK))
    u_mk (
        .clk(clk), .rst_n(rst_n),
        .slotq(slotq), .tick(tick), .frame_stb(frame_stb),
        .oct_stb(oct_stb), .tick_1k(tick_1k),
        .ha(ha), .pb_busy(pb_busy),
        .sdata(sdata), .sclk(sclk), .wr(wr),
        .probe_port(pr_port), .scan_port(scan_port),
        .probe_visit(pr_visit), .probe_valid(pr_valid),
        .probe_m(pr_m), .probe_busy(pr_busy), .probe_word(pr_word),
        .flood_go(flood_go), .flood_caller(flood_caller),
        .net_restart(net_restart), .net_done(net_done),
        .net_nogo(net_nogo), .net_local(net_local),
        .net_att(net_att), .net_att_port(net_att_port),
        .net_nw(net_nw), .net_wdst(net_wdst), .net_wsrc(net_wsrc),
        .net_wbsy(net_wbsy), .net_wclm(net_wclm), .net_wev(net_wev),
        .reg_busy(reg_busy), .reg_gone(r_gone), .reg_nodig(),
        .reg_brk(r_brk), .reg_ndig(r_ndig), .reg_digits(r_digits),
        .wq_ovf(wq_ovf),
        .wr_stb(wr_stb), .wr_dst(wr_dst), .wr_src(wr_src),
        .wr_bsy(wr_bsy), .wr_clm(wr_clm));

    generate if (HAS_NET) begin : net
        net_unit #(.NREG(1), .NRES(NRES),
                   .OWN_E(OWN_E), .OWN_B(OWN_B),
                   .NOGO(PNG), .STRAP_N(STRAP_N),
                   .T_GUARD(T_GUARD), .T_CLAIM(T_CLAIM),
                   .TRUNK_MASK(FLOOD_TRUNKS), .TRUNK_DIR(TRUNK_DIR))
        u_net (
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
            .fan_legs(), .res_used());
    end else begin : none
        assign net_restart = 1'b0;
        assign net_done = 1'b0;
        assign net_nogo = 1'b0;
        assign net_local = 1'b0;
        assign net_att = 1'b0;
        assign net_att_port = 6'd0;
        assign net_nw = 4'd0;
        assign net_wdst = 48'd0;
        assign net_wsrc = 48'd0;
        assign net_wbsy = 8'd0;
        assign net_wclm = 8'd0;
        assign net_wev = 8'd0;
        assign mack = 1'b0;
        assign got_claim = 1'b0;
        assign dirs_held = 4'd0;
    end endgenerate
endmodule
