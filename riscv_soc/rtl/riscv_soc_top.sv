// =============================================================================
// Module      : riscv_soc_top
// Project     : RISC-V SoC  (SE-SOC-001)
// Author      : Prabakaran Elaiyappan | SynaptiqEdge Technologies
//
// Description : Top-level SoC integration.
//
//  ┌─────────────────────────────────────────────────────────────┐
//  │                     riscv_soc_top                           │
//  │                                                             │
//  │  ┌───────────────┐    AHB-Lite    ┌─────────────────────┐  │
//  │  │ riscv_core_ext├───────────────►│   ahb_interconnect  │  │
//  │  │  (AHB Master) │◄───────────────┤                     │  │
//  │  └───────────────┘                │  Slave 0: DataMem   │  │
//  │                                   │  Slave 1: APB Bridge│  │
//  │                                   └──────────┬──────────┘  │
//  │                                              │ APB          │
//  │                                   ┌──────────▼──────────┐  │
//  │                                   │  ahb_to_apb_bridge  │  │
//  │                                   └──┬───┬────┬──────┬──┘  │
//  │                                      │   │    │      │      │
//  │                                   UART  I2C  SPI  TIMER    │
//  └─────────────────────────────────────────────────────────────┘
// =============================================================================
module riscv_soc_top
    import soc_pkg::*;
