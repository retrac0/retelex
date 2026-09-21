// marker -- the common control.  marker.md 2-4, network.md 3.
//
// A scanner, a probe, a sequencer and a diode matrix.  It holds nothing about
// the exchange: no route table, no translation, no record of where anything is.
// It reads what a port IS from the card's own word at every visit, hunts a
// class in fixed order from 00, writes two latches, and leaves.  Everything
// after those two writes is done by the ports.
//
//   first key   2-7   highway h; wait for the slot digit s; called = h s
//               0     hunt the operator          9  hunt an outside line
//               1     the network: 1 e b h s     8  cannot-complete
//
// The network part is network.md 3's pulse flood, at the origin:
//
//   the first digit is in, and it is 1  -> seize a free trunk, pointed AT THE
//       CALLER, so their remaining digits go down it live as dial pulses.
//   our own e b      -> release the trunk and carry on locally
//   an e or b of 8/9 -> reserved: release, cannot-complete
//   a break within 128 ms of the seizure -> abandon (monitor.md 3, rule 2)
//   the trunk's M rises -> it claimed; when the last digit is in, point the
//       caller at it and free the register
//   no claim 2 s after the last digit -> cannot-complete
//
// and at the far end, where the monitor -- not the marker -- decides:
//
//   a seizure arriving on a trunk -> hold it BUSY, listening to idle, so
//       backward A stays 0 and nothing has claimed yet
//   the monitor claims            -> re-point it with CLAIM set, so backward A
//       rises, and give a register the trunk's port: it is a line here now
//
// and at a HUB, where there is more than one other direction (3.2):
//
//   a seizure arriving -> a free trunk in EVERY other direction, each listening
//       to the incoming one; the incoming one goes on listening to idle, BUSY
//       set, so backward A stays 0.  A RESOLVER remembers the call until a
//       leg's M rises, because latches cannot be read back
`timescale 1ns/1ps

module marker #(
    parameter integer NREG      = 2,        // registers in the pool (marker.md 6)
    parameter integer NRES      = 1,        // resolvers, at a hub (network.md 3.2)
    parameter [2:0]   OWN_E     = 3'd2,
    parameter [2:0]   OWN_B     = 3'd2,
    parameter [5:0]   DIALTONE  = 6'o01,
    parameter [5:0]   BUSYTONE  = 6'o02,
    parameter [5:0]   NOGO      = 6'o03,
    parameter         HAS_NET   = 1'b1,
    // ms: the origin's guard (monitor.md 3, rule 2).  It is a STRAP in the
    // 74HC design -- three stages of the counter the sequence already runs on --
    // and the one number that says how big the network is: 128 ms covers ten hops
    // at a slow marker, 256 twenty-one, 512 forty-two (monitor.md 3.5).
    parameter integer T_GUARD   = 128,
    parameter integer T_CLAIM   = 2000,     // ms: give up waiting for a claim
    // A console is fitted on cable B (console.md 2).  With none, /CON is
    // ignored and may be left unconnected.
    parameter         HAS_CON   = 1'b0
)(
    input            clk,
    input            rst_n,

    // the clock card
    input      [2:0] slotq,
    input      [2:0] tick,
    input            frame_stb,
    input            oct_stb,
    input            tick_1k,

    // the probe: M off the A highway, BUSY and the card's word off PB
    input      [7:0] ha,
    input            pb_busy,
    input            pb_word,

    // cable B, serial (mainboard.md 2.3)
    output           sdata,
    output           sclk,
    output           wr,

    // the registers, a pool.  Everything the marker learns from a register is
    // a LEVEL valid when read -- its busy line, its store -- never an event.
    output reg [NREG-1:0]    reg_attach,
    output reg [5:0]         reg_port,
    output reg [5:0]         reg_src,        // held party loaded at attach; 00 = none
    input      [NREG-1:0]    reg_busy,
    input      [3*NREG-1:0]  reg_ndig,
    input      [20*NREG-1:0] reg_digits,
    input      [6*NREG-1:0]  reg_held,       // each register's src, levels
    output reg [NREG-1:0]    reg_restart,
    input      [NREG-1:0]    reg_gone,
    // WHICH WAY a register went away.  `gone` is CLR or the no-digit timeout
    // and the marker treats them alike; only the counter cares which, so this
    // is one more conductor on the ribbon that already runs between them.
    input      [NREG-1:0]    reg_nodig,
    input      [NREG-1:0]    reg_brk,
    output reg [NREG-1:0]    reg_release,

    // the monitors: a claim is a request held until it is acknowledged
    input            mon_claim,
    input      [5:0] mon_port,
    output reg       mon_ack,

    // for a testbench: any call claimed; every direction any call holds; the
    // legs a fan-out at this exchange is holding, and how many resolvers are in use
    output           any_claimed,
    output reg [3:0] dirs_held,
    output reg [3:0] fan_legs,
    output reg [3:0] res_used,
    // A MODEL diagnostic, not a part: in 74HC the sequencer holds the marker
    // until its write is away, and there is no queue to overrun.  Here there
    // is one, so a stress run wants to know it never did.
    output reg       wq_ovf,
    // How often a caller was put off a scan because a claim had the port bus
    // that cycle.  See `att` below: these are the cycles that used to give a
    // register the wrong port number.
    output reg [15:0] n_defer,
    // The last latch write that actually went out, for a console or a
    // testbench: this is what the operator's lamps would show.
    output reg        wr_stb,
    output reg [5:0]  wr_dst,
    output reg [5:0]  wr_src,
    output reg        wr_bsy, wr_clm,

    // /CON, the console's REQUEST for cable B, and the marker's own '244
    // enable.  A request and not a switch: it is honoured BETWEEN words and
    // never inside one, so a word in flight when it falls still finishes, WR
    // and all (console.md 2).  There is no grant; the console waits instead.
    input             con_n,
    output            bus_oe
);
    // fabric.md 3.5 / extensions.md 2.2 — class in the word, not the old
    // marker.md §1 renumbering.  111 is restricted (conference-as-class retired).
    localparam C_NONE = 3'd0, C_LINE = 3'd1, C_OPER = 3'd2, C_SRC  = 3'd3,
               C_OUT  = 3'd4, C_TRUNK= 3'd5, C_DATA = 3'd6, C_REST = 3'd7;

    // ---------------- the event word (counters.md 9) ------------------
    // What a pure listener cannot see, because nothing is WRITTEN when it
    // happens: a caller who found no register, a direction with no free trunk,
    // a register that timed out, glare.  extensions.md 4 wanted these counted
    // and wired them into the marker; they do not have to be.
    //
    // A word with G = 0 writes to no block -- the guard is ANDed into WR at
    // every one of them -- but it still shifts through every '164 and still
    // pulses WR.  So the marker can REPORT on the bus, and the one-'164 counter
    // card of counters.md 1, which discards bits 15-8 and cannot see G,
    // counts an event with a plain strap.
    //
    // BSY = 0 with CLM = 1 is the whole of the trick.  A claim is always
    // written BUSY (every push below with c = 1 has b = 1), so that combination
    // is one no latch write ever carries, and a strap that asks for it can
    // never count a call.  Sixty-four codes sit under it; these are five.
    localparam [5:0] EV_WAITREG = 6'o01,   // a caller wanting service found no register
                     EV_NODIG   = 6'o02,   // a register gave up: no digit dialled
                     EV_WQOVF   = 6'o03,   // the write queue overran (a model part)
                     EV_GLARE   = 6'o04,   // a seized trunk answered inside the guard
                     EV_NOTRUNK = 6'o10;   // + the direction: all trunks that way busy

    // ---------------- scanner and probe ---------------------------------
    reg [5:0] scan;
    reg       m_acc, b_acc;
    reg [7:0] wsr;
    reg       p_m, p_busy;
    reg [7:0] p_word;
    reg [5:0] p_port;
    reg       visit;

    // With the control bus serial, /BLK is the block's own '138 on DST[5:3], so
    // the block that drives PB is the block THE SHIFT REGISTER NAMES.  A probe
    // taken while the marker was shifting a word for another block reads that
    // other block's BUSY and word.  `pv` follows the visit and is cleared by
    // anything that makes the reading untrustworthy; only a visit that survives
    // it may be acted on.
    reg       pv, p_valid;
    reg [2:0] pb_blk;

    wire [7:0] wsr_next = {pb_word, wsr[7:1]};
    // extensions.md 2.2 / groups.md 2.1 — settled encoding:
    //   frame 0 = 0, [3:1] = class, [7:4] = options     class form
    //   frame 0 = 1, [6:1] = port,  frame 7 = 0         nail
    //   frame 0 = 1, [6:1] = port,  frame 7 = 1         answers to h s (not all ones)
    //   all ones                                        plain line (grounded pin)
    //   all zeros                                       unequipped / no word
    wire       p_plain  = &p_word;
    wire       p_nail   = p_word[0] && !p_word[7] && !p_plain;
    wire       p_ans    = p_word[0] &&  p_word[7] && !p_plain;  // answers to
    wire       p_form   = !p_word[0] && !p_plain;               // explicit class word
    wire [2:0] p_cls    = p_plain ? C_LINE :
                          p_nail  ? C_NONE :
                          p_ans   ? C_LINE :                    // plain line that covers
                          p_word[0] ? C_NONE :
                          p_word[3:1];
    wire [5:0] p_nail_to = p_word[6:1];            // nail partner, or answers-to number
    wire [5:0] p_ans_to  = p_word[6:1];
    // Trunk options (frames 4–7): direction, glare, strap-inhibit.
    wire [1:0] p_dir    = p_word[5:4];
    wire       p_g      = p_word[6];
    wire       p_n      = p_word[7];
    // Line options: frame 5 is priority; frame 6 busy-out.  Overflow `o` is
    // retired by groups.md (answers-to replaces the adjacent run).
    wire       p_pri    = p_form && (p_cls == C_LINE) && p_word[5];
    wire       p_bout   = p_form && p_word[6] &&
                          (p_cls == C_LINE || p_cls == C_OPER ||
                           p_cls == C_DATA || p_cls == C_REST);
    wire       p_z      = p_form && (p_cls == C_REST) && p_word[4];
    wire       p_w      = p_form && (p_cls == C_REST) && p_word[5];
    wire       p_L      = p_form && (p_cls == C_REST) && p_word[7];
    // Bare restricted floors to local-only (extensions.md 2.4).
    wire       p_local  = p_form && (p_cls == C_REST) && (p_L || (!p_z && !p_L));
    wire       p_free   = !p_busy && !p_m;
    wire       p_term   = p_free && !p_bout;               // terminating / hunt free

    // ---------------- the write queue and the serialiser ----------------
    // The sequencer's whole output is latch writes, and a write is one
    // sixteen-bit word on one wire.  The SAME serialiser also steers the
    // probe (see ctl_write.v).  Sixteen deep: with a pool, several calls may
    // queue their writes in one cycle.
    reg [14:0] wq [0:15];              // { G, CLM, BSY, SRC, DST }
    reg [3:0]  wh, wt;
    reg [1:0]  wst;
    reg        ser_req, ser_strobe;
    reg [5:0]  ser_dst, ser_src;
    reg        ser_bsy, ser_clm, ser_g;
    reg        probe_dirty;
    reg        ser_ev;                 // the word in the serialiser is an event
    reg        ovf_pend;               // EV_WQOVF is owed and the queue had no room
    reg        ovf_done;               // ... and has been sent: wq_ovf is sticky
    reg        arb;                    // a caller has been refused a register and
                                       // none has been handed out since
    // Priority under register overload (extensions.md 2.4.1).
    reg        pwait, pwait_seen;
    // Warm / outside-line auto-route as 0 (no register): probe 04 then answers-to.
    reg        warm_run, warm_probe;
    reg [5:0]  warm_from;
    // Per-register dialling limits captured at attach from the caller's word.
    reg [2:0]  clim     [0:NREG-1];    // {z_only, local_only, is_rest}
    // One flip-flop: the marker has let go of cable B.  While it is set the
    // '244 is off, the write sequencer starts nothing, and no visit is
    // trusted -- the block driving PB is the one the CONSOLE's word names.
    reg        yield;
    wire       con_req = HAS_CON && !con_n;
    assign     bus_oe  = !yield;
    wire       ser_busy;
    wire       w_pend = (wh != wt);

    ctl_write u_ser (.clk(clk), .rst_n(rst_n), .req(ser_req), .strobe(ser_strobe),
                     .g(ser_g),
                     .dst(ser_dst), .src(ser_src), .bsy(ser_bsy), .clm(ser_clm),
                     .busy(ser_busy), .sdata(sdata), .sclk(sclk), .wr(wr));

    task push(input [5:0] pt, input [5:0] sr, input b, input c);
        begin
            if (wt + 4'd1 == wh) wq_ovf <= 1'b1;   // sticky: fifteen deep, not sixteen
            wq[wt] = {1'b1, c, b, sr, pt}; wt = wt + 1'b1;
        end
    endtask

    // An event goes out the same way a write does, in its turn, so nothing
    // needs a second serialiser or a second rule.  It is pushed only when the
    // queue has slots to spare and is simply LOST when it has not: an event
    // must never delay a call, and the occasion it would drop is the one where
    // the marker is busiest -- which is what EV_WQOVF is for.
    task push_ev(input [5:0] pt, input [5:0] code);
        begin
            if ((wt - wh) < 4'd11) begin
                wq[wt] = {1'b0, 1'b1, 1'b0, code, pt}; wt = wt + 1'b1;
            end
        end
    endtask

    // ---------------- the hunt: ONE scanner, so one hunt, with an owner --
    reg       hunt_arm, hunt_run, hunt_done, hunt_ok;
    reg [2:0] hunt_cls;
    reg [5:0] hunt_port;
    reg       hunt_dirs;               // the network's: a trunk in every direction
    reg       hunt_ans;                // groups.md: hunt ports that answer to hunt_num
    reg [5:0] hunt_num;
    reg [5:0] cand [0:3];
    reg [3:0] cand_ok;
    reg [3:0] cand_any;                // a trunk faces that way AT ALL, free or not
    reg       hunt_busy;
    reg [3:0] hunt_owner;
    reg       hb;                      // the hunt was taken THIS cycle (blocking)

    localparam [5:0] PILOT_0 = 6'o04;  // groups.md: digit 0 → call 04

    // ---------------- a call: one of these a register --------------------
    // marker.md 4 and network.md 3.2 put a call's state with its
    // REGISTER -- "a '574 a direction in a bank a register" -- and the marker
    // is what acts on it.  Each register has a stage, its caller, the trunks
    // it seized and whether one claimed.
    localparam M_IDLE=4'd0, M_LOCAL=4'd1, M_PROBE=4'd2, M_HUNTW=4'd3,
               M_SEIZE=4'd4, M_NET=4'd5, M_WAITCL=4'd6, M_WANT=4'd7,
               M_CONSULT=4'd8;   // operator transfer: held in reg_held, talking to called


    reg [3:0]  mst     [0:NREG-1];
    reg [5:0]  caller  [0:NREG-1];
    reg [5:0]  called  [0:NREG-1];
    reg [5:0]  trunk   [0:NREG-1];
    reg [1:0]  hold    [0:NREG-1];     // a restart or attach takes a cycle to land
    reg [15:0] tmr     [0:NREG-1];
    reg [3:0]  d_held  [0:NREG-1];
    reg [5:0]  d_trunk [0:4*NREG-1];
    reg [2:0]  hcls    [0:NREG-1];     // the hunt this call is waiting to start
    reg [NREG-1:0] hdirs;
    reg [NREG-1:0] hans;               // M_WANT should start an answers-to hunt
    reg [NREG-1:0] f1, f2, claimed, guarding, ctx_clm;

    assign any_claimed = |claimed;

    // A digit's VALUE is the low three bits, forced to 000 when bit 3 is set --
    // three AND gates, so that a dialled 0, ten pulses, 1010, is octal 0
    // (protocol.md 5).  8 and 9 are service digits.
    function [2:0] oct(input [4:0] c);  oct  = c[3] ? 3'd0 : c[2:0];  endfunction
    function       isvc(input [4:0] c); isvc = (c == 5'd8) || (c == 5'd9) || (c > 5'd10); endfunction

    task nogo(input integer q);                // cannot-complete, and let go
        begin
            if (reg_held[q*6 +: 6] != 6'd0) begin
                // transfer abandon: put the operator back on the held party
                push(caller[q], reg_held[q*6 +: 6], 1'b1, ctx_clm[q]);
                push(reg_held[q*6 +: 6], caller[q], 1'b1, 1'b0);
            end else
                push(caller[q], NOGO, 1'b1, ctx_clm[q]);
            reg_release[q] <= 1'b1; mst[q] <= M_IDLE;
            claimed[q] <= 1'b0; guarding[q] <= 1'b0;
        end
    endtask

    task busy(input integer q);                // busy tone (busy-out / line busy)
        begin
            push(caller[q], BUSYTONE, 1'b1, ctx_clm[q]);
            reg_release[q] <= 1'b1; mst[q] <= M_IDLE;
            claimed[q] <= 1'b0; guarding[q] <= 1'b0;
        end
    endtask

    task drop_trunk(input integer q);          // let go of every trunk this call holds
        integer k;
        begin
            for (k = 0; k < 4; k = k + 1)
                if (d_held[q][k]) push(d_trunk[q*4+k], 6'o00, 1'b0, 1'b0);
            d_held[q] <= 4'd0;
        end
    endtask

    task drop_others(input integer q);         // keep the one that claimed
        integer k;
        begin
            for (k = 0; k < 4; k = k + 1)
                if (d_held[q][k] && d_trunk[q*4+k] != trunk[q])
                    push(d_trunk[q*4+k], 6'o00, 1'b0, 1'b0);
            d_held[q] <= 4'd0;
        end
    endtask

    task take_hunt(input integer q, input [2:0] c, input dirs);
        begin
            hunt_cls <= c; hunt_dirs <= dirs; hunt_ans <= 1'b0;
            hunt_arm <= 1'b1; hunt_done <= 1'b0; hunt_ok <= 1'b0; cand_ok <= 4'd0;
            cand_any <= 4'd0;
            hunt_busy <= 1'b1; hunt_owner <= q[3:0];
            hb = 1'b1;
        end
    endtask

    // groups.md §2: hunt the first free port that answers to `num`.
    task take_ans_hunt(input integer q, input [5:0] num);
        begin
            hunt_ans <= 1'b1; hunt_num <= num; hunt_dirs <= 1'b0;
            hunt_arm <= 1'b1; hunt_done <= 1'b0; hunt_ok <= 1'b0;
            hunt_busy <= 1'b1; hunt_owner <= q[3:0];
            hb = 1'b1;
        end
    endtask

    task free_hunt;
        begin
            hunt_busy <= 1'b0; hunt_done <= 1'b0; hunt_arm <= 1'b0;
            hunt_run <= 1'b0; hunt_ans <= 1'b0;
        end
    endtask

    // ---------------- the forwarder --------------------------------------
    // network.md 3: a seizure arriving on a trunk is patched onward into
    // every OTHER direction, and the exchange forgets everything but the
    // addresses, which go in a resolver.  It runs on its own so that a transit
    // is never held up by a call the marker is setting up.
    localparam F_IDLE = 2'd0, F_RUN = 2'd2, F_GO = 2'd3;
    reg [1:0] fst;
    reg [5:0] f_in, f_start;
    reg [1:0] f_dir;
    reg [5:0] f_cand [0:3];            // a free trunk in each OTHER direction
    reg [3:0] f_cok;

    // ---------------- the resolvers (network.md 3.2) ----------------
    // A hub forwards into two or three directions.  Any number of trunks may
    // listen to the incoming one, so the caller's pulses go down every leg at
    // once -- but the incoming trunk can listen to only ONE port, and which
    // leg will claim is not known until the claim comes back.  Latches cannot
    // be read back, so the hub remembers the call until then, and that is the
    // whole of a resolver: the incoming trunk's address and the legs'.
    //
    // A CHAIN TRANSIT TAKES ONE TOO, though 3.2 says it "holds nothing".  Its
    // one leg is patched through at once and there is nothing to resolve -- but
    // if the call turns out to be this exchange's own, its monitor must clear
    // that onward patch (3.1), and a marker that forgot the pair cannot.
    reg [NRES-1:0] rs_busy;
    reg [5:0]      rs_in  [0:NRES-1];
    reg [5:0]      rs_leg [0:4*NRES-1];
    reg [3:0]      rs_held[0:NRES-1];
    integer        v, rpick, nleg;
    reg [1:0]      first;
    reg            got, legclm;

    integer i, r, pick;
    reg [NREG-1:0] pk;                 // contexts given a caller THIS cycle (blocking)
    reg        att;                    // a register was attached THIS cycle (blocking)
    reg        conn;                   // a call connected to p_port THIS visit (blocking)
    reg        already;
    reg        got_reg;                // this visit's call request got a register
    reg        pri_wait_v;             // priority still wanting this visit
    reg [2:0]  nd;
    reg [4:0]  dg0, dg1;
    reg [5:0]  held;                   // reg_held[r] this cycle
    reg [2:0]  lim;                    // clim[r] this cycle

    always @* begin
        dirs_held = 4'd0;
        for (i = 0; i < NREG; i = i + 1) dirs_held = dirs_held | d_held[i];
        fan_legs = 4'd0;
        res_used = 4'd0;
        for (i = 0; i < NRES; i = i + 1) begin
            fan_legs = fan_legs | rs_held[i];
            res_used = res_used + {3'd0, rs_busy[i]};
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan <= 0; m_acc <= 0; b_acc <= 0; wsr <= 0;
            p_m <= 0; p_busy <= 0; p_word <= 0; p_port <= 0; visit <= 0;
            pv <= 0; p_valid <= 0; pb_blk <= 0;
            wh <= 0; wt <= 0; wst <= 0; probe_dirty <= 1'b1; wq_ovf <= 1'b0;
            n_defer <= 16'd0; yield <= 1'b0;
            wr_stb <= 1'b0; wr_dst <= 0; wr_src <= 0; wr_bsy <= 0; wr_clm <= 0;
            ser_req <= 0; ser_strobe <= 0; ser_dst <= 0; ser_src <= 0;
            ser_bsy <= 0; ser_clm <= 0; ser_g <= 1'b1; ser_ev <= 1'b0;
            ovf_pend <= 1'b0; ovf_done <= 1'b0; arb <= 1'b0;
            pwait <= 1'b0; pwait_seen <= 1'b0;
            warm_run <= 1'b0; warm_probe <= 1'b0; warm_from <= 6'd0;
            reg_attach <= 0; reg_port <= 0; reg_src <= 0;
            reg_release <= 0; reg_restart <= 0;
            mon_ack <= 0;
            hunt_arm <= 0; hunt_run <= 0; hunt_done <= 0; hunt_ok <= 0;
            hunt_cls <= 0; hunt_port <= 0; hunt_dirs <= 0; hunt_ans <= 0;
            hunt_num <= 0; cand_ok <= 0;
            cand_any <= 0;
            hunt_busy <= 0; hunt_owner <= 0;
            fst <= F_IDLE; f_in <= 0; f_dir <= 0; f_cok <= 0; f_start <= 0;
            rs_busy <= {NRES{1'b0}};
            for (i = 0; i < NRES; i = i + 1) begin rs_in[i] <= 6'd0; rs_held[i] <= 4'd0; end
            for (i = 0; i < 4*NRES; i = i + 1) rs_leg[i] <= 6'd0;
            for (i = 0; i < 4; i = i + 1) f_cand[i] <= 6'd0;
            f1 <= 0; f2 <= 0; claimed <= 0; guarding <= 0; ctx_clm <= 0;
            hdirs <= 0; hans <= 0;
            for (i = 0; i < NREG; i = i + 1) begin
                mst[i] <= M_IDLE; caller[i] <= 0; called[i] <= 0; trunk[i] <= 0;
                hold[i] <= 0; tmr[i] <= 0; d_held[i] <= 0; hcls[i] <= 0;
                clim[i] <= 3'd0;
            end
            for (i = 0; i < 4*NREG; i = i + 1) d_trunk[i] <= 6'd0;
            for (i = 0; i < 4; i = i + 1) cand[i] <= 6'd0;
            for (i = 0; i < 16; i = i + 1) wq[i] <= 15'd0;
        end else begin
            reg_attach  <= {NREG{1'b0}};
            reg_release <= {NREG{1'b0}};
            reg_restart <= {NREG{1'b0}};
            visit       <= 1'b0;
            mon_ack     <= 1'b0;
            wr_stb      <= 1'b0;
            hb = 1'b0; pk = {NREG{1'b0}}; conn = 1'b0;
            legclm = 1'b0; att = 1'b0; got = 1'b0;
            got_reg = 1'b0; pri_wait_v = 1'b0;

            // ---- probe -------------------------------------------------
            // M, BUSY and the card's word all arrive in this port's own cell:
            // the highways and both probe-bus commutators are addressed by SLOT.
            if (tick == 3'd4 && slotq == scan[2:0]) begin
                m_acc <= ha[scan[5:3]];
                b_acc <= pb_busy;
                wsr   <= wsr_next;              // one bit a frame, eight in a visit
            end
            if (oct_stb) begin
                p_m <= m_acc; p_busy <= b_acc; p_word <= wsr; p_port <= scan;
                p_valid <= pv;
                visit <= 1'b1;
                // A re-point cannot finish before the visit it governs, so a
                // disturbed visit is REPEATED, not lost.
                if (pv) scan <= scan + 1'b1;
                pv    <= 1'b1;
            end
            // ... and so is a visit the console's tenure touched: from /CON
            // falling until the marker has steered the probe again.
            if (ser_busy || ser_req || pb_blk != scan[5:3] || yield || con_req)
                pv <= 1'b0;

            // ---- the write sequencer -----------------------------------
            // A block turns over only when the scanner ACTUALLY advances.
            if (oct_stb && pv && scan[2:0] == 3'd7) probe_dirty <= 1'b1;
            ser_req <= 1'b0;
            case (wst)
            2'd0: if (!ser_busy && !ser_req && !yield && !con_req) begin
                      if (w_pend) begin
                          ser_dst <= wq[wh][5:0];  ser_src <= wq[wh][11:6];
                          ser_bsy <= wq[wh][12];   ser_clm <= wq[wh][13];
                          ser_g   <= wq[wh][14];   ser_ev  <= !wq[wh][14];
                          ser_strobe <= 1'b1; ser_req <= 1'b1; wst <= 2'd1;
                      end else if (probe_dirty) begin
                          ser_dst <= {scan[5:3], 3'd0}; ser_src <= 6'd0;
                          ser_bsy <= 1'b0; ser_clm <= 1'b0;
                          ser_g   <= 1'b1;  ser_ev <= 1'b0;
                          ser_strobe <= 1'b0; ser_req <= 1'b1;
                          probe_dirty <= 1'b0; wst <= 2'd1;
                      end
                  end
            2'd1: if (ser_busy) wst <= 2'd2;
            2'd2: if (!ser_busy) begin
                      pb_blk <= ser_dst[5:3];
                      if (ser_strobe) begin
                          // An event word came out of the queue like any other
                          // and it steered /BLK like any other, so it costs the
                          // probe exactly what a write costs it.  It is not a
                          // write: nothing reports it as one.
                          wh <= wh + 1'b1; probe_dirty <= 1'b1;
                          if (!ser_ev) begin
                              wr_stb <= 1'b1; wr_dst <= ser_dst; wr_src <= ser_src;
                              wr_bsy <= ser_bsy; wr_clm <= ser_clm;
                          end
                      end
                      wst <= 2'd0;
                  end
            default: wst <= 2'd0;
            endcase

            // ---- /CON: the console has asked for cable B -----------------
            // Let go BETWEEN words only.  A word cut short is a lost write, and
            // a WR cut short is a runt clock into a '273; a word that finishes
            // is neither, and the console's silence is longer than any word
            // (console.md 2).  When the console lets go, the blocks hold ITS
            // last word, so the probe is steered again before a visit counts.
            // After the case above, so that this `probe_dirty` is the last word.
            if (!yield) begin
                if (con_req && wst == 2'd0 && !ser_busy && !ser_req) yield <= 1'b1;
            end else if (!con_req) begin
                yield <= 1'b0; probe_dirty <= 1'b1;
            end

            // ---- the queue overran (a model part, counters.md 9) -----
            // Sticky, and owed until there is room for it: the one event that
            // cannot be pushed when it happens, because what happened is that
            // there was no room.
            if (wq_ovf && !ovf_pend && !ovf_done) begin ovf_pend <= 1'b1; end
            if (ovf_pend && (wt - wh) < 4'd11) begin
                push_ev(6'o00, EV_WQOVF); ovf_pend <= 1'b0; ovf_done <= 1'b1;
            end

            // ---- the hunt, in fixed order from 00 ----------------------
            if (visit && p_valid) begin        // a repeated visit is not a second port
                if (hunt_arm && p_port == 6'd63) begin
                    hunt_arm <= 1'b0; hunt_run <= 1'b1;
                end else if (hunt_run) begin
                    if (hunt_dirs) begin
                        // A free trunk in each direction; the glare bit takes
                        // the LAST found and not the first.
                        if (p_cls == C_TRUNK) cand_any[p_dir] <= 1'b1;
                        if (p_cls == C_TRUNK && p_free && (!cand_ok[p_dir] || p_g)) begin
                            cand[p_dir] <= p_port;
                            cand_ok[p_dir] <= 1'b1;
                        end
                    end else if (hunt_ans) begin
                        // groups.md §2: first free port that answers to hunt_num
                        if (!hunt_ok && p_ans && p_ans_to == hunt_num && p_term) begin
                            hunt_ok <= 1'b1; hunt_port <= p_port;
                        end
                    end else if (!hunt_ok && p_cls == hunt_cls && p_term) begin
                        hunt_ok <= 1'b1; hunt_port <= p_port;
                    end
                    if (p_port == 6'd63) begin hunt_run <= 1'b0; hunt_done <= 1'b1; end
                end
            end

            // ---- the forwarder ------------------------------------------
            // One scan finds a free trunk in EACH other direction; the glare
            // bit takes the last found and not the first.
            if (visit && p_valid && fst == F_RUN) begin
                if (p_cls == C_TRUNK && p_free && !p_n && p_dir != f_dir &&
                    (!f_cok[p_dir] || p_g)) begin
                    f_cand[p_dir] <= p_port; f_cok[p_dir] <= 1'b1;
                end
                if (p_port == f_start) fst <= F_GO;
            end
            if (fst == F_GO) begin
                nleg = 0; first = 2'd0; got = 1'b0;
                for (i = 0; i < 4; i = i + 1)
                    if (f_cok[i]) begin
                        nleg = nleg + 1;
                        if (!got) begin first = i[1:0]; got = 1'b1; end
                    end
                rpick = -1;
                for (v = 0; v < NRES; v = v + 1)
                    if (rpick < 0 && !rs_busy[v]) rpick = v;

                if (got && rpick >= 0) begin
                    // Each leg listens to the incoming trunk, so the caller's
                    // pulses go down every leg at once, and a resolver takes
                    // the addresses.
                    //
                    // Do not arm a leg on a dead source (traffic.md fan-out
                    // leak): a port releases only on the FALL of a detector,
                    // so BUSY written while f_in's M is already low sticks.
                    // At F_GO we are not visiting f_in; the live check is the
                    // resolver's no-claim clear below.  The push still happens
                    // -- cascade release is the happy path when A was high.
                    for (i = 0; i < 4; i = i + 1) begin
                        if (f_cok[i]) push(f_cand[i], f_in, 1'b1, 1'b0);
                        rs_leg[rpick*4+i] <= f_cand[i];
                    end
                    // ONE other direction and there is nothing to resolve: the
                    // incoming trunk listens to that leg at once, as a chain
                    // does, and backward A comes straight through.  More than
                    // one, and it goes on listening to idle with BUSY set (the
                    // write the seizure itself made), so backward A stays 0
                    // until a leg claims -- nothing has claimed yet.
                    //
                    // A CHAIN TRANSIT TAKES A RESOLVER TOO, though 3.2 says it
                    // "holds nothing": if the call turns out to be this
                    // exchange's own, its monitor must clear the onward patch
                    // (3.1, "the patch toward 25 cleared"), and a marker that
                    // forgot the pair cannot -- latches cannot be read back.
                    // The onward link and every link beyond it would stay
                    // seized for the whole conversation.
                    if (nleg == 1) push(f_in, f_cand[first], 1'b1, 1'b0);
                    rs_busy[rpick] <= 1'b1;
                    rs_in  [rpick] <= f_in;
                    rs_held[rpick] <= f_cok;
                end else if (got) begin
                    // No resolver free: "patch into the first direction found,
                    // as a chain would: the call reaches that branch only"
                    // (3.2) -- and this exchange cannot clear it afterwards.
                    push(f_cand[first], f_in,          1'b1, 1'b0);
                    push(f_in,          f_cand[first], 1'b1, 1'b0);
                end
                f_cok <= 4'd0;
                fst   <= F_IDLE;
            end

            // ---- the resolvers: which leg claimed ------------------------
            for (v = 0; v < NRES; v = v + 1) if (rs_busy[v] && visit && p_valid) begin
                legclm = 1'b0;
                for (i = 0; i < 4; i = i + 1)
                    if (rs_held[v][i] && p_port == rs_leg[v*4+i] && p_m) legclm = 1'b1;
                if (legclm) begin
                    // That branch has claimed.  The incoming trunk listens to
                    // it and backward A rises toward the origin; the others are
                    // pointed at idle, and each releases itself 256 ms later,
                    // and its link with it.  The call is two latches now.
                    push(rs_in[v], p_port, 1'b1, 1'b0);
                    for (i = 0; i < 4; i = i + 1)
                        if (rs_held[v][i] && rs_leg[v*4+i] != p_port)
                            push(rs_leg[v*4+i], 6'o00, 1'b0, 1'b0);
                    rs_busy[v] <= 1'b0; rs_held[v] <= 4'd0;
                end else if (p_port == rs_in[v] && !p_busy) begin
                    // No claim: forward A fell, the incoming trunk released
                    // itself.  Cascade release through the patch is the happy
                    // path (network.md 3.2), but only if the legs were written
                    // while A was still high.  Clear them here the same way a
                    // claim clears the unused ones -- otherwise a write that
                    // landed on a dead source leaves no edge to fall on
                    // (traffic.md fan-out leak).
                    for (i = 0; i < 4; i = i + 1)
                        if (rs_held[v][i])
                            push(rs_leg[v*4+i], 6'o00, 1'b0, 1'b0);
                    rs_busy[v] <= 1'b0; rs_held[v] <= 4'd0;
                end
            end

            // =========== every call in the pool, each cycle ===============
            for (r = 0; r < NREG; r = r + 1) begin
                nd  = reg_ndig  [r*3  +: 3];
                dg0 = reg_digits[r*20 +: 5];
                dg1 = reg_digits[r*20 + 5 +: 5];
                held = reg_held[r*6 +: 6];

                if (hold[r] != 2'd0) hold[r] <= hold[r] - 1'b1;

                // the claim coming back: an origin keeps the trunk whose M rises
                if (visit && p_valid && p_m && !claimed[r] &&
                    (mst[r] == M_NET || mst[r] == M_WAITCL))
                    for (i = 0; i < 4; i = i + 1)
                        if (d_held[r][i] && p_port == d_trunk[r*4+i]) begin
                            claimed[r] <= 1'b1;
                            trunk[r]   <= p_port;
                            // GLARE.  A claim cannot come back inside the
                            // origin's guard: the far end has to hear e b h s
                            // first, which is seconds.  M up on a trunk we
                            // seized 128 ms ago is the OTHER end seizing the
                            // same channel, and the two callers get each other
                            // (network.md 1: "residual glare").  The word's
                            // g bit is what makes it rare; this counts what is
                            // left, and changes nothing about what happens.
                            if (guarding[r]) push_ev(p_port, EV_GLARE);
                        end

                // the origin's 128 ms guard (monitor.md 3, rule 2)
                if (guarding[r] && tick_1k) begin
                    if (tmr[r] == T_GUARD[15:0]) guarding[r] <= 1'b0;
                    else tmr[r] <= tmr[r] + 1'b1;
                end

                if (reg_gone[r] && mst[r] != M_IDLE) begin
                    // the caller went away.  CLR is a hook down 256 ms and needs
                    // no report; the timeout is a caller who lifted and dialled
                    // nothing, and holds a register for the whole 10 s.
                    //
                    // Operator transfer (register.md 6.1): src was loaded at
                    // attach.  If we reached consult with a called party, hang-up
                    // pairs held ↔ called and drops the operator.  If we never
                    // connected (nodig / abandon mid-dial), put the operator
                    // back on the held party.
                    if (reg_nodig[r]) push_ev(caller[r], EV_NODIG);
                    if (mst[r] == M_NET || mst[r] == M_WAITCL) drop_trunk(r);
                    if (hunt_busy && hunt_owner == r[3:0]) free_hunt;
                    if (held != 6'd0 && mst[r] == M_CONSULT) begin
                        push(held, called[r], 1'b1, 1'b0);
                        push(called[r], held, 1'b1, 1'b0);
                        push(caller[r], 6'o00, 1'b0, 1'b0);
                    end else if (held != 6'd0) begin
                        push(caller[r], held, 1'b1, 1'b0);
                        push(held, caller[r], 1'b1, 1'b0);
                    end
                    mst[r] <= M_IDLE; claimed[r] <= 1'b0; guarding[r] <= 1'b0;
                end else if (guarding[r] && reg_brk[r]) begin
                    // a break inside the guard: abandon rather than risk a wrong number
                    drop_trunk(r); nogo(r);
                end else case (mst[r])
                M_LOCAL: if (hold[r] == 2'd0) begin
                    lim = clim[r];
                    if (!f1[r] && nd >= 3'd1) begin
                        // Restricted dialling limits (extensions.md 2.4), before
                        // the ordinary first-digit decode.
                        if (lim[2] && lim[0] && dg0 != 4'd10)
                            nogo(r);                               // z: only 0
                        else if (lim[2] && lim[1] &&
                                 (dg0 == 4'd9 || dg0 == 4'd1))
                            nogo(r);                               // local: no 9 / no flood
                        // the first digit: a key, or the highway of a number
                        // A transfer consult with a held party is local only:
                        // the network key cannot carry the held leg.
                        else if (dg0 == 4'd1) begin
                            if (held != 6'd0) nogo(r);
                            else if (HAS_NET) begin
                                push(caller[r], 6'o00, 1'b1, ctx_clm[r]);  // dial tone off
                                // The key is consumed AT ONCE, whether or not the
                                // scanner is free for the hunt: e b h s must land
                                // in slots 0-3 however long the hunt is queued.
                                reg_restart[r] <= 1'b1; hold[r] <= 2'd3;
                                hdirs[r] <= 1'b1; mst[r] <= M_WANT;
                            end else nogo(r);                // no network card fitted
                        end
                        else if (dg0 == 4'd8)  nogo(r);      // spare
                        else if (dg0 == 4'd9)  begin
                            if (held != 6'd0) nogo(r);
                            else begin hcls[r] <= C_OUT;  hdirs[r] <= 1'b0; mst[r] <= M_WANT; end
                        end
                        else if (dg0 == 4'd10) begin
                            // groups.md: 0 → call pilot 04, then answers-to hunt
                            if (held != 6'd0) nogo(r);
                            else begin
                                push(caller[r], 6'o00, 1'b1, ctx_clm[r]);
                                called[r] <= PILOT_0; mst[r] <= M_PROBE;
                            end
                        end
                        else if (isvc(dg0)) nogo(r);
                        else begin
                            push(caller[r], 6'o00, 1'b1, ctx_clm[r]);      // dial tone off
                            f1[r] <= 1'b1;
                        end
                    end else if (f1[r] && nd >= 3'd2) begin
                        called[r] <= {oct(dg0), oct(dg1)}; mst[r] <= M_PROBE;
                    end
                end
                M_CONSULT: ;   // waiting for hang-up / CLR -- handled in reg_gone

                M_WANT: if (!hunt_busy && !hb) begin
                    // one scanner, so one hunt at a time: wait for it
                    if (hans[r]) begin
                        take_ans_hunt(r, called[r]);
                        hans[r] <= 1'b0; mst[r] <= M_HUNTW;
                    end else begin
                        take_hunt(r, hcls[r], hdirs[r]);
                        mst[r] <= hdirs[r] ? M_SEIZE : M_HUNTW;
                    end
                end
                M_SEIZE: if (hunt_done && hunt_owner == r[3:0]) begin
                    free_hunt;
                    // A direction that HAS trunks and had none free is
                    // congestion, and it is worth a count whether or not some
                    // other direction carried the call: the flood is offered to
                    // all of them.  A direction with no trunks fitted is not
                    // congestion, which is what cand_any is for.
                    for (i = 0; i < 4; i = i + 1)
                        if (cand_any[i] && !cand_ok[i])
                            push_ev(6'o00, EV_NOTRUNK + i);
                    if (cand_ok != 4'd0) begin
                        // Seize one free trunk in EVERY direction, all listening
                        // to the CALLER: their digits go down the flood live.
                        for (i = 0; i < 4; i = i + 1)
                            if (cand_ok[i]) begin
                                push(cand[i], caller[r], 1'b1, 1'b0);
                                d_trunk[r*4+i] <= cand[i];
                            end
                        d_held[r]   <= cand_ok;
                        trunk[r]    <= 6'd0;
                        guarding[r] <= 1'b1; tmr[r] <= 0; mst[r] <= M_NET;
                        f1[r] <= 1'b0; f2[r] <= 1'b0;
                    end else nogo(r);                        // no free trunk anywhere
                end
                M_HUNTW: if (hunt_done && hunt_owner == r[3:0]) begin
                    free_hunt;
                    if (hunt_ok) begin
                        push(caller[r], hunt_port, 1'b1, ctx_clm[r]);
                        push(hunt_port, caller[r], 1'b1, 1'b0);
                        if (held != 6'd0) begin
                            called[r] <= hunt_port; mst[r] <= M_CONSULT;
                        end else begin
                            reg_release[r] <= 1'b1; mst[r] <= M_IDLE;
                        end
                    end else nogo(r);
                end
                M_NET: if (hold[r] == 2'd0) begin
                    if (!f1[r] && nd >= 3'd1) begin                   // e
                        if (isvc(dg0)) begin drop_trunk(r); nogo(r); end   // reserved
                        else f1[r] <= 1'b1;
                    end else if (f1[r] && !f2[r] && nd >= 3'd2) begin  // b
                        if (isvc(dg1)) begin drop_trunk(r); nogo(r); end
                        else if (oct(dg0) == OWN_E && oct(dg1) == OWN_B) begin
                            // our own code: release the trunks and carry on
                            // locally.  The store restarts, and h s arrive as
                            // any local number does.
                            drop_trunk(r);
                            reg_restart[r] <= 1'b1; hold[r] <= 2'd3;
                            f1[r] <= 1'b0; f2[r] <= 1'b0; mst[r] <= M_LOCAL;
                        end else f2[r] <= 1'b1;
                    end else if (f2[r] && nd >= 3'd4) begin            // h s: dialling is over
                        mst[r] <= M_WAITCL; tmr[r] <= 0;
                    end
                end
                M_PROBE: if (visit && p_valid && p_port == called[r]) begin
                    // Probe the dialled (or pilot) port.  Free → connect.
                    // Otherwise hunt ports that answer to that number
                    // (groups.md §2) — replaces the adjacent `o` overflow run.
                    if (conn)
                        nogo(r);
                    else if (p_term && (p_cls == C_LINE || p_cls == C_OPER ||
                                        p_cls == C_REST || p_cls == C_SRC)) begin
                        push(caller[r], called[r], 1'b1, ctx_clm[r]);
                        push(called[r], caller[r], 1'b1, 1'b0);
                        if (held != 6'd0) mst[r] <= M_CONSULT;
                        else begin
                            reg_release[r] <= 1'b1; mst[r] <= M_IDLE;
                        end
                        conn = 1'b1;
                    end else begin
                        // busy, empty, trunk, self, busy-out, … → answers-to
                        hans[r] <= 1'b1; mst[r] <= M_WANT;
                    end
                end
                M_WAITCL: if (claimed[r]) begin
                    drop_others(r);                          // the ones that did not claim
                    push(caller[r], trunk[r], 1'b1, ctx_clm[r]);
                    reg_release[r] <= 1'b1; mst[r] <= M_IDLE; claimed[r] <= 1'b0;
                end else if (tick_1k) begin
                    if (tmr[r] == T_CLAIM[15:0]) begin drop_trunk(r); nogo(r); end
                    else tmr[r] <= tmr[r] + 1'b1;
                end
                default: ;
                endcase
            end

            // =========== work that wants a free register ==================
            // A context given out this cycle is marked in pk at once, because
            // its stage only changes at the clock edge: without it a claim and
            // a call request in one cycle would both be handed the same register.

            // ---- the monitor claims: this call is ours -----------------
            if (mon_claim && !mon_ack && (wt - wh) < 4'd10) begin
                mon_ack <= 1'b1;
                pick = -1;
                for (r = 0; r < NREG; r = r + 1)
                    if (pick < 0 && mst[r] == M_IDLE && !reg_busy[r] && !pk[r]) pick = r;
                // ours: the hub's monitor claims, as any owner does, and every
                // leg of a fan-out on this trunk is pointed at idle (3.2)
                for (v = 0; v < NRES; v = v + 1)
                    if (rs_busy[v] && rs_in[v] == mon_port) begin
                        for (i = 0; i < 4; i = i + 1)
                            if (rs_held[v][i]) push(rs_leg[v*4+i], 6'o00, 1'b0, 1'b0);
                        rs_busy[v] <= 1'b0; rs_held[v] <= 4'd0;
                    end
                if (pick >= 0) begin
                    arb <= 1'b0;
                    push(mon_port, 6'o00, 1'b1, 1'b1);       // CLAIM: backward A rises
                    reg_attach[pick] <= 1'b1; reg_port <= mon_port; reg_src <= 6'd0;
                    caller[pick] <= mon_port; mst[pick] <= M_LOCAL;
                    claimed[pick] <= 1'b0; f1[pick] <= 1'b0; f2[pick] <= 1'b0;
                    hold[pick] <= 2'd3;
                    ctx_clm[pick] <= 1'b1;                   // claimed until release
                    pk[pick] = 1'b1; att = 1'b1;
                end else begin
                    // no register free: claimed, cannot complete -- the caller
                    // hears it at once (monitor.md 2)
                    push(mon_port, NOGO, 1'b1, 1'b1);
                end
            end

            // ---- nail first (extensions.md 3.1) -------------------------
            // A nail with BUSY clear is rewritten every visit before any call
            // request.  A nailed port is never free and never a caller.
            if (visit && p_valid && p_nail && !p_busy)
                push(p_port, p_nail_to, 1'b1, 1'b0);

            // ---- warm / outside: as dialled 0 — probe 04, then answers-to
            if (warm_run && warm_probe && visit && p_valid && p_port == PILOT_0) begin
                if (p_term && (p_cls == C_LINE || p_cls == C_OPER ||
                               p_cls == C_REST || p_cls == C_SRC)) begin
                    push(warm_from, PILOT_0, 1'b1, 1'b0);
                    push(PILOT_0, warm_from, 1'b1, 1'b0);
                    warm_run <= 1'b0; warm_probe <= 1'b0;
                end else if (!hunt_busy && !hb) begin
                    take_ans_hunt(4'hF, PILOT_0);
                    warm_probe <= 1'b0;
                end
            end
            if (warm_run && !warm_probe && hunt_done && hunt_owner == 4'hF) begin
                free_hunt;
                if (hunt_ok) begin
                    push(warm_from, hunt_port, 1'b1, 1'b0);
                    push(hunt_port, warm_from, 1'b1, 1'b0);
                end else
                    push(warm_from, NOGO, 1'b1, 1'b0);
                warm_run <= 1'b0;
            end

            // ---- a port wanting service ---------------------------------
            // Not an `else` of the claim: a visit is one cycle wide, and an
            // arriving SEIZURE must not wait a scan for one.
            if (visit && p_valid && p_m && !p_busy && !p_nail) begin
                if (p_cls == C_TRUNK) begin
                    // a seizure arriving: hold it busy, listening to idle, so
                    // backward A stays 0 -- no claim yet -- and hand it to the
                    // forwarder, unless it came in on a strapped link (3.3)
                    push(p_port, 6'o00, 1'b1, 1'b0);
                    if (fst == F_IDLE && !p_n) begin
                        f_in <= p_port; f_dir <= p_dir; f_start <= p_port;
                        f_cok <= 4'd0; fst <= F_RUN;
                    end
                end else if (p_cls == C_OUT || (p_cls == C_REST && p_w)) begin
                    // CO ringing in, or warm restricted: as if dialled 0.
                    already = 1'b0;
                    for (r = 0; r < NREG; r = r + 1)
                        if (mst[r] != M_IDLE && caller[r] == p_port) already = 1'b1;
                    if (!already && !warm_run) begin
                        warm_from <= p_port; warm_run <= 1'b1; warm_probe <= 1'b1;
                        push(p_port, 6'o00, 1'b1, 1'b0);   // hold busy while routing
                    end
                end else if (p_cls == C_LINE || p_cls == C_OPER ||
                             (p_cls == C_REST && !p_w)) begin
                    // a caller: the first free register.  None free, and the
                    // caller simply waits -- the scanner will be back in 8 ms.
                    // Under PWAIT, a non-priority line waits even with a free
                    // register until a full revolution finds no priority lift
                    // still wanting one (extensions.md 2.4.1).
                    already = 1'b0;
                    pick = -1;
                    for (r = 0; r < NREG; r = r + 1) begin
                        if (mst[r] != M_IDLE && caller[r] == p_port) already = 1'b1;
                        if (pick < 0 && mst[r] == M_IDLE && !reg_busy[r] && !pk[r]) pick = r;
                    end
                    if (!already && pick < 0 && !arb) begin
                        arb <= 1'b1; push_ev(p_port, EV_WAITREG);
                    end
                    if (!already && pick >= 0 && (p_pri || !pwait)) begin
                        if (att) n_defer <= n_defer + 1'b1;
                        else begin
                            arb <= 1'b0;
                            reg_attach[pick] <= 1'b1; reg_port <= p_port; reg_src <= 6'd0;
                            push(p_port, DIALTONE, 1'b1, 1'b0);
                            caller[pick] <= p_port; mst[pick] <= M_LOCAL;
                            claimed[pick] <= 1'b0; guarding[pick] <= 1'b0;
                            ctx_clm[pick] <= 1'b0; f1[pick] <= 1'b0; f2[pick] <= 1'b0;
                            hold[pick] <= 2'd3;
                            clim[pick] <= {(p_cls == C_REST), p_local, p_z};
                            pk[pick] = 1'b1;
                            got_reg = 1'b1;
                        end
                    end
                    if (p_pri && !already && !got_reg)
                        pri_wait_v = 1'b1;
                end
            end

            // ---- PWAIT: accumulate, and close the revolution at 77 ------
            if (pri_wait_v && p_port != 6'o77)
                pwait_seen <= 1'b1;
            if (visit && p_valid && p_port == 6'o77) begin
                pwait <= pwait_seen | pri_wait_v;
                pwait_seen <= 1'b0;
            end
        end
    end
endmodule
