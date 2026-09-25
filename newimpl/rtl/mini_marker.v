// mini_marker -- the small marker.  mini-marker.md.
//
// A marker that makes local calls on one exchange: two phones dial `h s`, one
// rings, they talk, either hangs up, and nobody is in charge of the call.  It
// reads M AND BUSY ONLY.  It never hunts a class, and one pulse collector
// lives inside it.
//
// THE HANDOFF.  The scanner is not this card's.  It is six stages of the
// clock card's divider and it free-runs at 64 kHz, a port every 15.63 us, a
// pass every 1 ms.  This marker holds one probe on SCAN and takes a port when
// it happens to be free; A PORT IT COULD NOT TAKE SIMPLY COMES ROUND AGAIN
// 1 ms LATER.  There is no count enable to clear, no visit to repeat, no
// validity bit and no re-point, because nothing this marker reads is steered
// by /BLK.  Compare mini_core.v:184 in the old tree, where the same loop
// needed `pv`, a probe-dirty flag and an interlock, and where a 64-port pass
// measured 72 visits.
//
// TWO RULES THAT ARE NOT OPTIONAL:
//   act on probe.port_q, NEVER on live SCAN -- by the time the sequencer has
//     decided, the scan has moved on.  rtl.md 1, in a new place;
//   do not return to IDLE with writes still queued -- the caller's BSY is
//     what stops it being seized a second time, a word takes 133 us and a
//     port comes round every 1 ms, so idling early seizes the same caller
//     twice.  THE SECOND CONDUCTOR HALVED THIS MARGIN: it was 133 us against
//     2 ms and is now 133 us against 1 ms, still seven words to a pass, but
//     the rule is now the one that would bite first if the word grew.
//
// ---- NETWORK: what a network unit adds (common-control.md 2.2, 4) ---------
//
// Fitted in top_net only.  In top_min every line below is tied to "no unit",
// and THE MARKER THEN TAKES EXACTLY THE PATH IT TOOK BEFORE THE NETWORK HALF
// EXISTED: /NET open, no word read, no yield, key 1 is highway 1.
//
//   /NET        the unit card grounds it.  Pulled up here, so an absent unit
//               reads absent -- the /ANS pattern, one fact from the board that
//               owns it, and NO PARAMETER (STYLE.md 4).  The old tree's
//               HAS_NET selected behaviour in an `if`
//   key 1       with /NET low: consumed at once, the register restarted, dial
//               tone dropped, flood_go.  The unit owns the call from there, and
//               the marker waits in YIELD for local, done or nogo
//   the word    with /NET low this marker READS A PORT'S CARD WORD before it
//               takes the port's M as a call, and before it connects a
//               dialled port.  A flood trunk's M is never a call request --
//               "leave this as M . /BUSY and a flood seizes a register at
//               every hop" -- and a trunk is never dialled.  THE CARD SAYS
//               WHAT IT IS; no jumper here or on the unit says it for the card
//   claim       the unit, having written a trunk's CLAIM, holds `att` until
//               this marker has either given the trunk the register as a
//               caller -- CLAIM kept on every later write to it -- or, with the
//               register busy, pointed it at cannot-complete with CLAIM set
//   cable B     the unit is a second master, ranked above this one.  /UREQ
//               low and this marker lets go between transactions
//
// The register and the unit share the ribbon of common-control.md 2.1: the
// unit taps digits, N, brk, gone, nodig and the caller, and its restart is
// ORed here with the key's.
`timescale 1ns/1ps
`include "exch.vh"

