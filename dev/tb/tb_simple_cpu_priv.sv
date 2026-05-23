`timescale 1ns / 1ps

module tb_simple_cpu_priv;

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
    wire        plic_eip;
    wire        clint_mtip;
    wire        clint_msip;

    integer pass_count;
    integer fail_count;

    core_top dut(
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
        .timer_irq(clint_mtip),
        .ext_meip_in(plic_eip),
        .ext_msip_in(clint_msip)
    );

    wire [15:0] gpio_io;

    ahb_lite_bus #(
        .ADDR_WIDTH  (32),
        .DATA_WIDTH  (32),
        .SLAVE_NUM   (5),
        .MEM_DEPTH   (8192),
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
        .o_gpio_irq (),
        .o_uart_irq (),
        .o_spi_irq  (),
        .o_plic_eip (plic_eip),
        .o_clint_mtip(clint_mtip),
        .o_clint_msip(clint_msip),
        .io_gpioPin (gpio_io),
        .i_uart_rx  (1'b1),
        .o_uart_tx  (),
        .o_spiMosi  (),
        .i_spiMiso  (1'b0),
        .o_spiSs    (),
        .o_spiClk   (),
        .o_gpioCtrl (),
        .o_gpioData ()
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

    reg [1:0] prev_priv;
    integer trace_count;
    reg [31:0] prev_wb_pc;
    reg sv32_active;
    reg [31:0] prev_x28;
    reg [31:0] prev_x29;

    always @(posedge clk) begin
        if (trace_count > 0) begin
            if (dut.u_regfile.rf[28] !== prev_x28 || dut.u_regfile.rf[29] !== prev_x29) begin
                $display("[%0t] COUNTER: x28=%0d x29=%0d x10=0x%08h priv=%b pc=0x%08h inst=0x%08h",
                    $time, dut.u_regfile.rf[28], dut.u_regfile.rf[29],
                    dut.u_regfile.rf[10],
                    dut.priv_mode, wb_pc, wb_inst);
            end
            prev_x28 = dut.u_regfile.rf[28];
            prev_x29 = dut.u_regfile.rf[29];
            if (dut.priv_mode !== prev_priv) begin
                $display("[%0t] PRIV_CHANGE: %b->%b pc=0x%08h mcause=0x%08h scause=0x%08h sepc=0x%08h", 
                    $time, prev_priv, dut.priv_mode, wb_pc, 
                    dut.u_trap_csr.u_csr_if.u_csr.r_mcause,
                    dut.u_trap_csr.u_csr_if.u_csr.r_scause,
                    dut.u_trap_csr.u_csr_if.u_csr.r_sepc);
            end
            prev_priv = dut.priv_mode;
            prev_wb_pc = wb_pc;
            trace_count = trace_count + 1;
        end
    end

    initial begin
        pass_count = 0;
        fail_count = 0;
        rf_addr = 5'd0;
        reset = 1'b1;
        trace_count = 0;
        prev_priv = 2'b11;
        prev_wb_pc = 32'h0;
        sv32_active = 1'b0;
        prev_x28 = 32'h0;
        prev_x29 = 32'h0;

        repeat (5) @(posedge clk);
        reset = 1'b0;
        trace_count = 1;

        repeat (2000000) @(posedge clk);

        check_reg(5'd28, 32'h0000000A);
        check_reg(5'd29, 32'h0000000A);
        check_reg(5'd20, 32'h00000001);

        rf_addr = 5'd24; #1; $display("DEBUG x24(mcause/scause) = 0x%08h", rf_data);
        rf_addr = 5'd25; #1; $display("DEBUG x25(mepc/sepc)    = 0x%08h", rf_data);
        rf_addr = 5'd10; #1; $display("DEBUG x10             = 0x%08h", rf_data);
        rf_addr = 5'd11; #1; $display("DEBUG x11             = 0x%08h", rf_data);
        $display("DEBUG if_pc = 0x%08h  wb_pc = 0x%08h", if_pc, wb_pc);

        $display("========================================");
        $display("privilege test summary");
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
