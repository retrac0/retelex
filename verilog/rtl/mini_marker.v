// mini_marker -- bring-up common control.  mini-marker.md.
//
// A scanner, a probe of M and BUSY, a sequencer, and one register inside.
// It does not read a card's option word and does not hunt a class.
// Two digits h s, two latch writes, and it leaves.
// Digit 1 is a highway until a network unit is fitted (HAS_NET): then key 1
// is flood_go and the unit owns the call (mini-marker.md 8, common-control.md).
// LEAF (exclusive of HAS_NET): digit 1 hunts UPLINK_MASK and patches (leaf-uplink.md).
//
//   first key   1-7   highway h; wait for the slot digit s; called = h s
//               0 8 9 and 11-16   cannot-complete
//               1 with HAS_NET    consume, restart, flood_go, YIELD
//               1 with LEAF       uplink hunt over UPLINK_MASK
//
// The register is pulse_reg.  restart is tied off when HAS_NET = 0.
// This is not network.md 9's outpulsing sender.
`timescale 1ns/1ps

module mini_marker #(
    parameter integer HIT      = 8,
    parameter integer ID       = 128,
    parameter integer CLR      = 256,
    parameter integer NODIG    = 12000,
    parameter [5:0]   DIALTONE = 6'o01,
    parameter [5:0]   NOGO     = 6'o03,
    parameter         HAS_NET  = 1'b0,     // jumper: network unit fitted
    parameter         LEAF     = 1'b0,     // jumper: digit 1 = uplink hunt
    // Ports that are trunks: M · /BUSY there is never a caller (common-control.md).
    parameter [63:0]  TRUNK_MASK = 64'd0,
    // LEAF: ports digit 1 may seize (block 1 trunks).
    parameter [63:0]  UPLINK_MASK = 64'd0
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

    // probe out for a network unit (common-control.md 2.2)
    output     [5:0] probe_port,
    output     [2:0] scan_port,
    output           probe_visit,
    output           probe_valid,
    output           probe_m,
    output           probe_busy,
    output    [15:0] probe_word,

    // network unit.  Tie the inputs off when HAS_NET = 0.
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

    // register levels the unit watches
    output           reg_busy,
    output           reg_gone,
    output           reg_nodig,
    output           reg_brk,
    output     [2:0] reg_ndig,
    output    [19:0] reg_digits,

    // for a testbench
    output reg       wq_ovf,
    output reg       wr_stb,
    output reg [5:0] wr_dst,
    output reg [5:0] wr_src,
    output reg       wr_bsy,
    output reg       wr_clm
);
    // ---------------- the register, one, inside --------------------------
    wire        r_busy, r_gone, r_nodig, r_brk, r_hook;
    wire [2:0]  r_ndig;
    wire [19:0] r_digits;
    reg         r_attach, r_release, r_restart_loc;
    reg  [5:0]  r_aport;

    wire restart_w = (HAS_NET && net_restart) | r_restart_loc;

    pulse_reg #(.HIT(HIT), .ID(ID), .CLR(CLR), .NODIG(NODIG)) u_reg (
        .clk(clk), .rst_n(rst_n), .slotq(slotq), .tick(tick), .tick_1k(tick_1k),
        .ha(ha),
        .attach(r_attach), .attach_port(r_aport), .attach_src(6'd0),
        .release_it(r_release), .restart(restart_w),
        .busy(r_busy), .port(), .src(),
        .ndig(r_ndig), .digits(r_digits),
        .gone(r_gone), .nodig(r_nodig), .brk(r_brk), .hook(r_hook));

    assign reg_busy   = r_busy;
    assign reg_gone   = r_gone;
    assign reg_nodig  = r_nodig;
    assign reg_brk    = r_brk;
    assign reg_ndig   = r_ndig;
    assign reg_digits = r_digits;

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

    assign scan_port   = scan[2:0];
    assign probe_port  = p_port;
    assign probe_visit = visit;
    assign probe_valid = p_valid;
    assign probe_m     = p_m;
    assign probe_busy  = p_busy;
    assign probe_word  = 16'd0;

    // ---------------- write queue (four deep) and serialiser -------------
    // { G, CLM, BSY, SRC, DST } — same word as marker.v so CLAIM sticks.
    reg [14:0] wq [0:3];
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

    task push(input [5:0] pt, input [5:0] sr, input b, input c);
        begin
            if (wt + 2'd1 == wh) wq_ovf <= 1'b1;
            wq[wt] = {1'b1, c, b, sr, pt}; wt = wt + 1'b1;
        end
    endtask

    task push_ev(input [5:0] pt, input [5:0] code);
        begin
            if (wt + 2'd1 != wh) begin
                wq[wt] = {1'b0, 1'b1, 1'b0, code, pt}; wt = wt + 1'b1;
            end
        end
    endtask

    // ---------------- a call ---------------------------------------------
    localparam M_IDLE    = 3'd0,
               M_COLLECT = 3'd1,
               M_PROBE   = 3'd2,
               M_YIELD   = 3'd3,
               M_UPLINK  = 3'd4;

    reg [2:0]  mst;
    reg [5:0]  caller, called;
    reg [1:0]  hold;                   // attach takes a cycle to land (rtl.md 1)
    reg        f1;                     // first (highway) digit is in
    reg        ctx_clm;                // CLAIM sticky until release
    reg [5:0]  up_start;               // UPLINK hunt wrap mark
    reg        up_armed;               // seen start once; wrap → none free

    assign flood_caller = caller;

    function [2:0] oct(input [4:0] c);
        oct = c[3] ? 3'd0 : c[2:0];
    endfunction

    wire [4:0] dg0 = r_digits[4:0];
    wire [4:0] dg1 = r_digits[9:5];
    wire [2:0] nd  = r_ndig;
    // first keys that are not a highway: anything outside 1-7
    // (0 is ten pulses, 8/9/11-16 are service)
    wire first_nogo = (dg0 < 5'd1) || (dg0 > 5'd7);
    wire is_trunk   = HAS_NET && TRUNK_MASK[p_port];
    wire leaf_mode  = LEAF && !HAS_NET;

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

            // drain the network unit's write burst (one cycle late; a hop is ms)
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

            // ---- the call ----------------------------------------------
            if (hold != 2'd0) hold <= hold - 1'b1;

            if (mst != M_IDLE && r_gone) begin
                // CLR / abandon: drop the latch.  nodig keeps the caller on
                // NOGO until they hang up (same shape as marker.v).
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
                    end else if (HAS_NET && dg0 == 5'd1) begin
                        push(caller, 6'o00, 1'b1, ctx_clm);
                        r_restart_loc <= 1'b1; hold <= 2'd3;
                        flood_go <= 1'b1; mst <= M_YIELD;
                    end else if (leaf_mode && dg0 == 5'd1) begin
                        push(caller, 6'o00, 1'b1, ctx_clm);  // dial tone off
                        up_start <= scan; up_armed <= 1'b0;
                        mst <= M_UPLINK;
                    end else begin
                        push(caller, 6'o00, 1'b1, ctx_clm);  // dial tone off
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
                // Abandon if the caller already hung up: a connect write with
                // both ends on-hook leaves no M/E edge to release (rtl.md).
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

            // ---- claim attach (before a new call request) --------------
            if (HAS_NET && net_att) begin
                if (mst == M_IDLE && !r_busy) begin
                    r_attach <= 1'b1; r_aport <= net_att_port;
                    caller <= net_att_port; mst <= M_COLLECT;
                    f1 <= 1'b0; hold <= 2'd3; ctx_clm <= 1'b1;
                end else begin
                    // no register free: claimed, cannot complete
                    push(net_att_port, NOGO, 1'b1, 1'b1);
                end
            end
            // ---- a port wanting service --------------------------------
            // Trunks are never callers when a unit is fitted.
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
