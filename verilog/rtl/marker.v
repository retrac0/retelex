// marker -- the common control.  marker.md 2-4, common-control.md.
//
// A scanner, a probe, a sequencer and a diode matrix.  It holds nothing about
// the exchange: no route table, no translation, no record of where anything is.
// It reads what a port IS from the card's own word at every visit, hunts a
// class in fixed order from 00, writes two latches, and leaves.  Everything
// after those two writes is done by the ports.  The pulse flood is net_unit.
//
//   first key   2-7   highway h; wait for the slot digit s; called = h s
//               0     hunt the operator          9  hunt an outside line
//               1     highway, or flood_go if a network unit is fitted
//               8     cannot-complete
`timescale 1ns/1ps

module marker #(
    parameter integer NREG      = 2,        // registers in the pool (marker.md 6)
    parameter [5:0]   DIALTONE  = 6'o01,
    parameter [5:0]   BUSYTONE  = 6'o02,
    parameter [5:0]   NOGO      = 6'o03,
    parameter         HAS_NET   = 1'b0,     // a network unit is fitted
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

    // the probe, so a network unit can watch the scan (common-control.md 2.2)
    output     [5:0] probe_port,
    output     [2:0] scan_port,          // live scanner[2:0] for the probe mux
    output           probe_visit,
    output           probe_valid,
    output           probe_m,
    output           probe_busy,
    output     [15:0] probe_word,

    // network unit.  Tie the inputs off when HAS_NET = 0.
    output reg [NREG-1:0]    flood_go,
    output     [6*NREG-1:0]  flood_caller,
    input      [NREG-1:0]    net_restart,
    input      [NREG-1:0]    net_done,
    input      [NREG-1:0]    net_nogo,
    input      [NREG-1:0]    net_local,   // own e b: continue as local
    input                    net_att,
    input      [5:0]         net_att_port,
    input      [3:0]         net_nw,
    input      [8*6-1:0]     net_wdst,
    input      [8*6-1:0]     net_wsrc,
    input      [7:0]         net_wbsy,
    input      [7:0]         net_wclm,
    input      [7:0]         net_wev,
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
    // counts an event with a plain jumper.
    //
    // BSY = 0 with CLM = 1 is the whole of the trick.  A claim is always
    // written BUSY (every push below with c = 1 has b = 1), so that combination
    // is one no latch write ever carries, and a jumper that asks for it can
    // never count a call.  Sixty-four codes sit under it; these are five.
    localparam [5:0] EV_WAITREG = 6'o01,   // a caller wanting service found no register
                     EV_NODIG   = 6'o02,   // a register gave up: no digit dialled
                     EV_WQOVF   = 6'o03;   // the write queue overran (a model part)

    // ---------------- scanner and probe ---------------------------------
    // One CLK_8K period a port (socket TX_OCT).  PB word/BUSY are held on
    // DST[2:0] (block.v), so the card's 16-bit word at 128 kHz fills in one
    // visit — eight ports a ms, 8 ms a scan (extensions.md 2.2, marker.md 3).
    reg [5:0] scan;
    reg       m_acc, b_acc;
    reg [15:0] wsr;
    reg [4:0]  wdiv;                   // 4.096 MHz / 32 = 128 kHz
    reg       p_m, p_busy;
    reg [15:0] p_word;
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

    // LSB-first on the pin (bit-time 0 = WORD[0]): first sample ends in [0].
    wire       w_take    = (wdiv == 5'd31);
    wire [15:0] wsr_next = {pb_word, wsr[15:1]};
    // extensions.md 2.2 — primary (bits 7–0): type + class/options or h s.
    // Secondary: tag [9:8], payload [15:10].  Unfitted → FF.
    //   00 hhhhhh      tied nail (all zeros = unequipped)
    //   01 hhhhhh      answers to h s
    //   10 hhhhhh      call nail: on lift, connect as if dialled h s
    //   11 ccc ppp     class form; all ones = plain line
    wire       p_plain  = &p_word;
    wire       p_none   = ~|p_word;
    wire [1:0] p_type   = p_word[1:0];
    wire [1:0] p_tag    = p_word[9:8];
    wire [5:0] p_pay    = p_word[15:10];
    wire       p_sec_ff = (p_word[15:8] == 8'hFF);
    // MBZ: restricted bit7 must be 0; line/oper/data bit7 must be 0;
    // trunk primary options must be 000; tag 11 requires payload ones.
    wire       p_form_raw = !p_plain && (p_type == 2'b11);
    wire [2:0] p_cls_raw  = p_form_raw ? p_word[4:2] : 3'd0;
    wire       p_opt_bad  = p_form_raw && (
                              (p_cls_raw == C_REST  && p_word[7]) ||
                              (p_cls_raw == C_LINE  && p_word[7]) ||
                              (p_cls_raw == C_OPER  && (p_word[7] || p_word[5])) ||
                              (p_cls_raw == C_DATA  && (p_word[7] || p_word[5])) ||
                              (p_cls_raw == C_SRC   && |p_word[7:5]) ||
                              (p_cls_raw == C_OUT   && |p_word[7:5]) ||
                              (p_cls_raw == C_TRUNK && |p_word[7:6]));
    // Answers-to secondary (extensions.md §2.2.1): FF idle; tag 00 field A
    // zeros only; tag 01 dual membership; tag 10 field B LUK000 or 111111.
    wire       p_ans_a    = (p_tag == 2'b00) && (p_pay == 6'b000000);
    wire       p_ans_dual = (p_tag == 2'b01);
    wire       p_ans_b_nf = (p_tag == 2'b10) && (p_pay == 6'b111111);
    wire       p_ans_b_fl = (p_tag == 2'b10) && (p_pay[2:0] == 3'b000) &&
                              !(p_pay[4] && p_pay[3]);   // U∧K → OOS
    wire       p_ans_sec  = (p_type == 2'b01) &&
                              (p_sec_ff || p_ans_a || p_ans_dual ||
                               p_ans_b_nf || p_ans_b_fl);
    wire       p_tag_bad  =
                              (!p_sec_ff && p_tag == 2'b11) ||
                              // tag 00: answers-to field A (zeros) OK; else
                              // reserved/OOS (call-nail network until dialler)
                              (p_tag == 2'b00 && p_type != 2'b01) ||
                              // trunk must have tag 10 and ttt=000
                              (p_cls_raw == C_TRUNK &&
                               !(p_tag == 2'b10 && p_pay[2:0] == 3'b000)) ||
                              // tag 01: class+cover (not trunk) or answers-to dual
                              (p_tag == 2'b01 &&
                               !(p_type == 2'b01 ||
                                 (p_form_raw && p_cls_raw != C_TRUNK))) ||
                              // tag 10: trunk or answers-to field B; else OOS
                              (p_tag == 2'b10 && p_type != 2'b01 &&
                               !(p_form_raw && p_cls_raw == C_TRUNK)) ||
                              // tied nail: secondary must be FF
                              (!p_sec_ff && p_type == 2'b00) ||
                              // answers-to: only listed secondaries
                              (p_type == 2'b01 && !p_ans_sec) ||
                              // call nail: only FF secondary for now
                              (p_type == 2'b10 && !p_sec_ff);
    wire       p_oos    = p_opt_bad || p_tag_bad;
    wire       p_form   = p_form_raw && !p_oos;
    wire       p_ans    = (p_type == 2'b01) && !p_oos;
    wire       p_cnail  = (p_type == 2'b10) && !p_oos && p_sec_ff; // local only
    wire       p_nail   = !p_none && (p_type == 2'b00) && !p_oos;
    wire [5:0] p_hs     = p_word[7:2];             // dest / answers-to / call-nail
    wire [2:0] p_cls    = p_plain ? C_LINE :
                          p_oos   ? C_NONE :
                          p_nail  ? C_NONE :
                          (p_ans || p_cnail) ? C_LINE :
                          p_form  ? p_word[4:2] : C_NONE;
    wire [5:0] p_nail_to = p_hs;
    // Field B L/U/K (extensions.md §2.2.1); 111111 or non-B → unconditional.
    wire       p_b_L     = p_ans && (p_tag == 2'b10) && !p_ans_b_nf && p_pay[5];
    wire       p_b_U     = p_ans && (p_tag == 2'b10) && !p_ans_b_nf && p_pay[4];
    wire       p_b_K     = p_ans && (p_tag == 2'b10) && !p_ans_b_nf && p_pay[3];
    wire [5:0] p_cnail_to = p_hs;
    // Line options: frame 5 priority; frame 6 busy-out.  Restricted z is
    // frame 5; bit 7 MBZ.  Floor: restricted ∧ ¬z → local-only.
    // Trunk option bit 5 = offers-tone (leaf-uplink.md).
    wire       p_pri    = p_form && (p_cls == C_LINE) && p_word[5];
    wire       p_bout   = p_form && p_word[6] &&
                          (p_cls == C_LINE || p_cls == C_OPER ||
                           p_cls == C_DATA || p_cls == C_REST);
    wire       p_z      = p_form && (p_cls == C_REST) && p_word[5];
    wire       p_offers = p_form && (p_cls == C_TRUNK) && p_word[5];
    wire       p_local  = p_form && (p_cls == C_REST) && !p_z;
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
    reg [5:0]  warm_from, warm_to;
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
    reg       hunt_ans;                // groups.md: hunt ports that answer to hunt_num
    reg [5:0] hunt_num;
    reg       hunt_busy;
    reg [3:0] hunt_owner;
    reg       hb;                      // the hunt was taken THIS cycle (blocking)
    // Field B conditions: why the owner probe failed, and caller origin.
    reg       hunt_own_oos;            // dialled/pilot was unequipped / OOS / empty
    reg       hunt_own_busy;           // dialled/pilot was busy / busy-out / held
    reg       hunt_from_trunk;         // caller is a claimed trunk (ctx_clm)
    localparam [5:0] PILOT_0 = 6'o04;  // groups.md: digit 0 → call 04

    // ---------------- a call: one of these a register --------------------
    localparam M_IDLE=4'd0, M_LOCAL=4'd1, M_PROBE=4'd2, M_HUNTW=4'd3,
               M_WANT=4'd7, M_CONSULT=4'd8, M_YIELD=4'd9;

    reg [3:0]  mst     [0:NREG-1];
    reg [5:0]  caller  [0:NREG-1];
    reg [5:0]  called  [0:NREG-1];
    reg [1:0]  hold    [0:NREG-1];     // a restart or attach takes a cycle to land
    reg [2:0]  hcls    [0:NREG-1];     // the hunt this call is waiting to start
    reg [NREG-1:0] hans;               // M_WANT should start an answers-to hunt
    reg [NREG-1:0] f1, f2, ctx_clm;

    assign probe_port  = p_port;
    assign scan_port   = scan[2:0];
    assign probe_visit = visit;
    assign probe_valid = p_valid;
    assign probe_m     = p_m;
    assign probe_busy  = p_busy;
    assign probe_word  = p_word;

    genvar gc;
    generate for (gc = 0; gc < NREG; gc = gc + 1) begin : fl
        assign flood_caller[gc*6 +: 6] = caller[gc];
    end endgenerate

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
        end
    endtask

    task busy(input integer q);                // busy tone (busy-out / line busy)
        begin
            push(caller[q], BUSYTONE, 1'b1, ctx_clm[q]);
            reg_release[q] <= 1'b1; mst[q] <= M_IDLE;
        end
    endtask

    task take_hunt(input integer q, input [2:0] c);
        begin
            hunt_cls <= c; hunt_ans <= 1'b0;
            hunt_arm <= 1'b1; hunt_done <= 1'b0; hunt_ok <= 1'b0;
            hunt_busy <= 1'b1; hunt_owner <= q[3:0];
            hb = 1'b1;
        end
    endtask

    // groups.md §2: hunt the first free port that answers to `num`.
    task take_ans_hunt(input integer q, input [5:0] num);
        begin
            hunt_ans <= 1'b1; hunt_num <= num;
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

    // A source is listen-only: one write.  Anything else is a pair.
    task pair_or_listen(input [5:0] from, input [5:0] dest, input dest_src, input clm);
        begin
            push(from, dest, 1'b1, clm);
            if (!dest_src) push(dest, from, 1'b1, 1'b0);
        end
    endtask

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

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan <= 0; m_acc <= 0; b_acc <= 0; wsr <= 0; wdiv <= 0;
            p_m <= 0; p_busy <= 0; p_word <= 0; p_port <= 0; visit <= 0;
            pv <= 0; p_valid <= 0; pb_blk <= 0;
            wh <= 0; wt <= 0; wst <= 0; probe_dirty <= 1'b1; wq_ovf <= 1'b0;
            n_defer <= 16'd0; yield <= 1'b0;
            wr_stb <= 1'b0; wr_dst <= 0; wr_src <= 0; wr_bsy <= 0; wr_clm <= 0;
            ser_req <= 0; ser_strobe <= 0; ser_dst <= 0; ser_src <= 0;
            ser_bsy <= 0; ser_clm <= 0; ser_g <= 1'b1; ser_ev <= 1'b0;
            ovf_pend <= 1'b0; ovf_done <= 1'b0; arb <= 1'b0;
            pwait <= 1'b0; pwait_seen <= 1'b0;
            warm_run <= 1'b0; warm_probe <= 1'b0;
            warm_from <= 6'd0; warm_to <= 6'd0;
            reg_attach <= 0; reg_port <= 0; reg_src <= 0;
            reg_release <= 0; reg_restart <= 0;
            flood_go <= 0;
            hunt_arm <= 0; hunt_run <= 0; hunt_done <= 0; hunt_ok <= 0;
            hunt_cls <= 0; hunt_port <= 0; hunt_ans <= 0;
            hunt_num <= 0;
            hunt_own_oos <= 0; hunt_own_busy <= 0; hunt_from_trunk <= 0;
            hunt_busy <= 0; hunt_owner <= 0;
            f1 <= 0; f2 <= 0; ctx_clm <= 0;
            hans <= 0;
            for (i = 0; i < NREG; i = i + 1) begin
                mst[i] <= M_IDLE; caller[i] <= 0; called[i] <= 0;
                hold[i] <= 0; hcls[i] <= 0;
                clim[i] <= 3'd0;
            end
            for (i = 0; i < 16; i = i + 1) wq[i] <= 15'd0;
        end else begin
            reg_attach  <= {NREG{1'b0}};
            reg_release <= {NREG{1'b0}};
            flood_go    <= {NREG{1'b0}};
            visit       <= 1'b0;
            wr_stb      <= 1'b0;
            hb = 1'b0; pk = {NREG{1'b0}}; conn = 1'b0;
            att = 1'b0;
            got_reg = 1'b0; pri_wait_v = 1'b0;
            reg_restart <= net_restart;

            // drain the network unit's write burst (one cycle late; a hop is ms)
            for (i = 0; i < 8; i = i + 1)
                if (i < net_nw) begin
                    if (net_wev[i])
                        push_ev(net_wdst[i*6 +: 6], net_wsrc[i*6 +: 6]);
                    else
                        push(net_wdst[i*6 +: 6], net_wsrc[i*6 +: 6],
                             net_wbsy[i], net_wclm[i]);
                end

            // ---- probe -------------------------------------------------
            // M still arrives in this port's own cell on HA.  BUSY and the
            // card's word ride PB held on DST[2:0] for the visit — sixteen
            // bits at 128 kHz (4.096 MHz / 32) fill one octet.  The /32
            // counter is retimed on CLK_8K with the cards' parallel load.
            if (tick == 3'd4 && slotq == scan[2:0])
                m_acc <= ha[scan[5:3]];
            if (oct_stb) begin
                // Bit 15 of the visit that just ended (w_take) lands here with
                // the card's load of the next word; then start the new visit.
                p_m <= m_acc;
                p_busy <= w_take ? pb_busy : b_acc;
                p_word <= w_take ? wsr_next : wsr;
                p_port <= scan;
                p_valid <= pv;
                visit <= 1'b1;
                wsr   <= 16'd0;
                b_acc <= pb_busy;
                wdiv  <= 5'd0;
                // A re-point cannot finish before the visit it governs, so a
                // disturbed visit is REPEATED, not lost.
                if (pv) scan <= scan + 1'b1;
                pv    <= 1'b1;
            end else if (w_take) begin
                wsr   <= wsr_next;
                b_acc <= pb_busy;
                wdiv  <= 5'd0;
            end else
                wdiv  <= wdiv + 1'b1;
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
                    if (hunt_ans) begin
                        // groups.md §2 / extensions.md §2.2.1: first free port
                        // that answers to hunt_num (primary, dual alias, or
                        // class+cover), subject to field B L/U/K.
                        if (!hunt_ok && p_term &&
                            ((p_ans && (p_hs == hunt_num ||
                                        (p_tag == 2'b01 && p_pay == hunt_num))) ||
                             (p_form && p_tag == 2'b01 && p_pay == hunt_num)) &&
                            (!p_b_L || !hunt_from_trunk) &&
                            (!p_b_U || hunt_own_oos) &&
                            (!p_b_K || hunt_own_busy)) begin
                            hunt_ok <= 1'b1; hunt_port <= p_port;
                        end
                    end else if (!hunt_ok && p_cls == hunt_cls && p_term) begin
                        hunt_ok <= 1'b1; hunt_port <= p_port;
                    end
                    if (p_port == 6'd63) begin hunt_run <= 1'b0; hunt_done <= 1'b1; end
                end
            end

            // =========== every call in the pool, each cycle ===============
            for (r = 0; r < NREG; r = r + 1) begin
                nd  = reg_ndig  [r*3  +: 3];
                dg0 = reg_digits[r*20 +: 5];
                dg1 = reg_digits[r*20 + 5 +: 5];
                held = reg_held[r*6 +: 6];

                if (hold[r] != 2'd0) hold[r] <= hold[r] - 1'b1;

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
                    if (hunt_busy && hunt_owner == r[3:0]) free_hunt;
                    if (held != 6'd0 && mst[r] == M_CONSULT) begin
                        push(held, called[r], 1'b1, 1'b0);
                        push(called[r], held, 1'b1, 1'b0);
                        push(caller[r], 6'o00, 1'b0, 1'b0);
                    end else if (held != 6'd0) begin
                        push(caller[r], held, 1'b1, 1'b0);
                        push(held, caller[r], 1'b1, 1'b0);
                    end
                    mst[r] <= M_IDLE;
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
                                push(caller[r], 6'o00, 1'b1, ctx_clm[r]);
                                reg_restart[r] <= 1'b1; hold[r] <= 2'd3;
                                flood_go[r] <= 1'b1; mst[r] <= M_YIELD;
                            end else begin
                                push(caller[r], 6'o00, 1'b1, ctx_clm[r]);
                                f1[r] <= 1'b1;                     // highway 1
                            end
                        end
                        else if (dg0 == 4'd8)  nogo(r);      // spare
                        else if (dg0 == 4'd9)  begin
                            if (held != 6'd0) nogo(r);
                            else begin hcls[r] <= C_OUT; mst[r] <= M_WANT; end
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

                M_YIELD: begin
                    if (net_local[r]) begin
                        mst[r] <= M_LOCAL; hold[r] <= 2'd3;
                        f1[r] <= 1'b0; f2[r] <= 1'b0;
                    end else if (net_done[r]) begin
                        reg_release[r] <= 1'b1; mst[r] <= M_IDLE;
                    end else if (net_nogo[r])
                        nogo(r);
                end

                M_WANT: if (!hunt_busy && !hb) begin
                    // one scanner, so one hunt at a time: wait for it
                    if (hans[r]) begin
                        take_ans_hunt(r, called[r]);
                        hans[r] <= 1'b0; mst[r] <= M_HUNTW;
                    end else begin
                        take_hunt(r, hcls[r]);
                        mst[r] <= M_HUNTW;
                    end
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
                M_PROBE: if (visit && p_valid && p_port == called[r]) begin
                    // Probe the dialled (or pilot) port.  Free → connect.
                    // Otherwise hunt ports that answer to that number
                    // (groups.md §2) — replaces the adjacent `o` overflow run.
                    if (conn)
                        nogo(r);
                    else if (p_term && (p_cls == C_LINE || p_cls == C_OPER ||
                                        p_cls == C_REST || p_cls == C_SRC ||
                                        p_cnail)) begin
                        pair_or_listen(caller[r], called[r],
                                       (p_cls == C_SRC), ctx_clm[r]);
                        if (held != 6'd0) mst[r] <= M_CONSULT;
                        else begin
                            reg_release[r] <= 1'b1; mst[r] <= M_IDLE;
                        end
                        conn = 1'b1;
                    end else begin
                        // busy, empty, trunk, self, busy-out, … → answers-to
                        hunt_own_oos  <= p_none || p_oos;
                        hunt_own_busy <= p_busy || p_bout ||
                                         (!p_free && !p_none && !p_oos);
                        hunt_from_trunk <= ctx_clm[r];
                        hans[r] <= 1'b1; mst[r] <= M_WANT;
                    end
                end
                default: ;
                endcase
            end

            // =========== work that wants a free register ==================
            // A context given out this cycle is marked in pk at once, because
            // its stage only changes at the clock edge: without it a claim and
            // a call request in one cycle would both be handed the same register.

            // ---- the network unit asked for a register on a claimed trunk
            if (HAS_NET && net_att) begin
                pick = -1;
                for (r = 0; r < NREG; r = r + 1)
                    if (pick < 0 && mst[r] == M_IDLE && !reg_busy[r] && !pk[r]) pick = r;
                if (pick >= 0) begin
                    arb <= 1'b0;
                    reg_attach[pick] <= 1'b1; reg_port <= net_att_port; reg_src <= 6'd0;
                    caller[pick] <= net_att_port; mst[pick] <= M_LOCAL;
                    f1[pick] <= 1'b0; f2[pick] <= 1'b0;
                    hold[pick] <= 2'd3;
                    ctx_clm[pick] <= 1'b1;                   // claimed until release
                    pk[pick] = 1'b1; att = 1'b1;
                end else begin
                    // no register free: claimed, cannot complete -- the caller
                    // hears it at once (monitor.md 2).  CLAIM is already written.
                    push(net_att_port, NOGO, 1'b1, 1'b1);
                end
            end

            // ---- tied nail first (extensions.md 3.1) --------------------
            // One-sided two-write: this port and the dest.  Do not nail a
            // source (it would BUSY the radio).  A tied nail is never a caller.
            if (visit && p_valid && p_nail && !p_busy) begin
                push(p_port, p_nail_to, 1'b1, 1'b0);
                if (p_nail_to != p_port)
                    push(p_nail_to, p_port, 1'b1, 1'b0);
            end

            // ---- call nail / outside: probe warm_to, then answers-to
            if (warm_run && warm_probe && visit && p_valid && p_port == warm_to) begin
                if (p_term && (p_cls == C_LINE || p_cls == C_OPER ||
                               p_cls == C_REST || p_cls == C_SRC || p_cnail)) begin
                    pair_or_listen(warm_from, warm_to, (p_cls == C_SRC), 1'b0);
                    warm_run <= 1'b0; warm_probe <= 1'b0;
                end else if (!hunt_busy && !hb) begin
                    hunt_own_oos  <= p_none || p_oos;
                    hunt_own_busy <= p_busy || p_bout ||
                                     (!p_free && !p_none && !p_oos);
                    hunt_from_trunk <= 1'b0;
                    take_ans_hunt(4'hF, warm_to);
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
                if (p_cnail) begin
                    already = 1'b0;
                    for (r = 0; r < NREG; r = r + 1)
                        if (mst[r] != M_IDLE && caller[r] == p_port) already = 1'b1;
                    if (!already && !warm_run) begin
                        warm_from <= p_port; warm_to <= p_cnail_to;
                        warm_run <= 1'b1; warm_probe <= 1'b1;
                        push(p_port, 6'o00, 1'b1, 1'b0);
                    end
                end else if (p_cls == C_OUT) begin
                    // CO ringing in: as if dialled 0.
                    already = 1'b0;
                    for (r = 0; r < NREG; r = r + 1)
                        if (mst[r] != M_IDLE && caller[r] == p_port) already = 1'b1;
                    if (!already && !warm_run) begin
                        warm_from <= p_port; warm_to <= PILOT_0;
                        warm_run <= 1'b1; warm_probe <= 1'b1;
                        push(p_port, 6'o00, 1'b1, 1'b0);
                    end
                end else if (p_cls == C_LINE || p_cls == C_OPER ||
                             p_cls == C_REST || p_offers) begin
                    // a caller: the first free register.  None free, and the
                    // caller simply waits -- the scanner will be back in 8 ms.
                    // Under PWAIT, a non-priority line waits even with a free
                    // register until a full revolution finds no priority lift
                    // still wanting one (extensions.md 2.4.1).
                    // offers-tone trunks (leaf-uplink.md) take the same path.
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
