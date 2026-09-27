// tb_hub1 -- C19 verify copy of work/load/hub/tb_hub.sv (+define+HUB_STRAP1 added).
// tb_hub -- TRAFFIC LOAD on a STAR: a hub and three leaves, local trunks.
// The harness is load_harness.svh (the hub copy beside this file: it adds
// +net_to=MASK); this file is the wiring plus the hub instrumentation.
//
//                         L1 2 2  (B)
//                         blk 1 faces S, g
//                            ||
//                         blk 1 faces N
//   L3 2 4 (D) blk 1 ==== blk 5  H 1 1 (A)  blk 3 ==== blk 1  L2 2 3 (C)
//   faces N, g            faces S            faces E           faces W, g
//
//   H nominal, L1 +100 ppm, L2 -100 ppm, L3 +50 ppm.
//   Phones: H on blocks 2, 4 (A20-27, A40-47); the leaves on 2-7 (48 lines).
//   +define+LD_SMALL: H on block 2, the leaves on 2-3 (16).
//
// +define+HUB_RING: L1 blk 3 (faces E) === L2 blk 3 (faces N, g) as well, a
//   ring H-L1-L2; L1 and L2 then keep phones on 2, 4-7 (LD_SMALL: 2, 4).
// +define+HUB_STRAP (with HUB_RING): the ring jumper (STRAP_N) on that link at
//   both ends -- L1's E, L2's N.
//
// The hub instrumentation (HUB lines, HUBSUM at the end) taps every unit:
//   SEIZE   a seizure classified: who holds the far end (ORIG an origin trunk,
//           LEG a forward's leg, RECENT one of those let go < 100 ms ago,
//           CLAIM a claimed port -- a claim taken as a seizure, C18 --, NONE)
//   FWD     a forward written: its legs and resolver
//   RES     a resolver acting: LEG (a leg's M: is there a claim behind it?
//           hops= to the claimed port, or NOCLAIM -- C13) or GONE, held ms
//   CLAIM   a monitor's claim; HERE if it frees a resolver; LATE if the port's
//           resolver had resolved by a leg already (C18)
//   OCLAIM  an origin taking its claim: hops to a claimed port, or SUSPECT
//   NOFWD   a seizure not forwarded (busy: the forwarder / no resolver) or a
//           forward that found no trunk (empty)
`timescale 1ns/1ps
`include "exch.vh"

module tb_hub;
    localparam int NX = 4;
`ifdef LD_SMALL
    localparam [63:0] PH_H  = 64'h0000_0000_00FF_0000;       // 20-27
    localparam [63:0] PH_L  = 64'h0000_0000_FFFF_0000;       // 20-37
    localparam [63:0] PH_LR = 64'h0000_00FF_00FF_0000;       // 20-27, 40-47
`else
    localparam [63:0] PH_H  = 64'h0000_00FF_00FF_0000;       // 20-27, 40-47
    localparam [63:0] PH_L  = 64'hFFFF_FFFF_FFFF_0000;       // 20-77
    localparam [63:0] PH_LR = 64'hFFFF_FFFF_00FF_0000;       // 20-27, 40-77
`endif
`ifdef HUB_RING
    localparam [63:0] PH_L1 = PH_LR, PH_L2 = PH_LR;
    localparam [63:0] LT_L1 = 64'h0000_0000_FF00_FF00, LT_L2 = 64'h0000_0000_FF00_FF00;
    localparam [7:0]  LU_L1 = 8'b0000_1010, LU_L2 = 8'b0000_1010;
`else
    localparam [63:0] PH_L1 = PH_L, PH_L2 = PH_L;
    localparam [63:0] LT_L1 = 64'h0000_0000_0000_FF00, LT_L2 = 64'h0000_0000_0000_FF00;
    localparam [7:0]  LU_L1 = 8'b0000_0010, LU_L2 = 8'b0000_0010;
`endif
`ifdef HUB_STRAP
    localparam [3:0] ST_L1 = 4'b0100, ST_L2 = 4'b0001;      // L1's E, L2's N
`elsif HUB_STRAP1
    // C19 verify: the ring jumper at ONE end of the L1-L2 link only (L1's E)
    localparam [3:0] ST_L1 = 4'b0100, ST_L2 = 4'b0000;
