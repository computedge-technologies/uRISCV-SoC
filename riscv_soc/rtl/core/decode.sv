// =============================================================================
// Module      : decode
// Project     : RISC-V SoC  (SE-SOC-001)
// Author      : Prabakaran Elaiyappan | SynaptiqEdge Technologies
// Description : Instruction field extractor + immediate sign-extender.
//               Uses full-width RHS concatenation to avoid iverilog partial-
//               LHS select limitations.
// =============================================================================
module decode (
    input  logic [31:0] instr,
    output logic [6:0]  opcode,
    output logic [2:0]  funct3,
    output logic        funct7_5,
    output logic [4:0]  rs1,
    output logic [4:0]  rs2,
    output logic [4:0]  rd,
    output logic [31:0] imm
);
    assign opcode   = instr[6:0];
    assign rd       = instr[11:7];
    assign funct3   = instr[14:12];
    assign rs1      = instr[19:15];
    assign rs2      = instr[24:20];
    assign funct7_5 = instr[30];

    wire sign = instr[31];

    always_comb begin
        case (opcode)
            // I-type: ADDI, ANDI, ORI, XORI, SLTI, SLTIU, SLLI, SRLI, SRAI
            7'b0010011,
            // I-type: JALR
            7'b1100111,
            // I-type: LOAD (LW LH LB LHU LBU)
            7'b0000011:
                imm = {{20{sign}}, instr[31:20]};

            // S-type: STORE (SW SH SB)
            7'b0100011:
                imm = {{20{sign}}, instr[31:25], instr[11:7]};

            // B-type: BEQ BNE BLT BGE BLTU BGEU
            7'b1100011:
                imm = {{19{sign}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};

            // U-type: LUI AUIPC
            7'b0110111,
            7'b0010111:
                imm = {instr[31:12], 12'b0};

            // J-type: JAL
            7'b1101111:
                imm = {{11{sign}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};

            default:
                imm = 32'b0;
        endcase
    end
endmodule
