// =============================================================================
// Module      : i2c_apb
// Project     : RISC-V SoC  (SE-SOC-001)
// Description : Simple APB I2C master controller (bit-bang FSM model).
//   Supports: START, STOP, byte write, byte read with ACK/NACK.
//
// Register Map:
//   0x00 CTRL  [3:0] [0]=EN [1]=START [2]=STOP [3]=RD_NACK
//   0x04 STAT  [3:0] [0]=BUSY [1]=ACK_ERR [2]=RXNE [3]=TXE
//   0x08 ADDR  [6:0] 7-bit target address [7]=R/W
//   0x0C TDR   [7:0] TX byte
//   0x10 RDR   [7:0] RX byte (read-only)
//   0x14 PRESC [15:0] clock prescaler (SCL = pclk / (4 * (PRESC+1)))
// =============================================================================
module i2c_apb
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
    // I2C pins (open-drain model)
    output logic        scl_oe,   // 1 = drive SCL low
    input  logic        scl_in,
    output logic        sda_oe,   // 1 = drive SDA low
    input  logic        sda_in,
    output logic        irq
);
    // ── Registers ─────────────────────────────────────────────────────────────
    logic [3:0]  ctrl_r;
    logic [7:0]  addr_r;     // [7]=R/W, [6:0]=address
    logic [7:0]  tdr_r;
    logic [7:0]  rdr_r;
    logic [15:0] presc_r;
    logic [3:0]  stat_r;

    // ── SCL tick generator ────────────────────────────────────────────────────
    logic [15:0] presc_cnt;
    logic        scl_tick;   // quarter-period tick

    always_ff @(posedge pclk or negedge prst_n) begin
        if (!prst_n) begin
            presc_cnt <= 16'b0;
            scl_tick  <= 1'b0;
        end else begin
            scl_tick <= 1'b0;
            if (presc_cnt == presc_r) begin
                presc_cnt <= 16'b0;
                scl_tick  <= 1'b1;
            end else
                presc_cnt <= presc_cnt + 1'b1;
        end
    end

    // ── I2C FSM ───────────────────────────────────────────────────────────────
        localparam logic [3:0] I2C_IDLE = 4'h0;
    localparam logic [3:0] I2C_START = 4'h1;
    localparam logic [3:0] I2C_ADDR = 4'h2;
    localparam logic [3:0] I2C_ACK1 = 4'h3;
    localparam logic [3:0] I2C_DATA = 4'h4;
    localparam logic [3:0] I2C_ACK2 = 4'h5;
    localparam logic [3:0] I2C_RD_DATA = 4'h6;
    localparam logic [3:0] I2C_RD_ACK = 4'h7;
    localparam logic [3:0] I2C_STOP = 4'h8;

    logic [3:0] i2c_st;
    logic [3:0]  bit_cnt;
    logic [7:0]  shift_r;
    logic        scl_r, sda_r;
    logic        tick_ph;   // half-period phase toggle

    assign scl_oe = ~scl_r;
    assign sda_oe = ~sda_r;

    always_ff @(posedge pclk or negedge prst_n) begin
        if (!prst_n) begin
            i2c_st     <= I2C_IDLE;
            scl_r      <= 1'b1;
            sda_r      <= 1'b1;
            bit_cnt    <= 4'b0;
            shift_r    <= 8'b0;
            tick_ph    <= 1'b0;
            stat_r     <= 4'b1000;  // TXE=1
            rdr_r      <= 8'b0;
        end else if (scl_tick) begin
            tick_ph <= ~tick_ph;
            case (i2c_st)
                I2C_IDLE: begin
                    scl_r <= 1'b1; sda_r <= 1'b1;
                    if (ctrl_r[1] && ctrl_r[0]) begin  // START request
                        i2c_st  <= I2C_START;
                        stat_r[0] <= 1'b1;  // BUSY
                    end
                end
                I2C_START: begin
                    if (!tick_ph) begin sda_r <= 1'b0; end  // SDA low while SCL high
                    else          begin scl_r <= 1'b0; i2c_st <= I2C_ADDR; shift_r <= addr_r; bit_cnt <= 4'd7; end
                end
                I2C_ADDR: begin
                    if (!tick_ph) begin scl_r <= 1'b0; sda_r <= shift_r[7]; shift_r <= {shift_r[6:0],1'b0}; end
                    else begin
                        scl_r <= 1'b1;
                        if (bit_cnt == 4'd0) i2c_st <= I2C_ACK1;
                        else bit_cnt <= bit_cnt - 1'b1;
                    end
                end
                I2C_ACK1: begin
                    if (!tick_ph) begin scl_r <= 1'b0; sda_r <= 1'b1; end
                    else begin
                        scl_r <= 1'b1;
                        stat_r[1] <= sda_in;  // ACK_ERR if NACK
                        if (!addr_r[7]) begin i2c_st <= I2C_DATA; shift_r <= tdr_r; bit_cnt <= 4'd7; end
                        else            begin i2c_st <= I2C_RD_DATA; bit_cnt <= 4'd7; end
                    end
                end
                I2C_DATA: begin
                    if (!tick_ph) begin scl_r <= 1'b0; sda_r <= shift_r[7]; shift_r <= {shift_r[6:0],1'b0}; end
                    else begin
                        scl_r <= 1'b1;
                        if (bit_cnt == 4'd0) i2c_st <= I2C_ACK2;
                        else bit_cnt <= bit_cnt - 1'b1;
                    end
                end
                I2C_ACK2: begin
                    if (!tick_ph) begin scl_r <= 1'b0; sda_r <= 1'b1; end
                    else begin
                        scl_r <= 1'b1;
                        stat_r[1] <= sda_in;
                        i2c_st <= ctrl_r[2] ? I2C_STOP : I2C_IDLE;
                    end
                end
                I2C_RD_DATA: begin
                    if (!tick_ph) begin scl_r <= 1'b0; sda_r <= 1'b1; end
                    else begin
                        scl_r   <= 1'b1;
                        shift_r <= {shift_r[6:0], sda_in};
                        if (bit_cnt == 4'd0) begin i2c_st <= I2C_RD_ACK; rdr_r <= {shift_r[6:0],sda_in}; stat_r[2] <= 1'b1; end
                        else bit_cnt <= bit_cnt - 1'b1;
                    end
                end
                I2C_RD_ACK: begin
                    if (!tick_ph) begin scl_r <= 1'b0; sda_r <= ctrl_r[3]; end  // NACK if RD_NACK
                    else begin scl_r <= 1'b1; i2c_st <= ctrl_r[2] ? I2C_STOP : I2C_IDLE; end
                end
                I2C_STOP: begin
                    if (!tick_ph) begin scl_r <= 1'b0; sda_r <= 1'b0; end
                    else begin scl_r <= 1'b1; sda_r <= 1'b1; i2c_st <= I2C_IDLE; stat_r[0] <= 1'b0; end
                end
                default: i2c_st <= I2C_IDLE;
            endcase
        end
    end

    assign irq = stat_r[2];  // RX data available

    // ── APB Write ─────────────────────────────────────────────────────────────
    always_ff @(posedge pclk or negedge prst_n) begin
        if (!prst_n) begin
            ctrl_r  <= 4'b0001;  // enabled
            addr_r  <= 8'b0;
            tdr_r   <= 8'b0;
            presc_r <= 16'd24;   // ~100kHz at 100MHz
        end else if (psel && penable && pwrite) begin
            case (paddr[11:0])
                I2C_CTRL:  ctrl_r  <= pwdata[3:0];
                I2C_ADDR:  addr_r  <= pwdata[7:0];
                I2C_TDR:   tdr_r   <= pwdata[7:0];
                I2C_PRESC: presc_r <= pwdata[15:0];
                default:;
            endcase
        end
    end

    // ── APB Read ──────────────────────────────────────────────────────────────
    always_comb begin
        prdata = 32'b0;
        case (paddr[11:0])
            I2C_CTRL:  prdata = {28'b0, ctrl_r};
            I2C_STAT:  prdata = {28'b0, stat_r};
            I2C_ADDR:  prdata = {24'b0, addr_r};
            I2C_RDR:   prdata = {24'b0, rdr_r};
            I2C_PRESC: prdata = {16'b0, presc_r};
            default:   prdata = 32'b0;
        endcase
    end

    assign pready  = 1'b1;
    assign pslverr = 1'b0;
endmodule
