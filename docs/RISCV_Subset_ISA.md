# RISC-V Subset ISA — Single-Cycle Processor
### Document ID: SE-ISA-001 | Version 1.0
**SynaptiqEdge Technologies Pvt Ltd — Chip Design Academy**

---

## 1. Introduction

This document defines a minimal subset of the RISC-V RV32I base integer instruction set, tailored for implementing a **single-cycle 32-bit processor**. The goal is to support essential computation: arithmetic, logic, shift, branching, loops, and unconditional jumps — sufficient to execute meaningful programs in assembly.

All instructions are **32-bit fixed-width**, conforming to the standard RV32I encoding formats. Any instruction not listed here is **not implemented** and will result in undefined behavior.

---

## 2. Programmer's Model

### 2.1 Register File

| Register  | ABI Name | Role                              |
|-----------|----------|-----------------------------------|
| x0        | zero     | Hardwired zero (reads always 0, writes ignored) |
| x1        | ra       | Return address                    |
| x2        | sp       | Stack pointer                     |
| x3–x4     | gp, tp   | Global/thread pointer (unused in subset) |
| x5–x7     | t0–t2    | Temporaries                       |
| x8–x9     | s0–s1    | Saved registers                   |
| x10–x11   | a0–a1    | Function arguments / return values |
| x12–x17   | a2–a7    | Function arguments                |
| x18–x27   | s2–s11   | Saved registers                   |
| x28–x31   | t3–t6    | Temporaries                       |

- **Width:** All registers are 32 bits wide.
- **x0** is read-only and always returns 0.
- **Total:** 32 general-purpose registers (x0–x31).

### 2.2 Program Counter (PC)

- 32-bit register, byte-addressed.
- Always increments by 4 (one word) unless a branch or jump modifies it.
- Reset value: `0x00000000`.

---

## 3. Instruction Encoding Formats

All instructions are 32 bits. The format determines how the immediate value and register fields are packed.

```
 31       25 24   20 19  15 14  12 11    7 6      0
 ┌──────────┬───────┬──────┬──────┬───────┬────────┐
 │  funct7  │  rs2  │  rs1 │funct3│  rd   │ opcode │  R-type
 ├──────────┴───────┘      │      │       │        │
 │       imm[11:0]         │funct3│  rd   │ opcode │  I-type
 ├───────────┬─────────────┘      │       │        │
 │ imm[11:5] │  rs2  │  rs1 │funct3│imm[4:0]│opcode│  S-type (unused here)
 ├───────────┴───────┴──────┴──────┴───────┴────────┤
 │imm[12|10:5]│ rs2  │  rs1 │funct3│imm[4:1|11]│op │  B-type
 ├────────────────────────────────┬───────┬─────────┤
 │          imm[31:12]            │  rd   │ opcode  │  U-type
 ├────────────────────────────────┴───────┴─────────┤
 │imm[20|10:1|11|19:12]           │  rd   │ opcode  │  J-type
 └──────────────────────────────────────────────────┘
```

### 3.1 Field Widths

| Field  | Bits | Description                        |
|--------|------|------------------------------------|
| opcode | [6:0]  | Instruction class identifier       |
| rd     | [11:7] | Destination register               |
| funct3 | [14:12]| Sub-operation selector             |
| rs1    | [19:15]| Source register 1                  |
| rs2    | [24:20]| Source register 2                  |
| funct7 | [31:25]| Extended opcode (R-type only)      |

---

## 4. Implemented Instructions

### 4.1 Summary Table

