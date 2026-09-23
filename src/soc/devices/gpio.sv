`include "soc/bus/apb/defs.svh"
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
    reg  [GPIO_NUM-1:0] gpio_pin_sync1;
    reg  [GPIO_NUM-1:0] gpio_pin_sync2;
    reg  [GPIO_NUM-1:0] gpio_pin_prev;
    wire [GPIO_NUM-1:0] gpio_pin_changed;

    wire write_access = PSEL & PENABLE & PWRITE & PREADY;
    wire read_access  = PSEL & PENABLE & !PWRITE & PREADY;

    assign o_gpioCtrl = gpio_ctrl;
    assign o_gpioData = gpio_data;

    genvar i;
    generate
        for (i = 0; i < GPIO_NUM; i = i + 1) begin : gen_io_pin
            assign io_gpioPin[i] = gpio_ctrl[i] ? gpio_data_lo[i] : 1'bz;
            // Detect pin value change
            assign gpio_pin_changed[i] = (gpio_pin_sync2[i] != gpio_pin_prev[i]) &&
                                         !gpio_ctrl[i]; // only input pins
        end
    endgenerate

    assign PREADY  = 1'b1;
    assign PSLVERR = 1'b0;

    // IRQ output: any pending & enabled interrupt
    always_comb begin
        o_irq = |(gpio_irq_stat & gpio_irq_en[GPIO_NUM-1:0]);
    end

    // Store previous pin values for change detection
    generate
        for (i = 0; i < GPIO_NUM; i = i + 1) begin : gen_pin_prev
            always_ff @(posedge PCLK or negedge PRESETn) begin
                if (!PRESETn) begin
                    gpio_pin_sync1[i] <= 1'b0;
                    gpio_pin_sync2[i] <= 1'b0;
                    gpio_pin_prev[i] <= 1'b0;
                end else begin
                    gpio_pin_sync1[i] <= io_gpioPin[i];
                    gpio_pin_sync2[i] <= gpio_pin_sync1[i];
                    gpio_pin_prev[i]  <= gpio_pin_sync2[i];
                end
            end
        end
    endgenerate

    // IRQ status: set on pin change, write-1-to-clear with PSTRB gating
    generate
        for (i = 0; i < GPIO_NUM; i = i + 1) begin : gen_irq_stat
            always_ff @(posedge PCLK or negedge PRESETn) begin
                if (!PRESETn) begin
                    gpio_irq_stat[i] <= 1'b0;
                end else begin
                    if (write_access && (PADDR[3:0] == GPIO_IRQ_STAT) && PSTRB[i/8] && PWDATA[i]) begin
                        gpio_irq_stat[i] <= 1'b0;  // write-1-to-clear
                    end else if (gpio_pin_changed[i] && gpio_irq_en[i]) begin
                        gpio_irq_stat[i] <= 1'b1;  // set on change
                    end
                end
            end
        end
    endgenerate

    always_ff @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            gpio_ctrl    <= {`APB_DATA_WIDTH{1'b0}};
            gpio_data_hi <= {(`APB_DATA_WIDTH-GPIO_NUM){1'b0}};
            gpio_irq_en  <= {`APB_DATA_WIDTH{1'b0}};
        end else begin
            if (write_access) begin
                case (PADDR[3:0])
                    GPIO_CTRL: begin
                        // Full 32-bit with PSTRB byte-lane masking
                        if (PSTRB[0]) gpio_ctrl[7:0]   <= PWDATA[7:0];
                        if (PSTRB[1]) gpio_ctrl[15:8]  <= PWDATA[15:8];
                        if (PSTRB[2]) gpio_ctrl[23:16] <= PWDATA[23:16];
                        if (PSTRB[3]) gpio_ctrl[31:24] <= PWDATA[31:24];
                    end
                    GPIO_DATA: begin
                        // gpio_data_hi: upper non-pin bits with PSTRB masking
                        if (PSTRB[2]) gpio_data_hi[23:GPIO_NUM] <= PWDATA[23:GPIO_NUM];
                        if (PSTRB[3]) gpio_data_hi[31:24]       <= PWDATA[31:24];
                    end
                    GPIO_IRQ_EN: begin
                        // Full 32-bit with PSTRB byte-lane masking
                        if (PSTRB[0]) gpio_irq_en[7:0]   <= PWDATA[7:0];
                        if (PSTRB[1]) gpio_irq_en[15:8]  <= PWDATA[15:8];
                        if (PSTRB[2]) gpio_irq_en[23:16] <= PWDATA[23:16];
                        if (PSTRB[3]) gpio_irq_en[31:24] <= PWDATA[31:24];
                    end
                    default: ;
                endcase
            end
        end
    end

    always_comb begin
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
            always_ff @(posedge PCLK or negedge PRESETn) begin
                if (!PRESETn) begin
                    gpio_data_lo[i] <= 1'b0;
                end else begin
                    if (write_access && (PADDR[3:0] == GPIO_DATA) && gpio_ctrl[i] && PSTRB[i/8]) begin
                        gpio_data_lo[i] <= PWDATA[i];
                    end else if (!gpio_ctrl[i]) begin
                        gpio_data_lo[i] <= gpio_pin_sync2[i];
                    end
                end
            end
        end
    endgenerate

endmodule
