#!/usr/bin/env python3
"""
=============================================================================
  riscv_asm.py — RISC-V Subset Assembler
  Project  : SE-ISA-001 Single-Cycle Processor
  Author   : Prabakaran Elaiyappan | SynaptiqEdge Technologies
  Version  : 1.0

  Supports all 29 instructions defined in SE-ISA-001:
    R-type : ADD SUB AND OR XOR SLL SRL SRA SLT SLTU
    I-type : ADDI ANDI ORI XORI SLTI SLTIU SLLI SRLI SRAI JALR
    B-type : BEQ BNE BLT BGE BLTU BGEU
    U-type : LUI AUIPC
    J-type : JAL
    Pseudo : NOP MV LI NEG NOT BEQZ BNEZ BLTZ BGEZ J RET CALL

  Output : .hex file (one 8-hex-digit word per line, big-endian)
           Compatible with $readmemh

  Usage  :
    python3 riscv_asm.py program.asm -o program.hex
    python3 riscv_asm.py program.asm -o program.hex --verbose
    python3 riscv_asm.py program.asm --list          # print listing only
=============================================================================
"""

import sys
import re
import argparse
from typing import Optional

# ── Register name → number ───────────────────────────────────────────────────
REG_MAP: dict[str, int] = {
    'x0':0,  'x1':1,  'x2':2,  'x3':3,  'x4':4,  'x5':5,  'x6':6,  'x7':7,
    'x8':8,  'x9':9,  'x10':10,'x11':11,'x12':12,'x13':13,'x14':14,'x15':15,
    'x16':16,'x17':17,'x18':18,'x19':19,'x20':20,'x21':21,'x22':22,'x23':23,
    'x24':24,'x25':25,'x26':26,'x27':27,'x28':28,'x29':29,'x30':30,'x31':31,
    # ABI names
    'zero':0,'ra':1,'sp':2,'gp':3,'tp':4,
    't0':5,'t1':6,'t2':7,
    's0':8,'fp':8,'s1':9,
    'a0':10,'a1':11,'a2':12,'a3':13,'a4':14,'a5':15,'a6':16,'a7':17,
    's2':18,'s3':19,'s4':20,'s5':21,'s6':22,'s7':23,'s8':24,'s9':25,
    's10':26,'s11':27,
    't3':28,'t4':29,'t5':30,'t6':31,
}

def reg(name: str) -> int:
    """Resolve register name to integer index."""
    n = name.strip().lower()
    if n not in REG_MAP:
        raise ValueError(f"Unknown register: '{name}'")
    return REG_MAP[n]

def imm_val(tok: str, labels: dict[str, int], pc: int, signed_bits: int,
            pc_relative: bool = False) -> int:
    """
    Parse an immediate token.  Supports:
      decimal:  42  -7
      hex:      0xFF  0x1A
      binary:   0b101
      label:    loop_start  (resolved to PC-relative offset if pc_relative=True)
    Raises ValueError if out of range.
    """
    tok = tok.strip()
    if tok in labels:
        val = labels[tok]
        if pc_relative:
            val = val - pc    # byte offset from current instruction
    else:
        try:
            val = int(tok, 0)   # int() with base 0 handles 0x, 0b, 0o prefixes
        except ValueError:
            raise ValueError(f"Cannot resolve immediate/label: '{tok}'")

    # Sign-range check
    lo = -(1 << (signed_bits - 1))
    hi =  (1 << (signed_bits - 1)) - 1
    if not (lo <= val <= hi):
        raise ValueError(
            f"Immediate {val} out of {signed_bits}-bit signed range [{lo}, {hi}]"
        )
    return val & ((1 << signed_bits) - 1)   # return unsigned bit pattern

def uimm_val(tok: str, bits: int) -> int:
    """Parse an unsigned immediate (for LUI/AUIPC upper-20)."""
    tok = tok.strip()
    try:
        val = int(tok, 0)
    except ValueError:
        raise ValueError(f"Cannot parse unsigned immediate: '{tok}'")
    if not (0 <= val < (1 << bits)):
        raise ValueError(f"Unsigned immediate {val} out of {bits}-bit range")
    return val

