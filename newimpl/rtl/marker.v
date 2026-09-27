// marker -- the class marker.  marker.md §4; card-word.md §2, §4-§6;
// register.md §3; network.md §3.6.  MAXIMAL.
//
// The mini marker's sequencer, and what a port's card says about it.  Every
// decision the mini marker makes on M and BUSY alone, this one makes on M,
// BUSY AND THE CARD'S WORD: who may lift for a register, what a dialled
// number reaches, where a failed number is hunted, which lines go first when
// the register is short.  It holds nothing about the exchange -- no route
// table, no translation, no record of where anything is.  Move a card and its
// role moves with it (marker.md §1).
//
// IT READS A WORD ONLY WHEN IT NEEDS ONE.  A read is a select on /WS in the
// port's own bit-time and eight frames of /HW (word_rx.v), and every reader
// waits out any other reader's eight frames.  A marker that walked every port
// in order, a word a pass, would hold off the network unit's reads -- its
// select moves one port a pass while the unit's target stays put, so a unit
// read could wait eight passes, and a transit's hop grow from about 12 ms to
// about 28, the 128 ms guard covering four hops instead of ten.  So this card
// reads:
//   one port every WALK passes, always -- the WALK, below;
//   the dialled port's word, before it connects it;
//   every port in turn, from 01, only while a HUNT runs -- 0, 9, a busy number.
//
// THE WALK IS THE ONLY WAY IN.  It reads the next port in order whatever the
// last one said, and takes every decision about a port at that read, as the
// scanning marker took them at its visit:
//   a tied nail whose port has released (card-word.md §6.1) -- one write,
//     the port listening to its dest.  A NAIL IS ONE WAY (Joel, 2026-09-26):
//     the dest is not written, so it is made whatever the dest is doing, and
//     a source may be nailed.  A private line is a nail on each card, each
//     naming the other, and neither end is ever a caller;
//   a caller -- M up and BUSY clear at the select, a word that may call, the
//     register free and this card idle -- is given the register there and then;
//   a call nail and a CO line ringing in the same, as if dialled or as 0.
// Anything else is passed over and seen again a round later.  Nothing is read
// out of turn, so NOTHING NEEDS REMEMBERING: a data line off-hook, a trunk
// before the unit holds it, a card in its power-up RC is read once a round
// like every other port.  A read of whoever lifts, the mini marker's way,
// re-reads such a port every other pass and shadows the seven behind it,
// which a 64-bit "dealt with" memory had to prevent (Joel, 2026-09-25).  A
// round is 63 x WALK passes: the longest a caller waits for dial tone.
//
// PRIORITY, as marker.md §4.3 writes it.  PWAIT: a round that finds a P
// line wanting the register and not getting it sets it at 77; a round that
// finds none clears it.  While it is set the walk passes over any caller but
// a P line, the register free or not.  Passing a caller over costs nothing:
// the walk comes back to it anyway.
//
// THREE RULES THAT ARE NOT OPTIONAL (the mini marker's):
//   act on the latched port -- the probe's port_q, the reader's rd_port --
//     never on live SCAN;
//   do not return to IDLE with writes still queued -- the caller's BSY is
//     what stops it being seized twice;
//   do not let go of a connected call until the called port could let go of
//     it -- WATCH, as mini_marker's, on the register this card holds.  A call
//     nail and a CO line ringing in take the register for exactly that, and
//     for nothing else.
//
// A BUSY LINE GETS BUSY TONE (Joel, 2026-09-25; numbering.md §4): a dialled
// voice line that is BUSY, off-hook or busy-out, when nobody free answers to
// its number, is pointed at 02.  Everything else that fails is cannot-complete,
// 03 -- an empty or out-of-service slot, a trunk, a data line, the caller's
// own number, a 9 with no free outside line.
//
// ---- NETWORK: the mini marker's network half, unchanged ----------------------
//   /NET        low: key 1 is the flood -- consumed, the register restarted,
//               flood_go -- and the unit owns the call until local, done or nogo
//   claim       `att` held by the unit: a free register is given to the trunk as
//               a caller, CLAIM on every write to it; a busy one is refused with
//               cannot-complete, CLAIM set -- but not in WATCH, which a claim
//               waits out
//   cable B     the unit ranks above this card: /UREQ low and it lets go
//               between transactions
// Restricted callers never open a flood (card-word.md §4's floor).
//
// ---- WHAT IT DOES NOT DO -----------------------------------------------------
// One register (a pool wants a bank a register on the unit, README 6).  The
// word's primary octet only: no covers, no dual numbers, no L/U/K conditions.
// No console, no event words for a counter card, no operator transfer.
//
//   marker.md §1-§6; card-word.md §2, §4-§6; numbering.md §2-§4;
//   features.md §1, §4, §5; register.md §3; network.md §3.6
`timescale 1ns/1ps
`include "exch.vh"

