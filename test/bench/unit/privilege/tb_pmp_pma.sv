`timescale 1ns/1ps
`include "common/bus/axi.svh"
`include "core/interface/types.svh"
`include "common/address_map.svh"

module tb_pmp_pma;
    reg [31:0] paddr;
    reg [2:0] access_size;
    access_class_t access_type;
    priv_mode_t effective_priv;
    reg [127:0] pmpcfg_flat;
    reg [511:0] pmpaddr_flat;
    wire pmp_allow;
    reg is_atomic, is_ptw;
    wire pma_allow;

    pmp_checker u_pmp(
        .paddr(paddr),
        .access_size(access_size),
        .access_type(access_type),
        .effective_priv(effective_priv),
        .pmpcfg_flat(pmpcfg_flat),
        .pmpaddr_flat(pmpaddr_flat),
        .allow(pmp_allow)
    );
    pma_checker u_pma(
        .paddr(paddr),
        .access_type(access_type),
        .access_size(access_size),
        .is_atomic(is_atomic),
        .is_ptw(is_ptw),
        .allow(pma_allow)
    );

    reg clk=0, resetn=0;
    always #5 clk=~clk;
    reg [11:0] sw_csr_addr;
    reg sw_csr_wen;
    reg [31:0] sw_csr_wdata;
    wire [31:0] sw_csr_rdata;
    wire [127:0] csr_pmpcfg_flat;
    wire [511:0] csr_pmpaddr_flat;

    /* verilator lint_off PINMISSING */
    cpu_csr u_csr(
        .clk(clk),
        .resetn(resetn),
        .sw_csr_addr(sw_csr_addr),
        .sw_csr_wen(sw_csr_wen),
        .sw_csr_wdata(sw_csr_wdata),
        .sw_csr_funct3(3'b001),
        .sw_csr_operand(sw_csr_wdata),
        .sw_csr_rdata(sw_csr_rdata),
        .hw_csr_wen(1'b0),
        .hw_trap_is_enter(1'b0),
        .hw_status_priv(PRIV_M),
        .hw_mepc_wdata(32'b0),
        .hw_mcause_wdata(32'b0),
        .hw_mtval_wdata(32'b0),
        .hw_mstatus_wdata(32'b0),
        .hw_sepc_wdata(32'b0),
        .hw_scause_wdata(32'b0),
        .hw_stval_wdata(32'b0),
        .hw_sstatus_wdata(32'b0),
        .ext_meip(1'b0),
        .ext_seip(1'b0),
        .ext_mtip(1'b0),
        .ext_msip(1'b0),
        .ext_mtime(64'b0),
        .cycle_en(1'b0),
        .inst_retire(1'b0),
        .pmpcfg_flat(csr_pmpcfg_flat),
        .pmpaddr_flat(csr_pmpaddr_flat)
    );
    /* verilator lint_on PINMISSING */

    integer pass_count=0, fail_count=0;
    task check(input condition,input [8*80-1:0] name); begin
        if(condition)begin pass_count=pass_count+1;$display("  PASS %0s",name);end
        else begin fail_count=fail_count+1;$display("  FAIL %0s",name);end
    end endtask

    task csr_write(input [11:0] addr,input [31:0] value); begin
        @(negedge clk);sw_csr_addr=addr;sw_csr_wdata=value;sw_csr_wen=1;
        @(posedge clk);#1;
        @(negedge clk);sw_csr_wen=0;
    end endtask

    task clear_pmp; begin
        pmpcfg_flat='0;pmpaddr_flat='0;
    end endtask

    initial begin
        paddr=0;access_size=`AXI_SIZE_WORD;access_type=ACCESS_LOAD;
        effective_priv=PRIV_S;pmpcfg_flat='0;pmpaddr_flat='0;
        is_atomic=0;is_ptw=0;
        sw_csr_addr=0;sw_csr_wen=0;sw_csr_wdata=0;

        #1;
        check(effective_data_priv(PRIV_M,1'b1,PRIV_U)==PRIV_U &&
              effective_data_priv(PRIV_M,1'b0,PRIV_U)==PRIV_M &&
              effective_data_priv(PRIV_S,1'b1,PRIV_U)==PRIV_S,
              "data effective privilege applies MPRV only in M-mode");
        check(!pmp_allow,"S-mode no-match defaults to deny");
        effective_priv=PRIV_M;#1;
        check(pmp_allow,"M-mode no-match defaults to allow");

        // Entry 0: 8-byte NAPOT region at 0x80001000, read/write for S/U.
        clear_pmp();
        pmpaddr_flat[31:0]=(32'h80001000>>2);
        pmpcfg_flat[7:0]=8'h1b;
        paddr=32'h80001004;effective_priv=PRIV_U;access_type=ACCESS_LOAD;#1;
        check(pmp_allow,"NAPOT permits a fully covered load");
        access_type=ACCESS_FETCH;#1;
        check(!pmp_allow,"PMP permission denies execute without X");
        paddr=32'h80001008;access_type=ACCESS_LOAD;#1;
        check(!pmp_allow,"S/U access beyond NAPOT region has no match");
        clear_pmp();
        pmpaddr_flat[31:0]=32'hffff_ffff;
        pmpcfg_flat[7:0]=8'h1f;
        paddr=32'hfc001000;access_size=`AXI_SIZE_WORD;
        access_type=ACCESS_FETCH;#1;
        check(pmp_allow,"all-ones NAPOT entry covers the complete 32-bit PA space");

        // Lower-priority broad region must not override entry 0 partial overlap.
        clear_pmp();
        pmpaddr_flat[31:0]=(32'h80001000>>2);
        pmpcfg_flat[7:0]=8'h13; // NA4, RW
        pmpaddr_flat[63:32]=(32'h80001000>>2)|32'h000001ff;
        pmpcfg_flat[15:8]=8'h1b; // 4 KiB NAPOT, RW
        paddr=32'h80000ffe;access_size=`AXI_SIZE_WORD;
        access_type=ACCESS_LOAD;effective_priv=PRIV_S;#1;
        check(!pmp_allow,"first partial-overlap entry denies the complete access");
        paddr=32'h80001000;access_type=ACCESS_STORE;
        pmpcfg_flat[7:0]=8'h19;#1; // entry 0 is read-only
        check(!pmp_allow,"lower-numbered full match has permission priority");

        // Unlocked rules do not constrain M; locked rules do.
        clear_pmp();
        pmpaddr_flat[31:0]=(32'h80001000>>2);
        pmpcfg_flat[7:0]=8'h99; // locked NAPOT, read only
        paddr=32'h80001000;effective_priv=PRIV_M;access_type=ACCESS_STORE;#1;
        check(!pmp_allow,"locked PMP rule restricts M-mode");
        access_type=ACCESS_LOAD;#1;
        check(pmp_allow,"locked PMP rule grants its declared M-mode permission");
        pmpcfg_flat[7:0]=8'h19;access_type=ACCESS_STORE;#1;
        check(pmp_allow,"unlocked matching rule is bypassed by M-mode");

        // TOR and NA4 address modes.
        clear_pmp();
        pmpaddr_flat[31:0]=(32'h00001000>>2);
        pmpcfg_flat[7:0]=8'h09;
        paddr=32'h00000ffc;effective_priv=PRIV_S;access_type=ACCESS_LOAD;#1;
        check(pmp_allow,"TOR upper endpoint is exclusive and full range matches");
        paddr=32'h00001000;#1;
        check(!pmp_allow,"TOR does not include its upper endpoint");
        clear_pmp();
        pmpaddr_flat[31:0]=(32'h80001000>>2);
        pmpaddr_flat[63:32]=(32'h80002000>>2);
        pmpcfg_flat[15:8]=8'h09;
        paddr=32'h80001000;#1;
        check(pmp_allow,"TOR entry uses the previous pmpaddr as lower bound");
        paddr=32'h80000ffc;#1;
        check(!pmp_allow,"TOR excludes addresses below its predecessor bound");
        clear_pmp();
        pmpaddr_flat[31:0]=(32'h80002000>>2);
        pmpcfg_flat[7:0]=8'h13;paddr=32'h80002000;#1;
        check(pmp_allow,"NA4 covers exactly one physical word");

        // Fixed PMA map and full-range checks.
        paddr=`SOC_DDR_BASE;access_size=`AXI_SIZE_WORD;access_type=ACCESS_FETCH;
        is_atomic=0;is_ptw=0;#1;check(pma_allow,"DDR is executable");
        access_type=ACCESS_STORE;is_atomic=1;#1;check(pma_allow,"DDR supports word atomics");
        is_atomic=0;is_ptw=1;#1;check(pma_allow,"DDR supports PTW writes");
        paddr=`SOC_BOOTROM_BASE;access_type=ACCESS_FETCH;is_ptw=0;#1;
        check(pma_allow,"BootROM is executable");
        access_type=ACCESS_STORE;#1;check(!pma_allow,"BootROM is read-only");
        paddr=`SOC_CLINT_BASE;access_type=ACCESS_LOAD;#1;check(pma_allow,"CLINT is readable");
        access_type=ACCESS_FETCH;#1;check(!pma_allow,"MMIO is not executable");
        access_type=ACCESS_STORE;is_atomic=1;#1;check(!pma_allow,"MMIO rejects atomics");
        is_atomic=0;is_ptw=1;#1;check(!pma_allow,"MMIO rejects PTW accesses");
        is_ptw=0;paddr=`SOC_SYSSTATUS_BASE;access_type=ACCESS_STORE;#1;
        check(!pma_allow,"SysStatus is read-only");
        paddr=32'h10004000;access_type=ACCESS_LOAD;#1;
        check(!pma_allow,"unimplemented APB timer slot is unmapped");
        paddr=`SOC_BOOTROM_BASE+`SOC_BOOTROM_SIZE-2;access_size=`AXI_SIZE_WORD;#1;
        check(!pma_allow,"access crossing a PMA region boundary is denied");

        // CSR WARL: reserved bits clear and R=0/W=1 is sanitized.
        repeat(3)@(posedge clk);@(negedge clk);resetn=1;
        csr_write(12'h3a0,32'h00001aff);
        check(csr_pmpcfg_flat[7:0]==8'h9f,
              "pmpcfg preserves modes while clearing reserved bits");
        check(csr_pmpcfg_flat[15:8]==8'h18,
              "pmpcfg clears W for the reserved R=0/W=1 combination");
        csr_write(12'h3a0,32'h00000000);
        check(csr_pmpcfg_flat[7:0]==8'h9f,
              "locked pmpcfg byte preserves its old value");

        // Reset, then prove a locked TOR entry locks its predecessor address.
        @(negedge clk);resetn=0;repeat(2)@(posedge clk);@(negedge clk);resetn=1;
        csr_write(12'h3b0,32'h11111111);
        csr_write(12'h3b1,32'h22222222);
        csr_write(12'h3a0,32'h00008900); // entry 1: L=1, TOR, R=1
        csr_write(12'h3b0,32'haaaaaaaa);
        csr_write(12'h3b1,32'hbbbbbbbb);
        check(csr_pmpaddr_flat[31:0]==32'h11111111,
              "locked TOR entry locks its predecessor pmpaddr");
        check(csr_pmpaddr_flat[63:32]==32'h22222222,
              "locked PMP entry locks its own pmpaddr");

        $display("PMP/PMA unit: pass=%0d fail=%0d",pass_count,fail_count);
        if(fail_count==0)$display("ALL TESTS PASSED");else $fatal(1, "TEST FAILED");
        $finish;
    end

    initial begin
        repeat (1800) @(posedge clk);
        $fatal(1, "TEST FAILED: timeout");
    end
endmodule
