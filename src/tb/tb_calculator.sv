`timescale 1ns / 1ps

/**
 * tb_calculator — Testbench for the RISC-V FPU Calculator application.
 *
 * Strategy:
 *   1. Boot the calculator (wait for welcome message + first prompt).
 *   2. Send test expressions one at a time via UART TX.
 *   3. Capture all UART TX output from the DUT via RX decoder.
 *   4. After all expressions, search the captured output for expected
 *      result strings "= <value>".
 *   5. Report PASS/FAIL per expression.
 *
 * Topology: core_top + ahb_lite_bus (same as tb_uart_echo).
 */

module tb_calculator;

    // ----------------------------------------------------------------
    //  Clock & reset
    // ----------------------------------------------------------------

    // Shared boilerplate: system_top, clock, reset, debug signals, check_reg, check_mem_word
    `include "tb_soc_includes.svh"


    wire reset = ~resetn;
    // Use accelerated baud rate matching forced dl=16
    // NS16550A bit period = 16 enables × dl cycles = 16 × 16 = 256 cycles
    localparam CYCLE      = 256;
    localparam HALF_CYCLE = CYCLE / 2;

    // ----------------------------------------------------------------
    //  Test expressions and expected results
    // ----------------------------------------------------------------
    localparam NUM_TESTS = 5;

    // Expression strings (newline-terminated, no trailing NUL — gets() handles null-termination)
    localparam EXPR0_LEN = 4;   // "1+2\n"
    localparam EXPR1_LEN = 4;   // "3*4\n"
    localparam EXPR2_LEN = 5;   // "10-3\n"
    localparam EXPR3_LEN = 4;   // "8/2\n"
    localparam EXPR4_LEN = 8;   // "sqrt(4)\n"

    reg [7:0] expr0 [0:EXPR0_LEN-1];
    reg [7:0] expr1 [0:EXPR1_LEN-1];
    reg [7:0] expr2 [0:EXPR2_LEN-1];
    reg [7:0] expr3 [0:EXPR3_LEN-1];
    reg [7:0] expr4 [0:EXPR4_LEN-1];

    initial begin
        expr0[0]="1"; expr0[1]="+"; expr0[2]="2"; expr0[3]="\n";
        expr1[0]="3"; expr1[1]="*"; expr1[2]="4"; expr1[3]="\n";
        expr2[0]="1"; expr2[1]="0"; expr2[2]="-"; expr2[3]="3"; expr2[4]="\n";
        expr3[0]="8"; expr3[1]="/"; expr3[2]="2"; expr3[3]="\n";
        expr4[0]="s"; expr4[1]="q"; expr4[2]="r"; expr4[3]="t";
        expr4[4]="("; expr4[5]="4"; expr4[6]=")"; expr4[7]="\n";
    end

    // Expected result strings (what appears after "= ")
    localparam RES0_LEN = 8;   // "3.000000"
    localparam RES1_LEN = 9;   // "12.000000"
    localparam RES2_LEN = 8;   // "7.000000"
    localparam RES3_LEN = 8;   // "4.000000"
    localparam RES4_LEN = 8;   // "2.000000"

    reg [7:0] res0 [0:RES0_LEN-1];
    reg [7:0] res1 [0:RES1_LEN-1];
    reg [7:0] res2 [0:RES2_LEN-1];
    reg [7:0] res3 [0:RES3_LEN-1];
    reg [7:0] res4 [0:RES4_LEN-1];

    initial begin
        res0[0]="3"; res0[1]="."; res0[2]="0"; res0[3]="0"; res0[4]="0"; res0[5]="0"; res0[6]="0"; res0[7]="0";
        res1[0]="1"; res1[1]="2"; res1[2]="."; res1[3]="0"; res1[4]="0"; res1[5]="0"; res1[6]="0"; res1[7]="0"; res1[8]="0";
        res2[0]="7"; res2[1]="."; res2[2]="0"; res2[3]="0"; res2[4]="0"; res2[5]="0"; res2[6]="0"; res2[7]="0";
        res3[0]="4"; res3[1]="."; res3[2]="0"; res3[3]="0"; res3[4]="0"; res3[5]="0"; res3[6]="0"; res3[7]="0";
        res4[0]="2"; res4[1]="."; res4[2]="0"; res4[3]="0"; res4[4]="0"; res4[5]="0"; res4[6]="0"; res4[7]="0";
    end

    // ----------------------------------------------------------------
    //  UART TX stimulus engine (sends bytes into i_uart_rx pin)
    //  Sends expressions one at a time with gaps between them.
    // ----------------------------------------------------------------
    localparam TX_IDLE  = 3'd0;
    localparam TX_START = 3'd1;
    localparam TX_DATA  = 3'd2;
    localparam TX_STOP  = 3'd3;
    localparam TX_GAP   = 3'd4;   // inter-expression gap
    localparam TX_BOOT  = 3'd5;   // boot delay before first expression

    reg [3:0]  tx_state;
    reg [7:0]  tx_shift;
    reg [2:0]  tx_bit_cnt;
    integer    tx_timer;
    integer    tx_byte_idx;
    integer    tx_expr_idx;       // which expression we're sending
    integer    tx_expr_len;       // length of current expression
    reg        tx_active;
    reg        tx_all_done;

    // Expression length lookup
    function integer get_expr_len(input integer idx);
        case (idx)
            0: return EXPR0_LEN;
            1: return EXPR1_LEN;
            2: return EXPR2_LEN;
            3: return EXPR3_LEN;
            4: return EXPR4_LEN;
            default: return 0;
        endcase
    endfunction

    // Expression byte lookup
    function [7:0] get_expr_byte(input integer idx, input integer byte_idx);
        case (idx)
            0: return expr0[byte_idx];
            1: return expr1[byte_idx];
            2: return expr2[byte_idx];
            3: return expr3[byte_idx];
            4: return expr4[byte_idx];
            default: return 8'h0;
        endcase
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            tx_state     <= TX_BOOT;  // start with boot delay
            tx_shift     <= 8'h0;
            tx_bit_cnt   <= 3'd0;
            tx_timer     <= 0;
            tx_byte_idx  <= 0;
            tx_expr_idx  <= 0;
            tx_expr_len  <= EXPR0_LEN;
            tx_active    <= 1'b0;
            tx_all_done  <= 1'b0;
            uart_rx      <= 1'b1;
        end else begin
            case (tx_state)
                TX_BOOT: begin
                    uart_rx <= 1'b1;
                    // Wait for calculator to boot and print welcome message + first prompt
                    // With accelerated baud (CYCLE=256), welcome ~95 chars × 2560 cycles ≈ 243K
                    // Plus prompt "> " ≈ 5K cycles. Use 5M cycles for generous margin
                    if (tx_timer >= 5000000) begin
                        tx_state <= TX_IDLE;
                        tx_timer <= 0;
                    end else begin
                        tx_timer <= tx_timer + 1;
                    end
                end

                TX_IDLE: begin
                    uart_rx <= 1'b1;
                    if (tx_expr_idx < NUM_TESTS && !tx_active) begin
                        tx_expr_len <= get_expr_len(tx_expr_idx);
                        tx_shift    <= get_expr_byte(tx_expr_idx, 0);
                        tx_state    <= TX_START;
                        tx_timer    <= 0;
                        tx_active   <= 1'b1;
                        tx_byte_idx <= 0;
                    end else if (tx_expr_idx >= NUM_TESTS) begin
                        tx_all_done <= 1'b1;
                        tx_active   <= 1'b0;
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
                        tx_byte_idx <= tx_byte_idx + 1;
                        if (tx_byte_idx + 1 < tx_expr_len) begin
                            // More bytes in this expression
                            tx_shift <= get_expr_byte(tx_expr_idx, tx_byte_idx + 1);
                            tx_state <= TX_START;
                            tx_timer <= 0;
                        end else begin
                            // Expression complete, go to gap
                            tx_state <= TX_GAP;
                            tx_timer <= 0;
                        end
                    end else begin
                        tx_timer <= tx_timer + 1;
                    end
                end

                TX_GAP: begin
                    uart_rx <= 1'b1;
                    // Wait for calculator to process expression and output result
                    // With accelerated baud (CYCLE=256), result ~20 chars × 2560 ≈ 51K
                    // Use 500K cycles for safety
                    if (tx_timer >= 500000) begin
                        tx_expr_idx <= tx_expr_idx + 1;
                        tx_active   <= 1'b0;
                        tx_state    <= TX_IDLE;
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
    //  UART RX checker (decodes bytes from o_uart_tx pin)
    // ----------------------------------------------------------------
    localparam RX_IDLE  = 2'd0;
    localparam RX_START = 2'd1;
    localparam RX_DATA  = 2'd2;
    localparam RX_STOP  = 2'd3;

    reg [1:0]  rx_state;
    reg [7:0]  rx_shift;
    reg [2:0]  rx_bit_cnt;
    integer    rx_timer;

    localparam MAX_DECODE = 512;        // max captured bytes
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
    //  Result checker: search decoded output for "= <result>" patterns
    // ----------------------------------------------------------------

    // Search for a substring in decoded_msg
    // Returns 1 if found, 0 if not
    function integer find_result(input integer start_idx,
                                 input integer search_len,
                                 input [7:0] pattern [],
                                 input integer pattern_len);
        integer i, j;
        integer match;
        begin
            find_result = 0;
            for (i = start_idx; i < search_len - pattern_len + 1; i = i + 1) begin
                match = 1;
                for (j = 0; j < pattern_len; j = j + 1) begin
                    if (decoded_msg[i + j] !== pattern[j]) begin
                        match = 0;
                    end
                end
                if (match) begin
                    find_result = 1;
                end
            end
        end
    endfunction

    // Build "= <result>" search patterns
    localparam SRCH_MAX = 16;

    reg [7:0] srch0 [0:SRCH_MAX-1];
    reg [7:0] srch1 [0:SRCH_MAX-1];
    reg [7:0] srch2 [0:SRCH_MAX-1];
    reg [7:0] srch3 [0:SRCH_MAX-1];
    reg [7:0] srch4 [0:SRCH_MAX-1];

    initial begin
        // "= 3.000000"
        srch0[0]="="; srch0[1]=" "; srch0[2]="3"; srch0[3]="."; srch0[4]="0"; srch0[5]="0"; srch0[6]="0"; srch0[7]="0"; srch0[8]="0"; srch0[9]="0";
        // "= 12.000000"
        srch1[0]="="; srch1[1]=" "; srch1[2]="1"; srch1[3]="2"; srch1[4]="."; srch1[5]="0"; srch1[6]="0"; srch1[7]="0"; srch1[8]="0"; srch1[9]="0"; srch1[10]="0";
        // "= 7.000000"
        srch2[0]="="; srch2[1]=" "; srch2[2]="7"; srch2[3]="."; srch2[4]="0"; srch2[5]="0"; srch2[6]="0"; srch2[7]="0"; srch2[8]="0"; srch2[9]="0";
        // "= 4.000000"
        srch3[0]="="; srch3[1]=" "; srch3[2]="4"; srch3[3]="."; srch3[4]="0"; srch3[5]="0"; srch3[6]="0"; srch3[7]="0"; srch3[8]="0"; srch3[9]="0";
        // "= 2.000000"
        srch4[0]="="; srch4[1]=" "; srch4[2]="2"; srch4[3]="."; srch4[4]="0"; srch4[5]="0"; srch4[6]="0"; srch4[7]="0"; srch4[8]="0"; srch4[9]="0";
    end

    // ----------------------------------------------------------------
    //  Test control: reset, wait for all output, then verify
    // ----------------------------------------------------------------
    integer i;

    initial begin
        pass_count = 0;
        fail_count = 0;

        // Wait for all 5 expressions to be sent and processed:
        //   Boot: 5M, 5 exprs × ~5K each, 4 gaps × 500K ≈ 7M cycles
        //   Processing: 5 results × ~50K ≈ 250K cycles
        //   Total ≈ 7.3M cycles, use 10M for safety
        repeat (10000000) @(posedge clk);

        $display("========================================");
        $display("Calculator test");
        $display("Decoded %0d bytes:", decoded_count);
        // Print ALL decoded chars
        for (i = 0; i < decoded_count; i = i + 1)
            $write("%c", decoded_msg[i]);
        $display("");
        // Also print hex for debugging
        $write("Hex: ");
        for (i = 0; i < decoded_count; i = i + 1)
            $write("%02h ", decoded_msg[i]);
        $display("");

        // ---- Test 0: 1+2 = 3.000000 ----
        if (find_result(0, decoded_count, srch0, 10)) begin
            pass_count = pass_count + 1;
            $display("PASS test 0: found '= 3.000000'");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL test 0: '= 3.000000' not found");
        end

        // ---- Test 1: 3*4 = 12.000000 ----
        if (find_result(0, decoded_count, srch1, 11)) begin
            pass_count = pass_count + 1;
            $display("PASS test 1: found '= 12.000000'");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL test 1: '= 12.000000' not found");
        end

        // ---- Test 2: 10-3 = 7.000000 ----
        if (find_result(0, decoded_count, srch2, 10)) begin
            pass_count = pass_count + 1;
            $display("PASS test 2: found '= 7.000000'");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL test 2: '= 7.000000' not found");
        end

        // ---- Test 3: 8/2 = 4.000000 ----
        if (find_result(0, decoded_count, srch3, 10)) begin
            pass_count = pass_count + 1;
            $display("PASS test 3: found '= 4.000000'");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL test 3: '= 4.000000' not found");
        end

        // ---- Test 4: sqrt(4) = 2.000000 ----
        if (find_result(0, decoded_count, srch4, 10)) begin
            pass_count = pass_count + 1;
            $display("PASS test 4: found '= 2.000000'");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL test 4: '= 2.000000' not found");
        end

        $display("========================================");
        $display("Calculator test summary: pass=%0d fail=%0d",
                 pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED");
        $display("========================================");
        $finish;
    end


endmodule

