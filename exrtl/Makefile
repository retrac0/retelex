# exrtl -- the exchange in Verilog.
#
# Two simulators run the same testbenches.  Icarus is the reference; Verilator
# is about two orders of magnitude faster and is what to use while working --
# the network testbench is 3 s of model time, which is minutes under Icarus and
# 22 s under Verilator.  Anything that passes under one must pass under the other.
RTL   := rtl/mux8.v rtl/ctl_write.v rtl/pulse_rx.v rtl/pulse_reg.v rtl/monitor.v rtl/marker.v \
         rtl/source_card.v rtl/port.v rtl/block.v rtl/clock_card.v rtl/mainboard.v \
         rtl/line_card.v rtl/mf8_encoder.v rtl/mf8_decoder.v rtl/mf8_framer.v \
         rtl/mf8_trunk_card.v rtl/exch_top.v
BUILD := build

TB_fabric := tb/tb_fabric.v
TB_mvp    := tb/tb_mvp.v
TB_two    := tb/mvp_site.v tb/tb_two.v
TB_trunk  := tb/trunk_site.v tb/bitpath.v tb/tb_trunk.v
TB_net    := tb/net_site.v tb/bitpath.v tb/tb_net.v

SIMS   := fabric mvp two trunk net
IVFLAG := -g2012 -I rtl
VLFLAG := --binary --timing -j 4 -Irtl -Wno-fatal

all: $(SIMS)

$(BUILD):
	@mkdir -p $(BUILD)

# Verilator, the fast one: `make fabric`, `make net`, ...
$(SIMS): %: $(BUILD)
	@mkdir -p $(BUILD)/vl/$*
	@verilator $(VLFLAG) --top-module tb_$* --Mdir $(BUILD)/vl/$* -o tb_$* \
	    $(RTL) $(TB_$*) > $(BUILD)/vl-$*.log 2>&1 || (cat $(BUILD)/vl-$*.log; false)
	@$(BUILD)/vl/$*/tb_$* 2>&1 | grep -v '^- '

# Icarus, the reference: `make iv-fabric`, `make iv-net`, ...
IVSIMS := $(addprefix iv-,$(SIMS))
$(IVSIMS): iv-%: $(BUILD)
	@iverilog $(IVFLAG) -o $(BUILD)/$*.vvp $(RTL) $(TB_$*) && vvp $(BUILD)/$*.vvp

iv: $(IVSIMS)

# The MF8 link with the two exchanges' crystals 100 ppm apart.
trunk-ppm: $(BUILD)
	@mkdir -p $(BUILD)/vl/trunkppm
	@verilator $(VLFLAG) -Gtb_trunk.PPM=100 --top-module tb_trunk \
	    --Mdir $(BUILD)/vl/trunkppm -o tb_trunkppm $(RTL) $(TB_trunk) > /dev/null 2>&1
	@$(BUILD)/vl/trunkppm/tb_trunkppm 2>&1 | grep -v '^- '

lint:
	@verilator --lint-only -Wall -Wno-fatal -Irtl --top-module exch_top \
	    -GBLOCK_FITTED=255 -GPORT_FITTED=18446744073709551615 $(RTL)
	@verilator --lint-only -Wall -Wno-fatal -Irtl --top-module mf8_trunk_card \
	    rtl/mf8_trunk_card.v rtl/mf8_encoder.v rtl/mf8_decoder.v rtl/mf8_framer.v
	@verilator --lint-only -Wall -Wno-fatal -Irtl --top-module marker \
	    rtl/marker.v

# The full 64-port exchange, every block fitted: cells and flip-flops.
synth: $(BUILD)
	@printf 'read_verilog -sv -I rtl -defer $(RTL)\n\
	chparam -set BLOCK_FITTED 255 -set PORT_FITTED 18446744073709551615 exch_top\n\
	hierarchy -top exch_top\nproc; opt; fsm; opt; memory; opt\ntechmap; opt\nstat -top exch_top\n' > $(BUILD)/synth.ys
	@yosys -s $(BUILD)/synth.ys 2>&1 | tail -n 30

clean:
	@rm -rf $(BUILD)

.PHONY: all iv $(SIMS) $(IVSIMS) trunk-ppm lint synth clean
