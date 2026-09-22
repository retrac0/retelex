# Breadboard CVSD encoder — ngspice
# A: LM311 + TL072 + LM13700 (baseline)
# B: TL072 comparator (no LM311)
# C: discrete ±Iabc steer (no LM13700)
# D: as A, but LM358 for Iabc + follower
#
# Each variant is simulated alone (shared Boyle decks fight in one .cir).

NGSPICE ?= ngspice
OUT := out

.PHONY: all compare check clean a b c d

all: compare check

$(OUT):
	mkdir -p $(OUT)

a b c d: $(OUT)
	$(NGSPICE) -b test_$@_solo.cir 2>&1 | tee $(OUT)/$@.log

compare: a b c d

check:
	python3 check.py

clean:
	rm -rf $(OUT)
