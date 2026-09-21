// tb_traffic -- a NETWORK of exchanges under traffic that is not smooth, and
// the same network at peak and off peak.
//
// `make stress` asks whether a full exchange jams.  This one asks a different
// question, of a whole network: WHEN DOES IT BLOCK, and does the shape of the
// demand change the answer.  Nothing here is a scenario; the only inputs are a
// topology, an arrival process and a holding-time law, and what comes out is
// erlangs and loss, link by link and pool by pool, in the gates.
//
// THE SHAPE.  A chain of NHUB hubs, each carrying SPOKE spokes, each spoke a
// chain of SLEN exchanges: the tandem-chain backbone of topology.md 5 with
// long spokes on it.  One set of parameters covers every shape the protocol
// allows --
//
//     NHUB=n SPOKE=0            a chain of n
//     NHUB=1 SPOKE=4 SLEN=1     a star: a hub and four spokes
//     NHUB=2 SPOKE=3 SLEN=1     the reference of network.md 5.1
//     NHUB=3 SPOKE=2 SLEN=2     a backbone of three tandems, spokes two deep
//
// -- and the wiring is arithmetic, so the same testbench is 2 exchanges or 14.
//
// THE ARRIVALS.  A line that has hung up waits an IDLE and lifts again.  What
// distribution that wait is drawn from is the whole of the traffic model:
//
//     MODEL 0  smooth   exponential about the mean: Poisson arrivals, the
//                       textbook case and the one Erlang B assumes
//     MODEL 1  bursty   the same mean in BURSTS.  The network alternates hot
//                       and cold; hot it is BURST_X times the rate, and the
//                       cold rate is set so the mean over the cycle is the
//                       same.  An office at a shift change (network.md 5.1)
//     MODEL 2  herd     smooth, with a FLASH CROWD on top: now and then a third
//                       of every line in the network lifts inside a few
//                       hundred milliseconds and they all dial the SAME
//                       exchange.  A radio station's number read out on air.
//                       This is the one that falls on a link rather than on
//                       the registers, because it is not just when the calls
//                       come but WHERE THEY GO
//
// THE HOLDING TIME is HOLD_MODEL: 0 exponential, 1 constant, 2 a two-class mix
// of nine short calls to one ten times as long -- the same mean, four times the
// variance.  Erlang B is insensitive to it in theory; the point of 2 is that
// nothing in this exchange has read Erlang.
//
// PEAK AGAINST OFF PEAK.  The run is PHASES phases of SECS each, the first at
// IDLE_OP between calls and the rest at IDLE_PK.  Every figure is reported a
// phase, so the same network is read twice and the traffic model is the only
// thing that moved.
//
// EVERY KNOB ABOVE THE TOPOLOGY IS A PLUSARG.  Eight exchanges take a quarter of
// an hour to compile and two minutes to run, so what the callers do is decided
// when the binary starts and not when it is built: +model=1 +secs=40 +pk=700
// and the rest, defaulting to the parameters.  The shape is still elaboration,
// because the shape is wires.
//
// THE TIME BASE is `make stress`'s: the dial and the register's three windows
// run at eight times life (HIT/ID/CLR = 1/16/32 ms against 8/128/256), which
// makes a call about a second and a half instead of twelve, while the marker's
// 8 ms scan and every hop it costs stay exactly as they are.  `exch.py
// traffic` runs the same network on the same scaling, and the two are read
// against each other there.
`timescale 1ns/1ps

module tb_traffic #(
    // ---- the shape ----------------------------------------------------
    // The default is what `make traffic` runs as a regression -- a hub and two spokes, four
    // seconds a phase -- and not the network `make traffic-net` measures.  Eight exchanges
    // take a quarter of an hour to compile and an hour and a half to run.
    parameter integer NHUB   = 1,         // hubs in the backbone chain
    parameter integer SPOKE  = 2,         // spokes a hub
    parameter integer SLEN   = 1,         // exchanges in a spoke
    parameter integer NLINE  = 12,        // lines an exchange, of the 32 slots left
    // ---- the traffic ---------------------------------------------------
    parameter integer MODEL  = 0,         // 0 smooth, 1 bursty, 2 herd
    parameter integer HOLDM  = 0,         // 0 exponential, 1 constant, 2 two-class
    parameter integer SECS   = 4,         // model seconds in a phase
    // Twice the longer idle, or the phase is all transient: it begins with every
    // line on hook, and a line that has not lifted yet is a line whose first lift
    // is still to come whatever the rate is meant to be.
    parameter integer WARM   = 6000,      // ms of traffic before anything is counted
    parameter integer PHASES = 2,
    parameter integer IDLE_OP = 3000,     // ms between calls, off peak
    parameter integer IDLE_PK = 1500,     // ... and at peak
    parameter integer HOLD    = 500,      // mean conversation, ms
    parameter integer LEAVE   = 30,       // % of calls that leave the exchange
    parameter integer BURST_X = 8,        // hot is this many times the rate
    parameter integer BURST_UP = 1000,    // ms hot
    parameter integer BURST_DN = 5000,    // ms cold
    parameter integer HERD_EVERY = 6000,  // ms between flash crowds
    parameter integer HERD_PC = 33,       // % of every line in the network
    parameter integer HERD_MS = 300,      // spread over this long
    // ---- the exchange ---------------------------------------------------
    parameter integer NREG  = 3,          // registers a pool (marker.md 6)
    parameter integer NMON  = 3,          // monitor cells a trunk block
    parameter integer NRES  = 3,          // resolvers a hub
    parameter integer DT_WAIT = 1200,     // how long a caller waits for dial tone
    parameter integer QUIET  = 1000,      // ms of quiet after a phase, for the jam check
    parameter integer SEED  = 32'h2468_ACE0,
    // One crystal for the whole network, or one an exchange.  Staggered clocks
    // cost the simulator an evaluation point for every exchange and buy nothing
    // here: the plesiochronous case is `make trunk-ppm` and `make stress-pair`,
    // and a shared clock is the copper tie of network.md 1 in any case.
    parameter integer STAGGER = 0,
    parameter         TRACE = 1'b0
) ();
    // ---- what is decided at run time --------------------------------------
    // The topology is elaboration: it is wires.  The demand is not, and a network of eight
    // exchanges costs a quarter of an hour to compile, so every knob that says what the
    // callers DO is a plusarg over the parameter's default.  One binary runs every model.
    integer r_model, r_holdm, r_secs, r_phases, r_op, r_pk, r_hold, r_leave, r_seed, r_warm;
    integer r_bx, r_bup, r_bdn, r_hevery, r_hpc, r_hms, r_quiet;

    localparam integer NEX = NHUB + NHUB * SPOKE * SLEN;
    localparam integer NS  = 1_000_000;                  // ns in a model ms
    localparam integer HIT = 1, ID = 16, CLR = 32;       // eight times life
    localparam integer T_RISE = 64, T_FALL = 2048;
    localparam integer RING_ON = 200, RING_OFF = 400;

    // ---- the topology, as arithmetic --------------------------------------
    // Hub h is exchange h.  Spoke exchange (h, s, p) is NHUB + (h*SPOKE+s)*SLEN
    // + p, p = 0 next the hub.  A hub's direction slots are its backbone
    // neighbours first -- slot 0 the previous hub, then the next -- and its
    // spokes after; a spoke exchange's slot 0 faces the hub and slot 1 faces
    // away.  Every exchange uses slots 0 .. NDIR-1, which is what net_site
    // wants.
    function integer nb_of(input integer h);            // backbone directions of a hub
        nb_of = ((h > 0) ? 1 : 0) + ((h < NHUB - 1) ? 1 : 0);
    endfunction
    function integer nxt_slot(input integer h);         // the slot facing hub h+1
        nxt_slot = (h > 0) ? 1 : 0;
    endfunction
    function integer sp_idx(input integer h, input integer s, input integer p);
        sp_idx = NHUB + (h * SPOKE + s) * SLEN + p;
    endfunction
    function integer ndir_of(input integer i);
        integer h, p;
        begin
            if (i < NHUB) ndir_of = nb_of(i) + SPOKE;
            else begin
                p = (i - NHUB) % SLEN;
                ndir_of = (p == SLEN - 1) ? 1 : 2;
            end
        end
    endfunction
    // the exchange at the far end of exchange i's direction d, and the slot
    // that faces back
    function integer peer_of(input integer i, input integer d);
        integer h, s, p, c;
        begin
            if (i < NHUB) begin
                if (d < nb_of(i)) peer_of = (d == 0 && i > 0) ? i - 1 : i + 1;
                else              peer_of = sp_idx(i, d - nb_of(i), 0);
            end else begin
                c = (i - NHUB) / SLEN; p = (i - NHUB) % SLEN;
                h = c / SPOKE; s = c % SPOKE;
                if (d == 0) peer_of = (p == 0) ? h : sp_idx(h, s, p - 1);
                else        peer_of = sp_idx(h, s, p + 1);
            end
        end
    endfunction
    function integer pdir_of(input integer i, input integer d);
        integer h, s, p, c, j;
        begin
            if (i < NHUB) begin
                if (d < nb_of(i))
                    // toward the previous hub, its "next" slot; toward the next, its slot 0
                    pdir_of = (d == 0 && i > 0) ? nxt_slot(i - 1) : 0;
                else
                    pdir_of = 0;                      // a spoke's slot 0 faces the hub
            end else begin
                c = (i - NHUB) / SLEN; p = (i - NHUB) % SLEN;
                h = c / SPOKE; s = c % SPOKE;
                if (d == 0) pdir_of = (p == 0) ? nb_of(h) + s : 1;
                else        pdir_of = 0;
            end
        end
    endfunction
    // Which block a direction's trunk group sits on: 0, 1, 3, 4 (net_site).
    function integer blk_of(input integer d);
        blk_of = (d == 0) ? 0 : (d == 1) ? 1 : (d == 2) ? 3 : 4;
    endfunction

    // A code an exchange: e from 2, b from 1.  b = 0 is ten pulses, which
    // would make one exchange's floods three times another's for no reason
    // (network.md 2, "give the codes of fewest pulses to the busiest").
    function integer code_e(input integer i); code_e = 2 + i / 7; endfunction
    function integer code_b(input integer i); code_b = 1 + i % 7; endfunction

    // The lines sit in blocks 2, 5, 6 and 7, whatever an exchange's degree, so
    // that a hub of four directions has as many lines as a leaf of one and the
    // only thing that differs between them is the trunking.
    function integer line_port(input integer j);
        line_port = (j < 8) ? (16 + j) : (32 + j);
    endfunction
    function [63:0] line_mask;
        integer j;
        begin
            line_mask = 64'd0;
            for (j = 0; j < NLINE; j = j + 1) line_mask[line_port(j)] = 1'b1;
        end
    endfunction
    localparam [63:0] LP = line_mask();

    // ---- the clocks -------------------------------------------------------
    // One period, staggered starts: two ends of a link must not change and
    // sample at the same instant.  The plesiochronous case is `make trunk-ppm`
    // and `make stress-pair`; nothing here turns on it.
    reg rst_n = 0;
    reg [15:0] clkr;
    genvar gc;
    generate for (gc = 0; gc < NEX; gc = gc + 1) begin : clks
        if (gc == 0 || STAGGER != 0) begin : own
            initial begin
                clkr[gc] = 1'b0;
                #(13 * gc + 1);
                forever #122.0703 clkr[gc] = ~clkr[gc];
            end
        end
    end endgenerate
    wire [15:0] xclk;
    generate for (gc = 0; gc < 16; gc = gc + 1)
        assign xclk[gc] = (STAGGER != 0) ? clkr[gc] : clkr[0];
    endgenerate
    wire clk0 = clkr[0];                      // the bench's own millisecond

    // ---- the exchanges ----------------------------------------------------
    reg  [63:0] hk  [0:15];
    wire [63:0] ee  [0:15];
    wire [63:0] pb  [0:15];
    wire [15:0] lout, lin;
    wire [15:0] fs;
    wire [3:0]  mfull [0:15];
    wire [3:0]  mbusy [0:15];
    wire [3:0]  rused [0:15];
    wire [79:0] ev    [0:15];
    wire [NREG-1:0] rg [0:15];
    wire [15:0] lkall;
    // the marker's last latch write at each exchange, so a held port can say what
    // put it there -- an operator's lamps would show the same (mainboard.md 2.3)
    wire        ws [0:15];
    wire [5:0]  wd [0:15], wr [0:15];
    wire        wb [0:15], wc [0:15];
    integer     lw_src [0:15][0:63], lw_bsy [0:15][0:63], lw_clm [0:15][0:63];
    real        lw_t   [0:15][0:63];

    genvar i, d;
    generate for (i = 0; i < NEX; i = i + 1) begin : ex
        localparam integer ND = ndir_of(i);
        localparam integer E  = code_e(i);
        localparam integer B  = code_b(i);
        // The glare bit is set at ONE end of every link: the two ends then hunt
        // it in opposite order (network.md 1).  "The higher index sets it"
        // is a rule both ends can be built to without knowing the topology.
        localparam         GG0 = (ND > 0) && (i > peer_of(i, 0));
        localparam         GG1 = (ND > 1) && (i > peer_of(i, 1));
        localparam         GG2 = (ND > 2) && (i > peer_of(i, 2));
        localparam         GG3 = (ND > 3) && (i > peer_of(i, 3));
        wire [ND-1:0] lk;
        assign lkall[i] = &lk;

        net_site #(.OWN_E(E[2:0]), .OWN_B(B[2:0]), .NDIR(ND),
                   .DIR0(2'd0), .G0(GG0), .DIR1(2'd1), .G1(GG1),
                   .DIR2(2'd2), .G2(GG2), .DIR3(2'd3), .G3(GG3),
                   .LINE_PORTS(LP),
                   .T_RISE(T_RISE), .T_FALL(T_FALL),
                   .RING_ON(RING_ON), .RING_OFF(RING_OFF),
                   .HIT(HIT), .ID(ID), .CLR(CLR), .T_GUARD(16), .T_CLAIM(250),
                   .NMON(NMON), .NREG(NREG), .NRES(NRES))
        X (.clk(xclk[i]), .rst_n(rst_n),
           .hook(hk[i]), .tx(64'd0), .rx(), .e(ee[i]),
           .line_in(lin[i*4 +: ND]), .line_out(lout[i*4 +: ND]), .locked(lk),
           .frame_stb(fs[i]), .ring_cad_n(), .dt_bit(), .ng_bit(),
           .mon_held(), .mon_busy(mbusy[i]), .mon_full(mfull[i]),
           .got_claim(), .dirs_held(), .fan_legs(), .res_used(rused[i]),
           .port_busy(pb[i]), .regs_busy(rg[i]), .wq_ovf(), .n_defer(),
           .wr_stb(ws[i]), .wr_dst(wd[i]), .wr_src(wr[i]),
           .wr_bsy(wb[i]), .wr_clm(wc[i]),
           .ev_cnt(ev[i]));
        always @(posedge xclk[i]) if (ws[i]) begin
            lw_src[i][wd[i]] = wr[i]; lw_bsy[i][wd[i]] = wb[i];
            lw_clm[i][wd[i]] = wc[i]; lw_t[i][wd[i]] = $realtime;
        end
    end endgenerate

    // the links: one conductor each way, and nothing in between
    generate for (i = 0; i < NEX; i = i + 1)
        for (d = 0; d < 4; d = d + 1)
            if (d < ndir_of(i))
                assign lin[i*4+d] = lout[peer_of(i, d) * 4 + pdir_of(i, d)];
            else
                assign lin[i*4+d] = 1'b0;
    endgenerate

    // ---- the bench's millisecond ------------------------------------------
    reg [6:0] frc = 0;
    reg       ms_stb = 1'b0;
    always @(posedge clk0) begin
        ms_stb <= 1'b0;
        if (fs[0]) begin
            if (frc == 7'd63) begin frc <= 0; ms_stb <= 1'b1; end
            else frc <= frc + 7'd1;
        end
    end

    // ---- the random stream, the bench's own so both simulators agree -------
    reg [31:0] lcg = 32'h2468_ACE0;
    function integer urnd(input integer n);              // 0 .. n-1
        begin
            lcg = lcg * 32'd1664525 + 32'd1013904223;
            urnd = (lcg >> 16) % n;
        end
    endfunction
    function real ur;                                    // (0, 1]
        begin
            lcg = lcg * 32'd1664525 + 32'd1013904223;
            ur  = (lcg[30:0] + 1.0) / 2147483648.0;
        end
    endfunction
    function integer expo(input integer mean);           // an exponential wait
        real v;
        begin
            v = -1.0 * mean * $ln(ur());
            expo = (v > 100000.0) ? 100000 : ((v < 1.0) ? 1 : $rtoi(v));
        end
    endfunction

    // ---- one caller a line -------------------------------------------------
    // A line is c = i*NLINE + j: exchange i, its j'th line.
    localparam integer NC = 16 * 40;
    localparam integer S_IDLE=0, S_LIFT=1, S_BRK=2, S_MK=3, S_PAUSE=4,
                       S_WAIT=5, S_TALK=6, S_HANG=7, S_RUNG=8;

    integer st [0:NC-1], tmr [0:NC-1], np [0:NC-1], dig [0:NC-1], dq [0:NC-1];
    integer ehi [0:NC-1], t_lift [0:NC-1], t_dt [0:NC-1], net_call [0:NC-1];
    // A LINE IS RUNG BY A CADENCE.  exch_top's ring is RING_ON/RING_OFF frames --
    // a few milliseconds on and twice that off at this bench's scaling -- so `e`
    // read at one instant is low two thirds of the time a line is being rung.
    // Answering on the instantaneous level loses two callers in three, and, worse,
    // sends the line back to S_IDLE with its timer already expired, so it lifts
    // again the same millisecond and the run offers twice the traffic it was
    // asked for.  `rseen` is a few cadence periods of memory instead.
    integer rseen [0:NC-1];
    localparam integer RING_MEM = 40;

    function integer ex_of(input integer c);  ex_of = c / NLINE; endfunction
    function integer ln_of(input integer c);  ln_of = c % NLINE; endfunction
    function integer prt_of(input integer c); prt_of = line_port(c % NLINE); endfunction

    task set_hook(input integer c, input v);
        begin hk[ex_of(c)][prt_of(c)] = v; end
    endtask
    function hook_of(input integer c); hook_of = hk[ex_of(c)][prt_of(c)]; endfunction
    function e_of   (input integer c); e_of    = ee[ex_of(c)][prt_of(c)]; endfunction
    function dt_of  (input integer c); dt_of   = pb[ex_of(c)][prt_of(c)]; endfunction

    // ---- what happened -----------------------------------------------------
    // Everything is kept a phase, so the same network is read twice.
    integer ph = 0;
    integer n_try [0:3], n_net [0:3], n_conn [0:3], n_gave [0:3], n_nodt [0:3],
            n_rung [0:3], n_dtwait [0:3];
    real    dt_sum [0:3], dt_max [0:3], pdd_sum [0:3];
    integer dt_n [0:3], pdd_n [0:3];
    integer dt_hist [0:3][0:7];          // dial tone: <1, 2, 4, 8, 16, 32, 64, >=64 scans

    // per exchange and direction: channel-milliseconds, and the marker's own
    // "every trunk this way is busy" event word (counters.md 9)
    real    ch_ms [0:3][0:15][0:3];
    integer ch_hi [0:3][0:15][0:3];
    real    res_ms [0:3][0:15];
    real    mon_ms [0:3][0:15][0:3];
    integer mon_fullms [0:3][0:15][0:3];
    real    reg_ms [0:3][0:15];
    integer ev0 [0:15][0:4], evp [0:3][0:15][0:4];
    integer ph_ms [0:3];

    // the partner invariant of `make stress`, kept as a bare check: a port that
    // is BUSY with its line on hook and its E dead for 300 ms is holding
    // something nobody asked for
    integer onhk [0:NC-1], elow [0:NC-1], bsyms [0:NC-1], stuck [0:NC-1];
    integer n_held = 0;

    integer errs = 0, chk = 0;
    reg     running = 1'b0;
    integer hot = 0, hot_left = 0;        // MODEL 1
    integer herd_left = 0, herd_n = 0, herd_dst = 0, n_herd = 0;   // MODEL 2
    integer idle_mean;

    task want(input v, input string what);
        begin
            chk = chk + 1;
            if (!v) begin errs = errs + 1; $display("     %-56s FAIL", what); end
            else $display("     %-56s ok", what);
        end
    endtask
    task wantn(input v, input integer got, input string what);
        begin
            chk = chk + 1;
            if (!v) begin errs = errs + 1;
                $display("     %-56s FAIL (%0d)", what, got); end
            else $display("     %-56s ok  (%0d)", what, got);
        end
    endtask

    // ---- planning a call ---------------------------------------------------
    // dq holds the digits four bits each, least significant first.
    integer pl_x, pl_p, pl_j, pl_d;
    task plan(input integer c, input integer force_dst);
        integer own;
        begin
            own = ex_of(c);
            if (force_dst >= 0)      pl_x = force_dst;
            else if (NEX > 1 && urnd(100) < r_leave) begin
                pl_x = urnd(NEX - 1);
                if (pl_x >= own) pl_x = pl_x + 1;
            end else pl_x = own;
            pl_j = urnd(NLINE);
            if (pl_x == own && pl_j == ln_of(c))            // never its own line
                pl_j = (pl_j + 1) % NLINE;
            pl_p = line_port(pl_j);
            if (pl_x == own) begin
                dq[c]  = ((pl_p & 7) << 4) | ((pl_p >> 3) & 7);      // h s
                dig[c] = 2; net_call[c] = 0;
            end else begin                                           // 1 e b h s
                dq[c] = (((pl_p & 7) << 16) | (((pl_p >> 3) & 7) << 12)
                         | (code_b(pl_x) << 8) | (code_e(pl_x) << 4) | 1);
                dig[c] = 5; net_call[c] = 1;
            end
            np[c] = 0;
        end
    endtask

    task next_digit(input integer c);
        begin
            if (dig[c] == 0) begin st[c] = S_WAIT; tmr[c] = 400 + urnd(500); end
            else begin
                pl_d = dq[c] & 4'hF;
                dq[c] = dq[c] >> 4;
                dig[c] = dig[c] - 1;
                np[c] = (pl_d == 0) ? 10 : pl_d;
                st[c] = S_BRK; tmr[c] = 12;
                set_hook(c, 1'b0);
            end
        end
    endtask

    // The wait before this line lifts again.  This is the whole traffic model.
    function integer next_idle;
        real mean;
        begin
            mean = idle_mean;
            if (r_model == 1) begin
                // The same mean in bursts.  A share s = up/(up+down) of the time the rate
                // is x times what it is the rest of the time, so the cold RATE must be the
                // mean over (1-s) + x*s to leave the average where it was -- and an idle is
                // one over a rate, so the cold IDLE is the mean idle times that.
                mean = idle_mean * (1.0 * r_bdn + 1.0 * r_bup * r_bx)
                                 / (1.0 * r_bup + 1.0 * r_bdn);
                if (hot) mean = mean / r_bx;
            end
            next_idle = expo($rtoi(mean));
        end
    endfunction

    function integer a_hold;
        begin
            if (r_holdm == 1)      a_hold = r_hold;
            else if (r_holdm == 2) a_hold = (urnd(10) == 0) ? (r_hold * 55 / 10)
                                                            : (r_hold * 5 / 10);
            else                   a_hold = expo(r_hold);
        end
    endfunction

    // ---- the traffic, every millisecond ------------------------------------
    integer i2, j2, k2, d2, b2, nbz, scans;
    reg     bsy;
    always @(posedge clk0) if (rst_n && ms_stb) begin
        // The quiet gap after a phase is not part of it: it is there to see what is
        // left held, and counting it would deflate every erlang in the run.
        if (running) begin
        ph_ms[ph] = ph_ms[ph] + 1;

        // what is held, this millisecond
        for (i2 = 0; i2 < NEX; i2 = i2 + 1) begin
            for (d2 = 0; d2 < 4; d2 = d2 + 1) if (d2 < ndir_of(i2)) begin
                nbz = 0;
                for (k2 = 0; k2 < 8; k2 = k2 + 1)
                    if (k2 != 0 && k2 != 4 && pb[i2][blk_of(d2) * 8 + k2])
                        nbz = nbz + 1;
                ch_ms[ph][i2][d2] = ch_ms[ph][i2][d2] + nbz;
                if (nbz > ch_hi[ph][i2][d2]) ch_hi[ph][i2][d2] = nbz;
                if (mbusy[i2][d2]) mon_ms[ph][i2][d2] = mon_ms[ph][i2][d2] + 1;
                if (mfull[i2][d2]) mon_fullms[ph][i2][d2] = mon_fullms[ph][i2][d2] + 1;
            end
            res_ms[ph][i2] = res_ms[ph][i2] + $countones(rused[i2]);
            reg_ms[ph][i2] = reg_ms[ph][i2] + $countones(rg[i2]);
        end
        end

        // MODEL 1: the network goes hot and cold together
        if (r_model == 1 && running) begin
            if (hot_left > 0) hot_left = hot_left - 1;
            if (hot_left == 0) begin
                hot = !hot;
                hot_left = expo(hot ? r_bup : r_bdn);
            end
        end
        // MODEL 2: a flash crowd, and every one of them wants the same exchange
        if (r_model == 2 && running) begin
            if (herd_left > 0) herd_left = herd_left - 1;
            if (herd_left == 0) begin
                herd_left = expo(r_hevery);
                herd_n    = NEX * NLINE * r_hpc / 100;
                herd_dst  = urnd(NEX);
                n_herd    = n_herd + 1;
            end
        end

        for (i2 = 0; i2 < NEX * NLINE; i2 = i2 + 1) begin
            if (tmr[i2] > 0) tmr[i2] = tmr[i2] - 1;
            if (hook_of(i2) && e_of(i2)) ehi[i2] = ehi[i2] + 1;
            else if (hook_of(i2))        ehi[i2] = 0;
            if (!hook_of(i2) && e_of(i2))   rseen[i2] = RING_MEM;
            else if (rseen[i2] > 0)         rseen[i2] = rseen[i2] - 1;

            case (st[i2])
            S_IDLE: begin
                if (running && rseen[i2] > 0) begin            // being rung
                    st[i2] = S_RUNG; tmr[i2] = urnd(200);
                    n_rung[ph] = n_rung[ph] + 1;
                end else if (running && herd_n > 0 && urnd(r_hms) == 0) begin
                    herd_n = herd_n - 1;
                    n_try[ph] = n_try[ph] + 1;
                    plan(i2, (herd_dst == ex_of(i2)) ? -1 : herd_dst);
                    if (net_call[i2]) n_net[ph] = n_net[ph] + 1;
                    set_hook(i2, 1'b1);
                    st[i2] = S_LIFT; tmr[i2] = DT_WAIT; ehi[i2] = 0;
                    t_lift[i2] = 0;
                end else if (running && tmr[i2] == 0) begin
                    n_try[ph] = n_try[ph] + 1;
                    plan(i2, -1);
                    if (net_call[i2]) n_net[ph] = n_net[ph] + 1;
                    set_hook(i2, 1'b1);
                    st[i2] = S_LIFT; tmr[i2] = DT_WAIT; ehi[i2] = 0;
                    t_lift[i2] = 0;
                end
            end
            S_LIFT: begin
                t_lift[i2] = t_lift[i2] + 1;
                if (dt_of(i2)) begin
                    // dial tone, as far as a bench can see it: the marker has
                    // written this port with the tone as its source
                    dt_sum[ph] = dt_sum[ph] + t_lift[i2];
                    dt_n[ph]   = dt_n[ph] + 1;
                    if (t_lift[i2] > dt_max[ph]) dt_max[ph] = t_lift[i2];
                    scans = t_lift[i2] / 8;
                    if (scans >= 1) n_dtwait[ph] = n_dtwait[ph] + 1;
                    k2 = 0;
                    while (k2 < 7 && scans > 0) begin scans = scans >> 1; k2 = k2 + 1; end
                    dt_hist[ph][k2] = dt_hist[ph][k2] + 1;
                    st[i2] = S_PAUSE; tmr[i2] = 10 + urnd(30);
                end else if (tmr[i2] == 0) begin
                    n_nodt[ph] = n_nodt[ph] + 1;
                    st[i2] = S_HANG; set_hook(i2, 1'b0); tmr[i2] = 60 + urnd(200);
                end
            end
            S_BRK: if (tmr[i2] == 0) begin
                set_hook(i2, 1'b1); st[i2] = S_MK; tmr[i2] = 8;
            end
            S_MK: if (tmr[i2] == 0) begin
                np[i2] = np[i2] - 1;
                if (np[i2] > 0) begin set_hook(i2, 1'b0); st[i2] = S_BRK; tmr[i2] = 12; end
                else begin
                    if (dig[i2] == 0) t_dt[i2] = 0;            // the last pulse of the number
                    st[i2] = S_PAUSE; tmr[i2] = 60 + urnd(60);
                end
            end
            S_PAUSE: if (tmr[i2] == 0) next_digit(i2);
            S_WAIT: begin
                t_dt[i2] = t_dt[i2] + 1;
                if (ehi[i2] > 16) begin                        // answered
                    n_conn[ph] = n_conn[ph] + 1;
                    pdd_sum[ph] = pdd_sum[ph] + t_dt[i2]; pdd_n[ph] = pdd_n[ph] + 1;
                    st[i2] = S_TALK; tmr[i2] = a_hold();
                end else if (tmr[i2] == 0) begin
                    n_gave[ph] = n_gave[ph] + 1;
                    st[i2] = S_HANG; set_hook(i2, 1'b0); tmr[i2] = 60 + urnd(200);
                end
            end
            S_RUNG: if (tmr[i2] == 0) begin
                if (!running) st[i2] = S_IDLE;
                else if (e_of(i2) || ehi[i2] > 0) begin
                    set_hook(i2, 1'b1);
                    st[i2] = S_TALK; tmr[i2] = a_hold(); ehi[i2] = 0;
                end else st[i2] = S_IDLE;
            end
            S_TALK: if (tmr[i2] == 0 || (hook_of(i2) && ehi[i2] == 0 && tmr[i2] < 300)) begin
                st[i2] = S_HANG; set_hook(i2, 1'b0); tmr[i2] = 60 + urnd(200);
            end
            S_HANG: if (tmr[i2] == 0) begin
                st[i2] = S_IDLE; tmr[i2] = next_idle();
            end
            default: st[i2] = S_IDLE;
            endcase

            // a port held with nothing on it
            if (hook_of(i2)) onhk[i2] = 0; else onhk[i2] = onhk[i2] + 1;
            if (e_of(i2))    elow[i2] = 0; else elow[i2] = elow[i2] + 1;
            bsy = pb[ex_of(i2)][prt_of(i2)];
            if (bsy) bsyms[i2] = bsyms[i2] + 1; else bsyms[i2] = 0;
            if (onhk[i2] > 300 && elow[i2] > 300 && bsyms[i2] > 300) begin
                if (stuck[i2] == 0) n_held = n_held + 1;
                stuck[i2] = stuck[i2] + 1;
            end else stuck[i2] = 0;
        end
    end

    // ---- reading it out ----------------------------------------------------
    function real erlb(input real a, input integer m);
        integer q; real b;
        begin
            b = 1.0;
            for (q = 1; q <= m; q = q + 1) b = a * b / (q + a * b);
            erlb = b;
        end
    endfunction

    task snap_ev(input integer p);
        integer q, z;
        begin
            for (q = 0; q < NEX; q = q + 1) begin
                evp[p][q][0] = ev[q][15:0]   - ev0[q][0];
                evp[p][q][1] = ev[q][31:16]  - ev0[q][1];
                evp[p][q][2] = ev[q][47:32]  - ev0[q][2];
                evp[p][q][3] = ev[q][63:48]  - ev0[q][3];
                evp[p][q][4] = ev[q][79:64]  - ev0[q][4];
                ev0[q][0] = ev[q][15:0];   ev0[q][1] = ev[q][31:16];
                ev0[q][2] = ev[q][47:32];  ev0[q][3] = ev[q][63:48];
                ev0[q][4] = ev[q][79:64];
            end
            z = 0;
        end
    endtask

    // Every phase begins with every line on hook, which is not a state the network is ever in
    // otherwise: the first idle's worth of calls all arrive together and nothing has been
    // answered yet.  WARM runs the traffic through that and then forgets it, so what is
    // measured is the network in its stride -- and `exch.py traffic` does the same, which is
    // what makes the two runs the same experiment.
    integer z1, z2;
    task zero_phase(input integer p);
        begin
            n_try[p]=0; n_net[p]=0; n_conn[p]=0; n_gave[p]=0; n_nodt[p]=0; n_rung[p]=0;
            n_dtwait[p]=0; dt_n[p]=0; pdd_n[p]=0; ph_ms[p]=0;
            dt_sum[p]=0.0; dt_max[p]=0.0; pdd_sum[p]=0.0;
            for (z1 = 0; z1 < 8; z1 = z1 + 1) dt_hist[p][z1] = 0;
            for (z1 = 0; z1 < 16; z1 = z1 + 1) begin
                res_ms[p][z1] = 0.0; reg_ms[p][z1] = 0.0;
                for (z2 = 0; z2 < 4; z2 = z2 + 1) begin
                    ch_ms[p][z1][z2] = 0.0; ch_hi[p][z1][z2] = 0;
                    mon_ms[p][z1][z2] = 0.0; mon_fullms[p][z1][z2] = 0;
                end
            end
        end
    endtask

    // A DELAY IS A 32-BIT EXPRESSION.  `#(secs * 1000 * NS)` is arithmetic on
    // `integer`s and 20 s of model time is 2e10 ns, which wraps: the run silently
    // becomes 2.8 s and every erlang in it is measured over the wrong window.
    // A millisecond at a time is 1e6 and cannot wrap, and 20 000 context switches
    // over a twenty-second run cost nothing beside 4096 clocks a millisecond.
    integer wm;
    task wait_ms(input integer ms);
        begin
            for (wm = 0; wm < ms; wm = wm + 1) #(NS);
        end
    endtask

    integer c3;
    task quiesce(input integer ms);
        begin
            running = 1'b0;
            for (c3 = 0; c3 < NEX * NLINE; c3 = c3 + 1) begin
                set_hook(c3, 1'b0);
                st[c3] = S_IDLE; tmr[c3] = urnd(idle_mean); ehi[c3] = 0;
            end
            wait_ms(ms);
        end
    endtask

    // the exchanges a phase's figures are quoted for: the busiest hub link and
    // the busiest spoke link, found from the run rather than assumed
    integer bh_i, bh_d, bs_i, bs_d;
    real    bh_e, bs_e;
    task pick_links(input integer p);
        integer q, r; real a;
        begin
            bh_i = -1; bs_i = -1; bh_e = -1.0; bs_e = -1.0;
            for (q = 0; q < NEX; q = q + 1)
                for (r = 0; r < 4; r = r + 1) if (r < ndir_of(q)) begin
                    a = ch_ms[p][q][r] / ph_ms[p];
                    if (q < NHUB && peer_of(q, r) < NHUB) begin
                        if (a > bh_e) begin bh_e = a; bh_i = q; bh_d = r; end
                    end else if (a > bs_e) begin bs_e = a; bs_i = q; bs_d = r; end
                end
        end
    endtask

    string MODELS [0:2];
    string HOLDS  [0:2];
    string phn;
    integer p3, q3, r3, tot_ntrk, tot_wait, nblk, nhub;
    real    a3, worst_e; integer worst_i, worst_d;

    initial begin
        r_model = MODEL; r_holdm = HOLDM; r_secs = SECS; r_phases = PHASES; r_warm = WARM;
        r_op = IDLE_OP; r_pk = IDLE_PK; r_hold = HOLD; r_leave = LEAVE; r_seed = SEED;
        r_bx = BURST_X; r_bup = BURST_UP; r_bdn = BURST_DN; r_quiet = QUIET;
        r_hevery = HERD_EVERY; r_hpc = HERD_PC; r_hms = HERD_MS;
        void'($value$plusargs("model=%d",  r_model));
        void'($value$plusargs("holdm=%d",  r_holdm));
        void'($value$plusargs("secs=%d",   r_secs));
        void'($value$plusargs("warm=%d",   r_warm));
        void'($value$plusargs("phases=%d", r_phases));
        void'($value$plusargs("op=%d",     r_op));
        void'($value$plusargs("pk=%d",     r_pk));
        void'($value$plusargs("hold=%d",   r_hold));
        void'($value$plusargs("leave=%d",  r_leave));
        void'($value$plusargs("seed=%d",   r_seed));
        void'($value$plusargs("bx=%d",     r_bx));
        void'($value$plusargs("bup=%d",    r_bup));
        void'($value$plusargs("bdn=%d",    r_bdn));
        void'($value$plusargs("quiet=%d",  r_quiet));
        lcg = r_seed[31:0];

        MODELS[0] = "smooth (Poisson)";
        MODELS[1] = "bursty (hot and cold)";
        MODELS[2] = "herd (a flash crowd)";
        HOLDS[0]  = "exponential";
        HOLDS[1]  = "constant";
        HOLDS[2]  = "two-class";

        for (i2 = 0; i2 < NC; i2 = i2 + 1) begin
            st[i2] = S_IDLE; tmr[i2] = (i2 * 131) % 4000; np[i2] = 0; dig[i2] = 0;
            dq[i2] = 0; ehi[i2] = 0; t_lift[i2] = 0; t_dt[i2] = 0; net_call[i2] = 0;
            onhk[i2] = 0; elow[i2] = 0; bsyms[i2] = 0; stuck[i2] = 0; rseen[i2] = 0;
        end
        for (i2 = 0; i2 < 16; i2 = i2 + 1) begin
            hk[i2] = 64'd0;
            for (j2 = 0; j2 < 5; j2 = j2 + 1) ev0[i2][j2] = 0;
            for (j2 = 0; j2 < 64; j2 = j2 + 1) begin
                lw_src[i2][j2] = 0; lw_bsy[i2][j2] = 0; lw_clm[i2][j2] = 0;
                lw_t[i2][j2] = 0.0;
            end
        end
        for (p3 = 0; p3 < 4; p3 = p3 + 1) begin
            n_try[p3]=0; n_net[p3]=0; n_conn[p3]=0; n_gave[p3]=0; n_nodt[p3]=0;
            n_rung[p3]=0; n_dtwait[p3]=0; dt_n[p3]=0; pdd_n[p3]=0; ph_ms[p3]=0;
            dt_sum[p3]=0.0; dt_max[p3]=0.0; pdd_sum[p3]=0.0;
            for (q3 = 0; q3 < 8; q3 = q3 + 1) dt_hist[p3][q3] = 0;
            for (q3 = 0; q3 < 16; q3 = q3 + 1) begin
                res_ms[p3][q3] = 0.0; reg_ms[p3][q3] = 0.0;
                for (r3 = 0; r3 < 4; r3 = r3 + 1) begin
                    ch_ms[p3][q3][r3] = 0.0; ch_hi[p3][q3][r3] = 0;
                    mon_ms[p3][q3][r3] = 0.0; mon_fullms[p3][q3][r3] = 0;
                end
                for (r3 = 0; r3 < 5; r3 = r3 + 1) evp[p3][q3][r3] = 0;
            end
        end

        $display("TRAFFIC (RTL) -- a network under demand that is not smooth.\n");
        $display("  %0d exchanges: %0d hub%s in a chain, %0d spoke%s each, %0d deep;  %0d lines an exchange, %0d in all.",
                 NEX, NHUB, (NHUB == 1) ? "" : "s", SPOKE, (SPOKE == 1) ? "" : "s",
                 SLEN, NLINE, NEX * NLINE);
        $display("  %0d registers, %0d monitor cells a trunk block, %0d resolvers.  %0d %% of calls leave home.",
                 NREG, NMON, NRES, r_leave);
        $display("  Arrivals: %0s.  Holding time: %0s, mean %0d ms.",
                 MODELS[r_model], HOLDS[r_holdm], r_hold);
        $display("  %0d s a phase after %0d ms of warm-up, %0d ms between a line's calls off peak",
                 r_secs, r_warm, r_op);
        $display("  and %0d ms at peak;  seed %0d.", r_pk, r_seed);
        $display("  The dial and the register's windows run at EIGHT times life (1/16/32 ms");
        $display("  against 8/128/256); the marker's 8 ms scan does not.\n");
        for (i2 = 0; i2 < NEX; i2 = i2 + 1)
            if (TRACE) $display("      %0d: code %0o%0o, %0d directions", i2,
                                code_e(i2), code_b(i2), ndir_of(i2));

        idle_mean = r_op;
        #4000 rst_n = 1;
        wait (&lkall[NEX-1:0]);
        #(30 * NS);
        $display("  0. All %0d exchanges up, every link locked.", NEX);
        snap_ev(0);
        for (q3 = 0; q3 < 16; q3 = q3 + 1)
            for (r3 = 0; r3 < 5; r3 = r3 + 1) evp[0][q3][r3] = 0;

        for (ph = 0; ph < r_phases; ph = ph + 1) begin
            idle_mean = (ph == 0) ? r_op : r_pk;
            hot = 0; hot_left = 1; herd_left = 1; herd_n = 0;
            for (c3 = 0; c3 < NEX * NLINE; c3 = c3 + 1)
                tmr[c3] = 1 + urnd(idle_mean);
            running = 1'b1;
            wait_ms(r_warm);
            zero_phase(ph); snap_ev(ph);            // forget the transient
            wait_ms(r_secs * 1000);
            running = 1'b0;
            snap_ev(ph);
            quiesce(r_quiet);
            $display("     phase %0d (%0s, %0d ms idle): %0d lifted, %0d of them network calls, %0d rang, %0d talked",
                     ph, (ph == 0) ? "off peak" : "peak", idle_mean,
                     n_try[ph], n_net[ph], n_rung[ph], n_conn[ph]);
            chk = chk + 1;
            if (n_conn[ph] < 1) begin
                errs = errs + 1; $display("     JAM: not one call completed in phase %0d", ph);
            end
            nbz = 0;
            for (i2 = 0; i2 < NEX; i2 = i2 + 1) nbz = nbz + $countones(pb[i2]);
            chk = chk + 1;
            if (nbz != 0) begin
                errs = errs + 1;
                $display("     JAM: %0d ports still BUSY with every line on hook", nbz);
                for (i2 = 0; i2 < NEX; i2 = i2 + 1)
                    for (k2 = 0; k2 < 64; k2 = k2 + 1)
                        if (pb[i2][k2])
                            $display("          %0o%0o port %0o (%0s), last written %0.1f ms ago: src %0o bsy %0d clm %0d",
                                     code_e(i2), code_b(i2), k2,
                                     (k2 == 6'o01) ? "dial tone" :
                                     (k2 == 6'o03) ? "cannot-complete" :
                                     LP[k2] ? "a line" : "a trunk channel",
                                     ($realtime - lw_t[i2][k2]) / NS,
                                     lw_src[i2][k2], lw_bsy[i2][k2], lw_clm[i2][k2]);
                $display("          (a write whose source's A was ALREADY low leaves no edge for the");
                $display("           port to release on -- rtl.md's hazard, which `make stress`");
                $display("           checks for at a line and this finds at a trunk)");
            end
        end

        // ---- 1. what the network carried --------------------------------
        $display("\n  1. What each phase offered and what got through.");
        $display("  %-10s %7s %7s %8s %8s %8s %8s %9s", "phase", "lifted", "network",
                 "talked", "no tone", "gave up", "calls/s", "erlangs");
        for (p3 = 0; p3 < r_phases; p3 = p3 + 1) begin
            a3 = 0.0;              // a link is two ports, so count the lower-numbered end only
            for (q3 = 0; q3 < NEX; q3 = q3 + 1)
                for (r3 = 0; r3 < 4; r3 = r3 + 1)
                    if (r3 < ndir_of(q3) && q3 < peer_of(q3, r3))
                        a3 = a3 + ch_ms[p3][q3][r3] / ph_ms[p3];
            // Every integer in a table here is printed as a real: %N.0f pads a
            // column the way a table wants it and %Nd did not.
            $display("  %-10s %7.0f %7.0f %8.0f %8.0f %8.0f %8.1f %9.2f",
                     (p3 == 0) ? "off peak" : "peak", 1.0 * n_try[p3], 1.0 * n_net[p3],
                     1.0 * n_conn[p3], 1.0 * n_nodt[p3], 1.0 * n_gave[p3],
                     1000.0 * n_try[p3] / ph_ms[p3], a3);
        end
        $display("     \"erlangs\" is every LINK in the network taken together, counted once.");

        // ---- 2. the links ------------------------------------------------
        $display("\n  2. Every link, a phase: erlangs on its eight channels, the high-water mark,");
        $display("     and the marker's own \"every trunk this way is busy\" event (counters.md 9).");
        $display("  %-14s %-10s %7s %5s %9s %9s", "link", "phase", "erlang", "high",
                 "Erlang B", "no trunk");
        for (q3 = 0; q3 < NEX; q3 = q3 + 1)
            for (r3 = 0; r3 < 4; r3 = r3 + 1) if (r3 < ndir_of(q3))
                if (q3 < peer_of(q3, r3)) begin
                    for (p3 = 0; p3 < r_phases; p3 = p3 + 1) begin
                        a3 = ch_ms[p3][q3][r3] / ph_ms[p3];
                        $display("  %0o%0o = %0o%0o       %-10s %7.2f %5.0f %8.2f %% %9.0f",
                                 code_e(q3), code_b(q3), code_e(peer_of(q3, r3)),
                                 code_b(peer_of(q3, r3)),
                                 (p3 == 0) ? "off peak" : "peak", a3,
                                 1.0 * ch_hi[p3][q3][r3], 100.0 * erlb(a3, 6),
                                 1.0 * (evp[p3][q3][2] + evp[p3][peer_of(q3, r3)][2]));
                    end
                end
        $display("     A \"no trunk\" is counted once a DIRECTION, so a hub's four count four.");

        // ---- 3. the pools -------------------------------------------------
        $display("\n  3. The pools, a phase: erlangs, and what they turned away.");
        $display("  %-10s %9s %11s %11s %12s %12s", "phase", "registers", "a caller",
                 "monitors", "unwatched", "resolvers");
        $display("  %-10s %9s %11s %11s %12s %12s", "", "(mean E)", "waited",
                 "(mean E)", "(ms full)", "(mean E)");
        for (p3 = 0; p3 < r_phases; p3 = p3 + 1) begin
            a3 = 0.0; worst_e = 0.0; tot_wait = 0; tot_ntrk = 0;
            b2 = 0; nblk = 0; nhub = 0;
            for (q3 = 0; q3 < NEX; q3 = q3 + 1) begin
                a3 = a3 + reg_ms[p3][q3] / ph_ms[p3];
                tot_wait = tot_wait + evp[p3][q3][1];
                if (ndir_of(q3) > 1) begin
                    // Anything that FORWARDS takes one, which is a transit as much
                    // as a hub: network.md 3.2 says a chain transit "holds
                    // nothing" and the RTL found otherwise (rtl.md).  A leaf
                    // has one direction and never forwards, so it never takes one.
                    worst_e = worst_e + res_ms[p3][q3] / ph_ms[p3];
                    nhub = nhub + 1;
                end
                for (r3 = 0; r3 < 4; r3 = r3 + 1) if (r3 < ndir_of(q3)) begin
                    tot_ntrk = tot_ntrk + mon_fullms[p3][q3][r3];
                    b2 = b2 + $rtoi(mon_ms[p3][q3][r3]);
                    nblk = nblk + 1;             // one monitor pool a trunk block
                end
            end
            // A pool at a time, which is the unit `exch.py traffic` reports and the
            // unit the pools are SIZED in: a register pool an exchange, a monitor
            // pool a trunk block, a resolver pool a hub.
            $display("  %-10s %9.2f %11.0f %11.2f %12.0f %12.2f",
                     (p3 == 0) ? "off peak" : "peak", a3 / NEX, 1.0 * tot_wait,
                     1.0 * b2 / ph_ms[p3] / nblk, 1.0 * tot_ntrk,
                     (nhub > 0) ? worst_e / nhub : 0.0);
        end
        $display("     A register pool an exchange, a monitor pool a trunk block, a resolver pool at");
        $display("     every exchange that can forward -- a transit as much as a hub.  The counts are");
        $display("     the network's.");

        // ---- 4. what a caller waited for -----------------------------------
        $display("\n  4. What a caller waited for.  Dial tone is the register; the rest is the dial.");
        $display("  %-10s %10s %10s %12s %13s", "phase", "dial tone", "worst",
                 "waited a scan", "last pulse to");
        $display("  %-10s %10s %10s %12s %13s", "", "mean, ms", "ms", "or more",
                 "ringback, ms");
        for (p3 = 0; p3 < r_phases; p3 = p3 + 1)
            $display("  %-10s %10.1f %10.0f %11.1f %% %13.1f",
                     (p3 == 0) ? "off peak" : "peak",
                     dt_sum[p3] / (dt_n[p3] ? dt_n[p3] : 1), dt_max[p3],
                     100.0 * n_dtwait[p3] / (dt_n[p3] ? dt_n[p3] : 1),
                     pdd_sum[p3] / (pdd_n[p3] ? pdd_n[p3] : 1));
        $display("     Dial tone, by how many 8 ms scans a caller waited:");
        $display("  %-10s %7s %7s %7s %7s %7s %7s %7s %7s", "phase", "0", "1", "2-3",
                 "4-7", "8-15", "16-31", "32-63", "64+");
        for (p3 = 0; p3 < r_phases; p3 = p3 + 1)
            $display("  %-10s %7.0f %7.0f %7.0f %7.0f %7.0f %7.0f %7.0f %7.0f",
                     (p3 == 0) ? "off peak" : "peak", 1.0 * dt_hist[p3][0], 1.0 * dt_hist[p3][1],
                     1.0 * dt_hist[p3][2], 1.0 * dt_hist[p3][3], 1.0 * dt_hist[p3][4],
                     1.0 * dt_hist[p3][5], 1.0 * dt_hist[p3][6], 1.0 * dt_hist[p3][7]);

        // ---- 5. the checks --------------------------------------------------
        $display("");
        if (r_model == 2) $display("     %0d flash crowds were let loose.", n_herd);
        wantn(n_held == 0, n_held,
              "no port was left BUSY with its line on hook and E dead");
        for (p3 = 0; p3 < r_phases; p3 = p3 + 1) begin
            // The peak phase must actually BE a peak, or nothing below it means
            // anything: the whole run turns on the two phases differing.
            if (p3 > 0)
                wantn(1000 * n_try[p3] / ph_ms[p3] > 1300 * n_try[0] / ph_ms[0],
                      1000 * n_try[p3] / ph_ms[p3],
                      "peak offered at least 30 % more calls a second than off peak");
        end
        pick_links(r_phases - 1);
        if (bs_i >= 0) begin
            a3 = ch_ms[r_phases-1][bs_i][bs_d] / ph_ms[r_phases-1];
            $display("     the busiest spoke link at peak carried %0.2f E of its 8", a3);
            wantn(a3 < 8.0, $rtoi(a3 * 100),
                  "no link carried more than its eight channels");
        end
        if (bh_i >= 0) begin
            a3 = ch_ms[r_phases-1][bh_i][bh_d] / ph_ms[r_phases-1];
            $display("     the busiest backbone link at peak carried %0.2f E of its 8", a3);
        end

        $display("\n  %0d checks, %0d errors.  %s", chk, errs, (errs == 0) ? "PASS" : "FAIL");
        if (errs) $fatal(1);
        $finish;
    end

    initial begin #2_000_000_000_000; $display("  TIMEOUT"); $finish; end
endmodule
