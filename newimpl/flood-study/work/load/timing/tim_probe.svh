// tim_probe.svh -- TIMING STUDY probes (work/load/timing).  Bench-side only.
//
// Included in a topology module AFTER tim_harness.svh and before the sites.
// The topology must define  function automatic int tim_far(int g)  -- the
// port at the far end of trunk channel g (x*64+p), or -1 -- and, after its
// sites, `TIM_TAP(x, INST) for every exchange.
//
// Every flood is TAGGED with its caller's call id (c_id, the CALL line's id=)
// and followed hop by hop.  One line an event:
//   TE <t ms, 3 dp> <ex> <EV> <port oct> <call> [fields]
//   KEY     flood_go: the caller's port; dial= the digits; dest=
//   OSWEEP  the origin's sweep starts (after N_WANT)
//   SEIZE   the origin's seizure write, one line a trunk
//   RISE/FALL  M edge at the unit's probe on a tagged port (caller or trunk);
//           bsy= BUSY in the same bit-time
//   CWAIT   classifier saw the rise but the reader was the sweep's (C_WAIT)
//   CREAD   classifier issues the read
//   HOLD    the hold write; cell=i|- ; fwd=1|0 (0: forwarder or resolvers busy)
//   UNHOLD  the T_ARM watch wrote the hold away
//   ARM     a monitor cell armed on the port
//   MDIG    a cell counted a digit: st=E|B cnt=
//   MREL    a cell let go (not by its claim)
//   CLAIM   the unit's CLAIM write
//   FSWEEP  the forwarder's sweep starts for f_in
//   FWD     the legs written: legs=...
//   FNONE   the forward ended with nothing written (cancel= / no trunk)
//   RES     a resolver acted: act=LEG|GONE
//   ATT     att rose; TAKE the marker attached the register; REFUSE refused
//   RDIG    the register (claimed trunk context) counted a digit: n= d=
//   OCLAIM  the origin took M on a held trunk as the claim; glare=
//   ODROP / OEND  the origin dropped / ended: after= (1 nogo 2 local) guard=
//   ODONE   the origin connected the caller to the kept trunk

