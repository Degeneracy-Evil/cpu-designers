`timescale 1ns / 1ps

module tb_clint;

    reg clk;
    reg resetn;

    reg  [31:0] awaddr;
    reg  [2:0]  awprot;
    reg         awvalid;
    wire        awready;
    reg  [31:0] wdata;
    reg  [3:0]  wstrb;
    reg         wvalid;
    wire        wready;
    wire [1:0]  bresp;
    wire        bvalid;
    reg         bready;
    reg  [31:0] araddr;
    reg  [2:0]  arprot;
    reg         arvalid;
    wire        arready;
    wire [31:0] rdata;
    wire [1:0]  rresp;
    wire        rvalid;
    reg         rready;
    wire        o_mtip;
    wire        o_msip;
    wire [63:0] o_mtime;
    wire [63:0] o_mtimecmp;

    integer pass_count;
    integer fail_count;

    localparam integer WR_AW_FIRST = 0;
    localparam integer WR_W_FIRST  = 1;
    localparam integer WR_SAME_CYC = 2;

    axi4lite_clint dut (
        .s_axi_aclk    (clk),
        .s_axi_aresetn (resetn),
        .s_axi_awaddr  (awaddr),
        .s_axi_awprot  (awprot),
        .s_axi_awvalid (awvalid),
        .s_axi_awready (awready),
        .s_axi_wdata   (wdata),
        .s_axi_wstrb   (wstrb),
        .s_axi_wvalid  (wvalid),
        .s_axi_wready  (wready),
        .s_axi_bresp   (bresp),
        .s_axi_bvalid  (bvalid),
        .s_axi_bready  (bready),
        .s_axi_araddr  (araddr),
        .s_axi_arprot  (arprot),
        .s_axi_arvalid (arvalid),
        .s_axi_arready (arready),
        .s_axi_rdata   (rdata),
        .s_axi_rresp   (rresp),
        .s_axi_rvalid  (rvalid),
        .s_axi_rready  (rready),
        .o_mtip        (o_mtip),
        .o_msip        (o_msip),
        .o_mtime       (o_mtime),
        .o_mtimecmp    (o_mtimecmp)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task check;
        input [255:0] name;
        input [63:0] actual;
        input [63:0] expected;
        begin
            if (actual === expected) begin
                pass_count = pass_count + 1;
                $display("PASS %0s = 0x%016h", name, actual);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL %0s expected=0x%016h got=0x%016h", name, expected, actual);
            end
        end
    endtask

    task axi_write;
        input [31:0] addr;
        input [31:0] data;
        input [3:0]  strb;
        input integer order_mode;
        reg aw_seen;
        reg w_seen;
        reg aw_started;
        reg w_started;
        begin
            awaddr = addr;
            awprot = 3'b000;
            wdata  = data;
            wstrb  = strb;
            awvalid = 1'b0;
            wvalid  = 1'b0;
            bready  = 1'b0;
            aw_seen = 1'b0;
            w_seen  = 1'b0;
            aw_started = 1'b0;
            w_started  = 1'b0;

            case (order_mode)
                WR_AW_FIRST: begin
                    awvalid = 1'b1;
                    aw_started = 1'b1;
                end
                WR_W_FIRST: begin
                    wvalid = 1'b1;
                    w_started = 1'b1;
                end
                default: begin
                    awvalid = 1'b1;
                    wvalid  = 1'b1;
                    aw_started = 1'b1;
                    w_started  = 1'b1;
                end
            endcase

            while (!aw_seen || !w_seen) begin
                @(posedge clk);
                if (!aw_seen && awvalid && awready) begin
                    aw_seen = 1'b1;
                    awvalid = 1'b0;
                end
                if (!w_seen && wvalid && wready) begin
                    w_seen = 1'b1;
                    wvalid = 1'b0;
                end
                if ((order_mode == WR_AW_FIRST) && aw_seen && !w_started) begin
                    wvalid = 1'b1;
                    w_started = 1'b1;
                end
                if ((order_mode == WR_W_FIRST) && w_seen && !aw_started) begin
                    awvalid = 1'b1;
                    aw_started = 1'b1;
                end
            end

            bready = 1'b1;
            while (!bvalid)
                @(posedge clk);
            @(posedge clk);
            bready = 1'b0;
        end
    endtask

    task axi_read;
        input  [31:0] addr;
        output [31:0] data;
        begin
            araddr = addr;
            arprot = 3'b000;
            arvalid = 1'b1;
            rready = 1'b1;
            while (!arready)
                @(posedge clk);
            @(posedge clk);
            #1;
            arvalid = 1'b0;
            while (!rvalid)
                @(posedge clk);
            #1;
            data = rdata;
            @(posedge clk);
            rready = 1'b0;
        end
    endtask

    initial begin
        reg [31:0] rd_val;
        reg [63:0] mtime_before;

        pass_count = 0;
        fail_count = 0;

        awaddr = 32'd0;
        awprot = 3'd0;
        awvalid = 1'b0;
        wdata = 32'd0;
        wstrb = 4'd0;
        wvalid = 1'b0;
        bready = 1'b0;
        araddr = 32'd0;
        arprot = 3'd0;
        arvalid = 1'b0;
        rready = 1'b0;
        resetn = 1'b0;

        repeat (5) @(posedge clk);
        resetn = 1'b1;
        repeat (2) @(posedge clk);

        check("CLINT mtimecmp reset lo", o_mtimecmp[31:0], 64'hFFFF_FFFF);
        check("CLINT mtimecmp reset hi", o_mtimecmp[63:32], 64'hFFFF_FFFF);
        check("CLINT MTIP low after reset", {63'd0, o_mtip}, 64'd0);

        axi_write(32'h0000_0000, 32'h0000_0001, 4'h1, WR_AW_FIRST);
        axi_read(32'h0000_0000, rd_val);
        check("CLINT msip AW-before-W", rd_val, 64'h1);

        axi_write(32'h0000_4000, 32'h1234_5678, 4'hF, WR_W_FIRST);
        axi_read(32'h0000_4000, rd_val);
        check("CLINT mtimecmp_lo W-before-AW", rd_val, 64'h1234_5678);

        axi_write(32'h0000_4004, 32'h9ABC_DEF0, 4'hF, WR_SAME_CYC);
        axi_read(32'h0000_4004, rd_val);
        check("CLINT mtimecmp_hi same-cycle", rd_val, 64'h9ABC_DEF0);
        check("CLINT combined mtimecmp split contract", o_mtimecmp, 64'h9ABC_DEF0_1234_5678);

        mtime_before = o_mtime;
        axi_write(32'h0000_BFF8, 32'h0000_1000, 4'hF, WR_W_FIRST);
        @(posedge clk);
        if (o_mtime[31:0] >= 32'h0000_1001)
            pass_count = pass_count + 1;
        else begin
            fail_count = fail_count + 1;
            $display("FAIL CLINT mtime write not preserved expected>=0x00001001 got=0x%08h", o_mtime[31:0]);
        end
        if (o_mtime > mtime_before)
            pass_count = pass_count + 1;
        else begin
            fail_count = fail_count + 1;
            $display("FAIL CLINT mtime advanced after write expected>%0d got=%0d", mtime_before, o_mtime);
        end

        axi_write(32'h0000_BFFC, 32'h0000_0001, 4'hF, WR_AW_FIRST);
        axi_read(32'h0000_BFFC, rd_val);
        check("CLINT mtime_hi split write/read", rd_val, 64'h0000_0001);

        axi_write(32'h0000_4000, 32'hFFFF_FFFF, 4'hF, WR_SAME_CYC);
        axi_write(32'h0000_4004, 32'hFFFF_FFFF, 4'hF, WR_AW_FIRST);
        repeat (2) @(posedge clk);
        check("CLINT MTIP deasserts when compare far ahead", {63'd0, o_mtip}, 64'd0);
        check("CLINT MSIP output mirrors register", {63'd0, o_msip}, 64'd1);

        $display("========================================");
        $display("AXI4-Lite CLINT unit summary");
        $display("pass=%0d fail=%0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $fatal(1, "TEST FAILED");
        $display("========================================");
        $finish;
    end

    initial begin
        repeat (1800) @(posedge clk);
        $fatal(1, "TEST FAILED: timeout");
    end
endmodule
