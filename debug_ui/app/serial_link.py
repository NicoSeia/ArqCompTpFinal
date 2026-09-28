"""
serial_link.py
Envoltorio sobre pyserial que habla el protocolo de la Debug Unit.
Una unica instancia global (`link`) = una conexion UART a la vez.
"""
import threading
from typing import List, Optional

import serial

from . import protocol

# baud_rate_gen.v: CLK_FREQ=100MHz, BAUD=9600 (parametros de system_top.v)
BAUD_RATE = 9600


class DebugUnitError(Exception):
    pass


class SerialLink:
    def __init__(self) -> None:
        self._ser: Optional[serial.Serial] = None
        self._port: Optional[str] = None
        # el protocolo es estrictamente sincrono (comando -> respuesta antes
        # del proximo comando), asi que un solo lock alcanza y evita que dos
        # requests HTTP concurrentes se pisen en el mismo puerto serie
        self._lock = threading.Lock()

    @property
    def is_open(self) -> bool:
        return self._ser is not None and self._ser.is_open

    @property
    def port(self) -> Optional[str]:
        return self._port

    def connect(self, port: str, timeout: float = 5.0) -> None:
        with self._lock:
            if self._ser is not None:
                self._ser.close()
            self._ser = serial.Serial(port, BAUD_RATE, timeout=timeout)
            self._port = port

    def disconnect(self) -> None:
        with self._lock:
            if self._ser is not None:
                self._ser.close()
            self._ser = None
            self._port = None

    def _require_open(self) -> serial.Serial:
        if self._ser is None or not self._ser.is_open:
            raise DebugUnitError("No hay conexion serie abierta. Llama a /connect primero.")
        return self._ser

    def _write(self, data: bytes) -> None:
        self._require_open().write(data)

    def _read_exact(self, n: int) -> bytes:
        ser = self._require_open()
        data = ser.read(n)
        if len(data) != n:
            raise DebugUnitError(
                f"Timeout esperando la Debug Unit: se esperaban {n} bytes, "
                f"llegaron {len(data)}. Revisa el cableado/baudrate o si el "
                f"pipeline quedo en un loop sin halt (RUN no tiene timeout en HW)."
            )
        return data

    # --- Comandos del protocolo, 1:1 con los opcodes ---

    def reset(self) -> None:
        with self._lock:
            self._write(bytes([protocol.OP_RESET]))
            # ST_RESET_CLEAR no responde nada por UART

    def load_program(self, words: List[int]) -> None:
        with self._lock:
            for w in words:
                self._write(protocol.encode_load_word(w))

    def run(self) -> dict:
        with self._lock:
            self._write(bytes([protocol.OP_RUN]))
            code = self._read_exact(1)[0]
            return {"halt_code": code, "halt_name": protocol.HALT_NAMES.get(code, "?")}

    def step(self) -> dict:
        with self._lock:
            self._write(bytes([protocol.OP_STEP]))
            code = self._read_exact(1)[0]
            return {"halt_code": code, "halt_name": protocol.HALT_NAMES.get(code, "?")}

    def dump_regs(self) -> List[int]:
        with self._lock:
            self._write(bytes([protocol.OP_DUMP_REGS]))
            raw = self._read_exact(protocol.REG_COUNT * 4)
            return protocol.decode_regs(raw)

    def dump_mem(self, addr: int, length: int) -> bytes:
        with self._lock:
            self._write(protocol.encode_dump_mem(addr, length))
            return self._read_exact(length)

    def dump_latches(self) -> dict:
        with self._lock:
            self._write(bytes([protocol.OP_DUMP_LATCHES]))
            total = (
                protocol.IF_ID_BYTES + protocol.ID_EX_BYTES
                + protocol.EX_MEM_BYTES + protocol.MEM_WB_BYTES
            )
            raw = self._read_exact(total)
            return protocol.decode_latches(raw)


link = SerialLink()  # instancia compartida por toda la app