# ── Encoding helpers ──────────────────────────────────────────────────────────

def r_type(funct7: int, rs2: int, rs1: int, funct3: int, rd: int, opcode: int) -> int:
    return ((funct7 & 0x7F) << 25 | (rs2 & 0x1F) << 20 | (rs1 & 0x1F) << 15 |
            (funct3 & 0x7) << 12 | (rd & 0x1F) << 7 | (opcode & 0x7F))

def i_type(imm12: int, rs1: int, funct3: int, rd: int, opcode: int) -> int:
    return ((imm12 & 0xFFF) << 20 | (rs1 & 0x1F) << 15 |
            (funct3 & 0x7) << 12 | (rd & 0x1F) << 7 | (opcode & 0x7F))

def b_type(imm13: int, rs2: int, rs1: int, funct3: int, opcode: int) -> int:
    # imm13 is a signed 13-bit offset (bit0 always 0)
    i = imm13 & 0x1FFF
    imm12   = (i >> 12) & 1
    imm11   = (i >> 11) & 1
    imm10_5 = (i >> 5)  & 0x3F
    imm4_1  = (i >> 1)  & 0xF
    return (imm12 << 31 | imm10_5 << 25 | (rs2 & 0x1F) << 20 |
            (rs1 & 0x1F) << 15 | (funct3 & 0x7) << 12 |
            imm4_1 << 8 | imm11 << 7 | (opcode & 0x7F))

def u_type(imm20: int, rd: int, opcode: int) -> int:
    return ((imm20 & 0xFFFFF) << 12 | (rd & 0x1F) << 7 | (opcode & 0x7F))

def j_type(imm21: int, rd: int, opcode: int) -> int:
    i = imm21 & 0x1FFFFF
    imm20    = (i >> 20) & 1
    imm19_12 = (i >> 12) & 0xFF
    imm11    = (i >> 11) & 1
    imm10_1  = (i >> 1)  & 0x3FF
    return (imm20 << 31 | imm10_1 << 21 | imm11 << 20 |
            imm19_12 << 12 | (rd & 0x1F) << 7 | (opcode & 0x7F))

# ── Opcodes / funct fields ────────────────────────────────────────────────────
OP_R    = 0b0110011
OP_I    = 0b0010011
OP_BR   = 0b1100011
OP_JAL  = 0b1101111
OP_JALR = 0b1100111
OP_LUI  = 0b0110111
OP_AUIPC= 0b0010111

# ── Assembler core ────────────────────────────────────────────────────────────

