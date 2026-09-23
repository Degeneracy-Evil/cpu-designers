`timescale 1ns / 1ps

/**
 * tb_uart_echo — Testbench for UART echo program.
 *
 * Stimulus:  A UART TX engine sends a known string into i_rx.
 * Checker:   A UART RX decoder monitors o_tx and captures echoed bytes.
 *            After sending the full stimulus, the decoded output is
 *            compared byte-by-byte against the expected echo.
 *
 * Topology:  core_top + ahb_lite_bus (same as tb_uart_hello).
 */

module tb_uart_echo;

    // ----------------------------------------------------------------
    //  Clock & reset
    // ----------------------------------------------------------------

    // Shared boilerplate: system_top, clock, reset, debug signals, check_reg, check_mem_word
    `include "support/soc_fixture.svh"


    wire reset = ~resetn;
    // Use accelerated baud rate matching forced dl=16
    // NS16550A bit period = 16 enables × dl cycles = 16 × 16 = 256 cycles
    localparam CYCLE      = 256;
    localparam HALF_CYCLE = CYCLE / 2;

    // ----------------------------------------------------------------
    //  Stimulus: string to send via UART TX engine → i_rx
    // ----------------------------------------------------------------
    localparam STIM_LEN = 5;
    reg [7:0] stim_msg [0:STIM_LEN-1];

    initial begin
        stim_msg[0] = "E";
        stim_msg[1] = "c";
        stim_msg[2] = "h";
        stim_msg[3] = "o";
        stim_msg[4] = "!";
    end

    // ----------------------------------------------------------------
    //  UART TX stimulus engine (sends bytes into i_rx pin)
    //  Protocol: idle=1, start=0, 8 data bits (LSB first), stop=1
    // ----------------------------------------------------------------
    localparam TX_IDLE  = 3'd0;
    localparam TX_START = 3'd1;
    localparam TX_DATA  = 3'd2;
    localparam TX_STOP  = 3'd3;
    localparam TX_BOOT  = 3'd4;   // boot delay before first stimulus

    reg [2:0]  tx_state;
    reg [7:0]  tx_shift;
    reg [2:0]  tx_bit_cnt;
    integer    tx_timer;
    integer    tx_byte_idx;
    reg        tx_active;       // high while stimulus is being sent
    reg        tx_done;         // high once all bytes have been sent

    always @(posedge clk) begin
        if (reset) begin
            tx_state    <= TX_BOOT;
            tx_shift    <= 8'h0;
            tx_bit_cnt  <= 3'd0;
            tx_timer    <= 0;
            tx_byte_idx <= 0;
            tx_active   <= 1'b0;
            tx_done     <= 1'b0;
            uart_rx     <= 1'b1;     // idle high
        end else begin
            case (tx_state)
                TX_BOOT: begin
                    uart_rx <= 1'b1;
                    // Wait for DUT to boot and init UART
                    if (tx_timer >= 50000) begin
                        tx_state <= TX_IDLE;
                        tx_timer <= 0;
                    end else begin
                        tx_timer <= tx_timer + 1;
                    end
                end

                TX_IDLE: begin
                    uart_rx <= 1'b1;
                    if (tx_byte_idx < STIM_LEN && !tx_active) begin
                        tx_shift  <= stim_msg[tx_byte_idx];
                        tx_state  <= TX_START;
                        tx_timer  <= 0;
                        tx_active <= 1'b1;
                    end else if (tx_byte_idx >= STIM_LEN) begin
                        tx_done   <= 1'b1;
                        tx_active <= 1'b0;
                    end
                end

                TX_START: begin
                    uart_rx <= 1'b0;     // start bit
                    if (tx_timer == CYCLE - 1) begin
                        tx_state   <= TX_DATA;
                        tx_bit_cnt <= 3'd0;
                        tx_timer   <= 0;
                    end else begin
                        tx_timer <= tx_timer + 1;
                    end
                end

                TX_DATA: begin
                    uart_rx <= tx_shift[0];   // LSB first
                    if (tx_timer == CYCLE - 1) begin
                        tx_shift   <= {1'b0, tx_shift[7:1]};
                        tx_bit_cnt <= tx_bit_cnt + 3'd1;
                        tx_timer   <= 0;
                        if (tx_bit_cnt == 3'd7) begin
                            tx_state <= TX_STOP;
                        end
                    end else begin
                        tx_timer <= tx_timer + 1;
                    end
                end

                TX_STOP: begin
                    uart_rx <= 1'b1;     // stop bit
                    if (tx_timer == CYCLE - 1) begin
                        tx_state    <= TX_IDLE;
                        tx_byte_idx <= tx_byte_idx + 1;
                        tx_active   <= 1'b0;
                    end else begin
                        tx_timer <= tx_timer + 1;
                    end
                end

                default: begin
                    uart_rx  <= 1'b1;
                    tx_state <= TX_IDLE;
                end
            endcase
        end
    end

    // ----------------------------------------------------------------
    //  UART RX checker (decodes bytes from o_tx pin)
    //  Same structure as tb_uart_hello.sv
    // ----------------------------------------------------------------
    localparam RX_IDLE  = 2'd0;
    localparam RX_START = 2'd1;
    localparam RX_DATA  = 2'd2;
    localparam RX_STOP  = 2'd3;

    reg [1:0]  rx_state;
    reg [7:0]  rx_shift;
    reg [2:0]  rx_bit_cnt;
    integer    rx_timer;

    localparam MAX_DECODE = 32;         // max captured bytes
    reg [7:0]  decoded_msg [0:MAX_DECODE-1];
    integer    decoded_count;

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
                    if (rx_timer == HALF_CYCLE - 1) begin
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
                        if (decoded_count < MAX_DECODE) begin
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

    // ----------------------------------------------------------------
    //  Test control: reset, wait for echo, then compare
    // ----------------------------------------------------------------

    integer i;

    initial begin
        pass_count = 0;
        fail_count = 0;

        // Wait long enough for:
        //   1. CPU to boot and init UART
        //   2. Stimulus TX engine to send all STIM_LEN bytes
        //   3. CPU to echo each byte back via UART TX
        //   4. RX checker to decode all echoed bytes
        // With accelerated baud (CYCLE=256), each byte ≈ 2560 cycles.
        // Add generous margin for CPU processing.
        repeat (1000000) @(posedge clk);

        $display("========================================");
        $display("UART Echo test");
        $display("Stimulus : %0d bytes", STIM_LEN);
        $display("Decoded  : %0d bytes:", decoded_count);
        for (i = 0; i < decoded_count; i = i + 1)
            $write("%c", decoded_msg[i]);
        $display("");

        // Check: decoded count should equal stimulus length
        if (decoded_count < STIM_LEN) begin
            fail_count = fail_count + 1;
            $display("FAIL: expected at least %0d echoed chars, got %0d",
                     STIM_LEN, decoded_count);
        end else begin
            pass_count = pass_count + 1;
            $display("PASS: decoded count >= %0d", STIM_LEN);
        end

        // Check: each decoded byte should match the stimulus (echo)
        for (i = 0; i < STIM_LEN; i = i + 1) begin
            if (i < decoded_count) begin
                if (decoded_msg[i] === stim_msg[i]) begin
                    pass_count = pass_count + 1;
                    $display("PASS echo[%0d]: sent='%c' (0x%02h) recv='%c' (0x%02h)",
                             i, stim_msg[i], stim_msg[i],
                             decoded_msg[i], decoded_msg[i]);
                end else begin
                    fail_count = fail_count + 1;
                    $display("FAIL echo[%0d]: sent='%c' (0x%02h) recv='%c' (0x%02h)",
                             i, stim_msg[i], stim_msg[i],
                             decoded_msg[i], decoded_msg[i]);
                end
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL echo[%0d]: sent='%c' (0x%02h) recv=MISSING",
                         i, stim_msg[i], stim_msg[i]);
            end
        end

        $display("========================================");
        $display("UART Echo test summary: pass=%0d fail=%0d",
                 pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $fatal(1, "TEST FAILED");
        $display("========================================");
        $finish;
    end


endmodule

