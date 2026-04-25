`timescale 1ns / 1ps

module bus4lzu_mock(
    input         clk,
    input         reset,

    input  [31:0] instAddr_32,
    output [31:0] instData_32,

    input         data_req,
    input  [3:0]  dataWen_4,
    input  [31:0] dataAddr_32,
    input  [31:0] writeData_32,
    output [31:0] readData_32,

    output        init_sig,
    output        timer_irq,

    input  [31:0] dbg_mem_addr,
    output [31:0] dbg_mem_data
);

    reg [31:0] imem [0:2047];
    reg [31:0] dmem [0:2047];
    integer i;

    initial begin
        for (i = 0; i < 2048; i = i + 1)
            dmem[i] = 32'b0;
        `ifdef CSR_TEST
            $readmemh("dev/2-simpleCPU/program_source/csr_test.hex", imem);
        `else
            $readmemh("dev/2-simpleCPU/program_source/icache_init.hex", imem);
        `endif
    end

    wire [10:0] iword_addr = instAddr_32[12:2];
    wire [10:0] dword_addr = dataAddr_32[12:2];

    assign instData_32 = imem[iword_addr];
    assign readData_32 = dmem[dword_addr];
    assign dbg_mem_data = dmem[dbg_mem_addr[12:2]];

    always @(posedge clk) begin
        if (data_req && dataAddr_32[31:16] != 16'h1001) begin
            if (dataWen_4[0] == 1'b0) dmem[dword_addr][7:0]   <= writeData_32[7:0];
            if (dataWen_4[1] == 1'b0) dmem[dword_addr][15:8]  <= writeData_32[15:8];
            if (dataWen_4[2] == 1'b0) dmem[dword_addr][23:16] <= writeData_32[23:16];
            if (dataWen_4[3] == 1'b0) dmem[dword_addr][31:24] <= writeData_32[31:24];
        end
    end

    reg [6:0] init_cnt;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            init_cnt <= 7'd0;
        end else if (init_cnt < 7'd100) begin
            init_cnt <= init_cnt + 7'd1;
        end
    end
    assign init_sig = (init_cnt < 7'd100);

    reg [31:0] timer_cnt;
    reg [31:0] timer_threshold;
    reg        timer_en;
    reg        timer_irq_r;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            timer_cnt       <= 32'b0;
            timer_threshold <= 32'hFFFFFFFF;
            timer_en        <= 1'b0;
            timer_irq_r     <= 1'b0;
        end else begin
            timer_irq_r <= 1'b0;
            if (timer_en && timer_cnt >= timer_threshold) begin
                timer_irq_r <= 1'b1;
                timer_cnt   <= 32'b0;
            end else if (timer_en) begin
                timer_cnt <= timer_cnt + 32'd1;
            end
            if (data_req && dataAddr_32[31:16] == 16'h1001) begin
                case (dataAddr_32[3:2])
                    2'd0: begin
                        if (dataWen_4 == 4'b0000) timer_threshold <= writeData_32;
                    end
                    2'd1: begin
                        if (dataWen_4 == 4'b0000) timer_en <= writeData_32[0];
                    end
                endcase
            end
        end
    end

    assign timer_irq = timer_irq_r;

endmodule
