// ctl_queue -- a master's side of cable B: its queue, its serialiser, its
// word reader, and when it may start.  One on every card that drives cable B.
//
// Two cards drive cable B once a network unit is fitted -- the marker and the
// unit -- and each fits this.  The bus has NO GRANT.  A master starts a
// TRANSACTION only when its `go` says it may, and it lets go only between
// transactions: a word cut short is a lost write, and a WR cut short is a
// runt clock into a '273.  Who may go is the card's business, not this one's:
//
//   the marker   go = /UREQ high.  It yields between transactions to the
//                unit's request line, a spare conductor on the 16-way
//   the unit     go = it has held /UREQ low for longer than the marker's
//                longest transaction, and keeps holding it until it is done
//
// A TRANSACTION is one written word (17 bit-times, 133 us), or one READ: a
// pointing word with WR suppressed, then the eight frames word_rx needs --
// about 1030 master ticks, 250 us.  The bus is held across the whole read,
// because the blocks' '164s have no output latch: another master's word
// shifted in during the read would move /BLK and another card would answer.
//
// THE QUEUE IS A MODEL PART.  In 74HC the sequencer holds until its word is
// away and there is no queue (counters.md 9); here a sequencer may decide
// several writes in one tick and hand them over at once.  What the model owes
// the board is that nothing is lost silently: a push the queue has no room for
// sets `ovf`, sticky, and every bench that fits this reads it.  The sequencer
// is expected to look at `room` first and wait; a timer or a visit that finds
// no room comes round again.  AN EVENT WORD NEVER DELAYS A CALL: one pushed
// with fewer than EV_ROOM entries free is dropped, not queued, and does not
// set ovf.
//
// Pushes arrive REGISTERED from the sequencer, so they land one tick after it
// decided them.  `empty` and `room` count what is arriving this tick, so a
// sequencer that decided a push last tick already sees it -- which is what
// keeps the mini marker's rule, "do not return to IDLE with writes still
// queued", true across the handover.
//
// Entry: { G, CLM, BSY, SRC[5:0], DST[5:0] } -- fifteen bits, the control
// word less its spare bit.  G = 0 is the event word.
//
//   mainboard.md 2.3, common-control.md 2.2, counters.md 9, console.md 2
`timescale 1ns/1ps
`include "exch.vh"

