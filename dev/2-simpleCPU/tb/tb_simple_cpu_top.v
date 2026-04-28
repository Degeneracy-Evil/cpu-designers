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
        $readmemh("dev/2-simpleCPU/program_source/icache_init.hex", u_bus.memory.SramDualPort.mem);
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
`ifdef USE_REAL_BUS
            if (u_bus.memory.SramDualPort.mem[addr[14:2]] === expected) begin
                pass_count = pass_count + 1;
                $display("PASS mem[0x%08h] = 0x%08h", addr, u_bus.memory.SramDualPort.mem[addr[14:2]]);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL mem[0x%08h] expected=0x%08h got=0x%08h", addr, expected, u_bus.memory.SramDualPort.mem[addr[14:2]]);
            end
`else
            mem_addr = addr;
            #1;
            if (mem_data === expected) begin
                pass_count = pass_count + 1;
                $display("PASS mem[0x%08h] = 0x%08h", addr, mem_data);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL mem[0x%08h] expected=0x%08h got=0x%08h", addr, expected, mem_data);
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

        repeat (2500) @(posedge clk);

        check_reg(5'd1,  32'd5);
        check_reg(5'd2,  32'd77);
        check_reg(5'd3,  32'd12);
        check_reg(5'd4,  32'd184);
        check_reg(5'd5,  32'd200);
        check_reg(5'd6,  32'd1);
        check_reg(5'd7,  32'd0);
        check_reg(5'd8,  32'd2);
        check_reg(5'd9,  32'd0);
        check_reg(5'd10, 32'd0);
        check_reg(5'd11, 32'd7);
        check_reg(5'd12, 32'd5);
        check_reg(5'd13, 32'd1);
        check_reg(5'd14, 32'd1);
        check_reg(5'd15, 32'd6);
        check_reg(5'd16, 32'd13);
        check_reg(5'd17, 32'd9);
        check_reg(5'd18, 32'd40);
        check_reg(5'd19, 32'd20);
        check_reg(5'd20, 32'd10);
        check_reg(5'd21, 32'h12345000);
        check_reg(5'd22, 32'd84);
        check_reg(5'd23, 32'd12);
        check_reg(5'd24, 32'd5);
        check_reg(5'd25, 32'd5);
        check_reg(5'd26, 32'd7);
        check_reg(5'd27, 32'd7);
        check_reg(5'd28, 32'd0);
        check_reg(5'd29, 32'd0);
        check_reg(5'd30, 32'd0);
        check_reg(5'd31, 32'd172);

        check_mem_word(32'd0, 32'd12);
`ifdef USE_REAL_BUS
        check_mem_word(32'd4, 32'h00070105);
`else
        check_mem_word(32'd4, 32'h00070005);
`endif

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
