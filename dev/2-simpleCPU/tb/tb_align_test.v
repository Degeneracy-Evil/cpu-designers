`timescale 1ns / 1ps

module tb_align_test;

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

`ifdef USE_REAL_BUS
    wire [15:0] gpio_io;
    soc_top u_bus(
        .clk(clk),
        .rstn(~reset),
        .rx(1'b1),
        .tx(),
        .timer_iqr(timer_irq),
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
        $readmemh("dev/2-simpleCPU/program_source/align_test.hex", u_bus.memory.SramDualPort.mem);
    end
`else
    bus4lzu_mock u_bus_mock(
        .clk(clk),
        .reset(reset),
        .instAddr_32(instAddr_32),
        .instData_32(instData_32),
        .data_req(data_req),
        .dataWen_4(dataWen_4),
        .dataAddr_32(dataAddr_32),
        .writeData_32(writeData_32),
        .readData_32(readData_32),
        .init_sig(init_sig),
        .timer_irq(timer_irq),
        .dbg_mem_addr(mem_addr),
        .dbg_mem_data(mem_data)
    );
`endif

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

    task check_mem_word;
        input [31:0] addr;
        input [31:0] expected;
        input [255:0] name;
        begin
`ifdef USE_REAL_BUS
            if (u_bus.memory.SramDualPort.mem[addr[14:2]] === expected) begin
                pass_count = pass_count + 1;
                $display("PASS %0s = 0x%08h", name, u_bus.memory.SramDualPort.mem[addr[14:2]]);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL %0s expected=0x%08h got=0x%08h", name, expected, u_bus.memory.SramDualPort.mem[addr[14:2]]);
            end
`else
            mem_addr = addr;
            #1;
            if (mem_data === expected) begin
                pass_count = pass_count + 1;
                $display("PASS %0s = 0x%08h", name, mem_data);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL %0s expected=0x%08h got=0x%08h", name, expected, mem_data);
            end
`endif
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

        check_reg(5'd2,  32'hFFFFFFC1, "x2=lb_0xC1_signed");
        check_reg(5'd3,  32'h000000C1, "x3=lbu_0xC1_unsigned");
        check_reg(5'd4,  32'hFFFFFFC2, "x4=lb_0xC2_signed");
        check_reg(5'd5,  32'h000000C2, "x5=lbu_0xC2_unsigned");
        check_reg(5'd6,  32'hFFFFFFC3, "x6=lb_0xC3_signed");
        check_reg(5'd7,  32'h000000C3, "x7=lbu_0xC3_unsigned");
        check_reg(5'd8,  32'hFFFFFFC4, "x8=lb_0xC4_signed");
        check_reg(5'd9,  32'h000000C4, "x9=lbu_0xC4_unsigned");

        check_reg(5'd20, 32'h00005678, "x20=lh_offset0");
        check_reg(5'd11, 32'h00005678, "x11=lhu_offset0");

        check_reg(5'd12, 32'hFFFFABCD, "x12=lh_offset2_signed");
        check_reg(5'd13, 32'h0000ABCD, "x13=lhu_offset2_unsigned");

        check_reg(5'd14, 32'hABCD5678, "x14=lw_word0");

        check_reg(5'd15, 32'h12345678, "x15=lw_word4");

        check_reg(5'd16, 32'h00000078, "x16=lb_byte4");
        check_reg(5'd17, 32'h00000056, "x17=lb_byte5");
        check_reg(5'd18, 32'h00000034, "x18=lb_byte6");
        check_reg(5'd19, 32'h00000012, "x19=lb_byte7");

        check_reg(5'd22, 32'hFFFFFFFF, "x22=lb_0xFF_signed");
        check_reg(5'd23, 32'h00000000, "x23=lb_0x00_signed");
        check_reg(5'd24, 32'h00000000, "x24=lb_0x00_signed");
        check_reg(5'd25, 32'hFFFFFFFF, "x25=lb_0xFF_signed");

        check_reg(5'd1,  32'h00000001, "x1=test_complete");

        $display("========================================");
        $display("Align test summary");
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
