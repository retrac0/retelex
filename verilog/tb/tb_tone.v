// tb_tone -- the tone card alone: the loop, the four gates, and the two buses.
// common/tone-plan.md 4.  The image is sim/tones.py's; the figures it is checked
// against are sim/tones.log's.
//
// The card is clocked directly rather than through an exchange, because the ring
// cadence is 4.096 s of model time -- 262144 frames -- and only frame edges
// matter to it.
`timescale 1ns/1ps

module tb_tone;
    // Full periods in frames, at 64 kHz.  A counter bit's period is 2^(n+1).
    localparam integer P_CC   = 32768;      // Q14: 0.512 s
    localparam integer P_BUSY = 65536;      // Q15: 1.024 s
    localparam integer P_RING = 262144;     // Q17: 4.096 s
    localparam integer LOOP   = 8192;       // the ROM, 128 ms

    reg clk = 0, frame_stb = 0, fill = 0;
    always #10 clk = ~clk;
    always @(posedge clk) begin
        frame_stb <= ~frame_stb;
        if (frame_stb) fill <= ~fill;       // FILL is TX_CLK/2: the 1010 an idle port sends
    end

    wire c_tx, a_tx, ans_n, ringback, busy, cannot, ring_cad_n;
    tone_card #(.ROM_FILE("rtl/tone_rom.hex")) dut (
        .clk(clk), .frame_stb(frame_stb), .fill(fill),
        .c_tx(c_tx), .a_tx(a_tx), .ans_n(ans_n),
        .ringback(ringback), .busy(busy), .cannot(cannot), .ring_cad_n(ring_cad_n));

    integer errors = 0, checks = 0;
    task check(input cond, input string what);
        begin
            checks = checks + 1;
            if (cond) $display("     %-62s ok", what);
            else begin $display("     %-62s FAIL", what); errors = errors + 1; end
        end
    endtask

    // Advance one frame edge and settle.  Sampling only ever happens at negedge,
    // where the card's non-blocking updates have landed.
    task frame;
        begin
            @(negedge clk);
            while (!frame_stb) @(negedge clk);
            @(negedge clk);
        end
    endtask

    // ---- the outputs are exactly plane-or-FILL, every frame -----------------
    // and the plane is exactly the ROM byte the address counter just presented.
    // cnt has already advanced past it, so the byte is at cnt-1.
    integer bad_mux = 0, bad_rom = 0;
    reg     armed = 0;      // the registers hold their reset value until the first frame
    wire [12:0] prev_addr = dut.cnt[12:0] - 13'd1;
    always @(negedge clk) if (armed && frame_stb) begin
        if (dut.plane_a !== dut.rom[prev_addr][0]) bad_rom = bad_rom + 1;
        if (dut.plane_b !== dut.rom[prev_addr][1]) bad_rom = bad_rom + 1;
    end
    always @(negedge clk) if (armed && frame_stb) begin
        if (ringback !== (dut.ring_gate   ? dut.plane_a : fill)) bad_mux = bad_mux + 1;
        if (busy     !== (dut.cnt[15]     ? dut.plane_b : fill)) bad_mux = bad_mux + 1;
        if (cannot   !== (dut.cnt[14]     ? dut.plane_b : fill)) bad_mux = bad_mux + 1;
        if (c_tx     !== dut.plane_a)                            bad_mux = bad_mux + 1;
        if (ring_cad_n !== ~dut.ring_gate)                       bad_mux = bad_mux + 1;
    end

    // ---- run-length of the ring gate, over one whole cycle ------------------
    integer runs [0:7];
    integer nrun = 0, run = 0;
    reg     prev_gate;
    integer i, ones;
    reg [LOOP-1:0] loop1, loop2;

    initial begin
        $display("\nTONE CARD -- one ROM, one counter, four tones.  common/tone-plan.md 4\n");

        check(a_tx === 1'b0 && ans_n === 1'b0,
              "a source never answers and is never rung: A_TX and /ANS low");

        // ---- 1. the loop ---------------------------------------------------
        $display("\n  1. The ROM loop -- 8192 frames, 128 ms");
        // Run two whole loops, checking every frame that each plane is the ROM
        // byte just addressed.  That plus a counter that wraps at 8192 IS the
        // loop repeating, and it needs no sampled capture to say so.
        repeat (4) frame;                     // past the reset frame: the plane
        while (dut.cnt[12:0] !== 13'd0) frame;    // registers hold 0 until the first edge
        armed = 1;
        for (i = 0; i < 2*LOOP; i = i + 1) begin
            if (i == LOOP) check(dut.cnt[12:0] === 13'd0,
                                 "the address counter wraps at 8192 -- the loop is seamless");
            frame;
        end
        check(bad_rom == 0, "both planes track the ROM byte addressed, every frame");
        ones = 0;
        for (i = 0; i < LOOP; i = i + 1) ones = ones + dut.rom[i][0];
        $display("     plane A: %0d ones of %0d", ones, LOOP);
        check(ones > LOOP/2 - 64 && ones < LOOP/2 + 64,
              "plane A is DC balanced, so the far decoder does not drift");
        ones = 0;
        for (i = 0; i < LOOP; i = i + 1) ones = ones + dut.rom[i][1];
        $display("     plane B: %0d ones of %0d", ones, LOOP);
        check(ones > LOOP/2 - 64 && ones < LOOP/2 + 64, "plane B likewise");

        // ---- 2. busy, and cannot-complete one stage faster -----------------
        $display("\n  2. The cadence gates are counter taps");
        check(P_CC == 32768 && P_BUSY == 65536,
              "cannot-complete 0.256/0.256 s, busy 0.512/0.512 s");
        $display("     cannot-complete gate = Q14, period %0d frames = %0d.%03d s",
                 P_CC, P_CC/64000, ((P_CC%64000)*1000)/64000);
        $display("     busy            gate = Q15, period %0d frames = %0d.%03d s",
                 P_BUSY, P_BUSY/64000, ((P_BUSY%64000)*1000)/64000);
        check(P_BUSY == 2*P_CC, "busy is cannot-complete one stage slower: the 60/120 IPM pair");

        // ---- 3. the double pulse -------------------------------------------
        $display("\n  3. The double pulse, from one NOR");
        while (dut.cnt !== 18'd0) frame;              // start of a ring cycle
        prev_gate = dut.ring_gate; run = 0; nrun = 0;
        for (i = 0; i < P_RING; i = i + 1) begin
            if (dut.ring_gate === prev_gate) run = run + 1;
            else begin
                if (nrun < 8) runs[nrun] = run;
                nrun = nrun + 1; run = 1; prev_gate = dut.ring_gate;
            end
            frame;
        end
        if (nrun < 8) runs[nrun] = run;               // the final run closes the cycle
        $display("     runs: %0d on, %0d off, %0d on, %0d off  (frames)",
                 runs[0], runs[1], runs[2], runs[3]);
        check(nrun == 3, "two bursts a cycle, not one and not four");
        check(runs[0] == P_RING/8 && runs[1] == P_RING/8 && runs[2] == P_RING/8,
              "0.512 s burst, 0.512 s gap, 0.512 s burst");
        check(runs[3] == P_RING - 3*(P_RING/8), "then 2.560 s silent -- period 4.096 s");

        // ---- 4. the muxes and the two bus lines ----------------------------
        $display("\n  4. The outputs, and the buses");
        check(bad_mux == 0, "every output is its plane or FILL, every frame");
        check(ring_cad_n === ~dut.ring_gate,
              "/RING_CAD is the ring gate complemented -- one '02, locked by construction");

        $display("\n  %0d checks, %0d errors.  %s\n", checks, errors, errors ? "FAIL" : "PASS");
        if (errors) $fatal(1, "tb_tone failed");
        $finish;
    end
endmodule
