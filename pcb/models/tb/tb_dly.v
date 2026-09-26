// tb_dly -- the delay cell every output in 74hc.v goes through, the RC it
// also makes, and the setup/hold watch on the flip-flops.
//
// The Verilator simulator ignores the delay on a continuous assignment (pcb/out/synth_dly),
// so hc_dly1 is procedural, and this bench is the proof that it delays, that
// it is inertial, that a tied input still arrives, and that rc_filt starts
// from a discharged capacitor.  Built twice: as it is, and with HC_TRANSPORT,
// where a pulse narrower than the delay must pass instead of vanishing.
//
// NOT COVERED: delays that are not whole nanoseconds; an input that changes
// in the same time step as a wake-up (the order is the simulator's, and a
// pulse exactly TPD wide may or may not pass).
`timescale 1ns/1ps

module tb_dly;
    integer chk = 0, errs = 0;

    task ck(input cond, input [8*72-1:0] what);
        begin
            chk = chk + 1;
            if (!cond) begin errs = errs + 1; $display("    FAIL  %0s  at %0t", what, $time); end
        end
    endtask

    // ---- the cells ---------------------------------------------------------
    reg  a;                     // symmetric, 7 ns
    wire ya;
    hc_dly1 #(.DR(7)) u_a (.a(a), .y(ya));

    reg  b;                     // the power-on RC: 20 up, 5 down, born low
    wire yb;
    rc_filt #(.T_UP(20), .T_DN(5), .INIT(0)) u_b (.A(b), .Y(yb));

    wire yc;                    // a tied input, which never changes
    hc_dly1 #(.DR(7)) u_c (.a(1'b1), .y(yc));

    reg  p, q;                  // a zero-width glitch: p rises, then q falls, one time step
    wire g = p & q;
    wire yg;
    hc_dly1 #(.DR(7)) u_g (.a(g), .y(yg));
    integer n_yg = 0;
    always @(posedge yg) n_yg = n_yg + 1;

    reg  [1:0] v;               // two bits, one delay each
    wire [1:0] yv;
    hc_dly #(.W(2), .D(7)) u_v (.a(v), .y(yv));

    reg  [7:0] rd;              // the watch, on a real part
    reg        rcp, rmr;
    wire [7:0] rq;
    hc273 u_r (.MR_n(rmr), .CP(rcp),
               .D0(rd[0]), .D1(rd[1]), .D2(rd[2]), .D3(rd[3]),
               .D4(rd[4]), .D5(rd[5]), .D6(rd[6]), .D7(rd[7]),
               .Q0(rq[0]), .Q1(rq[1]), .Q2(rq[2]), .Q3(rq[3]),
               .Q4(rq[4]), .Q5(rq[5]), .Q6(rq[6]), .Q7(rq[7]));

    integer t0;

    initial begin
        $display("  tb_dly -- the inertial delay cell, the power-on RC, the setup/hold watch");
`ifdef HC_TRANSPORT
        $display("     built with HC_TRANSPORT: every delay a transport delay");
`endif
        a = 1'b0; b = 1'b1; p = 1'b0; q = 1'b1; v = 2'b00;
        rd = 8'h00; rcp = 1'b0; rmr = 1'b1;

        // ---- time zero ------------------------------------------------------
        #1;
        ck(yb === 1'b0, "RC: the capacitor is born discharged, whatever A says");
        #5  ck(yc !== 1'b1, "a tied input has not arrived 6 ns in");
        #3  ck(yc === 1'b1, "a tied input has arrived 8 ns in: the time-0 wake-up");
        #10 ck(yb === 1'b0, "RC: still charging 19 ns after power-on");
        #2  ck(yb === 1'b1, "RC: over the threshold 21 ns after power-on -- the power-on reset");
        ck(ya === 1'b0, "a held low input is low at the output");

        // ---- a clean edge, both ways ---------------------------------------
        #20 t0 = $time; a = 1'b1;
        #6  ck(ya === 1'b0, "RISE: nothing 6 ns after the input");
        #2  ck(ya === 1'b1, "RISE: there 8 ns after");
        #20 a = 1'b0;
        #6  ck(ya === 1'b1, "FALL: nothing 6 ns after the input");
        #2  ck(ya === 1'b0, "FALL: there 8 ns after");

        // ---- a pulse narrower than the delay --------------------------------
        #20 a = 1'b1;
        #3  a = 1'b0;
        #3  ck(ya === 1'b0, "a 3 ns pulse has not arrived at 6 ns");
`ifdef HC_TRANSPORT
        #2  ck(ya === 1'b1, "TRANSPORT: the 3 ns pulse arrives, at 7 ns");
        #3  ck(ya === 1'b0, "TRANSPORT: and it is 3 ns wide");
