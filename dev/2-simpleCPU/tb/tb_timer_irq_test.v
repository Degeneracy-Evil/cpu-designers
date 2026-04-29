`timescale 1ns / 1ps

module tb_timer_irq_test;

    reg clk;
    reg reset;
    reg [4:0] rf_addr;

    wire [31:0] rf_data;
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

    wire [31:0] instAddr_32;
    wire [31:0] instData_32;
    wire [3:0]  dataWen_4;
    wire [31:0] dataAddr_32;
    wire [31:0] writeData_32;
    wire [31:0] readData_32;
    wire        data_req;
    wire        init_sig;
    wire        timer_irq;

    integer pass_count;
    integer fail_count;

    simple_cpu_top dut(
        .clk(clk),
        .reset(reset),
        .rf_addr(rf_addr),
        .rf_data(rf_data),
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
        .instAddr_32(instAddr_32),
        .instData_32(instData_32),
        .dataWen_4(dataWen_4),
        .dataAddr_32(dataAddr_32),
        .writeData_32(writeData_32),
        .readData_32(readData_32),
        .data_req(data_req),
        .init_sig(init_sig),
        .timer_irq(timer_irq)
    );

    wire [15:0] gpio_io;
    soc_top u_bus(
        .clk(clk),
        .rstn(~reset),
        .rx(1'b1),
        .tx(),
        .timer_irq(timer_irq),
        .init_sig(init_sig),
        .spi_miso(1'b0),
        .spi_mosi(),
        .spi_ss(),
        .spi_clk(),
        .gpio_io(gpio_io),
        .instAddr_32(instAddr_32),
        .instData_32(instData_32),
        .dataWen_4(dataWen_4),
        .dataAddr_32(dataAddr_32),
        .writeData_32(writeData_32),
        .readData_32(readData_32)
    );

    initial begin
        force u_bus.memory.data_init.r_init_1 = 1'b0;
    end

    initial begin
        $readmemh("dev/2-simpleCPU/program_source/timer_irq_test.hex", u_bus.memory.SramDualPort.mem);
    end

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task check_reg;
        input [4:0] addr;
        input [31:0] expected;
        input [255:0] name;
        begin
            rf_addr = addr;
            #1;
            if (rf_data === expected) begin
                pass_count = pass_count + 1;
                $display("PASS %0s = 0x%08h", name, rf_data);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL %0s expected=0x%08h got=0x%08h", name, expected, rf_data);
            end
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;
        rf_addr = 5'd0;
        reset = 1'b1;

        repeat (5) @(posedge clk);
        reset = 1'b0;

        repeat (8000) @(posedge clk);

        check_reg(5'd2, 32'h80000007, "x2=mcause_timer_irq");
        check_reg(5'd4, 32'h00000001, "x4=handler_entered");

        $display("========================================");
        $display("Timer IRQ test summary");
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
