// debugger -- a listener card that lights a lamp when the exchange breaks a
// rule it cannot break while working.  MINIMAL+MAXIMAL.
//
// It has NO AUTHORITY.  It drives nothing but LEDs.  It sits anywhere on the
// bus (debugger.md §1), like a lamp field (proposed/lamps.md), reads the
// bus's timing, scan, planes and control lines, keeps its own copy of the
// scanner and of the last control word,
// and runs in lock-step with the exchange as an observer.  Every check is a
// handful of gates into one flip-flop, and the flip-flop is STICKY: a fault
// that lasted one master tick a week ago is still lit when someone looks.
// /CLR is a button.
//
// THE LAMPS ARE GROUPED BY SUSPECT.  A lamp does not say what went wrong; it
// says which board to pull.  Nothing here needs to know how many ports are
// fitted, which block is jumpered where, or what the marker is doing -- the
// facts it leans on are ones every build shares: port 00 is never fitted, a
// control word is sixteen bits, and the scanner steps on every frame edge.
// Two lamps lean on more: SCLK_COUNT on SCLK gated per word, and REG_WAIT on
// how many passes a lifted phone may wait, which is the one strap that
// depends on the build (debugger.md §6, §7).
//
//   CLOCK CARD
//     0  SCAN_STALL   SCAN did not step at a frame edge, or stepped off one.
//                     The scanner stopped.  This is the fault class the fold
//                     exists to make impossible; if it lights, the divider
//                     has grown an enable again
//     1  SLOTQ_LATE   SLOTQ != SLOT at a capture strobe: the '175 did not
//                     take, and every strobe decoder is off by a cell
//   THE PLANE -- the bus, a pull-up, or one block's drain
//     2  HA_P00       /HA pulled down in port 00's turn.  00 is never fitted
//                     (fabric.md §2.4), so nothing may ever drive its slot
//     3  HB_P00       the same on /HB
//     4  HA_STUCK     /HA low at every capture of a whole pass: a drain stuck
//                     on, or a short.  ONE conductor, ONE failure domain --
//                     newimpl/README.md 6 asked for this lamp by name.  Lights
//                     with HA_P00, necessarily
//     5  HB_STUCK     the same on /HB
//   THE CONTROL LINES -- the serialiser, the wiring, or the marker's sequencing
//     6  SCLK_COUNT   WR arrived with a shift count that is not a multiple of
//                     sixteen since the last WR: one extra or one missing
//                     SCLK edge.  This is bus.md §6.2's hazard -- one
//                     extra shift and the next write lands on the wrong
//                     port -- caught in the act.  Every word ends in WR since /WS took the reads
//                     off the bus, so a clean count is exactly sixteen
//     7  WR_EDGE      WR rose within a quarter bit-time of an SCLK edge, or
//                     an edge followed within that window: bus.md §4's
//                     one rule
//   THE MARKER
//     8  SELF_POINT   a write whose SRC is its DST: a port told to listen to
//                     itself.  No sequence in the marker produces this
//     9  WR_P00       a write to port 00
//    10  REG_WAIT     some port off-hook and not BUSY at the end of K passes
//                     running: it lifted and nobody took it.  With a pool of
//                     registers this is a marker fault.  With ONE register
//                     it is the register-queue lamp: it lights when a caller
//                     lifts while another holds the register -- dialling, or
//                     through a flood -- which is worth a lamp too
//
// THERE WAS A FILL_SCAN0 LAMP.  FILL and SCAN0 were one divider stage on two
// pins; since 2026-09-25 FILL has no pin -- it is SCAN0 wherever it is wanted
// (frame_decode.v) -- so there is nothing left to disagree.
//
// NOT HERE, AND WHY.  A write with G clear is the event word and is legal.
// /HW is not watched: a card drives it only after a /WS select in its port's
// bit-time (fabric.md §4), and this card does not know what any card's word
// should be (debugger.md §5).  A
// write to an UNFITTED port other than 00 needs the fitted map, which is
// sixty-four straps this card does not have.  A seizure of an already-busy
// port -- the glare the mini-marker's untested branch would produce -- needs
// last pass's /HB for the port just written, which is a 64-stage shift
// register (eight '164) and a compare at the right turn; it is the most
// valuable lamp not on this card and the first one to add.
//
//   debugger.md; bus.md §4, §6.2; fabric.md §3.2, §4; proposed/lamps.md
`timescale 1ns/1ps
`include "exch.vh"