class Assembler:
    def __init__(self, verbose: bool = False):
        self.verbose = verbose

    def preprocess(self, lines: list[str]) -> list[tuple[int, str]]:
        """Strip comments and blank lines; return (original_lineno, cleaned_line)."""
        out = []
        for i, raw in enumerate(lines, 1):
            line = re.sub(r'[#;].*', '', raw).strip()   # remove # and ; comments
            if line:
                out.append((i, line))
        return out

    def first_pass(self, cleaned: list[tuple[int, str]]) -> tuple[dict[str, int], list[tuple[int, int, str]]]:
        """
        First pass: collect labels and their PC values.
        Returns labels dict and instruction-only list (lineno, pc, text).
        """
        labels: dict[str, int] = {}
        instrs: list[tuple[int, int, str]] = []
        pc = 0
        for lineno, line in cleaned:
            # Split off any label prefix  "loop:" or "done: ADDI ..."
            parts = line.split(':', 1)
            if len(parts) == 2 and re.match(r'^\w+$', parts[0].strip()):
                lbl = parts[0].strip()
                if lbl in labels:
                    raise SyntaxError(f"Line {lineno}: duplicate label '{lbl}'")
                labels[lbl] = pc
                line = parts[1].strip()
                if not line:
                    continue   # label-only line
            instrs.append((lineno, pc, line))
            pc += 4
        return labels, instrs

    def assemble_one(self, lineno: int, pc: int, line: str,
                     labels: dict[str, int]) -> list[int]:
        """
        Assemble one instruction line into a list of 32-bit words.
        Most instructions produce one word; pseudo-instructions may produce two.
        """
        # Normalise: split on whitespace and commas
        tokens = re.split(r'[\s,]+', line.strip())
        mnemonic = tokens[0].upper()
        args = tokens[1:]

        def A(i): return args[i]   # shorthand

        # ── Pseudo-instructions ───────────────────────────────────────────────
        if mnemonic == 'NOP':
            # ADDI x0, x0, 0
            return [i_type(0, 0, 0b000, 0, OP_I)]

        if mnemonic == 'MV':
            # MV rd, rs → ADDI rd, rs, 0
            rd, rs = reg(A(0)), reg(A(1))
            return [i_type(0, rs, 0b000, rd, OP_I)]

        if mnemonic == 'LI':
            # LI rd, imm → LUI + ADDI  (or just ADDI if imm fits 12-bit)
            rd = reg(A(0))
            v = int(A(1), 0)
            if -2048 <= v <= 2047:
                imm12 = v & 0xFFF
                return [i_type(imm12, 0, 0b000, rd, OP_I)]
            else:
                # Split into upper 20 and signed lower 12
                lo12 = v & 0xFFF
                if lo12 >= 0x800:   # lower 12 is negative when treated as signed
                    lo12 -= 0x1000
                hi20 = (v - lo12) >> 12
                w1 = u_type(hi20 & 0xFFFFF, rd, OP_LUI)
                w2 = i_type(lo12 & 0xFFF, rd, 0b000, rd, OP_I)
                return [w1, w2]

        if mnemonic == 'NEG':
            # NEG rd, rs → SUB rd, x0, rs
            rd, rs = reg(A(0)), reg(A(1))
            return [r_type(0b0100000, rs, 0, 0b000, rd, OP_R)]

        if mnemonic == 'NOT':
            # NOT rd, rs → XORI rd, rs, -1
            rd, rs = reg(A(0)), reg(A(1))
            return [i_type(0xFFF, rs, 0b100, rd, OP_I)]

        if mnemonic == 'BEQZ':
            rd, lbl = reg(A(0)), A(1)
            off = imm_val(lbl, labels, pc, 13, pc_relative=True)
            return [b_type(off, 0, rd, 0b000, OP_BR)]

        if mnemonic == 'BNEZ':
            rd, lbl = reg(A(0)), A(1)
            off = imm_val(lbl, labels, pc, 13, pc_relative=True)
            return [b_type(off, 0, rd, 0b001, OP_BR)]

        if mnemonic == 'BLTZ':
            rd, lbl = reg(A(0)), A(1)
            off = imm_val(lbl, labels, pc, 13, pc_relative=True)
            return [b_type(off, 0, rd, 0b100, OP_BR)]

        if mnemonic == 'BGEZ':
            rd, lbl = reg(A(0)), A(1)
            off = imm_val(lbl, labels, pc, 13, pc_relative=True)
            return [b_type(off, 0, rd, 0b101, OP_BR)]

        if mnemonic == 'J':
            # J label → JAL x0, label
            lbl = A(0)
            off = imm_val(lbl, labels, pc, 21, pc_relative=True)
            return [j_type(off, 0, OP_JAL)]

        if mnemonic == 'RET':
            # RET → JALR x0, ra, 0
            return [i_type(0, 1, 0b000, 0, OP_JALR)]

        if mnemonic == 'CALL':
            # CALL label → JAL ra, label
            lbl = A(0)
            off = imm_val(lbl, labels, pc, 21, pc_relative=True)
            return [j_type(off, 1, OP_JAL)]

        if mnemonic == 'HALT':
            # HALT → JAL x0, 0  (infinite loop to self; sentinel for TB)
            return [j_type(0, 0, OP_JAL)]


        # ── Store instructions: SW/SH/SB ─────────────────────────────────────
        STORE_OPS = {'SB': 0b000, 'SH': 0b001, 'SW': 0b010}
        if mnemonic in STORE_OPS:
            fn3 = STORE_OPS[mnemonic]
            rs2_r = reg(A(0))
            rest  = A(1)
            m2 = re.match(r'(-?\w+)\((\w+)\)', rest.replace(' ',''))
            if m2:
                i12 = imm_val(m2.group(1), labels, pc, 12)
                rs1_r = reg(m2.group(2))
            else:
                rs1_r = reg(A(1)); i12 = imm_val(A(2), labels, pc, 12)
            imm_lo = i12 & 0x1F; imm_hi = (i12 >> 5) & 0x7F
            return [((imm_hi<<25)|(rs2_r<<20)|(rs1_r<<15)|(fn3<<12)|(imm_lo<<7)|0b0100011) & 0xFFFFFFFF]

        # ── Load instructions: LW/LH/LB/LHU/LBU ──────────────────────────────
        LOAD_OPS = {'LB':0b000,'LH':0b001,'LW':0b010,'LBU':0b100,'LHU':0b101}
        if mnemonic in LOAD_OPS:
            fn3 = LOAD_OPS[mnemonic]; rd_r = reg(A(0))
            rest = A(1)
            m2 = re.match(r'(-?\w+)\((\w+)\)', rest.replace(' ',''))
            if m2:
                i12 = imm_val(m2.group(1), labels, pc, 12)
                rs1_r = reg(m2.group(2))
            else:
                rs1_r = reg(A(1)); i12 = imm_val(A(2), labels, pc, 12)
            return [i_type(i12, rs1_r, fn3, rd_r, 0b0000011)]

        # ── R-type ───────────────────────────────────────────────────────────
        R_OPS = {
            'ADD':  (0b0000000, 0b000),
            'SUB':  (0b0100000, 0b000),
            'AND':  (0b0000000, 0b111),
            'OR':   (0b0000000, 0b110),
            'XOR':  (0b0000000, 0b100),
            'SLL':  (0b0000000, 0b001),
            'SRL':  (0b0000000, 0b101),
            'SRA':  (0b0100000, 0b101),
            'SLT':  (0b0000000, 0b010),
            'SLTU': (0b0000000, 0b011),
        }
        if mnemonic in R_OPS:
            fn7, fn3 = R_OPS[mnemonic]
            rd, rs1, rs2 = reg(A(0)), reg(A(1)), reg(A(2))
            return [r_type(fn7, rs2, rs1, fn3, rd, OP_R)]

        # ── I-type ALU ────────────────────────────────────────────────────────
        I_OPS = {
            'ADDI':  0b000,
            'ANDI':  0b111,
            'ORI':   0b110,
            'XORI':  0b100,
            'SLTI':  0b010,
            'SLTIU': 0b011,
        }
        if mnemonic in I_OPS:
            fn3 = I_OPS[mnemonic]
            rd, rs1 = reg(A(0)), reg(A(1))
            i = imm_val(A(2), labels, pc, 12)
            return [i_type(i, rs1, fn3, rd, OP_I)]

        # ── Shift immediate ───────────────────────────────────────────────────
        if mnemonic in ('SLLI', 'SRLI', 'SRAI'):
            rd, rs1 = reg(A(0)), reg(A(1))
            shamt = int(A(2), 0)
            if not (0 <= shamt <= 31):
                raise ValueError(f"Shift amount {shamt} out of range [0,31]")
            fn7 = 0b0100000 if mnemonic == 'SRAI' else 0b0000000
            fn3 = {'SLLI':0b001,'SRLI':0b101,'SRAI':0b101}[mnemonic]
            imm12 = (fn7 << 5) | shamt
            return [i_type(imm12, rs1, fn3, rd, OP_I)]

        # ── LUI / AUIPC ───────────────────────────────────────────────────────
        if mnemonic == 'LUI':
            rd = reg(A(0))
            v = int(A(1), 0)
            # v is the 20-bit upper immediate; result = v << 12
            # If user passes full 32-bit value (e.g. 0x40000000), shift down
            if v >= (1 << 20):
                v >>= 12
            return [u_type(v & 0xFFFFF, rd, OP_LUI)]

        if mnemonic == 'AUIPC':
            rd = reg(A(0))
            v = int(A(1), 0)
            if v >= (1 << 20):
                v >>= 12
            return [u_type(v & 0xFFFFF, rd, OP_AUIPC)]

        # ── Branch ────────────────────────────────────────────────────────────
        BR_OPS = {
            'BEQ':  0b000,
            'BNE':  0b001,
            'BLT':  0b100,
            'BGE':  0b101,
            'BLTU': 0b110,
            'BGEU': 0b111,
        }
        if mnemonic in BR_OPS:
            fn3 = BR_OPS[mnemonic]
            rs1, rs2, lbl = reg(A(0)), reg(A(1)), A(2)
            off = imm_val(lbl, labels, pc, 13, pc_relative=True)
            return [b_type(off, rs2, rs1, fn3, OP_BR)]

        # ── JAL ───────────────────────────────────────────────────────────────
        if mnemonic == 'JAL':
            rd = reg(A(0))
            off = imm_val(A(1), labels, pc, 21, pc_relative=True)
            return [j_type(off, rd, OP_JAL)]

        # ── JALR ──────────────────────────────────────────────────────────────
        if mnemonic == 'JALR':
            # Syntax: JALR rd, rs1, imm  OR  JALR rd, imm(rs1)
            rd = reg(A(0))
            rest = ' '.join(args[1:])
            m = re.match(r'(-?\w+)\((\w+)\)', rest.replace(' ', ''))
            if m:
                i = imm_val(m.group(1), labels, pc, 12)
                rs1 = reg(m.group(2))
            else:
                rs1 = reg(A(1))
                i   = imm_val(A(2), labels, pc, 12)
            return [i_type(i, rs1, 0b000, rd, OP_JALR)]

        # ── .word directive ───────────────────────────────────────────────────
        if mnemonic == '.WORD':
            return [int(A(0), 0) & 0xFFFFFFFF]

        raise SyntaxError(f"Line {lineno}: unknown mnemonic '{mnemonic}'")

    def assemble(self, source: str) -> tuple[list[int], list[str]]:
        """
        Full two-pass assembly.
        Returns (word_list, listing_lines).
        """
        raw_lines = source.splitlines()
        cleaned   = self.preprocess(raw_lines)
        labels, instrs = self.first_pass(cleaned)

        if self.verbose:
            print(f"[ASM] Labels: {labels}")

        words: list[int] = []
        listing: list[str] = []

        # PC counters for multi-word pseudos
        pc = 0
        for lineno, instr_pc, line in instrs:
            try:
                encoded = self.assemble_one(lineno, instr_pc, line, labels)
            except Exception as e:
                raise SyntaxError(f"Line {lineno}: {e}") from e

            for w in encoded:
                hex_w = f"{w & 0xFFFFFFFF:08X}"
                listing.append(f"  0x{pc:04X}  {hex_w}    # {line}")
                words.append(w & 0xFFFFFFFF)
                pc += 4

        return words, listing

# ── CLI ───────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description='RISC-V Subset Assembler (SE-ISA-001)'
    )
    parser.add_argument('input',          help='Assembly source file (.asm)')
    parser.add_argument('-o', '--output', help='Output hex file (.hex)', default=None)
    parser.add_argument('--verbose',      action='store_true', help='Verbose output')
    parser.add_argument('--list',         action='store_true', help='Print listing')
    args = parser.parse_args()

    with open(args.input) as f:
        source = f.read()

    asm = Assembler(verbose=args.verbose)
    try:
        words, listing = asm.assemble(source)
    except SyntaxError as e:
        print(f"[ASM ERROR] {e}", file=sys.stderr)
        sys.exit(1)

    if args.list or args.verbose:
        print("\n=== Assembly Listing ===")
        for l in listing:
            print(l)
        print(f"=== {len(words)} words assembled ===\n")

    out_path = args.output or (args.input.rsplit('.', 1)[0] + '.hex')
    with open(out_path, 'w') as f:
        for w in words:
            f.write(f"{w:08X}\n")

    print(f"[ASM] Assembled {len(words)} words → {out_path}")

if __name__ == '__main__':
    main()
