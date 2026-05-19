# Sv32: Page-Based 32-bit Virtual-Memory Systems

> 来源：The RISC-V Instruction Set Manual, Volume II: Privileged Architecture, Section 12.3

When Sv32 is written to the MODE field in the `satp` register (see Section 12.1.11), the supervisor operates in a 32-bit paged virtual-memory system. In this mode, supervisor and user virtual addresses are translated into supervisor physical addresses by traversing a radix-tree page table. Sv32 is supported when SXLEN=32 and is designed to include mechanisms sufficient for supporting modern Unix-based operating systems.

## 12.3.1. Addressing and Memory Protection

Sv32 implementations support a 32-bit virtual address space, divided into pages. An Sv32 virtual address is partitioned into a virtual page number (VPN) and page offset, as shown in Figure 65. When Sv32 virtual memory mode is selected in the MODE field of the `satp` register, supervisor virtual addresses are translated into supervisor physical addresses via a two-level page table. The 20-bit VPN is translated into a 22-bit physical page number (PPN), while the 12-bit page offset is untranslated. The resulting supervisor-level physical addresses are then checked using any physical memory protection structures (Section 3.7), before being directly converted to machine-level physical addresses. If necessary, supervisor-level physical addresses are zero-extended to the number of physical address bits found in the implementation.

### Virtual Address Format (Figure 65)

| 31..22 | 21..12 | 11..0 |
|--------|--------|-------|
| VPN[1] | VPN[0] | page offset |
| 10 bits | 10 bits | 12 bits |

### Physical Address Format (Figure 66)

| 33..22 | 21..12 | 11..0 |
|--------|--------|-------|
| PPN[1] | PPN[0] | page offset |
| 12 bits | 10 bits | 12 bits |

### Page Table Entry Format (Figure 67)

| 31..20 | 19..10 | 9..8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|--------|--------|------|---|---|---|---|---|---|---|---|---|
| PPN[1] | PPN[0] | RSW | D | A | G | U | X | W | R | V |
| 12 bits | 10 bits | 2 bits | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 |

Sv32 page tables consist of 2^10 page-table entries (PTEs), each of four bytes. A page table is exactly the size of a page and must always be aligned to a page boundary. The physical page number of the root page table is stored in the `satp` register.

### PTE Fields

The PTE format for Sv32 is shown above. The **V** bit indicates whether the PTE is valid; if it is 0, all other bits in the PTE are don't-cares and may be used freely by software. The permission bits, **R**, **W**, and **X**, indicate whether the page is readable, writable, and executable, respectively. When all three are zero, the PTE is a pointer to the next level of the page table; otherwise, it is a leaf PTE. Writable pages must also be marked readable; the contrary combinations are reserved for future use.

### PTE R/W/X Encoding (Table 41)

| X | W | R | Meaning |
|---|---|---|---------|
| 0 | 0 | 0 | Pointer to next level of page table |
| 0 | 0 | 1 | Read-only page |
| 0 | 1 | 0 | *Reserved for future use* |
| 0 | 1 | 1 | Read-write page |
| 1 | 0 | 0 | Execute-only page |
| 1 | 0 | 1 | Read-execute page |
| 1 | 1 | 0 | *Reserved for future use* |
| 1 | 1 | 1 | Read-write-execute page |

Attempting to fetch an instruction from a page that does not have execute permissions raises a fetch page-fault exception. Attempting to execute a load, load-reserved, or cache-block management instruction whose effective address lies within a page without read permissions raises a load page-fault exception. Attempting to execute a store, store-conditional, AMO, or cache-block zero instruction whose effective address lies within a page without write permissions raises a store page-fault exception.

> AMOs never raise load page-fault exceptions. Since any unreadable page is also unwritable, attempting to perform an AMO on an unreadable page always raises a store page-fault exception.

### U Bit (User)

The **U** bit indicates whether the page is accessible to user mode. U-mode software may only access the page when U=1. If the SUM bit in the `sstatus` register is set, supervisor mode software may also access pages with U=1. However, supervisor code normally operates with the SUM bit clear, in which case, supervisor code will fault on accesses to user-mode pages. Irrespective of SUM, the supervisor may not execute code on pages with U=1.

### G Bit (Global)

The **G** bit designates a **global** mapping. Global mappings are those that exist in all address spaces. For non-leaf PTEs, the global setting implies that all mappings in the subsequent levels of the page table are global. Note that failing to mark a global mapping as global merely reduces performance, whereas marking a non-global mapping as global is a software bug that, after switching to an address space with a different non-global mapping for that address range, can unpredictably result in either mapping being used.

