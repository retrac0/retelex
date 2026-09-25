# The local highway trunk's wire (exchange/local-trunk.md 5) -- ngspice
NGSPICE ?= ngspice
OUT := out

.PHONY: all cable check clean

all: cable check

$(OUT):
	mkdir -p $(OUT)

cable: $(OUT)
	$(NGSPICE) -b test_cable.cir > $(OUT)/cable.log 2>&1

check:
	python3 check.py | tee $(OUT)/check.log

clean:
	rm -rf $(OUT)
