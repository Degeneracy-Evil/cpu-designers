`timescale 1ns / 1ps

module uart_tx
#(
    parameter CLK_FRE = 100,     //clock frequency(Mhz)
    parameter BAUD_RATE = 115200 //serial baud rate
)
(
    input                        clk,              //clock input
    input                        rst,            //asynchronous reset input, low active 
    input wire [15:0]            i_baud_div,     //baud rate divider (clock cycles per baud bit), 0 = use default
    input[7:0]                   i_txData_8,          //data to send
    input                        i_txDataValid_1,    //data to be sent is valid
    output reg                   o_txDataReady_1,    //send ready
    output                       o_txPin_1            //serial data output
);
//calculates the clock cycle for baud rate 
localparam [15:0]   DEFAULT_CYCLE = CLK_FRE * 1000000 / BAUD_RATE;
wire [15:0]         cycle_val = (i_baud_div != 16'd0) ? i_baud_div : DEFAULT_CYCLE;
//state machine code
localparam                       S_IDLE       = 1;
localparam                       S_START      = 2;//start bit
localparam                       S_SEND_BYTE  = 3;//data bits
localparam                       S_STOP       = 4;//stop bit
reg[2:0]                         state;
reg[2:0]                         next_state;
reg [15:0]                       cycle_cnt; //baud counter
reg[2:0]                         bit_cnt;//bit counter
reg[7:0]                         tx_data_latch; //latch data to send
reg                              tx_reg; //serial data output
assign o_txPin_1 = tx_reg;
always@(posedge clk or negedge rst)
begin
    if(rst == 1'b0)
        state <= S_IDLE;
    else
        state <= next_state;
end

always@(*)
begin
    case(state)
        S_IDLE:
            if(i_txDataValid_1)
                next_state = S_START;
            else
                next_state = S_IDLE;
        S_START:
            if(cycle_cnt == cycle_val - 1)
                next_state = S_SEND_BYTE;
            else
                next_state = S_START;
        S_SEND_BYTE:
            if(cycle_cnt == cycle_val - 1  && bit_cnt == 3'd7)
                next_state = S_STOP;
            else
                next_state = S_SEND_BYTE;
        S_STOP:
            if(cycle_cnt == cycle_val - 1)
                next_state = S_IDLE;
            else
                next_state = S_STOP;
        default:
            next_state = S_IDLE;
    endcase
end
always@(posedge clk or negedge rst)
begin
    if(rst == 1'b0)
        begin
            o_txDataReady_1 <= 1'b1;
        end
    else if(state == S_IDLE)
        if(i_txDataValid_1)
            o_txDataReady_1 <= 1'b0;
        else
            o_txDataReady_1 <= 1'b1;
    else if(state == S_STOP && cycle_cnt == cycle_val - 1)
            o_txDataReady_1 <= 1'b1;
end


always@(posedge clk or negedge rst)
begin
    if(rst == 1'b0)
        begin
            tx_data_latch <= 8'd0;
        end
    else if(state == S_IDLE && i_txDataValid_1)
            tx_data_latch <= i_txData_8;
        
end

always@(posedge clk or negedge rst)
begin
    if(rst == 1'b0)
        begin
            bit_cnt <= 3'd0;
        end
    else if(state == S_SEND_BYTE) begin
        if(cycle_cnt == cycle_val - 1)
            bit_cnt <= bit_cnt + 3'd1;
    end else
        bit_cnt <= 3'd0;
end


always@(posedge clk or negedge rst)
begin
    if(rst == 1'b0)
        cycle_cnt <= 16'd0;
    else if((state == S_SEND_BYTE && cycle_cnt == cycle_val - 1) || next_state != state)
        cycle_cnt <= 16'd0;
    else if(state != S_IDLE)
        cycle_cnt <= cycle_cnt + 16'd1;
    // BUG-55b: Guard — cycle_cnt must not increment when UART is idle.
    // Without this guard, cycle_cnt free-runs every clock cycle in S_IDLE,
    // generating unnecessary simulation events (16-bit toggle every cycle).
end

always@(posedge clk or negedge rst)
begin
    if(rst == 1'b0)
        tx_reg <= 1'b1;
    else
        case(state)
            S_IDLE,S_STOP:
                tx_reg <= 1'b1; 
            S_START:
                tx_reg <= 1'b0; 
            S_SEND_BYTE:
                tx_reg <= tx_data_latch[bit_cnt];
            default:
                tx_reg <= 1'b1; 
        endcase
end

endmodule 
