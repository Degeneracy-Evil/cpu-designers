`include "apb_def.vh"
`timescale 1ns / 1ps

module gpio #(
    parameter GPIO_NUM = 16
)(
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

    output wire [`APB_DATA_WIDTH-1:0]  o_gpioCtrl,
    output wire [`APB_DATA_WIDTH-1:0]  o_gpioData,

    inout  wire  [GPIO_NUM-1:0]        io_gpioPin
);

    localparam GPIO_CTRL = 4'h0;
    localparam GPIO_DATA = 4'h4;

    reg [`APB_DATA_WIDTH-1:0] gpio_ctrl;

    // Split gpio_data to avoid multiple-driver:
    //   gpio_data_lo [GPIO_NUM-1:0]   — pin-connected, driven by generate block
    //   gpio_data_hi [APB_DATA_WIDTH-1:GPIO_NUM] — non-pin, driven by main block
    reg [GPIO_NUM-1:0]               gpio_data_lo;
    reg [`APB_DATA_WIDTH-1:GPIO_NUM] gpio_data_hi;

    wire [`APB_DATA_WIDTH-1:0] gpio_data = {gpio_data_hi, gpio_data_lo};

    wire access_end = PSEL & PENABLE & PREADY;
    wire write_access = PSEL & PENABLE & PWRITE & PREADY;
    wire read_access  = PSEL & PENABLE & !PWRITE;

    assign o_gpioCtrl = gpio_ctrl;
    assign o_gpioData = gpio_data;

    genvar i;
    generate
        for (i = 0; i < GPIO_NUM; i = i + 1) begin : gen_io_pin
            assign io_gpioPin[i] = gpio_ctrl[i] ? gpio_data_lo[i] : 1'bz;
        end
    endgenerate

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            gpio_ctrl    <= {`APB_DATA_WIDTH{1'b0}};
            gpio_data_hi <= {(`APB_DATA_WIDTH-GPIO_NUM){1'b0}};
            PREADY       <= 1'b1;
            PSLVERR      <= 1'b0;
        end else begin
            PREADY  <= 1'b1;
            PSLVERR <= 1'b0;

            if (write_access) begin
                case (PADDR[3:0])
                    GPIO_CTRL: begin
                        gpio_ctrl <= PWDATA;
                    end
                    GPIO_DATA: begin
                        gpio_data_hi <= PWDATA[`APB_DATA_WIDTH-1:GPIO_NUM];
                    end
                    default: ;
                endcase
            end
        end
    end

    always @(*) begin
        if (read_access) begin
            case (PADDR[3:0])
                GPIO_CTRL: PRDATA = gpio_ctrl;
                GPIO_DATA: PRDATA = gpio_data;
                default:   PRDATA = {`APB_DATA_WIDTH{1'b0}};
            endcase
        end else begin
            PRDATA = {`APB_DATA_WIDTH{1'b0}};
        end
    end

    generate
        for (i = 0; i < GPIO_NUM; i = i + 1) begin : gen_io_data
            always @(posedge PCLK or negedge PRESETn) begin
                if (!PRESETn) begin
                    gpio_data_lo[i] <= 1'b0;
                end else begin
                    if (write_access && (PADDR[3:0] == GPIO_DATA) && gpio_ctrl[i]) begin
                        gpio_data_lo[i] <= PWDATA[i];
                    end else if (!gpio_ctrl[i]) begin
                        gpio_data_lo[i] <= io_gpioPin[i];
                    end
                end
            end
        end
    endgenerate

endmodule
