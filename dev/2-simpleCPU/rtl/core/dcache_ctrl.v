`timescale 1ns / 1ps

module dcache_ctrl #(
    parameter DEPTH = 4096
)(
    input  wire        clk,
    input  wire        reset,

    // CPU mem interface
    input  wire        cpu_req_valid,
    input  wire [31:0] cpu_req_addr,
    input  wire [31:0] cpu_req_wdata,
    input  wire [3:0]  cpu_req_wen,
    output wire [31:0] cpu_req_rdata,
    output wire        cpu_req_ready,

    // MMIO / Bus interface
    output wire        mmio_req,
    output wire [31:0] mmio_addr,
    output wire [31:0] mmio_wdata,
    output wire [3:0]  mmio_wen,
    input  wire [31:0] mmio_rdata,
    input  wire        mmio_valid
);

    wire is_mmio = cpu_req_addr[31];
    
    wire [31:0] dcache_dout;
    reg dcache_valid_r;
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            dcache_valid_r <= 1'b0;
        end else begin
            dcache_valid_r <= cpu_req_valid && !is_mmio;
        end
    end
    
    dcache u_dcache (
        .clka(clk),
        .ena(cpu_req_valid && !is_mmio),
        .wea(~cpu_req_wen), // cpu_req_wen: 1=read,0=write; BRAM wea: 1=write,0=read → invert
        .addra(cpu_req_addr[13:2]), // WARNING: 12-bit index → 4KB direct-mapped; addresses >=16KB wrap and alias
        .dina(cpu_req_wdata),
        .douta(dcache_dout),
        
        .clkb(1'b0),
        .enb(1'b0),
        .web(4'b0),
        .addrb(12'b0),
        .dinb(32'b0),
        .doutb()
    );

    // MUX for CPU
    assign cpu_req_rdata = is_mmio ? mmio_rdata : dcache_dout;
    assign cpu_req_ready = is_mmio ? mmio_valid : dcache_valid_r;

    // Connect to MMIO
    assign mmio_req   = is_mmio ? cpu_req_valid : 1'b0;
    assign mmio_addr  = cpu_req_addr;
    assign mmio_wdata = cpu_req_wdata;
    assign mmio_wen   = is_mmio ? cpu_req_wen : 4'b0;

endmodule
