`timescale 1ns / 1ps
module tb_exception_access_fault;
    localparam integer EXPECTED_TOTAL = 3;
    reg clk; reg reset; reg [4:0] rf_addr;
    wire [31:0] rf_data; wire [31:0] if_pc, if_inst, id_pc, id_inst, exe_pc, exe_inst;
    wire [31:0] mem_pc, mem_inst, wb_pc, wb_inst, display_state;
    wire [31:0] cpu_HADDR, cpu_HWDATA, cpu_HRDATA; wire [1:0] cpu_HTRANS;
    wire cpu_HWRITE, cpu_HREADY, cpu_HRESP; wire [2:0] cpu_HSIZE, cpu_HBURST;
    wire [3:0] cpu_HPROT; wire cpu_HMASTLOCK;
    wire timer_irq, plic_eip, clint_mtip, clint_msip;
    integer pass_count, fail_count;
    core_top dut(
        .clk(clk), .reset(reset), .rf_addr(rf_addr), .rf_data(rf_data),
        .if_pc(if_pc), .if_inst(if_inst), .id_pc(id_pc), .id_inst(id_inst),
        .exe_pc(exe_pc), .exe_inst(exe_inst), .mem_pc(mem_pc), .mem_inst(mem_inst),
        .wb_pc(wb_pc), .wb_inst(wb_inst), .display_state(display_state),
        .HADDR(cpu_HADDR), .HTRANS(cpu_HTRANS), .HWRITE(cpu_HWRITE),
        .HSIZE(cpu_HSIZE), .HBURST(cpu_HBURST), .HPROT(cpu_HPROT),
        .HMASTLOCK(cpu_HMASTLOCK), .HWDATA(cpu_HWDATA), .HRDATA(cpu_HRDATA),
        .HREADY(cpu_HREADY), .HRESP(cpu_HRESP), .init_sig(1'b0),
        .timer_irq(clint_mtip), .ext_meip_in(plic_eip), .ext_msip_in(clint_msip)
    );
    wire [15:0] gpio_io;
    ahb_lite_bus #(.ADDR_WIDTH(32), .DATA_WIDTH(32), .SLAVE_NUM(5), .MEM_DEPTH(8192),
        .WAIT_STATES(0), .GPIO_NUM(16), .UART_FREQ(100)) u_bus(
        .HCLK(clk), .HRESETn(~reset), .HADDR(cpu_HADDR), .HTRANS(cpu_HTRANS),
        .HWRITE(cpu_HWRITE), .HSIZE(cpu_HSIZE), .HBURST(cpu_HBURST), .HPROT(cpu_HPROT),
        .HMASTLOCK(cpu_HMASTLOCK), .HWDATA(cpu_HWDATA), .HRDATA(cpu_HRDATA),
        .HREADY(cpu_HREADY), .HRESP(cpu_HRESP), .o_timer_irq(timer_irq),
        .o_gpio_irq(), .o_uart_irq(), .o_spi_irq(), .o_plic_eip(plic_eip),
        .o_clint_mtip(clint_mtip), .o_clint_msip(clint_msip), .io_gpioPin(gpio_io),
        .i_uart_rx(1'b1), .o_uart_tx(), .o_spiMosi(), .i_spiMiso(1'b0),
        .o_spiSs(), .o_spiClk(), .o_gpioCtrl(), .o_gpioData()
    );
    initial begin clk = 1'b0; forever #5 clk = ~clk; end
    initial begin
        pass_count = 0; fail_count = 0; rf_addr = 5'd0; reset = 1'b1;
        repeat (5) @(posedge clk); reset = 1'b0;
        repeat (50000) @(posedge clk);
        $display(""); $display("--- Framework Results ---");
        rf_addr = 5'd28; #1; $display("  x28 (pass_count)    = %0d", rf_data);
        rf_addr = 5'd29; #1; $display("  x29 (total_count)   = %0d", rf_data);
        rf_addr = 5'd30; #1; $display("  x30 (first_fail_id) = %0d", rf_data);
        $display("");
        rf_addr = 5'd28; #1;
        if (rf_data === EXPECTED_TOTAL) begin pass_count = pass_count + 1; $display("  PASS pass_count = %0d", EXPECTED_TOTAL); end
        else begin fail_count = fail_count + 1; $display("  FAIL pass_count expected=%0d got=%0d", EXPECTED_TOTAL, rf_data); end
        rf_addr = 5'd30; #1;
        if (rf_data === 32'd0) begin pass_count = pass_count + 1; $display("  PASS first_fail_id = 0 (no failures)"); end
        else begin fail_count = fail_count + 1; $display("  FAIL first_fail_id = %0d", rf_data); end
        $display(""); $display("Exception ACCESS_FAULT test summary");
        $display("pass=%0d fail=%0d", pass_count, fail_count);
        if (fail_count == 0) $display("ALL TESTS PASSED"); else $display("TEST FAILED");
        $finish;
    end
endmodule
