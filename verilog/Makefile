SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c

# verilog -- the exchange in Verilog.
#
# Two simulators run the same testbenches.  Icarus is the reference; Verilator
# is about two orders of magnitude faster and is what to use while working --
# the network testbench is 3 s of model time, which is minutes under Icarus and
# 22 s under Verilator.  Anything that passes under one must pass under the other.
RTL   := rtl/mux8.v rtl/hc259.v rtl/ctl_write.v rtl/stats.v rtl/console.v rtl/pulse_rx.v rtl/pulse_reg.v rtl/monitor.v rtl/marker.v \
         rtl/source_card.v rtl/tone_card.v rtl/port.v rtl/block.v rtl/clock_card.v rtl/mainboard.v \
         rtl/line_card.v rtl/pulse_gen.v rtl/mf8_encoder.v rtl/mf8_decoder.v rtl/mf8_framer.v \
         rtl/mf8_trunk_card.v rtl/exch_top.v \
         rtl/lamp_card.v rtl/common_card.v rtl/hb_panel.v
BUILD := build

TB_fabric := tb/tb_fabric.v
TB_mvp    := tb/tb_mvp.v
TB_two    := tb/mvp_site.v tb/tb_two.v
TB_trunk  := tb/trunk_site.v tb/bitpath.v tb/tb_trunk.v
TB_net    := tb/net_site.v tb/bitpath.v tb/tb_net.v
TB_chain  := tb/net_site.v tb/bitpath.v tb/line_delay.v tb/tb_chain.v
TB_monitor := tb/tb_monitor.v
TB_pool   := tb/net_site.v tb/bitpath.v tb/tb_pool.v
TB_hub    := tb/net_site.v tb/bitpath.v tb/tb_hub.v
TB_ring   := tb/net_site.v tb/bitpath.v tb/tb_ring.v
TB_erlang := tb/tb_erlang.v
TB_stress := tb/net_site.v tb/tb_stress.v
TB_traffic := tb/net_site.v tb/tb_traffic.v
TB_stats  := tb/tb_stats.v
TB_console := tb/con_site.v tb/bitpath.v tb/tb_console.v
TB_panel  := tb/tb_panel.v
TB_tone   := tb/tb_tone.v
TB_tonex  := tb/tb_tonex.v
TB_sclk   := tb/tb_sclk.v
TB_priority := tb/net_site.v tb/tb_priority.v
TB_word   := tb/net_site.v tb/tb_word.v
TB_groups := tb/net_site.v tb/tb_groups.v
TB_pulse_gen := tb/net_site.v tb/tb_pulse_gen.v

SIMS   := fabric mvp two trunk net chain monitor pool hub ring erlang stress stats console traffic panel tone tonex sclk priority word groups pulse_gen
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

# `traffic` is not in `make iv`.  It is a network under load for seconds of model
# time, which is minutes under Verilator and hours under Icarus; `make iv-traffic`
# still works for anyone with the afternoon.  Everything it exercises -- the
# fabric, the marker, the pools, the links -- is under Icarus in the benches above.
IVSIMS := $(addprefix iv-,$(filter-out traffic,$(SIMS)))
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

# marker.md §6's register-pool axis: the same 48-line exchange and the same
# fixed load, swept over NREG = 1, 2, 3.  Reports dial-tone wait mean / delayed
# / >3 s for each pool size.
regs: $(BUILD)
	@for n in 1 2 3; do \
	    mkdir -p $(BUILD)/vl/regs$$n; \
	    verilator $(VLFLAG) -GNREG=$$n -GREGS_RPT=1 \
	        -GIDLE_LO=400 -GIDLE_HI=1200 -GDT_WAIT=2000 \
	        -GROUNDS=3 -GBURST=4000 \
	        --top-module tb_stress --Mdir $(BUILD)/vl/regs$$n -o tb_regs$$n \
	        $(RTL) $(TB_stress) > $(BUILD)/vl-regs$$n.log 2>&1 \
	        || (cat $(BUILD)/vl-regs$$n.log; false); \
	    echo ""; echo "======== NREG=$$n ========"; \
	    $(BUILD)/vl/regs$$n/tb_regs$$n 2>&1 | grep -v '^- '; \
	done

# Hub scenario 4 alone: two seizures inside one forwarder sweep.
hub-fwd: $(BUILD)
	@mkdir -p $(BUILD)/vl/hubfwd
	@verilator $(VLFLAG) -GONLY=4 --top-module tb_hub \
	    --Mdir $(BUILD)/vl/hubfwd -o tb_hubfwd $(RTL) $(TB_hub) \
	    > $(BUILD)/vl-hubfwd.log 2>&1 || (cat $(BUILD)/vl-hubfwd.log; false)
	@$(BUILD)/vl/hubfwd/tb_hubfwd 2>&1 | grep -v '^- '

# Hub scenario 5: abandoned flood -- fan-out legs must clear (traffic.md leak).
hub-leak: $(BUILD)
	@mkdir -p $(BUILD)/vl/hubleak
	@verilator $(VLFLAG) -GONLY=5 --top-module tb_hub \
	    --Mdir $(BUILD)/vl/hubleak -o tb_hubleak $(RTL) $(TB_hub) \
	    > $(BUILD)/vl-hubleak.log 2>&1 || (cat $(BUILD)/vl-hubleak.log; false)
	@$(BUILD)/vl/hubleak/tb_hubleak 2>&1 | grep -v '^- '

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