| #  | Mnemonic | Format | Operation                          | Category        |
|----|----------|--------|------------------------------------|-----------------|
| 1  | ADD      | R      | rd = rs1 + rs2                     | Arithmetic      |
| 2  | SUB      | R      | rd = rs1 - rs2                     | Arithmetic      |
| 3  | ADDI     | I      | rd = rs1 + sext(imm)               | Arithmetic      |
| 4  | AND      | R      | rd = rs1 & rs2                     | Logic           |
| 5  | OR       | R      | rd = rs1 \| rs2                    | Logic           |
| 6  | XOR      | R      | rd = rs1 ^ rs2                     | Logic           |
| 7  | ANDI     | I      | rd = rs1 & sext(imm)               | Logic           |
| 8  | ORI      | I      | rd = rs1 \| sext(imm)              | Logic           |
| 9  | XORI     | I      | rd = rs1 ^ sext(imm)               | Logic           |
| 10 | SLL      | R      | rd = rs1 << rs2[4:0]               | Shift           |
| 11 | SRL      | R      | rd = rs1 >> rs2[4:0] (logical)     | Shift           |
| 12 | SRA      | R      | rd = rs1 >>> rs2[4:0] (arithmetic) | Shift           |
| 13 | SLLI     | I      | rd = rs1 << shamt                  | Shift           |
| 14 | SRLI     | I      | rd = rs1 >> shamt (logical)        | Shift           |
| 15 | SRAI     | I      | rd = rs1 >>> shamt (arithmetic)    | Shift           |
| 16 | SLT      | R      | rd = (rs1 < rs2) ? 1 : 0 (signed) | Compare         |
| 17 | SLTU     | R      | rd = (rs1 < rs2) ? 1 : 0 (unsigned)| Compare        |
| 18 | SLTI     | I      | rd = (rs1 < sext(imm)) ? 1 : 0    | Compare         |
| 19 | SLTIU    | I      | rd = (rs1 < imm) ? 1 : 0 (unsigned)| Compare        |
| 20 | LUI      | U      | rd = imm << 12                     | Immediate Load  |
| 21 | AUIPC    | U      | rd = PC + (imm << 12)              | PC-relative     |
| 22 | BEQ      | B      | if (rs1 == rs2) PC += sext(imm)    | Branch          |
| 23 | BNE      | B      | if (rs1 != rs2) PC += sext(imm)    | Branch          |
| 24 | BLT      | B      | if (rs1 < rs2) PC += sext(imm)     | Branch          |
| 25 | BGE      | B      | if (rs1 >= rs2) PC += sext(imm)    | Branch          |
| 26 | BLTU     | B      | if (rs1 <u rs2) PC += sext(imm)    | Branch          |
| 27 | BGEU     | B      | if (rs1 >=u rs2) PC += sext(imm)   | Branch          |
| 28 | JAL      | J      | rd = PC+4; PC += sext(imm)         | Jump            |
| 29 | JALR     | I      | rd = PC+4; PC = (rs1 + sext(imm)) & ~1 | Jump       |

> **Note:** LW, SW (load/store) are intentionally excluded. The processor operates on a register-only model. Memory access can be added as a Phase-2 extension.

---

## 5. Instruction Encoding Details

### 5.1 R-Type Instructions

**Opcode:** `0110011`

```
 31     25  24   20  19   15  14   12  11    7   6      0
┌─────────┬───────┬───────┬────────┬────────┬─────────┐
│ funct7  │  rs2  │  rs1  │ funct3 │   rd   │ 0110011 │
└─────────┴───────┴───────┴────────┴────────┴─────────┘
```

| Instruction | funct7    | funct3 |
|-------------|-----------|--------|
| ADD         | `0000000` | `000`  |
| SUB         | `0100000` | `000`  |
| AND         | `0000000` | `111`  |
| OR          | `0000000` | `110`  |
| XOR         | `0000000` | `100`  |
| SLL         | `0000000` | `001`  |
| SRL         | `0000000` | `101`  |
| SRA         | `0100000` | `101`  |
| SLT         | `0000000` | `010`  |
| SLTU        | `0000000` | `011`  |

---

### 5.2 I-Type Instructions (ALU Immediate)

**Opcode:** `0010011`

```
 31          20  19   15  14   12  11    7   6      0
┌─────────────┬───────┬────────┬────────┬─────────┐
│  imm[11:0]  │  rs1  │ funct3 │   rd   │ 0010011 │
└─────────────┴───────┴────────┴────────┴─────────┘
```

