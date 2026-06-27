// =============================================================================
// Module      : uart_apb
// Project     : RISC-V SoC  (SE-SOC-001)
// Author      : Prabakaran Elaiyappan | SynaptiqEdge Technologies
//
// Description : APB UART — 8N1, programmable baud, TX/RX with status polling.
//
// Register Map (APB byte offsets):
//   0x00  TDR   [7:0]  TX Data Register (write to transmit)
//   0x04  RDR   [7:0]  RX Data Register (read received byte)
//   0x08  CTRL  [1:0]  [0]=TX_EN  [1]=RX_EN
//   0x0C  STAT  [3:0]  [0]=TX_BUSY  [1]=TX_FULL  [2]=RX_VALID  [3]=RX_OVR
//   0x10  BAUD  [15:0] Baud divisor: bit_period = clk*(BAUD+1)
// =============================================================================
module uart_apb
    import soc_pkg::*;
(
    input  logic        pclk,
    input  logic        prst_n,
    input  logic [11:0] paddr,
    input  logic        psel,
    input  logic        penable,
    input  logic        pwrite,
    input  logic [31:0] pwdata,
    output logic [31:0] prdata,
    output logic        pready,
    output logic        pslverr,
    output logic        txd,
    input  logic        rxd,
    output logic        irq_tx_empty,
    output logic        irq_rx_valid
);

    // ── Registers ─────────────────────────────────────────────────────────────
    logic [1:0]  ctrl;       // [0]=TX_EN [1]=RX_EN
    logic [15:0] baud_div;   // baud rate divisor
    logic [7:0]  rdr;        // received byte

    // Status bits — all driven from one always_ff
    logic tx_busy, tx_buf_full, rx_valid, rx_ovr;

    assign irq_tx_empty = ~tx_busy & ~tx_buf_full;
    assign irq_rx_valid  = rx_valid;

    // ── Baud tick ─────────────────────────────────────────────────────────────
    logic [15:0] baud_cnt;
    logic        baud_tick;
    always_ff @(posedge pclk or negedge prst_n) begin
        if (!prst_n) begin baud_cnt <= 0; baud_tick <= 0; end
        else if (baud_cnt == baud_div) begin baud_cnt <= 0; baud_tick <= 1; end
        else begin baud_cnt <= baud_cnt + 1; baud_tick <= 0; end
    end

    // ── TX logic ──────────────────────────────────────────────────────────────
    logic [9:0]  tx_shift;
    logic [3:0]  tx_bit_cnt;
    logic [7:0]  tx_buf;
    logic        txd_r;

    // APB write to TDR
    wire apb_wr_tdr = psel & penable & pwrite & (paddr == UART_TDR);

    always_ff @(posedge pclk or negedge prst_n) begin
        if (!prst_n) begin
            tx_shift    <= 10'h3FF;
            tx_bit_cnt  <= 0;
            tx_busy     <= 0;
            tx_buf_full <= 0;
            tx_buf      <= 0;
            txd_r       <= 1'b1;
        end else begin
            if (apb_wr_tdr && ctrl[0]) begin
                if (!tx_busy) begin
                    tx_shift   <= {1'b1, pwdata[7:0], 1'b0};
                    tx_bit_cnt <= 0;
                    tx_busy    <= 1;
                end else begin
                    tx_buf      <= pwdata[7:0];
                    tx_buf_full <= 1;
                end
            end
            if (tx_busy && baud_tick) begin
                txd_r      <= tx_shift[0];
                tx_shift   <= {1'b1, tx_shift[9:1]};
                tx_bit_cnt <= tx_bit_cnt + 1;
                if (tx_bit_cnt == 9) begin
                    if (tx_buf_full) begin
                        tx_shift    <= {1'b1, tx_buf, 1'b0};
                        tx_bit_cnt  <= 0;
                        tx_buf_full <= 0;
                    end else begin
                        tx_busy <= 0;
                        txd_r   <= 1;
                    end
                end
            end
        end
    end

    assign txd = tx_busy ? txd_r : 1'b1;

    // ── RX logic ──────────────────────────────────────────────────────────────
    logic        rxd_s0, rxd_s1;   // sync chain
    always_ff @(posedge pclk or negedge prst_n) begin
        if (!prst_n) begin rxd_s0<=1; rxd_s1<=1; end
        else         begin rxd_s0<=rxd; rxd_s1<=rxd_s0; end
    end

    logic [9:0]  rx_shift;
    logic [3:0]  rx_bit_cnt;
    logic [15:0] rx_baud_cnt;
    logic        rx_busy;

    always_ff @(posedge pclk or negedge prst_n) begin
        if (!prst_n) begin
            rx_shift <= 0; rx_bit_cnt <= 0;
            rx_baud_cnt <= 0; rx_busy <= 0;
            rx_valid <= 0; rx_ovr <= 0; rdr <= 0;
        end else begin
            if (ctrl[1]) begin
                if (!rx_busy) begin
                    if (!rxd_s1) begin   // start bit detected
                        rx_busy     <= 1;
                        rx_baud_cnt <= 0;
                        rx_bit_cnt  <= 0;
                    end
                end else begin
                    rx_baud_cnt <= rx_baud_cnt + 1;
                    if (rx_baud_cnt == baud_div) begin
                        rx_baud_cnt <= 0;
                        rx_bit_cnt  <= rx_bit_cnt + 1;
                        rx_shift    <= {rxd_s1, rx_shift[9:1]};
                        if (rx_bit_cnt == 9) begin
                            if (rxd_s1) begin       // valid stop bit
                                if (rx_valid) rx_ovr <= 1;
                                rdr      <= rx_shift[8:1];
                                rx_valid <= 1;
                            end
                            rx_busy <= 0;
                        end
                    end
                end
            end
            // Clear rx_valid on RDR read
            if (psel && penable && !pwrite && paddr == UART_RDR)
                rx_valid <= 0;
        end
    end

    // ── APB control/config writes ─────────────────────────────────────────────
    always_ff @(posedge pclk or negedge prst_n) begin
        if (!prst_n) begin
            ctrl     <= 2'b11;
            baud_div <= 16'd868;
        end else if (psel && penable && pwrite) begin
            case (paddr)
                UART_CTRL: ctrl     <= pwdata[1:0];
                UART_BAUD: baud_div <= pwdata[15:0];
                default:;
            endcase
        end
    end

    // ── APB read ──────────────────────────────────────────────────────────────
    always_comb begin
        prdata = 32'b0;
        case (paddr)
            UART_RDR:  prdata = {24'b0, rdr};
            UART_CTRL: prdata = {30'b0, ctrl};
            UART_STAT: prdata = {28'b0, rx_ovr, rx_valid, tx_buf_full, tx_busy};
            UART_BAUD: prdata = {16'b0, baud_div};
            default:   prdata = 32'b0;
        endcase
    end

    assign pready  = 1'b1;
    assign pslverr = 1'b0;

endmodule
