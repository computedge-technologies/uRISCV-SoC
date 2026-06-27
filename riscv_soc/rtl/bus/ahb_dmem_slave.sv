// =============================================================================
// Module      : ahb_dmem_slave
// Project     : RISC-V SoC  (SE-SOC-001)
// Description : AHB-Lite slave wrapper for the data_mem SRAM.
//               Converts AHB single transfers to synchronous SRAM accesses.
//               Zero wait-state for writes; one wait-state not needed (SRAM
//               async read can return same cycle).
// =============================================================================
module ahb_dmem_slave
    import soc_pkg::*;
(
    input  logic        hclk,
    input  logic        hrst_n,

    // AHB Slave Port
    input  logic [31:0] haddr,
    input  logic [1:0]  htrans,
    input  logic        hwrite,
    input  logic [2:0]  hsize,
    input  logic [31:0] hwdata,
    output logic [31:0] hrdata,
    output logic        hready,
    output logic        hresp
);
    // Registered address-phase signals
    logic [31:0] addr_r;
    logic        write_r;
    logic [2:0]  size_r;
    logic        valid_r;

    always_ff @(posedge hclk or negedge hrst_n) begin
        if (!hrst_n) begin
            addr_r  <= 32'b0;
            write_r <= 1'b0;
            size_r  <= 3'b010;
            valid_r <= 1'b0;
        end else begin
            addr_r  <= haddr;
            write_r <= hwrite;
            size_r  <= hsize;
            valid_r <= (htrans == HTRANS_NONSEQ);
        end
    end

    // Byte enables from size and address offset
    logic [3:0] be;
    always_comb begin
        case (size_r)
            3'b000: be = 4'b0001 << addr_r[1:0];          // byte
            3'b001: be = addr_r[1] ? 4'b1100 : 4'b0011;   // halfword
            default: be = 4'b1111;                          // word
        endcase
    end

    // Instantiate data memory
    data_mem #(.DEPTH(16384), .AWIDTH(14)) u_dmem (
        .clk   (hclk),
        .we    (valid_r & write_r),
        .be    (be),
        .addr  (addr_r[15:2]),
        .wdata (hwdata),
        .rdata (hrdata)
    );

    assign hready = 1'b1;
    assign hresp  = HRESP_OKAY;
endmodule
