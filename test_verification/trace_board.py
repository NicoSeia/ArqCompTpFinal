#!/usr/bin/env python3
"""
trace_board.py - Traza paso a paso en la placa: STEP + DUMP_LATCHES, y muestra
la instruccion que hay en IF/ID en cada ciclo (pc, instr), comparandola con
la que DEBERIA estar en esa direccion segun el .asm.

    python -u trace_board.py tests/ladder_120.asm --port COM6 --steps 200

Marca con '<<< DIFIERE' cuando la palabra que lee el pipeline no es la esperada
(p.ej. NOP en lugar de addi => la imem no tiene lo que se cargo).
IF/ID (97 bits) = {valid, pc, pc+4, instr}; se manda byte bajo primero (13 bytes).
"""
import argparse
import sys
import time
from pathlib import Path

import serial

sys.path.insert(0, str(Path(__file__).resolve().parent))
from assembler import assemble  # noqa: E402

OP_RESET, OP_LOAD, OP_STEP, OP_LATCHES = 0x00, 0x01, 0x03, 0x05


def read_exact(ser, n, what, timeout=5.0):
    buf = b""
    t0 = time.time()
    while len(buf) < n and time.time() - t0 < timeout:
        buf += ser.read(n - len(buf))
    if len(buf) != n:
        raise SystemExit(f"{what}: llegaron {len(buf)} de {n} bytes")
    return buf


def parse_if_id(raw13):
    v = int.from_bytes(raw13, "little")
    instr = v & 0xFFFFFFFF
    pc4 = (v >> 32) & 0xFFFFFFFF
    pc = (v >> 64) & 0xFFFFFFFF
    valid = (v >> 96) & 1
    return valid, pc, pc4, instr


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("asm")
    ap.add_argument("--port", required=True)
    ap.add_argument("--baud", type=int, default=9600)
    ap.add_argument("--steps", type=int, default=200)
    ap.add_argument("--start", type=int, default=0, help="no imprimir los primeros N pasos")
    args = ap.parse_args()

    words = assemble(Path(args.asm).read_text())
    print(f"{len(words)} palabras", flush=True)
    ser = serial.Serial(args.port, args.baud, timeout=0.5)
    try:
        ser.reset_input_buffer()
        ser.write(bytes([OP_RESET])); ser.flush(); time.sleep(0.3)
        ser.reset_input_buffer()
        payload = b"".join(bytes([OP_LOAD]) + (w & 0xFFFFFFFF).to_bytes(4, "little") for w in words)
        ser.write(payload); ser.flush()
        time.sleep(len(payload) * 10 / args.baud + 0.3)
        ser.reset_input_buffer()

        diffs = 0
        print(f"{'paso':>5} {'pc':>6} {'valid':>5} {'instr leida':>12} {'esperada':>10}", flush=True)
        for step in range(args.steps):
            ser.write(bytes([OP_STEP]))
            halt = read_exact(ser, 1, "STEP")[0]
            ser.write(bytes([OP_LATCHES]))
            lat = read_exact(ser, 70, "DUMP_LATCHES", 8.0)
            valid, pc, pc4, instr = parse_if_id(lat[:13])
            idx = pc >> 2
            exp = words[idx] if idx < len(words) else None
            mark = ""
            if valid and exp is not None and instr != exp:
                mark = "  <<< DIFIERE"; diffs += 1
            if step >= args.start or mark:
                e = f"0x{exp:08X}" if exp is not None else "(fuera)"
                print(f"{step:>5} 0x{pc:04X} {valid:>5}   0x{instr:08X} {e:>10}{mark}", flush=True)
            if halt != 0:
                print(f"halt_code={halt} en el paso {step}", flush=True)
                break
        print(f"\nPalabras leidas distintas de las esperadas: {diffs}")
    finally:
        ser.close()


if __name__ == "__main__":
    main()