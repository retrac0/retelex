// mini_core -- mini-marker.md scanner, probe, write queue, and call sequencer.
//
// Structural MSI where it maps cleanly (HC393 scanner, HC151 probe of HA);
// the call sequencer is the remaining control.  synth-hc blackboxes this
// module and bills it as the mvp.md marker estimate (without the register).
`timescale 1ns/1ps
(* keep_hierarchy *)
module mini_core #(
    parameter [5:0]   DIALTONE = 6'o01,
    parameter [5:0]   NOGO     = 6'o03,
    parameter         HAS_NET  = 1'b0,
    parameter         LEAF     = 1'b0,
    parameter [63:0]  TRUNK_MASK = 64'd0,
    parameter [63:0]  UPLINK_MASK = 64'd0
)(
    input            clk,
    input            rst_n,
    input      [2:0] slotq,
    input      [2:0] tick,
    input            frame_stb,
    input            oct_stb,
    input            tick_1k,
    input      [7:0] ha,
    input            pb_busy,

    // register levels / controls
    input            r_busy,
    input            r_gone,
    input            r_nodig,
    input            r_hook,
    input      [2:0] r_ndig,
    input     [15:0] r_digits,
    output reg       r_attach,
    output reg       r_release,
    output reg       r_restart_loc,
    output reg [5:0] r_aport,

    // serialiser
    input            ser_busy,
    output reg       ser_req,
    output reg       ser_strobe,
    output reg [5:0] ser_dst, ser_src,
    output reg       ser_bsy, ser_clm, ser_g,

    // probe out
    output     [5:0] probe_port,
    output     [2:0] scan_port,
    // The two strobes that go with SCAN on cable B (mainboard.md 2.3.3).
    // ADVANCE is the scanner's own count enable gated by the clock, so a
    // visit with no ADVANCE is a repeated one; START is a NOR of the six
    // counter outputs, high through port 00's visit.
    output           scan_adv,
    output           scan_start,
    output           probe_visit,
    output           probe_valid,
    output           probe_m,
    output           probe_busy,

    // network
    output reg       flood_go,
    output     [5:0] flood_caller,
    input            net_restart,
    input            net_done,
    input            net_nogo,
    input            net_local,
    input            net_att,
    input      [5:0] net_att_port,
    input      [3:0] net_nw,
    input     [47:0] net_wdst,
    input     [47:0] net_wsrc,
    input      [7:0] net_wbsy,
    input      [7:0] net_wclm,
    input      [7:0] net_wev,

    output reg       wq_ovf,
    output reg       wr_stb,
    output reg [5:0] wr_dst,
    output reg [5:0] wr_src,
    output reg       wr_bsy,
    output reg       wr_clm
);
    // ---- scanner: 6-bit count, billed as one HC393 ----------------------------
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
    reg  m_acc, b_acc;
    reg  p_m, p_busy;
    reg  [5:0] p_port;
    reg  visit, pv, p_valid;
    reg  [2:0] pb_blk;

    assign scan_port   = scan[2:0];
    assign scan_adv    = oct_stb & pv;
    assign scan_start  = (scan == 6'd0);
    assign probe_port  = p_port;
    assign probe_visit = visit;
    assign probe_valid = p_valid;
    assign probe_m     = p_m;
    assign probe_busy  = p_busy;

    // ---- write queue ----------------------------------------------------
    reg [14:0] wq [0:3];
    reg [1:0]  wh, wt, wst;
    reg        probe_dirty;
    wire       w_pend = (wh != wt);

    task push(input [5:0] pt, input [5:0] sr, input b, input c);
        begin
            if (wt + 2'd1 == wh) wq_ovf <= 1'b1;
            wq[wt] = {1'b1, c, b, sr, pt}; wt = wt + 1'b1;
        end
    endtask
    task push_ev(input [5:0] pt, input [5:0] code);
        begin
            if (wt + 2'd1 != wh)
                begin wq[wt] = {1'b0, 1'b1, 1'b0, code, pt}; wt = wt + 1'b1; end
        end
    endtask

    localparam M_IDLE=3'd0, M_COLLECT=3'd1, M_PROBE=3'd2, M_YIELD=3'd3, M_UPLINK=3'd4;
    reg [2:0]  mst;
    reg [5:0]  caller, called;
    reg [1:0]  hold;
    reg        f1, ctx_clm;
    reg [5:0]  up_start;
    reg        up_armed;

    assign flood_caller = caller;

    function [2:0] oct(input [3:0] c);
        oct = c[3] ? 3'd0 : c[2:0];
    endfunction

    wire [3:0] dg0 = r_digits[3:0];
    wire [3:0] dg1 = r_digits[7:4];
    wire [2:0] nd  = r_ndig;
    wire first_nogo = (dg0 < 4'd1) || (dg0 > 4'd7);
    wire is_trunk   = HAS_NET && TRUNK_MASK[p_port];
    wire leaf_mode  = LEAF && !HAS_NET;

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan <= 0;
            m_acc <= 0; b_acc <= 0;
            p_m <= 0; p_busy <= 0; p_port <= 0; visit <= 0;
            pv <= 0; p_valid <= 0; pb_blk <= 0;
            wh <= 0; wt <= 0; wst <= 0; probe_dirty <= 1'b1; wq_ovf <= 1'b0;
            wr_stb <= 1'b0; wr_dst <= 0; wr_src <= 0; wr_bsy <= 0; wr_clm <= 0;
            ser_req <= 0; ser_strobe <= 0; ser_dst <= 0; ser_src <= 0;
            ser_bsy <= 0; ser_clm <= 0; ser_g <= 1'b1;
            r_attach <= 0; r_release <= 0; r_aport <= 0; r_restart_loc <= 0;
            mst <= M_IDLE; caller <= 0; called <= 0; hold <= 0; f1 <= 0;
            ctx_clm <= 0; flood_go <= 0; up_start <= 0; up_armed <= 0;
            for (i = 0; i < 4; i = i + 1) wq[i] <= 15'd0;
        end else begin
            r_attach       <= 1'b0;
            r_release      <= 1'b0;
            r_restart_loc  <= 1'b0;
            visit          <= 1'b0;
            wr_stb         <= 1'b0;
            flood_go       <= 1'b0;

            if (HAS_NET) begin
                for (i = 0; i < 8; i = i + 1)
                    if (i < net_nw) begin
                        if (net_wev[i])
                            push_ev(net_wdst[i*6 +: 6], net_wsrc[i*6 +: 6]);
                        else
                            push(net_wdst[i*6 +: 6], net_wsrc[i*6 +: 6],
                                 net_wbsy[i], net_wclm[i]);
                    end
            end

            if (tick == 3'd4 && slotq == scan[2:0]) begin
                m_acc <= ha_bit;
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

            if (oct_stb && pv && scan[2:0] == 3'd7) probe_dirty <= 1'b1;
            ser_req <= 1'b0;
            case (wst)
            2'd0: if (!ser_busy && !ser_req) begin
                      if (w_pend) begin
                          ser_dst <= wq[wh][5:0];  ser_src <= wq[wh][11:6];
                          ser_bsy <= wq[wh][12];   ser_clm <= wq[wh][13];
                          ser_g   <= wq[wh][14];
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

            if (hold != 2'd0) hold <= hold - 1'b1;

            if (mst != M_IDLE && r_gone) begin
                if (r_nodig) push(caller, NOGO, 1'b1, ctx_clm);
                else         push(caller, 6'o00, 1'b0, 1'b0);
                mst <= M_IDLE; f1 <= 1'b0; ctx_clm <= 1'b0; up_armed <= 1'b0;
            end else case (mst)
            M_COLLECT: if (hold == 2'd0) begin
                if (!f1 && nd >= 3'd1) begin
                    if (first_nogo) begin
                        push(caller, NOGO, 1'b1, ctx_clm);
                        r_release <= 1'b1; mst <= M_IDLE;
                        f1 <= 1'b0; ctx_clm <= 1'b0;
                    end else if (HAS_NET && dg0 == 4'd1) begin
                        push(caller, 6'o00, 1'b1, ctx_clm);
                        r_restart_loc <= 1'b1; hold <= 2'd3;
                        flood_go <= 1'b1; mst <= M_YIELD;
                    end else if (leaf_mode && dg0 == 4'd1) begin
                        push(caller, 6'o00, 1'b1, ctx_clm);
                        up_start <= scan; up_armed <= 1'b0;
                        mst <= M_UPLINK;
                    end else begin
                        push(caller, 6'o00, 1'b1, ctx_clm);
                        f1 <= 1'b1;
                    end
                end else if (f1 && nd >= 3'd2) begin
                    called <= {oct(dg0), oct(dg1)}; mst <= M_PROBE;
                end
            end
            M_UPLINK: if (visit && p_valid) begin
                if (UPLINK_MASK[p_port] && !p_m && !p_busy) begin
                    if (!r_hook) begin
                        push(caller, 6'o00, 1'b0, 1'b0);
                        r_release <= 1'b1; mst <= M_IDLE; up_armed <= 1'b0;
                    end else begin
                        push(caller, p_port, 1'b1, 1'b0);
                        push(p_port, caller, 1'b1, 1'b0);
                        r_release <= 1'b1; mst <= M_IDLE; up_armed <= 1'b0;
                    end
                end else if (up_armed && p_port == up_start) begin
                    push(caller, NOGO, 1'b1, 1'b0);
                    r_release <= 1'b1; mst <= M_IDLE; up_armed <= 1'b0;
                end else if (p_port == up_start)
                    up_armed <= 1'b1;
            end
            M_YIELD: begin
                if (net_local) begin
                    mst <= M_COLLECT; hold <= 2'd3; f1 <= 1'b0;
                end else if (net_done) begin
                    r_release <= 1'b1; mst <= M_IDLE;
                    f1 <= 1'b0; ctx_clm <= 1'b0;
                end else if (net_nogo) begin
                    push(caller, NOGO, 1'b1, ctx_clm);
                    r_release <= 1'b1; mst <= M_IDLE;
                    f1 <= 1'b0; ctx_clm <= 1'b0;
                end
            end
            M_PROBE: if (visit && p_valid && p_port == called) begin
                if (!r_hook) begin
                    push(caller, 6'o00, 1'b0, 1'b0);
                    r_release <= 1'b1; mst <= M_IDLE;
                    f1 <= 1'b0; ctx_clm <= 1'b0;
                end else if (called == caller || p_m || p_busy) begin
                    push(caller, NOGO, 1'b1, ctx_clm);
                    r_release <= 1'b1; mst <= M_IDLE;
                    f1 <= 1'b0; ctx_clm <= 1'b0;
                end else begin
                    push(caller, called, 1'b1, ctx_clm);
                    push(called, caller, 1'b1, 1'b0);
                    r_release <= 1'b1; mst <= M_IDLE;
                    f1 <= 1'b0; ctx_clm <= 1'b0;
                end
            end
            default: ;
            endcase

            if (HAS_NET && net_att) begin
                if (mst == M_IDLE && !r_busy) begin
                    r_attach <= 1'b1; r_aport <= net_att_port;
                    caller <= net_att_port; mst <= M_COLLECT;
                    f1 <= 1'b0; hold <= 2'd3; ctx_clm <= 1'b1;
                end else
                    push(net_att_port, NOGO, 1'b1, 1'b1);
            end
            else if (visit && p_valid && p_m && !p_busy && !is_trunk &&
                     mst == M_IDLE && !r_busy) begin
                r_attach <= 1'b1; r_aport <= p_port;
                push(p_port, DIALTONE, 1'b1, 1'b0);
                caller <= p_port; mst <= M_COLLECT;
                f1 <= 1'b0; hold <= 2'd3; ctx_clm <= 1'b0;
            end
        end
    end
endmodule