`else
    localparam [3:0] ST_L1 = 4'b0000, ST_L2 = 4'b0000;
`endif
    localparam [63:0] LT_H  = 64'h0000_FF00_FF00_FF00;       // blocks 1, 3, 5
    localparam [63:0] LT_L3 = 64'h0000_0000_0000_FF00;
    localparam [64*NX-1:0] LD_PHONES = {PH_L, PH_L2, PH_L1, PH_H};
    localparam [64*NX-1:0] LD_TRUNKS = {LT_L3, LT_L2, LT_L1, LT_H};
    localparam [3*NX-1:0]  LD_CODE_E = {3'd2, 3'd2, 3'd2, 3'd1};
    localparam [3*NX-1:0]  LD_CODE_B = {3'd4, 3'd3, 3'd2, 3'd1};

`include "load_harness.svh"

    // ---- the crystals --------------------------------------------------------
    reg clk_h = 1'b0, clk_1 = 1'b0, clk_2 = 1'b0, clk_3 = 1'b0;
    always #122.070 clk_h = ~clk_h;
    initial begin #40; forever #(122.070 / 1.0001)  clk_1 = ~clk_1; end
    initial begin #90; forever #(122.070 / 0.9999)  clk_2 = ~clk_2; end
    initial begin #65; forever #(122.070 / 1.00005) clk_3 = ~clk_3; end
    assign ld_clk = {clk_3, clk_2, clk_1, clk_h};

    // ---- the trunk words: direction, g, class trunk ------------------------------
    function automatic [7:0] tw(input [1:0] d, input g); tw = {d, g, 3'b010, 2'b11}; endfunction
    localparam [1:0] DN = 2'd0, DS = 2'd1, DE = 2'd2, DW = 2'd3;
    localparam [63:0] W_H  = {16'd0, tw(DS, 1'b0), 8'd0, tw(DE, 1'b0), 8'd0, tw(DN, 1'b0), 8'd0};
    localparam [63:0] W_L1 = {32'd0, tw(DE, 1'b0), 8'd0, tw(DS, 1'b1), 8'd0};
    localparam [63:0] W_L2 = {32'd0, tw(DN, 1'b1), 8'd0, tw(DW, 1'b1), 8'd0};
    localparam [63:0] W_L3 = {48'd0, tw(DN, 1'b1), 8'd0};

    // ---- the cables ----------------------------------------------------------------
    wire [7:0] co_h, ao_h, ho_h, ko_h, up_h;
    wire [7:0] co_1, ao_1, ho_1, ko_1, up_1;
    wire [7:0] co_2, ao_2, ho_2, ko_2, up_2;
    wire [7:0] co_3, ao_3, ho_3, ko_3, up_3;
    // H: blk 1 <- L1 blk 1, blk 3 <- L2 blk 1, blk 5 <- L3 blk 1
    wire [7:0] ci_h = {2'd0, co_3[1], 1'b0, co_2[1], 1'b0, co_1[1], 1'b0};
    wire [7:0] ai_h = {2'd0, ao_3[1], 1'b0, ao_2[1], 1'b0, ao_1[1], 1'b0};
    wire [7:0] hi_h = {2'd0, ho_3[1], 1'b0, ho_2[1], 1'b0, ho_1[1], 1'b0};
    wire [7:0] ki_h = {2'd0, ko_3[1], 1'b0, ko_2[1], 1'b0, ko_1[1], 1'b0};
`ifdef HUB_RING
    // L1: blk 1 <- H blk 1, blk 3 <- L2 blk 3;  L2: blk 1 <- H blk 3, blk 3 <- L1 blk 3
    wire [7:0] ci_1 = {4'd0, co_2[3], 1'b0, co_h[1], 1'b0}, ai_1 = {4'd0, ao_2[3], 1'b0, ao_h[1], 1'b0};
    wire [7:0] hi_1 = {4'd0, ho_2[3], 1'b0, ho_h[1], 1'b0}, ki_1 = {4'd0, ko_2[3], 1'b0, ko_h[1], 1'b0};
    wire [7:0] ci_2 = {4'd0, co_1[3], 1'b0, co_h[3], 1'b0}, ai_2 = {4'd0, ao_1[3], 1'b0, ao_h[3], 1'b0};
    wire [7:0] hi_2 = {4'd0, ho_1[3], 1'b0, ho_h[3], 1'b0}, ki_2 = {4'd0, ko_1[3], 1'b0, ko_h[3], 1'b0};
