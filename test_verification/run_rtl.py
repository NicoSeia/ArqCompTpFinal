#!/usr/bin/env python3
"""
run_rtl.py - Corre un programa .asm en la placa (Basys 3) por UART y guarda
lo que devuelve el RTL real en un .txt (mismo formato que golden_model.py).

    python3 run_board.py tests/programa.asm --port COM4 -o out/board_out.txt

Protocolo de la Debug Unit (9600 8N1):
  0x00 RESET        (sin respuesta)
  0x01 LOAD_WORD    + 4 bytes little-endian (sin respuesta)
  0x02 RUN          -> 1 byte: halt_code
  0x04 DUMP_REGS    -> 128 bytes (x0..x31, 4 B little-endian c/u)
  0x06 DUMP_MEM     + addr(2B LE) + len(2B LE) -> len bytes
Requisito: pip install pyserial. Usar Windows (Git Bash/PowerShell), no WSL.
"""
import argparse
import sys
import time
from pathlib import Path

import serial  # pyserial

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_verification.assembler import assemble  # noqa: E402

OP_RESET, OP_LOAD, OP_RUN, OP_REGS, OP_MEM = 0x00, 0x01, 0x02, 0x04, 0x06
MEM_DUMP_BYTES = 640   # tiene que coincidir con golden_model.MEM_DUMP_BYTES


def read_exact(ser, n, what, timeout=10.0):
    """Lee exactamente n bytes o falla con un mensaje claro."""
    buf = b""
    t0 = time.time()
    while len(buf) < n and time.time() - t0 < timeout:
        buf += ser.read(n - len(buf))
    if len(buf) != n:
        raise SystemExit(f"ERROR: {what}: se esperaban {n} bytes y llegaron {len(buf)} "
                         f"(timeout {timeout}s). Revisar puerto/baud/bitstream.")
    return buf


def format_state(halt_code, regs_raw, mem_raw):
    lines = [f"halt_code = {halt_code}"]
    for i in range(32):
        lines.append(f"x{i} = 0x{int.from_bytes(regs_raw[4*i:4*i+4], 'little'):08X}")
    for off in range(0, len(mem_raw), 4):
        lines.append(f"mem[0x{off:04X}] = 0x{int.from_bytes(mem_raw[off:off+4], 'little'):08X}")
    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser(description="Corre un programa en la placa y guarda la salida")
    ap.add_argument("asm")
    ap.add_argument("--port", required=True, help="ej. COM4")
    ap.add_argument("--baud", type=int, default=9600)
    ap.add_argument("-o", "--output", default="out/board_out.txt")
    ap.add_argument("--run-timeout", type=float, default=10.0, help="segundos esperando el fin del RUN")
    args = ap.parse_args()

    words = assemble(Path(args.asm).read_text())
    print(f"[placa] {args.asm}: {len(words)} palabras")

    ser = serial.Serial(args.port, args.baud, timeout=0.5)
    try:
        time.sleep(0.2)
        ser.reset_input_buffer()          # descarta bytes viejos (evita respuestas corridas)

        ser.write(bytes([OP_RESET]))      # limpia imem con NOPs y reinicia pipeline
        ser.flush()
        time.sleep(0.3)                   # el barrido de imem tarda ~1024 ciclos de clock
        ser.reset_input_buffer()

        payload = bytearray()
        for w in words:
            payload += bytes([OP_LOAD]) + (w & 0xFFFFFFFF).to_bytes(4, "little")
        ser.write(payload)
        ser.flush()
        time.sleep(len(payload) * 10 / args.baud + 0.2)   # tiempo de transmision

        ser.reset_input_buffer()
        ser.write(bytes([OP_RUN]))
        halt = read_exact(ser, 1, "RUN (halt_code)", args.run_timeout)[0]
        print(f"[placa] RUN termino, halt_code={halt}")

        ser.write(bytes([OP_REGS]))
        regs = read_exact(ser, 128, "DUMP_REGS")

        ser.write(bytes([OP_MEM]) + (0).to_bytes(2, "little") + MEM_DUMP_BYTES.to_bytes(2, "little"))
        mem = read_exact(ser, MEM_DUMP_BYTES, "DUMP_MEM", timeout=max(10.0, MEM_DUMP_BYTES * 10 / args.baud + 3))

        extra = ser.read(64)
        if extra:
            print(f"[placa] AVISO: llegaron {len(extra)} bytes sobrantes: {extra.hex()}")
    finally:
        ser.close()

    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(format_state(halt, regs, mem))
    print(f"[placa] salida guardada en {out}")


if __name__ == "__main__":
    main()