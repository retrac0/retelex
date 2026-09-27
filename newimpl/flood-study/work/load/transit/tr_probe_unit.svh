// tr_probe_unit.svh -- TRANSIT PROBE for one exchange.  Before including:
//   `define TPX <exchange index>   `define TPS <site instance>
// Reads the unit's own nets (pre-edge values at the unit clock) and prints TP lines.
assign tp_dheld[`TPX]  = `TPS.u_x.u_net.d_held;
assign tp_dtrunk[`TPX] = `TPS.u_x.u_net.d_trunk;
assign tp_rsheld[`TPX] = `TPS.u_x.u_net.rs_held;
assign tp_rsleg[`TPX]  = `TPS.u_x.u_net.rs_leg;
assign tp_m[`TPX]      = `TPS.s_a;

always @(posedge ld_clk[`TPX]) begin
    int x, p, j, v, g, fg, hb, leg, nleg, ev;
    real t;
    string fs;
    x = `TPX;
    t = tp_now();
    // ---------------- the classifier: a seizure, or a hold written away -------------
    if (`TPS.u_x.u_net.w_cls && `TPS.u_x.u_net.cst == 3'd2) begin
        p = `TPS.u_x.u_net.cls_port; g = x*64 + p;
        tp_cnt[x*TPK + TK_SEIZE]++;
        tp_seize_t[g] = t;
        fg = tp_far(x, p);
        if (!`TPS.u_x.u_net.m_free_any) tp_cnt[x*TPK + TK_NOMON]++;
        if ((~4'b0000 & ~(4'd1 << `TPS.u_x.u_net.cls_dir)) == 4'd0) begin
            ev = 3; tp_cnt[x*TPK + TK_NFMASK]++;
        end else if (`TPS.u_x.u_net.fst != 2'd0) begin
            ev = 1; tp_cnt[x*TPK + TK_NFB]++;
            case (`TPS.u_x.u_net.fst)
            2'd1: begin
                tp_cnt[x*TPK + TK_NFB_WANT]++;
                if (`TPS.u_x.u_net.hst != 3'd0 && !`TPS.u_x.u_net.h_owner) tp_cnt[x*TPK + TK_NFB_ORIGSWEEP]++;
            end
            2'd2: tp_cnt[x*TPK + TK_NFB_HUNT]++;
            default: tp_cnt[x*TPK + TK_NFB_WRITE]++;
            endcase
        end else if (!`TPS.u_x.u_net.rs_free_any) begin
            ev = 2; tp_cnt[x*TPK + TK_NFRES]++;
        end else begin
            ev = 0; tp_cnt[x*TPK + TK_SFWD]++;
        end
        fs = "yes";
        if (ev == 1) fs = "FWDBUSY";
        if (ev == 2) fs = "RESNONE";
        if (ev == 3) fs = "nomask";
        if (fg >= 0 && tp_wr_t[fg] > 0.0) begin
            tp_hist(x, 0, t - tp_wr_t[fg]);
            if (t - tp_wr_t[fg] > 40.0) tp_cnt[x*TPK + TK_SEIZE_LATE]++;
        end
        $display("TP t=%.3f n=%0d ex=%s SEIZE p=%s dir=%0d mon=%0d fwd=%s fst=%0d hst=%0d hown=%0d rsb=%b hop=%.2f",
                 t, now_ms, xn(x), pn(g), `TPS.u_x.u_net.cls_dir, `TPS.u_x.u_net.m_free_any,
                 fs,
                 `TPS.u_x.u_net.fst, `TPS.u_x.u_net.hst, `TPS.u_x.u_net.h_owner, `TPS.u_x.u_net.rs_busy,
                 (fg >= 0 && tp_wr_t[fg] > 0.0) ? t - tp_wr_t[fg] : -1.0);
    end
    if (`TPS.u_x.u_net.w_cls && `TPS.u_x.u_net.cst == 3'd4) begin
        p = `TPS.u_x.u_net.cls_port;
        tp_cnt[x*TPK + TK_UNHOLD]++;
        if (`TPS.u_x.u_net.fst != 2'd0 && `TPS.u_x.u_net.f_in == 6'(p)) tp_cnt[x*TPK + TK_UNHOLD_FWD]++;
        $display("TP t=%.3f n=%0d ex=%s UNHOLD p=%s fst=%0d f_in=%s held_ms=%.2f", t, now_ms, xn(x), pn(x*64 + p),
                 `TPS.u_x.u_net.fst, pn(x*64 + `TPS.u_x.u_net.f_in), t - tp_seize_t[x*64 + p]);
    end
    if (`TPS.u_x.u_net.nf_empty) begin
        tp_cnt[x*TPK + TK_NFE]++;
        $display("TP t=%.3f n=%0d ex=%s NFEMPTY in=%s", t, now_ms, xn(x), pn(x*64 + `TPS.u_x.u_net.f_in));
    end
    // ---------------- the forward write ----------------------------------------------
    if (`TPS.u_x.u_net.w_fwd) begin
        p = `TPS.u_x.u_net.f_in; g = x*64 + p;
        tp_cnt[x*TPK + TK_FWD]++;
        tp_hist(x, 1, t - tp_seize_t[g]);
        hb = 0;
        if (!ld_busy[g] || !tp_m[x][p]) begin hb = 1; tp_cnt[x*TPK + TK_FWD_INDEAD]++; end
        if (`TPS.u_x.u_net.f_cancel) tp_cnt[x*TPK + TK_FWD_FCAN]++;
        if (tp_claim_t[g] > tp_seize_t[g]) tp_cnt[x*TPK + TK_FWD_INCLAIMED]++;
        nleg = 0;
        for (j = 0; j < 4; j++) if (`TPS.u_x.u_net.f_ok[j]) begin
            leg = `TPS.u_x.u_net.f_cand[j*6 +: 6];
            tp_wr_t[x*64 + leg] = t;
            if (ld_busy[x*64 + leg] || tp_m[x][leg]) nleg++;
        end
        if (nleg > 0) tp_cnt[x*TPK + TK_FWD_LEGTAKEN]++;
        for (v = 0; v < LD_NRES; v++) if (`TPS.u_x.u_net.rs_free1[v]) tp_res_t0[x*8 + v] = t;
        $display("TP t=%.3f n=%0d ex=%s FWD in=%s ok=%b cand=%o in_busy=%0d in_m=%0d fcan=%0d legtaken=%0d after_ms=%.2f",
                 t, now_ms, xn(x), pn(g), `TPS.u_x.u_net.f_ok, `TPS.u_x.u_net.f_cand, ld_busy[g], tp_m[x][p],
                 `TPS.u_x.u_net.f_cancel, nleg, t - tp_seize_t[g]);
    end
    // ---------------- the resolvers ---------------------------------------------------
    if (`TPS.u_x.u_net.w_res) begin
        for (v = 0; v < LD_NRES; v++) if (`TPS.u_x.u_net.rs_act1[v]) begin
            p = `TPS.u_x.u_net.rs_in[v*6 +: 6];
            if (`TPS.u_x.u_net.rs_act[v*2 +: 2] == 2'd1) begin
                j = `TPS.u_x.u_net.rs_cl[v*2 +: 2];
                leg = `TPS.u_x.u_net.rs_leg[(v*4 + j)*6 +: 6];
                fg = tp_far(x, leg);
                tp_cnt[x*TPK + TK_RES_LEG]++;
                hb = tp_heldby(fg);
                if (fg >= 0 && !(tp_claim_t[fg] > tp_res_t0[x*8 + v] - 1.0)) begin
                    tp_cnt[x*TPK + TK_RES_LEG_NOCLAIM]++;
                    if (hb != 0) tp_cnt[x*TPK + TK_RES_LEG_GLARE]++;
                end
                $display("TP t=%.3f n=%0d ex=%s RES v=%0d LEG in=%s leg=%s far=%s farclaim_ago=%.2f farheld=%0d hold_ms=%.2f",
                         t, now_ms, xn(x), v, pn(x*64 + p), pn(x*64 + leg), pn(fg),
                         (fg >= 0) ? t - tp_claim_t[fg] : -1.0, hb, t - tp_res_t0[x*8 + v]);
            end else begin
                tp_cnt[x*TPK + TK_RES_GONE]++;
                $display("TP t=%.3f n=%0d ex=%s RES v=%0d GONE in=%s hold_ms=%.2f", t, now_ms, xn(x), v,
                         pn(x*64 + p), t - tp_res_t0[x*8 + v]);
            end
            tp_hist(x, 2, t - tp_res_t0[x*8 + v]);
            tp_res_t0[x*8 + v] = -1.0;
        end
    end
    // ---------------- a claim here --------------------------------------------------
    if (`TPS.u_x.u_net.w_claim) begin
        p = `TPS.u_x.u_net.m_want_port; g = x*64 + p;
        tp_cnt[x*TPK + TK_CLAIM]++;
        tp_claim_t[g] = t;
        for (v = 0; v < LD_NRES; v++) if (`TPS.u_x.u_net.rs_mine[v]) begin
            tp_cnt[x*TPK + TK_RES_MINE]++;
            tp_hist(x, 2, t - tp_res_t0[x*8 + v]);
            $display("TP t=%.3f n=%0d ex=%s RES v=%0d MINE in=%s hold_ms=%.2f", t, now_ms, xn(x), v, pn(g),
                     t - tp_res_t0[x*8 + v]);
            tp_res_t0[x*8 + v] = -1.0;
        end
        $display("TP t=%.3f n=%0d ex=%s CLAIM p=%s mine=%b since_seize=%.2f", t, now_ms, xn(x), pn(g),
                 `TPS.u_x.u_net.rs_mine, t - tp_seize_t[g]);
    end
    // ---------------- the origin ------------------------------------------------------
    if (tp_pnst[x] == 0 && `TPS.u_x.u_net.nst == 4'd1) begin
        tp_cnt[x*TPK + TK_OFLOOD]++;
        tp_flood_t[x] = t;
        $display("TP t=%.3f n=%0d ex=%s OFLOOD caller=%s", t, now_ms, xn(x), pn(x*64 + `TPS.u_x.u_net.caller));
    end
    if (`TPS.u_x.u_net.w_orig && `TPS.u_x.u_net.nst == 4'd3) begin
        tp_cnt[x*TPK + TK_OSEIZE]++;
        nleg = 0;
        for (j = 0; j < 4; j++) if (`TPS.u_x.u_net.o_ok[j]) begin
            leg = `TPS.u_x.u_net.o_cand[j*6 +: 6];
            tp_wr_t[x*64 + leg] = t;
            if (ld_busy[x*64 + leg] || tp_m[x][leg]) nleg++;
        end
        if (nleg > 0) tp_cnt[x*TPK + TK_OSEIZE_TAKEN]++;
        $display("TP t=%.3f n=%0d ex=%s OSEIZE caller=%s ok=%b cand=%o taken=%0d after_flood=%.2f", t, now_ms, xn(x),
                 pn(x*64 + `TPS.u_x.u_net.caller), `TPS.u_x.u_net.o_ok, `TPS.u_x.u_net.o_cand, nleg, t - tp_flood_t[x]);
    end
    if (!tp_pcl[x] && `TPS.u_x.u_net.claimed && (`TPS.u_x.u_net.nst == 4'd4 || `TPS.u_x.u_net.nst == 4'd5 ||
                                                  `TPS.u_x.u_net.nst == 4'd6)) begin
        p = `TPS.u_x.u_net.trunk; g = x*64 + p;
        fg = tp_far(x, p);
        tp_cnt[x*TPK + TK_OCLAIM]++;
        if (`TPS.u_x.u_net.n_glare != 0 && `TPS.u_x.u_net.ev_glare) tp_cnt[x*TPK + TK_OCLAIM_GUARD]++;
        tp_hist(x, 3, t - tp_wr_t[g]);
        $display("TP t=%.3f n=%0d ex=%s OCLAIM caller=%s trunk=%s guard_glare=%0d since_seize=%.2f farheld=%0d",
                 t, now_ms, xn(x), pn(x*64 + `TPS.u_x.u_net.caller), pn(g), `TPS.u_x.u_net.ev_glare,
                 t - tp_wr_t[g], tp_heldby(fg));
    end
    if (`TPS.u_x.u_net.w_orig && `TPS.u_x.u_net.nst == 4'd6) begin
        tp_cnt[x*TPK + TK_ODONE]++;
        $display("TP t=%.3f n=%0d ex=%s ODONE caller=%s trunk=%s since_flood=%.2f", t, now_ms, xn(x),
                 pn(x*64 + `TPS.u_x.u_net.caller), pn(x*64 + `TPS.u_x.u_net.trunk), t - tp_flood_t[x]);
    end
    if (`TPS.u_x.u_net.nst == 4'd8 && tp_pnst[x] != 8) begin
        case (`TPS.u_x.u_net.o_after)
        2'd1: tp_cnt[x*TPK + TK_OEND_NOGO]++;
        2'd2: tp_cnt[x*TPK + TK_OEND_LOCAL]++;
        default: tp_cnt[x*TPK + TK_OEND_NONE]++;
        endcase
        $display("TP t=%.3f n=%0d ex=%s OEND caller=%s after=%0d from_nst=%0d claimed=%0d since_flood=%.2f", t, now_ms,
                 xn(x), pn(x*64 + `TPS.u_x.u_net.caller), `TPS.u_x.u_net.o_after, tp_pnst[x],
                 `TPS.u_x.u_net.claimed, t - tp_flood_t[x]);
    end
    tp_pnst[x] = `TPS.u_x.u_net.nst;
    tp_pcl[x]  = `TPS.u_x.u_net.claimed;
end
