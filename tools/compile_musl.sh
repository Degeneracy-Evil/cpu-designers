#!/bin/bash

set -euo pipefail

# 编译 musl-cross-make

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CPU_HOME="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
TOOLCHAINS_HOME="${CPU_HOME}/linux/toolchains"
MUSL_CROSS_HOME="${TOOLCHAINS_HOME}/musl-cross-make"
export MUSL_HOME="${TOOLCHAINS_HOME}/riscv32ima-linux-musl"

sudo apt install -y \
  build-essential git wget curl \
  bison flex texinfo gawk libtool-bin \
  automake autoconf python3

mkdir -p "${TOOLCHAINS_HOME}"
cd "${TOOLCHAINS_HOME}"

if [[ ! -d "${MUSL_CROSS_HOME}/.git" ]]; then
  git clone --depth 1 \
    https://github.com/richfelker/musl-cross-make.git \
    "${MUSL_CROSS_HOME}"
fi
cd "${MUSL_CROSS_HOME}"

cat > config.mak <<EOF
TARGET = riscv32-linux-musl
OUTPUT = ${MUSL_HOME}

GCC_CONFIG += --enable-languages=c --with-arch=rv32ima --with-abi=ilp32 --disable-multilib --disable-shared
COMMON_CONFIG += CFLAGS="-O2" CXXFLAGS="-O2"
DL_CMD = wget -c --tries=10 --retry-connrefused --timeout=30 -O
EOF

make -j"$(nproc)"

make install

if [[ ! -x "${MUSL_HOME}/bin/riscv32-linux-musl-gcc" ]]; then
  echo "error: toolchain build failed — riscv32-linux-musl-gcc not found" >&2
  exit 1
fi

echo "musl toolchain installed at: ${MUSL_HOME}"
echo "compile_kernel.sh will add ${MUSL_HOME}/bin to PATH automatically"
