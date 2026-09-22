# CVSD decoder A — ngspice
# Loopback: enc_a → dec_a → recon

NGSPICE ?= ngspice
OUT := out

.PHONY: all loop check clean

all: loop check

$(OUT):
	mkdir -p $(OUT)

loop: $(OUT)
	$(NGSPICE) -b test_loop.cir 2>&1 | tee $(OUT)/loop.log

check:
	python3 check.py

clean:
	rm -rf $(OUT)
