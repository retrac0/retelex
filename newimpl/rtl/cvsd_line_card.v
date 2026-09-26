// cvsd_line_card -- the CVSD subscriber line card.  channel-cards.md §2.
//
// Two pairs to one phone.  THE PHONE HOLDS THE CODEC; this card holds the two
// line interfaces, the hook detector and the slot logic -- channel-cards.md
// §2.5's parts and two transformers, with no relay, no ring generator, no
// ring trip and nothing above the 48 V phantom.  The phone's ringer is armed by a bit
// pattern, and its hook is read from one.
//
// THE CHANNEL SOCKET, AS EVERY CARD SEES IT (common-cards.md §1).  There is no
// interface construct in the language both simulators accept, so the socket
// is a PORT LIST: the fourteen signal pins in socket order, with the same
// names in the same order on every card, whether or not the card has a part
// on the pin.  A card drives four of them and only four -- a5 and a6 totem-
// pole, a12 and a13 open drain -- and listens to the rest.  A site
// instantiates any card by this list and connects it to socket [p][s]; the
// cards are interchangeable because the list is.
//
//   pin  name       dir   what THIS card does with it
//   a1   TX_CLK     in    H into the downstream encoder; the clock of the '175
//   a2   LOOP_HB    in    128 kHz: the encoder's half-cell clock
//   a3   TX_OCT     in    -- nothing.  It loads the word '165, not fitted here
//   a4   FILL       in    the bus's 1010, sent downstream while on-hook
//   a5   C_TX       out   Q_s: the upstream receiver's latch, resynchronised
//   a6   A_TX       out   NOT ON_HOOK
//   a7   RX_CLK     in    -- this card has no R domain
//   a8   RX_OCT     in    --
//   a9   C_RX       in    through the '175 on TX_CLK, downstream while off-hook
//   a10  A_RX       in    through an RC (2 ms) and a '14: RING the phone
//   a11  MUTE       in    ORed into the ON_HOOK select
//   a12  card word  out   tied to a row-c ground: all ones, a plain line
//   a13  /ANS       out   open: this port rings, and the caller hears ringback
//   a14  spare      out   open
//   rear line_dn    out   the downstream pair, to the phone
//        line_up    in    the upstream pair, from the phone
//
// Open-drain pins are modelled AT THE PIN: 0 is pulled low, 1 is left open
// and reads as the port's pull-up.  A card never shares its own socket, so
// there is no wired-OR to model here.
//
// THE CARD HAS NO MASTER CLOCK.  clk and rst_n are the simulation's timebase,
// not pins.  Every edge the logic acts on is derived from the socket's clock
// waveforms -- which is what the flip-flops clocked by TX_CLK and LOOP_HB do
// on the board -- and the upstream receiver times its intervals in that timebase
// where the board has one-shots (dm_rx.v).
//
// LOOP_HB IS MADE AT THE BLOCK, not the clock card: /SLOT[1], one inverter
// (common-cards.md §1.1, clocks.md §4).  Its rising edges are the cell boundary
// and mid-cell, which with H = TX_CLK is all the encoder needs.
//
//   channel-cards.md §2; subscriber-line.md §3, §4; mf8-spec.md 9.2, 9.4
`timescale 1ns/1ps

module cvsd_line_card (
    input        clk,
    input        rst_n,

    // ---- the channel socket, a1 .. a14 ----------------------------------
    input        tx_clk,      // a1
    input        loop_hb,     // a2
    input        tx_oct,      // a3   --
    input        fill,        // a4
    output       c_tx,        // a5
    output       a_tx,        // a6
    input        rx_clk,      // a7   --
    input        rx_oct,      // a8   --
    input        c_rx,        // a9
    input        a_rx,        // a10
    input        mute,        // a11
    output       word_n,      // a12  o.d.
    output       ans_n,       // a13  o.d.
    output       rai_n,       // a14  o.d.

    // ---- the rear connector: the two pairs --------------------------------
    output reg   line_dn,
    input        line_up
);
    // ---- the socket clocks' edges, in the simulation's timebase ------------
    reg  tx_d, hb_d;
    wire cell_start = tx_clk  && !tx_d;    // TX_CLK's rise: a cell boundary
    wire hb_edge    = loop_hb && !hb_d;    // LOOP_HB's rise: boundary, then mid

    // ---- the upstream receiver: mf8-spec.md 9.4 at the 64 kbps plug -------
    // '86, '221, '123, '74.  The rate plug is a fixed footprint on this card:
    // it never runs at another rate.
    wire q, q_stb, carrier, viol;
    dm_rx #(.CELL(64)) u_rx (
        .clk(clk), .rst_n(rst_n), .line(line_up),
        .q(q), .q_stb(q_stb), .carrier(carrier), .viol(viol));

    // ---- the hook detector: subscriber-line.md §3 --------------------------
    // X = Q xor Q[n-2]: half a '74 and a quarter of an '86.  1100 makes it
    // constantly 1; CVSD keeps it near the middle whatever it is fed.
    //
    // On the board the two '74s clock on the same edge that loads the latch,
    // so they hold Q[n-1] and Q[n-2] the moment Q is Q[n].  In this timebase
    // the strobe lands the tick AFTER the latch moved, so a flip-flop clocked
    // by it sees the new bit; a third stage stands in for that one edge, and
    // X is taken across the last two.  Q xor Q[n-1] -- the obvious slip --
    // reads 1100 as density 0.5 and speech as 0.8, which is every reading
    // backwards.
    reg  q1, q2, q3;
    wire x = q ^ q3;

    // G = X + violation + /carrier: a quarter of a '32.  THE VIOLATION TERM
    // IS NOT OPTIONAL: without it a dead pair with noise on it decodes as
    // speech-like bits and reads off-hook, and a cut cable seizes every line
    // in it.
    wire g = x || viol || !carrier;

    // The RC, tau = 4 ms, into a quarter of an LM339 at 0.85 / 0.70 of the
    // swing -- a comparator with a resistive reference, because no '14
    // threshold falls there.  THE RC IS AN RC: the RTL integrates it once a
    // cell, 256 cells to tau, only because the model has no analogue.  From
    // 0 it reaches 0.85 in 1.9 tau = 7.6 ms; from 1 it falls to 0.70 in
    // 0.36 tau = 1.4 ms.  That asymmetry is why a dial break arrives 6.1 ms
    // short (subscriber-line.md §5), and the register's windows are sized to
    // it (dialling.md §1, §2).
    localparam [15:0] HOOK_HI = 16'd55705;     // 0.85 of 65535
    localparam [15:0] HOOK_LO = 16'd45875;     // 0.70
    reg [15:0] hook_rc;
    reg        on_hook;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_d <= 1'b0; hb_d <= 1'b0;
            q1 <= 1'b1; q2 <= 1'b1; q3 <= 1'b1;
            hook_rc <= 16'hFFFF; on_hook <= 1'b1;   // a card powers up on-hook
        end else begin
            tx_d <= tx_clk;
            hb_d <= loop_hb;
            if (q_stb) begin q1 <= q; q2 <= q1; q3 <= q2; end
            if (cell_start) begin
                hook_rc <= g ? hook_rc + ((16'hFFFF - hook_rc) >> 8)
                             : hook_rc - (hook_rc >> 8);
                if      (hook_rc > HOOK_HI) on_hook <= 1'b1;
                else if (hook_rc < HOOK_LO) on_hook <= 1'b0;
            end
        end
    end

    // a quarter of an '04 off the comparator
    assign a_tx = !on_hook;

    // ---- the synchronisers: one '175, clocked by TX_CLK -------------------
    // The two clock-domain crossings of mf8-backplane.md 2: C_RX from the
    // bus into T, and the receiver's latch, which is loop-timed, into T.
    reg c_rx_1, c_rx_s, q_s1, q_s;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin c_rx_1 <= 1'b0; c_rx_s <= 1'b0; q_s1 <= 1'b1; q_s <= 1'b1; end
        else if (cell_start) begin
            c_rx_1 <= c_rx; c_rx_s <= c_rx_1;
            q_s1   <= q;    q_s    <= q_s1;
        end
    end
    assign c_tx = q_s;

    // ---- A_RX through the RC (tau = 2 ms) and a quarter of a '14 ----------
    // mf8-spec.md §14's filter.  A Schmitt gate's thresholds sit near
    // 0.55 / 0.35 of the swing; the exact figure is not load-bearing here.
    localparam [15:0] ARX_HI = 16'd36044;
    localparam [15:0] ARX_LO = 16'd22937;
    reg [15:0] arx_rc;
    reg        a_rx_f;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin arx_rc <= 16'd0; a_rx_f <= 1'b0; end
        else if (cell_start) begin
            arx_rc <= a_rx ? arx_rc + ((16'hFFFF - arx_rc) >> 7)
                           : arx_rc - (arx_rc >> 7);
            if      (arx_rc > ARX_HI) a_rx_f <= 1'b1;
            else if (arx_rc < ARX_LO) a_rx_f <= 1'b0;
        end
    end

    // ---- the rule: three 2:1 selections, three quarters of a '157 ---------
    //   DN_D = (ON_HOOK + MUTE) ? (A_RX_f ? 0 : FILL) : C_RX_s
    // FILL is the bus's 1010, so the card makes no idle pattern of its own;
    // all-zeros is ground.  MUTE joins the select so an off-hook phone hears
    // 1010 through an outage rather than the receiver's last latched bits.
    wire sel  = on_hook || mute;
    wire dn_d = sel ? (a_rx_f ? 1'b0 : fill) : c_rx_s;

    // ---- the downstream encoder: mf8-spec.md 9.2 ---------------------------
    // Half a 74HC112 and a quarter of a '00: a JK wired J = K = EN, with
    // EN = H + /bit and H = TX_CLK.  At the boundary H is 1 and it toggles
    // whatever the bit; at mid-cell H is 0 and it toggles for a 0.  On the
    // board the '112 takes LOOP_HB's FALLING edge, a quarter bit from any H
    // edge (channel-cards.md §2.4, clocks.md §4).  The model acts on the
    // rise and reads H after that edge, which is the same function; whether
    // the drawn edge closes the race with H is channel-cards.md §6's.
    reg dn_bit;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin line_dn <= 1'b0; dn_bit <= 1'b1; end
        else if (hb_edge) begin
            if (tx_clk)       begin line_dn <= ~line_dn; dn_bit <= dn_d; end
            else if (!dn_bit)       line_dn <= ~line_dn;
        end
    end

    // ---- the declarations -------------------------------------------------
    assign word_n = 1'b0;    // a wire to ground: all ones, a plain line
    assign ans_n  = 1'b1;    // open: the port rings this line
    assign rai_n  = 1'b1;    // open

    // the pins this card has no part on
    wire _unused = &{1'b0, tx_oct, rx_clk, rx_oct, 1'b0};
endmodule
