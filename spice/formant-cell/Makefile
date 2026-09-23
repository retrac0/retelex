# One-channel OTA log–antilog voice cell — ngspice
# SPEC.md: enc (logenv + AM @ 800 Hz) ↔ dec (logenv + AM @ 1 kHz)

NGSPICE ?= ngspice
OUT := out

.PHONY: all tone loop check wav speech clean

all: tone loop check

$(OUT):
	mkdir -p $(OUT)

tone loop: $(OUT)
	$(NGSPICE) -b test_$@.cir 2>&1 | tee $(OUT)/$@.log

check:
	python3 check.py

wav: loop
	python3 render.py

# Behavioral twin — residual-excited talkers (sim/formant_cell.py)
speech:
	python3 ../../sim/formant_cell.py --mode residual --out $(CURDIR)/$(OUT)/talkers

clean:
	rm -rf $(OUT)
