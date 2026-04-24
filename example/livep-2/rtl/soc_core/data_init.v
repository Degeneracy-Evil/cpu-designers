`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2023/07/18 17:46:05
// Design Name: 
// Module Name: data_init
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


module data_init
(
    input wire         clk,
    input wire         rst_n,                      //复位信号，低电平有效
    input wire         uart_rx,                    //用于接收外部数据（即数据包），每次接收1bit
    input wire         enable,                     //使能信号，为高电平则该模块工作
    output wire        uart_tx,                    //用于CRC校验后发送ACK/NAK信号，与uart_rx一样，每次传输1bit数据
    
    output wire        ibus_we,                    //Icache写使能信号，当数据发送给Icache时有效
    output wire [31:0] ibus_addr_o,                //Icache的目的地址
    output wire [31:0] ibus_data_o,                //发送往Icache的数据，从data寄存器中取出，每次发送32bit
    output wire        dbus_we,                    //Dcache写使能信号，当数据发送给Dcache时有效
    output wire [31:0] dbus_addr_o,                //Dcache的目的地址
    output wire [31:0] dbus_data_o                 //发送往Dcache的数据，从data寄存器中取出，每次发送32bit
);

    localparam UART_RESP_ACK          = 8'h6  ;    //uart接收确认信号ACK
    localparam UART_RESP_NAK          = 8'h15 ;    //uart接收未确认信号NAK
    localparam UART_REMAIN_PACKET_LEN = 8'd131;    //数据包长度131Byte

    //data_init状态机，独热码
    localparam  IDLE       =  12'h000;
    localparam  NUM        =  12'h001;
    localparam  DATA0      =  12'h002;
    localparam  DATA1      =  12'h004;
    localparam  DATA2      =  12'h008;
    localparam  DATA3      =  12'h010;
    localparam  SEND       =  12'h020;
    localparam  CRC1       =  12'h040;
    localparam  CRC_START  =  12'h080;
    localparam  CRC_CALC   =  12'h100;
    localparam  CRC_END    =  12'h200;
    localparam  ACK        =  12'h400;
    localparam  NAK        =  12'h800;

    reg        r_ibus_we;
    reg [31:0] r_ibus_addr_o;
    reg [31:0] r_ibus_data_o;
    reg        r_dbus_we;
    reg [31:0] r_dbus_addr_o;
    reg [31:0] r_dbus_data_o;
    
    reg [ 7:0] tx_data;          //DATAing data
    reg        tx_data_valid;    //DATAing data valid
    wire       tx_data_ready;    //singal for DATAing data
    wire [7:0] rx_data;          //receiving data
    wire       rx_data_valid;    // receiving data valid
    wire       rx_data_ready;    // singal for receiving data
    reg [13:0] c_state;     
    reg [13:0] n_state;  
    wire       rstn;
    assign rstn          = rst_n & enable;

    assign rx_data_ready = 1'b1;
    
    reg [31:0] data;             //接收来自rx的数据，每次接收8bit
    reg [ 7:0]  count;           //已接收多少Byte的数据，累计至128时数据部分接收完毕，进入CRC
    reg [31:0] addr_i;           //Icache地址
    reg [31:0] addr_d;           //Dcache地址
    reg        valid;            //SEND状态暂存rx_data_valid信号
    
    //文件大小包的序号，用于标识发往Icache还是Dcache
    reg [ 7:0] number;
    //是否为第一个包（第一个包只需CRC不需要存储）
    reg [ 7:0] first;

    //用于CRC计算
    reg [ 7:0] crc_data[0:128];
    reg [ 7:0] rec_bytes_index;
    reg [ 7:0] need_to_rec_bytes;
    reg [15:0] crc_result;
    reg [ 3:0] crc_bit_index;
    reg [ 7:0] crc_byte_index;
    reg [15:0] r_crc_16;

    //-----{三段式状态机}begin
    //-----{时序逻辑，描述状态转移}begin
    always @(posedge clk or negedge rstn) begin
        if(!rstn)
            c_state <= IDLE;
        else 
            c_state <= n_state;
    end
    //-----{时序逻辑，描述状态转移}end

    //-----{组合逻辑，判断状态转移条件}begin
    always @(*) begin
        case (c_state)
            IDLE:begin
                if(rx_data_valid == 1'b1)
                    n_state = NUM;
                else 
                    n_state = IDLE;
            end
            NUM:begin
                if(rx_data_valid == 1'b1)
                    n_state = DATA0;
                else 
                    n_state = NUM;
            end
            DATA0:begin
                if(rx_data_valid == 1'b1)
                    n_state = DATA1;
                else 
                    n_state = DATA0;
            end
            DATA1:begin
                if(rx_data_valid == 1'b1)
                    n_state = DATA2;
                else 
                    n_state = DATA1;
            end
            DATA2:begin
                if(rx_data_valid == 1'b1)
                    n_state = DATA3;
                else 
                    n_state = DATA2;
            end        
            DATA3:begin
                if(rx_data_valid == 1'b1)
                    n_state = SEND;
                else
                    n_state = DATA3;
            end    
            SEND:begin
                if(count == 8'd128)
                    //n_state = CRC1;
                    n_state = CRC_START;//测试用
                else 
                    n_state = DATA0;
            end
            CRC1:begin
                if(rx_data_valid == 1'b1)
                    n_state = CRC_START;
                else
                    n_state = CRC1;            
            end
            CRC_START:begin
                if(rx_data_valid == 1'b1)
                    n_state = CRC_CALC;
                else
                    n_state = CRC_START;    
            end
            CRC_CALC:begin
                if ((crc_byte_index == need_to_rec_bytes - 2) && crc_bit_index == 4'h8)
                    n_state = CRC_END;
                else 
                    n_state = CRC_CALC;
            end
            CRC_END:begin
                if (crc_result == r_crc_16)
                    n_state = ACK;
                else
                    n_state = NAK;
            end
            ACK:begin
                //如果ACK信号发送完毕，则切换状态
                if(tx_data_ready == 1'b1)
                    n_state = NUM;
                else
                    n_state = ACK;
            end
            NAK:begin
                //如果NAK信号发送完毕，则切换状态
                if(tx_data_ready == 1'b1)
                    n_state = NUM;
                else
                    n_state = NAK;
            end
            default: 
                n_state = IDLE;
        endcase
    end
    //-----{组合逻辑，判断状态转移条件}end
    
    //-----{时序逻辑，对每个状态的输出进行判断}begin
    always @(posedge clk or negedge rstn) begin
        if(!rstn)begin
            r_ibus_we       <= 1'b0;
            r_ibus_addr_o   <= 32'b0;
            r_ibus_data_o   <= 32'b0;
            r_dbus_we       <= 1'b0;
            r_dbus_addr_o   <= 32'b0;
            r_dbus_data_o   <= 32'b0;
            tx_data         <= 8'b0;
            tx_data_valid   <= 1'b0;
            data            <= 32'b0;
            count           <= 8'b0;
            
            addr_i          <= 32'h0;
            //addr_d <= 32'h4000;
            addr_d          <= 32'h0;
            number          <= 8'b0;
            first           <= 8'b0;
            valid           <= 1'b0;
            r_crc_16        <= 16'h0;
            rec_bytes_index <= 8'b1;
        end
        else begin
            case (n_state)
                NUM:      begin
                    r_ibus_we       <= 1'b0;
                    r_dbus_we       <= 1'b0;
                    tx_data_valid   <= 1'b0;
                    rec_bytes_index <= 8'b1;
                    crc_data[0]     <= rx_data;
                    /*
                    first和number都是存放数据包序号，
                    first每来一个数据包都要更新，
                    number只在Icache和Dcache切换时更新
                    */
                    first           <= rx_data;
                        if(rx_data == 8'h0 || rx_data == 8'hff)
                            number  <= rx_data;
                end
                DATA0:    begin
                    r_ibus_we       <= 1'b0;
                    r_dbus_we       <= 1'b0;
                    if(rx_data_valid == 1'b1)begin
                        count       <= count+1;
                        data[7:0]   <= rx_data;
                    end
                    else if(valid == 1'b1)
                        data[7:0]   <= rx_data;
                end 
                DATA1:    begin
                    r_ibus_we       <= 1'b0;
                    r_dbus_we       <= 1'b0;
                    if(rx_data_valid == 1'b1)begin
                        count       <= count+1;
                        data[15:8]  <= rx_data;
                    end
                end
                DATA2:    begin
                    r_ibus_we       <= 1'b0;
                    r_dbus_we       <= 1'b0;
                    if (rx_data_valid == 1'b1) begin
                        count       <= count+1;
                        data[23:16] <= rx_data;
                    end
                end
                DATA3:    begin
                    r_ibus_we       <= 1'b0;
                    r_dbus_we       <= 1'b0;
                    if(rx_data_valid == 1'b1)begin
                        count       <= count+1;
                        data[31:24] <= rx_data;
                    end
                end
                SEND:     begin
                    //crc_data暂存数据包数据以进行CRC校验
                    crc_data[rec_bytes_index  ] <= data[31:24];
                    crc_data[rec_bytes_index+1] <= data[23:16];
                    crc_data[rec_bytes_index+2] <= data[15:8];
                    crc_data[rec_bytes_index+3] <= data[7:0];
                    rec_bytes_index             <= rec_bytes_index+4;
                    valid                       <= rx_data_valid;
                    //根据地址判断发往Icache还是Dcache
                    //先判断发送方向（number），再判断是否为第一个包
                    if(number == 8'h0)begin
                        r_dbus_we     <= 1'b0;
                        r_ibus_addr_o <= addr_i;
                        r_ibus_data_o <= data;
                        if(first != 8'h0)
                          begin
                              r_ibus_we <= 1'b1;
                              addr_i    <= addr_i+4;
                          end
                        else
                          r_ibus_we <= 1'b0;
                    end
                    else if(number == 8'hff) begin
                        r_ibus_we     <= 1'b0;
                        r_dbus_addr_o <= addr_d;
                        r_dbus_data_o <=data;
                        if(first != 8'hff)
                          begin
                              r_dbus_we <= 1'b1;
                              addr_d    <= addr_d+4;
                          end
                        else
                          r_dbus_we <= 1'b0;
                    end
                    else begin                    
                        r_ibus_we     <= 1'b0;
                        r_ibus_addr_o <= 32'b0;
                        r_ibus_data_o <= 32'b0;
                        r_dbus_we     <= 1'b0;
                        r_dbus_addr_o <= 32'b0;
                        r_dbus_data_o <= 32'b0;
                        tx_data       <= 8'b0;
                        tx_data_valid <= 1'b0;
                        data          <= 32'b0;
                        count         <= 8'b0;
                    end
                    if(count < 8'd128)
                        count         <= count+1;
                end
                CRC1:     begin
                    r_crc_16[7:0]  <= rx_data;
                end
                CRC_START:begin
                    r_ibus_we      <= 1'b0;
                    r_dbus_we      <= 1'b0;
                    r_crc_16[15:8] <= rx_data;
                end
                ACK:      begin
                    r_ibus_we     <= 1'b0;
                    r_dbus_we     <= 1'b0;
                    tx_data_valid <= 1'b1;
                    tx_data       <= UART_RESP_ACK;
                end
                NAK:      begin
                    r_ibus_we     <= 1'b0;
                    r_dbus_we     <= 1'b0;
                    tx_data_valid <= 1'b1;
                    tx_data       <= UART_RESP_NAK;
                end
                default:  begin
                    r_ibus_we     <= 1'b0;
                    r_ibus_addr_o <= 32'b0;
                    r_ibus_data_o <= 32'b0;
                    r_dbus_we     <= 1'b0;
                    r_dbus_addr_o <= 32'b0;
                    r_dbus_data_o <= 32'b0;
                    tx_data       <= 8'b0;
                    tx_data_valid <= 1'b0;
                    data          <= 32'b0;
                    count         <= 8'b0;
                end 
            endcase
        end
    end
    //-----{时序逻辑，对每个状态的输出进行判断}end

    assign ibus_we     = r_ibus_we;
    assign ibus_addr_o = r_ibus_addr_o;
    assign ibus_data_o = r_ibus_data_o;
    assign dbus_we     = r_dbus_we;
    assign dbus_addr_o = r_dbus_addr_o;
    assign dbus_data_o = r_dbus_data_o;
    
    //-----{CRC计算}begin
    always @ (posedge clk or negedge rstn) begin
        if (!rstn) begin
            need_to_rec_bytes <= 8'h0;
        end else begin
            need_to_rec_bytes <= UART_REMAIN_PACKET_LEN;
        end
    end

    always @ (posedge clk or negedge rstn) begin
        if (!rstn) begin
            crc_result <= 16'h0;
        end else begin
            case (c_state)
                CRC_START: begin
                    crc_result <= 16'hffff;
                end
                CRC_CALC: begin
                    if (crc_bit_index == 4'h0) begin
                        crc_result <= crc_result ^ crc_data[crc_byte_index];
                    end else begin
                        if (crc_bit_index < 4'h9) begin
                            if (crc_result[0] == 1'b1) begin
                                crc_result <= {1'b0, crc_result[15:1]} ^ 16'ha001;
                            end else begin
                                crc_result <= {1'b0, crc_result[15:1]};
                            end
                        end
                    end
                end
            endcase
        end
    end

    always @ (posedge clk or negedge rstn) begin
        if (!rstn) begin
            crc_bit_index <= 4'h0;
        end else begin
            case (c_state)
                CRC_START: begin
                    crc_bit_index <= 4'h0;
                end
                CRC_CALC: begin
                    if (crc_bit_index < 4'h9) begin
                        crc_bit_index <= crc_bit_index + 1'b1;
                    end else begin
                        crc_bit_index <= 4'h0;
                    end
                end
            endcase
        end
    end

    always @ (posedge clk or negedge rstn) begin
        if (!rstn) begin
            crc_byte_index <= 8'h0;
        end else begin
            case (c_state)
                CRC_START: begin
                    crc_byte_index <= 8'h0;
                end
                CRC_CALC: begin
                    if (crc_bit_index == 4'h0) begin
                        crc_byte_index <= crc_byte_index + 1'b1;
                    end
                end
            endcase
        end
    end
    //-----{CRC计算}end
    
uart_rx#
(
    .CLK_FRE(50),
    .BAUD_RATE(115200)
) uart_rx_inst
(
    .clk                        (clk                      ),
    .rst_n                      (rstn                     ),
    .rx_data                    (rx_data                  ),
    .rx_data_valid              (rx_data_valid            ),
    .rx_data_ready              (rx_data_ready            ),
    .rx_pin                     (uart_rx                  )
);

uart_tx#
(
    .CLK_FRE(50),
    .BAUD_RATE(115200)
) uart_tx_inst
(
    .clk                        (clk                      ),
    .rst_n                      (rstn                     ),
    .tx_data                    (tx_data                  ),
    .tx_data_valid              (tx_data_valid            ),
    .tx_data_ready              (tx_data_ready            ),
    .tx_pin                     (uart_tx                  )
);
endmodule
