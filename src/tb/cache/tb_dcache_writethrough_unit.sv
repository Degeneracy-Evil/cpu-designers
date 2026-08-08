`timescale 1ns / 1ps
`include "axi4_def.svh"

module tb_dcache_writethrough_unit;
    reg clk = 1'b0;
    reg resetn = 1'b0;
    always #5 clk = ~clk;

    reg cpu_req_valid;
    reg [31:0] cpu_req_addr;
    reg [31:0] cpu_req_vaddr;
    reg mmu_ready;
    reg [31:0] cpu_req_wdata;
    reg cpu_req_hwrite;
    reg [2:0] cpu_req_hsize;
    wire [31:0] cpu_req_rdata;
    wire cpu_req_ready;
    wire mmio_req;
    reg mmio_accept;
    wire [31:0] mmio_addr;
    wire [31:0] mmio_wdata;
    wire mmio_hwrite;
    wire [2:0] mmio_hsize;
    reg [31:0] mmio_rdata;
    reg mmio_valid;
    reg mmio_error;
    wire refill_req;
    wire [31:0] refill_addr;
    reg [255:0] refill_data;
    reg refill_valid;
    reg refill_done;
    reg refill_error;

    dcache_ctrl dut (
        .clk(clk), .resetn(resetn),
        .cpu_req_valid(cpu_req_valid), .cpu_req_addr(cpu_req_addr),
        .cpu_req_vaddr(cpu_req_vaddr), .mmu_ready(mmu_ready),
        .cpu_req_wdata(cpu_req_wdata), .cpu_req_hwrite(cpu_req_hwrite),
        .cpu_req_hsize(cpu_req_hsize), .cpu_req_rdata(cpu_req_rdata),
        .cpu_req_ready(cpu_req_ready),
        .mmio_req(mmio_req), .mmio_accept(mmio_accept),
        .mmio_addr(mmio_addr), .mmio_wdata(mmio_wdata),
        .mmio_hwrite(mmio_hwrite), .mmio_hsize(mmio_hsize),
        .mmio_rdata(mmio_rdata), .mmio_valid(mmio_valid),
        .mmio_error(mmio_error),
        .refill_req(refill_req), .refill_addr(refill_addr),
        .refill_data(refill_data), .refill_valid(refill_valid),
        .refill_done(refill_done), .refill_error(refill_error),
        .snoop_write_valid(1'b0), .snoop_write_addr(32'b0),
        .snoop_write_data(32'b0),
        .dbg_watch_lh_valid(), .dbg_watch_lh_data(),
        .dbg_watch_lh_count(), .dbg_watch_rf_valid(),
        .dbg_watch_rf_data(), .dbg_watch_rf_count(),
        .dbg_watch_wb_valid(), .dbg_watch_wb_data(),
        .dbg_watch_wb_count()
    );

    reg [31:0] memory [0:1023];
    integer pass_count;
    integer fail_count;
    integer refill_count;
    integer i;

    reg mmio_busy;
    reg mmio_block;
    integer mmio_delay;
    reg [31:0] mmio_addr_r;
    reg [31:0] mmio_wdata_r;
    reg mmio_write_r;
    reg [2:0] mmio_size_r;

    reg refill_busy;
    reg refill_block;
    integer refill_delay;
    reg [31:0] refill_addr_r;

    task write_memory;
        input [31:0] addr;
        input [31:0] data;
        input [2:0] size;
        reg [31:0] old_word;
        begin
            old_word = memory[addr[11:2]];
            case (size)
                `AXI_SIZE_BYTE: begin
                    case (addr[1:0])
                        2'd0: old_word[7:0]   = data[7:0];
                        2'd1: old_word[15:8]  = data[7:0];
                        2'd2: old_word[23:16] = data[7:0];
                        2'd3: old_word[31:24] = data[7:0];
                    endcase
                end
                `AXI_SIZE_HWORD: begin
                    if (addr[1]) old_word[31:16] = data[31:16];
                    else         old_word[15:0]  = data[15:0];
                end
                default: old_word = data;
            endcase
            memory[addr[11:2]] = old_word;
        end
    endtask

    // Delayed single-beat write/read responder used by the DCache bypass port.
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            mmio_accept <= 1'b0;
            mmio_valid <= 1'b0;
            mmio_error <= 1'b0;
            mmio_rdata <= 32'b0;
            mmio_busy <= 1'b0;
            mmio_block <= 1'b0;
            mmio_delay <= 0;
            mmio_addr_r <= 0;
            mmio_wdata_r <= 0;
            mmio_write_r <= 0;
            mmio_size_r <= 0;
        end else begin
            mmio_accept <= 1'b0;
            mmio_valid <= 1'b0;
            if (!mmio_req)
                mmio_block <= 1'b0;
            if (mmio_req && !mmio_busy && !mmio_block) begin
                mmio_accept <= 1'b1;
                mmio_busy <= 1'b1;
                mmio_addr_r <= mmio_addr;
                mmio_wdata_r <= mmio_wdata;
                mmio_write_r <= mmio_hwrite;
                mmio_size_r <= mmio_hsize;
                mmio_delay <= 3;
            end else if (mmio_busy) begin
                if (mmio_delay != 0)
                    mmio_delay <= mmio_delay - 1;
                else begin
                    if (mmio_write_r)
                        write_memory(mmio_addr_r, mmio_wdata_r, mmio_size_r);
                    mmio_rdata <= memory[mmio_addr_r[11:2]];
                    mmio_valid <= 1'b1;
                    mmio_busy <= 1'b0;
                    mmio_block <= 1'b1;
                end
            end
        end
    end

    // Delayed 8-beat-equivalent line responder. The compatibility interface
    // returns the assembled line in one pulse after the artificial delay.
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            refill_data <= 256'b0;
            refill_valid <= 1'b0;
            refill_done <= 1'b0;
            refill_error <= 1'b0;
            refill_busy <= 1'b0;
            refill_block <= 1'b0;
            refill_delay <= 0;
            refill_addr_r <= 0;
            refill_count <= 0;
        end else begin
            refill_valid <= 1'b0;
            refill_done <= 1'b0;
            if (!refill_req)
                refill_block <= 1'b0;
            if (refill_req && !refill_busy && !refill_block) begin
                refill_busy <= 1'b1;
                refill_addr_r <= refill_addr;
                refill_delay <= 5;
                refill_count <= refill_count + 1;
            end else if (refill_busy) begin
                if (refill_delay != 0)
                    refill_delay <= refill_delay - 1;
                else begin
                    for (i = 0; i < 8; i = i + 1)
                        refill_data[i*32 +: 32] <= memory[(refill_addr_r[11:2] + i) & 10'h3ff];
                    refill_valid <= 1'b1;
                    refill_done <= 1'b1;
                    refill_busy <= 1'b0;
                    refill_block <= 1'b1;
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

    task cpu_access;
        input [31:0] addr;
        input write_en;
        input [2:0] size;
        input [31:0] wdata_in;
        output [31:0] rdata_out;
        begin
            @(posedge clk);
            cpu_req_addr = addr;
            cpu_req_vaddr = addr;
            cpu_req_hwrite = write_en;
            cpu_req_hsize = size;
            cpu_req_wdata = wdata_in;
            cpu_req_valid = 1'b1;
            while (!cpu_req_ready) begin
                @(posedge clk);
                #1;
            end
            rdata_out = cpu_req_rdata;
            @(posedge clk);
            cpu_req_valid = 1'b0;
            cpu_req_hwrite = 1'b0;
            repeat (2) @(posedge clk);
        end
    endtask

    localparam [31:0] ADDR_A = 32'h8000_1000;
    localparam [31:0] ADDR_B = 32'h8000_1100;
    localparam [31:0] ADDR_C = 32'h8000_1200;
    localparam [31:0] ADDR_D = 32'h8000_1300;
    reg [31:0] value;
    integer refills_before;

    initial begin
        cpu_req_valid = 0;
        cpu_req_addr = 0;
        cpu_req_vaddr = 0;
        mmu_ready = 1;
        cpu_req_wdata = 0;
        cpu_req_hwrite = 0;
        cpu_req_hsize = `AXI_SIZE_WORD;
        pass_count = 0;
        fail_count = 0;
        for (i = 0; i < 1024; i = i + 1)
            memory[i] = 32'h6000_0000 + i;

        repeat (5) @(posedge clk);
        resetn = 1'b1;
        repeat (3) @(posedge clk);

        cpu_access(ADDR_A, 1'b1, `AXI_SIZE_WORD, 32'hDEAD_BEEF, value);
        check(memory[ADDR_A[11:2]] == 32'hDEAD_BEEF,
              "store miss commits to backing memory");
        check(!dut.valid_array[0][0] && !dut.valid_array[0][1],
              "store miss does not allocate a cache way");

        cpu_access(ADDR_A, 1'b0, `AXI_SIZE_WORD, 0, value);
        check(value == 32'hDEAD_BEEF && refill_count == 1,
              "first load miss refills way 0");
        cpu_access(ADDR_B, 1'b0, `AXI_SIZE_WORD, 0, value);
        check(refill_count == 2 && dut.valid_array[0][0] && dut.valid_array[0][1],
              "second same-set tag fills way 1");

        refills_before = refill_count;
        cpu_access(ADDR_A, 1'b0, `AXI_SIZE_WORD, 0, value);
        check(value == 32'hDEAD_BEEF && refill_count == refills_before,
              "way 0 remains a load hit");
        cpu_access(ADDR_C, 1'b0, `AXI_SIZE_WORD, 0, value);
        check(refill_count == refills_before + 1,
              "third same-set tag replaces exactly one way");

        refills_before = refill_count;
        cpu_access(ADDR_A, 1'b1, `AXI_SIZE_WORD, 32'h1234_5678, value);
        cpu_access(ADDR_A, 1'b0, `AXI_SIZE_WORD, 0, value);
        check(value == 32'h1234_5678 && refill_count == refills_before &&
              memory[ADDR_A[11:2]] == 32'h1234_5678,
              "store hit updates cache only after backing write completes");

        refills_before = refill_count;
        cpu_access(ADDR_D, 1'b1, `AXI_SIZE_BYTE, 32'h0000_00A5, value);
        check(refill_count == refills_before && memory[ADDR_D[11:2]][7:0] == 8'hA5,
              "byte store miss is write-through and no-write-allocate");

        $display("dcache write-through unit: pass=%0d fail=%0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED");
        $finish;
    end

    initial begin
        repeat (5000) @(posedge clk);
        $display("TEST FAILED: timeout");
        $finish;
    end
endmodule