`else
    wire [7:0] ci_1 = {6'd0, co_h[1], 1'b0}, ai_1 = {6'd0, ao_h[1], 1'b0};
    wire [7:0] hi_1 = {6'd0, ho_h[1], 1'b0}, ki_1 = {6'd0, ko_h[1], 1'b0};
    wire [7:0] ci_2 = {6'd0, co_h[3], 1'b0}, ai_2 = {6'd0, ao_h[3], 1'b0};
    wire [7:0] hi_2 = {6'd0, ho_h[3], 1'b0}, ki_2 = {6'd0, ko_h[3], 1'b0};
`endif
    wire [7:0] ci_3 = {6'd0, co_h[5], 1'b0}, ai_3 = {6'd0, ao_h[5], 1'b0};
    wire [7:0] hi_3 = {6'd0, ho_h[5], 1'b0}, ki_3 = {6'd0, ko_h[5], 1'b0};

    site_net #(`LD_SITE_TIMERS, .PHONES(PH_H), .TRUNKS(64'd0), .OWN_E(3'd1), .OWN_B(3'd1),
               .LTU(8'b0010_1010), .LTWORD(W_H)) A (
        `LD_SITE_COMMON(0),
        .c_out(), .a_out(), .clk_out(), .c_in(64'd0), .a_in(64'd0), .clk_in(64'd0), .link_up(),
        .lt_c_out(co_h), .lt_a_out(ao_h), .lt_h_out(ho_h), .lt_k_out(ko_h),
        .lt_c_in(ci_h), .lt_a_in(ai_h), .lt_h_in(hi_h), .lt_k_in(ki_h), .lt_up(up_h));

    site_net #(`LD_SITE_TIMERS, .PHONES(PH_L1), .TRUNKS(64'd0), .OWN_E(3'd2), .OWN_B(3'd2),
               .STRAP_N(ST_L1), .LTU(LU_L1), .LTWORD(W_L1)) B (
        `LD_SITE_COMMON(1),
        .c_out(), .a_out(), .clk_out(), .c_in(64'd0), .a_in(64'd0), .clk_in(64'd0), .link_up(),
        .lt_c_out(co_1), .lt_a_out(ao_1), .lt_h_out(ho_1), .lt_k_out(ko_1),
        .lt_c_in(ci_1), .lt_a_in(ai_1), .lt_h_in(hi_1), .lt_k_in(ki_1), .lt_up(up_1));

    site_net #(`LD_SITE_TIMERS, .PHONES(PH_L2), .TRUNKS(64'd0), .OWN_E(3'd2), .OWN_B(3'd3),
               .STRAP_N(ST_L2), .LTU(LU_L2), .LTWORD(W_L2)) C (
        `LD_SITE_COMMON(2),
        .c_out(), .a_out(), .clk_out(), .c_in(64'd0), .a_in(64'd0), .clk_in(64'd0), .link_up(),
        .lt_c_out(co_2), .lt_a_out(ao_2), .lt_h_out(ho_2), .lt_k_out(ko_2),
        .lt_c_in(ci_2), .lt_a_in(ai_2), .lt_h_in(hi_2), .lt_k_in(ki_2), .lt_up(up_2));

    site_net #(`LD_SITE_TIMERS, .PHONES(PH_L), .TRUNKS(64'd0), .OWN_E(3'd2), .OWN_B(3'd4),
               .LTU(8'b0000_0010), .LTWORD(W_L3)) D (
        `LD_SITE_COMMON(3),
        .c_out(), .a_out(), .clk_out(), .c_in(64'd0), .a_in(64'd0), .clk_in(64'd0), .link_up(),
        .lt_c_out(co_3), .lt_a_out(ao_3), .lt_h_out(ho_3), .lt_k_out(ko_3),
        .lt_c_in(ci_3), .lt_a_in(ai_3), .lt_h_in(hi_3), .lt_k_in(ki_3), .lt_up(up_3));

    function automatic [63:0] ex8(input [7:0] u);
        for (int b = 0; b < 8; b++) ex8[b*8 +: 8] = {8{u[b]}};
    endfunction
    assign ld_tup = {ex8(up_3) & LT_L3, ex8(up_2) & LT_L2, ex8(up_1) & LT_L1, ex8(up_h) & LT_H};

    `LD_PROBE(0, A);
    `LD_PROBE(1, B);
    `LD_PROBE(2, C);
    `LD_PROBE(3, D);

    // ============================================================================
    // HUB INSTRUMENTATION
    // ============================================================================
    localparam int HN = LD_NRES;
    wire [NX-1:0]        hb_wfwd, hb_wres, hb_wclaim, hb_wcls, hb_nfb, hb_nfe, hb_rsfa, hb_mfa, hb_claimed;
    wire [NX-1:0]        hb_t1k;
    wire [3*NX-1:0]      hb_cst;
    wire [2*NX-1:0]      hb_fst, hb_cdir;
    wire [6*NX-1:0]      hb_fin, hb_mwp, hb_cport, hb_trunk;
    wire [4*NX-1:0]      hb_fok, hb_dheld, hb_ook, hb_nst;
    wire [24*NX-1:0]     hb_fcand, hb_dtrunk, hb_ocand;
    wire [HN*NX-1:0]     hb_rsbusy, hb_rstwo, hb_rsact1, hb_rsfree1, hb_rsmine;
    wire [2*HN*NX-1:0]   hb_rsact, hb_rscl;
    wire [6*HN*NX-1:0]   hb_rsin;
    wire [24*HN*NX-1:0]  hb_rsleg;
    wire [4*HN*NX-1:0]   hb_rsheld;
    wire [NG-1:0]        hb_clm, hb_lbsy;
    wire [6*NG-1:0]      hb_addr;
    assign hb_t1k = ld_t1k;

`define HUB_TAP(X, S) \
    assign hb_wfwd[X]   = S.u_x.u_net.w_fwd; \
    assign hb_wres[X]   = S.u_x.u_net.w_res; \
    assign hb_wclaim[X] = S.u_x.u_net.w_claim; \
    assign hb_wcls[X]   = S.u_x.u_net.w_cls && (S.u_x.u_net.cst == 3'd2); \
    assign hb_nfb[X]    = S.u_x.u_net.nf_busy; \
    assign hb_nfe[X]    = S.u_x.u_net.nf_empty; \
    assign hb_rsfa[X]   = S.u_x.u_net.rs_free_any; \
    assign hb_mfa[X]    = S.u_x.u_net.m_free_any; \
    assign hb_claimed[X] = S.u_x.u_net.claimed; \
    assign hb_cst[(X)*3 +: 3]  = S.u_x.u_net.cst; \
    assign hb_fst[(X)*2 +: 2]  = S.u_x.u_net.fst; \
    assign hb_cdir[(X)*2 +: 2] = S.u_x.u_net.cls_dir; \
    assign hb_fin[(X)*6 +: 6]   = S.u_x.u_net.f_in; \
    assign hb_mwp[(X)*6 +: 6]   = S.u_x.u_net.m_want_port; \
    assign hb_cport[(X)*6 +: 6] = S.u_x.u_net.cls_port; \
    assign hb_trunk[(X)*6 +: 6] = S.u_x.u_net.trunk; \
    assign hb_fok[(X)*4 +: 4]   = S.u_x.u_net.f_ok; \
    assign hb_dheld[(X)*4 +: 4] = S.u_x.u_net.d_held; \
    assign hb_ook[(X)*4 +: 4]   = S.u_x.u_net.o_ok; \
    assign hb_nst[(X)*4 +: 4]   = S.u_x.u_net.nst; \
    assign hb_fcand[(X)*24 +: 24]  = S.u_x.u_net.f_cand; \
    assign hb_dtrunk[(X)*24 +: 24] = S.u_x.u_net.d_trunk; \
    assign hb_ocand[(X)*24 +: 24]  = S.u_x.u_net.o_cand; \
    assign hb_rsbusy[(X)*HN +: HN]  = S.u_x.u_net.rs_busy; \
    assign hb_rstwo[(X)*HN +: HN]   = S.u_x.u_net.rs_two; \
    assign hb_rsact1[(X)*HN +: HN]  = S.u_x.u_net.rs_act1; \
    assign hb_rsfree1[(X)*HN +: HN] = S.u_x.u_net.rs_free1; \
    assign hb_rsmine[(X)*HN +: HN]  = S.u_x.u_net.rs_mine; \
    assign hb_rsact[(X)*2*HN +: 2*HN] = S.u_x.u_net.rs_act; \
    assign hb_rscl[(X)*2*HN +: 2*HN]  = S.u_x.u_net.rs_cl; \
    assign hb_rsin[(X)*6*HN +: 6*HN]  = S.u_x.u_net.rs_in; \
    assign hb_rsleg[(X)*24*HN +: 24*HN] = S.u_x.u_net.rs_leg; \
    assign hb_rsheld[(X)*4*HN +: 4*HN]  = S.u_x.u_net.rs_held

`define HUB_P1(X, S, B, K) \
    assign hb_clm[(X)*64 + (B)*8 + K]  = S.u_x.u_exch.pos[B].u_blk.u_port``K.clm; \
    assign hb_lbsy[(X)*64 + (B)*8 + K] = S.u_x.u_exch.pos[B].u_blk.u_port``K.bsy; \
    assign hb_addr[((X)*64 + (B)*8 + K)*6 +: 6] = S.u_x.u_exch.pos[B].u_blk.u_port``K.addr
`define HUB_PORTS(X, S, B) \
    `HUB_P1(X, S, B, 0); `HUB_P1(X, S, B, 1); `HUB_P1(X, S, B, 2); `HUB_P1(X, S, B, 3); \
    `HUB_P1(X, S, B, 4); `HUB_P1(X, S, B, 5); `HUB_P1(X, S, B, 6); `HUB_P1(X, S, B, 7)

    `HUB_TAP(0, A);
    `HUB_TAP(1, B);
    `HUB_TAP(2, C);
    `HUB_TAP(3, D);
    `HUB_PORTS(0, A, 1);
    `HUB_PORTS(0, A, 3);
    `HUB_PORTS(0, A, 5);
    `HUB_PORTS(1, B, 1);
    `HUB_PORTS(2, C, 1);
    `HUB_PORTS(3, D, 1);
`ifdef HUB_RING
    `HUB_PORTS(1, B, 3);
    `HUB_PORTS(2, C, 3);
`endif

    // the far end of a trunk port, as a global index; -1 for anything else
    function automatic int far_g(input int g);
        int x, p, b, k;
        if (g < 0 || g >= NG) return -1;
        x = g / 64; p = g % 64; b = p / 8; k = p % 8;
        case (x)
        0: case (b) 1: return 1*64 + 8 + k; 3: return 2*64 + 8 + k; 5: return 3*64 + 8 + k; default: return -1; endcase
        1: begin if (b == 1) return 0*64 + 8 + k;
`ifdef HUB_RING
                 if (b == 3) return 2*64 + 24 + k;
`endif
                 return -1; end
        2: begin if (b == 1) return 0*64 + 24 + k;
`ifdef HUB_RING
                 if (b == 3) return 1*64 + 24 + k;
`endif
                 return -1; end
        3: begin if (b == 1) return 0*64 + 40 + k; return -1; end
        default: return -1;
        endcase
    endfunction
    function automatic bit is_tp(input int g); return (g >= 0 && g < NG) && LD_TRUNKS[g]; endfunction

    // hops from trunk port g, along the far end and what it listens to, to a
    // claimed port: 1 the far port itself is claimed, 2 its latch points at a
    // trunk whose far end is, ...; -1 none within 4
    function automatic int claim_hops(input int g);
        int f, h, a;
        f = far_g(g);
        for (h = 1; h <= 4; h++) begin
            if (f < 0) return -1;
            if (hb_clm[f]) return h;
            a = (f / 64) * 64 + int'(hb_addr[f*6 +: 6]);
            if (!is_tp(a) || a == f) return -1;
            f = far_g(a);
        end
        return -1;
    endfunction
    function automatic string pst(input int g);
        if (g < 0) return "-";
        return $sformatf("%s[src=%s b=%0d c=%0d B=%0d]", pn(g), pn((g / 64) * 64 + int'(hb_addr[g*6 +: 6])),
                         hb_lbsy[g], hb_clm[g], ld_busy[g]);
    endfunction

    // who holds trunk port g of exchange x as its own, right now
    function automatic int owner(input int g);
        int x, p, j, r;
        x = g / 64; p = g % 64;
        for (j = 0; j < 4; j++) begin
            if (hb_dheld[x*4 + j] && int'(hb_dtrunk[x*24 + j*6 +: 6]) == p) return 1;    // ORIG
            if (hb_nst[x*4 +: 4] == 4'd3 && hb_ook[x*4 + j] && int'(hb_ocand[x*24 + j*6 +: 6]) == p) return 1;
            if (hb_fst[x*2 +: 2] == 2'd3 && hb_fok[x*4 + j] && int'(hb_fcand[x*24 + j*6 +: 6]) == p) return 2;
            for (r = 0; r < HN; r++)
                if (hb_rsheld[(x*HN + r)*4 + j] && int'(hb_rsleg[((x*HN + r)*4 + j)*6 +: 6]) == p) return 2;  // LEG
        end
        return 0;
    endfunction

    // ---- the counts ------------------------------------------------------------------
    real hu_lastown [0:NG-1];           // last ms a port was an origin trunk or a leg
    real hu_lastres [0:NG-1];           // last ms an in-port's resolver resolved by a leg
    int  hu_seize [0:NX*8-1];           // by: 0 ORIG 1 LEG 2 RECENT 3 CLAIM 4 NONE
    int  hu_fwd [0:NX-1], hu_legs [0:NX*4-1], hu_nfb_f [0:NX-1], hu_nfb_r [0:NX-1], hu_nfe [0:NX-1];
    int  hu_res [0:NX*4-1];             // 0 LEG 1 GONE 2 HERE
    real hu_rhold [0:NX*4-1], hu_rmax [0:NX*4-1];
    int  hu_noclaim [0:NX-1], hu_late [0:NX-1], hu_claims [0:NX-1], hu_osus [0:NX-1], hu_oclaim [0:NX-1];
    real hu_ralloc [0:NX*8-1];
    int  hu_nomon_leaf [0:NX-1];
    initial begin
        for (int i = 0; i < NG; i++) begin hu_lastown[i] = -1.0e9; hu_lastres[i] = -1.0e9; end
        for (int x = 0; x < NX; x++) begin
            hu_fwd[x] = 0; hu_nfb_f[x] = 0; hu_nfb_r[x] = 0; hu_nfe[x] = 0; hu_noclaim[x] = 0;
            hu_late[x] = 0; hu_claims[x] = 0; hu_osus[x] = 0; hu_oclaim[x] = 0; hu_nomon_leaf[x] = 0;
            for (int k = 0; k < 8; k++) begin hu_seize[x*8 + k] = 0; hu_ralloc[x*8 + k] = 0.0; end
            for (int k = 0; k < 4; k++) begin
                hu_legs[x*4 + k] = 0; hu_res[x*4 + k] = 0; hu_rhold[x*4 + k] = 0.0; hu_rmax[x*4 + k] = 0.0;
            end
        end
    end
    function automatic string byname(input int k);
        case (k) 0: return "ORIG"; 1: return "LEG"; 2: return "RECENT"; 3: return "CLAIM"; default: return "NONE"; endcase
    endfunction
    function automatic string dname(input int d);
        case (d) 0: return "N"; 1: return "S"; 2: return "E"; default: return "W"; endcase
    endfunction

    genvar hx;
    generate for (hx = 0; hx < NX; hx = hx + 1) begin : hub_x
        bit d_claimed = 1'b0;
        always @(posedge ld_clk[hx]) begin : ev
            int j, r, f, p, k, by, hops, o, nl;
            real t, hold;
            string s;
            t = $realtime / 1.0e6;
            // the owners, once a ms
            if (hb_t1k[hx]) begin
                for (j = 0; j < 4; j++) begin
                    if (hb_dheld[hx*4 + j]) hu_lastown[hx*64 + int'(hb_dtrunk[hx*24 + j*6 +: 6])] = t;
                    for (r = 0; r < HN; r++)
                        if (hb_rsheld[(hx*HN + r)*4 + j]) hu_lastown[hx*64 + int'(hb_rsleg[((hx*HN + r)*4 + j)*6 +: 6])] = t;
                end
            end
            // ---- a seizure classified --------------------------------------------
            if (hb_wcls[hx]) begin
                p = int'(hb_cport[hx*6 +: 6]); f = far_g(hx*64 + p);
                o = (f >= 0) ? owner(f) : 0;
                if (o == 1) by = 0; else if (o == 2) by = 1;
                else if (f >= 0 && hb_clm[f]) by = 3;
                else if (f >= 0 && t - hu_lastown[f] < 100.0) by = 2;
                else by = 4;
                hu_seize[hx*8 + by]++;
                if (!hb_mfa[hx]) hu_nomon_leaf[hx]++;
                if (hb_nfb[hx]) begin
                    if (hb_fst[hx*2 +: 2] != 2'd0) hu_nfb_f[hx]++; else hu_nfb_r[hx]++;
                end
                $display("HUB t=%.3f ex=%s SEIZE port=%s dir=%s from=%s by=%s mon=%0d fwd=%s%s", t, xn(hx),
                         pn(hx*64 + p), dname(int'(hb_cdir[hx*2 +: 2])), pst(f), byname(by), hb_mfa[hx],
                         !hb_nfb[hx] ? "ok" : (hb_fst[hx*2 +: 2] != 2'd0 ? "BUSY-FWDR" : "BUSY-NORES"),
                         (by >= 3) ? " PHANTOMSEIZE" : "");
            end
            // ---- a forward written --------------------------------------------------
            if (hb_wfwd[hx]) begin
                s = ""; nl = 0;
                for (j = 0; j < 4; j++) if (hb_fok[hx*4 + j]) begin
                    s = {s, $sformatf(" %s:%s", dname(j), pn(hx*64 + int'(hb_fcand[hx*24 + j*6 +: 6])))}; nl++;
                end
                for (r = 0; r < HN; r++) if (hb_rsfree1[hx*HN + r]) begin k = r; hu_ralloc[hx*8 + r] = t; end
                hu_fwd[hx]++; hu_legs[hx*4 + (nl > 3 ? 3 : nl)]++;
                $display("HUB t=%.3f ex=%s FWD in=%s legs=%0d%s res=%0d", t, xn(hx), pn(hx*64 + int'(hb_fin[hx*6 +: 6])), nl, s, k);
            end
            if (hb_nfe[hx]) begin
                hu_nfe[hx]++;
                if (hx == 0) $display("HUB t=%.3f ex=%s NOFWD-EMPTY in=%s", t, xn(hx), pn(hx*64 + int'(hb_fin[hx*6 +: 6])));
            end
            // ---- a resolver acting ------------------------------------------------------
            if (hb_wres[hx]) begin
                for (r = 0; r < HN; r++) if (hb_rsact1[hx*HN + r]) begin
                    hold = t - hu_ralloc[hx*8 + r];
                    p = int'(hb_rsin[(hx*HN + r)*6 +: 6]);
                    if (hb_rsact[(hx*HN + r)*2 +: 2] == 2'd1) begin
                        k = int'(hb_rscl[(hx*HN + r)*2 +: 2]);
                        f = hx*64 + int'(hb_rsleg[((hx*HN + r)*4 + k)*6 +: 6]);
                        hops = claim_hops(f);
                        if (hops < 0) hu_noclaim[hx]++;
                        hu_lastres[hx*64 + p] = t;
                        hu_res[hx*4 + 0]++; hu_rhold[hx*4 + 0] += hold;
                        if (hold > hu_rmax[hx*4 + 0]) hu_rmax[hx*4 + 0] = hold;
                        $display("HUB t=%.3f ex=%s RES r=%0d LEG in=%s leg=%s:%s two=%0d held_ms=%.1f far=%s %s", t, xn(hx), r,
                                 pn(hx*64 + p), dname(k), pn(f), !hb_rstwo[hx*HN + r], hold, pst(far_g(f)),
                                 hops < 0 ? "NOCLAIM" : $sformatf("hops=%0d", hops));
                    end else begin
                        hu_res[hx*4 + 1]++; hu_rhold[hx*4 + 1] += hold;
                        if (hold > hu_rmax[hx*4 + 1]) hu_rmax[hx*4 + 1] = hold;
                        $display("HUB t=%.3f ex=%s RES r=%0d GONE in=%s held_ms=%.1f", t, xn(hx), r, pn(hx*64 + p), hold);
                    end
                end
            end
            // ---- a monitor's claim --------------------------------------------------------
            if (hb_wclaim[hx]) begin
                p = int'(hb_mwp[hx*6 +: 6]);
                hu_claims[hx]++;
                s = "";
                for (r = 0; r < HN; r++) if (hb_rsmine[hx*HN + r]) begin
                    hold = t - hu_ralloc[hx*8 + r];
                    hu_res[hx*4 + 2]++; hu_rhold[hx*4 + 2] += hold;
                    if (hold > hu_rmax[hx*4 + 2]) hu_rmax[hx*4 + 2] = hold;
                    s = {s, $sformatf(" HERE r=%0d held_ms=%.1f", r, hold)};
                end
                if (hb_rsmine[hx*HN +: HN] == '0 && t - hu_lastres[hx*64 + p] < 5000.0) begin
                    hu_late[hx]++;
                    s = {s, $sformatf(" LATE (its resolver resolved by a leg %.1f ms ago)", t - hu_lastres[hx*64 + p])};
                end
                $display("HUB t=%.3f ex=%s CLAIM port=%s from=%s%s", t, xn(hx), pn(hx*64 + p), pst(far_g(hx*64 + p)), s);
            end
            // ---- an origin taking its claim ---------------------------------------------------
            if (hb_claimed[hx] && !d_claimed) begin
                p = int'(hb_trunk[hx*6 +: 6]);
                hops = claim_hops(hx*64 + p);
                hu_oclaim[hx]++;
                if (hops < 0) hu_osus[hx]++;
                $display("HUB t=%.3f ex=%s OCLAIM trunk=%s far=%s %s", t, xn(hx), pn(hx*64 + p), pst(far_g(hx*64 + p)),
                         hops < 0 ? "SUSPECT" : $sformatf("hops=%0d", hops));
            end
            d_claimed <= hb_claimed[hx];
        end
    end endgenerate

    final begin
        int x, k;
        for (x = 0; x < NX; x++) begin
            $write("HUBSUM ex=%s seize ORIG=%0d LEG=%0d RECENT=%0d CLAIM=%0d NONE=%0d nomon=%0d",
                   xn(x), hu_seize[x*8 + 0], hu_seize[x*8 + 1], hu_seize[x*8 + 2], hu_seize[x*8 + 3],
                   hu_seize[x*8 + 4], hu_nomon_leaf[x]);
            $write(" fwd=%0d legs1=%0d legs2=%0d legs3=%0d nofwd_fwdr=%0d nofwd_nores=%0d nofwd_empty=%0d",
                   hu_fwd[x], hu_legs[x*4 + 1], hu_legs[x*4 + 2], hu_legs[x*4 + 3], hu_nfb_f[x], hu_nfb_r[x], hu_nfe[x]);
            $write(" res_leg=%0d res_gone=%0d res_here=%0d", hu_res[x*4 + 0], hu_res[x*4 + 1], hu_res[x*4 + 2]);
            for (k = 0; k < 3; k++)
                $write(" hold%0d_mean=%.1f hold%0d_max=%.1f", k, hu_res[x*4 + k] ? hu_rhold[x*4 + k] / hu_res[x*4 + k] : 0.0,
                       k, hu_rmax[x*4 + k]);
            $write(" rleg_noclaim=%0d claims=%0d late_claims=%0d oclaims=%0d oclaim_suspect=%0d\n",
                   hu_noclaim[x], hu_claims[x], hu_late[x], hu_oclaim[x], hu_osus[x]);
        end
    end
endmodule
