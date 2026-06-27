// =============================================================================
// Package     : riscv_pkg
// Project     : RISC-V SoC  (SE-SOC-001)
// Author      : Prabakaran Elaiyappan | SynaptiqEdge Technologies
//
// Description : Shared constants for the RISC-V core.
//               - ALU operation codes (ALUOp[3:0] = {funct7_5, funct3})
//               - RV32I opcode encodings
//
//   Encoding table:
//   ┌──────────┬─────────┬────────┬────────────┐
//   │ ALUOp    │ funct7_5│ funct3 │ Operation  │
//   ├──────────┼─────────┼────────┼────────────┤
//   │ 4'b0000  │    0    │  000   │ ADD        │
//   │ 4'b0001  │    0    │  001   │ SLL        │
//   │ 4'b0010  │    0    │  010   │ SLT        │
//   │ 4'b0011  │    0    │  011   │ SLTU       │
//   │ 4'b0100  │    0    │  100   │ XOR        │
//   │ 4'b0101  │    0    │  101   │ SRL        │
//   │ 4'b0110  │    0    │  110   │ OR         │
//   │ 4'b0111  │    0    │  111   │ AND        │
//   │ 4'b1000  │    1    │  000   │ SUB        │
//   │ 4'b1101  │    1    │  101   │ SRA        │
//   └──────────┴─────────┴────────┴────────────┘
//
// Usage: `import riscv_pkg::*;` in any module that needs these constants.
//        Must be compiled BEFORE control_unit.sv, alu.sv, ctrl_ext.sv,
//        branch_logic.sv, riscv_core.sv, riscv_core_ext.sv.
// =============================================================================

package riscv_pkg;

    // ── ALU Operation Codes  (ALUOp[3:0] = {funct7_5, funct3}) ──────────────
    localparam logic [3:0] ALU_ADD  = 4'b0000;   // ADD  / ADDI
    localparam logic [3:0] ALU_SLL  = 4'b0001;   // SLL  / SLLI
    localparam logic [3:0] ALU_SLT  = 4'b0010;   // SLT  / SLTI
    localparam logic [3:0] ALU_SLTU = 4'b0011;   // SLTU / SLTIU
    localparam logic [3:0] ALU_XOR  = 4'b0100;   // XOR  / XORI
    localparam logic [3:0] ALU_SRL  = 4'b0101;   // SRL  / SRLI
    localparam logic [3:0] ALU_OR   = 4'b0110;   // OR   / ORI
    localparam logic [3:0] ALU_AND  = 4'b0111;   // AND  / ANDI
    localparam logic [3:0] ALU_SUB  = 4'b1000;   // SUB  (funct7_5=1, funct3=000)
    localparam logic [3:0] ALU_SRA  = 4'b1101;   // SRA  / SRAI (funct7_5=1, funct3=101)

    // ── RV32I Opcode Encodings ───────────────────────────────────────────────
    localparam logic [6:0] OP_R     = 7'b0110011;   // R-type  (ADD SUB AND OR ...)
    localparam logic [6:0] OP_I     = 7'b0010011;   // I-type  (ADDI ANDI ORI ...)
    localparam logic [6:0] OP_LOAD  = 7'b0000011;   // Load    (LW LH LB LHU LBU)
    localparam logic [6:0] OP_STOR  = 7'b0100011;   // Store   (SW SH SB)
    localparam logic [6:0] OP_BR    = 7'b1100011;   // Branch  (BEQ BNE BLT BGE ...)
    localparam logic [6:0] OP_JAL   = 7'b1101111;   // JAL
    localparam logic [6:0] OP_JALR  = 7'b1100111;   // JALR
    localparam logic [6:0] OP_LUI   = 7'b0110111;   // LUI
    localparam logic [6:0] OP_AUIPC = 7'b0010111;   // AUIPC

endpackage
