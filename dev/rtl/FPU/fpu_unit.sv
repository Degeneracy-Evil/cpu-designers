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
    output        rd_is_int     // 1 = result writes integer register
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

  // ===================================================================
  // Handshake registers (mirror mu_unit.sv exactly)
  // ===================================================================
  reg adder_start;
  reg mul_start;
  reg div_start;
  reg sqrt_start;
  reg cvt_start;
  reg fma_start;
  reg adder_busy;
  reg mul_busy;
  reg div_busy;
  reg sqrt_busy;
  reg cvt_busy;
  reg fma_busy;
  reg req_hold;
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
  // Handshake logic (mirror mu_unit.sv)
  // ===================================================================
  assign fpu_busy  = adder_busy | mul_busy | div_busy | sqrt_busy | cvt_busy | fma_busy;
  assign fpu_ready = (~fpu_busy) & (~req_hold) & (~result_valid_reg);

  wire req_fire;
  assign req_fire = req_valid & fpu_ready;

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
  // Main FSM (mirror mu_unit.sv pattern exactly)
  // ===================================================================
  always_ff @(posedge clk or negedge resetn)
  begin
    if (!resetn)
    begin
      adder_start       <= 1'b0;
      mul_start         <= 1'b0;
      div_start         <= 1'b0;
      sqrt_start        <= 1'b0;
      cvt_start         <= 1'b0;
      fma_start         <= 1'b0;
      adder_busy        <= 1'b0;
      mul_busy          <= 1'b0;
      div_busy          <= 1'b0;
      sqrt_busy         <= 1'b0;
      cvt_busy          <= 1'b0;
      fma_busy          <= 1'b0;
      req_hold          <= 1'b0;
      result_valid_reg  <= 1'b0;
      result_hold_reg   <= 32'b0;
      fflags_reg        <= 5'b0;
      rd_is_int_reg     <= 1'b0;
      fpu_funct_reg     <= 7'b0;
      fpu_rm_reg        <= 3'b0;
      src1_reg          <= 32'b0;
      src2_reg          <= 32'b0;
      src3_reg          <= 32'b0;
    end
    else
    begin
      // Default: clear start signals (mirror mu_unit pattern)
      adder_start <= 1'b0;
      mul_start   <= 1'b0;
      div_start   <= 1'b0;
      sqrt_start  <= 1'b0;
      cvt_start   <= 1'b0;
      fma_start   <= 1'b0;

      if (flush)
      begin
        adder_busy       <= 1'b0;
        mul_busy         <= 1'b0;
        div_busy         <= 1'b0;
        sqrt_busy        <= 1'b0;
        cvt_busy         <= 1'b0;
        fma_busy         <= 1'b0;
        req_hold         <= 1'b0;
        result_valid_reg <= 1'b0;
        // BUG-6 fix: clear hold registers on flush to prevent stale data
        // leakage after flush→idle transition
        result_hold_reg  <= 32'b0;
        fflags_reg       <= 5'b0;
        rd_is_int_reg    <= 1'b0;
      end
      else
      begin
        // req_hold management (mirror mu_unit)
        if (!req_valid)
        begin
          req_hold <= 1'b0;
        end
        else if (req_fire)
        begin
          req_hold <= 1'b1;
        end

        // result_got clears result_valid (mirror mu_unit)
        if (result_valid_reg && result_got)
        begin
          result_valid_reg <= 1'b0;
        end

        // Sequential sub-module done handling (mirror mu_unit)
        if (adder_done && adder_busy)
        begin
          adder_busy       <= 1'b0;
          result_hold_reg  <= adder_result;
          fflags_reg       <= adder_fflags;
          rd_is_int_reg    <= 1'b0;
          result_valid_reg <= 1'b1;
        end

        if (mul_done && mul_busy)
        begin
          mul_busy         <= 1'b0;
          result_hold_reg  <= mul_result;
          fflags_reg       <= mul_fflags;
          rd_is_int_reg    <= 1'b0;
          result_valid_reg <= 1'b1;
        end

        if (div_done && div_busy)
        begin
          div_busy         <= 1'b0;
          result_hold_reg  <= div_result;
          fflags_reg       <= div_fflags;
          rd_is_int_reg    <= 1'b0;
          result_valid_reg <= 1'b1;
        end

        if (sqrt_done && sqrt_busy)
        begin
          sqrt_busy        <= 1'b0;
          result_hold_reg  <= sqrt_result;
          fflags_reg       <= sqrt_fflags;
          rd_is_int_reg    <= 1'b0;
          result_valid_reg <= 1'b1;
        end

        if (cvt_done && cvt_busy)
        begin
          cvt_busy         <= 1'b0;
          result_hold_reg  <= cvt_result;
          fflags_reg       <= cvt_fflags;
          rd_is_int_reg    <= is_rd_int;
          result_valid_reg <= 1'b1;
        end

        if (fma_done && fma_busy)
        begin
          fma_busy         <= 1'b0;
          result_hold_reg  <= fma_result;
          fflags_reg       <= fma_fflags;
          rd_is_int_reg    <= 1'b0;
          result_valid_reg <= 1'b1;
        end

        // Request dispatch on req_fire
        if (req_fire)
        begin
          fpu_funct_reg <= fpu_funct;
          fpu_rm_reg    <= fpu_rm;
          src1_reg      <= src1;
          src2_reg      <= src2;
          src3_reg      <= src3;

          case (fpu_funct)
            FPU_FADD, FPU_FSUB: begin
              adder_start <= 1'b1;
              adder_busy  <= 1'b1;
            end
            FPU_FMUL: begin
              mul_start <= 1'b1;
              mul_busy  <= 1'b1;
            end
            FPU_FDIV: begin
              div_start <= 1'b1;
              div_busy  <= 1'b1;
            end
            FPU_FSQRT: begin
              sqrt_start <= 1'b1;
              sqrt_busy  <= 1'b1;
            end
            FPU_FCVT_W_S, FPU_FCVT_WU_S,
            FPU_FCVT_S_W, FPU_FCVT_S_WU: begin
              cvt_start <= 1'b1;
              cvt_busy  <= 1'b1;
            end
            FPU_FMADD, FPU_FMSUB, FPU_FNMSUB, FPU_FNMADD: begin
              fma_start <= 1'b1;
              fma_busy  <= 1'b1;
            end
            // Combinational operations: inputs are latched above;
            // result captured next cycle by comb_done logic below.
            default: ; // no action needed
          endcase
        end

        // Combinational result capture: one cycle after req_fire,
        // src1_reg/src2_reg/fpu_funct_reg have the new values,
        // and the combinational sub-modules compute the correct result.
        if (req_hold && ~fpu_busy && ~result_valid_reg && is_comb_op)
        begin
          result_hold_reg  <= comb_result;
          fflags_reg       <= comb_fflags;
          rd_is_int_reg    <= is_rd_int;
          result_valid_reg <= 1'b1;
          req_hold         <= 1'b0;
        end
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

endmodule
