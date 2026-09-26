// baseband_card -- the baseband tie trunk.  trunks.md §2.  NETWORK.
//
// A tie trunk with nothing in between: C and A out, C and A in, and a fifth
// conductor each way carrying TX_CLK.  No line code, no framer, no codec.
// What the near port hears from its fabric goes down the wire; what comes
// back is what that port's card says (network.md §1).  About two and a quarter
// packages in the 74HC population, two more for RS-422 (trunks.md §2): the
// cheapest card in the exchange, and it sits in any channel socket like a
// line card.
//
// THE CARD SAYS WHAT IT IS.  Its word -- class trunk, glare, direction -- is
// one '165 loaded from jumpers ON THIS CARD, and nothing else in the exchange
// holds a copy: not the marker, not the network unit.  Whoever needs to know
// selects the port on /WS and reads it off /HW (word_rx.v).  A trunk's direction is
// the direction of the link it is wired to, and the card is what is wired to
// it; a strap anywhere else could disagree with the cable.
//
// THE LINK-DOWN DETECTOR IS THE ENABLE ON THE WORD (trunks.md §2).
// Four conductors cannot tell an idle link from a cut one; the fifth carries
// the far end's TX_CLK, a continuous 64 kHz square wave, and half a '123
// retriggered by it says the far end is alive.  With it gone the word pin is
// left open: the port reads NONE, all zeros, and no hunt will take it.  A
// cut cable also reads A = 0 here, so a call in progress releases.
//
//   pin  name       dir   what THIS card does with it
//   a1   TX_CLK     in    shifts the word; re-times incoming C; the fifth conductor out
//   a2   LOOP_HB    in    --   nothing on this card encodes a line
//   a3   TX_OCT     in    loads the word, in the first half of frame 7
//   a4   FILL       in    --   the port idles to FILL through its own commutator
//   a5   C_TX       out   incoming C, re-timed at the frame edge
//   a6   A_TX       out   incoming A: this is M at the port
//   a7   RX_CLK     in    --   TX_CLK in a block (common-cards.md §1.1); nothing drives it
//   a8   RX_OCT     in    --
//   a9   C_RX       in    straight out on the line
//   a10  A_RX       in    straight out on the line: E as it stands, a trunk never rings
//   a11  MUTE       in    --   tied to "locked" in a block; this card's detector is its own
//   a12  card word  out   the '165, gated by link-up and the power-up RC
//   a13  /ANS       out   tied low on the board: a trunk answers at once and never rings
//   a14  spare      out   open
//   rear c_out, a_out, clk_out / c_in, a_in, clk_in
//
//   trunks.md §1, §2; card-word.md §2, §3; network.md §1, §2; common-cards.md §1
`timescale 1ns/1ps

module baseband_card #(
    // THE WORD'S PRIMARY OCTET, in bit-time order -- WORD[n] is bit-time n.
    // Class form, family 01, member 0 (11 01 0), then g at 5 and the
    // direction at 6-7, N=0 S=1 E=2 W=3 (card-word.md §2).  Jumpers.
    parameter [7:0]  WORD      = 8'b00_0_010_11,
    // trunks.md §2's jumper: incoming C re-timed by the LOCAL frame edge
    // (two clocks, a slip every 390-780 ms) or by the FAR end's clock on the
    // fifth conductor (one clock, bit-exact).
    parameter        ONE_CLOCK = 1'b0,
    // The power-up RC that holds the word off: 100 ms of frames.  A '165
    // clocking before its load settles says a random word, and one in 32 of
    // those is a live flood seat (card-word.md §3, held off at power-up).
    parameter [15:0] HOLDOFF   = 16'd6400,
    // Half a '123 on the fifth conductor: three frames of silence is a cut.
    // In master ticks, because the model has no RC.
    parameter [7:0]  DEAD      = 8'd192
)(
    input        clk,         // the simulation's timebase, not a pin
    input        rst_n,       // power-on

    // ---- the channel socket, a1 .. a14 ----------------------------------
    input        tx_clk,      // a1
    input        loop_hb,     // a2   --
    input        tx_oct,      // a3
    input        fill,        // a4   --
    output       c_tx,        // a5
    output       a_tx,        // a6
    input        rx_clk,      // a7   --
    input        rx_oct,      // a8   --
    input        c_rx,        // a9
    input        a_rx,        // a10
    input        mute,        // a11  --
    output       word_n,      // a12  o.d.
    output       ans_n,       // a13  o.d.
    output       rai_n,       // a14  o.d.

    // ---- the rear connector: the link --------------------------------------
    output       c_out,
    output       a_out,
    output       clk_out,
    input        c_in,
    input        a_in,
    input        clk_in,

    // ---- for a bench -------------------------------------------------------
    output       link_up
);
    // ---- the socket's clock edges, in the simulation's timebase ------------
    reg  tx_d, far_d;
    wire frame_edge = tx_clk && !tx_d;      // TX_CLK's rise
    wire far_edge   = clk_in && !far_d;     // the far end's

    // ---- transmit: straight through ----------------------------------------
    assign c_out   = c_rx;
    assign a_out   = a_rx;
    assign clk_out = tx_clk;

    // ---- receive: half a '74 for C, the RC and a quarter '14 for A ---------
    // The RC is tens of microseconds, against 1 ms between samples of M, so
    // dial pulses cross it undistorted (trunks.md §2).  Two flip-flops on
    // the frame edge stand in for it; the model has no analogue.
    reg c_sync, a_s1, a_s2;

    // ---- half a '123 on the fifth conductor --------------------------------
    reg [7:0] quiet;
    assign link_up = (quiet < DEAD);

    // ---- the power-up RC ---------------------------------------------------
    reg [15:0] up_cnt;
    wire       settled = (up_cnt == HOLDOFF);

    // ---- the word: one 74HC165 ---------------------------------------------
    // SH//LD is /(TX_OCT . TX_CLK), a quarter '00 -- the '165 loads while the
    // pin is low (card-word.md §3) -- so the load happens in the FIRST
    // half of frame 7 and is released 32 ticks before the frame edge that
    // shifts.  Loading on TX_OCT alone would release the load at the same
    // edge that shifts, and which one won would be the board's propagation
    // delays.  So frame 7 carries bit 0, frame 0 bit 1, frame f bit f+1 --
    // which is what word_rx.v's rotated '259 expects.  SER is strapped high:
    // the second '165 is not fitted, and its eight bits read FF.
    reg [7:0] sh;
    wire      ld = tx_oct && tx_clk;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_d <= 1'b0; far_d <= 1'b0;
            c_sync <= 1'b0; a_s1 <= 1'b0; a_s2 <= 1'b0;
            quiet <= 8'hFF; up_cnt <= 16'd0; sh <= 8'hFF;
        end else begin
            tx_d  <= tx_clk;
            far_d <= clk_in;

            if (far_edge)          quiet <= 8'd0;
            else if (quiet != 8'hFF) quiet <= quiet + 8'd1;

            if (ONE_CLOCK ? far_edge : frame_edge) c_sync <= c_in;
            if (frame_edge) begin
                a_s1 <= a_in; a_s2 <= a_s1;
                if (!settled) up_cnt <= up_cnt + 16'd1;
            end

            if (ld)              sh <= WORD;
            else if (frame_edge) sh <= {1'b1, sh[7:1]};
        end
    end

    assign c_tx = c_sync;
    // A cut cable is A = 0 whatever the receiver's failsafe says, so a call in
    // progress releases (network.md §2, "Link down").  And a card still in
    // its power-up RC presents no M: a seizure it passed on before its word
    // could say "trunk" would be read as NONE, and taken for nobody's.
    assign a_tx = a_s2 && link_up && settled;

    // open drain, modelled at the pin: 0 pulled low (a one), 1 left open
    assign word_n = !(sh[0] && link_up && settled);
    assign ans_n  = 1'b0;
    assign rai_n  = 1'b1;

    wire _unused = &{1'b0, loop_hb, fill, rx_clk, rx_oct, mute, 1'b0};
endmodule
