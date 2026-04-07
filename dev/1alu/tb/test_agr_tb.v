
module test_agr_tb;

  // Parameters

  //Ports
  reg  in;
  wire  out;

  test_agr  test_agr_inst (
              .in(~in),
              .out(out)
            );

  initial
  begin
    $dumpfile("wave.vcd");       //生成的vcd文件名称
    $dumpvars(0, test_agr_tb);    //tb模块名称

    in = 0;
    #10;
    in = 1;
    #10

    $finish;
  end

endmodule
