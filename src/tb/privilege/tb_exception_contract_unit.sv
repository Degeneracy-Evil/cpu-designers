`timescale 1ns/1ps
`include "core_bus_types.svh"

module tb_exception_contract_unit;
    reg clk=0,resetn=0;always #5 clk=~clk;
    reg id_valid,id_done,dec_illegal,dec_is_ecall,dec_is_ebreak;
    reg [31:0] id_pc,id_inst;
    reg mem_valid,mem_done,mem_misalign_load,mem_misalign_store;
    reg [31:0] mem_misalign_addr,mem_pc;
    reg trap_enter_valid,trap_return_valid;
    reg priv_mode_t priv_mode;
    reg [31:0] csr_mstatus,csr_mie,csr_mtvec,csr_mepc,csr_mip;
    reg [31:0] csr_medeleg,csr_mideleg,csr_stvec,csr_sepc,current_pc;
    reg exe_misalign_valid;reg [31:0] exe_misalign_target,exe_pc;
    reg inst_access_fault;reg [31:0] inst_access_fault_pc,inst_access_fault_addr;
    reg load_access_fault;reg [31:0] load_access_fault_addr;
    reg store_access_fault;reg [31:0] store_access_fault_addr,mem_access_fault_pc;
    reg inst_page_fault;reg [31:0] inst_page_fault_pc,inst_page_fault_vaddr;
    reg load_page_fault;reg [31:0] load_page_fault_vaddr;
    reg store_page_fault;reg [31:0] store_page_fault_vaddr,mem_page_fault_pc;
    wire exception_at_decode,trap_pending;wire [31:0] trap_pc;
    wire priv_mode_t target_priv,hw_target_priv;
    wire hw_csr_wen,hw_trap_is_enter;
    wire [31:0] hw_mepc_wdata,hw_mcause_wdata,hw_mtval_wdata,hw_mstatus_wdata;
    wire [31:0] hw_sepc_wdata,hw_scause_wdata,hw_stval_wdata,hw_sstatus_wdata;
    wire inst_access_fault_pending,data_access_fault_pending;
    wire inst_page_fault_pending,data_page_fault_pending;

    cpu_trap_manager dut(.*);
    integer pass_count=0,fail_count=0;
    task check(input condition,input [8*76-1:0] name);begin
        if(condition)begin pass_count=pass_count+1;$display("  PASS %0s",name);end
        else begin fail_count=fail_count+1;$display("  FAIL %0s",name);end
    end endtask
    task clear_faults;begin
        inst_access_fault=0;load_access_fault=0;store_access_fault=0;
        inst_page_fault=0;load_page_fault=0;store_page_fault=0;
    end endtask
    task clear_latched;begin
        @(negedge clk);trap_enter_valid=1;
        @(posedge clk);#1;
        @(negedge clk);trap_enter_valid=0;
        repeat(2)@(posedge clk);
    end endtask

    initial begin
        id_valid=0;id_done=0;dec_illegal=0;dec_is_ecall=0;dec_is_ebreak=0;
        id_pc=0;id_inst=0;mem_valid=0;mem_done=0;mem_misalign_load=0;
        mem_misalign_store=0;mem_misalign_addr=0;mem_pc=0;
        trap_enter_valid=0;trap_return_valid=0;priv_mode=PRIV_M;
        csr_mstatus=0;csr_mie=0;csr_mtvec=32'h80001000;csr_mepc=0;csr_mip=0;
        csr_medeleg=0;csr_mideleg=0;csr_stvec=32'h80002000;csr_sepc=0;current_pc=0;
        exe_misalign_valid=0;exe_misalign_target=0;exe_pc=0;
        inst_access_fault_pc=0;inst_access_fault_addr=0;load_access_fault_addr=0;
        store_access_fault_addr=0;mem_access_fault_pc=0;
        inst_page_fault_pc=0;inst_page_fault_vaddr=0;load_page_fault_vaddr=0;
        store_page_fault_vaddr=0;mem_page_fault_pc=0;clear_faults();
        repeat(4)@(posedge clk);@(negedge clk);resetn=1;repeat(2)@(posedge clk);

        @(negedge clk);inst_access_fault=1;
        inst_access_fault_pc=32'h80000120;inst_access_fault_addr=32'h40003124;
        @(posedge clk);#1;@(negedge clk);inst_access_fault=0;
        @(posedge clk);#1;
        check(inst_access_fault_pending&&hw_mcause_wdata==1,
              "instruction access fault uses architectural cause");
        check(hw_mepc_wdata==32'h80000120&&hw_mtval_wdata==32'h40003124,
              "instruction fault keeps instruction PC separate from virtual address");
        clear_latched();

        @(negedge clk);store_access_fault=1;
        store_access_fault_addr=32'h40004008;mem_access_fault_pc=32'h80000200;
        @(posedge clk);#1;@(negedge clk);store_access_fault=0;
        @(posedge clk);#1;
        check(data_access_fault_pending&&hw_mcause_wdata==7,
              "store-class physical failure becomes store access fault");
        check(hw_mepc_wdata==32'h80000200&&hw_mtval_wdata==32'h40004008,
              "data access fault reports instruction PC and effective VA");
        clear_latched();

        @(negedge clk);inst_page_fault=1;
        inst_page_fault_pc=32'h80000300;inst_page_fault_vaddr=32'h50000304;
        @(posedge clk);#1;@(negedge clk);inst_page_fault=0;
        @(posedge clk);#1;
        check(inst_page_fault_pending&&hw_mcause_wdata==12,
              "instruction page fault uses architectural cause");
        check(hw_mepc_wdata==32'h80000300&&hw_mtval_wdata==32'h50000304,
              "page fault descriptor preserves EPC and virtual TVAL");

        $display("exception contract unit: pass=%0d fail=%0d",pass_count,fail_count);
        if(fail_count==0)$display("ALL TESTS PASSED");else $display("TEST FAILED");
        $finish;
    end
    initial begin repeat(1000)@(posedge clk);$display("TEST FAILED: timeout");$finish;end
endmodule
