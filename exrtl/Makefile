# exrtl -- the exchange in Verilog.
#
# Two simulators run the same testbenches.  Icarus is the reference; Verilator
# is about two orders of magnitude faster and is what to use while working --
# the network testbench is 3 s of model time, which is minutes under Icarus and
# 22 s under Verilator.  Anything that passes under one must pass under the other.
RTL   := rtl/mux8.v rtl/ctl_write.v rtl/stats.v rtl/console.v rtl/pulse_rx.v rtl/pulse_reg.v rtl/monitor.v rtl/marker.v \
         rtl/source_card.v rtl/port.v rtl/block.v rtl/clock_card.v rtl/mainboard.v \
         rtl/line_card.v rtl/mf8_encoder.v rtl/mf8_decoder.v rtl/mf8_framer.v \
         rtl/mf8_trunk_card.v rtl/exch_top.v
BUILD := build

TB_fabric := tb/tb_fabric.v
TB_mvp    := tb/tb_mvp.v
TB_two    := tb/mvp_site.v tb/tb_two.v
TB_trunk  := tb/trunk_site.v tb/bitpath.v tb/tb_trunk.v
TB_net    := tb/net_site.v tb/bitpath.v tb/tb_net.v
TB_chain  := tb/net_site.v tb/bitpath.v tb/tb_chain.v
TB_monitor := tb/tb_monitor.v
TB_pool   := tb/net_site.v tb/bitpath.v tb/tb_pool.v
TB_hub    := tb/net_site.v tb/bitpath.v tb/tb_hub.v
TB_ring   := tb/net_site.v tb/bitpath.v tb/tb_ring.v
TB_erlang := tb/tb_erlang.v
TB_stress := tb/net_site.v tb/tb_stress.v
TB_stats  := tb/tb_stats.v
TB_console := tb/con_site.v tb/bitpath.v tb/tb_console.v

SIMS   := fabric mvp two trunk net chain monitor pool hub ring erlang stress stats console
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
# Icarus is ~100x slower, so the traffic run is offered a tenth of the calls
# there: it checks that the two simulators agree, not the erlang figures.
IVPAR_erlang := -Ptb_erlang.NCALLS=25
# ... and the console's two traffic runs are a tenth as long.
IVPAR_console := -Ptb_console.TRAFFIC_MS=500

IVSIMS := $(addprefix iv-,$(SIMS))
$(IVSIMS): iv-%: $(BUILD)
	@iverilog $(IVFLAG) $(IVPAR_$*) -o $(BUILD)/$*.vvp $(RTL) $(TB_$*) && vvp $(BUILD)/$*.vvp

iv: $(IVSIMS)

# Forty-eight callers thrashing a TWO-register exchange: every caller queueing
# for dial tone, almost nothing completing, and the question is only whether
# anything jams.
stress-overload: $(BUILD)
	@mkdir -p $(BUILD)/vl/stressover
	@verilator $(VLFLAG) -GNREG=2 -GIDLE_LO=100 -GIDLE_HI=800 -GDT_WAIT=600 \
	    --top-module tb_stress --Mdir $(BUILD)/vl/stressover -o tb_stressover \
	    $(RTL) $(TB_stress) > $(BUILD)/vl-stressover.log 2>&1 \
	    || (cat $(BUILD)/vl-stressover.log; false)
	@$(BUILD)/vl/stressover/tb_stressover 2>&1 | grep -v '^- '

# The same stress run over a PAIR of exchanges, calls going both ways and
# the two crystals 100 ppm apart.
stress-pair: $(BUILD)
	@mkdir -p $(BUILD)/vl/stresspair
	@verilator $(VLFLAG) -GPAIR=1 -GPPM=100 --top-module tb_stress \
	    --Mdir $(BUILD)/vl/stresspair -o tb_stresspair $(RTL) $(TB_stress) \
	    > $(BUILD)/vl-stresspair.log 2>&1 || (cat $(BUILD)/vl-stresspair.log; false)
	@$(BUILD)/vl/stresspair/tb_stresspair 2>&1 | grep -v '^- '

# The traffic run with enough calls to measure a 2 % loss, not just check it.
erlang-long: $(BUILD)
	@mkdir -p $(BUILD)/vl/erlangl
	@verilator $(VLFLAG) -GNCALLS=3000 --top-module tb_erlang \
	    --Mdir $(BUILD)/vl/erlangl -o tb_erlangl $(RTL) $(TB_erlang) \
	    > $(BUILD)/vl-erlangl.log 2>&1 || (cat $(BUILD)/vl-erlangl.log; false)
	@$(BUILD)/vl/erlangl/tb_erlangl 2>&1 | grep -v '^- '

# The ring with the strap taken out: the flood goes round and round.
ring-open: $(BUILD)
	@mkdir -p $(BUILD)/vl/ringopen
	@verilator $(VLFLAG) -GSTRAP=0 --top-module tb_ring \
	    --Mdir $(BUILD)/vl/ringopen -o tb_ringopen $(RTL) $(TB_ring) \
	    > $(BUILD)/vl-ringopen.log 2>&1 || (cat $(BUILD)/vl-ringopen.log; false)
	@$(BUILD)/vl/ringopen/tb_ringopen 2>&1 | grep -v '^- '

# The console's CONTROL: /CON as exch-mainboard.md 2.3 first had it -- one '244
# enable, the marker cut off mid-word and not told.  Part 1 only; nothing is
# asserted.  It is there to be read beside `make console`.
console-naive: $(BUILD)
	@mkdir -p $(BUILD)/vl/consolenaive
	@verilator $(VLFLAG) -GNAIVE=1 --top-module tb_console \
	    --Mdir $(BUILD)/vl/consolenaive -o tb_consolenaive $(RTL) $(TB_console) \
	    > $(BUILD)/vl-consolenaive.log 2>&1 || (cat $(BUILD)/vl-consolenaive.log; false)
	@$(BUILD)/vl/consolenaive/tb_consolenaive 2>&1 | grep -v '^- '

# The MF8 link with the two exchanges' crystals 100 ppm apart.
# -G takes a BARE parameter name: -Gtb_trunk.PPM=100 is not found, and with the
# log going to /dev/null this target was silently dead from Verilator 5 on.
trunk-ppm: $(BUILD)
	@mkdir -p $(BUILD)/vl/trunkppm
	@verilator $(VLFLAG) -GPPM=100 --top-module tb_trunk \
	    --Mdir $(BUILD)/vl/trunkppm -o tb_trunkppm $(RTL) $(TB_trunk) \
	    > $(BUILD)/vl-trunkppm.log 2>&1 || (cat $(BUILD)/vl-trunkppm.log; false)
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

.PHONY: all iv $(SIMS) $(IVSIMS) ring-open erlang-long stress-pair stress-overload console-naive trunk-ppm lint synth clean
