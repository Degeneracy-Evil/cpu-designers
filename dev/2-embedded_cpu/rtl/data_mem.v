`timescale 1ns / 1ps

// Data cache wrapper using FPGA BRAM IP.
// Current CPU-side write enable is single-bit. Byte/halfword writes are expanded
// into read-modify-write in this wrapper before issuing one-word IP write.
module data_mem(
    input         clk,
    input         reset,
    input         req,
    input         write_en,
    input  [31:0] addr,
    input  [31:0] wdata,
    input  [3:0]  wstrb,
    output reg [31:0] rdata,
    output        ready,
    output reg    rvalid,
    output reg    wdone,
    input  [31:0] mem_addr,
    output [31:0] mem_data
);

    localparam S_IDLE      = 2'd0;
    localparam S_READ_WAIT = 2'd1;
    localparam S_RMW_WRITE = 2'd2;

    reg [1:0] state;

    reg [10:0] addra_reg;
    reg [31:0] dina_reg;
    reg        wea_reg;

    reg [10:0] latched_addr;
    reg [31:0] latched_wdata;
    reg [3:0]  latched_wstrb;

    wire [31:0] douta;
    wire [31:0] doutb;
    wire [31:0] merged_wdata;

    assign ready = (state == S_IDLE);

    assign merged_wdata[7:0]   = latched_wstrb[0] ? latched_wdata[7:0]   : douta[7:0];
    assign merged_wdata[15:8]  = latched_wstrb[1] ? latched_wdata[15:8]  : douta[15:8];
    assign merged_wdata[23:16] = latched_wstrb[2] ? latched_wdata[23:16] : douta[23:16];
    assign merged_wdata[31:24] = latched_wstrb[3] ? latched_wdata[31:24] : douta[31:24];

    // IP instance for dCache (32-bit x 2048 words).
    // Replace module name with generated IP name in FPGA project if needed.
    dcache dcache_bram (
        .clka(clk),
        .ena(1'b1),
        .wea(wea_reg),
        .addra(addra_reg),
        .dina(dina_reg),
        .douta(douta),
        .clkb(clk),
        .enb(1'b1),
        .web(1'b0),
        .addrb(mem_addr[12:2]),
        .dinb(32'b0),
        .doutb(doutb)
    );

    assign mem_data = doutb;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= S_IDLE;
            addra_reg <= 11'b0;
            dina_reg <= 32'b0;
            wea_reg <= 1'b0;
            latched_addr <= 11'b0;
            latched_wdata <= 32'b0;
            latched_wstrb <= 4'b0;
            rdata <= 32'b0;
            rvalid <= 1'b0;
            wdone <= 1'b0;
        end else begin
            wea_reg <= 1'b0;
            rvalid <= 1'b0;
            wdone <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (req) begin
                        addra_reg <= addr[12:2];
                        if (write_en) begin
                            latched_addr <= addr[12:2];
                            latched_wdata <= wdata;
                            latched_wstrb <= wstrb;
                            state <= S_RMW_WRITE;
                        end else begin
                            state <= S_READ_WAIT;
                        end
                    end
                end

                S_READ_WAIT: begin
                    rdata <= douta;
                    rvalid <= 1'b1;
                    state <= S_IDLE;
                end

                S_RMW_WRITE: begin
                    addra_reg <= latched_addr;
                    dina_reg <= merged_wdata;
                    wea_reg <= 1'b1;
                    wdone <= 1'b1;
                    state <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
