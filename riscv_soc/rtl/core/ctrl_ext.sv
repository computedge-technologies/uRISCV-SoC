// =============================================================================
// Module      : ctrl_ext
// Project     : RISC-V SoC  (SE-SOC-001)
// Description : Extended control unit adding load/store decode to SE-ISA-001.
// =============================================================================
module ctrl_ext
    import riscv_pkg::*;
(
    input  logic [6:0] opcode,
    input  logic [2:0] funct3,
    input  logic       funct7_5,

    output logic        reg_write,
    output logic        alu_src,
    output logic [3:0]  alu_op,
    output logic        branch,
    output logic        jump,
    output logic        jump_src,
    output logic [1:0]  result_src,
    output logic        lui_sel,
    output logic        is_load,
    output logic        is_store
);
    always_comb begin
        reg_write  = 0; alu_src = 0; alu_op = ALU_ADD;
        branch     = 0; jump    = 0; jump_src = 0;
        result_src = 0; lui_sel = 0;
        is_load    = 0; is_store = 0;

        case (opcode)
            OP_R: begin
                reg_write = 1; alu_src = 0;
                alu_op    = {funct7_5, funct3};
            end
            OP_I: begin
                reg_write = 1; alu_src = 1;
                alu_op    = {funct7_5, funct3};
            end
            7'b0000011: begin   // LOAD: LB LH LW LBU LHU
                reg_write  = 1; alu_src = 1;
                alu_op     = ALU_ADD;
                result_src = 2'b11;   // load data
                is_load    = 1;
            end
            7'b0100011: begin   // STORE: SB SH SW
                reg_write  = 0; alu_src = 1;
                alu_op     = ALU_ADD;
                is_store   = 1;
            end
            OP_BR: begin
                branch = 1; alu_src = 0; alu_op = ALU_SUB;
            end
            OP_JAL: begin
                reg_write  = 1; jump = 1; jump_src = 0;
                result_src = 2'b01;
            end
            OP_JALR: begin
                reg_write  = 1; alu_src = 1; alu_op = ALU_ADD;
                jump = 1; jump_src = 1; result_src = 2'b01;
            end
            OP_LUI: begin
                reg_write  = 1; alu_src = 1; alu_op = ALU_ADD;
                result_src = 2'b10; lui_sel = 1;
            end
            OP_AUIPC: begin
                reg_write  = 1; alu_src = 1; alu_op = ALU_ADD;
            end
            default:;
        endcase
    end
endmodule
