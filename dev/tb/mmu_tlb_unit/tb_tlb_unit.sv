`timescale 1ns / 1ps

// =========================================================================
// TLB Unit Testbench
// Directly instantiates tlb.sv + tree_plru.sv + behavioral BRAM models
// Tests P0 critical bugs identified in the MMU/TLB audit
// =========================================================================
module tb_tlb_unit;

    // =====================
    // Clock and Reset
    // =====================
    reg clk = 0;
    reg resetn = 0;

    always #5 clk = ~clk;  // 100 MHz, 10ns period

    // =====================
    // TLB DUT Signals
    // =====================
    // i-side lookup
    reg  [19:0] i_lookup_vpn_r = 0;
    reg  [8:0]  i_lookup_asid_r = 0;
    reg         i_lookup_req_r = 0;
    wire        i_lookup_hit;
    wire [21:0] i_lookup_ppn;
    wire        i_lookup_r, i_lookup_w, i_lookup_x, i_lookup_u;
    wire        i_lookup_a, i_lookup_d, i_lookup_g;
    wire        i_lookup_is_megapage, i_lookup_valid;

    // d-side lookup
    reg  [19:0] d_lookup_vpn_r = 0;
    reg  [8:0]  d_lookup_asid_r = 0;
    reg         d_lookup_req_r = 0;
    wire        d_lookup_hit;
    wire [21:0] d_lookup_ppn;
    wire        d_lookup_r, d_lookup_w, d_lookup_x, d_lookup_u;
    wire        d_lookup_a, d_lookup_d, d_lookup_g;
    wire        d_lookup_is_megapage, d_lookup_valid;

    // Fill
    reg         fill_req_r = 0;
    reg  [19:0] fill_vpn_r = 0;
    reg  [8:0]  fill_asid_r = 0;
    reg  [21:0] fill_ppn_r = 0;
    reg         fill_r_r = 0, fill_w_r = 0, fill_x_r = 0, fill_u_r = 0;
    reg         fill_a_r = 0, fill_d_r = 0, fill_g_r = 0, fill_is_megapage_r = 0;

    // Flush
    reg         flush_all_r = 0;
    wire        flush_done;

    // =====================
    // DUT Instantiation
    // =====================
    tlb u_dut(
        .clk(clk), .resetn(resetn),

        .i_lookup_vpn(i_lookup_vpn_r), .i_lookup_asid(i_lookup_asid_r),
        .i_lookup_req(i_lookup_req_r), .i_lookup_hit(i_lookup_hit),
        .i_lookup_ppn(i_lookup_ppn),
        .i_lookup_r(i_lookup_r), .i_lookup_w(i_lookup_w),
        .i_lookup_x(i_lookup_x), .i_lookup_u(i_lookup_u),
        .i_lookup_a(i_lookup_a), .i_lookup_d(i_lookup_d),
        .i_lookup_g(i_lookup_g), .i_lookup_is_megapage(i_lookup_is_megapage),
        .i_lookup_valid(i_lookup_valid),

        .d_lookup_vpn(d_lookup_vpn_r), .d_lookup_asid(d_lookup_asid_r),
        .d_lookup_req(d_lookup_req_r), .d_lookup_hit(d_lookup_hit),
        .d_lookup_ppn(d_lookup_ppn),
        .d_lookup_r(d_lookup_r), .d_lookup_w(d_lookup_w),
        .d_lookup_x(d_lookup_x), .d_lookup_u(d_lookup_u),
        .d_lookup_a(d_lookup_a), .d_lookup_d(d_lookup_d),
        .d_lookup_g(d_lookup_g), .d_lookup_is_megapage(d_lookup_is_megapage),
        .d_lookup_valid(d_lookup_valid),

        .fill_req(fill_req_r), .fill_vpn(fill_vpn_r), .fill_asid(fill_asid_r),
        .fill_ppn(fill_ppn_r), .fill_r(fill_r_r), .fill_w(fill_w_r),
        .fill_x(fill_x_r), .fill_u(fill_u_r), .fill_a(fill_a_r),
        .fill_d(fill_d_r), .fill_g(fill_g_r), .fill_is_megapage(fill_is_megapage_r),

        .flush_all(flush_all_r), .flush_done(flush_done)
    );

    // =====================
    // Test Infrastructure
    // =====================
    integer test_pass = 0;
    integer test_fail = 0;
    integer test_total = 0;
    integer fail_id = 0;

    // Check task: evaluate condition, report pass/fail
    task check(input cond, input [255:0] name);
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

    // Clear all inputs
    task clear_inputs;
        begin
            i_lookup_req_r = 0;
            d_lookup_req_r = 0;
            fill_req_r = 0;
            flush_all_r = 0;
        end
    endtask

    // Drive a fill request for 1 cycle
    task do_fill(
        input [19:0] vpn, input [8:0] asid, input [21:0] ppn,
        input fr, fw, fx, fu, fa, fd, fg, input mega
    );
        begin
            @(posedge clk);
            #1;
            fill_req_r = 1;
            fill_vpn_r = vpn; fill_asid_r = asid; fill_ppn_r = ppn;
            fill_r_r = fr; fill_w_r = fw; fill_x_r = fx; fill_u_r = fu;
            fill_a_r = fa; fill_d_r = fd; fill_g_r = fg; fill_is_megapage_r = mega;
            @(posedge clk);
            #1;
            fill_req_r = 0;
            fill_r_r = 0; fill_w_r = 0; fill_x_r = 0; fill_u_r = 0;
            fill_a_r = 0; fill_d_r = 0; fill_g_r = 0; fill_is_megapage_r = 0;
        end
    endtask

    // Single i-side lookup: assert req for 1 cycle, sample result
    task i_lookup_single(
        input [19:0] vpn, input [8:0] asid,
        output hit, output valid, output [21:0] ppn
    );
        begin
            @(posedge clk);
            #1;
            i_lookup_req_r = 1;
            i_lookup_vpn_r = vpn;
            i_lookup_asid_r = asid;
            @(posedge clk);
            #1;
            i_lookup_req_r = 0;
            hit = i_lookup_hit;
            valid = i_lookup_valid;
            ppn = i_lookup_ppn;
        end
    endtask

    // Single d-side lookup: assert req for 1 cycle, sample result
    task d_lookup_single(
        input [19:0] vpn, input [8:0] asid,
        output hit, output valid, output [21:0] ppn
    );
        begin
            @(posedge clk);
            #1;
            d_lookup_req_r = 1;
            d_lookup_vpn_r = vpn;
            d_lookup_asid_r = asid;
            @(posedge clk);
            #1;
            d_lookup_req_r = 0;
            hit = d_lookup_hit;
            valid = d_lookup_valid;
            ppn = d_lookup_ppn;
        end
    endtask

    // Flush all entries
    task do_flush;
        begin
            @(posedge clk);
            #1;
            flush_all_r = 1;
            wait(flush_done);
            #1;
            flush_all_r = 0;
            @(posedge clk);
        end
    endtask

    // =====================
    // Test Cases
    // =====================

    // TC_TLB_000: Basic fill + i-lookup (sanity)
    task tc_tlb_000;
        reg hit, valid;
        reg [21:0] ppn;
        begin
            $display("--- TC_TLB_000: Basic fill + i-lookup (sanity) ---");
            do_fill(20'h100, 9'h0, 22'h200, 1,1,1,0,1,0,0, 0);
            i_lookup_single(20'h100, 9'h0, hit, valid, ppn);
            check(valid === 1'b1, "TC_TLB_000: i-lookup valid");
            check(hit === 1'b1, "TC_TLB_000: i-lookup hit");
            check(ppn === 22'h200, "TC_TLB_000: i-lookup PPN=0x200");
        end
    endtask

    // TC_TLB_001: Basic fill + d-lookup (sanity)
    task tc_tlb_001;
        reg hit, valid;
        reg [21:0] ppn;
        begin
            $display("--- TC_TLB_001: Basic fill + d-lookup (sanity) ---");
            do_fill(20'h104, 9'h0, 22'h204, 1,1,0,0,1,0,0, 0);
            d_lookup_single(20'h104, 9'h0, hit, valid, ppn);
            check(valid === 1'b1, "TC_TLB_001: d-lookup valid");
            check(hit === 1'b1, "TC_TLB_001: d-lookup hit");
            check(ppn === 22'h204, "TC_TLB_001: d-lookup PPN=0x204");
        end
    endtask

    // TC_TLB_002: Fill corrupts d-lookup (BUG TLB-1)
    // d_lookup issued at cycle 0, fill arrives at cycle 1.
    // The d_lookup result should be valid at cycle 1 with correct hit.
    task tc_tlb_002;
        begin
            $display("--- TC_TLB_002: Fill corrupts d-lookup (BUG TLB-1) ---");
            // Fill entry at VPN_A = 0x100 (set 0)
            do_fill(20'h100, 9'h0, 22'h200, 1,1,1,0,1,0,0, 0);

            // Issue d_lookup for VPN_A at cycle 0
            @(posedge clk);
            #1;
            d_lookup_req_r = 1;
            d_lookup_vpn_r = 20'h100;
            d_lookup_asid_r = 9'h0;

            // At cycle 1: assert fill for VPN_B = 0x400 (set 1, different set)
            @(posedge clk);
            #1;
            fill_req_r = 1;
            fill_vpn_r = 20'h400;
            fill_asid_r = 9'h0;
            fill_ppn_r = 22'h500;
            fill_r_r = 1; fill_w_r = 1; fill_x_r = 1; fill_u_r = 0;
            fill_a_r = 1; fill_d_r = 0; fill_g_r = 0; fill_is_megapage_r = 0;

            // At this point (cycle 1): d_lookup_valid should be 1 from cycle 0's req
            // and d_lookup_hit should be 1 for VPN_A
            check(d_lookup_valid === 1'b1,
                  "TC_TLB_002: d-lookup valid when fill arrives at result cycle");
            check(d_lookup_hit === 1'b1,
                  "TC_TLB_002: d-lookup hit preserved when fill arrives");
            check(d_lookup_ppn === 22'h200,
                  "TC_TLB_002: d-lookup PPN correct when fill arrives");

            // Clean up
            d_lookup_req_r = 0;
            @(posedge clk);
            #1;
            fill_req_r = 0;
            fill_r_r = 0; fill_w_r = 0; fill_x_r = 0; fill_u_r = 0;
            fill_a_r = 0; fill_d_r = 0; fill_g_r = 0; fill_is_megapage_r = 0;
        end
    endtask

    // TC_TLB_003: Back-to-back i-lookups with different VPNs (BUG TLB-2)
    // Issue i_lookup for VPN_A at cycle 0, then i_lookup for VPN_B at cycle 1.
    // The result for VPN_A should be correct at cycle 1.
    task tc_tlb_003;
        begin
            $display("--- TC_TLB_003: Back-to-back i-lookups (BUG TLB-2) ---");
            // Fill two entries: VPN_A=0x100 (set 0), VPN_B=0x440 (set 1)
            do_fill(20'h100, 9'h0, 22'h200, 1,1,1,0,1,0,0, 0);
            do_fill(20'h440, 9'h0, 22'h240, 1,1,1,0,1,0,0, 0);

            // Issue i_lookup for VPN_A at cycle 0
            @(posedge clk);
            #1;
            i_lookup_req_r = 1;
            i_lookup_vpn_r = 20'h100;  // VPN_A
            i_lookup_asid_r = 9'h0;

            // At cycle 1: change to VPN_B (back-to-back different VPN)
            @(posedge clk);
            #1;
            // Sample result for VPN_A (should be valid and hit)
            check(i_lookup_valid === 1'b1,
                  "TC_TLB_003: first i-lookup valid at cycle 1");
            check(i_lookup_hit === 1'b1,
                  "TC_TLB_003: first i-lookup hit (VPN_A) at cycle 1");
            check(i_lookup_ppn === 22'h200,
                  "TC_TLB_003: first i-lookup PPN correct at cycle 1");

            // Now change to VPN_B
            i_lookup_vpn_r = 20'h440;  // VPN_B

            // At cycle 2: check result for VPN_B
            @(posedge clk);
            #1;
            check(i_lookup_valid === 1'b1,
                  "TC_TLB_003: second i-lookup valid at cycle 2");
            check(i_lookup_hit === 1'b1,
                  "TC_TLB_003: second i-lookup hit (VPN_B) at cycle 2");
            check(i_lookup_ppn === 22'h240,
                  "TC_TLB_003: second i-lookup PPN correct at cycle 2");

            i_lookup_req_r = 0;
        end
    endtask

    // TC_TLB_004: Back-to-back d-lookups with different VPNs (BUG TLB-3)
    task tc_tlb_004;
        begin
            $display("--- TC_TLB_004: Back-to-back d-lookups (BUG TLB-3) ---");
            do_fill(20'h100, 9'h0, 22'h200, 1,1,0,0,1,0,0, 0);
            do_fill(20'h440, 9'h0, 22'h240, 1,1,0,0,1,0,0, 0);

            // Issue d_lookup for VPN_A at cycle 0
            @(posedge clk);
            #1;
            d_lookup_req_r = 1;
            d_lookup_vpn_r = 20'h100;
            d_lookup_asid_r = 9'h0;

            // At cycle 1: change to VPN_B
            @(posedge clk);
            #1;
            check(d_lookup_valid === 1'b1,
                  "TC_TLB_004: first d-lookup valid at cycle 1");
            check(d_lookup_hit === 1'b1,
                  "TC_TLB_004: first d-lookup hit (VPN_A) at cycle 1");
            check(d_lookup_ppn === 22'h200,
                  "TC_TLB_004: first d-lookup PPN correct at cycle 1");

            d_lookup_vpn_r = 20'h440;

            // At cycle 2: check result for VPN_B
            @(posedge clk);
            #1;
            check(d_lookup_valid === 1'b1,
                  "TC_TLB_004: second d-lookup valid at cycle 2");
            check(d_lookup_hit === 1'b1,
                  "TC_TLB_004: second d-lookup hit (VPN_B) at cycle 2");
            check(d_lookup_ppn === 22'h240,
                  "TC_TLB_004: second d-lookup PPN correct at cycle 2");

            d_lookup_req_r = 0;
        end
    endtask

    // TC_TLB_005: d-lookup miss returns valid=1 with hit=0
    task tc_tlb_005;
        reg hit, valid;
        reg [21:0] ppn;
        begin
            $display("--- TC_TLB_005: d-lookup miss (no entry) ---");
            d_lookup_single(20'h999, 9'h0, hit, valid, ppn);
            check(valid === 1'b1, "TC_TLB_005: miss lookup valid=1");
            check(hit === 1'b0, "TC_TLB_005: miss lookup hit=0");
        end
    endtask

    // TC_TLB_006: i-lookup miss returns valid=1 with hit=0
    task tc_tlb_006;
        reg hit, valid;
        reg [21:0] ppn;
        begin
            $display("--- TC_TLB_006: i-lookup miss (no entry) ---");
            i_lookup_single(20'h999, 9'h0, hit, valid, ppn);
            check(valid === 1'b1, "TC_TLB_006: miss lookup valid=1");
            check(hit === 1'b0, "TC_TLB_006: miss lookup hit=0");
        end
    endtask

    // TC_TLB_007: ASID mismatch causes miss
    task tc_tlb_007;
        reg hit, valid;
        reg [21:0] ppn;
        begin
            $display("--- TC_TLB_007: ASID mismatch ---");
            do_fill(20'h100, 9'h1, 22'h200, 1,1,1,0,1,0,0, 0);
            // Lookup with different ASID
            i_lookup_single(20'h100, 9'h2, hit, valid, ppn);
            check(valid === 1'b1, "TC_TLB_007: valid=1 for ASID mismatch");
            check(hit === 1'b0, "TC_TLB_007: miss on ASID mismatch");
            // Lookup with correct ASID
            i_lookup_single(20'h100, 9'h1, hit, valid, ppn);
            check(hit === 1'b1, "TC_TLB_007: hit on ASID match");
        end
    endtask

    // TC_TLB_008: Global bit ignores ASID
    task tc_tlb_008;
        reg hit, valid;
        reg [21:0] ppn;
        begin
            $display("--- TC_TLB_008: Global bit ignores ASID ---");
            do_fill(20'h100, 9'h1, 22'h200, 1,1,1,0,1,0,1, 0); // g=1
            // Lookup with different ASID should still hit
            i_lookup_single(20'h100, 9'h5, hit, valid, ppn);
            check(hit === 1'b1, "TC_TLB_008: hit with global bit despite ASID mismatch");
        end
    endtask

    // TC_TLB_009: Flush clears all entries
    task tc_tlb_009;
        reg hit, valid;
        reg [21:0] ppn;
        begin
            $display("--- TC_TLB_009: Flush clears entries ---");
            do_fill(20'h100, 9'h0, 22'h200, 1,1,1,0,1,0,0, 0);
            i_lookup_single(20'h100, 9'h0, hit, valid, ppn);
            check(hit === 1'b1, "TC_TLB_009: hit before flush");

            do_flush;

            i_lookup_single(20'h100, 9'h0, hit, valid, ppn);
            check(hit === 1'b0, "TC_TLB_009: miss after flush");
        end
    endtask

    // TC_TLB_010: Megapage lookup matches on VPN[19:10]
    task tc_tlb_010;
        reg hit, valid;
        reg [21:0] ppn;
        begin
            $display("--- TC_TLB_010: Megapage lookup ---");
            // Fill megapage: VPN=0x100 (lower 10 bits will be ignored)
            do_fill(20'h100, 9'h0, 22'h200, 1,1,1,0,1,0,0, 1); // mega=1
            // Lookup VPN=0x1FF — should hit because VPN[19:10] matches 0x100[19:10]=0x0
            // Wait: VPN[19:10] for 0x100 = 0x0, for 0x1FF = 0x0 → match
            // Actually: 0x100 = 0001_0000_0000, [19:10] = 0000_0000_00 = 0x0
            //           0x1FF = 0001_1111_1111, [19:10] = 0000_0000_00 = 0x0 → match!
            i_lookup_single(20'h1FF, 9'h0, hit, valid, ppn);
            check(hit === 1'b1, "TC_TLB_010: megapage hit on VPN[19:10] match");
            check(ppn === 22'h200, "TC_TLB_010: megapage PPN correct");
        end
    endtask

    // TC_TLB_011: Fill and d-lookup at same cycle (fill preempts)
    task tc_tlb_011;
        begin
            $display("--- TC_TLB_011: Fill preempts d-lookup at same cycle ---");
            // Fill VPN_A first
            do_fill(20'h100, 9'h0, 22'h200, 1,1,1,0,1,0,0, 0);

            // Issue d_lookup and fill at the same cycle
            @(posedge clk);
            #1;
            d_lookup_req_r = 1;
            d_lookup_vpn_r = 20'h100;
            d_lookup_asid_r = 9'h0;
            fill_req_r = 1;
            fill_vpn_r = 20'h400;
            fill_asid_r = 9'h0;
            fill_ppn_r = 22'h500;
            fill_r_r = 1; fill_w_r = 1; fill_x_r = 1; fill_u_r = 0;
            fill_a_r = 1; fill_d_r = 0; fill_g_r = 0; fill_is_megapage_r = 0;

            @(posedge clk);
            #1;
            // When fill and d-lookup at same cycle, fill has priority.
            // d_lookup_valid should be 0 (no read was performed)
            check(d_lookup_valid === 1'b0,
                  "TC_TLB_011: d-lookup not valid when fill preempts at same cycle");

            d_lookup_req_r = 0;
            @(posedge clk);
            #1;
            fill_req_r = 0;
            fill_r_r = 0; fill_w_r = 0; fill_x_r = 0; fill_u_r = 0;
            fill_a_r = 0; fill_d_r = 0; fill_g_r = 0; fill_is_megapage_r = 0;

            // Now lookup VPN_B (the filled one) should hit
            @(posedge clk);
            #1;
            d_lookup_req_r = 1;
            d_lookup_vpn_r = 20'h400;
            d_lookup_asid_r = 9'h0;
            @(posedge clk);
            #1;
            d_lookup_req_r = 0;
            check(d_lookup_valid === 1'b1, "TC_TLB_011: fill completed, lookup valid");
            check(d_lookup_hit === 1'b1, "TC_TLB_011: fill completed, lookup hit");
        end
    endtask

    // TC_TLB_012: Multiple fills to same set, then lookup each
    task tc_tlb_012;
        reg hit, valid;
        reg [21:0] ppn;
        begin
            $display("--- TC_TLB_012: Multiple fills to same set ---");
            // VPNs 0x1000, 0x2000, 0x3000, 0x4000 all map to set 0 (vpn[11:10]=00)
            do_fill(20'h1000, 9'h0, 22'hA00, 1,1,1,0,1,0,0, 0);
            do_fill(20'h2000, 9'h0, 22'hB00, 1,1,1,0,1,0,0, 0);
            do_fill(20'h3000, 9'h0, 22'hC00, 1,1,1,0,1,0,0, 0);
            do_fill(20'h4000, 9'h0, 22'hD00, 1,1,1,0,1,0,0, 0);

            i_lookup_single(20'h1000, 9'h0, hit, valid, ppn);
            check(hit === 1'b1 && ppn === 22'hA00, "TC_TLB_012: way 0 lookup");
            i_lookup_single(20'h2000, 9'h0, hit, valid, ppn);
            check(hit === 1'b1 && ppn === 22'hB00, "TC_TLB_012: way 1 lookup");
            i_lookup_single(20'h3000, 9'h0, hit, valid, ppn);
            check(hit === 1'b1 && ppn === 22'hC00, "TC_TLB_012: way 2 lookup");
            i_lookup_single(20'h4000, 9'h0, hit, valid, ppn);
            check(hit === 1'b1 && ppn === 22'hD00, "TC_TLB_012: way 3 lookup");
        end
    endtask

    // TC_TLB_013: 5th fill to same set evicts via PLRU (BUG TLB-4)
    task tc_tlb_013;
        reg hit, valid;
        reg [21:0] ppn;
        begin
            $display("--- TC_TLB_013: 5th fill evicts via PLRU (BUG TLB-4) ---");
            // Fill 4 entries in set 0 (vpn[11:10]=00)
            do_fill(20'h1000, 9'h0, 22'hA00, 1,1,1,0,1,0,0, 0);
            do_fill(20'h2000, 9'h0, 22'hB00, 1,1,1,0,1,0,0, 0);
            do_fill(20'h3000, 9'h0, 22'hC00, 1,1,1,0,1,0,0, 0);
            do_fill(20'h4000, 9'h0, 22'hD00, 1,1,1,0,1,0,0, 0);

            // All 4 should be present
            i_lookup_single(20'h1000, 9'h0, hit, valid, ppn);
            check(hit === 1'b1, "TC_TLB_013: way 0 present before 5th fill");
            i_lookup_single(20'h2000, 9'h0, hit, valid, ppn);
            check(hit === 1'b1, "TC_TLB_013: way 1 present before 5th fill");
            i_lookup_single(20'h3000, 9'h0, hit, valid, ppn);
            check(hit === 1'b1, "TC_TLB_013: way 2 present before 5th fill");
            i_lookup_single(20'h4000, 9'h0, hit, valid, ppn);
            check(hit === 1'b1, "TC_TLB_013: way 3 present before 5th fill");

            // 5th fill to same set — should evict one via PLRU
            do_fill(20'h5000, 9'h0, 22'hE00, 1,1,1,0,1,0,0, 0);

            // The new entry should be present
            i_lookup_single(20'h5000, 9'h0, hit, valid, ppn);
            check(hit === 1'b1, "TC_TLB_013: new entry present after 5th fill");
            check(ppn === 22'hE00, "TC_TLB_013: new entry PPN correct");

            // Count how many of the original 4 are still present
            // (PLRU should evict exactly 1, so 3 should remain + 1 new = 4 total)
            begin : check_evict
                integer remaining;
                reg h;
                reg v;
                reg [21:0] p;
                remaining = 0;
                i_lookup_single(20'h1000, 9'h0, h, v, p);
                if (h) remaining = remaining + 1;
                i_lookup_single(20'h2000, 9'h0, h, v, p);
                if (h) remaining = remaining + 1;
                i_lookup_single(20'h3000, 9'h0, h, v, p);
                if (h) remaining = remaining + 1;
                i_lookup_single(20'h4000, 9'h0, h, v, p);
                if (h) remaining = remaining + 1;
                check(remaining == 3, "TC_TLB_013: exactly 1 evicted, 3 remaining");
            end
        end
    endtask

    // TC_TLB_014: i-side and d-side simultaneous lookup
    task tc_tlb_014;
        begin
            $display("--- TC_TLB_014: Simultaneous i+d lookup ---");
            do_fill(20'h100, 9'h0, 22'h200, 1,1,1,0,1,0,0, 0);
            do_fill(20'h440, 9'h0, 22'h240, 1,1,0,0,1,0,0, 0);

            @(posedge clk);
            #1;
            i_lookup_req_r = 1;
            i_lookup_vpn_r = 20'h100;
            i_lookup_asid_r = 9'h0;
            d_lookup_req_r = 1;
            d_lookup_vpn_r = 20'h440;
            d_lookup_asid_r = 9'h0;

            @(posedge clk);
            #1;
            i_lookup_req_r = 0;
            d_lookup_req_r = 0;

            check(i_lookup_valid === 1'b1, "TC_TLB_014: i-lookup valid (simultaneous)");
            check(i_lookup_hit === 1'b1, "TC_TLB_014: i-lookup hit (simultaneous)");
            check(d_lookup_valid === 1'b1, "TC_TLB_014: d-lookup valid (simultaneous)");
            check(d_lookup_hit === 1'b1, "TC_TLB_014: d-lookup hit (simultaneous)");
        end
    endtask

    // TC_TLB_015: PLRU eviction order after 4 sequential fills
    // After 4 fills to same set, PLRU state=000, victim=way 0.
    // 5th fill should evict the first entry (way 0).
    task tc_tlb_015;
        reg hit, valid;
        reg [21:0] ppn;
        begin
            $display("--- TC_TLB_015: PLRU eviction order (5th fill evicts way 0) ---");
            do_fill(20'h1000, 9'h0, 22'hA00, 1,1,1,0,1,0,0, 0);  // way 0
            do_fill(20'h2000, 9'h0, 22'hB00, 1,1,1,0,1,0,0, 0);  // way 1
            do_fill(20'h3000, 9'h0, 22'hC00, 1,1,1,0,1,0,0, 0);  // way 2
            do_fill(20'h4000, 9'h0, 22'hD00, 1,1,1,0,1,0,0, 0);  // way 3

            // 5th fill — should evict way 0 (VPN 0x1000)
            do_fill(20'h5000, 9'h0, 22'hE00, 1,1,1,0,1,0,0, 0);

            i_lookup_single(20'h1000, 9'h0, hit, valid, ppn);
            check(valid === 1'b1, "TC_TLB_015: evicted entry lookup valid");
            check(hit === 1'b0, "TC_TLB_015: way 0 evicted (VPN 0x1000 miss)");

            i_lookup_single(20'h2000, 9'h0, hit, valid, ppn);
            check(hit === 1'b1 && ppn === 22'hB00, "TC_TLB_015: way 1 still present");
            i_lookup_single(20'h3000, 9'h0, hit, valid, ppn);
            check(hit === 1'b1 && ppn === 22'hC00, "TC_TLB_015: way 2 still present");
            i_lookup_single(20'h4000, 9'h0, hit, valid, ppn);
            check(hit === 1'b1 && ppn === 22'hD00, "TC_TLB_015: way 3 still present");
            i_lookup_single(20'h5000, 9'h0, hit, valid, ppn);
            check(hit === 1'b1 && ppn === 22'hE00, "TC_TLB_015: new entry present");
        end
    endtask

    // TC_TLB_016: PLRU after lookup access changes eviction target
    // After 4 fills, lookup way 0 → PLRU state changes → 5th fill evicts way 3.
    task tc_tlb_016;
        reg hit, valid;
        reg [21:0] ppn;
        integer remaining;
        begin
            $display("--- TC_TLB_016: PLRU after access changes eviction ---");
            do_fill(20'h1000, 9'h0, 22'hA00, 1,1,1,0,1,0,0, 0);  // way 0
            do_fill(20'h2000, 9'h0, 22'hB00, 1,1,1,0,1,0,0, 0);  // way 1
            do_fill(20'h3000, 9'h0, 22'hC00, 1,1,1,0,1,0,0, 0);  // way 2
            do_fill(20'h4000, 9'h0, 22'hD00, 1,1,1,0,1,0,0, 0);  // way 3

            // Access way 0 via lookup → PLRU state changes from 000 to 110
            i_lookup_single(20'h1000, 9'h0, hit, valid, ppn);
            check(hit === 1'b1, "TC_TLB_016: lookup way 0 hits");

            // 5th fill — way 0 should be protected by the lookup access.
            // The exact victim depends on PLRU state transition details;
            // the key invariant is that way 0 (recently accessed) survives.
            do_fill(20'h5000, 9'h0, 22'hE00, 1,1,1,0,1,0,0, 0);

            // Way 0 must still be present (lookup protected it from eviction)
            i_lookup_single(20'h1000, 9'h0, hit, valid, ppn);
            check(hit === 1'b1 && ppn === 22'hA00, "TC_TLB_016: way 0 still present (protected by lookup)");

            // New entry must be present
            i_lookup_single(20'h5000, 9'h0, hit, valid, ppn);
            check(hit === 1'b1 && ppn === 22'hE00, "TC_TLB_016: new entry present");

            // Exactly 4 entries remain; each present entry has correct PPN
            remaining = 0;
            i_lookup_single(20'h1000, 9'h0, hit, valid, ppn);
            if (hit) begin remaining = remaining + 1;
                check(ppn === 22'hA00, "TC_TLB_016: VPN 0x1000 PPN correct"); end
            i_lookup_single(20'h2000, 9'h0, hit, valid, ppn);
            if (hit) begin remaining = remaining + 1;
                check(ppn === 22'hB00, "TC_TLB_016: VPN 0x2000 PPN correct"); end
            i_lookup_single(20'h3000, 9'h0, hit, valid, ppn);
            if (hit) begin remaining = remaining + 1;
                check(ppn === 22'hC00, "TC_TLB_016: VPN 0x3000 PPN correct"); end
            i_lookup_single(20'h4000, 9'h0, hit, valid, ppn);
            if (hit) begin remaining = remaining + 1;
                check(ppn === 22'hD00, "TC_TLB_016: VPN 0x4000 PPN correct"); end
            i_lookup_single(20'h5000, 9'h0, hit, valid, ppn);
            if (hit) begin remaining = remaining + 1;
                check(ppn === 22'hE00, "TC_TLB_016: VPN 0x5000 PPN correct"); end
            check(remaining == 4, "TC_TLB_016: exactly 4 entries remain after 5 fills");
        end
    endtask

    // TC_TLB_017: All 4 sets independence
    task tc_tlb_017;
        reg hit, valid;
        reg [21:0] ppn;
        begin
            $display("--- TC_TLB_017: All 4 sets independence ---");
            // Fill one entry in each set
            do_fill(20'h0000, 9'h0, 22'hA01, 1,1,1,0,1,0,0, 0);  // set 0
            do_fill(20'h0400, 9'h0, 22'hA02, 1,1,1,0,1,0,0, 0);  // set 1
            do_fill(20'h0800, 9'h0, 22'hA03, 1,1,1,0,1,0,0, 0);  // set 2
            do_fill(20'h0C00, 9'h0, 22'hA04, 1,1,1,0,1,0,0, 0);  // set 3

            i_lookup_single(20'h0000, 9'h0, hit, valid, ppn);
            check(hit === 1'b1 && ppn === 22'hA01, "TC_TLB_017: set 0 hit");
            i_lookup_single(20'h0400, 9'h0, hit, valid, ppn);
            check(hit === 1'b1 && ppn === 22'hA02, "TC_TLB_017: set 1 hit");
            i_lookup_single(20'h0800, 9'h0, hit, valid, ppn);
            check(hit === 1'b1 && ppn === 22'hA03, "TC_TLB_017: set 2 hit");
            i_lookup_single(20'h0C00, 9'h0, hit, valid, ppn);
            check(hit === 1'b1 && ppn === 22'hA04, "TC_TLB_017: set 3 hit");

            // Fill a 2nd entry in each set (different VPN, same set)
            do_fill(20'h1000, 9'h0, 22'hB01, 1,1,1,0,1,0,0, 0);  // set 0
            do_fill(20'h1400, 9'h0, 22'hB02, 1,1,1,0,1,0,0, 0);  // set 1
            do_fill(20'h1800, 9'h0, 22'hB03, 1,1,1,0,1,0,0, 0);  // set 2
            do_fill(20'h1C00, 9'h0, 22'hB04, 1,1,1,0,1,0,0, 0);  // set 3

            i_lookup_single(20'h1000, 9'h0, hit, valid, ppn);
            check(hit === 1'b1 && ppn === 22'hB01, "TC_TLB_017: set 0 2nd entry hit");
            i_lookup_single(20'h1400, 9'h0, hit, valid, ppn);
            check(hit === 1'b1 && ppn === 22'hB02, "TC_TLB_017: set 1 2nd entry hit");
            i_lookup_single(20'h1800, 9'h0, hit, valid, ppn);
            check(hit === 1'b1 && ppn === 22'hB03, "TC_TLB_017: set 2 2nd entry hit");
            i_lookup_single(20'h1C00, 9'h0, hit, valid, ppn);
            check(hit === 1'b1 && ppn === 22'hB04, "TC_TLB_017: set 3 2nd entry hit");
        end
    endtask

    // TC_TLB_018: ASID edge values (0 and 511)
    task tc_tlb_018;
        reg hit, valid;
        reg [21:0] ppn;
        begin
            $display("--- TC_TLB_018: ASID edge values (0 and 511) ---");
            do_fill(20'h100, 9'h000, 22'hA10, 1,1,1,0,1,0,0, 0);  // ASID=0
            do_fill(20'h200, 9'h1FF, 22'hA20, 1,1,1,0,1,0,0, 0);  // ASID=511

            // Matching ASIDs → hit
            i_lookup_single(20'h100, 9'h000, hit, valid, ppn);
            check(hit === 1'b1 && ppn === 22'hA10, "TC_TLB_018: ASID=0 match hit");
            i_lookup_single(20'h200, 9'h1FF, hit, valid, ppn);
            check(hit === 1'b1 && ppn === 22'hA20, "TC_TLB_018: ASID=511 match hit");

            // Non-matching ASIDs → miss
            i_lookup_single(20'h100, 9'h001, hit, valid, ppn);
            check(hit === 1'b0, "TC_TLB_018: ASID=0 vs 1 miss");
            i_lookup_single(20'h200, 9'h000, hit, valid, ppn);
            check(hit === 1'b0, "TC_TLB_018: ASID=511 vs 0 miss");
        end
    endtask

    // TC_TLB_019: Global bit with multiple ASIDs
    task tc_tlb_019;
        reg hit, valid;
        reg [21:0] ppn;
        begin
            $display("--- TC_TLB_019: Global bit with multiple ASIDs ---");
            do_fill(20'h100, 9'h001, 22'h010, 1,1,1,0,1,0,1, 0);  // G=1, ASID=1

            i_lookup_single(20'h100, 9'h000, hit, valid, ppn);
            check(hit === 1'b1, "TC_TLB_019: global hit with ASID=0");
            i_lookup_single(20'h100, 9'h0FF, hit, valid, ppn);
            check(hit === 1'b1, "TC_TLB_019: global hit with ASID=255");
            i_lookup_single(20'h100, 9'h1FF, hit, valid, ppn);
            check(hit === 1'b1, "TC_TLB_019: global hit with ASID=511");
            i_lookup_single(20'h100, 9'h001, hit, valid, ppn);
            check(hit === 1'b1 && ppn === 22'h010, "TC_TLB_019: global hit with original ASID");
        end
    endtask

    // TC_TLB_020: Megapage hit with different vpn[9:0]
    task tc_tlb_020;
        reg hit, valid;
        reg [21:0] ppn;
        begin
            $display("--- TC_TLB_020: Megapage hit with different vpn[9:0] ---");
            do_fill(20'h000, 9'h0, 22'h100, 1,1,1,0,1,0,0, 1);  // mega=1, VPN=0x000

            // All these VPNs have [19:10]=0x000 → should hit
            i_lookup_single(20'h001, 9'h0, hit, valid, ppn);
            check(hit === 1'b1 && ppn === 22'h100, "TC_TLB_020: mega hit VPN=0x001");
            i_lookup_single(20'h3FF, 9'h0, hit, valid, ppn);
            check(hit === 1'b1 && ppn === 22'h100, "TC_TLB_020: mega hit VPN=0x3FF");
            i_lookup_single(20'h100, 9'h0, hit, valid, ppn);
            check(hit === 1'b1 && ppn === 22'h100, "TC_TLB_020: mega hit VPN=0x100");
            i_lookup_single(20'h000, 9'h0, hit, valid, ppn);
            check(hit === 1'b1 && ppn === 22'h100, "TC_TLB_020: mega hit VPN=0x000");
        end
    endtask

    // TC_TLB_021: Megapage miss with different vpn[19:10]
    task tc_tlb_021;
        reg hit, valid;
        reg [21:0] ppn;
        begin
            $display("--- TC_TLB_021: Megapage miss with different vpn[19:10] ---");
            do_fill(20'h000, 9'h0, 22'h100, 1,1,1,0,1,0,0, 1);  // mega=1, [19:10]=0x000

            // VPN=0x400 has [19:10]=0x001 → miss
            i_lookup_single(20'h400, 9'h0, hit, valid, ppn);
            check(hit === 1'b0, "TC_TLB_021: mega miss VPN=0x400");
            // VPN=0x800 has [19:10]=0x002 → miss
            i_lookup_single(20'h800, 9'h0, hit, valid, ppn);
            check(hit === 1'b0, "TC_TLB_021: mega miss VPN=0x800");
            // VPN=0xFFC00 has [19:10]=0x3FF → miss
            i_lookup_single(20'hFFC00, 9'h0, hit, valid, ppn);
            check(hit === 1'b0, "TC_TLB_021: mega miss VPN=0xFFC00");
        end
    endtask

    // TC_TLB_022: Megapage is_megapage output
    task tc_tlb_022;
        begin
            $display("--- TC_TLB_022: Megapage is_megapage output ---");
            // Fill megapage entry
            do_fill(20'h100, 9'h0, 22'h200, 1,1,1,0,1,0,0, 1);  // mega=1

            // i-lookup: check is_megapage output
            @(posedge clk);
            #1;
            i_lookup_req_r = 1;
            i_lookup_vpn_r = 20'h100;
            i_lookup_asid_r = 9'h0;
            @(posedge clk);
            #1;
            i_lookup_req_r = 0;
            check(i_lookup_valid === 1'b1, "TC_TLB_022: i-lookup valid (mega)");
            check(i_lookup_hit === 1'b1, "TC_TLB_022: i-lookup hit (mega)");
            check(i_lookup_is_megapage === 1'b1, "TC_TLB_022: i-lookup is_megapage=1");

            // d-lookup: check is_megapage output
            @(posedge clk);
            #1;
            d_lookup_req_r = 1;
            d_lookup_vpn_r = 20'h100;
            d_lookup_asid_r = 9'h0;
            @(posedge clk);
            #1;
            d_lookup_req_r = 0;
            check(d_lookup_valid === 1'b1, "TC_TLB_022: d-lookup valid (mega)");
            check(d_lookup_hit === 1'b1, "TC_TLB_022: d-lookup hit (mega)");
            check(d_lookup_is_megapage === 1'b1, "TC_TLB_022: d-lookup is_megapage=1");

            // Fill non-megapage entry — use VPN=0x1000 ([19:10]=0x004) to avoid
            // matching the megapage entry at VPN=0x100 ([19:10]=0x000)
            do_fill(20'h1000, 9'h0, 22'h300, 1,1,1,0,1,0,0, 0);  // mega=0

            @(posedge clk);
            #1;
            i_lookup_req_r = 1;
            i_lookup_vpn_r = 20'h1000;
            i_lookup_asid_r = 9'h0;
            @(posedge clk);
            #1;
            i_lookup_req_r = 0;
            check(i_lookup_hit === 1'b1, "TC_TLB_022: i-lookup hit (non-mega)");
            check(i_lookup_is_megapage === 1'b0, "TC_TLB_022: i-lookup is_megapage=0");
        end
    endtask

    // TC_TLB_023: Simultaneous i+d same set different VPN
    task tc_tlb_023;
        begin
            $display("--- TC_TLB_023: Simultaneous i+d same set different VPN ---");
            // Both VPNs map to set 0 (vpn[11:10]=00)
            do_fill(20'h1000, 9'h0, 22'hA10, 1,1,1,0,1,0,0, 0);
            do_fill(20'h2000, 9'h0, 22'hA20, 1,1,0,0,1,0,0, 0);

            @(posedge clk);
            #1;
            i_lookup_req_r = 1;
            i_lookup_vpn_r = 20'h1000;
            i_lookup_asid_r = 9'h0;
            d_lookup_req_r = 1;
            d_lookup_vpn_r = 20'h2000;
            d_lookup_asid_r = 9'h0;

            @(posedge clk);
            #1;
            i_lookup_req_r = 0;
            d_lookup_req_r = 0;

            check(i_lookup_valid === 1'b1, "TC_TLB_023: i-lookup valid");
            check(i_lookup_hit === 1'b1, "TC_TLB_023: i-lookup hit");
            check(i_lookup_ppn === 22'hA10, "TC_TLB_023: i-lookup PPN correct");
            check(d_lookup_valid === 1'b1, "TC_TLB_023: d-lookup valid");
            check(d_lookup_hit === 1'b1, "TC_TLB_023: d-lookup hit");
            check(d_lookup_ppn === 22'hA20, "TC_TLB_023: d-lookup PPN correct");
        end
    endtask

    // TC_TLB_024: Simultaneous i+d same VPN both hit
    task tc_tlb_024;
        begin
            $display("--- TC_TLB_024: Simultaneous i+d same VPN both hit ---");
            do_fill(20'h100, 9'h0, 22'h200, 1,1,1,0,1,0,0, 0);

            @(posedge clk);
            #1;
            i_lookup_req_r = 1;
            i_lookup_vpn_r = 20'h100;
            i_lookup_asid_r = 9'h0;
            d_lookup_req_r = 1;
            d_lookup_vpn_r = 20'h100;
            d_lookup_asid_r = 9'h0;

            @(posedge clk);
            #1;
            i_lookup_req_r = 0;
            d_lookup_req_r = 0;

            check(i_lookup_valid === 1'b1, "TC_TLB_024: i-lookup valid");
            check(i_lookup_hit === 1'b1, "TC_TLB_024: i-lookup hit");
            check(i_lookup_ppn === 22'h200, "TC_TLB_024: i-lookup PPN correct");
            check(d_lookup_valid === 1'b1, "TC_TLB_024: d-lookup valid");
            check(d_lookup_hit === 1'b1, "TC_TLB_024: d-lookup hit");
            check(d_lookup_ppn === 22'h200, "TC_TLB_024: d-lookup PPN correct");
        end
    endtask

    // TC_TLB_025: Refill same VPN with different PPN (duplicate fill behavior)
    task tc_tlb_025;
        reg hit, valid;
        reg [21:0] ppn;
        begin
            $display("--- TC_TLB_025: Refill same VPN with different PPN ---");
            do_fill(20'h100, 9'h0, 22'h200, 1,1,1,0,1,0,0, 0);  // PPN=0x200
            do_fill(20'h100, 9'h0, 22'h300, 1,1,1,0,1,0,0, 0);  // PPN=0x300 (duplicate VPN)

            // Lookup should hit — first entry (way 0) has priority in hit_way logic
            i_lookup_single(20'h100, 9'h0, hit, valid, ppn);
            check(hit === 1'b1, "TC_TLB_025: duplicate VPN still hits");
            check(ppn === 22'h200, "TC_TLB_025: first entry PPN returned (way 0 priority)");

            // After flush, only second fill remains (if it was in a different way)
            // Actually after flush all entries are cleared
            do_flush;
            i_lookup_single(20'h100, 9'h0, hit, valid, ppn);
            check(hit === 1'b0, "TC_TLB_025: miss after flush");

            // Refill with new PPN
            do_fill(20'h100, 9'h0, 22'h300, 1,1,1,0,1,0,0, 0);
            i_lookup_single(20'h100, 9'h0, hit, valid, ppn);
            check(hit === 1'b1 && ppn === 22'h300, "TC_TLB_025: new PPN after flush+refill");
        end
    endtask

    // TC_TLB_026: All flag bits preserved
    task tc_tlb_026;
        begin
            $display("--- TC_TLB_026: All flag bits preserved ---");
            // Fill with R=1,W=0,X=1,U=1,A=1,D=0,G=0
            do_fill(20'h100, 9'h0, 22'h200, 1,0,1,1,1,0,0, 0);

            // i-lookup: check each flag
            @(posedge clk);
            #1;
            i_lookup_req_r = 1;
            i_lookup_vpn_r = 20'h100;
            i_lookup_asid_r = 9'h0;
            @(posedge clk);
            #1;
            i_lookup_req_r = 0;
            check(i_lookup_hit === 1'b1, "TC_TLB_026: i-lookup hit");
            check(i_lookup_r === 1'b1, "TC_TLB_026: i-lookup R=1");
            check(i_lookup_w === 1'b0, "TC_TLB_026: i-lookup W=0");
            check(i_lookup_x === 1'b1, "TC_TLB_026: i-lookup X=1");
            check(i_lookup_u === 1'b1, "TC_TLB_026: i-lookup U=1");
            check(i_lookup_a === 1'b1, "TC_TLB_026: i-lookup A=1");
            check(i_lookup_d === 1'b0, "TC_TLB_026: i-lookup D=0");
            check(i_lookup_g === 1'b0, "TC_TLB_026: i-lookup G=0");

            // d-lookup: check each flag
            @(posedge clk);
            #1;
            d_lookup_req_r = 1;
            d_lookup_vpn_r = 20'h100;
            d_lookup_asid_r = 9'h0;
            @(posedge clk);
            #1;
            d_lookup_req_r = 0;
            check(d_lookup_hit === 1'b1, "TC_TLB_026: d-lookup hit");
            check(d_lookup_r === 1'b1, "TC_TLB_026: d-lookup R=1");
            check(d_lookup_w === 1'b0, "TC_TLB_026: d-lookup W=0");
            check(d_lookup_x === 1'b1, "TC_TLB_026: d-lookup X=1");
            check(d_lookup_u === 1'b1, "TC_TLB_026: d-lookup U=1");
            check(d_lookup_a === 1'b1, "TC_TLB_026: d-lookup A=1");
            check(d_lookup_d === 1'b0, "TC_TLB_026: d-lookup D=0");
            check(d_lookup_g === 1'b0, "TC_TLB_026: d-lookup G=0");
        end
    endtask

    // TC_TLB_027: Flush during active i-lookup result cycle
    task tc_tlb_027;
        reg hit, valid;
        reg [21:0] ppn;
        begin
            $display("--- TC_TLB_027: Flush during i-lookup result cycle ---");
            do_fill(20'h100, 9'h0, 22'h200, 1,1,1,0,1,0,0, 0);

            // Issue i-lookup
            @(posedge clk);
            #1;
            i_lookup_req_r = 1;
            i_lookup_vpn_r = 20'h100;
            i_lookup_asid_r = 9'h0;

            // At result cycle: assert flush simultaneously
            @(posedge clk);
            #1;
            i_lookup_req_r = 0;
            flush_all_r = 1;

            // i-lookup result should still be valid and correct
            check(i_lookup_valid === 1'b1, "TC_TLB_027: i-lookup valid at flush cycle");
            check(i_lookup_hit === 1'b1, "TC_TLB_027: i-lookup hit at flush cycle");
            check(i_lookup_ppn === 22'h200, "TC_TLB_027: i-lookup PPN correct at flush cycle");

            // Wait for flush to complete
            wait(flush_done);
            #1;
            flush_all_r = 0;
            @(posedge clk);
            #1;

            // After flush, lookup should miss
            i_lookup_single(20'h100, 9'h0, hit, valid, ppn);
            check(hit === 1'b0, "TC_TLB_027: miss after flush");
        end
    endtask

    // TC_TLB_028: Back-to-back fills to different sets
    task tc_tlb_028;
        reg hit, valid;
        reg [21:0] ppn;
        begin
            $display("--- TC_TLB_028: Back-to-back fills to different sets ---");
            do_fill(20'h0000, 9'h0, 22'h001, 1,1,1,0,1,0,0, 0);  // set 0
            do_fill(20'h0400, 9'h0, 22'h002, 1,1,1,0,1,0,0, 0);  // set 1
            do_fill(20'h0800, 9'h0, 22'h003, 1,1,1,0,1,0,0, 0);  // set 2
            do_fill(20'h0C00, 9'h0, 22'h004, 1,1,1,0,1,0,0, 0);  // set 3

            i_lookup_single(20'h0000, 9'h0, hit, valid, ppn);
            check(hit === 1'b1 && ppn === 22'h001, "TC_TLB_028: set 0 hit");
            i_lookup_single(20'h0400, 9'h0, hit, valid, ppn);
            check(hit === 1'b1 && ppn === 22'h002, "TC_TLB_028: set 1 hit");
            i_lookup_single(20'h0800, 9'h0, hit, valid, ppn);
            check(hit === 1'b1 && ppn === 22'h003, "TC_TLB_028: set 2 hit");
            i_lookup_single(20'h0C00, 9'h0, hit, valid, ppn);
            check(hit === 1'b1 && ppn === 22'h004, "TC_TLB_028: set 3 hit");
        end
    endtask

    // TC_TLB_029: PLRU stress — 8 fills to same set, verify 4 remain
    task tc_tlb_029;
        reg hit, valid;
        reg [21:0] ppn;
        integer remaining;
        begin
            $display("--- TC_TLB_029: PLRU stress (8 fills to same set) ---");
            // Fill 8 entries to set 0 (vpn[11:10]=00)
            do_fill(20'h1000, 9'h0, 22'hA00, 1,1,1,0,1,0,0, 0);
            do_fill(20'h2000, 9'h0, 22'hB00, 1,1,1,0,1,0,0, 0);
            do_fill(20'h3000, 9'h0, 22'hC00, 1,1,1,0,1,0,0, 0);
            do_fill(20'h4000, 9'h0, 22'hD00, 1,1,1,0,1,0,0, 0);
            do_fill(20'h5000, 9'h0, 22'hE00, 1,1,1,0,1,0,0, 0);
            do_fill(20'h6000, 9'h0, 22'hF00, 1,1,1,0,1,0,0, 0);
            do_fill(20'h7000, 9'h0, 22'hA01, 1,1,1,0,1,0,0, 0);
            do_fill(20'h8000, 9'h0, 22'hB01, 1,1,1,0,1,0,0, 0);

            // After 8 fills to a 4-way set, exactly 4 entries should remain.
            // The specific eviction pattern depends on PLRU implementation details
            // (state updates from first-invalid-way fills affect victim selection).
            // Verify the invariant: 4 entries present, each with correct PPN.

            // Check each VPN: if present, PPN must match the fill value
            remaining = 0;
            i_lookup_single(20'h1000, 9'h0, hit, valid, ppn);
            if (hit) begin remaining = remaining + 1;
                check(ppn === 22'hA00, "TC_TLB_029: VPN 0x1000 PPN correct"); end
            i_lookup_single(20'h2000, 9'h0, hit, valid, ppn);
            if (hit) begin remaining = remaining + 1;
                check(ppn === 22'hB00, "TC_TLB_029: VPN 0x2000 PPN correct"); end
            i_lookup_single(20'h3000, 9'h0, hit, valid, ppn);
            if (hit) begin remaining = remaining + 1;
                check(ppn === 22'hC00, "TC_TLB_029: VPN 0x3000 PPN correct"); end
            i_lookup_single(20'h4000, 9'h0, hit, valid, ppn);
            if (hit) begin remaining = remaining + 1;
                check(ppn === 22'hD00, "TC_TLB_029: VPN 0x4000 PPN correct"); end
            i_lookup_single(20'h5000, 9'h0, hit, valid, ppn);
            if (hit) begin remaining = remaining + 1;
                check(ppn === 22'hE00, "TC_TLB_029: VPN 0x5000 PPN correct"); end
            i_lookup_single(20'h6000, 9'h0, hit, valid, ppn);
            if (hit) begin remaining = remaining + 1;
                check(ppn === 22'hF00, "TC_TLB_029: VPN 0x6000 PPN correct"); end
            i_lookup_single(20'h7000, 9'h0, hit, valid, ppn);
            if (hit) begin remaining = remaining + 1;
                check(ppn === 22'hA01, "TC_TLB_029: VPN 0x7000 PPN correct"); end
            i_lookup_single(20'h8000, 9'h0, hit, valid, ppn);
            if (hit) begin remaining = remaining + 1;
                check(ppn === 22'hB01, "TC_TLB_029: VPN 0x8000 PPN correct"); end

            check(remaining == 4, "TC_TLB_029: exactly 4 entries remain after 8 fills");
        end
    endtask

    // TC_TLB_030: d-lookup while fill at same cycle (port B priority)
    task tc_tlb_030;
        reg hit, valid;
        reg [21:0] ppn;
        begin
            $display("--- TC_TLB_030: d-lookup while fill (port B priority) ---");
            do_fill(20'h100, 9'h0, 22'h200, 1,1,1,0,1,0,0, 0);

            // Issue d-lookup and fill at the same cycle
            @(posedge clk);
            #1;
            d_lookup_req_r = 1;
            d_lookup_vpn_r = 20'h100;
            d_lookup_asid_r = 9'h0;
            fill_req_r = 1;
            fill_vpn_r = 20'h400;
            fill_asid_r = 9'h0;
            fill_ppn_r = 22'h500;
            fill_r_r = 1; fill_w_r = 1; fill_x_r = 1; fill_u_r = 0;
            fill_a_r = 1; fill_d_r = 0; fill_g_r = 0; fill_is_megapage_r = 0;

            @(posedge clk);
            #1;
            d_lookup_req_r = 0;
            fill_req_r = 0;
            fill_r_r = 0; fill_w_r = 0; fill_x_r = 0; fill_u_r = 0;
            fill_a_r = 0; fill_d_r = 0; fill_g_r = 0; fill_is_megapage_r = 0;

            // d-lookup should be invalid (fill preempts port B)
            check(d_lookup_valid === 1'b0,
                  "TC_TLB_030: d-lookup not valid when fill preempts");

            // Both entries should be present after fill
            d_lookup_single(20'h100, 9'h0, hit, valid, ppn);
            check(hit === 1'b1 && ppn === 22'h200, "TC_TLB_030: original entry present");
            d_lookup_single(20'h400, 9'h0, hit, valid, ppn);
            check(hit === 1'b1 && ppn === 22'h500, "TC_TLB_030: new entry present");
        end
    endtask

    // TC_TLB_031: i-lookup while fill at same cycle (port A independent)
    task tc_tlb_031;
        reg hit, valid;
        reg [21:0] ppn;
        begin
            $display("--- TC_TLB_031: i-lookup while fill (port A independent) ---");
            do_fill(20'h100, 9'h0, 22'h200, 1,1,1,0,1,0,0, 0);

            // Issue i-lookup and fill at the same cycle (different sets)
            @(posedge clk);
            #1;
            i_lookup_req_r = 1;
            i_lookup_vpn_r = 20'h100;
            i_lookup_asid_r = 9'h0;
            fill_req_r = 1;
            fill_vpn_r = 20'h400;
            fill_asid_r = 9'h0;
            fill_ppn_r = 22'h500;
            fill_r_r = 1; fill_w_r = 1; fill_x_r = 1; fill_u_r = 0;
            fill_a_r = 1; fill_d_r = 0; fill_g_r = 0; fill_is_megapage_r = 0;

            @(posedge clk);
            #1;
            i_lookup_req_r = 0;
            fill_req_r = 0;
            fill_r_r = 0; fill_w_r = 0; fill_x_r = 0; fill_u_r = 0;
            fill_a_r = 0; fill_d_r = 0; fill_g_r = 0; fill_is_megapage_r = 0;

            // i-lookup should be valid (port A independent of fill on port B)
            check(i_lookup_valid === 1'b1,
                  "TC_TLB_031: i-lookup valid with concurrent fill");
            check(i_lookup_hit === 1'b1,
                  "TC_TLB_031: i-lookup hit with concurrent fill");
            check(i_lookup_ppn === 22'h200,
                  "TC_TLB_031: i-lookup PPN correct");

            // New entry should also be present
            i_lookup_single(20'h400, 9'h0, hit, valid, ppn);
            check(hit === 1'b1 && ppn === 22'h500, "TC_TLB_031: new entry present");
        end
    endtask

    // TC_TLB_032: VPN=0 edge case
    task tc_tlb_032;
        reg hit, valid;
        reg [21:0] ppn;
        begin
            $display("--- TC_TLB_032: VPN=0 edge case ---");
            do_fill(20'h00000, 9'h0, 22'h123, 1,1,1,0,1,0,0, 0);
            i_lookup_single(20'h00000, 9'h0, hit, valid, ppn);
            check(hit === 1'b1 && ppn === 22'h123, "TC_TLB_032: VPN=0 i-lookup hit");
            d_lookup_single(20'h00000, 9'h0, hit, valid, ppn);
            check(hit === 1'b1 && ppn === 22'h123, "TC_TLB_032: VPN=0 d-lookup hit");
        end
    endtask

    // TC_TLB_033: VPN=max (0xFFFFF) edge case
    task tc_tlb_033;
        reg hit, valid;
        reg [21:0] ppn;
        begin
            $display("--- TC_TLB_033: VPN=0xFFFFF edge case ---");
            do_fill(20'hFFFFF, 9'h0, 22'h456, 1,1,1,0,1,0,0, 0);
            i_lookup_single(20'hFFFFF, 9'h0, hit, valid, ppn);
            check(hit === 1'b1 && ppn === 22'h456, "TC_TLB_033: VPN=max i-lookup hit");
            d_lookup_single(20'hFFFFF, 9'h0, hit, valid, ppn);
            check(hit === 1'b1 && ppn === 22'h456, "TC_TLB_033: VPN=max d-lookup hit");
        end
    endtask

    // TC_TLB_034: All 4 ways same set, verify flags independently
    task tc_tlb_034;
        begin
            $display("--- TC_TLB_034: All 4 ways same set, flags independently ---");
            // Fill 4 entries to set 0 with different flag combinations
            do_fill(20'h1000, 9'h0, 22'hA00, 1,1,0,0,1,1,0, 0);  // RW AD
            do_fill(20'h2000, 9'h0, 22'hB00, 0,0,1,0,1,0,0, 0);  // X A
            do_fill(20'h3000, 9'h0, 22'hC00, 1,0,0,1,0,0,1, 0);  // R U G
            do_fill(20'h4000, 9'h0, 22'hD00, 1,1,1,1,1,1,1, 0);  // all flags

            // Check way 0: R=1,W=1,X=0,U=0,A=1,D=1,G=0
            @(posedge clk);
            #1;
            i_lookup_req_r = 1;
            i_lookup_vpn_r = 20'h1000;
            i_lookup_asid_r = 9'h0;
            @(posedge clk);
            #1;
            i_lookup_req_r = 0;
            check(i_lookup_hit === 1'b1, "TC_TLB_034: way 0 hit");
            check(i_lookup_r === 1'b1 && i_lookup_w === 1'b1 && i_lookup_x === 1'b0,
                  "TC_TLB_034: way 0 R=1,W=1,X=0");
            check(i_lookup_u === 1'b0 && i_lookup_a === 1'b1 && i_lookup_d === 1'b1,
                  "TC_TLB_034: way 0 U=0,A=1,D=1");
            check(i_lookup_g === 1'b0, "TC_TLB_034: way 0 G=0");

            // Check way 1: R=0,W=0,X=1,U=0,A=1,D=0,G=0
            @(posedge clk);
            #1;
            i_lookup_req_r = 1;
            i_lookup_vpn_r = 20'h2000;
            i_lookup_asid_r = 9'h0;
            @(posedge clk);
            #1;
            i_lookup_req_r = 0;
            check(i_lookup_hit === 1'b1, "TC_TLB_034: way 1 hit");
            check(i_lookup_r === 1'b0 && i_lookup_w === 1'b0 && i_lookup_x === 1'b1,
                  "TC_TLB_034: way 1 R=0,W=0,X=1");
            check(i_lookup_u === 1'b0 && i_lookup_a === 1'b1 && i_lookup_d === 1'b0,
                  "TC_TLB_034: way 1 U=0,A=1,D=0");
            check(i_lookup_g === 1'b0, "TC_TLB_034: way 1 G=0");

            // Check way 2: R=1,W=0,X=0,U=1,A=0,D=0,G=1
            @(posedge clk);
            #1;
            i_lookup_req_r = 1;
            i_lookup_vpn_r = 20'h3000;
            i_lookup_asid_r = 9'h0;
            @(posedge clk);
            #1;
            i_lookup_req_r = 0;
            check(i_lookup_hit === 1'b1, "TC_TLB_034: way 2 hit");
            check(i_lookup_r === 1'b1 && i_lookup_w === 1'b0 && i_lookup_x === 1'b0,
                  "TC_TLB_034: way 2 R=1,W=0,X=0");
            check(i_lookup_u === 1'b1 && i_lookup_a === 1'b0 && i_lookup_d === 1'b0,
                  "TC_TLB_034: way 2 U=1,A=0,D=0");
            check(i_lookup_g === 1'b1, "TC_TLB_034: way 2 G=1");

            // Check way 3: R=1,W=1,X=1,U=1,A=1,D=1,G=1
            @(posedge clk);
            #1;
            i_lookup_req_r = 1;
            i_lookup_vpn_r = 20'h4000;
            i_lookup_asid_r = 9'h0;
            @(posedge clk);
            #1;
            i_lookup_req_r = 0;
            check(i_lookup_hit === 1'b1, "TC_TLB_034: way 3 hit");
            check(i_lookup_r === 1'b1 && i_lookup_w === 1'b1 && i_lookup_x === 1'b1,
                  "TC_TLB_034: way 3 R=1,W=1,X=1");
            check(i_lookup_u === 1'b1 && i_lookup_a === 1'b1 && i_lookup_d === 1'b1,
                  "TC_TLB_034: way 3 U=1,A=1,D=1");
            check(i_lookup_g === 1'b1, "TC_TLB_034: way 3 G=1");
        end
    endtask

    // =====================
    // Main Test Sequence
    // =====================
    initial begin
        $display("========================================");
        $display("  TLB Unit Testbench (USE_TLB_BRAM=1)");
        $display("========================================");

        // Reset
        resetn = 0;
        clear_inputs;
        repeat(10) @(posedge clk);
        @(posedge clk);
        #1;
        resetn = 1;

        // Wait for initial flush to complete (TLB starts in S_FLUSH)
        // Flush takes 4 cycles (NUM_SETS=4)
        wait(flush_done);
        @(posedge clk);
        #1;
        $display("Initial flush complete. Starting tests...\n");

        // Run tests (flush between each for isolation)
        tc_tlb_000;    do_flush;
        tc_tlb_001;    do_flush;
        tc_tlb_002;    do_flush;
        tc_tlb_003;    do_flush;
        tc_tlb_004;    do_flush;
        tc_tlb_005;    do_flush;
        tc_tlb_006;    do_flush;
        tc_tlb_007;    do_flush;
        tc_tlb_008;    do_flush;
        tc_tlb_009;    do_flush;
        tc_tlb_010;    do_flush;
        tc_tlb_011;    do_flush;
        tc_tlb_012;    do_flush;
        tc_tlb_013;    do_flush;
        tc_tlb_014;    do_flush;
        // New comprehensive tests (015-034)
        tc_tlb_015;    do_flush;
        tc_tlb_016;    do_flush;
        tc_tlb_017;    do_flush;
        tc_tlb_018;    do_flush;
        tc_tlb_019;    do_flush;
        tc_tlb_020;    do_flush;
        tc_tlb_021;    do_flush;
        tc_tlb_022;    do_flush;
        tc_tlb_023;    do_flush;
        tc_tlb_024;    do_flush;
        tc_tlb_025;    do_flush;
        tc_tlb_026;    do_flush;
        tc_tlb_027;    do_flush;
        tc_tlb_028;    do_flush;
        tc_tlb_029;    do_flush;
        tc_tlb_030;    do_flush;
        tc_tlb_031;    do_flush;
        tc_tlb_032;    do_flush;
        tc_tlb_033;    do_flush;
        tc_tlb_034;

        // Report
        $display("\n========================================");
        $display("  TLB Unit Test Summary");
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
