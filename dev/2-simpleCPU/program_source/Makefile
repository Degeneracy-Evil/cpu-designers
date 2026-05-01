AS = riscv64-unknown-elf-as
LD = riscv64-unknown-elf-ld
OBJCOPY = riscv64-unknown-elf-objcopy
ARCH = rv32i_zicsr
ABI = ilp32

PROGS = comprehensive_test csr_test align_test timer_irq_test timer_seconds icache_init

all: $(PROGS:%=%.hex)

%.o: %.s
	$(AS) -march=$(ARCH) -mabi=$(ABI) -o $@ $<

%.elf: %.o link.ld
	$(LD) -m elf32lriscv -T link.ld -o $@ $<

%.verilog.hex: %.elf
	$(OBJCOPY) -O verilog $< $@

%.hex: %.verilog.hex
	python3 verilog_to_words.py $< $@

clean:
	rm -f *.o *.elf *.verilog.hex *.hex

.PHONY: all clean
