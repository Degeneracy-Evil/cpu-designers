
module get_neg_tb;

  // Parameters

  //Ports
  reg [31:0] source;
  wire [31:0] out;
  reg [31:0] expected;
  integer i;

  get_neg  get_neg_inst (
             .source(source),
             .out(out)
           );

  initial
  begin
    $dumpfile("wave.vcd");       //生成的vcd文件名称
    $dumpvars(0, get_neg_tb);    //tb模块名称

    source = 32'h00000000;
    #10;
    source = 32'h00000001;
    #10;
    source = 32'h00000009;
    #10;
    source = 32'h80000000;
    #10;

    for (i = 0; i < 16; i = i + 1)
    begin
      source = i;
      #1;
      expected = -source;
      if (out !== expected)
      begin
        $display("ERROR source=%h out=%h expected=%h", source, out, expected);
        $finish;
      end
      #9;
    end

    $display("PASS get_neg 32-bit test");
    $finish;
  end

endmodule
