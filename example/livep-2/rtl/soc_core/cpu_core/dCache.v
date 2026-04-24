module dCache (
    //ç«¯å£1
    //0Ğ´1¶Á
    input clk,
    input [12:0] address,
    input [3:0] wen,
    input [31:0] w_data,
    input [3:0] ren,

    output reg [31:0] r_data

);

    reg [31:0] regs[8191:0];    //ï¿??ï¿??8K * 32bit çš„å­˜å‚¨å™¨
    integer i;
    
    initial begin
    regs[0] = 32'h00000005;
    for (i = 1; i < 8192; i = i+1)
            regs[i] = 32'b0;
    end
    
    always @(posedge clk) begin
            case (wen)
                4'b1111: r_data[31:0] = regs[address][31:0];
                4'b1110: regs[address][7:0] = w_data[7:0];
                4'b1101: regs[address][15:8] = w_data[7:0];
                4'b1011: regs[address][23:16] = w_data[7:0];
                4'b0111: regs[address][31:24] = w_data[7:0];
                4'b1100: regs[address][15:0] = w_data[15:0];
                4'b1001: regs[address][23:8] = w_data[15:0];
                4'b0011: regs[address][31:16] = w_data[15:0];
                4'b0000: regs[address][31:0] = w_data[31:0];
            endcase    
        end

    
endmodule