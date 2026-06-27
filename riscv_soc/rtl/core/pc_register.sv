// =============================================================================
// Module      : pc_register
// Project     : RISC-V Subset Single-Cycle Processor  (SE-ISA-001)
// Author      : Prabakaran Elaiyappan | SynaptiqEdge Technologies
// Description : 32-bit Program Counter. Synchronous active-low reset.
// =============================================================================

module pc_register (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] pc_next,
    output logic [31:0] pc
);
    always_ff @(posedge clk) begin
        if (!rst_n) pc <= 32'h0000_0000;
        else        pc <= pc_next;
    end
endmodule


// =============================================================================
// Module      : pc_plus4
// Description : Combinational PC+4 incrementer.
// =============================================================================

module pc_plus4 (
    input  logic [31:0] pc,
    output logic [31:0] pc4
);
    assign pc4 = pc + 32'd4;
endmodule
