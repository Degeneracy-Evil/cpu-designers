module get_neg_1b (
    input inhibitory_in,
    input source,
    output wire inhibitory_out,
    output wire out
  );
  // 产生后续抑制信号
  wire inh_out;
  or(inh_out,inhibitory_in,source);
  buf(inhibitory_out,inh_out);

  // 计算所需
  wire n_sor;
  wire n_inh;
  not(n_sor,source);
  not(n_inh,inhibitory_in);

  // 按照抑制生成信号
  wire ans_keep;
  wire ans_neg;
  and(ans_keep,n_inh,source);
  and(ans_neg,inhibitory_in,n_sor);
  or(out,ans_keep,ans_neg);

endmodule

module get_neg (
    input wire [31:0] source,
    output wire [31:0] out
  );
  // 三十二位求相反数（补码）器件
  buf(out[0],source[0]);

  wire [30:0] inhibitory;
  genvar i;
  generate
    for(i=1;i<32;i=i+1) begin : gmod
      if(i==1) begin : first
        get_neg_1b unit(
                     .inhibitory_in(source[0]),
                     .source(source[i]),
                     .inhibitory_out(inhibitory[i-1]),
                     .out(out[i])
                   );
      end else begin : chain
        get_neg_1b unit(
                     .inhibitory_in(inhibitory[i-2]),
                     .source(source[i]),
                     .inhibitory_out(inhibitory[i-1]),
                     .out(out[i])
                   );
      end
    end
  endgenerate
endmodule
