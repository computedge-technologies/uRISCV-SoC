// =============================================================================
// Package     : soc_pkg
// Project     : RISC-V SoC  (SE-SOC-001)
// Author      : Prabakaran Elaiyappan | SynaptiqEdge Technologies
// Description : SoC-wide constants: address map, bus widths, APB/AHB defs.
// =============================================================================

package soc_pkg;

    // ── Bus widths ────────────────────────────────────────────────────────────
    localparam int ADDR_W  = 32;
    localparam int DATA_W  = 32;

    // ── AHB HTRANS encoding ───────────────────────────────────────────────────
    localparam logic [1:0] HTRANS_IDLE   = 2'b00;
    localparam logic [1:0] HTRANS_BUSY   = 2'b01;
    localparam logic [1:0] HTRANS_NONSEQ = 2'b10;
    localparam logic [1:0] HTRANS_SEQ    = 2'b11;

    // ── AHB HBURST (only SINGLE used) ────────────────────────────────────────
    localparam logic [2:0] HBURST_SINGLE = 3'b000;

    // ── AHB HSIZE ─────────────────────────────────────────────────────────────
    localparam logic [2:0] HSIZE_BYTE = 3'b000;
    localparam logic [2:0] HSIZE_HALF = 3'b001;
    localparam logic [2:0] HSIZE_WORD = 3'b010;

    // ── AHB HRESP ─────────────────────────────────────────────────────────────
    localparam logic HRESP_OKAY  = 1'b0;
    localparam logic HRESP_ERROR = 1'b1;

    // =========================================================================
    // Address Map
    //  0x0000_0000 – 0x0000_FFFF   Instruction Memory (64 KB, internal)
    //  0x2000_0000 – 0x2000_FFFF   Data Memory        (64 KB)
    //  0x4000_0000 – 0x4000_0FFF   UART0
    //  0x4000_1000 – 0x4000_1FFF   I2C0
    //  0x4000_2000 – 0x4000_2FFF   SPI0
    //  0x4000_3000 – 0x4000_3FFF   TIMER0
    // =========================================================================

    localparam logic [31:0] UART_BASE   = 32'h4000_0000;
    localparam logic [31:0] I2C_BASE    = 32'h4000_1000;
    localparam logic [31:0] SPI_BASE    = 32'h4000_2000;
    localparam logic [31:0] TIMER_BASE  = 32'h4000_3000;
    localparam logic [31:0] DMEM_BASE   = 32'h2000_0000;

    // Anything 0x4000_xxxx → APB bridge
    localparam logic [31:0] APB_REGION_BASE = 32'h4000_0000;
    localparam logic [31:0] APB_REGION_MASK = 32'hFFFF_0000;
    localparam logic [31:0] DMEM_MASK        = 32'hFFFF_0000;

    // ── UART Register Offsets ─────────────────────────────────────────────────
    localparam logic [11:0] UART_TDR  = 12'h00;
    localparam logic [11:0] UART_RDR  = 12'h04;
    localparam logic [11:0] UART_CTRL = 12'h08;
    localparam logic [11:0] UART_STAT = 12'h0C;
    localparam logic [11:0] UART_BAUD = 12'h10;

    // ── I2C Register Offsets ──────────────────────────────────────────────────
    localparam logic [11:0] I2C_CTRL  = 12'h00;
    localparam logic [11:0] I2C_STAT  = 12'h04;
    localparam logic [11:0] I2C_ADDR  = 12'h08;
    localparam logic [11:0] I2C_TDR   = 12'h0C;
    localparam logic [11:0] I2C_RDR   = 12'h10;
    localparam logic [11:0] I2C_PRESC = 12'h14;

    // ── SPI Register Offsets ──────────────────────────────────────────────────
    localparam logic [11:0] SPI_CTRL  = 12'h00;
    localparam logic [11:0] SPI_STAT  = 12'h04;
    localparam logic [11:0] SPI_TDR   = 12'h08;
    localparam logic [11:0] SPI_RDR   = 12'h0C;
    localparam logic [11:0] SPI_PRESC = 12'h10;

    // ── TIMER Register Offsets ────────────────────────────────────────────────
    localparam logic [11:0] TIMER_CTRL = 12'h00;
    localparam logic [11:0] TIMER_LOAD = 12'h04;
    localparam logic [11:0] TIMER_CNT  = 12'h08;
    localparam logic [11:0] TIMER_STAT = 12'h0C;

endpackage
