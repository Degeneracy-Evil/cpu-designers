`timescale 1ns / 1ps

module spi(

    input wire       clk,
    input wire       rst,
    
    //来自总线的信号
    input wire      i_cs_1,
    input wire      i_as_1,
    input wire      i_rw_1,
    
    //输出到总线
    output reg      o_rdy_1,
    
//    input wire       we_i,
    input wire[31:0] i_data_32,
    input wire[31:0] i_addr_32,
    output reg[31:0] o_data_32,

    output reg       o_spiMosi_1,             // spi控制器输出、spi设备输入信号
    input  wire      i_spiMiso_1,             // spi控制器输入、spi设备输出信号
    output wire      o_spiSs_1,              // spi设备片选
    output reg       o_spiClk_1               // spi设备时钟，最大频率为输入clk的一半

    );

    localparam SPI_CTRL   = 4'h0;    // spi_ctrl寄存器地址偏移
    localparam SPI_DATA   = 4'h4;    // spi_data寄存器地址偏移
    localparam SPI_STATUS = 4'h8;    // spi_status寄存器地址偏移

    // spi控制寄存器
    // addr: 0x00
    // [0]: 1: enable, 0: disable
    // [1]: CPOL
    // [2]: CPHA
    // [3]: select slave, 1: select, 0: deselect
    // [15:8]: clk div
    reg[31:0] spi_ctrl;
    // spi数据寄存器
    // addr: 0x04
    // [7:0] cmd or inout data
    reg[31:0] spi_data;
    // spi状态寄存器
    // addr: 0x08
    // [0]: 1: busy, 0: idle
    reg[31:0] spi_status;

    reg[8:0] clk_cnt;               // 分频计数
    reg en;                         // 使能，开始传输信号，传输期间一直有效
    reg[4:0] spi_clk_edge_cnt;      // spi clk时钟沿的个数
    reg spi_clk_edge_level;         // spi clk沿电平
    reg[7:0] rdata;                 // 从spi设备读回来的数据
    reg done;                       // 传输完成信号
    reg[3:0] bit_index;             // 数据bit索引
    wire[8:0] div_cnt;


    assign o_spiSs_1 = ~spi_ctrl[3];   // SPI设备片选信号
    assign div_cnt = spi_ctrl[15:8];// 0: 2分频，1：4分频，2：8分频，3：16分频，4：32分频，以此类推

    // 产生使能信号
    // 传输期间一直有效
    always @ (posedge clk or negedge rst) begin
        if (!rst) begin
            en <= 1'b0;
            o_rdy_1<=1'b1;
        end else begin
            /*就绪信号生成*/
            if((i_cs_1 == 1'b0)&&(i_as_1==1'b0))begin//改动
                o_rdy_1<= 1'b0;
            end else begin
                o_rdy_1<=1'b1;
            end
            if (spi_ctrl[0] == 1'b1 && (i_cs_1==1'b0)&&(i_as_1==1'b0)) begin
                en <= 1'b1;
            end else if (done == 1'b1) begin
                en <= 1'b0;
            end else begin
                en <= en;
            end
        end
    end

    // 对输入时钟进行计数
    always @ (posedge clk or negedge rst) begin
        if (!rst) begin
            clk_cnt <= 9'h0;
        end else if (en == 1'b1) begin
            if (clk_cnt == div_cnt) begin
                clk_cnt <= 9'h0;
            end else begin
                clk_cnt <= clk_cnt + 1'b1;
            end
        end else begin
            clk_cnt <= 9'h0;
        end
    end

    // 对spi clk沿进行计数
    // 每当计数到分频值时产生一个上升沿脉冲
    always @ (posedge clk or negedge rst) begin
        if (!rst) begin
            spi_clk_edge_cnt <= 5'h0;
            spi_clk_edge_level <= 1'b0;
        end else if (en == 1'b1) begin
            // 计数达到分频值
            if (clk_cnt == div_cnt) begin
                if (spi_clk_edge_cnt == 5'd17) begin
                    spi_clk_edge_cnt <= 5'h0;
                    spi_clk_edge_level <= 1'b0;
                end else begin
                    spi_clk_edge_cnt <= spi_clk_edge_cnt + 1'b1;
                    spi_clk_edge_level <= 1'b1;
                end
            end else begin
                spi_clk_edge_level <= 1'b0;
            end
        end else begin
            spi_clk_edge_cnt <= 5'h0;
            spi_clk_edge_level <= 1'b0;
        end
    end

    // bit序列
    always @ (posedge clk or negedge rst) begin
        if (!rst) begin
            o_spiClk_1 <= 1'b0;
            rdata <= 8'h0;
            o_spiMosi_1 <= 1'b0;
            bit_index <= 4'h0;
        end else begin
            if (en) begin
                if (spi_clk_edge_level == 1'b1) begin
                    case (spi_clk_edge_cnt)
                        // 第奇数个时钟沿
                        1, 3, 5, 7, 9, 11, 13, 15: begin
                            o_spiClk_1 <= ~o_spiClk_1;
                            if (spi_ctrl[2] == 1'b1) begin
                                o_spiMosi_1 <= spi_data[bit_index];   // 送出1bit数据
                                bit_index <= bit_index - 1'b1;
                            end else begin
                                rdata <= {rdata[6:0], i_spiMiso_1};   // 读1bit数据
                            end
                        end
                        // 第偶数个时钟沿
                        2, 4, 6, 8, 10, 12, 14, 16: begin
                            o_spiClk_1 <= ~o_spiClk_1;
                            if (spi_ctrl[2] == 1'b1) begin
                                rdata <= {rdata[6:0], i_spiMiso_1};   // 读1bit数据
                            end else begin
                                o_spiMosi_1 <= spi_data[bit_index];   // 送出1bit数据
                                bit_index <= bit_index - 1'b1;
                            end
                        end
                        17: begin
                            o_spiClk_1 <= spi_ctrl[1];
                        end
                    endcase
                end
            end else begin
                // 初始状态
                o_spiClk_1 <= spi_ctrl[1];
                if (spi_ctrl[2] == 1'b0) begin
                    o_spiMosi_1 <= spi_data[7];           // 送出最高位数据
                    bit_index <= 4'h6;
                end else begin
                    bit_index <= 4'h7;
                end
            end
        end
    end

    // 产生结束(完成)信号
    always @ (posedge clk or negedge rst) begin
        if (!rst) begin
            done <= 1'b0;
        end else begin
            if (en && spi_clk_edge_cnt == 5'd17) begin
                done <= 1'b1;
            end else begin
                done <= 1'b0;
            end
        end
    end

    // write reg
    always @ (posedge clk or negedge rst) begin
        if (!rst) begin
            spi_ctrl <= 32'h0;
            spi_data <= 32'h0;
            spi_status <= 32'h0;
        end else begin
            spi_status[0] <= en;
            if (i_rw_1 == 1'b0) begin//改动
                case (i_addr_32[3:0])
                    SPI_CTRL: begin
                        spi_ctrl <= i_data_32;
                    end
                    SPI_DATA: begin
                        spi_data <= i_data_32;
                    end
                    default: begin

                    end
                endcase
            end else begin
                spi_ctrl[0] <= 1'b0;
                // 发送完成后更新数据寄存器
                if (done == 1'b1) begin
                    spi_data <= {24'h0, rdata};
                end
            end
        end
    end

    // read reg
    always @ (*) begin
        if (!rst) begin
            o_data_32 = 32'h0;
        end else begin
            case (i_addr_32[3:0])
                SPI_CTRL: begin
                    o_data_32 = spi_ctrl;
                end
                SPI_DATA: begin
                    o_data_32 = spi_data;
                end
                SPI_STATUS: begin
                    o_data_32 = spi_status;
                end
                default: begin
                    o_data_32 = 32'h0;
                end
            endcase
        end
    end

endmodule