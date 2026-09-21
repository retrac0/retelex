// tb_erlang -- the monitor pool against monitor.md 4's sizing table.
//
// 4 sizes the pool by Erlang B on an offered load, and the load is argued from
// three numbers: every call dialled with `1` anywhere in the network wants a
// monitor on each block its flood reaches; a monitor whose `e` is the one
// dialled holds until `b` is in, 2.7 s from the seizure; one whose `e` is not
// lets go after the first digit, 1.5 s.  Two a block to four exchanges, three
// to twenty, four to thirty-six, five beyond.
//
// Here the pool is offered the traffic and the loss is counted.  Nothing about
// the holding time is asserted: it is whatever the RTL's own windows make it,
// and it is measured and printed beside 4's figures.
//
// THE TIME BASE.  A monitor sees exactly two things from the clock card: the
// 8 kHz octet mark that steps its scanner, and the 1 kHz tick its three windows
// count on.  Their ratio is all that matters, so this bench keeps it -- eight
// octet marks a tick, one slot a mark, eight slots a millisecond, exactly as in
// the exchange -- and drops the 4.096 MHz master clock between them.  Every
// count the monitor makes is the count it makes in the real exchange; one model
// millisecond costs 8 clocks instead of 4096, which is what makes a run of
// twenty thousand model seconds possible at all.  The windows are the REAL
// ones: a pulse at 8 ms, a digit at 128, a caller gone at 256.
//
// SIX CHANNELS, NOT INFINITE SOURCES.  Erlang B assumes arrivals that do not
// care what is already up.  A block holds six trunk channels, so at the top of
// the table a few arrivals find no free CHANNEL and are never offered to the
// pool at all.  Those are counted and reported separately, and left out of both
// sides of the loss: they are an artefact of the block, not of 4's argument.
`timescale 1ns/1ps

module tb_erlang #(
    parameter integer NCALLS = 250,      // seizures offered at each load
    parameter integer LCG0   = 32'h1234_5678
) ();
    localparam integer MS  = 1000;                  // ns of $time in a model ms
    localparam [2:0]   OWN_E = 3'd2, OWN_B = 3'd3;
    localparam integer BRK = 60, MK = 40;           // ms: a dial at 10 pps, 60/40
    localparam integer HOLD_ON = 200, COOL = 50;    // ms after `b`, and before re-use

    // ---- the clock, and the two strobes a monitor gets ------------------
    // A clock IS the octet mark here: the 4.096 MHz between the two strobes is
    // the part a monitor never sees, so it is the part that goes.  Eight marks
    // a tick, one slot a mark, eight slots a millisecond -- the exchange's own
    // cadence, at 8 clocks a millisecond instead of 4096.
    reg clk = 0;
    always #62.5 clk = ~clk;                        // 8 clocks = 1000 ns = one ms
    reg rst_n = 0;
    reg [2:0] div = 0;
    always @(posedge clk) div <= div + 1'b1;
    wire oct_stb = 1'b1;                            // eight a millisecond
    wire tick_1k = (div == 3'd0);                   // and one tick under them

    // ---- the block's eight M and BUSY lines ------------------------------
    reg [7:0] m = 8'h00, busyv = 8'h00;

    // ---- four pools on the same stimulus ---------------------------------
    // One run sizes the whole column of 4's table at once: the cells differ,
    // the traffic does not.
    wire [3:0] pclaim, pheld, pfull;
    wire [1:0] c2; wire [2:0] c3; wire [3:0] c4; wire [4:0] c5;
    reg  [3:0] ack = 4'd0;
    always @(posedge clk) ack <= pclaim & ~ack;     // a marker that answers at once

    monitor #(.NMON(2), .OWN_E(OWN_E), .OWN_B(OWN_B), .BLOCK(3'd0)) u_p2 (
        .clk(clk), .rst_n(rst_n), .oct_stb(oct_stb), .tick_1k(tick_1k),
        .m(m), .busy(busyv), .chan_mask(8'b1110_1110),
        .claim(pclaim[0]), .claim_port(), .claim_ack(ack[0]),
        .held(pheld[0]), .all_busy(pfull[0]), .cells(c2));
    monitor #(.NMON(3), .OWN_E(OWN_E), .OWN_B(OWN_B), .BLOCK(3'd0)) u_p3 (
        .clk(clk), .rst_n(rst_n), .oct_stb(oct_stb), .tick_1k(tick_1k),
        .m(m), .busy(busyv), .chan_mask(8'b1110_1110),
        .claim(pclaim[1]), .claim_port(), .claim_ack(ack[1]),
        .held(pheld[1]), .all_busy(pfull[1]), .cells(c3));
    monitor #(.NMON(4), .OWN_E(OWN_E), .OWN_B(OWN_B), .BLOCK(3'd0)) u_p4 (
        .clk(clk), .rst_n(rst_n), .oct_stb(oct_stb), .tick_1k(tick_1k),
        .m(m), .busy(busyv), .chan_mask(8'b1110_1110),
        .claim(pclaim[2]), .claim_port(), .claim_ack(ack[2]),
        .held(pheld[2]), .all_busy(pfull[2]), .cells(c4));
    monitor #(.NMON(5), .OWN_E(OWN_E), .OWN_B(OWN_B), .BLOCK(3'd0)) u_p5 (
        .clk(clk), .rst_n(rst_n), .oct_stb(oct_stb), .tick_1k(tick_1k),
        .m(m), .busy(busyv), .chan_mask(8'b1110_1110),
        .claim(pclaim[3]), .claim_port(), .claim_ack(ack[3]),
        .held(pheld[3]), .all_busy(pfull[3]), .cells(c5));

    // ---- the random stream ------------------------------------------------
    // The tb's own generator, so that Icarus and Verilator measure the same
    // traffic to the call: $random does not agree between them.
    reg [31:0] lcg = LCG0;
    function real urand;
        begin
            lcg = lcg * 32'd1664525 + 32'd1013904223;
            urand = (lcg[30:0] + 1.0) / 2147483648.0;
        end
    endfunction

    // 0-7, and a dialled 0 is ten pulses (protocol.md 5)
    function integer pulses(input integer d); pulses = (d == 0) ? 10 : d; endfunction

    // ---- the traffic generator -------------------------------------------
    // One state machine a channel, stepped on the 1 kHz tick: the caller's
    // pause, the pulses of e, the pause, the pulses of b, and the release.
    localparam integer S_IDLE=0, S_PAUSE=1, S_BRK=2, S_MK=3, S_HOLD=4, S_COOL=5;

    integer cst  [0:7];
    integer ctmr [0:7];
    integer cn   [0:7];                  // pulses left in this digit
    integer cdig [0:7];                  // 0 = e is being dialled, 1 = b
    integer cbp  [0:7];                  // pulses of b, kept for when e is done
    integer cbusy[0:7];                  // ms until the marker marks it BUSY

    reg     gen_on = 1'b0;
    real    lam;                         // arrivals a millisecond
    real    p_e;                         // share of floods whose e is ours
    integer nxt;
    integer offered, nofree, blocked [0:3];
    integer k, j;
    reg     any;
    real    occ [0:3];                   // cell-milliseconds, for the carried load
    integer t_ms;

    task start_call(input integer ch);
        integer de, db;
        begin
            de = (urand() < p_e) ? OWN_E : ((OWN_E + 1 + $rtoi(urand() * 7.0)) % 8);
            db = (urand() < 0.125) ? OWN_B : ((OWN_B + 1 + $rtoi(urand() * 7.0)) % 8);
            cst [ch] = S_PAUSE;
            ctmr[ch] = 500 + $rtoi(urand() * 600.0);      // the caller's pause
            cn  [ch] = pulses(de);
            cbp [ch] = pulses(db);
            cdig[ch] = 0;
            cbusy[ch] = 4;                              // the marker's own scan
            m[ch] = 1'b1;                               // the seizure
        end
    endtask

    always @(posedge clk) if (rst_n && tick_1k) begin
        t_ms = t_ms + 1;
        for (j = 0; j < 4; j = j + 1)
            occ[j] = occ[j] + ((j == 0) ? $countones(c2) : (j == 1) ? $countones(c3) :
                               (j == 2) ? $countones(c4) : $countones(c5));

        // the marker marks an arriving seizure BUSY a scan later
        for (k = 0; k < 8; k = k + 1) begin
            if (cbusy[k] > 0) begin
                cbusy[k] = cbusy[k] - 1;
                if (cbusy[k] == 0) busyv[k] = 1'b1;
            end
        end

        // each channel's own call
        for (k = 0; k < 8; k = k + 1) begin
            if (ctmr[k] > 0) ctmr[k] = ctmr[k] - 1;
            if (ctmr[k] == 0) case (cst[k])
            S_PAUSE: begin cst[k] = S_BRK; ctmr[k] = BRK; m[k] = 1'b0; end
            S_BRK:   begin cst[k] = S_MK;  ctmr[k] = MK;  m[k] = 1'b1; end
            S_MK: begin
                cn[k] = cn[k] - 1;
                if (cn[k] > 0) begin cst[k] = S_BRK; ctmr[k] = BRK; m[k] = 1'b0; end
                else if (cdig[k] == 0) begin              // e is in: pause, then b
                    cdig[k] = 1; cn[k] = cbp[k];
                    cst[k] = S_PAUSE; ctmr[k] = 500 + $rtoi(urand() * 600.0);
                end else begin                            // b is in
                    cst[k] = S_HOLD; ctmr[k] = HOLD_ON;
                end
            end
            S_HOLD: begin                                 // the flood lets go
                m[k] = 1'b0; busyv[k] = 1'b0;
                cst[k] = S_COOL; ctmr[k] = COOL;
            end
            S_COOL:  cst[k] = S_IDLE;
            default: ;
            endcase
        end

        // Poisson arrivals: an exponential gap, and the first free channel
        if (gen_on && offered + nofree < NCALLS) begin
            if (nxt > 0) nxt = nxt - 1;
            if (nxt == 0) begin
                nxt = 1 + $rtoi(-$ln(urand()) / lam);
                any = 1'b0;
                for (k = 1; k < 8; k = k + 1)
                    if (!any && k != 4 && cst[k] == S_IDLE) begin
                        any = 1'b1;
                        // 4 counts a call lost when every monitor is busy AS
                        // THE SEIZURE ARRIVES: that is this sample.
                        for (j = 0; j < 4; j = j + 1)
                            if (pfull[j]) blocked[j] = blocked[j] + 1;
                        offered = offered + 1;
                        start_call(k);
                    end
                if (!any) nofree = nofree + 1;
            end
        end
    end

    // ---- Erlang B ---------------------------------------------------------
    function real erlb(input real a, input integer mm);
        integer i; real b;
        begin
            b = 1.0;
            for (i = 1; i <= mm; i = i + 1) b = a * b / (i + a * b);
            erlb = b;
        end
    endfunction

    integer errs = 0, chk = 0;
    task want(input v, input string what);
        begin
            chk = chk + 1;
            if (!v) begin errs = errs + 1; $display("     %-56s FAIL", what); end
            else $display("     %-56s ok", what);
        end
    endtask

    // ---- one load -----------------------------------------------------------
    real a_meas, p, band;
    integer i2;
    task run_load(input real a_target, input real pe, input real h_exp,
                  input string what);
        begin
            p_e = pe;
            lam = a_target / h_exp;              // arrivals a millisecond
            offered = 0; nofree = 0; nxt = 1; t_ms = 0;
            for (i2 = 0; i2 < 4; i2 = i2 + 1) begin blocked[i2] = 0; occ[i2] = 0.0; end
            $display("\n  %s", what);
            $display("     offering %0d seizures at %0.3f a second ...", NCALLS,
                     lam * 1000.0);
            gen_on = 1'b1;
            wait (offered + nofree >= NCALLS);
            gen_on = 1'b0;
            #(4000 * MS);                        // let the last calls finish
            a_meas = occ[3] / t_ms;              // the five-cell pool carries nearly all

            $display("     %0d seizures offered, %0d found no free channel;  %0.3f E carried,",
                     offered, nofree, a_meas);
            $display("     a monitor held %0.2f s on average, against 4's %0.1f s",
                     (a_meas / lam) / 1000.0, h_exp / 1000.0);
            $display("       cells   Erlang B   measured");
            for (i2 = 0; i2 < 4; i2 = i2 + 1) begin
                p = 1.0 * blocked[i2] / offered;
                $display("         %0d      %6.2f %%   %6.2f %%   (%0d of %0d)",
                         i2 + 2, 100.0 * erlb(a_meas, i2 + 2), 100.0 * p,
                         blocked[i2], offered);
            end
            // the instrument first: the traffic offered must be the traffic
            // asked for.  Too few calls and the estimate is noise, so the
            // short Icarus run measures without asserting.
            if (NCALLS >= 100)
                want(a_meas > 0.82 * a_target && a_meas < 1.18 * a_target,
                     "the load offered is the load 4 assumes");
            for (i2 = 0; i2 < 4; i2 = i2 + 1) begin
                p    = erlb(a_meas, i2 + 2);
                band = 4.0 * $sqrt(p * (1.0 - p) / offered) + 0.005;
                want((1.0 * blocked[i2] / offered) < p + band &&
                     (1.0 * blocked[i2] / offered) > p - band,
                     $sformatf("%0d cells: the loss is Erlang B's, inside 4 sigma", i2 + 2));
            end
        end
    endtask

    // ---- what a monitor is actually held for --------------------------------
    // The cell lets go part way through the dialling, so the moment is caught
    // as it happens rather than looked for afterwards.
    real t0, t_fall;
    always @(negedge pheld[3]) t_fall = $realtime;

    task hold_case(input integer de, input integer db, input string what,
                   output real ms_held);
        integer i, n;
        begin
            wait (!pheld[3]);
            #(300 * MS);
            m[1] = 1'b1; t0 = $realtime;              // the seizure
            #(8 * MS);  busyv[1] = 1'b1;              // the marker, a scan later
            #(792 * MS);                              // the caller's pause
            for (n = 0; n < 2; n = n + 1) begin
                for (i = 0; i < ((n == 0) ? pulses(de) : pulses(db)); i = i + 1) begin
                    m[1] = 1'b0; #(BRK * MS); m[1] = 1'b1; #(MK * MS);
                end
                if (n == 0) #(800 * MS);
            end
            #(400 * MS);
            ms_held = (t_fall - t0) / MS;
            $display("     %-40s %6.2f s", what, ms_held / 1000.0);
            m[1] = 1'b0; busyv[1] = 1'b0; #(400 * MS);
        end
    endtask

    real h_no, h_yes, h_clm;

    initial begin
        t_ms = 0;
        for (k = 0; k < 8; k = k + 1) begin
            cst[k] = S_IDLE; ctmr[k] = 0; cn[k] = 0; cdig[k] = 0;
            cbp[k] = 0; cbusy[k] = 0;
        end
        for (j = 0; j < 4; j = j + 1) begin blocked[j] = 0; occ[j] = 0.0; end
        p_e = 1.0; lam = 0.0001; nxt = 0; offered = 0; nofree = 0;

        $display("ERLANG (RTL) -- the monitor pool against monitor.md 4.\n");
        $display("  The windows are the real ones (8, 128, 256 ms) and the dial is 10 pps,");
        $display("  60/40, with 500-1100 ms between digits.\n");
        #4000 rst_n = 1;
        #(2000 * MS);

        // ---- 1. how long a monitor is held --------------------------------
        $display("  1. What a monitor is held for, from the seizure:");
        hold_case(3, 3, "e is not ours: it lets go at once",       h_no);
        hold_case(2, 5, "e is ours, b is not: it reads one more",  h_yes);
        hold_case(2, 3, "e and b are both ours: it CLAIMS",        h_clm);
        $display("     4 assumes 1.5 s for the first and 2.7 s for the others.");
        want(h_no > 1000.0 && h_no < 2000.0,  "the first is about 4's 1.5 s");
        want(h_yes > 2000.0 && h_yes < 3400.0, "the second is about 4's 2.7 s");
        want(h_clm < h_yes + 200.0,
             "and a CLAIM frees its cell too: not held for the whole call");

        // ---- 2. the loads of 4's table ------------------------------------
        run_load(0.26, 1.0,   2700.0, "2. Eight exchanges, one `e` for all -- 4's 0.26 E row.");
        run_load(0.39, 0.125, 1650.0, "3. Twenty exchanges, codes over eight `e` -- 0.39 E.");
        run_load(0.93, 0.125, 1650.0, "4. Forty-seven exchanges -- 0.93 E, the last row.");

        $display("\n  %0d checks, %0d errors.  %s", chk, errs, (errs == 0) ? "PASS" : "FAIL");
        if (errs) $fatal(1);
        $finish;
    end

    initial begin #200_000_000_000; $display("  TIMEOUT"); $finish; end
endmodule
