// console -- the operator's console, the second master on cable B.
// console.md; mainboard.md 2.3's /CON; features.md 4.
//
// Keys, two pairs of octal wheels and two toggles, and what they make is the
// marker's own sixteen-bit word (mainboard.md 2.3.1).  The console has
// no verbs of its own.  Everything it does is a latch write:
//
//   WRITE     the word as the wheels have it: DST listens to SRC.  Bring-up
//             step 3, a patch by hand -- and SERVICE OBSERVING, which is the
//             same write with a sink's port on the DST wheels
//   RELEASE   the same DST, and SDATA held low for the second byte: SRC 00,
//             BSY 0, CLM 0 -- the word a call's own end would have written,
//             had anyone written it.  ONE GATE on the serial stream
//   PROBE     the same word with NO WR: nothing is written, and the block the
//             word names drives the probe bus.  The marker steers its own probe
//             with exactly this (marker.v, `probe_dirty`), so the console reads
//             a port the way the marker reads one -- BUSY, and the card's word
//
// BOTH is a toggle, not a key: the key runs TWICE in one tenure, the second
// word with the two port fields crossed.  It is the only thing here that is
// not one word, and it is what a connection and a release both are:
//
//   WRITE + BOTH    DST <- SRC and SRC <- DST: two lines connected, the pair
//                   that extensions.md 3.1 calls "two latches pointed at
//                   each other by hand".  Both words are inside ONE tenure, so
//                   no marker word can land between them
//   RELEASE + BOTH  both ends of a call, which is what a release IS
//                   (console.md 3.1: one end is not enough)
//   PROBE + BOTH    both ends read, into two sets of lamps
//
// TAKING THE BUS.  /CON is a REQUEST, and there is no grant.  The marker
// honours it between words and never inside one (marker.v, `yield`), so a
// word of the marker's that is already in flight when /CON falls finishes
// first, WR and all.  The console does not wait to be told: its tenure opens
// with WAIT periods of its own clock in silence, its '244 still off, and WAIT
// is longer than any word the marker can send.  So the console works the same
// with a marker fitted, with none, and with one that is stopped -- which is
// the order fabric.md 7 brings an exchange up in.
//
//   /CON  ~~\__________________________________________________/~~~
//   oe    ____________________/~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\____
//            |  WAIT, silent  |  sixteen bits      | WR |
//
// At TX_CLK's rate, 64 kHz, that is 32 + 16 + 1 periods: about three quarters
// of a millisecond, less than the scanner spends on one block.
//
// A SLOWER CLOCK THAN THE MARKER'S, on purpose.  The blocks' shift registers
// have no phase, only content (mainboard.md 2.3.2), so two masters need
// not agree on a rate; the marker shifts at 512 kHz and this at 64.
//
// HOLD keeps the bus after the word.  With a marker fitted that STOPS the
// marker: calls in progress carry on, because nobody is in charge of a call,
// and nothing new is set up.  It is the bring-up state, and a maintenance one.
//
// THE WATCH is a listener on the same three wires, not part of the master:
// two '164, a '688 on DST against the DST wheels, and a '574.  It shows what
// the watched port's latch was last WRITTEN with -- latches cannot be read
// back, so this is the only way the console learns who a port is talking to,
// and it must be armed before the call is set up.  A port clears its own
// latch and tells nobody; the watch is stale once the port's BUSY lamp is out.
//
// SUPERVISION is the other three wires' worth: what the console can READ.
// A latch cannot be read back, so what is readable is only what the port
// circuits and the cards put on the bus:
//
//   the hook of either end   HA[h] in the port's own cell, off CABLE A -- the
//                            same bit the marker's probe reads, and the one
//                            thing here that needs no tenure, no marker and no
//                            control bus at all.  Two '151 and two flip-flops
//   BUSY and the card's word off PB0 and PB1, in the octet after a PROBE word.
//                            The block that drives PB is the block the SHIFT
//                            REGISTER names (mainboard.md 2.3.2), so a
//                            console word steers it to the console's own port
//   who a port listens to    only the watch, and only if it was armed first
`timescale 1ns/1ps
`include "exch_defs.vh"

