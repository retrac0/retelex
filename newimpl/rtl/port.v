// port -- one of the 64 ports: the crosspoint (fabric.md 3.2) and the
// supervision (3.5).  About eight and a half packages, populated only with
// its card -- an unfitted slot leaves the commutator input pulled to FILL and
// none of this stuffed (fabric.md 5.1).
//
// The crosspoint is a '273 holding [ highway | slot ], a '151 to pick the
// highway, a second to pick the moment, a '74 pair to keep the answers, and
// -- new -- a '688 that says when the folded A wire is carrying the port this
// one is listening to.  The supervision is two RC-and-'14 detectors and a
// handful of gates, and it is the whole of "nobody is in charge of a call":
// the port rings itself, sends its own ringback, and clears its own latch.
//
// WHAT CHANGED FROM fabric.md 3.2.  The A highway select -- a second '151 on
// HA[0..7] -- is gone, because HA[0..7] are gone.  A and BUSY are on one
// open-collector conductor at 64 kbps, addressed by SCAN: port p drives
// bit-time p on /HA with its M and bit-time p on /HB with its BUSY, and a pass
// is 64 bit-times = 1 ms.  In its place this port has two comparisons: one against the port
// it is LISTENING to, which captures E, and one against its OWN number, which
// enables its open drain.
`timescale 1ns/1ps
`include "exch.vh"

