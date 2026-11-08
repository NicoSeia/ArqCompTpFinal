#!/usr/bin/env python3
"""
assembler.py

Ensamblador de dos pasadas para el subset RV32I del trabajo final
(pipeline RISC-V segmentado + Debug Unit por UART). Traduce un archivo
de texto en assembly a una lista de palabras de 32 bits, con el mismo
encoding que decodifican control_unit.sv / imm_gen.sv del lado del
hardware -- no hay ninguna regla nueva acá, es la codificación de
control_unit.sv escrita como programa en vez de como circuito.

Instrucciones soportadas (las mismas del subset de la consigna):
    R-type : add sub sll srl sra and or xor slt sltu
    I-type : lb lh lw lbu lhu addi andi ori xori slti sltiu slli srli srai jalr
    S-type : sb sh sw
    B-type : beq bne
    U-type : lui
    J-type : jal
    Pseudo : nop (-> addi x0,x0,0), halt (-> 0x00000000, dispara el halt
             por instrucción ilegal ya construido en pipeline_top.sv)

Uso como script:
    python3 assembler.py programa.asm -o programa.hex

Uso como módulo (para cuando se arme la interfaz del paso 7):
    from assembler import assemble
    words = assemble(texto_fuente)   # -> list[int], uno por instrucción
"""

import argparse
import re
import sys


# =============================================================================
# Opcodes (7 bits) -- los mismos valores que OP_R, OP_IMM, etc. en riscv_pkg.sv
# =============================================================================

OP_R      = 0b0110011
OP_I_ALU  = 0b0010011
OP_LOAD   = 0b0000011
OP_JALR   = 0b1100111
OP_STORE  = 0b0100011
OP_BRANCH = 0b1100011
OP_LUI    = 0b0110111
OP_JAL    = 0b1101111


# =============================================================================
# Tabla de encoding: mnemónico -> (formato, opcode, funct3, funct7)
# "formato" decide cómo se parsean los operandos y qué encoder se usa.
# funct7 es None cuando no aplica (todo lo que no sea R-type, o el bit alto
# de slli/srli/srai que se arma con el shift amount).
# =============================================================================

INSTR_TABLE = {
    # R-type: mnem rd, rs1, rs2
    "add":  ("R", OP_R, 0b000, 0b0000000),
    "sub":  ("R", OP_R, 0b000, 0b0100000),
    "sll":  ("R", OP_R, 0b001, 0b0000000),
    "slt":  ("R", OP_R, 0b010, 0b0000000),
    "sltu": ("R", OP_R, 0b011, 0b0000000),
    "xor":  ("R", OP_R, 0b100, 0b0000000),
    "srl":  ("R", OP_R, 0b101, 0b0000000),
    "sra":  ("R", OP_R, 0b101, 0b0100000),
    "or":   ("R", OP_R, 0b110, 0b0000000),
    "and":  ("R", OP_R, 0b111, 0b0000000),

    # I-type ALU inmediato: mnem rd, rs1, imm
    "addi":  ("I", OP_I_ALU, 0b000, None),
    "slti":  ("I", OP_I_ALU, 0b010, None),
    "sltiu": ("I", OP_I_ALU, 0b011, None),
    "xori":  ("I", OP_I_ALU, 0b100, None),
    "ori":   ("I", OP_I_ALU, 0b110, None),
    "andi":  ("I", OP_I_ALU, 0b111, None),

    # I-type shift inmediato: mnem rd, rs1, shamt (0-31) -- el funct7 se
    # empaqueta junto con shamt en el campo de inmediato, no es un operando
    "slli": ("I_SHIFT", OP_I_ALU, 0b001, 0b0000000),
    "srli": ("I_SHIFT", OP_I_ALU, 0b101, 0b0000000),
    "srai": ("I_SHIFT", OP_I_ALU, 0b101, 0b0100000),

    # I-type load: mnem rd, offset(rs1)
    "lb":  ("LOAD", OP_LOAD, 0b000, None),
    "lh":  ("LOAD", OP_LOAD, 0b001, None),
    "lw":  ("LOAD", OP_LOAD, 0b010, None),
    "lbu": ("LOAD", OP_LOAD, 0b100, None),
    "lhu": ("LOAD", OP_LOAD, 0b101, None),

    # I-type jalr: mnem rd, offset(rs1)
    "jalr": ("JALR", OP_JALR, 0b000, None),

    # S-type: mnem rs2, offset(rs1)  (rs2 es el dato a guardar)
    "sb": ("S", OP_STORE, 0b000, None),
    "sh": ("S", OP_STORE, 0b001, None),
    "sw": ("S", OP_STORE, 0b010, None),

    # B-type: mnem rs1, rs2, target  (target: etiqueta o número)
    "beq": ("B", OP_BRANCH, 0b000, None),
    "bne": ("B", OP_BRANCH, 0b001, None),

    # U-type: mnem rd, imm20  (imm20 es el valor YA corrido, ej. lui x7,1 -> 0x1000)
    "lui": ("U", OP_LUI, None, None),

    # J-type: mnem rd, target  (target: etiqueta o número)
    "jal": ("J", OP_JAL, None, None),
}


