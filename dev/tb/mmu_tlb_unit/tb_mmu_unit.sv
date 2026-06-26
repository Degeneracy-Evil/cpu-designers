`timescale 1ns / 1ps

// =========================================================================
// MMU Unit Testbench
// Instantiates MMU.sv (which contains TLB + PTW internally)
// Provides a behavioral dcache BFM (memory array with 1-2 cycle response)
// Tests P0 critical bugs: i-side walk, d-side walk, permission faults
// =========================================================================
module tb_mmu_unit;

    // =====================
    // Clock and Reset
    // =====================
    reg clk = 0;
    reg resetn = 0;

    always #5 clk = ~clk;  // 100 MHz, 10ns period

    // =====================
    // MMU DUT Signals
    // =====================
    reg         translate_req = 0;
    reg  [31:0] translate_vaddr = 0;
    reg  [1:0]  translate_access = 2'b00;

    wire [31:0] i_paddr;
    wire        i_miss;
    wire        i_page_fault;
    wire [3:0]  i_pf_cause;
    wire [31:0] i_pf_vaddr;
    wire        i_ready;

    wire [31:0] d_paddr;
    wire        d_miss;
    wire        d_page_fault;
    wire [3:0]  d_pf_cause;
    wire [31:0] d_pf_vaddr;
    wire        d_ready;

    wire        translate_done_w;
    wire [31:0] translate_paddr_w;
    wire        translate_fault_w;
    wire [3:0]  translate_cause_w;
    wire [31:0] translate_vaddr_out_w;

    reg  [1:0]  priv_mode = 2'b11;   // M mode default
    reg  [31:0] satp = 32'h0;
    reg         mstatus_sum = 0;
    reg         mstatus_mxr = 0;

    // PTW cache interface (BFM provides ready/rdata/fault)
    wire        ptw_cache_req;
    wire [31:0] ptw_cache_addr;
    reg         ptw_cache_ready = 0;
    reg  [31:0] ptw_cache_rdata = 0;
    reg         ptw_cache_fault = 0;

    // PMP check (always grant in unit test)
    wire        pmp_grant = 1'b1;
    wire [1:0]  pmp_fault_type = 2'b00;

    reg         sfence_vma = 0;

    wire        sfence_done;
    wire        dbg_i_walk_active;
    wire        dbg_pending_i_walk;
    wire [2:0]  dbg_nb_i_state;
    wire        dbg_nb_i_input_changed;
    wire [31:0] dbg_nb_i_latched_vaddr;
    wire        dbg_nb_i_latched_sv32;
    wire        dbg_i_tlb_hit;
    wire        dbg_i_tlb_valid;
    wire        dbg_i_tlb_perm_fault;
    wire [1:0]  dbg_walk_state;
    wire [2:0]  dbg_nb_d_state;
    wire        dbg_d_tlb_hit;
    wire        dbg_d_tlb_valid;
    wire        dbg_d_tlb_perm_fault;
    wire        dbg_d_input_changed;
    wire [31:0] dbg_d_latched_vaddr;
    wire        dbg_d_latched_sv32;
    wire        dbg_pending_d_walk;
    wire        dbg_d_pf_from_ptw;
    wire        dbg_d_tlb_miss;

    // =====================
    // DUT Instantiation
    // =====================
    MMU u_dut(
        .clk(clk), .resetn(resetn),

        .translate_req(translate_req),
        .translate_vaddr(translate_vaddr),
        .translate_access(translate_access),
        .translate_priv(priv_mode),
        .translate_satp(satp),
        .translate_sum(mstatus_sum),
        .translate_mxr(mstatus_mxr),

        .translate_done(translate_done_w),
        .translate_paddr(translate_paddr_w),
        .translate_fault(translate_fault_w),
        .translate_cause(translate_cause_w),
        .translate_vaddr_out(translate_vaddr_out_w),

        .i_paddr(i_paddr), .i_miss(i_miss),
        .i_page_fault(i_page_fault), .i_pf_cause(i_pf_cause),
        .i_pf_vaddr(i_pf_vaddr), .i_ready(i_ready),

        .d_paddr(d_paddr), .d_miss(d_miss),
        .d_page_fault(d_page_fault), .d_pf_cause(d_pf_cause),
        .d_pf_vaddr(d_pf_vaddr), .d_ready(d_ready),

        .priv_mode(priv_mode), .satp(satp),
        .mstatus_sum(mstatus_sum), .mstatus_mxr(mstatus_mxr),

        .ptw_cache_req(ptw_cache_req), .ptw_cache_addr(ptw_cache_addr),
        .ptw_cache_ready(ptw_cache_ready), .ptw_cache_rdata(ptw_cache_rdata),
        .ptw_cache_fault(ptw_cache_fault),

        .pmp_grant(pmp_grant), .pmp_fault_type(pmp_fault_type),

        .sfence_vma(sfence_vma),

        .sfence_done(sfence_done),
        .dbg_i_walk_active(dbg_i_walk_active),
        .dbg_pending_i_walk(dbg_pending_i_walk),
        .dbg_nb_i_state(dbg_nb_i_state),
        .dbg_nb_i_input_changed(dbg_nb_i_input_changed),
        .dbg_nb_i_latched_vaddr(dbg_nb_i_latched_vaddr),
        .dbg_nb_i_latched_sv32(dbg_nb_i_latched_sv32),
        .dbg_i_tlb_hit(dbg_i_tlb_hit),
        .dbg_i_tlb_valid(dbg_i_tlb_valid),
        .dbg_i_tlb_perm_fault(dbg_i_tlb_perm_fault),
        .dbg_walk_state(dbg_walk_state),
        .dbg_nb_d_state(dbg_nb_d_state),
        .dbg_d_tlb_hit(dbg_d_tlb_hit),
        .dbg_d_tlb_valid(dbg_d_tlb_valid),
        .dbg_d_tlb_perm_fault(dbg_d_tlb_perm_fault),
        .dbg_d_input_changed(dbg_d_input_changed),
        .dbg_d_latched_vaddr(dbg_d_latched_vaddr),
        .dbg_d_latched_sv32(dbg_d_latched_sv32),
        .dbg_pending_d_walk(dbg_pending_d_walk),
        .dbg_d_pf_from_ptw(dbg_d_pf_from_ptw),
        .dbg_d_tlb_miss(dbg_d_tlb_miss)
    );

    // =====================
    // PTW Cache BFM
    // =====================
    // Word-addressed memory: ptw_mem[addr[17:2]] (64K entries = 256KB)
    // 1-2 cycle response latency: sees req at cycle N, ready=1 at cycle N+1 or N+2
    reg [31:0] ptw_mem [0:65535];
    integer mem_i;

    // Error injection: set inject_bus_error to cause next cache response to fault
    reg inject_bus_error = 0;

    // BFM state: tracks whether we've already responded to the current request
    reg bfm_served = 0;

    always @(posedge clk) begin
        ptw_cache_ready <= 1'b0;
        ptw_cache_fault <= 1'b0;
        if (!resetn) begin
            ptw_cache_ready <= 1'b0;
            ptw_cache_fault <= 1'b0;
            bfm_served      <= 1'b0;
        end else if (ptw_cache_req && !bfm_served) begin
            // New request: read from memory array and respond next cycle
            ptw_cache_rdata <= ptw_mem[ptw_cache_addr[17:2]];
            ptw_cache_ready <= 1'b1;
            bfm_served      <= 1'b1;
            if (inject_bus_error) begin
                ptw_cache_fault <= 1'b1;
                inject_bus_error <= 1'b0;
            end
        end else if (!ptw_cache_req) begin
            // Request dropped — reset served flag for next request
            bfm_served <= 1'b0;
        end
    end

    // =====================
    // Test Infrastructure
    // =====================
    integer test_pass = 0;
    integer test_fail = 0;
    integer test_total = 0;
    integer fail_id = 0;

    task check(input cond, input [511:0] name);
        begin
            test_total = test_total + 1;
            if (cond) begin
                $display("  [PASS] %0s", name);
                test_pass = test_pass + 1;
            end else begin
                $display("  [FAIL] %0s", name);
                test_fail = test_fail + 1;
                if (fail_id == 0) fail_id = test_total;
            end
        end
    endtask

    // Clear page table memory
    task clear_mem;
        begin
            for (mem_i = 0; mem_i < 65536; mem_i = mem_i + 1)
                ptw_mem[mem_i] = 32'h0;
        end
    endtask

    // Set up Sv32 page table:
    //   satp = 0x80000001 (mode=Sv32, ASID=0, PPN=0x1, root@0x1000)
    //   L1 PTE @0x1000 (vpn1=0): pointer, PPN=0x2, V=1  → PTE=0x00000801
    //   For i_vaddr=0x00100000: vpn1=0, vpn0=0x100
    //     L0 PTE @0x2400 (0x2000+0x100*4): leaf PPN=0x3, RWXAD → PTE=0x00000CCF
    //   For d_vaddr=0x00200000: vpn1=0, vpn0=0x200
    //     L0 PTE @0x2800 (0x2000+0x200*4): leaf PPN=0x4, RWXAD → PTE=0x000010CF
    //   For d_vaddr=0x00300000: vpn1=0, vpn0=0x300
    //     L0 PTE @0x2C00 (0x2000+0x300*4): leaf PPN=0x2, RXAD  → PTE=0x000008CB (W=0)
    task setup_page_table;
        begin
            ptw_mem[18'h400]  = 32'h00000801;  // 0x1000>>2: L1 pointer PPN=0x2
            ptw_mem[18'h900]  = 32'h00000CCF;  // 0x2400>>2: L0 leaf PPN=0x3 RWXAD (vpn0=0x100)
            ptw_mem[18'hA00]  = 32'h000010CF;  // 0x2800>>2: L0 leaf PPN=0x4 RWXAD (vpn0=0x200)
            ptw_mem[18'hB00]  = 32'h000008CB;  // 0x2C00>>2: L0 leaf PPN=0x2 RXAD W=0 (vpn0=0x300)
        end
    endtask

    // =====================
    // PTE / Page Table Helpers
    // =====================

    // Build a 32-bit Sv32 PTE: {PPN[21:0], D, A, G, U, X, W, R, V}
    function [31:0] mk_pte(input [21:0] ppn,
                           input d, a, g, u, x, w, r, v);
        mk_pte = {ppn, 2'b00, d, a, g, u, x, w, r, v};  // Sv32: {PPN[21:0], RSV[9:8], D,A,G,U,X,W,R,V}
    endfunction

    // L1[vpn1] → pointer to L0 table at l0_ppn (V=1, R=W=X=0)
    // root PPN=0x1 → root@0x1000 → ptw_mem index = 0x400 + vpn1
    task setup_l1_pointer(input [9:0] vpn1, input [21:0] l0_ppn);
        begin
            ptw_mem[18'h400 + vpn1] = mk_pte(l0_ppn, 1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0, 1'b1);
        end
    endtask

    // L0[vpn0] leaf PTE in L0 table at l0_ppn
    // L0 table base = l0_ppn << 12 → ptw_mem index = (l0_ppn << 10) + vpn0
    task set_l0_leaf(input [21:0] l0_ppn, input [9:0] vpn0,
                     input [21:0] leaf_ppn,
                     input d, a, g, u, x, w, r);
        begin
            ptw_mem[(l0_ppn << 10) + vpn0] = mk_pte(leaf_ppn, d, a, g, u, x, w, r, 1'b1);
        end
    endtask

    // L1[vpn1] megapage leaf PTE (is_leaf: R|W|X != 0)
    task set_l1_megapage(input [9:0] vpn1, input [21:0] leaf_ppn,
                         input d, a, g, u, x, w, r);
        begin
            ptw_mem[18'h400 + vpn1] = mk_pte(leaf_ppn, d, a, g, u, x, w, r, 1'b1);
        end
    endtask

    // Comprehensive permission page table:
    //   satp = 0x80000001 (root PPN=0x1)
    //   L1[0] → L0 table at PPN=0x2 (index 0x400 = pointer)
    //   L0[0x100]: S-page RWXAD  PPN=0x3  (vaddr 0x00100000, paddr 0x00003000)
    //   L0[0x110]: U-page RWXAD  PPN=0x5  (vaddr 0x00110000, paddr 0x00005000)
    //   L0[0x120]: S-page R-only PPN=0x6  (vaddr 0x00120000, paddr 0x00006000)
    //   L0[0x130]: S-page X-only PPN=0x7  (vaddr 0x00130000, paddr 0x00007000)
    //   L0[0x140]: S-page RW     PPN=0x8  (vaddr 0x00140000, paddr 0x00008000)
    //   L0[0x150]: U-page R-only PPN=0x9  (vaddr 0x00150000, paddr 0x00009000)
    task setup_perm_page_table;
        begin
            setup_l1_pointer(10'h000, 22'h2);           // L1[0] → L0@PPN=0x2
            set_l0_leaf(22'h2, 10'h100, 22'h3, 1'b1,1'b1,1'b0,1'b0,1'b1,1'b1,1'b1); // S RWXAD
            set_l0_leaf(22'h2, 10'h110, 22'h5, 1'b1,1'b1,1'b0,1'b1,1'b1,1'b1,1'b1); // U RWXAD
            set_l0_leaf(22'h2, 10'h120, 22'h6, 1'b1,1'b1,1'b0,1'b0,1'b0,1'b0,1'b1); // S R-only
            set_l0_leaf(22'h2, 10'h130, 22'h7, 1'b1,1'b1,1'b0,1'b0,1'b1,1'b0,1'b0); // S X-only (R=0,W=0,X=1)
            set_l0_leaf(22'h2, 10'h140, 22'h8, 1'b1,1'b1,1'b0,1'b0,1'b1,1'b1,1'b1); // S RW
            set_l0_leaf(22'h2, 10'h150, 22'h9, 1'b1,1'b1,1'b0,1'b1,1'b0,1'b0,1'b1); // U R-only
        end
    endtask

    // Wait for i_ready or i_page_fault with timeout
    task wait_i_ready_or_fault(input integer max_cycles);
        integer cnt;
        begin
            cnt = 0;
            // Force at least 2 clock edges so inputs propagate through FSM
            repeat(2) begin
                @(posedge clk);
                #1;
                cnt = cnt + 1;
            end
            while (!i_ready && !i_page_fault && cnt < max_cycles) begin
                @(posedge clk);
                #1;
                cnt = cnt + 1;
            end
        end
    endtask

    // Wait for d_ready or d_page_fault with timeout
    task wait_d_ready_or_fault(input integer max_cycles);
        integer cnt;
        begin
            cnt = 0;
            // Force at least 2 clock edges so inputs propagate through FSM
            repeat(2) begin
                @(posedge clk);
                #1;
                cnt = cnt + 1;
            end
            while (!d_ready && !d_page_fault && cnt < max_cycles) begin
                @(posedge clk);
                #1;
                cnt = cnt + 1;
            end
        end
    endtask

    // Pulse sfence_vma and wait for sfence_done
    task do_sfence;
        integer cnt;
        begin
            @(posedge clk);
            #1;
            sfence_vma = 1;
            cnt = 0;
            while (!sfence_done && cnt < 200) begin
                @(posedge clk);
                #1;
                cnt = cnt + 1;
            end
            sfence_vma = 0;
            @(posedge clk);
            #1;
        end
    endtask

    // Between tests: switch to bare mode, sfence, clear memory
    task between_tests;
        begin
            @(posedge clk);
            #1;
            satp = 32'h0;
            priv_mode = 2'b11;
            translate_req = 0;
            translate_vaddr = 0;
            translate_access = 2'b00;
            do_sfence;
            clear_mem;
        end
    endtask

    // =====================
    // Test Cases
    // =====================

    // TC_MMU_000: Bare mode identity translation (sanity)
    task tc_mmu_000;
        begin
            $display("--- TC_MMU_000: Bare mode identity translation (sanity) ---");
            @(posedge clk);
            #1;
            satp = 32'h0;
            priv_mode = 2'b11;       // M mode
            translate_vaddr = 32'h00100000;
            translate_access = 2'b00;  // FETCH
            translate_req = 1;

            wait_i_ready_or_fault(100);

            $display("  [DBG] i_ready=%b i_paddr=0x%08h i_pf=%b i_state=%0d i_latched_sv32=%b",
                     i_ready, i_paddr, i_page_fault, dbg_nb_i_state, dbg_nb_i_latched_sv32);
            check(i_ready === 1'b1, "TC_MMU_000: i_ready in bare mode");
            check(i_paddr === 32'h00100000, "TC_MMU_000: i_paddr identity in bare mode");
            check(i_page_fault === 1'b0, "TC_MMU_000: no i_page_fault in bare mode");
        end
    endtask

    // TC_MMU_001: Sv32 i-side translation (P0: i-side page walk)
    // i_vaddr=0x00100000 → vpn1=0, vpn0=0x400
    // L1@0x1000=pointer(PPN=0x2) → L0@0x3000=leaf(PPN=0x3,RWXAD)
    // Expected paddr = 0x00300000>>12 = {PPN=0x3, offset=0x000} = 0x00003000
    task tc_mmu_001;
        begin
            $display("--- TC_MMU_001: Sv32 i-side translation (P0: i-walk) ---");
            setup_page_table;
            @(posedge clk);
            #1;
            satp = 32'h80000001;    // Sv32, ASID=0, PPN=0x1
            priv_mode = 2'b01;      // S mode
            mstatus_sum = 0;
            mstatus_mxr = 0;
            translate_vaddr = 32'h00100000;
            translate_access = 2'b00;  // FETCH
            translate_req = 1;

            wait_i_ready_or_fault(200);

            $display("  [DBG] i_ready=%b i_paddr=0x%08h i_pf=%b pf_cause=%0d",
                     i_ready, i_paddr, i_page_fault, i_pf_cause);
            check(i_ready === 1'b1, "TC_MMU_001: i_ready after i-walk");
            check(i_paddr === 32'h00003000, "TC_MMU_001: i_paddr=0x3000 (PPN=0x3,off=0x000)");
            check(i_page_fault === 1'b0, "TC_MMU_001: no i_page_fault");
        end
    endtask

    // TC_MMU_002: Sv32 d-side translation (P0: d-side page walk)
    // d_vaddr=0x00200000 → vpn1=0, vpn0=0x800
    // L1@0x1000=pointer(PPN=0x2) → L0@0x4000=leaf(PPN=0x4,RWXAD)
    // Expected paddr = {PPN=0x4, offset=0x000} = 0x00004000
    task tc_mmu_002;
        begin
            $display("--- TC_MMU_002: Sv32 d-side translation (P0: d-walk) ---");
            setup_page_table;
            @(posedge clk);
            #1;
            satp = 32'h80000001;
            priv_mode = 2'b01;      // S mode
            mstatus_sum = 0;
            mstatus_mxr = 0;
            translate_vaddr = 32'h00200000;
            translate_access = 2'b01;  // LOAD
            translate_req = 1;

            wait_d_ready_or_fault(200);

            $display("  [DBG] d_ready=%b d_paddr=0x%08h d_pf=%b pf_cause=%0d",
                     d_ready, d_paddr, d_page_fault, d_pf_cause);
            check(d_ready === 1'b1, "TC_MMU_002: d_ready after d-walk");
            check(d_paddr === 32'h00004000, "TC_MMU_002: d_paddr=0x4000 (PPN=0x4,off=0x000)");
            check(d_page_fault === 1'b0, "TC_MMU_002: no d_page_fault");
        end
    endtask

    // TC_MMU_003: Sv32 i-side page fault in U mode (P0: permission fault)
    // i_vaddr=0x00100000, priv_mode=U, PTE has U=0 → perm fault
    // Expected: i_page_fault=1, i_pf_cause=12 (instruction page fault)
    task tc_mmu_003;
        begin
            $display("--- TC_MMU_003: Sv32 i-side page fault U-mode (P0: perm) ---");
            setup_page_table;
            @(posedge clk);
            #1;
            satp = 32'h80000001;
            priv_mode = 2'b00;      // U mode
            mstatus_sum = 0;
            mstatus_mxr = 0;
            translate_vaddr = 32'h00100000;
            translate_access = 2'b00;  // FETCH
            translate_req = 1;

            wait_i_ready_or_fault(200);

            $display("  [DBG] i_ready=%b i_pf=%b pf_cause=%0d i_paddr=0x%08h",
                     i_ready, i_page_fault, i_pf_cause, i_paddr);
            check(i_page_fault === 1'b1, "TC_MMU_003: i_page_fault on U-mode fetch U=0");
            check(i_pf_cause === 4'd12, "TC_MMU_003: i_pf_cause=12 (instr page fault)");
            check(i_ready === 1'b0, "TC_MMU_003: i_ready=0 on page fault");
        end
    endtask

    // TC_MMU_004: Sv32 d-side store to read-only page (P0: d-side perm fault)
    // d_vaddr=0x00300000 → vpn1=0, vpn0=0xC00
    // L0@0x5000=leaf(PPN=0x2, R=1,W=0,X=1,A=1,D=1) → STORE faults (!W)
    // Expected: d_page_fault=1, d_pf_cause=15 (store page fault)
    task tc_mmu_004;
        begin
            $display("--- TC_MMU_004: Sv32 d-side store to read-only (P0: d-perm) ---");
            setup_page_table;
            @(posedge clk);
            #1;
            satp = 32'h80000001;
            priv_mode = 2'b01;      // S mode
            mstatus_sum = 0;
            mstatus_mxr = 0;
            translate_vaddr = 32'h00300000;
            translate_access = 2'b10;  // STORE
            translate_req = 1;

            wait_d_ready_or_fault(200);

            $display("  [DBG] d_ready=%b d_pf=%b pf_cause=%0d d_paddr=0x%08h",
                     d_ready, d_page_fault, d_pf_cause, d_paddr);
            check(d_page_fault === 1'b1, "TC_MMU_004: d_page_fault on store to W=0 page");
            check(d_pf_cause === 4'd15, "TC_MMU_004: d_pf_cause=15 (store page fault)");
            check(d_ready === 1'b0, "TC_MMU_004: d_ready=0 on page fault");
        end
    endtask

    // TC_MMU_005: sfence_done premature (BUG MMU-5)
    // sfence_done = sfence_pending_r && (i_state==I_IDLE) && (d_state==D_IDLE)
    // Bug: sfence_done might assert before TLB flush actually completes,
    // allowing stale entries to be used immediately after sfence_done.
    // Test: fill TLB via translation, pulse sfence, wait for sfence_done,
    // then immediately lookup same address — if TLB still has entry (hit
    // without walk), flush was incomplete when sfence_done asserted.
    task tc_mmu_005;
        integer walk_count;
        begin
            $display("--- TC_MMU_005: sfence_done premature check (BUG MMU-5) ---");
            setup_page_table;
            @(posedge clk);
            #1;
            satp = 32'h80000001;
            priv_mode = 2'b01;      // S mode
            translate_vaddr = 32'h00100000;
            translate_access = 2'b00;  // FETCH
            translate_req = 1;

            // Wait for first translation (fills TLB)
            wait_i_ready_or_fault(200);
            check(i_ready === 1'b1, "TC_MMU_005: first translation succeeded");

            // Now pulse sfence_vma and wait for sfence_done
            @(posedge clk);
            #1;
            sfence_vma = 1;
            @(posedge clk);
            #1;
            sfence_vma = 0;

            // Wait for sfence_done with timeout
            begin : sfence_wait
                integer cnt;
                cnt = 0;
                while (!sfence_done && cnt < 100) begin
                    @(posedge clk);
                    #1;
                    cnt = cnt + 1;
                end
                $display("  [DBG] sfence_done after %0d cycles", cnt);
                check(sfence_done === 1'b1, "TC_MMU_005: sfence_done asserted");
            end

            // Immediately after sfence_done, check if TLB still has stale entry
            // If i_ready asserts immediately (same cycle or next) without ptw_cache_req,
            // the TLB wasn't flushed — bug confirmed
            @(posedge clk);
            #1;

            // Count PTW bus requests over next 5 cycles
            walk_count = 0;
            begin : count_walks
                integer i;
                for (i = 0; i < 10; i = i + 1) begin
                    @(posedge clk);
                    #1;
                    if (ptw_cache_req) walk_count = walk_count + 1;
                end
            end

            $display("  [DBG] ptw_cache_req cycles after sfence_done: %0d", walk_count);
            // If walk_count > 0, TLB was flushed (miss triggered walk) — correct behavior
            // If walk_count == 0 and i_ready==1, stale entry used — bug MMU-5 confirmed
            if (walk_count == 0) begin
                check(i_ready === 1'b0, "TC_MMU_005: no stale hit after sfence (BUG MMU-5)");
            end else begin
                check(1'b1, "TC_MMU_005: TLB properly flushed (walk needed) — no bug");
            end
        end
    endtask

    // TC_MMU_006: Sequential i-then-d translation (unified MMU)
    // With unified MMU, i and d cannot translate simultaneously.
    // Test: do i-side translation first, then d-side, verify both succeed.
    task tc_mmu_006;
        begin
            $display("--- TC_MMU_006: Sequential i-then-d translation (unified MMU) ---");
            setup_page_table;
            @(posedge clk);
            #1;
            satp = 32'h80000001;
            priv_mode = 2'b01;      // S mode

            // First: i-side translation
            translate_vaddr = 32'h00100000;   // vpn1=0, vpn0=0x100 → needs walk
            translate_access = 2'b00;         // FETCH
            translate_req = 1;

            wait_i_ready_or_fault(200);

            $display("  [DBG] i_ready=%b i_paddr=0x%08h i_pf=%b", i_ready, i_paddr, i_page_fault);
            check(i_ready === 1'b1, "TC_MMU_006: i_ready after i-side walk");
            check(i_paddr === 32'h00003000, "TC_MMU_006: i_paddr=0x3000 (PPN=0x3,off=0x000)");
            check(i_page_fault === 1'b0, "TC_MMU_006: no i_page_fault");

            // Deassert request, then do d-side translation
            translate_req = 0;
            @(posedge clk); #1;
            translate_vaddr = 32'h00200000;   // vpn1=0, vpn0=0x200 → needs walk
            translate_access = 2'b01;         // LOAD
            translate_req = 1;

            wait_d_ready_or_fault(200);

            $display("  [DBG] d_ready=%b d_paddr=0x%08h d_pf=%b", d_ready, d_paddr, d_page_fault);
            check(d_ready === 1'b1, "TC_MMU_006: d_ready after d-side walk");
            check(d_paddr === 32'h00004000, "TC_MMU_006: d_paddr=0x4000 (PPN=0x4,off=0x000)");
            check(d_page_fault === 1'b0, "TC_MMU_006: no d_page_fault");
        end
    endtask

    // TC_MMU_007: S-mode fetch from S-page RWXAD (should succeed)
    task tc_mmu_007;
        begin
            $display("--- TC_MMU_007: S-mode fetch from S-page RWXAD ---");
            setup_perm_page_table;
            @(posedge clk); #1;
            satp = 32'h80000001; priv_mode = 2'b01; mstatus_sum = 0; mstatus_mxr = 0;
            translate_vaddr = 32'h00100000; translate_access = 2'b00; translate_req = 1;
            wait_i_ready_or_fault(200);
            $display("  [DBG] i_ready=%b i_paddr=0x%08h i_pf=%b cause=%0d", i_ready, i_paddr, i_page_fault, i_pf_cause);
            check(i_ready === 1'b1, "TC_MMU_007: i_ready S-fetch S-page");
            check(i_paddr === 32'h00003000, "TC_MMU_007: i_paddr=0x3000");
            check(i_page_fault === 1'b0, "TC_MMU_007: no fault");
        end
    endtask

    // TC_MMU_008: S-mode load from S-page RWXAD (should succeed)
    task tc_mmu_008;
        begin
            $display("--- TC_MMU_008: S-mode load from S-page RWXAD ---");
            setup_perm_page_table;
            @(posedge clk); #1;
            satp = 32'h80000001; priv_mode = 2'b01; mstatus_sum = 0; mstatus_mxr = 0;
            translate_vaddr = 32'h00100000; translate_access = 2'b01; translate_req = 1;
            wait_d_ready_or_fault(200);
            $display("  [DBG] d_ready=%b d_paddr=0x%08h d_pf=%b cause=%0d", d_ready, d_paddr, d_page_fault, d_pf_cause);
            check(d_ready === 1'b1, "TC_MMU_008: d_ready S-load S-page");
            check(d_paddr === 32'h00003000, "TC_MMU_008: d_paddr=0x3000");
            check(d_page_fault === 1'b0, "TC_MMU_008: no fault");
        end
    endtask

    // TC_MMU_009: S-mode store to S-page RWXAD (should succeed)
    task tc_mmu_009;
        begin
            $display("--- TC_MMU_009: S-mode store to S-page RWXAD ---");
            setup_perm_page_table;
            @(posedge clk); #1;
            satp = 32'h80000001; priv_mode = 2'b01; mstatus_sum = 0; mstatus_mxr = 0;
            translate_vaddr = 32'h00100000; translate_access = 2'b10; translate_req = 1;
            wait_d_ready_or_fault(200);
            $display("  [DBG] d_ready=%b d_paddr=0x%08h d_pf=%b cause=%0d", d_ready, d_paddr, d_page_fault, d_pf_cause);
            check(d_ready === 1'b1, "TC_MMU_009: d_ready S-store S-page");
            check(d_paddr === 32'h00003000, "TC_MMU_009: d_paddr=0x3000");
            check(d_page_fault === 1'b0, "TC_MMU_009: no fault");
        end
    endtask

    // TC_MMU_010: U-mode fetch from U-page RWXAD (should succeed)
    task tc_mmu_010;
        begin
            $display("--- TC_MMU_010: U-mode fetch from U-page RWXAD ---");
            setup_perm_page_table;
            @(posedge clk); #1;
            satp = 32'h80000001; priv_mode = 2'b00; mstatus_sum = 0; mstatus_mxr = 0;
            translate_vaddr = 32'h00110000; translate_access = 2'b00; translate_req = 1;
            wait_i_ready_or_fault(200);
            $display("  [DBG] i_ready=%b i_paddr=0x%08h i_pf=%b cause=%0d", i_ready, i_paddr, i_page_fault, i_pf_cause);
            check(i_ready === 1'b1, "TC_MMU_010: i_ready U-fetch U-page");
            check(i_paddr === 32'h00005000, "TC_MMU_010: i_paddr=0x5000");
            check(i_page_fault === 1'b0, "TC_MMU_010: no fault");
        end
    endtask

    // TC_MMU_011: U-mode load from U-page RWXAD (should succeed)
    task tc_mmu_011;
        begin
            $display("--- TC_MMU_011: U-mode load from U-page RWXAD ---");
            setup_perm_page_table;
            @(posedge clk); #1;
            satp = 32'h80000001; priv_mode = 2'b00; mstatus_sum = 0; mstatus_mxr = 0;
            translate_vaddr = 32'h00110000; translate_access = 2'b01; translate_req = 1;
            wait_d_ready_or_fault(200);
            $display("  [DBG] d_ready=%b d_paddr=0x%08h d_pf=%b cause=%0d", d_ready, d_paddr, d_page_fault, d_pf_cause);
            check(d_ready === 1'b1, "TC_MMU_011: d_ready U-load U-page");
            check(d_paddr === 32'h00005000, "TC_MMU_011: d_paddr=0x5000");
            check(d_page_fault === 1'b0, "TC_MMU_011: no fault");
        end
    endtask

    // TC_MMU_012: U-mode store to U-page RWXAD (should succeed)
    task tc_mmu_012;
        begin
            $display("--- TC_MMU_012: U-mode store to U-page RWXAD ---");
            setup_perm_page_table;
            @(posedge clk); #1;
            satp = 32'h80000001; priv_mode = 2'b00; mstatus_sum = 0; mstatus_mxr = 0;
            translate_vaddr = 32'h00110000; translate_access = 2'b10; translate_req = 1;
            wait_d_ready_or_fault(200);
            $display("  [DBG] d_ready=%b d_paddr=0x%08h d_pf=%b cause=%0d", d_ready, d_paddr, d_page_fault, d_pf_cause);
            check(d_ready === 1'b1, "TC_MMU_012: d_ready U-store U-page");
            check(d_paddr === 32'h00005000, "TC_MMU_012: d_paddr=0x5000");
            check(d_page_fault === 1'b0, "TC_MMU_012: no fault");
        end
    endtask

    // TC_MMU_013: S-mode fetch from U-page (should fault, cause=12)
    // SUM doesn't apply to fetch — S can never fetch U pages
    task tc_mmu_013;
        begin
            $display("--- TC_MMU_013: S-mode fetch from U-page (fault) ---");
            setup_perm_page_table;
            @(posedge clk); #1;
            satp = 32'h80000001; priv_mode = 2'b01; mstatus_sum = 0; mstatus_mxr = 0;
            translate_vaddr = 32'h00110000; translate_access = 2'b00; translate_req = 1;
            wait_i_ready_or_fault(200);
            $display("  [DBG] i_ready=%b i_pf=%b cause=%0d", i_ready, i_page_fault, i_pf_cause);
            check(i_page_fault === 1'b1, "TC_MMU_013: i_page_fault S-fetch U-page");
            check(i_pf_cause === 4'd12, "TC_MMU_013: cause=12 (instr pf)");
        end
    endtask

    // TC_MMU_014: S-mode load from U-page without SUM (should fault, cause=13)
    task tc_mmu_014;
        begin
            $display("--- TC_MMU_014: S-mode load from U-page no SUM (fault) ---");
            setup_perm_page_table;
            @(posedge clk); #1;
            satp = 32'h80000001; priv_mode = 2'b01; mstatus_sum = 0; mstatus_mxr = 0;
            translate_vaddr = 32'h00110000; translate_access = 2'b01; translate_req = 1;
            wait_d_ready_or_fault(200);
            $display("  [DBG] d_ready=%b d_pf=%b cause=%0d", d_ready, d_page_fault, d_pf_cause);
            check(d_page_fault === 1'b1, "TC_MMU_014: d_page_fault S-load U-page no SUM");
            check(d_pf_cause === 4'd13, "TC_MMU_014: cause=13 (load pf)");
        end
    endtask

    // TC_MMU_015: S-mode load from U-page with SUM=1 (should succeed)
    task tc_mmu_015;
        begin
            $display("--- TC_MMU_015: S-mode load from U-page SUM=1 (succeed) ---");
            setup_perm_page_table;
            @(posedge clk); #1;
            satp = 32'h80000001; priv_mode = 2'b01; mstatus_sum = 1; mstatus_mxr = 0;
            translate_vaddr = 32'h00110000; translate_access = 2'b01; translate_req = 1;
            wait_d_ready_or_fault(200);
            $display("  [DBG] d_ready=%b d_paddr=0x%08h d_pf=%b cause=%0d", d_ready, d_paddr, d_page_fault, d_pf_cause);
            check(d_ready === 1'b1, "TC_MMU_015: d_ready S-load U-page SUM=1");
            check(d_paddr === 32'h00005000, "TC_MMU_015: d_paddr=0x5000");
            check(d_page_fault === 1'b0, "TC_MMU_015: no fault");
        end
    endtask

    // TC_MMU_016: S-mode store to U-page with SUM=1 (should succeed)
    task tc_mmu_016;
        begin
            $display("--- TC_MMU_016: S-mode store to U-page SUM=1 (succeed) ---");
            setup_perm_page_table;
            @(posedge clk); #1;
            satp = 32'h80000001; priv_mode = 2'b01; mstatus_sum = 1; mstatus_mxr = 0;
            translate_vaddr = 32'h00110000; translate_access = 2'b10; translate_req = 1;
            wait_d_ready_or_fault(200);
            $display("  [DBG] d_ready=%b d_paddr=0x%08h d_pf=%b cause=%0d", d_ready, d_paddr, d_page_fault, d_pf_cause);
            check(d_ready === 1'b1, "TC_MMU_016: d_ready S-store U-page SUM=1");
            check(d_paddr === 32'h00005000, "TC_MMU_016: d_paddr=0x5000");
            check(d_page_fault === 1'b0, "TC_MMU_016: no fault");
        end
    endtask

    // TC_MMU_017: S-mode fetch from U-page with SUM=1 (should STILL fault)
    // SUM only applies to load/store, not fetch
    task tc_mmu_017;
        begin
            $display("--- TC_MMU_017: S-mode fetch from U-page SUM=1 (still fault) ---");
            setup_perm_page_table;
            @(posedge clk); #1;
            satp = 32'h80000001; priv_mode = 2'b01; mstatus_sum = 1; mstatus_mxr = 0;
            translate_vaddr = 32'h00110000; translate_access = 2'b00; translate_req = 1;
            wait_i_ready_or_fault(200);
            $display("  [DBG] i_ready=%b i_pf=%b cause=%0d", i_ready, i_page_fault, i_pf_cause);
            check(i_page_fault === 1'b1, "TC_MMU_017: i_page_fault S-fetch U-page even with SUM");
            check(i_pf_cause === 4'd12, "TC_MMU_017: cause=12 (instr pf)");
        end
    endtask

    // TC_MMU_018: S-mode load from R-only S-page (should succeed)
    task tc_mmu_018;
        begin
            $display("--- TC_MMU_018: S-mode load from R-only S-page ---");
            setup_perm_page_table;
            @(posedge clk); #1;
            satp = 32'h80000001; priv_mode = 2'b01; mstatus_sum = 0; mstatus_mxr = 0;
            translate_vaddr = 32'h00120000; translate_access = 2'b01; translate_req = 1;
            wait_d_ready_or_fault(200);
            $display("  [DBG] d_ready=%b d_paddr=0x%08h d_pf=%b cause=%0d", d_ready, d_paddr, d_page_fault, d_pf_cause);
            check(d_ready === 1'b1, "TC_MMU_018: d_ready S-load R-only");
            check(d_paddr === 32'h00006000, "TC_MMU_018: d_paddr=0x6000");
            check(d_page_fault === 1'b0, "TC_MMU_018: no fault");
        end
    endtask

    // TC_MMU_019: S-mode load from X-only page without MXR (should fault, cause=13)
    task tc_mmu_019;
        begin
            $display("--- TC_MMU_019: S-mode load from X-only no MXR (fault) ---");
            setup_perm_page_table;
            @(posedge clk); #1;
            satp = 32'h80000001; priv_mode = 2'b01; mstatus_sum = 0; mstatus_mxr = 0;
            translate_vaddr = 32'h00130000; translate_access = 2'b01; translate_req = 1;
            wait_d_ready_or_fault(200);
            $display("  [DBG] d_ready=%b d_pf=%b cause=%0d", d_ready, d_page_fault, d_pf_cause);
            check(d_page_fault === 1'b1, "TC_MMU_019: d_page_fault load X-only no MXR");
            check(d_pf_cause === 4'd13, "TC_MMU_019: cause=13 (load pf)");
        end
    endtask

    // TC_MMU_020: S-mode load from X-only page with MXR=1 (should succeed)
    task tc_mmu_020;
        begin
            $display("--- TC_MMU_020: S-mode load from X-only MXR=1 (succeed) ---");
            setup_perm_page_table;
            @(posedge clk); #1;
            satp = 32'h80000001; priv_mode = 2'b01; mstatus_sum = 0; mstatus_mxr = 1;
            translate_vaddr = 32'h00130000; translate_access = 2'b01; translate_req = 1;
            wait_d_ready_or_fault(200);
            $display("  [DBG] d_ready=%b d_paddr=0x%08h d_pf=%b cause=%0d", d_ready, d_paddr, d_page_fault, d_pf_cause);
            check(d_ready === 1'b1, "TC_MMU_020: d_ready load X-only MXR=1");
            check(d_paddr === 32'h00007000, "TC_MMU_020: d_paddr=0x7000");
            check(d_page_fault === 1'b0, "TC_MMU_020: no fault");
        end
    endtask

    // TC_MMU_021: S-mode store to R-only page (should fault, cause=15)
    task tc_mmu_021;
        begin
            $display("--- TC_MMU_021: S-mode store to R-only (fault) ---");
            setup_perm_page_table;
            @(posedge clk); #1;
            satp = 32'h80000001; priv_mode = 2'b01; mstatus_sum = 0; mstatus_mxr = 0;
            translate_vaddr = 32'h00120000; translate_access = 2'b10; translate_req = 1;
            wait_d_ready_or_fault(200);
            $display("  [DBG] d_ready=%b d_pf=%b cause=%0d", d_ready, d_page_fault, d_pf_cause);
            check(d_page_fault === 1'b1, "TC_MMU_021: d_page_fault store R-only");
            check(d_pf_cause === 4'd15, "TC_MMU_021: cause=15 (store pf)");
        end
    endtask

    // TC_MMU_022: U-mode load from S-page (should fault, cause=13)
    // U-mode can only access U=1 pages
    task tc_mmu_022;
        begin
            $display("--- TC_MMU_022: U-mode load from S-page (fault) ---");
            setup_perm_page_table;
            @(posedge clk); #1;
            satp = 32'h80000001; priv_mode = 2'b00; mstatus_sum = 0; mstatus_mxr = 0;
            translate_vaddr = 32'h00100000; translate_access = 2'b01; translate_req = 1;
            wait_d_ready_or_fault(200);
            $display("  [DBG] d_ready=%b d_pf=%b cause=%0d", d_ready, d_page_fault, d_pf_cause);
            check(d_page_fault === 1'b1, "TC_MMU_022: d_page_fault U-load S-page");
            check(d_pf_cause === 4'd13, "TC_MMU_022: cause=13 (load pf)");
        end
    endtask

    // TC_MMU_023: Megapage translation (L1 leaf, aligned PPN)
    // L1[0] = megapage leaf PPN=0x1000, RWXAD, U=0
    // vaddr=0x00100000 → paddr = {ppn[21:10], vaddr[21:0]} = {0x4, 0x100000} = 0x10100000
    task tc_mmu_023;
        begin
            $display("--- TC_MMU_023: Megapage translation (aligned) ---");
            set_l1_megapage(10'h000, 22'h1000, 1'b1,1'b1,1'b0,1'b0,1'b1,1'b1,1'b1);
            @(posedge clk); #1;
            satp = 32'h80000001; priv_mode = 2'b01; mstatus_sum = 0; mstatus_mxr = 0;
            translate_vaddr = 32'h00100000; translate_access = 2'b00; translate_req = 1;
            wait_i_ready_or_fault(200);
            $display("  [DBG] i_ready=%b i_paddr=0x%08h i_pf=%b cause=%0d", i_ready, i_paddr, i_page_fault, i_pf_cause);
            check(i_ready === 1'b1, "TC_MMU_023: i_ready megapage");
            check(i_paddr === 32'h01100000, "TC_MMU_023: i_paddr=0x01100000 (mega)");
            check(i_page_fault === 1'b0, "TC_MMU_023: no fault");
        end
    endtask

    // TC_MMU_024: Megapage PPN misalignment (PPN[9:0] != 0 → fault)
    task tc_mmu_024;
        begin
            $display("--- TC_MMU_024: Megapage PPN misalignment (fault) ---");
            set_l1_megapage(10'h000, 22'h1001, 1'b1,1'b1,1'b0,1'b0,1'b1,1'b1,1'b1); // PPN[9:0]=0x001
            @(posedge clk); #1;
            satp = 32'h80000001; priv_mode = 2'b01; mstatus_sum = 0; mstatus_mxr = 0;
            translate_vaddr = 32'h00100000; translate_access = 2'b00; translate_req = 1;
            wait_i_ready_or_fault(200);
            $display("  [DBG] i_ready=%b i_pf=%b cause=%0d", i_ready, i_page_fault, i_pf_cause);
            check(i_page_fault === 1'b1, "TC_MMU_024: i_page_fault misaligned mega");
            check(i_pf_cause === 4'd12, "TC_MMU_024: cause=12 (instr pf)");
        end
    endtask

    // TC_MMU_025: A/D bit update — leaf PTE with A=0/D=0 now causes page fault
    // (hardware A/D update removed; trap-to-software instead)
    task tc_mmu_025;
        begin
            $display("--- TC_MMU_025: A/D bit A=0/D=0 → page fault (trap to software) ---");
            setup_l1_pointer(10'h000, 22'h2);
            set_l0_leaf(22'h2, 10'h100, 22'h3, 1'b0,1'b0,1'b0,1'b0,1'b1,1'b1,1'b1); // A=0, D=0
            @(posedge clk); #1;
            satp = 32'h80000001; priv_mode = 2'b01; mstatus_sum = 0; mstatus_mxr = 0;
            translate_vaddr = 32'h00100000; translate_access = 2'b01; translate_req = 1;
            wait_d_ready_or_fault(300);
            $display("  [DBG] d_ready=%b d_paddr=0x%08h d_pf=%b cause=%0d", d_ready, d_paddr, d_page_fault, d_pf_cause);
            check(d_page_fault === 1'b1, "TC_MMU_025: d_page_fault on A=0/D=0 (trap to sw)");
            check(d_pf_cause === 4'd13, "TC_MMU_025: cause=13 (load page fault)");
            check(d_ready === 1'b0, "TC_MMU_025: d_ready=0 on page fault");
        end
    endtask

    // TC_MMU_026: Invalid PTE (V=0) → page fault
    task tc_mmu_026;
        begin
            $display("--- TC_MMU_026: Invalid PTE V=0 (fault) ---");
            setup_l1_pointer(10'h000, 22'h2);
            ptw_mem[(22'h2 << 10) + 10'h100] = mk_pte(22'h3, 1'b0,1'b0,1'b0,1'b0,1'b1,1'b1,1'b1, 1'b0); // V=0
            @(posedge clk); #1;
            satp = 32'h80000001; priv_mode = 2'b01; mstatus_sum = 0; mstatus_mxr = 0;
            translate_vaddr = 32'h00100000; translate_access = 2'b00; translate_req = 1;
            wait_i_ready_or_fault(200);
            $display("  [DBG] i_ready=%b i_pf=%b cause=%0d", i_ready, i_page_fault, i_pf_cause);
            check(i_page_fault === 1'b1, "TC_MMU_026: i_page_fault V=0 PTE");
            check(i_pf_cause === 4'd12, "TC_MMU_026: cause=12 (instr pf)");
        end
    endtask

    // TC_MMU_027: Cache fault during walk → access fault
    task tc_mmu_027;
        begin
            $display("--- TC_MMU_027: Cache fault during walk (access fault) ---");
            setup_perm_page_table;
            @(posedge clk); #1;
            satp = 32'h80000001; priv_mode = 2'b01; mstatus_sum = 0; mstatus_mxr = 0;
            translate_vaddr = 32'h00100000; translate_access = 2'b00; translate_req = 1;
            inject_bus_error = 1;  // next cache response faults
            wait_i_ready_or_fault(200);
            $display("  [DBG] i_ready=%b i_pf=%b cause=%0d", i_ready, i_page_fault, i_pf_cause);
            check(i_page_fault === 1'b1, "TC_MMU_027: i_page_fault on cache fault");
            // Cache fault → access fault, cause=1 (instruction access fault)
            check(i_pf_cause === 4'd1, "TC_MMU_027: cause=1 (instr access fault)");
        end
    endtask

    // TC_MMU_028: Non-leaf L0 PTE (pointer at L0 level) → page fault
    // In Sv32, L0 must be a leaf; a pointer (R=W=X=0, V=1) at L0 is illegal
    task tc_mmu_028;
        begin
            $display("--- TC_MMU_028: Non-leaf L0 PTE (fault) ---");
            setup_l1_pointer(10'h000, 22'h2);
            // L0[0x100] = pointer (V=1, R=W=X=0) — illegal at level 0
            ptw_mem[(22'h2 << 10) + 10'h100] = mk_pte(22'h3, 1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0, 1'b1);
            @(posedge clk); #1;
            satp = 32'h80000001; priv_mode = 2'b01; mstatus_sum = 0; mstatus_mxr = 0;
            translate_vaddr = 32'h00100000; translate_access = 2'b00; translate_req = 1;
            wait_i_ready_or_fault(200);
            $display("  [DBG] i_ready=%b i_pf=%b cause=%0d", i_ready, i_page_fault, i_pf_cause);
            check(i_page_fault === 1'b1, "TC_MMU_028: i_page_fault non-leaf L0");
            check(i_pf_cause === 4'd12, "TC_MMU_028: cause=12 (instr pf)");
        end
    endtask

    // TC_MMU_029: TLB hit after fill — second translation of same addr skips walk
    task tc_mmu_029;
        integer walk_count;
        begin
            $display("--- TC_MMU_029: TLB hit after fill (no re-walk) ---");
            setup_perm_page_table;
            @(posedge clk); #1;
            satp = 32'h80000001; priv_mode = 2'b01; mstatus_sum = 0; mstatus_mxr = 0;
            translate_vaddr = 32'h00100000; translate_access = 2'b00; translate_req = 1;
            // First translation — should walk
            wait_i_ready_or_fault(200);
            check(i_ready === 1'b1, "TC_MMU_029: first translation succeeded");
            // Deassert request, then re-assert for second translation
            @(posedge clk); #1;
            translate_req = 0;
            @(posedge clk); #1;
            translate_req = 1;
            // Count bus requests — should be 0 (TLB hit)
            walk_count = 0;
            begin : hit_walk_count
                integer i;
                for (i = 0; i < 20; i = i + 1) begin
                    @(posedge clk); #1;
                    if (ptw_cache_req) walk_count = walk_count + 1;
                    if (i_ready) i = 20; // break
                end
            end
            $display("  [DBG] walk_count=%0d i_ready=%b i_paddr=0x%08h", walk_count, i_ready, i_paddr);
            check(i_ready === 1'b1, "TC_MMU_029: second translation ready (TLB hit)");
            check(i_paddr === 32'h00003000, "TC_MMU_029: i_paddr=0x3000 (hit)");
            check(walk_count === 0, "TC_MMU_029: no walk on TLB hit");
        end
    endtask

    // TC_MMU_030: translate_req=0 — no translation when no request
    task tc_mmu_030;
        begin
            $display("--- TC_MMU_030: translate_req=0 (no translation) ---");
            setup_perm_page_table;
            @(posedge clk); #1;
            satp = 32'h80000001; priv_mode = 2'b01; mstatus_sum = 0; mstatus_mxr = 0;
            translate_req = 0;
            repeat(10) @(posedge clk);
            #1;
            $display("  [DBG] d_ready=%b d_miss=%b d_pf=%b", d_ready, d_miss, d_page_fault);
            check(d_ready === 1'b0, "TC_MMU_030: d_ready=0 when no request");
            check(d_page_fault === 1'b0, "TC_MMU_030: no fault when no request");
        end
    endtask

    // TC_MMU_031: M-mode bare translation (satp=0 → identity)
    task tc_mmu_031;
        begin
            $display("--- TC_MMU_031: M-mode bare translation (identity) ---");
            @(posedge clk); #1;
            satp = 32'h0; priv_mode = 2'b11; mstatus_sum = 0; mstatus_mxr = 0;
            translate_vaddr = 32'hDEADBEEF; translate_access = 2'b00; translate_req = 1;
            wait_i_ready_or_fault(100);
            $display("  [DBG] i_ready=%b i_paddr=0x%08h i_pf=%b", i_ready, i_paddr, i_page_fault);
            check(i_ready === 1'b1, "TC_MMU_031: i_ready bare mode");
            check(i_paddr === 32'hDEADBEEF, "TC_MMU_031: i_paddr=identity");
            check(i_page_fault === 1'b0, "TC_MMU_031: no fault bare mode");
        end
    endtask

    // TC_MMU_032: Page fault vaddr reporting (i_pf_vaddr matches i_vaddr)
    task tc_mmu_032;
        begin
            $display("--- TC_MMU_032: Page fault vaddr reporting ---");
            setup_perm_page_table;
            @(posedge clk); #1;
            satp = 32'h80000001; priv_mode = 2'b00; mstatus_sum = 0; mstatus_mxr = 0;
            translate_vaddr = 32'h00100000; translate_access = 2'b00; translate_req = 1;
            wait_i_ready_or_fault(200);
            $display("  [DBG] i_pf=%b cause=%0d i_pf_vaddr=0x%08h", i_page_fault, i_pf_cause, i_pf_vaddr);
            check(i_page_fault === 1'b1, "TC_MMU_032: page fault occurred");
            check(i_pf_vaddr === 32'h00100000, "TC_MMU_032: i_pf_vaddr matches i_vaddr");
        end
    endtask

    // TC_MMU_033: sfence during active walk — should cancel walk and flush TLB
    task tc_mmu_033;
        begin
            $display("--- TC_MMU_033: sfence during walk ---");
            setup_perm_page_table;
            @(posedge clk); #1;
            satp = 32'h80000001; priv_mode = 2'b01; mstatus_sum = 0; mstatus_mxr = 0;
            translate_vaddr = 32'h00100000; translate_access = 2'b00; translate_req = 1;
            // Wait a couple cycles for walk to start, then sfence
            repeat(3) @(posedge clk); #1;
            sfence_vma = 1;
            @(posedge clk); #1;
            sfence_vma = 0;
            // Wait for sfence_done
            begin : sfence_during_wait
                integer cnt;
                cnt = 0;
                while (!sfence_done && cnt < 200) begin
                    @(posedge clk); #1;
                    cnt = cnt + 1;
                end
                $display("  [DBG] sfence_done after %0d cycles", cnt);
                check(sfence_done === 1'b1, "TC_MMU_033: sfence_done asserted");
            end
            // Re-assert translation — should walk again (TLB flushed)
            @(posedge clk); #1;
            translate_req = 1;
            wait_i_ready_or_fault(200);
            $display("  [DBG] i_ready=%b i_paddr=0x%08h i_pf=%b", i_ready, i_paddr, i_page_fault);
            check(i_ready === 1'b1, "TC_MMU_033: translation succeeds after sfence");
            check(i_paddr === 32'h00003000, "TC_MMU_033: i_paddr=0x3000");
        end
    endtask

    // TC_MMU_034: Sequential i-then-d translation (unified MMU)
    // With unified MMU, i and d cannot translate simultaneously.
    // Test: do i-side translation, then d-side, verify both succeed with correct paddr.
    task tc_mmu_034;
        integer cnt;
        begin
            $display("--- TC_MMU_034: Sequential i-then-d translation ---");
            setup_perm_page_table;
            @(posedge clk); #1;
            satp = 32'h80000001; priv_mode = 2'b01; mstatus_sum = 0; mstatus_mxr = 0;

            // First: i-side translation
            translate_vaddr = 32'h00100000; translate_access = 2'b00; translate_req = 1;
            wait_i_ready_or_fault(200);
            $display("  [DBG] i_ready=%b i_paddr=0x%08h", i_ready, i_paddr);
            check(i_ready === 1'b1, "TC_MMU_034: i_ready after i-side");
            check(i_paddr === 32'h00003000, "TC_MMU_034: i_paddr=0x3000");

            // Then: d-side translation
            translate_req = 0;
            @(posedge clk); #1;
            translate_vaddr = 32'h00140000; translate_access = 2'b01; translate_req = 1;
            wait_d_ready_or_fault(200);
            $display("  [DBG] d_ready=%b d_paddr=0x%08h", d_ready, d_paddr);
            check(d_ready === 1'b1, "TC_MMU_034: d_ready after d-side");
            check(d_paddr === 32'h00008000, "TC_MMU_034: d_paddr=0x8000");
        end
    endtask

    // TC_MMU_035: satp write in M-mode must flush stale TLB entries
    task tc_mmu_035;
        integer walk_count;
        begin
            $display("--- TC_MMU_035: M-mode satp write flushes TLB ---");
            clear_mem;

            // Root 1 @ 0x1000 (PPN=0x1), L0 @ 0x2000 (PPN=0x2):
            //   VA 0x0010_0000 -> PA 0x0000_3000 (PPN=0x3)
            ptw_mem[18'h400] = mk_pte(22'h2, 1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b1);
            ptw_mem[18'h900] = mk_pte(22'h3, 1'b1,1'b1,1'b0,1'b0,1'b1,1'b1,1'b1,1'b1);

            // Root 2 @ 0x3000 (PPN=0x3), L0 @ 0x4000 (PPN=0x4):
            //   same VA 0x0010_0000 -> PA 0x0000_9000 (PPN=0x9)
            ptw_mem[18'hC00]  = mk_pte(22'h4, 1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b1);
            ptw_mem[18'h1100] = mk_pte(22'h9, 1'b1,1'b1,1'b0,1'b0,1'b1,1'b1,1'b1,1'b1);

            @(posedge clk); #1;
            satp = 32'h80000001; priv_mode = 2'b01; mstatus_sum = 0; mstatus_mxr = 0;
            translate_vaddr = 32'h00100000; translate_access = 2'b00; translate_req = 1;
            wait_i_ready_or_fault(200);
            check(i_ready === 1'b1, "TC_MMU_035: first translation succeeded");
            check(i_paddr === 32'h00003000, "TC_MMU_035: first translation uses root1");

            // Rewrite satp while still in M-mode, then return to S-mode. The
            // next translation must not hit the old TLB entry from root1.
            @(posedge clk); #1;
            priv_mode = 2'b11;
            satp = 32'h80000003;
            @(posedge clk); #1;
            priv_mode = 2'b01;

            walk_count = 0;
            begin : satp_m_walk_count
                integer i;
                for (i = 0; i < 40; i = i + 1) begin
                    @(posedge clk); #1;
                    if (ptw_cache_req) walk_count = walk_count + 1;
                    if (i_ready || i_page_fault) i = 40;
                end
            end
            $display("  [DBG] walk_count=%0d i_ready=%b i_paddr=0x%08h i_pf=%b",
                     walk_count, i_ready, i_paddr, i_page_fault);
            check(i_ready === 1'b1, "TC_MMU_035: translation succeeds after M-mode satp write");
            check(i_paddr === 32'h00009000, "TC_MMU_035: second translation uses root2");
            check(walk_count > 0, "TC_MMU_035: stale TLB entry was flushed and re-walked");
        end
    endtask

    // =====================
    // Main Test Sequence
    // =====================
    initial begin
        $display("========================================");
        $display("  MMU Unit Testbench (USE_TLB_BRAM=1)");
        $display("========================================");

        // Initialize memory
        clear_mem;

        // Reset
        resetn = 0;
        translate_req = 0;
        translate_vaddr = 0;
        translate_access = 2'b00;
        priv_mode = 2'b11;
        satp = 32'h0;
        mstatus_sum = 0;
        mstatus_mxr = 0;
        sfence_vma = 0;

        repeat(10) @(posedge clk);
        @(posedge clk);
        #1;
        resetn = 1;

        // Wait for initial TLB flush to complete
        repeat(20) @(posedge clk);
        $display("Reset complete. Starting tests...\n");

        // Run tests
        tc_mmu_000;    between_tests;
        tc_mmu_001;    between_tests;
        tc_mmu_002;    between_tests;
        tc_mmu_003;    between_tests;
        tc_mmu_004;    between_tests;
        tc_mmu_005;    between_tests;
        tc_mmu_006;    between_tests;
        // Permission tests
        tc_mmu_007;    between_tests;
        tc_mmu_008;    between_tests;
        tc_mmu_009;    between_tests;
        tc_mmu_010;    between_tests;
        tc_mmu_011;    between_tests;
        tc_mmu_012;    between_tests;
        tc_mmu_013;    between_tests;
        tc_mmu_014;    between_tests;
        tc_mmu_015;    between_tests;
        tc_mmu_016;    between_tests;
        tc_mmu_017;    between_tests;
        tc_mmu_018;    between_tests;
        tc_mmu_019;    between_tests;
        tc_mmu_020;    between_tests;
        tc_mmu_021;    between_tests;
        tc_mmu_022;    between_tests;
        // PTW tests
        tc_mmu_023;    between_tests;
        tc_mmu_024;    between_tests;
        tc_mmu_025;    between_tests;
        tc_mmu_026;    between_tests;
        tc_mmu_027;    between_tests;
        tc_mmu_028;    between_tests;
        // Integration tests
        tc_mmu_029;    between_tests;
        tc_mmu_030;    between_tests;
        tc_mmu_031;    between_tests;
        tc_mmu_032;    between_tests;
        tc_mmu_033;    between_tests;
        tc_mmu_034;    between_tests;
        tc_mmu_035;

        // Report
        $display("\n========================================");
        $display("  MMU Unit Test Summary");
        $display("========================================");
        $display("  Total: %0d", test_total);
        $display("  Pass:  %0d", test_pass);
        $display("  Fail:  %0d", test_fail);
        if (test_fail > 0)
            $display("  First failure: test #%0d", fail_id);
        $display("========================================");

        $finish;
    end

    // Watchdog timer
    initial begin
        #500000;
        $display("\nERROR: Simulation timeout at 500us");
        $finish;
    end

endmodule