### RSW Field

The **RSW** field is reserved for use by supervisor software; the implementation shall ignore this field.

### A and D Bits (Accessed and Dirty)

Each leaf PTE contains an accessed (**A**) and dirty (**D**) bit:

- The **A** bit indicates the virtual page has been read, written, or fetched from since the last time the A bit was cleared.
- The **D** bit indicates the virtual page has been written since the last time the D bit was cleared.

Two schemes to manage the A and D bits are defined:

1. **Svade extension**: when a virtual page is accessed and the A bit is clear, or is written and the D bit is clear, a page-fault exception is raised.

2. **When Svade is not implemented**: the PTE is updated automatically to set the A/D bits upon access.

When a virtual page is accessed and the A bit is clear, the PTE is updated to set the A bit. When the virtual page is written and the D bit is clear, the PTE is updated to set the D bit. When G-stage address translation is in use and is not Bare, the G-stage virtual pages may be accessed or written by implicit accesses to VS-level memory management data structures, such as page tables.

When two-stage address translation is in use, an explicit access may cause both VS-stage and G-stage PTEs to be updated. The PTE update must be atomic with respect to other accesses to the PTE, and must atomically perform all page-table walk checks for that leaf PTE as part of, and before, conditionally updating the PTE value. Updates of the A bit may be performed as a result of speculation, even if the associated memory access ultimately is not performed architecturally. However, updates to the D bit, resulting from an explicit store, must be exact (i.e., non-speculative), and observed in program order by the local hart.

The PTE update must appear in the global memory order before the memory access that caused the PTE update and before any subsequent explicit memory access to that virtual page by the local hart. The ordering on loads and stores provided by FENCE instructions and the acquire/release bits on atomic instructions also orders the PTE updates associated with those loads and stores as observed by remote harts.

The PTE update is not required to be atomic with respect to the memory access that caused the update and a trap may occur between the PTE update and the memory access that caused the PTE update. If a trap occurs then the A and/or D bit may be updated but the memory access that caused the PTE update might not occur. The hart must not perform the memory access that caused the PTE update before the PTE update is globally visible.

The page tables must be located in memory with hardware page-table write access and *RsrvEventual* PMA.

All harts in a system must employ the same PTE-update scheme as each other.

The A and D bits are never cleared by the implementation. If the supervisor software does not rely on accessed and/or dirty bits, e.g. if it does not swap memory pages to secondary storage or if the pages are being used to map I/O space, it should always set them to 1 in the PTE to improve performance.

### Megapages

Any level of PTE may be a leaf PTE, so in addition to 4 KiB pages, Sv32 supports **4 MiB megapages**. A megapage must be virtually and physically aligned to a 4 MiB boundary; a page-fault exception is raised if the physical address is insufficiently aligned.

### Non-leaf PTE Constraints

For non-leaf PTEs, the D, A, and U bits are reserved for future standard use. Until their use is defined by a standard extension, they must be cleared by software for forward compatibility.

### LR/SC Reservation Set

For implementations with both page-based virtual memory and the "A" standard extension, the LR/SC reservation set must lie completely within a single base physical page (i.e., a naturally aligned 4 KiB physical-memory region).

### Misaligned Accesses

On some implementations, misaligned loads, stores, and instruction fetches may also be decomposed into multiple accesses, some of which may succeed before a page-fault exception occurs. In particular, a portion of a misaligned store that passes the exception check may become visible, even if another portion fails the exception check. The same behavior may manifest for stores wider than XLEN bits (e.g., the FSD instruction in RV32D), even when the store address is naturally aligned.

---

## 12.3.2. Virtual Address Translation Process

A virtual address *va* is translated into a physical address *pa* as follows:

1. Let *a* be `satp.ppn` × PAGESIZE, and let *i* = LEVELS − 1. (For Sv32, PAGESIZE = 2^12 and LEVELS = 2.) The `satp` register must be *active*, i.e., the effective privilege mode must be S-mode or U-mode.

2. Let *pte* be the value of the PTE at address *a* + *va.vpn*[*i*] × PTESIZE. (For Sv32, PTESIZE = 4.) If accessing *pte* violates a PMA or PMP check, raise an access-fault exception corresponding to the original access type.

