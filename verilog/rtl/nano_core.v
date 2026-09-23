// nano_core -- nano-marker.md §4: scanner, probe, write engine, sequencer.
//
// mini_core with everything a network unit needed taken out, and three things
// squeezed:
//
//   * **No write queue.**  mini_core carries four 15-bit slots and a pair of
//     pointers.  A nanomarker never has more than two writes outstanding, and
//     the second is the first with DST and SRC swapped -- one select on the
//     '157 mux.  What is left is `wp` / `wp_two` / `wp_sec` and the far end.
//   * **No `called` register.**  The register's six-bit store already holds
//     {h, s} in port order (nano_reg), so the probe compares the scanner
//     against it directly.
//   * **Presence off the card word, without reading it.**  All-zero is the
//     reserved none/OOS word (`extensions.md` §2.2) and an open slot floats to
//     it, so a port is fitted exactly when the word line asserts at some
//     bit-time of the visit.  That is an accumulator and a holding FF -- two
//     flip-flops and a gate -- not a '164 and an eight-input NOR.  A hunt
//     skips an empty slot instead of patching the caller to silence, which is
//     what lets two MF2 cards at 10 and 14 be one group with gaps between.
//     A dialled number lands on the same test: an unequipped slot is
//     cannot-complete, as it is on the full marker.
//   * **No 64-bit trunk mask.**  A hunt group is one strapped block
//     (`UP_BLK`, three DIP switches against `scan[5:3]`) instead of
//     UPLINK_MASK, which on a board is eight '151s or a PROM.
//
// One hunt serves two keys.  Key 1 hunts the uplink block, rotary from
// wherever the scanner is.  Key 0 hunts the operator at 04-07, in fixed order
// from 04 (mvp.md: 04 is the operator's home).  The difference is one
// flip-flop, a three-input NOR and a select.
//
// The caller's address is the register's own port latch, which nano_reg holds
// past release, so the core does not keep a second copy of it.
`timescale 1ns/1ps
(* keep_hierarchy *)
module nano_core #(
    parameter [5:0]   DIALTONE = 6'o01,
    parameter [5:0]   NOGO     = 6'o03,
    parameter         LEAF     = 1'b1,
    parameter [2:0]   UP_BLK   = 3'd1,
    parameter         OP_EN    = 1'b1,
    parameter [2:0]   OP_BLK   = 3'd0
)(
    input            clk,
    input            rst_n,
    input      [2:0] slotq,
    input      [2:0] tick,
    input            oct_stb,
    input      [7:0] ha,
    input            pb_busy,
    input            pb_word,

    // register
    input            r_busy,
    input            r_gone,
    input            r_nodig,
    input            r_hook,
    input      [1:0] r_ndig,
    input      [5:0] r_digits,
    input      [5:0] r_port,
    output reg       r_attach,
    output reg       r_release,
    output reg [5:0] r_aport,

    // serialiser
    input            ser_busy,
    output reg       ser_req,
    output reg       ser_strobe,
    output reg [5:0] ser_dst, ser_src,
    output reg       ser_bsy, ser_clm, ser_g,

    output     [2:0] scan_port,
    // The two strobes that go with SCAN on cable B (mainboard.md 2.3.3).
    // ADVANCE is the scanner's own count enable gated by the clock, so a
    // visit with no ADVANCE is a repeated one; START is a NOR of the six
    // counter outputs, high through port 00's visit.
    output           scan_adv,
    output           scan_start,
    output reg       wr_stb,
    output reg [5:0] wr_dst,
    output reg [5:0] wr_src,
    output reg       wr_bsy,
    output reg       wr_clm
);
    // ---- scanner: 6-bit count, billed as one HC393 -----------------------
    reg [5:0] scan;
    wire [3:0] _s1, _s2;
    hc393 u_scan_bom (
        .clk(clk), .rst_n(rst_n), .tick(1'b0),
        .mr1(1'b0), .ce1(1'b0), .q1(_s1),
        .mr2(1'b0), .ce2(1'b0), .q2(_s2)
    );

    // ---- probe: HC151 of HA + capture FFs --------------------------------
    wire ha_bit;
    mux8 u_ph (.d(ha), .s(scan[5:3]), .y(ha_bit));
    reg  m_acc, b_acc, w_acc;
    reg  p_m, p_busy, p_word;
    reg  [5:0] p_port;
    reg  visit, pv, p_valid;
    reg  [2:0] pb_blk;
    reg        probe_dirty;

    assign scan_port = scan[2:0];
    assign scan_adv    = oct_stb & pv;
    assign scan_start  = (scan == 6'd0);

    // ---- write engine ----------------------------------------------------
    localparam WS_DT = 3'd0,   // caller <- dial tone, BUSY
               WS_ON = 3'd1,   // caller <- 00,        BUSY   (tone off)
               WS_NG = 3'd2,   // caller <- 03,        BUSY
               WS_CL = 3'd3,   // caller <- 00,        clear  (let go)
               WS_PR = 3'd4;   // caller <-> far, both BUSY

    reg        wp, wp_two, wp_sec;
    reg  [2:0] wp_sel;
    reg  [5:0] wp_far;
    reg  [1:0] wst;
    reg        att_d;

    reg  [5:0] d_dst, d_src;
    reg        d_bsy;
    always @* begin
        case (wp_sel)
        WS_DT:   begin d_dst = r_port; d_src = DIALTONE; d_bsy = 1'b1; end
        WS_ON:   begin d_dst = r_port; d_src = 6'o00;    d_bsy = 1'b1; end
        WS_NG:   begin d_dst = r_port; d_src = NOGO;     d_bsy = 1'b1; end
        WS_CL:   begin d_dst = r_port; d_src = 6'o00;    d_bsy = 1'b0; end
        default: if (wp_sec) begin d_dst = wp_far; d_src = r_port; d_bsy = 1'b1; end
                 else        begin d_dst = r_port; d_src = wp_far; d_bsy = 1'b1; end
        endcase
    end

    // ---- sequencer -------------------------------------------------------
    localparam S_IDLE = 2'd0, S_COLLECT = 2'd1, S_PROBE = 2'd2, S_HUNT = 2'd3;
    reg [1:0] sst;
    reg       f1, up_seen, gone_pend, nodig_pend, op_hunt;
    reg [2:0] up_first;
    reg [1:0] hold;

    // Which group this hunt is walking, and where it may begin.  The uplink
    // is rotary -- it starts at whatever port the scanner is on -- and the
    // operator is fixed order, held off until 04 comes round so 04 answers
    // first whenever it is free.
    wire       in_grp = op_hunt ? ((p_port[5:3] == OP_BLK) && p_port[2])
                                : (p_port[5:3] == UP_BLK);
    wire       at_home = !op_hunt || (p_port[2:0] == 3'd4);
    wire       may_take = up_seen | at_home;

    wire [2:0] dg0 = r_digits[2:0];    // the first key, while ndig == 1
    wire [5:0] num = r_digits;         // the called port, once ndig == 2

    task wpush(input [2:0] s, input two, input [5:0] far);
        begin
            wp <= 1'b1; wp_sel <= s; wp_two <= two; wp_sec <= 1'b0;
            wp_far <= far;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan <= 0;
            m_acc <= 0; b_acc <= 0; w_acc <= 0;
            p_m <= 0; p_busy <= 0; p_word <= 0; p_port <= 0; visit <= 0;
            pv <= 0; p_valid <= 0; pb_blk <= 0; probe_dirty <= 1'b1;
            wp <= 0; wp_two <= 0; wp_sec <= 0; wp_sel <= 0; wp_far <= 0;
            wst <= 0; att_d <= 0;
            wr_stb <= 1'b0; wr_dst <= 0; wr_src <= 0; wr_bsy <= 0; wr_clm <= 0;
            ser_req <= 0; ser_strobe <= 0; ser_dst <= 0; ser_src <= 0;
            ser_bsy <= 0; ser_clm <= 0; ser_g <= 1'b1;
            r_attach <= 0; r_release <= 0; r_aport <= 0;
            sst <= S_IDLE; f1 <= 0; hold <= 0;
            up_seen <= 0; up_first <= 0; gone_pend <= 0; nodig_pend <= 0;
            op_hunt <= 0;
        end else begin
            r_attach  <= 1'b0;
            r_release <= 1'b0;
            visit     <= 1'b0;
            wr_stb    <= 1'b0;
            att_d     <= r_attach;

            // ---- scanner and probe ---------------------------------------
            if (tick == 3'd4 && slotq == scan[2:0]) begin
                m_acc <= ha_bit;
                b_acc <= pb_busy;
            end
            // The word is 16 bits at 128 kHz across the visit, but the only
            // thing wanted from it is whether any bit was a 1: all-zero is
            // none/OOS and nothing else is.  So accumulate, do not shift.
            if (oct_stb) begin
                p_m <= m_acc; p_busy <= b_acc; p_port <= scan;
                p_word  <= w_acc;
                w_acc   <= 1'b0;
                p_valid <= pv;
                visit <= 1'b1;
                if (pv) scan <= scan + 1'b1;
                pv    <= 1'b1;
            end else if (pb_word)
                w_acc <= 1'b1;
            if (ser_busy || ser_req || pb_blk != scan[5:3])
                pv <= 1'b0;
            if (oct_stb && pv && scan[2:0] == 3'd7) probe_dirty <= 1'b1;

            // ---- serialiser: the pending write, else name the block ------
            ser_req <= 1'b0;
            case (wst)
            2'd0: if (!ser_busy && !ser_req && !r_attach && !att_d) begin
                      if (wp) begin
                          ser_dst <= d_dst;  ser_src <= d_src;
                          ser_bsy <= d_bsy;  ser_clm <= 1'b0;
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
                          probe_dirty <= 1'b1;
                          wr_stb <= 1'b1; wr_dst <= ser_dst; wr_src <= ser_src;
                          wr_bsy <= ser_bsy; wr_clm <= ser_clm;
                          if (wp_two && !wp_sec) wp_sec <= 1'b1;
                          else begin
                              wp <= 1'b0; wp_two <= 1'b0; wp_sec <= 1'b0;
                          end
                      end
                      wst <= 2'd0;
                  end
            default: wst <= 2'd0;
            endcase

            if (hold != 2'd0) hold <= hold - 1'b1;

            // The register can let go (CLR, or the no-digit timer) while a
            // write is still shifting out.  Hold the event until the engine
            // is free -- there is no queue to drop it into.
            if (r_gone) begin
                gone_pend  <= 1'b1;
                nodig_pend <= r_nodig;
            end

            // ---- the call ------------------------------------------------
            if (sst != S_IDLE && gone_pend && !wp) begin
                if (nodig_pend) wpush(WS_NG, 1'b0, 6'd0);
                else            wpush(WS_CL, 1'b0, 6'd0);
                sst <= S_IDLE; f1 <= 1'b0;
                gone_pend <= 1'b0; nodig_pend <= 1'b0;
            end else case (sst)
            S_COLLECT: if (hold == 2'd0 && !wp) begin
                if (!f1 && r_ndig >= 2'd1) begin
                    if (dg0 == 3'd0) begin
                        // 0, 8 and 9 all count as 0, so all three reach the
                        // operator -- misdial to the operator, not optional.
                        if (OP_EN) begin
                            wpush(WS_ON, 1'b0, 6'd0);
                            op_hunt <= 1'b1; up_seen <= 1'b0; sst <= S_HUNT;
                        end else begin
                            wpush(WS_NG, 1'b0, 6'd0);
                            r_release <= 1'b1; sst <= S_IDLE;
                        end
                    end else if (LEAF && dg0 == 3'd1) begin
                        wpush(WS_ON, 1'b0, 6'd0);
                        op_hunt <= 1'b0; up_seen <= 1'b0; sst <= S_HUNT;
                    end else begin
                        wpush(WS_ON, 1'b0, 6'd0);
                        f1 <= 1'b1;
                    end
                end else if (f1 && r_ndig >= 2'd2) begin
                    sst <= S_PROBE;
                end
            end
            S_HUNT: if (visit && p_valid && !wp && in_grp && may_take) begin
                if (!p_m && !p_busy && p_word) begin
                    if (!r_hook) begin
                        wpush(WS_CL, 1'b0, 6'd0);
                        r_release <= 1'b1; sst <= S_IDLE;
                    end else begin
                        wpush(WS_PR, 1'b1, p_port);
                        r_release <= 1'b1; sst <= S_IDLE;
                    end
                end else if (up_seen && p_port[2:0] == up_first) begin
                    wpush(WS_NG, 1'b0, 6'd0);
                    r_release <= 1'b1; sst <= S_IDLE;
                end else if (!up_seen) begin
                    up_seen <= 1'b1; up_first <= p_port[2:0];
                end
            end
            S_PROBE: if (visit && p_valid && !wp && p_port == num) begin
                if (!r_hook) begin
                    wpush(WS_CL, 1'b0, 6'd0);
                    r_release <= 1'b1; sst <= S_IDLE; f1 <= 1'b0;
                end else if (num == r_port || p_m || p_busy || !p_word) begin
                    // !p_word is an unequipped slot.  The full marker gives
                    // cannot-complete on one (mvp.md); the mini-marker patches
                    // the caller to it and the write into the absent latch is
                    // ignored, which is silence with no way to tell why.  One
                    // more input on this OR buys the marker's answer.
                    wpush(WS_NG, 1'b0, 6'd0);
                    r_release <= 1'b1; sst <= S_IDLE; f1 <= 1'b0;
                end else begin
                    wpush(WS_PR, 1'b1, num);
                    r_release <= 1'b1; sst <= S_IDLE; f1 <= 1'b0;
                end
            end
            default: ;
            endcase

            // ---- seizure: M and not BUSY, register free -------------------
            if (sst == S_IDLE && !r_busy && !wp && !gone_pend &&
                visit && p_valid && p_m && !p_busy) begin
                r_attach <= 1'b1; r_aport <= p_port;
                wpush(WS_DT, 1'b0, 6'd0);
                sst <= S_COLLECT; f1 <= 1'b0; hold <= 2'd3;
            end
        end
    end

    wire _unused_scan = |{_s1, _s2};
endmodule
