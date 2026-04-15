`timescale 1ns / 1ps

// Instruction memory.
// - Word-addressed read-only memory for fetch stage.
// - Optional hex initialization file.
// - Out-of-range access returns NOP (addi x0, x0, 0).
module instr_mem #(
    // Number of 32-bit words.
    parameter MEM_DEPTH = 256,
    // Optional initialization file path for $readmemh.
    parameter INIT_FILE = ""
)(
    // Byte address from PC.
    input  [31:0] addr,
    // 32-bit instruction output.
    output [31:0] instr
);

    // Backing storage array.
    reg [31:0] mem[0:MEM_DEPTH-1];
    integer i;
    // Word index derived from byte address (drop low 2 bits).
    wire [31:0] word_addr;

    assign word_addr = {2'b00, addr[31:2]};

    // Memory initialization.
    initial begin
        // Fill with NOP by default.
        for (i = 0; i < MEM_DEPTH; i = i + 1)
            mem[i] = 32'h00000013;

        // Overlay with program image when provided.
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    // Combinational fetch.
    assign instr = (word_addr < MEM_DEPTH) ? mem[word_addr] : 32'h00000013;

endmodule
