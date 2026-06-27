// =============================================================================
// Module      : spi_apb
// Project     : RISC-V SoC  (SE-SOC-001)
// Description : APB SPI master (Mode 0: CPOL=0, CPHA=0). 8-bit transfers.
//
// Register Map:
//   0x00 CTRL  [2:0] [0]=EN [1]=CS_AUTO [2]=CPHA
//   0x04 STAT  [1:0] [0]=BUSY [1]=RXNE
//   0x08 TDR   [7:0] Write to start transfer
//   0x0C RDR   [7:0] Read received byte
//   0x10 PRESC [7:0] SCK = pclk / (2*(PRESC+1))
// =============================================================================
module spi_apb
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
    // SPI pins
    output logic        sck,
    output logic        mosi,
    input  logic        miso,
    output logic        cs_n,
    output logic        irq
);
    logic [2:0]  ctrl_r;
    logic [7:0]  tdr_r, rdr_r;
    logic [7:0]  presc_r;
    logic [1:0]  stat_r;

    // SCK tick generator
    logic [7:0]  presc_cnt;
    logic        sck_tick;
    always_ff @(posedge pclk or negedge prst_n) begin
        if (!prst_n) begin presc_cnt <= 8'b0; sck_tick <= 1'b0; end
        else begin
            sck_tick <= 1'b0;
            if (presc_cnt == presc_r) begin presc_cnt <= 8'b0; sck_tick <= 1'b1; end
            else presc_cnt <= presc_cnt + 1'b1;
        end
    end

    // SPI shift register
    logic [7:0]  shift_r;
    logic [3:0]  bit_cnt;
    logic        sck_r;
    logic        busy;
    logic        sck_ph;

    assign busy     = stat_r[0];
    assign sck      = sck_r & busy;
    assign mosi     = shift_r[7];
    assign cs_n     = ctrl_r[1] ? ~busy : 1'b0;
    assign irq      = stat_r[1];

    always_ff @(posedge pclk or negedge prst_n) begin
        if (!prst_n) begin
            shift_r  <= 8'b0; rdr_r <= 8'b0;
            bit_cnt  <= 4'b0; sck_r <= 1'b0;
            stat_r   <= 2'b00; sck_ph <= 1'b0;
        end else begin
            // Load TDR → start transfer
            if (psel && penable && pwrite && paddr[11:0] == SPI_TDR && !busy) begin
                shift_r   <= pwdata[7:0];
                bit_cnt   <= 4'd7;
                stat_r[0] <= 1'b1;
                sck_ph    <= 1'b0;
            end

            if (busy && sck_tick) begin
                sck_ph <= ~sck_ph;
                if (!sck_ph) begin
                    sck_r <= 1'b1;  // SCK rising — sample MISO
                    shift_r <= {shift_r[6:0], miso};
                end else begin
                    sck_r <= 1'b0;  // SCK falling — shift MOSI
                    if (bit_cnt == 4'd0) begin
                        stat_r[0] <= 1'b0;  // done
                        stat_r[1] <= 1'b1;  // RXNE
                        rdr_r     <= shift_r;
                        sck_r     <= 1'b0;
                    end else
                        bit_cnt <= bit_cnt - 1'b1;
                end
            end

            // Clear RXNE on read
            if (psel && penable && !pwrite && paddr[11:0] == SPI_RDR)
                stat_r[1] <= 1'b0;
        end
    end

    // APB Write
    always_ff @(posedge pclk or negedge prst_n) begin
        if (!prst_n) begin ctrl_r <= 3'b011; presc_r <= 8'd4; tdr_r <= 8'b0; end
        else if (psel && penable && pwrite) begin
            case (paddr[11:0])
                SPI_CTRL:  ctrl_r  <= pwdata[2:0];
                SPI_PRESC: presc_r <= pwdata[7:0];
                default:;
            endcase
        end
    end

    // APB Read
    always_comb begin
        prdata = 32'b0;
        case (paddr[11:0])
            SPI_CTRL:  prdata = {29'b0, ctrl_r};
            SPI_STAT:  prdata = {30'b0, stat_r};
            SPI_RDR:   prdata = {24'b0, rdr_r};
            SPI_PRESC: prdata = {24'b0, presc_r};
            default:   prdata = 32'b0;
        endcase
    end

    assign pready  = 1'b1;
    assign pslverr = 1'b0;
endmodule