#(
    parameter int IMEM_DEPTH  = 256,
    parameter int IMEM_AWIDTH = 8
)(
    input  logic        clk,
    input  logic        rst_n,

`ifdef SYNTH
    input  logic                    imem_wr_en,
    input  logic [IMEM_AWIDTH-1:0]  imem_wr_addr,
    input  logic [31:0]             imem_wr_data,
`endif

    // ── UART ─────────────────────────────────────────────────────────────────
    output logic        uart_txd,
    input  logic        uart_rxd,

    // ── I2C (open-drain) ──────────────────────────────────────────────────────
    output logic        i2c_scl_oe,
    input  logic        i2c_scl_in,
    output logic        i2c_sda_oe,
    input  logic        i2c_sda_in,

    // ── SPI ───────────────────────────────────────────────────────────────────
    output logic        spi_sck,
    output logic        spi_mosi,
    input  logic        spi_miso,
    output logic        spi_cs_n,

    // ── Interrupts (to RISC-V via future CLIC/PLIC) ───────────────────────────
    output logic        irq_uart_tx,
    output logic        irq_uart_rx,
    output logic        irq_i2c,
    output logic        irq_spi,
    output logic        irq_timer,

    // ── Observation ──────────────────────────────────────────────────────────
    output logic [31:0] o_pc,
    output logic [31:0] o_instr,
    output logic [31:0] o_reg_a0
);

    // ══════════════════════════════════════════════════════════════════════════
    // AHB-Lite bus wires (Master → Interconnect)
    // ══════════════════════════════════════════════════════════════════════════
    logic [31:0] m_haddr, m_hwdata, m_hrdata;
    logic [1:0]  m_htrans;
    logic        m_hwrite, m_hready, m_hresp;
    logic [2:0]  m_hsize, m_hburst;

    // ── Slave 0: Data Memory ──────────────────────────────────────────────────
    logic [31:0] s0_haddr, s0_hwdata, s0_hrdata;
    logic [1:0]  s0_htrans;
    logic        s0_hwrite, s0_hready, s0_hresp;
    logic [2:0]  s0_hsize;

    // ── Slave 1: APB Bridge ───────────────────────────────────────────────────
    logic [31:0] s1_haddr, s1_hwdata, s1_hrdata;
    logic [1:0]  s1_htrans;
    logic        s1_hwrite, s1_hready, s1_hresp;
    logic [2:0]  s1_hsize;

    // ══════════════════════════════════════════════════════════════════════════
    // APB bus wires
    // ══════════════════════════════════════════════════════════════════════════
    logic [31:0] paddr;
    logic        pwrite, penable;
    logic [31:0] pwdata;
    logic [3:0]  psel;

    // Per-slave APB response arrays
    logic [31:0] prdata  [3:0];
    logic        pready  [3:0];
    logic        pslverr [3:0];

    // ══════════════════════════════════════════════════════════════════════════
    // RISC-V Core (AHB Master)
    // ══════════════════════════════════════════════════════════════════════════
    ahb_master_riscv #(
        .IMEM_DEPTH  (IMEM_DEPTH),
        .IMEM_AWIDTH (IMEM_AWIDTH)
    ) u_master (
        .hclk      (clk),
        .hrst_n    (rst_n),
        .haddr     (m_haddr),
        .htrans    (m_htrans),
        .hwrite    (m_hwrite),
        .hsize     (m_hsize),
        .hburst    (m_hburst),
        .hwdata    (m_hwdata),
        .hrdata    (m_hrdata),
        .hready    (m_hready),
        .hresp     (m_hresp),
        .o_pc      (o_pc),
        .o_instr   (o_instr),
        .o_reg_a0  (o_reg_a0),
`ifdef SYNTH
        .imem_wr_en   (imem_wr_en),
        .imem_wr_addr (imem_wr_addr),
        .imem_wr_data (imem_wr_data),
`endif
        .o_uart_tx_req  (),
        .o_uart_tx_byte ()
    );

    // ══════════════════════════════════════════════════════════════════════════
    // AHB Interconnect
    // ══════════════════════════════════════════════════════════════════════════
    ahb_interconnect u_ic (
        .hclk    (clk),    .hrst_n  (rst_n),
        .m_haddr (m_haddr), .m_htrans(m_htrans), .m_hwrite(m_hwrite),
        .m_hsize (m_hsize), .m_hburst(m_hburst), .m_hwdata(m_hwdata),
        .m_hrdata(m_hrdata),.m_hready(m_hready), .m_hresp (m_hresp),
        .s0_haddr(s0_haddr),.s0_htrans(s0_htrans),.s0_hwrite(s0_hwrite),
        .s0_hsize(s0_hsize),.s0_hwdata(s0_hwdata),.s0_hrdata(s0_hrdata),
        .s0_hready(s0_hready),.s0_hresp(s0_hresp),
        .s1_haddr(s1_haddr),.s1_htrans(s1_htrans),.s1_hwrite(s1_hwrite),
        .s1_hsize(s1_hsize),.s1_hwdata(s1_hwdata),.s1_hrdata(s1_hrdata),
        .s1_hready(s1_hready),.s1_hresp(s1_hresp)
    );

    // ══════════════════════════════════════════════════════════════════════════
    // Slave 0: Data Memory
    // ══════════════════════════════════════════════════════════════════════════
    ahb_dmem_slave u_dmem (
        .hclk   (clk),    .hrst_n (rst_n),
        .haddr  (s0_haddr),.htrans(s0_htrans),.hwrite(s0_hwrite),
        .hsize  (s0_hsize),.hwdata(s0_hwdata),
        .hrdata (s0_hrdata),.hready(s0_hready),.hresp(s0_hresp)
    );

    // ══════════════════════════════════════════════════════════════════════════
    // Slave 1: AHB-to-APB Bridge
    // ══════════════════════════════════════════════════════════════════════════
    ahb_to_apb_bridge #(.N_SLAVES(4)) u_bridge (
        .hclk  (clk),    .hrst_n(rst_n),
        .haddr (s1_haddr),.htrans(s1_htrans),.hwrite(s1_hwrite),
        .hsize (s1_hsize),.hwdata(s1_hwdata),
        .hrdata(s1_hrdata),.hready(s1_hready),.hresp(s1_hresp),
        .paddr  (paddr),  .pwrite(pwrite), .pwdata(pwdata),
        .psel   (psel),   .penable(penable),
        .prdata (prdata), .pready(pready),  .pslverr(pslverr)
    );

    // ══════════════════════════════════════════════════════════════════════════
    // APB Peripheral 0 : UART
    // ══════════════════════════════════════════════════════════════════════════
    uart_apb u_uart (
        .pclk(clk), .prst_n(rst_n),
        .paddr(paddr[11:0]), .psel(psel[0]), .penable(penable),
        .pwrite(pwrite), .pwdata(pwdata),
        .prdata(prdata[0]), .pready(pready[0]), .pslverr(pslverr[0]),
        .txd(uart_txd), .rxd(uart_rxd),
        .irq_tx_empty(irq_uart_tx), .irq_rx_valid(irq_uart_rx)
    );

    // ══════════════════════════════════════════════════════════════════════════
    // APB Peripheral 1 : I2C
    // ══════════════════════════════════════════════════════════════════════════
    i2c_apb u_i2c (
        .pclk(clk), .prst_n(rst_n),
        .paddr(paddr[11:0]), .psel(psel[1]), .penable(penable),
        .pwrite(pwrite), .pwdata(pwdata),
        .prdata(prdata[1]), .pready(pready[1]), .pslverr(pslverr[1]),
        .scl_oe(i2c_scl_oe), .scl_in(i2c_scl_in),
        .sda_oe(i2c_sda_oe), .sda_in(i2c_sda_in),
        .irq(irq_i2c)
    );

    // ══════════════════════════════════════════════════════════════════════════
    // APB Peripheral 2 : SPI
    // ══════════════════════════════════════════════════════════════════════════
    spi_apb u_spi (
        .pclk(clk), .prst_n(rst_n),
        .paddr(paddr[11:0]), .psel(psel[2]), .penable(penable),
        .pwrite(pwrite), .pwdata(pwdata),
        .prdata(prdata[2]), .pready(pready[2]), .pslverr(pslverr[2]),
        .sck(spi_sck), .mosi(spi_mosi), .miso(spi_miso), .cs_n(spi_cs_n),
        .irq(irq_spi)
    );

    // ══════════════════════════════════════════════════════════════════════════
    // APB Peripheral 3 : TIMER
    // ══════════════════════════════════════════════════════════════════════════
    timer_apb u_timer (
        .pclk(clk), .prst_n(rst_n),
        .paddr(paddr[11:0]), .psel(psel[3]), .penable(penable),
        .pwrite(pwrite), .pwdata(pwdata),
        .prdata(prdata[3]), .pready(pready[3]), .pslverr(pslverr[3]),
        .irq(irq_timer)
    );

endmodule
