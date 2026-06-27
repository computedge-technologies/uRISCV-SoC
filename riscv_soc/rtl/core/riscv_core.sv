// =============================================================================
// Module      : riscv_core
// Project     : RISC-V Subset Single-Cycle Processor  (SE-ISA-001)
// Author      : Prabakaran Elaiyappan | SynaptiqEdge Technologies
//
// Description : Top-level single-cycle datapath integrating all sub-modules:
//                 PC Register, PC+4 Adder, Instruction Memory,
//                 Decode/ImmGen, Control Unit, Register File, ALU,
//                 Branch Logic, PC Mux, Result Mux.
//
// Parameters  :
//   MEM_DEPTH  — Instruction memory depth in 32-bit words (default 256)
//   MEM_AWIDTH — Address bits (default 8)
// =============================================================================

module riscv_core #(
    parameter int MEM_DEPTH  = 256,
    parameter int MEM_AWIDTH = 8
) (
    input  logic clk,
    input  logic rst_n,

`ifdef SYNTH
    // ── Instruction memory write port (SYNTH only) ──────────────────────────
    input  logic                    imem_wr_en,
    input  logic [MEM_AWIDTH-1:0]   imem_wr_addr,
    input  logic [31:0]             imem_wr_data,
`endif

    // ── Observation ports (useful for simulation and verification) ───────────
    output logic [31:0] o_pc,
    output logic [31:0] o_instr,
    output logic [31:0] o_alu_result,
    output logic [31:0] o_reg_a0      // x10 (a0) — result register by convention
);

    import riscv_pkg::*;

    // ── Internal wires ───────────────────────────────────────────────────────
    logic [31:0] pc, pc4, pc_next, instr;
    logic [6:0]  opcode;
    logic [2:0]  funct3;
    logic        funct7_5;
    logic [4:0]  rs1_addr, rs2_addr, rd_addr;
    logic [31:0] imm;
    logic        reg_write, alu_src, branch, jump, jump_src, lui_sel;
    logic [3:0]  alu_op;
    logic [1:0]  result_src;
    logic [31:0] rs1_data, rs2_data;
    logic [31:0] alu_a, alu_b, alu_result;
    logic        alu_zero, alu_neg, alu_ult;
    logic        branch_taken;
    logic [31:0] branch_tgt, jalr_tgt, jal_tgt;
    logic [31:0] wr_data;

    // ── PC Register ─────────────────────────────────────────────────────────
    pc_register u_pc (
        .clk     (clk),
        .rst_n   (rst_n),
        .pc_next (pc_next),
        .pc      (pc)
    );

    // ── PC+4 Adder ──────────────────────────────────────────────────────────
    pc_plus4 u_pc4 (
        .pc  (pc),
        .pc4 (pc4)
    );

    // ── Instruction Memory ───────────────────────────────────────────────────
    instr_mem #(
        .DEPTH  (MEM_DEPTH),
        .AWIDTH (MEM_AWIDTH)
    ) u_imem (
        .pc      (pc),
        .instr   (instr),
`ifdef SYNTH
        .clk     (clk),
        .wr_en   (imem_wr_en),
        .wr_addr (imem_wr_addr),
        .wr_data (imem_wr_data),
`endif
        ._unused (1'b0)
    );

    // ── Decode + Immediate Generator ─────────────────────────────────────────
    decode u_decode (
        .instr    (instr),
        .opcode   (opcode),
        .funct3   (funct3),
        .funct7_5 (funct7_5),
        .rs1      (rs1_addr),
        .rs2      (rs2_addr),
        .rd       (rd_addr),
        .imm      (imm)
    );

    // ── Control Unit ─────────────────────────────────────────────────────────
    control_unit u_ctrl (
        .opcode     (opcode),
        .funct3     (funct3),
        .funct7_5   (funct7_5),
        .reg_write  (reg_write),
        .alu_src    (alu_src),
        .alu_op     (alu_op),
        .branch     (branch),
        .jump       (jump),
        .jump_src   (jump_src),
        .result_src (result_src),
        .lui_sel    (lui_sel)
    );

    // ── Register File ────────────────────────────────────────────────────────
    reg_file u_regfile (
        .clk       (clk),
        .reg_write (reg_write),
        .rs1_addr  (rs1_addr),
        .rs2_addr  (rs2_addr),
        .rd_addr   (rd_addr),
        .wr_data   (wr_data),
        .rs1_data  (rs1_data),
        .rs2_data  (rs2_data)
    );

    // ── ALU input muxes ──────────────────────────────────────────────────────
    // A: normally rs1, but forced to 0 for LUI (0 + imm = imm)
    // B: rs2 or immediate depending on ALUSrc
    assign alu_a = lui_sel  ? 32'b0   : rs1_data;
    assign alu_b = alu_src  ? imm     : rs2_data;

    // ── Unsigned less-than for BLTU/BGEU ────────────────────────────────────
    // Computed combinationally alongside ALU
    assign alu_ult = (rs1_data < rs2_data);   // unsigned comparison

    // ── ALU ──────────────────────────────────────────────────────────────────
    alu u_alu (
        .a        (alu_a),
        .b        (alu_b),
        .alu_op   (alu_op),
        .result   (alu_result),
        .zero     (alu_zero),
        .negative (alu_neg)
    );

    // ── Branch Logic ─────────────────────────────────────────────────────────
    branch_logic u_branch (
        .funct3       (funct3),
        .zero         (alu_zero),
        .negative     (alu_neg),
        .branch       (branch),
        .ult          (alu_ult),
        .branch_taken (branch_taken)
    );

    // ── Target address adders ────────────────────────────────────────────────
    assign branch_tgt = pc  + imm;              // B-type: PC + sext(imm)
    assign jal_tgt    = pc  + imm;              // J-type: PC + sext(imm) (same adder reuse)
    assign jalr_tgt   = (rs1_data + imm) & ~32'd1;  // I-type: (rs1+imm) & ~1

    // ── PC Multiplexer (4-to-1) ──────────────────────────────────────────────
    always_comb begin
        if (jump) begin
            pc_next = jump_src ? jalr_tgt : jal_tgt;
        end else if (branch_taken) begin
            pc_next = branch_tgt;
        end else begin
            pc_next = pc4;
        end
    end

    // ── Result Multiplexer (write-back data selection) ───────────────────────
    always_comb begin
        unique case (result_src)
            2'b00: wr_data = alu_result;   // Normal ALU result
            2'b01: wr_data = pc4;          // JAL/JALR: link address (PC+4)
            2'b10: wr_data = imm;          // LUI: write upper immediate directly
            default: wr_data = alu_result;
        endcase
    end

    // ── Observation outputs ──────────────────────────────────────────────────
    assign o_pc         = pc;
    assign o_instr      = instr;
    assign o_alu_result = alu_result;
    assign o_reg_a0     = u_regfile.regs[10];   // x10 = a0

endmodule
