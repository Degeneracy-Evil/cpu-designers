AS = riscv64-unknown-elf-as
LD = riscv64-unknown-elf-ld
OBJCOPY = riscv64-unknown-elf-objcopy
ARCH = rv32im_zicsr
ABI = ilp32

# Test programs (CPU verification)
TEST_PROGS = cpu_test cpu_test_compute cpu_test_trap cpu_test_fencei \
             cpu_test_access_fault cpu_test_priv cpu_test_mmu

# Application programs (FPGA demos)
APP_PROGS = led_marquee uart_hello

# All programs
PROGS = $(TEST_PROGS:%=test/%) $(APP_PROGS:%=app/%)

all: $(PROGS:%=%.hex)

# Generic pattern rules for subdirectory builds
test/%.o: test/%.s
	$(AS) -march=$(ARCH) -mabi=$(ABI) -o $@ $<

app/%.o: app/%.s
	$(AS) -march=$(ARCH) -mabi=$(ABI) -o $@ $<

test/%.elf: test/%.o link.ld
	$(LD) -m elf32lriscv -T link.ld -o $@ $<

app/%.elf: app/%.o link.ld
	$(LD) -m elf32lriscv -T link.ld -o $@ $<

test/%.verilog.hex: test/%.elf
	$(OBJCOPY) -O verilog $< $@

app/%.verilog.hex: app/%.elf
	$(OBJCOPY) -O verilog $< $@

test/%.hex: test/%.verilog.hex
	python3 verilog_to_words.py $< $@

app/%.hex: app/%.verilog.hex
	python3 verilog_to_words.py $< $@

clean:
	rm -f test/*.o test/*.elf test/*.verilog.hex
	rm -f app/*.o app/*.elf app/*.verilog.hex

.PHONY: all clean
