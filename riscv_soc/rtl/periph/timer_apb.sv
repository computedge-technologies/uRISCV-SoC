// =============================================================================
// Module      : timer_apb
// Project     : RISC-V SoC  (SE-SOC-001)
// Description : APB 32-bit countdown timer / counter.
//
// Register Map:
//   0x00 CTRL [2:0] [0]=EN [1]=MODE(0=one-shot,1=periodic) [2]=IE (IRQ enable)
//   0x04 LOAD [31:0] Reload value
//   0x08 CNT  [31:0] Current count (read-only)
//   0x0C STAT [0]   Overflow/match flag; write 1 to clear
// =============================================================================
module timer_apb
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
    output logic        irq
);
    logic [2:0]  ctrl_r;
    logic [31:0] load_r;
    logic [31:0] cnt_r;
    logic        ovf_r;

    assign irq = ovf_r & ctrl_r[2];

    always_ff @(posedge pclk or negedge prst_n) begin
        if (!prst_n) begin
            ctrl_r <= 3'b0; load_r <= 32'hFFFF_FFFF;
            cnt_r  <= 32'hFFFF_FFFF; ovf_r <= 1'b0;
        end else begin
            // APB write
            if (psel && penable && pwrite) begin
                case (paddr[11:0])
                    TIMER_CTRL: ctrl_r <= pwdata[2:0];
                    TIMER_LOAD: begin load_r <= pwdata; cnt_r <= pwdata; end
                    TIMER_STAT: if (pwdata[0]) ovf_r <= 1'b0;  // W1C
                    default:;
                endcase
            end

            // Count down
            if (ctrl_r[0]) begin
                if (cnt_r == 32'b0) begin
                    ovf_r <= 1'b1;
                    if (ctrl_r[1]) cnt_r <= load_r;  // periodic reload
                    else           ctrl_r[0] <= 1'b0; // one-shot stop
                end else
                    cnt_r <= cnt_r - 1'b1;
            end
        end
    end

    always_comb begin
        prdata = 32'b0;
        case (paddr[11:0])
            TIMER_CTRL: prdata = {29'b0, ctrl_r};
            TIMER_LOAD: prdata = load_r;
            TIMER_CNT:  prdata = cnt_r;
            TIMER_STAT: prdata = {31'b0, ovf_r};
            default:    prdata = 32'b0;
        endcase
    end

    assign pready  = 1'b1;
    assign pslverr = 1'b0;
endmodule
