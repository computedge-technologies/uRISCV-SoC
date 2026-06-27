// =============================================================================
// Module      : data_mem
// Project     : RISC-V SoC  (SE-SOC-001)
// Description : 32-bit word-addressable data memory (SRAM model).
//               Single read/write port. Synchronous write, async read.
//               Connected to AHB slave interface via ahb_data_mem wrapper.
// =============================================================================
module data_mem #(
    parameter int DEPTH  = 16384,   // 64 KB / 4 bytes
    parameter int AWIDTH = 14
)(
    input  logic              clk,
    input  logic              we,
    input  logic [3:0]        be,           // byte enable
    input  logic [AWIDTH-1:0] addr,
    input  logic [31:0]       wdata,
    output logic [31:0]       rdata
);
    logic [31:0] mem [0:DEPTH-1];

//    initial begin
//        integer i;
//        for (i = 0; i < DEPTH; i++) mem[i] = 32'h0;
//    end

    always_ff @(posedge clk) begin
        if (we) begin
            if (be[0]) mem[addr][7:0]   <= wdata[7:0];
            if (be[1]) mem[addr][15:8]  <= wdata[15:8];
            if (be[2]) mem[addr][23:16] <= wdata[23:16];
            if (be[3]) mem[addr][31:24] <= wdata[31:24];
        end
    end

    assign rdata = mem[addr];
endmodule
