`timescale 1ns / 1ps

// =========================================================================
// Debug UART Transmitter
// Sends display_name and display_value as formatted text via UART.
// Format: "NAME=HHHHHHHH\r\n" (16 chars per line)
// When enable=1, takes over the UART TX pin. When enable=0, UART TX=idle.
// =========================================================================
module debug_uart_tx(
    input         clk,           // 100MHz sys_clk
    input         resetn,
    input         enable,        // sw[5]: 1=debug UART mode, 0=normal
    input  [39:0] display_name,  // 5 ASCII chars
    input  [31:0] display_value, // 32-bit value
    input         display_valid,
    output reg    uart_tx,
    output reg    scan_advance   // pulse: tell parent to advance display_number
);

    // Baud rate: 230400, Clock: 100MHz
    // Baud divisor: 100_000_000 / 230400 = 434.03
    localparam [9:0] BAUD_DIV = 10'd433;  // 434-1

    // Line format: "NAME=HHHHHHHH\r\n" = 16 chars
    localparam LINE_LEN = 16;

    // State machine
    localparam [2:0] S_IDLE   = 3'd0;
    localparam [2:0] S_FORMAT = 3'd1;
    localparam [2:0] S_SEND   = 3'd2;
    localparam [2:0] S_DELAY  = 3'd3;
    localparam [2:0] S_ADV    = 3'd4;  // advance scan counter + wait for fresh data

    reg [2:0]  state;
    reg [4:0]  char_idx;       // 0..15
    reg [9:0]  baud_cnt;
    reg [3:0]  bit_idx;        // 0=start, 1-8=data, 9=stop, 10=done
    reg [7:0]  shift_reg;
    reg [23:0] delay_cnt;      // 24-bit for longer delay

    // Skip entries whose label is all spaces (undefined LCD slots)
    wire label_is_blank = (display_name == 40'h2020202020);

    // Line buffer (registered)
    reg [7:0] line_buf [0:15];

    // Hex digit to ASCII conversion
    function [7:0] hex2asc;
        input [3:0] h;
        begin
            hex2asc = (h < 4'hA) ? (h + 8'h30) : (h + 8'h37);
        end
    endfunction

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state     <= S_IDLE;
            char_idx  <= 5'd0;
            baud_cnt  <= 10'd0;
            bit_idx   <= 4'd0;
            shift_reg <= 8'd0;
            uart_tx   <= 1'b1;   // UART idle = high
            delay_cnt <= 24'd0;
            scan_advance <= 1'b0;
        end else if (!enable) begin
            uart_tx   <= 1'b1;   // idle high when disabled
            state     <= S_IDLE;
            baud_cnt  <= 10'd0;
            bit_idx   <= 4'd0;
            char_idx  <= 5'd0;
            scan_advance <= 1'b0;
        end else begin
            case (state)
                // ── Wait for valid data, then format line ──
                S_IDLE: begin
                    if (display_valid && !label_is_blank) begin
                        // Format: "NAME=HHHHHHHH\r\n"
                        line_buf[0]  <= display_name[39:32];
                        line_buf[1]  <= display_name[31:24];
                        line_buf[2]  <= display_name[23:16];
                        line_buf[3]  <= display_name[15:8];
                        line_buf[4]  <= display_name[7:0];
                        line_buf[5]  <= 8'h3D;  // '='
                        line_buf[6]  <= hex2asc(display_value[31:28]);
                        line_buf[7]  <= hex2asc(display_value[27:24]);
                        line_buf[8]  <= hex2asc(display_value[23:20]);
                        line_buf[9]  <= hex2asc(display_value[19:16]);
                        line_buf[10] <= hex2asc(display_value[15:12]);
                        line_buf[11] <= hex2asc(display_value[11:8]);
                        line_buf[12] <= hex2asc(display_value[7:4]);
                        line_buf[13] <= hex2asc(display_value[3:0]);
                        line_buf[14] <= 8'h0D;  // \r
                        line_buf[15] <= 8'h0A;  // \n
                        char_idx <= 5'd0;
                        baud_cnt <= 10'd0;
                        bit_idx  <= 4'd0;
                        state    <= S_FORMAT;
                    end
                end

                // ── Wait one cycle for line_buf to settle ──
                S_FORMAT: begin
                    state <= S_SEND;
                end

                // ── Send chars via UART ──
                S_SEND: begin
                    if (baud_cnt == BAUD_DIV) begin
                        baud_cnt <= 10'd0;
                        if (bit_idx == 4'd0) begin
                            // Start bit
                            uart_tx   <= 1'b0;
                            shift_reg <= line_buf[char_idx];
                            bit_idx   <= 4'd1;
                        end else if (bit_idx <= 4'd8) begin
                            // Data bits (LSB first)
                            uart_tx   <= shift_reg[0];
                            shift_reg <= shift_reg >> 1;
                            bit_idx   <= bit_idx + 1;
                        end else if (bit_idx == 4'd9) begin
                            // Stop bit
                            uart_tx <= 1'b1;
                            bit_idx <= 4'd10;
                        end else begin
                            // bit_idx == 10: char complete
                            bit_idx <= 4'd0;
                            if (char_idx == 5'd15) begin
                                state     <= S_DELAY;
                                delay_cnt <= 24'd0;
                            end else begin
                                char_idx <= char_idx + 1;
                            end
                        end
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end

                // ── Inter-line delay (~16ms at 100MHz) ──
                S_DELAY: begin
                    if (delay_cnt == 24'hFFFFFF) begin
                        state        <= S_ADV;
                        scan_advance <= 1'b1;  // pulse: advance to next entry
                        delay_cnt    <= 24'd0;
                    end else begin
                        delay_cnt <= delay_cnt + 1;
                    end
                end

                // ── Advance done, wait for fresh display_valid ──
                S_ADV: begin
                    // Phase 1: pulse scan_advance for 1 cycle
                    // Phase 2: wait for display_valid to drop (old data clearing)
                    // Phase 3: wait for display_valid to rise (new data ready)
                    if (delay_cnt < 24'd20) begin
                        // Brief settling period after scan_advance
                        // (~20 cycles needed for CDC round-trip)
                        scan_advance <= (delay_cnt == 24'd0) ? 1'b1 : 1'b0;
                        delay_cnt    <= delay_cnt + 1;
                    end else begin
                        // Now wait for fresh display_valid
                        if (display_valid && !label_is_blank) begin
                            state <= S_FORMAT;
                            // Latch line_buf here
                            line_buf[0]  <= display_name[39:32];
                            line_buf[1]  <= display_name[31:24];
                            line_buf[2]  <= display_name[23:16];
                            line_buf[3]  <= display_name[15:8];
                            line_buf[4]  <= display_name[7:0];
                            line_buf[5]  <= 8'h3D;  // '='
                            line_buf[6]  <= hex2asc(display_value[31:28]);
                            line_buf[7]  <= hex2asc(display_value[27:24]);
                            line_buf[8]  <= hex2asc(display_value[23:20]);
                            line_buf[9]  <= hex2asc(display_value[19:16]);
                            line_buf[10] <= hex2asc(display_value[15:12]);
                            line_buf[11] <= hex2asc(display_value[11:8]);
                            line_buf[12] <= hex2asc(display_value[7:4]);
                            line_buf[13] <= hex2asc(display_value[3:0]);
                            line_buf[14] <= 8'h0D;  // \r
                            line_buf[15] <= 8'h0A;  // \n
                            char_idx <= 5'd0;
                            baud_cnt <= 10'd0;
                            bit_idx  <= 4'd0;
                        end
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
