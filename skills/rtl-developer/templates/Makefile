IVERILOG  ?= iverilog
VERILATOR ?= verilator

TOP ?= fifo_sync
TB  ?= $(TOP)_tb
SIM ?= simv
DEPS ?= dff.sv dffr.sv

.PHONY: all lint sim sva clean
all: lint sim

lint:
	$(VERILATOR) --lint-only -Wall --top-module $(TOP) $(TOP).sv

sim:
	$(IVERILOG) -g2012 -o $(SIM) $(TOP).sv $(DEPS) $(TB).sv
	vvp $(SIM)

sva:
	$(VERILATOR) --binary --timing --assert -DSVA_ON -Wno-TIMESCALEMOD \
		--top-module $(TB) $(TOP).sv $(DEPS) $(TB).sv -o $(SIM)_sva
	./obj_dir/$(SIM)_sva

clean:
	rm -f $(SIM) $(SIM)_sva
	rm -rf obj_dir
