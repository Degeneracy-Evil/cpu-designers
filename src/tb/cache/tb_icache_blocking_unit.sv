`timescale 1ns / 1ps

module tb_icache_blocking_unit;
    reg clk = 1'b0;
    reg resetn = 1'b0;
    always #5 clk = ~clk;

    reg cpu_req_valid;
    reg [31:0] cpu_req_addr;
    reg [31:0] cpu_req_vaddr;
    reg mmu_ready;
    reg flush_req;
    wire [31:0] cpu_req_data;
    wire cpu_req_ready;
    wire mmio_req;
    reg mmio_accept;
    wire [31:0] mmio_addr;
    reg [31:0] mmio_data;
    reg mmio_valid;
    wire refill_req;
    wire [31:0] refill_addr;
    reg [255:0] refill_data;
    reg refill_valid;
    reg refill_done;
    reg refill_error;
    reg invalidate_req;
    wire invalidate_done;

    icache_ctrl dut (
        .clk(clk), .resetn(resetn),
        .cpu_req_valid(cpu_req_valid), .cpu_req_addr(cpu_req_addr),
        .cpu_req_vaddr(cpu_req_vaddr), .mmu_ready(mmu_ready),
        .flush_req(flush_req), .cpu_req_data(cpu_req_data),
        .cpu_req_ready(cpu_req_ready),
        .mmio_req(mmio_req), .mmio_accept(mmio_accept),
        .mmio_addr(mmio_addr), .mmio_data(mmio_data),
        .mmio_valid(mmio_valid),
        .refill_req(refill_req), .refill_addr(refill_addr),
        .refill_data(refill_data), .refill_valid(refill_valid),
        .refill_done(refill_done), .refill_error(refill_error),
        .invalidate_req(invalidate_req), .invalidate_done(invalidate_done),
        .dbg_state()
    );

    integer pass_count;
    integer fail_count;
    integer refill_count;
    integer mmio_count;
    integer i;

    function [31:0] line_word;
        input [31:0] base;
        input [2:0] word_index;
        begin
            line_word = base ^ 32'h1357_9BDF ^ {27'b0, word_index, 2'b0};
        end
    endfunction

    reg refill_busy;
    reg refill_block;
    reg refill_fail_next;
    integer refill_delay;
    reg [31:0] refill_addr_r;
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            refill_data <= 0;
            refill_valid <= 0;
            refill_done <= 0;
            refill_error <= 0;
            refill_busy <= 0;
            refill_block <= 0;
            refill_delay <= 0;
            refill_addr_r <= 0;
            refill_count <= 0;
        end else begin
            refill_valid <= 0;
            refill_done <= 0;
            refill_error <= 0;
            if (!refill_req)
                refill_block <= 0;
            if (refill_req && !refill_busy && !refill_block) begin
                refill_busy <= 1;
                refill_addr_r <= refill_addr;
                refill_delay <= 8;
                refill_count <= refill_count + 1;
            end else if (refill_busy) begin
                if (refill_delay != 0)
                    refill_delay <= refill_delay - 1;
                else begin
                    for (i = 0; i < 8; i = i + 1)
                        refill_data[i*32 +: 32] <= line_word(refill_addr_r, i[2:0]);
                    refill_valid <= !refill_fail_next;
                    refill_done <= 1;
                    refill_error <= refill_fail_next;
                    refill_busy <= 0;
                    refill_block <= 1;
                end
            end
        end
    end

    reg mmio_busy;
    reg mmio_block;
    integer mmio_delay;
    reg [31:0] mmio_addr_r;
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            mmio_accept <= 0;
            mmio_data <= 0;
            mmio_valid <= 0;
            mmio_busy <= 0;
            mmio_block <= 0;
            mmio_delay <= 0;
            mmio_addr_r <= 0;
            mmio_count <= 0;
        end else begin
            mmio_accept <= 0;
            mmio_valid <= 0;
            if (!mmio_req)
                mmio_block <= 0;
            if (mmio_req && !mmio_busy && !mmio_block) begin
                mmio_accept <= 1;
                mmio_busy <= 1;
                mmio_addr_r <= mmio_addr;
                mmio_delay <= 6;
                mmio_count <= mmio_count + 1;
            end else if (mmio_busy) begin
                if (mmio_delay != 0)
                    mmio_delay <= mmio_delay - 1;
                else begin
                    mmio_data <= mmio_addr_r ^ 32'hCAFE_0000;
                    mmio_valid <= 1;
                    mmio_busy <= 0;
                    mmio_block <= 1;
                end
            end
        end
    end

    task check;
        input condition;
        input [8*72-1:0] name;
        begin
            if (condition) begin
                pass_count = pass_count + 1;
                $display("  PASS %0s", name);
            end else begin
                fail_count = fail_count + 1;
                $display("  FAIL %0s", name);
            end
        end
    endtask

    task fetch;
        input [31:0] addr;
        output [31:0] data;
        begin
            @(negedge clk);
            cpu_req_addr = addr;
            cpu_req_vaddr = addr;
            cpu_req_valid = 1;
            while (!cpu_req_ready) begin
                @(posedge clk);
                #1;
            end
            data = cpu_req_data;
            @(negedge clk);
            cpu_req_valid = 0;
            repeat (2) @(posedge clk);
        end
    endtask

    localparam [31:0] ADDR_A = 32'h8000_1004;
    localparam [31:0] ADDR_B = 32'h8000_1108;
    localparam [31:0] ADDR_C = 32'h8000_120C;
    localparam [31:0] ADDR_D = 32'h8000_1310;
    localparam [31:0] ADDR_E = 32'h8000_1414;
    localparam [31:0] ADDR_F = 32'h8000_1518;
    localparam [31:0] ADDR_ERROR = 32'h8000_161C;
    localparam [31:0] MMIO_A = 32'hFC00_0020;
    localparam [31:0] MMIO_B = 32'hFC00_0040;
    reg [31:0] value;
    integer count_before;
    reg stale_ready_seen;

    initial begin
        cpu_req_valid = 0;
        cpu_req_addr = 0;
        cpu_req_vaddr = 0;
        mmu_ready = 1;
        flush_req = 0;
        invalidate_req = 0;
        pass_count = 0;
        fail_count = 0;
        stale_ready_seen = 0;
        refill_fail_next = 0;

        repeat (5) @(posedge clk);
        @(negedge clk);
        resetn = 1;
        repeat (3) @(posedge clk);

        fetch(ADDR_A, value);
        check(value == line_word({ADDR_A[31:5], 5'b0}, ADDR_A[4:2]) && refill_count == 1,
              "first fetch refills way 0");
        fetch(ADDR_B, value);
        check(refill_count == 2 && dut.valid_array[0][0] && dut.valid_array[0][1],
              "second same-set tag refills way 1");
        count_before = refill_count;
        fetch(ADDR_A, value);
        check(refill_count == count_before,
              "two-way entry remains a hit");
        fetch(ADDR_C, value);
        check(refill_count == count_before + 1,
              "third same-set tag replaces exactly one way");

        // Redirect while an accepted refill is delayed. The old line may fill,
        // but only the new fetch is allowed to assert cpu_req_ready.
        @(negedge clk);
        cpu_req_addr = ADDR_D;
        cpu_req_vaddr = ADDR_D;
        cpu_req_valid = 1;
        while (!refill_busy) @(posedge clk);
        @(negedge clk);
        cpu_req_addr = ADDR_E;
        cpu_req_vaddr = ADDR_E;
        stale_ready_seen = 0;
        while (!cpu_req_ready) begin
            @(posedge clk);
            #1;
            if (cpu_req_ready && (cpu_req_data != line_word({ADDR_E[31:5], 5'b0}, ADDR_E[4:2])))
                stale_ready_seen = 1;
        end
        value = cpu_req_data;
        @(negedge clk);
        cpu_req_valid = 0;
        repeat (2) @(posedge clk);
        check(!stale_ready_seen && value == line_word({ADDR_E[31:5], 5'b0}, ADDR_E[4:2]),
              "redirect drains old refill and returns only the new address");

        // A flush during refill marks the architectural result stale but does
        // not cancel the refill. The same live address is then served as a hit.
        count_before = refill_count;
        @(negedge clk);
        cpu_req_addr = ADDR_F;
        cpu_req_vaddr = ADDR_F;
        cpu_req_valid = 1;
        while (!refill_busy) @(posedge clk);
        @(negedge clk);
        flush_req = 1;
        @(negedge clk);
        flush_req = 0;
        while (!cpu_req_ready) begin
            @(posedge clk);
            #1;
        end
        value = cpu_req_data;
        @(negedge clk);
        cpu_req_valid = 0;
        repeat (2) @(posedge clk);
        check(refill_count == count_before + 1 &&
              value == line_word({ADDR_F[31:5], 5'b0}, ADDR_F[4:2]),
              "flush does not cancel an accepted refill");

        @(negedge clk);
        invalidate_req = 1;
        while (!invalidate_done) begin
            @(posedge clk);
            #1;
        end
        @(negedge clk);
        invalidate_req = 0;
        count_before = refill_count;
        fetch(ADDR_A, value);
        check(refill_count == count_before + 1,
              "fence-style invalidate clears every set");

        // The same ownership rule also applies to uncached instruction reads.
        @(negedge clk);
        cpu_req_addr = MMIO_A;
        cpu_req_vaddr = MMIO_A;
        cpu_req_valid = 1;
        while (!mmio_busy) @(posedge clk);
        @(negedge clk);
        cpu_req_addr = MMIO_B;
        cpu_req_vaddr = MMIO_B;
        while (!cpu_req_ready) begin
            @(posedge clk);
            #1;
        end
        value = cpu_req_data;
        @(negedge clk);
        cpu_req_valid = 0;
        check(mmio_count == 2 && value == (MMIO_B ^ 32'hCAFE_0000),
              "MMIO redirect discards the old response by latched ownership");

        // An errored refill must terminate the blocking transaction without
        // installing a valid line or returning stale instruction data.
        count_before = refill_count;
        refill_fail_next = 1;
        @(negedge clk);
        cpu_req_addr = ADDR_ERROR;
        cpu_req_vaddr = ADDR_ERROR;
        cpu_req_valid = 1;
        while (!refill_busy) @(posedge clk);
        while (!refill_done) begin
            @(posedge clk);
            #1;
        end
        @(negedge clk);
        cpu_req_valid = 0;
        refill_fail_next = 0;
        @(posedge clk);
        #1;
        check(!cpu_req_ready && (dut.state == 3'd0) &&
              (refill_count == count_before + 1),
              "refill error drains without returning instruction data");
        fetch(ADDR_ERROR, value);
        check((refill_count == count_before + 2) &&
              (value == line_word({ADDR_ERROR[31:5], 5'b0}, ADDR_ERROR[4:2])),
              "refill error does not install a cache line");

        $display("icache blocking unit: pass=%0d fail=%0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED");
        $finish;
    end

    initial begin
        repeat (8000) @(posedge clk);
        $display("TEST FAILED: timeout");
        $finish;
    end
endmodule
