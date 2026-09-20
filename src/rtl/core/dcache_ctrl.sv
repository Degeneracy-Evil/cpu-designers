`timescale 1ns / 1ps
`include "axi4_def.svh"
`include "cache_def.svh"

// Blocking two-way PIPT data cache. Loads allocate, stores are write-through
// and do not allocate. The PTW is a second logical owner with fixed priority.
module dcache_ctrl(
    input wire clk, input wire resetn,
    input wire cpu_req_valid, input wire [31:0] cpu_req_paddr,
    input wire [31:0] cpu_req_wdata, input wire cpu_req_write,
    input wire [2:0] cpu_req_size,
    output wire [31:0] cpu_req_rdata, output wire cpu_req_ready,
    output wire cpu_req_error, output wire cpu_req_error_is_store,
    output wire [31:0] cpu_req_error_addr,
    input wire ptw_req_valid, input wire [31:0] ptw_req_addr,
    input wire [31:0] ptw_req_wdata, input wire ptw_req_write,
    output wire [31:0] ptw_req_rdata, output wire ptw_req_done,
    output wire ptw_req_error,
    output wire mem_req_valid, input wire mem_req_ready,
    output wire [31:0] mem_req_addr, output wire mem_req_write,
    output wire [2:0] mem_req_size, output wire [7:0] mem_req_len,
    output wire [31:0] mem_req_wdata,
    input wire mem_resp_valid, input wire [255:0] mem_resp_data,
    input wire mem_resp_error
);
    localparam NUM_SETS=`DCACHE_NUM_SETS, TAG_WIDTH=`DCACHE_TAG_WIDTH;
    localparam LINE_WIDTH=`DCACHE_LINE_WIDTH, SET_W=`DCACHE_SET_IDX_WIDTH;
    localparam WAY_W=`DCACHE_WAY_WIDTH, ADDR_W=`DCACHE_ADDR_WIDTH;
    localparam WEA_W=`DCACHE_WEA_WIDTH;
    localparam [2:0] S_IDLE=0,S_LOOKUP=1,S_READ_HIT=2,S_MEM_REQ=3,S_MEM_WAIT=4;
    localparam [32:0] DDR_LIMIT={1'b0,`DDR3_BASE_ADDR}+`DDR3_MEM_SIZE;

    reg [2:0] state;
    reg valid_array[0:NUM_SETS-1][0:1];
    reg [TAG_WIDTH-1:0] tag_array[0:NUM_SETS-1][0:1];
    reg victim_array[0:NUM_SETS-1];
    reg [31:0] op_addr_r,op_wdata_r;
    reg op_write_r,op_ptw_r,line_refill_r;
    reg [2:0] op_size_r,op_word_r;
    reg [SET_W-1:0] op_set_r;
    reg [TAG_WIDTH-1:0] op_tag_r;
    reg [WAY_W-1:0] fill_way_r,store_way_r;
    reg store_hit_r;
    reg [31:0] response_data_r,cpu_error_addr_r,ptw_rdata_r;
    reg cpu_ready_r,cpu_error_r,cpu_error_is_store_r;
    reg ptw_done_r,ptw_error_r,ptw_block_r;

    wire cpu_cacheable=({1'b0,cpu_req_paddr}>={1'b0,`DDR3_BASE_ADDR})&&
                       ({1'b0,cpu_req_paddr}<DDR_LIMIT);
    wire ptw_cacheable=({1'b0,ptw_req_addr}>={1'b0,`DDR3_BASE_ADDR})&&
                       ({1'b0,ptw_req_addr}<DDR_LIMIT);
    wire hit0=valid_array[op_set_r][0]&&(tag_array[op_set_r][0]==op_tag_r);
    wire hit1=valid_array[op_set_r][1]&&(tag_array[op_set_r][1]==op_tag_r);
    wire cache_hit=hit0||hit1;
    wire [WAY_W-1:0] hit_way=hit0?{WAY_W{1'b0}}:{{(WAY_W-1){1'b0}},1'b1};
    wire [WAY_W-1:0] victim_way=!valid_array[op_set_r][0]?{WAY_W{1'b0}}:
        !valid_array[op_set_r][1]?{{(WAY_W-1){1'b0}},1'b1}:victim_array[op_set_r];

    assign cpu_req_rdata=response_data_r; assign cpu_req_ready=cpu_ready_r;
    assign cpu_req_error=cpu_error_r;
    assign cpu_req_error_is_store=cpu_error_is_store_r;
    assign cpu_req_error_addr=cpu_error_addr_r;
    assign ptw_req_rdata=ptw_rdata_r; assign ptw_req_done=ptw_done_r;
    assign ptw_req_error=ptw_error_r;
    assign mem_req_valid=(state==S_MEM_REQ);
    assign mem_req_addr=line_refill_r?{op_addr_r[31:5],5'b0}:op_addr_r;
    assign mem_req_write=op_write_r;
    assign mem_req_size=line_refill_r?`AXI_SIZE_WORD:op_size_r;
    assign mem_req_len=line_refill_r?8'd7:8'd0;
    assign mem_req_wdata=op_wdata_r;

    wire [3:0] store_byte_we=(op_size_r==`AXI_SIZE_BYTE)?(4'b0001<<op_addr_r[1:0]):
        (op_size_r==`AXI_SIZE_HWORD)?(op_addr_r[1]?4'b1100:4'b0011):4'b1111;
    wire [31:0] store_word_data=(op_size_r==`AXI_SIZE_BYTE)?
        ({24'b0,op_wdata_r[7:0]}<<(op_addr_r[1:0]*8)):
        (op_size_r==`AXI_SIZE_HWORD)?({16'b0,op_wdata_r[15:0]}<<(op_addr_r[1]*16)):op_wdata_r;
    wire [WEA_W-1:0] store_line_we=({{(WEA_W-4){1'b0}},store_byte_we}<<(op_word_r*4));
    wire [LINE_WIDTH-1:0] store_line_data=({{(LINE_WIDTH-32){1'b0}},store_word_data}<<(op_word_r*32));
    wire data_a_read=(state==S_LOOKUP)&&!op_write_r&&cache_hit;
    wire data_a_store=(state==S_MEM_WAIT)&&mem_resp_valid&&!mem_resp_error&&op_write_r&&store_hit_r;
    wire [ADDR_W-1:0] data_a_addr=data_a_store?{op_set_r,store_way_r}:{op_set_r,hit_way};
    wire [LINE_WIDTH-1:0] data_a_out;
    wire refill_write=(state==S_MEM_WAIT)&&mem_resp_valid&&!mem_resp_error&&line_refill_r;
    wire [ADDR_W-1:0] data_b_addr={op_set_r,fill_way_r};
    dcached u_dcached(
        .clka(clk),.ena(data_a_read||data_a_store),
        .wea(data_a_store?store_line_we:{WEA_W{1'b0}}),.addra(data_a_addr),
        .dina(data_a_store?store_line_data:{LINE_WIDTH{1'b0}}),.douta(data_a_out),
        .clkb(clk),.enb(refill_write),.web({WEA_W{1'b1}}),.addrb(data_b_addr),
        .dinb(mem_resp_data),.doutb());

    task automatic finish_owner(input [31:0] data,input error);
        begin
            if(op_ptw_r) begin
                ptw_rdata_r<=data; ptw_done_r<=1; ptw_error_r<=error; ptw_block_r<=1;
            end else if(error) begin
                cpu_error_r<=1; cpu_error_is_store_r<=op_write_r; cpu_error_addr_r<=op_addr_r;
            end else begin response_data_r<=data; cpu_ready_r<=1; end
        end
    endtask

    integer s;
    always_ff @(posedge clk or negedge resetn) begin
        if(!resetn) begin
            state<=S_IDLE; op_addr_r<=0; op_wdata_r<=0; op_write_r<=0;
            op_size_r<=`AXI_SIZE_WORD; op_set_r<=0; op_word_r<=0; op_tag_r<=0;
            fill_way_r<=0; store_way_r<=0; store_hit_r<=0; line_refill_r<=0;
            op_ptw_r<=0; response_data_r<=0; cpu_ready_r<=0; cpu_error_r<=0;
            cpu_error_is_store_r<=0; cpu_error_addr_r<=0; ptw_rdata_r<=0;
            ptw_done_r<=0; ptw_error_r<=0; ptw_block_r<=0;
            for(s=0;s<NUM_SETS;s=s+1) begin
                valid_array[s][0]<=0; valid_array[s][1]<=0;
                tag_array[s][0]<=0; tag_array[s][1]<=0; victim_array[s]<=0;
            end
        end else begin
            cpu_ready_r<=0; cpu_error_r<=0; ptw_done_r<=0; ptw_error_r<=0;
            if(!ptw_req_valid) ptw_block_r<=0;
            case(state)
                S_IDLE: begin
                    if(ptw_req_valid&&!ptw_block_r) begin
                        store_hit_r<=0;
                        op_addr_r<=ptw_req_addr; op_wdata_r<=ptw_req_wdata;
                        op_write_r<=ptw_req_write; op_size_r<=`AXI_SIZE_WORD;
                        op_set_r<=ptw_req_addr[`DCACHE_SET_IDX_HI:`DCACHE_SET_IDX_LO];
                        op_word_r<=ptw_req_addr[`DCACHE_WORD_OFF_HI:`DCACHE_WORD_OFF_LO];
                        op_tag_r<=ptw_req_addr[`DCACHE_TAG_HI:`DCACHE_TAG_LO];
                        op_ptw_r<=1; line_refill_r<=!ptw_req_write&&ptw_cacheable;
                        state<=ptw_cacheable?S_LOOKUP:S_MEM_REQ;
                    end else if(cpu_req_valid&&!cpu_ready_r&&!cpu_error_r) begin
                        store_hit_r<=0;
                        op_addr_r<=cpu_req_paddr; op_wdata_r<=cpu_req_wdata;
                        op_write_r<=cpu_req_write; op_size_r<=cpu_req_size;
                        op_set_r<=cpu_req_paddr[`DCACHE_SET_IDX_HI:`DCACHE_SET_IDX_LO];
                        op_word_r<=cpu_req_paddr[`DCACHE_WORD_OFF_HI:`DCACHE_WORD_OFF_LO];
                        op_tag_r<=cpu_req_paddr[`DCACHE_TAG_HI:`DCACHE_TAG_LO];
                        op_ptw_r<=0; line_refill_r<=!cpu_req_write&&cpu_cacheable;
                        state<=cpu_cacheable?S_LOOKUP:S_MEM_REQ;
                    end
                end
                S_LOOKUP: begin
                    if(op_write_r) begin
                        store_hit_r<=cache_hit; store_way_r<=hit_way;
                        line_refill_r<=0; state<=S_MEM_REQ;
                    end else if(cache_hit) state<=S_READ_HIT;
                    else begin fill_way_r<=victim_way; line_refill_r<=1; state<=S_MEM_REQ; end
                end
                S_READ_HIT: begin
                    finish_owner(data_a_out[op_word_r*32+:32],1'b0);
                    victim_array[op_set_r]<=~hit_way; state<=S_IDLE;
                end
                S_MEM_REQ: if(mem_req_ready) state<=S_MEM_WAIT;
                S_MEM_WAIT: if(mem_resp_valid) begin
                    if(!mem_resp_error) begin
                        if(line_refill_r) begin
                            valid_array[op_set_r][fill_way_r]<=1;
                            tag_array[op_set_r][fill_way_r]<=op_tag_r;
                            victim_array[op_set_r]<=~fill_way_r;
                        end else if(op_write_r&&store_hit_r) victim_array[op_set_r]<=~store_way_r;
                    end
                    finish_owner(line_refill_r?mem_resp_data[op_word_r*32+:32]:mem_resp_data[31:0],mem_resp_error);
                    state<=S_IDLE;
                end
                default: state<=S_IDLE;
            endcase
        end
    end
endmodule
