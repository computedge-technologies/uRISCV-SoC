// =============================================================================
// Module      : ahb_interconnect
// Project     : RISC-V SoC  (SE-SOC-001)
// Author      : Prabakaran Elaiyappan | SynaptiqEdge Technologies
//
// Description : Simple 1-master, 2-slave AHB-Lite interconnect.
//               Slave 0 : Data Memory  (0x2000_0000 – 0x2000_FFFF)
//               Slave 1 : APB Bridge   (0x4000_0000 – 0x4000_FFFF)
//
//               Address decode is purely combinational. Only SINGLE transfers
//               supported. No arbitration needed (single master).
// =============================================================================
module ahb_interconnect
    import soc_pkg::*;
(
    input  logic        hclk,
    input  logic        hrst_n,

    // ── From Master (RISC-V AHB wrapper) ─────────────────────────────────────
    input  logic [31:0] m_haddr,
    input  logic [1:0]  m_htrans,
    input  logic        m_hwrite,
    input  logic [2:0]  m_hsize,
    input  logic [2:0]  m_hburst,
    input  logic [31:0] m_hwdata,
    output logic [31:0] m_hrdata,
    output logic        m_hready,
    output logic        m_hresp,

    // ── To Slave 0: Data Memory ───────────────────────────────────────────────
    output logic [31:0] s0_haddr,
    output logic [1:0]  s0_htrans,
    output logic        s0_hwrite,
    output logic [2:0]  s0_hsize,
    output logic [31:0] s0_hwdata,
    input  logic [31:0] s0_hrdata,
    input  logic        s0_hready,
    input  logic        s0_hresp,

    // ── To Slave 1: APB Bridge ────────────────────────────────────────────────
    output logic [31:0] s1_haddr,
    output logic [1:0]  s1_htrans,
    output logic        s1_hwrite,
    output logic [2:0]  s1_hsize,
    output logic [31:0] s1_hwdata,
    input  logic [31:0] s1_hrdata,
    input  logic        s1_hready,
    input  logic        s1_hresp
);

    // ── Address decode (registered to match AHB pipeline) ────────────────────
    // The address phase is presented one cycle before the data phase.
    // We register the slave select from the address phase and use it
    // in the data phase to steer HRDATA/HREADY back to the master.

    logic sel_s0, sel_s1, sel_none;   // address-phase decode
    logic sel_s0_d, sel_s1_d;         // data-phase decode (registered)

    // Combinational decode of HADDR
    always_comb begin
        sel_s0   = ((m_haddr & DMEM_MASK) == (DMEM_BASE & DMEM_MASK)) &&
                   (m_htrans == HTRANS_NONSEQ);
        sel_s1   = ((m_haddr & APB_REGION_MASK) == (APB_REGION_BASE & APB_REGION_MASK)) &&
                   (m_htrans == HTRANS_NONSEQ);
        sel_none = ~sel_s0 & ~sel_s1;
    end

    // Register slave select for data phase
    always_ff @(posedge hclk or negedge hrst_n) begin
        if (!hrst_n) begin
            sel_s0_d <= 1'b0;
            sel_s1_d <= 1'b0;
        end else if (m_hready) begin
            sel_s0_d <= sel_s0;
            sel_s1_d <= sel_s1;
        end
    end

    // ── Fan-out address/control to all slaves ─────────────────────────────────
    // Each slave only acts when its HTRANS is NONSEQ
    assign s0_haddr  = m_haddr;
    assign s0_htrans = sel_s0 ? m_htrans : HTRANS_IDLE;
    assign s0_hwrite = m_hwrite;
    assign s0_hsize  = m_hsize;
    assign s0_hwdata = m_hwdata;

    assign s1_haddr  = m_haddr;
    assign s1_htrans = sel_s1 ? m_htrans : HTRANS_IDLE;
    assign s1_hwrite = m_hwrite;
    assign s1_hsize  = m_hsize;
    assign s1_hwdata = m_hwdata;

    // ── Steer HRDATA and HREADY back to master using data-phase select ────────
    always_comb begin
        if (sel_s0_d) begin
            m_hrdata = s0_hrdata;
            m_hready = s0_hready;
            m_hresp  = s0_hresp;
        end else if (sel_s1_d) begin
            m_hrdata = s1_hrdata;
            m_hready = s1_hready;
            m_hresp  = s1_hresp;
        end else begin
            m_hrdata = 32'hDEAD_BEEF;   // default: no slave selected
            m_hready = 1'b1;
            m_hresp  = HRESP_OKAY;
        end
    end

endmodule
