`timescale 1ns/1ps
`include "core_bus_types.svh"
`include "csr_defs.svh"

module tb_csr_privileged_unit;
    reg clk=0,resetn=0;
    always #5 clk=~clk;

    reg [11:0] sw_csr_addr;
    reg sw_csr_wen;
    reg [31:0] sw_csr_wdata;
    wire [31:0] sw_csr_rdata;
    reg ext_meip,ext_seip,ext_mtip,ext_msip;
    wire [31:0] csr_mstatus,csr_mip,csr_sstatus,csr_sip,csr_satp;
    wire [31:0] csr_mcounteren,csr_scounteren;

    /* verilator lint_off PINMISSING */
    cpu_csr dut(
        .clk(clk),.resetn(resetn),
        .sw_csr_addr(sw_csr_addr),.sw_csr_wen(sw_csr_wen),
        .sw_csr_wdata(sw_csr_wdata),.sw_csr_rdata(sw_csr_rdata),
        .hw_csr_wen(1'b0),.hw_trap_is_enter(1'b0),.hw_status_priv(PRIV_M),
        .hw_mepc_wdata(0),.hw_mcause_wdata(0),.hw_mtval_wdata(0),
        .hw_mstatus_wdata(0),.hw_sepc_wdata(0),.hw_scause_wdata(0),
        .hw_stval_wdata(0),.hw_sstatus_wdata(0),
        .ext_meip(ext_meip),.ext_seip(ext_seip),.ext_mtip(ext_mtip),
        .ext_msip(ext_msip),.ext_mtime(64'b0),
        .cycle_en(1'b0),.inst_retire(1'b0),
        .csr_mstatus(csr_mstatus),.csr_mip(csr_mip),
        .csr_sstatus(csr_sstatus),.csr_sip(csr_sip),.csr_satp(csr_satp),
        .csr_mcounteren(csr_mcounteren),.csr_scounteren(csr_scounteren)
    );
    /* verilator lint_on PINMISSING */

    integer pass_count=0,fail_count=0;
    task check(input condition,input [8*80-1:0] name);begin
        if(condition)begin pass_count=pass_count+1;$display("  PASS %0s",name);end
        else begin fail_count=fail_count+1;$display("  FAIL %0s",name);end
    end endtask

    task csr_write(input [11:0] addr,input [31:0] value);begin
        @(negedge clk);sw_csr_addr=addr;sw_csr_wdata=value;sw_csr_wen=1;
        @(posedge clk);#1;
        @(negedge clk);sw_csr_wen=0;#1;
    end endtask

    initial begin
        sw_csr_addr=0;sw_csr_wen=0;sw_csr_wdata=0;
        ext_meip=0;ext_seip=0;ext_mtip=0;ext_msip=0;
        repeat(3)@(posedge clk);@(negedge clk);resetn=1;

        csr_write(`CSR_MSTATUS,32'hffff_ffff);
        check(csr_mstatus==`CSR_MSTATUS_WRITABLE_MASK,
              "mstatus exposes only implemented integer fields");
        check(csr_mstatus[31]==0&&csr_mstatus[16:13]==0,
              "SD VS XS and FS are fixed zero");

        csr_write(`CSR_MSTATUSH,32'hffff_ffff);
        sw_csr_addr=`CSR_MSTATUSH;#1;
        check(sw_csr_rdata==0,"mstatush accepts writes and remains fixed zero");

        csr_write(`CSR_MSTATUS,32'h0000_1000);
        check(csr_mstatus[12:11]==PRIV_U,
              "reserved MPP encoding legalizes to U");

        csr_write(`CSR_MSTATUS,0);
        csr_write(`CSR_SSTATUS,32'hffff_ffff);
        check(csr_mstatus==`CSR_SSTATUS_WRITABLE_MASK&&
              csr_sstatus==`CSR_SSTATUS_WRITABLE_MASK,
              "sstatus writes only its restricted mstatus view");

        csr_write(`CSR_MCOUNTEREN,32'hffff_ffff);
        csr_write(`CSR_SCOUNTEREN,32'hffff_ffff);
        check(csr_mcounteren==7&&csr_scounteren==7,
              "counter enable CSRs implement only CY TM IR");

        csr_write(`CSR_SATP,32'h7fff_ffff);
        check(csr_satp==0,"Bare satp canonicalizes ASID and PPN to zero");
        csr_write(`CSR_SATP,32'h9234_5678);
        check(csr_satp==32'h9234_5678,"Sv32 satp preserves ASID and PPN");

        csr_write(`CSR_MIDELEG,32'hffff_ffff);
        csr_write(`CSR_MIP,32'h0000_0222);
        ext_meip=1;ext_seip=1;ext_mtip=1;ext_msip=1;#1;
        check(csr_mip==32'h0000_0aaa,
              "mip combines hardware and supervisor software pending sources");
        check(csr_sip==32'h0000_0222,
              "sip is the delegated supervisor pending view");
        csr_write(`CSR_MIP,0);
        check(csr_mip==32'h0000_0a88,
              "mip writes cannot clear hardware pending sources");

        $display("csr privileged unit: pass=%0d fail=%0d",pass_count,fail_count);
        if(fail_count==0)$display("ALL TESTS PASSED");else $display("TEST FAILED");
        $finish;
    end
endmodule