# ---- the traffic runs --------------------------------------------------
# EVERYTHING ABOUT THE DEMAND IS A PLUSARG, so the network is compiled once and
# run for every traffic model.  Eight exchanges take a quarter of an hour to
# verilate and compile -- the exchange's combinational cone is one C function an
# exchange and g++ is superlinear in it -- which is what --output-split is for.
# `make traffic` itself is the small regression: a hub and two spokes.
VLSPLIT     := --output-split 6000 --output-split-cfuncs 800
TRAFFIC_NET := -GNHUB=2 -GSPOKE=3 -GSLEN=1 -GNLINE=12
TRAFFIC_DEEP := -GNHUB=2 -GSPOKE=2 -GSLEN=2 -GNLINE=12
# The warm-up is twice the longer idle: a phase starts with every line on hook,
# which is not a state a network is ever in, and a line that has not lifted yet is
# a first lift still to come whatever the rate is meant to be.
# A plusarg is taken from its FIRST match, so no argument may appear twice here.
TRAFFIC_ARG  := +warm=6000 +secs=10 +op=3000 +pk=1500
TRAFFIC_ONE  := +warm=3000 +secs=8 +op=1500 +pk=1500 +phases=1 +seed=87654321
TRAFFIC_DARG := +warm=6000 +secs=8 +op=3000 +pk=1500
NETBIN  := $(BUILD)/vl/trafficnet/tb_trafficnet
DEEPBIN := $(BUILD)/vl/trafficdeep/tb_trafficdeep

$(NETBIN): $(RTL) $(TB_traffic)
	@mkdir -p $(BUILD)/vl/trafficnet
	@verilator $(VLFLAG) $(VLSPLIT) $(TRAFFIC_NET) --top-module tb_traffic \
	    --Mdir $(BUILD)/vl/trafficnet -o tb_trafficnet $(RTL) $(TB_traffic) \
	    > $(BUILD)/vl-trafficnet.log 2>&1 || (cat $(BUILD)/vl-trafficnet.log; false)

$(DEEPBIN): $(RTL) $(TB_traffic)
	@mkdir -p $(BUILD)/vl/trafficdeep
	@verilator $(VLFLAG) $(VLSPLIT) $(TRAFFIC_DEEP) --top-module tb_traffic \
	    --Mdir $(BUILD)/vl/trafficdeep -o tb_trafficdeep $(RTL) $(TB_traffic) \
	    > $(BUILD)/vl-trafficdeep.log 2>&1 || (cat $(BUILD)/vl-trafficdeep.log; false)

# Eight exchanges, two hubs with three leaves each, off peak and then peak.
# ~90 minutes.  `exch.py traffic` 1 is the same network on the same clock.
traffic-net: $(NETBIN)
	@$(NETBIN) $(TRAFFIC_ARG) +model=0 +phases=2 +seed=305419896 2>&1 | grep -v '^- '

# The same network at peak only, once for each arrival process and each
# holding-time law.  Five runs of ~45 minutes; run them at once if you have the
# cores, because each one is a single thread.
traffic-models: $(NETBIN)
	@for a in "+model=0" "+model=1" "+model=2" "+holdm=1" "+holdm=2"; do \
	    $(NETBIN) $(TRAFFIC_ONE) $$a 2>&1 | grep -v '^- '; \
	done

# Ten exchanges: the same two hubs, but the spokes are two deep.  A transit on
# every spoke, and the link next the hub carries the whole spoke past it.
traffic-deep: $(DEEPBIN)
	@$(DEEPBIN) $(TRAFFIC_DARG) +model=0 +phases=2 +seed=305419896 2>&1 | grep -v '^- '

# The same chain with 20 ms of carrier on every link -- 160 ms in the world, because
# this bench dials eight times fast.  C.s monitor is patched in 40 ms after the origin
# seized, against a 16 ms guard -- two and a half times over it -- and the call
# still goes through: the seizure and the pulses are the same wire (5.1).
chain-delay: $(BUILD)
	@mkdir -p $(BUILD)/vl/chaindelay
	@verilator $(VLFLAG) -GDLY=20 --top-module tb_chain \
	    --Mdir $(BUILD)/vl/chaindelay -o tb_chaindelay $(RTL) $(TB_chain) \
	    > $(BUILD)/vl-chaindelay.log 2>&1 || (cat $(BUILD)/vl-chaindelay.log; false)
	@$(BUILD)/vl/chaindelay/tb_chaindelay 2>&1 | grep -v '^- '

# The ring with the strap taken out: the flood goes round and round.
ring-open: $(BUILD)
	@mkdir -p $(BUILD)/vl/ringopen
	@verilator $(VLFLAG) -GSTRAP=0 --top-module tb_ring \
	    --Mdir $(BUILD)/vl/ringopen -o tb_ringopen $(RTL) $(TB_ring) \
	    > $(BUILD)/vl-ringopen.log 2>&1 || (cat $(BUILD)/vl-ringopen.log; false)
	@$(BUILD)/vl/ringopen/tb_ringopen 2>&1 | grep -v '^- '

# The console's CONTROL: /CON as mainboard.md 2.3 first had it -- one '244
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

.PHONY: all iv $(SIMS) $(IVSIMS) chain-delay ring-open erlang-long stress-pair stress-overload console-naive trunk-ppm traffic-net traffic-models traffic-deep hub-fwd hub-leak regs lint synth clean pulse-gen iv-pulse-gen
pulse-gen: pulse_gen
iv-pulse-gen: iv-pulse_gen
