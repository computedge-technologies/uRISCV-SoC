// =============================================================================
// Module      : ahb_to_apb_bridge
// Project     : RISC-V SoC  (SE-SOC-001)
// Author      : Prabakaran Elaiyappan | SynaptiqEdge Technologies
//
// Description : AHB-Lite to APB bridge.
//               Converts AHB NONSEQ single transfers into APB 2-phase
//               (SETUP → ENABLE) transactions. Inserts one wait state on
//               the AHB side during the APB transaction.
//
//               APB slave decode (4 KB each, based on HADDR[15:12]):
//                 0000 → UART0   0x4000_0xxx
//                 0001 → I2C0    0x4000_1xxx
//                 0010 → SPI0    0x4000_2xxx
//                 0011 → TIMER0  0x4000_3xxx
//
// APB FSM:
//   IDLE  → AHB request arrives → latch address/data
//   SETUP → Assert PSEL, deassert PENABLE (setup phase, 1 cycle)
//   ENABLE→ Assert PSEL + PENABLE (access phase, 1 cycle)
//           Sample PRDATA/PREADY → return HRDATA, deassert HREADY
// =============================================================================
module ahb_to_apb_bridge
    import soc_pkg::*;
#(
    parameter int N_SLAVES = 4    // UART, I2C, SPI, TIMER
)(
    input  logic        hclk,
    input  logic        hrst_n,

    // ── AHB Slave Port ────────────────────────────────────────────────────────
    input  logic [31:0] haddr,
    input  logic [1:0]  htrans,
    input  logic        hwrite,
    input  logic [2:0]  hsize,
    input  logic [31:0] hwdata,
    output logic [31:0] hrdata,
    output logic        hready,
    output logic        hresp,

    // ── APB Master Port (broadcast to all slaves) ─────────────────────────────
    output logic [31:0]         paddr,
    output logic                pwrite,
    output logic [31:0]         pwdata,
    output logic [N_SLAVES-1:0] psel,    // one-hot slave select
    output logic                penable,
    input  logic [31:0]         prdata [N_SLAVES-1:0],
    input  logic                pready [N_SLAVES-1:0],
    input  logic                pslverr[N_SLAVES-1:0]
);

    // ── State machine ─────────────────────────────────────────────────────────
        localparam logic [1:0] APB_IDLE = 2'b00;
    localparam logic [1:0] APB_SETUP = 2'b01;
    localparam logic [1:0] APB_ENABLE = 2'b10;

    logic [1:0] state, state_nxt;

    // Latched AHB transaction
    logic [31:0] lat_haddr;
    logic        lat_hwrite;
    logic [31:0] lat_hwdata;
    logic [N_SLAVES-1:0] lat_psel;

    // AHB request: only NONSEQ and not idle
    logic ahb_req;
    assign ahb_req = (htrans == HTRANS_NONSEQ);

    // ── Slave select decode from HADDR[15:12] ────────────────────────────────
    function automatic logic [N_SLAVES-1:0] decode_sel(input logic [31:0] addr);
        case (addr[15:12])
            4'h0: decode_sel = 4'b0001;   // UART
            4'h1: decode_sel = 4'b0010;   // I2C
            4'h2: decode_sel = 4'b0100;   // SPI
            4'h3: decode_sel = 4'b1000;   // TIMER
            default: decode_sel = 4'b0000;
        endcase
    endfunction

    // ── State register ────────────────────────────────────────────────────────
    always_ff @(posedge hclk or negedge hrst_n) begin
        if (!hrst_n) state <= APB_IDLE;
        else         state <= state_nxt;
    end

    // ── Latch AHB address phase ───────────────────────────────────────────────
    always_ff @(posedge hclk or negedge hrst_n) begin
        if (!hrst_n) begin
            lat_haddr  <= 32'b0;
            lat_hwrite <= 1'b0;
            lat_hwdata <= 32'b0;
            lat_psel   <= '0;
        end else if (state == APB_IDLE && ahb_req) begin
            lat_haddr  <= haddr;
            lat_hwrite <= hwrite;
            lat_psel   <= decode_sel(haddr);
        end else if (state == APB_SETUP) begin
            // Capture write data in setup phase (AHB data phase)
            lat_hwdata <= hwdata;
        end
    end

    // ── Active slave index (one-hot to binary) ────────────────────────────────
    logic [$clog2(N_SLAVES)-1:0] active_slave;
    always_comb begin
        active_slave = '0;
        for (int i = 0; i < N_SLAVES; i++)
            if (lat_psel[i]) active_slave = i[$clog2(N_SLAVES)-1:0];
    end

    // ── Next-state logic ──────────────────────────────────────────────────────
    always_comb begin
        state_nxt = state;
        case (state)
            APB_IDLE:   if (ahb_req)                          state_nxt = APB_SETUP;
            APB_SETUP:                                         state_nxt = APB_ENABLE;
            APB_ENABLE: if (pready[active_slave])              state_nxt = APB_IDLE;
            default:    state_nxt = APB_IDLE;
        endcase
    end

    // ── APB output drive ──────────────────────────────────────────────────────
    always_comb begin
        paddr   = lat_haddr;
        pwrite  = lat_hwrite;
        pwdata  = lat_hwdata;
        psel    = '0;
        penable = 1'b0;

        case (state)
            APB_SETUP: begin
                psel    = lat_psel;
                penable = 1'b0;
            end
            APB_ENABLE: begin
                psel    = lat_psel;
                penable = 1'b1;
            end
            default:;
        endcase
    end

    // ── AHB response ──────────────────────────────────────────────────────────
    always_comb begin
        hrdata = prdata[active_slave];
        hresp  = pslverr[active_slave] ? HRESP_ERROR : HRESP_OKAY;

        case (state)
            APB_IDLE:   hready = 1'b1;
            APB_SETUP:  hready = 1'b0;   // hold AHB master
            APB_ENABLE: hready = pready[active_slave];
            default:    hready = 1'b1;
        endcase
    end

endmodule
