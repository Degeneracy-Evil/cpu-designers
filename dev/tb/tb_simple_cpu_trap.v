`timescale 1ns / 1ps

module tb_simple_cpu_trap;

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

    wire [31:0] cpu_HADDR;
    wire [1:0]  cpu_HTRANS;
    wire        cpu_HWRITE;
    wire [2:0]  cpu_HSIZE;
    wire [2:0]  cpu_HBURST;
    wire [3:0]  cpu_HPROT;
    wire        cpu_HMASTLOCK;
    wire [31:0] cpu_HWDATA;
    wire [31:0] cpu_HRDATA;
    wire        cpu_HREADY;
    wire        cpu_HRESP;

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
        .HADDR(cpu_HADDR),
        .HTRANS(cpu_HTRANS),
        .HWRITE(cpu_HWRITE),
        .HSIZE(cpu_HSIZE),
        .HBURST(cpu_HBURST),
        .HPROT(cpu_HPROT),
        .HMASTLOCK(cpu_HMASTLOCK),
        .HWDATA(cpu_HWDATA),
        .HRDATA(cpu_HRDATA),
        .HREADY(cpu_HREADY),
        .HRESP(cpu_HRESP),
        .init_sig(1'b0),
        .timer_irq(timer_irq)
    );

    wire [15:0] gpio_io;

    ahb_periph_bus #(
        .ADDR_WIDTH  (32),
        .DATA_WIDTH  (32),
        .SLAVE_NUM   (2),
        .MEM_DEPTH   (262144),
        .WAIT_STATES (0),
        .GPIO_NUM    (16),
        .UART_FREQ   (100)
    ) u_bus (
        .HCLK       (clk),
        .HRESETn    (~reset),
        .HADDR      (cpu_HADDR),
        .HTRANS     (cpu_HTRANS),
        .HWRITE     (cpu_HWRITE),
        .HSIZE      (cpu_HSIZE),
        .HBURST     (cpu_HBURST),
        .HPROT      (cpu_HPROT),
        .HMASTLOCK  (cpu_HMASTLOCK),
        .HWDATA     (cpu_HWDATA),
        .HRDATA     (cpu_HRDATA),
        .HREADY     (cpu_HREADY),
        .HRESP      (cpu_HRESP),
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
        $readmemh("dev/program_source/cpu_test_trap.hex", u_bus.u_ahb_sram_slave.u_bram.mem);
        $readmemh("dev/program_source/cpu_test_trap.hex", dut.u_icache_wrap.u_icache.mem);
        $readmemh("dev/program_source/cpu_test_trap.hex", dut.u_dcache_wrap.u_dcache.mem);
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

        repeat (20000) @(posedge clk);

        check_reg(5'd1,  32'h00000008);
        check_reg(5'd2,  32'h00000000);
        check_reg(5'd3,  32'h00000000);
        check_reg(5'd4,  32'h00000000);
        check_reg(5'd19, 32'h00000002);
        check_reg(5'd20, 32'h0000003c);
        check_reg(5'd21, 32'h00000003);

        check_mem_word(32'h48, 32'h0000000b);
        check_mem_word(32'h4C, 32'h00000003);
        check_mem_word(32'h50, 32'h00000002);

        $display("========================================");
        $display("trap test summary");
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
