// tb_ring4 -- C19 VERIFY bench (scratch, not part of the tree).  A ring of four
// exchanges on baseband ties, timers scaled by 8 as tb_chain:
//
//        X 2 2  E 04,05  ==L==  04,05 W (g)  Y 2 3
//        W 74,75                             E 06,07
//          ||                                   ||
//        E 13,14 (g)                         W 11,12 (g)
//        V 2 5  W 11,12 (g) ==== 13,14 E    Z 2 4
//
// L = X-Y is the strapped link.  Default: strapped at X's end only (X's E);
// +define+BOTH: both ends (X's E and Y's W);  +define+NONE: no strap.
//
// The ports are placed to open the double-claim race wide: X's L trunks are
// scanned early in the pass (block 0) and its other ring trunks late
// (block 7), so the origin samples the two ways ~0.9 ms apart.
//
// One call a run: X20 dials 1 2 <b> 2 1 (+b=3: Y21, the far end of L;
// +b=4: Z21, the member opposite X).  +dx +dy +dz +dv: each site's reset
// release, in us (its scan phase); +dd: the caller's lift offset, in us.
`timescale 1ns/1ps
`include "exch.vh"

module tb_ring4r;
`define TMS ($realtime / 1.0e6)
    localparam [`PW-1:0] P20 = 6'o20, P21 = 6'o21;
    function [7:0] tw(input [1:0] d, input g); tw = {d, g, 3'b010, 2'b11}; endfunction
    localparam [1:0] DE = 2'd2, DW = 2'd3;
    // X: L (E) 04,05; toward V (W) 74,75
    localparam [511:0] TW_X = ({504'd0, tw(DE,1'b0)} << (8*6'o04)) | ({504'd0, tw(DE,1'b0)} << (8*6'o05)) |
                              ({504'd0, tw(DW,1'b0)} << (8*6'o74)) | ({504'd0, tw(DW,1'b0)} << (8*6'o75));
    localparam [63:0]  TR_X = (64'd1 << 6'o04) | (64'd1 << 6'o05) | (64'd1 << 6'o74) | (64'd1 << 6'o75);
    // Y: L (W, g) 04,05; toward Z (E) 06,07
    localparam [511:0] TW_Y = ({504'd0, tw(DW,1'b1)} << (8*6'o04)) | ({504'd0, tw(DW,1'b1)} << (8*6'o05)) |
                              ({504'd0, tw(DE,1'b0)} << (8*6'o06)) | ({504'd0, tw(DE,1'b0)} << (8*6'o07));
    localparam [63:0]  TR_Y = (64'd1 << 6'o04) | (64'd1 << 6'o05) | (64'd1 << 6'o06) | (64'd1 << 6'o07);
    // Z: toward Y (W, g) 11,12; toward V (E) 13,14
    localparam [511:0] TW_Z = ({504'd0, tw(DW,1'b1)} << (8*6'o11)) | ({504'd0, tw(DW,1'b1)} << (8*6'o12)) |
                              ({504'd0, tw(DE,1'b0)} << (8*6'o13)) | ({504'd0, tw(DE,1'b0)} << (8*6'o14));
    localparam [63:0]  TR_Z = (64'd1 << 6'o11) | (64'd1 << 6'o12) | (64'd1 << 6'o13) | (64'd1 << 6'o14);
    // V: toward Z (W, g) 11,12; toward X (E, g) 13,14
    localparam [511:0] TW_V = ({504'd0, tw(DW,1'b1)} << (8*6'o11)) | ({504'd0, tw(DW,1'b1)} << (8*6'o12)) |
                              ({504'd0, tw(DE,1'b1)} << (8*6'o13)) | ({504'd0, tw(DE,1'b1)} << (8*6'o14));
    localparam [63:0]  TR_V = TR_Z;
`ifdef NONE
    localparam [3:0] STX = 4'b0000, STY = 4'b0000;
`elsif BOTH
    localparam [3:0] STX = 4'b0100, STY = 4'b1000;
