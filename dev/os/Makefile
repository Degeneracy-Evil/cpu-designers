# ============================================================
# Makefile — SimpleOS two-stage build
#
# Stage 1 (user):  compile user sources → user.elf → user.bin
# Stage 2 (kernel): embed user.bin via .incbin → os.elf → os.hex
#
# The resulting os.hex is in $readmemh format (one 8-hex-char word
# per line, little-endian) — matches axi_wrap_ram.sv's
# $readmemh("prog.hex", BRAM) and axi4lite_bootrom.sv's
# $readmemh("bootloader.hex", mem).
#
# Toolchain: riscv64-unknown-elf-* (riscv32 not installed; the
# -march=rv32imaf_zicsr_zifencei -mabi=ilp32 flags produce RV32
# elf32-littleriscv objects equivalent to a native riscv32 build).
# ============================================================

# ---- Toolchain ----
CC      = riscv64-unknown-elf-gcc
OBJCOPY = riscv64-unknown-elf-objcopy
OBJDUMP = riscv64-unknown-elf-objdump

# ---- Build flags ----
CFLAGS  = -march=rv32imaf_zicsr_zifencei -mabi=ilp32 \
          -ffreestanding -nostdlib -fno-builtin -Wall -Wextra \
          -I$(INCLUDE_DIR) -I$(USER_DIR) -I$(KERNEL_DIR)
ASFLAGS = -march=rv32imaf_zicsr_zifencei -mabi=ilp32 \
          -ffreestanding -nostdlib -Wall
LDFLAGS = -march=rv32imaf_zicsr_zifencei -mabi=ilp32 \
          -ffreestanding -nostdlib -Wl,--no-relax -Wl,--build-id=none

# ---- Directories ----
INCLUDE_DIR = include
USER_DIR    = user
KERNEL_DIR  = kernel
BUILD_DIR   = build

# ---- Source files ----
USER_SRCS_C   = user/user_printf.c user/user_gets.c user/calculator.c \
                user/atof.c user/ftoa.c user/math.c
USER_SRCS_S   = user/user_start.S user/user_syscall.S
USER_SRCS     = $(USER_SRCS_S) $(USER_SRCS_C)

KERNEL_SRCS_S = kernel/entry.S kernel/trap.S
KERNEL_SRCS_C = kernel/m_init.c kernel/s_main.c kernel/trap.c \
                kernel/syscall.c kernel/uart.c
KERNEL_SRCS   = $(KERNEL_SRCS_S) $(KERNEL_SRCS_C)

# ---- Object files ----
# .S and .c files with the same basename (e.g. trap.S + trap.c) would
# collide if mapped to the same .o path. Use .S.o / .c.o suffixes to
# keep them distinct.
USER_OBJS   = $(patsubst %.S,$(BUILD_DIR)/%.S.o,$(patsubst %.c,$(BUILD_DIR)/%.c.o,$(USER_SRCS)))
KERNEL_OBJS = $(patsubst %.S,$(BUILD_DIR)/%.S.o,$(patsubst %.c,$(BUILD_DIR)/%.c.o,$(KERNEL_SRCS)))
WRAP_OBJ    = $(BUILD_DIR)/user_bin_wrap.o

# ---- Outputs ----
USER_ELF = $(BUILD_DIR)/user.elf
USER_BIN = $(BUILD_DIR)/user.bin
OS_ELF   = $(BUILD_DIR)/os.elf
OS_BIN   = $(BUILD_DIR)/os.bin
OS_HEX   = $(BUILD_DIR)/os.hex

# ---- Install target ----
PROG_SRC_DIR  = ../program_source
INSTALLED_HEX = $(PROG_SRC_DIR)/app/os.hex

# ---- Phony targets ----
.PHONY: all clean user kernel install

# ---- Default target ----
all: user kernel install

# ============================================================
# Stage 1: User program
# ============================================================

user: $(USER_BIN)

$(USER_BIN): $(USER_ELF)
	$(OBJCOPY) -O binary $< $@
	@echo "[USER] $$@ ($$(stat -c%s $@) bytes)"

$(USER_ELF): $(USER_OBJS) user.ld
	@mkdir -p $(BUILD_DIR)
	$(CC) $(LDFLAGS) -T user.ld -o $@ $(USER_OBJS)
	@echo "[LINK] $@"

