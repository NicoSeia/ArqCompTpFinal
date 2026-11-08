#!/usr/bin/env python3
"""
golden_model.py - Modelo de referencia (ISS) del procesador del TP.

Lee un programa en assembler (.asm), lo ensambla con assembler.py, lo ejecuta
instruccion por instruccion y escribe el resultado esperado en un .txt:
    python3 golden_model.py tests/programa.asm -o out/golden_out.txt

Replica el CONTRATO del RTL (no el RISC-V estandar completo):
  - Subset: R-type, I-type, lb/lh/lw/lbu/lhu, sb/sh/sw, beq/bne, lui, jal, jalr.
  - Cualquier otra palabra (incluida 0x00000000 = halt) -> instruccion ilegal -> halt code 2.
  - El programa termina cuando el PC llega a len*4 -> halt code 1.
  - x0 fijo en 0, shifts usan b[4:0], jalr limpia bit0, link = pc+4.
  - dmem de 4 KiB, little-endian. Store h/w desalineado se ignora;
    lh/lw desalineado devuelve 0 (comportamiento del RTL).
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from assembler import assemble  # noqa: E402

MASK = 0xFFFFFFFF
DMEM_BYTES = 4096
IMEM_WORDS = 1024
MEM_DUMP_BYTES = 640          # cuantos bytes de dmem se comparan (desde addr 0)
MAX_STEPS = 200000            # proteccion contra bucles infinitos


def sext(v, bits):
    v &= (1 << bits) - 1
    return v - (1 << bits) if v >> (bits - 1) else v


class Illegal(Exception):
    pass


class GoldenModel:
    def __init__(self, words):
        if len(words) > IMEM_WORDS:
            raise ValueError(f"programa de {len(words)} palabras, la imem tiene {IMEM_WORDS}")
        self.words = list(words)
        self.regs = [0] * 32
        self.mem = bytearray(DMEM_BYTES)
        self.pc = 0
        self.halt_code = 0
        self.instr_count = 0

    # --- memoria ---
    def load(self, addr, size, unsigned):
        a = addr & (DMEM_BYTES - 1)
        if size == 1:
            v = self.mem[a]
            return v if unsigned else sext(v, 8) & MASK
        if size == 2:
            if a & 1:
                return 0
            v = self.mem[a] | (self.mem[a + 1] << 8)
            return v if unsigned else sext(v, 16) & MASK
        if a & 3:
            return 0
        return int.from_bytes(self.mem[a:a + 4], "little")

    def store(self, addr, size, value):
        a = addr & (DMEM_BYTES - 1)
        if size == 1:
            self.mem[a] = value & 0xFF
        elif size == 2:
            if not (a & 1):
                self.mem[a:a + 2] = (value & 0xFFFF).to_bytes(2, "little")
        else:
            if not (a & 3):
                self.mem[a:a + 4] = (value & MASK).to_bytes(4, "little")

    def wr(self, rd, v):
        if rd != 0:
            self.regs[rd] = v & MASK

    # --- ejecucion ---
    def step(self):
        """Ejecuta una instruccion. Devuelve False si el programa termino."""
        idx = self.pc >> 2
        if idx >= len(self.words):
            self.halt_code = 1
            return False
        ins = self.words[idx]
        op = ins & 0x7F
        rd = (ins >> 7) & 0x1F
        f3 = (ins >> 12) & 0x7
        rs1 = (ins >> 15) & 0x1F
        rs2 = (ins >> 20) & 0x1F
        f7 = (ins >> 25) & 0x7F
        a = self.regs[rs1]
        b = self.regs[rs2]
        next_pc = (self.pc + 4) & MASK

        if op == 0b0110011:  # R-type
            sh = b & 31
            if f3 == 0 and f7 == 0:      r = a + b
            elif f3 == 0 and f7 == 0x20: r = a - b
            elif f3 == 1 and f7 == 0:    r = a << sh
            elif f3 == 2 and f7 == 0:    r = int(sext(a, 32) < sext(b, 32))
            elif f3 == 3 and f7 == 0:    r = int(a < b)
            elif f3 == 4 and f7 == 0:    r = a ^ b
            elif f3 == 5 and f7 == 0:    r = a >> sh
            elif f3 == 5 and f7 == 0x20: r = sext(a, 32) >> sh
            elif f3 == 6 and f7 == 0:    r = a | b
            elif f3 == 7 and f7 == 0:    r = a & b
            else: raise Illegal
            self.wr(rd, r)
        elif op == 0b0010011:  # I-type ALU
            imm = sext(ins >> 20, 12)
            sh = (ins >> 20) & 31
            if f3 == 0:   r = a + imm
            elif f3 == 2: r = int(sext(a, 32) < imm)
            elif f3 == 3: r = int(a < (imm & MASK))
            elif f3 == 4: r = a ^ (imm & MASK)
            elif f3 == 6: r = a | (imm & MASK)
            elif f3 == 7: r = a & (imm & MASK)
            elif f3 == 1 and f7 == 0:    r = a << sh
            elif f3 == 5 and f7 == 0:    r = a >> sh
            elif f3 == 5 and f7 == 0x20: r = sext(a, 32) >> sh
            else: raise Illegal
            self.wr(rd, r)
        elif op == 0b0000011:  # loads
            imm = sext(ins >> 20, 12)
            addr = (a + imm) & MASK
            table = {0: (1, False), 1: (2, False), 2: (4, False), 4: (1, True), 5: (2, True)}
            if f3 not in table:
                raise Illegal
            size, uns = table[f3]
            self.wr(rd, self.load(addr, size, uns))
        elif op == 0b0100011:  # stores
            imm = sext(((ins >> 25) << 5) | ((ins >> 7) & 0x1F), 12)
            addr = (a + imm) & MASK
            if f3 not in (0, 1, 2):
                raise Illegal
            self.store(addr, 1 << f3, b)
        elif op == 0b1100011:  # branches (solo beq/bne)
            if f3 not in (0, 1):
                raise Illegal
            imm = sext(((ins >> 31) << 12) | (((ins >> 7) & 1) << 11) |
                       (((ins >> 25) & 0x3F) << 5) | (((ins >> 8) & 0xF) << 1), 13)
            if (a == b) == (f3 == 0):
                next_pc = (self.pc + imm) & MASK
        elif op == 0b0110111:  # lui
            self.wr(rd, ins & 0xFFFFF000)
        elif op == 0b1101111:  # jal
            imm = sext(((ins >> 31) << 20) | (((ins >> 12) & 0xFF) << 12) |
                       (((ins >> 20) & 1) << 11) | (((ins >> 21) & 0x3FF) << 1), 21)
            self.wr(rd, self.pc + 4)
            next_pc = (self.pc + imm) & MASK
        elif op == 0b1100111:  # jalr
            if f3 != 0:
                raise Illegal
            imm = sext(ins >> 20, 12)
            target = (a + imm) & MASK & ~1
            self.wr(rd, self.pc + 4)
            next_pc = target
        else:
            raise Illegal

        self.pc = next_pc
        self.instr_count += 1
        return True

    def run(self):
        for _ in range(MAX_STEPS):
            try:
                if not self.step():
                    return
            except Illegal:
                self.halt_code = 2
                return
        raise RuntimeError("el programa no termina (bucle infinito?)")


def format_state(halt_code, regs, mem):
    lines = [f"halt_code = {halt_code}"]
    for i, v in enumerate(regs):
        lines.append(f"x{i} = 0x{v & MASK:08X}")
    for off in range(0, len(mem), 4):
        w = int.from_bytes(mem[off:off + 4], "little")
        lines.append(f"mem[0x{off:04X}] = 0x{w:08X}")
    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser(description="Golden model del procesador RISC-V del TP")
    ap.add_argument("asm", help="programa en assembler (.asm / .txt)")
    ap.add_argument("-o", "--output", default="out/golden_out.txt")
    args = ap.parse_args()

    words = assemble(Path(args.asm).read_text())
    gm = GoldenModel(words)
    gm.run()
    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(format_state(gm.halt_code, gm.regs, gm.mem[:MEM_DUMP_BYTES]))
    print(f"[golden] {len(words)} palabras, {gm.instr_count} instrucciones ejecutadas, "
          f"halt_code={gm.halt_code} -> {out}")


if __name__ == "__main__":
    main()