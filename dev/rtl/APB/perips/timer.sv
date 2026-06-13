`include "apb_def.svh"
`include "timer_define.svh"
`timescale 1ns / 1ps

module timer(
    input  wire                        PCLK,
    input  wire                        PRESETn,

    input  wire  [`APB_ADDR_WIDTH-1:0] PADDR,
    input  wire  [`APB_PROT_WIDTH-1:0] PPROT,
    input  wire                        PSEL,
    input  wire                        PENABLE,
    input  wire                        PWRITE,
    input  wire  [`APB_DATA_WIDTH-1:0] PWDATA,
    input  wire  [`APB_STRB_WIDTH-1:0] PSTRB,

    output wire                        PREADY,
    output reg  [`APB_DATA_WIDTH-1:0]  PRDATA,
    output wire                        PSLVERR,

    output reg                         o_irq
);

    reg      mode;
    reg      start;
    reg [31:0] expr_val;
    reg [31:0] counter;

    wire write_access = PSEL & PENABLE & PWRITE & PREADY;
    wire read_access  = PSEL & PENABLE & !PWRITE & PREADY;

    wire expr_flag = (start && (counter >= expr_val) && (expr_val != 32'b0));

    assign PREADY  = 1'b1;
    assign PSLVERR = 1'b0;

    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            start    <= 1'b0;
            mode     <= `TIMER_MODE_PERIODIC;
            o_irq    <= 1'b0;
            expr_val <= 32'h0;
            counter  <= 32'h0;
        end else begin
            // expr_val: full 32-bit with PSTRB byte-lane masking
            if (write_access && (PADDR[3:2] == 2'd0)) begin
                if (PSTRB[0]) expr_val[7:0]   <= PWDATA[7:0];
                if (PSTRB[1]) expr_val[15:8]  <= PWDATA[15:8];
                if (PSTRB[2]) expr_val[23:16] <= PWDATA[23:16];
                if (PSTRB[3]) expr_val[31:24] <= PWDATA[31:24];
            end

            // start/mode: both in byte 0, gated by PSTRB[0]
            if (write_access && (PADDR[3:2] == 2'd1) && PSTRB[0]) begin
                start <= PWDATA[`TimerStartLoc];
                mode  <= PWDATA[`TimerModeLoc];
            end else if (expr_flag && (mode == `TIMER_MODE_ONE_SHOT)) begin
                start <= 1'b0;
            end

            // o_irq clear: bit 0 in byte 0, gated by PSTRB[0]
            if (expr_flag) begin
                o_irq <= 1'b1;
            end else if (write_access && (PADDR[3:2] == 2'd2) && PSTRB[0]) begin
                o_irq <= PWDATA[`TimerIrqLoc];
            end

            // counter: full 32-bit with PSTRB byte-lane masking
            if (write_access && (PADDR[3:2] == 2'd3)) begin
                if (PSTRB[0]) counter[7:0]   <= PWDATA[7:0];
                if (PSTRB[1]) counter[15:8]  <= PWDATA[15:8];
                if (PSTRB[2]) counter[23:16] <= PWDATA[23:16];
                if (PSTRB[3]) counter[31:24] <= PWDATA[31:24];
            end else if (expr_flag) begin
                counter <= 32'h0;
            end else if (start) begin
                counter <= counter + 1'b1;
            end
        end
    end

    always_comb begin
        if (read_access) begin
            case (PADDR[3:2])
                2'd0: PRDATA = expr_val;
                2'd1: PRDATA = {30'b0, mode, start};
                2'd2: PRDATA = {31'b0, o_irq};
                2'd3: PRDATA = counter;
            endcase
        end else begin
            PRDATA = {`APB_DATA_WIDTH{1'b0}};
        end
    end

endmodule
