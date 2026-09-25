// mini_marker -- the small marker.  mini-marker.md.
//
// A marker that makes local calls on one exchange: two phones dial `h s`, one
// rings, they talk, either hangs up, and nobody is in charge of the call.  It
// reads M AND BUSY ONLY.  It never looks at a card's option word, it never
// hunts a class, and one pulse collector lives inside it.
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

    // ---- cable A -----------------------------------------------------------
    input      [2:0]        slotq,
    input                   cap_stb,
    input                   frame_stb,
    input      [`SCANW-1:0] scan,
    input                   ha_n,          // M
    input                   hb_n,          // BUSY, the same bit-time
    input                   tick_1k,

    // ---- cable B, as its master --------------------------------------------
    output                  sdata,
    output                  sclk,
    output                  wr,

    // ---- the probe, on the tap so a card can watch without the marker
    //      knowing what it is looking for (common-control.md 2.2) -----------
    //
    // `probe_fresh` IS NOT OPTIONAL ON THE TAP.  m and busy are levels held
    // for a whole pass, so a listener without it cannot tell a new sample from
    // the same one read again, and would count one seizure sixty-four times.
    // It is common-control.md 2.2's `visit` under the name the fold gave it.
    //
    // The tap still carries the marker's re-point: in S_PROBE p_addr is
    // `called`, so a watcher sees the port freeze.  That is a wart, and the
    // fix is not to widen this -- it is for each listener to fit its own
    // probe, which is now one '688 and half a '74, as pulse_reg already does.
    output     [`PW-1:0]    probe_port,
    output                  probe_m,
    output                  probe_busy,
    output                  probe_fresh,

    // ---- the register's levels, and this card's state, for a bench --------
    output                  reg_busy,
    output     [2:0]        reg_ndig,
    output     [15:0]       reg_digits,
    output     [`PW-1:0]    caller_o,
    output     [`PW-1:0]    called_o,
    output reg [1:0]        state
);
    localparam [1:0] S_IDLE = 2'd0, S_COLLECT = 2'd1,
                     S_PROBE = 2'd2, S_DRAIN = 2'd3;

    // ---- the probe.  Two '157s pick its address: the scan, or the port we
    //      are about to act on.
    reg  [`PW-1:0] called;
    wire           hunt = (state != S_PROBE);
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

    // ---- protocol.md 5's digit rule, taken literally ------------------------
    // "A digit's value is the low three bits of the register's pulse count,
    // forced to 000 when bit 3 is set: three AND gates."  Ten pulses is 0, and
    // so are eight and nine -- which is exactly why 0, 8 and 9 are one test
    // on the first key.  Implemented as anything looser, a dialled 9 in an
    // address position reads as 1.
    wire [2:0] d0 = r_digits[3] ? 3'd0 : r_digits[2:0];
    wire [2:0] d1 = r_digits[7] ? 3'd0 : r_digits[6:4];

    // ---- the serialiser and a four-deep queue ------------------------------
    reg            ser_req;
    reg [`PW-1:0]  ser_dst, ser_src;
    reg            ser_bsy;
    wire           ser_busy;
    ctl_write u_ser (
        .clk(clk), .rst_n(rst_n), .req(ser_req), .strobe(1'b1), .g(1'b1),
        .dst(ser_dst), .src(ser_src), .bsy(ser_bsy), .clm(1'b0),
        .busy(ser_busy), .sdata(sdata), .sclk(sclk), .wr(wr));

    reg [12:0] wq [0:3];         // {dst, src, bsy}
    reg [1:0]  wh, wt;
    wire       wq_empty = (wh == wt);
    wire       bus_idle = wq_empty && !ser_busy && !ser_req;

    reg [`PW-1:0] caller;
    reg [2:0]     hwy;
    reg           have_h;

    assign caller_o = caller;
    assign called_o = called;

    // The tail moves with a BLOCKING assignment, on purpose: the two writes
    // of a connect are queued in the SAME cycle, which is what makes a
    // connection one action rather than two that something could interleave.
    // The head is nonblocking, as everything else here is.
    /* verilator lint_off BLKSEQ */
    task push(input [`PW-1:0] d, input [`PW-1:0] s, input b);
        begin
            wq[wt] = {d, s, b};
            wt     = wt + 2'd1;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; called <= {`PW{1'b0}}; caller <= {`PW{1'b0}};
            hwy <= 3'd0; have_h <= 1'b0;
            r_attach <= 1'b0; r_release <= 1'b0; r_restart <= 1'b0;
            r_port <= {`PW{1'b0}};
            ser_req <= 1'b0; ser_dst <= {`PW{1'b0}}; ser_src <= {`PW{1'b0}};
            ser_bsy <= 1'b0;
            wh <= 2'd0; wt = 2'd0;
        end else begin
            r_attach  <= 1'b0;
            r_release <= 1'b0;
            r_restart <= 1'b0;
            ser_req   <= 1'b0;

            // ---- drain, before anything pushes -----------------------------
            if (!ser_busy && !ser_req && !wq_empty) begin
                ser_dst <= wq[wh][12:7];
                ser_src <= wq[wh][6:1];
                ser_bsy <= wq[wh][0];
                ser_req <= 1'b1;
                wh      <= wh + 2'd1;
            end

            case (state)
            // ---- IDLE: take a port off the scan when one is offered --------
            S_IDLE: begin
                have_h <= 1'b0;
                // A call request is M and not BUSY.  That is the whole rule.
                if (p_fresh && p_m && !p_busy && !r_busy && bus_idle) begin
                    caller   <= p_port;      // port_q, NOT scan
                    r_port   <= p_port;
                    r_attach <= 1'b1;
                    push(p_port, DIALTONE, 1'b1);
                    state    <= S_COLLECT;
                end
            end

            // ---- COLLECT: two digits, octal as dialled ---------------------
            S_COLLECT: begin
                if (r_gone) begin
                    // hang-up mid-dial is abandon: no latch left pointing at 03
                    push(caller, SILENCE, 1'b0);
                    r_release <= 1'b1;
                    state     <= S_DRAIN;
                end else if (r_nodig) begin
                    push(caller, NOGO, 1'b1);
                    r_release <= 1'b1;
                    state     <= S_DRAIN;
                end else if (!have_h && (r_ndig >= 3'd1)) begin
                    if (d0 == 3'd0) begin
                        // 0, 8 and 9 all fold to 0 by the digit rule, and all
                        // three are cannot-complete on the first key.
                        push(caller, NOGO, 1'b1);
                        r_release <= 1'b1;
                        state     <= S_DRAIN;
                    end else begin
                        hwy    <= d0;
                        have_h <= 1'b1;
                        push(caller, SILENCE, 1'b1);   // dial tone off
                    end
                end else if (have_h && (r_ndig >= 3'd2)) begin
                    called <= {hwy, d1};
                    state  <= S_PROBE;
                end
            end

            // ---- PROBE: visit the called port ------------------------------
            S_PROBE: begin
                if (r_gone) begin
                    push(caller, SILENCE, 1'b0);
                    r_release <= 1'b1;
                    state     <= S_DRAIN;
                end else if (p_fresh && (p_port == called)) begin
                    if ((called == caller) || p_m || p_busy) begin
                        push(caller, NOGO, 1'b1);
                        r_release <= 1'b1;
                        state     <= S_DRAIN;
                    end else begin
                        // A connection is two writes, and the marker is
                        // finished with the call.  Ringing, ringback, answer
                        // and release are the ports' own.
                        push(caller, called, 1'b1);
                        push(called, caller, 1'b1);
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

    /* verilator lint_on BLKSEQ */

    wire _unused = &{1'b0, r_brk, r_counting, r_hook, r_caller, 1'b0};
endmodule