`else
        #2  ck(ya === 1'b0, "INERTIAL: a 3 ns pulse never reaches the output (8 ns)");
        #3  ck(ya === 1'b0, "INERTIAL: nor later (11 ns)");
`endif

        // ---- a pulse wider than the delay keeps its width ------------------
        #20 a = 1'b1;
        #10 a = 1'b0;
        ck(ya === 1'b1, "a 10 ns pulse is on the output 10 ns in");
        #6  ck(ya === 1'b1, "and still at 16 ns");
        #2  ck(ya === 1'b0, "and gone at 18 ns: it came out 10 ns wide");

        // ---- the RC: slow up, fast down, short dips swallowed ---------------
        #30 b = 1'b0;
        #4  b = 1'b1;
`ifdef HC_TRANSPORT
        #10 ;
`else
        #1  ck(yb === 1'b1, "RC: a 4 ns dip does not reach a 5 ns threshold");
        #10 ck(yb === 1'b1, "RC: nor later");
`endif
        #30 b = 1'b0;
        #4  ck(yb === 1'b1, "RC: 4 ns into a long dip, still above");
        #2  ck(yb === 1'b0, "RC: 6 ns in, below -- T_DN is 5");
        #4  b = 1'b1;
        #19 ck(yb === 1'b0, "RC: 19 ns after the dip ends, still charging");
        #2  ck(yb === 1'b1, "RC: 21 ns after, charged -- T_UP is 20");

        // ---- a zero-width glitch -------------------------------------------
        #30 n_yg = 0;
        p = 1'b1;
        #0 q = 1'b0;
        #20;
// Icarus only: Verilator 5.050 does not resume '#0 q = 0' in the same time
// step -- it ran it at 37 ns, after the 7 ns timer (pcb/out/dlyx/g.v) -- so
// under Verilator this is a 7 ns pulse, not a zero-wide glitch.
`ifndef HC_TRANSPORT
`ifndef VERILATOR
        ck(n_yg == 0, "INERTIAL: a glitch zero wide never makes an edge");
`endif
`endif
        ck(yg === 1'b0, "the glitching AND settles low");

        // ---- per bit ---------------------------------------------------------
        #30 v[0] = 1'b1;
        #3  v[1] = 1'b1;
        #5  ck(yv === 2'b01, "PER BIT: bit 0 arrives 7 ns after ITS change, not held back by bit 1");
        #3  ck(yv === 2'b11, "PER BIT: bit 1 arrives 7 ns after its own");

        // ---- the setup/hold watch --------------------------------------------
`ifndef HC_NO_TCHK
        #30 rd = 8'h11;
        #20 rcp = 1'b1;                    // 20 ns of setup: clean
        #20 rd = 8'h22;                    // 20 ns of hold: clean
        #20 rcp = 1'b0;
        ck(u_r.u_t.n_setup == 0 && u_r.u_t.n_hold == 0, "WATCH: 20 ns either side is silent");
        ck(rq === 8'h11, "and the register took what D held at the edge");
        #20 rd = 8'h33;
        #5  rcp = 1'b1;                    // 5 ns of setup against 12
        #20 rcp = 1'b0;
        ck(u_r.u_t.n_setup == 1, "WATCH: D 5 ns before the edge is a setup violation");
        #20 rcp = 1'b1;
        #2  rd = 8'h44;                    // 2 ns of hold against 3
        #20 rcp = 1'b0;
        ck(u_r.u_t.n_hold == 1, "WATCH: D 2 ns after the edge is a hold violation");
        #20 rmr = 1'b0;
        #20 rd = 8'h55;
        #2  rcp = 1'b1;                    // cleared: the part does not clock
        #20 rcp = 1'b0; rmr = 1'b1;
        ck(u_r.u_t.n_setup == 1, "WATCH: an edge while /MR holds the part is not checked");
`endif

        $display("");
        $display("  %0d checks, %0d errors.  %0s", chk, errs, errs ? "FAIL" : "PASS");
        if (errs) $fatal(1);
        $finish;
    end

    initial begin
        #100000;
        $display("  TIMEOUT");
        $fatal(1);
    end
endmodule
