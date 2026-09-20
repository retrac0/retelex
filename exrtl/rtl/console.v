// console -- the operator's console, the second master on cable B.
// ex-console.md; exch-mainboard.md 2.3's /CON; exch-features.md 4.
//
// Keys, two pairs of octal wheels and two toggles, and what they make is the
// marker's own sixteen-bit word (exch-mainboard.md 2.3.1).  The console has
// no verbs of its own.  Everything it does is a latch write:
//
//   WRITE     the word as the wheels have it: DST listens to SRC.  Bring-up
//             step 3, a patch by hand -- and SERVICE OBSERVING, which is the
//             same write with a sink's port on the DST wheels
//   RELEASE   the same DST, and SDATA held low for the second byte: SRC 00,
//             BSY 0, CLM 0 -- the word a call's own end would have written,
//             had anyone written it.  ONE GATE on the serial stream
//
// TAKING THE BUS.  /CON is a REQUEST, and there is no grant.  The marker
// honours it between words and never inside one (marker.v, `yield`), so a
// word of the marker's that is already in flight when /CON falls finishes
// first, WR and all.  The console does not wait to be told: its tenure opens
// with WAIT periods of its own clock in silence, its '244 still off, and WAIT
// is longer than any word the marker can send.  So the console works the same
// with a marker fitted, with none, and with one that is stopped -- which is
// the order exch-fabric.md 7 brings an exchange up in.
//
//   /CON  ~~\__________________________________________________/~~~
//   oe    ____________________/~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\____
//            |  WAIT, silent  |  sixteen bits      | WR |
//
// At TX_CLK's rate, 64 kHz, that is 32 + 16 + 1 periods: about three quarters
// of a millisecond, less than the scanner spends on one block.
//
// A SLOWER CLOCK THAN THE MARKER'S, on purpose.  The blocks' shift registers
// have no phase, only content (exch-mainboard.md 2.3.2), so two masters need
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
`timescale 1ns/1ps

module console #(
    parameter integer DIV  = 64,      // master clocks an SCLK period: 64 kHz, TX_CLK's rate
    parameter integer WAIT = 32       // periods of silence after /CON falls.  0 = take it at once
)(
    input            clk,
    input            rst_n,

    // the keys, the wheels and the toggles
    input            key_write,
    input            key_release,
    input            key_hold,        // a toggle, not a key: up = keep the bus
    input            key_arm,         // clears the watch's SEEN lamp
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
    output reg       watch_seen
);
    localparam S_IDLE = 3'd0, S_WAIT = 3'd1, S_SHIFT = 3'd2, S_STROBE = 3'd3, S_HELD = 3'd4;

    reg [2:0]  st;
    reg [15:0] w;
    reg        rel, pend;
    reg [4:0]  nbit;                  // bits still to go
    reg [7:0]  nwait;
    reg [7:0]  d;

    localparam [7:0] DLAST = DIV[7:0] - 8'd1;
    localparam [7:0] DHALF = DIV[7:0] >> 1;
    localparam [7:0] DQ1   = DIV[7:0] >> 2;
    localparam [7:0] DQ3   = (DIV[7:0] >> 1) + (DIV[7:0] >> 2);

    assign busy  = (st != S_IDLE) && (st != S_HELD);
    assign con_n = (st == S_IDLE);
    assign oe    = (st == S_SHIFT) || (st == S_STROBE) || (st == S_HELD);

    // RELEASE's one gate: the serial stream forced low for bits 7-0
    wire sd_next = w[15] && !(rel && nbit <= 5'd8);

    wire key = key_write || key_release;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_IDLE; w <= 16'd0; rel <= 1'b0; pend <= 1'b0;
            nbit <= 5'd0; nwait <= 8'd0; d <= 8'd0;
            sdata <= 1'b0; sclk <= 1'b0; wr <= 1'b0; done <= 1'b0;
        end else begin
            done <= 1'b0;
            case (st)
            S_IDLE: begin
                sclk <= 1'b0; wr <= 1'b0; sdata <= 1'b0;
                if (key || key_hold) begin
                    // the two '165 load: G, the spare, DST, SRC, BSY, CLM
                    w    <= {1'b1, 1'b0, sw_dst, sw_src, sw_bsy, sw_clm};
                    rel  <= key_release;
                    pend <= key;
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
                    if (nbit == 5'd1) st <= S_STROBE;
                end
            end
            S_STROBE: begin                     // WR clear of every SCLK edge (2.3.2's one rule)
                d <= (d == DLAST) ? 8'd0 : d + 8'd1;
                if (d == DQ1) wr <= 1'b1;
                if (d == DQ3) wr <= 1'b0;
                if (d == DLAST) begin
                    done <= 1'b1; pend <= 1'b0; sdata <= 1'b0;
                    st <= key_hold ? S_HELD : S_IDLE;
                end
            end
            S_HELD: begin                       // the bus is the console's, and quiet
                sclk <= 1'b0; wr <= 1'b0;
                if (key) begin
                    w    <= {1'b1, 1'b0, sw_dst, sw_src, sw_bsy, sw_clm};
                    rel  <= key_release;
                    pend <= 1'b1; nbit <= 5'd16; d <= 8'd0;
                    st   <= S_SHIFT;                // no silence wanted: it is ours already
                end else if (!key_hold) st <= S_IDLE;
            end
            default: st <= S_IDLE;
            endcase
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