wire [NX-1:0]            tp_spf, tp_spm, tp_spb;
wire [6*NX-1:0]          tp_spp;
wire [NX-1:0]            tp_clsiss, tp_clsseen;
wire [6*NX-1:0]          tp_clsrp, tp_clsport;
wire [3*NX-1:0]          tp_cst;
wire [NX-1:0]            tp_wcls, tp_mfreeany, tp_nfb, tp_nfe;
wire [LD_NMON*NX-1:0]    tp_mfree1, tp_mheld, tp_marmed, tp_dstb, tp_mwant;
wire [6*LD_NMON*NX-1:0]  tp_mport;
wire [4*LD_NMON*NX-1:0]  tp_dcnt;
wire [2*LD_NMON*NX-1:0]  tp_mst;
wire [NX-1:0]            tp_wclaim;
wire [6*NX-1:0]          tp_mwp;
wire [2*NX-1:0]          tp_fst;
wire [6*NX-1:0]          tp_fin;
wire [NX-1:0]            tp_wfwd, tp_fcancel, tp_hdone, tp_howner;
wire [4*NX-1:0]          tp_fok, tp_hok;
wire [24*NX-1:0]         tp_fcand;
wire [4*NX-1:0]          tp_nst, tp_ook;
wire [24*NX-1:0]         tp_ocand;
wire [6*NX-1:0]          tp_caller, tp_rport, tp_trunk;
wire [NX-1:0]            tp_worig, tp_fgo, tp_guard, tp_rbrk, tp_claimed;
wire [2*NX-1:0]          tp_oafter;
wire [16*NX-1:0]         tp_tmr;
wire [NX-1:0]            tp_wres;
wire [LD_NRES*NX-1:0]    tp_ract1;
wire [2*LD_NRES*NX-1:0]  tp_ract, tp_rcl;
wire [6*LD_NRES*NX-1:0]  tp_rin;
wire [NX-1:0]            tp_att, tp_ktake, tp_kctx, tp_rbusy;
wire [6*NX-1:0]          tp_attp, tp_kattp, tp_kcaller;
wire [3*NX-1:0]          tp_rnd;
wire [16*NX-1:0]         tp_rdig;
wire [NX-1:0]            tp_late;           // the fix's late-rise hold (fix/net_unit.v only)
`ifndef TIM_FIX
assign tp_late = '0;
`endif
`define TIM_TAP_FIX(X, S) assign tp_late[X] = S.u_x.u_net.cls_late

`define TIM_TAP(X, S) \
    assign tp_spf[X] = S.u_x.u_net.sp_fresh; \
    assign tp_spm[X] = S.u_x.u_net.sp_m; \
    assign tp_spb[X] = S.u_x.u_net.sp_busy; \
    assign tp_spp[(X)*6 +: 6] = S.u_x.u_net.sp_port; \
    assign tp_clsiss[X] = S.u_x.u_net.cls_issue; \
    assign tp_clsseen[X] = S.u_x.u_net.cls_seen; \
    assign tp_clsrp[(X)*6 +: 6] = S.u_x.u_net.cls_rport; \
    assign tp_clsport[(X)*6 +: 6] = S.u_x.u_net.cls_port; \
    assign tp_cst[(X)*3 +: 3] = S.u_x.u_net.cst; \
    assign tp_wcls[X] = S.u_x.u_net.w_cls; \
    assign tp_mfreeany[X] = S.u_x.u_net.m_free_any; \
    assign tp_nfb[X] = S.u_x.u_net.nf_busy; \
    assign tp_nfe[X] = S.u_x.u_net.nf_empty; \
    assign tp_mfree1[(X)*LD_NMON +: LD_NMON] = S.u_x.u_net.m_free1; \
    assign tp_mheld[(X)*LD_NMON +: LD_NMON] = S.u_x.u_net.m_held; \
    assign tp_marmed[(X)*LD_NMON +: LD_NMON] = S.u_x.u_net.m_armed; \
    assign tp_dstb[(X)*LD_NMON +: LD_NMON] = S.u_x.u_net.d_stb; \
    assign tp_mwant[(X)*LD_NMON +: LD_NMON] = S.u_x.u_net.m_want; \
    assign tp_mport[(X)*6*LD_NMON +: 6*LD_NMON] = S.u_x.u_net.m_port; \
    assign tp_dcnt[(X)*4*LD_NMON +: 4*LD_NMON] = S.u_x.u_net.d_cnt; \
    assign tp_mst[(X)*2*LD_NMON +: 2*LD_NMON] = S.u_x.u_net.m_st; \
    assign tp_wclaim[X] = S.u_x.u_net.w_claim; \
    assign tp_mwp[(X)*6 +: 6] = S.u_x.u_net.m_want_port; \
    assign tp_fst[(X)*2 +: 2] = S.u_x.u_net.fst; \
    assign tp_fin[(X)*6 +: 6] = S.u_x.u_net.f_in; \
    assign tp_wfwd[X] = S.u_x.u_net.w_fwd; \
    assign tp_fcancel[X] = S.u_x.u_net.f_cancel; \
    assign tp_hdone[X] = S.u_x.u_net.h_done; \
    assign tp_howner[X] = S.u_x.u_net.h_owner; \
    assign tp_fok[(X)*4 +: 4] = S.u_x.u_net.f_ok; \
    assign tp_hok[(X)*4 +: 4] = S.u_x.u_net.h_ok; \
    assign tp_fcand[(X)*24 +: 24] = S.u_x.u_net.f_cand; \
    assign tp_nst[(X)*4 +: 4] = S.u_x.u_net.nst; \
    assign tp_ook[(X)*4 +: 4] = S.u_x.u_net.o_ok; \
    assign tp_ocand[(X)*24 +: 24] = S.u_x.u_net.o_cand; \
    assign tp_caller[(X)*6 +: 6] = S.u_x.u_net.caller; \
    assign tp_rport[(X)*6 +: 6] = S.u_x.u_net.r_port; \
    assign tp_trunk[(X)*6 +: 6] = S.u_x.u_net.trunk; \
    assign tp_worig[X] = S.u_x.u_net.w_orig; \
    assign tp_fgo[X] = S.u_x.u_net.flood_go; \
    assign tp_guard[X] = S.u_x.u_net.guarding; \
    assign tp_rbrk[X] = S.u_x.u_net.r_brk; \
    assign tp_claimed[X] = S.u_x.u_net.claimed; \
    assign tp_oafter[(X)*2 +: 2] = S.u_x.u_net.o_after; \
    assign tp_tmr[(X)*16 +: 16] = S.u_x.u_net.tmr; \
    assign tp_wres[X] = S.u_x.u_net.w_res; \
    assign tp_ract1[(X)*LD_NRES +: LD_NRES] = S.u_x.u_net.rs_act1; \
    assign tp_ract[(X)*2*LD_NRES +: 2*LD_NRES] = S.u_x.u_net.rs_act; \
    assign tp_rcl[(X)*2*LD_NRES +: 2*LD_NRES] = S.u_x.u_net.rs_cl; \
    assign tp_rin[(X)*6*LD_NRES +: 6*LD_NRES] = S.u_x.u_net.rs_in; \
    assign tp_att[X] = S.u_x.u_net.att; \
    assign tp_attp[(X)*6 +: 6] = S.u_x.u_net.att_port; \
    assign tp_ktake[X] = S.u_x.u_mk.att_take; \
    assign tp_kctx[X] = S.u_x.u_mk.ctx_clm; \
    assign tp_kattp[(X)*6 +: 6] = S.u_x.u_mk.u_att_port; \
    assign tp_kcaller[(X)*6 +: 6] = S.u_x.u_mk.caller; \
    assign tp_rbusy[X] = S.u_x.u_mk.u_reg.busy; \
    assign tp_rnd[(X)*3 +: 3] = S.u_x.u_mk.u_reg.ndig; \
    assign tp_rdig[(X)*16 +: 16] = S.u_x.u_mk.u_reg.digits

