// =============================================================================
// Module      : reg_file
// Project     : RISC-V Subset Single-Cycle Processor  (SE-ISA-001)
// Author      : Prabakaran Elaiyappan | SynaptiqEdge Technologies
// Description : 32 × 32-bit register file.
//               Two asynchronous read ports (rs1, rs2).
//               One synchronous write port (rd, posedge clk, RegWrite).
//               x0 is hardwired to 0 — writes to x0 are suppressed.
// =============================================================================

module reg_file (
    input  logic        clk,
    input  logic        reg_write,    // Write enable
    input  logic [4:0]  rs1_addr,     // Read address A
    input  logic [4:0]  rs2_addr,     // Read address B
    input  logic [4:0]  rd_addr,      // Write address
    input  logic [31:0] wr_data,      // Write data
    output logic [31:0] rs1_data,     // Read data A
    output logic [31:0] rs2_data      // Read data B
);

    logic [31:0] regs [0:31];

//     // ── Initialise all registers to 0 (for simulation cleanliness) ──────────
//     initial begin
//         integer i;
//         for (i = 0; i < 32; i++) regs[i] = 32'h0;
//     end

    // ── Synchronous write (x0 write suppressed) ──────────────────────────────
    always_ff @(posedge clk) begin
        if (reg_write && (rd_addr != 5'b0))
            regs[rd_addr] <= wr_data;
    end

    // ── Asynchronous read (x0 always returns 0) ──────────────────────────────
    assign rs1_data = (rs1_addr == 5'b0) ? 32'h0 : regs[rs1_addr];
    assign rs2_data = (rs2_addr == 5'b0) ? 32'h0 : regs[rs2_addr];

endmodule
