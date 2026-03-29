# Makefile for 32-bit ALU
# Author: CPU Designers
# Date: 2026-03-28

# Compiler and simulator
CC = iverilog
SIM = vvp
WAVE = gtkwave

# Directories
RTL_DIR = rtl
TB_DIR = tb
DOC_DIR = docs
WAVE_DIR = waves

# Output
OUTPUT = alu_tb
WAVE_FILE = alu_wave.vcd

# Compiler flags
CFLAGS = -Wall

# RTL files
RTL_FILES = $(RTL_DIR)/basic_gates.v \
            $(RTL_DIR)/mux.v \
            $(RTL_DIR)/cla_adder_4bit.v \
            $(RTL_DIR)/cla_adder_16bit.v \
            $(RTL_DIR)/cla_adder_32bit.v \
            $(RTL_DIR)/subtractor.v \
            $(RTL_DIR)/shifter.v \
            $(RTL_DIR)/logic_unit.v \
            $(RTL_DIR)/lui.v \
            $(RTL_DIR)/booth_multiplier.v \
            $(RTL_DIR)/non_restoring_divider.v \
            $(RTL_DIR)/alu_result_selector.v \
            $(RTL_DIR)/alu_32bit.v

# Testbench files
TB_FILES = $(TB_DIR)/tb_alu_32bit.v

# All source files
ALL_FILES = $(RTL_FILES) $(TB_FILES)

# Default target
.PHONY: all
all: info test

# Display information
.PHONY: info
info:
	@echo "========================================"
	@echo "32-bit ALU Test Suite"
	@echo "========================================"
	@echo ""

# Compile only
.PHONY: compile
compile:
	@echo "Compiling ALU..."
	$(CC) $(CFLAGS) -o $(OUTPUT) $(ALL_FILES)
	@echo "✓ Compilation complete."

# Run test (without recompiling)
.PHONY: run
run:
	@echo "Running tests..."
	$(SIM) $(OUTPUT)

# Compile and test
.PHONY: test
test: compile run

# Generate waveform
.PHONY: wave
wave: CFLAGS += -DGENERATE_WAVE
wave: compile
	@echo "Generating waveform..."
	@mkdir -p $(WAVE_DIR)
	$(SIM) $(OUTPUT)
	@echo "✓ Waveform generated: $(WAVE_DIR)/$(WAVE_FILE)"
	@echo "View with: $(WAVE) $(WAVE_DIR)/$(WAVE_FILE)"

# View waveform
.PHONY: view
view:
	@if [ ! -f $(WAVE_DIR)/$(WAVE_FILE) ]; then \
		echo "Error: Wave file not found. Run 'make wave' first."; \
		exit 1; \
	fi
	$(WAVE) $(WAVE_DIR)/$(WAVE_FILE) &

# Syntax check
.PHONY: check
check:
	@echo "Checking syntax..."
	@for file in $(RTL_FILES); do \
		echo "Checking $$file..."; \
		$(CC) -t null -o /dev/null $$file 2>&1 | grep -v "module" || true; \
	done
	@echo "✓ Syntax check complete."

# Lint check (using iverilog warnings)
.PHONY: lint
lint:
	@echo "Running lint check..."
	$(CC) -Wall -t null -o /dev/null $(ALL_FILES) 2>&1
	@echo "✓ Lint check complete."

# Clean generated files
.PHONY: clean
clean:
	@echo "Cleaning generated files..."
	rm -f $(OUTPUT)
	rm -f $(TB_DIR)/*.vcd
	rm -f *.vcd
	rm -rf $(WAVE_DIR)
	rm -f tb/mul_* tb/div_* tb/*_test tb/*_debug
	@echo "✓ Clean complete."

# Deep clean (including backup files)
.PHONY: distclean
distclean: clean
	@echo "Deep cleaning..."
	rm -f *~ */*~
	rm -f *.bak */*.bak
	@echo "✓ Deep clean complete."

# List all source files
.PHONY: list
list:
	@echo "RTL files:"
	@for file in $(RTL_FILES); do echo "  $$file"; done
	@echo ""
	@echo "Testbench files:"
	@for file in $(TB_FILES); do echo "  $$file"; done

# Count lines of code
.PHONY: count
count:
	@echo "Lines of code:"
	@echo "  RTL:      $$(wc -l $(RTL_FILES) | tail -1 | awk '{print $$1}')"
	@echo "  Testbench: $$(wc -l $(TB_FILES) | tail -1 | awk '{print $$1}')"
	@echo "  Total:    $$(wc -l $(ALL_FILES) | tail -1 | awk '{print $$1}')"

# Generate documentation
.PHONY: docs
docs:
	@echo "Generating documentation..."
	@if command -v doxygen >/dev/null 2>&1; then \
		doxygen Doxyfile 2>/dev/null || echo "Doxygen not configured"; \
	else \
		echo "Doxygen not installed. Skipping API documentation."; \
	fi
	@echo "✓ Documentation in $(DOC_DIR)/"

# Run all checks
.PHONY: check-all
check-all: check lint test
	@echo ""
	@echo "========================================"
	@echo "All checks passed!"
	@echo "========================================"

# Help
.PHONY: help
help:
	@echo "32-bit ALU Makefile"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  all        - Display info and run tests (default)"
	@echo "  compile    - Compile all modules"
	@echo "  run        - Run tests (without recompiling)"
	@echo "  test       - Compile and run tests"
	@echo "  wave       - Generate waveform file"
	@echo "  view       - View waveform with GTKWave"
	@echo "  check      - Syntax check"
	@echo "  lint       - Lint check"
	@echo "  clean      - Remove generated files"
	@echo "  distclean  - Deep clean (including backups)"
	@echo "  list       - List all source files"
	@echo "  count      - Count lines of code"
	@echo "  docs       - Generate documentation"
	@echo "  check-all  - Run all checks (syntax, lint, test)"
	@echo "  help       - Show this help message"
	@echo ""
	@echo "Examples:"
	@echo "  make test        # Run all tests"
	@echo "  make wave        # Generate waveform"
	@echo "  make check-all   # Run all checks"

# Show test summary
.PHONY: summary
summary: test
	@echo ""
	@echo "Test summary has been displayed above."

# Debug target - compile with debug info
.PHONY: debug
debug: CFLAGS += -DDEBUG
debug: clean compile
	@echo "✓ Debug build complete."