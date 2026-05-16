`timescale 1ns / 1ps

module tb_uart_hello;

    reg clk;
    reg reset;

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

    wire        uart_tx;

    core_top dut(
        .clk(clk),
        .reset(reset),
        .rf_addr(5'b0),
        .rf_data(),
        .if_pc(),
        .if_inst(),
        .id_pc(),
        .id_inst(),
        .exe_pc(),
        .exe_inst(),
        .mem_pc(),
        .mem_inst(),
        .wb_pc(),
        .wb_inst(),
        .display_state(),
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
        .timer_irq(timer_irq),
        .ext_meip_in(1'b0),
        .ext_msip_in(1'b0)
    );

    wire [15:0] gpio_io;

    ahb_lite_bus #(
        .ADDR_WIDTH  (32),
        .DATA_WIDTH  (32),
        .SLAVE_NUM   (4),
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
        .o_plic_eip (),
        .o_clint_mtip(),
        .o_clint_msip(),
        .io_gpioPin (gpio_io),
        .i_uart_rx  (1'b1),
        .o_uart_tx  (uart_tx),
        .o_spiMosi  (),
        .i_spiMiso  (1'b0),
        .o_spiSs    (),
        .o_spiClk   ()
    );

    initial begin
`ifndef XILINX_SIMULATOR
        $readmemh("dev/program_source/uart_hello.hex", u_bus.u_ahb_sram_slave.u_bram.mem);
        $readmemh("dev/program_source/uart_hello.hex", dut.u_icache_wrap.u_icache.mem);
        $readmemh("dev/program_source/uart_hello.hex", dut.u_dcache_wrap.u_dcache.mem);
`endif
    end

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    localparam CLK_FRE    = 100;
    localparam BAUD_RATE  = 115200;
    localparam CYCLE      = CLK_FRE * 1000000 / BAUD_RATE;
    localparam BIT_PERIOD = CYCLE * 10;

    localparam MSG_LEN = 11;
    reg [7:0] expected_msg [0:MSG_LEN-1];
    reg [7:0] decoded_msg [0:MSG_LEN-1];
    integer   decoded_count;
    integer   pass_count;
    integer   fail_count;

    initial begin
        expected_msg[0]  = "H";
        expected_msg[1]  = "e";
        expected_msg[2]  = "l";
        expected_msg[3]  = "l";
        expected_msg[4]  = "o";
        expected_msg[5]  = " ";
        expected_msg[6]  = "W";
        expected_msg[7]  = "o";
        expected_msg[8]  = "r";
        expected_msg[9]  = "l";
        expected_msg[10] = "d";
    end

    localparam RX_IDLE  = 2'd0;
    localparam RX_START = 2'd1;
    localparam RX_DATA  = 2'd2;
    localparam RX_STOP  = 2'd3;

    reg [1:0] rx_state;
    reg [7:0] rx_shift;
    reg [2:0] rx_bit_cnt;
    integer   rx_timer;

    always @(posedge clk) begin
        if (reset) begin
            rx_state      <= RX_IDLE;
            rx_shift      <= 8'h0;
            rx_bit_cnt    <= 3'd0;
            rx_timer      <= 0;
            decoded_count <= 0;
        end else begin
            case (rx_state)
                RX_IDLE: begin
                    if (uart_tx === 1'b0) begin
                        rx_state <= RX_START;
                        rx_timer <= 0;
                    end
                end
                RX_START: begin
                    if (rx_timer == (CYCLE / 2 - 1)) begin
                        if (uart_tx === 1'b0) begin
                            rx_state   <= RX_DATA;
                            rx_shift   <= 8'h0;
                            rx_bit_cnt <= 3'd0;
                            rx_timer   <= 0;
                        end else begin
                            rx_state <= RX_IDLE;
                        end
                    end else begin
                        rx_timer <= rx_timer + 1;
                    end
                end
                RX_DATA: begin
                    if (rx_timer == CYCLE - 1) begin
                        rx_shift   <= {uart_tx, rx_shift[7:1]};
                        rx_bit_cnt <= rx_bit_cnt + 3'd1;
                        rx_timer   <= 0;
                        if (rx_bit_cnt == 3'd7) begin
                            rx_state <= RX_STOP;
                        end
                    end else begin
                        rx_timer <= rx_timer + 1;
                    end
                end
                RX_STOP: begin
                    if (rx_timer == CYCLE - 1) begin
                        rx_state <= RX_IDLE;
                        if (decoded_count < MSG_LEN) begin
                            decoded_msg[decoded_count] <= rx_shift;
                            decoded_count <= decoded_count + 1;
                        end
                    end else begin
                        rx_timer <= rx_timer + 1;
                    end
                end
            endcase
        end
    end

    initial begin
`ifndef XILINX_SIMULATOR
        $dumpfile("dev/tb/waveform/uart_hello.vcd");
        $dumpvars(0, u_bus.u_apb_perips.u_uart.uart_tx_inst);
`endif
    end

    integer i;

    initial begin
        pass_count = 0;
        fail_count = 0;
        reset = 1'b1;

        repeat (5) @(posedge clk);
        reset = 1'b0;

        repeat (3000000) @(posedge clk);

        $display("========================================");
        $display("UART Hello World test");
        $display("Decoded %0d characters:", decoded_count);
        for (i = 0; i < decoded_count; i = i + 1)
            $write("%c", decoded_msg[i]);
        $display("");

        if (decoded_count != MSG_LEN) begin
            fail_count = fail_count + 1;
            $display("FAIL: expected %0d chars, got %0d", MSG_LEN, decoded_count);
        end else begin
            pass_count = pass_count + 1;
            $display("PASS: character count = %0d", MSG_LEN);
        end

        for (i = 0; i < MSG_LEN; i = i + 1) begin
            if (i < decoded_count) begin
                if (decoded_msg[i] === expected_msg[i]) begin
                    pass_count = pass_count + 1;
                    $display("PASS char[%0d]: expected='%c' (0x%02h) got='%c' (0x%02h)",
                             i, expected_msg[i], expected_msg[i], decoded_msg[i], decoded_msg[i]);
                end else begin
                    fail_count = fail_count + 1;
                    $display("FAIL char[%0d]: expected='%c' (0x%02h) got='%c' (0x%02h)",
                             i, expected_msg[i], expected_msg[i], decoded_msg[i], decoded_msg[i]);
                end
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL char[%0d]: expected='%c' (0x%02h) got=MISSING",
                         i, expected_msg[i], expected_msg[i]);
            end
        end

        $display("========================================");
        $display("UART test summary: pass=%0d fail=%0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED");
        $display("========================================");
        $finish;
    end

endmodule
