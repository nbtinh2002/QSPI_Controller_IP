#----------------------------------------------------------------
# Makefile đơn giản hóa cho mô phỏng Verilog với Icarus + GTKWave
#----------------------------------------------------------------

# Top-level
TOP ?= qspi_tx_fifo
TOP_TB	?= tb_$(TOP)

# Folder
RTL_DIR    := ./RTL

# Output
VCD        := $(TOP_TB).vcd
BIN        := simv.out

# Sources
RTL_SRCS   := $(filter-out $(RTL_DIR)/$(TOP_TB).v, $(wildcard $(RTL_DIR)/*.v))

# Command
IVERILOG   := iverilog
VVP        := vvp
GTKWAVE    := gtkwave

all: clean compile run wave

compile:
	@echo "[Compile] Compiling ..."
	$(IVERILOG) -o $(BIN) -g2012 -I$(RTL_DIR) -s $(TOP_TB) $(RTL_SRCS) $(RTL_DIR)/$(TOP_TB).v

run: compile
	@echo "[Run] Running simulation..."
	$(VVP) $(BIN)


wave: run
	@echo "[Waveform] Launching GTKWave..."
	GTK_DEBUG=none $(GTKWAVE) $(VCD) > /dev/null 2>&1 &


clean:
	@echo "[Clean] Cleaning up..."
	rm -rf *.vcd *.out $(BIN) 

.PHONY: clean compile run wave
