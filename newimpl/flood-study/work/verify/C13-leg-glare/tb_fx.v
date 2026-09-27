// tb_fx -- AUDIT (fwd slice): the forwarder, the resolvers and the sweep of ONE
// exchange, driven from its links.  REAL TIMERS (T_ARM 16, T_REL 256, HIT 8,
// ID 128, CLR 256, guard 128, T_CLAIM 2000, T_KEY 5000, NODIG 10000), because
// the sweep and cable B are unscaled and the races here are sweep-against-
// timer.
//
// B is code 2 3, top_net (mini marker, one register, NMON 2, NRES 2), phones at
// 20 21 22.  Its links:
//   W  a local eight-channel trunk on block 1 (10-17).  The far unit F is a
//      local_trunk instance in the bench, clocked from B, whose header side the
//      bench drives (far_m = the far ports' A toward B) and reads (f_a_tx = what
//      the far ports see as M from B).  `lnk` is the cable.
//   E  baseband cards at 30-33, S at 40-43, N at 74-77.  Their far ends are the
//      bench: sm = the far A (M at B's port), a_out = B's port's backward A (what
//      the far exchange sees as M), sup = the far clock (link up).
// The bench plays every neighbour: it seizes, dials, claims and hangs up on the
// wires, and reads B's registers hierarchically only to REPORT.
//
//   +sc=2 +var=0|1  a link outage under a forward: the resolver outlives it
//   +sc=3           glare on a forward's leg
//   +sc=4           resolver pool exhausted: floods held and not passed on
//   +sc=5           hop latency: nominal, behind a T_ARM watch, behind an origin sweep
//   +sc=6 +dly=D +load=0|1   a flood arriving D ms after its origin seized, the
//                   origin's first break at 129 ms (just past its guard)
`timescale 1ns/1ps
`include "exch.vh"

