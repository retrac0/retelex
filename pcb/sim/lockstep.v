// lockstep.v -- the boards in LOCKSTEP with the RTL, inside any newimpl bench.
//
// A module called `block`, with block.v's parameters and ports, holding BOTH:
//   block_ref     newimpl/rtl/block.v, renamed (run.py makes the copy)
//   block_boards  pcb/out/gen/block_stack.v (mkstack.py), renamed: the three boards
// on the same inputs.  The exchange runs on the REFERENCE's outputs (shadow
// mode), so the bench sees exactly the RTL's behaviour, and every output of the
// boards is compared with the reference's for the whole of the run -- not only
// where the bench happens to look.
//
// WHEN A COMPARISON COUNTS.  At tick 5 of every cell -- one master tick after
// cap_stb, the edge on which the RTL's ports capture -- each output bit of the
// boards must equal the reference's IF BOTH have held their values for STABLE
// master ticks, the tick just gone included.  The boards are gates with
// delays and the RTL is not; an input the bench moves off the clock reaches
// one a few ns before the other; and the boards' '273 takes a write on /WR's
// leading edge, one tick before port.v's wr_edge.  Each is a skew of a tick or
// less, and waiting for both sides to settle absorbs it.  A difference that
// lasts is a difference: once both are steady they must agree.  hc_out counts
// only while JUMPERED (an unjumpered block's '244 lets go; mainboard.v reads
// nothing from it).
//
// AFTER A WRITE, c_rx for a frame and a_rx for a pass are not compared.  A
// '273 that changes one tick early can move a port's capture into the frame
// (C) or the pass (E) before the RTL's: the same connection, begun one
// capture sooner.  Measured in tb_ha before this mask: one port, one frame.
//
// Every mismatch prints a line starting BLOCK-STACK (the first few per output),
// and run.py fails a bench on any such line.
`timescale 1ns/1ps
`include "exch.vh"

module lk_cmp #(
    parameter integer   W      = 1,
    parameter integer   STABLE = 3,
    parameter [8*8-1:0] NAME   = "out"
)(
    input          clk,
    input          rst_n,
    input          en,          // a sample instant
    input          mask,        // do not compare now
    input  [W-1:0] ref_v,
    input  [W-1:0] brd_v
);
    reg  [W-1:0] prev, prevb;
    integer      age [0:W-1];
    integer      ageb [0:W-1];
    integer      n_bad = 0, n_chk = 0, i;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            prev <= {W{1'b0}}; prevb <= {W{1'b0}};
            for (i = 0; i < W; i = i + 1) begin age[i] <= 0; ageb[i] <= 0; end
        end else begin
            prev <= ref_v; prevb <= brd_v;
            for (i = 0; i < W; i = i + 1) begin
                age[i]  <= (ref_v[i] !== prev[i])  ? 0 : (age[i]  < 100000 ? age[i]  + 1 : age[i]);
                ageb[i] <= (brd_v[i] !== prevb[i]) ? 0 : (ageb[i] < 100000 ? ageb[i] + 1 : ageb[i]);
            end
            if (en && !mask)
                for (i = 0; i < W; i = i + 1)
                    if (age[i] >= STABLE && ageb[i] >= STABLE &&
                        ref_v[i] === prev[i] && brd_v[i] === prevb[i]) begin
                        n_chk = n_chk + 1;
                        if (brd_v[i] !== ref_v[i]) begin
                            n_bad = n_bad + 1;
                            if (n_bad <= 4)
                                $display("  BLOCK-STACK %m: %0s[%0d] boards %b, RTL %b, at %0t (RTL steady %0d ticks, boards %0d)",
                                         NAME, i, brd_v[i], ref_v[i], $time, age[i], ageb[i]);
                        end
                    end
        end
    final if (n_bad != 0)
        $display("  BLOCK-STACK %m: %0s differs at %0d of %0d samples", NAME, n_bad, n_chk);
endmodule

