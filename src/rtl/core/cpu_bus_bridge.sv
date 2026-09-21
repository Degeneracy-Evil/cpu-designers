`timescale 1ns / 1ps
`include "axi4_def.svh"

// One-outstanding blocking adapter. DCache has arbitration priority; the
// selected owner remains locked from request handshake through final response.
module cpu_bus_bridge(
    input wire clk,input wire resetn,
    input wire i_req_valid,output wire i_req_ready,input wire [31:0] i_req_addr,
    input wire i_req_write,input wire [2:0] i_req_size,input wire [7:0] i_req_len,
    input wire [31:0] i_req_wdata,
    input wire [3:0] i_req_wstrb,
    output wire i_resp_valid,output wire [255:0] i_resp_data,output wire i_resp_error,
    input wire d_req_valid,output wire d_req_ready,input wire [31:0] d_req_addr,
    input wire d_req_write,input wire [2:0] d_req_size,input wire [7:0] d_req_len,
    input wire [31:0] d_req_wdata,
    input wire [3:0] d_req_wstrb,
    output wire d_resp_valid,output wire [255:0] d_resp_data,output wire d_resp_error,
    output logic [3:0] awid,output logic [31:0] awaddr,output logic [7:0] awlen,
    output logic [2:0] awsize,output logic [1:0] awburst,output logic awlock,
    output logic [3:0] awcache,output logic [2:0] awprot,output logic [3:0] awqos,
    output logic [3:0] awregion,output logic awvalid,input logic awready,
    output logic [31:0] wdata,output logic [3:0] wstrb,output logic wlast,
    output logic wvalid,input logic wready,
    input logic [1:0] bresp,input logic bvalid,output logic bready,
    output logic [3:0] arid,output logic [31:0] araddr,output logic [7:0] arlen,
    output logic [2:0] arsize,output logic [1:0] arburst,output logic arlock,
    output logic [3:0] arcache,output logic [2:0] arprot,output logic [3:0] arqos,
    output logic [3:0] arregion,output logic arvalid,input logic arready,
    input logic [31:0] rdata,input logic [1:0] rresp,input logic rlast,
    input logic rvalid,output logic rready
);
    localparam [2:0] S_IDLE=0,S_READ_ADDR=1,S_READ_DATA=2,S_WRITE_SEND=3,S_WRITE_RESP=4;
    reg [2:0] state;
    reg owner_d_r;
    reg [31:0] addr_r,wdata_r;
    reg [3:0] wstrb_r;
    reg [2:0] size_r,beat_r;
    reg [7:0] len_r;
    reg [255:0] read_data_r,resp_data_r;
    reg read_error_r,aw_done_r,w_done_r;
    reg i_resp_valid_r,i_resp_error_r,d_resp_valid_r,d_resp_error_r;

    wire take_d=(state==S_IDLE)&&d_req_valid;
    wire take_i=(state==S_IDLE)&&!d_req_valid&&i_req_valid;
    assign d_req_ready=(state==S_IDLE);
    assign i_req_ready=(state==S_IDLE)&&!d_req_valid;
    assign i_resp_valid=i_resp_valid_r; assign i_resp_data=resp_data_r;
    assign i_resp_error=i_resp_error_r;
    assign d_resp_valid=d_resp_valid_r; assign d_resp_data=resp_data_r;
    assign d_resp_error=d_resp_error_r;

    wire r_error=(rresp==`AXI_RESP_SLVERR)||(rresp==`AXI_RESP_DECERR);
    wire b_error=(bresp==`AXI_RESP_SLVERR)||(bresp==`AXI_RESP_DECERR);
    wire [255:0] read_with_current=(read_data_r&~({224'b0,32'hffff_ffff}<<(beat_r*32)))|
                                   ({224'b0,rdata}<<(beat_r*32));

    always_comb begin
        awid=0; awaddr=addr_r; awlen=len_r; awsize=size_r; awburst=`AXI_BURST_INCR;
        awlock=`AXI_LOCK_NORMAL; awcache=(len_r!=0)?`AXI_CACHE_NORM_BUF:`AXI_CACHE_DEV_NONBUF;
        awprot=`AXI_PROT_DATA_PRIV_SECURE; awqos=0; awregion=0;
        awvalid=(state==S_WRITE_SEND)&&!aw_done_r;
        wdata=wdata_r; wstrb=wstrb_r; wlast=1'b1;
        wvalid=(state==S_WRITE_SEND)&&!w_done_r; bready=(state==S_WRITE_RESP);
        arid=0; araddr=addr_r; arlen=len_r; arsize=size_r; arburst=`AXI_BURST_INCR;
        arlock=`AXI_LOCK_NORMAL; arcache=(len_r!=0)?`AXI_CACHE_NORM_BUF:`AXI_CACHE_DEV_NONBUF;
        arprot=owner_d_r?`AXI_PROT_DATA_PRIV_SECURE:`AXI_PROT_INST_PRIV_SECURE;
        arqos=0; arregion=0; arvalid=(state==S_READ_ADDR); rready=(state==S_READ_DATA);
    end

    always_ff @(posedge clk or negedge resetn) begin
        if(!resetn) begin
            state<=S_IDLE; owner_d_r<=0; addr_r<=0; wdata_r<=0; wstrb_r<=0; size_r<=`AXI_SIZE_4B;
            len_r<=0; beat_r<=0; read_data_r<=0; resp_data_r<=0; read_error_r<=0;
            aw_done_r<=0; w_done_r<=0; i_resp_valid_r<=0; i_resp_error_r<=0;
            d_resp_valid_r<=0; d_resp_error_r<=0;
        end else begin
            i_resp_valid_r<=0; i_resp_error_r<=0; d_resp_valid_r<=0; d_resp_error_r<=0;
            case(state)
                S_IDLE: begin
                    beat_r<=0; read_data_r<=0; read_error_r<=0; aw_done_r<=0; w_done_r<=0;
                    if(take_d) begin
                        owner_d_r<=1; addr_r<=d_req_addr; wdata_r<=d_req_wdata; wstrb_r<=d_req_wstrb;
                        size_r<=d_req_size; len_r<=d_req_len;
                        state<=d_req_write?S_WRITE_SEND:S_READ_ADDR;
                    end else if(take_i) begin
                        owner_d_r<=0; addr_r<=i_req_addr; wdata_r<=i_req_wdata; wstrb_r<=i_req_wstrb;
                        size_r<=i_req_size; len_r<=i_req_len;
                        state<=i_req_write?S_WRITE_SEND:S_READ_ADDR;
                    end
                end
                S_READ_ADDR: if(arready) state<=S_READ_DATA;
                S_READ_DATA: if(rvalid) begin
                    read_data_r[beat_r*32+:32]<=rdata;
                    if(r_error) read_error_r<=1;
                    if(rlast) begin
                        resp_data_r<=read_with_current;
                        if(owner_d_r) begin d_resp_valid_r<=1; d_resp_error_r<=read_error_r||r_error; end
                        else begin i_resp_valid_r<=1; i_resp_error_r<=read_error_r||r_error; end
                        state<=S_IDLE;
                    end else beat_r<=beat_r+1'b1;
                end
                S_WRITE_SEND: begin
                    if(awvalid&&awready) aw_done_r<=1;
                    if(wvalid&&wready) w_done_r<=1;
                    if((aw_done_r||(awvalid&&awready))&&(w_done_r||(wvalid&&wready))) state<=S_WRITE_RESP;
                end
                S_WRITE_RESP: if(bvalid) begin
                    resp_data_r<=0;
                    if(owner_d_r) begin d_resp_valid_r<=1; d_resp_error_r<=b_error; end
                    else begin i_resp_valid_r<=1; i_resp_error_r<=b_error; end
                    state<=S_IDLE;
                end
                default: state<=S_IDLE;
            endcase
        end
    end
endmodule
