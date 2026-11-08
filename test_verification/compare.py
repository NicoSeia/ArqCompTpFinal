#!/usr/bin/env python3
"""
compare.py - Compara dos salidas (golden vs placa/simulacion).
    python3 compare.py out/golden_out.txt out/board_out.txt
Formato de cada archivo (lineas):  halt_code = N | xN = 0x... | mem[0x....] = 0x...
Sale con codigo 0 si son iguales, 1 si hay diferencias.
"""
import re
import sys
from pathlib import Path

LINE = re.compile(r"^\s*(halt_code|x\d+|mem\[0x[0-9a-fA-F]+\])\s*=\s*(0x[0-9a-fA-F]+|\d+)\s*$")


def norm_key(k):
    if k.startswith("mem["):
        return f"mem[0x{int(k[4:-1], 16):04X}]"
    return k


def parse(path):
    d = {}
    for ln in Path(path).read_text().splitlines():
        if not ln.strip() or ln.lstrip().startswith("#"):
            continue
        m = LINE.match(ln)
        if not m:
            raise SystemExit(f"{path}: linea no reconocida: {ln!r}")
        d[norm_key(m.group(1))] = int(m.group(2), 0)
    return d


def main():
    if len(sys.argv) != 3:
        raise SystemExit("uso: compare.py <esperado(golden)> <obtenido(placa)>")
    exp, got = parse(sys.argv[1]), parse(sys.argv[2])
    keys = list(exp) + [k for k in got if k not in exp]
    diffs = []
    for k in keys:
        if k not in got:
            diffs.append((k, exp[k], None))
        elif k not in exp:
            diffs.append((k, None, got[k]))
        elif exp[k] != got[k]:
            diffs.append((k, exp[k], got[k]))

    n_regs = sum(1 for k in exp if k.startswith("x"))
    n_mem = sum(1 for k in exp if k.startswith("mem"))
    print(f"Comparando: {n_regs} registros + {n_mem} words de memoria + halt_code")
    if not diffs:
        print("RESULTADO: OK - golden model y RTL coinciden en todo.")
        return 0
    print(f"RESULTADO: FALLA - {len(diffs)} diferencias\n")
    print(f"{'campo':<16}{'esperado (golden)':>20}{'obtenido (placa)':>20}")
    fmt = lambda v: "-" if v is None else (str(v) if False else f"0x{v:08X}")
    for k, e, g in diffs:
        if k == "halt_code":
            print(f"{k:<16}{e!s:>20}{g!s:>20}")
        else:
            print(f"{k:<16}{fmt(e):>20}{fmt(g):>20}")
    return 1


if __name__ == "__main__":
    sys.exit(main())