`timescale 1ns / 1ps

module ptw(
    input              clk,
    input              resetn,

    input       [31:0] satp,
    input       [1:0]  priv_mode,
    input              mstatus_sum,
    input              mstatus_mxr,
    input       [1:0]  access_type,

    input       [31:0] walk_vaddr,
    input              walk_req,
    input              walk_abort,
    output             walk_idle,
    output             walk_done,
    output             walk_fault,
    output      [3:0]  walk_fault_cause,
    output      [31:0] walk_fault_vaddr,

    output      [21:0] walk_ppn,
    output             walk_r,
    output             walk_w,
    output             walk_x,
    output             walk_u,
    output             walk_a,
    output             walk_d,
    output             walk_g,
    output             walk_is_megapage,

    output             ptw_bus_req,
    output      [31:0] ptw_bus_addr,
    output             ptw_bus_we,
    output      [31:0] ptw_bus_wdata,
    input       [31:0] ptw_bus_rdata,
    input              ptw_bus_done,
    input              ptw_bus_error
);
    localparam [1:0] PRIV_U = 2'b00;
    localparam [1:0] PRIV_S = 2'b01;

    localparam [1:0] ACCESS_FETCH = 2'b00;
    localparam [1:0] ACCESS_LOAD  = 2'b01;
    localparam [1:0] ACCESS_STORE = 2'b10;

    localparam [1:0] FAULT_NONE   = 2'd0;
    localparam [1:0] FAULT_PAGE   = 2'd1;
    localparam [1:0] FAULT_ACCESS = 2'd2;

    localparam [3:0] S_IDLE       = 4'd0;
    localparam [3:0] S_L1_REQUEST = 4'd1;
    localparam [3:0] S_L1_WAIT    = 4'd2;
    localparam [3:0] S_L1_CHECK   = 4'd3;
    localparam [3:0] S_L0_REQUEST = 4'd4;
    localparam [3:0] S_L0_WAIT    = 4'd5;
    localparam [3:0] S_L0_CHECK   = 4'd6;
    localparam [3:0] S_PERM_CHECK = 4'd7;
    localparam [3:0] S_AD_REQUEST = 4'd8;
    localparam [3:0] S_AD_WAIT    = 4'd9;
    localparam [3:0] S_DONE       = 4'd10;
    localparam [3:0] S_FAULT      = 4'd11;

    reg [3:0] state;

    // A walk is a transaction: all architectural inputs are captured once and
    // remain stable until completion or an acknowledged abort.
    reg [31:0] vaddr_r;
    reg [31:0] satp_r;
    reg [1:0]  priv_r;
    reg        sum_r;
    reg        mxr_r;
    reg [1:0]  access_r;

    reg [31:0] pte_r;
    reg [31:0] pte_addr_r;
    reg [31:0] ad_wdata_r;
    reg        is_megapage_r;
    reg [1:0]  fault_kind_r;
    reg        abort_pending_r;

    wire [9:0] vpn1 = vaddr_r[31:22];
    wire [9:0] vpn0 = vaddr_r[21:12];
    wire [21:0] pte_ppn = {pte_r[31:20], pte_r[19:10]};
    wire pte_v = pte_r[0];
    wire pte_r_bit = pte_r[1];
    wire pte_w_bit = pte_r[2];
    wire pte_x_bit = pte_r[3];
    wire pte_u_bit = pte_r[4];
    wire pte_g_bit = pte_r[5];
    wire pte_a_bit = pte_r[6];
    wire pte_d_bit = pte_r[7];
    wire pte_leaf = pte_r_bit || pte_x_bit;
    wire pte_invalid = !pte_v || (!pte_r_bit && pte_w_bit);

    // Sv32 page-table addresses are 34-bit. The current SoC has a 32-bit
    // physical bus, so an unrepresentable address must fault instead of being
    // silently truncated.
    wire [34:0] l1_pte_addr = {1'b0, satp_r[21:0], 12'b0} +
                              {23'b0, vpn1, 2'b0};
    wire [34:0] l0_pte_addr = {1'b0, pte_ppn, 12'b0} +
                              {23'b0, vpn0, 2'b0};

    reg perm_fault;
    always_comb begin
        perm_fault = 1'b0;
        if (priv_r == PRIV_U && !pte_u_bit)
            perm_fault = 1'b1;
        if (priv_r == PRIV_S && pte_u_bit) begin
            if (access_r == ACCESS_FETCH || !sum_r)
                perm_fault = 1'b1;
        end
        if (access_r == ACCESS_FETCH && !pte_x_bit)
            perm_fault = 1'b1;
        if (access_r == ACCESS_LOAD && !pte_r_bit && !(pte_x_bit && mxr_r))
            perm_fault = 1'b1;
        if (access_r == ACCESS_STORE && !pte_w_bit)
            perm_fault = 1'b1;
        if (is_megapage_r && pte_ppn[9:0] != 10'b0)
            perm_fault = 1'b1;
    end

    reg [3:0] fault_cause;
    always_comb begin
        if (fault_kind_r == FAULT_ACCESS) begin
            case (access_r)
                ACCESS_FETCH: fault_cause = 4'd1;
                ACCESS_LOAD:  fault_cause = 4'd5;
                default:      fault_cause = 4'd7;
            endcase
        end else begin
            case (access_r)
                ACCESS_FETCH: fault_cause = 4'd12;
                ACCESS_LOAD:  fault_cause = 4'd13;
                default:      fault_cause = 4'd15;
            endcase
        end
    end

    assign walk_idle = (state == S_IDLE);
    assign walk_done = (state == S_DONE);
    assign walk_fault = (state == S_FAULT);
    assign walk_fault_cause = fault_cause;
    assign walk_fault_vaddr = vaddr_r;

    assign walk_ppn = pte_ppn;
    assign walk_r = pte_r_bit;
    assign walk_w = pte_w_bit;
    assign walk_x = pte_x_bit;
    assign walk_u = pte_u_bit;
    assign walk_a = pte_a_bit;
    assign walk_d = pte_d_bit;
    assign walk_g = pte_g_bit;
    assign walk_is_megapage = is_megapage_r;

    // The request remains asserted for the entire WAIT state. There is no
    // cancellation after issue; an abort is completed only after the response.
    assign ptw_bus_req = (state == S_L1_WAIT) ||
                         (state == S_L0_WAIT) ||
                         (state == S_AD_WAIT);
    assign ptw_bus_addr = pte_addr_r;
    assign ptw_bus_we = (state == S_AD_WAIT);
    assign ptw_bus_wdata = ad_wdata_r;

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state <= S_IDLE;
            vaddr_r <= 32'b0;
            satp_r <= 32'b0;
            priv_r <= 2'b0;
            sum_r <= 1'b0;
            mxr_r <= 1'b0;
            access_r <= ACCESS_FETCH;
            pte_r <= 32'b0;
            pte_addr_r <= 32'b0;
            ad_wdata_r <= 32'b0;
            is_megapage_r <= 1'b0;
            fault_kind_r <= FAULT_NONE;
            abort_pending_r <= 1'b0;
        end else begin
            // Abort immediately when no bus transaction is outstanding. In a
            // WAIT state, remember the abort and drain the issued transaction.
            if (walk_abort && state != S_IDLE &&
                state != S_L1_WAIT && state != S_L0_WAIT && state != S_AD_WAIT) begin
                state <= S_IDLE;
                abort_pending_r <= 1'b0;
            end else begin
                if (walk_abort && (state == S_L1_WAIT || state == S_L0_WAIT || state == S_AD_WAIT))
                    abort_pending_r <= 1'b1;

                case (state)
                    S_IDLE: begin
                        abort_pending_r <= 1'b0;
                        fault_kind_r <= FAULT_NONE;
                        if (walk_req && !walk_abort) begin
                            vaddr_r <= walk_vaddr;
                            satp_r <= satp;
                            priv_r <= priv_mode;
                            sum_r <= mstatus_sum;
                            mxr_r <= mstatus_mxr;
                            access_r <= access_type;
                            is_megapage_r <= 1'b0;
                            state <= S_L1_REQUEST;
                        end
                    end

                    S_L1_REQUEST: begin
                        if (l1_pte_addr[34:32] != 3'b0) begin
                            fault_kind_r <= FAULT_ACCESS;
                            state <= S_FAULT;
                        end else begin
                            pte_addr_r <= l1_pte_addr[31:0];
                            state <= S_L1_WAIT;
                        end
                    end

                    S_L1_WAIT: begin
                        if (ptw_bus_error || ptw_bus_done) begin
                            if (abort_pending_r || walk_abort) begin
                                state <= S_IDLE;
                                abort_pending_r <= 1'b0;
                            end else if (ptw_bus_error) begin
                                fault_kind_r <= FAULT_ACCESS;
                                state <= S_FAULT;
                            end else begin
                                pte_r <= ptw_bus_rdata;
                                state <= S_L1_CHECK;
                            end
                        end
                    end

                    S_L1_CHECK: begin
                        if (pte_invalid) begin
                            fault_kind_r <= FAULT_PAGE;
                            state <= S_FAULT;
                        end else if (pte_leaf) begin
                            is_megapage_r <= 1'b1;
                            state <= S_PERM_CHECK;
                        end else begin
                            state <= S_L0_REQUEST;
                        end
                    end

                    S_L0_REQUEST: begin
                        if (l0_pte_addr[34:32] != 3'b0) begin
                            fault_kind_r <= FAULT_ACCESS;
                            state <= S_FAULT;
                        end else begin
                            pte_addr_r <= l0_pte_addr[31:0];
                            state <= S_L0_WAIT;
                        end
                    end

                    S_L0_WAIT: begin
                        if (ptw_bus_error || ptw_bus_done) begin
                            if (abort_pending_r || walk_abort) begin
                                state <= S_IDLE;
                                abort_pending_r <= 1'b0;
                            end else if (ptw_bus_error) begin
                                fault_kind_r <= FAULT_ACCESS;
                                state <= S_FAULT;
                            end else begin
                                pte_r <= ptw_bus_rdata;
                                state <= S_L0_CHECK;
                            end
                        end
                    end

                    S_L0_CHECK: begin
                        if (pte_invalid || !pte_leaf) begin
                            fault_kind_r <= FAULT_PAGE;
                            state <= S_FAULT;
                        end else begin
                            is_megapage_r <= 1'b0;
                            state <= S_PERM_CHECK;
                        end
                    end

                    S_PERM_CHECK: begin
                        if (perm_fault) begin
                            fault_kind_r <= FAULT_PAGE;
                            state <= S_FAULT;
                        end else if (!pte_a_bit ||
                                     (access_r == ACCESS_STORE && !pte_d_bit)) begin
                            ad_wdata_r <= pte_r | 32'h0000_0040 |
                                         ((access_r == ACCESS_STORE) ? 32'h0000_0080 : 32'b0);
                            state <= S_AD_REQUEST;
                        end else begin
                            state <= S_DONE;
                        end
                    end

                    S_AD_REQUEST: state <= S_AD_WAIT;

                    S_AD_WAIT: begin
                        if (ptw_bus_error || ptw_bus_done) begin
                            if (abort_pending_r || walk_abort) begin
                                state <= S_IDLE;
                                abort_pending_r <= 1'b0;
                            end else if (ptw_bus_error) begin
                                fault_kind_r <= FAULT_ACCESS;
                                state <= S_FAULT;
                            end else begin
                                pte_r <= ad_wdata_r;
                                state <= S_DONE;
                            end
                        end
                    end

                    S_DONE: state <= S_IDLE;
                    S_FAULT: state <= S_IDLE;
                    default: state <= S_IDLE;
                endcase
            end
        end
    end
endmodule
