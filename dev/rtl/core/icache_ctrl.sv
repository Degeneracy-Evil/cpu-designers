`timescale 1ns / 1ps

module icache_ctrl #(
    parameter DEPTH = 4096
)(
    input  wire        clk,
    input  wire        reset,

    // CPU front-end interface
    input  wire        cpu_req_valid,
    input  wire [31:0] cpu_req_addr,
    output wire [31:0] cpu_req_data,
    output wire        cpu_req_ready,

    // MMIO / Bus interface
    output wire        mmio_req,
    output wire [31:0] mmio_addr,
    input  wire [31:0] mmio_data,
    input  wire        mmio_valid
);

    wire is_mmio = ~cpu_req_addr[31];
    
    // Cache internal logic
    wire [31:0] icache_dout;
    reg icache_valid_r;
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            icache_valid_r <= 1'b0;
        end else begin
            icache_valid_r <= bram_ena_r;
        end
    end
    
    wire bram_ena_comb = cpu_req_valid && !is_mmio;

    reg        bram_ena_r;
    reg [11:0] bram_addra_r;

    always @(posedge clk) begin
        bram_ena_r   <= bram_ena_comb;
        bram_addra_r <= cpu_req_addr[13:2];
    end

    icache u_icache (
        .clka(clk),
        .ena(bram_ena_r),
        .wea(4'b0),
        .addra(bram_addra_r),
        .dina(32'b0),
        .douta(icache_dout),
        
        .clkb(1'b0),
        .enb(1'b0),
        .web(4'b0),
        .addrb(12'b0),
        .dinb(32'b0),
        .doutb()
    );

    // MUX for CPU
    assign cpu_req_data  = is_mmio ? mmio_data : icache_dout;
    assign cpu_req_ready = is_mmio ? mmio_valid : icache_valid_r;

    // Connect to MMIO
    assign mmio_req  = is_mmio ? cpu_req_valid : 1'b0;
    assign mmio_addr = cpu_req_addr;

endmodule
