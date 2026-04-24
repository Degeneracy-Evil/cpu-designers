`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2023/07/17 14:55:55
// Design Name: 
// Module Name: uart_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
`include "bus_define.vh"

module uart_top
(
input wire                          cs_,         
input  wire                         as_,         
input  wire                         rw,          
input  wire[31:0]                   addr,
input wire[31:0]                    wr_data,
input wire                          clk,
input  wire                         reset,
input  wire                         rx,
output wire[31:0]                   rd_data,
output reg                          rdy_,
output wire                         tx   
);
 wire [7:0] rx_data;
    reg rx_over;

    // ¼Ä´æÆ÷(Æ«ÒÆ)µØÖ·
    localparam UART_CTRL    = 8'h0;
    localparam UART_STATUS  = 8'h4;
    localparam UART_TXDATA  = 8'h8;
    localparam UART_RXDATA  = 8'hc;

    // UART¿ØÖÆ¼Ä´æÆ÷£¬¿É¶Á¿ÉÐ´
    // bit[0]: UART TXÊ¹ÄÜ, 1: enable, 0: disable
    // bit[1]: UART RXÊ¹ÄÜ, 1: enable, 0: disable
    reg[31:0] uart_ctrl;

    // UART×´Ì¬¼Ä´æÆ÷
    // Ö»¶Á£¬bit[0]: TX¿ÕÏÐ×´Ì¬±êÖ¾, 1: busy, 0: idle
    // ¿É¶Á¿ÉÐ´£¬bit[1]: RX½ÓÊÕÍê³É±êÖ¾, 1: over, 0: receiving
    reg[31:0] uart_status;

    // UART·¢ËÍÊý¾Ý¼Ä´æÆ÷£¬¿É¶Á¿ÉÐ´
    reg[31:0] uart_tx;

    // UART½ÓÊÕÊý¾Ý¼Ä´æÆ÷£¬Ö»¶Á
    reg[31:0] uart_rx;
	
    wire tx_data_ready;
    wire rx_data_valid;
    wire wen = 1'b1 ;
    wire write_reg_ctrl_en = wen & (addr[7:0] == UART_CTRL);
    wire write_reg_status_en = wen & (addr[7:0] == UART_STATUS);
    wire write_reg_txdata_en = wen & (addr[7:0] == UART_TXDATA);
    wire tx_start = write_reg_txdata_en  & uart_ctrl[0] & (~uart_status[0]) & tx_data_ready;
    wire rx_recv_over = uart_ctrl[1] & rx_data_valid;



    always @ (posedge clk or negedge reset) begin
        if (!reset) begin
            uart_rx <= 32'h0;
        end else begin
            if((cs_== `ENABLE_)&&(as_==`ENABLE_))begin
                rdy_ <=`ENABLE_;
            end else begin
                rdy_<=`DISABLE_;
            end
            // Ð´uart_rxdata
            if((cs_== `ENABLE_)&&(as_==`ENABLE_)&&(rw==`READ))begin
                // ½ÓÊÕÍê³ÉÊ±£¬±£´æ½ÓÊÕµ½µÄÊý¾Ý
                if (rx_recv_over) begin
                    uart_rx[7:0] <= rx_data;
                end
            end
            //Ð´uart_txdata
            if((cs_== `ENABLE_)&&(as_==`ENABLE_)&&(rw==`WRITE))begin
               // ¿ªÊ¼·¢ËÍÊ±£¬±£´æÒª·¢ËÍµÄÊý¾Ý
            if (tx_start) begin
                uart_tx[7:0] <= wr_data[7:0];
            end
            end
         end
    end

    // Ð´uart_status
    always @ (posedge clk or negedge reset) begin
        if (!reset) begin
            uart_status <= 32'h0;
        end else begin
            if (write_reg_status_en) begin
                // Ð´RXÍê³É±êÖ¾
                uart_status[1] <= wr_data[1];
                
            end else begin
                // ¿ªÊ¼·¢ËÍÊý¾ÝÊ±£¬ÖÃÎ»TXÃ¦±êÖ¾
                if (tx_start) begin
                    uart_status[0] <= 1'b1;
                // ·¢ËÍÍê³ÉÊ±£¬ÇåTXÃ¦±êÖ¾
                end else if (tx_data_ready == 1'b1) begin
                    uart_status[0] <= 1'b0;
                // ½ÓÊÕÍê³É£¬ÖÃÎ»½ÓÊÕÍê³É±êÖ¾
                end
                if (rx_recv_over) begin
                    uart_status[1] <= 1'b1;
                end
            end
        end
    end

    // Ð´uart_ctrl
    always @ (posedge clk or negedge reset) begin
        if (!reset) begin
            uart_ctrl <= 32'h0;
        end else begin
            if (write_reg_ctrl_en) begin
                uart_ctrl <= {24'b0,wr_data[7:0]};
            end
        end
    end

assign rd_data = (addr[7:0] == UART_CTRL) ? uart_ctrl:
                (addr[7:0] == UART_STATUS) ? uart_status:
                (addr[7:0] == UART_RXDATA) ? uart_rx:32'b0;
/***************************************************************************
calling uart_tx module and uart_rx module
****************************************************************************/
    uart_rx#
    (
        .CLK_FRE(50),
        .BAUD_RATE(115200)
    ) uart_rx_inst
    (
        .clk                        (clk                      ),
        .rst_n                      (reset                    ),
        .rx_data                    (rx_data                  ),
        .rx_data_valid              (rx_data_valid            ),
        .rx_data_ready              (uart_ctrl[1]             ),
        .rx_pin                     (rx                   )
    );
    
    uart_tx#
    (
        .CLK_FRE(50),
        .BAUD_RATE(115200)
    ) uart_tx_inst
    (
        .clk                        (clk                     ),
        .rst_n                      (reset                   ),
        .tx_data                    (uart_tx[7:0]            ),
        .tx_data_valid              (tx_start                ),
        .tx_data_ready              (tx_data_ready           ), 
        .tx_pin                     (tx                  )
    );

endmodule
