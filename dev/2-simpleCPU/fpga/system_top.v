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

    wire cpu_clk;
    assign cpu_clk = clk;

    wire reset;
    assign reset = ~resetn;

    wire [31:0] instAddr_32;
    wire [31:0] instData_32;
    wire [3:0]  dataWen_4;
    wire [31:0] dataAddr_32;
    wire [31:0] writeData_32;
    wire [31:0] readData_32;
    wire        data_req;
    wire        init_sig;
    wire        timer_irq;

    soc_top
    #(
        .CLK_FREQ(100),
        .GPIO_NUM(16)
    ) u_bus (
        .clk          (cpu_clk      ),
        .rstn         (resetn       ),
        .rx           (uart_rx      ),
        .tx           (uart_tx      ),
        .timer_irq    (timer_irq    ),
        .init_sig     (init_sig     ),
        .spi_miso     (spi_miso     ),
        .spi_mosi     (spi_mosi     ),
        .spi_ss       (spi_ss       ),
        .spi_clk      (spi_clk      ),
        .gpio_io      (gpio_io      ),
        .instAddr_32  (instAddr_32  ),
        .instData_32  (instData_32  ),
        .dataWen_4    (dataWen_4    ),
        .dataAddr_32  (dataAddr_32  ),
        .writeData_32 (writeData_32 ),
        .readData_32  (readData_32  )
    );

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

    simple_cpu_top cpu(
        .clk          (cpu_clk      ),
        .reset        (reset        ),
        .rf_addr      (rf_addr      ),
        .rf_data      (rf_data      ),
        .if_pc        (if_pc        ),
        .if_inst      (if_inst      ),
        .id_pc        (id_pc        ),
        .id_inst      (id_inst      ),
        .exe_pc       (exe_pc       ),
        .exe_inst     (exe_inst     ),
        .mem_pc       (mem_pc       ),
        .mem_inst     (mem_inst     ),
        .wb_pc        (wb_pc        ),
        .wb_inst      (wb_inst     ),
        .display_state(display_state),
        .instAddr_32  (instAddr_32  ),
        .instData_32  (instData_32  ),
        .dataWen_4    (dataWen_4    ),
        .dataAddr_32  (dataAddr_32  ),
        .writeData_32 (writeData_32 ),
        .readData_32  (readData_32  ),
        .data_req     (data_req     ),
        .init_sig     (init_sig     ),
        .timer_irq    (timer_irq    )
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
                    display_value <= dataAddr_32;
                end
                6'd10: begin
                    display_valid <= 1'b1;
                    display_name  <= "DDATA";
                    display_value <= readData_32;
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
