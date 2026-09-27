// tr_probe_common.svh -- TRANSIT PROBE, shared part.  Included once in tb_tr3.sv
// after tr_harness.svh; then tr_probe_unit.svh once an exchange.
// Prints TP lines (t = sim ms, n = harness now_ms) and a TPSUM block at the end.
// Topology-specific: tp_far() below is tb_load3's wiring (A 010+i = B 010+i,
// B 030+i = C 010+i).

// counters, a row of TPK a exchange
localparam int TPK = 40;
localparam int TK_SEIZE = 0, TK_SFWD = 1, TK_NFB = 2, TK_NFRES = 3, TK_NFMASK = 4, TK_NFE = 5,
               TK_FWD = 6, TK_FWD_INDEAD = 7, TK_FWD_FCAN = 8, TK_FWD_LEGTAKEN = 9,
               TK_RES_LEG = 10, TK_RES_GONE = 11, TK_RES_MINE = 12, TK_RES_LEG_NOCLAIM = 13,
               TK_UNHOLD = 14, TK_UNHOLD_FWD = 15, TK_CLAIM = 16, TK_OFLOOD = 17,
               TK_OSEIZE_TAKEN = 18, TK_NFB_WANT = 19, TK_NFB_HUNT = 20, TK_NFB_WRITE = 21,
               TK_NOMON = 22, TK_OSEIZE = 23, TK_OCLAIM = 24, TK_OCLAIM_GUARD = 25,
               TK_ODONE = 26, TK_OEND_NOGO = 27, TK_OEND_LOCAL = 28, TK_OEND_NONE = 29,
               TK_RES_LEG_GLARE = 30, TK_FWD_INCLAIMED = 31, TK_NFB_ORIGSWEEP = 32,
               TK_SEIZE_LATE = 33, TK_OCLAIM_NOTREAL = 34, TK_RES_NEVER = 35;
int  tp_cnt [0:NX*TPK-1];
real tp_res_t0 [0:NX*8-1];          // when each resolver was taken
real tp_wr_t   [0:NG-1];            // the last unit write seizing this port (origin or leg)
real tp_claim_t[0:NG-1];            // the last CLAIM written on this port
real tp_seize_t[0:NG-1];            // the last classification of this port as a seizure
int  tp_pnst [0:NX-1];
bit  tp_pcl  [0:NX-1];
real tp_flood_t [0:NX-1];
// histograms (ms, 1 ms bins up to 4095): 0 hop delay (upstream write -> seize here),
// 1 seize -> forward write, 2 resolver hold, 3 origin write -> origin claim
localparam int TPH = 4096;
int  tp_h [0:NX*4*TPH-1];
int  tp_hn [0:NX*4-1];
real tp_hs [0:NX*4-1];
real tp_hmax [0:NX*4-1];

// the planes each unit holds, for the far-end checks
wire [3:0]            tp_dheld  [0:NX-1];
wire [23:0]           tp_dtrunk [0:NX-1];
wire [LD_NRES*4-1:0]  tp_rsheld [0:NX-1];
wire [LD_NRES*24-1:0] tp_rsleg  [0:NX-1];
wire [63:0]           tp_m      [0:NX-1];      // M into each port (the card's A)

function automatic int tp_far(int x, int p);
    if (x == 0 && p >= 8 && p < 16)  return 1*64 + p;
    if (x == 1 && p >= 8 && p < 16)  return 0*64 + p;
    if (x == 1 && p >= 24 && p < 32) return 2*64 + (p - 16);
    if (x == 2 && p >= 8 && p < 16)  return 1*64 + (p + 16);
    return -1;
endfunction

