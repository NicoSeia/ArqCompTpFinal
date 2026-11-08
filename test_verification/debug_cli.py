#!/usr/bin/env python3
"""
dbg_cli.py -- CLI interactiva para la Debug Unit del pipeline RISC-V (UART 9600 8N1).

Uso:
    python dbg_cli.py --port COM8                 # modo interactivo
    python dbg_cli.py --port COM8 -x "load p.asm" -x run -x regs   # comandos sueltos
    python dbg_cli.py --port COM8 -f sesion.txt   # script con un comando por linea

Comandos (help <cmd> para detalle):
    reset                 limpia imem (NOP), pipeline y regfile; load_addr = 0
    load <archivo>        .asm (se ensambla) o .hex (una palabra hex por linea); hace reset antes
    run                   modo continuo: corre hasta el halt y muestra el motivo
    step [n]              n ciclos (default 1); muestra latches y registros que cambiaron
    regs                  los 32 registros (hex y decimal)
    latches               IF/ID, ID/EX, EX/MEM y MEM/WB decodificados
    mem <addr> [bytes]    volcado de memoria de datos (default 64 bytes)
    auto on|off           mostrar latches automaticamente en cada step (default on)
    quit

Protocolo (little-endian): 0x00 RESET | 0x01+4B LOAD_WORD | 0x02 RUN -> 1B halt_code
0x03 STEP -> 1B halt_code | 0x04 DUMP_REGS -> 128B | 0x05 DUMP_LATCHES -> 70B
0x06+addr(2B)+len(2B) DUMP_MEM -> len B.
"""
import argparse
import cmd
import os
import shlex
import sys
import time

OP_RESET, OP_LOAD, OP_RUN, OP_STEP = 0x00, 0x01, 0x02, 0x03
OP_REGS, OP_LATCHES, OP_MEM = 0x04, 0x05, 0x06
HALT_TXT = {0: "ninguno (sigue corriendo)",
            1: "HALT por rango (PC fuera del programa)",
            2: "HALT por instruccion ilegal / halt (0x00000000)"}
IMEM_WORDS = 1024
DMEM_BYTES = 4096

# Layout de los latches: (nombre, ancho) de MSB a LSB, igual que pipeline_top.v
CTRL = [("reg_write", 1), ("mem_read", 1), ("mem_write", 1), ("wb_src", 2), ("alu_src", 1),
        ("branch", 1), ("jump", 1), ("jalr", 1), ("mem_unsigned", 1),
        ("alu_op", 4), ("mem_size", 2), ("imm_src", 3)]
LATCHES = [
    ("IF/ID", 13, [("valid", 1), ("pc", 32), ("pc+4", 32), ("instr", 32)]),
    ("ID/EX", 25, [("valid", 1), ("pc", 32), ("pc+4", 32), ("rs1_data", 32), ("rs2_data", 32),
                   ("imm", 32), ("rs1", 5), ("rs2", 5), ("rd", 5), ("funct3", 3)] + CTRL),
    ("EX/MEM", 16, [("valid", 1), ("alu_result", 32), ("rs2_data", 32), ("rd", 5), ("pc+4", 32)] + CTRL),
    ("MEM/WB", 16, [("valid", 1), ("mem_data", 32), ("alu_result", 32), ("pc+4", 32), ("rd", 5)] + CTRL),
]
ALU_OPS = ["ADD", "SUB", "SLL", "SLT", "SLTU", "XOR", "SRL", "SRA", "OR", "AND", "PASS"]
WB_SRC = ["ALU", "MEM", "PC+4"]
HEX_FIELDS = {"pc", "pc+4", "instr", "rs1_data", "rs2_data", "imm", "alu_result", "mem_data"}


# ----------------------------------------------------------------------------
# Desensamblador minimo (solo para mostrar la instruccion de cada etapa)
# ----------------------------------------------------------------------------
def _sx(v, bits):
    return v - (1 << bits) if v & (1 << (bits - 1)) else v


