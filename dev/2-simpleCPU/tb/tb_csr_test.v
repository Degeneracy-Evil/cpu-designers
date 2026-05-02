`timescale 1ns / 1ps

module tb_csr_test;

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
    wire        timer_irq;
    wire        inst_valid;
    wire        data_valid;

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
    integer cycle_count;

    always @(posedge clk) begin
        if (!reset) begin
            cycle_count = cycle_count + 1;
            if (display_state[3:0] >= 6) begin
                $display("cycle=%0d state=%0d pc_if=0x%08h inst_if=0x%08h", 
                         cycle_count, display_state[3:0], if_pc, if_inst);
            end
        end
    end

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
        .SLAVE_NUM   (4),
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
        $readmemh("dev/2-simpleCPU/program_source/csr_test.hex", u_bus.u_ahb_sram_slave.u_bram.mem);
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

    task check_mem_word;
        input [31:0] addr;
        input [31:0] expected;
        input [255:0] name;
        begin
            if (u_bus.u_ahb_sram_slave.u_bram.mem[addr[19:2]] === expected) begin
                pass_count = pass_count + 1;
                $display("PASS %0s = 0x%08h", name, u_bus.u_ahb_sram_slave.u_bram.mem[addr[19:2]]);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL %0s expected=0x%08h got=0x%08h", name, expected, u_bus.u_ahb_sram_slave.u_bram.mem[addr[19:2]]);
            end
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;
        cycle_count = 0;
        rf_addr = 5'd0;
        reset = 1'b1;

        repeat (5) @(posedge clk);
        reset = 1'b0;

        repeat (5000) @(posedge clk);

        check_reg(5'd2,  32'h00000000, "x2=old_mstatus");
        check_reg(5'd3,  32'h00000000, "x3=old_mie");
        check_reg(5'd4,  32'h00000000, "x4=old_mtvec");
        check_reg(5'd5,  32'h00000000, "x5=old_mscratch");
        check_reg(5'd6,  32'h0000AAAA, "x6=mscratch_after_write_AAAA");
        check_reg(5'd7,  32'h00000000, "x7=mscratch_after_write_5555");
        check_reg(5'd8,  32'h00005555, "x8=mscratch_before_csrrs_1");
        check_reg(5'd9,  32'h00005555, "x9=mscratch_before_csrrs_100");
        check_reg(5'd11, 32'h00005555, "x11=mscratch_before_csrrc_1");
        check_reg(5'd12, 32'h00005554, "x12=mscratch_before_csrrc_100");
        check_reg(5'd13, 32'h00005454, "x13=mscratch_before_csrrwi_0");
        check_reg(5'd14, 32'h00000000, "x14=mscratch_before_csrrwi_5");
        check_reg(5'd15, 32'h00000005, "x15=mscratch_before_csrrsi_2");
        check_reg(5'd16, 32'h00000007, "x16=mscratch_before_csrrsi_0");
        check_reg(5'd17, 32'h00000007, "x17=mscratch_before_csrrci_1");
        check_reg(5'd18, 32'h00000006, "x18=mscratch_before_csrrci_0");

        check_mem_word(32'h48, 32'h0000000B, "mem[72]=mcause_ecall");
        check_mem_word(32'h4C, 32'h00000003, "mem[76]=mcause_ebreak");
        check_mem_word(32'h50, 32'h00000002, "mem[80]=mcause_illegal");

        check_mem_word(32'h0, 32'h00000003, "mem[0]=x1_after_all_exceptions");

        $display("========================================");
        $display("CSR test summary");
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
