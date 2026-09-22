// net_unit -- the pulse flood, off the marker.  network.md 3, common-control.md.
//
// Origin seize, transit forward, hub resolvers, own-code, the origin guard,
// CLAIM writes.  The marker consumes key 1, restarts, raises flood_go, and
// otherwise hunts a class.  Monitors claim HERE, not at the marker.
//
// Writes leave as a burst the marker (or a third cable-B master) drains the
// next cycle -- one serialiser, the same sixteen-bit word.
`timescale 1ns/1ps

module net_unit #(
    parameter integer NREG      = 2,
    parameter integer NRES      = 1,
    parameter [2:0]   OWN_E     = 3'd2,
    parameter [2:0]   OWN_B     = 3'd2,
    parameter [5:0]   NOGO      = 6'o03,
    parameter [3:0]   STRAP_N   = 4'b0,
    parameter integer T_GUARD   = 128,
    parameter integer T_CLAIM   = 2000,
    // Mini-marker has no word: these ports are trunks, 2 bits of direction each.
    parameter [63:0]  TRUNK_MASK = 64'd0,
    parameter [127:0] TRUNK_DIR  = 128'd0
)(
    input            clk,
    input            rst_n,
    input            tick_1k,

    // the marker's probe, watched
    input            visit,
    input            p_valid,
    input      [5:0] p_port,
    input            p_m,
    input            p_busy,
    input      [7:0] p_word,

    // origin: this register consumed key 1
    input  [NREG-1:0]    flood_go,
    input  [6*NREG-1:0]  flood_caller,
    input  [NREG-1:0]    reg_gone,
    input  [NREG-1:0]    reg_brk,
    input  [3*NREG-1:0]  reg_ndig,
    input  [20*NREG-1:0] reg_digits,

    output reg [NREG-1:0] restart,
    output reg [NREG-1:0] go_local,
    output reg [NREG-1:0] done,
    output reg [NREG-1:0] nogo,

    // incoming claim from a monitor pool
    input            mon_claim,
    input      [5:0] mon_port,
    output reg       mon_ack,
    output reg       att_req,
    output reg [5:0] att_port,

    // latch writes, registered, drained next cycle
    output reg [3:0]      nw,
    output reg [8*6-1:0]  wdst,
    output reg [8*6-1:0]  wsrc,
    output reg [7:0]      wbsy,
    output reg [7:0]      wclm,
    output reg [7:0]      wev,

    output           any_claimed,
    output reg [3:0] dirs_held,
    output reg [3:0] fan_legs,
    output reg [3:0] res_used
);
    localparam C_NONE = 3'd0, C_LINE = 3'd1, C_OPER = 3'd2, C_SRC  = 3'd3,
               C_OUT  = 3'd4, C_TRUNK= 3'd5, C_DATA = 3'd6, C_REST = 3'd7;

    localparam [5:0] EV_GLARE   = 6'o04,
                     EV_NOTRUNK = 6'o10;

    wire       p_plain  = &p_word;
    wire       p_none   = ~|p_word;
    wire [1:0] p_type   = p_word[1:0];
    wire       p_form   = !p_plain && (p_type == 2'b11);
    wire [2:0] p_cls    = p_plain ? C_LINE :
                          (!p_none && p_type == 2'b00) ? C_NONE :
                          (p_type == 2'b01 || p_type == 2'b10) ? C_LINE :
                          p_form  ? p_word[4:2] : C_NONE;
    wire       is_trunk = (p_cls == C_TRUNK) || TRUNK_MASK[p_port];
    wire [1:0] p_dir    = (p_cls == C_TRUNK) ? p_word[6:5]
                                             : TRUNK_DIR[p_port*2 +: 2];
    wire       p_g      = (p_cls == C_TRUNK) && p_word[7];
    wire       p_n      = is_trunk && STRAP_N[p_dir];
    wire       p_free   = !p_busy && !p_m;

    function [2:0] oct(input [4:0] c);  oct  = c[3] ? 3'd0 : c[2:0];  endfunction
    function       isvc(input [4:0] c); isvc = (c == 5'd8) || (c == 5'd9) || (c > 5'd10); endfunction

    localparam N_IDLE=3'd0, N_WANT=3'd1, N_HUNT=3'd2, N_NET=3'd3, N_WAITCL=3'd4;

    reg [2:0]  nst     [0:NREG-1];
    reg [5:0]  caller  [0:NREG-1];
    reg [5:0]  trunk   [0:NREG-1];
    reg [1:0]  hold    [0:NREG-1];
    reg [15:0] tmr     [0:NREG-1];
    reg [3:0]  d_held  [0:NREG-1];
    reg [5:0]  d_trunk [0:4*NREG-1];
    reg [NREG-1:0] f1, f2, claimed, guarding;

    assign any_claimed = |claimed;

    // ---------------- hunt: one free trunk a direction -------------------
    reg       hunt_arm, hunt_run, hunt_done;
    reg [3:0] cand_ok, cand_any;
    reg [5:0] cand [0:3];
    reg       hunt_busy;
    reg [3:0] hunt_owner;
    reg       hb;

    // ---------------- forwarder ------------------------------------------
    localparam F_IDLE = 2'd0, F_RUN = 2'd2, F_GO = 2'd3;
    reg [1:0] fst;
    reg [5:0] f_in, f_start;
    reg [1:0] f_dir;
    reg [5:0] f_cand [0:3];
    reg [3:0] f_cok;

    // ---------------- resolvers ------------------------------------------
    reg [NRES-1:0] rs_busy;
    reg [5:0]      rs_in  [0:NRES-1];
    reg [5:0]      rs_leg [0:4*NRES-1];
    reg [3:0]      rs_held[0:NRES-1];

    integer        i, r, v, rpick, nleg, nw_i;
    reg [1:0]      first;
    reg            got, legclm;
    reg [5:0]      bdst [0:7];
    reg [5:0]      bsrc [0:7];
    reg            bbsy [0:7];
    reg            bclm [0:7];
    reg            bev  [0:7];
    reg [2:0]      nd;
    reg [4:0]      dg0, dg1;

    task npush(input [5:0] pt, input [5:0] sr, input b, input c, input e);
        begin
            if (nw_i < 8) begin
                bdst[nw_i] = pt; bsrc[nw_i] = sr;
                bbsy[nw_i] = b;  bclm[nw_i] = c; bev[nw_i] = e;
                nw_i = nw_i + 1;
            end
        end
    endtask

    task drop_trunk(input integer q);
        integer k;
        begin
            for (k = 0; k < 4; k = k + 1)
                if (d_held[q][k]) npush(d_trunk[q*4+k], 6'o00, 1'b0, 1'b0, 1'b0);
            d_held[q] <= 4'd0;
        end
    endtask

    task drop_others(input integer q);
        integer k;
        begin
            for (k = 0; k < 4; k = k + 1)
                if (d_held[q][k] && d_trunk[q*4+k] != trunk[q])
                    npush(d_trunk[q*4+k], 6'o00, 1'b0, 1'b0, 1'b0);
            d_held[q] <= 4'd0;
        end
    endtask

    always @* begin
        dirs_held = 4'd0;
        for (i = 0; i < NREG; i = i + 1) dirs_held = dirs_held | d_held[i];
        fan_legs = 4'd0;
        res_used = 4'd0;
        for (i = 0; i < NRES; i = i + 1) begin
            fan_legs = fan_legs | rs_held[i];
            res_used = res_used + {3'd0, rs_busy[i]};
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            restart <= 0; go_local <= 0; done <= 0; nogo <= 0;
            mon_ack <= 0; att_req <= 0; att_port <= 0;
            nw <= 0; wdst <= 0; wsrc <= 0; wbsy <= 0; wclm <= 0; wev <= 0;
            hunt_arm <= 0; hunt_run <= 0; hunt_done <= 0;
            cand_ok <= 0; cand_any <= 0; hunt_busy <= 0; hunt_owner <= 0;
            fst <= F_IDLE; f_in <= 0; f_dir <= 0; f_cok <= 0; f_start <= 0;
            rs_busy <= {NRES{1'b0}};
            for (i = 0; i < NRES; i = i + 1) begin rs_in[i] <= 6'd0; rs_held[i] <= 4'd0; end
            for (i = 0; i < 4*NRES; i = i + 1) rs_leg[i] <= 6'd0;
            for (i = 0; i < 4; i = i + 1) begin f_cand[i] <= 6'd0; cand[i] <= 6'd0; end
            f1 <= 0; f2 <= 0; claimed <= 0; guarding <= 0;
            for (i = 0; i < NREG; i = i + 1) begin
                nst[i] <= N_IDLE; caller[i] <= 0; trunk[i] <= 0;
                hold[i] <= 0; tmr[i] <= 0; d_held[i] <= 0;
            end
            for (i = 0; i < 4*NREG; i = i + 1) d_trunk[i] <= 6'd0;
        end else begin
            restart <= {NREG{1'b0}};
            go_local <= {NREG{1'b0}};
            done    <= {NREG{1'b0}};
            nogo    <= {NREG{1'b0}};
            mon_ack <= 1'b0;
            att_req <= 1'b0;
            hb = 1'b0; got = 1'b0; legclm = 1'b0;
            nw_i = 0;
            for (i = 0; i < 8; i = i + 1) begin
                bdst[i] = 6'd0; bsrc[i] = 6'd0;
                bbsy[i] = 1'b0; bclm[i] = 1'b0; bev[i] = 1'b0;
            end

            // ---- hunt ---------------------------------------------------
            if (visit && p_valid) begin
                if (hunt_arm && p_port == 6'd63) begin
                    hunt_arm <= 1'b0; hunt_run <= 1'b1;
                end else if (hunt_run) begin
                    if (is_trunk) cand_any[p_dir] <= 1'b1;
                    if (is_trunk && p_free && (!cand_ok[p_dir] || p_g)) begin
                        cand[p_dir] <= p_port;
                        cand_ok[p_dir] <= 1'b1;
                    end
                    if (p_port == 6'd63) begin hunt_run <= 1'b0; hunt_done <= 1'b1; end
                end
            end

            // ---- forwarder ----------------------------------------------
            if (visit && p_valid && fst == F_RUN) begin
                if (is_trunk && p_free && !p_n && p_dir != f_dir &&
                    (!f_cok[p_dir] || p_g)) begin
                    f_cand[p_dir] <= p_port; f_cok[p_dir] <= 1'b1;
                end
                if (p_port == f_start) fst <= F_GO;
            end
            if (fst == F_GO) begin
                nleg = 0; first = 2'd0; got = 1'b0;
                for (i = 0; i < 4; i = i + 1)
                    if (f_cok[i]) begin
                        nleg = nleg + 1;
                        if (!got) begin first = i[1:0]; got = 1'b1; end
                    end
                rpick = -1;
                for (v = 0; v < NRES; v = v + 1)
                    if (rpick < 0 && !rs_busy[v]) rpick = v;

                if (got && rpick >= 0) begin
                    for (i = 0; i < 4; i = i + 1) begin
                        if (f_cok[i]) npush(f_cand[i], f_in, 1'b1, 1'b0, 1'b0);
                        rs_leg[rpick*4+i] <= f_cand[i];
                    end
                    if (nleg == 1) npush(f_in, f_cand[first], 1'b1, 1'b0, 1'b0);
                    rs_busy[rpick] <= 1'b1;
                    rs_in  [rpick] <= f_in;
                    rs_held[rpick] <= f_cok;
                end else if (got) begin
                    npush(f_cand[first], f_in,          1'b1, 1'b0, 1'b0);
                    npush(f_in,          f_cand[first], 1'b1, 1'b0, 1'b0);
                end
                f_cok <= 4'd0;
                fst   <= F_IDLE;
            end

            // ---- resolvers ----------------------------------------------
            for (v = 0; v < NRES; v = v + 1) if (rs_busy[v] && visit && p_valid) begin
                legclm = 1'b0;
                for (i = 0; i < 4; i = i + 1)
                    if (rs_held[v][i] && p_port == rs_leg[v*4+i] && p_m) legclm = 1'b1;
                if (legclm) begin
                    npush(rs_in[v], p_port, 1'b1, 1'b0, 1'b0);
                    for (i = 0; i < 4; i = i + 1)
                        if (rs_held[v][i] && rs_leg[v*4+i] != p_port)
                            npush(rs_leg[v*4+i], 6'o00, 1'b0, 1'b0, 1'b0);
                    rs_busy[v] <= 1'b0; rs_held[v] <= 4'd0;
                end else if (p_port == rs_in[v] && !p_busy) begin
                    for (i = 0; i < 4; i = i + 1)
                        if (rs_held[v][i])
                            npush(rs_leg[v*4+i], 6'o00, 1'b0, 1'b0, 1'b0);
                    rs_busy[v] <= 1'b0; rs_held[v] <= 4'd0;
                end
            end

            // ---- origin calls -------------------------------------------
            for (r = 0; r < NREG; r = r + 1) begin
                nd  = reg_ndig  [r*3  +: 3];
                dg0 = reg_digits[r*20 +: 5];
                dg1 = reg_digits[r*20 + 5 +: 5];

                if (hold[r] != 2'd0) hold[r] <= hold[r] - 1'b1;

                if (flood_go[r] && nst[r] == N_IDLE) begin
                    caller[r] <= flood_caller[r*6 +: 6];
                    nst[r] <= N_WANT;
                    f1[r] <= 1'b0; f2[r] <= 1'b0;
                    claimed[r] <= 1'b0; guarding[r] <= 1'b0;
                end

                if (visit && p_valid && p_m && !claimed[r] &&
                    (nst[r] == N_NET || nst[r] == N_WAITCL))
                    for (i = 0; i < 4; i = i + 1)
                        if (d_held[r][i] && p_port == d_trunk[r*4+i]) begin
                            claimed[r] <= 1'b1;
                            trunk[r]   <= p_port;
                            if (guarding[r]) npush(p_port, EV_GLARE, 1'b0, 1'b1, 1'b1);
                        end

                if (guarding[r] && tick_1k) begin
                    if (tmr[r] == T_GUARD[15:0]) guarding[r] <= 1'b0;
                    else tmr[r] <= tmr[r] + 1'b1;
                end

                if (reg_gone[r] && nst[r] != N_IDLE) begin
                    drop_trunk(r);
                    if (hunt_busy && hunt_owner == r[3:0]) begin
                        hunt_busy <= 1'b0; hunt_done <= 1'b0; hunt_arm <= 1'b0;
                        hunt_run <= 1'b0;
                    end
                    nst[r] <= N_IDLE; claimed[r] <= 1'b0; guarding[r] <= 1'b0;
                end else if (guarding[r] && reg_brk[r]) begin
                    drop_trunk(r); nogo[r] <= 1'b1; nst[r] <= N_IDLE;
                    guarding[r] <= 1'b0;
                end else case (nst[r])
                N_WANT: if (!hunt_busy && !hb) begin
                    hunt_arm <= 1'b1; hunt_done <= 1'b0; cand_ok <= 4'd0;
                    cand_any <= 4'd0; hunt_busy <= 1'b1; hunt_owner <= r[3:0];
                    hb = 1'b1; nst[r] <= N_HUNT;
                end
                N_HUNT: if (hunt_done && hunt_owner == r[3:0]) begin
                    hunt_busy <= 1'b0; hunt_done <= 1'b0; hunt_arm <= 1'b0;
                    hunt_run <= 1'b0;
                    for (i = 0; i < 4; i = i + 1)
                        if (cand_any[i] && !cand_ok[i])
                            npush(6'o00, EV_NOTRUNK + i, 1'b0, 1'b1, 1'b1);
                    if (cand_ok != 4'd0) begin
                        for (i = 0; i < 4; i = i + 1)
                            if (cand_ok[i]) begin
                                npush(cand[i], caller[r], 1'b1, 1'b0, 1'b0);
                                d_trunk[r*4+i] <= cand[i];
                            end
                        d_held[r]   <= cand_ok;
                        trunk[r]    <= 6'd0;
                        guarding[r] <= 1'b1; tmr[r] <= 0; nst[r] <= N_NET;
                        f1[r] <= 1'b0; f2[r] <= 1'b0;
                    end else begin
                        nogo[r] <= 1'b1; nst[r] <= N_IDLE;
                    end
                end
                N_NET: if (hold[r] == 2'd0) begin
                    if (!f1[r] && nd >= 3'd1) begin
                        if (isvc(dg0)) begin
                            drop_trunk(r); nogo[r] <= 1'b1; nst[r] <= N_IDLE;
                        end else f1[r] <= 1'b1;
                    end else if (f1[r] && !f2[r] && nd >= 3'd2) begin
                        if (isvc(dg1)) begin
                            drop_trunk(r); nogo[r] <= 1'b1; nst[r] <= N_IDLE;
                        end else if (oct(dg0) == OWN_E && oct(dg1) == OWN_B) begin
                            drop_trunk(r);
                            restart[r] <= 1'b1; hold[r] <= 2'd3;
                            go_local[r] <= 1'b1;
                            f1[r] <= 1'b0; f2[r] <= 1'b0; nst[r] <= N_IDLE;
                        end else f2[r] <= 1'b1;
                    end else if (f2[r] && nd >= 3'd4) begin
                        nst[r] <= N_WAITCL; tmr[r] <= 0;
                    end
                end
                N_WAITCL: if (claimed[r]) begin
                    drop_others(r);
                    npush(caller[r], trunk[r], 1'b1, 1'b0, 1'b0);
                    done[r] <= 1'b1; nst[r] <= N_IDLE; claimed[r] <= 1'b0;
                end else if (tick_1k) begin
                    if (tmr[r] == T_CLAIM[15:0]) begin
                        drop_trunk(r); nogo[r] <= 1'b1; nst[r] <= N_IDLE;
                    end else tmr[r] <= tmr[r] + 1'b1;
                end
                default: ;
                endcase
            end

            // ---- monitor claims -----------------------------------------
            if (mon_claim && !mon_ack) begin
                mon_ack <= 1'b1;
                for (v = 0; v < NRES; v = v + 1)
                    if (rs_busy[v] && rs_in[v] == mon_port) begin
                        for (i = 0; i < 4; i = i + 1)
                            if (rs_held[v][i]) npush(rs_leg[v*4+i], 6'o00, 1'b0, 1'b0, 1'b0);
                        rs_busy[v] <= 1'b0; rs_held[v] <= 4'd0;
                    end
                npush(mon_port, 6'o00, 1'b1, 1'b1, 1'b0);
                att_req  <= 1'b1;
                att_port <= mon_port;
            end

            // ---- incoming seizure: not a caller -------------------------
            if (visit && p_valid && p_m && !p_busy && is_trunk) begin
                npush(p_port, 6'o00, 1'b1, 1'b0, 1'b0);
                if (fst == F_IDLE && !p_n) begin
                    f_in <= p_port; f_dir <= p_dir; f_start <= p_port;
                    f_cok <= 4'd0; fst <= F_RUN;
                end
            end

            nw <= nw_i[3:0];
            for (i = 0; i < 8; i = i + 1) begin
                wdst[i*6 +: 6] <= bdst[i];
                wsrc[i*6 +: 6] <= bsrc[i];
                wbsy[i] <= bbsy[i];
                wclm[i] <= bclm[i];
                wev[i]  <= bev[i];
            end
        end
    end
endmodule
