#!/bin/bash
# 该脚本用于编译Linux内核和OpenSBI固件，并将生成的固件复制到内核构建目录。
# 该脚本必须在项目根目录下运行！
# 最终产物位置在：./build/opensbi/fw_payload.bin

set -euo pipefail

# 准备环境变量
export CPU_HOME=$(pwd)
export DTS_HOME=${CPU_HOME}/boot/dts
export DTB_BUILD=${CPU_HOME}/build/dtb
export DTB_OUT=${CPU_HOME}/build/dtb/simplecpu.dtb
export KERNEL_HOME=${CPU_HOME}/kernel/linux-7.1
export KERNEL_BUILD=${CPU_HOME}/build/kernel
export KERNEL_IMG=${CPU_HOME}/build/kernel/arch/riscv/boot/Image
export OPENSBI_HOME=${CPU_HOME}/kernel/opensbi
export OPENSBI_BUILD=${CPU_HOME}/build/opensbi

# 准备环境
rm -rf ${CPU_HOME}/build
mkdir -p $DTB_BUILD
mkdir -p $KERNEL_BUILD
mkdir -p $OPENSBI_BUILD

# 生成设备树
cd $DTS_HOME

dtc -I dts -O dtb \
  -o $DTB_OUT \
  simplecpu.dts

# 内核基础配置生成
cd $KERNEL_HOME

make ARCH=riscv \
  CROSS_COMPILE=riscv64-linux-gnu- \
  O="$KERNEL_BUILD" \
  defconfig

ARCH=riscv \
CROSS_COMPILE=riscv64-linux-gnu- \
./scripts/kconfig/merge_config.sh \
  -O "$KERNEL_BUILD" \
  "$KERNEL_BUILD/.config" \
  arch/riscv/configs/32-bit.config

