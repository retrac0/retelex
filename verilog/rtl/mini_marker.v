// mini_marker -- bring-up common control.  mini-marker.md.
//
// A scanner, a probe of M and BUSY, a sequencer, and one register inside.
// It does not read a card's option word and does not hunt a class.
// Two digits h s, two latch writes, and it leaves.
// Digit 1 is a highway until a network unit is fitted (mini-marker.md 8).
//
//   first key   1-7   highway h; wait for the slot digit s; called = h s
//               0 8 9 and 11-16   cannot-complete
//
// The register is pulse_reg.  restart is tied off here: nothing consumes a
// prefix until a unit is wired.  This is not network.md 9's outpulsing sender.
`timescale 1ns/1ps

module mini_marker #(
    parameter integer HIT      = 8,
    parameter integer ID       = 128,
    parameter integer CLR      = 256,
    parameter integer NODIG    = 12000,
    parameter [5:0]   DIALTONE = 6'o01,
    parameter [5:0]   NOGO     = 6'o03
)(
    input            clk,
    input            rst_n,

    // the clock card
    input      [2:0] slotq,
    input      [2:0] tick,
    input            frame_stb,
    input            oct_stb,
    input            tick_1k,

    // the probe: M off the A highway, BUSY off PB.  No word.
    input      [7:0] ha,
    input            pb_busy,

    // cable B, serial (mainboard.md 2.3)
    output           sdata,
    output           sclk,
    output           wr,

    // for a testbench
    output           reg_busy,
    output reg       wq_ovf,
    output reg       wr_stb,
    output reg [5:0] wr_dst,
    output reg [5:0] wr_src,
    output reg       wr_bsy,
    output reg       wr_clm
);
    // ---------------- the register, one, inside --------------------------
    wire        r_busy, r_gone, r_nodig;
    wire [2:0]  r_ndig;
    wire [19:0] r_digits;
    reg         r_attach, r_release;
    reg  [5:0]  r_aport;

    pulse_reg #(.HIT(HIT), .ID(ID), .CLR(CLR), .NODIG(NODIG)) u_reg (
        .clk(clk), .rst_n(rst_n), .slotq(slotq), .tick(tick), .tick_1k(tick_1k),
        .ha(ha),
        .attach(r_attach), .attach_port(r_aport), .attach_src(6'd0),
        .release_it(r_release), .restart(1'b0),
        .busy(r_busy), .port(), .src(),
        .ndig(r_ndig), .digits(r_digits),
        .gone(r_gone), .nodig(r_nodig), .brk());

    assign reg_busy = r_busy;

    // ---------------- scanner and probe ----------------------------------
    // Same listen structure as marker.v, minus the word shift register.
    // A visit while the serialiser named another block is discarded (rtl.md).
    reg [5:0] scan;
    reg       m_acc, b_acc;
    reg       p_m, p_busy;
    reg [5:0] p_port;
    reg       visit;
    reg       pv, p_valid;
    reg [2:0] pb_blk;

    // ---------------- write queue (four deep) and serialiser -------------
    // { BSY, SRC, DST }.  G is always 1, CLAIM always 0.
    reg [12:0] wq [0:3];
    reg [1:0]  wh, wt;
    reg [1:0]  wst;
    reg        ser_req, ser_strobe;
    reg [5:0]  ser_dst, ser_src;
    reg        ser_bsy, ser_clm, ser_g;
    reg        probe_dirty;
    wire       ser_busy;
    wire       w_pend = (wh != wt);

    ctl_write u_ser (.clk(clk), .rst_n(rst_n), .req(ser_req), .strobe(ser_strobe),
                     .g(ser_g),
                     .dst(ser_dst), .src(ser_src), .bsy(ser_bsy), .clm(ser_clm),
                     .busy(ser_busy), .sdata(sdata), .sclk(sclk), .wr(wr));

    task push(input [5:0] pt, input [5:0] sr, input b);
        begin
            if (wt + 2'd1 == wh) wq_ovf <= 1'b1;
            wq[wt] = {b, sr, pt}; wt = wt + 1'b1;
        end
    endtask

    // ---------------- a call ---------------------------------------------
    localparam M_IDLE    = 2'd0,
               M_COLLECT = 2'd1,
               M_PROBE   = 2'd2;

    reg [1:0]  mst;
    reg [5:0]  caller, called;
    reg [1:0]  hold;                   // attach takes a cycle to land (rtl.md 1)
    reg        f1;                     // first (highway) digit is in

    function [2:0] oct(input [4:0] c);
        oct = c[3] ? 3'd0 : c[2:0];
    endfunction

    wire [4:0] dg0 = r_digits[4:0];
    wire [4:0] dg1 = r_digits[9:5];
    wire [2:0] nd  = r_ndig;
    // first keys that are not a highway: anything outside 1-7
    // (0 is ten pulses, 8/9/11-16 are service)
    wire first_nogo = (dg0 < 5'd1) || (dg0 > 5'd7);

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan <= 0; m_acc <= 0; b_acc <= 0;
            p_m <= 0; p_busy <= 0; p_port <= 0; visit <= 0;
            pv <= 0; p_valid <= 0; pb_blk <= 0;
            wh <= 0; wt <= 0; wst <= 0; probe_dirty <= 1'b1; wq_ovf <= 1'b0;
            wr_stb <= 1'b0; wr_dst <= 0; wr_src <= 0; wr_bsy <= 0; wr_clm <= 0;
            ser_req <= 0; ser_strobe <= 0; ser_dst <= 0; ser_src <= 0;
            ser_bsy <= 0; ser_clm <= 0; ser_g <= 1'b1;
            r_attach <= 0; r_release <= 0; r_aport <= 0;
            mst <= M_IDLE; caller <= 0; called <= 0; hold <= 0; f1 <= 0;
            for (i = 0; i < 4; i = i + 1) wq[i] <= 13'd0;
        end else begin
            r_attach  <= 1'b0;
            r_release <= 1'b0;
            visit     <= 1'b0;
            wr_stb    <= 1'b0;

            // ---- probe -------------------------------------------------
            if (tick == 3'd4 && slotq == scan[2:0]) begin
                m_acc <= ha[scan[5:3]];
                b_acc <= pb_busy;
            end
            if (oct_stb) begin
                p_m <= m_acc; p_busy <= b_acc; p_port <= scan;
                p_valid <= pv;
                visit <= 1'b1;
                if (pv) scan <= scan + 1'b1;
                pv    <= 1'b1;
            end
            if (ser_busy || ser_req || pb_blk != scan[5:3])
                pv <= 1'b0;

            // ---- the write sequencer -----------------------------------
            if (oct_stb && pv && scan[2:0] == 3'd7) probe_dirty <= 1'b1;
            ser_req <= 1'b0;
            case (wst)
            2'd0: if (!ser_busy && !ser_req) begin
                      if (w_pend) begin
                          ser_dst <= wq[wh][5:0];  ser_src <= wq[wh][11:6];
                          ser_bsy <= wq[wh][12];   ser_clm <= 1'b0;
                          ser_g   <= 1'b1;
                          ser_strobe <= 1'b1; ser_req <= 1'b1; wst <= 2'd1;
                      end else if (probe_dirty) begin
                          ser_dst <= {scan[5:3], 3'd0}; ser_src <= 6'd0;
                          ser_bsy <= 1'b0; ser_clm <= 1'b0;
                          ser_g   <= 1'b1;
                          ser_strobe <= 1'b0; ser_req <= 1'b1;
                          probe_dirty <= 1'b0; wst <= 2'd1;
                      end
                  end
            2'd1: if (ser_busy) wst <= 2'd2;
            2'd2: if (!ser_busy) begin
                      pb_blk <= ser_dst[5:3];
                      if (ser_strobe) begin
                          wh <= wh + 1'b1; probe_dirty <= 1'b1;
                          wr_stb <= 1'b1; wr_dst <= ser_dst; wr_src <= ser_src;
                          wr_bsy <= ser_bsy; wr_clm <= ser_clm;
                      end
                      wst <= 2'd0;
                  end
            default: wst <= 2'd0;
            endcase

            // ---- the call ----------------------------------------------
            if (hold != 2'd0) hold <= hold - 1'b1;

            if (mst != M_IDLE && r_gone) begin
                if (r_nodig) push(caller, NOGO, 1'b1);
                mst <= M_IDLE; f1 <= 1'b0;
            end else case (mst)
            M_COLLECT: if (hold == 2'd0) begin
                if (!f1 && nd >= 3'd1) begin
                    if (first_nogo) begin
                        push(caller, NOGO, 1'b1);
                        r_release <= 1'b1; mst <= M_IDLE; f1 <= 1'b0;
                    end else begin
                        push(caller, 6'o00, 1'b1);          // dial tone off
                        f1 <= 1'b1;
                    end
                end else if (f1 && nd >= 3'd2) begin
                    called <= {oct(dg0), oct(dg1)}; mst <= M_PROBE;
                end
            end
            M_PROBE: if (visit && p_valid && p_port == called) begin
                if (called == caller || p_m || p_busy) begin
                    push(caller, NOGO, 1'b1);
                    r_release <= 1'b1; mst <= M_IDLE; f1 <= 1'b0;
                end else begin
                    push(caller, called, 1'b1);
                    push(called, caller, 1'b1);
                    r_release <= 1'b1; mst <= M_IDLE; f1 <= 1'b0;
                end
            end
            default: ;
            endcase

            // ---- a port wanting service --------------------------------
            if (visit && p_valid && p_m && !p_busy &&
                mst == M_IDLE && !r_busy) begin
                r_attach <= 1'b1; r_aport <= p_port;
                push(p_port, DIALTONE, 1'b1);
                caller <= p_port; mst <= M_COLLECT;
                f1 <= 1'b0; hold <= 2'd3;
            end
        end
    end
endmodule