// ---- per port: the flood it carries, and its M as the unit's probe last saw it ----
int  tg     [0:NG-1];         // call id, 0 none
real tg_t   [0:NG-1];         // when it was tagged (ms)
bit  tg_m   [0:NG-1];
int  tim_win_ms = (LD_T_KEY + LD_T_CLAIM) * 2;
int  tim_on = 1;

function automatic real tnow(); return $realtime / 1.0e6; endfunction
function automatic string po(int p); return $sformatf("%0o%0o", p / 8, p % 8); endfunction
function automatic bit tim_ok(int g);
    return (tg[g] != 0) && (tnow() - tg_t[g] < real'(tim_win_ms));
endfunction

initial begin
    int g;
    for (g = 0; g < NG; g++) begin tg[g] = 0; tg_t[g] = -1.0e9; tg_m[g] = 0; end
    if (!$value$plusargs("tim=%d", tim_on)) tim_on = 1;
    $display("KNOB tim=%0d", tim_on);
end

genvar tpx;
generate for (tpx = 0; tpx < NX; tpx = tpx + 1) begin : tim_x
    // last tick's values, for edges
    reg [3:0]         nst_d = 0;
    reg [1:0]         fst_d = 0;
    reg [2:0]         cst_d = 0;
    reg [LD_NMON-1:0] armed_d = 0, held_d = 0;
    reg               att_d = 0, claimed_d = 0, guard_d = 0, rbrk_d = 0;
    reg [2:0]         rnd_d = 0;
    reg               wclaim_d = 0;
    reg [5:0]         mwp_d = 0;
    always @(posedge ld_clk[tpx]) if (tim_on && ld_rst_n) begin : tev
        int x, g, p, i, j, c, fg, cl, q;
        string s;
        x = tpx;
        // ---- the probe: M edges; a trunk's rise takes the far end's tag ----
        if (tp_spf[x]) begin
            p = tp_spp[x*6 +: 6]; g = x*64 + p;
            if (tp_spm[x] != tg_m[g]) begin
                if (tp_spm[x] && LD_TRUNKS[g]) begin
                    fg = tim_far(g);
                    if (fg >= 0 && tim_ok(fg)) begin tg[g] = tg[fg]; tg_t[g] = tnow(); end
                    else begin tg[g] = 0; end
                end
                if (tim_ok(g) || LD_TRUNKS[g])
                    $display("TE %.3f %s %s %s %0d bsy=%0d", tnow(), xn(x), tp_spm[x] ? "RISE" : "FALL",
                             po(p), tim_ok(g) ? tg[g] : 0, tp_spb[x]);
                tg_m[g] = tp_spm[x];
            end
        end
        // ---- the origin ----
        if (tp_fgo[x]) begin
            p = tp_rport[x*6 +: 6]; g = x*64 + p;
            c = LD_PHONES[g] ? c_id[g] : -1;
            tg[g] = c; tg_t[g] = tnow(); tg_m[g] = 1;
            $display("TE %.3f %s KEY %s %0d dial=%s dest=%s", tnow(), xn(x), po(p), c,
                     LD_PHONES[g] ? digstr(g) : "?", LD_PHONES[g] ? ((c_kind[g] == K_BAD) ? "BAD" : pn(c_dest[g])) : "?");
        end
        c = tg[x*64 + tp_caller[x*6 +: 6]];
        if (nst_d == 4'd1 && tp_nst[x*4 +: 4] == 4'd2)
            $display("TE %.3f %s OSWEEP %s %0d", tnow(), xn(x), po(tp_caller[x*6 +: 6]), c);
        if (tp_worig[x] && tp_nst[x*4 +: 4] == 4'd3) begin
            for (j = 0; j < 4; j++) if (tp_ook[x*4 + j]) begin
                p = tp_ocand[x*24 + j*6 +: 6]; g = x*64 + p;
                tg[g] = c; tg_t[g] = tnow(); tg_m[g] = 0;
                $display("TE %.3f %s SEIZE %s %0d caller=%s", tnow(), xn(x), po(p), c, po(tp_caller[x*6 +: 6]));
            end
        end
        if (tp_claimed[x] && !claimed_d)
            $display("TE %.3f %s OCLAIM %s %0d glare=%0d tmr=%0d", tnow(), xn(x), po(tp_trunk[x*6 +: 6]), c,
                     guard_d, tp_tmr[x*16 +: 16]);
        if (tp_nst[x*4 +: 4] == 4'd7 && nst_d != 4'd7)
            $display("TE %.3f %s ODROP %s %0d after=%0d guard=%0d brk=%0d tmr=%0d from=%0d", tnow(), xn(x),
                     po(tp_caller[x*6 +: 6]), c, tp_oafter[x*2 +: 2], guard_d, rbrk_d, tp_tmr[x*16 +: 16], nst_d);
        if (tp_nst[x*4 +: 4] == 4'd8 && nst_d != 4'd8 && nst_d != 4'd7)
            $display("TE %.3f %s OEND %s %0d after=%0d from=%0d", tnow(), xn(x),
                     po(tp_caller[x*6 +: 6]), c, tp_oafter[x*2 +: 2], nst_d);
        if (tp_worig[x] && tp_nst[x*4 +: 4] == 4'd6)
            $display("TE %.3f %s ODONE %s %0d trunk=%s", tnow(), xn(x), po(tp_caller[x*6 +: 6]), c,
                     po(tp_trunk[x*6 +: 6]));
        // ---- the classifier ----
        if (tp_clsiss[x]) begin
            p = tp_clsrp[x*6 +: 6];
            if (LD_TRUNKS[x*64 + p])
                $display("TE %.3f %s CREAD %s %0d", tnow(), xn(x), po(p), tg[x*64 + p]);
        end else if (tp_clsseen[x]) begin
            p = tp_spp[x*6 +: 6];
            if (LD_TRUNKS[x*64 + p])
                $display("TE %.3f %s CWAIT %s %0d", tnow(), xn(x), po(p), tg[x*64 + p]);
        end
        if (tp_wcls[x]) begin
            p = tp_clsport[x*6 +: 6]; g = x*64 + p;
            if (tp_cst[x*3 +: 3] == 3'd4)
                $display("TE %.3f %s UNHOLD %s %0d", tnow(), xn(x), po(p), tg[g]);
            else begin
                cl = -1;
                for (i = 0; i < LD_NMON; i++) if (tp_mfree1[x*LD_NMON + i]) cl = i;
                if (tp_late[x])
                    $display("TE %.3f %s HOLD %s %0d cell=- fwd=0 late=1", tnow(), xn(x), po(p), tg[g]);
                else
                $display("TE %.3f %s HOLD %s %0d cell=%s fwd=%0d", tnow(), xn(x), po(p), tg[g],
                         (cl >= 0) ? $sformatf("%0d", cl) : "-", !tp_nfb[x]);
            end
        end
        // ---- the monitors ----
        for (i = 0; i < LD_NMON; i++) begin
            p = tp_mport[x*6*LD_NMON + i*6 +: 6]; g = x*64 + p;
            if (tp_marmed[x*LD_NMON + i] && !armed_d[i])
                $display("TE %.3f %s ARM %s %0d cell=%0d", tnow(), xn(x), po(p), tg[g], i);
            if (tp_dstb[x*LD_NMON + i] && tp_mheld[x*LD_NMON + i])
                $display("TE %.3f %s MDIG %s %0d cell=%0d st=%s cnt=%0d", tnow(), xn(x), po(p), tg[g], i,
                         (tp_mst[x*2*LD_NMON + i*2 +: 2] == 2'd1) ? "E" :
                         (tp_mst[x*2*LD_NMON + i*2 +: 2] == 2'd2) ? "B" : "D",
                         tp_dcnt[x*4*LD_NMON + i*4 +: 4]);
            if (!tp_mheld[x*LD_NMON + i] && held_d[i] && !(wclaim_d && p == mwp_d))
                $display("TE %.3f %s MREL %s %0d cell=%0d", tnow(), xn(x), po(p), tg[g], i);
        end
        if (tp_wclaim[x]) begin
            p = tp_mwp[x*6 +: 6];
            $display("TE %.3f %s CLAIM %s %0d", tnow(), xn(x), po(p), tg[x*64 + p]);
        end
        // ---- the forwarder ----
        if (fst_d == 2'd1 && tp_fst[x*2 +: 2] == 2'd2)
            $display("TE %.3f %s FSWEEP %s %0d", tnow(), xn(x), po(tp_fin[x*6 +: 6]), tg[x*64 + tp_fin[x*6 +: 6]]);
        if (fst_d == 2'd1 && tp_fst[x*2 +: 2] == 2'd0)
            $display("TE %.3f %s FNONE %s %0d cancel=%0d nosweep=1", tnow(), xn(x), po(tp_fin[x*6 +: 6]),
                     tg[x*64 + tp_fin[x*6 +: 6]], tp_fcancel[x]);
        if (fst_d == 2'd2 && tp_fst[x*2 +: 2] == 2'd0)
            $display("TE %.3f %s FNONE %s %0d cancel=%0d legs=%0d", tnow(), xn(x), po(tp_fin[x*6 +: 6]),
                     tg[x*64 + tp_fin[x*6 +: 6]], tp_fcancel[x], tp_fok[x*4 +: 4]);
        if (tp_wfwd[x]) begin
            p = tp_fin[x*6 +: 6]; c = tg[x*64 + p]; s = "";
            for (j = 0; j < 4; j++) if (tp_fok[x*4 + j]) begin
                q = tp_fcand[x*24 + j*6 +: 6]; g = x*64 + q;
                tg[g] = c; tg_t[g] = tnow(); tg_m[g] = 0;
                s = {s, " ", po(q)};
            end
            $display("TE %.3f %s FWD %s %0d legs=%s", tnow(), xn(x), po(p), c, s);
        end
        if (tp_wres[x]) begin
            for (i = 0; i < LD_NRES; i++) if (tp_ract1[x*LD_NRES + i]) begin
                p = tp_rin[x*6*LD_NRES + i*6 +: 6];
                $display("TE %.3f %s RES %s %0d act=%s leg=%0d", tnow(), xn(x), po(p), tg[x*64 + p],
                         (tp_ract[x*2*LD_NRES + i*2 +: 2] == 2'd1) ? "LEG" : "GONE", tp_rcl[x*2*LD_NRES + i*2 +: 2]);
            end
        end
        // ---- the claim reaches the marker ----
        if (tp_att[x] && !att_d)
            $display("TE %.3f %s ATT %s %0d", tnow(), xn(x), po(tp_attp[x*6 +: 6]), tg[x*64 + tp_attp[x*6 +: 6]]);
        if (tp_ktake[x])
            $display("TE %.3f %s TAKE %s %0d", tnow(), xn(x), po(tp_kattp[x*6 +: 6]), tg[x*64 + tp_kattp[x*6 +: 6]]);
        if (ld_p_mref[x] && !tp_ktake[x])
            $display("TE %.3f %s REFUSE %s %0d", tnow(), xn(x), po(tp_kattp[x*6 +: 6]), tg[x*64 + tp_kattp[x*6 +: 6]]);
        if (tp_kctx[x] && tp_rbusy[x] && tp_rnd[x*3 +: 3] != rnd_d && tp_rnd[x*3 +: 3] != 3'd0) begin
            p = tp_kcaller[x*6 +: 6]; j = tp_rnd[x*3 +: 3] - 1;
            $display("TE %.3f %s RDIG %s %0d n=%0d d=%0d", tnow(), xn(x), po(p), tg[x*64 + p],
                     tp_rnd[x*3 +: 3], tp_rdig[x*16 + j*4 +: 4]);
        end
        nst_d <= tp_nst[x*4 +: 4]; fst_d <= tp_fst[x*2 +: 2]; cst_d <= tp_cst[x*3 +: 3];
        armed_d <= tp_marmed[x*LD_NMON +: LD_NMON]; held_d <= tp_mheld[x*LD_NMON +: LD_NMON];
        att_d <= tp_att[x]; claimed_d <= tp_claimed[x]; guard_d <= tp_guard[x]; rbrk_d <= tp_rbrk[x];
        rnd_d <= tp_rnd[x*3 +: 3];
        wclaim_d <= tp_wclaim[x]; mwp_d <= tp_mwp[x*6 +: 6];
    end
end endgenerate
