// local_trunk -- the local eight-channel highway trunk.  trunks.md §3.  NETWORK.
//
// A block adapter (fabric.md §6.2): it serves one block's eight seats through
// their card-side pins in place of subscriber cards, and the eight port
// circuits behind them become eight trunk channels to one neighbouring
// exchange.  How the eight appearances reach the port cards is open
// (block-stack.md §9).  The RTL wires eight socket-shaped appearances.  The wire is highway-shaped --
// eight cells a frame at 512 kbps, C and A on conductors of their own -- with
// the sender's HCLK and TX_CLK beside them, so the receiver is timed by the
// far end and needs no clock recovery.  No line code, no F and S, no crystal.
// About seventeen packages beside the eight port circuits the block already has.
//
// PLESIOCHRONOUS, ON PURPOSE (trunks.md §3, network.md §8).  Each exchange
// keeps its own crystal and nothing slaves a clock card.  The receive demux
// is timed by the far HCLK; the eight bits cross into the local frame at the
// local TX_CLK, and that crossing is where a slip happens -- one bit dropped
// or doubled a channel, the event mf8-backplane.md 7 measured below the codec.
//
// EVERY EDGE ON THE WIRE IS CLOCKED BY AN EDGE HALF A CELL AWAY FROM IT.  A
// port's C_RX and A_RX change at the mid-cell capture, HCLK's fall; this card
// samples them at HCLK's rise and changes the wire there; the far end samples
// the wire at the far HCLK's fall.  The frame is found the same way at both
// ends: TX_CLK, sampled at HCLK's fall, is high in cells 0-3 and low in 4-7,
// so its first high sample is cell 0.  Resetting a counter on TX_CLK's RISE
// would race HCLK's rise, which is the same clock-card edge.
//
// NO TRANSMIT LATCH.  trunks.md §3's sketch muxes C_RX / A_RX with two
// '151s; that is enough, because the ports already hold each bit for a whole
// frame and change it half a cell from where this card looks.  The transmit
// side is the two '151s, a counter and a '74.
//
// NO RC ON A (trunks.md §3).  A arrives as a clocked bit in its own cell,
// sampled mid-cell and crossed at the frame edge like C: there is no raw wire
// to filter, and the port's own detectors and the registers' windows already
// do the timing.  An RC and Schmitt "as MF8" was the old sketch's
// (exchange/decisions.md).
//
// THE CARD SAYS WHAT IT IS, EIGHT TIMES.  One '165 from jumpers -- class
// trunk, glare, direction -- fanned to all eight word pins, since the eight
// channels share one link and so one direction.  Link-down floats all eight:
// the group reads NONE and leaves the hunt, MUTE_BLK busies every port, every
// A_TX falls so calls in progress release, and every C_TX is FILL.
//
// THE ADAPTER COMMONS CARRY HCLK.  J6 gives TX_CLK, TX_OCT, FILL and HCLK in
// and MUTE_BLK out (block-stack.md §6, trunks.md §3); a 512 kbps mux needs
// the cell clock.  SLOT is not on J6 and not needed: the counter below is
// SLOT, rebuilt.
//
//   header appearances (x8)  C_TX, A_TX, word, /ANS out; C_RX, A_RX in
//   adapter commons, J6      TX_CLK, TX_OCT, FILL, HCLK in; MUTE_BLK out
//   rear, each way           C_hw, A_hw, HCLK, TX_CLK
//
//   trunks.md §1, §3; fabric.md §6.2; block-stack.md §6; card-word.md §2, §3;
//   network.md §2, §8
`timescale 1ns/1ps

module local_trunk #(
    // THE WORD'S PRIMARY OCTET, in bit-time order -- WORD[n] is bit-time n,
    // as baseband_card.v's.  Jumpers.
    parameter [7:0]  WORD    = 8'b00_0_010_11,
    // The power-up RC that holds the word and the group off: 100 ms of frames.
    parameter [15:0] HOLDOFF = 16'd6400,
    // Half a '123 on the far HCLK: three frames of silence is a cut.  In
    // master ticks, because the model has no RC.
    parameter [7:0]  DEAD    = 8'd192,
    // AN OUTAGE IS A RELEASE, NEVER A PULSE (baseband_card.v's POISON, eight
    // times).  An outage of RIDE frames poisons every channel: A held at 0
    // both ways and the word NONE.  Each channel clears on its own once it has
    // been idle both ways -- its A_RX and the far A -- for four strobes of
    // STB frames running (a shared 128 ms tap, a 2-bit count a channel: over
    // 384 ms, past T_REL and CLR).  A channel at a time, so a far exchange
    // still seizing one channel cannot keep the other seven dead.  About
    // three packages.  Flood study C07.
    parameter [15:0] RIDE    = 16'd256,
    parameter [15:0] STB     = 16'd8192
)(
    input        clk,         // the simulation's timebase, not a pin
    input        rst_n,       // power-on

    // ---- the block header: eight appearances --------------------------------
    output [7:0] c_tx,        // into the block's commutator
    output [7:0] a_tx,        // M at each port
    output [7:0] word_n,      // o.d.
    output [7:0] ans_n,       // o.d.
    input  [7:0] c_rx,
    input  [7:0] a_rx,

    // ---- the block header commons -------------------------------------------
    input        tx_clk,
    input        tx_oct,
    input        fill,
    input        hclk,        // J6 pin 9 (block-stack.md §6)
    output       mute_blk,

    // ---- the rear: the link, each way ---------------------------------------
    output       c_out,
    output       a_out,
    output       hclk_out,
    output       clk_out,
    input        c_in,
    input        a_in,
    input        hclk_in,
    input        clk_in,

    // ---- for a bench --------------------------------------------------------
    output       link_up
);
    // ---- the clock edges, in the simulation's timebase ----------------------
    reg  tx_d, hk_d, fh_d;
    wire frame_edge = tx_clk && !tx_d;         // TX_CLK's rise
    wire hk_rise    = hclk && !hk_d;           // a cell starts
    wire hk_fall    = !hclk && hk_d;           // mid-cell
    wire fh_rise    = hclk_in && !fh_d;
    wire fh_fall    = !hclk_in && fh_d;        // mid-cell at the far end

    // ---- transmit: SLOT rebuilt, 2 x '151, and a '74 onto the wire -----------
    // nx is the NEXT cell, set at each mid-cell: cell 0 when TX_CLK is first
    // seen high, else one on.  74HC163, and a quarter '74 remembering TX_CLK.
    reg  [2:0] nx;
    reg        tq;
    wire       t_first = tx_clk && !tq;        // this mid-cell is cell 0's
    reg        c_q, a_q;

    assign c_out    = c_q;
    assign a_out    = a_q;
    assign hclk_out = hclk;
    assign clk_out  = tx_clk;

    // ---- receive: the same counter on the far clocks, 2 x '259 --------------
    reg  [2:0] rn;
    reg        rq;
    wire       r_first = clk_in && !rq;
    wire [2:0] r_cell  = r_first ? 3'd0 : rn;
    reg  [7:0] hold_c, hold_a;

    // ---- the crossing: 2 x '273 on the local frame edge ----------------------
    reg  [7:0] x_c, x_a;

    // ---- half a '123 on the far HCLK ----------------------------------------
    reg  [7:0] quiet;
    assign link_up = (quiet < DEAD);

    // ---- the power-up RC ------------------------------------------------------
    reg  [15:0] up_cnt;
    wire        settled = (up_cnt == HOLDOFF);
    wire        live    = link_up && settled;

    // ---- the word: one 74HC165, fanned to eight 2N7002s ----------------------
    // Loaded in the first half of frame 7 and shifted at each frame edge, as
    // baseband_card.v's: so frame 7 carries bit 0 and word_rx.v's rotated
    // '259 reads it at any phase.  SER strapped high.
    reg  [7:0] sh;
    wire       ld = tx_oct && tx_clk;

    // ---- the poison: a flip-flop and a 2-bit count a channel ------------------
    reg  [7:0]  poison;
    reg  [15:0] dn, ps;                        // frames down; the strobe's tap
    reg  [15:0] idc;                           // 2 bits a channel
    wire [7:0]  idle2 = ~a_rx & ~x_a;          // idle both ways

    integer pc;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_d <= 1'b0; hk_d <= 1'b0; fh_d <= 1'b0;
            nx <= 3'd0; tq <= 1'b0; c_q <= 1'b0; a_q <= 1'b0;
            rn <= 3'd0; rq <= 1'b0; hold_c <= 8'd0; hold_a <= 8'd0;
            x_c <= 8'd0; x_a <= 8'd0;
            quiet <= 8'hFF; up_cnt <= 16'd0; sh <= 8'hFF;
            poison <= 8'd0; dn <= 16'd0; ps <= 16'd0; idc <= 16'd0;
        end else begin
            tx_d <= tx_clk;
            hk_d <= hclk;
            fh_d <= hclk_in;

            // transmit
            if (hk_fall) begin
                tq <= tx_clk;
                nx <= t_first ? 3'd1 : nx + 3'd1;
            end
            if (hk_rise) begin
                c_q <= c_rx[nx];
                a_q <= a_rx[nx] && !poison[nx];
            end

            // receive: the '259s written mid-cell, addressed by the far count
            if (fh_fall) begin
                rq <= clk_in;
                rn <= r_cell + 3'd1;
                hold_c[r_cell] <= c_in;
                hold_a[r_cell] <= a_in;
            end
            if (fh_rise || fh_fall) quiet <= 8'd0;
            else if (quiet != 8'hFF) quiet <= quiet + 8'd1;

            // the crossing, and the word
            if (frame_edge) begin
                x_c <= hold_c;
                x_a <= hold_a;
                if (!settled) up_cnt <= up_cnt + 16'd1;
                // the poison
                if (!link_up) begin
                    if (dn != 16'hFFFF) dn <= dn + 16'd1;
                    if (dn >= RIDE - 16'd1) begin poison <= 8'hFF; idc <= 16'd0; end
                end else dn <= 16'd0;
                ps <= (ps >= STB - 16'd1) ? 16'd0 : ps + 16'd1;
                for (pc = 0; pc < 8; pc = pc + 1)
                    if (!poison[pc] || !live || !idle2[pc]) idc[pc*2 +: 2] <= 2'd0;
                    else if (ps == 16'd0) begin
                        if (idc[pc*2 +: 2] == 2'd3) poison[pc] <= 1'b0;
                        else idc[pc*2 +: 2] <= idc[pc*2 +: 2] + 2'd1;
                    end
            end
            if (ld)              sh <= WORD;
            else if (frame_edge) sh <= {1'b1, sh[7:1]};
        end
    end

    // ---- 74HC157 x2 and 74HC08 x2: what the block sees -----------------------
    // A dead link is FILL on every C and no M anywhere, so a call in progress
    // releases and an idle group reads like an unfitted one.
    assign c_tx     = live ? x_c : {8{fill}};
    assign a_tx     = live ? (x_a & ~poison) : 8'd0;
    assign mute_blk = !live;

    // open drain, modelled at the pin: 0 pulled low (a one), 1 left open;
    // a poisoned channel reads NONE, so no hunt takes it until it clears
    assign word_n = ~({8{sh[0] && live}} & ~poison);
    assign ans_n  = 8'd0;                      // tied low: a trunk never rings
endmodule
