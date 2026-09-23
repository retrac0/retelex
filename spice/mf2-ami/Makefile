# MF2 AMI PHY — ngspice (74HC encode/decode + HV-tolerant line)
NGSPICE ?= ngspice
OUT := out

.PHONY: all loop surge check clean

all: loop surge check

$(OUT):
	mkdir -p $(OUT)

loop: $(OUT)
	$(NGSPICE) -b test_loop.cir 2>&1 | tee $(OUT)/loop.log

surge: $(OUT)
	$(NGSPICE) -b test_50v.cir 2>&1 | tee $(OUT)/surge.log

check:
	python3 check.py

clean:
	rm -rf $(OUT)
