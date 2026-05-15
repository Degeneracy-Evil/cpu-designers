`timescale 1ns / 1ps

module ahb_plic #(
    parameter NUM_SRC = 8
)(
    input  wire         HCLK,
    input  wire         HRESETn,

    input  wire         HSEL,
    input  wire [31:0]  HADDR,
    input  wire [1:0]   HTRANS,
    input  wire         HWRITE,
    input  wire [2:0]   HSIZE,
    input  wire [31:0]  HWDATA,
    input  wire         HREADY,
    output wire         HREADYOUT,
    output wire         HRESP,
    output reg  [31:0]  HRDATA,

    input  wire [NUM_SRC-1:0] src_irq,
    output wire               o_eip
);

    wire access_active = HSEL && HTRANS[1];
    wire rd_valid = access_active && !HWRITE;
    wire wr_valid = access_active && HWRITE && HREADY;

    wire addr_is_prio   = (HADDR[23:6] == 18'd0);
    wire addr_is_pend   = (HADDR[23:14] == 10'd0) && (HADDR[13:2] == 12'd256);
    wire addr_is_enable = (HADDR[23:14] == 10'd0) && (HADDR[13:2] == 12'd512);
    wire addr_is_thresh = (HADDR[23:4] == {20'h20000});
    wire addr_is_claim  = (HADDR[23:4] == {20'h20001});

    reg  [31:0] r_prio [0:NUM_SRC-1];
    reg  [31:0] r_pending;
    reg  [31:0] r_enable;
    reg  [31:0] r_threshold;
    reg  [NUM_SRC-1:0] r_gw_en;

    reg  [7:0]  r_claim_id;
    reg         r_claim_valid;
    reg  [31:0] r_complete;

    integer ii;

    // 修复：将 r_prio 作为参数传入 function，避免组合逻辑直接读取时序寄存器
    function [7:0] find_highest;
        input [31:0] pend, enbl, thresh;
        input [31:0] prio_arr [0:NUM_SRC-1]; // 新增参数
        reg   [31:0] pmat [1:NUM_SRC-1];
        reg   [31:0] best;
        reg   [7:0]  id;
        integer      j;
        begin
            best = 32'd0;
            id   = 8'd0;
            for (j = 1; j < NUM_SRC; j = j + 1) begin
                pmat[j] = 32'd0;
                if (pend[j] && enbl[j])
                    pmat[j] = prio_arr[j]; // 使用传入的参数
            end
            for (j = NUM_SRC-1; j >= 1; j = j - 1) begin
                if (pmat[j] > thresh && pmat[j] > best) begin
                    best = pmat[j];
                    id   = j;
                end
            end
            find_highest = id;
        end
    endfunction

    // 调用 function 时传入 r_prio
    wire [7:0] highest_id = find_highest(r_pending, r_enable, r_threshold, r_prio);
    wire       any_pending = (highest_id != 8'd0);
    
    assign o_eip = any_pending;

    // 修复：合并两个 always 块，彻底解决 multi-driven 报错
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            r_pending    <= 32'd0;
            r_enable     <= 32'd0;
            r_threshold  <= 32'd0;
            r_claim_id   <= 8'd0;
            r_claim_valid<= 1'b0;
            r_complete   <= 32'd0;
            r_gw_en      <= {(NUM_SRC){1'b1}};
            for (ii = 0; ii < NUM_SRC; ii = ii + 1)
                r_prio[ii] <= 32'd0;
        end else begin
            // 1. 处理 pending 和 gateway enable 逻辑
            for (ii = 1; ii < NUM_SRC; ii = ii + 1) begin
                if (r_gw_en[ii] && src_irq[ii])
                    r_pending[ii] <= 1'b1;
            end

            for (ii = 1; ii < NUM_SRC; ii = ii + 1) begin
                if (!src_irq[ii])
                    r_gw_en[ii] <= 1'b1;
            end

            // 2. 处理 AHB 写操作
            if (wr_valid && addr_is_prio && (HADDR[7:2] < NUM_SRC))
                r_prio[HADDR[7:2]] <= HWDATA;

            if (wr_valid && addr_is_enable)
                r_enable <= HWDATA;

            if (wr_valid && addr_is_thresh)
                r_threshold <= HWDATA;

            if (wr_valid && addr_is_claim) begin
                r_complete <= HWDATA;
                if ((HWDATA >= 1) && (HWDATA < NUM_SRC))
                    r_gw_en[HWDATA] <= 1'b1;
            end

            // 3. 处理 AHB 读 Claim 时的清除逻辑
            if (rd_valid && addr_is_claim && r_claim_valid) begin
                r_pending[r_claim_id] <= 1'b0;
                r_gw_en[r_claim_id] <= 1'b0;
                r_claim_valid <= 1'b0;
            end

            // 4. 处理 Claim 寄存器的赋值逻辑（原第二个 always 块的内容）
            if (rd_valid && addr_is_claim && !r_claim_valid) begin
                r_claim_id    <= highest_id;
                r_claim_valid <= any_pending;
            end else if (!rd_valid || !addr_is_claim) begin
                r_claim_valid <= 1'b0;
            end
        end
    end

    always @(*) begin
        HRDATA = 32'd0;
        if (rd_valid) begin
            if (addr_is_prio) begin
                HRDATA = (HADDR[7:2] < NUM_SRC) ? r_prio[HADDR[7:2]] : 32'd0;
            end else if (addr_is_pend) begin
                HRDATA = r_pending;
            end else if (addr_is_enable) begin
                HRDATA = r_enable;
            end else if (addr_is_thresh) begin
                HRDATA = r_threshold;
            end else if (addr_is_claim) begin
                HRDATA = {24'd0, r_claim_id};
            end
        end
    end

    assign HREADYOUT = 1'b1;
    assign HRESP = 1'b0;

endmodule