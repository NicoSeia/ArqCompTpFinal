// -----------------------------------------------------------------------------
// riscv_pkg.sv
//
//   R-type : add, sub, sll, srl, sra, and, or, xor, slt, sltu
//   I-type : lb, lh, lw, lbu, lhu, addi, andi, ori, xori, slti, sltiu,
//            slli, srli, srai, jalr
//   S-type : sb, sh, sw
//   B-type : beq, bne
//   U-type : lui
//   J-type : jal
// -----------------------------------------------------------------------------

package riscv_pkg;

  // ---------------------------------------------------------------------------
  // Parámetros generales
  // ---------------------------------------------------------------------------
  parameter int XLEN        = 32;  // ancho de datos / registros
  parameter int REG_ADDR_W  = 5;   // 32 registros -> 5 bits
  parameter int IMEM_ADDR_W = 10;  // ajustar según tamaño real de memoria de programa
  parameter int DMEM_ADDR_W = 12;  // ajustar según tamaño real de memoria de datos

  // ---------------------------------------------------------------------------
  // Opcodes (bits [6:0] de la instrucción) - subset implementado
  // ---------------------------------------------------------------------------
  typedef enum logic [6:0] {
    OP_R      = 7'b0110011,  // R-type
    OP_IMM    = 7'b0010011,  // I-type ALU inmediato (addi, slli, slti, sltiu, xori, srli, srai, ori, andi)
    OP_LOAD   = 7'b0000011,  // I-type carga (lb, lh, lw, lbu, lhu)
    OP_JALR   = 7'b1100111,  // I-type salto (jalr)
    OP_STORE  = 7'b0100011,  // S-type (sb, sh, sw)
    OP_BRANCH = 7'b1100011,  // B-type (beq, bne)
    OP_LUI    = 7'b0110111,  // U-type (lui)
    OP_JAL    = 7'b1101111   // J-type (jal)
  } opcode_e;

  // ---------------------------------------------------------------------------
  // Operación interna de ALU (ya decodificada por el control unit,
  // no es el encoding crudo de funct3/funct7)
  // ---------------------------------------------------------------------------
  typedef enum logic [3:0] {
    ALU_ADD,
    ALU_SUB,
    ALU_SLL,
    ALU_SLT,
    ALU_SLTU,
    ALU_XOR,
    ALU_SRL,
    ALU_SRA,
    ALU_OR,
    ALU_AND,
    ALU_PASS   // resultado = b, sin usar a (lui carga el inmediato directo)
  } alu_op_e;

  // ---------------------------------------------------------------------------
  // Tipo de inmediato -> selecciona el generador de inmediato en Decode
  // ---------------------------------------------------------------------------
  typedef enum logic [2:0] {
    IMM_I,
    IMM_S,
    IMM_B,
    IMM_U,
    IMM_J,
    IMM_X   // no aplica (R-type no usa inmediato)
  } imm_src_e;

  // ---------------------------------------------------------------------------
  // Tamaño de acceso a memoria de datos (load/store)
  // ---------------------------------------------------------------------------
  typedef enum logic [1:0] {
    MEM_BYTE,
    MEM_HALF,
    MEM_WORD
  } mem_size_e;

  // ---------------------------------------------------------------------------
  // Origen del dato que se escribe en rd (reemplaza al viejo mem_to_reg de 1 bit,
  // que solo alcanzaba para elegir entre ALU y memoria: jal/jalr necesitan
  // escribir PC+4, un tercer origen)
  // ---------------------------------------------------------------------------
  typedef enum logic [1:0] {
    WB_ALU,
    WB_MEM,
    WB_PC4
  } wb_src_e;

  // ---------------------------------------------------------------------------
  // Señales de control generadas en Decode
  // ---------------------------------------------------------------------------
  typedef struct packed {
    logic      reg_write;    // habilita escritura en el banco de registros
    logic      mem_read;     // habilita lectura de memoria de datos
    logic      mem_write;    // habilita escritura en memoria de datos
    wb_src_e   wb_src;       // qué se escribe en rd: ALU, memoria, o PC+4
    logic      alu_src;      // 1: segundo operando de la ALU es el inmediato, 0: es rs2
    logic      branch;       // instrucción branch (evaluar condición en EX/MEM)
    logic      jump;         // salto incondicional (jal o jalr)
    logic      jalr;         // 1 específicamente en jalr: el target es rs1+imm, no pc+imm
    logic      mem_unsigned; // 1: extensión sin signo en la carga (lbu/lhu)
    alu_op_e   alu_op;
    mem_size_e mem_size;
    imm_src_e  imm_src;
  } ctrl_t;

  // ---------------------------------------------------------------------------
  // Campos genéricos de la instrucción cruda (posiciones fijas del ISA:
  // opcode, rd, funct3, rs1, rs2 y funct7 siempre caen en el mismo rango
  // de bits, independientemente del tipo de instrucción)
  // ---------------------------------------------------------------------------
  typedef struct packed {
    logic [6:0] funct7;
    logic [4:0] rs2;
    logic [4:0] rs1;
    logic [2:0] funct3;
    logic [4:0] rd;
    logic [6:0] opcode;
  } instr_fields_t;

  // ---------------------------------------------------------------------------
  // Pendiente (paso 3 del plan): structs de latches de pipeline
  // if_id_t, id_ex_t, ex_mem_t, mem_wb_t
  // ---------------------------------------------------------------------------

endpackage