// is global port g held by its own unit as an origin trunk (1) or a forward leg (2)?
function automatic int tp_heldby(int g);
    int x, p, j, v;
    if (g < 0) return 0;
    x = g / 64; p = g % 64;
    for (j = 0; j < 4; j++) if (tp_dheld[x][j] && tp_dtrunk[x][j*6 +: 6] == 6'(p)) return 1;
    for (v = 0; v < LD_NRES; v++)
        for (j = 0; j < 4; j++)
            if (tp_rsheld[x][v*4 + j] && tp_rsleg[x][(v*4 + j)*6 +: 6] == 6'(p)) return 2;
    return 0;
endfunction

task automatic tp_hist(int x, int w, real ms);
    int b;
    b = $rtoi(ms);
    if (b < 0) b = 0;
    if (b >= TPH) b = TPH - 1;
    tp_h[(x*4 + w)*TPH + b]++;
    tp_hn[x*4 + w]++; tp_hs[x*4 + w] += ms;
    if (ms > tp_hmax[x*4 + w]) tp_hmax[x*4 + w] = ms;
endtask

function automatic int tp_pct(int x, int w, int pc);
    int i, acc, lim, n;
    n = tp_hn[x*4 + w];
    if (n == 0) return -1;
    lim = (n * pc + 99) / 100; acc = 0;
    for (i = 0; i < TPH; i++) begin acc += tp_h[(x*4 + w)*TPH + i]; if (acc >= lim) return i; end
    return TPH - 1;
endfunction

function automatic real tp_now();
    return $realtime / 1.0e6;
endfunction

initial begin : tp_init
    int i;
    for (i = 0; i < NX*TPK; i++) tp_cnt[i] = 0;
    for (i = 0; i < NX*8; i++) tp_res_t0[i] = -1.0;
    for (i = 0; i < NG; i++) begin tp_wr_t[i] = -1.0e9; tp_claim_t[i] = -1.0e9; tp_seize_t[i] = -1.0e9; end
    for (i = 0; i < NX; i++) begin tp_pnst[i] = 0; tp_pcl[i] = 0; tp_flood_t[i] = -1.0; end
    for (i = 0; i < NX*4*TPH; i++) tp_h[i] = 0;
    for (i = 0; i < NX*4; i++) begin tp_hn[i] = 0; tp_hs[i] = 0.0; tp_hmax[i] = 0.0; end
end

final begin : tp_final
    int x, k;
    string nm [0:TPK-1];
    string hn [0:3];
    for (k = 0; k < TPK; k++) nm[k] = $sformatf("k%0d", k);
    nm[TK_SEIZE] = "seize"; nm[TK_SFWD] = "seize_fwd"; nm[TK_NFB] = "nofwd_fwdbusy";
    nm[TK_NFRES] = "nofwd_resnone"; nm[TK_NFMASK] = "nofwd_nomask"; nm[TK_NFE] = "nofwd_empty";
    nm[TK_FWD] = "fwd"; nm[TK_FWD_INDEAD] = "fwd_in_dead"; nm[TK_FWD_FCAN] = "fwd_fcancel";
    nm[TK_FWD_LEGTAKEN] = "fwd_leg_taken"; nm[TK_RES_LEG] = "res_leg"; nm[TK_RES_GONE] = "res_gone";
    nm[TK_RES_MINE] = "res_mine"; nm[TK_RES_LEG_NOCLAIM] = "res_leg_noclaim";
    nm[TK_UNHOLD] = "unhold"; nm[TK_UNHOLD_FWD] = "unhold_fwd_inprog"; nm[TK_CLAIM] = "claim";
    nm[TK_OFLOOD] = "orig_flood"; nm[TK_OSEIZE_TAKEN] = "orig_seize_taken";
    nm[TK_NFB_WANT] = "nfb_want"; nm[TK_NFB_HUNT] = "nfb_hunt"; nm[TK_NFB_WRITE] = "nfb_write";
    nm[TK_NOMON] = "nomon"; nm[TK_OSEIZE] = "orig_seize"; nm[TK_OCLAIM] = "orig_claim";
    nm[TK_OCLAIM_GUARD] = "orig_claim_inguard"; nm[TK_ODONE] = "orig_done";
    nm[TK_OEND_NOGO] = "orig_nogo"; nm[TK_OEND_LOCAL] = "orig_local"; nm[TK_OEND_NONE] = "orig_gone";
    nm[TK_RES_LEG_GLARE] = "res_leg_glare"; nm[TK_FWD_INCLAIMED] = "fwd_in_claimed";
    nm[TK_NFB_ORIGSWEEP] = "nfb_origsweep"; nm[TK_SEIZE_LATE] = "seize_late_gt40ms";
    nm[TK_OCLAIM_NOTREAL] = "orig_claim_noclaim"; nm[TK_RES_NEVER] = "res_held_at_end";
    hn[0] = "hop"; hn[1] = "seize_to_fwd"; hn[2] = "res_hold"; hn[3] = "orig_to_claim";
    for (x = 0; x < NX; x++) begin
        for (k = 0; k < LD_NRES; k++) if (tp_res_t0[x*8 + k] >= 0.0) tp_cnt[x*TPK + TK_RES_NEVER]++;
        $write("TPSUM ex=%s", xn(x));
        for (k = 0; k < 36; k++) $write(" %s=%0d", nm[k], tp_cnt[x*TPK + k]);
        $write("\n");
        for (k = 0; k < 4; k++)
            $display("TPHIST ex=%s what=%s n=%0d mean=%.2f p50=%0d p90=%0d p99=%0d max=%.2f", xn(x),
                     hn[k],
                     tp_hn[x*4 + k], tp_hn[x*4 + k] ? tp_hs[x*4 + k] / tp_hn[x*4 + k] : 0.0,
                     tp_pct(x, k, 50), tp_pct(x, k, 90), tp_pct(x, k, 99), tp_hmax[x*4 + k]);
    end
end
