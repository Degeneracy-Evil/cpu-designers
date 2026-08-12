#!/bin/bash
# 该脚本用于编译Linux内核和OpenSBI固件，并将生成的固件复制到内核构建目录。
# 最终产物位置在：./build/opensbi/platform/generic/firmware/fw_payload.bin

set -euo pipefail

# 准备环境变量
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CPU_HOME="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
export CPU_HOME
export DTS_HOME="${CPU_HOME}/linux/dts"
export DTB_BUILD="${CPU_HOME}/build/dtb"
export DTB_OUT="${DTB_BUILD}/simplecpu.dtb"
export KERNEL_HOME="${CPU_HOME}/linux/linux-7.1"
export KERNEL_BUILD="${CPU_HOME}/build/kernel"
export KERNEL_IMG="${KERNEL_BUILD}/arch/riscv/boot/Image"
export OPENSBI_HOME="${CPU_HOME}/linux/opensbi"
export OPENSBI_BUILD="${CPU_HOME}/build/opensbi"
export OPENSBI_DEFCONFIG="${CPU_HOME}/config/opensbi_simplecpu_defconfig"
export BUSYBOX_HOME="${CPU_HOME}/linux/busybox-1.36.1"
export ROOTFS_BUILD="${CPU_HOME}/build/rootfs"
export INITRAMFS_IMG="${CPU_HOME}/build/initramfs.cpio.gz"
export FIRMWARE_HEX="${CPU_HOME}/build/program/firmware/fw_payload.hex"

MUSL_TOOLCHAIN_BIN="${CPU_HOME}/linux/toolchains/riscv32ima-linux-musl/bin"
export PATH="${MUSL_TOOLCHAIN_BIN}:${PATH}"

for tool in make dtc cpio gzip grep nproc python3 sudo \
            riscv32-linux-musl-gcc riscv64-linux-gnu-gcc; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "error: required tool not found: ${tool}" >&2
    exit 1
  fi
done

# 准备环境
rm -rf "${DTB_BUILD}" "${KERNEL_BUILD}" "${OPENSBI_BUILD}" "${ROOTFS_BUILD}"
mkdir -p "${DTB_BUILD}" "${KERNEL_BUILD}" "${OPENSBI_BUILD}" "${ROOTFS_BUILD}"

# 编译busybox
cd "${BUSYBOX_HOME}"

make ARCH=riscv CROSS_COMPILE=riscv32-linux-musl- distclean
make ARCH=riscv CROSS_COMPILE=riscv32-linux-musl- defconfig
sed -i \
  's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' \
  .config
sed -i \
  -e 's/^CONFIG_HWCLOCK=y/# CONFIG_HWCLOCK is not set/' \
  -e 's/^CONFIG_FEATURE_HWCLOCK_ADJTIME_FHS=y/# CONFIG_FEATURE_HWCLOCK_ADJTIME_FHS is not set/' \
  .config
make ARCH=riscv CROSS_COMPILE=riscv32-linux-musl- oldconfig

make ARCH=riscv CROSS_COMPILE=riscv32-linux-musl- -j"$(nproc)"

## 先在busybox目录下执行make install，生成rootfs目录结构
make ARCH=riscv CROSS_COMPILE=riscv32-linux-musl- \
  CONFIG_PREFIX="${ROOTFS_BUILD}" install

# 配置initramfs
cd "${ROOTFS_BUILD}"

mkdir -p proc sys dev tmp
cat > init <<'EOF'
#!/bin/sh

echo "[init] Hello from RV32 initramfs"
echo "[init] Mounting proc/sysfs/devtmpfs"

mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev 2>/dev/null || echo "[init] devtmpfs mount failed"

echo "[init] Starting shell loop"

while true; do
    /bin/sh </dev/console >/dev/console 2>&1
    echo "[init] shell exited, restarting..."
    sleep 1
done
EOF
chmod +x init

rm -f dev/console dev/null

# 创建设备节点需要 root；优先非交互 sudo -n，避免在 CI/无 TTY 下挂起。
# 若 sudo 不可用或需要密码，给出明确报错退出。
run_mknod() {
  local node="$1" mode="$2" type="$3" major="$4" minor="$5"
  if [ "$(id -u)" -eq 0 ]; then
    mknod -m "$mode" "$node" "$type" "$major" "$minor"
  elif command -v sudo >/dev/null 2>&1; then
    sudo -n mknod -m "$mode" "$node" "$type" "$major" "$minor" 2>/dev/null \
      || { echo "error: need root to mknod $node (run script as root or set NOPASSWD sudo)" >&2; return 1; }
  else
    echo "error: need root to mknod $node but sudo is unavailable" >&2
    return 1
  fi
}