# =============================================================================
# Errores
# =============================================================================

class AssemblerError(Exception):
    def __init__(self, msg, line_no=None):
        self.line_no = line_no
        full = f"línea {line_no}: {msg}" if line_no else msg
        super().__init__(full)


def check_range(value, lo, hi, line_no, mnem):
    if not (lo <= value <= hi):
        raise AssemblerError(
            f"inmediato fuera de rango para '{mnem}': {value} "
            f"(debe estar entre {lo} y {hi})", line_no)


# =============================================================================
# Parsing de operandos
# =============================================================================

_REG_RE = re.compile(r'^x(\d+)$')
_OFFSET_RE = re.compile(r'^\s*(-?(?:0[xX][0-9a-fA-F]+|\d+))\s*\(\s*(x\d+)\s*\)\s*$')


def parse_reg(tok, line_no):
    tok = tok.strip()
    m = _REG_RE.match(tok)
    if not m:
        raise AssemblerError(f"registro inválido: '{tok}' (se esperaba x0-x31)", line_no)
    n = int(m.group(1))
    if not (0 <= n <= 31):
        raise AssemblerError(f"registro fuera de rango: '{tok}' (debe ser x0-x31)", line_no)
    return n


def parse_imm(tok, line_no):
    tok = tok.strip()
    try:
        return int(tok, 0)  # soporta decimal ("42") y hex ("0x2A") automáticamente
    except ValueError:
        raise AssemblerError(f"inmediato inválido: '{tok}'", line_no)


def parse_offset_reg(tok, line_no):
    """Parsea la sintaxis 'offset(registro)' que usan loads, stores y jalr."""
    m = _OFFSET_RE.match(tok.strip())
    if not m:
        raise AssemblerError(
            f"formato inválido, se esperaba 'offset(registro)': '{tok}'", line_no)
    imm = int(m.group(1), 0)
    reg = parse_reg(m.group(2), line_no)
    return imm, reg


def tokenize_operands(s):
    return [t.strip() for t in s.split(',') if t.strip()]


def resolve_target(token, current_addr, symtab, line_no):
    """El operando de un branch/jump puede ser una etiqueta o un número
    directo (offset ya calculado a mano, por si hace falta)."""
    token = token.strip()
    if token in symtab:
        return symtab[token] - current_addr
    try:
        return int(token, 0)
    except ValueError:
        raise AssemblerError(f"etiqueta no definida: '{token}'", line_no)


# =============================================================================
# Encoders -- uno por formato, misma disposición de bits que ya usamos en
# los helpers rtype/itype/stype/btype/utype/jtype de los testbenches en SV.
# =============================================================================

