// monitor -- the seeker, as a POOL.  exch-monitor.md.
//
// The only part of the network that reads a digit it was not sent, so it is the
// part that must never be wrong.  It sits on a block that holds trunks and
// reads its trunk ports' M and BUSY lines directly; it never touches the fabric.
//
//   idle      the trunk's M is low
//   seized    M rises, AND A MONITOR SAW IT RISE      -> count this seizure
//   counting  register.md 2's windows, on that M
//   decide    first digit is our e   -> read one digit more
//             second is our b        -> CLAIM
//             either 8 or 9          -> reserved: let go
//             anything else          -> let go, at once
//   done      nothing more until the trunk releases
//
// A POOL, NOT ONE A CHANNEL (4).  One scanner steps the block's eight slots on
// the 8 kHz octet mark; a fresh seizure goes to whichever cell is free, and if
// none is, "the seizure goes unwatched here, for good" -- the exchange still
// passes the call on, it just cannot be the one that owns it.  4 sizes the pool:
// two a block to four exchanges, three to twenty, four to thirty-six, five
// beyond, and the figure is the loss to callers whose calls this exchange owns.
//
// THE SEIZURE RULE HAS THREE TERMS, not the two of 4, and the third is needed
// as soon as an exchange has outgoing trunks of its own:
//
//   M high now, M low at the last visit, and BUSY low AT THE LAST VISIT.
//
// Rule 1 -- "only a seizure whose rise it saw" -- is the second term, and it is
// what keeps a monitor that attached late, in the pause BETWEEN two digits,
// from counting b as e and h as b.  The third term tells an arriving seizure
// from a CLAIM COMING BACK: backward A rising on this exchange's own outgoing
// trunk satisfies the first two exactly, and without the third a monitor is
// held for the whole of every call the exchange transits.  It must be BUSY as
// of the last visit and not BUSY now, because this scanner covers eight slots
// while the marker's covers sixty-four ports: the marker reaches an incoming
// seizure first about one time in eight, and a live BUSY test throws those
// away.  The two cases differ in ORDER, not in state -- this exchange writes
// BUSY before the far end's answer raises M -- so the last visit is what
// separates them.
`timescale 1ns/1ps

module monitor #(
    parameter integer NMON = 2,              // cells in the pool (4)
    parameter [2:0]   OWN_E = 3'd0,
    parameter [2:0]   OWN_B = 3'd0,
    parameter [2:0]   BLOCK = 3'd0,          // which block these eight slots are
    parameter integer HIT = 8, ID = 128, CLR = 256
)(
    input            clk,
    input            rst_n,
    input            oct_stb,                // 8 kHz: one slot a visit, eight in a ms
    input            tick_1k,
    input      [7:0] m,                      // the block's eight ports' M, direct
    input      [7:0] busy,                   // and their BUSY, from the same block
    input      [7:0] chan_mask,              // which slots the trunk card owns

    // A claim is a REQUEST, held until the marker acknowledges it.  As a bare
    // pulse it could be lost: every cell counts on the same 1 kHz tick, so two
    // calls whose last pulse ended in the same millisecond strobe together, and
    // two pools on one exchange can do the same.  A lost claim is a call this
    // exchange owned and never took -- the one thing 4 sizes the pool to avoid.
    output           claim,
    output     [5:0] claim_port,
    input            claim_ack,
    output           held,                   // any cell counting
    output           all_busy                // a seizure now would go unwatched
);
    localparam IDLE = 2'd0, WANT_E = 2'd1, WANT_B = 2'd2, DONE = 2'd3;

    reg  [2:0]          scan;
    reg  [7:0]          seen, seen_b;
    reg  [NMON-1:0]     c_held;
    reg  [3*NMON-1:0]   c_slot;
    reg  [2*NMON-1:0]   c_st;
    reg  [10*NMON-1:0]  c_low;
    reg  [NMON-1:0]     c_want;              // decided to claim, not yet acknowledged

    wire [NMON-1:0]     d_stb, d_clr;
    wire [4*NMON-1:0]   d_cnt;

    assign held     = |c_held;
    assign all_busy = &c_held;
    assign claim    = |c_want;

    integer w;
    reg [NMON-1:0] first_want;               // one-hot: the cell being presented
    reg [2:0]      want_slot;
    always @* begin
        first_want = {NMON{1'b0}};
        want_slot  = 3'd0;
        for (w = 0; w < NMON; w = w + 1)
            if (c_want[w] && first_want == {NMON{1'b0}}) begin
                first_want[w] = 1'b1;
                want_slot     = c_slot[w*3 +: 3];
            end
    end
    assign claim_port = {BLOCK, want_slot};

    // A fresh seizure: the three terms above.
    wire fresh = chan_mask[scan] && m[scan] && !seen[scan] && !seen_b[scan];

    // Which cell takes it -- the first free one.  None free, and the seizure
    // goes unwatched here, for good.
    integer j;
    reg [NMON-1:0] take;
    always @* begin
        take = {NMON{1'b0}};
        for (j = 0; j < NMON; j = j + 1)
            if (!c_held[j] && take == {NMON{1'b0}}) take[j] = 1'b1;
    end

    genvar g;
    generate for (g = 0; g < NMON; g = g + 1) begin : seeker
        pulse_rx #(.HIT(HIT), .ID(ID), .CLR(CLR)) u_rx (
            .clk(clk), .rst_n(rst_n), .tick_1k(tick_1k),
            .arm(c_held[g]), .m(m[c_slot[g*3 +: 3]]),
            .cnt(d_cnt[g*4 +: 4]), .dig_stb(d_stb[g]), .clear(d_clr[g]),
            .counting(), .brk_stb());
    end endgenerate

    integer k;
    reg [3:0] n;
    reg [2:0] v;
    reg       bad;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan <= 0; seen <= 0; seen_b <= 0;
            c_held <= 0; c_slot <= 0; c_st <= 0; c_low <= 0; c_want <= 0;
        end else begin
            // the marker took the one being presented
            if (claim_ack) c_want <= c_want & ~first_want;

            if (oct_stb) begin
                if (fresh)
                    for (k = 0; k < NMON; k = k + 1)
                        if (take[k]) begin
                            c_held[k]           <= 1'b1;
                            c_slot[k*3 +: 3]    <= scan;
                            c_st  [k*2 +: 2]    <= WANT_E;
                            c_low [k*10 +: 10]  <= 10'd0;
                        end
                seen[scan]   <= m[scan];
                seen_b[scan] <= busy[scan];
                scan         <= scan + 1'b1;
            end

            for (k = 0; k < NMON; k = k + 1) if (c_held[k]) begin
                n   = d_cnt[k*4 +: 4];
                // e and b are 0-7 and a dialled 0 is ten pulses; 8 and 9 reserved
                v   = (n == 4'd10) ? 3'd0 : n[2:0];
                bad = (n == 4'd8) || (n == 4'd9) || (n > 4'd10);

                if (d_stb[k]) begin
                    case (c_st[k*2 +: 2])
                    WANT_E: if (bad || v != OWN_E) begin
                                c_held[k] <= 1'b0; c_st[k*2 +: 2] <= IDLE;
                            end else c_st[k*2 +: 2] <= WANT_B;
                    WANT_B: if (bad || v != OWN_B) begin
                                c_held[k] <= 1'b0; c_st[k*2 +: 2] <= IDLE;
                            end else begin
                                c_want[k]      <= 1'b1;   // ours: ask the marker
                                c_st[k*2 +: 2] <= DONE;   // two digits and no more
                            end
                    default: ;
                    endcase
                end

                // the trunk releasing frees the cell: M low for 256 ms
                if (tick_1k) begin
                    if (m[c_slot[k*3 +: 3]]) c_low[k*10 +: 10] <= 10'd0;
                    else if (c_low[k*10 +: 10] == CLR[9:0]) begin
                        c_held[k] <= 1'b0; c_st[k*2 +: 2] <= IDLE;
                        c_low[k*10 +: 10] <= 10'd0;
                        c_want[k] <= 1'b0;        // the caller gave up first
                    end else c_low[k*10 +: 10] <= c_low[k*10 +: 10] + 1'b1;
                end
                if (d_clr[k]) begin
                    c_held[k] <= 1'b0; c_st[k*2 +: 2] <= IDLE; c_want[k] <= 1'b0;
                end
            end
        end
    end
endmodule
