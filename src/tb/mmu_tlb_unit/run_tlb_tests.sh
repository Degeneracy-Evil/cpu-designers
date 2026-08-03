#!/bin/bash
# =========================================================================
# TLB Unit Test Run Script
# Compiles and simulates tb_tlb_unit using Vivado xsim command-line flow
# =========================================================================
set -e

VIVADO_BIN=/tools/Xilinx/Vivado/2018.3/bin
XVLOG=$VIVADO_BIN/xvlog
XELAB=$VIVADO_BIN/xelab
XSIM=$VIVADO_BIN/xsim

# Project paths
RTL_CORE=src/rtl/core
TB_DIR=src/tb/mmu_tlb_unit
INCLUDE_DIR=$RTL_CORE

# Output directory
WORK_DIR=xsim_tlb_work
rm -rf $WORK_DIR
mkdir -p $WORK_DIR

echo "========================================"
echo "  TLB Unit Test Simulation"
echo "========================================"

# Step 1: Compile SystemVerilog sources
echo "[1/3] Compiling SystemVerilog sources..."

$XVLOG --sv \
    --include $INCLUDE_DIR \
    --define USE_TLB_BRAM \
    $RTL_CORE/tlb.sv \
    $RTL_CORE/tree_plru.sv \
    $TB_DIR/tb_bram_model.sv \
    $TB_DIR/tb_tlb_unit.sv \
    2>&1 | tee $WORK_DIR/compile.log

echo ""

# Step 2: Elaborate (default work library)
echo "[2/3] Elaborating testbench..."

$XELAB \
    tb_tlb_unit \
    2>&1 | tee $WORK_DIR/elaborate.log

echo ""

# Step 3: Simulate
echo "[3/3] Running simulation..."

$XSIM \
    tb_tlb_unit \
    --runall \
    2>&1 | tee $WORK_DIR/simulate.log

echo ""
echo "Done. Logs in $WORK_DIR/"