def enc_r(funct7, rs2, rs1, funct3, rd, opcode):
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def enc_i(imm, rs1, funct3, rd, opcode):
    imm &= 0xFFF
    return (imm << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def enc_s(imm, rs2, rs1, funct3, opcode):
    imm &= 0xFFF
    imm_11_5 = (imm >> 5) & 0x7F
    imm_4_0 = imm & 0x1F
    return (imm_11_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (imm_4_0 << 7) | opcode


def enc_b(imm, rs2, rs1, funct3, opcode):
    imm &= 0x1FFF  # 13 bits (bit 0 siempre 0, implícito)
    bit12 = (imm >> 12) & 0x1
    bit11 = (imm >> 11) & 0x1
    bits10_5 = (imm >> 5) & 0x3F
    bits4_1 = (imm >> 1) & 0xF
    return (bit12 << 31) | (bits10_5 << 25) | (rs2 << 20) | (rs1 << 15) | \
           (funct3 << 12) | (bits4_1 << 8) | (bit11 << 7) | opcode


def enc_u(imm20, rd, opcode):
    imm20 &= 0xFFFFF  # 20 bits
    return (imm20 << 12) | (rd << 7) | opcode


def enc_j(imm, rd, opcode):
    imm &= 0x1FFFFF  # 21 bits (bit 0 siempre 0, implícito)
    bit20 = (imm >> 20) & 0x1
    bits19_12 = (imm >> 12) & 0xFF
    bit11 = (imm >> 11) & 0x1
    bits10_1 = (imm >> 1) & 0x3FF
    return (bit20 << 31) | (bits10_1 << 21) | (bit11 << 20) | (bits19_12 << 12) | (rd << 7) | opcode


# =============================================================================
# Pasada 1: barre el archivo, arma la tabla de símbolos (etiqueta -> dirección)
# =============================================================================

_LABEL_RE = re.compile(r'^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$')


def strip_comment(line):
    for marker in ('#', '//'):
        idx = line.find(marker)
        if idx != -1:
            line = line[:idx]
    return line.strip()


def first_pass(lines):
    """Devuelve (instrucciones, tabla_de_símbolos).
    instrucciones: lista de (dirección, mnemónico, operandos_crudos, línea_original)
    """
    symtab = {}
    instrs = []
    addr = 0

    for line_no, raw in enumerate(lines, start=1):
        line = strip_comment(raw)
        if not line:
            continue

        m = _LABEL_RE.match(line)
        if m:
            label, rest = m.group(1), m.group(2).strip()
            if label in symtab:
                raise AssemblerError(f"etiqueta duplicada: '{label}'", line_no)
            symtab[label] = addr
            line = rest
            if not line:
                continue

        parts = line.split(None, 1)
        mnem = parts[0].lower()
        operand_str = parts[1] if len(parts) > 1 else ""

        instrs.append((addr, mnem, operand_str, line_no))
        addr += 4

    return instrs, symtab


# =============================================================================
# Pasada 2: traduce cada instrucción a su palabra de 32 bits
# =============================================================================

def second_pass(instrs, symtab):
    words = []

    for addr, mnem, operand_str, line_no in instrs:

        if mnem == "halt":
            words.append(0x00000000)
            continue

        if mnem == "nop":
            words.append(enc_i(0, 0, 0b000, 0, OP_I_ALU))
            continue

        if mnem not in INSTR_TABLE:
            raise AssemblerError(f"instrucción desconocida: '{mnem}'", line_no)

        fmt, opcode, funct3, funct7 = INSTR_TABLE[mnem]
        ops = tokenize_operands(operand_str)

        try:
            if fmt == "R":
                rd = parse_reg(ops[0], line_no)
                rs1 = parse_reg(ops[1], line_no)
                rs2 = parse_reg(ops[2], line_no)
                word = enc_r(funct7, rs2, rs1, funct3, rd, opcode)

            elif fmt == "I":
                rd = parse_reg(ops[0], line_no)
                rs1 = parse_reg(ops[1], line_no)
                imm = parse_imm(ops[2], line_no)
                check_range(imm, -2048, 2047, line_no, mnem)
                word = enc_i(imm, rs1, funct3, rd, opcode)

            elif fmt == "I_SHIFT":
                rd = parse_reg(ops[0], line_no)
                rs1 = parse_reg(ops[1], line_no)
                shamt = parse_imm(ops[2], line_no)
                check_range(shamt, 0, 31, line_no, mnem)
                packed_imm = (funct7 << 5) | shamt
                word = enc_i(packed_imm, rs1, funct3, rd, opcode)

            elif fmt == "LOAD":
                rd = parse_reg(ops[0], line_no)
                imm, rs1 = parse_offset_reg(ops[1], line_no)
                check_range(imm, -2048, 2047, line_no, mnem)
                word = enc_i(imm, rs1, funct3, rd, opcode)

            elif fmt == "JALR":
                rd = parse_reg(ops[0], line_no)
                imm, rs1 = parse_offset_reg(ops[1], line_no)
                check_range(imm, -2048, 2047, line_no, mnem)
                word = enc_i(imm, rs1, funct3, rd, opcode)

            elif fmt == "S":
                rs2 = parse_reg(ops[0], line_no)
                imm, rs1 = parse_offset_reg(ops[1], line_no)
                check_range(imm, -2048, 2047, line_no, mnem)
                word = enc_s(imm, rs2, rs1, funct3, opcode)

            elif fmt == "B":
                rs1 = parse_reg(ops[0], line_no)
                rs2 = parse_reg(ops[1], line_no)
                imm = resolve_target(ops[2], addr, symtab, line_no)
                if imm % 2 != 0:
                    raise AssemblerError(
                        f"el offset de '{mnem}' tiene que ser par (bit 0 implícito), dio {imm}", line_no)
                check_range(imm, -4096, 4094, line_no, mnem)
                word = enc_b(imm, rs2, rs1, funct3, opcode)

            elif fmt == "U":
                rd = parse_reg(ops[0], line_no)
                imm20 = parse_imm(ops[1], line_no)
                check_range(imm20, 0, 0xFFFFF, line_no, mnem)
                word = enc_u(imm20, rd, opcode)

            elif fmt == "J":
                rd = parse_reg(ops[0], line_no)
                imm = resolve_target(ops[1], addr, symtab, line_no)
                if imm % 2 != 0:
                    raise AssemblerError(
                        f"el offset de '{mnem}' tiene que ser par (bit 0 implícito), dio {imm}", line_no)
                check_range(imm, -1048576, 1048574, line_no, mnem)
                word = enc_j(imm, rd, opcode)

            else:
                raise AssemblerError(f"formato interno desconocido para '{mnem}'", line_no)

        except IndexError:
            raise AssemblerError(f"faltan operandos para '{mnem}'", line_no)

        words.append(word & 0xFFFFFFFF)

    return words


# =============================================================================
# API pública
# =============================================================================

def assemble(source_text):
    """Traduce el texto fuente completo a una lista de palabras de 32 bits."""
    lines = source_text.splitlines()
    instrs, symtab = first_pass(lines)
    return second_pass(instrs, symtab)


def main():
    parser = argparse.ArgumentParser(
        description="Ensamblador para el subset RV32I del trabajo final (pipeline + Debug Unit UART)")
    parser.add_argument("input", help="archivo .asm de entrada")
    parser.add_argument("-o", "--output", help="archivo .hex de salida (default: mismo nombre, extensión .hex)")
    args = parser.parse_args()

    with open(args.input) as f:
        source = f.read()

    try:
        words = assemble(source)
    except AssemblerError as e:
        print(f"Error de ensamblado: {e}", file=sys.stderr)
        sys.exit(1)

    out_path = args.output or (args.input.rsplit(".", 1)[0] + ".hex")
    with open(out_path, "w") as f:
        for w in words:
            f.write(f"{w:08X}\n")

    print(f"OK: {len(words)} instrucciones -> {out_path}")


if __name__ == "__main__":
    main()