module tb_fx;
    integer chk = 0, errs = 0;
    task ck(input cond, input [8*120-1:0] what);
        begin chk = chk + 1;
            if (!cond) begin errs = errs + 1; $display("    FAIL  %0s", what); end
            else       $display("    ok    %0s", what);
        end
    endtask

    reg clk = 1'b0, rst_n = 1'b0;
    always #122.070 clk = ~clk;

    localparam [7:0] WN = {2'd0, 1'b0, 3'b010, 2'b11};
    localparam [7:0] WS = {2'd1, 1'b0, 3'b010, 2'b11};
    localparam [7:0] WE = {2'd2, 1'b0, 3'b010, 2'b11};
    localparam [7:0] WW = {2'd3, 1'b0, 3'b010, 2'b11};
    localparam [63:0] TR = (64'hF << 6'o30) | (64'hF << 6'o40) | (64'hF << 6'o74);
    localparam [63:0] PH = 64'h7 << 6'o20;
    function [511:0] tw_of(input integer dummy);
        integer q;
        begin
            tw_of = 512'd0;
            for (q = 0; q < 4; q = q + 1) begin
                tw_of[(6'o30 + q)*8 +: 8] = WE;
                tw_of[(6'o40 + q)*8 +: 8] = WS;
                tw_of[(6'o74 + q)*8 +: 8] = WN;
            end
        end
    endfunction
    localparam [511:0] TW = tw_of(0);

    // ---- the site ------------------------------------------------------------
    reg  [63:0] hook = 64'd0, tx = 64'd0;
    wire [63:0] rx, e, busy;
    wire [63:0] c_out, a_out, clk_out, link_up;
    reg  [63:0] sm = 64'd0, sc = 64'd0, sup = TR;
    wire [63:0] c_in = sc & TR, a_in = sm & TR;
    wire [63:0] clk_in = clk_out & sup;

    wire [7:0] lc_o, la_o, lh_o, lk_o, lup;
    wire       b_txclk, b_c8k, b_fill, b_hclk;
    reg        lnk = 1'b1;
    reg  [7:0] far_m = 8'd0, far_c = 8'd0;
    wire [7:0] f_c_tx, f_a_tx;
    wire       f_c_out, f_a_out, f_h_out, f_k_out, f_up, f_mute;
    wire [7:0] lc_i = {6'd0, lnk & f_c_out, 1'b0}, la_i = {6'd0, lnk & f_a_out, 1'b0};
    wire [7:0] lh_i = {6'd0, lnk & f_h_out, 1'b0}, lk_i = {6'd0, lnk & f_k_out, 1'b0};

    wire fs, t1k, rcad, sd, scl, wrb, clash, regb, mko, clm, hnt, uno;
    wire [2:0] mks; wire [3:0] dirs; wire [1:0] res, mon; wire [7:0] ngl, nnf;

    site_fx #(.PHONES(PH), .TRUNKS(TR), .TWORD(TW), .OWN_E(3'd2), .OWN_B(3'd3),
              .T_ARM(9'd16), .T_REL(9'd256), .RING_ON(13'd2048), .RING_OFF(13'd4096),
              .HIT(9'd8), .ID(9'd128), .CLR(9'd256), .NODIG(16'd10000),
              .T_GUARD0(16'd128), .T_KEY(16'd5000), .T_CLAIM(16'd2000),
              .LTU(8'b0000_0010), .LTWORD({48'd0, WW, 8'd0})) B (
        .clk(clk), .rst_n(rst_n), .hook(hook), .tx(tx), .rx(rx), .e(e),
        .c_out(c_out), .a_out(a_out), .clk_out(clk_out), .c_in(c_in), .a_in(a_in),
        .clk_in(clk_in), .link_up(link_up),
        .lt_c_out(lc_o), .lt_a_out(la_o), .lt_h_out(lh_o), .lt_k_out(lk_o),
        .lt_c_in(lc_i), .lt_a_in(la_i), .lt_h_in(lh_i), .lt_k_in(lk_i), .lt_up(lup),
        .o_tx_clk(b_txclk), .o_clk_8k(b_c8k), .o_fill(b_fill), .o_hclk(b_hclk),
        .frame_stb(fs), .tick_1k(t1k), .ring_cad_n(rcad), .port_busy(busy),
        .b_sdata(sd), .b_sclk(scl), .b_wr(wrb), .b_clash(clash),
        .reg_busy(regb), .mk_state(mks), .mk_ovf(mko), .dirs_held(dirs),
        .res_busy(res), .mon_held(mon), .claimed(clm), .hunting(hnt), .un_ovf(uno),
        .n_glare(ngl), .n_nofwd(nnf));

    local_trunk #(.WORD(WE), .HOLDOFF(16'd64)) F (
        .clk(clk), .rst_n(rst_n), .c_tx(f_c_tx), .a_tx(f_a_tx), .word_n(), .ans_n(),
        .c_rx(far_c), .a_rx(far_m), .tx_clk(b_txclk), .tx_oct(b_c8k), .fill(b_fill),
        .hclk(b_hclk), .mute_blk(f_mute),
        .c_out(f_c_out), .a_out(f_a_out), .hclk_out(f_h_out), .clk_out(f_k_out),
        .c_in(lnk & lc_o[1]), .a_in(lnk & la_o[1]), .hclk_in(lnk & lh_o[1]),
        .clk_in(lnk & lk_o[1]), .link_up(f_up));

    // ---- B's insides, READ ONLY, for the report --------------------------------
    wire [2:0]  hst     = B.u_x.u_net.hst;
    wire [6:0]  h_n     = B.u_x.u_net.h_n;
    wire        h_owner = B.u_x.u_net.h_owner;
    wire [1:0]  fst     = B.u_x.u_net.fst;
    wire [3:0]  nst     = B.u_x.u_net.nst;
    wire [2:0]  cst     = B.u_x.u_net.cst;
    wire [1:0]  rsb     = B.u_x.u_net.rs_busy;
    wire [11:0] rs_in   = B.u_x.u_net.rs_in;
    wire [47:0] rs_leg  = B.u_x.u_net.rs_leg;
    wire [7:0]  rs_held = B.u_x.u_net.rs_held;
    wire [3:0]  rs_act  = B.u_x.u_net.rs_act;
    wire [3:0]  d_held  = B.u_x.u_net.d_held;

    // every port's latch: [ addr | bsy | clm ]
    wire [8*64-1:0] lat;
    genvar gh;
    generate for (gh = 0; gh < 8; gh = gh + 1) begin : LT
        assign lat[(gh*8+0)*8 +: 8] = {B.u_x.u_exch.pos[gh].u_blk.u_port0.addr, B.u_x.u_exch.pos[gh].u_blk.u_port0.bsy, B.u_x.u_exch.pos[gh].u_blk.u_port0.clm};
        assign lat[(gh*8+1)*8 +: 8] = {B.u_x.u_exch.pos[gh].u_blk.u_port1.addr, B.u_x.u_exch.pos[gh].u_blk.u_port1.bsy, B.u_x.u_exch.pos[gh].u_blk.u_port1.clm};
        assign lat[(gh*8+2)*8 +: 8] = {B.u_x.u_exch.pos[gh].u_blk.u_port2.addr, B.u_x.u_exch.pos[gh].u_blk.u_port2.bsy, B.u_x.u_exch.pos[gh].u_blk.u_port2.clm};
        assign lat[(gh*8+3)*8 +: 8] = {B.u_x.u_exch.pos[gh].u_blk.u_port3.addr, B.u_x.u_exch.pos[gh].u_blk.u_port3.bsy, B.u_x.u_exch.pos[gh].u_blk.u_port3.clm};
        assign lat[(gh*8+4)*8 +: 8] = {B.u_x.u_exch.pos[gh].u_blk.u_port4.addr, B.u_x.u_exch.pos[gh].u_blk.u_port4.bsy, B.u_x.u_exch.pos[gh].u_blk.u_port4.clm};
        assign lat[(gh*8+5)*8 +: 8] = {B.u_x.u_exch.pos[gh].u_blk.u_port5.addr, B.u_x.u_exch.pos[gh].u_blk.u_port5.bsy, B.u_x.u_exch.pos[gh].u_blk.u_port5.clm};
        assign lat[(gh*8+6)*8 +: 8] = {B.u_x.u_exch.pos[gh].u_blk.u_port6.addr, B.u_x.u_exch.pos[gh].u_blk.u_port6.bsy, B.u_x.u_exch.pos[gh].u_blk.u_port6.clm};
        assign lat[(gh*8+7)*8 +: 8] = {B.u_x.u_exch.pos[gh].u_blk.u_port7.addr, B.u_x.u_exch.pos[gh].u_blk.u_port7.bsy, B.u_x.u_exch.pos[gh].u_blk.u_port7.clm};
    end endgenerate
    function [5:0] la(input integer p); la = lat[p*8+2 +: 6]; endfunction
    function       lb(input integer p); lb = lat[p*8+1];      endfunction

    // ---- time --------------------------------------------------------------------
    integer msn = 0;
    always @(posedge clk) if (t1k) msn = msn + 1;
    function real tms(input integer dummy); tms = $realtime / 1.0e6; endfunction

    // ---- a log of what matters: B's resolvers, forwarder, sweep, trunk ports --------
    localparam [63:0] WATCH = TR | (64'hFF << 8) | PH;
    reg [63:0] busy_d = 64'd0, aout_d = 64'd0; reg [7:0] fa_d = 8'd0;
    reg [1:0] rsb_d = 2'd0, fst_d = 2'd0; reg [2:0] hst_d = 3'd0; reg [3:0] nst_d = 4'd0;
    reg [7:0] nnf_d = 8'd0, ngl_d = 8'd0; reg [1:0] mon_d = 2'd0; reg lup_d = 1'b0;
    reg [8*64-1:0] lat_d = {64{8'd0}};
    integer lp;
    reg logon = 1'b1;
    always @(posedge clk) if (rst_n) begin
        if (logon) begin
            if (rsb != rsb_d)
                $display("  %9.3f ms  rs_busy %b -> %b   in %o %o  held %b %b  legs0 %o %o %o %o  legs1 %o %o %o %o",
                         tms(0), rsb_d, rsb, rs_in[5:0], rs_in[11:6], rs_held[3:0], rs_held[7:4],
                         rs_leg[5:0], rs_leg[11:6], rs_leg[17:12], rs_leg[23:18],
                         rs_leg[29:24], rs_leg[35:30], rs_leg[41:36], rs_leg[47:42]);
            if (fst != fst_d) $display("  %9.3f ms  fst %0d -> %0d", tms(0), fst_d, fst);
            if (hst != hst_d) $display("  %9.3f ms  hst %0d -> %0d (owner %0d)", tms(0), hst_d, hst, h_owner);
            if (nst != nst_d) $display("  %9.3f ms  nst %0d -> %0d  d_held %b", tms(0), nst_d, nst, d_held);
            if (nnf != nnf_d) $display("  %9.3f ms  n_nofwd %0d -> %0d", tms(0), nnf_d, nnf);
            if (ngl != ngl_d) $display("  %9.3f ms  n_glare %0d -> %0d", tms(0), ngl_d, ngl);
            if (mon != mon_d) $display("  %9.3f ms  mon_held %b -> %b", tms(0), mon_d, mon);
            if (lup[1] != lup_d) $display("  %9.3f ms  B's LTU link_up -> %b", tms(0), lup[1]);
            for (lp = 0; lp < 64; lp = lp + 1) if (WATCH[lp]) begin
                if (busy[lp] != busy_d[lp]) $display("  %9.3f ms  port %o BUSY -> %b", tms(0), lp[5:0], busy[lp]);
                if (TR[lp] && a_out[lp] != aout_d[lp]) $display("  %9.3f ms  port %o a_out (far M) -> %b", tms(0), lp[5:0], a_out[lp]);
                if (lat[lp*8 +: 8] != lat_d[lp*8 +: 8])
                    $display("  %9.3f ms  port %o latch -> src %o bsy %b clm %b", tms(0), lp[5:0],
                             lat[lp*8+2 +: 6], lat[lp*8+1], lat[lp*8]);
            end
            for (lp = 0; lp < 8; lp = lp + 1)
                if (f_a_tx[lp] != fa_d[lp]) $display("  %9.3f ms  far LTU ch %0d: M seen by W neighbour -> %b", tms(0), lp, f_a_tx[lp]);
        end
        rsb_d <= rsb; fst_d <= fst; hst_d <= hst; nst_d <= nst; nnf_d <= nnf; ngl_d <= ngl;
        mon_d <= mon; lup_d <= lup[1]; busy_d <= busy; aout_d <= a_out; fa_d <= f_a_tx; lat_d <= lat;
    end

    // ---- a listener on cable B: event words ---------------------------------------
    reg [15:0] shb = 16'd0; reg scl_d = 1'b0, wr_d = 1'b0;
    integer ev_glare = 0, ev_notrunk = 0, ev_other = 0;
    always @(posedge clk) begin
        scl_d <= scl; wr_d <= wrb;
        if (scl && !scl_d) shb <= {shb[14:0], sd};
        if (wrb && !wr_d && !shb[15]) begin
            if      (shb[7:2] == 6'o04) ev_glare   = ev_glare + 1;
            else if (shb[7:2] == 6'o10) ev_notrunk = ev_notrunk + 1;
            else                        ev_other   = ev_other + 1;
        end
    end
    integer nclash = 0;
    always @(posedge clk) if (clash) nclash = nclash + 1;

    // ---- the bench's hands ------------------------------------------------------------
    task ms(input integer n); begin repeat (n) @(posedge t1k); end endtask

    // a digit on a line: p < 64 a phone or a baseband stub, 64+k the far LTU channel k
    task automatic setm(input integer p, input v);
        begin
            if (p >= 64) far_m[p-64] = v; else if (TR[p]) sm[p] = v; else hook[p] = v;
        end
    endtask
    task automatic pdial(input integer p, input integer d);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                setm(p, 1'b0); repeat (60) @(posedge t1k);
                setm(p, 1'b1); repeat (40) @(posedge t1k);
            end
        end
    endtask

    // what does the far end of trunk p hear from B (its C out), over eight frames
    reg s0, s1; integer j;
    task hear_out(input integer p);
        begin s0 = 1'b0; s1 = 1'b0;
            for (j = 0; j < 8; j = j + 1) begin
                @(posedge fs); @(posedge clk);
                if (p >= 64) begin if (f_c_tx[p-64]) s1 = 1'b1; else s0 = 1'b1; end
                else         begin if (c_out[p])     s1 = 1'b1; else s0 = 1'b1; end
            end
        end
    endtask
    task hear_rx(input integer p);
        begin s0 = 1'b0; s1 = 1'b0;
            for (j = 0; j < 8; j = j + 1) begin
                @(posedge fs); @(posedge clk);
                if (rx[p]) s1 = 1'b1; else s0 = 1'b1;
            end
        end
    endtask

    task dump_lat(input integer p);
        $display("  %9.3f ms  latch %o: src %o bsy %b clm %b   BUSY %b  a_out %b", tms(0), p[5:0],
                 la(p), lb(p), lat[p*8], busy[p], TR[p] ? a_out[p] : 1'b0);
    endtask

    task idle(input [8*120-1:0] what);
        begin
            ms(900);
            ck((busy & WATCH) == 64'd0 && rsb == 2'd0 && mon == 2'd0 && !regb && dirs == 4'd0 &&
               fst == 2'd0 && hst == 3'd0 && cst == 3'd0, what);
            if (!((busy & WATCH) == 64'd0 && rsb == 2'd0))
                $display("    left: busy %h  rs_busy %b  mon %b  reg %b  dirs %b  fst %0d cst %0d",
                         busy & WATCH, rsb, mon, regb, dirs, fst, cst);
        end
    endtask

    // ---- the measurements ---------------------------------------------------------------
    // Rise time of every trunk's far M (a_out), and of every far LTU channel's M.
    realtime t_rise [0:71];
    integer q2;
    always @(posedge clk) begin
        for (q2 = 0; q2 < 64; q2 = q2 + 1) if (TR[q2] && a_out[q2] && !aout_d[q2]) t_rise[q2] = $realtime;
        for (q2 = 0; q2 < 8; q2 = q2 + 1) if (f_a_tx[q2] && !fa_d[q2]) t_rise[64 + q2] = $realtime;
    end
    // the far appearance of a port: a baseband port is itself, an LTU port 1k is 64+k
    function integer far_of(input [5:0] p);
        far_of = (p[5:3] == 3'd1) ? (64 + p[2:0]) : p;
    endfunction

    // The hop: from the far M rising INTO port `pin` to the far M rising OUT of
    // each leg the resolver holding `pin` wrote.  Waits for the forward.
    realtime t_in, hopmax, hopmin;
    integer  nleg, rv2, jv, waited;
    reg      found;
    reg [5:0] lg;
    task hop(input [5:0] pin, input [8*40-1:0] what);
        begin
            found = 1'b0; waited = 0;
            while (!found && waited < 80) begin
                @(posedge t1k); waited = waited + 1;
                for (rv2 = 0; rv2 < 2; rv2 = rv2 + 1)
                    if (rsb[rv2] && rs_in[rv2*6 +: 6] == pin) found = 1'b1;
            end
            if (!found) $display("  HOP %0s: port %o was NOT forwarded (n_nofwd %0d)", what, pin, nnf);
            else begin
                ms(5);
                nleg = 0; hopmax = 0; hopmin = 1.0e12;
                for (rv2 = 0; rv2 < 2; rv2 = rv2 + 1)
                    if (rsb[rv2] && rs_in[rv2*6 +: 6] == pin)
                        for (jv = 0; jv < 4; jv = jv + 1) if (rs_held[rv2*4 + jv]) begin
                            lg = rs_leg[(rv2*4 + jv)*6 +: 6];
                            nleg = nleg + 1;
                            if (t_rise[far_of(lg)] - t_in > hopmax) hopmax = t_rise[far_of(lg)] - t_in;
                            if (t_rise[far_of(lg)] - t_in < hopmin) hopmin = t_rise[far_of(lg)] - t_in;
                            $display("  HOP %0s: in %o -> leg %o : %.3f ms", what, pin, lg,
                                     (t_rise[far_of(lg)] - t_in) / 1.0e6);
                        end
                $display("  HOP %0s: %0d legs, first %.3f ms, last %.3f ms", what, nleg,
                         hopmin / 1.0e6, hopmax / 1.0e6);
            end
        end
    endtask


    // ---- VERIFY C13: B's probe samples of S40 (port 40 octal) -- "armed" means
    // a sample with BUSY 1 and M 0 while a resolver holds 40 as a leg, BEFORE
    // the first sample with M 1 (the fwd auditor's proposed arming condition)
    wire        v_fresh = B.u_x.u_net.sp_fresh;
    wire [5:0]  v_port  = B.u_x.u_net.sp_port;
    wire        v_m     = B.u_x.u_net.sp_m, v_b = B.u_x.u_net.sp_busy;
    reg v_armed = 1'b0, v_msn = 1'b0, v_track = 1'b0;
    always @(posedge clk) if (v_track && v_fresh && v_port == 6'o40) begin
        if (v_b && !v_m && !v_msn && !v_armed) begin
            v_armed <= 1'b1;
            $display("  %9.3f ms  VERIFY: B's probe sees S40 BUSY 1, M 0 -- an arming sample", tms(0));
        end
        if (v_m && !v_msn) begin
            v_msn <= 1'b1;
            $display("  %9.3f ms  VERIFY: B's probe first sees M 1 on S40 (BUSY %b); armed before it: %b",
                     tms(0), v_b, v_armed);
        end
    end
    realtime t40w;
    always @(posedge clk) if (v_track && busy[6'o40] && !busy_d[6'o40]) t40w = $realtime;

    // ---- the scenarios ------------------------------------------------------------------
    integer sc_n, var_n, dly, load, k, ph, nf0, ng0, eg0, t_hold;
    realtime t_cls;

    initial begin
        if (!$value$plusargs("sc=%d", sc_n))    sc_n  = 5;
        if (!$value$plusargs("var=%d", var_n))  var_n = 0;
        if (!$value$plusargs("dly=%d", dly))    dly   = 112;
        if (!$value$plusargs("load=%d", load))  load  = 0;
        for (k = 0; k < 72; k = k + 1) t_rise[k] = 0;
        $display("\n  tb_fx -- one exchange, its links driven by the bench.  sc=%0d var=%0d dly=%0d load=%0d",
                 sc_n, var_n, dly, load);
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        ms(30);
        ck(lup[1] && f_up && (link_up & TR) == TR, "every link is up");

        // =====================================================================
        if (sc_n == 2) begin
            $display("  sc2: a forward whose incoming link goes down; the resolver outlives it");
            sup[6'o74 +: 4] = 4'd0;                    // N down: two legs, E and S
            ms(20);
            far_m[0] = 1'b1;                           // the W neighbour seizes channel 0: B10
            ms(40);
            ck(rsb == 2'b01 && busy[6'o30] && busy[6'o40] && la(6'o30) == 6'o10 && la(6'o40) == 6'o10,
               "B10 held and forwarded into E30 and S40; one resolver holds the forward");
            ck(a_out[6'o30] && a_out[6'o40], "both legs carry the W caller's M onward");
            // the cable is cut; the W neighbour's call is gone with it
            lnk = 1'b0; far_m[0] = 1'b0;
            ms(10);
            ck(busy[15:8] == 8'hFF, "MUTE_BLK: all eight LTU ports read BUSY");
            ms(400);
            ck(!busy[6'o30] && !busy[6'o40], "the legs released themselves: their E fell");
            ck(rsb == 2'b00, "the resolver let go of a forward whose incoming is dead");
            dump_lat(6'o10); dump_lat(6'o30); dump_lat(6'o40);
            if (var_n == 0) begin
                $display("  sc2 var0: B20 floods on the old legs; the cable is mended mid-dial");
                hook[6'o20] = 1'b1; ms(300);
                pdial(6'o20, 1);                       // the key
                ms(250);
                ck(d_held == 4'b0110 && busy[6'o30] && busy[6'o40] && la(6'o30) == 6'o20 && la(6'o40) == 6'o20,
                   "B20's key seized E30 and S40 -- the dead forward's old legs");
                ms(500);
                pdial(6'o20, 4);                       // e = 4 (nobody claims)
                lnk = 1'b1;                            // mended
                ms(40);
                dump_lat(6'o10); dump_lat(6'o30); dump_lat(6'o40);
                ck(busy[6'o30] && busy[6'o40] && la(6'o30) == 6'o20 && la(6'o40) == 6'o20,
                   "after the mend B20's two trunks still listen to B20");
                ck(a_out[6'o30] && a_out[6'o40], "and the E and S neighbours still see B20's M");
                ck(rsb == 2'b00, "and no resolver is left over");
                // B20 finishes 1 4 4 2 1; the E neighbour claims after b
                ms(600); pdial(6'o20, 4); ms(150);
                sm[6'o30] = 1'b1;                       // E claims
                ms(500); pdial(6'o20, 2); ms(600); pdial(6'o20, 1); ms(300);
                dump_lat(6'o20); dump_lat(6'o30); dump_lat(6'o40);
                sc[6'o30] = 1'b1; ms(3); hear_rx(6'o20); ck(s1 && !s0, "B20 hears the E party (1)");
                sc[6'o30] = 1'b0; ms(3); hear_rx(6'o20); ck(s0 && !s1, "B20 hears the E party (0)");
                tx[6'o20] = 1'b1; ms(3); hear_out(6'o30); ck(s1 && !s0, "the E party hears B20 (1)");
                tx[6'o20] = 1'b0; ms(3); hear_out(6'o30); ck(s0 && !s1, "the E party hears B20 (0)");
                ck(mon == 2'b00 && rsb == 2'b00, "no monitor or resolver took the E party's claim as a seizure");
                hook[6'o20] = 1'b0; sm[6'o30] = 1'b0;
            end else begin
                $display("  sc2 var1: the E neighbour seizes E30 (an old leg) to call B21; later the cable is mended");
                sm[6'o30] = 1'b1;
                ms(30);
                dump_lat(6'o10); dump_lat(6'o30); dump_lat(6'o40);
                ck(busy[6'o30] && la(6'o30) == 6'o00, "B holds E30 as an incoming seizure");
                ms(600); pdial(6'o30, 2); ms(700); pdial(6'o30, 3); ms(300);
                ck(lat[6'o30*8] == 1'b1 && a_out[6'o30], "B claimed the E call");
                ms(300); pdial(6'o30, 2); ms(700); pdial(6'o30, 1); ms(400);
                ck(la(6'o21) == 6'o30 && la(6'o30) == 6'o21, "B connected E30 and B21");
                hook[6'o21] = 1'b1; ms(300);
                lnk = 1'b1;                            // mended
                ms(100);
                dump_lat(6'o10);
                ck(!busy[6'o10] && !f_a_tx[0], "after the mend channel 0 is free, and the W neighbour sees no M on it");
                sc[6'o30] = 1'b1; ms(3); hear_out(64); t_hold = s1 && !s0;
                sc[6'o30] = 1'b0; ms(3); hear_out(64);
                ck(!(t_hold && s0 && !s1), "the E caller's voice does not reach the W neighbour on channel 0");
                ms(1000);
                ck(!busy[6'o10] && !f_a_tx[0], "a second later: still no M on channel 0 at the W neighbour");
                sm[6'o30] = 1'b0; hook[6'o21] = 1'b0;   // the call ends
                ms(900);
                ck(!busy[6'o10] && !f_a_tx[0], "after the call ends channel 0 is free");
            end
            sup = TR; lnk = 1'b1;
            idle("sc2: all idle again");
        end

        // =====================================================================
        if (sc_n == 3) begin
            $display("  sc3: glare on a forward's leg");
            v_track = 1'b1;
            ng0 = ngl; eg0 = ev_glare;
            sm[6'o30] = 1'b1;                          // a flood arrives on E30
            // the S neighbour seizes S40 for its own call just after B's forward
            // has confirmed it and before the leg's word is out
            wait (hst == 3'd2 && h_owner && h_n == 7'd40);
            sm[6'o40] = 1'b1;
            $display("  %9.3f ms  the S neighbour seizes S40 (its own call)", tms(0));
            ms(30);
            dump_lat(6'o30); dump_lat(6'o40); dump_lat(6'o10); dump_lat(6'o74);
            ck(la(6'o30) != 6'o40, "the E flood's incoming is not re-pointed at S40");
            sc[6'o40] = 1'b1; ms(3); hear_out(6'o30); t_hold = s1 && !s0;
            sc[6'o40] = 1'b0; ms(3); hear_out(6'o30);
            ck(!(t_hold && s0 && !s1), "the E caller does not hear the S caller");
            // pulse the S caller's hook: does the E origin see it as backward A?
            sm[6'o40] = 1'b0; ms(20); t_hold = a_out[6'o30]; sm[6'o40] = 1'b1; ms(20);
            ck(!(!t_hold && a_out[6'o30]), "the E origin's backward A does not follow the S caller's hook");
            ck(ngl != ng0 || ev_glare != eg0, "the glare is counted (n_glare or EV_GLARE)");
            $display("  n_glare %0d -> %0d, EV_GLARE %0d -> %0d, armed-before-M %b", ng0, ngl, eg0, ev_glare, v_armed);
            sm[6'o30] = 1'b0; sm[6'o40] = 1'b0;
            idle("sc3: all idle again");
        end


        // =====================================================================
        // VERIFY C13 sc7: as sc3, but the S neighbour's M reaches B's S40 a little
        // LATER -- dly7 us after B's leg write has made S40 BUSY (the far end's
        // confirm-to-M delay is up to ~2.7 ms, so this is still glare: the far
        // confirm visit can precede B's M reaching it).
        if (sc_n == 7) begin
            $display("  sc7: glare on a forward's leg, the far M %0d us after B's leg write", dly);
            v_track = 1'b1;
            ng0 = ngl; eg0 = ev_glare;
            sm[6'o30] = 1'b1;                          // a flood arrives on E30
            wait (busy[6'o40] === 1'b1);
            #(dly * 1000);
            sm[6'o40] = 1'b1;
            $display("  %9.3f ms  the S neighbour's M reaches S40 (%0.3f ms after S40 went BUSY)", tms(0),
                     ($realtime - t40w) / 1.0e6);
            ms(30);
            dump_lat(6'o30); dump_lat(6'o40); dump_lat(6'o10); dump_lat(6'o74);
            ck(la(6'o30) != 6'o40, "the E flood's incoming is not re-pointed at S40");
            ck(ngl != ng0 || ev_glare != eg0, "the glare is counted (n_glare or EV_GLARE)");
            $display("  n_glare %0d -> %0d, EV_GLARE %0d -> %0d, armed-before-M %b", ng0, ngl, eg0, ev_glare, v_armed);
            sm[6'o30] = 1'b0; sm[6'o40] = 1'b0;
            idle("sc7: all idle again");
        end
        // =====================================================================
        if (sc_n == 4) begin
            $display("  sc4: four floods at once through a two-resolver transit");
            nf0 = nnf;
            sm[6'o30] = 1'b1; ms(40);                 // E30: legs W10 S40 N74
            sm[6'o41] = 1'b1; ms(40);                 // S41: legs W11 E31 N75
            far_m[2] = 1'b1;  ms(40);                 // W12: no resolver
            sm[6'o77] = 1'b1; ms(40);                 // N77: no resolver
            dump_lat(6'o30); dump_lat(6'o41); dump_lat(6'o12); dump_lat(6'o77);
            ck(rsb == 2'b11, "two resolvers hold two forwards");
            ck(nnf - nf0 == 2, "the third and fourth floods were held and not passed on (n_nofwd +2)");
            ck(busy[6'o12] && busy[6'o77], "both are held here (BUSY) though nobody passes them on");
            $display("  mon_held %b: the first two floods have the two monitors", mon);
            // the E flood's S leg claims: resolver 0 frees; a fifth flood
            sm[6'o40] = 1'b1; ms(40);
            ck(la(6'o30) == 6'o40 && rsb != 2'b11, "S40 claimed the E flood: E30 now listens to it, a resolver is free");
            sm[6'o76] = 1'b1; ms(40);
            dump_lat(6'o76);
            ck(rsb == 2'b11, "a fifth flood, N76, took the freed resolver");
            // everybody hangs up
            sm = 64'd0; far_m = 8'd0;
            idle("sc4: all released, nothing held");
            ck(nclash == 0 && !uno && !mko, "no clash, no queue overflow");
        end

        // =====================================================================
        if (sc_n == 5) begin
            $display("  sc5: hop latency at real timers");
            for (ph = 0; ph < 4; ph = ph + 1) begin
                @(posedge t1k); #(ph * 250_000 + 7_000);
                sm[6'o30] = 1'b1; t_in = $realtime;
                hop(6'o30, "5a nominal");
                sm[6'o30] = 1'b0;
                ms(700);
            end
            // behind the T_ARM watch of a flood that arrived 1 ms earlier
            for (ph = 0; ph < 2; ph = ph + 1) begin
                @(posedge t1k); #(ph * 500_000 + 7_000);
                sm[6'o41] = 1'b1; ms(1);
                sm[6'o30] = 1'b1; t_in = $realtime;
                hop(6'o30, "5b behind a T_ARM watch");
                sm[6'o30] = 1'b0; sm[6'o41] = 1'b0;
                ms(700);
            end
            // behind an origin sweep: B20 keys 1; the flood arrives as the sweep starts
            for (ph = 0; ph < 2; ph = ph + 1) begin
                hook[6'o20] = 1'b1; ms(300);
                pdial(6'o20, 1);
                wait (hst == 3'd1 && !h_owner);
                #(ph * 3_000_000);
                sm[6'o30] = 1'b1; t_in = $realtime;
                hop(6'o30, "5c behind an origin sweep");
                hook[6'o20] = 1'b0; sm[6'o30] = 1'b0;
                ms(900);
            end
            // both: an origin sweep, then two floods 1 ms apart
            nf0 = nnf;
            hook[6'o20] = 1'b1; ms(300);
            pdial(6'o20, 1);
            wait (hst == 3'd1 && !h_owner);
            sm[6'o41] = 1'b1; t_in = $realtime;
            fork
                begin ms(1); sm[6'o30] = 1'b1; end
                hop(6'o41, "5d first flood, behind an origin sweep");
            join
            ms(60);
            $display("  5d: second flood (1 ms after the first) forwarded? rs_in %o %o  n_nofwd +%0d",
                     rs_in[5:0], rs_in[11:6], nnf - nf0);
            ck(nnf == nf0, "5d: a second flood 1 ms behind the first, behind an origin sweep, is still forwarded");
            hook[6'o20] = 1'b0; sm[6'o30] = 1'b0; sm[6'o41] = 1'b0;
            idle("sc5: all idle again");
        end

        // =====================================================================
        if (sc_n == 6) begin
            $display("  sc6: a flood that reached B %0d ms after its origin seized; first break at 129 ms; load %0d",
                     dly, load);
            if (load) begin sm[6'o41] = 1'b1; ms(1); end   // another flood, a millisecond earlier
            sm[6'o30] = 1'b1; t_in = $realtime;
            fork
                begin wait (busy[6'o30]); t_cls = $realtime;
                      $display("  %9.3f ms  B holds E30, %.3f ms after its M rose", tms(0), (t_cls - t_in) / 1.0e6); end
                begin #((129 - dly) * 1_000_000);
                      pdial(6'o30, 3); end                // e = 3: the caller dialled 1 3 3 2 1
            join
            ms(700); pdial(6'o30, 3); ms(400);           // b = 3
            ck(!(lat[6'o30*8] == 1'b1), "B did not claim a call dialled to exchange 3 3");
            ms(300); pdial(6'o30, 2); ms(700); pdial(6'o30, 1); ms(400);
            ck(!busy[6'o21], "and B21 was not rung");
            dump_lat(6'o30); dump_lat(6'o21);
            sm[6'o30] = 1'b0; sm[6'o41] = 1'b0;
            idle("sc6: all idle again");
        end

        ck(nclash == 0, "cable B never had two masters at once");
        ck(!uno && !mko, "no queue refused a write");
        $display("\n  %0d checks, %0d errors.  %s\n", chk, errs, (errs == 0) ? "PASS" : "FAIL");
        $finish;
    end

    initial begin #30_000_000_000; $display("  WATCHDOG at 30 s simulated"); $finish; end

    wire _unused = &{1'b0, rcad, clm, e, f_c_tx, f_mute, lc_o, la_o, lh_o, lk_o, mks, res, 1'b0};
endmodule
