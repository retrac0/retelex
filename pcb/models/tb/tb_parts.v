// tb_parts -- every package in 74hc.v against its datasheet function table.
//
// COMBINATIONAL AND TRI-STATE PARTS: one stimulus vector v feeds them all.
// v counts through all 4096 values of its low twelve bits, which is every
// input combination of every part with twelve inputs or fewer, and then
// 3000 more vectors built for the '688, half of them with P = Q or P and Q
// one bit apart.  Each part's datasheet function is written again here, in
// the bench, as a zero-delay reference; a probe per output group checks, at
// EVERY vector, that the model has not moved 1 ns before its TPD and is
// right 1 ns after it.  So the delay of every output of every part is
// checked on every vector, not only its function.
//
// FLIP-FLOPS AND REGISTERS: scripted, row by row of their tables,
// including the '74's both-low row and its release order, and each with its
// clock-to-output delay sampled either side.
//
// NOT COVERED: which PIN each port is on -- that is tb/pins.py, against the
// KiCad symbols.  Setup and hold (tb_dly).  Glitch behaviour of real parts.
`timescale 1ns/1ps

// A probe: checks one part's outputs against the bench's reference on every
// vector.  go rises 1 ns after the vector is applied.
module tbp_probe #(
    parameter integer     W    = 1,
    parameter integer     TPD  = 7,
    parameter [8*12-1:0]  NAME = "part"
)(
    input wire [W-1:0] r,
    input wire [W-1:0] o,
    input wire         go
);
    integer     n_chk, n_err, shown;
    reg [W-1:0] was, now;
    reg         first;
    initial begin n_chk = 0; n_err = 0; shown = 0; first = 1'b1; end

    task bad(input [8*40-1:0] what, input [W-1:0] want);
        begin
            n_err = n_err + 1;
            if (shown < 4) begin
                shown = shown + 1;
                $display("    FAIL  %0s %0s: want %b, model %b, at %0t", NAME, what, want, o, $time);
            end
        end
    endtask

    always @(posedge go) begin
        now = r;
        #(TPD - 2);                       // 1 ns before the delay
        if (!first) begin
            n_chk = n_chk + 1;
            if (o !== was) bad("moved before its delay", was);
        end
        #2;                               // 1 ns after it
        n_chk = n_chk + 1;
        if (o !== now) bad("wrong, or late", now);
        was = now; first = 1'b0;
    end
endmodule

module tb_parts;
    integer chk = 0, errs = 0;

    task ck(input cond, input [8*72-1:0] what);
        begin
            chk = chk + 1;
            if (!cond) begin errs = errs + 1; $display("    FAIL  %0s  at %0t", what, $time); end
        end
    endtask

    // =====================================================================
    // COMBINATIONAL: the stimulus and the references
    // =====================================================================
    reg  [16:0] v;
    reg         go;

    // gates: section k's inputs are v[2k-2], v[2k-1] (and v[2k] for the '11)
    wire [3:0] r00 = {~(v[6] & v[7]), ~(v[4] & v[5]), ~(v[2] & v[3]), ~(v[0] & v[1])};
    wire [3:0] r02 = {~(v[6] | v[7]), ~(v[4] | v[5]), ~(v[2] | v[3]), ~(v[0] | v[1])};
    wire [3:0] r08 = ~r00;
    wire [3:0] r32 = ~r02;
    wire [3:0] r86 = {v[6] ^ v[7], v[4] ^ v[5], v[2] ^ v[3], v[0] ^ v[1]};
    wire [5:0] r04 = ~v[5:0];
    wire [2:0] r11 = {&v[8:6], &v[5:3], &v[2:0]};
    wire [1:0] r4002 = {~|v[7:4], ~|v[3:0]};

    // '138: A = v[2:0], /E1 = v3, /E2 = v4, E3 = v5
    wire       en138 = ~v[3] & ~v[4] & v[5];
    reg  [7:0] r138;
    integer    j;
    always @* begin
        r138 = 8'hFF;
        for (j = 0; j < 8; j = j + 1) if (en138 && v[2:0] == j) r138[j] = 1'b0;
    end

    // '148: /I0../I7 = v[7:0], /EI = v8.  {/GS, /EO, /A2, /A1, /A0}
    reg  [4:0] r148;
    reg  [2:0] hi148;
    reg        any148;
    integer    k148;
    always @* begin
        any148 = 1'b0; hi148 = 3'd0;
        for (k148 = 0; k148 < 8; k148 = k148 + 1)       // the last low one scanned is the highest
            if (!v[k148]) begin any148 = 1'b1; hi148 = k148[2:0]; end
        if (v[8])         r148 = 5'b11_111;             // disabled: everything high
        else if (!any148) r148 = 5'b10_111;             // enabled, idle: /EO low
        else              r148 = {2'b01, ~hi148};
    end

    // '151: I = v[7:0], S = v[10:8], /E = v11.  {/Y, Y}
    wire       y151 = v[v[10:8]];
    wire [1:0] r151 = v[11] ? 2'b10 : {~y151, y151};

    // '157: nI0 = v[3:0], nI1 = v[7:4], S = v8, /E = v9
    wire [3:0] r157 = v[9] ? 4'b0000 : (v[8] ? v[7:4] : v[3:0]);

    // '688: P = v[7:0], Q = v[15:8], /E = v16
    wire       r688 = !(v[16] == 1'b0 && v[7:0] == v[15:8]);

    // '125: nA = v[3:0], /nOE = v[7:4]
    wire [3:0] r125o = v[3:0];
    wire [3:0] r125e = ~v[7:4];

    // '244: 1An = v[3:0], 2An = v[7:4], /1OE = v8, /2OE = v9.  {group 2, group 1}
    wire [7:0] r244o = v[7:0];
    wire [7:0] r244e = {{4{~v[9]}}, {4{~v[8]}}};

    // '4051: Yn = v[7:0], S = v[10:8], /E = v11.  {Z_oe, Z}
    wire [1:0] r4051 = {~v[11], v[v[10:8]]};

    // =====================================================================
    // COMBINATIONAL: the parts
    // =====================================================================
    wire [3:0] o00, o02, o08, o32, o86;
    wire [5:0] o04, o14;
    wire [2:0] o11;
    wire [1:0] o4002;

    hc00 u00 (.A1(v[0]), .B1(v[1]), .Y1(o00[0]), .A2(v[2]), .B2(v[3]), .Y2(o00[1]),
              .A3(v[4]), .B3(v[5]), .Y3(o00[2]), .A4(v[6]), .B4(v[7]), .Y4(o00[3]));
    hc02 u02 (.A1(v[0]), .B1(v[1]), .Y1(o02[0]), .A2(v[2]), .B2(v[3]), .Y2(o02[1]),
              .A3(v[4]), .B3(v[5]), .Y3(o02[2]), .A4(v[6]), .B4(v[7]), .Y4(o02[3]));
    hc08 u08 (.A1(v[0]), .B1(v[1]), .Y1(o08[0]), .A2(v[2]), .B2(v[3]), .Y2(o08[1]),
              .A3(v[4]), .B3(v[5]), .Y3(o08[2]), .A4(v[6]), .B4(v[7]), .Y4(o08[3]));
    hc32 u32 (.A1(v[0]), .B1(v[1]), .Y1(o32[0]), .A2(v[2]), .B2(v[3]), .Y2(o32[1]),
              .A3(v[4]), .B3(v[5]), .Y3(o32[2]), .A4(v[6]), .B4(v[7]), .Y4(o32[3]));
    hc86 u86 (.A1(v[0]), .B1(v[1]), .Y1(o86[0]), .A2(v[2]), .B2(v[3]), .Y2(o86[1]),
              .A3(v[4]), .B3(v[5]), .Y3(o86[2]), .A4(v[6]), .B4(v[7]), .Y4(o86[3]));
    hc04 u04 (.A1(v[0]), .Y1(o04[0]), .A2(v[1]), .Y2(o04[1]), .A3(v[2]), .Y3(o04[2]),
              .A4(v[3]), .Y4(o04[3]), .A5(v[4]), .Y5(o04[4]), .A6(v[5]), .Y6(o04[5]));
    hc14 u14 (.A1(v[0]), .Y1(o14[0]), .A2(v[1]), .Y2(o14[1]), .A3(v[2]), .Y3(o14[2]),
              .A4(v[3]), .Y4(o14[3]), .A5(v[4]), .Y5(o14[4]), .A6(v[5]), .Y6(o14[5]));
    hc11 u11 (.A1(v[0]), .B1(v[1]), .C1(v[2]), .Y1(o11[0]),
              .A2(v[3]), .B2(v[4]), .C2(v[5]), .Y2(o11[1]),
              .A3(v[6]), .B3(v[7]), .C3(v[8]), .Y3(o11[2]));
    hc4002 u4002 (.A1(v[0]), .B1(v[1]), .C1(v[2]), .D1(v[3]), .Y1(o4002[0]),
                  .A2(v[4]), .B2(v[5]), .C2(v[6]), .D2(v[7]), .Y2(o4002[1]));

    wire [7:0] o138;
    hc138 u138 (.A0(v[0]), .A1(v[1]), .A2(v[2]), .E1_n(v[3]), .E2_n(v[4]), .E3(v[5]),
                .Y0_n(o138[0]), .Y1_n(o138[1]), .Y2_n(o138[2]), .Y3_n(o138[3]),
                .Y4_n(o138[4]), .Y5_n(o138[5]), .Y6_n(o138[6]), .Y7_n(o138[7]));

    wire [4:0] o148;
    hc148 u148 (.I0_n(v[0]), .I1_n(v[1]), .I2_n(v[2]), .I3_n(v[3]),
                .I4_n(v[4]), .I5_n(v[5]), .I6_n(v[6]), .I7_n(v[7]), .EI_n(v[8]),
                .A0_n(o148[0]), .A1_n(o148[1]), .A2_n(o148[2]), .EO_n(o148[3]), .GS_n(o148[4]));

    wire [1:0] o151;
    hc151 u151 (.I0(v[0]), .I1(v[1]), .I2(v[2]), .I3(v[3]), .I4(v[4]), .I5(v[5]), .I6(v[6]), .I7(v[7]),
                .S0(v[8]), .S1(v[9]), .S2(v[10]), .E_n(v[11]), .Y(o151[0]), .Y_n(o151[1]));

    wire [3:0] o157;
    hc157 u157 (.I0_1(v[0]), .I0_2(v[1]), .I0_3(v[2]), .I0_4(v[3]),
                .I1_1(v[4]), .I1_2(v[5]), .I1_3(v[6]), .I1_4(v[7]),
                .S(v[8]), .E_n(v[9]), .Y1(o157[0]), .Y2(o157[1]), .Y3(o157[2]), .Y4(o157[3]));

    wire o688;
    hc688 u688 (.P0(v[0]), .P1(v[1]), .P2(v[2]), .P3(v[3]), .P4(v[4]), .P5(v[5]), .P6(v[6]), .P7(v[7]),
                .Q0(v[8]), .Q1(v[9]), .Q2(v[10]), .Q3(v[11]), .Q4(v[12]), .Q5(v[13]), .Q6(v[14]), .Q7(v[15]),
                .E_n(v[16]), .P_EQ_Q_n(o688));

    wire [3:0] o125, e125;
    hc125 u125 (.A1(v[0]), .A2(v[1]), .A3(v[2]), .A4(v[3]),
                .OE1_n(v[4]), .OE2_n(v[5]), .OE3_n(v[6]), .OE4_n(v[7]),
                .Y1(o125[0]), .Y2(o125[1]), .Y3(o125[2]), .Y4(o125[3]),
                .Y1_oe(e125[0]), .Y2_oe(e125[1]), .Y3_oe(e125[2]), .Y4_oe(e125[3]));

    wire [7:0] o244, e244;
    hc244 u244 (.A0_1(v[0]), .A1_1(v[1]), .A2_1(v[2]), .A3_1(v[3]),
                .A0_2(v[4]), .A1_2(v[5]), .A2_2(v[6]), .A3_2(v[7]),
                .OE1_n(v[8]), .OE2_n(v[9]),
                .Y0_1(o244[0]), .Y1_1(o244[1]), .Y2_1(o244[2]), .Y3_1(o244[3]),
                .Y0_2(o244[4]), .Y1_2(o244[5]), .Y2_2(o244[6]), .Y3_2(o244[7]),
                .Y0_1_oe(e244[0]), .Y1_1_oe(e244[1]), .Y2_1_oe(e244[2]), .Y3_1_oe(e244[3]),
                .Y0_2_oe(e244[4]), .Y1_2_oe(e244[5]), .Y2_2_oe(e244[6]), .Y3_2_oe(e244[7]));

    wire [1:0] o4051;
    hc4051 u4051 (.Y0(v[0]), .Y1(v[1]), .Y2(v[2]), .Y3(v[3]), .Y4(v[4]), .Y5(v[5]), .Y6(v[6]), .Y7(v[7]),
                  .S0(v[8]), .S1(v[9]), .S2(v[10]), .E_n(v[11]), .Z(o4051[0]), .Z_oe(o4051[1]));

    wire pd02, pd00;
    fet_2n7002 uf2 (.G(v[0]), .pd(pd02));
    fet_2n7000 uf0 (.G(v[1]), .pd(pd00));

    tbp_probe #(4, 7,  "hc00")   p00   (.r(r00),   .o(o00),   .go(go));
    tbp_probe #(4, 7,  "hc02")   p02   (.r(r02),   .o(o02),   .go(go));
    tbp_probe #(4, 7,  "hc08")   p08   (.r(r08),   .o(o08),   .go(go));
    tbp_probe #(4, 8,  "hc32")   p32   (.r(r32),   .o(o32),   .go(go));
    tbp_probe #(4, 11, "hc86")   p86   (.r(r86),   .o(o86),   .go(go));
    tbp_probe #(6, 7,  "hc04")   p04   (.r(r04),   .o(o04),   .go(go));
    tbp_probe #(6, 12, "hc14")   p14   (.r(r04),   .o(o14),   .go(go));
    tbp_probe #(3, 9,  "hc11")   p11   (.r(r11),   .o(o11),   .go(go));
    tbp_probe #(2, 10, "hc4002") p4002 (.r(r4002), .o(o4002), .go(go));
    tbp_probe #(8, 12, "hc138")  p138  (.r(r138),  .o(o138),  .go(go));
    tbp_probe #(5, 14, "hc148")  p148  (.r(r148),  .o(o148),  .go(go));
    tbp_probe #(2, 17, "hc151")  p151  (.r(r151),  .o(o151),  .go(go));
    tbp_probe #(4, 14, "hc157")  p157  (.r(r157),  .o(o157),  .go(go));
    tbp_probe #(1, 16, "hc688")  p688  (.r(r688),  .o(o688),  .go(go));
    tbp_probe #(4, 9,  "hc125")  p125o (.r(r125o), .o(o125),  .go(go));
    tbp_probe #(4, 11, "hc125oe") p125e (.r(r125e), .o(e125), .go(go));
    tbp_probe #(8, 9,  "hc244")  p244o (.r(r244o), .o(o244),  .go(go));
    tbp_probe #(8, 12, "hc244oe") p244e (.r(r244e), .o(e244), .go(go));
    tbp_probe #(2, 18, "hc4051") p4051 (.r(r4051), .o(o4051), .go(go));
    tbp_probe #(1, 5,  "2n7002") pf2   (.r(v[0]),  .o(pd02),  .go(go));
    tbp_probe #(1, 5,  "2n7000") pf0   (.r(v[1]),  .o(pd00),  .go(go));

    localparam integer STEP = 30;         // > the longest TPD + 1
    task apply(input [16:0] nv);
        begin v = nv; #1 go = 1'b1; #1 go = 1'b0; #(STEP - 2); end
    endtask

    // =====================================================================
    // SEQUENTIAL: the parts and their stimulus
    // =====================================================================
    // '74: each half has its own clock and asynchronous inputs, normally
    // moved together; D2 is D1's complement, so a crossed D shows.
    reg  d74, cp74, sd74, rd74, cp74b, sd74b, rd74b;
    wire q1, q1n, q2, q2n;
    hc74 u74 (.D1(d74), .CP1(cp74), .SD1_n(sd74), .RD1_n(rd74), .Q1(q1), .Q1_n(q1n),
              .D2(~d74), .CP2(cp74b), .SD2_n(sd74b), .RD2_n(rd74b), .Q2(q2), .Q2_n(q2n));
    task m74(input c, input s, input r);
        begin cp74 = c; sd74 = s; rd74 = r; cp74b = c; sd74b = s; rd74b = r; end
    endtask

    reg  [3:0] d175;
    reg        cp175, mr175;
    wire [3:0] q175, q175n;
    hc175 u175 (.MR_n(mr175), .CP(cp175), .D0(d175[0]), .D1(d175[1]), .D2(d175[2]), .D3(d175[3]),
                .Q0(q175[0]), .Q1(q175[1]), .Q2(q175[2]), .Q3(q175[3]),
                .Q0_n(q175n[0]), .Q1_n(q175n[1]), .Q2_n(q175n[2]), .Q3_n(q175n[3]));

    reg  [7:0] d273;
    reg        cp273, mr273;
    wire [7:0] q273;
    hc273 u273 (.MR_n(mr273), .CP(cp273),
                .D0(d273[0]), .D1(d273[1]), .D2(d273[2]), .D3(d273[3]),
                .D4(d273[4]), .D5(d273[5]), .D6(d273[6]), .D7(d273[7]),
                .Q0(q273[0]), .Q1(q273[1]), .Q2(q273[2]), .Q3(q273[3]),
                .Q4(q273[4]), .Q5(q273[5]), .Q6(q273[6]), .Q7(q273[7]));

    reg        dsa, dsb, cp164, mr164;
    wire [7:0] q164;
    hc164 u164 (.DSA(dsa), .DSB(dsb), .CP(cp164), .MR_n(mr164),
                .Q0(q164[0]), .Q1(q164[1]), .Q2(q164[2]), .Q3(q164[3]),
                .Q4(q164[4]), .Q5(q164[5]), .Q6(q164[6]), .Q7(q164[7]));

    // '595: Qn and Qn_oe as two bytes, Q7S alone; P595 goes in first, then
    // P595B pushes it out through Q7S
    localparam [7:0] P595 = 8'hB4, P595B = 8'hC9;
    reg        ds595, shcp595, stcp595, mr595, oe595;
    wire [7:0] q595, e595;
    wire       q7s595;
    hc595 u595 (.DS(ds595), .SHCP(shcp595), .STCP(stcp595), .MR_n(mr595), .OE_n(oe595),
                .Q0(q595[0]), .Q1(q595[1]), .Q2(q595[2]), .Q3(q595[3]),
                .Q4(q595[4]), .Q5(q595[5]), .Q6(q595[6]), .Q7(q595[7]),
                .Q0_oe(e595[0]), .Q1_oe(e595[1]), .Q2_oe(e595[2]), .Q3_oe(e595[3]),
                .Q4_oe(e595[4]), .Q5_oe(e595[5]), .Q6_oe(e595[6]), .Q7_oe(e595[7]),
                .Q7S(q7s595));

    integer i, n, pchk, perr;
    reg [7:0] pv, qv, exp8;

    initial begin
        $display("  tb_parts -- every package against its datasheet table, every output's delay");
        $display("     4096 exhaustive vectors + 3000 for the '688; delay checked 1 ns either side of TPD");
        go = 1'b0; v = 17'd0;
        m74(1'b0, 1'b1, 1'b1); d74 = 1'b0;
        d175 = 4'd0; cp175 = 1'b0; mr175 = 1'b1;
        d273 = 8'd0; cp273 = 1'b0; mr273 = 1'b1;
        dsa = 1'b0; dsb = 1'b1; cp164 = 1'b0; mr164 = 1'b1;
        ds595 = 1'b0; shcp595 = 1'b0; stcp595 = 1'b0; mr595 = 1'b1; oe595 = 1'b0;
        #50;

        // ---- combinational: exhaustive, then the comparator --------------
        for (i = 0; i < 4096; i = i + 1) apply(i[16:0]);
        for (i = 0; i < 3000; i = i + 1) begin
            pv = $random;
            case (i % 4)
                0:       qv = pv;                        // equal
                1:       qv = pv ^ (8'd1 << (i % 8));    // one bit apart
                default: qv = $random;
            endcase
            apply({(i % 8) == 7, qv, pv});               // /E high one vector in eight
        end

        // =================================================================
        // '74
        // =================================================================
        m74(1'b0, 1'b1, 1'b0); #30;
        ck(q1 === 1'b0 && q1n === 1'b1 && q2 === 1'b0 && q2n === 1'b1, "'74: /RD low clears both halves");
        m74(1'b0, 1'b1, 1'b1); #30;
        ck(q1 === 1'b0, "'74: letting /RD go changes nothing");
        d74 = 1'b1; #20 m74(1'b1, 1'b1, 1'b1);
        #13 ck(q1 === 1'b0, "'74: CP->Q: nothing 13 ns after the edge");
        #2  ck(q1 === 1'b1 && q1n === 1'b0, "'74: CP->Q: D taken, there 15 ns after (TPD 14)");
        ck(q2 === 1'b0 && q2n === 1'b1, "'74: half 2 took ITS D, /D1");
        d74 = 1'b0; #20 m74(1'b0, 1'b1, 1'b1); #30;
        ck(q1 === 1'b1, "'74: a falling edge takes nothing");
        m74(1'b1, 1'b1, 1'b1); #30;
        ck(q1 === 1'b0 && q2 === 1'b1, "'74: the next rise takes D = 0 (and /D = 1)");
        m74(1'b1, 1'b0, 1'b1);
        #13 ck(q1 === 1'b0, "'74: /SD->Q: nothing at 13 ns");
        #2  ck(q1 === 1'b1 && q1n === 1'b0, "'74: /SD->Q: set at 15 ns, with CP high");
        m74(1'b0, 1'b0, 1'b1); #20 m74(1'b1, 1'b0, 1'b1); #30;
        ck(q1 === 1'b1, "'74: a clock while /SD holds the part is ignored");
        m74(1'b1, 1'b1, 1'b1); #30;
        ck(q1 === 1'b1, "'74: letting /SD go with CP high takes nothing -- the held clock is gone");
        m74(1'b0, 1'b1, 1'b1); #20 m74(1'b1, 1'b1, 1'b1); #30;
        ck(q1 === 1'b0, "'74: and the next clock loads again");
        d74 = 1'b1; m74(1'b0, 1'b1, 1'b0); #20 m74(1'b1, 1'b1, 1'b0); #30;
        ck(q1 === 1'b0, "'74: a clock while /RD holds the part is ignored");
        m74(1'b1, 1'b0, 1'b0); #30;
        ck(q1 === 1'b1 && q1n === 1'b1, "'74: /SD and /RD both low: BOTH outputs high");
        m74(1'b1, 1'b0, 1'b1); #30;
        ck(q1 === 1'b1 && q1n === 1'b0, "'74: /RD lets go first: /SD, still low, sets");
        m74(1'b1, 1'b1, 1'b1); #30;
        ck(q1 === 1'b1 && q1n === 1'b0, "'74: and Q stays high when /SD lets go after it");
        m74(1'b1, 1'b0, 1'b0); #30 m74(1'b1, 1'b1, 1'b0); #30;
        ck(q1 === 1'b0 && q1n === 1'b1, "'74: /SD lets go first: /RD, still low, clears");
        m74(1'b1, 1'b1, 1'b1); #30;
        ck(q1 === 1'b0, "'74: and Q stays low when /RD lets go after it");
        // the halves are separate parts
        d74 = 1'b0; m74(1'b0, 1'b1, 1'b1); #30;
        cp74b = 1'b1; #30;
        ck(q1 === 1'b0 && q2 === 1'b1, "'74: CP2 clocks half 2 and not half 1");
        sd74 = 1'b0; #30;
        ck(q1 === 1'b1 && q2 === 1'b1, "'74: /SD1 sets half 1");
        rd74b = 1'b0; #30;
        ck(q1 === 1'b1 && q2 === 1'b0, "'74: /RD2 clears half 2 and not half 1");
        m74(1'b0, 1'b1, 1'b1); #30;

        // =================================================================
        // '175
        // =================================================================
        mr175 = 1'b0; #30;
        ck(q175 === 4'h0 && q175n === 4'hF, "'175: /MR clears, /Q all high");
        mr175 = 1'b1; d175 = 4'hA; #20 cp175 = 1'b1;
        #13 ck(q175 === 4'h0, "'175: CP->Q: nothing at 13 ns");
        #2  ck(q175 === 4'hA && q175n === 4'h5, "'175: CP->Q: D and /D at 15 ns (TPD 14)");
        d175 = 4'h5; #20 cp175 = 1'b0; #30;
        ck(q175 === 4'hA, "'175: a falling edge takes nothing");
        mr175 = 1'b0;
        #13 ck(q175 === 4'hA, "'175: /MR->Q: nothing at 13 ns");
        #2  ck(q175 === 4'h0, "'175: /MR->Q: cleared at 15 ns, asynchronously");
        cp175 = 1'b1; #30;
        ck(q175 === 4'h0, "'175: a clock under /MR is ignored");
        mr175 = 1'b1; #30;
        ck(q175 === 4'h0, "'175: letting /MR go with CP high takes nothing");
        cp175 = 1'b0; #20 cp175 = 1'b1; #30;
        ck(q175 === 4'h5, "'175: the next rise loads");
        cp175 = 1'b0;

        // =================================================================
        // '273
        // =================================================================
        mr273 = 1'b0; #30;
        ck(q273 === 8'h00, "'273: /MR clears");
        mr273 = 1'b1; d273 = 8'hC3; #20 cp273 = 1'b1;
        #14 ck(q273 === 8'h00, "'273: CP->Q: nothing at 14 ns");
        #2  ck(q273 === 8'hC3, "'273: CP->Q: all eight at 16 ns (TPD 15)");
        d273 = 8'h3C; #20 cp273 = 1'b0; #30;
        ck(q273 === 8'hC3, "'273: a falling edge takes nothing");
        cp273 = 1'b1; #30;
        ck(q273 === 8'h3C, "'273: a rise takes the new D");
        mr273 = 1'b0;
        #14 ck(q273 === 8'h3C, "'273: /MR->Q: nothing at 14 ns");
        #2  ck(q273 === 8'h00, "'273: /MR->Q: cleared at 16 ns, with CP high");
        mr273 = 1'b1; #30;
        ck(q273 === 8'h00, "'273: letting /MR go with CP high takes nothing");
        cp273 = 1'b0; d273 = 8'h5A; #20 cp273 = 1'b1; #30;
        ck(q273 === 8'h5A, "'273: the next rise loads");
        cp273 = 1'b0;

        // =================================================================
        // '164
        // =================================================================
        mr164 = 1'b0; #30;
        ck(q164 === 8'h00, "'164: /MR clears");
        mr164 = 1'b1; dsb = 1'b1; exp8 = 8'h00; n = 0;
        for (i = 7; i >= 0; i = i - 1) begin
            dsa = pv[i]; #20 cp164 = 1'b1;
            exp8 = {exp8[6:0], pv[i]};
            if (i == 7) begin
                #12 if (q164 !== 8'h00) n = n + 1;
                #2  if (q164 !== exp8) n = n + 1;
                #16;
            end else #30;
            if (q164 !== exp8) n = n + 1;
            cp164 = 1'b0;
        end
        ck(n == 0, "'164: eight clocks shift DSA in at Q0 and along to Q7; 12 ns nothing, 14 there");
        ck(q164 === pv, "'164: after eight, Q7..Q0 is the byte, first bit at Q7");
        dsa = 1'b1; dsb = 1'b0; #20 cp164 = 1'b1; #30 cp164 = 1'b0;
        ck(q164[0] === 1'b0 && q164[7:1] === pv[6:0], "'164: DSB low gates DSA: a 0 goes in");
        dsb = 1'b1; #20 cp164 = 1'b1; #30 cp164 = 1'b0;
        ck(q164[0] === 1'b1, "'164: DSA.DSB high: a 1 goes in");
        mr164 = 1'b0; #30;
        ck(q164 === 8'h00, "'164: /MR clears at any time");
        mr164 = 1'b1;

        // =================================================================
        // '595
        // =================================================================
        mr595 = 1'b0; #30;
        ck(q7s595 === 1'b0, "'595: /MR clears the shift register: Q7S low");
        stcp595 = 1'b1; #30 stcp595 = 1'b0;
        ck(q595 === 8'h00, "'595: STCP takes the cleared shift register: Qn all low");
        ck(e595 === 8'hFF, "'595: /OE low: all eight enabled");
        mr595 = 1'b1; exp8 = 8'h00; n = 0;
        for (i = 7; i >= 0; i = i - 1) begin
            ds595 = P595[i]; #20 shcp595 = 1'b1;
            exp8 = {exp8[6:0], P595[i]};
            if (i == 0) begin                            // P595[7] = 1 reaches Q7S
                #15 if (q7s595 !== 1'b0) n = n + 1;
                #2  if (q7s595 !== 1'b1) n = n + 1;
                #13;
            end else #30;
            if (q7s595 !== exp8[7]) n = n + 1;
            if (q595 !== 8'h00) n = n + 1;
            shcp595 = 1'b0;
        end
        ck(n == 0, "'595: eight SHCP shift DS in; Q7S is bit 7, 15 ns nothing, 17 there");
        ck(q595 === 8'h00, "'595: and nothing reaches Qn before STCP");
        stcp595 = 1'b1;
        #15 ck(q595 === 8'h00, "'595: STCP->Qn: nothing at 15 ns");
        #2  ck(q595 === P595, "'595: STCP->Qn: the byte at 17 ns (TPD 16), first bit at Q7");
        // P595B in, P595 out through Q7S, first bit first; Qn hold throughout.
        // The first shift is made with STCP still high, so its fall has a
        // different shift register to take, and must not.
        n = 0;
        for (i = 7; i >= 0; i = i - 1) begin
            ds595 = P595B[i]; #20 shcp595 = 1'b1;
            exp8 = {exp8[6:0], P595B[i]};
            #30;
            if (q7s595 !== exp8[7]) n = n + 1;
            if (q595 !== P595) n = n + 1;
            shcp595 = 1'b0;
            if (i == 7) begin
                stcp595 = 1'b0; #30;
                ck(q595 === P595, "'595: a falling STCP takes nothing");
            end
        end
        ck(n == 0, "'595: Q7S puts the old byte out bit by bit while Qn hold it");
        ck(q7s595 === P595B[7], "'595: after eight more, Q7S is the new byte's first bit");
        // /OE: the enables go, the values stay, and STCP still loads
        oe595 = 1'b1;
        #14 ck(e595 === 8'hFF, "'595: /OE->Qn_oe: nothing at 14 ns");
        #2  ck(e595 === 8'h00, "'595: /OE high: all eight disabled at 16 ns (TEN 15)");
        ck(q595 === P595, "'595: disabled, the value ports still carry the storage register");
        stcp595 = 1'b1; #30 stcp595 = 1'b0;
        ck(q595 === P595B && e595 === 8'h00, "'595: STCP loads while disabled; still disabled");
        oe595 = 1'b0;
        #14 ck(e595 === 8'h00, "'595: /OE low: nothing at 14 ns");
        #2  ck(e595 === 8'hFF, "'595: /OE low: all eight enabled again at 16 ns");
        ck(q7s595 === 1'b1, "'595: /OE does not touch Q7S");
        // /MR: the shift register only
        #20 mr595 = 1'b0;
        #15 ck(q7s595 === 1'b1, "'595: /MR->Q7S: nothing at 15 ns");
        #2  ck(q7s595 === 1'b0, "'595: /MR->Q7S: cleared at 17 ns, asynchronously");
        ck(q595 === P595B, "'595: /MR leaves the storage register: Qn hold");
        ds595 = 1'b1; #20 shcp595 = 1'b1; #30;
        stcp595 = 1'b1; #30 stcp595 = 1'b0;
        ck(q595 === 8'h00, "'595: STCP under /MR takes zero: all eight cleared, no SHCP shift");
        mr595 = 1'b1; #30;
        stcp595 = 1'b1; #30 stcp595 = 1'b0;
        ck(q595 === 8'h00 && q7s595 === 1'b0, "'595: letting /MR go with SHCP high takes nothing");
        shcp595 = 1'b0; #20;
        // the clocks tied: the storage register one clock behind
        ds595 = 1'b1; #20 shcp595 = 1'b1; stcp595 = 1'b1; #30;
        ck(q595 === 8'h00, "'595: SHCP and STCP tied: Qn take the shift register before the shift");
        shcp595 = 1'b0; stcp595 = 1'b0; ds595 = 1'b0; #20 shcp595 = 1'b1; stcp595 = 1'b1; #30;
        ck(q595 === 8'h01, "'595: and the next shared edge shows the bit: one clock behind");
        shcp595 = 1'b0; stcp595 = 1'b0;

        // ---- the tally --------------------------------------------------------
        pchk = p00.n_chk + p02.n_chk + p08.n_chk + p32.n_chk + p86.n_chk + p04.n_chk + p14.n_chk
             + p11.n_chk + p4002.n_chk + p138.n_chk + p148.n_chk + p151.n_chk + p157.n_chk
             + p688.n_chk + p125o.n_chk + p125e.n_chk + p244o.n_chk + p244e.n_chk + p4051.n_chk
             + pf2.n_chk + pf0.n_chk;
        perr = p00.n_err + p02.n_err + p08.n_err + p32.n_err + p86.n_err + p04.n_err + p14.n_err
             + p11.n_err + p4002.n_err + p138.n_err + p148.n_err + p151.n_err + p157.n_err
             + p688.n_err + p125o.n_err + p125e.n_err + p244o.n_err + p244e.n_err + p4051.n_err
             + pf2.n_err + pf0.n_err;
        chk = chk + pchk; errs = errs + perr;
        $display("");
        $display("  %0d checks (%0d of them probe samples), %0d errors.  %0s",
                 chk, pchk, errs, errs ? "FAIL" : "PASS");
        if (errs) $fatal(1);
        $finish;
    end

    initial begin
        #2000000;
        $display("  TIMEOUT");
        $fatal(1);
    end
endmodule