def disasm(w):
    if w == 0x00000000:
        return "halt"
    op, rd, f3 = w & 0x7F, (w >> 7) & 31, (w >> 12) & 7
    rs1, rs2, f7 = (w >> 15) & 31, (w >> 20) & 31, w >> 25
    ii = _sx(w >> 20, 12)
    if op == 0x33:
        n = {(0, 0): "add", (0, 0x20): "sub", (1, 0): "sll", (2, 0): "slt", (3, 0): "sltu",
             (4, 0): "xor", (5, 0): "srl", (5, 0x20): "sra", (6, 0): "or", (7, 0): "and"}.get((f3, f7))
        return f"{n} x{rd}, x{rs1}, x{rs2}" if n else "?"
    if op == 0x13:
        if f3 in (1, 5):
            n = {1: "slli", 5: "srli" if f7 == 0 else "srai"}[f3]
            return f"{n} x{rd}, x{rs1}, {rs2}"
        n = {0: "addi", 2: "slti", 3: "sltiu", 4: "xori", 6: "ori", 7: "andi"}[f3]
        return f"{n} x{rd}, x{rs1}, {ii}"
    if op == 0x03:
        n = {0: "lb", 1: "lh", 2: "lw", 4: "lbu", 5: "lhu"}.get(f3, "l?")
        return f"{n} x{rd}, {ii}(x{rs1})"
    if op == 0x23:
        n = {0: "sb", 1: "sh", 2: "sw"}.get(f3, "s?")
        return f"{n} x{rs2}, {_sx(((w >> 25) << 5) | ((w >> 7) & 31), 12)}(x{rs1})"
    if op == 0x63:
        off = _sx(((w >> 31) << 12) | (((w >> 7) & 1) << 11) | (((w >> 25) & 63) << 5) | (((w >> 8) & 15) << 1), 13)
        return f"{ {0: 'beq', 1: 'bne'}.get(f3, 'b?') } x{rs1}, x{rs2}, {off:+d}"
    if op == 0x37:
        return f"lui x{rd}, 0x{w >> 12:x}"
    if op == 0x6F:
        off = _sx(((w >> 31) << 20) | (((w >> 12) & 255) << 12) | (((w >> 20) & 1) << 11) | (((w >> 21) & 1023) << 1), 21)
        return f"jal x{rd}, {off:+d}"
    if op == 0x67:
        return f"jalr x{rd}, {ii}(x{rs1})"
    return "?"


# ----------------------------------------------------------------------------
# Enlace con la Debug Unit
# ----------------------------------------------------------------------------
class DebugLink:
    def __init__(self, port, baud=9600, timeout=2.0):
        import serial  # pip install pyserial
        self.ser = serial.Serial(port, baud, bytesize=8, parity="N", stopbits=1, timeout=timeout)
        time.sleep(0.1)
        self.ser.reset_input_buffer()

    def write(self, data):
        self.ser.write(bytes(data))
        self.ser.flush()

    def read(self, n, timeout=None):
        old = self.ser.timeout
        if timeout is not None:
            self.ser.timeout = timeout
        data = self.ser.read(n)
        self.ser.timeout = old
        if len(data) != n:
            raise TimeoutError(f"se esperaban {n} bytes y llegaron {len(data)}")
        return data

    def reset(self):
        self.write([OP_RESET])
        time.sleep(0.2)  # la DU barre 1024 palabras de imem; sin respuesta

    def load_words(self, words):
        buf = bytearray()
        for w in words:
            buf += bytes([OP_LOAD]) + (w & 0xFFFFFFFF).to_bytes(4, "little")
        self.write(buf)
        time.sleep(0.05)

    def run(self, timeout=10.0):
        self.write([OP_RUN])
        return self.read(1, timeout)[0]

    def step(self):
        self.write([OP_STEP])
        return self.read(1, 2.0)[0]

    def regs(self):
        self.write([OP_REGS])
        d = self.read(128, 5.0)
        return [int.from_bytes(d[4 * i:4 * i + 4], "little") for i in range(32)]

    def latches(self):
        self.write([OP_LATCHES])
        d = self.read(70, 5.0)
        out, pos = [], 0
        for name, nbytes, fields in LATCHES:
            raw = int.from_bytes(d[pos:pos + nbytes], "little")
            pos += nbytes
            total = sum(w for _, w in fields)
            vals, shift = {}, total
            for fname, w in fields:
                shift -= w
                vals[fname] = (raw >> shift) & ((1 << w) - 1)
            out.append((name, vals))
        return out

    def mem(self, addr, length):
        out = bytearray()
        while length > 0:  # trozos de 256 B
            n = min(length, 256)
            self.write([OP_MEM, addr & 0xFF, (addr >> 8) & 0xFF, n & 0xFF, (n >> 8) & 0xFF])
            out += self.read(n, 5.0 + n / 900)
            addr += n
            length -= n
        return bytes(out)


