// tb_hubb -- the hub star of tb_hub.sv on BASEBAND TIE CARDS, two channels a
// direction: the links are the bottleneck here, so the last free channel -- the
// glare condition, C13 -- is common.  Same harness, same HUB instrumentation.
//
//   H (A, 1 1): 11 12 face N (-> L1 11 12), 13 14 face E (-> L2 11 12), 15 16 face S (-> L3 11 12)
//   leaves: 11 12 face the hub with g.  Phones as tb_hub (LD_SMALL too).  No ring option.
`timescale 1ns/1ps
`include "exch.vh"

module tb_hub;
    localparam int NX = 4;
`ifdef LD_SMALL
    localparam [63:0] PH_H  = 64'h0000_0000_00FF_0000;
    localparam [63:0] PH_L  = 64'h0000_0000_FFFF_0000;
`else
    localparam [63:0] PH_H  = 64'h0000_00FF_00FF_0000;
    localparam [63:0] PH_L  = 64'hFFFF_FFFF_FFFF_0000;
`endif
    localparam [63:0] TR_H  = 64'h0000_0000_0000_7E00;       // 11-16 (octal)
    localparam [63:0] TR_L  = 64'h0000_0000_0000_0600;       // 11-12 (octal)
    localparam [64*NX-1:0] LD_PHONES = {PH_L, PH_L, PH_L, PH_H};
    localparam [64*NX-1:0] LD_TRUNKS = {TR_L, TR_L, TR_L, TR_H};
    localparam [3*NX-1:0]  LD_CODE_E = {3'd2, 3'd2, 3'd2, 3'd1};
    localparam [3*NX-1:0]  LD_CODE_B = {3'd4, 3'd3, 3'd2, 3'd1};

`include "load_harness.svh"

    reg clk_h = 1'b0, clk_1 = 1'b0, clk_2 = 1'b0, clk_3 = 1'b0;
    always #122.070 clk_h = ~clk_h;
    initial begin #40; forever #(122.070 / 1.0001)  clk_1 = ~clk_1; end
    initial begin #90; forever #(122.070 / 0.9999)  clk_2 = ~clk_2; end
    initial begin #65; forever #(122.070 / 1.00005) clk_3 = ~clk_3; end
    assign ld_clk = {clk_3, clk_2, clk_1, clk_h};

    function automatic [7:0] tw(input [1:0] d, input g); tw = {d, g, 3'b010, 2'b11}; endfunction
    localparam [1:0] DN = 2'd0, DS = 2'd1, DE = 2'd2, DW = 2'd3;
    function automatic [511:0] tws(input [63:0] m, input [7:0] w);
        tws = '0;
        for (int q = 0; q < 64; q++) if (m[q]) tws[q*8 +: 8] = w;
    endfunction
    localparam [63:0] HN_ = 64'h0000_0000_0000_0600, HE_ = 64'h0000_0000_0000_1800, HS_ = 64'h0000_0000_0000_6000;
    localparam [511:0] W_H  = tws(HN_, tw(DN, 1'b0)) | tws(HE_, tw(DE, 1'b0)) | tws(HS_, tw(DS, 1'b0));
    localparam [511:0] W_L1 = tws(TR_L, tw(DS, 1'b1));
    localparam [511:0] W_L2 = tws(TR_L, tw(DW, 1'b1));
    localparam [511:0] W_L3 = tws(TR_L, tw(DN, 1'b1));

    wire [63:0] co_h, ao_h, ko_h, up_h, co_1, ao_1, ko_1, up_1, co_2, ao_2, ko_2, up_2, co_3, ao_3, ko_3, up_3;
    // H 11,12 <-> L1 11,12;  H 13,14 <-> L2 11,12;  H 15,16 <-> L3 11,12
    wire [63:0] ci_h = ((co_1 & TR_L)) | ((co_2 & TR_L) << 2) | ((co_3 & TR_L) << 4);
    wire [63:0] ai_h = ((ao_1 & TR_L)) | ((ao_2 & TR_L) << 2) | ((ao_3 & TR_L) << 4);
    wire [63:0] ki_h = ((ko_1 & TR_L)) | ((ko_2 & TR_L) << 2) | ((ko_3 & TR_L) << 4);
    wire [63:0] ci_1 = co_h & TR_L,        ai_1 = ao_h & TR_L,        ki_1 = ko_h & TR_L;
    wire [63:0] ci_2 = (co_h >> 2) & TR_L, ai_2 = (ao_h >> 2) & TR_L, ki_2 = (ko_h >> 2) & TR_L;
    wire [63:0] ci_3 = (co_h >> 4) & TR_L, ai_3 = (ao_h >> 4) & TR_L, ki_3 = (ko_h >> 4) & TR_L;

`define HUBB_SITE(NAME, X, PHN, TRN, TWD, E, B, CO, AO, KO, CI, AI, KI, UP) \
    site_net #(`LD_SITE_TIMERS, .PHONES(PHN), .TRUNKS(TRN), .TWORD(TWD), .OWN_E(E), .OWN_B(B)) NAME ( \
        `LD_SITE_COMMON(X), \
        .c_out(CO), .a_out(AO), .clk_out(KO), .c_in(CI), .a_in(AI), .clk_in(KI), .link_up(UP), \
        .lt_c_out(), .lt_a_out(), .lt_h_out(), .lt_k_out(), \
        .lt_c_in(8'd0), .lt_a_in(8'd0), .lt_h_in(8'd0), .lt_k_in(8'd0), .lt_up())

    `HUBB_SITE(A, 0, PH_H, TR_H, W_H,  3'd1, 3'd1, co_h, ao_h, ko_h, ci_h, ai_h, ki_h, up_h);
    `HUBB_SITE(B, 1, PH_L, TR_L, W_L1, 3'd2, 3'd2, co_1, ao_1, ko_1, ci_1, ai_1, ki_1, up_1);
    `HUBB_SITE(C, 2, PH_L, TR_L, W_L2, 3'd2, 3'd3, co_2, ao_2, ko_2, ci_2, ai_2, ki_2, up_2);
    `HUBB_SITE(D, 3, PH_L, TR_L, W_L3, 3'd2, 3'd4, co_3, ao_3, ko_3, ci_3, ai_3, ki_3, up_3);

    assign ld_tup = {up_3 & TR_L, up_2 & TR_L, up_1 & TR_L, up_h & TR_H};

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
    `HUB_PORTS(1, B, 1);
    `HUB_PORTS(2, C, 1);
    `HUB_PORTS(3, D, 1);

    // the far end of a trunk port, as a global index; -1 for anything else
    // ports in decimal: octal 11,12 = 9,10; 13,14 = 11,12; 15,16 = 13,14
    function automatic int far_g(input int g);
        int x, p;
        if (g < 0 || g >= NG) return -1;
        x = g / 64; p = g % 64;
        if (x == 0) begin
            if (p == 9  || p == 10) return 1*64 + p;
            if (p == 11 || p == 12) return 2*64 + p - 2;
            if (p == 13 || p == 14) return 3*64 + p - 4;
            return -1;
        end
        if (p == 9 || p == 10) return (x == 1) ? p : (x == 2) ? p + 2 : p + 4;
        return -1;
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
