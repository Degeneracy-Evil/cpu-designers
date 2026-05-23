`include "apb_def.svh"
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

    output wire                        PREADY,
    output reg  [`APB_DATA_WIDTH-1:0]  PRDATA,
    output wire                        PSLVERR,

    output wire [`APB_DATA_WIDTH-1:0]  o_gpioCtrl,
    output wire [`APB_DATA_WIDTH-1:0]  o_gpioData,

    inout  wire  [GPIO_NUM-1:0]        io_gpioPin,

    output reg                         o_irq
);

    localparam GPIO_CTRL     = 4'h0;
    localparam GPIO_DATA     = 4'h4;
    localparam GPIO_IRQ_EN  = 4'h8;
    localparam GPIO_IRQ_STAT = 4'hC;

    reg [`APB_DATA_WIDTH-1:0] gpio_ctrl;
    reg [`APB_DATA_WIDTH-1:0] gpio_irq_en;

    // Split gpio_data to avoid multiple-driver:
    //   gpio_data_lo [GPIO_NUM-1:0]   — pin-connected, driven by generate block
    //   gpio_data_hi [APB_DATA_WIDTH-1:GPIO_NUM] — non-pin, driven by main block
    reg [GPIO_NUM-1:0]               gpio_data_lo;
    reg [`APB_DATA_WIDTH-1:GPIO_NUM] gpio_data_hi;

    wire [`APB_DATA_WIDTH-1:0] gpio_data = {gpio_data_hi, gpio_data_lo};

    // IRQ status: one bit per pin, write-1-to-clear
    reg [GPIO_NUM-1:0] gpio_irq_stat;

    // Pin change detection
    reg  [GPIO_NUM-1:0] gpio_pin_prev;
    wire [GPIO_NUM-1:0] gpio_pin_changed;

    wire write_access = PSEL & PENABLE & PWRITE & PREADY;
    wire read_access  = PSEL & PENABLE & !PWRITE;

    assign o_gpioCtrl = gpio_ctrl;
    assign o_gpioData = gpio_data;

    genvar i;
    generate
        for (i = 0; i < GPIO_NUM; i = i + 1) begin : gen_io_pin
            assign io_gpioPin[i] = gpio_ctrl[i] ? gpio_data_lo[i] : 1'bz;
            // Detect pin value change
            assign gpio_pin_changed[i] = (io_gpioPin[i] !== gpio_pin_prev[i]) &&
                                         !gpio_ctrl[i]; // only input pins
        end
    endgenerate

    assign PREADY  = 1'b1;
    assign PSLVERR = 1'b0;

    // IRQ output: any pending & enabled interrupt
    always @(*) begin
        o_irq = |(gpio_irq_stat & gpio_irq_en[GPIO_NUM-1:0]);
    end

    // Store previous pin values for change detection
    generate
        for (i = 0; i < GPIO_NUM; i = i + 1) begin : gen_pin_prev
            always @(posedge PCLK or negedge PRESETn) begin
                if (!PRESETn) begin
                    gpio_pin_prev[i] <= 1'b0;
                end else begin
                    gpio_pin_prev[i] <= io_gpioPin[i];
                end
            end
        end
    endgenerate

    // IRQ status: set on pin change, write-1-to-clear
    generate
        for (i = 0; i < GPIO_NUM; i = i + 1) begin : gen_irq_stat
            always @(posedge PCLK or negedge PRESETn) begin
                if (!PRESETn) begin
                    gpio_irq_stat[i] <= 1'b0;
                end else begin
                    if (write_access && (PADDR[3:0] == GPIO_IRQ_STAT) && PWDATA[i]) begin
                        gpio_irq_stat[i] <= 1'b0;  // write-1-to-clear
                    end else if (gpio_pin_changed[i] && gpio_irq_en[i]) begin
                        gpio_irq_stat[i] <= 1'b1;  // set on change
                    end
                end
            end
        end
    endgenerate

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            gpio_ctrl    <= {`APB_DATA_WIDTH{1'b0}};
            gpio_data_hi <= {(`APB_DATA_WIDTH-GPIO_NUM){1'b0}};
            gpio_irq_en  <= {`APB_DATA_WIDTH{1'b0}};
        end else begin
            if (write_access) begin
                case (PADDR[3:0])
                    GPIO_CTRL: begin
                        gpio_ctrl <= PWDATA;
                    end
                    GPIO_DATA: begin
                        gpio_data_hi <= PWDATA[`APB_DATA_WIDTH-1:GPIO_NUM];
                    end
                    GPIO_IRQ_EN: begin
                        gpio_irq_en <= PWDATA;
                    end
                    default: ;
                endcase
            end
        end
    end

    always @(*) begin
        if (read_access) begin
            case (PADDR[3:0])
                GPIO_CTRL:     PRDATA = gpio_ctrl;
                GPIO_DATA:     PRDATA = gpio_data;
                GPIO_IRQ_EN:   PRDATA = gpio_irq_en;
                GPIO_IRQ_STAT: PRDATA = {{(`APB_DATA_WIDTH-GPIO_NUM){1'b0}}, gpio_irq_stat};
                default:       PRDATA = {`APB_DATA_WIDTH{1'b0}};
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
