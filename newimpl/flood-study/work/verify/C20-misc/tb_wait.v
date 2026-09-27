// tb_wait -- VERIFY scratch bench for C20 finding wait-constant-doc-stale.
// Not part of the tree.
//
// The two cable-B masters as top_net fits them: the marker's ctl_queue
// (DEPTH 8, NP 2, go = /UREQ high, mini_marker.v:224-227) and the unit's
// (DEPTH 16, NP 5, EV_ROOM 6, go = granted), with the unit's request logic
// copied verbatim from net_unit.v:219-232 and WAIT taken from +wait=N.  Each
// trial pushes one marker word at tick 0 and one unit word at tick OFF, both
// registered as a sequencer's pushes are; the trial measures ticks with both
// '244s enabled (b_clash) and the gap from the marker's oe falling to the
// unit's oe rising.  OFF runs -4 .. 600.
`timescale 1ns/1ps
`include "exch.vh"

module tb_wait;
    reg clk = 1'b0, rst_n = 1'b0;
    always #122.070 clk = ~clk;

    reg  [1:0]  m_pv = 2'd0;
    reg  [29:0] m_pd = 30'd0;
    wire        m_sd, m_sc, m_wr, m_oe, m_pend, m_empty, m_ovf, m_sent;
    wire [4:0]  m_room;
    wire        ureq_n;
    ctl_queue #(.DEPTH(8), .NP(2)) mq (
        .clk(clk), .rst_n(rst_n), .sdata(m_sd), .sclk(m_sc), .wr(m_wr), .oe(m_oe),
        .go(ureq_n), .pending(m_pend), .empty(m_empty),
        .push_v(m_pv), .push_d(m_pd), .room(m_room), .ovf(m_ovf), .sent(m_sent));

    reg  [4:0]  u_pv = 5'd0;
    reg  [74:0] u_pd = 75'd0;
    wire        u_sd, u_sc, u_wr, u_oe, u_pend, u_empty, u_ovf, u_sent;
    wire [4:0]  u_room;
    reg         granted;
    reg  [11:0] wcnt;
    integer     WAITV;
    wire        want_bus = !u_empty;
    assign      ureq_n   = !want_bus;
    // net_unit.v:225-232, WAIT a run-time number here
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin granted <= 1'b0; wcnt <= 12'd0; end
        else if (!want_bus) begin granted <= 1'b0; wcnt <= 12'd0; end
        else if (!granted) begin
            if ({20'd0, wcnt} == WAITV - 1) granted <= 1'b1;
            else                           wcnt    <= wcnt + 12'd1;
        end
    end
    ctl_queue #(.DEPTH(16), .NP(5), .EV_ROOM(6)) uq (
        .clk(clk), .rst_n(rst_n), .sdata(u_sd), .sclk(u_sc), .wr(u_wr), .oe(u_oe),
        .go(granted), .pending(u_pend), .empty(u_empty),
        .push_v(u_pv), .push_d(u_pd), .room(u_room), .ovf(u_ovf), .sent(u_sent));

    integer tc = 0, tm = -1000, tu = -1000;
    integer clash = 0, m_fall = -1, u_rise = -1, m_len = 0, m_rise = -1;
    reg m_oe_d = 1'b0, u_oe_d = 1'b0;
    always @(posedge clk) begin
        tc <= tc + 1;
        m_pv <= (tc == tm) ? 2'b01 : 2'b00;
        m_pd <= {15'd0, 1'b1, 1'b0, 1'b1, 6'o01, 6'o20};
        u_pv <= (tc == tu) ? 5'b00001 : 5'b00000;
        u_pd <= {60'd0, 1'b1, 1'b0, 1'b1, 6'o00, 6'o11};
        m_oe_d <= m_oe; u_oe_d <= u_oe;
        if (m_oe && u_oe) clash <= clash + 1;
        if (!m_oe_d && m_oe) m_rise <= tc;
        if (m_oe_d && !m_oe) begin m_fall <= tc; m_len <= tc - m_rise; end
        if (!u_oe_d && u_oe) u_rise <= tc;
    end

    integer w, off, wi, tot_clash, min_gap, max_gap, min_gap_off, n_first, mlen;
    integer waits [0:5];
    initial begin
        waits[0] = 640; waits[1] = 549; waits[2] = 548; waits[3] = 547; waits[4] = 546; waits[5] = 500;
        WAITV = 640;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);
        for (wi = 0; wi < 6; wi = wi + 1) begin
            WAITV = waits[wi];
            tot_clash = 0; min_gap = 99999; max_gap = -99999; min_gap_off = 0; n_first = 0; mlen = 0;
            for (off = -4; off <= 600; off = off + 1) begin
                @(posedge clk);
                clash = 0; m_fall = -1; u_rise = -1; m_rise = -1;
                tm = tc + 2; tu = tc + 2 + off;
                repeat (2000) @(posedge clk);
                if (!(m_empty && u_empty)) $display("  trial off=%0d did not drain", off);
                tot_clash = tot_clash + clash;
                if (m_rise >= 0 && u_rise >= 0 && m_rise < u_rise) begin
                    // the marker went first: how long after its '244 let go did the unit's come on
                    n_first = n_first + 1; mlen = m_len;
                    if (u_rise - m_fall < min_gap) begin min_gap = u_rise - m_fall; min_gap_off = off; end
                    if (u_rise - m_fall > max_gap) max_gap = u_rise - m_fall;
                end
            end
            $display("  WAIT=%0d: clash ticks over all offsets %0d; marker first in %0d trials, its oe %0d ticks; unit oe after marker oe fell: min %0d (off %0d) max %0d ticks",
                     WAITV, tot_clash, n_first, mlen, min_gap, min_gap_off, max_gap);
        end
        $finish;
    end
endmodule
