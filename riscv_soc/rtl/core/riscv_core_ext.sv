// =============================================================================
// Module      : riscv_core_ext
// Project     : RISC-V SoC  (SE-SOC-001)
// Author      : Prabakaran Elaiyappan | SynaptiqEdge Technologies
//
// Description : Extended single-cycle RISC-V core with:
//               - Load/Store instructions (LW SW LB SB LH SH LBU LHU)
//               - External data memory port (drives AHB master wrapper)
//               - Stall input for bus wait-state insertion
//
// New instructions added vs SE-ISA-001:
//   LW  rd, imm(rs1)   — load  word
//   LH  rd, imm(rs1)   — load  halfword (sign-extended)
//   LB  rd, imm(rs1)   — load  byte     (sign-extended)
//   LHU rd, imm(rs1)   — load  halfword (zero-extended)
//   LBU rd, imm(rs1)   — load  byte     (zero-extended)
//   SW  rs2, imm(rs1)  — store word
//   SH  rs2, imm(rs1)  — store halfword
//   SB  rs2, imm(rs1)  — store byte
// =============================================================================
module riscv_core_ext #(
    parameter int MEM_DEPTH  = 256,
    parameter int MEM_AWIDTH = 8
)(
    input  logic clk,
    input  logic rst_n,
    input  logic stall,       // 1 = freeze PC and register write

`ifdef SYNTH
    input  logic                   imem_wr_en,
    input  logic [MEM_AWIDTH-1:0]  imem_wr_addr,
    input  logic [31:0]            imem_wr_data,
`endif

    // ── Data memory port (to AHB master wrapper) ─────────────────────────────
    output logic        dmem_req,
    output logic        dmem_we,
    output logic [1:0]  dmem_size,   // 00=byte 01=half 10=word
    output logic [31:0] dmem_addr,
    output logic [31:0] dmem_wdata,
    input  logic [31:0] dmem_rdata,

    // ── Observation ──────────────────────────────────────────────────────────
    output logic [31:0] o_pc,
    output logic [31:0] o_instr,
    output logic [31:0] o_reg_a0
);

    import riscv_pkg::*;

    // ── Internal wires ────────────────────────────────────────────────────────
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
    logic [31:0] branch_tgt, jalr_tgt;
    logic [31:0] wr_data;

    // Load/store control
    logic        is_load, is_store;
    logic [31:0] load_data;

    // ── PC Register (stall-aware) ─────────────────────────────────────────────
    always_ff @(posedge clk) begin
        if (!rst_n)       pc <= 32'h0;
        else if (!stall)  pc <= pc_next;
    end

    pc_plus4 u_pc4 (.pc(pc), .pc4(pc4));

    // ── Instruction Memory ────────────────────────────────────────────────────
    instr_mem #(.DEPTH(MEM_DEPTH),.AWIDTH(MEM_AWIDTH)) u_imem (
        .pc     (pc),
        .instr  (instr),
`ifdef SYNTH
        .clk      (clk),
        .wr_en    (imem_wr_en),
        .wr_addr  (imem_wr_addr),
        .wr_data  (imem_wr_data),
`endif
        ._unused(1'b0)
    );

    // ── Decode ────────────────────────────────────────────────────────────────
    decode u_decode (
        .instr(instr), .opcode(opcode), .funct3(funct3),
        .funct7_5(funct7_5), .rs1(rs1_addr), .rs2(rs2_addr),
        .rd(rd_addr), .imm(imm)
    );

    // ── Extended Control Unit ─────────────────────────────────────────────────
    ctrl_ext u_ctrl (
        .opcode(opcode), .funct3(funct3), .funct7_5(funct7_5),
        .reg_write(reg_write), .alu_src(alu_src), .alu_op(alu_op),
        .branch(branch), .jump(jump), .jump_src(jump_src),
        .result_src(result_src), .lui_sel(lui_sel),
        .is_load(is_load), .is_store(is_store)
    );

    // ── Register File (stall-aware write) ────────────────────────────────────
    reg_file u_regfile (
        .clk(clk),
        .reg_write(reg_write & ~stall),
        .rs1_addr(rs1_addr), .rs2_addr(rs2_addr), .rd_addr(rd_addr),
        .wr_data(wr_data),
        .rs1_data(rs1_data), .rs2_data(rs2_data)
    );

    assign alu_a   = lui_sel ? 32'b0 : rs1_data;
    assign alu_b   = alu_src ? imm   : rs2_data;
    assign alu_ult = (rs1_data < rs2_data);

    alu u_alu (
        .a(alu_a), .b(alu_b), .alu_op(alu_op),
        .result(alu_result), .zero(alu_zero), .negative(alu_neg)
    );

    branch_logic u_branch (
        .funct3(funct3), .zero(alu_zero), .negative(alu_neg),
        .branch(branch), .ult(alu_ult), .branch_taken(branch_taken)
    );

    assign branch_tgt = pc + imm;
    assign jalr_tgt   = (rs1_data + imm) & ~32'd1;

    always_comb begin
        if      (jump)         pc_next = jump_src ? jalr_tgt : (pc + imm);
        else if (branch_taken) pc_next = branch_tgt;
        else                   pc_next = pc4;
    end

    // ── Data memory interface ─────────────────────────────────────────────────
    // ALU result is the effective address for loads/stores
    // dmem_req fires once per new instruction; dmem_pending prevents re-issue
    logic dmem_pending;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)          dmem_pending <= 1'b0;
        else if (!stall)     dmem_pending <= 1'b0;  // cleared when stall drops
        else if (dmem_req)   dmem_pending <= 1'b1;  // set when first issued
    end
    assign dmem_req = (is_load | is_store) & ~stall & ~dmem_pending;
    assign dmem_we    = is_store;
    assign dmem_addr  = alu_result;
    assign dmem_wdata = rs2_data;

    // funct3 determines transfer size: 00=byte 01=half 10=word
    assign dmem_size  = funct3[1] ? (funct3[0] ? 2'b11 : 2'b10) : (funct3[0] ? 2'b01 : 2'b00);

    // ── Load data sign/zero extension ────────────────────────────────────────
    always_comb begin
        case (funct3)
            3'b000: load_data = {{24{dmem_rdata[7]}},  dmem_rdata[7:0]};   // LB
            3'b001: load_data = {{16{dmem_rdata[15]}}, dmem_rdata[15:0]};  // LH
            3'b010: load_data = dmem_rdata;                                 // LW
            3'b100: load_data = {24'b0, dmem_rdata[7:0]};                  // LBU
            3'b101: load_data = {16'b0, dmem_rdata[15:0]};                 // LHU
            default: load_data = dmem_rdata;
        endcase
    end

    // ── Result MUX ───────────────────────────────────────────────────────────
    always_comb begin
        case (result_src)
            2'b00:   wr_data = alu_result;
            2'b01:   wr_data = pc4;
            2'b10:   wr_data = imm;
            2'b11:   wr_data = load_data;   // load from memory
            default: wr_data = alu_result;
        endcase
    end

    // ── Outputs ───────────────────────────────────────────────────────────────
    assign o_pc      = pc;
    assign o_instr   = instr;
    assign o_reg_a0  = u_regfile.regs[10];

endmodule
