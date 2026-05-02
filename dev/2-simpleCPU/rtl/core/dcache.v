`timescale 1ns / 1ps

module dcache #(
    parameter DEPTH = 512
)(
    input  wire        clka,
    input  wire        ena,
    input  wire [3:0]  wea,
    input  wire [$clog2(DEPTH)-1:0] addra,
    input  wire [31:0] dina,
    output wire [31:0] douta,
    input  wire        clkb,
    input  wire        enb,
    input  wire [3:0]  web,
    input  wire [$clog2(DEPTH)-1:0] addrb,
    input  wire [31:0] dinb,
    output wire [31:0] doutb
);

    reg [31:0] mem [0:DEPTH-1];

    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = 32'b0;
    end

    reg [31:0] douta_r;
    assign douta = douta_r;

    reg [31:0] doutb_r;
    assign doutb = doutb_r;

    always @(posedge clka) begin
        if (ena) begin
            if (wea != 4'b0000) begin
                if (wea[0]) mem[addra][7:0]   <= dina[7:0];
                if (wea[1]) mem[addra][15:8]  <= dina[15:8];
                if (wea[2]) mem[addra][23:16] <= dina[23:16];
                if (wea[3]) mem[addra][31:24] <= dina[31:24];
                douta_r <= dina;
            end else begin
                douta_r <= mem[addra];
            end
        end
    end

    always @(posedge clkb) begin
        if (enb) begin
            if (web != 4'b0000) begin
                if (web[0]) mem[addrb][7:0]   <= dinb[7:0];
                if (web[1]) mem[addrb][15:8]  <= dinb[15:8];
                if (web[2]) mem[addrb][23:16] <= dinb[23:16];
                if (web[3]) mem[addrb][31:24] <= dinb[31:24];
                doutb_r <= dinb;
            end else begin
                doutb_r <= mem[addrb];
            end
        end
    end

endmodule