| Instruction | funct3 | Notes                              |
|-------------|--------|------------------------------------|
| ADDI        | `000`  | imm is sign-extended               |
| ANDI        | `111`  | imm is sign-extended               |
| ORI         | `110`  | imm is sign-extended               |
| XORI        | `100`  | imm is sign-extended               |
| SLTI        | `010`  | signed comparison                  |
| SLTIU       | `011`  | unsigned; imm sign-extended before compare |
| SLLI        | `001`  | imm[11:5]=`0000000`, shamt=imm[4:0] |
| SRLI        | `101`  | imm[11:5]=`0000000`, shamt=imm[4:0] |
| SRAI        | `101`  | imm[11:5]=`0100000`, shamt=imm[4:0] |

> **Shift Immediate Encoding:** For SLLI/SRLI/SRAI, bits [24:20] carry the shift amount (shamt, 5 bits). Bits [31:25] serve as the funct7 disambiguator.

---

### 5.3 U-Type Instructions

```
 31               12  11    7   6      0
┌──────────────────┬────────┬─────────┐
│    imm[31:12]    │   rd   │ opcode  │
└──────────────────┴────────┴─────────┘
```

| Instruction | Opcode    | Operation                   |
|-------------|-----------|-----------------------------|
| LUI         | `0110111` | rd = imm[31:12] << 12       |
| AUIPC       | `0010111` | rd = PC + (imm[31:12] << 12)|

> The lower 12 bits of the result are zero for LUI. AUIPC is essential for PC-relative addressing and position-independent code.

---

### 5.4 B-Type Instructions (Branches)

**Opcode:** `1100011`

```
 31    30    25  24  20  19  15  14  12  11    8   7    6      0
┌────┬───────┬───────┬───────┬───────┬───────┬───┬──────────┐
│ 12 │10:5   │  rs2  │  rs1  │funct3 │  4:1  │11 │ 1100011  │
└────┴───────┴───────┴───────┴───────┴───────┴───┴──────────┘
  imm[12]  imm[10:5]         funct3   imm[4:1] imm[11]
```

**Immediate Reconstruction:** `imm = {imm[12], imm[11], imm[10:5], imm[4:1], 1'b0}`
(Bit 0 is always 0 — branches are 2-byte aligned minimum; in this subset always 4-byte aligned.)

| Instruction | funct3 | Condition                          |
|-------------|--------|------------------------------------|
| BEQ         | `000`  | rs1 == rs2                         |
| BNE         | `001`  | rs1 != rs2                         |
| BLT         | `100`  | rs1 < rs2 (signed)                 |
| BGE         | `101`  | rs1 >= rs2 (signed)                |
| BLTU        | `110`  | rs1 < rs2 (unsigned)               |
| BGEU        | `111`  | rs1 >= rs2 (unsigned)              |

**Branch Target:** `PC_next = PC + sext(imm)` (taken), or `PC + 4` (not taken).
The immediate encodes a **PC-relative byte offset**, range: **±4KB**.

---

### 5.5 J-Type Instructions (Jump)

```
 31    30       21  20    19       12  11    7   6      0
┌────┬──────────┬────┬─────────────┬────────┬─────────┐
│ 20 │  10:1    │ 11 │   19:12     │   rd   │ 1101111 │
└────┴──────────┴────┴─────────────┴────────┴─────────┘
  imm[20]  imm[10:1]  imm[11]   imm[19:12]
```

**Immediate Reconstruction:** `imm = {imm[20], imm[19:12], imm[11], imm[10:1], 1'b0}`

| Instruction | Opcode    | Operation                                      |
|-------------|-----------|------------------------------------------------|
| JAL         | `1101111` | rd = PC+4; PC = PC + sext(imm)                |

**Jump range:** ±1MB (PC-relative).

---

### 5.6 JALR (I-Type Jump)

**Opcode:** `1100111`, funct3 = `000`

```
 31          20  19   15   14  12  11    7   6      0
┌─────────────┬───────┬───────┬────────┬─────────┐
│  imm[11:0]  │  rs1  │  000  │   rd   │ 1100111 │
└─────────────┴───────┴───────┴────────┴─────────┘
```

**Operation:** `rd = PC+4; PC = (rs1 + sext(imm)) & ~1`

> The LSB of the computed target is forced to 0 (per RV32I spec). Bit 1 must also be 0 (4-byte aligned targets in this implementation).

