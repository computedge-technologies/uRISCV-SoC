// =============================================================================
// Module      : tb_soc_uart
// Project     : RISC-V SoC  (SE-SOC-001)
// Author      : Prabakaran Elaiyappan | SynaptiqEdge Technologies
//
// Description : SoC-level self-checking testbench.
//   - Boots RISC-V SoC, runs uart_test.asm via $readmemh
//   - Bit-accurate UART RX monitor decodes 8N1 frames from TXD
//   - AHB + APB bus transaction monitor with address decode
//   - Verifies received string == "Hello, SynaptiqEdge!\r\n"
//   - Checks a0 success flag, UART config registers
// =============================================================================
//  `timescale 1ns/1ps

module tb_soc_uart;

    // ── Parameters ────────────────────────────────────────────────────────────
    localparam int CLK_PERIOD  = 10;            // 10 ns → 100 MHz
    localparam int BAUD_DIV    = 868;           // matches uart_test.asm
    localparam int BIT_TICKS   = BAUD_DIV + 1; // clk ticks per UART bit
    localparam int MAX_CYCLES  = 3_000_000;
    localparam int IMEM_DEPTH  = 256;
    localparam int IMEM_AWIDTH = 8;

    // ── DUT IOs ───────────────────────────────────────────────────────────────
    logic        clk, rst_n;
    logic        uart_txd, uart_rxd;
    logic        i2c_scl_oe, i2c_scl_in, i2c_sda_oe, i2c_sda_in;
    logic        spi_sck, spi_mosi, spi_miso, spi_cs_n;
    logic        irq_uart_tx, irq_uart_rx, irq_i2c, irq_spi, irq_timer;
    logic [31:0] o_pc, o_instr, o_reg_a0;

    riscv_soc_top #(
        .IMEM_DEPTH  (IMEM_DEPTH),
        .IMEM_AWIDTH (IMEM_AWIDTH)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .uart_txd(uart_txd), .uart_rxd(uart_rxd),
        .i2c_scl_oe(i2c_scl_oe), .i2c_scl_in(i2c_scl_in),
        .i2c_sda_oe(i2c_sda_oe), .i2c_sda_in(i2c_sda_in),
        .spi_sck(spi_sck), .spi_mosi(spi_mosi),
        .spi_miso(spi_miso), .spi_cs_n(spi_cs_n),
        .irq_uart_tx(irq_uart_tx), .irq_uart_rx(irq_uart_rx),
        .irq_i2c(irq_i2c), .irq_spi(irq_spi), .irq_timer(irq_timer),
        .o_pc(o_pc), .o_instr(o_instr), .o_reg_a0(o_reg_a0)
    );

    assign uart_rxd   = 1'b1;
    assign i2c_scl_in = 1'b1;
    assign i2c_sda_in = 1'b1;
    assign spi_miso   = 1'b0;

    // ── Clock ─────────────────────────────────────────────────────────────────
    initial clk = 0;
    always  #(CLK_PERIOD/2) clk = ~clk;

    integer cycle_cnt;
    initial cycle_cnt = 0;
    always @(posedge clk) cycle_cnt = cycle_cnt + 1;

    // ── Waveform ──────────────────────────────────────────────────────────────
    initial begin
        $dumpfile("waves_soc.vcd");
        $dumpvars(0, tb_soc_uart);
    end

    // =========================================================================
    // UART Bit-Accurate RX Monitor
    // Triggers on falling edge of TXD (start bit), samples 8 data bits,
    // verifies stop bit, stores byte in rx_buf[].
    // =========================================================================
    reg  [7:0]  rx_buf [0:127];
    integer     rx_idx;
    initial     rx_idx = 0;

    // Edge detect
    reg txd_d;
    initial txd_d = 1;
    always @(posedge clk) txd_d <= uart_txd;
    wire start_bit_edge = (txd_d == 1'b1) && (uart_txd == 1'b0);

    // UART frame decode — runs in its own always block triggered by start edge
    // Using time-based sampling with # delays (BIT_TICKS * CLK_PERIOD ns)
    event uart_frame_start;
    always @(posedge start_bit_edge) -> uart_frame_start;

    always @(uart_frame_start) begin : uart_rx_mon
        reg [7:0] rx_byte;
        integer   bit_idx;
        integer   half_bit_ns;
        integer   full_bit_ns;
        half_bit_ns = (CLK_PERIOD * BIT_TICKS) / 2;
        full_bit_ns = CLK_PERIOD * BIT_TICKS;

        // Wait to centre of start bit, then verify
        #(half_bit_ns);
        if (uart_txd !== 1'b0) disable uart_rx_mon;  // false trigger

        // Sample 8 data bits at centre of each bit period
        rx_byte = 8'h00;
        for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
            #(full_bit_ns);
            rx_byte[bit_idx] = uart_txd;
        end

        // Check stop bit
        #(full_bit_ns);
        if (uart_txd !== 1'b1)
            $display("[UART_MON] WARNING: missing stop bit at byte index %0d (t=%0t)", rx_idx, $time);

        // Store and print
        rx_buf[rx_idx] = rx_byte;
        if (rx_byte >= 8'h20 && rx_byte <= 8'h7E)
            $display("[UART_MON] RX[%02d] 0x%02h '%c'  (t=%0t ns, cycle=%0d)",
                     rx_idx, rx_byte, rx_byte, $time, cycle_cnt);
        else
            $display("[UART_MON] RX[%02d] 0x%02h '.'  (t=%0t ns, cycle=%0d)",
                     rx_idx, rx_byte, $time, cycle_cnt);
        rx_idx = rx_idx + 1;
    end

    // =========================================================================
    // AHB Bus Monitor
    // =========================================================================
    wire [31:0] m_haddr  = dut.m_haddr;
    wire [1:0]  m_htrans = dut.m_htrans;
    wire        m_hwrite = dut.m_hwrite;
    wire [31:0] m_hwdata = dut.m_hwdata;
    wire [31:0] m_hrdata = dut.m_hrdata;
    wire        m_hready = dut.m_hready;

    always @(posedge clk) begin
        if (rst_n && m_htrans == 2'b10) begin
            if (m_hwrite)
                $display("[AHB ] cyc=%6d WRITE addr=0x%08h data=0x%08h",
                         cycle_cnt, m_haddr, m_hwdata);
            else
                $display("[AHB ] cyc=%6d READ  addr=0x%08h rdat=0x%08h rdy=%b",
                         cycle_cnt, m_haddr, m_hrdata, m_hready);
        end
    end

    // =========================================================================
    // APB Bus Monitor
    // =========================================================================
    wire [31:0] p_addr   = dut.paddr;
    wire [3:0]  p_sel    = dut.psel;
    wire        p_enable = dut.penable;
    wire        p_write  = dut.pwrite;
    wire [31:0] p_wdata  = dut.pwdata;

    // Decode APB slave name
    function automatic [63:0] apb_slave_name;
        input [3:0] sel;
        case (sel)
            4'b0001: apb_slave_name = "UART    ";
            4'b0010: apb_slave_name = "I2C     ";
            4'b0100: apb_slave_name = "SPI     ";
            4'b1000: apb_slave_name = "TIMER   ";
            default: apb_slave_name = "UNKNOWN ";
        endcase
    endfunction

    // Decode UART register name
    function automatic [63:0] uart_reg_name;
        input [11:0] addr;
        case (addr)
            12'h00: uart_reg_name = "TDR     ";
            12'h04: uart_reg_name = "RDR     ";
            12'h08: uart_reg_name = "CTRL    ";
            12'h0C: uart_reg_name = "STAT    ";
            12'h10: uart_reg_name = "BAUD    ";
            default: uart_reg_name = "UNKNOWN ";
        endcase
    endfunction

    always @(posedge clk) begin
        if (rst_n && |p_sel && p_enable) begin
            if (p_write)
                $display("[APB ] cyc=%6d WRITE slave=%s reg=%s data=0x%08h",
                         cycle_cnt, apb_slave_name(p_sel),
                         uart_reg_name(p_addr[11:0]), p_wdata);
            else
                $display("[APB ] cyc=%6d READ  slave=%s reg=%s paddr=0x%08h",
                         cycle_cnt, apb_slave_name(p_sel),
                         uart_reg_name(p_addr[11:0]), p_addr);
        end
    end

    // =========================================================================
    // Bridge HRDATA debug
    wire [31:0] bridge_hrdata = dut.s1_hrdata;
    wire        bridge_hready = dut.s1_hready;

    always @(posedge clk) begin
        if (rst_n && bridge_hready && dut.u_master.st == 2'b10) begin
            $display("[BRG ] cyc=%6d hrdata=0x%08h hready=%b t1=0x%08h",
                cycle_cnt, bridge_hrdata, bridge_hready,
                dut.u_master.u_core.u_regfile.regs[6]);
        end
    end

    // =========================================================================
    // CPU Trace
    // =========================================================================
    reg [31:0] last_pc;
    initial last_pc = 32'hFFFF_FFFF;
    always @(posedge clk) begin
        if (rst_n && o_pc !== last_pc) begin
            $display("[CPU ] cyc=%6d PC=0x%08h INSTR=0x%08h",
                     cycle_cnt, o_pc, o_instr);
            last_pc <= o_pc;
        end
    end

    // =========================================================================
    // Halt detection: JAL x0, 0  =  32'h0000_006F
    // =========================================================================
    wire halted = rst_n && (o_instr == 32'h0000_006F);

    // =========================================================================
    // Pass / Fail infrastructure
    // =========================================================================
    integer pass_cnt, fail_cnt;
    initial begin pass_cnt = 0; fail_cnt = 0; end

    task automatic chk;
        input        cond;
        input [255:0] msg;
        begin
            if (cond) begin
                $display("  [PASS] %s", msg);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  [FAIL] %s", msg);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // =========================================================================
    // Expected string: "Hello, SynaptiqEdge!\r\n"  (22 bytes)
    // =========================================================================
    localparam integer EXPECT_LEN = 22;
    reg [7:0] expected [0:21];
    initial begin
        expected[ 0] = 8'h48; // H
        expected[ 1] = 8'h65; // e
        expected[ 2] = 8'h6C; // l
        expected[ 3] = 8'h6C; // l
        expected[ 4] = 8'h6F; // o
        expected[ 5] = 8'h2C; // ,
        expected[ 6] = 8'h20; // (space)
        expected[ 7] = 8'h53; // S
        expected[ 8] = 8'h79; // y
        expected[ 9] = 8'h6E; // n
        expected[10] = 8'h61; // a
        expected[11] = 8'h70; // p
        expected[12] = 8'h74; // t
        expected[13] = 8'h69; // i
        expected[14] = 8'h71; // q
        expected[15] = 8'h45; // E
        expected[16] = 8'h64; // d
        expected[17] = 8'h67; // g
        expected[18] = 8'h65; // e
        expected[19] = 8'h21; // !
        expected[20] = 8'h0D; // \r
        expected[21] = 8'h0A; // \n
    end

    // =========================================================================
    // Main Stimulus
    // =========================================================================
    integer i;
    initial begin
        $display("================================================================");
        $display("  RISC-V SoC UART Testbench  |  SE-SOC-001 v1.0");
        $display("  SynaptiqEdge Technologies / Chip Design Academy");
        $display("================================================================");
        $display("  Clock: %0d MHz  BAUD_DIV: %0d  BIT_PERIOD: %0d ns",
                 1000/CLK_PERIOD, BAUD_DIV, CLK_PERIOD*BIT_TICKS);
        $display("  Expected TX: \"Hello, SynaptiqEdge!\\r\\n\" (%0d bytes)\n", EXPECT_LEN);

        // Reset
        rst_n = 0;
        repeat(5) @(posedge clk); #1;
        rst_n = 1;
        $display("[TB] Reset released. SoC running...\n");
        $display("  --- Bus Monitor & CPU Trace ---");

        // Run until HALT or timeout
        fork
            begin
                wait(halted);
                // Allow last UART frame to finish
                repeat(BIT_TICKS * 12) @(posedge clk);
            end
            begin
                repeat(MAX_CYCLES) @(posedge clk);
                $display("\n[TB] TIMEOUT after %0d cycles!", MAX_CYCLES);
                $finish(1);
            end
        join_any
        disable fork;

        $display("\n[TB] HALT at PC=0x%08h  cycles=%0d\n", o_pc, cycle_cnt);

        // ── UART Verification ─────────────────────────────────────────────────
        $display("================================================================");
        $display("  UART TXD Verification");
        $display("================================================================");
        $display("  Received %0d bytes, expected %0d", rx_idx, EXPECT_LEN);

        chk(rx_idx == EXPECT_LEN, "Byte count matches expected (22 bytes)");

        for (i = 0; i < EXPECT_LEN && i < rx_idx; i = i + 1) begin
            if (rx_buf[i] === expected[i]) begin
                if (expected[i] >= 8'h20)
                    $display("  [PASS] rx[%02d] = 0x%02h '%c'", i, rx_buf[i], rx_buf[i]);
                else
                    $display("  [PASS] rx[%02d] = 0x%02h (ctrl)", i, rx_buf[i]);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  [FAIL] rx[%02d] = 0x%02h, expected 0x%02h",
                         i, rx_buf[i], expected[i]);
                fail_cnt = fail_cnt + 1;
            end
        end

        // ── SoC / Peripheral Checks ───────────────────────────────────────────
        $display("\n================================================================");
        $display("  SoC Peripheral Register Checks");
        $display("================================================================");
        chk(o_reg_a0 == 32'd1,   "CPU a0=1 (success flag)");
        chk(dut.u_uart.ctrl     == 2'b11,    "UART CTRL[1:0]=3 (TX+RX enabled)");
        chk(dut.u_uart.baud_div == 16'd868,  "UART BAUD_DIV=868 (~115200 @ 100MHz)");
        chk(dut.u_uart.tx_busy  == 1'b0,     "UART TX_BUSY=0 (all bytes sent)");
        chk(dut.u_master.u_core.u_regfile.regs[0] == 32'd0, "x0 always zero");

        // ── Summary ──────────────────────────────────────────────────────────
        $display("\n================================================================");
        if (fail_cnt == 0)
            $display("  RESULT: ALL %0d CHECKS PASSED", pass_cnt);
        else
            $display("  RESULT: %0d PASSED  /  %0d FAILED", pass_cnt, fail_cnt);
        $display("================================================================");
        $finish;
    end

    // Timeout watchdog
    initial begin
        #(CLK_PERIOD * MAX_CYCLES * 2);
        $display("[TB] ABSOLUTE TIMEOUT");
        $finish(1);
    end

endmodule
