# =============================================================================
# Program     : uart_test.asm
# Description : UART TX test.
#               1) Set baud divisor  (100 MHz / 868 ≈ 115200 baud)
#               2) Enable UART TX
#               3) Transmit "Hello, SynaptiqEdge!\r\n" one byte at a time,
#                  polling TX_BUSY before each byte.
# Register usage:
#   t0 = UART base address
#   t1 = scratch / poll value
#   a0 = current char to transmit
# =============================================================================

# ── UART register addresses (base = 0x4000_0000) ─────────────────────────────
# TDR  +0x00   RDR  +0x04   CTRL +0x08   STAT +0x0C   BAUD +0x10

        LUI   t0, 0x40000     # t0 = 0x4000_0000  (UART base)

# ── 1. Set baud divisor = 868 (100 MHz / 115200) ─────────────────────────────
        LI    t1, 868
        SW    t1, 0x10(t0)    # UART_BAUD = 868

# ── 2. Enable TX+RX  (CTRL = 0x03) ──────────────────────────────────────────
        LI    t1, 3
        SW    t1, 0x08(t0)    # UART_CTRL = 3

# ── 3. Transmit each character of "Hello, SynaptiqEdge!\r\n" ─────────────────

        # Helper macro: wait_tx / send_byte defined inline below

# 'H' = 0x48
        LI    a0, 0x48
        JAL   ra, send_byte

# 'e' = 0x65
        LI    a0, 0x65
        JAL   ra, send_byte

# 'l' = 0x6C
        LI    a0, 0x6C
        JAL   ra, send_byte

# 'l' = 0x6C
        LI    a0, 0x6C
        JAL   ra, send_byte

# 'o' = 0x6F
        LI    a0, 0x6F
        JAL   ra, send_byte

# ',' = 0x2C
        LI    a0, 0x2C
        JAL   ra, send_byte

# ' ' = 0x20
        LI    a0, 0x20
        JAL   ra, send_byte

# 'S' = 0x53
        LI    a0, 0x53
        JAL   ra, send_byte

# 'y' = 0x79
        LI    a0, 0x79
        JAL   ra, send_byte

# 'n' = 0x6E
        LI    a0, 0x6E
        JAL   ra, send_byte

# 'a' = 0x61
        LI    a0, 0x61
        JAL   ra, send_byte

# 'p' = 0x70
        LI    a0, 0x70
        JAL   ra, send_byte

# 't' = 0x74
        LI    a0, 0x74
        JAL   ra, send_byte

# 'i' = 0x69
        LI    a0, 0x69
        JAL   ra, send_byte

# 'q' = 0x71
        LI    a0, 0x71
        JAL   ra, send_byte

# 'E' = 0x45
        LI    a0, 0x45
        JAL   ra, send_byte

# 'd' = 0x64
        LI    a0, 0x64
        JAL   ra, send_byte

# 'g' = 0x67
        LI    a0, 0x67
        JAL   ra, send_byte

# 'e' = 0x65
        LI    a0, 0x65
        JAL   ra, send_byte

# '!' = 0x21
        LI    a0, 0x21
        JAL   ra, send_byte

# '\r' = 0x0D
        LI    a0, 0x0D
        JAL   ra, send_byte

# '\n' = 0x0A
        LI    a0, 0x0A
        JAL   ra, send_byte

# ── 4. Set a0=1 as success flag, then halt ───────────────────────────────────
        LI    a0, 1
        HALT

# =============================================================================
# Subroutine : send_byte
#   a0 = byte to send   t0 = UART base (preserved)
#   Polls STAT[0] (TX_BUSY) until clear, then writes byte to TDR.
# =============================================================================
send_byte:
        # Poll TX_BUSY (STAT bit 0)
poll_tx:
        LW    t1, 0x0C(t0)    # t1 = UART_STAT
        ANDI  t1, t1, 1       # isolate TX_BUSY bit
        BNEZ  t1, poll_tx     # if busy, keep polling

        SW    a0, 0x00(t0)    # UART_TDR = a0  (transmit!)
        RET
