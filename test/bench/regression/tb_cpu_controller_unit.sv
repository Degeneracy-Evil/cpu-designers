`timescale 1ns / 1ps
`include "core/interface/types.svh"

module tb_cpu_controller_unit;
    localparam [3:0] S_IDLE=0, S_FETCH=1, S_DECODE=2, S_EXEC=3,
                     S_MEM=4, S_WB=5, S_CSR=6, S_TRAP=7,
                     S_RETURN=8, S_FENCEI=9, S_SFENCE=10,
                     S_RETURN_BOUNDARY=11;

    reg clk = 1'b0;
    reg resetn = 1'b0;
    always #5 clk = ~clk;

    reg if_done, id_done, exe_done, mem_done, wb_done;
    reg dec_need_exe, dec_is_csr, dec_is_mret, dec_is_sret;
    reg dec_is_nop_like, dec_is_fencei, dec_is_sfence_vma;
    reg exe_is_branch, exe_need_mem;
    reg sync_exception_pending, interrupt_pending;
    reg init_sig, fencei_done, sfence_vma_done;
    wire if_valid, id_valid, exe_valid, mem_valid, wb_valid, csr_valid;
    wire trap_enter_valid, trap_return_valid, exe_to_wb;
    trap_return_kind_t trap_return_kind;
    wire fencei_req, sfence_vma_req;
    wire [3:0] state;

    cpu_controller dut(.*);

    integer pass_count = 0;
    integer fail_count = 0;

    task check(input condition, input [8*72-1:0] name);
        begin
            if (condition) begin
                pass_count = pass_count + 1;
                $display("  PASS %0s", name);
            end else begin
                fail_count = fail_count + 1;
                $display("  FAIL %0s (state=%0d)", name, state);
            end
        end
    endtask

    task clear_inputs;
        begin
            if_done=0; id_done=0; exe_done=0; mem_done=0; wb_done=0;
            dec_need_exe=0; dec_is_csr=0; dec_is_mret=0; dec_is_sret=0;
            dec_is_nop_like=0; dec_is_fencei=0; dec_is_sfence_vma=0;
            exe_is_branch=0; exe_need_mem=0;
            sync_exception_pending=0; interrupt_pending=0;
            init_sig=0; fencei_done=0; sfence_vma_done=0;
        end
    endtask

    task restart;
        begin
            @(negedge clk); resetn=0; clear_inputs();
            repeat(2) @(posedge clk);
            @(negedge clk); resetn=1;
            @(posedge clk); #1;
            check(state==S_FETCH && if_valid, "reset enters FETCH");
        end
    endtask

    task fetch_to_decode;
        begin
            @(negedge clk); if_done=1;
            @(posedge clk); #1; if_done=0;
            check(state==S_DECODE && id_valid, "fetch completion enters DECODE");
        end
    endtask

    task decode_to_exec;
        begin
            @(negedge clk); id_done=1; dec_need_exe=1;
            @(posedge clk); #1; id_done=0; dec_need_exe=0;
            check(state==S_EXEC && exe_valid, "ordinary decode enters EXEC");
        end
    endtask

    initial begin
        clear_inputs();

        restart();
        repeat(3) @(posedge clk); #1;
        check(state==S_FETCH, "FETCH stalls solely while if_done is low");
        fetch_to_decode(); decode_to_exec();
        @(negedge clk); exe_done=1;
        @(posedge clk); #1; exe_done=0;
        check(state==S_WB && wb_valid, "normal ALU instruction enters WB");
        @(negedge clk); wb_done=1;
        @(posedge clk); #1; wb_done=0;
        check(state==S_FETCH, "normal instruction retires to FETCH");

        restart(); fetch_to_decode(); decode_to_exec();
        @(negedge clk); exe_done=1; exe_is_branch=1;
        @(posedge clk); #1; exe_done=0; exe_is_branch=0;
        check(state==S_FETCH, "completed branch returns to FETCH");

        restart(); fetch_to_decode(); decode_to_exec();
        @(negedge clk); exe_done=1; exe_need_mem=1;
        @(posedge clk); #1; exe_done=0; exe_need_mem=0;
        check(state==S_MEM && mem_valid, "load/store enters MEM");
        repeat(3) @(posedge clk); #1;
        check(state==S_MEM, "MEM stalls solely while mem_done is low");
        @(negedge clk); mem_done=1;
        @(posedge clk); #1; mem_done=0;
        check(state==S_WB, "memory completion enters WB");

        restart(); fetch_to_decode();
        @(negedge clk); id_done=1; dec_is_csr=1;
        @(posedge clk); #1; id_done=0; dec_is_csr=0;
        check(state==S_CSR && csr_valid, "CSR instruction enters CSR_ACCESS");
        @(posedge clk); #1;
        check(state==S_WB, "CSR_ACCESS advances to WB");

        restart(); fetch_to_decode();
        @(negedge clk); sync_exception_pending=1;
        @(posedge clk); #1; sync_exception_pending=0;
        check(state==S_TRAP && trap_enter_valid, "illegal/ecall/ebreak aggregate enters trap");

        restart(); fetch_to_decode();
        @(negedge clk); id_done=1; dec_is_mret=1;
        @(posedge clk); #1; id_done=0; dec_is_mret=0;
        check(state==S_RETURN && trap_return_valid && trap_return_kind==RET_M,
              "mret enters TRAP_RETURN with explicit kind");
        @(posedge clk); #1;
        check(state==S_RETURN_BOUNDARY && !trap_return_valid &&
              !if_valid && !id_valid && !exe_valid && !mem_valid &&
              !wb_valid && !csr_valid && !trap_enter_valid,
              "return boundary issues no functional request");
        @(posedge clk); #1;
        check(state==S_FETCH,"return boundary fetches when no interrupt is pending");

        restart(); fetch_to_decode();
        @(negedge clk); id_done=1; dec_is_sret=1;
        @(posedge clk); #1; id_done=0; dec_is_sret=0;
        check(state==S_RETURN && trap_return_kind==RET_S,
              "sret enters TRAP_RETURN with explicit kind");
        @(negedge clk); interrupt_pending=1;
        @(posedge clk); #1;
        check(state==S_RETURN_BOUNDARY && !trap_return_valid,
              "sret reaches explicit return boundary");
        @(posedge clk); #1; interrupt_pending=0;
        check(state==S_TRAP && trap_enter_valid,
              "return boundary immediately accepts a pending interrupt");

        restart();
        @(negedge clk); sync_exception_pending=1;
        @(posedge clk); #1; sync_exception_pending=0;
        check(state==S_TRAP, "instruction access/page fault enters trap");
        restart(); fetch_to_decode(); decode_to_exec();
        @(negedge clk); exe_done=1; exe_need_mem=1;
        @(posedge clk); #1; exe_done=0; exe_need_mem=0;
        @(negedge clk); sync_exception_pending=1;
        @(posedge clk); #1; sync_exception_pending=0;
        check(state==S_TRAP, "load/store access/page fault enters trap");

        restart(); fetch_to_decode(); decode_to_exec();
        @(negedge clk); exe_done=1; interrupt_pending=1;
        @(posedge clk); #1; exe_done=0;
        check(state==S_WB, "interrupt does not cancel an executing instruction");
        @(negedge clk); wb_done=1;
        @(posedge clk); #1; wb_done=0; interrupt_pending=0;
        check(state==S_TRAP, "interrupt is taken after retirement");

        restart(); fetch_to_decode();
        @(negedge clk); id_done=1; dec_is_nop_like=1; interrupt_pending=1;
        @(posedge clk); #1; id_done=0; dec_is_nop_like=0; interrupt_pending=0;
        check(state==S_TRAP, "decode-only completion accepts pending interrupt");

        restart(); fetch_to_decode();
        @(negedge clk); id_done=1; dec_is_fencei=1;
        @(posedge clk); #1; id_done=0; dec_is_fencei=0;
        check(state==S_FENCEI && fencei_req, "FENCE.I holds invalidate request");
        repeat(3) @(posedge clk); #1;
        check(state==S_FENCEI && fencei_req, "FENCE.I waits for completion");
        @(negedge clk); fencei_done=1;
        @(posedge clk); #1; fencei_done=0;
        check(state==S_FETCH && !fencei_req, "FENCE.I completion returns to FETCH");

        restart(); fetch_to_decode();
        @(negedge clk); id_done=1; dec_is_fencei=1;
        @(posedge clk); #1; id_done=0; dec_is_fencei=0;
        @(negedge clk); fencei_done=1; interrupt_pending=1;
        @(posedge clk); #1; fencei_done=0; interrupt_pending=0;
        check(state==S_TRAP, "FENCE.I completion accepts pending interrupt");

        restart(); fetch_to_decode();
        @(negedge clk); id_done=1; dec_is_sfence_vma=1;
        @(posedge clk); #1; id_done=0; dec_is_sfence_vma=0;
        check(state==S_SFENCE && sfence_vma_req, "SFENCE.VMA holds flush request");
        repeat(3) @(posedge clk); #1;
        check(state==S_SFENCE && sfence_vma_req, "SFENCE.VMA waits for completion");
        @(negedge clk); sfence_vma_done=1;
        @(posedge clk); #1; sfence_vma_done=0;
        check(state==S_FETCH && !sfence_vma_req, "SFENCE.VMA completion returns to FETCH");

        restart(); fetch_to_decode();
        @(negedge clk); id_done=1; dec_is_sfence_vma=1;
        @(posedge clk); #1; id_done=0; dec_is_sfence_vma=0;
        @(negedge clk); sfence_vma_done=1; interrupt_pending=1;
        @(posedge clk); #1; sfence_vma_done=0; interrupt_pending=0;
        check(state==S_TRAP, "SFENCE.VMA completion accepts pending interrupt");

        $display("cpu_controller unit: pass=%0d fail=%0d", pass_count, fail_count);
        if (fail_count==0) $display("ALL TESTS PASSED");
        else $display("TEST FAILED");
        $finish;
    end

    initial begin
        repeat(2000) @(posedge clk);
        $display("TEST FAILED: timeout");
        $finish;
    end
endmodule