`else
    localparam [3:0] STX = 4'b0100, STY = 4'b0000;
`endif

    reg clk = 1'b0;
    always #122.070 clk = ~clk;
    reg rst_x = 1'b0, rst_y = 1'b0, rst_z = 1'b0, rst_v = 1'b0;

    reg  [63:0] hook_x = 0, tx_x = 0, hook_y = 0, hook_z = 0, hook_v = 0;
    wire [63:0] rx_x, e_x, rx_y, e_y, rx_z, e_z, rx_v, e_v;
    wire [63:0] bx, by, bz, bv;
    wire [63:0] xc, xa, xk, yc, ya, yk, zc, za, zk, vc, va, vk, upx, upy, upz, upv;
    reg  [63:0] xci, xai, xki, yci, yai, yki, zci, zai, zki, vci, vai, vki;
    wire        t1x, t1y, t1z, t1v, clx, cly, clz, clv, rgx, rgy, rgz, rgv, cmx, cmy, cmz, cmv;
    wire [1:0]  resx, resy, resz, resv, monx, mony, monz, monv;
    wire [3:0]  dx_h, dy_h, dz_h, dv_h;
    wire [7:0]  nfx, nfy, nfz, nfv;

// REAL TIMERS (tb_ring4r): register.md / network.md values, 10 pps 60/40, 720 ms pauses
`define SP .PHONES(64'h0000_0000_0003_0000), \
        .T_ARM(9'd16), .T_REL(9'd256), .RING_ON(13'd2048), .RING_OFF(13'd4096), \
        .HIT(9'd8), .ID(9'd128), .CLR(9'd256), .NODIG(16'd10000), \
        .T_GUARD0(16'd128), .T_KEY(16'd5000), .T_CLAIM(16'd2000)
`define SITE(N, RST, TR, TW, E, B, ST, HK, TX, RX, EO, CO, AO, KO, CI, AI, KI, UP, T1, CL, RG, CM, DH, RS, MO, NF) \
    site_net #(`SP, .TRUNKS(TR), .TWORD(TW), .OWN_E(E), .OWN_B(B), .STRAP_N(ST)) N ( \
        .clk(clk), .rst_n(RST), .hook(HK), .tx(TX), .rx(RX), .e(EO), \
        .c_out(CO), .a_out(AO), .clk_out(KO), .c_in(CI), .a_in(AI), .clk_in(KI), .link_up(UP), \
        .lt_c_out(), .lt_a_out(), .lt_h_out(), .lt_k_out(), \
        .lt_c_in(8'd0), .lt_a_in(8'd0), .lt_h_in(8'd0), .lt_k_in(8'd0), .lt_up(), \
        .frame_stb(), .tick_1k(T1), .ring_cad_n(), .port_busy(), \
        .b_sdata(), .b_sclk(), .b_wr(), .b_clash(CL), \
        .reg_busy(RG), .mk_state(), .mk_ovf(), .dirs_held(DH), \
        .res_busy(RS), .mon_held(MO), .claimed(CM), .hunting(), \
        .un_ovf(), .n_glare(), .n_nofwd(NF))

    `SITE(X, rst_x, TR_X, TW_X, 3'd2, 3'd2, STX, hook_x, tx_x, rx_x, e_x, xc, xa, xk, xci, xai, xki, upx, t1x, clx, rgx, cmx, dx_h, resx, monx, nfx);
    `SITE(Y, rst_y, TR_Y, TW_Y, 3'd2, 3'd3, STY, hook_y, 64'd0, rx_y, e_y, yc, ya, yk, yci, yai, yki, upy, t1y, cly, rgy, cmy, dy_h, resy, mony, nfy);
    `SITE(Z, rst_z, TR_Z, TW_Z, 3'd2, 3'd4, 4'b0000, hook_z, 64'd0, rx_z, e_z, zc, za, zk, zci, zai, zki, upz, t1z, clz, rgz, cmz, dz_h, resz, monz, nfz);
    `SITE(V, rst_v, TR_V, TW_V, 3'd2, 3'd5, 4'b0000, hook_v, 64'd0, rx_v, e_v, vc, va, vk, vci, vai, vki, upv, t1v, clv, rgv, cmv, dv_h, resv, monv, nfv);

    // ---- the cables: X04,05-Y04,05  Y06,07-Z11,12  Z13,14-V11,12  V13,14-X74,75
    always @* begin
        xci = 0; xai = 0; xki = 0; yci = 0; yai = 0; yki = 0;
        zci = 0; zai = 0; zki = 0; vci = 0; vai = 0; vki = 0;
        // L
        xci[6'o04] = yc[6'o04]; xai[6'o04] = ya[6'o04]; xki[6'o04] = yk[6'o04];
        yci[6'o04] = xc[6'o04]; yai[6'o04] = xa[6'o04]; yki[6'o04] = xk[6'o04];
        xci[6'o05] = yc[6'o05]; xai[6'o05] = ya[6'o05]; xki[6'o05] = yk[6'o05];
        yci[6'o05] = xc[6'o05]; yai[6'o05] = xa[6'o05]; yki[6'o05] = xk[6'o05];
        // Y-Z
        yci[6'o06] = zc[6'o11]; yai[6'o06] = za[6'o11]; yki[6'o06] = zk[6'o11];
        zci[6'o11] = yc[6'o06]; zai[6'o11] = ya[6'o06]; zki[6'o11] = yk[6'o06];
        yci[6'o07] = zc[6'o12]; yai[6'o07] = za[6'o12]; yki[6'o07] = zk[6'o12];
        zci[6'o12] = yc[6'o07]; zai[6'o12] = ya[6'o07]; zki[6'o12] = yk[6'o07];
        // Z-V
        zci[6'o13] = vc[6'o11]; zai[6'o13] = va[6'o11]; zki[6'o13] = vk[6'o11];
        vci[6'o11] = zc[6'o13]; vai[6'o11] = za[6'o13]; vki[6'o11] = zk[6'o13];
        zci[6'o14] = vc[6'o12]; zai[6'o14] = va[6'o12]; zki[6'o14] = vk[6'o12];
        vci[6'o12] = zc[6'o14]; vai[6'o12] = za[6'o14]; vki[6'o12] = zk[6'o14];
        // V-X
        vci[6'o13] = xc[6'o74]; vai[6'o13] = xa[6'o74]; vki[6'o13] = xk[6'o74];
        xci[6'o74] = vc[6'o13]; xai[6'o74] = va[6'o13]; xki[6'o74] = vk[6'o13];
        vci[6'o14] = xc[6'o75]; vai[6'o14] = xa[6'o75]; vki[6'o14] = xk[6'o75];
        xci[6'o75] = vc[6'o14]; xai[6'o75] = va[6'o14]; xki[6'o75] = vk[6'o14];
    end

    // ---- traces: classifications, forwards, claims, the marker's answer, the origin's take
    integer n_cls [0:3]; integer n_fwd [0:3]; integer n_claim [0:3];
    integer taken_port = -1, refused_port = -1, kept = -1, first_taken_t = 0;
    initial for (int i = 0; i < 4; i++) begin n_cls[i] = 0; n_fwd[i] = 0; n_claim[i] = 0; end
`define TRACE(S, I, CM, NM) \
    reg CM``_d = 1'b0; \
    always @(posedge clk) begin \
        CM``_d <= CM; \
        if (S.u_x.u_net.w_cls && S.u_x.u_net.cst == 3'd2) begin n_cls[I]++; \
            $display("  [%9.3f] %s SEIZE port %02o dir %0d mon_free %0d fwd %0s", `TMS, NM, S.u_x.u_net.cls_port, \
                     S.u_x.u_net.cls_dir, S.u_x.u_net.m_free_any, S.u_x.u_net.nf_busy ? "BUSY" : "ok/none"); end \
        if (S.u_x.u_net.w_fwd) begin n_fwd[I]++; \
            $display("  [%9.3f] %s FWD in %02o ok %b cand %o", `TMS, NM, S.u_x.u_net.f_in, S.u_x.u_net.f_ok, S.u_x.u_net.f_cand); end \
        if (S.u_x.u_net.nf_empty) $display("  [%9.3f] %s NOFWD-EMPTY in %02o", `TMS, NM, S.u_x.u_net.f_in); \
        if (S.u_x.u_net.w_claim) begin n_claim[I]++; \
            $display("  [%9.3f] %s CLAIM port %02o (want %b)", `TMS, NM, S.u_x.u_net.m_want_port, S.u_x.u_net.m_want); end \
        if (S.u_x.u_mk.att_ack) begin \
            $display("  [%9.3f] %s att_ack %0s port %02o", `TMS, NM, S.u_x.u_mk.r_attach ? "TAKEN" : "REFUSED", S.u_x.u_net.att_port); \
            if (I == owner) begin if (S.u_x.u_mk.r_attach) begin taken_port = S.u_x.u_net.att_port; first_taken_t = $time; end \
                                  else refused_port = S.u_x.u_net.att_port; end end \
        if (CM && !CM``_d) begin \
            $display("  [%9.3f] %s ORIGIN TAKES claim on %02o", `TMS, NM, S.u_x.u_net.trunk); \
            if (I == 0) kept = S.u_x.u_net.trunk; end \
    end
    integer owner = 1;
    integer clash = 0;
    always @(posedge clk) if (clx || cly || clz || clv) clash = clash + 1;
    `TRACE(X, 0, cmx, "X")
    `TRACE(Y, 1, cmy, "Y")
    `TRACE(Z, 2, cmz, "Z")
    `TRACE(V, 3, cmv, "V")

    task automatic ms(input integer n); begin repeat (n) @(posedge t1x); end endtask
    task automatic dial(input integer d);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                hook_x[P20] = 1'b0; ms(60);
                hook_x[P20] = 1'b1; ms(40);
            end
            ms(720);
        end
    endtask

    integer dxu, dyu, dzu, dvu, ddu, bb, hi, lo, ring_ok, hear1, hear0;
    initial begin
        if (!$value$plusargs("dx=%d", dxu)) dxu = 0;
        if (!$value$plusargs("dy=%d", dyu)) dyu = 0;
        if (!$value$plusargs("dz=%d", dzu)) dzu = 0;
        if (!$value$plusargs("dv=%d", dvu)) dvu = 0;
        if (!$value$plusargs("dd=%d", ddu)) ddu = 0;
        if (!$value$plusargs("b=%d", bb)) bb = 3;
        owner = (bb == 3) ? 1 : (bb == 4) ? 2 : 3;
        $display("\n  tb_ring4 STX %b STY %b  dx %0d dy %0d dz %0d dv %0d dd %0d  X20 dials 1 2 %0d 2 1",
                 STX, STY, dxu, dyu, dzu, dvu, ddu, bb);
        fork
            begin #(5000 + dxu * 1000); rst_x = 1'b1; end
            begin #(5000 + dyu * 1000); rst_y = 1'b1; end
            begin #(5000 + dzu * 1000); rst_z = 1'b1; end
            begin #(5000 + dvu * 1000); rst_v = 1'b1; end
        join
        ms(30);
        if (!(upx[6'o04] && upx[6'o74] && upy[6'o06] && upz[6'o13])) $display("  LINKS NOT UP");
        #(ddu * 1000);
        hook_x[P20] = 1'b1; ms(500);
        dial(1);
        $display("  [%9.3f] after key: X dirs %b", `TMS, dx_h);
        dial(2); dial(bb); dial(2); dial(1);
        ms(30);
        hi = 0; lo = 0;
        for (int i = 0; i < 1500; i++) begin
            @(posedge t1x);
            if ((bb == 3 && e_y[P21]) || (bb == 4 && e_z[P21])) hi++; else lo++;
        end
        ring_ok = (hi > 50);
        hear1 = 0; hear0 = 0;
        for (int i = 0; i < 50; i++) begin @(posedge t1x); if (rx_x[P20]) hear1++; else hear0++; end
        $display("  OUTCOME b=%0d rang=%0d (hi %0d lo %0d) owner_taken=%02o owner_refused=%02o origin_kept=%02o X20_rx1=%0d/50 claims X%0d Y%0d Z%0d V%0d seizures X%0d Y%0d Z%0d V%0d fwds X%0d Y%0d Z%0d V%0d",
                 bb, ring_ok, hi, lo, taken_port, refused_port, kept, hear1,
                 n_claim[0], n_claim[1], n_claim[2], n_claim[3], n_cls[0], n_cls[1], n_cls[2], n_cls[3],
                 n_fwd[0], n_fwd[1], n_fwd[2], n_fwd[3]);
        hook_x[P20] = 1'b0;
        ms(1500);
        $display("  IDLE-CHECK busy X %h Y %h Z %h V %h reg %0d%0d%0d%0d res %b %b %b %b mon %b %b %b %b",
                 X.port_busy, Y.port_busy, Z.port_busy, V.port_busy, rgx, rgy, rgz, rgv,
                 resx, resy, resz, resv, monx, mony, monz, monv);
        $display("  clash %0d", clash);
        $finish;
    end
    initial begin #40_000_000_000; $display("  TIMEOUT"); $fatal(1); end
endmodule
