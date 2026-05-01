`timescale 1ns / 1ps

module tb_cpu_bus_adapter;

    reg         clk;
    reg         resetn;
    reg  [31:0] inst_addr;
    reg         inst_req;
    reg  [31:0] data_addr;
    reg  [31:0] data_wdata;
    reg  [3:0]  data_wen;
    reg         data_req;

    wire [31:0] inst_data;
    wire [31:0] data_rdata;
    wire        req_valid;
    wire        req_write;
    wire [31:0] req_addr;
    wire [31:0] req_wdata;
    wire [2:0]  req_size;
    wire [2:0]  req_burst;
    wire [3:0]  req_prot;
    wire        req_lock;

    wire        inst_valid;
    wire        data_valid;

    reg         req_ready;
    reg         resp_valid;
    reg         resp_error;
    reg  [31:0] resp_rdata;

    integer pass_count;
    integer fail_count;

    cpu_bus_adapter #(
        .ADDR_WIDTH (32),
        .DATA_WIDTH (32)
    ) u_dut (
        .clk        (clk),
        .resetn     (resetn),
        .inst_addr  (inst_addr),
        .inst_data  (inst_data),
        .inst_req   (inst_req),
        .data_addr  (data_addr),
        .data_wdata (data_wdata),
        .data_rdata (data_rdata),
        .data_wen   (data_wen),
        .data_req   (data_req),
        .req_valid  (req_valid),
        .req_write  (req_write),
        .req_addr   (req_addr),
        .req_wdata  (req_wdata),
        .req_size   (req_size),
        .req_burst  (req_burst),
        .req_prot   (req_prot),
        .req_lock   (req_lock),
        .req_ready  (req_ready),
        .resp_valid (resp_valid),
        .resp_error (resp_error),
        .resp_rdata (resp_rdata),
        .inst_valid (inst_valid),
        .data_valid (data_valid)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        pass_count = 0;
        fail_count = 0;

        resetn    = 1'b0;
        inst_req  = 1'b0;
        data_req  = 1'b0;
        inst_addr = 32'b0;
        data_addr = 32'b0;
        data_wdata= 32'b0;
        data_wen  = 4'b1111;
        req_ready = 1'b1;
        resp_valid= 1'b0;
        resp_error= 1'b0;
        resp_rdata= 32'b0;

        repeat (5) @(posedge clk);
        resetn = 1'b1;
        repeat (2) @(posedge clk);

        begin : i_side_read_test
            inst_addr = 32'h00000100;
            inst_req  = 1'b1;
            req_ready = 1'b1;
            @(posedge clk);
            while (!req_valid) @(posedge clk);
            if (req_write === 1'b0 && req_addr === 32'h00000100) begin
                pass_count = pass_count + 1;
                $display("PASS I-side read request");
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL I-side read request");
            end
            resp_valid = 1'b1;
            resp_rdata = 32'h12345678;
            @(posedge clk);
            resp_valid = 1'b0;
            inst_req   = 1'b0;
            repeat (2) @(posedge clk);
            if (inst_data === 32'h12345678) begin
                pass_count = pass_count + 1;
                $display("PASS I-side read data");
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL I-side read data expected=0x12345678 got=0x%08h", inst_data);
            end
        end

        begin : d_side_write_test
            data_addr  = 32'h00000200;
            data_wdata = 32'hDEADBEEF;
            data_wen   = 4'b0000;
            data_req   = 1'b1;
            req_ready  = 1'b1;
            @(posedge clk);
            while (!req_valid) @(posedge clk);
            if (req_write === 1'b1 && req_addr === 32'h00000200 && req_wdata === 32'hDEADBEEF) begin
                pass_count = pass_count + 1;
                $display("PASS D-side write request (word)");
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL D-side write request");
            end
            resp_valid = 1'b1;
            @(posedge clk);
            resp_valid = 1'b0;
            data_req   = 1'b0;
            repeat (2) @(posedge clk);
        end

        begin : d_side_read_test
            data_addr = 32'h00000300;
            data_wen  = 4'b1111;
            data_req  = 1'b1;
            req_ready = 1'b1;
            @(posedge clk);
            while (!req_valid) @(posedge clk);
            if (req_write === 1'b0 && req_addr === 32'h00000300) begin
                pass_count = pass_count + 1;
                $display("PASS D-side read request");
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL D-side read request");
            end
            resp_valid = 1'b1;
            resp_rdata = 32'hCAFEBABE;
            @(posedge clk);
            resp_valid = 1'b0;
            data_req   = 1'b0;
            repeat (2) @(posedge clk);
            if (data_rdata === 32'hCAFEBABE) begin
                pass_count = pass_count + 1;
                $display("PASS D-side read data");
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL D-side read data expected=0xCAFEBABE got=0x%08h", data_rdata);
            end
        end

        begin : wen_conversion_test
            data_wen = 4'b1110;
            data_req = 1'b1;
            req_ready= 1'b1;
            @(posedge clk);
            while (!req_valid) @(posedge clk);
            if (req_write === 1'b1) begin
                pass_count = pass_count + 1;
                $display("PASS dataWen=1110 -> write=1");
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL dataWen=1110 -> write=1");
            end
            resp_valid = 1'b1;
            @(posedge clk);
            resp_valid = 1'b0;
            data_req   = 1'b0;
            repeat (2) @(posedge clk);
        end

        $display("========================================");
        $display("cpu_bus_adapter test summary");
        $display("pass=%0d fail=%0d", pass_count, fail_count);
        if (fail_count == 0) begin
            $display("ALL TESTS PASSED");
        end else begin
            $display("TEST FAILED");
        end
        $display("========================================");
        $finish;
    end

endmodule