# 配置内核变量
scripts/config --file "$KERNEL_BUILD/.config" \
  -d SMP \
  -d MODULES \
  \
  -e EXPERT \
  -e EMBEDDED \
  -e CC_OPTIMIZE_FOR_SIZE \
  -d CC_OPTIMIZE_FOR_PERFORMANCE \
  \
  -d NET \
  -d WIRELESS \
  -d WLAN \
  -d BT \
  -d NFC \
  \
  -d BLOCK \
  -d SCSI \
  -d ATA \
  -d MD \
  -d BLK_DEV_DM \
  -d NVME_CORE \
  -d MMC \
  -d MTD \
  \
  -d PCI \
  -d PCIEPORTBUS \
  -d HOTPLUG_PCI \
  -d USB_SUPPORT \
  -d USB \
  \
  -d VIRTIO \
  -d VIRTIO_MENU \
  -d KVM \
  \
  -d DRM \
  -d FB \
  -d SOUND \
  -d SND \
  -d MEDIA_SUPPORT \
  -d INPUT \
  -d HID \
  \
  -d EFI \
  -d ACPI \
  \
  -d SECURITY \
  -d KEYS \
  -d AUDIT \
  -d CGROUPS \
  -d NAMESPACES \
  -d BPF_SYSCALL \
  -d PERF_EVENTS \
  \
  -d DEBUG_KERNEL \
  -d DEBUG_INFO \
  -d FTRACE \
  -d TRACING \
  -d KPROBES \
  -d KALLSYMS \
  \
  -e PRINTK \
  -e TTY \
  -e SERIAL_EARLYCON \
  -e SERIAL_8250 \
  -e SERIAL_8250_CONSOLE \
  -e SERIAL_OF_PLATFORM \
  -e RISCV_SBI \
  -e RISCV_TIMER \
  -e SIFIVE_PLIC \
  -e OF \
  \
  -d SERIAL_8250_DMA \
  -d SERIAL_8250_DW \
  -d SERIAL_8250_DWLIB \
  -d SERIAL_8250_16550A_VARIANTS \
  -d RISCV_SBI_CPUIDLE \
  -d RISCV_SBI_MPXY_MBOX \
  -d RISCV_ALTERNATIVE \
  -d RISCV_ISA_FALLBACK \
  -d RISCV_ISA_ZAWRS \
  -d RISCV_ISA_ZACAS \
  -d RISCV_ISA_ZBA \
  -d RISCV_ISA_ZBB \
  -d RISCV_ISA_ZBC \
  -d RISCV_ISA_ZBKB \
  -d RISCV_ISA_ZICBOM \
  -d RISCV_ISA_ZICBOZ \
  -d RISCV_ISA_ZICBOP \
  -d RISCV_ISA_VENDOR_EXT \
  -d RISCV_ISA_VENDOR_EXT_ANDES \
  -d RISCV_ISA_VENDOR_EXT_MIPS \
  -d RISCV_ISA_VENDOR_EXT_SIFIVE \
  -d RISCV_ISA_VENDOR_EXT_THEAD \
  -d RISCV_APLIC \
  -d RISCV_APLIC_MSI \
  -d RISCV_IMSIC \
  -d RISCV_RPMI_SYSMSI \
  -d NONPORTABLE \
  -d ERRATA_ANDES \
  -d ERRATA_SIFIVE \
  -d ERRATA_THEAD \
  -d TOOLCHAIN_HAS_ZIHINTPAUSE \
  -d TOOLCHAIN_HAS_ZICOND \
  -d TOOLCHAIN_HAS_VECTOR_CRYPTO \
  -d TOOLCHAIN_NEEDS_EXPLICIT_ZICSR_ZIFENCEI \
  -d RISCV_MISALIGNED \
  -d RISCV_SCALAR_MISALIGNED \
  -d RISCV_PROBE_UNALIGNED_ACCESS \
  \
  -d OVERLAY_FS \
  -d DMADEVICES \
  -d DMA_ENGINE \
  -d VIRTUALIZATION \
  -d KVM \
  -d FPU \
  -d RISCV_SBI_V01 \
  -d CPU_IDLE \
  -d RISCV_SBI_CPUIDLE \
  -d CPU_FREQ \
  -d SECURITYFS \
  -d SECURITY \
  -d CRYPTO \
  -d XZ_DEC \
  -e CMODEL_MEDLOW \
  -d CMODEL_MEDANY \
  \
  -d STRICT_KERNEL_RWX \
  -d STRICT_MODULE_RWX \
  -d DEBUG_ALIGN_RODATA \
  -d RANDOMIZE_BASE \
  \
  -d RISCV_ISA_C

# 自动补充生成内核配置
make ARCH=riscv \
  CROSS_COMPILE=riscv64-linux-gnu- \
  O="$KERNEL_BUILD" \
  olddefconfig

# 编译内核
time \
make ARCH=riscv \
  CROSS_COMPILE=riscv64-linux-gnu- \
  O="$KERNEL_BUILD" \
  -j$(nproc) \
  Image

##################################
# 编译OpenSBI
##################################

# git clone https://github.com/riscv-software-src/opensbi.git
# 需要先手动配置CONFIG_SERIAL_SEMIHOSTING=n
# make PLATFORM=generic menuconfig

cd ${OPENSBI_HOME}

#make clean

make -j$(nproc) \
  PLATFORM=generic \
  CROSS_COMPILE=riscv64-linux-gnu- \
  PLATFORM_RISCV_XLEN=32 \
  PLATFORM_RISCV_ISA=rv32ima_zicsr_zifencei \
  PLATFORM_RISCV_ABI=ilp32 \
  FW_TEXT_START=0x80000000 \
  FW_PAYLOAD_OFFSET=0x400000 \
  FW_PAYLOAD_PATH="$KERNEL_IMG" \
  FW_FDT_PATH="$DTB_OUT"

# 将生成的OpenSBI固件复制到内核构建目录
cp build/platform/generic/firmware/fw_payload.{bin,elf} \
   ${OPENSBI_BUILD}/
