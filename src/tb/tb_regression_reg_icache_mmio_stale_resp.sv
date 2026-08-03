`timescale 1ns / 1ps

module tb_regression_reg_icache_mmio_stale_resp;

    localparam [31:0] ADDR_OLD = 32'hFC00_0000;
    localparam [31:0] ADDR_NEW = 32'hFC00_0004;
    localparam [31:0] DATA_OLD = 32'h0009_8067;
    localparam [31:0] DATA_NEW = 32'h0000_0013;

    reg clk;
    reg resetn;

    reg         cpu_req_valid;
    reg [31:0]  cpu_req_addr;
    reg [31:0]  cpu_req_vaddr;
    reg         mmu_ready;
    reg         flush_req;
    wire [31:0] cpu_req_data;
    wire        cpu_req_ready;

    wire        mmio_req;
    reg         mmio_accept;
    wire [31:0] mmio_addr;
    reg [31:0]  mmio_data;
    reg         mmio_valid;

    wire        refill_req;
    wire [31:0] refill_addr;
    reg  [255:0] refill_data;
    reg         refill_valid;

    reg         invalidate_req;
    wire        invalidate_done;
    wire [2:0]  dbg_state;

    integer pass_count;
    integer fail_count;

    icache_ctrl dut (
        .clk(clk),
        .resetn(resetn),
        .cpu_req_valid(cpu_req_valid),
        .cpu_req_addr(cpu_req_addr),
        .cpu_req_vaddr(cpu_req_vaddr),
        .mmu_ready(mmu_ready),
        .flush_req(flush_req),
        .cpu_req_data(cpu_req_data),
        .cpu_req_ready(cpu_req_ready),
        .mmio_req(mmio_req),
        .mmio_accept(mmio_accept),
        .mmio_addr(mmio_addr),
        .mmio_data(mmio_data),
        .mmio_valid(mmio_valid),
        .refill_req(refill_req),
        .refill_addr(refill_addr),
        .refill_data(refill_data),
        .refill_valid(refill_valid),
        .invalidate_req(invalidate_req),
        .invalidate_done(invalidate_done),
        .dbg_state(dbg_state)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic expect_true;
        input condition;
        input [256*8-1:0] msg;
        begin
            if (condition) begin
                pass_count = pass_count + 1;
                $display("  PASS %0s", msg);
            end else begin
                fail_count = fail_count + 1;
                $display("  FAIL %0s", msg);
            end
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;

        resetn = 1'b0;
        cpu_req_valid = 1'b0;
        cpu_req_addr = 32'b0;
        cpu_req_vaddr = 32'b0;
        mmu_ready = 1'b0;
        flush_req = 1'b0;
        mmio_accept = 1'b0;
        mmio_data = 32'b0;
        mmio_valid = 1'b0;
        refill_data = 256'b0;
        refill_valid = 1'b0;
        invalidate_req = 1'b0;

        repeat (4) @(posedge clk);
        resetn = 1'b1;
        repeat (2) @(posedge clk);

        // Issue first uncached instruction fetch.
        cpu_req_valid = 1'b1;
        cpu_req_addr  = ADDR_OLD;
        cpu_req_vaddr = ADDR_OLD;
        mmu_ready     = 1'b1;
        @(posedge clk);
        expect_true(mmio_req && (mmio_addr == ADDR_OLD), "old MMIO fetch request issued");

        // Bridge accepts old request.
        mmio_accept = 1'b1;
        @(posedge clk);
        mmio_accept = 1'b0;
        expect_true(!mmio_req, "pending request cleared after accept");

        // Redirect to a new PC before old response returns.
        cpu_req_addr  = ADDR_NEW;
        cpu_req_vaddr = ADDR_NEW;
        flush_req     = 1'b1;
        @(posedge clk);
        flush_req     = 1'b0;

        // Late stale response for old PC must be ignored.
        mmio_data  = DATA_OLD;
        mmio_valid = 1'b1;
        @(posedge clk);
        mmio_valid = 1'b0;
        expect_true(!cpu_req_ready, "stale old response not consumed");

        // New request should now be issued for redirected PC.
        @(posedge clk);
        expect_true(mmio_req && (mmio_addr == ADDR_NEW), "new MMIO fetch request issued after redirect");

        // Bridge accepts new request.
        mmio_accept = 1'b1;
        @(posedge clk);
        mmio_accept = 1'b0;

        // Correct new response must be consumed.
        mmio_data  = DATA_NEW;
        mmio_valid = 1'b1;
        @(posedge clk);
        mmio_valid = 1'b0;
        expect_true(cpu_req_ready, "new response consumed");
        expect_true(cpu_req_data == DATA_NEW, "returned instruction matches redirected PC");

        // Reproduce the harder case seen on FPGA: redirect flushes the old
        // uncached request, but the replacement request is not yet re-issued
        // because translation/new request setup is not ready. A late old
        // response must still be discarded.
        cpu_req_valid = 1'b0;
        mmu_ready     = 1'b0;
        repeat (2) @(posedge clk);

        cpu_req_valid = 1'b1;
        cpu_req_addr  = ADDR_OLD;
        cpu_req_vaddr = ADDR_OLD;
        mmu_ready     = 1'b1;
        @(posedge clk);
        expect_true(mmio_req && (mmio_addr == ADDR_OLD), "second old MMIO fetch request issued");

        mmio_accept = 1'b1;
        @(posedge clk);
        mmio_accept = 1'b0;
        expect_true(!mmio_req, "second pending request cleared after accept");

        cpu_req_addr  = ADDR_NEW;
        cpu_req_vaddr = ADDR_NEW;
        mmu_ready     = 1'b0;
        flush_req     = 1'b1;
        @(posedge clk);
        flush_req     = 1'b0;

        mmio_data  = DATA_OLD;
        mmio_valid = 1'b1;
        @(posedge clk);
        mmio_valid = 1'b0;
        expect_true(!cpu_req_ready, "stale old response discarded while replacement request inactive");

        mmu_ready = 1'b1;
        @(posedge clk);
        expect_true(mmio_req && (mmio_addr == ADDR_NEW), "replacement MMIO fetch re-issued after stale discard");

        mmio_accept = 1'b1;
        @(posedge clk);
        mmio_accept = 1'b0;

        mmio_data  = DATA_NEW;
        mmio_valid = 1'b1;
        @(posedge clk);
        mmio_valid = 1'b0;
        expect_true(cpu_req_ready, "replacement response consumed after inactive-window discard");
        expect_true(cpu_req_data == DATA_NEW, "replacement instruction matches redirected PC after inactive-window discard");

        $display("");
        $display("========================================");
        $display("Regression icache_mmio_stale_resp summary");
        $display("pass=%0d fail=%0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED");
        $display("========================================");
        $finish;
    end

endmodule
