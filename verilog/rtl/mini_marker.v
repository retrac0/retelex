// mini_marker -- bring-up common control.  mini-marker.md.
//
// Register (pulse_reg) + cable-B serialiser (ctl_write) + mini_core
// (scanner / probe / sequencer).  Digit 1 is a highway until HAS_NET; LEAF
// makes digit 1 an uplink hunt (leaf-uplink.md).
`timescale 1ns/1ps

module mini_marker #(
    parameter integer HIT      = 8,
    parameter integer ID       = 128,
    parameter integer CLR      = 256,
    parameter integer NODIG    = 12000,
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
    output           sdata,
    output           sclk,
    output           wr,
    output     [5:0] probe_port,
    output     [2:0] scan_port,
    output           probe_visit,
    output           probe_valid,
    output           probe_m,
    output           probe_busy,
    output    [15:0] probe_word,
    output           flood_go,
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
    output           reg_busy,
    output           reg_gone,
    output           reg_nodig,
    output           reg_brk,
    output     [2:0] reg_ndig,
    output    [15:0] reg_digits,
    output           wq_ovf,
    output           wr_stb,
    output     [5:0] wr_dst,
    output     [5:0] wr_src,
    output           wr_bsy,
    output           wr_clm
);
    wire        r_busy, r_gone, r_nodig, r_brk, r_hook;
    wire [2:0]  r_ndig;
    wire [15:0] r_digits;
    wire        r_attach, r_release, r_restart_loc;
    wire [5:0]  r_aport;
    wire        restart_w = (HAS_NET && net_restart) | r_restart_loc;

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
    assign probe_word = 16'd0;

    wire       ser_req, ser_strobe, ser_busy;
    wire [5:0] ser_dst, ser_src;
    wire       ser_bsy, ser_clm, ser_g;

    ctl_write u_ser (
        .clk(clk), .rst_n(rst_n), .req(ser_req), .strobe(ser_strobe),
        .g(ser_g), .dst(ser_dst), .src(ser_src), .bsy(ser_bsy), .clm(ser_clm),
        .busy(ser_busy), .sdata(sdata), .sclk(sclk), .wr(wr));

    mini_core #(
        .DIALTONE(DIALTONE), .NOGO(NOGO),
        .HAS_NET(HAS_NET), .LEAF(LEAF),
        .TRUNK_MASK(TRUNK_MASK), .UPLINK_MASK(UPLINK_MASK)
    ) u_core (
        .clk(clk), .rst_n(rst_n),
        .slotq(slotq), .tick(tick), .frame_stb(frame_stb),
        .oct_stb(oct_stb), .tick_1k(tick_1k),
        .ha(ha), .pb_busy(pb_busy),
        .r_busy(r_busy), .r_gone(r_gone), .r_nodig(r_nodig), .r_hook(r_hook),
        .r_ndig(r_ndig), .r_digits(r_digits),
        .r_attach(r_attach), .r_release(r_release),
        .r_restart_loc(r_restart_loc), .r_aport(r_aport),
        .ser_busy(ser_busy), .ser_req(ser_req), .ser_strobe(ser_strobe),
        .ser_dst(ser_dst), .ser_src(ser_src),
        .ser_bsy(ser_bsy), .ser_clm(ser_clm), .ser_g(ser_g),
        .probe_port(probe_port), .scan_port(scan_port),
        .probe_visit(probe_visit), .probe_valid(probe_valid),
        .probe_m(probe_m), .probe_busy(probe_busy),
        .flood_go(flood_go), .flood_caller(flood_caller),
        .net_restart(net_restart), .net_done(net_done), .net_nogo(net_nogo),
        .net_local(net_local), .net_att(net_att), .net_att_port(net_att_port),
        .net_nw(net_nw), .net_wdst(net_wdst), .net_wsrc(net_wsrc),
        .net_wbsy(net_wbsy), .net_wclm(net_wclm), .net_wev(net_wev),
        .wq_ovf(wq_ovf), .wr_stb(wr_stb),
        .wr_dst(wr_dst), .wr_src(wr_src), .wr_bsy(wr_bsy), .wr_clm(wr_clm)
    );
endmodule
