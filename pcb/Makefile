# KiCad boards under pcb/, driven by kicad-cli.
#
#   make list            boards found
#   make check           ERC + DRC on every board (make -k to see all failures)
#   make erc-portcard    one board's ERC; also drc-, pdf-, fab-
#   make pdf             schematic PDFs for every board
#   make fab-portcard    gerbers, drill, BOM and a zip for the fab house
#   make models          the 74HC model library's own benches (models/)
#   make netcheck        the block stack's schematics -> Verilog -> newimpl benches
#                        on the boards; BENCH="dial ctl" picks benches
#   make lockstep        the same benches with block.v driving and the boards
#                        compared against it at every mid-cell
#   make place-portcard  first placement from the netlist (overwrites the board)
#   make route-portcard  Freerouting, then a GND pour (needs the jar: tools/route.py)
#   make clean
#
# Every board is a directory holding <name>.kicad_pro; the name is the board.
# Reports and fab files go to out/<name>/, which git ignores.

KICAD ?= kicad-cli
OUT   := out

PROJECTS := $(wildcard */*.kicad_pro */*/*.kicad_pro)
BOARDS   := $(basename $(notdir $(PROJECTS)))

.PHONY: list check erc drc pdf fab clean models netgen netcheck lockstep

# ---- the block stack (exchange/block-stack.md) -------------------------------
BENCH ?= dial ctl debug line

models:
	@$(MAKE) -C models test

netgen:
	@sim/gen.sh

netcheck: netgen
	@python3 sim/run.py $(BENCH)

lockstep: netgen
	@python3 sim/run.py --lockstep $(BENCH)

place-%:
	@sim/gen.sh >/dev/null && python3 tools/pcb.py $*

route-%:
	@python3 tools/route.py $*/$*.kicad_pcb $*/$*.kicad_pcb 30
.DELETE_ON_ERROR:

list:
	@$(foreach p,$(PROJECTS),echo "$(basename $(notdir $(p)))	$(dir $(p))";)

check: erc drc
erc: $(addprefix erc-,$(BOARDS))
drc: $(addprefix drc-,$(BOARDS))
pdf: $(addprefix pdf-,$(BOARDS))
fab: $(addprefix fab-,$(BOARDS))

# $(1) board name, $(2) path without extension
define board
.PHONY: erc-$(1) drc-$(1) pdf-$(1) fab-$(1)

erc-$(1):
	@mkdir -p $(OUT)/$(1)
	@$(KICAD) sch erc --severity-error --severity-warning --exit-code-violations \
		-o $(OUT)/$(1)/erc.rpt $(2).kicad_sch >/dev/null \
		&& echo "ERC $(1): clean" \
		|| { echo "ERC $(1): $$$$(grep -c '^\[' $(OUT)/$(1)/erc.rpt) violations, see $(OUT)/$(1)/erc.rpt"; exit 1; }

drc-$(1):
	@mkdir -p $(OUT)/$(1)
	@$(KICAD) pcb drc --severity-error --severity-warning --exit-code-violations \
		-o $(OUT)/$(1)/drc.rpt $(2).kicad_pcb >/dev/null \
		&& echo "DRC $(1): clean" \
		|| { echo "DRC $(1): $$$$(grep -c '^\[' $(OUT)/$(1)/drc.rpt) violations, see $(OUT)/$(1)/drc.rpt"; exit 1; }

pdf-$(1):
	@mkdir -p $(OUT)/$(1)
	$(KICAD) sch export pdf -o $(OUT)/$(1)/$(1)-sch.pdf $(2).kicad_sch

fab-$(1):
	@rm -rf $(OUT)/$(1)/fab && mkdir -p $(OUT)/$(1)/fab
	$(KICAD) pcb export gerbers --board-plot-params -o $(OUT)/$(1)/fab/ $(2).kicad_pcb
	$(KICAD) pcb export drill --generate-map -o $(OUT)/$(1)/fab/ $(2).kicad_pcb
	$(KICAD) sch export bom -o $(OUT)/$(1)/$(1)-bom.csv $(2).kicad_sch
	cd $(OUT)/$(1) && rm -f $(1)-fab.zip && zip -qj $(1)-fab.zip fab/*
	@echo "fab $(1): $(OUT)/$(1)/$(1)-fab.zip"
endef

$(foreach p,$(PROJECTS),$(eval $(call board,$(basename $(notdir $(p))),$(basename $(p)))))

clean:
	rm -rf $(OUT)
