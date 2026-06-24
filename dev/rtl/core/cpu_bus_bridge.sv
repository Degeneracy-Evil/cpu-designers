`timescale 1ns / 1ps
`include "axi4_def.svh"

// BUG-86 (UART RXDATA double-pop) was originally fixed with Approach A+C
// (mmio_req gated by !cpu_req_ready_r + mmio_*_served held until req deasserts).
// BUG-91 subsequently replaced this with a proper pending/accept/resp_valid
// three-phase handshake, which is the current implementation:
//   - icache/dcache drive mmio_req = mmio_pending_r (single-cycle pulse intent)
//   - bus bridge asserts mmio_accept for 1 cycle in S_IDLE when selecting a source
//   - cache clears mmio_pending_r on accept, sets mmio_inflight_r (BUG-97)
//   - mmio_*_served has been deleted; "was this request already served?" is now
//     guaranteed by the source-side pending bit, not by bridge-side served flags
//   - mmio_addr/mmio_wdata/mmio_hwrite/mmio_hsize are latched in cache (BUG-91
//     supplementary fix) to prevent stale-response misjudgment

module cpu_bus_bridge(
    input         clk,
    input         resetn,

    // ---------- Cache / MMIO request inputs (unchanged) ----------
    input         icache_mmio_req,
    output        icache_mmio_accept,
    input  [31:0] icache_mmio_addr,

    input         dcache_mmio_req,
    output        dcache_mmio_accept,
    input  [31:0] dcache_mmio_addr,
    input  [31:0] dcache_mmio_wdata,
    input         dcache_mmio_hwrite,
    input  [2:0]  dcache_mmio_hsize,

    output [31:0] ahb_inst_data,
    output        ahb_inst_valid,
    output [31:0] ahb_data_rdata,
    output        ahb_data_valid,

    input         icache_refill_req,
    input  [31:0] icache_refill_addr,
    output [255:0] icache_refill_data,
    output        icache_refill_valid,

    input         dcache_refill_req,
    input  [31:0] dcache_refill_addr,
    output [255:0] dcache_refill_data,
    output        dcache_refill_valid,
    output        dcache_refill_done,
    output        dcache_refill_error,

    input         dcache_wb_req,
    input  [31:0] dcache_wb_addr,
    input  [255:0] dcache_wb_data,
    output        dcache_wb_valid,
    output        dcache_wb_done,
    output        dcache_wb_error,

    // ---------- AXI4 Master — AW Channel (Write Address) ----------
    output logic [3:0]  awid,
    output logic [31:0] awaddr,
    output logic [7:0]  awlen,
    output logic [2:0]  awsize,
    output logic [1:0]  awburst,
    output logic        awlock,
    output logic [3:0]  awcache,
    output logic [2:0]  awprot,
    output logic [3:0]  awqos,
    output logic [3:0]  awregion,
    output logic        awvalid,
    input  logic        awready,

    // ---------- AXI4 Master — W Channel (Write Data) ----------
    output logic [31:0] wdata,
    output logic [3:0]  wstrb,
    output logic        wlast,
    output logic        wvalid,
    input  logic        wready,

    // ---------- AXI4 Master — B Channel (Write Response) ----------
    input  logic [1:0]  bresp,
    input  logic        bvalid,
    output logic        bready,

    // ---------- AXI4 Master — AR Channel (Read Address) ----------
    output logic [3:0]  arid,
    output logic [31:0] araddr,
    output logic [7:0]  arlen,
    output logic [2:0]  arsize,
    output logic [1:0]  arburst,
    output logic        arlock,
    output logic [3:0]  arcache,
    output logic [2:0]  arprot,
    output logic [3:0]  arqos,
    output logic [3:0]  arregion,
    output logic        arvalid,
    input  logic        arready,

    // ---------- AXI4 Master — R Channel (Read Data) ----------
    input  logic [31:0] rdata,
    input  logic [1:0]  rresp,
    input  logic        rlast,
    input  logic        rvalid,
    output logic        rready,

    // ---------- Error outputs (unchanged) ----------
    output        icache_error,
    output        dcache_error,
    output        dcache_error_is_store,
    output [31:0] bus_error_addr
);

    // =====================================================================
    // State encoding — AXI4 has more phases than AHB-Lite
    //   Read:  AR (issue address) → R  (receive data beats)
    //   Write: AW+W (issue addr+data) → B (receive response)
    //          or AW → W (burst beats) → B
    // =====================================================================
    localparam S_IDLE          = 4'd0;
    // MMIO read
    localparam S_MMIO_AR       = 4'd1;
    localparam S_MMIO_R        = 4'd2;
    // MMIO write (AW+W simultaneous for single-beat)
    localparam S_MMIO_AW_W     = 4'd3;
    localparam S_MMIO_B        = 4'd4;
    // icache refill (burst read)
    localparam S_IREFILL_AR    = 4'd5;
    localparam S_IREFILL_R     = 4'd6;
    // dcache refill (burst read)
    localparam S_DREFILL_AR    = 4'd7;
    localparam S_DREFILL_R     = 4'd8;
    // dcache writeback (burst write)
    localparam S_WB_AW         = 4'd9;
    localparam S_WB_W          = 4'd10;
    localparam S_WB_B          = 4'd11;

    reg [3:0] state;

    // ---------- Latched request metadata ----------
    reg [31:0] addr_r;
    reg        write_r;
    reg [2:0]  size_r;
    reg        is_inst_r;       // 1 = icache MMIO, 0 = dcache MMIO
    reg [31:0] latch_wdata_r;

    // ---------- Burst tracking ----------
    reg [2:0]  beat_cnt;
    reg [31:0] burst_base_addr;
    reg [255:0] refill_shift_reg;
    reg [255:0] wb_shift_reg;

    // ---------- Response registers ----------
    reg [31:0] ahb_inst_data_r;
    reg        ahb_inst_valid_r;
    reg [31:0] ahb_data_rdata_r;
    reg        ahb_data_valid_r;

    reg        icache_mmio_accept_r;
    reg        dcache_mmio_accept_r;

    reg        icache_refill_valid_r;
    reg        dcache_refill_valid_r;
    reg        dcache_wb_valid_r;
    reg        dcache_refill_done_r;
    reg        dcache_refill_error_r;
    reg        dcache_wb_done_r;
    reg        dcache_wb_error_r;
    reg        dcache_wb_wait_drop_r;

    reg        icache_error_r;
    reg        dcache_error_r;
    reg        dcache_error_is_store_r;
    reg [31:0] bus_error_addr_r;
    reg [2:0]  wb_starve_cnt_r;
    reg        wb_boost_r;

    // ---------- Simultaneous AW+W handshake tracking ----------
    reg aw_hs_done_r;
    reg w_hs_done_r;

    // =====================================================================
    // Output assignments — response side
    // =====================================================================
    assign ahb_inst_data     = ahb_inst_data_r;
    assign ahb_inst_valid    = ahb_inst_valid_r;
    assign icache_mmio_accept = icache_mmio_accept_r;
    assign ahb_data_rdata    = ahb_data_rdata_r;
    assign ahb_data_valid    = ahb_data_valid_r;
    assign dcache_mmio_accept = dcache_mmio_accept_r;
    wire refill_capture_active = ((state == S_IREFILL_R) || (state == S_DREFILL_R)) && rvalid && !r_error;
    wire [255:0] refill_shift_reg_with_current =
        refill_capture_active ? ((refill_shift_reg & ~({224'b0, 32'hFFFF_FFFF} << (beat_cnt * 32))) |
                                 ({224'b0, rdata} << (beat_cnt * 32))) :
                                refill_shift_reg;

    assign icache_refill_data  = refill_shift_reg_with_current;
    assign icache_refill_valid = icache_refill_valid_r;
    assign dcache_refill_data  = refill_shift_reg_with_current;
    assign dcache_refill_valid = dcache_refill_valid_r;
    assign dcache_refill_done  = dcache_refill_done_r;
    assign dcache_refill_error = dcache_refill_error_r;
    assign dcache_wb_valid     = dcache_wb_valid_r;
    assign dcache_wb_done      = dcache_wb_done_r;
    assign dcache_wb_error     = dcache_wb_error_r;

    assign icache_error        = icache_error_r;
    assign dcache_error        = dcache_error_r;
    assign dcache_error_is_store = dcache_error_is_store_r;
    assign bus_error_addr      = bus_error_addr_r;

    // =====================================================================
    // AXI4 default outputs — safe values when channels are idle
    // =====================================================================
    // ID, QoS, Region — constant
    assign awid     = 4'b0000;
    assign arid     = 4'b0000;
    assign awqos    = 4'b0000;   // Not used in this design
    assign awregion = 4'b0000;
    assign arqos    = 4'b0000;
    assign arregion = 4'b0000;

    // =====================================================================
    // Helper: AXI4 error check (OKAY=00, EXOKAY=01 are success)
    // =====================================================================
    wire r_error = (rresp == `AXI_RESP_SLVERR) || (rresp == `AXI_RESP_DECERR);
    wire b_error = (bresp == `AXI_RESP_SLVERR) || (bresp == `AXI_RESP_DECERR);

    // =====================================================================
    // Sub-word store: shift wstrb and wdata to correct byte lane
    //   addr_r[1:0] determines which byte lane within the 32-bit word.
    //   Byte store:   4'b0001 << lane  (single byte strobe)
    //   Halfword:     4'b0011 << lane  (lane must be 0 or 2)
    //   Word:         4'b1111          (all bytes, lane must be 0)
    //   Byte stores arrive unshifted and need lane placement here.
    //   Halfword/word stores are already lane-positioned by cpu_mem.
    // =====================================================================
    wire [1:0]  mmio_byte_lane = addr_r[1:0];
    wire [3:0]  mmio_shifted_wstrb;
    wire [31:0] mmio_shifted_wdata;

    assign mmio_shifted_wstrb = (size_r == `AXI_SIZE_1B) ? (4'b0001 << mmio_byte_lane) :
                                (size_r == `AXI_SIZE_2B) ? (4'b0011 << mmio_byte_lane) :
                                4'b1111;

    assign mmio_shifted_wdata = (size_r == `AXI_SIZE_1B) ?
                                ((mmio_byte_lane == 2'b00) ? latch_wdata_r :
                                 (mmio_byte_lane == 2'b01) ? {latch_wdata_r[23:0], 8'b0} :
                                 (mmio_byte_lane == 2'b10) ? {latch_wdata_r[15:0], 16'b0} :
                                                              {latch_wdata_r[7:0], 24'b0}) :
                                latch_wdata_r;

    // =====================================================================
    // FSM
    // =====================================================================
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state                  <= S_IDLE;
            addr_r                 <= 32'b0;
            write_r                <= 1'b0;
            size_r                 <= `AXI_SIZE_4B;
            is_inst_r              <= 1'b0;
            latch_wdata_r          <= 32'b0;
            beat_cnt               <= 3'd0;
            burst_base_addr        <= 32'b0;
            refill_shift_reg       <= 256'b0;
            wb_shift_reg           <= 256'b0;
            ahb_inst_data_r        <= 32'b0;
            ahb_inst_valid_r       <= 1'b0;
            ahb_data_rdata_r       <= 32'b0;
            ahb_data_valid_r       <= 1'b0;
            icache_mmio_accept_r   <= 1'b0;
            dcache_mmio_accept_r   <= 1'b0;
            icache_refill_valid_r  <= 1'b0;
            dcache_refill_valid_r  <= 1'b0;
            dcache_wb_valid_r      <= 1'b0;
            dcache_refill_done_r   <= 1'b0;
            dcache_refill_error_r  <= 1'b0;
            dcache_wb_done_r       <= 1'b0;
            dcache_wb_error_r      <= 1'b0;
            dcache_wb_wait_drop_r  <= 1'b0;
            icache_error_r         <= 1'b0;
            dcache_error_r         <= 1'b0;
            dcache_error_is_store_r <= 1'b0;
            bus_error_addr_r       <= 32'b0;
            wb_starve_cnt_r        <= 3'd0;
            wb_boost_r             <= 1'b0;
            aw_hs_done_r           <= 1'b0;
            w_hs_done_r            <= 1'b0;
            // AXI4 channel defaults
            awvalid  <= 1'b0;
            wvalid   <= 1'b0;
            arvalid  <= 1'b0;
            awaddr   <= 32'b0;
            awlen    <= 8'h00;
            awsize   <= `AXI_SIZE_4B;
            awburst  <= `AXI_BURST_INCR;
            awlock   <= `AXI_LOCK_NORMAL;
            awcache  <= `AXI_CACHE_DEV_NONBUF;
            awprot   <= `AXI_PROT_DATA_PRIV_SECURE;
            araddr   <= 32'b0;
            arlen    <= 8'h00;
            arsize   <= `AXI_SIZE_4B;
            arburst  <= `AXI_BURST_INCR;
            arlock   <= `AXI_LOCK_NORMAL;
            arcache  <= `AXI_CACHE_DEV_NONBUF;
            arprot   <= `AXI_PROT_DATA_PRIV_SECURE;
            wdata    <= 32'b0;
            wstrb    <= 4'b1111;
            wlast    <= 1'b1;
        end else begin
            // Default: clear one-cycle pulses
            ahb_inst_valid_r       <= 1'b0;
            ahb_data_valid_r       <= 1'b0;
            icache_refill_valid_r  <= 1'b0;
            dcache_refill_valid_r  <= 1'b0;
            dcache_wb_valid_r      <= 1'b0;
            dcache_refill_done_r   <= 1'b0;
            dcache_refill_error_r  <= 1'b0;
            dcache_wb_done_r       <= 1'b0;
            dcache_wb_error_r      <= 1'b0;
            if (!dcache_wb_req)
                dcache_wb_wait_drop_r <= 1'b0;
            icache_error_r         <= 1'b0;
            dcache_error_r         <= 1'b0;
            dcache_error_is_store_r <= 1'b0;
            icache_mmio_accept_r   <= 1'b0;
            dcache_mmio_accept_r   <= 1'b0;

            if (state == S_IDLE) begin
                if (dcache_wb_req) begin
                    if ((icache_mmio_req || dcache_mmio_req) && !wb_boost_r) begin
                        if (wb_starve_cnt_r == 3'd3) begin
                            wb_boost_r      <= 1'b1;
                            wb_starve_cnt_r <= 3'd0;
                        end else begin
                            wb_starve_cnt_r <= wb_starve_cnt_r + 3'd1;
                        end
                    end else if (!(icache_mmio_req || dcache_mmio_req)) begin
                        wb_starve_cnt_r <= 3'd0;
                    end
                end else begin
                    wb_starve_cnt_r <= 3'd0;
                    wb_boost_r      <= 1'b0;
                end
            end

            case (state)
                // =====================================================
                // S_IDLE — Arbitrate among request sources
                // Priority: icache_mmio > dcache_mmio > dcache_wb > icache_refill > dcache_refill
                // =====================================================
                S_IDLE: begin
                    awvalid <= 1'b0;
                    wvalid  <= 1'b0;
                    arvalid <= 1'b0;

                    if (dcache_wb_req && wb_boost_r && !dcache_wb_valid_r && !dcache_wb_wait_drop_r) begin
                        state           <= S_WB_AW;
                        addr_r          <= dcache_wb_addr;
                        write_r         <= 1'b1;
                        burst_base_addr <= dcache_wb_addr;
                        beat_cnt        <= 3'd0;
                        wb_shift_reg    <= dcache_wb_data;
                        aw_hs_done_r    <= 1'b0;
                        w_hs_done_r     <= 1'b0;
                        wb_boost_r      <= 1'b0;
                        wb_starve_cnt_r <= 3'd0;
                    end
                    else if (icache_mmio_req && !ahb_inst_valid_r) begin
                        // MMIO instruction read → AR channel
                        state       <= S_MMIO_AR;
                        addr_r      <= icache_mmio_addr;
                        write_r     <= 1'b0;
                        size_r      <= `AXI_SIZE_4B;
                        is_inst_r   <= 1'b1;
                        icache_mmio_accept_r <= 1'b1;
                    end
                    else if (dcache_mmio_req && !ahb_data_valid_r) begin
                        if (dcache_mmio_hwrite) begin
                            // MMIO data write → AW+W channels
                            state         <= S_MMIO_AW_W;
                            addr_r        <= dcache_mmio_addr;
                            write_r       <= 1'b1;
                            size_r        <= dcache_mmio_hsize;
                            is_inst_r     <= 1'b0;
                            latch_wdata_r <= dcache_mmio_wdata;
                            aw_hs_done_r  <= 1'b0;
                            w_hs_done_r   <= 1'b0;
                            dcache_mmio_accept_r <= 1'b1;
                        end else begin
                            // MMIO data read → AR channel
                            state       <= S_MMIO_AR;
                            addr_r      <= dcache_mmio_addr;
                            write_r     <= 1'b0;
                            size_r      <= dcache_mmio_hsize;
                            is_inst_r   <= 1'b0;
                            dcache_mmio_accept_r <= 1'b1;
                        end
                    end
                    else if (dcache_wb_req && !dcache_wb_valid_r && !dcache_wb_wait_drop_r) begin
                        // Writeback burst → AW+W simultaneous (beat 0), then W beats 1-7, then B
                        state           <= S_WB_AW;
                        addr_r          <= dcache_wb_addr;
                        write_r         <= 1'b1;
                        burst_base_addr <= dcache_wb_addr;
                        beat_cnt        <= 3'd0;
                        wb_shift_reg    <= dcache_wb_data;
                        aw_hs_done_r    <= 1'b0;
                        w_hs_done_r     <= 1'b0;
                        wb_boost_r      <= 1'b0;
                        wb_starve_cnt_r <= 3'd0;
                    end
                    else if (icache_refill_req && !icache_refill_valid_r) begin
                        // Icache refill burst → AR then R
                        state           <= S_IREFILL_AR;
                        addr_r          <= icache_refill_addr;
                        write_r         <= 1'b0;
                        burst_base_addr <= icache_refill_addr;
                        beat_cnt        <= 3'd0;
                        refill_shift_reg <= 256'b0;
                    end
                    else if (dcache_refill_req && !dcache_refill_valid_r) begin
                        // Dcache refill burst → AR then R
                        state           <= S_DREFILL_AR;
                        addr_r          <= dcache_refill_addr;
                        write_r         <= 1'b0;
                        burst_base_addr <= dcache_refill_addr;
                        beat_cnt        <= 3'd0;
                        refill_shift_reg <= 256'b0;
                    end
                end

                // =====================================================
                // MMIO Read — AR phase
                // =====================================================
                S_MMIO_AR: begin
                    arvalid  <= 1'b1;
                    araddr   <= addr_r;
                    arlen    <= 8'h00;         // Single beat
                    arsize   <= size_r;
                    arburst  <= `AXI_BURST_INCR;
                    arlock   <= `AXI_LOCK_NORMAL;
                    arcache  <= `AXI_CACHE_DEV_NONBUF;
                    arprot   <= is_inst_r ? `AXI_PROT_INST_PRIV_SECURE : `AXI_PROT_DATA_PRIV_SECURE;

                    if (arready) begin
                        // AR handshake complete
                        state   <= S_MMIO_R;
                    end
                end

                // =====================================================
                // MMIO Read — R phase (single beat)
                // =====================================================
                S_MMIO_R: begin
                    arvalid <= 1'b0;  // AR channel done — clear valid
                    if (rvalid) begin
                        // BUG-86 fix: After a branch redirect, the icache
                        // changes icache_mmio_addr to the NEW PC while the
                        // bus bridge is still completing an AXI read for the
                        // OLD PC (addr_r).  If we propagate the stale
                        // response, the icache returns wrong instruction
                        // data and the CPU crashes.  Detect this by checking
                        // addr_r != icache_mmio_addr for instruction reads.
                        if (is_inst_r && icache_mmio_addr != addr_r) begin
                            // Stale response — discard and restart with
                            // the new address if the request is still active.
                            if (icache_mmio_req) begin
                                addr_r  <= icache_mmio_addr;
                                state   <= S_MMIO_AR;
                            end else begin
                                state   <= S_IDLE;
                            end
                        end else if (r_error) begin
                            state           <= S_IDLE;
                            bus_error_addr_r <= addr_r;
                            if (is_inst_r) begin
                                icache_error_r   <= 1'b1;
                                ahb_inst_valid_r <= 1'b1;
                            end else begin
                                dcache_error_r          <= 1'b1;
                                dcache_error_is_store_r <= 1'b0;
                                ahb_data_valid_r        <= 1'b1;
                            end
                        end else begin
                            state <= S_IDLE;
                            if (is_inst_r) begin
                                ahb_inst_data_r  <= rdata;
                                ahb_inst_valid_r <= 1'b1;
                            end else begin
                                ahb_data_rdata_r <= rdata;
                                ahb_data_valid_r <= 1'b1;
                            end
                        end
                    end
                end

                // =====================================================
                // MMIO Write — AW+W phase (simultaneous, single beat)
                // =====================================================
                S_MMIO_AW_W: begin
                    // Drive AW channel
                    if (!aw_hs_done_r) begin
                        awvalid  <= 1'b1;
                        awaddr   <= addr_r;
                        awlen    <= 8'h00;
                        awsize   <= size_r;
                        awburst  <= `AXI_BURST_INCR;
                        awlock   <= `AXI_LOCK_NORMAL;
                        awcache  <= `AXI_CACHE_DEV_NONBUF;
                        awprot   <= `AXI_PROT_DATA_PRIV_SECURE;
                    end

                    // Drive W channel — use shifted wstrb/wdata for sub-word stores
                    if (!w_hs_done_r) begin
                        wvalid   <= 1'b1;
                        wdata    <= mmio_shifted_wdata;
                        wstrb    <= mmio_shifted_wstrb;
                        wlast    <= 1'b1;
                    end

                    // Track independent handshakes
                    if (arready) begin end  // placeholder — awready/wready below
                    if (awvalid && awready) aw_hs_done_r <= 1'b1;
                    if (wvalid  && wready)  w_hs_done_r  <= 1'b1;

                    // When both complete, move to B phase
                    if ((aw_hs_done_r || (awvalid && awready)) &&
                        (w_hs_done_r  || (wvalid  && wready))) begin
                        awvalid <= 1'b0;
                        wvalid  <= 1'b0;
                        state   <= S_MMIO_B;
                    end
                end

                // =====================================================
                // MMIO Write — B phase (wait for response)
                // =====================================================
                S_MMIO_B: begin
                    if (bvalid) begin
                        if (b_error) begin
                            state           <= S_IDLE;
                            bus_error_addr_r <= addr_r;
                            dcache_error_r          <= 1'b1;
                            dcache_error_is_store_r <= 1'b1;
                            ahb_data_valid_r        <= 1'b1;
                        end else begin
                            state <= S_IDLE;
                            // For MMIO write, data_valid signals completion
                            ahb_data_valid_r <= 1'b1;
                        end
                    end
                end

                // =====================================================
                // Icache Refill — AR phase (burst 8)
                // =====================================================
                S_IREFILL_AR: begin
                    arvalid  <= 1'b1;
                    araddr   <= addr_r;
                    arlen    <= 8'h07;         // 8 beats
                    arsize   <= `AXI_SIZE_4B;
                    arburst  <= `AXI_BURST_INCR;
                    arlock   <= `AXI_LOCK_NORMAL;
                    arcache  <= `AXI_CACHE_NORM_BUF;  // Cacheable
                    arprot   <= `AXI_PROT_INST_PRIV_SECURE;

                    if (arready) begin
                        state   <= S_IREFILL_R;
                    end
                end

                // =====================================================
                // Icache Refill — R phase (8 beats)
                // =====================================================
                S_IREFILL_R: begin
                    arvalid <= 1'b0;  // AR channel done — clear valid
                    if (rvalid) begin
                        if (r_error) begin
                            // Consume remaining beats before returning to S_IDLE
                            // to prevent RAM from getting stuck in R_BURST
                            if (rlast) begin
                                state           <= S_IDLE;
                                icache_error_r  <= 1'b1;
                                bus_error_addr_r <= burst_base_addr;
                            end
                        end else begin
                            refill_shift_reg[beat_cnt*32 +: 32] <= rdata;
                            if (rlast) begin
                                state                  <= S_IDLE;
                                icache_refill_valid_r  <= 1'b1;
                            end else begin
                                beat_cnt <= beat_cnt + 3'd1;
                            end
                        end
                    end
                end

                // =====================================================
                // Dcache Refill — AR phase (burst 8)
                // =====================================================
                S_DREFILL_AR: begin
                    arvalid  <= 1'b1;
                    araddr   <= addr_r;
                    arlen    <= 8'h07;
                    arsize   <= `AXI_SIZE_4B;
                    arburst  <= `AXI_BURST_INCR;
                    arlock   <= `AXI_LOCK_NORMAL;
                    arcache  <= `AXI_CACHE_NORM_BUF;
                    arprot   <= `AXI_PROT_DATA_PRIV_SECURE;

                    if (arready) begin
                        state   <= S_DREFILL_R;
                    end
                end

                // =====================================================
                // Dcache Refill — R phase (8 beats)
                // =====================================================
                S_DREFILL_R: begin
                    arvalid <= 1'b0;  // AR channel done — clear valid
                    if (rvalid) begin
                        if (r_error) begin
                            // Consume remaining beats before returning to S_IDLE
                            // to prevent RAM from getting stuck in R_BURST
                            if (rlast) begin
                                state            <= S_IDLE;
                                dcache_error_r   <= 1'b1;
                                dcache_error_is_store_r <= 1'b0;
                                bus_error_addr_r <= burst_base_addr;
                                dcache_refill_done_r  <= 1'b1;
                                dcache_refill_error_r <= 1'b1;
                            end
                        end else begin
                            refill_shift_reg[beat_cnt*32 +: 32] <= rdata;
                            if (rlast) begin
                                state                  <= S_IDLE;
                                dcache_refill_valid_r  <= 1'b1;
                                dcache_refill_done_r   <= 1'b1;
                                dcache_refill_error_r  <= 1'b0;
                            end else begin
                                beat_cnt <= beat_cnt + 3'd1;
                            end
                        end
                    end
                end

                // =====================================================
                // Dcache Writeback — AW+W phase (beat 0 simultaneous)
                // Per AXI spec A2.3.2: WVALID must NOT wait for AWREADY.
                // Drive AW and W channels independently, track handshakes.
                // =====================================================
                S_WB_AW: begin
                    // Drive AW channel (until handshake completes)
                    if (!aw_hs_done_r) begin
                        awvalid  <= 1'b1;
                        awaddr   <= addr_r;
                        awlen    <= 8'h07;
                        awsize   <= `AXI_SIZE_4B;
                        awburst  <= `AXI_BURST_INCR;
                        awlock   <= `AXI_LOCK_NORMAL;
                        awcache  <= `AXI_CACHE_NORM_BUF;
                        awprot   <= `AXI_PROT_DATA_PRIV_SECURE;
                    end else begin
                        awvalid <= 1'b0;
                    end

                    // Drive W channel — first beat simultaneously with AW
                    if (!w_hs_done_r) begin
                        wvalid   <= 1'b1;
                        wdata    <= wb_shift_reg[31:0];
                        wstrb    <= 4'b1111;
                        wlast    <= 1'b0;  // Not last yet (beat 0 of 8)
                    end else begin
                        wvalid <= 1'b0;  // Clear after first W handshake
                    end

                    // Track independent handshakes
                    if (awvalid && awready) aw_hs_done_r <= 1'b1;
                    if (wvalid  && wready)  w_hs_done_r  <= 1'b1;

                    // When both complete, move to W phase for remaining beats (1-7)
                    if ((aw_hs_done_r || (awvalid && awready)) &&
                        (w_hs_done_r  || (wvalid  && wready))) begin
                        awvalid      <= 1'b0;
                        wvalid       <= 1'b1;  // Immediately drive beat 1
                        beat_cnt     <= 3'd1;
                        wb_shift_reg <= wb_shift_reg >> 32;
                        wdata        <= wb_shift_reg[63:32];
                        wstrb        <= 4'b1111;
                        wlast        <= 1'b0;  // beat 1, not last
                        state        <= S_WB_W;
                    end
                end

                // =====================================================
                // Dcache Writeback — W phase (beats 1-7)
                // =====================================================
                S_WB_W: begin
                    awvalid <= 1'b0;  // AW channel done — clear valid
                    if (wvalid && wready) begin

                        // W handshake for current beat
                        if (wlast) begin
                            // Last beat sent — move to B phase
                            wvalid <= 1'b0;
                            state  <= S_WB_B;
                        end else begin
                            // Advance to next beat
                            beat_cnt    <= beat_cnt + 3'd1;
                            wb_shift_reg <= wb_shift_reg >> 32;
                            wdata       <= wb_shift_reg[63:32];
                            wstrb       <= 4'b1111;
                            wlast       <= (beat_cnt == 3'd6);  // beat 7 is last
                        end
                    end
                end

                // =====================================================
                // Dcache Writeback — B phase
                // =====================================================
                S_WB_B: begin
                    if (bvalid) begin
                        if (b_error) begin
                            state            <= S_IDLE;
                            dcache_error_r   <= 1'b1;
                            dcache_error_is_store_r <= 1'b1;
                            bus_error_addr_r <= burst_base_addr;
                            dcache_wb_done_r  <= 1'b1;
                            dcache_wb_error_r <= 1'b1;
                            dcache_wb_wait_drop_r <= 1'b1;
                        end else begin
                            state            <= S_IDLE;
                            dcache_wb_valid_r <= 1'b1;
                            dcache_wb_done_r  <= 1'b1;
                            dcache_wb_error_r <= 1'b0;
                            dcache_wb_wait_drop_r <= 1'b1;
                        end
                    end
                end

                default: begin
                    state   <= S_IDLE;
                    awvalid <= 1'b0;
                    wvalid  <= 1'b0;
                    arvalid <= 1'b0;
                end
            endcase
        end
    end

    // =====================================================================
    // rready / bready — combinatorial, asserted when expecting responses
    // This is safe: rvalid/bvalid only come after we initiated the transaction
    // =====================================================================
    always_comb begin
        rready = 1'b0;
        bready = 1'b0;

        case (state)
            S_MMIO_R:     rready = 1'b1;
            S_IREFILL_R:  rready = 1'b1;
            S_DREFILL_R:  rready = 1'b1;
            S_MMIO_B:     bready = 1'b1;
            S_WB_B:       bready = 1'b1;
            default:      ;  // both 0
        endcase
    end

endmodule
