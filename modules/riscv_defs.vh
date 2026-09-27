// -----------------------------------------------------------------------------
// riscv_defs.vh
//
// Reemplazo en Verilog-2001 de riscv_pkg.sv -- version recortada.
//
// Solo quedan acá `define ESCALARES: opcodes, los "_op"/"_src" ya
// decodificados (comparten codificacion entre control_unit.v, que los
// produce, y sus consumidores -- alu.v, imm_gen.v, dmem.v, forward_unit.v,
// hazard_detect.v, debug_unit.v), los anchos generales del datapath, y los
// 4 totales de ancho de los latches de pipeline (IF_ID_W/ID_EX_W/EX_MEM_W/
// MEM_WB_W), que pipeline_top.v y debug_unit.v siguen necesitando para el
// borde externo (puertos *_q_out/*_q_in de DUMP_LATCHES).
//
// Lo que YA NO está acá: el bus de control empaquetado (antes CTRL_W +
// 12 `define de rango de bits) y el layout interno de los 4 latches
// (antes IF_ID_VALID/IF_ID_PC/... con offsets calculados a mano). Esos
// offsets eran el riesgo real -- cualquier cambio futuro a un campo
// obligaba a recalcular a mano todos los que venían después, y un error
// ahí compila pero da resultados incorrectos en silencio. Ahora esos
// campos viajan como puertos con nombre: if_id_reg.v / id_ex_reg.v /
// ex_mem_reg.v / mem_wb_reg.v y las conexiones dentro de pipeline_top.v.
// El total en bits de cada latch (para el borde externo) se arma con un
// único `{...}` de concatenación al final de pipeline_top.v, en el mismo
// orden de campos que tenía el struct/bus original -- así que
// system_top.v y debug_unit.v no cambiaron nada.
//
// Uso:  `include "riscv_defs.vh"   (compilar con -I .)
// -----------------------------------------------------------------------------
`ifndef RISCV_DEFS_VH
`define RISCV_DEFS_VH

// ---------------------------------------------------------------------------
// Parametros generales
// ---------------------------------------------------------------------------
`define XLEN         32   // ancho de datos / registros
`define REG_ADDR_W   5    // 32 registros -> 5 bits
`define IMEM_ADDR_W  10   // ajustar segun tamanio real de memoria de programa
`define DMEM_ADDR_W  12   // ajustar segun tamanio real de memoria de datos

// ---------------------------------------------------------------------------
// Opcodes (bits [6:0] de la instruccion) - subset implementado
// ---------------------------------------------------------------------------
`define OP_R       7'b0110011  // R-type
`define OP_IMM     7'b0010011  // I-type ALU inmediato (addi, slli, slti, sltiu, xori, srli, srai, ori, andi)
`define OP_LOAD    7'b0000011  // I-type carga (lb, lh, lw, lbu, lhu)
`define OP_JALR    7'b1100111  // I-type salto (jalr)
`define OP_STORE   7'b0100011  // S-type (sb, sh, sw)
`define OP_BRANCH  7'b1100011  // B-type (beq, bne)
`define OP_LUI     7'b0110111  // U-type (lui)
`define OP_JAL     7'b1101111  // J-type (jal)

// ---------------------------------------------------------------------------
// Operacion interna de ALU (ya decodificada por control_unit, compartida
// entre control_unit.v (produce) y alu.v (consume))   [ex alu_op_e, 4 bits]
// ---------------------------------------------------------------------------
`define ALU_OP_W  4
`define ALU_ADD   4'd0
`define ALU_SUB   4'd1
`define ALU_SLL   4'd2
`define ALU_SLT   4'd3
`define ALU_SLTU  4'd4
`define ALU_XOR   4'd5
`define ALU_SRL   4'd6
`define ALU_SRA   4'd7
`define ALU_OR    4'd8
`define ALU_AND   4'd9
`define ALU_PASS  4'd10  // resultado = b, sin usar a (lui carga el inmediato directo)

