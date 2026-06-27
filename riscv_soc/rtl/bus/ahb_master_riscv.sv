// =============================================================================
// Module      : ahb_master_riscv
// Project     : RISC-V SoC  (SE-SOC-001)
// Author      : Prabakaran Elaiyappan | SynaptiqEdge Technologies
//
// Description : AHB-Lite master wrapper for riscv_core_ext.
//               Converts single-cycle dmem_req into AHB NONSEQ transfers.
//
// Pipeline:
//   Cycle N  : core issues dmem_req, addr, we, wdata. stall goes HIGH.
//              We latch addr/we/size. Transition IDLE→ADDR.
//   Cycle N+1: Drive HADDR/HTRANS/HWRITE. Still stalled.
//              Transition ADDR→DATA.
//   Cycle N+2: Drive HWDATA (for writes). hready=1 → transaction done.
//              Stall drops. Core resumes.
// =============================================================================
module ahb_master_riscv
    import soc_pkg::*;
    import riscv_pkg::*;
#(
    parameter int IMEM_DEPTH  = 256,
    parameter int IMEM_AWIDTH = 8
)(
    input  logic        hclk,
    input  logic        hrst_n,
    output logic [31:0] haddr,
    output logic [1:0]  htrans,
    output logic        hwrite,
    output logic [2:0]  hsize,
    output logic [2:0]  hburst,
    output logic [31:0] hwdata,
    input  logic [31:0] hrdata,
    input  logic        hready,
    input  logic        hresp,
    output logic [31:0] o_pc,
    output logic [31:0] o_instr,
    output logic [31:0] o_reg_a0,
`ifdef SYNTH
    input  logic                    imem_wr_en,
    input  logic [IMEM_AWIDTH-1:0]  imem_wr_addr,
    input  logic [31:0]             imem_wr_data,
`endif
    output logic        o_uart_tx_req,
    output logic [7:0]  o_uart_tx_byte
);
    logic core_dreq, core_dwe;
    logic [1:0]  core_dsize;
    logic [31:0] core_daddr, core_dwdata, core_drdata;
    logic        core_stall;

    riscv_core_ext #(
        .MEM_DEPTH  (IMEM_DEPTH),
        .MEM_AWIDTH (IMEM_AWIDTH)
    ) u_core (
        .clk(hclk), .rst_n(hrst_n), .stall(core_stall),
`ifdef SYNTH
        .imem_wr_en(imem_wr_en), .imem_wr_addr(imem_wr_addr), .imem_wr_data(imem_wr_data),
`endif
        .dmem_req(core_dreq), .dmem_we(core_dwe), .dmem_size(core_dsize),
        .dmem_addr(core_daddr), .dmem_wdata(core_dwdata), .dmem_rdata(core_drdata),
        .o_pc(o_pc), .o_instr(o_instr), .o_reg_a0(o_reg_a0)
    );
    assign core_drdata = hrdata;

    // ── State machine ─────────────────────────────────────────────────────────
    localparam logic [1:0] S_IDLE=2'b00, S_ADDR=2'b01, S_DATA=2'b10;
    logic [1:0] st;

    // Latched transaction info — captured when request first seen
    logic [31:0] lat_addr;
    logic        lat_we;
    logic [2:0]  lat_size;
    logic [31:0] lat_wdata;

    always_ff @(posedge hclk or negedge hrst_n) begin
        if (!hrst_n) begin
            st       <= S_IDLE;
            lat_addr <= 32'b0; lat_we <= 1'b0;
            lat_size <= 3'b010; lat_wdata <= 32'b0;
        end else begin
            case (st)
                S_IDLE: begin
                    if (core_dreq) begin
                        // Latch everything immediately
                        lat_addr  <= core_daddr;
                        lat_we    <= core_dwe;
                        lat_size  <= {1'b0, core_dsize};
                        lat_wdata <= core_dwdata;
                        st        <= S_ADDR;
                    end
                end
                S_ADDR: begin
                    // Address phase: HADDR driven. Move to data phase.
                    st <= S_DATA;
                end
                S_DATA: begin
                    // Data phase: HWDATA driven, wait for hready
                    if (hready) begin
                        if (core_dreq) begin
                            // Back-to-back: latch next immediately
                            lat_addr  <= core_daddr;
                            lat_we    <= core_dwe;
                            lat_size  <= {1'b0, core_dsize};
                            lat_wdata <= core_dwdata;
                            st        <= S_ADDR;
                        end else
                            st <= S_IDLE;
                    end
                end
                default: st <= S_IDLE;
            endcase
        end
    end

    // ── AHB output ────────────────────────────────────────────────────────────
    always_comb begin
        haddr  = 32'b0;
        htrans = HTRANS_IDLE;
        hwrite = 1'b0;
        hsize  = HSIZE_WORD;
        hburst = HBURST_SINGLE;
        hwdata = 32'b0;
        case (st)
            S_ADDR: begin
                haddr  = lat_addr;
                htrans = HTRANS_NONSEQ;
                hwrite = lat_we;
                hsize  = lat_size;
            end
            S_DATA: begin
                haddr  = lat_addr;
                htrans = HTRANS_IDLE;
                hwrite = lat_we;
                hsize  = lat_size;
                hwdata = lat_wdata;
            end
            default:;
        endcase
    end

    // Stall the core while the AHB transaction is in flight
    assign core_stall = (st == S_ADDR) || (st == S_DATA && !hready);

    assign o_uart_tx_req  = 1'b0;
    assign o_uart_tx_byte = 8'b0;

endmodule
