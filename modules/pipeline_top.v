`timescale 1ns / 1ps
`include "riscv_defs.vh"
// Nota Verilog-2001: los puertos de entrada ya no tienen valor por defecto.
// Para usar el pipeline "suelto" (sin Debug Unit) conectar:
//   enable=1, program_len={`IMEM_ADDR_W{1'b1}} (nunca halt por rango),
//   imem_we=0, imem_waddr=0, imem_wdata=0, regfile_debug_addr=0, dmem_debug_addr=0
//
// Nota de la conversión SV -> Verilog: los 4 latches de pipeline (antes
// pipe_reg #(.T(if_id_t)) etc., con structs packed) ahora son 4 modulos
// con puertos individuales con nombre (if_id_reg/id_ex_reg/ex_mem_reg/
// mem_wb_reg) -- no hay un bus intermedio ni offsets de bits calculados a
// mano en ningun lado de este archivo. Los puertos EXTERNOS de este modulo
// (if_id_q_out/id_ex_q_out/ex_mem_q_out/mem_wb_q_out) siguen siendo buses
// planos, para no tener que tocar system_top.v ni debug_unit.v: se arman
// con un unico `{...}` de concatenacion al final de este archivo, en el
// mismo orden de campos (MSB primero) que tenian los structs/bus
// originales -- así que DUMP_LATCHES sigue mandando exactamente los
// mismos bytes de siempre.
module pipeline_top (
    input  wire clk,
    input  wire rst,
    input  wire enable,  // 0 = pausa todo el pipeline sin tocar el clock (sección 3 del README) [antes default 1'b1]

    // --- Hacia/desde la Debug Unit (sección 4 del README) ---
    input  wire [`IMEM_ADDR_W-1:0] program_len,         // [antes default '1: nunca halt por rango]
    input  wire                    imem_we,             // [antes default 1'b0]
    input  wire [`IMEM_ADDR_W-1:0] imem_waddr,          // [antes default '0]
    input  wire [31:0]             imem_wdata,          // [antes default '0]
    input  wire [`REG_ADDR_W-1:0]  regfile_debug_addr,  // [antes default '0]
    output wire [`XLEN-1:0]        regfile_debug_data,
    input  wire [`DMEM_ADDR_W-1:0] dmem_debug_addr,     // [antes default '0]
    output wire [7:0]              dmem_debug_data,
    output wire                    halted,
    output reg  [`HALT_CODE_W-1:0] halt_code,

    // --- Hacia la Debug Unit: latches crudos, para DUMP_LATCHES ---
    output wire [`IF_ID_W-1:0]  if_id_q_out,
    output wire [`ID_EX_W-1:0]  id_ex_q_out,
    output wire [`EX_MEM_W-1:0] ex_mem_q_out,
    output wire [`MEM_WB_W-1:0] mem_wb_q_out
);

  // redirect/redirect_pc se declaran acá arriba porque IF los necesita
  // (para el mux de pc_next) y todavía no llegamos a EX, que es donde se
  // generan.
  wire        redirect;
  wire [31:0] redirect_pc;

  // stall_load_use, misma razón otra vez: pc_reg y el latch if_id lo
  // necesitan en IF, y se calcula recién en la sección EX.
  wire stall_load_use;

  // ---------------------------------------------------------------------
  // Señales "d_"/"q_" de los 4 latches, todas declaradas acá arriba (en
  // Verilog un identificador tiene que existir antes de usarse, y cada
  // etapa lee campos de latches que "viven" en etapas posteriores:
  // halted, forwarding, WB).
  // ---------------------------------------------------------------------

  // ---- IF/ID ----
  wire        ifid_d_valid;
  wire [31:0] ifid_d_pc, ifid_d_pc_plus4, ifid_d_instr;
  wire        ifid_q_valid;
  wire [31:0] ifid_q_pc, ifid_q_pc_plus4, ifid_q_instr;

  // ---- ID/EX ----
  wire        idex_d_valid;
  wire [31:0] idex_d_pc, idex_d_pc_plus4, idex_d_rs1_data, idex_d_rs2_data, idex_d_imm;
  wire [4:0]  idex_d_rs1, idex_d_rs2, idex_d_rd;
  wire [2:0]  idex_d_funct3;
  wire        idex_d_reg_write, idex_d_mem_read, idex_d_mem_write, idex_d_alu_src;
  wire        idex_d_branch, idex_d_jump, idex_d_jalr, idex_d_mem_unsigned;
  wire [1:0]  idex_d_wb_src, idex_d_mem_size;
  wire [3:0]  idex_d_alu_op;
  wire [2:0]  idex_d_imm_src;

  wire        idex_q_valid;
  wire [31:0] idex_q_pc, idex_q_pc_plus4, idex_q_rs1_data, idex_q_rs2_data, idex_q_imm;
  wire [4:0]  idex_q_rs1, idex_q_rs2, idex_q_rd;
  wire [2:0]  idex_q_funct3;
  wire        idex_q_reg_write, idex_q_mem_read, idex_q_mem_write, idex_q_alu_src;
  wire        idex_q_branch, idex_q_jump, idex_q_jalr, idex_q_mem_unsigned;
  wire [1:0]  idex_q_wb_src, idex_q_mem_size;
  wire [3:0]  idex_q_alu_op;
  wire [2:0]  idex_q_imm_src;

  // ---- EX/MEM ----
  wire        exmem_d_valid;
  wire [31:0] exmem_d_alu_result, exmem_d_rs2_data, exmem_d_pc_plus4;
  wire [4:0]  exmem_d_rd;
  wire        exmem_d_reg_write, exmem_d_mem_read, exmem_d_mem_write, exmem_d_alu_src;
  wire        exmem_d_branch, exmem_d_jump, exmem_d_jalr, exmem_d_mem_unsigned;
  wire [1:0]  exmem_d_wb_src, exmem_d_mem_size;
  wire [3:0]  exmem_d_alu_op;
  wire [2:0]  exmem_d_imm_src;

  wire        exmem_q_valid;
  wire [31:0] exmem_q_alu_result, exmem_q_rs2_data, exmem_q_pc_plus4;
  wire [4:0]  exmem_q_rd;
  wire        exmem_q_reg_write, exmem_q_mem_read, exmem_q_mem_write, exmem_q_alu_src;
  wire        exmem_q_branch, exmem_q_jump, exmem_q_jalr, exmem_q_mem_unsigned;
  wire [1:0]  exmem_q_wb_src, exmem_q_mem_size;
  wire [3:0]  exmem_q_alu_op;
  wire [2:0]  exmem_q_imm_src;

  // ---- MEM/WB ----
  wire        memwb_d_valid;
  wire [31:0] memwb_d_mem_data, memwb_d_alu_result, memwb_d_pc_plus4;
  wire [4:0]  memwb_d_rd;
  wire        memwb_d_reg_write, memwb_d_mem_read, memwb_d_mem_write, memwb_d_alu_src;
  wire        memwb_d_branch, memwb_d_jump, memwb_d_jalr, memwb_d_mem_unsigned;
  wire [1:0]  memwb_d_wb_src, memwb_d_mem_size;
  wire [3:0]  memwb_d_alu_op;
  wire [2:0]  memwb_d_imm_src;

  wire        memwb_q_valid;
  wire [31:0] memwb_q_mem_data, memwb_q_alu_result, memwb_q_pc_plus4;
  wire [4:0]  memwb_q_rd;
  wire        memwb_q_reg_write, memwb_q_mem_read, memwb_q_mem_write, memwb_q_alu_src;
  wire        memwb_q_branch, memwb_q_jump, memwb_q_jalr, memwb_q_mem_unsigned;
  wire [1:0]  memwb_q_wb_src, memwb_q_mem_size;
  wire [3:0]  memwb_q_alu_op;
  wire [2:0]  memwb_q_imm_src;

  // Halt (sección 2 del README). Por rango: el PC ya se fue mas allá de lo
  // que la Debug Unit cargó. Por ilegal: control_unit no reconoció la
  // instrucción actual de ID. Importante: no es un freeze de golpe --eso
  // cortaría instrucciones legítimas todavía en tránsito por EX/MEM/WB--
  // sino que a partir de que se dispara, if_id_reg se flushea (como ante
  // un branch mal predicho) para no aceptar más instrucciones nuevas, y
  // "halted" recién se levanta cuando los 4 latches ya drenaron a burbuja.
  wire halt_by_range, halt_by_illegal, halt_trigger;
  reg  halt_latched, halt_cause_illegal_latched;
  wire run_enable;  // 1 = se puede avanzar este ciclo (por ahora, solo enable)

  assign run_enable   = enable;
  assign halt_trigger = halt_by_range || halt_by_illegal;

  always @(posedge clk) begin
    if (rst) begin
      halt_latched               <= 1'b0;
      halt_cause_illegal_latched <= 1'b0;
    end else if (run_enable && !halt_latched && halt_trigger) begin
      halt_latched               <= 1'b1;
      halt_cause_illegal_latched <= halt_by_illegal;
    end
  end

  // Ya drenado: ninguno de los 4 latches tiene una instrucción real adentro
  assign halted = halt_latched && !ifid_q_valid && !idex_q_valid
                  && !exmem_q_valid && !memwb_q_valid;

  always @* begin
    if (!halted)                          halt_code = `HALT_NONE;
    else if (halt_cause_illegal_latched)  halt_code = `HALT_ILLEGAL;
    else                                  halt_code = `HALT_RANGE;
  end

  // ============================================================ IF
  wire [31:0] pc, pc_next, pc_plus4_if, instr_if;

  assign pc_plus4_if   = pc + 32'd4;
  assign pc_next       = redirect ? redirect_pc : pc_plus4_if;
  assign halt_by_range = (pc[`IMEM_ADDR_W+1:2] >= program_len);

  pc_reg u_pc (.clk(clk), .rst(rst), .stall(stall_load_use || halt_latched || !run_enable), .pc_next(pc_next), .pc(pc));
  imem u_imem (
      .clk(clk), .we(imem_we), .waddr(imem_waddr), .wdata(imem_wdata),
      .addr(pc[`IMEM_ADDR_W+1:0]), .instr(instr_if)
  );

  assign ifid_d_valid    = 1'b1;  // IF siempre produce un fetch real este ciclo
  assign ifid_d_pc       = pc;
  assign ifid_d_pc_plus4 = pc_plus4_if;
  assign ifid_d_instr    = instr_if;

  // flush por halt: usa halt_trigger (combinacional) para cortar YA en el
  // mismo ciclo en que se detecta -- si usara solo halt_latched (que recién
  // vale 1 el ciclo siguiente) se colaría una instrucción de más antes de
  // que el flush hiciera efecto. halt_latched sostiene el flush después,
  // una vez que if_id_q ya dejó de mostrar la condición que lo disparó.
  if_id_reg u_if_id (
      .clk(clk), .rst(rst), .flush(redirect || halt_trigger || halt_latched), .stall(stall_load_use || !run_enable),
      .d_valid(ifid_d_valid), .d_pc(ifid_d_pc), .d_pc_plus4(ifid_d_pc_plus4), .d_instr(ifid_d_instr),
      .q_valid(ifid_q_valid), .q_pc(ifid_q_pc), .q_pc_plus4(ifid_q_pc_plus4), .q_instr(ifid_q_instr)
  );

  // ============================================================ ID
  wire [31:0] fields_id;
  assign fields_id = ifid_q_instr;

  wire        ctrl_id_reg_write, ctrl_id_mem_read, ctrl_id_mem_write, ctrl_id_alu_src;
  wire        ctrl_id_branch, ctrl_id_jump, ctrl_id_jalr, ctrl_id_mem_unsigned;
  wire [1:0]  ctrl_id_wb_src, ctrl_id_mem_size;
  wire [3:0]  ctrl_id_alu_op;
  wire [2:0]  ctrl_id_imm_src;
  wire        illegal_id;
  control_unit u_ctrl (
      .opcode(fields_id[`INSTR_OPCODE]), .funct3(fields_id[`INSTR_FUNCT3]), .funct7(fields_id[`INSTR_FUNCT7]),
      .reg_write(ctrl_id_reg_write), .mem_read(ctrl_id_mem_read), .mem_write(ctrl_id_mem_write),
      .wb_src(ctrl_id_wb_src), .alu_src(ctrl_id_alu_src),
      .branch(ctrl_id_branch), .jump(ctrl_id_jump), .jalr(ctrl_id_jalr), .mem_unsigned(ctrl_id_mem_unsigned),
      .alu_op(ctrl_id_alu_op), .mem_size(ctrl_id_mem_size), .imm_src(ctrl_id_imm_src),
      .illegal(illegal_id)
  );

  assign halt_by_illegal = illegal_id && ifid_q_valid;

  wire [31:0] imm_id;
  imm_gen u_imm (.instr(ifid_q_instr), .imm_src(ctrl_id_imm_src), .imm(imm_id));

  wire [31:0] rs1_data_id, rs2_data_id;
  reg  [31:0] wb_data;

  regfile #(.ENABLE_WB_BYPASS(1'b1)) u_regfile (
      .clk(clk), .rst(rst), .enable(run_enable), .we(memwb_q_reg_write),
      .rs1_addr(fields_id[`INSTR_RS1]), .rs2_addr(fields_id[`INSTR_RS2]), .rd_addr(memwb_q_rd),
      .rd_data(wb_data), .rs1_data(rs1_data_id), .rs2_data(rs2_data_id),
      .debug_addr(regfile_debug_addr), .debug_data(regfile_debug_data)
  );

  assign idex_d_valid    = ifid_q_valid;
  assign idex_d_pc       = ifid_q_pc;
  assign idex_d_pc_plus4 = ifid_q_pc_plus4;
  assign idex_d_rs1_data = rs1_data_id;
  assign idex_d_rs2_data = rs2_data_id;
  assign idex_d_imm      = imm_id;
  assign idex_d_rs1      = fields_id[`INSTR_RS1];
  assign idex_d_rs2      = fields_id[`INSTR_RS2];
  assign idex_d_rd       = fields_id[`INSTR_RD];
  assign idex_d_funct3   = fields_id[`INSTR_FUNCT3];

  assign idex_d_reg_write    = ctrl_id_reg_write;
  assign idex_d_mem_read     = ctrl_id_mem_read;
  assign idex_d_mem_write    = ctrl_id_mem_write;
  assign idex_d_wb_src       = ctrl_id_wb_src;
  assign idex_d_alu_src      = ctrl_id_alu_src;
  assign idex_d_branch       = ctrl_id_branch;
  assign idex_d_jump         = ctrl_id_jump;
  assign idex_d_jalr         = ctrl_id_jalr;
  assign idex_d_mem_unsigned = ctrl_id_mem_unsigned;
  assign idex_d_alu_op       = ctrl_id_alu_op;
  assign idex_d_mem_size     = ctrl_id_mem_size;
  assign idex_d_imm_src      = ctrl_id_imm_src;

  id_ex_reg u_id_ex (
      .clk(clk), .rst(rst), .flush(redirect || stall_load_use), .stall(!run_enable),
      .d_valid(idex_d_valid), .d_pc(idex_d_pc), .d_pc_plus4(idex_d_pc_plus4),
      .d_rs1_data(idex_d_rs1_data), .d_rs2_data(idex_d_rs2_data), .d_imm(idex_d_imm),
      .d_rs1(idex_d_rs1), .d_rs2(idex_d_rs2), .d_rd(idex_d_rd), .d_funct3(idex_d_funct3),
      .d_reg_write(idex_d_reg_write), .d_mem_read(idex_d_mem_read), .d_mem_write(idex_d_mem_write),
      .d_wb_src(idex_d_wb_src), .d_alu_src(idex_d_alu_src), .d_branch(idex_d_branch),
      .d_jump(idex_d_jump), .d_jalr(idex_d_jalr), .d_mem_unsigned(idex_d_mem_unsigned),
      .d_alu_op(idex_d_alu_op), .d_mem_size(idex_d_mem_size), .d_imm_src(idex_d_imm_src),
      .q_valid(idex_q_valid), .q_pc(idex_q_pc), .q_pc_plus4(idex_q_pc_plus4),
      .q_rs1_data(idex_q_rs1_data), .q_rs2_data(idex_q_rs2_data), .q_imm(idex_q_imm),
      .q_rs1(idex_q_rs1), .q_rs2(idex_q_rs2), .q_rd(idex_q_rd), .q_funct3(idex_q_funct3),
      .q_reg_write(idex_q_reg_write), .q_mem_read(idex_q_mem_read), .q_mem_write(idex_q_mem_write),
      .q_wb_src(idex_q_wb_src), .q_alu_src(idex_q_alu_src), .q_branch(idex_q_branch),
      .q_jump(idex_q_jump), .q_jalr(idex_q_jalr), .q_mem_unsigned(idex_q_mem_unsigned),
      .q_alu_op(idex_q_alu_op), .q_mem_size(idex_q_mem_size), .q_imm_src(idex_q_imm_src)
  );

  // ============================================================ EX
  // Nota: antes había un wire ctrl_ex = id_ex_q[`ID_EX_CTRL]; ya no hace
  // falta -- los 12 campos de control salen del latch id_ex_reg como
  // puertos con nombre (idex_q_*), listos para usar directo.

  // --- Detección de load-use (afecta IF/ID, se calcula acá porque necesita ctrl_ex) ---
  hazard_detect u_hazard (
      .id_ex_mem_read(idex_q_mem_read), .id_ex_rd(idex_q_rd),
      .rs1_id(fields_id[`INSTR_RS1]), .rs2_id(fields_id[`INSTR_RS2]),
      .stall_load_use(stall_load_use)
  );

  // --- Forwarding ---
  wire [`FWD_SRC_W-1:0] forward_a, forward_b;
  forward_unit u_fwd (
      .rs1_ex(idex_q_rs1), .rs2_ex(idex_q_rs2),
      .rd_ex_mem(exmem_q_rd), .reg_write_ex_mem(exmem_q_reg_write),
      .rd_mem_wb(memwb_q_rd), .reg_write_mem_wb(memwb_q_reg_write),
      .forward_a(forward_a), .forward_b(forward_b)
  );

  // Qué forwardear desde EX/MEM: para la mayoría de las instrucciones es
  // alu_result, pero jal/jalr escriben pc_plus4, no el resultado de la ALU.
  // Si la productora en EX/MEM es un load (wb_src==WB_MEM), esto todavía da
  // el valor incorrecto -- la dirección calculada, no el dato leído -- pero
  // ese caso específico (load-use) lo resuelve el stall del próximo paso,
  // no el forwarding.
  wire [31:0] ex_mem_fwd_val;
  assign ex_mem_fwd_val = (exmem_q_wb_src == `WB_PC4) ? exmem_q_pc_plus4 : exmem_q_alu_result;

  reg [31:0] rs1_fwd, rs2_fwd;
  always @* begin
    case (forward_a)
      `FWD_EX_MEM: rs1_fwd = ex_mem_fwd_val;
      `FWD_MEM_WB: rs1_fwd = wb_data;
      default:     rs1_fwd = idex_q_rs1_data;
    endcase
  end
  always @* begin
    case (forward_b)
      `FWD_EX_MEM: rs2_fwd = ex_mem_fwd_val;
      `FWD_MEM_WB: rs2_fwd = wb_data;
      default:     rs2_fwd = idex_q_rs2_data;
    endcase
  end

  wire [31:0] alu_b_ex, alu_result_ex;
  wire        alu_zero_ex;
  assign alu_b_ex = idex_q_alu_src ? idex_q_imm : rs2_fwd;

  alu u_alu (
      .a(rs1_fwd), .b(alu_b_ex), .op(idex_q_alu_op),
      .result(alu_result_ex), .zero(alu_zero_ex)
  );

  // rs1_data acá también tiene que ser el forwardeado: si no, un jalr cuyo
  // rs1 se escribió una o dos instrucciones antes calcularía mal el target.
  branch_resolve u_branch (
      .pc(idex_q_pc), .imm(idex_q_imm), .rs1_data(rs1_fwd),
      .alu_zero(alu_zero_ex), .funct3(idex_q_funct3),
      .branch(idex_q_branch), .jump(idex_q_jump), .jalr(idex_q_jalr),
      .redirect(redirect), .redirect_pc(redirect_pc)
  );

  assign exmem_d_valid      = idex_q_valid;
  assign exmem_d_alu_result = alu_result_ex;
  assign exmem_d_rs2_data   = rs2_fwd;  // dato de store, ya forwardeado
  assign exmem_d_rd         = idex_q_rd;
  assign exmem_d_pc_plus4   = idex_q_pc_plus4;

  assign exmem_d_reg_write    = idex_q_reg_write;
  assign exmem_d_mem_read     = idex_q_mem_read;
  assign exmem_d_mem_write    = idex_q_mem_write;
  assign exmem_d_wb_src       = idex_q_wb_src;
  assign exmem_d_alu_src      = idex_q_alu_src;
  assign exmem_d_branch       = idex_q_branch;
  assign exmem_d_jump         = idex_q_jump;
  assign exmem_d_jalr         = idex_q_jalr;
  assign exmem_d_mem_unsigned = idex_q_mem_unsigned;
  assign exmem_d_alu_op       = idex_q_alu_op;
  assign exmem_d_mem_size     = idex_q_mem_size;
  assign exmem_d_imm_src      = idex_q_imm_src;

  // Nunca se flushea: la instrucción que está en EX cuando se resuelve el
  // branch es la del branch mismo (legítima), no una de las especulativas.
  ex_mem_reg u_ex_mem (
      .clk(clk), .rst(rst), .flush(1'b0), .stall(!run_enable),
      .d_valid(exmem_d_valid), .d_alu_result(exmem_d_alu_result), .d_rs2_data(exmem_d_rs2_data),
      .d_rd(exmem_d_rd), .d_pc_plus4(exmem_d_pc_plus4),
      .d_reg_write(exmem_d_reg_write), .d_mem_read(exmem_d_mem_read), .d_mem_write(exmem_d_mem_write),
      .d_wb_src(exmem_d_wb_src), .d_alu_src(exmem_d_alu_src), .d_branch(exmem_d_branch),
      .d_jump(exmem_d_jump), .d_jalr(exmem_d_jalr), .d_mem_unsigned(exmem_d_mem_unsigned),
      .d_alu_op(exmem_d_alu_op), .d_mem_size(exmem_d_mem_size), .d_imm_src(exmem_d_imm_src),
      .q_valid(exmem_q_valid), .q_alu_result(exmem_q_alu_result), .q_rs2_data(exmem_q_rs2_data),
      .q_rd(exmem_q_rd), .q_pc_plus4(exmem_q_pc_plus4),
      .q_reg_write(exmem_q_reg_write), .q_mem_read(exmem_q_mem_read), .q_mem_write(exmem_q_mem_write),
      .q_wb_src(exmem_q_wb_src), .q_alu_src(exmem_q_alu_src), .q_branch(exmem_q_branch),
      .q_jump(exmem_q_jump), .q_jalr(exmem_q_jalr), .q_mem_unsigned(exmem_q_mem_unsigned),
      .q_alu_op(exmem_q_alu_op), .q_mem_size(exmem_q_mem_size), .q_imm_src(exmem_q_imm_src)
  );

  // ============================================================ MEM
  wire [31:0] dmem_rdata_mem;

  // Antes hacía falta un wire intermedio (alu_result_mem) porque Verilog
  // no permite encadenar selecciones (x[a:b][c:d]) sobre una expresión de
  // bus. Ahora exmem_q_alu_result ya es un wire propio (puerto con
  // nombre del latch), así que se puede indexar directo.
  dmem u_dmem (
      .clk(clk), .enable(run_enable), .mem_read(exmem_q_mem_read), .mem_write(exmem_q_mem_write),
      .mem_size(exmem_q_mem_size), .mem_unsigned(exmem_q_mem_unsigned),
      .addr(exmem_q_alu_result[`DMEM_ADDR_W-1:0]), .wdata(exmem_q_rs2_data),
      .rdata(dmem_rdata_mem),
      .debug_addr(dmem_debug_addr), .debug_data(dmem_debug_data)
  );

  assign memwb_d_valid      = exmem_q_valid;
  assign memwb_d_mem_data   = dmem_rdata_mem;
  assign memwb_d_alu_result = exmem_q_alu_result;
  assign memwb_d_pc_plus4   = exmem_q_pc_plus4;
  assign memwb_d_rd         = exmem_q_rd;

  assign memwb_d_reg_write    = exmem_q_reg_write;
  assign memwb_d_mem_read     = exmem_q_mem_read;
  assign memwb_d_mem_write    = exmem_q_mem_write;
  assign memwb_d_wb_src       = exmem_q_wb_src;
  assign memwb_d_alu_src      = exmem_q_alu_src;
  assign memwb_d_branch       = exmem_q_branch;
  assign memwb_d_jump         = exmem_q_jump;
  assign memwb_d_jalr         = exmem_q_jalr;
  assign memwb_d_mem_unsigned = exmem_q_mem_unsigned;
  assign memwb_d_alu_op       = exmem_q_alu_op;
  assign memwb_d_mem_size     = exmem_q_mem_size;
  assign memwb_d_imm_src      = exmem_q_imm_src;

  mem_wb_reg u_mem_wb (
      .clk(clk), .rst(rst), .flush(1'b0), .stall(!run_enable),
      .d_valid(memwb_d_valid), .d_mem_data(memwb_d_mem_data), .d_alu_result(memwb_d_alu_result),
      .d_pc_plus4(memwb_d_pc_plus4), .d_rd(memwb_d_rd),
      .d_reg_write(memwb_d_reg_write), .d_mem_read(memwb_d_mem_read), .d_mem_write(memwb_d_mem_write),
      .d_wb_src(memwb_d_wb_src), .d_alu_src(memwb_d_alu_src), .d_branch(memwb_d_branch),
      .d_jump(memwb_d_jump), .d_jalr(memwb_d_jalr), .d_mem_unsigned(memwb_d_mem_unsigned),
      .d_alu_op(memwb_d_alu_op), .d_mem_size(memwb_d_mem_size), .d_imm_src(memwb_d_imm_src),
      .q_valid(memwb_q_valid), .q_mem_data(memwb_q_mem_data), .q_alu_result(memwb_q_alu_result),
      .q_pc_plus4(memwb_q_pc_plus4), .q_rd(memwb_q_rd),
      .q_reg_write(memwb_q_reg_write), .q_mem_read(memwb_q_mem_read), .q_mem_write(memwb_q_mem_write),
      .q_wb_src(memwb_q_wb_src), .q_alu_src(memwb_q_alu_src), .q_branch(memwb_q_branch),
      .q_jump(memwb_q_jump), .q_jalr(memwb_q_jalr), .q_mem_unsigned(memwb_q_mem_unsigned),
      .q_alu_op(memwb_q_alu_op), .q_mem_size(memwb_q_mem_size), .q_imm_src(memwb_q_imm_src)
  );

  // ============================================================ WB
  always @* begin
    case (memwb_q_wb_src)
      `WB_ALU: wb_data = memwb_q_alu_result;
      `WB_MEM: wb_data = memwb_q_mem_data;
      `WB_PC4: wb_data = memwb_q_pc_plus4;
      default: wb_data = memwb_q_alu_result;
    endcase
  end

  // -----------------------------------------------------------------------
  // Latches crudos hacia la Debug Unit (DUMP_LATCHES). Único punto donde
  // los campos con nombre vuelven a juntarse en un bus plano -- mismo
  // orden de campos (MSB primero) que tenían if_id_t/id_ex_t/ex_mem_t/
  // mem_wb_t (y ctrl_t adentro de cada uno) en la versión SV original, así
  // que el byte-stream que arma debug_unit.v no cambia un bit.
  // -----------------------------------------------------------------------
  assign if_id_q_out = {ifid_q_valid, ifid_q_pc, ifid_q_pc_plus4, ifid_q_instr};

  assign id_ex_q_out = {
      idex_q_valid, idex_q_pc, idex_q_pc_plus4, idex_q_rs1_data, idex_q_rs2_data, idex_q_imm,
      idex_q_rs1, idex_q_rs2, idex_q_rd, idex_q_funct3,
      idex_q_reg_write, idex_q_mem_read, idex_q_mem_write, idex_q_wb_src, idex_q_alu_src,
      idex_q_branch, idex_q_jump, idex_q_jalr, idex_q_mem_unsigned,
      idex_q_alu_op, idex_q_mem_size, idex_q_imm_src
  };

  assign ex_mem_q_out = {
      exmem_q_valid, exmem_q_alu_result, exmem_q_rs2_data, exmem_q_rd, exmem_q_pc_plus4,
      exmem_q_reg_write, exmem_q_mem_read, exmem_q_mem_write, exmem_q_wb_src, exmem_q_alu_src,
      exmem_q_branch, exmem_q_jump, exmem_q_jalr, exmem_q_mem_unsigned,
      exmem_q_alu_op, exmem_q_mem_size, exmem_q_imm_src
  };

  assign mem_wb_q_out = {
      memwb_q_valid, memwb_q_mem_data, memwb_q_alu_result, memwb_q_pc_plus4, memwb_q_rd,
      memwb_q_reg_write, memwb_q_mem_read, memwb_q_mem_write, memwb_q_wb_src, memwb_q_alu_src,
      memwb_q_branch, memwb_q_jump, memwb_q_jalr, memwb_q_mem_unsigned,
      memwb_q_alu_op, memwb_q_mem_size, memwb_q_imm_src
  };

endmodule