module block #(
    parameter [2:0]  BLOCK       = 3'd0,
    parameter        JUMPERED    = 1'b1,
    parameter [7:0]  PORT_FITTED = 8'hFF,
    parameter [8:0]  T_ARM       = 9'd16,
    parameter [8:0]  T_REL       = 9'd256
)(
    input                   clk,
    input                   rst_n,
    input      [2:0]        slot,
    input      [2:0]        slotq,
    input                   cap_stb,
    input                   frame_stb,
    input                   tick_1k,
    input      [`SCANW-1:0] scan,
    input                   fill,
    input                   rbt,
    input                   ring_cad_n,
    input      [7:0]        hc,
    output                  hc_out,
    input                   ha_n,
    output                  ha_pd,
    output                  hb_pd,
    input      [7:0]        c_tx,
    input      [7:0]        a_tx,
    input      [7:0]        ans_n,
    input      [7:0]        word_n,
    output     [7:0]        c_rx,
    output     [7:0]        a_rx,
    input                   mute_blk,
    input                   sdata,
    input                   sclk,
    input                   wr,
    input                   ws_n,
    output                  hw_pd,
    output     [7:0]        port_busy
);
    wire       hc_out_b, ha_pd_b, hb_pd_b, hw_pd_b;
    wire [7:0] c_rx_b, a_rx_b, busy_b;

    block_ref #(.BLOCK(BLOCK), .JUMPERED(JUMPERED), .PORT_FITTED(PORT_FITTED),
                .T_ARM(T_ARM), .T_REL(T_REL)) u_ref (
        .clk(clk), .rst_n(rst_n), .slot(slot), .slotq(slotq), .cap_stb(cap_stb),
        .frame_stb(frame_stb), .tick_1k(tick_1k), .scan(scan), .fill(fill), .rbt(rbt),
        .ring_cad_n(ring_cad_n), .hc(hc), .hc_out(hc_out), .ha_n(ha_n), .ha_pd(ha_pd),
        .hb_pd(hb_pd), .c_tx(c_tx), .a_tx(a_tx), .ans_n(ans_n), .word_n(word_n),
        .c_rx(c_rx), .a_rx(a_rx), .mute_blk(mute_blk), .sdata(sdata), .sclk(sclk),
        .wr(wr), .ws_n(ws_n), .hw_pd(hw_pd), .port_busy(port_busy));

    block_boards #(.BLOCK(BLOCK), .JUMPERED(JUMPERED), .PORT_FITTED(PORT_FITTED),
                   .T_ARM(T_ARM), .T_REL(T_REL)) u_brd (
        .clk(clk), .rst_n(rst_n), .slot(slot), .slotq(slotq), .cap_stb(cap_stb),
        .frame_stb(frame_stb), .tick_1k(tick_1k), .scan(scan), .fill(fill), .rbt(rbt),
        .ring_cad_n(ring_cad_n), .hc(hc), .hc_out(hc_out_b), .ha_n(ha_n), .ha_pd(ha_pd_b),
        .hb_pd(hb_pd_b), .c_tx(c_tx), .a_tx(a_tx), .ans_n(ans_n), .word_n(word_n),
        .c_rx(c_rx_b), .a_rx(a_rx_b), .mute_blk(mute_blk), .sdata(sdata), .sclk(sclk),
        .wr(wr), .ws_n(ws_n), .hw_pd(hw_pd_b), .port_busy(busy_b));

    // The boards capture when /STB falls, at the START of tick 4; the RTL at the
    // clk edge that ENDS it.  Sampling on that edge would read the RTL's old
    // value against the boards' new one (measured: every c_rx change).  One
    // tick later both have settled.
    reg cmp_stb;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) cmp_stb <= 1'b0;
        else        cmp_stb <= cap_stb;

    // after any write: a frame's mask for c_rx, a pass's for a_rx
    reg        wr_d;
    reg [12:0] since_wr;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin wr_d <= 1'b0; since_wr <= 13'h1FFF; end
        else begin
            wr_d <= wr;
            if (wr && !wr_d)               since_wr <= 13'd0;
            else if (since_wr != 13'h1FFF) since_wr <= since_wr + 13'd1;
        end
    wire mask_c = since_wr < 13'd80;       // a frame is 64 ticks
    wire mask_a = since_wr < 13'd4200;     // a pass is 4096

    generate if (JUMPERED || PORT_FITTED != 8'd0) begin : cmp
        lk_cmp #(.W(1), .NAME("hc_out")) c_hc (.clk(clk), .rst_n(rst_n), .en(cmp_stb && JUMPERED), .mask(1'b0),
                                               .ref_v(hc_out), .brd_v(hc_out_b));
        lk_cmp #(.W(3), .NAME("planes")) c_pl (.clk(clk), .rst_n(rst_n), .en(cmp_stb), .mask(1'b0),
                                               .ref_v({hw_pd, hb_pd, ha_pd}), .brd_v({hw_pd_b, hb_pd_b, ha_pd_b}));
        lk_cmp #(.W(8), .NAME("c_rx")) c_cr (.clk(clk), .rst_n(rst_n), .en(cmp_stb), .mask(mask_c),
                                             .ref_v(c_rx), .brd_v(c_rx_b));
        lk_cmp #(.W(8), .NAME("a_rx")) c_ar (.clk(clk), .rst_n(rst_n), .en(cmp_stb), .mask(mask_a),
                                             .ref_v(a_rx), .brd_v(a_rx_b));
        lk_cmp #(.W(8), .NAME("busy")) c_bz (.clk(clk), .rst_n(rst_n), .en(cmp_stb), .mask(1'b0),
                                             .ref_v(port_busy), .brd_v(busy_b));
    end endgenerate
endmodule
