`timescale 1ns/1ps
`include "core_bus_types.svh"

module tb_stage_exception_unit;
    reg clk=0,resetn=0;always #5 clk=~clk;

    reg id_valid;
    if_id_bus_t if_id_bus_r;
    reg [31:0] rs1_value,rs2_value;
    wire [4:0] rs1_addr,rs2_addr;
    wire id_done,dec_need_exe,dec_is_csr;
    wire dec_is_mret,dec_is_sret,dec_is_nop_like,dec_is_fencei,dec_is_sfence_vma;
    id_exe_bus_t id_exe_bus;
    wire [31:0] id_pc,id_inst;
    exception_t decode_exception;
    priv_mode_t priv_mode;
    reg [31:0] csr_mstatus,csr_mcounteren,csr_scounteren;

    reg exe_valid;
    id_exe_bus_t execute_bus_r;
    wire exe_done,exe_branch_taken,exe_is_ctrl_flow,exe_is_branch,exe_need_mem;
    wire [31:0] exe_branch_target,exe_pc,exe_inst;
    exe_mem_bus_t exe_mem_bus;
    exception_t exe_exception;

    cpu_decode u_decode(
        .id_valid(id_valid),.if_id_bus_r(if_id_bus_r),
        .rs1_value(rs1_value),.rs2_value(rs2_value),
        .rs1_addr(rs1_addr),.rs2_addr(rs2_addr),.id_done(id_done),
        .decode_exception(decode_exception),.dec_need_exe(dec_need_exe),
        .id_exe_bus(id_exe_bus),
        .id_pc(id_pc),.id_inst(id_inst),.dec_is_csr(dec_is_csr),
        .dec_is_mret(dec_is_mret),.dec_is_sret(dec_is_sret),
        .dec_is_nop_like(dec_is_nop_like),.dec_is_fencei(dec_is_fencei),
        .dec_is_sfence_vma(dec_is_sfence_vma),.priv_mode(priv_mode),
        .csr_mstatus(csr_mstatus),.csr_mcounteren(csr_mcounteren),
        .csr_scounteren(csr_scounteren)
    );

    cpu_execute u_execute(
        .clk(clk),.resetn(resetn),.exe_valid(exe_valid),
        .id_exe_bus_r(execute_bus_r),.exe_done(exe_done),
        .exe_mem_bus(exe_mem_bus),.exe_branch_taken(exe_branch_taken),
        .exe_branch_target(exe_branch_target),.exe_is_ctrl_flow(exe_is_ctrl_flow),
        .exe_is_branch(exe_is_branch),.exe_need_mem(exe_need_mem),
        .exe_pc(exe_pc),.exe_inst(exe_inst),.exe_exception(exe_exception),
        .dbg_mu_active(),.dbg_mu_req_valid(),.dbg_mu_ready(),.dbg_mu_busy(),
        .dbg_mu_result_valid(),.dbg_mu_funct3(),.dbg_exe_is_mu()
    );

    integer pass_count=0,fail_count=0;
    task check(input condition,input [8*80-1:0] name);begin
        if(condition)begin pass_count=pass_count+1;$display("  PASS %0s",name);end
        else begin fail_count=fail_count+1;$display("  FAIL %0s",name);end
    end endtask

    task set_decode(input [31:0] instruction,input priv_mode_t mode);begin
        if_id_bus_r.pc=32'h80000100;
        if_id_bus_r.pc_plus4=32'h80000104;
        if_id_bus_r.inst=instruction;
        priv_mode=mode;id_valid=1;#1;
    end endtask

    initial begin
        id_valid=0;if_id_bus_r='0;rs1_value=0;rs2_value=0;
        priv_mode=PRIV_M;csr_mstatus=0;csr_mcounteren=0;csr_scounteren=0;
        exe_valid=0;execute_bus_r='0;
        repeat(4)@(posedge clk);@(negedge clk);resetn=1;

        set_decode(32'hffff_ffff,PRIV_M);
        check(decode_exception.valid&&!id_done&&decode_exception.cause==2,
              "illegal instruction faults instead of completing Decode");
        check(decode_exception.epc==32'h80000100&&decode_exception.tval==32'hffff_ffff,
              "illegal instruction reports PC and instruction bits");

        set_decode(32'h0000_0073,PRIV_U);
        check(decode_exception.valid&&decode_exception.cause==8&&!id_done,
              "U-mode ECALL produces cause 8 without Decode completion");
        set_decode(32'h0000_0073,PRIV_S);
        check(decode_exception.cause==9,"S-mode ECALL produces cause 9");
        set_decode(32'h0000_0073,PRIV_M);
        check(decode_exception.cause==11,"M-mode ECALL produces cause 11");
        set_decode(32'h0010_0073,PRIV_M);
        check(decode_exception.cause==3&&decode_exception.tval==0,
              "EBREAK produces cause 3 with zero TVAL");
        set_decode(32'h0000_0013,PRIV_M);
        check(id_done&&!decode_exception.valid,"legal ADDI completes Decode normally");
        id_valid=0;

        execute_bus_r='0;
        execute_bus_r.pc=32'h80000200;
        execute_bus_r.pc_plus4=32'h80000204;
        execute_bus_r.inst=32'h0020006f;
        execute_bus_r.alu_control=16'b0001_0000_0000_0000;
        execute_bus_r.alu_src1=32'h80000200;
        execute_bus_r.alu_src2=32'd2;
        execute_bus_r.is_jal_like=1;
        execute_bus_r.wb_we=1;
        @(negedge clk);exe_valid=1;
        @(posedge clk);#1;
        check(exe_exception.valid&&!exe_done&&exe_exception.cause==0,
              "misaligned control-flow target faults instead of completing Execute");
        check(exe_exception.epc==32'h80000200&&exe_exception.tval==32'h80000202,
              "Execute exception reports instruction PC and bad target");

        $display("stage exception unit: pass=%0d fail=%0d",pass_count,fail_count);
        if(fail_count==0)$display("ALL TESTS PASSED");else $display("TEST FAILED");
        $finish;
    end
    initial begin repeat(1000)@(posedge clk);$display("TEST FAILED: timeout");$finish;end
endmodule