---

## 6. Control Path Summary

### 6.1 Control Signals

| Signal       | Width | Description                                      |
|--------------|-------|--------------------------------------------------|
| RegWrite     | 1     | Enable write to register file                    |
| ALUSrc       | 1     | 0 = rs2, 1 = immediate                           |
| ALUOp        | 3     | Selects ALU operation                            |
| Branch       | 1     | Instruction is a branch type                     |
| Jump         | 1     | Instruction is JAL/JALR                          |
| JumpSrc      | 1     | 0 = PC-relative (JAL), 1 = register (JALR)      |
| PCSel        | 1     | 0 = PC+4, 1 = branch/jump target                |
| ResultSrc    | 2     | 00 = ALU result, 01 = PC+4 (for JAL/JALR link)  |
| LUI_sel      | 1     | Bypass ALU, write imm<<12 directly to rd         |

### 6.2 Datapath Overview (Single-Cycle)

```
              ┌──────────────────────────────────────────┐
              │              INSTRUCTION MEMORY           │
              └──────────────────┬───────────────────────┘
                                 │ inst[31:0]
                    ┌────────────▼────────────┐
                    │     INSTRUCTION DECODE  │
                    │  (opcode, funct3, funct7│
                    │   rs1, rs2, rd, imm)    │
                    └──┬───┬────┬────┬────┬──┘
                       │   │    │    │    │
                  rs1  │   │rs2 │    │rd  │imm
              ┌────────▼───▼────┐    │    │
              │   REGISTER FILE  │    │    │
              │  (32 × 32-bit)  │    │    │
              └────────┬────────┘    │    │
                  A    │    B        │    │
              ┌────────▼────────▼───▼┐   │
              │        ALU           │   │
              │  (add/sub/and/or/   │   │
              │   xor/sll/srl/sra/  │   │
              │   slt/sltu)         │   │
              └───────────┬──────────┘   │
                          │ ALU Result   │
                 ┌────────▼──────────────▼──┐
                 │      RESULT MUX          │
                 │ (ALU result / PC+4 / LUI)│
                 └────────────┬─────────────┘
                              │ Write Data
                              ▼
                         [Register File Write]

     PC ──► [PC+4 adder] ──► PC_next (not-taken)
     PC ──► [Branch adder: PC + imm] ──► branch target
     rs1 ──► [JALR adder: rs1 + imm, &~1] ──► jalr target
                              │
                    ┌─────────▼─────────┐
                    │     PC MUX        │
                    │ (PC+4 / branch /  │
                    │  JAL / JALR)      │
                    └─────────┬─────────┘
                              ▼
                           [PC Register]
```

---

## 7. ALU Operation Encoding

The ALU accepts a 4-bit control signal derived from `{funct7[5], funct3}`:

| ALU Ctrl | funct7[5] | funct3 | Operation    |
|----------|-----------|--------|--------------|
| `0000`   | 0         | `000`  | ADD          |
| `0001`   | 0         | `001`  | SLL          |
| `0010`   | 0         | `010`  | SLT (signed) |
| `0011`   | 0         | `011`  | SLTU         |
| `0100`   | 0         | `100`  | XOR          |
| `0101`   | 0         | `101`  | SRL          |
| `0110`   | 0         | `110`  | OR           |
| `0111`   | 0         | `111`  | AND          |
| `1000`   | 1         | `000`  | SUB          |
| `1101`   | 1         | `101`  | SRA          |

> For I-type ALU instructions, `funct7[5]` is derived from `inst[30]`. For ADDI and other immediate ops with no funct7 ambiguity, funct7[5] is treated as 0.

---

## 8. Immediate Generation

The **Imm Gen** unit extracts and sign-extends the immediate based on instruction type:

| Format | Encoding                                         | Sign Extension from |
|--------|--------------------------------------------------|---------------------|
| I-type | `inst[31:20]`                                    | bit 31              |
| B-type | `{inst[31], inst[7], inst[30:25], inst[11:8], 1'b0}` | bit 31         |
| U-type | `{inst[31:12], 12'b0}`                           | bit 31              |
| J-type | `{inst[31], inst[19:12], inst[20], inst[30:21], 1'b0}` | bit 31       |

