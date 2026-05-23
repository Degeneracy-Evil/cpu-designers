`timescale 1ns / 1ps

module MMU #(
    parameter TLB_ENTRIES = 16
)(
    input              clk,
    input              reset,

    input       [31:0] vaddr,
    input       [1:0]  access_type,
    input       [1:0]  priv_mode,
    input       [31:0] satp,
    input              mstatus_sum,
    input              mstatus_mxr,
    input              translate_en,    // 0 = bare mode (no translation/faults)

    output      [31:0] paddr,
    output             miss,
    output             page_fault,
    output      [3:0]  page_fault_cause,
    output      [31:0] page_fault_vaddr,

    input              ptw_done,
    input              ptw_fault,

    input              sfence_vma,

    output             ptw_bus_req,
    output      [31:0] ptw_bus_addr,
    output             ptw_bus_we,
    output      [31:0] ptw_bus_wdata,
    input       [31:0] ptw_bus_rdata,
    input              ptw_bus_done,
    input              ptw_bus_error
);

    localparam PRIV_M = 2'b11;

    localparam ACCESS_FETCH = 2'b00;
    localparam ACCESS_LOAD  = 2'b01;
    localparam ACCESS_STORE = 2'b10;

    wire sv32_enabled = satp[31] && (priv_mode != PRIV_M) && translate_en;
    wire [19:0] vpn   = vaddr[31:12];
    wire [8:0]  asid  = satp[30:22];

    wire        tlb_hit;
    wire [21:0] tlb_ppn;
    wire        tlb_r, tlb_w, tlb_x, tlb_u;
    wire        tlb_a, tlb_d, tlb_g;
    wire        tlb_is_megapage;

    wire [21:0] ptw_fill_ppn;
    wire        ptw_fill_r, ptw_fill_w, ptw_fill_x, ptw_fill_u;
    wire        ptw_fill_a, ptw_fill_d, ptw_fill_g;
    wire        ptw_fill_is_megapage;
    wire [19:0] ptw_fill_vpn;
    wire [8:0]  ptw_fill_asid;

    wire [3:0]  ptw_fault_cause_out;
    wire [31:0] ptw_fault_vaddr_out;

    assign ptw_fill_vpn  = vaddr[31:12];
    assign ptw_fill_asid = satp[30:22];

    tlb #(.ENTRIES(TLB_ENTRIES)) u_tlb(
        .clk(clk),
        .reset(reset),
        .lookup_vpn(vpn),
        .lookup_asid(asid),
        .lookup_req(1'b1),
        .lookup_hit(tlb_hit),
        .lookup_ppn(tlb_ppn),
        .lookup_r(tlb_r),
        .lookup_w(tlb_w),
        .lookup_x(tlb_x),
        .lookup_u(tlb_u),
        .lookup_a(tlb_a),
        .lookup_d(tlb_d),
        .lookup_g(tlb_g),
        .lookup_is_megapage(tlb_is_megapage),
        .fill_req(ptw_done),
        .fill_vpn(ptw_fill_vpn),
        .fill_asid(ptw_fill_asid),
        .fill_ppn(ptw_fill_ppn),
        .fill_r(ptw_fill_r),
        .fill_w(ptw_fill_w),
        .fill_x(ptw_fill_x),
        .fill_u(ptw_fill_u),
        .fill_a(ptw_fill_a),
        .fill_d(ptw_fill_d),
        .fill_g(ptw_fill_g),
        .fill_is_megapage(ptw_fill_is_megapage),
        .flush_all(sfence_vma)
    );

    reg tlb_perm_fault;
    always @(*) begin
        tlb_perm_fault = 1'b0;
        if (priv_mode == 2'b00 && !tlb_u)
            tlb_perm_fault = 1'b1;
        if (priv_mode == 2'b01 && tlb_u) begin
            if (access_type == ACCESS_FETCH)
                tlb_perm_fault = 1'b1;
            else if (!mstatus_sum)
                tlb_perm_fault = 1'b1;
        end
        if (access_type == ACCESS_FETCH && !tlb_x)
            tlb_perm_fault = 1'b1;
        if (access_type == ACCESS_LOAD) begin
            if (!tlb_r && !(tlb_x && mstatus_mxr))
                tlb_perm_fault = 1'b1;
        end
        if (access_type == ACCESS_STORE && !tlb_w)
            tlb_perm_fault = 1'b1;
    end

    wire [33:0] translated_paddr;
    assign translated_paddr = tlb_is_megapage ?
        {tlb_ppn[21:10], vaddr[21:0]} :
        {tlb_ppn, vaddr[11:0]};

    wire translation_ok = sv32_enabled && tlb_hit && !tlb_perm_fault;
    wire tlb_miss       = sv32_enabled && !tlb_hit;
    wire tlb_pf         = sv32_enabled && tlb_hit && tlb_perm_fault;

    assign paddr = !sv32_enabled ? vaddr :
                   translation_ok ? translated_paddr[31:0] : vaddr;

    reg walk_active_r;
    always @(posedge clk or posedge reset) begin
        if (reset)
            walk_active_r <= 1'b0;
        else if (sfence_vma)
            walk_active_r <= 1'b0;
        else if (tlb_miss && !walk_active_r)
            walk_active_r <= 1'b1;
        else if (ptw_done || ptw_fault)
            walk_active_r <= 1'b0;
    end

    assign miss = tlb_miss && !walk_active_r;

    reg pf_r;
    reg [3:0] pf_cause_r;
    reg [31:0] pf_vaddr_r;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            pf_r <= 1'b0;
            pf_cause_r <= 4'b0;
            pf_vaddr_r <= 32'b0;
        end else begin
            pf_r <= 1'b0;
            if (tlb_pf && !walk_active_r) begin
                pf_r <= 1'b1;
                pf_vaddr_r <= vaddr;
                case (access_type)
                    ACCESS_FETCH: pf_cause_r <= 4'd12;
                    ACCESS_LOAD:  pf_cause_r <= 4'd13;
                    default:      pf_cause_r <= 4'd15;
                endcase
            end else if (ptw_fault && walk_active_r) begin
                pf_r <= 1'b1;
            end
        end
    end

    assign page_fault       = pf_r;
    assign page_fault_cause = pf_r ? (ptw_fault ? ptw_fault_cause_out : pf_cause_r) : 4'b0;
    assign page_fault_vaddr = pf_r ? (ptw_fault ? ptw_fault_vaddr_out : pf_vaddr_r) : 32'b0;

    ptw u_ptw(
        .clk(clk),
        .reset(reset),
        .satp(satp),
        .priv_mode(priv_mode),
        .mstatus_sum(mstatus_sum),
        .mstatus_mxr(mstatus_mxr),
        .access_type(access_type),
        .walk_vaddr(vaddr),
        .walk_req(tlb_miss && !walk_active_r),
        .walk_done(ptw_done),
        .walk_fault(ptw_fault),
        .walk_fault_cause(ptw_fault_cause_out),
        .walk_fault_vaddr(ptw_fault_vaddr_out),
        .walk_ppn(ptw_fill_ppn),
        .walk_r(ptw_fill_r),
        .walk_w(ptw_fill_w),
        .walk_x(ptw_fill_x),
        .walk_u(ptw_fill_u),
        .walk_a(ptw_fill_a),
        .walk_d(ptw_fill_d),
        .walk_g(ptw_fill_g),
        .walk_is_megapage(ptw_fill_is_megapage),
        .ptw_bus_req(ptw_bus_req),
        .ptw_bus_addr(ptw_bus_addr),
        .ptw_bus_we(ptw_bus_we),
        .ptw_bus_wdata(ptw_bus_wdata),
        .ptw_bus_rdata(ptw_bus_rdata),
        .ptw_bus_done(ptw_bus_done),
        .ptw_bus_error(ptw_bus_error)
    );

endmodule
