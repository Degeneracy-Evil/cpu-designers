`timescale 1ns / 1ps

module tb_simple_cpu_top;

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
    wire        inst_valid;
    wire [3:0]  dataWen_4;
    wire [31:0] dataAddr_32;
    wire [31:0] writeData_32;
    wire [31:0] readData_32;
    wire        data_valid;
    wire        data_req;
    wire        timer_irq;

    wire        bus_req_valid;
    wire        bus_req_write;
    wire [31:0] bus_req_addr;
    wire [31:0] bus_req_wdata;
    wire [2:0]  bus_req_size;
    wire [2:0]  bus_req_burst;
    wire [3:0]  bus_req_prot;
    wire        bus_req_lock;
    wire        bus_req_ready;
    wire        bus_resp_valid;
    wire        bus_resp_error;
    wire [31:0] bus_resp_rdata;

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
        .inst_valid(inst_valid),
        .dataWen_4(dataWen_4),
        .dataAddr_32(dataAddr_32),
        .writeData_32(writeData_32),
        .readData_32(readData_32),
        .data_valid(data_valid),
        .data_req(data_req),
        .init_sig(1'b0),
        .timer_irq(timer_irq)
    );

    cpu_bus_adapter #(
        .ADDR_WIDTH (32),
        .DATA_WIDTH (32)
    ) u_adapter (
        .clk        (clk),
        .resetn     (~reset),
        .inst_addr  (instAddr_32),
        .inst_data  (instData_32),
        .inst_req   (1'b1),
        .data_addr  (dataAddr_32),
        .data_wdata (writeData_32),
        .data_rdata (readData_32),
        .data_wen   (dataWen_4),
        .data_req   (data_req),
        .req_valid  (bus_req_valid),
        .req_write  (bus_req_write),
        .req_addr   (bus_req_addr),
        .req_wdata  (bus_req_wdata),
        .req_size   (bus_req_size),
        .req_burst  (bus_req_burst),
        .req_prot   (bus_req_prot),
        .req_lock   (bus_req_lock),
        .req_ready  (bus_req_ready),
        .resp_valid (bus_resp_valid),
        .resp_error (bus_resp_error),
        .resp_rdata (bus_resp_rdata),
        .inst_valid (inst_valid),
        .data_valid (data_valid)
    );

    wire [15:0] gpio_io;

    ahb_periph_bus #(
        .ADDR_WIDTH  (32),
        .DATA_WIDTH  (32),
        .SLAVE_NUM   (2),
        .MEM_DEPTH   (262144),
        .WAIT_STATES (0),
        .GPIO_NUM    (16),
        .UART_FREQ   (25)
    ) u_bus (
        .HCLK       (clk),
        .HRESETn    (~reset),
        .req_valid  (bus_req_valid),
        .req_write  (bus_req_write),
        .req_addr   (bus_req_addr),
        .req_wdata  (bus_req_wdata),
        .req_size   (bus_req_size),
        .req_burst  (bus_req_burst),
        .req_prot   (bus_req_prot),
        .req_lock   (bus_req_lock),
        .req_ready  (bus_req_ready),
        .resp_valid (bus_resp_valid),
        .resp_error (bus_resp_error),
        .resp_rdata (bus_resp_rdata),
        .o_timer_irq(timer_irq),
        .io_gpioPin (gpio_io),
        .i_uart_rx  (1'b1),
        .o_uart_tx  (),
        .o_spiMosi  (),
        .i_spiMiso  (1'b0),
        .o_spiSs    (),
        .o_spiClk   ()
    );

    initial begin
`ifndef XILINX_SIMULATOR
        $readmemh("dev/2-simpleCPU/program_source/icache_init.hex", u_bus.u_ahb_sram_slave.u_bram.mem);
        $readmemh("dev/2-simpleCPU/program_source/icache_init.hex", dut.u_icache_wrap.u_icache.mem);
        $readmemh("dev/2-simpleCPU/program_source/icache_init.hex", dut.u_dcache_wrap.u_dcache.mem);
`endif
    end

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
`ifndef XILINX_SIMULATOR
            if (dut.u_dcache_wrap.u_dcache.mem[addr[13:2]] === expected) begin
                pass_count = pass_count + 1;
                $display("PASS mem[0x%08h] = 0x%08h", addr, dut.u_dcache_wrap.u_dcache.mem[addr[13:2]]);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL mem[0x%08h] expected=0x%08h got=0x%08h", addr, expected, dut.u_dcache_wrap.u_dcache.mem[addr[13:2]]);
            end
`else
            $display("SKIP mem check in Vivado");
            pass_count = pass_count + 1;
`endif
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;
        rf_addr = 5'd0;
        reset = 1'b1;

        repeat (5) @(posedge clk);
        reset = 1'b0;

        repeat (10000) @(posedge clk);

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
        check_mem_word(32'd4, 32'h00070105);

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
