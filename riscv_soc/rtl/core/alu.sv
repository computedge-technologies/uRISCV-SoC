// =============================================================================
// Module      : alu
// Project     : RISC-V Subset Single-Cycle Processor  (SE-ISA-001)
// Author      : Prabakaran Elaiyappan | SynaptiqEdge Technologies
// Description : 32-bit ALU.  Supports all operations required by the ISA
//               subset: ADD SUB AND OR XOR SLL SRL SRA SLT SLTU.
//               ALUOp = {funct7_5, funct3}.
// =============================================================================

module alu
    import riscv_pkg::*;
(
    input  logic [31:0] a,            // Operand A (rs1 or 0 for LUI)
    input  logic [31:0] b,            // Operand B (rs2 or immediate)
    input  logic [3:0]  alu_op,       // Operation select

    output logic [31:0] result,       // Computation result
    output logic        zero,         // 1 when result == 0
    output logic        negative      // result[31] (sign bit) — for BLT/BGE
);

    // GOOD — universally supported by VCS, Xcelium, Questa, iverilog
     logic signed [31:0] a_signed;
     logic signed [31:0] b_signed;

     assign a_signed = a;   // implicit reinterpretation — same bits, signed type
     assign b_signed = b;
   
    logic [4:0]  shamt;
    logic signed [31:0] a_s, b_s;

    assign shamt = b[4:0];
//    assign a_s   = signed'(a);
//    assign b_s   = signed'(b);

    always_comb begin
        result = 32'b0;
        unique case (alu_op)
            ALU_ADD  : result = a + b;
            ALU_SUB  : result = a - b;
            ALU_AND  : result = a & b;
            ALU_OR   : result = a | b;
            ALU_XOR  : result = a ^ b;
            ALU_SLL  : result = a << shamt;
            ALU_SRL  : result = a >> shamt;
            ALU_SRA  : result = (a_signed >>> shamt);
            ALU_SLT  : result = (a_signed < b_signed)  ? 32'd1 : 32'd0;
            ALU_SLTU : result = (a < b)       ? 32'd1 : 32'd0;
            default  : result = 32'b0;
        endcase
    end

    assign zero     = (result == 32'b0);
    assign negative = result[31];

endmodule