module debugger #(
    // passes a lifted, unserved port may wait before REG_WAIT.  The marker
    // takes a port within about a pass and a word; sixteen is generous.
    parameter integer REG_WAIT_PASSES = 16,
    // master ticks either side of an SCLK edge that WR must keep clear of.
    // A bit-time is 32 at 128 kHz, so eight is a quarter: debugger.md §2's
    // strap, against bus.md §4's rule.
    parameter integer WR_GUARD        = 8
)(
    input                   clk,
    input                   rst_n,
    input                   clr_n,       // the button

    // ---- the bus: timing, scan and the planes ------------------------------
    input      [2:0]        slot,
    input      [2:0]        slotq,
    input                   cap_stb,
    input                   frame_stb,
    input      [`SCANW-1:0] scan,
    input                   ha_n,
    input                   hb_n,

    // ---- the bus: the control lines ----------------------------------------
    input                   sdata,
    input                   sclk,
    input                   wr,

    output reg [10:0]       led
);
    // The capture instant, as every port and every probe computes it.
    wire a_stb = cap_stb && (slotq == `CELL_A);

    // ---- edges --------------------------------------------------------------
    reg  sclk_d, wr_d;
    wire sclk_rise = sclk && !sclk_d;
    wire sclk_edge = sclk != sclk_d;
    wire wr_rise   = wr   && !wr_d;

    // ---- the scanner mirror: a '393 clocked by the frame edge ---------------
    // The clock card's own counter steps on the same edge, so during the
    // frame_stb tick SCAN is already new and the mirror is still old; the
    // compare skips that one tick and holds on every other.
    //
    // The reset state -- tick 0 of slot 0 -- reads as a frame edge that no
    // count preceded, so the first frame_stb after reset ARMS the mirror and
    // does not step it.  Step it there and the mirror is one ahead for ever,
    // and this lamp is lit on a working exchange, which is worse than no
    // lamp.  On the board the '393 and the '4040 stage share one edge and
    // one /RESET and have no such tick; this is the RTL strobe's artefact.
    reg [`SCANW-1:0] mscan;
    reg              armed;

    // ---- the pass boundary, off this card's own mirror ----------------------
    // TICK is SCAN5's fall and has no pin of its own.  Taken off the mirror
    // rather than off SCAN, so a stalled SCAN lights SCAN_STALL and does not
    // also stop the pass bookkeeping the other lamps judge by.  In step, this
    // is the same tick as the exchange's: during the frame_stb tick SCAN has
    // just gone to 00 and the mirror still reads 77.
    wire pass_stb = frame_stb && armed && (mscan == {`SCANW{1'b1}});

    // ---- the control word mirror: two '164, exactly as a block has --------
    reg [`CWW-1:0] cw;
    wire            w_g   = cw[`CWW-1];
    wire [`PW-1:0]  w_dst = cw[13:8];
    wire [`PW-1:0]  w_src = cw[7:2];

    // ---- SCLK edges since the last WR: a '163 -------------------------------
    // Modulo sixteen: one glitch shifts seventeen.  It was modulo on purpose
    // while a pointing word -- sixteen shifts with no WR -- made a legal
    // thirty-two; since /WS there is none, and exactly sixteen is the rule.
    reg [3:0] nshift;

    // ---- ticks since the last SCLK edge, saturating; and the window after WR
    reg [7:0] since_edge;
    reg [7:0] watch;

    // ---- the planes: was the wire seen released this pass? -----------------
    reg ha_seen_hi, hb_seen_hi;
    reg pass_valid;          // a whole pass has gone by since reset or /CLR

    // ---- REG_WAIT ------------------------------------------------------------
    reg          unserved;   // some port read M and not BUSY this pass
    reg  [15:0]  wait_passes;

    // ---- the checks, each one tick ------------------------------------------
    // A WR on the very tick of an SCLK edge is the worst case of the timing
    // rule and lights WR_EDGE, not SCLK_COUNT: the count judges that edge as
    // having arrived, so a sixteenth edge coincident with WR is still sixteen.
    wire [10:0] hit;
    assign hit[0]  = armed && !frame_stb && (scan != mscan);
    assign hit[1]  = cap_stb && (slotq != slot);
    assign hit[2]  = a_stb && (scan == {`SCANW{1'b0}}) && !ha_n;
    assign hit[3]  = a_stb && (scan == {`SCANW{1'b0}}) && !hb_n;
    assign hit[4]  = pass_stb && pass_valid && !ha_seen_hi;
    assign hit[5]  = pass_stb && pass_valid && !hb_seen_hi;
    assign hit[6]  = wr_rise && ((nshift + {3'b000, sclk_rise}) != 4'd0);
    assign hit[7]  = (wr_rise && (sclk_edge || (since_edge < WR_GUARD[7:0])))
                   || (sclk_edge && (watch != 8'd0));
    assign hit[8]  = wr_rise && w_g && (w_src == w_dst);
    assign hit[9]  = wr_rise && w_g && (w_dst == {`PW{1'b0}});
    assign hit[10] = pass_stb && unserved
                   && (wait_passes == REG_WAIT_PASSES[15:0] - 16'd1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sclk_d <= 1'b0; wr_d <= 1'b0;
            mscan <= {`SCANW{1'b0}}; armed <= 1'b0;
            cw <= {`CWW{1'b0}};
            nshift <= 4'd0; since_edge <= 8'd0; watch <= 8'd0;
            ha_seen_hi <= 1'b0; hb_seen_hi <= 1'b0; pass_valid <= 1'b0;
            unserved <= 1'b0; wait_passes <= 16'd0;
        end else begin
            sclk_d <= sclk;
            wr_d   <= wr;

            // the scanner mirror: the first frame edge arms it, the rest step it
            if (frame_stb) begin
                if (armed) mscan <= mscan + 1'b1;
                armed <= 1'b1;
            end

            // the word mirror, on the same edge a block's '164 takes it
            if (sclk_rise) cw <= {cw[`CWW-2:0], sdata};

            // the shift count.  WR wins over an edge on the same tick, and
            // that coincidence is itself a WR_EDGE fault
            if (wr_rise)        nshift <= 4'd0;
            else if (sclk_rise) nshift <= nshift + 1'b1;

            // the guard window either side of an SCLK edge
            if (sclk_edge)               since_edge <= 8'd0;
            else if (since_edge != 8'hFF) since_edge <= since_edge + 1'b1;
            if (wr_rise)                 watch <= WR_GUARD[7:0];
            else if (watch != 8'd0)      watch <= watch - 1'b1;

            // the planes: any capture that finds the wire released clears
            // the stuck suspicion for this pass
            if (a_stb && ha_n) ha_seen_hi <= 1'b1;
            if (a_stb && hb_n) hb_seen_hi <= 1'b1;

            // a lifted phone nobody has taken: M and not BUSY, in one turn
            if (a_stb && !ha_n && hb_n) unserved <= 1'b1;

            // the pass boundary: judge the pass, then start the next one.
            // pass_stb is a frame edge, never a capture, so nothing above
            // collides with this
            if (pass_stb) begin
                pass_valid <= 1'b1;
                ha_seen_hi <= 1'b0;
                hb_seen_hi <= 1'b0;
                if (unserved) begin
                    if (wait_passes != REG_WAIT_PASSES[15:0])
                        wait_passes <= wait_passes + 1'b1;
                end else wait_passes <= 16'd0;
                unserved <= 1'b0;
            end

            // /CLR restarts the pass bookkeeping too, so a lamp cleared
            // mid-pass is not relit by the half-pass it was cleared in
            if (!clr_n) begin
                pass_valid <= 1'b0; ha_seen_hi <= 1'b0; hb_seen_hi <= 1'b0;
                unserved <= 1'b0; wait_passes <= 16'd0;
            end
        end
    end

    // ---- the lamps: eleven sticky flip-flops, a '273 and a '175 ------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)      led <= 11'd0;
        else if (!clr_n) led <= 11'd0;
        else             led <= led | hit;
    end
endmodule
