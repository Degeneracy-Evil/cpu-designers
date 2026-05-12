`timescale 1ns / 1ps
module system_top(
    input         clk,
    input         resetn,

    input  [7:0]  sw,

    input         uart_rx,
    output        uart_tx,

    input         spi_miso,
    output        spi_mosi,
    output        spi_ss,
    output        spi_clk,

    inout  [15:0] gpio_io,

    output        lcd_rst,
    output        lcd_cs,
    output        lcd_rs,
    output        lcd_wr,
    output        lcd_rd,
    inout  [15:0] lcd_data_io,
    output        lcd_bl_ctr,
    inout         ct_int,
    inout         ct_sda,
    output        ct_scl,
    output        ct_rstn
);

    wire reset;
    assign reset = ~resetn;

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

    wire [ 4:0] rf_addr;
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

    core_top cpu(
        .clk          (clk           ),
        .reset        (reset         ),
        .rf_addr      (rf_addr       ),
        .rf_data      (rf_data       ),
        .if_pc        (if_pc         ),
        .if_inst      (if_inst       ),
        .id_pc        (id_pc         ),
        .id_inst      (id_inst       ),
        .exe_pc       (exe_pc        ),
        .exe_inst     (exe_inst      ),
        .mem_pc       (mem_pc        ),
        .mem_inst     (mem_inst      ),
        .wb_pc        (wb_pc         ),
        .wb_inst      (wb_inst       ),
        .display_state(display_state ),
        .HADDR        (cpu_HADDR     ),
        .HTRANS       (cpu_HTRANS    ),
        .HWRITE       (cpu_HWRITE    ),
        .HSIZE        (cpu_HSIZE     ),
        .HBURST       (cpu_HBURST    ),
        .HPROT        (cpu_HPROT     ),
        .HMASTLOCK    (cpu_HMASTLOCK ),
        .HWDATA       (cpu_HWDATA    ),
        .HRDATA       (cpu_HRDATA    ),
        .HREADY       (cpu_HREADY    ),
        .HRESP        (cpu_HRESP     ),
        .init_sig     (1'b0          ),
        .timer_irq    (clint_mtip    ),
        .ext_meip_in  (plic_eip      ),
        .ext_msip_in  (clint_msip    )
    );

    ahb_lite_bus #(
        .ADDR_WIDTH  (32),
        .DATA_WIDTH  (32),
        .SLAVE_NUM   (4),
        .MEM_DEPTH   (262144),
        .WAIT_STATES (0),
        .GPIO_NUM    (16),
        .UART_FREQ   (100)
    ) u_ahb_lite_bus (
        .HCLK       (clk),
        .HRESETn    (resetn),
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
        .o_plic_eip (plic_eip),
        .o_clint_mtip(clint_mtip),
        .o_clint_msip(clint_msip),
        .io_gpioPin (gpio_io),
        .i_uart_rx  (uart_rx),
        .o_uart_tx  (uart_tx),
        .o_spiMosi  (spi_mosi),
        .i_spiMiso  (spi_miso),
        .o_spiSs    (spi_ss),
        .o_spiClk   (spi_clk)
    );

    reg         display_valid;
    reg  [39:0] display_name;
    reg  [31:0] display_value;
    wire [5 :0] display_number;
    wire        input_valid;
    wire [31:0] input_value;

    lcd_module lcd_module(
        .clk            (clk           ),
        .resetn         (resetn        ),
        .display_valid  (display_valid ),
        .display_name   (display_name  ),
        .display_value  (display_value ),
        .display_number (display_number),
        .input_valid    (input_valid   ),
        .input_value    (input_value   ),
        .lcd_rst        (lcd_rst       ),
        .lcd_cs         (lcd_cs        ),
        .lcd_rs         (lcd_rs        ),
        .lcd_wr         (lcd_wr        ),
        .lcd_rd         (lcd_rd        ),
        .lcd_data_io    (lcd_data_io   ),
        .lcd_bl_ctr     (lcd_bl_ctr    ),
        .ct_int         (ct_int        ),
        .ct_sda         (ct_sda        ),
        .ct_scl         (ct_scl        ),
        .ct_rstn        (ct_rstn       )
    );

    assign rf_addr = display_number - 6'd11;

    always @(posedge clk) begin
        if (display_number > 6'd10 && display_number < 6'd43) begin
            display_valid       <= 1'b1;
            display_name[39:16] <= "REG";
            display_name[15:8]  <= {4'b0011, 3'b000, rf_addr[4]};
            display_name[7:0]   <= {4'b0011, rf_addr[3:0]};
            display_value       <= rf_data;
        end else begin
            case(display_number)
                6'd1: begin
                    display_valid <= 1'b1;
                    display_name  <= "IF_PC";
                    display_value <= if_pc;
                end
                6'd2: begin
                    display_valid <= 1'b1;
                    display_name  <= "IF_IN";
                    display_value <= if_inst;
                end
                6'd3: begin
                    display_valid <= 1'b1;
                    display_name  <= "ID_PC";
                    display_value <= id_pc;
                end
                6'd4: begin
                    display_valid <= 1'b1;
                    display_name  <= "EXEPC";
                    display_value <= exe_pc;
                end
                6'd5: begin
                    display_valid <= 1'b1;
                    display_name  <= "MEMPC";
                    display_value <= mem_pc;
                end
                6'd6: begin
                    display_valid <= 1'b1;
                    display_name  <= "MEMIN";
                    display_value <= mem_inst;
                end
                6'd7: begin
                    display_valid <= 1'b1;
                    display_name  <= "WB_PC";
                    display_value <= wb_pc;
                end
                6'd8: begin
                    display_valid <= 1'b1;
                    display_name  <= "WB_IN";
                    display_value <= wb_inst;
                end
                6'd9: begin
                    display_valid <= 1'b1;
                    display_name  <= "DADDR";
                    display_value <= cpu_HADDR;
                end
                6'd10: begin
                    display_valid <= 1'b1;
                    display_name  <= "DDATA";
                    display_value <= cpu_HRDATA;
                end
                6'd43: begin
                    display_valid <= 1'b1;
                    display_name  <= "STATE";
                    display_value <= display_state;
                end
                6'd44: begin
                    display_valid <= 1'b1;
                    display_name  <= "SW   ";
                    display_value <= {24'b0, sw};
                end
                default: begin
                    display_valid <= 1'b0;
                    display_name  <= 40'd0;
                    display_value <= 32'b0;
                end
            endcase
        end
    end

endmodule
