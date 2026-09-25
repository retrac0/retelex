SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c

# newimpl -- the exchange in Verilog, rebuilt around the folded A plane.
#
# The test sequence is Verilator: `make` runs every bench, then `make lint`
# and `make faults`.  Icarus is retired from it (2026-09-25): too slow for the
# network benches -- tb_net ran over an hour under it without finishing.  The
# RTL stays in the language both accept (STYLE.md 5), so `make iv-<bench>`
# still runs one bench under Icarus, by hand.
#
# There is no chip library and no BOM flow here.  A '151 is an assign under a
# comment that says so.

RTL := rtl/clock_card.v rtl/frame_decode.v rtl/port.v rtl/block.v rtl/mainboard.v rtl/exch.v \
       rtl/ctl_write.v rtl/word_rx.v rtl/ctl_queue.v \
       rtl/probe.v rtl/pulse_rx.v rtl/pulse_reg.v \
       rtl/mini_marker.v rtl/top_min.v rtl/debugger.v \
       rtl/dm_rx.v rtl/cvsd_line_card.v rtl/baseband_card.v rtl/local_trunk.v \
       rtl/net_unit.v rtl/top_net.v

BUILD := build

TB_clock  := tb/tb_clock.v
TB_fabric := tb/tb_fabric.v
TB_ctl    := tb/tb_ctl.v
TB_ha     := tb/tb_ha.v
TB_probe  := tb/tb_probe.v
TB_dial   := tb/tb_dial.v
TB_mini   := tb/tb_mini.v
TB_debug  := tb/tb_debug.v
TB_line   := tb/subscriber.v tb/tb_line.v
TB_word   := tb/tb_word.v
TB_tie    := tb/tb_tie.v
TB_ltu    := tb/tb_ltu.v
TB_lnet   := tb/site_net.v tb/tb_lnet.v
TB_net    := tb/site_net.v tb/tb_net.v
TB_chain  := tb/site_net.v tb/tb_chain.v
TB_lfull  := tb/site_net.v tb/tb_lfull.v
TB_lchain := tb/site_net.v tb/tb_lchain.v

SIMS   := clock fabric ctl ha probe dial mini debug line word tie ltu net chain lnet lfull lchain
IVSIMS := $(addprefix iv-,$(SIMS))    # by hand only: not in the sequence

IVFLAG := -g2012 -I rtl
VLTHREADS ?= 4
VLFLAG := --binary --timing -j 4 --threads $(VLTHREADS) -Irtl -Wno-fatal

.PHONY: all lint clean faults $(SIMS) $(IVSIMS)

all: $(SIMS)

$(BUILD):
	@mkdir -p $(BUILD)

# Verilator: the working simulator.
$(SIMS): %: | $(BUILD)
	@mkdir -p $(BUILD)/vl/$*
	@verilator $(VLFLAG) --top-module tb_$* --Mdir $(BUILD)/vl/$* -o tb_$* \
	    $(RTL) $(TB_$*) > $(BUILD)/vl-$*.log 2>&1 || (cat $(BUILD)/vl-$*.log; false)
	@$(BUILD)/vl/$*/tb_$*

# Icarus: one bench at a time, by hand.  There is no `make iv`: every bench
# under Icarus is hours, and it is not part of the test sequence.
# A static pattern rule, not a bare pattern rule: make does not search
# implicit rules for a target declared .PHONY.
$(IVSIMS): iv-%: | $(BUILD)
	@iverilog $(IVFLAG) -o $(BUILD)/$*.vvp $(RTL) $(TB_$*)
	@vvp $(BUILD)/$*.vvp

# Every module lints on its own, with -Wall and nothing waived.
#
# THE STATUS MUST SURVIVE THE LOOP.  `verilator ... && echo` puts the compiler
# on the left of an &&, which `set -e` does not abort on, and a for loop exits
# with the status of its LAST iteration -- so the old form could only ever fail
# on top_min, the eleventh of eleven, and a warning introduced in port, probe,
# pulse_rx or mini_marker passed silently.  Collect the failures instead.
lint:
	@fail=0; \
	for m in clock_card frame_decode port block mainboard exch ctl_write word_rx ctl_queue probe \
	         pulse_rx pulse_reg mini_marker top_min debugger \
	         dm_rx cvsd_line_card baseband_card local_trunk net_unit top_net; do \
	    if verilator --lint-only -Wall -Irtl --top-module $$m $(RTL); then \
	        echo "  $$m  clean"; \
	    else \
	        echo "  $$m  FAILED"; fail=1; \
	    fi; \
	done; \
	exit $$fail

# Every check that guards a rule is shown able to fail: each fault in
# faults.py is put back into a copy of the tree, and must turn its bench red.
faults: | $(BUILD)
	@python3 faults.py

clean:
	@rm -rf $(BUILD)
