`timescale 1ns / 1ps
`include "axi4_def.svh"
`include "cache_def.svh"
`include "soc_addr_map.svh"

// Blocking two-way PIPT instruction cache. Redirects discard an accepted
// request's result, but every external request is drained normally.
module icache_ctrl(
    input wire clk, input wire resetn,
    input wire cpu_req_valid, input wire [31:0] cpu_req_paddr,
    input wire flush_req,
    output wire [31:0] cpu_req_data, output wire cpu_req_ready,
    output wire cpu_req_error, output wire [31:0] cpu_req_error_addr,
    output wire mem_req_valid, input wire mem_req_ready,
    output wire [31:0] mem_req_addr, output wire mem_req_write,
    output wire [2:0] mem_req_size, output wire [7:0] mem_req_len,
    output wire [31:0] mem_req_wdata,
    input wire mem_resp_valid, input wire [255:0] mem_resp_data,
    input wire mem_resp_error,
    input wire invalidate_req, output wire invalidate_done,
    output wire [2:0] dbg_state
);
    localparam NUM_SETS=`ICACHE_NUM_SETS, TAG_WIDTH=`ICACHE_TAG_WIDTH;
    localparam LINE_WIDTH=`ICACHE_LINE_WIDTH, SET_W=`ICACHE_SET_IDX_WIDTH;
    localparam WAY_W=`ICACHE_WAY_WIDTH, ADDR_W=`ICACHE_ADDR_WIDTH;
    localparam WEA_W=`ICACHE_WEA_WIDTH;
    localparam [2:0] S_IDLE=0, S_LOOKUP=1, S_READ_HIT=2, S_MEM_REQ=3, S_MEM_WAIT=4;
    localparam [32:0] DDR_LIMIT={1'b0,`SOC_DDR_BASE}+`SOC_DDR_SIZE;

    reg [2:0] state;
    reg valid_array[0:NUM_SETS-1][0:1];
    reg [TAG_WIDTH-1:0] tag_array[0:NUM_SETS-1][0:1];
    reg victim_array[0:NUM_SETS-1];
    reg [31:0] op_addr_r;
    reg [SET_W-1:0] op_set_r;
    reg [2:0] op_word_r;
    reg [TAG_WIDTH-1:0] op_tag_r;
    reg [WAY_W-1:0] fill_way_r;
    reg line_refill_r, discard_r;
    reg [31:0] response_data_r, cpu_error_addr_r;
    reg cpu_ready_r, cpu_error_r, invalidate_done_r, invalidate_block_r;

    wire request_cacheable=({1'b0,cpu_req_paddr}>={1'b0,`SOC_DDR_BASE})&&
                           ({1'b0,cpu_req_paddr}<DDR_LIMIT);
    wire hit0=valid_array[op_set_r][0]&&(tag_array[op_set_r][0]==op_tag_r);
    wire hit1=valid_array[op_set_r][1]&&(tag_array[op_set_r][1]==op_tag_r);
    wire cache_hit=hit0||hit1;
    wire [WAY_W-1:0] hit_way=hit0?{WAY_W{1'b0}}:{{(WAY_W-1){1'b0}},1'b1};
    wire [WAY_W-1:0] victim_way=!valid_array[op_set_r][0]?{WAY_W{1'b0}}:
        !valid_array[op_set_r][1]?{{(WAY_W-1){1'b0}},1'b1}:victim_array[op_set_r];

    assign cpu_req_data=response_data_r;
    assign cpu_req_ready=cpu_ready_r;
    assign cpu_req_error=cpu_error_r;
    assign cpu_req_error_addr=cpu_error_addr_r;
    assign invalidate_done=invalidate_done_r;
    assign dbg_state=state;
    assign mem_req_valid=(state==S_MEM_REQ);
    assign mem_req_addr=line_refill_r?{op_addr_r[31:5],5'b0}:op_addr_r;
    assign mem_req_write=1'b0;
    assign mem_req_size=`AXI_SIZE_WORD;
    assign mem_req_len=line_refill_r?8'd7:8'd0;
    assign mem_req_wdata=32'b0;

    wire data_a_read=(state==S_LOOKUP)&&cache_hit;
    wire [ADDR_W-1:0] data_a_addr={op_set_r,hit_way};
    wire [LINE_WIDTH-1:0] data_a_out;
    wire refill_write=(state==S_MEM_WAIT)&&mem_resp_valid&&!mem_resp_error&&line_refill_r;
    wire [ADDR_W-1:0] data_b_addr={op_set_r,fill_way_r};
    icached u_icached(
        .clka(clk),.ena(data_a_read),.wea({WEA_W{1'b0}}),.addra(data_a_addr),
        .dina({LINE_WIDTH{1'b0}}),.douta(data_a_out),
        .clkb(clk),.enb(refill_write),.web({WEA_W{1'b1}}),.addrb(data_b_addr),
        .dinb(mem_resp_data),.doutb());

    integer s;
    always_ff @(posedge clk or negedge resetn) begin
        if(!resetn) begin
            state<=S_IDLE; op_addr_r<=0; op_set_r<=0; op_word_r<=0; op_tag_r<=0;
            fill_way_r<=0; line_refill_r<=0; discard_r<=0; response_data_r<=0;
            cpu_ready_r<=0; cpu_error_r<=0; cpu_error_addr_r<=0; invalidate_done_r<=0;
            invalidate_block_r<=0;
            for(s=0;s<NUM_SETS;s=s+1) begin
                valid_array[s][0]<=0; valid_array[s][1]<=0;
                tag_array[s][0]<=0; tag_array[s][1]<=0; victim_array[s]<=0;
            end
        end else begin
            cpu_ready_r<=0; cpu_error_r<=0; invalidate_done_r<=0;
            if(!invalidate_req) invalidate_block_r<=0;
            if(flush_req&&((state==S_LOOKUP)||(state==S_READ_HIT))) begin
                state<=S_IDLE; discard_r<=0;
            end else begin
                if(flush_req&&((state==S_MEM_REQ)||(state==S_MEM_WAIT))) discard_r<=1;
                case(state)
                    S_IDLE: begin
                        discard_r<=0;
                        if(flush_req) begin
                            // Do not latch a fetch from the cycle being redirected.
                        end else if(invalidate_req) begin
                            if(!invalidate_block_r) begin
                                for(s=0;s<NUM_SETS;s=s+1) begin
                                    valid_array[s][0]<=0; valid_array[s][1]<=0; victim_array[s]<=0;
                                end
                                invalidate_done_r<=1; invalidate_block_r<=1;
                            end
                        end else if(cpu_req_valid&&!cpu_ready_r&&!cpu_error_r) begin
                            op_addr_r<=cpu_req_paddr;
                            op_set_r<=cpu_req_paddr[`ICACHE_SET_IDX_HI:`ICACHE_SET_IDX_LO];
                            op_word_r<=cpu_req_paddr[`ICACHE_WORD_OFF_HI:`ICACHE_WORD_OFF_LO];
                            op_tag_r<=cpu_req_paddr[`ICACHE_TAG_HI:`ICACHE_TAG_LO];
                            line_refill_r<=request_cacheable;
                            state<=request_cacheable?S_LOOKUP:S_MEM_REQ;
                        end
                    end
                    S_LOOKUP: begin
                        if(cache_hit) state<=S_READ_HIT;
                        else begin fill_way_r<=victim_way; line_refill_r<=1; state<=S_MEM_REQ; end
                    end
                    S_READ_HIT: begin
                        if(!discard_r) begin
                            response_data_r<=data_a_out[op_word_r*32+:32]; cpu_ready_r<=1;
                            victim_array[op_set_r]<=~hit_way;
                        end
                        state<=S_IDLE;
                    end
                    S_MEM_REQ: if(mem_req_ready) state<=S_MEM_WAIT;
                    S_MEM_WAIT: if(mem_resp_valid) begin
                        if(mem_resp_error) begin
                            if(!discard_r&&!flush_req) begin
                                cpu_error_r<=1; cpu_error_addr_r<=op_addr_r;
                            end
                        end else begin
                            if(line_refill_r) begin
                                valid_array[op_set_r][fill_way_r]<=1;
                                tag_array[op_set_r][fill_way_r]<=op_tag_r;
                                victim_array[op_set_r]<=~fill_way_r;
                            end
                            if(!discard_r&&!flush_req) begin
                                response_data_r<=line_refill_r?mem_resp_data[op_word_r*32+:32]:mem_resp_data[31:0];
                                cpu_ready_r<=1;
                            end
                        end
                        discard_r<=0; state<=S_IDLE;
                    end
                    default: state<=S_IDLE;
                endcase
            end
        end
    end
endmodule