# ---- Pattern rules: user sources ----
$(BUILD_DIR)/user/%.S.o: user/%.S
	@mkdir -p $(BUILD_DIR)/user
	$(CC) $(ASFLAGS) -c -x assembler-with-cpp -o $@ $<

$(BUILD_DIR)/user/%.c.o: user/%.c
	@mkdir -p $(BUILD_DIR)/user
	$(CC) $(CFLAGS) -Os -c -o $@ $<

# ---- Pattern rules: kernel sources ----
$(BUILD_DIR)/kernel/%.S.o: kernel/%.S
	@mkdir -p $(BUILD_DIR)/kernel
	$(CC) $(ASFLAGS) -c -x assembler-with-cpp -o $@ $<

$(BUILD_DIR)/kernel/%.c.o: kernel/%.c
	@mkdir -p $(BUILD_DIR)/kernel
	$(CC) $(CFLAGS) -Os -c -o $@ $<

# ============================================================
# Stage 2: Kernel (embeds user.bin)
# ============================================================

kernel: $(OS_HEX)

# user_bin_wrap.S: embeds user.bin into the kernel via .incbin.
# Must be regenerated whenever user.bin changes so the .incbin
# picks up the new content. The -I$(BUILD_DIR) on assembly lets
# the assembler find user.bin in the build directory.
# The "a" flag makes .user_bin allocatable (ALLOC+LOAD) so that
# objcopy -O binary includes it in the flat binary output.
$(BUILD_DIR)/user_bin_wrap.S: $(USER_BIN)
	@mkdir -p $(BUILD_DIR)
	@printf '.section .user_bin, "a", "progbits"\n\t.incbin "user.bin"\n' > $@
	@echo "[GEN ] $@ (embeds user.bin)"

$(WRAP_OBJ): $(BUILD_DIR)/user_bin_wrap.S
	$(CC) $(ASFLAGS) -I$(BUILD_DIR) -c -x assembler-with-cpp -o $@ $<

$(OS_ELF): $(KERNEL_OBJS) $(WRAP_OBJ) os.ld
	$(CC) $(LDFLAGS) -T os.ld -o $@ $(KERNEL_OBJS) $(WRAP_OBJ)
	@echo "[LINK] $@"

$(OS_BIN): $(OS_ELF)
	$(OBJCOPY) -O binary $< $@
	@echo "[OBJCOPY] $$@ ($$(stat -c%s $@) bytes)"

# Convert flat binary → $readmemh hex format (one 8-hex-char word
# per line, little-endian). This matches the format produced by
# tools/rv2coe.py:write_hex() and consumed by $readmemh in
# axi_wrap_ram.sv / axi4lite_bootrom.sv.
# --pad-start 4096: prepend 4096 zero words (0x4000 bytes) so the
# kernel (linked at 0x80004000) lands at the correct BRAM offset
# when $readmemh loads from BRAM[0] = PA 0x80000000.
# --boot-jump 0x80004000: place a 2-instruction jump (lui t0; jr t0)
# at word 0 (PA 0x80000000) so the phase-1 bootloader (which jumps to
# the SRAM base 0x80000000) reaches the kernel entry at 0x80004000.
KERNEL_BASE = 0x80004000
SRAM_BASE   = 0x80000000
PAD_WORDS   = $(shell echo $$(( ($(KERNEL_BASE) - $(SRAM_BASE)) / 4 )))

$(OS_HEX): $(OS_BIN) bin2hex.py
	@python3 bin2hex.py $(OS_BIN) $(OS_HEX) --pad-start $(PAD_WORDS) --boot-jump $(KERNEL_BASE)

# ============================================================
# Install: copy os.hex to program_source/app/
# ============================================================

install: $(OS_HEX)
	@mkdir -p $(PROG_SRC_DIR)/app
	@cp $(OS_HEX) $(INSTALLED_HEX)
	@echo "[INSTALL] $(INSTALLED_HEX)"

# ============================================================
# Clean
# ============================================================

clean:
	rm -rf $(BUILD_DIR)
	rm -f $(INSTALLED_HEX)
	@echo "[CLEAN] build artifacts removed"
