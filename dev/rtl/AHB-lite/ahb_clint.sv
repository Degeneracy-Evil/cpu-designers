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

    wire access_active = HSEL && HTRANS[1];
    wire rd_valid = access_active && !HWRITE;
    wire wr_valid = access_active && HWRITE && HREADY;

    localparam ADDR_MTIMECMP_LO = 4'h0;
    localparam ADDR_MTIMECMP_HI = 4'h4;
    localparam ADDR_MTIME_LO    = 4'h8;
    localparam ADDR_MTIME_HI    = 4'hC;

    wire addr_cmplo  = (HADDR[3:0] == ADDR_MTIMECMP_LO);
    wire addr_cmphi  = (HADDR[3:0] == ADDR_MTIMECMP_HI);
    wire addr_timelo = (HADDR[3:0] == ADDR_MTIME_LO);
    wire addr_timehi = (HADDR[3:0] == ADDR_MTIME_HI);

    reg [31:0] r_mtimecmp_lo;
    reg [31:0] r_mtimecmp_hi;
    reg [63:0] r_mtime;

    wire [63:0] mtimecmp_64;
    assign mtimecmp_64 = {r_mtimecmp_hi, r_mtimecmp_lo};

    wire mtip_raw;
    assign mtip_raw = (r_mtime >= mtimecmp_64) && (mtimecmp_64 != 64'd0);

    assign o_mtip = mtip_raw;
    assign o_msip = 1'b0;

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            r_mtimecmp_lo <= 32'd0;
            r_mtimecmp_hi <= 32'd0;
            r_mtime       <= 64'd0;
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
        end
    end

    always @(*) begin
        HRDATA = 32'd0;
        if (rd_valid) begin
            if (addr_cmplo)      HRDATA = r_mtimecmp_lo;
            else if (addr_cmphi) HRDATA = r_mtimecmp_hi;
            else if (addr_timelo) HRDATA = r_mtime[31:0];
            else if (addr_timehi) HRDATA = r_mtime[63:32];
        end
    end

    assign HREADYOUT = 1'b1;
    assign HRESP = 1'b0;

endmodule
