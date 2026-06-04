# FPU Integration Process Log

## 2026-06-04: FPU Unit + Pipeline Integration (Phase 3)

### Part A: Created fpu_unit.sv
- **File**: `dev/rtl/FPU/fpu_unit.sv`
- Top-level FPU module with handshake protocol mirroring mu_unit.sv exactly
- Encodes 20 FPU operations via `fpu_funct[6:0]` localparams
- Instantiates all FPU sub-modules: fpu_adder, fpu_multiplier, fpu_divider, fpu_sqrt, fpu_cvt (sequential), fpu_compare, fpu_minmax, fpu_classify, fpu_sign_inject (combinational)
- Handshake: `fpu_busy` = OR of all sub-module busy flags; `fpu_ready` = ~busy & ~req_hold & ~result_valid_reg
- Combinational ops (FMIN/FMAX/FSGNJ*/FEQ/FLT/FLE/FCLASS/FMV): result captured one cycle after req_fire
- Sequential ops (FADD/FSUB/FMUL/FDIV/FSQRT/FCVT*): start sub-module on req_fire, capture result on done
- `rd_is_int` output indicates result writes integer register (FEQ/FLT/FLE/FCLASS/FMV.X.W/FCVT.W.S/FCVT.WU.S)
- `fflags[4:0]` output: {NV, DZ, OF, UF, NX}

### Part B: Pipeline Integration

#### B1: cpu_decode.sv
- Added opcodes: OPCODE_LOAD_FP (0000111), OPCODE_STORE_FP (0100111), OPCODE_OP_FP (1010011)
- Added 20 FPU instruction match wires (inst_fadd_s through inst_fmv_w_x)
- Added category flags: is_fpu, is_flw, is_fsw
- Added fpu_funct[6:0] encoding, fpu_rm[2:0], fpu_rd_is_int
- Updated valid_inst to include is_fpu | is_flw | is_fsw
- Updated wb_we to include is_fpu | is_flw
- Extended id_exe_bus from 320 to 334 bits [333:0] (added 14 bits: is_fpu, is_flw, is_fsw, fpu_funct[6:0], fpu_rm[2:0], fpu_rd_is_int)

#### B2: cpu_execute.sv
- Added inputs: csr_frm[2:0], frs1_value[31:0], frs2_value[31:0]
- Unpacked new FPU fields from id_exe_bus_r
- Instantiated fpu_unit with DYN rounding mode resolution (fpu_rm==3'b111 ? csr_frm : fpu_rm)
- Added FPU handshake logic (fpu_req_valid, fpu_result_got, fpu_active) mirroring MU pattern
- Updated dispatch: is_fpu starts FPU, mutual exclusion with MU via !fpu_active check
- Extended exe_mem_bus from 207 to 216 bits [215:0] (added 9 bits: is_fpu, is_flw, is_fsw, fpu_rd_is_int, fpu_fflags[4:0])
- Updated exe_need_mem to include is_flw | is_fsw

#### B3: cpu_mem.sv
- Added input: frs2_value[31:0] for FSW store data
- Unpacked new FPU fields from exe_mem_bus_r
- FLW handled as word load (is_load || is_flw)
- FSW handled as word store using frs2_value (is_store || is_fsw)
- Extended mem_wb_bus from 168 to 177 bits [176:0] (added 9 bits: is_fpu, is_flw, is_fsw, fpu_rd_is_int, fpu_fflags[4:0])
- Updated mem_data_access and misalign checks for FLW/FSW

#### B4: cpu_wb.sv
- Unpacked new FPU fields from mem_wb_bus_r
- Added outputs: fp_wen, fp_waddr[4:0], fp_wdata[31:0], wb_fflags[4:0]
- Integer register write: FPU rd_is_int=1 results write to integer register
- Float register write: FPU rd_is_int=0 results and FLW write to float register
- wb_fflags: FPU exception flags for CSR accumulation (0 for non-FPU instructions)

#### B5: cpu_controller.sv
- No changes needed. Controller already stalls in STATE_EXEC while !exe_done.

#### B6: core_top.sv
- Instantiated fpu_regfile (u_fregfile) with debug read port sharing rf_addr
- Connected float register read addresses (frs1_addr = rs1_addr, frs2_addr = rs2_addr)
- Passed frs1_value/frs2_value to cpu_execute as additional inputs
- Passed frs2_value to cpu_mem for FSW
- Connected FPU CSR signals: csr_frm from cpu_trap_csr to cpu_execute, wb_fflags to fflags_wdata
- Updated exe_wb_bus shortcut for new bus layout
- Updated bus register widths and pc_plus4 extraction

#### B7: cpu_csr_interface.sv
- Updated id_exe_bus_r width from 320 to 334 bits
- Added fflags_wdata/fflags_wen inputs and csr_fflags/csr_frm outputs
- Connected to cpu_csr instance
- Updated bit extraction positions for new bus layout

#### B8: cpu_trap_csr.sv
- Updated id_exe_bus_r width from 320 to 334 bits
- Added fflags_wdata/fflags_wen inputs and csr_fflags/csr_frm outputs
- Connected to cpu_csr_interface instance

### Bus Width Summary
| Bus | Old Width | New Width | New Bits |
|-----|-----------|-----------|----------|
| id_exe_bus | 320 [319:0] | 334 [333:0] | +14 (is_fpu, is_flw, is_fsw, fpu_funct[6:0], fpu_rm[2:0], fpu_rd_is_int) |
| exe_mem_bus | 207 [206:0] | 216 [215:0] | +9 (is_fpu, is_flw, is_fsw, fpu_rd_is_int, fpu_fflags[4:0]) |
| mem_wb_bus | 168 [167:0] | 177 [176:0] | +9 (is_fpu, is_flw, is_fsw, fpu_rd_is_int, fpu_fflags[4:0]) |
