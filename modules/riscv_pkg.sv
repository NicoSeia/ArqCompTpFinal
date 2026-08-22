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
  // Latches de pipeline (paso 3 del plan)
  //
  // Decisión de diseño: los branches/jumps se resuelven en EX (igual que en
  // el diseño clásico de libro), no en ID. Consecuencia: cuando se toma un
  // salto, IF ya trajo 2 instrucciones de más (la que sigue al branch, y la
  // siguiente a esa) que hay que flushear -> penalidad de 3 ciclos.
  //
  // Por eso PC+4 se calcula en IF (no depende de decodificar nada) y viaja
  // en todos los latches hasta WB, donde jal/jalr lo necesitan para escribir
  // la dirección de retorno en rd. El target de branch/jal (pc+imm) y el de
  // jalr (rs1+imm) se calculan recién en EX, y de ahí sale directo la señal
  // de redirect + flush hacia IF - no viajan en los latches porque no son
  // datos que se propaguen etapa a etapa, son una corrección puntual del PC.
  // ---------------------------------------------------------------------------
 
  // IF/ID: lo mínimo que ID necesita para decodificar
  typedef struct packed {
    logic        valid;     // 0 en un bubble estructural (reset o flush);
                             // 1 en cualquier fetch real, aunque sea basura
                             // mas alla del programa. Sin esto, un bubble
                             // (instr=0, el mismo encoding que "ilegal")
                             // dispararía halt por ilegal apenas arranca
                             // el pipeline, antes de la primera instrucción
                             // real.
    logic [31:0] pc;
    logic [31:0] pc_plus4;
    logic [31:0] instr;
  } if_id_t;
 
  // ID/EX: instrucción ya decodificada, lista para ejecutar
  typedef struct packed {
    logic                  valid;      // propagado desde if_id_t (ver ahí)
    logic [31:0]           pc;         // para pc_target = pc + imm en EX
    logic [31:0]           pc_plus4;   // viaja hasta WB (jal/jalr)
    logic [31:0]           rs1_data;
    logic [31:0]           rs2_data;
    logic [31:0]           imm;
    logic [REG_ADDR_W-1:0] rs1;        // número de registro (no el dato) -> forwarding futuro
    logic [REG_ADDR_W-1:0] rs2;
    logic [REG_ADDR_W-1:0] rd;
    logic [2:0]             funct3;     // distingue beq/bne en EX
    ctrl_t                  ctrl;
  } id_ex_t;
 
  // EX/MEM: resultado de la ALU, listo para memoria o para WB directo
  typedef struct packed {
    logic                  valid;      // propagado desde id_ex_t
    logic [31:0]           alu_result;
    logic [31:0]           rs2_data;   // dato a guardar si es store
    logic [REG_ADDR_W-1:0] rd;
    logic [31:0]           pc_plus4;
    ctrl_t                  ctrl;
  } ex_mem_t;
 
  // MEM/WB: lo que sea que se termine escribiendo en el banco de registros
  typedef struct packed {
    logic                  valid;      // propagado desde ex_mem_t
    logic [31:0]           mem_data;
    logic [31:0]           alu_result;
    logic [31:0]           pc_plus4;
    logic [REG_ADDR_W-1:0] rd;
    ctrl_t                  ctrl;
  } mem_wb_t;
 
  // ---------------------------------------------------------------------------
  // Fuente del forwarding (paso 3 del plan: unidad de riesgos)
  // ---------------------------------------------------------------------------
  typedef enum logic [1:0] {
    FWD_NONE,     // usar el valor que ya trajo el regfile en ID
    FWD_EX_MEM,   // forward desde ex_mem_q.alu_result (instrucción inmediatamente anterior, gap=1)
    FWD_MEM_WB    // forward desde el dato de write-back (dos instrucciones antes, gap=2)
  } fwd_src_e;
 
  // ---------------------------------------------------------------------------
  // Código de HALT (sección 2 del README): distingue las dos causas para la
  // respuesta de 1 byte que RUN/STEP le deben al host (sección 4)
  // ---------------------------------------------------------------------------
  typedef enum logic [1:0] {
    HALT_NONE,     // sigue corriendo
    HALT_RANGE,    // PC se fue mas alla del programa cargado
    HALT_ILLEGAL   // instruccion no reconocida por control_unit
  } halt_code_e;

endpackage