// ---------------------------------------------------------------------------
// Tipo de inmediato -> selecciona el generador de inmediato en Decode.
// Compartida entre control_unit.v (produce) e imm_gen.v (consume).
// [ex imm_src_e, 3 bits]
// ---------------------------------------------------------------------------
`define IMM_SRC_W  3
`define IMM_I      3'd0
`define IMM_S      3'd1
`define IMM_B      3'd2
`define IMM_U      3'd3
`define IMM_J      3'd4
`define IMM_X      3'd5  // no aplica (R-type no usa inmediato)

// ---------------------------------------------------------------------------
// Tamanio de acceso a memoria de datos (load/store). Compartida entre
// control_unit.v (produce) y dmem.v (consume)  [ex mem_size_e, 2 bits]
// ---------------------------------------------------------------------------
`define MEM_SIZE_W  2
`define MEM_BYTE    2'd0
`define MEM_HALF    2'd1
`define MEM_WORD    2'd2

// ---------------------------------------------------------------------------
// Origen del dato que se escribe en rd   [ex wb_src_e, 2 bits]
// ---------------------------------------------------------------------------
`define WB_SRC_W  2
`define WB_ALU    2'd0
`define WB_MEM    2'd1
`define WB_PC4    2'd2

// ---------------------------------------------------------------------------
// Fuente del forwarding (unidad de riesgos). Compartida entre
// forward_unit.v (produce) y pipeline_top.v (consume) [ex fwd_src_e, 2 bits]
// ---------------------------------------------------------------------------
`define FWD_SRC_W   2
`define FWD_NONE    2'd0  // usar el valor que ya trajo el regfile en ID
`define FWD_EX_MEM  2'd1  // forward desde ex_mem_q.alu_result (gap=1)
`define FWD_MEM_WB  2'd2  // forward desde el dato de write-back (gap=2)

// ---------------------------------------------------------------------------
// Codigo de HALT: distingue las dos causas para la respuesta de 1 byte
// que RUN/STEP le deben al host  [ex halt_code_e, 2 bits]
// ---------------------------------------------------------------------------
`define HALT_CODE_W   2
`define HALT_NONE     2'd0  // sigue corriendo
`define HALT_RANGE    2'd1  // PC se fue mas alla del programa cargado
`define HALT_ILLEGAL  2'd2  // instruccion no reconocida por control_unit

// ---------------------------------------------------------------------------
// Campos genericos de la instruccion cruda (posiciones fijas del ISA):
// opcode, rd, funct3, rs1, rs2 y funct7 siempre caen en el mismo rango
// de bits, sea cual sea el tipo de instruccion. Estos son rangos sobre
// el word de instruccion crudo (instr[31:0]), no sobre un latch -- no
// tienen el problema de offsets en cascada porque son fijos por el ISA,
// nunca cambian.
// ---------------------------------------------------------------------------
`define INSTR_FUNCT7  31:25
`define INSTR_RS2     24:20
`define INSTR_RS1     19:15
`define INSTR_FUNCT3  14:12
`define INSTR_RD      11:7
`define INSTR_OPCODE  6:0

// ---------------------------------------------------------------------------
// Anchos TOTALES (en bits) de los 4 latches de pipeline. Ya no describen un
// layout interno (eso ahora son puertos con nombre en if_id_reg.v /
// id_ex_reg.v / ex_mem_reg.v / mem_wb_reg.v) -- son solo el tamaño del bus
// plano que pipeline_top.v arma al final (un único `{...}` de
// concatenación) para el borde externo hacia debug_unit.v (DUMP_LATCHES).
// Mismos valores que antes (97/198/121/121): el layout byte a byte que ve
// el host por UART no cambió.
// ---------------------------------------------------------------------------
`define IF_ID_W   97
`define ID_EX_W   198
`define EX_MEM_W  121
`define MEM_WB_W  121

`endif // RISCV_DEFS_VH