module ctl_queue #(
    parameter integer DEPTH   = 4,   // entries, a power of two, at most 16.  A model part
    parameter integer NP      = 2,   // entries a sequencer may hand over in one tick
    parameter integer EV_ROOM = 2    // an event word needs this many free, or is dropped
)(
    input                    clk,
    input                    rst_n,

    // ---- cable A, for the reader -----------------------------------------
    input      [2:0]         slotq,
    input                    cap_stb,
    input      [`SCANW-1:0]  scan,

    // ---- cable B -----------------------------------------------------------
    output                   sdata,
    output                   sclk,
    output                   wr,
    output                   oe,       // the '244 enable: this master holds the bus
    input                    hw_n,

    // ---- the card's bus access ---------------------------------------------
    input                    go,       // this master may START a transaction now
    output                   pending,  // it has something for the bus
    output                   empty,    // nothing queued, arriving, or in flight

    // ---- writes ------------------------------------------------------------
    input      [NP-1:0]      push_v,   // which slots carry an entry this tick
    input      [NP*15-1:0]   push_d,   // slot k in bits 15k+14:15k; lower slots go first
    output     [4:0]         room,     // free entries, less what is arriving
    output reg               ovf,      // sticky: a write was refused for want of room

    // ---- reads -------------------------------------------------------------
    input                    rd_req,   // one tick: read rd_port's primary octet
    input      [`PW-1:0]     rd_port,
    output                   rd_busy,  // a read is waiting or in flight
    output reg               rd_done,  // one tick: rd_word is valid
    output reg [7:0]         rd_word,

    // ---- for a bench -------------------------------------------------------
    output reg               sent      // one tick: a written word's WR has gone out
);
    // ---- the queue -----------------------------------------------------------
    // A power of two, so the indices wrap by themselves.
    function integer lg2(input integer v);
        integer b;
        begin lg2 = 0; for (b = v - 1; b > 0; b = b >> 1) lg2 = lg2 + 1; end
    endfunction
    localparam integer AW = lg2(DEPTH);
    localparam [4:0]   DP = DEPTH[4:0];

    reg [14:0]   q [0:DEPTH-1];
    reg [AW-1:0] wh;                     // head index
    reg [4:0]    cnt;                    // entries held

    // Where each arriving entry goes, and whether it is taken at all.  Worked
    // out in slot order, so an empty slot or a refused entry leaves no hole.
    // A sequencer gives each kind of write a fixed slot -- the unit gives each
    // direction its own -- and marks the ones it is sending.
    reg [NP-1:0] take;
    reg [AW-1:0] slot_of [0:NP-1];
    reg [4:0]    n_take;
    reg          refuse;
    integer      k;
    reg [4:0]    free_now;
    reg [AW-1:0] tail;
    always @* begin
        free_now = DP - cnt;
        tail     = wh + cnt[AW-1:0];
        n_take   = 5'd0;
        refuse   = 1'b0;
        take     = {NP{1'b0}};
        for (k = 0; k < NP; k = k + 1) begin
            slot_of[k] = {AW{1'b0}};
            if (push_v[k]) begin
                if (!push_d[k*15 + 14] && (free_now < EV_ROOM[4:0])) begin
                    // an event, and the queue is nearly full: drop it
                end else if (free_now == 5'd0) begin
                    refuse = 1'b1;
                end else begin
                    take[k]    = 1'b1;
                    slot_of[k] = tail + n_take[AW-1:0];
                    n_take     = n_take + 5'd1;
                    free_now   = free_now - 5'd1;
                end
            end
        end
    end

    // `room` already counts what is arriving, so a sequencer deciding now
    // sees its own push of last tick.
    reg [4:0] n_in;
    integer   j;
    always @* begin
        n_in = 5'd0;
        for (j = 0; j < NP; j = j + 1) n_in = n_in + {4'd0, push_v[j]};
    end
    assign room = (DP - cnt >= n_in) ? DP - cnt - n_in : 5'd0;

    // ---- the serialiser --------------------------------------------------------
    reg            s_req, s_strobe, s_g, s_bsy, s_clm;
    reg [`PW-1:0]  s_dst, s_src;
    wire           s_busy;
    ctl_write u_ser (
        .clk(clk), .rst_n(rst_n), .req(s_req), .strobe(s_strobe), .g(s_g),
        .dst(s_dst), .src(s_src), .bsy(s_bsy), .clm(s_clm),
        .busy(s_busy), .sdata(sdata), .sclk(sclk), .wr(wr));

    // ---- the reader ------------------------------------------------------------
    reg        r_arm;
    wire       r_busy, r_done;
    wire [7:0] r_word;
    word_rx u_rx (
        .clk(clk), .rst_n(rst_n), .slotq(slotq), .cap_stb(cap_stb), .scan(scan),
        .hw_n(hw_n), .arm(r_arm), .busy(r_busy), .done(r_done), .word(r_word));

    // ---- the transaction -------------------------------------------------------
    localparam [1:0] T_IDLE = 2'd0, T_WRITE = 2'd1, T_POINT = 2'd2, T_READ = 2'd3;
    reg [1:0]      t;
    reg            rd_want;
    reg [`PW-1:0]  rd_at;
    reg            s_busy_d;

    assign oe      = (t != T_IDLE);
    assign rd_busy = rd_want || (t == T_POINT) || (t == T_READ);
    assign pending = (cnt != 5'd0) || (push_v != {NP{1'b0}}) || rd_busy;
    assign empty   = !pending && (t == T_IDLE);

    wire [14:0] head = q[wh];

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wh <= {AW{1'b0}}; cnt <= 5'd0; ovf <= 1'b0;
            for (i = 0; i < DEPTH; i = i + 1) q[i] <= 15'd0;
            s_req <= 1'b0; s_strobe <= 1'b1; s_g <= 1'b1; s_bsy <= 1'b0; s_clm <= 1'b0;
            s_dst <= {`PW{1'b0}}; s_src <= {`PW{1'b0}};
            r_arm <= 1'b0; t <= T_IDLE; rd_want <= 1'b0; rd_at <= {`PW{1'b0}};
            rd_done <= 1'b0; rd_word <= 8'd0; s_busy_d <= 1'b0; sent <= 1'b0;
        end else begin
            s_req   <= 1'b0;
            r_arm   <= 1'b0;
            rd_done <= 1'b0;
            sent    <= 1'b0;
            s_busy_d <= s_busy;

            if (refuse) ovf <= 1'b1;
            for (i = 0; i < NP; i = i + 1)
                if (take[i]) q[slot_of[i]] <= push_d[i*15 +: 15];

            if (rd_req) begin rd_want <= 1'b1; rd_at <= rd_port; end

            case (t)
            // WRITES BEFORE READS.  A hold, a seize or a CLAIM is late the
            // moment a pass goes by; a read is only information.
            T_IDLE: if (go && !s_busy) begin
                if (cnt != 5'd0) begin
                    s_g <= head[14]; s_clm <= head[13]; s_bsy <= head[12];
                    s_src <= head[11:6]; s_dst <= head[5:0]; s_strobe <= 1'b1;
                    s_req <= 1'b1;
                    wh <= wh + 1'b1;
                    t  <= T_WRITE;
                end else if (rd_want) begin
                    // the pointing word: DST names the port, WR suppressed
                    s_g <= 1'b1; s_clm <= 1'b0; s_bsy <= 1'b0;
                    s_src <= {`PW{1'b0}}; s_dst <= rd_at; s_strobe <= 1'b0;
                    s_req <= 1'b1;
                    rd_want <= 1'b0;
                    t  <= T_POINT;
                end
            end
            T_WRITE: if (s_busy_d && !s_busy) begin sent <= 1'b1; t <= T_IDLE; end
            // The pointing word is in every block's '164s once the
            // serialiser goes idle; only then may the reader start.
            T_POINT: if (s_busy_d && !s_busy) begin r_arm <= 1'b1; t <= T_READ; end
            T_READ:  if (r_done) begin
                         rd_word <= r_word; rd_done <= 1'b1; t <= T_IDLE;
                     end
            default: t <= T_IDLE;
            endcase

            // The count moves once a tick, by what arrived less what left.
            cnt <= cnt + n_take - (((t == T_IDLE) && go && !s_busy && (cnt != 5'd0)) ? 5'd1 : 5'd0);
        end
    end

    wire _unused = &{1'b0, r_busy, 1'b0};
endmodule