module marker #(
    // Tones are ADDRESSES (numbering.md §2, features.md §1).  With no source card
    // at one of them, the caller hears silence there.
    parameter [`PW-1:0] SILENCE  = 6'o00,
    parameter [`PW-1:0] DIALTONE = 6'o01,
    parameter [`PW-1:0] BUSYTONE = 6'o02,
    parameter [`PW-1:0] NOGO     = 6'o03,
    // 0 calls 04, then whoever answers to it (numbering.md §3, marker.md §4.5)
    parameter [`PW-1:0] PILOT_0  = 6'o04,
    // the walk's pace: passes between its reads.  A tap of the pass counter;
    // 4 is a round of the 63 ports in about a quarter second, the longest a
    // caller waits for dial tone.  Never 1: a read every pass drifts one port
    // a pass, and a unit read can wait out eight passes behind it
    parameter [4:0]     WALK     = 5'd4
)(
    input                   clk,
    input                   rst_n,

    // ---- the bus: timing, scan and the planes ------------------------------
    input      [2:0]        slotq,
    input                   cap_stb,
    input                   frame_stb,
    input      [`SCANW-1:0] scan,
    input                   ha_n,          // M
    input                   hb_n,          // BUSY, the same bit-time

    // ---- the bus: the control lines, as a master ---------------------------
    output                  sdata,
    output                  sclk,
    output                  wr,
    output                  b_oe,          // this card's '244s are driving it
    input                   hw_n,          // /HW, for the word reads
    input                   ws_n,          // /WS as received: anybody's select
    output                  ws_pd,         // this card's select, onto /WS
    input                   ureq_n,        // NETWORK: the unit wants the bus.  Pulled up

    // ---- the register's ribbon (register.md §3) ----------------------------
    output reg              reg_attach,    // one tick: seize it for reg_port
    output reg [`PW-1:0]    reg_port,
    output reg              reg_release,
    output reg              reg_restart,   // this card's, ORed with the unit's
    input                   r_busy,
    input      [2:0]        r_ndig,
    input      [15:0]       r_digits,
    input                   r_gone,
    input                   r_nodig,
    input                   r_settled,
    input                   r_hook,        // the caller off-hook, as the register sees it

    // ---- NETWORK: the unit's ribbon ------------------------------------------
    input                   net_n,         // /NET: the unit card is fitted.  Pulled up
    output reg              flood_go,
    input                   u_restart,
    input                   u_local,
    input                   u_done,
    input                   u_nogo,
    input                   u_att,         // level: a claimed trunk wants the register
    input      [`PW-1:0]    u_att_port,
    output reg              att_ack,

    // ---- this card's state, for a bench -----------------------------------
    output     [`PW-1:0]    caller_o,
    output     [`PW-1:0]    called_o,
    output reg [3:0]        state,
    output                  pwait_o,
    output                  q_ovf          // the queue refused a write.  Must never light
);
    // 4'd1 was S_READ, a read of whoever lifted: the walk does it now
    localparam [3:0] S_IDLE  = 4'd0,                     S_COLLECT = 4'd2,
                     S_CALLED = 4'd3, S_HUNT  = 4'd4, S_WATCH   = 4'd5,
                     S_YIELD = 4'd6, S_DRAIN  = 4'd7, S_NAIL    = 4'd8;
    localparam [`PW-1:0] P00 = 6'o00, P01 = 6'o01, P77 = 6'o77;

    wire net = !net_n;

    // TICK is SCAN5's fall; the bus carries no line of its own for it
    wire tick_1k = frame_stb && (scan == {`SCANW{1'b0}});

    // ---- the probe, on SCAN: every port's M and BUSY, every pass -----------
    // It is never re-pointed.  What the sequencer wants of one port it takes
    // at that port's turn, `port_q` in hand.
    wire           p_m, p_busy, p_fresh;
    wire [`PW-1:0] p_port;
    probe u_probe (
        .clk(clk), .rst_n(rst_n), .slotq(slotq), .cap_stb(cap_stb),
        .frame_stb(frame_stb), .scan(scan), .ha_n(ha_n), .hb_n(hb_n),
        .port(scan),
        .m(p_m), .busy(p_busy), .port_q(p_port), .fresh(p_fresh));

    // ---- cable B: this card's queue and serialiser -------------------------
    reg  [1:0]     push_v;           // slot 0 alone, or both: a connect
    reg  [29:0]    push_d;
    wire [4:0]     room;
    wire           q_empty, q_pending, q_sent;

    ctl_queue #(.DEPTH(8), .NP(2)) u_q (
        .clk(clk), .rst_n(rst_n),
        .sdata(sdata), .sclk(sclk), .wr(wr), .oe(b_oe),
        .go(ureq_n), .pending(q_pending), .empty(q_empty),
        .push_v(push_v), .push_d(push_d), .room(room), .ovf(q_ovf),
        .sent(q_sent));

    wire bus_idle = q_empty;

    // ---- the word reader: one, shared by the sequencer and the walk ---------
    reg            rd_req;
    reg  [`PW-1:0] rd_port;
    reg            rd_own;          // 0 the sequencer's read, 1 the walk's
    wire           rd_done, rd_busy;
    wire [7:0]     rd_word;
    word_rx u_rd (
        .clk(clk), .rst_n(rst_n),
        .slotq(slotq), .cap_stb(cap_stb), .frame_stb(frame_stb), .scan(scan),
        .hw_n(hw_n), .ws_n(ws_n), .ws_pd(ws_pd),
        .rd_req(rd_req), .rd_port(rd_port), .busy(rd_busy), .done(rd_done),
        .word(rd_word));

    wire rd_free = !rd_busy && !rd_req;

    // THE PORT'S M AND BUSY AT ITS SELECT, kept with its word.  The probe
    // publishes a port's pair at the start of the frame after its turn --
    // the turn the select was made in -- while the read is still taking its
    // eight frames; the last pair of that port before `done` is the select's.
    reg s_m, s_b;

    // ---- what the word says ---------------------------------------------------
    wire           d_none, d_oos, d_plain, d_line, d_rest, d_src, d_out, d_trunk;
    wire           d_tone, d_tnail, d_ans, d_cnail, d_pri, d_bout, d_data;
    wire           d_zonly, d_voice, d_caller;
    wire [`PW-1:0] d_hs;
    word_dec u_dec (
        .w(rd_word), .none(d_none), .oos(d_oos), .plain(d_plain), .line(d_line),
        .rest(d_rest), .src(d_src), .out(d_out), .trunk(d_trunk), .tone(d_tone),
        .tnail(d_tnail), .ans(d_ans), .cnail(d_cnail), .hs(d_hs), .pri(d_pri),
        .bout(d_bout), .data(d_data), .zonly(d_zonly), .voice(d_voice),
        .caller(d_caller));

    function [14:0] ent(input [`PW-1:0] d, input [`PW-1:0] s, input b, input c);
        ent = {1'b1, c, b, s, d};
    endfunction

    // ---- numbering.md §1's digits, as the raw counts ------------------------
    // The mini marker folds 8, 9 and 10 to 0 and refuses all three.  Here the
    // count decides: ten pulses is the operator, nine an outside line, eight
    // and 11-15 are service digits.  In an address position ten is 0.
    wire [3:0] c0   = r_digits[3:0];
    wire [3:0] c1   = r_digits[7:4];
    wire [2:0] v1   = c1[3] ? 3'd0 : c1[2:0];
    wire       svc1 = (c1 == 4'd8) || (c1 == 4'd9) || (c1 > 4'd10);

    // ---- one call ------------------------------------------------------------
    reg [`PW-1:0] caller, called;
    reg [2:0]     hwy;
    reg           have_h;
    reg           ctx_clm;       // the caller is a claimed trunk: CLAIM on its writes
    reg           keyed;         // this call has used its key: a 1 now is no key
    reg           y_nogo;        // the unit's nogo, kept until there is room
    reg [1:0]     hold;          // ticks for the unit's restart to land
    reg           lim_z;         // restricted, z: only 0 completes
    reg           lim_local;     // restricted without z: no 9 and no flood
    reg           own_busy;      // the number's own port was a voice line, not free
    reg           h_ans;         // the hunt: 1 answers-to h_num, 0 class outside line
    reg [`PW-1:0] h_num, h_p;
    reg           rd_on;         // the sequencer's read is out

    assign caller_o = caller;
    assign called_o = called;

    // ---- the walk ------------------------------------------------------------
    reg [`PW-1:0] wq;            // the port it reads next: a '161 and a half
    reg [4:0]     wgap;          // passes since its last read
    reg           w_on;          // its read is out
    reg           nail_v;        // a tied nail found unmade, for the sequencer
    reg [`PW-1:0] nail_p, nail_d;
    reg           pwait, pwait_seen;     // marker.md §4.3: two flip-flops
    assign pwait_o = pwait;

    // The walk reads when the sequencer is not reading: never in CALLED, HUNT
    // or NAIL, and not while a nail it found is still to be made.
    wire w_state = (state == S_IDLE) || (state == S_COLLECT) || (state == S_YIELD) ||
                   (state == S_WATCH) || (state == S_DRAIN);
    wire w_issue = w_state && (wgap >= WALK) && !w_on && rd_free && !nail_v;

    // A claim may be taken where the register is free and the sequencer is
    // between calls; it must be refused where the register is someone's --
    // never on the tick a read completes, and at once in WATCH (mini_marker).
    wire att_take   = u_att && !att_ack && !r_busy &&
                      ((state == S_IDLE) || (state == S_DRAIN));
    wire att_refuse = u_att && !att_ack && r_busy && !rd_done;

    // The walk's own read: what it says, taken apart where it lands, with the
    // port's M and BUSY at its select.
    wire w_done  = rd_done && rd_own;
    wire w_ask   = s_m && !s_b;                                // off-hook, not BUSY
    wire w_nail  = d_tnail && !s_b && (d_hs != rd_port);       // a nail unmade
    wire w_pline = w_ask && d_caller && d_pri;                 // a P line wanting
    // Taken at its read: this card idle, the register free, nothing of this
    // card's queued, and no claim this tick.  Under PWAIT a caller must be a P
    // line.  A call nail and a CO line take the register only for the watch
    // after their connect, and PWAIT does not hold them.
    wire w_take  = w_done && (state == S_IDLE) && !att_take && !r_busy &&
                   bus_idle && (room >= 5'd1) && w_ask &&
                   ((d_caller && (d_pri || !pwait)) || d_cnail || d_out);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; caller <= P00; called <= P00;
            hwy <= 3'd0; have_h <= 1'b0; ctx_clm <= 1'b0; keyed <= 1'b0;
            y_nogo <= 1'b0; hold <= 2'd0; lim_z <= 1'b0; lim_local <= 1'b0;
            own_busy <= 1'b0; h_ans <= 1'b0; h_num <= P00; h_p <= P01; rd_on <= 1'b0;
            reg_attach <= 1'b0; reg_port <= P00; reg_release <= 1'b0; reg_restart <= 1'b0;
            push_v <= 2'd0; push_d <= 30'd0;
            rd_req <= 1'b0; rd_port <= P00; rd_own <= 1'b0; s_m <= 1'b0; s_b <= 1'b0;
            flood_go <= 1'b0; att_ack <= 1'b0;
            wq <= P01; wgap <= 5'd0; w_on <= 1'b0; pwait <= 1'b0; pwait_seen <= 1'b0;
            nail_v <= 1'b0; nail_p <= P00; nail_d <= P00;
        end else begin
            reg_attach  <= 1'b0;
            reg_release <= 1'b0;
            // the unit's own-code restart is ORed with this card's, here
            reg_restart <= u_restart;
            push_v      <= 2'd0;
            rd_req      <= 1'b0;
            flood_go    <= 1'b0;
            att_ack     <= 1'b0;

            // ---- the pair at the select, for whichever read is out ------------
            if (rd_busy && p_fresh && (p_port == rd_port)) begin s_m <= p_m; s_b <= p_busy; end
            if (rd_done && !rd_own) rd_on <= 1'b0;

            // ---- the walk -------------------------------------------------------
            if (tick_1k && !w_on && (wgap != 5'd31)) wgap <= wgap + 5'd1;
            if (w_issue) begin
                rd_req <= 1'b1; rd_port <= wq; rd_own <= 1'b1;
                w_on <= 1'b1; wgap <= 5'd0;
            end
            if (w_done) begin
                w_on <= 1'b0;
                if (w_nail) begin nail_v <= 1'b1; nail_p <= rd_port; nail_d <= d_hs; end
                if (w_pline && !w_take) pwait_seen <= 1'b1;
                // PWAIT (marker.md §4.3), closed at 77: set if the round
                // found a P line wanting the register and not getting it,
                // cleared by a round that found none
                if (wq == P77) begin
                    wq         <= P01;
                    pwait      <= pwait_seen || (w_pline && !w_take);
                    pwait_seen <= 1'b0;
                end else wq <= wq + 6'd1;
            end

            if (att_take) begin
                // ---- NETWORK: a claimed trunk is given the register ----------
                // A caller like any line, with no dial tone -- the far caller
                // is already dialling h s -- and CLAIM on every write to it.
                caller     <= u_att_port;
                reg_port   <= u_att_port;
                reg_attach <= 1'b1;
                ctx_clm    <= 1'b1;
                keyed      <= 1'b0;
                have_h     <= 1'b0;
                lim_z      <= 1'b0;
                lim_local  <= 1'b0;
                hold       <= 2'd0;
                att_ack    <= 1'b1;
                state      <= S_COLLECT;
            end else if (att_refuse && (room >= 5'd1) &&
                         !(u_local || u_done || u_nogo)) begin
                // "Claimed, cannot complete": the unit's CLAIM word went out
                // before `att` rose, so this lands after it.
                push_v  <= 2'b01;
                push_d  <= {15'd0, ent(u_att_port, NOGO, 1'b1, 1'b1)};
                att_ack <= 1'b1;
            end else case (state)
            // ---- IDLE: a nail to make, or a caller the walk has just read -----
            S_IDLE: begin
                have_h <= 1'b0; ctx_clm <= 1'b0; keyed <= 1'b0; y_nogo <= 1'b0;
                lim_z  <= 1'b0; lim_local <= 1'b0;
                if (nail_v && bus_idle) state <= S_NAIL;
                else if (w_take) begin
                    caller     <= rd_port;                // the read's port, NOT scan
                    reg_port   <= rd_port;
                    reg_attach <= 1'b1;
                    push_v     <= 2'b01;
                    if (d_caller) begin
                        push_d    <= {15'd0, ent(rd_port, DIALTONE, 1'b1, 1'b0)};
                        lim_z     <= d_zonly;
                        lim_local <= d_rest && !d_zonly;  // the floor: local only
                        state     <= S_COLLECT;
                    end else begin
                        // A CALL NAIL, or a CO LINE RINGING IN: as if `h s`, or
                        // 0, had been dialled, and no digits (marker.md §4.6,
                        // features.md §4).  The register is taken as the WATCH
                        // after the connect and for nothing else; the caller is
                        // held BUSY meanwhile.
                        push_d    <= {15'd0, ent(rd_port, SILENCE, 1'b1, 1'b0)};
                        called    <= d_cnail ? d_hs : PILOT_0;
                        state     <= S_CALLED;
                    end
                end
            end

            // ---- COLLECT: the key, and h s ----------------------------------------
            S_COLLECT: if (hold != 2'd0) hold <= hold - 2'd1;
            else if (r_gone) begin
                // hang-up mid-dial is abandon: no latch left pointing at a tone
                if (room >= 5'd1) begin
                    push_v      <= 2'b01;
                    push_d      <= {15'd0, ent(caller, SILENCE, 1'b0, 1'b0)};
                    reg_release <= 1'b1;
                    state       <= S_DRAIN;
                end
            end else if (r_nodig) begin
                // off-hook only: on-hook, the caller's port may have released
                // itself, and BSY would hold it for good (mini_marker)
                if ((room >= 5'd1) && r_hook) begin
                    push_v      <= 2'b01;
                    push_d      <= {15'd0, ent(caller, NOGO, 1'b1, ctx_clm)};
                    reg_release <= 1'b1;
                    state       <= S_DRAIN;
                end
            end else if (!have_h && (r_ndig >= 3'd1)) begin
                if (room >= 5'd1) begin
                    push_v <= 2'b01;
                    // dial tone off, whatever the key turns out to be
                    push_d <= {15'd0, ent(caller, SILENCE, 1'b1, ctx_clm)};
                    if ((lim_z && (c0 != 4'd10)) || (c0 == 4'd8) || (c0 > 4'd10) ||
                        (lim_local && (c0 == 4'd9))) begin
                        // z lets only 0 through; the floor refuses 9; 8 and
                        // 11-15 are service digits (card-word.md §4, numbering.md §1)
                        push_d      <= {15'd0, ent(caller, NOGO, 1'b1, ctx_clm)};
                        reg_release <= 1'b1;
                        state       <= S_DRAIN;
                    end else if ((c0 == 4'd1) && net) begin
                        // ---- NETWORK: key 1 is the flood ------------------------
                        // Refused from a claimed trunk (it would flood back up
                        // its own link), after the call's own code has made it
                        // local, and from a restricted card (the floor).
                        if (ctx_clm || keyed || lim_local) begin
                            push_d      <= {15'd0, ent(caller, NOGO, 1'b1, ctx_clm)};
                            reg_release <= 1'b1;
                            state       <= S_DRAIN;
                        end else begin
                            reg_restart <= 1'b1;
                            flood_go    <= 1'b1;
                            keyed       <= 1'b1;
                            state       <= S_YIELD;
                        end
                    end else if (c0 == 4'd10) begin
                        // 0: the operator's pilot, then whoever answers to it
                        called <= PILOT_0;
                        state  <= S_CALLED;
                    end else if (c0 == 4'd9) begin
                        // 9: the first free outside line, in slot order
                        h_ans    <= 1'b0;
                        h_p      <= P01;
                        own_busy <= 1'b0;
                        state    <= S_HUNT;
                    end else begin
                        // 2-7, or 1 with no unit fitted: the highway
                        hwy    <= c0[2:0];
                        have_h <= 1'b1;
                    end
                end
            end else if (have_h && (r_ndig >= 3'd2)) begin
                if (svc1) begin
                    if (room >= 5'd1) begin
                        push_v      <= 2'b01;
                        push_d      <= {15'd0, ent(caller, NOGO, 1'b1, ctx_clm)};
                        reg_release <= 1'b1;
                        state       <= S_DRAIN;
                    end
                end else begin
                    called <= {hwy, v1};
                    state  <= S_CALLED;
                end
            end

            // ---- CALLED: the number's own port ---------------------------------
            // Its word and its M and BUSY at the select.  A source is listened
            // to; a free voice line is connected; anything else is hunted for
            // among the ports that answer to the number (marker.md §4.5).
            S_CALLED: if (!rd_on) begin
                if (r_gone) begin
                    if (room >= 5'd1) begin
                        push_v      <= 2'b01;
                        push_d      <= {15'd0, ent(caller, SILENCE, 1'b0, 1'b0)};
                        reg_release <= 1'b1;
                        state       <= S_DRAIN;
                    end
                end else if (rd_free && (room >= 5'd4)) begin
                    rd_req <= 1'b1; rd_port <= called; rd_own <= 1'b0; rd_on <= 1'b1;
                end
            end else if (rd_done && !rd_own) begin
                if (r_gone) begin
                    // it is abandon, whatever the word said; `rd_on` falls
                    // above, and the branch before this one writes the caller
                end else if ((called != caller) && d_src) begin
                    // a source is listened to, never written (features.md §5)
                    push_v      <= 2'b01;
                    push_d      <= {15'd0, ent(caller, called, 1'b1, ctx_clm)};
                    reg_release <= 1'b1;
                    state       <= S_DRAIN;
                end else if ((called != caller) && d_voice && !s_m && !s_b && !d_bout) begin
                    // A connection is two writes, in this order, in one tick;
                    // then WATCH, until the called port can let go of it.
                    push_v <= 2'b11;
                    push_d <= {ent(called, caller, 1'b1, 1'b0),
                               ent(caller, called, 1'b1, ctx_clm)};
                    state  <= S_WATCH;
                end else begin
                    // Every other reason the probe fails: busy, ringing,
                    // busy-out, empty, out of service, a trunk, a data line,
                    // the caller's own number.  Busy tone at the end only for
                    // a voice line that was not free.
                    own_busy <= (called != caller) && d_voice && (s_m || s_b || d_bout);
                    h_ans    <= 1'b1;
                    h_num    <= called;
                    h_p      <= P01;
                    state    <= S_HUNT;
                end
            end

            // ---- HUNT: every port from 01, in slot order ---------------------------
            // The first that is free at its select and answers to the number --
            // or, for 9, is an outside line -- is taken at the read that finds
            // it (marker.md §4.5).  A read a pass: about 63 ms for a round.
            S_HUNT: if (!rd_on) begin
                if (r_gone) begin
                    if (room >= 5'd1) begin
                        push_v      <= 2'b01;
                        push_d      <= {15'd0, ent(caller, SILENCE, 1'b0, 1'b0)};
                        reg_release <= 1'b1;
                        state       <= S_DRAIN;
                    end
                end else if (rd_free && (room >= 5'd4)) begin
                    rd_req <= 1'b1; rd_port <= h_p; rd_own <= 1'b0; rd_on <= 1'b1;
                end
            end else if (rd_done && !rd_own && !r_gone) begin
                if (!s_m && !s_b && (h_p != caller) &&
                    (h_ans ? (d_ans && (d_hs == h_num)) : d_out)) begin
                    called <= h_p;
                    push_v <= 2'b11;
                    push_d <= {ent(h_p, caller, 1'b1, 1'b0),
                               ent(caller, h_p, 1'b1, ctx_clm)};
                    state  <= S_WATCH;
                end else if (h_p == P77) begin
                    push_v      <= 2'b01;
                    push_d      <= {15'd0, ent(caller, (h_ans && own_busy) ? BUSYTONE : NOGO,
                                               1'b1, ctx_clm)};
                    reg_release <= 1'b1;
                    state       <= S_DRAIN;
                end else h_p <= h_p + 6'd1;
            end

            // ---- WATCH: the caller, until the called port can let go --------
            // mini_marker's, word for word: the register stays on the caller
            // until it has been off-hook SETTLE ms from the connect, so the
            // called port's E detector has risen and it can release itself.
            // The caller gone first: write the called port free.  The line
            // chattering for the whole no-digit time: free both.
            S_WATCH: if (!bus_idle) reg_restart <= 1'b1;
            else if (r_gone || (r_nodig && r_hook)) begin
                if (room >= 5'd2) begin
                    push_v      <= r_gone ? 2'b01 : 2'b11;
                    push_d      <= {ent(caller, NOGO, 1'b1, ctx_clm),
                                    ent(called, SILENCE, 1'b0, 1'b0)};
                    reg_release <= 1'b1;
                    state       <= S_DRAIN;
                end
            end else if (r_settled) begin
                reg_release <= 1'b1;
                state       <= S_IDLE;
            end

            // ---- NETWORK: YIELD -- the unit has the call ---------------------------
            S_YIELD: begin
                if (r_gone) begin
                    if (room >= 5'd1) begin
                        push_v      <= 2'b01;
                        push_d      <= {15'd0, ent(caller, SILENCE, 1'b0, 1'b0)};
                        reg_release <= 1'b1;
                        state       <= S_DRAIN;
                    end
                end else if (u_local) begin
                    // own e b: the store restarted; h s follow as a local number
                    have_h <= 1'b0;
                    hold   <= 2'd3;
                    state  <= S_COLLECT;
                end else if (u_done) begin
                    reg_release <= 1'b1;
                    state       <= S_DRAIN;
                end else if (u_nogo || y_nogo || r_nodig) begin
                    y_nogo <= 1'b1;
                    if ((room >= 5'd1) && r_hook) begin
                        push_v      <= 2'b01;
                        push_d      <= {15'd0, ent(caller, NOGO, 1'b1, 1'b0)};
                        reg_release <= 1'b1;
                        state       <= S_DRAIN;
                    end
                end
            end

            // ---- NAIL: a tied nail the walk found unmade ------------------------
            // One write: the nail's port listens to its dest, BUSY (card-word.md
            // §6.1).  The dest is not written, so there is nothing to wait for.
            S_NAIL: if (room >= 5'd1) begin
                push_v <= 2'b01;
                push_d <= {15'd0, ent(nail_p, nail_d, 1'b1, 1'b0)};   // the nail's one write
                nail_v <= 1'b0;
                state  <= S_DRAIN;
            end

            // ---- DRAIN: the caller's BSY must be on the wire before we
            //      could possibly seize it again ------------------------------
            S_DRAIN: if (bus_idle) state <= S_IDLE;

            default: state <= S_IDLE;
            endcase
        end
    end

    // Class, glare and direction of a trunk are the unit's; what the other
    // outputs of the decode say is folded into the ones used above
    wire _unused = &{1'b0, q_pending, q_sent, r_digits[15:8], d_none, d_oos,
                     d_plain, d_line, d_trunk, d_tone, d_data, 1'b0};
endmodule
