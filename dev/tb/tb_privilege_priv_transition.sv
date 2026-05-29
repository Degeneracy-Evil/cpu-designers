`timescale 1ns / 1ps

// ============================================================
// tb_privilege_priv_transition.sv — M↔S↔U privilege transition testbench
// ============================================================

module tb_privilege_priv_transition;

    localparam integer EXPECTED_TOTAL = 11;
    localparam integer SIM_CYCLES    = 200000;

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

    // ── Debug: trace privilege transitions ──
    integer cycle_cnt;
    integer trap_count;

    initial begin
        cycle_cnt = 0;
        trap_count = 0;
        @(negedge reset);
        forever begin
            @(posedge clk);
            cycle_cnt = cycle_cnt + 1;

            // Detect trap entry (print first 8)
            if (dut.trap_enter_valid && cycle_cnt > 100) begin
                trap_count = trap_count + 1;
                if (trap_count <= 8) begin
                    $display("[t=%0d] >>> TRAP #%0d: exe_pc=0x%08h mstatus=0x%08h priv=%0d",
                        cycle_cnt, trap_count, exe_pc, dut.csr_mstatus, dut.priv_mode);
                end
            end

            // Detect mret/sret execution
            if ((dut.dec_is_mret || dut.dec_is_sret) && cycle_cnt > 100 && cycle_cnt <= 10000) begin
                $display("[t=%0d] >>> %s: exe_pc=0x%08h mstatus=0x%08h priv=%0d",
                    cycle_cnt, dut.dec_is_mret ? "MRET" : "SRET",
                    exe_pc, dut.csr_mstatus, dut.priv_mode);
            end
        end
    end

    initial begin
        pass_count = 0;
        fail_count = 0;
        rf_addr = 5'd0;
        reset = 1'b1;

        repeat (5) @(posedge clk);
        reset = 1'b0;

        repeat (SIM_CYCLES) @(posedge clk);

        $display("");
        $display("--- Privilege PRIV_TRANSITION Results ---");

        rf_addr = 5'd28; #1;
        $display("  x28 (pass_count)    = %0d", rf_data);

        rf_addr = 5'd29; #1;
        $display("  x29 (total_count)   = %0d", rf_data);

        rf_addr = 5'd30; #1;
        $display("  x30 (first_fail_id) = %0d", rf_data);

        $display("");
        $display("  [DEBUG] Final CPU state:");
        $display("    if_pc  = 0x%08h", if_pc);
        $display("    exe_pc = 0x%08h", exe_pc);
        $display("    priv   = %0d", dut.priv_mode);
        $display("    mstatus= 0x%08h", dut.csr_mstatus);

        $display("");

        rf_addr = 5'd28; #1;
        if (rf_data === EXPECTED_TOTAL) begin
            pass_count = pass_count + 1;
            $display("  PASS pass_count = %0d", EXPECTED_TOTAL);
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL pass_count expected=%0d got=%0d", EXPECTED_TOTAL, rf_data);
        end

        rf_addr = 5'd30; #1;
        if (rf_data === 32'd0) begin
            pass_count = pass_count + 1;
            $display("  PASS first_fail_id = 0 (no failures)");
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL first_fail_id = %0d (test %0d failed)", rf_data, rf_data);
        end

        $display("");
        $display("========================================");
        $display("Privilege PRIV_TRANSITION summary");
        $display("pass=%0d fail=%0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED");
        $display("========================================");
        $finish;
    end

endmodule
