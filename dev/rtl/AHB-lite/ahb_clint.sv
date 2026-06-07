`timescale 1ns / 1ps

module ahb_clint(
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

    output wire         o_mtip,
    output wire         o_msip
);

    // AHB-Lite: latch address & control during address phase (HTRANS[1]=1 && HREADY),
    // then use latched values during data phase. The CPU bus bridge sets HTRANS=IDLE
    // in the data phase, so gating on HTRANS[1] would cause reads to return 0 and
    // writes to be silently dropped.
    wire ahb_transfer = HSEL && HTRANS[1] && HREADY;

    reg [31:0] latch_addr;
    reg        latch_write;
    reg        latch_valid;   // High during data phase (cycle after address phase)

    always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            latch_addr   <= 32'b0;
            latch_write  <= 1'b0;
            latch_valid  <= 1'b0;
        end else begin
            latch_valid <= ahb_transfer;
            if (ahb_transfer) begin
                latch_addr   <= HADDR;
                latch_write  <= HWRITE;
            end
        end
    end

    wire rd_valid = latch_valid && !latch_write;
    wire wr_valid = latch_valid && latch_write;

    localparam ADDR_MTIMECMP_LO = 4'h0;
    localparam ADDR_MTIMECMP_HI = 4'h4;
    localparam ADDR_MTIME_LO    = 4'h8;
    localparam ADDR_MTIME_HI    = 4'hC;
    localparam ADDR_MSIP        = 4'h10;

    // Address decode uses LATCHED address (valid during data phase)
    wire addr_cmplo  = (latch_addr[3:0] == ADDR_MTIMECMP_LO);
    wire addr_cmphi  = (latch_addr[3:0] == ADDR_MTIMECMP_HI);
    wire addr_timelo = (latch_addr[3:0] == ADDR_MTIME_LO);
    wire addr_timehi = (latch_addr[3:0] == ADDR_MTIME_HI);
    wire addr_msip   = (latch_addr[3:0] == ADDR_MSIP);

    reg [31:0] r_mtimecmp_lo;
    reg [31:0] r_mtimecmp_hi;
    reg [63:0] r_mtime;
    reg        r_msip;

    wire [63:0] mtimecmp_64;
    assign mtimecmp_64 = {r_mtimecmp_hi, r_mtimecmp_lo};

    wire mtip_raw;
    assign mtip_raw = (r_mtime >= mtimecmp_64) && (mtimecmp_64 != 64'd0);

    assign o_mtip = mtip_raw;
    assign o_msip = r_msip;

    always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            r_mtimecmp_lo <= 32'd0;
            r_mtimecmp_hi <= 32'd0;
            r_mtime       <= 64'd0;
            r_msip        <= 1'b0;
        end else begin
            r_mtime <= r_mtime + 64'd1;

            if (wr_valid && addr_cmplo)
                r_mtimecmp_lo <= HWDATA;
            if (wr_valid && addr_cmphi)
                r_mtimecmp_hi <= HWDATA;
            if (wr_valid && addr_timelo)
                r_mtime[31:0] <= HWDATA;
            if (wr_valid && addr_timehi)
                r_mtime[63:32] <= HWDATA;
            if (wr_valid && addr_msip)
                r_msip <= HWDATA[0];
        end
    end

    always_comb begin
        HRDATA = 32'd0;
        if (rd_valid) begin
            if (addr_cmplo)      HRDATA = r_mtimecmp_lo;
            else if (addr_cmphi) HRDATA = r_mtimecmp_hi;
            else if (addr_timelo) HRDATA = r_mtime[31:0];
            else if (addr_timehi) HRDATA = r_mtime[63:32];
            else if (addr_msip)   HRDATA = {31'b0, r_msip};
        end
    end

    assign HREADYOUT = 1'b1;
    assign HRESP = 1'b0;

endmodule
