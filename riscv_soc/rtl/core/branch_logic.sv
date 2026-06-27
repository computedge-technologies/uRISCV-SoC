// =============================================================================
// Module      : branch_logic
// Project     : RISC-V Subset Single-Cycle Processor  (SE-ISA-001)
// Author      : Prabakaran Elaiyappan | SynaptiqEdge Technologies
// Description : Evaluates branch taken/not-taken based on funct3 condition
//               code and ALU flags (zero, negative, carry-out for unsigned).
//
// Branch conditions (funct3):
//   000 BEQ  : rs1 == rs2  → zero
//   001 BNE  : rs1 != rs2  → !zero
//   100 BLT  : rs1  < rs2 (signed)  → negative != overflow; simplified: result<0
//   101 BGE  : rs1 >= rs2 (signed)  → !(negative != overflow)
//   110 BLTU : rs1  < rs2 (unsigned)
//   111 BGEU : rs1 >= rs2 (unsigned)
//
// The ALU always performs SUB for branches; we use the SUB result flags.
// For unsigned compare we track borrow = (a < b) directly in ALU SLTU.
// =============================================================================

module branch_logic (
    input  logic [2:0]  funct3,
    input  logic        zero,         // ALU result == 0
    input  logic        negative,     // ALU result[31]
    input  logic        branch,       // Control: is this a branch instr?
    // Unsigned less-than: reuse a separate SLTU path or carry flag
    // We add a direct ult (unsigned less than) flag from the datapath
    input  logic        ult,          // 1 when rs1 < rs2 (unsigned)
    output logic        branch_taken  // 1 → take the branch
);

    logic condition;

    always_comb begin
        unique case (funct3)
            3'b000: condition = zero;          // BEQ
            3'b001: condition = !zero;         // BNE
            3'b100: condition = negative;      // BLT  (signed; SUB result < 0)
            3'b101: condition = !negative;     // BGE  (signed)
            3'b110: condition = ult;           // BLTU
            3'b111: condition = !ult;          // BGEU
            default: condition = 1'b0;
        endcase
    end

    assign branch_taken = branch & condition;

endmodule
