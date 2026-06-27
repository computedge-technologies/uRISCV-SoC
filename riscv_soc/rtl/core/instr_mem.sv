// =============================================================================
// Module      : instr_mem
// Project     : RISC-V Subset Single-Cycle Processor  (SE-ISA-001)
// Author      : Prabakaran Elaiyappan | SynaptiqEdge Technologies
//
// Description : Instruction Memory — dual-mode via compile-time defines.
//
//   `ifdef SIM
//       Read-only ROM.  Loaded from a .hex file at time 0 via $readmemh.
//       The hex file path is overridable via +define+HEX_FILE="path/to/file.hex"
//
//   `ifdef SYNTH
//       The memory array is written word-by-word through a write port
//       (wr_en, wr_addr, wr_data) before rst_n is de-asserted.
//       This allows an external loader (JTAG, SPI, etc.) to fill the ROM
//       after power-on while the processor is held in reset.
//
//   Only ONE of SIM or SYNTH should be defined at a time.
//
// Parameters  :
//   DEPTH  — number of 32-bit words  (default 256 → 1 KB)
//   AWIDTH — address bits (ceil(log2(DEPTH)))
// =============================================================================

module instr_mem #(
    parameter int DEPTH  = 256,
    parameter int AWIDTH = 8          // log2(DEPTH)
) (
    // ── Read port (always present) ──────────────────────────────────────────
    input  logic [31:0] pc,           // Byte address from PC
    output logic [31:0] instr,        // 32-bit instruction word

`ifdef SYNTH
    // ── Write port (SYNTH only — pre-load before rst_n de-assert) ──────────
    input  logic              clk,
    input  logic              wr_en,
    input  logic [AWIDTH-1:0] wr_addr,
    input  logic [31:0]       wr_data,
`endif

    // Dummy port so port list is never empty in all modes
    input  logic              _unused
);

    // ── Memory array ────────────────────────────────────────────────────────
    logic [31:0] mem [0:DEPTH-1];

`ifdef SIM
    // -------------------------------------------------------------------------
    // SIMULATION MODE
    // Load .hex file at elaboration time (time 0).
    // Override hex path with: +define+HEX_FILE=\"/your/path/prog.hex\"
    // -------------------------------------------------------------------------
    `ifndef HEX_FILE
        `define HEX_FILE "program.hex"
    `endif

    initial begin
        integer i;
        // Initialise all locations to NOP (ADDI x0,x0,0 = 32'h0000_0013)
        for (i = 0; i < DEPTH; i++) mem[i] = 32'h0000_0013;
        $display("[IMEM] Loading hex: %s", `HEX_FILE);
        $readmemh(`HEX_FILE, mem);
        $display("[IMEM] Load complete. First 4 words:");
        for (i = 0; i < 4 && i < DEPTH; i++)
            $display("  mem[%0d] = %08h", i, mem[i]);
    end

`elsif SYNTH
    // -------------------------------------------------------------------------
    // SYNTHESIS MODE
    // Write port allows a loader to fill the memory while the processor is
    // held in reset (rst_n = 0).  Reads are asynchronous (combinational).
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (wr_en)
            mem[wr_addr] <= wr_data;
    end

`else
    initial begin
        $fatal(1, "[IMEM] ERROR: Neither SIM nor SYNTH is defined. Compile with +define+SIM or +define+SYNTH.");
    end
`endif

    // ── Combinational (asynchronous) read — word-addressed ──────────────────
    assign instr = mem[pc[AWIDTH+1:2]];   // pc >> 2 → word index

endmodule
