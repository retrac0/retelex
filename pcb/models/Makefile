# pcb/models -- the 74HC parts as the netlist check sees them.  NOT the hand RTL.
#
#   make test     the pin tables against the KiCad symbols, then every part
#                 bench under Verilator and Icarus, inertial and transport
#   make clean
#
# Every simulation runs under ../tools/capped: its own cgroup and a memory
# ceiling, so a runaway is killed alone.  Builds go to ../out/models (ignored).

SHELL  := /bin/bash
.SHELLFLAGS := -euo pipefail -c

OUT    := ../out/models
CAP    := ../tools/capped
export TMPDIR := /home/joel/telco/newimpl/build/tmp

BENCH  := tb_parts tb_dly
VL     := verilator --binary --timing -j 2 -Wno-fatal
IV     := iverilog -g2012

.PHONY: test pins $(BENCH) clean

test: pins $(BENCH)

pins:
	@python3 tb/pins.py check | tail -1

$(BENCH): %:
	@mkdir -p $(OUT) $(TMPDIR)
	@for mode in inertial transport; do \
	    if [ $$mode = transport ]; then vd=+define+HC_TRANSPORT; id=-DHC_TRANSPORT; n=$*_tr; \
	    else vd=; id=; n=$*; fi; \
	    $(CAP) $(VL) $$vd --top-module $* --Mdir $(OUT)/$$n -o $* 74hc.v tb/$*.v \
	        > $(OUT)/$$n.log 2>&1 || { cat $(OUT)/$$n.log; exit 1; }; \
	    printf '  %-12s verilator %-9s ' $* $$mode; $(CAP) $(OUT)/$$n/$* | grep -E 'checks'; \
	    $(IV) $$id -o $(OUT)/$$n.vvp 74hc.v tb/$*.v; \
	    printf '  %-12s icarus    %-9s ' $* $$mode; $(CAP) vvp $(OUT)/$$n.vvp | grep -E 'checks'; \
	done

clean:
	rm -rf $(OUT)