# ----------------------------------------------------------------------------
# Formato de salida
# ----------------------------------------------------------------------------
def fmt_latch(name, v):
    if name == "IF/ID":
        extra = f"pc=0x{v['pc']:08x}  {disasm(v['instr']):<22} (0x{v['instr']:08x})"
    elif name == "ID/EX":
        extra = (f"pc=0x{v['pc']:08x}  rs1=x{v['rs1']}(0x{v['rs1_data']:08x}) "
                 f"rs2=x{v['rs2']}(0x{v['rs2_data']:08x}) imm=0x{v['imm']:08x} rd=x{v['rd']}")
    elif name == "EX/MEM":
        extra = f"alu=0x{v['alu_result']:08x} rs2_data=0x{v['rs2_data']:08x} rd=x{v['rd']}"
    else:
        extra = f"mem=0x{v['mem_data']:08x} alu=0x{v['alu_result']:08x} rd=x{v['rd']}"
    if name != "IF/ID":
        op = ALU_OPS[v["alu_op"]] if v["alu_op"] < len(ALU_OPS) else str(v["alu_op"])
        flags = [k for k in ("reg_write", "mem_read", "mem_write", "branch", "jump", "jalr") if v[k]]
        wb = WB_SRC[v["wb_src"]] if v["wb_src"] < 3 else "?"
        extra += f"\n{'':10}ctrl: alu_op={op} wb_src={wb} " + (" ".join(flags) if flags else "-")
    return f"{name:<7}{'V' if v['valid'] else '.'} {extra}"


def fmt_regs(regs, prev=None):
    lines = []
    for r in range(0, 32, 4):
        cells = []
        for i in range(r, r + 4):
            mark = "*" if prev is not None and prev[i] != regs[i] else " "
            cells.append(f"x{i:<2}{mark}=0x{regs[i]:08x}")
        lines.append("  ".join(cells))
    return "\n".join(lines)


def hexdump(data, base):
    lines = []
    for i in range(0, len(data), 16):
        chunk = data[i:i + 16]
        words = " ".join(f"{int.from_bytes(chunk[j:j + 4], 'little'):08x}"
                         for j in range(0, len(chunk) - len(chunk) % 4, 4))
        by = " ".join(f"{b:02x}" for b in chunk)
        lines.append(f"0x{base + i:04x}: {by:<47}  | words: {words}")
    return "\n".join(lines)


def read_program(path):
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
    if path.lower().endswith(".asm") or path.lower().endswith(".s"):
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        from assembler import assemble
        return assemble(text)
    words = []
    for line in text.splitlines():
        line = line.split("#")[0].split("//")[0].strip()
        if line:
            words.append(int(line, 16))
    return words


