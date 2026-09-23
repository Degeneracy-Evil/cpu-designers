`include "common/bus/axi.svh"
`include "soc/bus/apb/defs.svh"
`timescale 1ns / 1ps

module axi4lite_to_apb #(
    parameter ADDR_WIDTH = `APB_ADDR_WIDTH,
    parameter DATA_WIDTH = `APB_DATA_WIDTH
)(
    // =========================================================================
    // AXI4-Lite Slave Interface
    // =========================================================================
    input  logic        s_axi_aclk,
    input  logic        s_axi_aresetn,

    input  logic [31:0] s_axi_awaddr,
    input  logic [2:0]  s_axi_awprot,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,

    input  logic [31:0] s_axi_wdata,
    input  logic [3:0]  s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,

    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,

    input  logic [31:0] s_axi_araddr,
    input  logic [2:0]  s_axi_arprot,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,

    output logic [31:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready,

    // =========================================================================
    // APB Master Interface (drives APB bus — same signals as ahb_lite_to_apb)
    // =========================================================================
    output logic [ADDR_WIDTH-1:0]   PADDR,
    output logic [2:0]              PPROT,
    output logic                    PSEL,
    output logic                    PENABLE,
    output logic                    PWRITE,
    output logic [DATA_WIDTH-1:0]   PWDATA,
    output logic [DATA_WIDTH/8-1:0] PSTRB,

    input  logic                    PREADY,
    input  logic [DATA_WIDTH-1:0]   PRDATA,
    input  logic                    PSLVERR
);

    // -------------------------------------------------------------------------
    // State encoding
    // -------------------------------------------------------------------------
    localparam logic [2:0] ST_IDLE         = 3'b000;
    localparam logic [2:0] ST_READ_SETUP   = 3'b001;
    localparam logic [2:0] ST_READ_ACCESS  = 3'b010;
    localparam logic [2:0] ST_READ_RESP    = 3'b011;
    localparam logic [2:0] ST_WRITE_SETUP  = 3'b100;
    localparam logic [2:0] ST_WRITE_ACCESS = 3'b101;
    localparam logic [2:0] ST_WRITE_RESP   = 3'b110;

    logic [2:0] state;

    // Active transaction fields driven onto APB and AXI responses
    logic [ADDR_WIDTH-1:0]   latch_addr;
    logic [2:0]              latch_prot;
    logic [DATA_WIDTH-1:0]   latch_wdata;
    logic [DATA_WIDTH/8-1:0] latch_wstrb;
    logic [DATA_WIDTH-1:0]   latch_rdata;
    logic                    latch_slverr;

    // Pending write channel storage. AXI4-Lite allows AW and W to arrive
    // independently, so keep them separate until a complete write request is
    // assembled, then copy into the active APB transaction latches.
    logic [ADDR_WIDTH-1:0]   pending_awaddr;
    logic [2:0]              pending_awprot;
    logic [DATA_WIDTH-1:0]   pending_wdata;
    logic [DATA_WIDTH/8-1:0] pending_wstrb;
    logic aw_latched;
    logic w_latched;

    // -------------------------------------------------------------------------
    // AXI4-Lite handshake outputs
    // -------------------------------------------------------------------------
    // AW and W channels are accepted independently via latching.
    // Read has priority when no write channel is partially latched.
    // Once any write channel is latched, the write is committed and
    // must complete before a read can be accepted.
    assign s_axi_arready = (state == ST_IDLE) && !aw_latched && !w_latched;
    assign s_axi_awready = (state == ST_IDLE) && !aw_latched &&
                           (w_latched || !s_axi_arvalid);
    assign s_axi_wready  = (state == ST_IDLE) && !w_latched &&
                           (aw_latched || !s_axi_arvalid);

    // R channel — driven from latched values; stable while RVALID && !RREADY
    assign s_axi_rvalid = (state == ST_READ_RESP);
    assign s_axi_rdata  = latch_rdata;
    assign s_axi_rresp  = latch_slverr ? `AXI_RESP_SLVERR : `AXI_RESP_OKAY;

    // B channel — driven from latched value; stable while BVALID && !BREADY
    assign s_axi_bvalid = (state == ST_WRITE_RESP);
    assign s_axi_bresp  = latch_slverr ? `AXI_RESP_SLVERR : `AXI_RESP_OKAY;

    // -------------------------------------------------------------------------
    // APB output combinational logic
    // -------------------------------------------------------------------------
    always_comb begin
        PADDR  = latch_addr;
        // AXI4 AxPROT[0] and APB4 PPROT[0] have opposite polarity:
        //   AXI4: 0=Privileged, 1=Unprivileged
        //   APB4: 0=Unprivileged, 1=Privileged
        // Bits [2:1] are identical polarity in both protocols.
        PPROT  = {latch_prot[2], latch_prot[1], ~latch_prot[0]};
        PWDATA = latch_wdata;
        PSTRB  = latch_wstrb;

        case (state)
            ST_READ_SETUP: begin
                PSEL    = 1'b1;
                PENABLE = 1'b0;
                PWRITE  = 1'b0;
            end
            ST_READ_ACCESS: begin
                PSEL    = 1'b1;
                PENABLE = 1'b1;
                PWRITE  = 1'b0;
            end
            ST_WRITE_SETUP: begin
                PSEL    = 1'b1;
                PENABLE = 1'b0;
                PWRITE  = 1'b1;
            end
            ST_WRITE_ACCESS: begin
                PSEL    = 1'b1;
                PENABLE = 1'b1;
                PWRITE  = 1'b1;
            end
            default: begin  // IDLE, READ_RESP, WRITE_RESP
                PSEL    = 1'b0;
                PENABLE = 1'b0;
                PWRITE  = 1'b0;
            end
        endcase
    end

    // -------------------------------------------------------------------------
    // State machine & latch updates
    // -------------------------------------------------------------------------
    always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            state        <= ST_IDLE;
            latch_addr   <= {ADDR_WIDTH{1'b0}};
            latch_prot   <= 3'b0;
            latch_wdata  <= {DATA_WIDTH{1'b0}};
            latch_wstrb  <= {(DATA_WIDTH/8){1'b0}};
            latch_rdata  <= {DATA_WIDTH{1'b0}};
            latch_slverr <= 1'b0;
            pending_awaddr <= {ADDR_WIDTH{1'b0}};
            pending_awprot <= 3'b0;
            pending_wdata  <= {DATA_WIDTH{1'b0}};
            pending_wstrb  <= {(DATA_WIDTH/8){1'b0}};
            aw_latched   <= 1'b0;
            w_latched    <= 1'b0;
        end else begin
            case (state)
                // -------------------------------------------------------------
                // IDLE — accept new AXI4-Lite transaction
                // AW and W channels are latched independently; once both
                // are latched the APB write proceeds.  Read has priority
                // only when no write channel is partially latched.
                // -------------------------------------------------------------
                ST_IDLE: begin
                    if (s_axi_arvalid && !aw_latched && !w_latched) begin
                        // Read request: latch AR channel
                        state       <= ST_READ_SETUP;
                        latch_addr  <= s_axi_araddr;
                        latch_prot  <= s_axi_arprot;
                        latch_wstrb <= {(DATA_WIDTH/8){1'b0}};
                        aw_latched  <= 1'b0;
                        w_latched   <= 1'b0;
                    end else begin
                        // Latch AW channel if valid and not already latched
                        if (s_axi_awvalid && !aw_latched) begin
                            pending_awaddr <= s_axi_awaddr;
                            pending_awprot <= s_axi_awprot;
                            aw_latched  <= 1'b1;
                        end
                        // Latch W channel if valid and not already latched
                        if (s_axi_wvalid && !w_latched) begin
                            pending_wdata <= s_axi_wdata;
                            pending_wstrb <= s_axi_wstrb;
                            w_latched   <= 1'b1;
                        end
                        // When both channels are (or will be) latched,
                        // proceed to APB write setup phase
                        if ((aw_latched || s_axi_awvalid) &&
                            (w_latched  || s_axi_wvalid)) begin
                            latch_addr  <= aw_latched ? pending_awaddr : s_axi_awaddr;
                            latch_prot  <= aw_latched ? pending_awprot : s_axi_awprot;
                            latch_wdata <= w_latched  ? pending_wdata  : s_axi_wdata;
                            latch_wstrb <= w_latched  ? pending_wstrb  : s_axi_wstrb;
                            aw_latched  <= 1'b0;
                            w_latched   <= 1'b0;
                            state <= ST_WRITE_SETUP;
                        end
                    end
                end

                // -------------------------------------------------------------
                // READ_SETUP — APB setup phase (PSEL=1, PENABLE=0, PWRITE=0)
                // -------------------------------------------------------------
                ST_READ_SETUP: begin
                    state <= ST_READ_ACCESS;
                end

                // -------------------------------------------------------------
                // READ_ACCESS — APB access phase (PENABLE=1), wait for PREADY
                // -------------------------------------------------------------
                ST_READ_ACCESS: begin
                    if (PREADY) begin
                        state        <= ST_READ_RESP;
                        latch_rdata  <= PRDATA;
                        latch_slverr <= PSLVERR;
                    end
                end

                // -------------------------------------------------------------
                // READ_RESP — drive R channel, wait for RREADY
                // -------------------------------------------------------------
                ST_READ_RESP: begin
                    if (s_axi_rready) begin
                        state <= ST_IDLE;
                    end
                end

                // -------------------------------------------------------------
                // WRITE_SETUP — APB setup phase (PSEL=1, PENABLE=0, PWRITE=1)
                // -------------------------------------------------------------
                ST_WRITE_SETUP: begin
                    state <= ST_WRITE_ACCESS;
                end

                // -------------------------------------------------------------
                // WRITE_ACCESS — APB access phase (PENABLE=1), wait for PREADY
                // -------------------------------------------------------------
                ST_WRITE_ACCESS: begin
                    if (PREADY) begin
                        state        <= ST_WRITE_RESP;
                        latch_slverr <= PSLVERR;
                    end
                end

                // -------------------------------------------------------------
                // WRITE_RESP — drive B channel, wait for BREADY
                // -------------------------------------------------------------
                ST_WRITE_RESP: begin
                    if (s_axi_bready) begin
                        state       <= ST_IDLE;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