---

## 9. Pseudo-Instructions Reference

These are assembler convenience macros, synthesized from real instructions:

| Pseudo       | Real Instruction(s)           | Effect                         |
|--------------|-------------------------------|--------------------------------|
| `NOP`        | `ADDI x0, x0, 0`             | No operation                   |
| `MV rd, rs`  | `ADDI rd, rs, 0`             | Copy register                  |
| `LI rd, imm` | `LUI rd, imm[31:12]` + `ADDI rd, rd, imm[11:0]` | Load 32-bit immediate |
| `NEG rd, rs` | `SUB rd, x0, rs`             | Two's complement negation      |
| `NOT rd, rs` | `XORI rd, rs, -1`            | Bitwise NOT                    |
| `BEQZ rs, L` | `BEQ rs, x0, L`             | Branch if zero                 |
| `BNEZ rs, L` | `BNE rs, x0, L`             | Branch if non-zero             |
| `BLTZ rs, L` | `BLT rs, x0, L`             | Branch if negative             |
| `BGEZ rs, L` | `BGE rs, x0, L`             | Branch if non-negative         |
| `J label`    | `JAL x0, label`              | Unconditional jump (discard ra)|
| `RET`        | `JALR x0, ra, 0`            | Return from function           |
| `CALL label` | `JAL ra, label`              | Call subroutine                |

---

## 10. Example Programs

### 10.1 Sum of 1 to N (Loop)

```asm
# a0 = N (input)
# a1 = sum (output)
    ADDI  a1, x0, 0      # sum = 0
    ADDI  t0, x0, 1      # i = 1
loop:
    BGT   t0, a0, done   # if i > N, exit  (use BLT a0, t0)
    ADD   a1, a1, t0     # sum += i
    ADDI  t0, t0, 1      # i++
    JAL   x0, loop       # jump back
done:
    # a1 contains result
```

### 10.2 Compute GCD (Branch + Loop)

```asm
# a0 = x, a1 = y
gcd:
    BEQ   a1, x0, end    # if y == 0, done
    # compute x mod y using subtraction
    BLT   a0, a1, swap   # if x < y, swap
    SUB   a0, a0, a1     # x = x - y
    JAL   x0, gcd
swap:
    XOR   a0, a0, a1
    XOR   a1, a0, a1
    XOR   a0, a0, a1     # swap a0, a1
    JAL   x0, gcd
end:
    # a0 = GCD
```

### 10.3 Subroutine Call and Return

```asm
main:
    ADDI  a0, x0, 5      # arg: n = 5
    JAL   ra, factorial   # call factorial
    # a0 now holds result
    JAL   x0, main        # infinite loop (halt)

factorial:
    ADDI  sp, sp, -8     # (stack demo — skip if no memory)
    ADDI  t0, x0, 1
    BEQ   a0, t0, ret1   # if n == 1, return 1
    # (recursive case would need memory; use iterative instead)
ret1:
    ADDI  a0, x0, 1
    JALR  x0, ra, 0      # return
```

---

## 11. Not Implemented (Excluded from This Subset)

The following RV32I instructions are **excluded** from this processor:

| Category         | Instructions Excluded          | Reason                            |
|------------------|--------------------------------|-----------------------------------|
| Memory           | LB, LH, LW, LBU, LHU, SB, SH, SW | No data memory in Phase-1     |
| System           | ECALL, EBREAK, FENCE, CSR*    | No OS/debug support needed        |
| Multiply/Divide  | MUL, DIV, REM (RV32M)         | Separate extension                |
| Floating Point   | All F/D extensions             | Out of scope                      |

---

## 12. Revision History

| Version | Date       | Author                  | Change                         |
|---------|------------|-------------------------|--------------------------------|
| 1.0     | 2026-06-26 | Prabakaran Elaiyappan   | Initial release — 29-instruction subset |

---

*SynaptiqEdge Technologies Pvt Ltd · Chip Design Academy*
*DPIIT Recognised Startup | Rasipuram, Namakkal, Tamil Nadu*