# ----------------------------------------------------------------------------
# Shell
# ----------------------------------------------------------------------------
class Shell(cmd.Cmd):
    intro = "Debug Unit RISC-V. 'help' para ver los comandos."
    prompt = "(riscv) "

    def __init__(self, link):
        super().__init__()
        self.link = link
        self.auto = True
        self.prev_regs = None
        self.prog_len = 0
        self.cycles = 0

    def _guard(self, fn, *a):
        try:
            return fn(*a)
        except TimeoutError as e:
            print(f"[timeout] {e}. Si la DU quedo colgada (p.ej. bucle infinito), resetear la placa (boton CPU RESET) y volver a cargar.")
        except Exception as e:
            print(f"[error] {type(e).__name__}: {e}")

    # --- comandos ---
    def do_reset(self, arg):
        "reset: limpia imem (NOP), pipeline y registros. No limpia la memoria de datos."
        self._guard(self.link.reset)
        self.prev_regs, self.prog_len, self.cycles = None, 0, 0
        print("reset enviado")

    def do_load(self, arg):
        "load <archivo.asm|archivo.hex>: reset + carga del programa"
        if not arg.strip():
            return print("uso: load <archivo>")
        try:
            words = read_program(shlex.split(arg)[0])
        except Exception as e:
            return print(f"[error al leer/ensamblar] {e}")
        if len(words) > IMEM_WORDS:
            return print(f"programa de {len(words)} palabras; la imem tiene {IMEM_WORDS}")

        def go():
            self.link.reset()
            self.link.load_words(words)
        self._guard(go)
        self.prog_len, self.prev_regs, self.cycles = len(words), None, 0
        print(f"cargadas {len(words)} instrucciones")

    def do_run(self, arg):
        "run: corre hasta el halt (timeout 10 s) y muestra el motivo"
        t = time.time()
        code = self._guard(self.link.run)
        if code is None:
            return
        print(f"halt_code={code}: {HALT_TXT.get(code, '?')}  ({time.time() - t:.2f} s)")
        self.do_regs("")

    def do_step(self, arg):
        "step [n]: avanza n ciclos de clock (default 1)"
        n = int(arg) if arg.strip() else 1
        for _ in range(n):
            code = self._guard(self.link.step)
            if code is None:
                return
            self.cycles += 1
            print(f"--- ciclo {self.cycles}  halt_code={code} ---")
            if self.auto:
                self.do_latches("")
            if code != 0:
                print(HALT_TXT.get(code, "?"))
                break
        self._show_regs_changes()

    def _show_regs_changes(self):
        regs = self._guard(self.link.regs)
        if regs is None:
            return
        if self.prev_regs is None:
            print("registros:")
            print(fmt_regs(regs))
        else:
            ch = [f"x{i}: 0x{self.prev_regs[i]:08x} -> 0x{regs[i]:08x}"
                  for i in range(32) if regs[i] != self.prev_regs[i]]
            print("registros que cambiaron: " + (", ".join(ch) if ch else "ninguno"))
        self.prev_regs = regs

    def do_regs(self, arg):
        "regs: los 32 registros (* = cambio respecto de la lectura anterior)"
        regs = self._guard(self.link.regs)
        if regs is None:
            return
        print(fmt_regs(regs, self.prev_regs))
        print("decimal (con signo): " + "  ".join(
            f"x{i}={_sx(v, 32)}" for i, v in enumerate(regs) if v))
        self.prev_regs = regs

    def do_latches(self, arg):
        "latches: IF/ID, ID/EX, EX/MEM y MEM/WB decodificados"
        lat = self._guard(self.link.latches)
        if lat is None:
            return
        for name, v in lat:
            print(fmt_latch(name, v))

    def do_mem(self, arg):
        "mem <addr> [bytes]: volcado de la memoria de datos (default 64 bytes). addr en decimal o 0x.."
        p = arg.split()
        if not p:
            return print("uso: mem <addr> [bytes]")
        addr = int(p[0], 0)
        n = int(p[1], 0) if len(p) > 1 else 64
        if addr < 0 or addr + n > DMEM_BYTES or n <= 0:
            return print(f"rango invalido (memoria de {DMEM_BYTES} bytes)")
        d = self._guard(self.link.mem, addr, n)
        if d is not None:
            print(hexdump(d, addr))

    def do_auto(self, arg):
        "auto on|off: mostrar los latches en cada step"
        self.auto = arg.strip().lower() != "off"
        print(f"auto {'on' if self.auto else 'off'}")

    def do_quit(self, arg):
        "quit: salir"
        return True

    do_exit = do_quit
    do_EOF = do_quit

    def emptyline(self):
        pass


def main():
    ap = argparse.ArgumentParser(description="CLI de la Debug Unit RISC-V")
    ap.add_argument("--port", required=True, help="puerto serie (COM8, /dev/ttyUSB1)")
    ap.add_argument("--baud", type=int, default=9600)
    ap.add_argument("-x", "--exec", action="append", default=[], help="comando a ejecutar (repetible)")
    ap.add_argument("-f", "--file", help="archivo con un comando por linea")
    a = ap.parse_args()
    sh = Shell(DebugLink(a.port, a.baud))
    cmds = list(a.exec)
    if a.file:
        with open(a.file, encoding="utf-8") as f:
            cmds += [l.strip() for l in f if l.strip() and not l.startswith("#")]
    if cmds:
        for c in cmds:
            print(f"{sh.prompt}{c}")
            if sh.onecmd(c):
                break
    else:
        sh.cmdloop()


if __name__ == "__main__":
    main()