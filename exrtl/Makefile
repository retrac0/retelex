# exrtl -- the exchange in Verilog.  iverilog for the testbenches, yosys to
# confirm it is hardware and to count what it costs.
RTL   := rtl/mux8.v rtl/port.v rtl/block.v rtl/clock_card.v rtl/mainboard.v rtl/line_card.v rtl/exch_top.v
BUILD := build

all: fabric mvp two

$(BUILD):
	@mkdir -p $(BUILD)

fabric: $(BUILD)
	@iverilog -g2012 -I rtl -o $(BUILD)/fabric.vvp $(RTL) tb/tb_fabric.v && vvp $(BUILD)/fabric.vvp

mvp: $(BUILD)
	@iverilog -g2012 -I rtl -o $(BUILD)/mvp.vvp $(RTL) tb/tb_mvp.v && vvp $(BUILD)/mvp.vvp

# Lint the whole exchange fitted: with the MVP parameters most of the 64 card
# pins are genuinely unconnected, which is correct but drowns the real warnings.
two: $(BUILD)
	@iverilog -g2012 -I rtl -o $(BUILD)/two.vvp $(RTL) tb/mvp_site.v tb/tb_two.v && vvp $(BUILD)/two.vvp

lint:
	@verilator --lint-only -Wall -Wno-fatal -Irtl --top-module exch_top \
	    -GBLOCK_FITTED=255 -GPORT_FITTED=18446744073709551615 $(RTL)

# The full 64-port exchange, every block fitted: cells and flip-flops.
synth: $(BUILD)
	@printf 'read_verilog -sv -I rtl -defer $(RTL)\n\
	chparam -set BLOCK_FITTED 255 -set PORT_FITTED 18446744073709551615 exch_top\n\
	hierarchy -top exch_top\nproc; opt; fsm; opt; memory; opt\ntechmap; opt\nstat -top exch_top\n' > $(BUILD)/synth.ys
	@yosys -s $(BUILD)/synth.ys 2>&1 | tail -n 30

clean:
	@rm -rf $(BUILD)

.PHONY: all fabric mvp two lint synth clean
