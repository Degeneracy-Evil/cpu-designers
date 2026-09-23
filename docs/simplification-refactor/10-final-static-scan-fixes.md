# Final Static Scan Fixes

> Branch: `chp`  
> This is the last code-fix pass before architecture freeze. Keep changes local; do not reopen any architectural refactor.

## 1. Prevent duplicate physical request after DCache error

Current risk:

- `cpu_mem.phys_req_valid` stays asserted until trap entry.
- DCache returns `cpu_req_error` as a pulse and returns to `S_IDLE`.
- Before trap entry reaches `cpu_mem`, DCache can see the still-held request again and accept it a second time.
- This is unsafe for writes/MMIO side effects.

Fix locally in `dcache_ctrl.sv`:

- Add a CPU-side held-request block flag, analogous to `ptw_block_r`.
- Set it when a CPU request completes with error.
- While blocked, do not accept another CPU request.
- Clear it only after `cpu_req_valid` drops.
- Do not change the existing CPU/DCache interface or trap flow.

## 2. Correct mip/sip software-pending semantics

Files: `cpu_csr.sv` and related masks if needed.

Required behavior:

- Hardware pending sources remain read-only to CSR writes.
- S-mode software should only be able to modify SSIP through `sip`.
- STIP and external SEIP are not writable through `sip`.
- Preserve the special SEIP rule: reading `mip.SEIP` is `external_seip OR software_seip`, but CSR RMW writes must not accidentally feed the external pending value back into the software-pending latch.

Implementation guidance:

- Keep explicit software-pending storage separate from hardware pending.
- For `sip`, only SSIP software state is writable.
- For `mip`, preserve only the software-writable pending portions actually implemented by this platform.
- Do not use the combined read value directly as the source of software-pending state during CSRRS/CSRRC.

## 3. Fix PLIC gateway re-arm timing

File: `axi4lite_plic.sv`.

Current behavior re-enables a gateway when the source signal goes low. That can allow the same source to issue another request before the previous claim has been completed.

Required behavior:

- Once a gateway forwards an interrupt request, disable that gateway.
- Re-enable it only when the corresponding interrupt ID is completed by a context.
- Source deassertion alone must not re-arm the gateway.
- If the source is still asserted when completion occurs, it may generate a new request after re-arm.

Keep the existing small PLIC structure and claim/complete interface.

## 4. Register mtime Gray code before CDC

File: `system_top.sv` around the `mtime` CDC path.

Current code derives Gray code combinationally from the binary `mtime` counter and then synchronizes it. On FPGA, binary-bit skew can create combinational Gray glitches.

Fix:

- In the source clock domain, compute and register the Gray-coded `mtime`.
- Synchronize the registered Gray value into the destination clock domain with the existing two-stage synchronizer.
- Decode Gray to binary after synchronization.
- Do not redesign the CLINT or clocking architecture.

## 5. Small cleanup only

While touching the above files, clean only obvious leftovers:

- PLIC source 0 priority should remain hardwired/reserved as 0.
- Remove stale comments such as old “Phase 6” / legacy remap wording where they no longer describe current behavior.
- Remove clearly unused local wires created by earlier refactors.

Do not split modules, rename large interfaces, or introduce new wrappers.

After these fixes, stop proactive RTL refactoring.