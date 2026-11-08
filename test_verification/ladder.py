#!/usr/bin/env python3
"""
ladder.py - Diagnostico de carga: corre programas de largo creciente en la placa
y mide cuantas instrucciones se ejecutaron realmente.

    python ladder.py --port COM6
    python ladder.py --port COM6 --sizes 10 40 100 150 200 217

Cada programa: 3x 'addi x2,x0,0' + N x 'addi x2,x2,1' + 'sw x2,0(x0)' + halt.
Si todo se carga y ejecuta bien, mem[0] = N. Si faltan palabras al inicio o el PC
arranca tarde, mem[0] < N y la diferencia dice cuantas se perdieron.
"""
import argparse
import sys
import time
from pathlib import Path

import serial

sys.path.insert(0, str(Path(__file__).resolve().parent))
from assembler import assemble  # noqa: E402

OP_RESET, OP_LOAD, OP_RUN, OP_MEM = 0x00, 0x01, 0x02, 0x06


def read_exact(ser, n, what, timeout=10.0):
    buf = b""
    t0 = time.time()
    while len(buf) < n and time.time() - t0 < timeout:
        buf += ser.read(n - len(buf))
    if len(buf) != n:
        raise SystemExit(f"{what}: llegaron {len(buf)} de {n} bytes")
    return buf


def make_program(n):
    src = ["addi x2, x0, 0"] * 3 + ["addi x2, x2, 1"] * n + ["sw x2, 0(x0)", "halt"]
    return assemble("\n".join(src))


def run_words(ser, words, baud, word_delay=0.0):
    ser.reset_input_buffer()
    ser.write(bytes([OP_RESET])); ser.flush(); time.sleep(0.3)
    ser.reset_input_buffer()
    payload = b"".join(bytes([OP_LOAD]) + (w & 0xFFFFFFFF).to_bytes(4, "little") for w in words)
    if word_delay > 0:   # modo lento: una palabra (5 bytes) por vez con pausa
        for i in range(0, len(payload), 5):
            ser.write(payload[i:i + 5]); ser.flush()
            time.sleep(5 * 10 / baud + word_delay)
        time.sleep(0.3)
    else:
        ser.write(payload); ser.flush()
        time.sleep(len(payload) * 10 / baud + 0.3)
    ser.reset_input_buffer()
    ser.write(bytes([OP_RUN]))
    halt = read_exact(ser, 1, "RUN", 10)[0]
    ser.write(bytes([OP_MEM]) + (0).to_bytes(2, "little") + (4).to_bytes(2, "little"))
    cnt = int.from_bytes(read_exact(ser, 4, "DUMP_MEM", 5), "little")
    return halt, cnt


def main(ser_factory=serial.Serial):
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", required=True)
    ap.add_argument("--baud", type=int, default=9600)
    ap.add_argument("--word-delay", type=float, default=0.0, help="pausa extra (s) entre palabras; ej. 0.005")
    ap.add_argument("--sizes", type=int, nargs="+", default=[10, 40, 80, 120, 160, 200, 214])
    args = ap.parse_args()
    print(f"Conectando a {args.port} a {args.baud} baud...", flush=True)
    ser = ser_factory(args.port, args.baud, timeout=0.5)
    print(f"{'N addi':>7} {'palabras':>9} {'ejecutadas':>11} {'halt':>5}  resultado", flush=True)
    try:
        for n in args.sizes:
            words = make_program(n)
            try:
                halt, cnt = run_words(ser, words, args.baud, args.word_delay)
            except SystemExit as e:
                print(f"{n:>7} {len(words):>9} {'-':>11} {'-':>5}  FALLA: {e}", flush=True)
                continue
            ok = "OK" if cnt == n and halt == 2 else f"FALLA (faltan {n - cnt})"
            print(f"{n:>7} {len(words):>9} {cnt:>11} {halt:>5}  {ok}", flush=True)
    finally:
        ser.close()


if __name__ == "__main__":
    main()