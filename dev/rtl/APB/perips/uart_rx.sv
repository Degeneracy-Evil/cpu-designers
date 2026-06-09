`timescale 1ns / 1ps

module uart_rx
#(
    parameter CLK_FRE = 100,     //clock frequency(Mhz)
    parameter BAUD_RATE = 115200 //serial baud rate
)
(
    input                        clk,              //clock input
    input                        rst_n,          //asynchronous reset input, low active
    output reg[7:0]              o_rxData_8,          //received serial data
    output reg                   o_rxDataValid_1,    //received serial data is valid
    input                        i_rxDataReady_1,    //data receiver module ready
    input                        i_rxPin_1,           //serial data input
    input wire [15:0]            i_baud_div           //baud rate divider (0 = use default)
);
//calculates the clock cycle for baud rate 
localparam [15:0]                       DEFAULT_CYCLE = CLK_FRE * 1000000 / BAUD_RATE;
wire [15:0]                             cycle_val = (i_baud_div != 16'd0) ? i_baud_div : DEFAULT_CYCLE;
//state machine code
localparam                       S_IDLE      = 1;
localparam                       S_START     = 2; //start bit
localparam                       S_REC_BYTE  = 3; //data bits
localparam                       S_STOP      = 4; //stop bit
localparam                       S_DATA      = 5;

reg[2:0]                         state;
reg[2:0]                         next_state;
reg                              rx_d0;            //delay 1 clock for i_rxPin_1
reg                              rx_d1;            //delay 1 clock for rx_d0
wire                             rx_negedge;       //negedge of i_rxPin_1
reg[7:0]                         rx_bits;          //temporary storage of received data
reg[15:0]                        cycle_cnt;        //baud counter
reg[2:0]                         bit_cnt;          //bit counter

assign rx_negedge = rx_d1 && ~rx_d0;

always_ff @(posedge clk or negedge rst_n)
begin
    if(!rst_n)
    begin
        rx_d0 <= 1'b0;
        rx_d1 <= 1'b0;    
    end
    else
    begin
        rx_d0 <= i_rxPin_1;
        rx_d1 <= rx_d0;
    end
end


always_ff @(posedge clk or negedge rst_n)
begin
    if(!rst_n)
        state <= S_IDLE;
    else
        state <= next_state;
end

always_comb
begin
    case(state)
        S_IDLE:
            if(rx_negedge)
                next_state = S_START;
            else
                next_state = S_IDLE;
        S_START:
            if(cycle_cnt == cycle_val - 1)
                next_state = S_REC_BYTE;
            else
                next_state = S_START;
        S_REC_BYTE:
            if(cycle_cnt == cycle_val - 1  && bit_cnt == 3'd7)
                next_state = S_STOP;
            else
                next_state = S_REC_BYTE;
        S_STOP:
            if(cycle_cnt == cycle_val/2 - 1)
                next_state = S_DATA;
            else
                next_state = S_STOP;
        S_DATA:
            if(i_rxDataReady_1)    //data receive complete
                next_state = S_IDLE;
            else
                next_state = S_DATA;
        default:
            next_state = S_IDLE;
    endcase
end

always_ff @(posedge clk or negedge rst_n)
begin
    if(!rst_n)
        o_rxDataValid_1 <= 1'b0;
    else if(state == S_STOP && next_state != state)
        o_rxDataValid_1 <= 1'b1;
    else if(state == S_DATA && i_rxDataReady_1)
        o_rxDataValid_1 <= 1'b0;
end

always_ff @(posedge clk or negedge rst_n)
begin
    if(!rst_n)
        o_rxData_8 <= 8'd0;
    else if(state == S_STOP && next_state != state)
        o_rxData_8 <= rx_bits;//latch received data
end

always_ff @(posedge clk or negedge rst_n)
begin
    if(!rst_n)
        begin
            bit_cnt <= 3'd0;
        end
    else if(state == S_REC_BYTE) begin
        if(cycle_cnt == cycle_val - 1)
            bit_cnt <= bit_cnt + 3'd1;
    end else
        bit_cnt <= 3'd0;
end


always_ff @(posedge clk or negedge rst_n)
begin
    if(!rst_n)
        cycle_cnt <= 16'd0;
    else if((state == S_REC_BYTE && cycle_cnt == cycle_val - 1) || next_state != state)
        cycle_cnt <= 16'd0;
    else if(state != S_IDLE)
        cycle_cnt <= cycle_cnt + 16'd1;
    // BUG-55b: Guard — cycle_cnt must not increment when UART is idle.
    // Without this guard, cycle_cnt free-runs every clock cycle in S_IDLE,
    // generating unnecessary simulation events (16-bit toggle every cycle).
end
//receive serial data bit data
always_ff @(posedge clk or negedge rst_n)
begin
    if(!rst_n)
        rx_bits <= 8'd0;
    else if(state == S_REC_BYTE && cycle_cnt == cycle_val/2 - 1)
        rx_bits[bit_cnt] <= i_rxPin_1;
end
endmodule 

