`include "apb_def.vh"

module spi(
    input  wire                        PCLK,
    input  wire                        PRESETn,

    input  wire  [`APB_ADDR_WIDTH-1:0] PADDR,
    input  wire  [`APB_PROT_WIDTH-1:0] PPROT,
    input  wire                        PSEL,
    input  wire                        PENABLE,
    input  wire                        PWRITE,
    input  wire  [`APB_DATA_WIDTH-1:0] PWDATA,
    input  wire  [`APB_STRB_WIDTH-1:0] PSTRB,

    output reg                         PREADY,
    output reg  [`APB_DATA_WIDTH-1:0]  PRDATA,
    output reg                         PSLVERR,

    output reg                         o_spiMosi,
    input  wire                        i_spiMiso,
    output wire                        o_spiSs,
    output reg                         o_spiClk
);

    localparam SPI_CTRL   = 4'h0;
    localparam SPI_DATA   = 4'h4;
    localparam SPI_STATUS = 4'h8;

    reg [`APB_DATA_WIDTH-1:0] spi_ctrl;
    reg [`APB_DATA_WIDTH-1:0] spi_data;
    reg [`APB_DATA_WIDTH-1:0] spi_status;

    reg [8:0]  clk_cnt;
    reg        en;
    reg [4:0]  spi_clk_edge_cnt;
    reg        spi_clk_edge_level;
    reg [7:0]  rdata;
    reg        done;
    reg [3:0]  bit_index;
    wire [8:0] div_cnt;

    wire write_access = PSEL & PENABLE & PWRITE & PREADY;
    wire read_access  = PSEL & PENABLE & !PWRITE;

    assign o_spiSs  = ~spi_ctrl[3];
    assign div_cnt  = spi_ctrl[15:8];

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            en <= 1'b0;
            PREADY  <= 1'b1;
            PSLVERR <= 1'b0;
        end else begin
            PREADY  <= 1'b1;
            PSLVERR <= 1'b0;

            if (write_access && (PADDR[3:0] == SPI_CTRL) && PWDATA[0]) begin
                en <= 1'b1;
            end else if (done) begin
                en <= 1'b0;
            end
        end
    end

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            clk_cnt <= 9'h0;
        end else if (en) begin
            if (clk_cnt == div_cnt) begin
                clk_cnt <= 9'h0;
            end else begin
                clk_cnt <= clk_cnt + 1'b1;
            end
        end else begin
            clk_cnt <= 9'h0;
        end
    end

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            spi_clk_edge_cnt   <= 5'h0;
            spi_clk_edge_level <= 1'b0;
        end else if (en) begin
            if (clk_cnt == div_cnt) begin
                if (spi_clk_edge_cnt == 5'd17) begin
                    spi_clk_edge_cnt   <= 5'h0;
                    spi_clk_edge_level <= 1'b0;
                end else begin
                    spi_clk_edge_cnt   <= spi_clk_edge_cnt + 1'b1;
                    spi_clk_edge_level <= 1'b1;
                end
            end else begin
                spi_clk_edge_level <= 1'b0;
            end
        end else begin
            spi_clk_edge_cnt   <= 5'h0;
            spi_clk_edge_level <= 1'b0;
        end
    end

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            o_spiClk   <= 1'b0;
            rdata      <= 8'h0;
            o_spiMosi  <= 1'b0;
            bit_index  <= 4'h0;
        end else begin
            if (en) begin
                if (spi_clk_edge_level) begin
                    case (spi_clk_edge_cnt)
                        1, 3, 5, 7, 9, 11, 13, 15: begin
                            o_spiClk <= ~o_spiClk;
                            if (spi_ctrl[2]) begin
                                o_spiMosi <= spi_data[bit_index];
                                bit_index <= bit_index - 1'b1;
                            end else begin
                                rdata <= {rdata[6:0], i_spiMiso};
                            end
                        end
                        2, 4, 6, 8, 10, 12, 14, 16: begin
                            o_spiClk <= ~o_spiClk;
                            if (spi_ctrl[2]) begin
                                rdata <= {rdata[6:0], i_spiMiso};
                            end else begin
                                o_spiMosi <= spi_data[bit_index];
                                bit_index <= bit_index - 1'b1;
                            end
                        end
                        17: begin
                            o_spiClk <= spi_ctrl[1];
                        end
                    endcase
                end
            end else begin
                o_spiClk <= spi_ctrl[1];
                if (!spi_ctrl[2]) begin
                    o_spiMosi <= spi_data[7];
                    bit_index <= 4'h6;
                end else begin
                    bit_index <= 4'h7;
                end
            end
        end
    end

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            done <= 1'b0;
        end else begin
            if (en && spi_clk_edge_cnt == 5'd17) begin
                done <= 1'b1;
            end else begin
                done <= 1'b0;
            end
        end
    end

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            spi_ctrl   <= 32'h0;
            spi_data   <= 32'h0;
            spi_status <= 32'h0;
        end else begin
            spi_status[0] <= en;

            if (write_access) begin
                case (PADDR[3:0])
                    SPI_CTRL: spi_ctrl <= PWDATA;
                    SPI_DATA: spi_data <= PWDATA;
                    default: ;
                endcase
            end

            if (done) begin
                spi_data[7:0] <= rdata;
                spi_ctrl[0]   <= 1'b0;
            end
        end
    end

    always @(*) begin
        if (read_access) begin
            case (PADDR[3:0])
                SPI_CTRL:   PRDATA = spi_ctrl;
                SPI_DATA:   PRDATA = spi_data;
                SPI_STATUS: PRDATA = spi_status;
                default:    PRDATA = {`APB_DATA_WIDTH{1'b0}};
            endcase
        end else begin
            PRDATA = {`APB_DATA_WIDTH{1'b0}};
        end
    end

endmodule
