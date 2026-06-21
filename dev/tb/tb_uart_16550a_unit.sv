`timescale 1ns / 1ps

module tb_uart_16550a_unit;

    localparam integer UART_DIVISOR = 16;
    localparam integer UART_BIT_CYCLES = UART_DIVISOR * 16;

    reg         clk;
    reg         resetn;
    reg  [31:0] PADDR;
    reg  [2:0]  PPROT;
    reg         PSEL;
    reg         PENABLE;
    reg         PWRITE;
    reg  [31:0] PWDATA;
    reg  [3:0]  PSTRB;
    wire        PREADY;
    wire [31:0] PRDATA;
    wire        PSLVERR;
    reg         uart_rx;
    wire        uart_tx;
    wire        uart_irq;

    integer pass_count;
    integer fail_count;

    uart_16550a dut (
        .PCLK    (clk),
        .PRESETn (resetn),
        .PADDR   (PADDR),
        .PPROT   (PPROT),
        .PSEL    (PSEL),
        .PENABLE (PENABLE),
        .PWRITE  (PWRITE),
        .PWDATA  (PWDATA),
        .PSTRB   (PSTRB),
        .PREADY  (PREADY),
        .PRDATA  (PRDATA),
        .PSLVERR (PSLVERR),
        .i_rx    (uart_rx),
        .o_tx    (uart_tx),
        .o_irq   (uart_irq)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task check;
        input [255:0] name;
        input [31:0] actual;
        input [31:0] expected;
        begin
            if (actual === expected) begin
                pass_count = pass_count + 1;
                $display("PASS %0s = 0x%08h", name, actual);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL %0s expected=0x%08h got=0x%08h", name, expected, actual);
            end
        end
    endtask

    task apb_write;
        input [31:0] addr;
        input [31:0] data;
        input [3:0]  strb;
        begin
            @(posedge clk);
            PADDR   <= addr;
            PWDATA  <= data;
            PSTRB   <= strb;
            PWRITE  <= 1'b1;
            PSEL    <= 1'b1;
            PENABLE <= 1'b0;
            @(posedge clk);
            PENABLE <= 1'b1;
            @(posedge clk);
            PSEL    <= 1'b0;
            PENABLE <= 1'b0;
            PWRITE  <= 1'b0;
            PSTRB   <= 4'd0;
        end
    endtask

    task apb_read;
        input  [31:0] addr;
        output [31:0] data;
        begin
            @(posedge clk);
            PADDR   <= addr;
            PWRITE  <= 1'b0;
            PSEL    <= 1'b1;
            PENABLE <= 1'b0;
            @(posedge clk);
            PENABLE <= 1'b1;
            @(posedge clk);
            data = PRDATA;
            PSEL    <= 1'b0;
            PENABLE <= 1'b0;
        end
    endtask

    task uart_send_byte;
        input [7:0] data;
        integer bit_idx;
        begin
            uart_rx = 1'b1;
            repeat (UART_BIT_CYCLES) @(posedge clk);
            uart_rx = 1'b0;
            repeat (UART_BIT_CYCLES) @(posedge clk);
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                uart_rx = data[bit_idx];
                repeat (UART_BIT_CYCLES) @(posedge clk);
            end
            uart_rx = 1'b1;
            repeat (UART_BIT_CYCLES) @(posedge clk);
        end
    endtask

    task uart_expect_tx_byte;
        input [7:0] expected;
        reg [7:0] observed;
        integer bit_idx;
        begin
            observed = 8'h00;
            wait (uart_tx == 1'b0);
            repeat (UART_BIT_CYCLES + (UART_BIT_CYCLES / 2)) @(posedge clk);
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                observed[bit_idx] = uart_tx;
                repeat (UART_BIT_CYCLES) @(posedge clk);
            end
            check("UART TX byte", observed, expected);
        end
    endtask

    initial begin
        reg [31:0] rd_val;

        pass_count = 0;
        fail_count = 0;

        PADDR = 32'd0;
        PPROT = 3'd0;
        PSEL = 1'b0;
        PENABLE = 1'b0;
        PWRITE = 1'b0;
        PWDATA = 32'd0;
        PSTRB = 4'd0;
        uart_rx = 1'b1;
        resetn = 1'b0;

        repeat (5) @(posedge clk);
        resetn = 1'b1;
        repeat (2) @(posedge clk);

        apb_write(32'h0000_000C, 32'h0000_0080, 4'h1);
        apb_write(32'h0000_0000, UART_DIVISOR, 4'h1);
        apb_write(32'h0000_0004, 32'h0000_0000, 4'h1);
        apb_write(32'h0000_000C, 32'h0000_0003, 4'h1);

        apb_write(32'h0000_001C, 32'h0000_005A, 4'h1);
        apb_read(32'h0000_001C, rd_val);
        check("UART SCR lane0 write/read", rd_val, 32'h0000_005A);

        apb_write(32'h0000_001C, 32'hAA00_0000, 4'h8);
        apb_read(32'h0000_001C, rd_val);
        check("UART upper-byte write ignored", rd_val, 32'h0000_005A);

        apb_read(32'h0000_0014, rd_val);
        check("UART LSR initial TX empty", rd_val[6:5], 2'b11);

        apb_write(32'h0000_0004, 32'h0000_0001, 4'h1);
        fork
            uart_send_byte(8'h33);
        join_none
        wait (uart_irq == 1'b1);
        apb_read(32'h0000_0014, rd_val);
        check("UART LSR data ready after RX", rd_val[0], 1'b1);
        apb_read(32'h0000_0000, rd_val);
        check("UART RX byte", rd_val, 32'h0000_0033);

        apb_write(32'h0000_0000, 32'h0000_0041, 4'h1);
        uart_expect_tx_byte(8'h41);

        $display("========================================");
        $display("UART 16550A wrapper unit summary");
        $display("pass=%0d fail=%0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED");
        $display("========================================");
        $finish;
    end

endmodule
