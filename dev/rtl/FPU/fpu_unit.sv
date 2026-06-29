`timescale 1ns / 1ps

module fpu_unit(
    input         clk,
    input         resetn,
    input  [6:0]  fpu_funct,    // FPU operation select
    input  [2:0]  fpu_rm,       // rounding mode (from instruction or CSR)
    input  [31:0] src1, src2,   // FPU operands (from float register file)
    input  [31:0] src3,         // FPU operand rs3 (for FMA instructions)
    input         req_valid,
    input         flush,
    input         result_got,
    output [31:0] result,       // FPU result
    output        fpu_busy,
    output        fpu_ready,
    output        result_valid,
    output [4:0]  fflags,       // {NV, DZ, OF, UF, NX}
    output        rd_is_int,    // 1 = result writes integer register
    output        fpu_error     // 1 = timeout/error, result is invalid
  );

  // ===================================================================
  // Operation encoding
  // ===================================================================
  localparam [6:0] FPU_FADD      = 7'd0;
  localparam [6:0] FPU_FSUB      = 7'd1;
  localparam [6:0] FPU_FMUL      = 7'd2;
  localparam [6:0] FPU_FDIV      = 7'd3;
  localparam [6:0] FPU_FSQRT     = 7'd4;
  localparam [6:0] FPU_FMIN      = 7'd5;
  localparam [6:0] FPU_FMAX      = 7'd6;
  localparam [6:0] FPU_FSGNJ     = 7'd7;
  localparam [6:0] FPU_FSGNJN    = 7'd8;
  localparam [6:0] FPU_FSGNJX    = 7'd9;
  localparam [6:0] FPU_FEQ       = 7'd10;
  localparam [6:0] FPU_FLT       = 7'd11;
  localparam [6:0] FPU_FLE       = 7'd12;
  localparam [6:0] FPU_FCLASS    = 7'd13;
  localparam [6:0] FPU_FMV_X_W   = 7'd14;
  localparam [6:0] FPU_FMV_W_X   = 7'd15;
  localparam [6:0] FPU_FCVT_W_S  = 7'd16;
  localparam [6:0] FPU_FCVT_WU_S = 7'd17;
  localparam [6:0] FPU_FCVT_S_W  = 7'd18;
  localparam [6:0] FPU_FCVT_S_WU = 7'd19;
  localparam [6:0] FPU_FMADD     = 7'd20;
  localparam [6:0] FPU_FMSUB     = 7'd21;
  localparam [6:0] FPU_FNMSUB    = 7'd22;
  localparam [6:0] FPU_FNMADD    = 7'd23;

  // D extension operations (double-precision)
  localparam [6:0] FPU_FADD_D      = 7'd24;
  localparam [6:0] FPU_FSUB_D      = 7'd25;
  localparam [6:0] FPU_FMUL_D      = 7'd26;
  localparam [6:0] FPU_FDIV_D      = 7'd27;
  localparam [6:0] FPU_FSQRT_D     = 7'd28;
  localparam [6:0] FPU_FMIN_D      = 7'd29;
  localparam [6:0] FPU_FMAX_D      = 7'd30;
  localparam [6:0] FPU_FSGNJ_D     = 7'd31;
  localparam [6:0] FPU_FSGNJN_D    = 7'd32;
  localparam [6:0] FPU_FSGNJX_D    = 7'd33;
  localparam [6:0] FPU_FEQ_D       = 7'd34;
  localparam [6:0] FPU_FLT_D       = 7'd35;
  localparam [6:0] FPU_FLE_D       = 7'd36;
  localparam [6:0] FPU_FCLASS_D    = 7'd37;
  localparam [6:0] FPU_FCVT_W_D    = 7'd38;
  localparam [6:0] FPU_FCVT_WU_D   = 7'd39;
  localparam [6:0] FPU_FCVT_D_W    = 7'd40;
  localparam [6:0] FPU_FCVT_D_WU   = 7'd41;
  localparam [6:0] FPU_FCVT_S_D    = 7'd42;
  localparam [6:0] FPU_FCVT_D_S    = 7'd43;
  localparam [6:0] FPU_FLD         = 7'd44;
  localparam [6:0] FPU_FSD         = 7'd45;

  // ===================================================================
  // FSM state register (MMU-style explicit state enum)
  // ===================================================================
  localparam F_IDLE     = 3'd0;
  localparam F_DISPATCH = 3'd1;
  localparam F_WAIT     = 3'd2;
  localparam F_DONE     = 3'd3;
  localparam F_COMPLETE = 3'd4;

  reg [2:0] f_state;

  // ===================================================================
  // Timeout watchdog (F_WAIT state)
  //   div/sqrt iterations take many cycles; threshold=1000 is safe margin.
  //   On timeout: force completion with fpu_error=1 (invalid result).
  // ===================================================================
  reg [9:0] timeout_cnt;
  localparam [9:0] TIMEOUT_MAX = 10'd1000;
  reg fpu_error_reg;

  // ===================================================================
  // Handshake registers
  // ===================================================================
  reg adder_start;
  reg mul_start;
  reg div_start;
  reg sqrt_start;
  reg cvt_start;
  reg fma_start;
  reg result_valid_reg;
  reg [31:0] result_hold_reg;
  reg [4:0]  fflags_reg;
  reg        rd_is_int_reg;
  reg [6:0]  fpu_funct_reg;
  reg [2:0]  fpu_rm_reg;
  reg [31:0] src1_reg;
  reg [31:0] src2_reg;
  reg [31:0] src3_reg;

  // ===================================================================
  // Handshake logic
  //   fpu_ready: high ONLY in F_IDLE (prevents reentrancy)
  //   fpu_busy:  high during active processing (not in IDLE/COMPLETE)
  // ===================================================================
  assign fpu_busy  = (f_state != F_IDLE) && (f_state != F_COMPLETE);
  assign fpu_ready = (f_state == F_IDLE);

  // ===================================================================
  // Category wires from latched fpu_funct_reg
  // ===================================================================
  wire is_comb_op = (fpu_funct_reg == FPU_FMIN)    || (fpu_funct_reg == FPU_FMAX) ||
                    (fpu_funct_reg == FPU_FSGNJ)   || (fpu_funct_reg == FPU_FSGNJN) ||
                    (fpu_funct_reg == FPU_FSGNJX)  ||
                    (fpu_funct_reg == FPU_FEQ)     || (fpu_funct_reg == FPU_FLT) ||
                    (fpu_funct_reg == FPU_FLE)     ||
                    (fpu_funct_reg == FPU_FCLASS)  ||
                    (fpu_funct_reg == FPU_FMV_X_W) || (fpu_funct_reg == FPU_FMV_W_X);

  wire is_rd_int = (fpu_funct_reg == FPU_FEQ)       ||
                   (fpu_funct_reg == FPU_FLT)       ||
                   (fpu_funct_reg == FPU_FLE)       ||
                   (fpu_funct_reg == FPU_FCLASS)    ||
                   (fpu_funct_reg == FPU_FMV_X_W)   ||
                   (fpu_funct_reg == FPU_FCVT_W_S)  ||
                   (fpu_funct_reg == FPU_FCVT_WU_S);

  // ===================================================================
  // Sub-module funct encoding from latched fpu_funct_reg
  // ===================================================================
  wire [2:0] cmp_funct_r;
  assign cmp_funct_r = (fpu_funct_reg == FPU_FEQ) ? 3'b010 :
                       (fpu_funct_reg == FPU_FLT) ? 3'b000 :
                       /* FPU_FLE */                3'b001;

  wire [2:0] sgnj_funct_r;
  assign sgnj_funct_r = (fpu_funct_reg == FPU_FSGNJ)  ? 3'b000 :
                        (fpu_funct_reg == FPU_FSGNJN) ? 3'b001 :
                        /* FPU_FSGNJX */                3'b010;

  wire [2:0] cvt_funct_r;
  assign cvt_funct_r = (fpu_funct_reg == FPU_FCVT_W_S)  ? 3'd0 :
                       (fpu_funct_reg == FPU_FCVT_WU_S) ? 3'd1 :
                       (fpu_funct_reg == FPU_FCVT_S_W)  ? 3'd2 :
                       /* FPU_FCVT_S_WU */                3'd3;

  // ===================================================================
  // Sequential sub-module instances (use latched src1_reg/src2_reg)
  // ===================================================================
  wire [31:0] adder_result;
  wire [4:0]  adder_fflags;
  wire        adder_done;

  fpu_adder u_adder(
      .clk(clk),
      .resetn(resetn),
      .src1(src1_reg),
      .src2(src2_reg),
      .is_sub((fpu_funct_reg == FPU_FSUB)),
      .rm(fpu_rm_reg),
      .start(adder_start),
      .flush(flush),
      .result(adder_result),
      .fflags(adder_fflags),
      .done(adder_done)
  );

  wire [31:0] mul_result;
  wire [4:0]  mul_fflags;
  wire        mul_done;

  fpu_multiplier u_mul(
      .clk(clk),
      .resetn(resetn),
      .src1(src1_reg),
      .src2(src2_reg),
      .rm(fpu_rm_reg),
      .start(mul_start),
      .flush(flush),
      .result(mul_result),
      .fflags(mul_fflags),
      .done(mul_done)
  );

  wire [31:0] div_result;
  wire [4:0]  div_fflags;
  wire        div_done;

  fpu_divider u_div(
      .clk(clk),
      .resetn(resetn),
      .src1(src1_reg),
      .src2(src2_reg),
      .rm(fpu_rm_reg),
      .start(div_start),
      .flush(flush),
      .result(div_result),
      .fflags(div_fflags),
      .done(div_done)
  );

  wire [31:0] sqrt_result;
  wire [4:0]  sqrt_fflags;
  wire        sqrt_done;

  fpu_sqrt u_sqrt(
      .clk(clk),
      .resetn(resetn),
      .src1(src1_reg),
      .rm(fpu_rm_reg),
      .start(sqrt_start),
      .flush(flush),
      .result(sqrt_result),
      .fflags(sqrt_fflags),
      .done(sqrt_done)
  );

  wire [31:0] cvt_result;
  wire [4:0]  cvt_fflags;
  wire        cvt_done;

  fpu_cvt u_cvt(
      .clk(clk),
      .resetn(resetn),
      .src1(src1_reg),
      .cvt_funct(cvt_funct_r),
      .rm(fpu_rm_reg),
      .start(cvt_start),
      .flush(flush),
      .result(cvt_result),
      .fflags(cvt_fflags),
      .done(cvt_done)
  );

  wire [31:0] fma_result;
  wire [4:0]  fma_fflags;
  wire        fma_done;

  fpu_fma u_fma(
      .clk(clk),
      .resetn(resetn),
      .src1(src1_reg),
      .src2(src2_reg),
      .src3(src3_reg),
      .fma_funct(fpu_funct_reg),
      .rm(fpu_rm_reg),
      .start(fma_start),
      .flush(flush),
      .result(fma_result),
      .fflags(fma_fflags),
      .done(fma_done)
  );

  // ===================================================================
  // Combinational sub-module instances (use latched src1_reg/src2_reg)
  // ===================================================================
  wire [31:0] cmp_result;
  wire [4:0]  cmp_fflags;

  fpu_compare u_cmp(
      .src1(src1_reg),
      .src2(src2_reg),
      .cmp_funct(cmp_funct_r),
      .result(cmp_result),
      .fflags(cmp_fflags)
  );

  wire [31:0] minmax_result;
  wire [4:0]  minmax_fflags;

  fpu_minmax u_minmax(
      .src1(src1_reg),
      .src2(src2_reg),
      .is_max((fpu_funct_reg == FPU_FMAX)),
      .result(minmax_result),
      .fflags(minmax_fflags)
  );

  wire [31:0] classify_result;
  wire [4:0]  classify_fflags;

  fpu_classify u_classify(
      .src1(src1_reg),
      .result(classify_result),
      .fflags(classify_fflags)
  );

  wire [31:0] sgnj_result;
  wire [4:0]  sgnj_fflags;

  fpu_sign_inject u_sgnj(
      .src1(src1_reg),
      .src2(src2_reg),
      .sgnj_funct(sgnj_funct_r),
      .result(sgnj_result),
      .fflags(sgnj_fflags)
  );

  // ===================================================================
  // Combinational result mux (from latched fpu_funct_reg)
  // ===================================================================
  wire [31:0] comb_result;
  assign comb_result = (fpu_funct_reg == FPU_FMIN)    ? minmax_result  :
                       (fpu_funct_reg == FPU_FMAX)    ? minmax_result  :
                       (fpu_funct_reg == FPU_FSGNJ)   ? sgnj_result    :
                       (fpu_funct_reg == FPU_FSGNJN)  ? sgnj_result    :
                       (fpu_funct_reg == FPU_FSGNJX)  ? sgnj_result    :
                       (fpu_funct_reg == FPU_FEQ)     ? cmp_result     :
                       (fpu_funct_reg == FPU_FLT)     ? cmp_result     :
                       (fpu_funct_reg == FPU_FLE)     ? cmp_result     :
                       (fpu_funct_reg == FPU_FCLASS)  ? classify_result :
                       (fpu_funct_reg == FPU_FMV_X_W) ? src1_reg       :
                       /* FPU_FMV_W_X */                src1_reg;

  wire [4:0] comb_fflags;
  assign comb_fflags = (fpu_funct_reg == FPU_FMIN)    ? minmax_fflags  :
                       (fpu_funct_reg == FPU_FMAX)    ? minmax_fflags  :
                       (fpu_funct_reg == FPU_FSGNJ)   ? sgnj_fflags    :
                       (fpu_funct_reg == FPU_FSGNJN)  ? sgnj_fflags    :
                       (fpu_funct_reg == FPU_FSGNJX)  ? sgnj_fflags    :
                       (fpu_funct_reg == FPU_FEQ)     ? cmp_fflags     :
                       (fpu_funct_reg == FPU_FLT)     ? cmp_fflags     :
                       (fpu_funct_reg == FPU_FLE)     ? cmp_fflags     :
                       (fpu_funct_reg == FPU_FCLASS)  ? classify_fflags :
                       /* FMV.X.W / FMV.W.X */          5'b0;

  // ===================================================================
  // Sub-module done/result/fflags selection (from latched fpu_funct_reg)
  // ===================================================================
  wire is_adder_op = (fpu_funct_reg == FPU_FADD) || (fpu_funct_reg == FPU_FSUB);
  wire is_mul_op   = (fpu_funct_reg == FPU_FMUL);
  wire is_div_op   = (fpu_funct_reg == FPU_FDIV);
  wire is_sqrt_op  = (fpu_funct_reg == FPU_FSQRT);
  wire is_cvt_op   = (fpu_funct_reg == FPU_FCVT_W_S)  || (fpu_funct_reg == FPU_FCVT_WU_S) ||
                     (fpu_funct_reg == FPU_FCVT_S_W)  || (fpu_funct_reg == FPU_FCVT_S_WU);
  wire is_fma_op   = (fpu_funct_reg == FPU_FMADD) || (fpu_funct_reg == FPU_FMSUB) ||
                     (fpu_funct_reg == FPU_FNMSUB) || (fpu_funct_reg == FPU_FNMADD);

  wire done_sel = is_adder_op ? adder_done :
                  is_mul_op   ? mul_done   :
                  is_div_op   ? div_done   :
                  is_sqrt_op  ? sqrt_done  :
                  is_cvt_op   ? cvt_done   :
                  is_fma_op   ? fma_done   :
                  1'b0;

  wire [31:0] result_sel = is_comb_op ? comb_result :
                  is_adder_op ? adder_result :
                  is_mul_op   ? mul_result   :
                  is_div_op   ? div_result   :
                  is_sqrt_op  ? sqrt_result  :
                  is_cvt_op   ? cvt_result   :
                  is_fma_op   ? fma_result   :
                  32'b0;

  wire [4:0] fflags_sel = is_comb_op ? comb_fflags :
                  is_adder_op ? adder_fflags :
                  is_mul_op   ? mul_fflags   :
                  is_div_op   ? div_fflags   :
                  is_sqrt_op  ? sqrt_fflags  :
                  is_cvt_op   ? cvt_fflags   :
                  is_fma_op   ? fma_fflags   :
                  5'b0;

  // ===================================================================
  // Main FSM (MMU-style explicit state register)
  // ===================================================================
  always_ff @(posedge clk or negedge resetn)
  begin
    if (!resetn)
    begin
      f_state           <= F_IDLE;
      adder_start       <= 1'b0;
      mul_start         <= 1'b0;
      div_start         <= 1'b0;
      sqrt_start        <= 1'b0;
      cvt_start         <= 1'b0;
      fma_start         <= 1'b0;
      result_valid_reg  <= 1'b0;
      result_hold_reg   <= 32'b0;
      fflags_reg        <= 5'b0;
      rd_is_int_reg     <= 1'b0;
      fpu_funct_reg     <= 7'b0;
      fpu_rm_reg        <= 3'b0;
      src1_reg          <= 32'b0;
      src2_reg          <= 32'b0;
      src3_reg          <= 32'b0;
      timeout_cnt       <= 10'b0;
      fpu_error_reg     <= 1'b0;
    end
    else
    begin
      // Default: clear start signals (1-cycle pulses)
      adder_start <= 1'b0;
      mul_start   <= 1'b0;
      div_start   <= 1'b0;
      sqrt_start  <= 1'b0;
      cvt_start   <= 1'b0;
      fma_start   <= 1'b0;

      if (flush)
      begin
        // Flush: return to idle, clear all state (BUG-6 fix preserved:
        // clear result_hold_reg to prevent stale data leakage)
        f_state          <= F_IDLE;
        result_valid_reg <= 1'b0;
        result_hold_reg  <= 32'b0;
        fflags_reg       <= 5'b0;
        rd_is_int_reg    <= 1'b0;
        timeout_cnt      <= 10'b0;
        fpu_error_reg    <= 1'b0;
      end
      else
      begin
        case (f_state)
          // ── F_IDLE: wait for req_valid, latch all inputs ──
          F_IDLE: begin
            if (req_valid) begin
              fpu_funct_reg <= fpu_funct;
              fpu_rm_reg    <= fpu_rm;
              src1_reg      <= src1;
              src2_reg      <= src2;
              src3_reg      <= src3;
              f_state       <= F_DISPATCH;
            end
          end

          // ── F_DISPATCH: start sub-module, or skip to F_DONE for comb ops ──
          F_DISPATCH: begin
            if (is_comb_op) begin
              // Combinational op: result already available from comb mux
              // (src1_reg/src2_reg/fpu_funct_reg settled after F_IDLE latch)
              f_state <= F_DONE;
            end
            else begin
              case (fpu_funct_reg)
                FPU_FADD, FPU_FSUB: adder_start <= 1'b1;
                FPU_FMUL:           mul_start   <= 1'b1;
                FPU_FDIV:           div_start   <= 1'b1;
                FPU_FSQRT:          sqrt_start  <= 1'b1;
                FPU_FCVT_W_S, FPU_FCVT_WU_S,
                FPU_FCVT_S_W, FPU_FCVT_S_WU: cvt_start <= 1'b1;
                FPU_FMADD, FPU_FMSUB, FPU_FNMSUB, FPU_FNMADD: fma_start <= 1'b1;
                default: ; // unreachable
              endcase
              timeout_cnt <= 10'b0;   // arm watchdog on entering F_WAIT
              f_state <= F_WAIT;
            end
          end

          // ── F_WAIT: wait for active sub-module done signal ──
          //   Timeout watchdog: if sub-module done does not arrive within
          //   TIMEOUT_MAX cycles, force completion with fpu_error=1 so the
          //   caller handshake still completes (result_valid asserted) but
          //   the result is marked invalid.
          F_WAIT: begin
            if (done_sel) begin
              f_state <= F_DONE;
            end else if (timeout_cnt >= TIMEOUT_MAX) begin
              fpu_error_reg <= 1'b1;
              f_state       <= F_DONE;
            end else begin
              timeout_cnt <= timeout_cnt + 10'd1;
            end
          end

          // ── F_DONE: latch result/fflags/rd_is_int, set result_valid ──
          F_DONE: begin
            result_hold_reg  <= result_sel;
            fflags_reg       <= fflags_sel;
            rd_is_int_reg    <= is_rd_int;
            result_valid_reg <= 1'b1;
            f_state          <= F_COMPLETE;
          end

          // ── F_COMPLETE: hold result_valid until result_got ──
          // NBA shadow cycle protection: only assign result_valid_reg
          // conditionally (on result_got). When staying in F_COMPLETE, no
          // unconditional assignment is made, so the default clear does NOT
          // fire — result_valid_reg holds its value. When result_got arrives,
          // the conditional clear takes effect next cycle in F_IDLE.
          F_COMPLETE: begin
            if (result_got) begin
              result_valid_reg <= 1'b0;
              fpu_error_reg    <= 1'b0;   // clear error after caller consumes result
              f_state          <= F_IDLE;
            end
            // else: hold result_valid_reg/fpu_error_reg high (no assignment
            // → retains value)
          end

          default: f_state <= F_IDLE;
        endcase
      end
    end
  end

  // ===================================================================
  // Output assignments
  // ===================================================================
  assign result       = result_hold_reg;
  assign result_valid = result_valid_reg;
  assign fflags       = fflags_reg;
  assign rd_is_int    = rd_is_int_reg;
  assign fpu_error    = fpu_error_reg;

endmodule
