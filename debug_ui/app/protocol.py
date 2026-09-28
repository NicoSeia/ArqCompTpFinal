"""
protocol.py
Constantes y helpers de bajo nivel del protocolo de la Debug Unit (UART).
Refleja 1:1 la FSM de debug_link/debug_unit.v -- si algo cambia ahi, cambia aca.
"""
from typing import List, Dict

# --- Opcodes ---
OP_RESET        = 0x00
OP_LOAD_WORD    = 0x01
OP_RUN          = 0x02
OP_STEP         = 0x03
OP_DUMP_REGS    = 0x04
OP_DUMP_LATCHES = 0x05
OP_DUMP_MEM     = 0x06
OP_CLEAR_MEM    = 0x07  # definido en el protocolo pero no implementado en HW (se ignora)

# --- Codigos de halt (HALT_CODE_W = 2 bits, riscv_defs.vh) ---
HALT_NONE    = 0
HALT_RANGE   = 1
HALT_ILLEGAL = 2
HALT_NAMES = {HALT_NONE: "none", HALT_RANGE: "range", HALT_ILLEGAL: "illegal"}

REG_COUNT = 32

# --- Tamanios en bytes de cada latch, tal cual los calcula debug_unit.v
#     ((`ancho` + 7) / 8) a partir de IF_ID_W/ID_EX_W/EX_MEM_W/MEM_WB_W ---
IF_ID_BYTES  = 13   # ceil(97/8)
ID_EX_BYTES  = 25   # ceil(198/8)
EX_MEM_BYTES = 16   # ceil(121/8)
MEM_WB_BYTES = 16   # ceil(121/8)

# --- Layout de cada latch, en el mismo orden MSB->LSB de la concatenacion
#     `{...}` armada en pipeline_top.v. El ultimo campo de cada lista cae
#     en los bits menos significativos (y por lo tanto en el primer byte
#     que manda la Debug Unit, que shiftea byte bajo primero). ---
IF_ID_FIELDS = [
    ("valid", 1), ("pc", 32), ("pc_plus4", 32), ("instr", 32),
]
ID_EX_FIELDS = [
    ("valid", 1), ("pc", 32), ("pc_plus4", 32),
    ("rs1_data", 32), ("rs2_data", 32), ("imm", 32),
    ("rs1", 5), ("rs2", 5), ("rd", 5), ("funct3", 3),
    ("reg_write", 1), ("mem_read", 1), ("mem_write", 1), ("wb_src", 2), ("alu_src", 1),
    ("branch", 1), ("jump", 1), ("jalr", 1), ("mem_unsigned", 1),
    ("alu_op", 4), ("mem_size", 2), ("imm_src", 3),
]
EX_MEM_FIELDS = [
    ("valid", 1), ("alu_result", 32), ("rs2_data", 32), ("rd", 5), ("pc_plus4", 32),
    ("reg_write", 1), ("mem_read", 1), ("mem_write", 1), ("wb_src", 2), ("alu_src", 1),
    ("branch", 1), ("jump", 1), ("jalr", 1), ("mem_unsigned", 1),
    ("alu_op", 4), ("mem_size", 2), ("imm_src", 3),
]
MEM_WB_FIELDS = [
    ("valid", 1), ("mem_data", 32), ("alu_result", 32), ("pc_plus4", 32), ("rd", 5),
    ("reg_write", 1), ("mem_read", 1), ("mem_write", 1), ("wb_src", 2), ("alu_src", 1),
    ("branch", 1), ("jump", 1), ("jalr", 1), ("mem_unsigned", 1),
    ("alu_op", 4), ("mem_size", 2), ("imm_src", 3),
]


def encode_load_word(word: int) -> bytes:
    """LOAD_WORD: opcode + 4 bytes little-endian (ST_LOAD_B0..B3)."""
    return bytes([OP_LOAD_WORD]) + (word & 0xFFFFFFFF).to_bytes(4, "little")


def encode_dump_mem(addr: int, length: int) -> bytes:
    """DUMP_MEM: opcode + addr (2B LE) + cantidad (2B LE). addr se trunca
    a DMEM_ADDR_W bits del lado del hardware (12 bits -> 4096 posiciones)."""
    return (
        bytes([OP_DUMP_MEM])
        + (addr & 0xFFFF).to_bytes(2, "little")
        + (length & 0xFFFF).to_bytes(2, "little")
    )


def decode_regs(raw: bytes) -> List[int]:
    """32 registros x 4 bytes little-endian -> lista x0..x31."""
    assert len(raw) == REG_COUNT * 4
    return [int.from_bytes(raw[i:i + 4], "little") for i in range(0, len(raw), 4)]


def _unpack_fields(value: int, fields) -> Dict[str, int]:
    """fields en orden MSB->LSB (como en el `{...}` de Verilog). El ultimo
    campo de la lista cayo en los bits mas bajos de `value`, asi que se
    recorre al reves acumulando el offset desde bit 0."""
    result: Dict[str, int] = {}
    offset = 0
    for name, width in reversed(fields):
        mask = (1 << width) - 1
        result[name] = (value >> offset) & mask
        offset += width
    return result


def decode_latches(raw: bytes) -> Dict[str, Dict[str, int]]:
    """DUMP_LATCHES manda, en orden: if_id, id_ex, ex_mem, mem_wb -- cada
    uno con sus bytes shifteados LSB primero (zero-extendidos a bytes)."""
    expected = IF_ID_BYTES + ID_EX_BYTES + EX_MEM_BYTES + MEM_WB_BYTES
    assert len(raw) == expected

    chunks = {}
    offset = 0
    for name, nbytes, fields in (
        ("if_id", IF_ID_BYTES, IF_ID_FIELDS),
        ("id_ex", ID_EX_BYTES, ID_EX_FIELDS),
        ("ex_mem", EX_MEM_BYTES, EX_MEM_FIELDS),
        ("mem_wb", MEM_WB_BYTES, MEM_WB_FIELDS),
    ):
        value = int.from_bytes(raw[offset:offset + nbytes], "little")
        chunks[name] = _unpack_fields(value, fields)
        offset += nbytes
    return chunks