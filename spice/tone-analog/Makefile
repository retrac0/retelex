# Analog tone front-end — ngspice
# tone-plan.md §5: carrier + LFO, pure / soft / hard, cadence mute → AUDIO
#
# Does not include the CVSD encoder (see ../cvsd-enc/).

NGSPICE ?= ngspice
OUT := out

.PHONY: all pure soft hard cadence rbt rbt-spice check clean

all: pure soft hard cadence check

$(OUT):
	mkdir -p $(OUT)

pure soft hard cadence rbt: $(OUT)
	$(NGSPICE) -b test_$@.cir 2>&1 | tee $(OUT)/$@.log

# 10 s ringback WAV: soft warble + §5.2 double-pulse cadence (≥2 periods)
rbt-spice: rbt
	python3 render_rbt.py

check:
	python3 check.py

clean:
	rm -rf $(OUT)
