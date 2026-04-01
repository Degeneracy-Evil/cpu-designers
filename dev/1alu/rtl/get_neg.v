module get_neg_1b (
    input  wire inhibitory_in,
    input  wire source,
    output wire inhibitory_out,
    output wire out
  );
  assign inhibitory_out = inhibitory_in | source;
  assign out = source ^ inhibitory_in;
endmodule

// 三十二位求相反数（补码）器件
module get_neg (
    input  wire [31:0] source,
    output wire [31:0] out
  );
  wire [30:0] inhibitory;
  genvar i;

  assign out[0] = source[0];
  assign inhibitory[0] = source[0];

  generate
    for(i = 1; i < 31; i = i + 1)
    begin : gmod
      get_neg_1b unit (
                   .inhibitory_in(inhibitory[i-1]),
                   .source(source[i]),
                   .inhibitory_out(inhibitory[i]),
                   .out(out[i])
                 );
    end
  endgenerate

  get_neg_1b last_unit (
               .inhibitory_in(inhibitory[29]),
               .source(source[31]),
               .inhibitory_out(),
               .out(out[31])
             );
endmodule
