`timescale 1ns / 1ps

module tb_simple_cpu_top;

    reg clk;
    reg reset;
    reg [4:0] rf_addr;
    reg [31:0] mem_addr;

    wire [31:0] rf_data;
    wire [31:0] mem_data;
    wire [31:0] if_pc;
    wire [31:0] if_inst;
    wire [31:0] id_pc;
    wire [31:0] id_inst;
    wire [31:0] exe_pc;
    wire [31:0] exe_inst;
    wire [31:0] mem_pc;
    wire [31:0] mem_inst;
    wire [31:0] wb_pc;
    wire [31:0] wb_inst;
    wire [31:0] display_state;

    wire uart_tx_pin;

    integer pass_count;
    integer fail_count;

    simple_cpu_top dut(
        .clk(clk),
        .reset(reset),
        .rf_addr(rf_addr),
        .mem_addr(mem_addr),
        .rf_data(rf_data),
        .mem_data(mem_data),
        .if_pc(if_pc),
        .if_inst(if_inst),
        .id_pc(id_pc),
        .id_inst(id_inst),
        .exe_pc(exe_pc),
        .exe_inst(exe_inst),
        .mem_pc(mem_pc),
        .mem_inst(mem_inst),
        .wb_pc(wb_pc),
        .wb_inst(wb_inst),
        .display_state(display_state),
        .uart_rx_pin(1'b0),
        .uart_tx_pin(uart_tx_pin)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task check_reg;
        input [4:0] addr;
        input [31:0] expected;
        begin
            rf_addr = addr;
            #1;
            if (rf_data === expected) begin
                pass_count = pass_count + 1;
                $display("PASS reg x%0d = 0x%08h", addr, rf_data);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL reg x%0d expected=0x%08h got=0x%08h", addr, expected, rf_data);
            end
        end
    endtask

    task check_mem_word;
        input [31:0] addr;
        input [31:0] expected;
        begin
            mem_addr = addr;
            @(posedge clk);
            #1;
            if (mem_data === expected) begin
                pass_count = pass_count + 1;
                $display("PASS mem[0x%08h] = 0x%08h", addr, mem_data);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL mem[0x%08h] expected=0x%08h got=0x%08h", addr, expected, mem_data);
            end
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;
        rf_addr = 5'd0;
        mem_addr = 32'd0;
        reset = 1'b1;

        repeat (5) @(posedge clk);
        reset = 1'b0;

        repeat (5000) @(posedge clk);

        check_reg(5'd1,  32'h37);
        check_reg(5'd2,  32'h400);
        check_reg(5'd3,  32'd0);
        check_reg(5'd4,  32'd0);
        check_reg(5'd5,  32'd0);
        check_reg(5'd6,  32'd0);
        check_reg(5'd7,  32'd0);
        check_reg(5'd8,  32'd0);
        check_reg(5'd9,  32'd0);
        check_reg(5'd10, 32'h37);
        check_reg(5'd11, 32'd0);
        check_reg(5'd12, 32'd0);
        check_reg(5'd13, 32'd0);
        check_reg(5'd14, 32'd10);
        check_reg(5'd15, 32'h37);
        check_reg(5'd16, 32'd0);
        check_reg(5'd17, 32'd0);
        check_reg(5'd18, 32'd0);
        check_reg(5'd19, 32'd0);
        check_reg(5'd20, 32'd0);
        check_reg(5'd21, 32'd0);
        check_reg(5'd22, 32'd0);
        check_reg(5'd23, 32'd0);
        check_reg(5'd24, 32'd0);
        check_reg(5'd25, 32'd0);
        check_reg(5'd26, 32'd0);
        check_reg(5'd27, 32'd0);
        check_reg(5'd28, 32'd0);
        check_reg(5'd29, 32'd0);
        check_reg(5'd30, 32'd0);
        check_reg(5'd31, 32'd0);

        check_mem_word(32'h3e8, 32'h59);
        check_mem_word(32'h3ec, 32'h37);

        $display("========================================");
        $display("simpleCPU test summary");
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