module port #(
    // Straps and stuffing.  Not options -- there is no feature here that a
    // parameter turns on.
    parameter        FITTED = 1'b1,   // a port circuit is populated at this slot
    parameter [2:0]  BLOCK  = 3'd0,   // strapped at the block; port-card.md's BLOCK[0..2]
    parameter [2:0]  POS    = 3'd0,   // which ribbon slot this is
    // The two detectors, in milliseconds.  THESE ARE RC NETWORKS -- a diode
    // and two resistors into a 74HC14, up in 16 ms and down in 256 (fabric.md
    // 3.5).  The fold does not touch them and does not make them cheaper.
    // The model counts TICK because that is the time base the RC
    // approximates and RTL has no analogue.
    parameter [8:0]  T_ARM  = 9'd16,
    parameter [8:0]  T_REL  = 9'd256
)(
    input                   clk,
    input                   rst_n,       // also /RESET, filtered at the block

    // ---- from the clock card, through the block's receivers ---------------
    input      [2:0]        slotq,       // the strobe decoder's address
    input                   cap_stb,     // mid-cell
    input                   tick_1k,     // TICK: the two detectors' time base
    input      [`SCANW-1:0] scan,        // the port whose turn it is, 0..63
    input                   ring_cad_n,  // 2.048 s / 4.096 s, low true

    // ---- the fabric --------------------------------------------------------
    input      [7:0]        hc,          // the eight C highways
    input                   ha_n,        // /HA as received.  IDLE HIGH
    output                  ha_pd,       // this port's open drain onto /HA (M)
    output                  hb_pd,       // and onto /HB (BUSY), the same turn

    // ---- the channel socket (common-cards.md 1) ---------------------------
    input                   a_tx,        // a6.  M: the card's hook
    input                   ans_n,       // a13.  /ANS, pulled up: open = this port rings
    output                  c_rx,        // a9
    output                  a_rx,        // a10.  E, chopped by the cadence while ringing

    // ---- the block ---------------------------------------------------------
    input                   mute_blk,    // an adapter busies its whole group
    output                  rb,          // being rung: the block's '157 sends RBT
    output                  busy,        // the full BUSY term

    // ---- the write, already decoded by the block ---------------------------
    input                   wr,
    input      [`PW-1:0]    src,
    input                   bsy_in,
    input                   clm_in
);
    // ---- the '273: the crosspoint, and the whole of the connection --------
    // WIDENS WITH `PW: at nine bits this is eleven, so two packages.
    reg [`PW-1:0] addr;          // [5:3] highway, [2:0] slot -- the number as dialled
    reg           bsy, clm;

    // ---- the C path: unchanged from fabric.md 3.2 -------------------------
    // 74HC151 -- highway select: the eight HC on the data inputs, the latch's
    // highway bits on the selects.
    wire c_sel = hc[addr[`PW-1:`PW-3]];

    // 74HC151 -- slot select: the block's eight strobe lines on the data
    // inputs, the latch's slot bits on the selects.  Its inverted output W is
    // the capture clock, rising in the middle of the chosen cell.
    wire w_c = cap_stb && (slotq == addr[2:0]);

    // ---- the A path: two comparisons where a '151 used to be --------------
    // 74HC688 -- is the plane carrying the port we are listening to?
    // WIDENS WITH `PW: at nine bits this is a '688 and half an '85.
    wire eq_src = (scan == addr);

    // A 74HC30 -- is it OUR turn?  Layout, not logic: six true-or-complement
    // picks of the SCAN bits into an eight-input NAND.  THE HIGHWAY HALF IS
    // NOT STRAPPED HERE: BLOCK[2:0] comes down the block ribbon from the
    // mainboard's shunt, so a port's number on the planes is the highway its
    // block is jumpered onto -- the same number as its voice.  Only the slot,
    // POS, is the port's own, and that is wiring, not a strap: it is which
    // socket the circuit sits in.  No comparator package, and no ID pins on
    // the channel socket.  (mainboard.md 4, port-card.md)
    wire eq_own = (scan == {BLOCK, POS});

    // The A capture instant is strobe line 4's falling edge -- the middle of
    // cell 4, 8.79 us into the 15.63 us bit-time.  The block's '138 already
    // makes that line for a port listening to slot 4, and it is already
    // SLOTQ-addressed and so already free of fabric.md 3.2's hazard.
    wire a_stb = cap_stb && (slotq == `CELL_A);
    wire w_a   = a_stb && eq_src;

    reg c_cap, e_cap;
    wire m = a_tx;                      // M: the card's hook
    wire e = e_cap;                     // E: the other party's M, come back

    // ---- 2N7002 x2: the open drains onto /HA and /HB ----------------------
    // Enabled for the WHOLE bit-time, not pulsed.  Two ports' enables overlap
    // by a few nanoseconds at the frame edge during handover, which on a
    // wired-OR is harmless -- and is a second argument for open collector
    // over tri-state.  *_pd is "this port is pulling the line down", i.e. a
    // one; the mainboard inverts each wired-OR into /HA and /HB.
    //
    // ONE TURN, BOTH FACTS.  A port owns slot p on both planes at once, so a
    // reader gets M and BUSY of the same port in the same bit-time and never
    // has to hold one while it waits for the other.  That is what the second
    // conductor buys, and it is why the pass is 64 bit-times and not 128.
    assign ha_pd = FITTED && eq_own && m;
    assign hb_pd = FITTED && eq_own && busy;

    // ---- fabric.md 3.5, in gates ------------------------------------------
    // The '273 is EDGE-clocked by the write decoder's line.  The block holds
    // that line for the middle half of a bit-time -- 3.9 us, mainboard.md
    // 2.3.2's window -- and the latch must take the word ONCE, on its rising
    // edge, not on every master tick the line happens to be high for.
    reg wr_d;
    wire wr_edge = wr && !wr_d;

    reg fm, fe;                          // the two RC-and-'14 detectors
    reg [8:0] cm, ce;                    // their climb, in milliseconds
    reg rel;                             // the CR differentiator into the '273's CLR

    // /ANS is a PIN, not a parameter.  It is the card's (a13, open drain,
    // ~680 ohm pull-up at the port), and the port's gates never see the
    // class: a phone's card leaves it open, everything that answers at once
    // ties it low.  fabric.md 3.5.
    wire rings = ans_n;

    wire on = FITTED && rings && !m && !fm;   // an on-hook port that rings -- and not
                                              // one that hung up a moment ago
    assign rb   = on && e;                    // RB = ON . E
    assign busy = FITTED && (bsy || fe || (fm && !m) || mute_blk);

    // rtl.md: A out = E + CLAIM is the A the port hands its CARD, never what
    // it puts on the wire.  Put CLAIM on the wire and the claim jams the very
    // register it summoned, because that register reads the far caller's dial
    // pulses out of this port's own bit-time.
    assign a_rx = FITTED && ((e || clm) && !(on && ring_cad_n));
    assign c_rx = FITTED && c_cap;

    wire [8:0] thr_m = m ? T_ARM : T_REL;
    wire [8:0] thr_e = e ? T_ARM : T_REL;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            addr <= {`PW{1'b0}}; bsy <= 1'b0; clm <= 1'b0;
            c_cap <= 1'b0; e_cap <= 1'b0;
            fm <= 1'b0; fe <= 1'b0; cm <= 9'd0; ce <= 9'd0; rel <= 1'b0;
            wr_d <= 1'b0;
        end else if (FITTED) begin
            rel  <= 1'b0;
            wr_d <= wr;

            // the '74 pair.  C in the middle of its own cell, off the highway;
            // E in the middle of cell 4, off /HA, when the wire is carrying
            // the port we listen to.  ha_n is low true.
            if (w_c) c_cap <= c_sel;
            if (w_a) e_cap <= ~ha_n;

            // the detectors.  Fast up, slow down; an RC in the real thing.
            if (tick_1k) begin
                if (m == fm) cm <= 9'd0;
                else if (cm >= thr_m - 9'd1) begin
                    cm <= 9'd0; fm <= m;
                    if (!m) rel <= 1'b1;        // fM fell
                end else cm <= cm + 1'b1;

                if (e == fe) ce <= 9'd0;
                else if (ce >= thr_e - 9'd1) begin
                    ce <= 9'd0; fe <= e;
                    if (!e) rel <= 1'b1;        // fE fell
                end else ce <= ce + 1'b1;
            end

            // The marker writes; the port clears itself.  A RELEASE BEATS A
            // WRITE -- the fall of either detector, squared up through a CR
            // differentiator, straight into the '273's asynchronous CLR.
            if (rel)          begin addr <= {`PW{1'b0}}; bsy <= 1'b0;    clm <= 1'b0; end
            else if (wr_edge) begin addr <= src;         bsy <= bsy_in;  clm <= clm_in; end
        end
    end
endmodule
