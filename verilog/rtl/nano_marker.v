// nano_marker -- one board.  nano-marker.md.
//
// nano_reg (three-bit register) + ctl_write (cable B) + nano_core (scanner,
// probe, write engine, sequencer).  No network unit, no monitors, no card
// word, no write queue.  Digit 1 is one strapped block of uplink trunks
// (LEAF); everything else is a two-digit local number, octal as dialled.
//
// Key 0 hunts the operator at 04-07 (OP_EN), in fixed order from 04.  Either
// hunt skips a slot whose card word is all zeros -- none/OOS, which is what an
// open slot floats to -- so a group may have gaps in it.
//
// What it gives up against mini_marker, permanently: 8 and 9 as keys of their
// own.  The register counts 1..7 and folds 8, 9 and 0 all onto 0, so all three
// reach the operator.  A caller who reaches another exchange over the uplink
// keeps all ten digits: by then this marker has let go and the far register is
// counting.
`timescale 1ns/1ps

module nano_marker #(
    parameter integer HIT      = 8,
    parameter integer ID       = 128,
    parameter integer CLR      = 256,
    parameter integer NODIG    = 12000,
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
    input            tick_1k,
    input      [7:0] ha,
    input            pb_busy,
    input            pb_word,
    output           sdata,
    output           sclk,
    output           wr,
    output     [2:0] scan_port,
    output           scan_adv,
    output           scan_start,
    output           reg_busy,
    output           reg_gone,
    output           reg_nodig,
    output           reg_brk,
    output     [1:0] reg_ndig,
    output     [5:0] reg_digits,
    output           wr_stb,
    output     [5:0] wr_dst,
    output     [5:0] wr_src,
    output           wr_bsy,
    output           wr_clm
);
    wire        r_busy, r_gone, r_nodig, r_brk, r_hook;
    wire [1:0]  r_ndig;
    wire [5:0]  r_digits, r_port;
    wire        r_attach, r_release;
    wire [5:0]  r_aport;

    nano_reg #(.HIT(HIT), .ID(ID), .CLR(CLR), .NODIG(NODIG)) u_reg (
        .clk(clk), .rst_n(rst_n), .slotq(slotq), .tick(tick), .tick_1k(tick_1k),
        .ha(ha),
        .attach(r_attach), .attach_port(r_aport), .release_it(r_release),
        .busy(r_busy), .port(r_port),
        .ndig(r_ndig), .digits(r_digits),
        .gone(r_gone), .nodig(r_nodig), .brk(r_brk), .hook(r_hook));

    assign reg_busy   = r_busy;
    assign reg_gone   = r_gone;
    assign reg_nodig  = r_nodig;
    assign reg_brk    = r_brk;
    assign reg_ndig   = r_ndig;
    assign reg_digits = r_digits;

    wire       ser_req, ser_strobe, ser_busy;
    wire [5:0] ser_dst, ser_src;
    wire       ser_bsy, ser_clm, ser_g;

    ctl_write u_ser (
        .clk(clk), .rst_n(rst_n), .req(ser_req), .strobe(ser_strobe),
        .g(ser_g), .dst(ser_dst), .src(ser_src), .bsy(ser_bsy), .clm(ser_clm),
        .busy(ser_busy), .sdata(sdata), .sclk(sclk), .wr(wr));

    nano_core #(
        .DIALTONE(DIALTONE), .NOGO(NOGO), .LEAF(LEAF), .UP_BLK(UP_BLK),
        .OP_EN(OP_EN), .OP_BLK(OP_BLK)
    ) u_core (
        .clk(clk), .rst_n(rst_n),
        .slotq(slotq), .tick(tick), .oct_stb(oct_stb),
        .ha(ha), .pb_busy(pb_busy), .pb_word(pb_word),
        .r_busy(r_busy), .r_gone(r_gone), .r_nodig(r_nodig), .r_hook(r_hook),
        .r_ndig(r_ndig), .r_digits(r_digits), .r_port(r_port),
        .r_attach(r_attach), .r_release(r_release), .r_aport(r_aport),
        .ser_busy(ser_busy), .ser_req(ser_req), .ser_strobe(ser_strobe),
        .ser_dst(ser_dst), .ser_src(ser_src),
        .ser_bsy(ser_bsy), .ser_clm(ser_clm), .ser_g(ser_g),
        .scan_port(scan_port), .scan_adv(scan_adv), .scan_start(scan_start),
        .wr_stb(wr_stb), .wr_dst(wr_dst), .wr_src(wr_src),
        .wr_bsy(wr_bsy), .wr_clm(wr_clm)
    );
endmodule
