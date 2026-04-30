`include "ahb_def.vh"

module ahb_sram_slave #(
    parameter ADDR_WIDTH   = `AHB_ADDR_WIDTH,
    parameter DATA_WIDTH   = `AHB_DATA_WIDTH,
    parameter MEM_DEPTH    = 1024,
    parameter WAIT_STATES  = 0
)(
    input  wire                    HCLK,
    input  wire                    HRESETn,

    input  wire                    HSEL,
    input  wire  [ADDR_WIDTH-1:0]  HADDR,
    input  wire  [1:0]             HTRANS,
    input  wire                    HWRITE,
    input  wire  [2:0]             HSIZE,
    input  wire  [2:0]             HBURST,
    input  wire  [3:0]             HPROT,
    input  wire  [DATA_WIDTH-1:0]  HWDATA,
    input  wire                    HREADY,

    output reg                     HREADYOUT,
    output reg                     HRESP,
    output reg  [DATA_WIDTH-1:0]   HRDATA
);

    localparam INDEX_WIDTH = $clog2(MEM_DEPTH);

    reg [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];

    reg [ADDR_WIDTH-1:0]   latch_addr;
    reg                    latch_write;
    reg [2:0]              latch_size;
    reg                    latch_sel;

    reg [INDEX_WIDTH-1:0]  read_addr;

    wire ahb_transfer = HSEL & HREADY & (HTRANS[1]);

    reg [3:0] wait_cnt;

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            HREADYOUT  <= 1'b1;
            HRESP      <= 1'b0;
            HRDATA     <= {DATA_WIDTH{1'b0}};
            latch_addr <= {ADDR_WIDTH{1'b0}};
            latch_write<= 1'b0;
            latch_size <= `AHB_SIZE_WORD;
            latch_sel  <= 1'b0;
            read_addr  <= {INDEX_WIDTH{1'b0}};
            wait_cnt   <= 4'd0;
        end else begin
            if (wait_cnt > 4'd0) begin
                wait_cnt <= wait_cnt - 4'd1;
                if (wait_cnt == 4'd1) begin
                    HREADYOUT <= 1'b1;
                    if (latch_write) begin
                        case (latch_size)
                            `AHB_SIZE_BYTE: begin
                                mem[latch_addr[INDEX_WIDTH+1:2]][latch_addr[1:0]*8 +: 8] <= HWDATA[7:0];
                            end
                            `AHB_SIZE_HWORD: begin
                                mem[latch_addr[INDEX_WIDTH+1:2]][latch_addr[1]*16 +: 16] <= HWDATA[15:0];
                            end
                            default: begin
                                mem[latch_addr[INDEX_WIDTH+1:2]] <= HWDATA;
                            end
                        endcase
                    end else begin
                        HRDATA <= mem[read_addr];
                    end
                end
            end else if (ahb_transfer) begin
                latch_addr  <= HADDR;
                latch_write <= HWRITE;
                latch_size  <= HSIZE;
                latch_sel   <= 1'b1;
                read_addr   <= HADDR[INDEX_WIDTH+1:2];

                if (WAIT_STATES > 0) begin
                    wait_cnt  <= WAIT_STATES;
                    HREADYOUT <= 1'b0;
                    HRESP     <= 1'b0;
                end else begin
                    HREADYOUT <= 1'b1;
                    HRESP     <= 1'b0;
                    if (HWRITE) begin
                        case (HSIZE)
                            `AHB_SIZE_BYTE: begin
                                mem[HADDR[INDEX_WIDTH+1:2]][HADDR[1:0]*8 +: 8] <= HWDATA[7:0];
                            end
                            `AHB_SIZE_HWORD: begin
                                mem[HADDR[INDEX_WIDTH+1:2]][HADDR[1]*16 +: 16] <= HWDATA[15:0];
                            end
                            default: begin
                                mem[HADDR[INDEX_WIDTH+1:2]] <= HWDATA;
                            end
                        endcase
                    end else begin
                        HRDATA <= mem[HADDR[INDEX_WIDTH+1:2]];
                    end
                end
            end else if (HSEL && HREADY && (HTRANS == `AHB_TRANS_IDLE || HTRANS == `AHB_TRANS_BUSY)) begin
                HREADYOUT <= 1'b1;
                HRESP     <= 1'b0;
                latch_sel <= 1'b0;
            end else if (!HSEL && HREADY) begin
                HREADYOUT <= 1'b1;
                HRESP     <= 1'b0;
                latch_sel <= 1'b0;
            end
        end
    end

endmodule