run_mknod dev/console 600 c 5 1 || exit 1
run_mknod dev/null    666 c 1 3 || exit 1

if [ ! -e dev/console ] || [ ! -e dev/null ]; then
  echo "error: device nodes not created (missing dev/console or dev/null)" >&2
  exit 1
fi

find . -print0 | cpio --null -o --format=newc | gzip -9 > "${INITRAMFS_IMG}"

INITRAMFS_LIST="$(gzip -dc "${INITRAMFS_IMG}" | cpio -it 2>/dev/null)"
if ! grep -Eq '^(\./)?init$' <<<"${INITRAMFS_LIST}"; then
  echo "error: initramfs does not contain init" >&2
  exit 1
fi
if ! grep -Eq '^(\./)?bin/sh$' <<<"${INITRAMFS_LIST}"; then
  echo "error: initramfs does not contain bin/sh" >&2
  exit 1
fi

# 生成设备树
cd "${DTS_HOME}"

dtc -I dts -O dtb \
  -o "${DTB_OUT}" \
  simplecpu.dts

# 内核基础配置生成
cd "${KERNEL_HOME}"

make ARCH=riscv mrproper

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
  -d ERRATA_ANDES \
  -d ERRATA_SIFIVE \
  -d ERRATA_THEAD \
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

scripts/config --file "$KERNEL_BUILD/.config" \
  -e NONPORTABLE \
  -d PORTABLE \
  -d EFI \
  -d ACPI \
  -d RISCV_ISA_C

scripts/config --file "$KERNEL_BUILD/.config" \
  -e BLK_DEV_INITRD \
  -e RD_GZIP \
  --set-str INITRAMFS_SOURCE "${INITRAMFS_IMG}"

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
  -j"$(nproc)" \
  Image

##################################
# 编译OpenSBI
##################################

cd "${OPENSBI_HOME}"

OPENSBI_ARGS=(
  "O=${OPENSBI_BUILD}"
  "PLATFORM=generic"
  "PLATFORM_RISCV_XLEN=32"
  "PLATFORM_RISCV_ISA=rv32ima_zicsr_zifencei"
  "PLATFORM_RISCV_ABI=ilp32"
  "CROSS_COMPILE=riscv64-linux-gnu-"
)
OPENSBI_CONFIG="${OPENSBI_BUILD}/platform/generic/kconfig/.config"

# Generate a project-owned minimal configuration without modifying the ignored
# OpenSBI source checkout.  The normal make invocation below synchronizes it to
# auto.conf/autoconf.h before compiling.
mkdir -p "$(dirname -- "${OPENSBI_CONFIG}")"
KCONFIG_CONFIG="${OPENSBI_CONFIG}" \
OPENSBI_SRC_DIR="${OPENSBI_HOME}" \
OPENSBI_PLATFORM="generic" \
OPENSBI_PLATFORM_SRC_DIR="${OPENSBI_HOME}/platform/generic" \
python3 "${OPENSBI_HOME}/scripts/Kconfiglib/defconfig.py" \
  --kconfig "${OPENSBI_HOME}/Kconfig" \
  "${OPENSBI_DEFCONFIG}"

make -j"$(nproc)" \
  "${OPENSBI_ARGS[@]}" \
  FW_TEXT_START=0x80000000 \
  FW_PAYLOAD_OFFSET=0x400000 \
  FW_PAYLOAD_PATH="${KERNEL_IMG}" \
  FW_FDT_PATH="${DTB_OUT}"

# 生成 SRAM/DDR 仿真可直接加载的 little-endian word HEX。
mkdir -p "$(dirname -- "${FIRMWARE_HEX}")"
python3 "${CPU_HOME}/tools/bin2hex.py" \
  "${OPENSBI_BUILD}/platform/generic/firmware/fw_payload.bin" \
  "${FIRMWARE_HEX}"

echo "firmware bin: ${OPENSBI_BUILD}/platform/generic/firmware/fw_payload.bin"
echo "firmware elf: ${OPENSBI_BUILD}/platform/generic/firmware/fw_payload.elf"
echo "firmware hex: ${FIRMWARE_HEX}"