module mini_marker #(
    // Tones are ADDRESSES here, not hunts.  With no source card fitted the
    // caller hears silence, which is mvp.md 2's documented behaviour.
    parameter [`PW-1:0] DIALTONE = 6'o01,
    parameter [`PW-1:0] SILENCE  = 6'o00,
    parameter [`PW-1:0] NOGO     = 6'o03,
    parameter [8:0]     HIT      = 9'd8,
    parameter [8:0]     ID       = 9'd128,
    parameter [8:0]     CLR      = 9'd256,
    parameter [15:0]    NODIG    = 16'd10000   // register.md 6; see pulse_reg
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
    input                   hw_n,          // NETWORK: /HW, for the word read
    input                   ureq_n,        // NETWORK: the unit wants the bus.  Pulled up

    // ---- NETWORK: the unit's ribbon ------------------------------------------
    input                   net_n,         // /NET: the unit card is fitted.  Pulled up
    output reg              flood_go,      // one tick: key 1 consumed, the unit owns it
    input                   u_restart,     // one tick: own e b -- begin the store again
    input                   u_local,       // one tick: the call is local from here
    input                   u_done,        // one tick: caller <-> trunk written; free the register
    input                   u_nogo,        // one tick: cannot-complete this origin call
    input                   u_att,         // level: a claimed trunk wants the register
    input      [`PW-1:0]    u_att_port,
    output reg              att_ack,       // one tick: attached, or refused

    // ---- the probe, on the tap so a card can watch without the marker
    //      knowing what it is looking for (common-control.md 2.2) -----------
    //
    // `probe_fresh` IS NOT OPTIONAL ON THE TAP.  m and busy are levels held
    // for a whole pass, so a listener without it cannot tell a new sample from
    // the same one read again, and would count one seizure sixty-four times.
    // It is common-control.md 2.2's `visit` under the name the fold gave it.
    //
    // The tap still carries the marker's re-point: in S_PROBE and S_TAKE
    // p_addr is `called`, so a watcher sees the port freeze.  That is a wart,
    // and the fix is not to widen this -- it is for each listener to fit its
    // own probe, which the network unit does.
    output     [`PW-1:0]    probe_port,
    output                  probe_m,
    output                  probe_busy,
    output                  probe_fresh,

    // ---- the register's ribbon (common-control.md 2.1) ---------------------
    output                  reg_busy,
    output     [2:0]        reg_ndig,
    output     [15:0]       reg_digits,
    output     [`PW-1:0]    reg_port,      // NETWORK: the caller the register holds
    output                  reg_gone,      // NETWORK: CLR
    output                  reg_nodig,     // NETWORK: the no-digit timeout
    output                  reg_brk,       // NETWORK: one tick, a break counted

    // ---- this card's state, for a bench -----------------------------------
    output     [`PW-1:0]    caller_o,
    output     [`PW-1:0]    called_o,
    output reg [2:0]        state,
    output                  q_ovf          // the queue refused a write.  Must never light
);
    localparam [2:0] S_IDLE  = 3'd0, S_COLLECT = 3'd1, S_PROBE = 3'd2,
                     S_DRAIN = 3'd3, S_READ    = 3'd4, S_TAKE  = 3'd5,
                     S_YIELD = 3'd6;

    wire net = !net_n;

    // TICK is SCAN5's fall, and the bus carries no line of its own for it: the
    // 1 ms time base is the pass boundary, one gate on SCAN and the frame edge
    wire tick_1k = frame_stb && (scan == {`SCANW{1'b0}});

    // ---- the probe.  Two '157s pick its address: the scan, or the port we
    //      are about to act on.
    reg  [`PW-1:0] called;
    wire           hunt = (state != S_PROBE) && (state != S_TAKE);
    wire [`PW-1:0] p_addr = hunt ? scan : called;

    wire           p_m, p_busy, p_fresh;
    wire [`PW-1:0] p_port;
    probe u_probe (
        .clk(clk), .rst_n(rst_n), .slotq(slotq), .cap_stb(cap_stb),
        .frame_stb(frame_stb), .scan(scan), .ha_n(ha_n), .hb_n(hb_n),
        .port(p_addr),
        .m(p_m), .busy(p_busy), .port_q(p_port), .fresh(p_fresh));

    assign probe_port  = p_port;
    assign probe_m     = p_m;
    assign probe_busy  = p_busy;
    assign probe_fresh = p_fresh;

    // ---- one register, on this card (mini-marker.md 1) ---------------------
    reg              r_attach, r_release, r_restart;
    reg  [`PW-1:0]   r_port;
    wire             r_busy, r_gone, r_nodig, r_brk, r_counting, r_hook;
    wire [2:0]       r_ndig;
    wire [15:0]      r_digits;
    wire [`PW-1:0]   r_caller;

    pulse_reg #(.HIT(HIT), .ID(ID), .CLR(CLR), .NODIG(NODIG)) u_reg (
        .clk(clk), .rst_n(rst_n),
        .slotq(slotq), .cap_stb(cap_stb), .frame_stb(frame_stb),
        .scan(scan), .ha_n(ha_n), .hb_n(hb_n), .tick_1k(tick_1k),
        .attach(r_attach), .attach_port(r_port),
        .release_it(r_release), .restart(r_restart),
        .busy(r_busy), .port(r_caller), .ndig(r_ndig), .digits(r_digits),
        .gone(r_gone), .nodig(r_nodig), .brk(r_brk), .counting(r_counting),
        .hook(r_hook));

    assign reg_busy   = r_busy;
    assign reg_ndig   = r_ndig;
    assign reg_digits = r_digits;
    assign reg_port   = r_caller;
    assign reg_gone   = r_gone;
    assign reg_nodig  = r_nodig;
    assign reg_brk    = r_brk;

    // ---- protocol.md 5's digit rule, taken literally ------------------------
    // "A digit's value is the low three bits of the register's pulse count,
    // forced to 000 when bit 3 is set: three AND gates."  Ten pulses is 0, and
    // so are eight and nine -- which is exactly why 0, 8 and 9 are one test
    // on the first key.  Implemented as anything looser, a dialled 9 in an
    // address position reads as 1.
    wire [2:0] d0 = r_digits[3] ? 3'd0 : r_digits[2:0];
    wire [2:0] d1 = r_digits[7] ? 3'd0 : r_digits[6:4];

    // "8 and 9 are caught as service digits before they are ever an
    // address" (protocol.md 5) -- on the SECOND key too.  Folded, a
    // misdialled 2 8 rang 20: a wrong number, and from another exchange a
    // wrong number the caller cannot see.  Ten pulses is 0 and is an address;
    // 8, 9 and 11-15 are not.  A '85 and two gates on the count's top bits.
    wire [3:0] c1  = r_digits[7:4];
    wire       svc1 = (c1 == 4'd8) || (c1 == 4'd9) || (c1 > 4'd10);

    // ---- cable B: this card's queue, serialiser and word reader ------------
    // Eight deep: a caller's dial tone and dial-tone-off, a connect's two, and
    // a claim refused, all waiting behind a unit that holds the bus for a
    // whole hunt.  The sequencer looks at `room` before it pushes, so the
    // overflow flag is a check, not a behaviour.
    reg  [1:0]     push_v;           // slot 0 alone, or both: a connect
    reg  [29:0]    push_d;
    wire [4:0]     room;
    wire           q_empty;
    reg            rd_req;
    reg  [`PW-1:0] rd_port;
    wire           rd_done;
    wire [7:0]     rd_word;
    wire           q_pending, q_rd_busy, q_sent;

    ctl_queue #(.DEPTH(8), .NP(2)) u_q (
        .clk(clk), .rst_n(rst_n),
        .slotq(slotq), .cap_stb(cap_stb), .scan(scan),
        .sdata(sdata), .sclk(sclk), .wr(wr), .oe(b_oe), .hw_n(hw_n),
        .go(ureq_n), .pending(q_pending), .empty(q_empty),
        .push_v(push_v), .push_d(push_d), .room(room), .ovf(q_ovf),
        .rd_req(rd_req), .rd_port(rd_port), .rd_busy(q_rd_busy), .rd_done(rd_done),
        .rd_word(rd_word), .sent(q_sent));

    wire bus_idle = q_empty;

    // A flood trunk says so in its primary octet: class form, family 01,
    // member 0 -- 11 01 0 in wire order (extensions.md 2.2).  Its glare and
    // direction are the unit's business; to this marker it is only "not a
    // caller, not a number".  A tone trunk is member 1 and IS a caller at a
    // leaf's central (leaf-uplink.md), so it does not match.
    wire rd_trunk = (rd_word[4:0] == 5'b01011);

    function [14:0] ent(input [`PW-1:0] d, input [`PW-1:0] s, input b, input c);
        ent = {1'b1, c, b, s, d};
    endfunction

    reg [`PW-1:0] caller;
    reg [2:0]     hwy;
    reg           have_h;
    reg           ctx_clm;       // the caller is a claimed trunk: CLAIM on its writes
    reg           keyed;         // this call has used its key: a 1 now is no key
    reg           y_nogo;        // the unit's nogo, kept until there is room to act on it
    reg           rd_caller;     // the word being read is a caller candidate's
    reg [1:0]     hold;          // ticks for the unit's restart to land

    assign caller_o = caller;
    assign called_o = called;

    // A claim may be taken where the register is free and the sequencer is
    // not in the middle of a bus transaction of its own.
    wire att_take   = u_att && !att_ack && !r_busy &&
                      ((state == S_IDLE) || (state == S_TAKE) || (state == S_DRAIN));
    // ... and must be refused where the register is someone's -- but never on
    // the tick a read completes: rd_done is one tick, and a refusal taking
    // that tick would leave S_READ waiting for a strobe that has gone.
    wire att_refuse = u_att && !att_ack && r_busy && !rd_done;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; called <= {`PW{1'b0}}; caller <= {`PW{1'b0}};
            hwy <= 3'd0; have_h <= 1'b0; ctx_clm <= 1'b0; rd_caller <= 1'b0;
            keyed <= 1'b0; y_nogo <= 1'b0;
            hold <= 2'd0;
            r_attach <= 1'b0; r_release <= 1'b0; r_restart <= 1'b0;
            r_port <= {`PW{1'b0}};
            push_v <= 2'd0; push_d <= 30'd0;
            rd_req <= 1'b0; rd_port <= {`PW{1'b0}};
            flood_go <= 1'b0; att_ack <= 1'b0;
        end else begin
            r_attach  <= 1'b0;
            r_release <= 1'b0;
            // the unit's own-code restart is ORed with the key's, here
            r_restart <= u_restart;
            push_v    <= 2'd0;
            rd_req    <= 1'b0;
            flood_go  <= 1'b0;
            att_ack   <= 1'b0;

            if (att_take) begin
                // ---- NETWORK: a claimed trunk is given the register ----------
                // It becomes a caller like any line, with no dial tone -- the
                // far caller is already dialling h s -- and CLAIM on every
                // write to it from here to its release.  It takes priority
                // over a local caller: that one comes round again in 1 ms.
                caller   <= u_att_port;
                r_port   <= u_att_port;
                r_attach <= 1'b1;
                ctx_clm  <= 1'b1;
                keyed    <= 1'b0;
                have_h   <= 1'b0;
                hold     <= 2'd0;
                att_ack  <= 1'b1;
                state    <= S_COLLECT;
            end else if (att_refuse && (room >= 5'd1) &&
                         !(u_local || u_done || u_nogo)) begin
                // "Claimed, cannot complete" -- the caller hears it at once
                // through the path already up.  The unit's CLAIM word has gone
                // out before `att` rose, so this lands after it.
                push_v <= 2'b01;
                push_d <= {15'd0, ent(u_att_port, NOGO, 1'b1, 1'b1)};
                att_ack <= 1'b1;
            end else case (state)
            // ---- IDLE: take a port off the scan when one is offered --------
            S_IDLE: begin
                have_h  <= 1'b0;
                ctx_clm <= 1'b0;
                keyed   <= 1'b0;
                y_nogo  <= 1'b0;
                // A call request is M and not BUSY.  That is the whole rule --
                // on an exchange with no unit.
                if (p_fresh && p_m && !p_busy && !r_busy && bus_idle) begin
                    if (net) begin
                        // NETWORK: ask the card first.  A flood trunk's M is
                        // the unit's, never a caller's.
                        called    <= p_port;      // port_q, NOT scan
                        rd_port   <= p_port;
                        rd_req    <= 1'b1;
                        rd_caller <= 1'b1;
                        state     <= S_READ;
                    end else begin
                        caller   <= p_port;      // port_q, NOT scan
                        r_port   <= p_port;
                        r_attach <= 1'b1;
                        push_v   <= 2'b01;
                        push_d   <= {15'd0, ent(p_port, DIALTONE, 1'b1, 1'b0)};
                        state    <= S_COLLECT;
                    end
                end
            end

            // ---- NETWORK: READ a port's word, for a caller or a called -----
            S_READ: if (rd_done) begin
                if (rd_caller) begin
                    // a trunk is left to the unit, and so is a port that says
                    // NONE -- a card held off by its power-up RC, out of
                    // service, or a trunk whose link is down.  A line's word
                    // is all ones.  Anything else is taken if it is still
                    // asking when it comes round.
                    state <= (rd_trunk || (rd_word == 8'd0)) ? S_IDLE : S_TAKE;
                end else if (rd_trunk) begin
                    // a trunk is never dialled: marker.md 2
                    if (room >= 5'd1) begin
                        push_v    <= 2'b01;
                        push_d    <= {15'd0, ent(caller, NOGO, 1'b1, ctx_clm)};
                        r_release <= 1'b1;
                        state     <= S_DRAIN;
                    end
                    // no room: rd_done is gone, so read again
                    else begin rd_req <= 1'b1; rd_port <= called; end
                end else state <= S_PROBE;
            end

            // ---- NETWORK: the caller candidate, once more --------------------
            // Its word said "not a trunk".  The read took a quarter of a pass,
            // so look again before taking it: it may have hung up, or been
            // taken, in between.
            S_TAKE: if (p_fresh && (p_port == called)) begin
                if (p_m && !p_busy && !r_busy && bus_idle) begin
                    caller   <= called;
                    r_port   <= called;
                    r_attach <= 1'b1;
                    push_v   <= 2'b01;
                    push_d   <= {15'd0, ent(called, DIALTONE, 1'b1, 1'b0)};
                    state    <= S_COLLECT;
                end else state <= S_IDLE;
            end

            // ---- COLLECT: two digits, octal as dialled ---------------------
            S_COLLECT: if (hold != 2'd0) hold <= hold - 2'd1;
            else if (r_gone) begin
                // hang-up mid-dial is abandon: no latch left pointing at 03
                if (room >= 5'd1) begin
                    push_v    <= 2'b01;
                    push_d    <= {15'd0, ent(caller, SILENCE, 1'b0, 1'b0)};
                    r_release <= 1'b1;
                    state     <= S_DRAIN;
                end
            end else if (r_nodig) begin
                if (room >= 5'd1) begin
                    push_v    <= 2'b01;
                    push_d    <= {15'd0, ent(caller, NOGO, 1'b1, ctx_clm)};
                    r_release <= 1'b1;
                    state     <= S_DRAIN;
                end
            end else if (!have_h && (r_ndig >= 3'd1)) begin
                if (room >= 5'd1) begin
                    push_v <= 2'b01;
                    if ((d0 == 3'd1) && net && !r_digits[3]) begin
                        // ---- NETWORK: key 1 is the flood ------------------
                        // Consumed at once, the store restarted so e b h s
                        // land in slots 0-3, dial tone off -- and the unit
                        // owns the call.  A claimed trunk dialling 1 would
                        // send a new flood back up the link it came in on;
                        // and after the call's own code has turned it local,
                        // h = 1 is a trunk's highway, not a second key.  Both
                        // refused.
                        if (ctx_clm || keyed) begin
                            push_d    <= {15'd0, ent(caller, NOGO, 1'b1, ctx_clm)};
                            r_release <= 1'b1;
                            state     <= S_DRAIN;
                        end else begin
                            push_d    <= {15'd0, ent(caller, SILENCE, 1'b1, 1'b0)};
                            r_restart <= 1'b1;
                            flood_go  <= 1'b1;
                            keyed     <= 1'b1;
                            state     <= S_YIELD;
                        end
                    end else if (d0 == 3'd0) begin
                        // 0, 8 and 9 all fold to 0 by the digit rule, and all
                        // three are cannot-complete on the first key.
                        push_d    <= {15'd0, ent(caller, NOGO, 1'b1, ctx_clm)};
                        r_release <= 1'b1;
                        state     <= S_DRAIN;
                    end else begin
                        hwy    <= d0;
                        have_h <= 1'b1;
                        push_d <= {15'd0, ent(caller, SILENCE, 1'b1, ctx_clm)};  // dial tone off
                    end
                end
            end else if (have_h && (r_ndig >= 3'd2)) begin
                if (svc1) begin
                    if (room >= 5'd1) begin
                        push_v    <= 2'b01;
                        push_d    <= {15'd0, ent(caller, NOGO, 1'b1, ctx_clm)};
                        r_release <= 1'b1;
                        state     <= S_DRAIN;
                    end
                end else begin
                    called <= {hwy, d1};
                    if (net) begin
                        rd_port   <= {hwy, d1};
                        rd_req    <= 1'b1;
                        rd_caller <= 1'b0;
                        state     <= S_READ;
                    end else state <= S_PROBE;
                end
            end

            // ---- PROBE: visit the called port ------------------------------
            S_PROBE: begin
                if (r_gone) begin
                    if (room >= 5'd1) begin
                        push_v    <= 2'b01;
                        push_d    <= {15'd0, ent(caller, SILENCE, 1'b0, 1'b0)};
                        r_release <= 1'b1;
                        state     <= S_DRAIN;
                    end
                end else if (p_fresh && (p_port == called) && (room >= 5'd2)) begin
                    if ((called == caller) || p_m || p_busy) begin
                        push_v    <= 2'b01;
                        push_d    <= {15'd0, ent(caller, NOGO, 1'b1, ctx_clm)};
                        r_release <= 1'b1;
                        state     <= S_DRAIN;
                    end else begin
                        // A connection is two writes, and the marker is
                        // finished with the call.  Ringing, ringback, answer
                        // and release are the ports' own.  They go in one
                        // tick, in this order, and nothing of this card's can
                        // come between them; a unit's word may, and touches
                        // neither port.
                        push_v    <= 2'b11;
                        push_d    <= {ent(called, caller, 1'b1, 1'b0),
                                      ent(caller, called, 1'b1, ctx_clm)};
                        r_release <= 1'b1;
                        state     <= S_DRAIN;
                    end
                end
            end

            // ---- NETWORK: YIELD -- the unit has the call -----------------------
            S_YIELD: begin
                if (r_gone) begin
                    if (room >= 5'd1) begin
                        push_v    <= 2'b01;
                        push_d    <= {15'd0, ent(caller, SILENCE, 1'b0, 1'b0)};
                        r_release <= 1'b1;
                        state     <= S_DRAIN;
                    end
                end else if (u_local) begin
                    // own e b: the unit restarted the store; h s follow as a
                    // local number.  Two ticks for the restart to land before
                    // the digit count is believed again.
                    have_h <= 1'b0;
                    hold   <= 2'd3;
                    state  <= S_COLLECT;
                end else if (u_done) begin
                    // the unit wrote caller <-> trunk
                    r_release <= 1'b1;
                    state     <= S_DRAIN;
                end else if (u_nogo || y_nogo || r_nodig) begin
                    // u_nogo is one tick; kept in y_nogo until there is room
                    y_nogo <= 1'b1;
                    if (room >= 5'd1) begin
                        push_v    <= 2'b01;
                        push_d    <= {15'd0, ent(caller, NOGO, 1'b1, 1'b0)};
                        r_release <= 1'b1;
                        state     <= S_DRAIN;
                    end
                end
            end

            // ---- DRAIN: the caller's BSY must be on the wire before we
            //      could possibly seize it again ------------------------------
            S_DRAIN: if (bus_idle) state <= S_IDLE;

            default: state <= S_IDLE;
            endcase
        end
    end

    // the word's glare and direction are the unit's; the queue's own status
    // lines are for a card that shares the bus more than this one does
    wire _unused = &{1'b0, r_counting, r_hook, rd_word[7:5], q_pending,
                     q_rd_busy, q_sent, 1'b0};
endmodule
