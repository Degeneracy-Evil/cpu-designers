`timescale 1ns / 1ps

module tb_axi4lite_plic_unit;

    localparam integer NUM_SRC = 8;
    localparam integer NUM_CTX = 2;

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
    reg  [NUM_SRC-1:0] src_irq;
    wire [NUM_CTX-1:0] o_eip;

    integer pass_count;
    integer fail_count;

    localparam integer WR_AW_FIRST = 0;
    localparam integer WR_W_FIRST  = 1;
    localparam integer WR_SAME_CYC = 2;

    axi4lite_plic #(
        .NUM_SRC(NUM_SRC),
        .NUM_CTX(NUM_CTX)
    ) dut (
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
        .src_irq       (src_irq),
        .o_eip         (o_eip)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task check;
        input [255:0] name;
        input [31:0] actual;
        input [31:0] expected;
        begin
            if (actual === expected) begin
                pass_count = pass_count + 1;
                $display("PASS %0s = 0x%08h", name, actual);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL %0s expected=0x%08h got=0x%08h", name, expected, actual);
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
                    aw_seen  = 1'b1;
                    awvalid  = 1'b0;
                end
                if (!w_seen && wvalid && wready) begin
                    w_seen   = 1'b1;
                    wvalid   = 1'b0;
                end
                if ((order_mode == WR_AW_FIRST) && aw_seen && !w_started) begin
                    wvalid    = 1'b1;
                    w_started = 1'b1;
                end
                if ((order_mode == WR_W_FIRST) && w_seen && !aw_started) begin
                    awvalid    = 1'b1;
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
            araddr  = addr;
            arprot  = 3'b000;
            arvalid = 1'b1;
            rready  = 1'b1;
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
        src_irq = '0;
        resetn = 1'b0;

        repeat (5) @(posedge clk);
        resetn = 1'b1;
        repeat (2) @(posedge clk);

        axi_write(32'h0000_0000, 32'd7, 4'hF, WR_SAME_CYC);
        axi_read(32'h0000_0000, rd_val);
        check("PLIC source zero priority is reserved", rd_val, 32'd0);

        axi_write(32'h0000_000C, 32'd7, 4'hF, WR_AW_FIRST);
        axi_write(32'h0000_0014, 32'd7, 4'hF, WR_W_FIRST);
        axi_write(32'h0C00_2000, 32'h0000_0028, 4'hF, WR_SAME_CYC);
        axi_write(32'h0C20_0000, 32'd0, 4'hF, WR_AW_FIRST);

        src_irq[3] = 1'b1;
        src_irq[5] = 1'b1;
        repeat (2) @(posedge clk);

        check("PLIC ctx0 EIP after equal-priority pend", {31'd0, o_eip[0]}, 32'd1);

        axi_read(32'h0C20_0004, rd_val);
        check("PLIC equal-priority claim prefers lower ID", rd_val, 32'd3);

        axi_read(32'h0C20_0004, rd_val);
        check("PLIC second claim returns remaining higher ID", rd_val, 32'd5);

        src_irq[3] = 1'b0;
        src_irq[5] = 1'b0;
        repeat (2) @(posedge clk);

        src_irq[3] = 1'b1;
        repeat (2) @(posedge clk);
        check("PLIC source deassertion does not rearm gateway", {31'd0, o_eip[0]}, 32'd0);
        axi_write(32'h0C20_0004, 32'd3, 4'hF, WR_SAME_CYC);
        repeat (2) @(posedge clk);
        check("PLIC completion rearms asserted source", {31'd0, o_eip[0]}, 32'd1);
        axi_read(32'h0C20_0004, rd_val);
        check("PLIC rearmed source can be claimed again", rd_val, 32'd3);
        src_irq[3] = 1'b0;
        axi_write(32'h0C20_0004, 32'd3, 4'hF, WR_SAME_CYC);
        axi_write(32'h0C20_0004, 32'd5, 4'hF, WR_SAME_CYC);
        repeat (2) @(posedge clk);

        axi_write(32'h0000_0008, 32'd3, 4'hF, WR_SAME_CYC);
        axi_write(32'h0000_0010, 32'd4, 4'hF, WR_AW_FIRST);
        axi_write(32'h0C00_2000, 32'h0000_0004, 4'hF, WR_W_FIRST);
        axi_write(32'h0C00_2080, 32'h0000_0010, 4'hF, WR_AW_FIRST);
        axi_write(32'h0C20_1000, 32'd3, 4'hF, WR_W_FIRST);

        src_irq[2] = 1'b1;
        src_irq[4] = 1'b1;
        repeat (2) @(posedge clk);

        check("PLIC ctx0 EIP independent enable", {31'd0, o_eip[0]}, 32'd1);
        check("PLIC ctx1 EIP threshold pass", {31'd0, o_eip[1]}, 32'd1);

        axi_read(32'h0C20_0004, rd_val);
        check("PLIC ctx0 claim uses ctx0 selector", rd_val, 32'd2);

        axi_read(32'h0C20_1004, rd_val);
        check("PLIC ctx1 claim uses ctx1 selector", rd_val, 32'd4);

        axi_write(32'h0C20_1000, 32'd4, 4'hF, WR_SAME_CYC);
        src_irq[4] = 1'b0;
        repeat (2) @(posedge clk);
        src_irq[4] = 1'b1;
        repeat (2) @(posedge clk);
        check("PLIC ctx1 threshold blocks equal priority", {31'd0, o_eip[1]}, 32'd0);

        $display("========================================");
        $display("AXI4-Lite PLIC unit summary");
        $display("pass=%0d fail=%0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED");
        $display("========================================");
        $finish;
    end

endmodule
