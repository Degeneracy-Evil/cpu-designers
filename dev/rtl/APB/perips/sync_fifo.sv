`timescale 1ns / 1ps

// ============================================================================
// sync_fifo — Parameterized synchronous FIFO (single-clock domain)
// ============================================================================
//
// Pointer scheme:
//   wr_ptr and rd_ptr are (ADDR_BITS+1) bits wide. The MSB is a "wrap-around"
//   flag; the lower ADDR_BITS index into the memory array.
//
//   - When wr_ptr == rd_ptr and their MSBs match -> FIFO is empty.
//   - When wr_ptr == rd_ptr and their MSBs differ -> FIFO is full.
//   - count = wr_ptr - rd_ptr  (unsigned subtraction, works across wrap).
//
//   DEPTH must be a power of 2.
//   Read data is combinational (rd_data = mem[rd_ptr[ADDR_BITS-1:0]]).
//   Simultaneous read+write when full: read takes priority, write is blocked.
// ============================================================================

module sync_fifo #(
    parameter WIDTH = 8,    // data bit width
    parameter DEPTH = 16    // FIFO depth (must be power of 2)
) (
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire                      wr_en,
    input  wire  [WIDTH-1:0]         wr_data,
    input  wire                      rd_en,
    output wire  [WIDTH-1:0]         rd_data,
    output wire                      full,
    output wire                      empty,
    output wire  [$clog2(DEPTH):0]   count
);

    localparam ADDR_BITS = $clog2(DEPTH);

    // -------------------------------------------------------------------------
    // Internal storage — single always block to avoid multi-driver on mem
    // -------------------------------------------------------------------------
    reg [ADDR_BITS:0] wr_ptr;
    reg [ADDR_BITS:0] rd_ptr;
    reg [WIDTH-1:0]   mem [0:DEPTH-1];

    // -------------------------------------------------------------------------
    // Status flags
    // -------------------------------------------------------------------------
    assign full  = (wr_ptr[ADDR_BITS] != rd_ptr[ADDR_BITS]) &&
                   (wr_ptr[ADDR_BITS-1:0] == rd_ptr[ADDR_BITS-1:0]);
    assign empty = (wr_ptr == rd_ptr);
    assign count = wr_ptr - rd_ptr;

    // -------------------------------------------------------------------------
    // Combinational read
    // -------------------------------------------------------------------------
    assign rd_data = mem[rd_ptr[ADDR_BITS-1:0]];

    // -------------------------------------------------------------------------
    // Write + Read + Reset — single always block to avoid multi-driver on mem
    // -------------------------------------------------------------------------
    wire wr_valid = wr_en && !full;
    wire rd_valid = rd_en && !empty;

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            for (i = 0; i < DEPTH; i = i + 1)
                mem[i] <= {WIDTH{1'b0}};
        end else begin
            // Write
            if (wr_valid) begin
                mem[wr_ptr[ADDR_BITS-1:0]] <= wr_data;
                wr_ptr <= wr_ptr + 1'b1;
            end
            // Read
            if (rd_valid) begin
                rd_ptr <= rd_ptr + 1'b1;
            end
        end
    end

endmodule
