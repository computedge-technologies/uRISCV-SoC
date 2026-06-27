// =============================================================================
// Module      : control_unit
// Project     : RISC-V Subset Single-Cycle Processor  (SE-ISA-001)
// Author      : Prabakaran Elaiyappan | SynaptiqEdge Technologies
// Description : Combinational control signal generation from opcode/funct fields.
//
// ALUOp encoding  {funct7_5, funct3}:
//   0000 = ADD    0001 = SLL    0010 = SLT    0011 = SLTU
//   0100 = XOR    0101 = SRL    0110 = OR     0111 = AND
//   1000 = SUB    1101 = SRA
//
// ResultSrc:
//   2'b00 = ALU result
//   2'b01 = PC+4  (JAL/JALR link address)
//   2'b10 = imm<<12 already in imm  (LUI — ALU bypassed via ALUSrc=1, A=0)
// =============================================================================

module control_unit
    import riscv_pkg::*;
(
    input  logic [6:0] opcode,
    input  logic [2:0] funct3,
    input  logic       funct7_5,

    output logic       reg_write,    // 1 = write register file
    output logic       alu_src,      // 0 = B=rs2 | 1 = B=imm
    output logic [3:0] alu_op,       // ALU operation select
    output logic       branch,       // 1 = conditional branch
    output logic       jump,         // 1 = unconditional jump
    output logic       jump_src,     // 0 = JAL (PC-rel) | 1 = JALR (reg-rel)
    output logic [1:0] result_src,   // 00=ALU | 01=PC+4 | 10=LUI passthrough
    output logic       lui_sel       // 1 = LUI: force rs1=x0 in ALU (A=0+imm)
);

    always_comb begin
        // Safe defaults
        reg_write  = 1'b0;
        alu_src    = 1'b0;
        alu_op     = ALU_ADD;
        branch     = 1'b0;
        jump       = 1'b0;
        jump_src   = 1'b0;
        result_src = 2'b00;
        lui_sel    = 1'b0;

        unique case (opcode)
            // ── R-type: ADD SUB AND OR XOR SLL SRL SRA SLT SLTU ────────────
            OP_R: begin
                reg_write = 1'b1;
                alu_src   = 1'b0;
                alu_op    = {funct7_5, funct3};
            end

            // ── I-type ALU: ADDI ANDI ORI XORI SLTI SLTIU SLLI SRLI SRAI ──
            OP_I: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                // funct7_5 distinguishes SRLI (0) from SRAI (1)
                alu_op    = {funct7_5, funct3};
            end

            // ── B-type: BEQ BNE BLT BGE BLTU BGEU ──────────────────────────
            OP_BR: begin
                reg_write = 1'b0;
                alu_src   = 1'b0;
                alu_op    = ALU_SUB;   // Compare via subtraction; zero/neg flags used
                branch    = 1'b1;
            end

            // ── JAL ──────────────────────────────────────────────────────────
            OP_JAL: begin
                reg_write  = 1'b1;
                jump       = 1'b1;
                jump_src   = 1'b0;     // Target = PC + imm
                result_src = 2'b01;    // Write PC+4 to rd
            end

            // ── JALR ─────────────────────────────────────────────────────────
            OP_JALR: begin
                reg_write  = 1'b1;
                alu_src    = 1'b1;
                alu_op     = ALU_ADD;
                jump       = 1'b1;
                jump_src   = 1'b1;     // Target = ALU result (rs1+imm) & ~1
                result_src = 2'b01;    // Write PC+4 to rd
            end

            // ── LUI ──────────────────────────────────────────────────────────
            OP_LUI: begin
                reg_write  = 1'b1;
                alu_src    = 1'b1;
                alu_op     = ALU_ADD;
                result_src = 2'b10;    // Bypass ALU — write imm directly
                lui_sel    = 1'b1;     // Force rs1=x0 → ALU A=0, result=imm
            end

            // ── AUIPC ────────────────────────────────────────────────────────
            OP_AUIPC: begin
                reg_write  = 1'b1;
                alu_src    = 1'b1;
                alu_op     = ALU_ADD;  // ALU computes PC + (imm<<12)
                result_src = 2'b00;
            end

            default: begin
                /* Unimplemented opcode → all signals hold safe defaults */
            end
        endcase
    end

endmodule
