SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c

# newimpl -- the exchange in Verilog, rebuilt around the folded A plane.
#
# Two simulators run the same testbenches.  Verilator is what to use while
# working; Icarus is the reference.  Anything that passes under one must pass
# under the other.
#
# There is no chip library and no BOM flow here.  A '151 is an assign under a
# comment that says so.

RTL := rtl/clock_card.v rtl/port.v rtl/block.v rtl/mainboard.v rtl/exch.v \
       rtl/ctl_write.v rtl/probe.v rtl/pulse_rx.v rtl/pulse_reg.v \
       rtl/mini_marker.v rtl/top_min.v rtl/debugger.v \
       rtl/dm_rx.v rtl/cvsd_line_card.v

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

SIMS   := clock fabric ctl ha probe dial mini debug line
IVSIMS := $(addprefix iv-,$(SIMS))

IVFLAG := -g2012 -I rtl
VLFLAG := --binary --timing -j 4 -Irtl -Wno-fatal

.PHONY: all lint clean $(SIMS) $(IVSIMS) iv

all: $(SIMS)

$(BUILD):
	@mkdir -p $(BUILD)

# Verilator: the working simulator.
$(SIMS): %: | $(BUILD)
	@mkdir -p $(BUILD)/vl/$*
	@verilator $(VLFLAG) --top-module tb_$* --Mdir $(BUILD)/vl/$* -o tb_$* \
	    $(RTL) $(TB_$*) > $(BUILD)/vl-$*.log 2>&1 || (cat $(BUILD)/vl-$*.log; false)
	@$(BUILD)/vl/$*/tb_$*

# Icarus: the reference.
iv: $(IVSIMS)

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
	for m in clock_card port block mainboard exch ctl_write probe \
	         pulse_rx pulse_reg mini_marker top_min debugger \
	         dm_rx cvsd_line_card; do \
	    if verilator --lint-only -Wall -Irtl --top-module $$m $(RTL); then \
	        echo "  $$m  clean"; \
	    else \
	        echo "  $$m  FAILED"; fail=1; \
	    fi; \
	done; \
	exit $$fail

clean:
	@rm -rf $(BUILD)
