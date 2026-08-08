`timescale 1ns / 1ps

module tb_cpu_bus_bridge_unit;
    reg clk = 1'b0;
    reg resetn = 1'b0;
    always #5 clk = ~clk;

    reg icache_mmio_req;
    wire icache_mmio_accept;
    reg [31:0] icache_mmio_addr;
    reg dcache_mmio_req;
    wire dcache_mmio_accept;
    reg [31:0] dcache_mmio_addr;
    reg [31:0] dcache_mmio_wdata;
    reg dcache_mmio_hwrite;
    reg [2:0] dcache_mmio_hsize;
    wire [31:0] ahb_inst_data;
    wire ahb_inst_valid;
    wire [31:0] ahb_data_rdata;
    wire ahb_data_valid;
    reg icache_refill_req;
    reg [31:0] icache_refill_addr;
    wire [255:0] icache_refill_data;
    wire icache_refill_valid;
    wire icache_refill_done;
    wire icache_refill_error;
    reg dcache_refill_req;
    reg [31:0] dcache_refill_addr;
    wire [255:0] dcache_refill_data;
    wire dcache_refill_valid;
    wire dcache_refill_done;
    wire dcache_refill_error;
    reg ptw_req;
    reg [31:0] ptw_addr;
    reg ptw_we;
    reg [31:0] ptw_wdata;
    wire [31:0] ptw_rdata;
    wire ptw_done;
    wire ptw_error;

    wire [3:0] awid;
    wire [31:0] awaddr;
    wire [7:0] awlen;
    wire [2:0] awsize;
    wire [1:0] awburst;
    wire awlock;
    wire [3:0] awcache;
    wire [2:0] awprot;
    wire [3:0] awqos;
    wire [3:0] awregion;
    wire awvalid;
    reg awready;
    wire [31:0] wdata;
    wire [3:0] wstrb;
    wire wlast;
    wire wvalid;
    reg wready;
    reg [1:0] bresp;
    reg bvalid;
    wire bready;
    wire [3:0] arid;
    wire [31:0] araddr;
    wire [7:0] arlen;
    wire [2:0] arsize;
    wire [1:0] arburst;
    wire arlock;
    wire [3:0] arcache;
    wire [2:0] arprot;
    wire [3:0] arqos;
    wire [3:0] arregion;
    wire arvalid;
    reg arready;
    reg [31:0] rdata;
    reg [1:0] rresp;
    reg rlast;
    reg rvalid;
    wire rready;
    wire icache_error;
    wire dcache_error;
    wire dcache_error_is_store;
    wire [31:0] bus_error_addr;

    cpu_bus_bridge dut (
        .clk(clk), .resetn(resetn),
        .icache_mmio_req(icache_mmio_req),
        .icache_mmio_accept(icache_mmio_accept),
        .icache_mmio_addr(icache_mmio_addr),
        .dcache_mmio_req(dcache_mmio_req),
        .dcache_mmio_accept(dcache_mmio_accept),
        .dcache_mmio_addr(dcache_mmio_addr),
        .dcache_mmio_wdata(dcache_mmio_wdata),
        .dcache_mmio_hwrite(dcache_mmio_hwrite),
        .dcache_mmio_hsize(dcache_mmio_hsize),
        .ahb_inst_data(ahb_inst_data), .ahb_inst_valid(ahb_inst_valid),
        .ahb_data_rdata(ahb_data_rdata), .ahb_data_valid(ahb_data_valid),
        .icache_refill_req(icache_refill_req),
        .icache_refill_addr(icache_refill_addr),
        .icache_refill_data(icache_refill_data),
        .icache_refill_valid(icache_refill_valid),
        .icache_refill_done(icache_refill_done),
        .icache_refill_error(icache_refill_error),
        .dcache_refill_req(dcache_refill_req),
        .dcache_refill_addr(dcache_refill_addr),
        .dcache_refill_data(dcache_refill_data),
        .dcache_refill_valid(dcache_refill_valid),
        .dcache_refill_done(dcache_refill_done),
        .dcache_refill_error(dcache_refill_error),
        .ptw_req(ptw_req), .ptw_addr(ptw_addr), .ptw_we(ptw_we),
        .ptw_wdata(ptw_wdata), .ptw_rdata(ptw_rdata),
        .ptw_done(ptw_done), .ptw_error(ptw_error),
        .awid(awid), .awaddr(awaddr), .awlen(awlen), .awsize(awsize),
        .awburst(awburst), .awlock(awlock), .awcache(awcache),
        .awprot(awprot), .awqos(awqos), .awregion(awregion),
        .awvalid(awvalid), .awready(awready),
        .wdata(wdata), .wstrb(wstrb), .wlast(wlast),
        .wvalid(wvalid), .wready(wready),
        .bresp(bresp), .bvalid(bvalid), .bready(bready),
        .arid(arid), .araddr(araddr), .arlen(arlen), .arsize(arsize),
        .arburst(arburst), .arlock(arlock), .arcache(arcache),
        .arprot(arprot), .arqos(arqos), .arregion(arregion),
        .arvalid(arvalid), .arready(arready),
        .rdata(rdata), .rresp(rresp), .rlast(rlast),
        .rvalid(rvalid), .rready(rready),
        .icache_error(icache_error), .dcache_error(dcache_error),
        .dcache_error_is_store(dcache_error_is_store),
        .bus_error_addr(bus_error_addr)
    );

    integer cycle_count;
    integer pass_count;
    integer fail_count;
    integer read_delay;
    integer read_gap;
    reg read_active;
    reg [31:0] read_addr_r;
    reg [7:0] read_len_r;
    reg [7:0] read_beat_r;
    integer write_resp_delay;
    reg aw_seen;
    reg wlast_seen;
    reg [31:0] captured_awaddr;
    reg [31:0] captured_wdata;
    reg [3:0] captured_wstrb;

    function [31:0] read_value;
        input [31:0] base;
        input [7:0] beat;
        begin
            read_value = (base + {beat, 2'b00}) ^ 32'hA5A5_5A5A;
        end
    endfunction

    // Deliberately slow AXI slave: address acceptance, every read beat, write
    // channels and write response all have independent wait cycles.
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            cycle_count <= 0;
            arready <= 1'b0;
            rvalid <= 1'b0;
            rlast <= 1'b0;
            rdata <= 32'b0;
            rresp <= 2'b00;
            read_active <= 1'b0;
            read_addr_r <= 32'b0;
            read_len_r <= 8'b0;
            read_beat_r <= 8'b0;
            read_delay <= 3;
            read_gap <= 0;
            awready <= 1'b0;
            wready <= 1'b0;
            bvalid <= 1'b0;
            bresp <= 2'b00;
            write_resp_delay <= 0;
            aw_seen <= 1'b0;
            wlast_seen <= 1'b0;
            captured_awaddr <= 32'b0;
            captured_wdata <= 32'b0;
            captured_wstrb <= 4'b0;
        end else begin
            cycle_count <= cycle_count + 1;
            arready <= !read_active && !rvalid && ((cycle_count & 3) == 3);
            awready <= !aw_seen && ((cycle_count & 3) == 1);
            wready <= !wlast_seen && ((cycle_count & 1) == 1);

            if (arvalid && arready) begin
                read_active <= 1'b1;
                read_addr_r <= araddr;
                read_len_r <= arlen;
                read_beat_r <= 0;
                read_delay <= 4;
                arready <= 1'b0;
            end

            if (read_active && !rvalid) begin
                if (read_delay != 0)
                    read_delay <= read_delay - 1;
                else if (read_gap != 0)
                    read_gap <= read_gap - 1;
                else begin
                    rdata <= read_value(read_addr_r, read_beat_r);
                    rresp <= 2'b00;
                    rlast <= (read_beat_r == read_len_r);
                    rvalid <= 1'b1;
                end
            end

            if (rvalid && rready) begin
                rvalid <= 1'b0;
                if (rlast) begin
                    rlast <= 1'b0;
                    read_active <= 1'b0;
                    read_delay <= 3;
                end else begin
                    read_beat_r <= read_beat_r + 1'b1;
                    read_gap <= 2;
                end
            end

            if (awvalid && awready) begin
                aw_seen <= 1'b1;
                captured_awaddr <= awaddr;
                awready <= 1'b0;
            end
            if (wvalid && wready) begin
                captured_wdata <= wdata;
                captured_wstrb <= wstrb;
                if (wlast)
                    wlast_seen <= 1'b1;
            end
            if (aw_seen && wlast_seen && !bvalid) begin
                if (write_resp_delay < 5)
                    write_resp_delay <= write_resp_delay + 1;
                else begin
                    bvalid <= 1'b1;
                    bresp <= 2'b00;
                end
            end
            if (bvalid && bready) begin
                bvalid <= 1'b0;
                aw_seen <= 1'b0;
                wlast_seen <= 1'b0;
                write_resp_delay <= 0;
            end
        end
    end

    task check;
        input condition;
        input [8*72-1:0] name;
        begin
            if (condition) begin
                pass_count = pass_count + 1;
                $display("  PASS %0s", name);
            end else begin
                fail_count = fail_count + 1;
                $display("  FAIL %0s", name);
            end
        end
    endtask

    integer i;
    reg [255:0] expected_line;
    reg wrong_client_seen;
    initial begin
        icache_mmio_req = 0;
        icache_mmio_addr = 0;
        dcache_mmio_req = 0;
        dcache_mmio_addr = 0;
        dcache_mmio_wdata = 0;
        dcache_mmio_hwrite = 0;
        dcache_mmio_hsize = 3'b010;
        icache_refill_req = 0;
        icache_refill_addr = 0;
        dcache_refill_req = 0;
        dcache_refill_addr = 0;
        ptw_req = 0;
        ptw_addr = 0;
        ptw_we = 0;
        ptw_wdata = 0;
        pass_count = 0;
        fail_count = 0;
        expected_line = 0;
        wrong_client_seen = 0;

        repeat (4) @(posedge clk);
        resetn = 1'b1;
        repeat (2) @(posedge clk);

        // I-MMIO owns the response even if the live request address changes.
        icache_mmio_addr = 32'hFC00_0020;
        icache_mmio_req = 1'b1;
        while (!icache_mmio_accept) @(posedge clk);
        @(posedge clk);
        icache_mmio_req = 1'b0;
        icache_mmio_addr = 32'hFC00_0040;
        while (!ahb_inst_valid) begin
            @(posedge clk);
            #1;
        end
        check(ahb_inst_data == read_value(32'hFC00_0020, 0),
              "I-MMIO response uses latched address/client");

        // PTW and D-refill arrive together. PTW has priority, and the held PTW
        // level must not be accepted twice before its source drops req.
        ptw_addr = 32'h8000_3000;
        ptw_req = 1'b1;
        dcache_refill_addr = 32'h8000_4000;
        dcache_refill_req = 1'b1;
        while (!ptw_done) begin
            @(posedge clk);
            #1;
            if (dcache_refill_valid)
                wrong_client_seen = 1'b1;
        end
        check(!wrong_client_seen, "lower-priority client receives no PTW response");
        check(ptw_rdata == read_value(32'h8000_3000, 0),
              "PTW receives its own delayed response");
        @(posedge clk);
        ptw_req = 1'b0;

        for (i = 0; i < 8; i = i + 1)
            expected_line[i*32 +: 32] = read_value(32'h8000_4000, i);
        while (!dcache_refill_valid) begin
            @(posedge clk);
            #1;
        end
        check(dcache_refill_done && dcache_refill_data == expected_line,
              "D-refill burst survives per-beat response gaps");
        @(posedge clk);
        dcache_refill_req = 1'b0;

        // Byte write checks latched write metadata and independent AW/W waits.
        dcache_mmio_addr = 32'h1000_0003;
        dcache_mmio_wdata = 32'h0000_00C7;
        dcache_mmio_hwrite = 1'b1;
        dcache_mmio_hsize = 3'b000;
        dcache_mmio_req = 1'b1;
        while (!dcache_mmio_accept) @(posedge clk);
        @(posedge clk);
        dcache_mmio_req = 1'b0;
        while (!ahb_data_valid) begin
            @(posedge clk);
            #1;
        end
        check(captured_awaddr == 32'h1000_0003 &&
              captured_wstrb == 4'b1000 && captured_wdata == 32'hC700_0000,
              "D-MMIO byte write keeps address/data/strobe through AXI waits");

        repeat (8) @(posedge clk);
        check(!ahb_inst_valid && !ahb_data_valid && !ptw_done &&
              !dcache_refill_valid,
              "all response pulses are single-cycle and client-specific");

        $display("cpu_bus_bridge unit: pass=%0d fail=%0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED");
        $finish;
    end

    initial begin
        repeat (4000) @(posedge clk);
        $display("TEST FAILED: timeout");
        $finish;
    end
endmodule