3. If *pte.v* = 0, or if *pte.r* = 0 and *pte.w* = 1, or if any bits or encodings that are reserved for future standard use are set within *pte*, stop and raise a page-fault exception corresponding to the original access type.

4. Otherwise, the PTE is valid. If *pte.r* = 1 or *pte.x* = 1, go to step 5. Otherwise, this PTE is a pointer to the next level of the page table. Let *i* = *i* − 1. If *i* < 0, stop and raise a page-fault exception corresponding to the original access type. Otherwise, let *a* = *pte.ppn* × PAGESIZE and go to step 2.

5. A leaf PTE has been reached. If *i* > 0 and *pte.ppn*[*i* − 1 : 0] ≠ 0, this is a misaligned superpage; stop and raise a page-fault exception corresponding to the original access type.

6. Determine if the requested memory access is allowed by the *pte.u* bit, given the current privilege mode and the value of the SUM and MXR fields of the `mstatus` register. If not, stop and raise a page-fault exception corresponding to the original access type.

7. Determine if the requested memory access is allowed by the *pte.r*, *pte.w*, and *pte.x* bits, given the Shadow Stack Memory Protection rules. If not, stop and raise an access-fault exception.

8. Determine if the requested memory access is allowed by the *pte.r*, *pte.w*, and *pte.x* bits. If not, stop and raise a page-fault exception corresponding to the original access type.

9. If *pte.a* = 0, or if the original memory access is a store and *pte.d* = 0:

   - If the Svade extension is implemented, stop and raise a page-fault exception corresponding to the original access type.

   - If a store to the PTE at address *a* + *va.vpn*[*i*] × PTESIZE would violate a PMA or PMP check, raise an access-fault exception corresponding to the original access type.

   - Perform the following steps atomically:
     - Compare *pte* to the value of the PTE at address *a* + *va.vpn*[*i*] × PTESIZE.
     - If the values match, set *pte.a* to 1 and, if the original memory access is a store, also set *pte.d* to 1. Then store *pte* to the PTE at address *a* + *va.vpn*[*i*] × PTESIZE.
     - If the comparison fails, return to step 2.

10. The translation is successful. The translated physical address is given as follows:

    - *pa.pgoff* = *va.pgoff*.
    - If *i* > 0, then this is a superpage translation and *pa.ppn*[*i* − 1 : 0] = *va.vpn*[*i* − 1 : 0].
    - *pa.ppn*[LEVELS − 1 : *i*] = *pte.ppn*[LEVELS − 1 : *i*].

### Address-Translation Cache

All implicit accesses to the address-translation data structures in this algorithm are performed using width PTESIZE.

The results of implicit address-translation reads in step 2 may be held in a read-only, incoherent **address-translation cache** but not shared with other harts. The address-translation cache may hold an arbitrary number of entries, including an arbitrary number of entries for the same address and ASID. Entries in the address-translation cache may then satisfy subsequent step 2 reads if the ASID associated with the entry matches the ASID loaded in step 0 or if the entry is associated with a **global** mapping. To ensure that implicit reads observe writes to the same memory locations, an SFENCE.VMA instruction must be executed after the writes to flush the relevant cached translations.

The address-translation cache cannot be used in step 9; accessed and dirty bits may only be updated in memory directly.

### Speculative Execution

Implementations may also execute the address-translation algorithm speculatively at any time, for any virtual address, as long as `satp` is active. Such speculative executions have the effect of pre-populating the address-translation cache.

Speculative executions of the address-translation algorithm behave as non-speculative executions of the algorithm do, except that they must not set the dirty bit for a PTE, they must not trigger an exception, and they must not create address-translation cache entries if those entries would have been invalidated by any SFENCE.VMA instruction executed by the hart since the speculative execution of the algorithm began.

---

## Summary of Key Parameters

| Parameter | Sv32 Value |
|-----------|-----------|
| SXLEN | 32 |
| Virtual Address Width | 32 bits |
| Page Size (PAGESIZE) | 4 KiB (2^12) |
| Number of Page Table Levels (LEVELS) | 2 |
| PTE Size (PTESIZE) | 4 bytes |
| PTEs per Page Table | 2^10 = 1024 |
| VPN Width | 20 bits (VPN[1]: 10 bits, VPN[0]: 10 bits) |
| PPN Width | 22 bits (PPN[1]: 12 bits, PPN[0]: 10 bits) |
| Supported Page Sizes | 4 KiB, 4 MiB (megapage) |
| Max Physical Address | 34 bits |