module console #(
    parameter integer DIV  = 64,      // master clocks an SCLK period: 64 kHz, TX_CLK's rate
    parameter integer WAIT = 32       // periods of silence after /CON falls.  0 = take it at once
)(
    input            clk,
    input            rst_n,

    // the keys, the wheels and the toggles
    input            key_write,
    input            key_release,
    input            key_probe,       // read a port: the word goes out with no WR
    input            key_hold,        // a toggle, not a key: up = keep the bus
    input            key_arm,         // clears the watch's SEEN lamp
    input            sw_both,         // a toggle: the key runs twice, crossed
    input      [5:0] sw_dst,          // the port to write, h s
    input      [5:0] sw_src,          // what it is to listen to, h s
    input            sw_bsy,
    input            sw_clm,
    output           busy,            // a tenure is running and the keys are dead
    output reg       done,            // one pulse: the word is away

    // cable B, as a master
    output           con_n,           // /CON, low for the whole tenure
    output           oe,              // the console's own '244: off through the silence
    output reg       sdata,
    output reg       sclk,
    output reg       wr,

    // cable B, as a listener: the watch
    input            bus_sdata,
    input            bus_sclk,
    input            bus_wr,
    output reg [5:0] watch_src,
    output reg       watch_bsy,
    output reg       watch_clm,
    output reg       watch_seen,

    // cable A, as a listener: the hook of each end, every frame, for ever
    input      [7:0] ha,
    input      [2:0] slotq,
    input      [2:0] tick,
    input            frame_stb,
    input            tx_oct,
    output reg       hook_dst,
    output reg       hook_src,

    // the probe bus, as a listener: what a PROBE word brings back
    input            pb_busy,
    input            pb_word,
    output reg       sup_busy_dst,
    output reg       sup_busy_src,
    output reg [7:0] sup_word_dst,
    output reg [7:0] sup_word_src,
    output reg       sup_seen
);
    localparam S_IDLE = 3'd0, S_WAIT = 3'd1, S_SHIFT = 3'd2, S_STROBE = 3'd3,
               S_HELD = 3'd4, S_PROBE = 3'd5;

    reg [2:0]  st;
    reg [15:0] w;
    reg        rel, prb, pend;
    reg        second;                // this is the crossed word of a BOTH
    reg [4:0]  nbit;                  // bits still to go
    reg [7:0]  nwait;
    reg [7:0]  d;
    reg        psync;                 // the probe's octet has begun
    reg [7:0]  pw;                    // the card's word, one bit a frame
    reg        pb;

    localparam [7:0] DLAST = DIV[7:0] - 8'd1;
    localparam [7:0] DHALF = DIV[7:0] >> 1;
    localparam [7:0] DQ1   = DIV[7:0] >> 2;
    localparam [7:0] DQ3   = (DIV[7:0] >> 1) + (DIV[7:0] >> 2);

    assign busy  = (st != S_IDLE) && (st != S_HELD);
    assign con_n = (st == S_IDLE);
    assign oe    = (st == S_SHIFT) || (st == S_STROBE) || (st == S_HELD) || (st == S_PROBE);

    // RELEASE's one gate: the serial stream forced low for bits 7-0
    wire sd_next = w[15] && !(rel && nbit <= 5'd8);

    wire key = key_write || key_release || key_probe;

    // The two '165 load: G, the spare, DST, SRC, BSY, CLM -- and BOTH's second
    // word is the same wheels with the two port fields crossed.  In 74HC that
    // is the stream mux RELEASE already needs, one field wider: the bit
    // counter says which field is going out, and BOTH says which wheels feed it.
    wire [15:0] w_first  = {1'b1, 1'b0, sw_dst, sw_src, sw_bsy, sw_clm};
    wire [15:0] w_second = {1'b1, 1'b0, sw_src, sw_dst, sw_bsy, sw_clm};

    // Which port this pass is about: the one whose cell the probe reads.
    wire [5:0] pport = second ? sw_src : sw_dst;
    wire       pcell = (tick == `TICK_MID) && (slotq == pport[2:0]);
    wire       oct_stb = frame_stb && tx_oct;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_IDLE; w <= 16'd0; rel <= 1'b0; prb <= 1'b0; pend <= 1'b0;
            nbit <= 5'd0; nwait <= 8'd0; d <= 8'd0; second <= 1'b0;
            sdata <= 1'b0; sclk <= 1'b0; wr <= 1'b0; done <= 1'b0;
            psync <= 1'b0; pw <= 8'd0; pb <= 1'b0;
            sup_busy_dst <= 1'b0; sup_busy_src <= 1'b0;
            sup_word_dst <= 8'd0; sup_word_src <= 8'd0; sup_seen <= 1'b0;
        end else begin
            done <= 1'b0;
            case (st)
            S_IDLE: begin
                sclk <= 1'b0; wr <= 1'b0; sdata <= 1'b0;
                if (key || key_hold) begin
                    w    <= w_first;
                    rel  <= key_release;
                    prb  <= key_probe;
                    pend <= key;
                    second <= 1'b0;
                    if (key_probe) sup_seen <= 1'b0;
                    nwait <= WAIT[7:0]; d <= 8'd0;
                    st <= (WAIT == 0) ? (key ? S_SHIFT : S_HELD) : S_WAIT;
                    nbit <= 5'd16;
                end
            end
            S_WAIT: begin                       // silent: the marker's word may still be going
                d <= (d == DLAST) ? 8'd0 : d + 8'd1;
                if (d == DLAST) begin
                    nwait <= nwait - 8'd1;
                    if (nwait == 8'd1) st <= pend ? S_SHIFT : S_HELD;
                end
            end
            S_SHIFT: begin
                d <= (d == DLAST) ? 8'd0 : d + 8'd1;
                if (d == 8'd0)  sdata <= sd_next;
                if (d == DHALF) sclk  <= 1'b1;      // the shifting edge, mid-bit
                if (d == DLAST) begin
                    sclk <= 1'b0;
                    w    <= {w[14:0], 1'b0};
                    nbit <= nbit - 5'd1;
                    // a PROBE never strobes: the word steers /BLK and nothing else
                    if (nbit == 5'd1) begin
                        st <= prb ? S_PROBE : S_STROBE;
                        psync <= 1'b0; pw <= 8'd0; pb <= 1'b0;
                    end
                end
            end
            S_STROBE: begin                     // WR clear of every SCLK edge (2.3.2's one rule)
                d <= (d == DLAST) ? 8'd0 : d + 8'd1;
                if (d == DQ1) wr <= 1'b1;
                if (d == DQ3) wr <= 1'b0;
                if (d == DLAST) begin
                    sdata <= 1'b0;
                    if (sw_both && !second) begin   // the crossed word, in the SAME tenure
                        w <= w_second; second <= 1'b1; nbit <= 5'd16; st <= S_SHIFT;
                    end else begin
                        done <= 1'b1; pend <= 1'b0; second <= 1'b0;
                        st <= key_hold ? S_HELD : S_IDLE;
                    end
                end
            end
            S_PROBE: begin
                // The bus is still the console's and WR never pulses, so nothing
                // is written.  The block the word names is driving PB: read it
                // for one whole octet, in the port's own cell, exactly as the
                // marker reads a port at every visit (marker.v, the probe).
                sclk <= 1'b0; wr <= 1'b0; sdata <= 1'b0;
                if (!psync) begin
                    if (oct_stb) begin psync <= 1'b1; pw <= 8'd0; end
                end else begin
                    if (pcell) begin pb <= pb_busy; pw <= {pb_word, pw[7:1]}; end
                    if (oct_stb) begin
                        if (second) begin sup_busy_src <= pb; sup_word_src <= pw; end
                        else        begin sup_busy_dst <= pb; sup_word_dst <= pw; end
                        if (sw_both && !second) begin
                            w <= w_second; second <= 1'b1; nbit <= 5'd16; st <= S_SHIFT;
                        end else begin
                            done <= 1'b1; pend <= 1'b0; second <= 1'b0; sup_seen <= 1'b1;
                            st <= key_hold ? S_HELD : S_IDLE;
                        end
                    end
                end
            end
            S_HELD: begin                       // the bus is the console's, and quiet
                sclk <= 1'b0; wr <= 1'b0;
                if (key) begin
                    w    <= w_first;
                    rel  <= key_release;
                    prb  <= key_probe;
                    second <= 1'b0;
                    if (key_probe) sup_seen <= 1'b0;
                    pend <= 1'b1; nbit <= 5'd16; d <= 8'd0;
                    st   <= S_SHIFT;                // no silence wanted: it is ours already
                end else if (!key_hold) st <= S_IDLE;
            end
            default: st <= S_IDLE;
            endcase
        end
    end

    // ---- supervision off cable A: the hook of each end ---------------------
    // Two '151 on HA[0..7] picked by the two block wheels, and two flip-flops
    // clocked when SLOTQ reaches the slot wheels: the same bit, in the same
    // cell, that the marker's probe reads (marker.v).  It needs no tenure and
    // no marker, and it is the only supervision the console has at bring-up
    // step 2, before there is a control bus worth the name.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin hook_dst <= 1'b0; hook_src <= 1'b0; end
        else begin
            if (tick == `TICK_MID && slotq == sw_dst[2:0]) hook_dst <= ha[sw_dst[5:3]];
            if (tick == `TICK_MID && slotq == sw_src[2:0]) hook_src <= ha[sw_src[5:3]];
        end
    end

    // ---- the watch ---------------------------------------------------------
    reg [15:0] lsr;
    reg        bsclk_d, bwr_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lsr <= 16'd0; bsclk_d <= 1'b0; bwr_d <= 1'b0;
            watch_src <= 6'd0; watch_bsy <= 1'b0; watch_clm <= 1'b0; watch_seen <= 1'b0;
        end else begin
            bsclk_d <= bus_sclk; bwr_d <= bus_wr;
            if (bus_sclk && !bsclk_d) lsr <= {lsr[14:0], bus_sdata};
            if (key_arm) watch_seen <= 1'b0;
            // the '688: G, and DST against the wheels; the '574 clocked by WR
            if (bus_wr && !bwr_d && lsr[15] && lsr[13:8] == sw_dst) begin
                watch_src <= lsr[7:2]; watch_bsy <= lsr[1]; watch_clm <= lsr[0];
                watch_seen <= 1'b1;
            end
        end
    end
endmodule
