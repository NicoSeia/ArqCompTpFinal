`timescale 1ns / 1ps
module pipeline_top
  import riscv_pkg::*;
(
    input logic clk,
    input logic rst,
    input logic enable = 1'b1,  // 0 = pausa todo el pipeline sin tocar el clock (sección 3 del README)
 
    // --- Hacia/desde la Debug Unit (sección 4 del README) ---
    input  logic [IMEM_ADDR_W-1:0] program_len = '1,  // default: nunca halt por rango
    input  logic                   imem_we = 1'b0,
    input  logic [IMEM_ADDR_W-1:0] imem_waddr = '0,
    input  logic [31:0]            imem_wdata = '0,
    input  logic [REG_ADDR_W-1:0]  regfile_debug_addr = '0,
    output logic [XLEN-1:0]        regfile_debug_data,
    input  logic [DMEM_ADDR_W-1:0] dmem_debug_addr = '0,
    output logic [7:0]             dmem_debug_data,
    output logic                   halted,
    output halt_code_e             halt_code,
 
    // --- Hacia la Debug Unit: latches crudos, para DUMP_LATCHES ---
    output if_id_t  if_id_q_out,
    output id_ex_t  id_ex_q_out,
    output ex_mem_t ex_mem_q_out,
    output mem_wb_t mem_wb_q_out
);
 
  // redirect/redirect_pc se declaran acá arriba porque IF los necesita
  // (para el mux de pc_next) y todavía no llegamos a EX, que es donde se
  // generan.
  logic        redirect;
  logic [31:0] redirect_pc;
 
  // mem_wb_q también se declara temprano: ID necesita su .rd y su
  // ctrl.reg_write para el puerto de escritura del regfile, y todavía no
  // llegamos a WB, que es donde vive el registro que lo produce.
  mem_wb_t mem_wb_q;
 
  // ex_mem_q y ctrl_mem, misma razón: forward_unit (en EX) necesita el rd
  // y el reg_write de la instrucción que ya está en EX/MEM, antes de llegar
  // a la sección MEM que es donde naturalmente "viven".
  ex_mem_t ex_mem_d, ex_mem_q;
  ctrl_t   ctrl_mem;
  assign ctrl_mem = ex_mem_q.ctrl;
 
  // stall_load_use, misma razón otra vez: pc_reg y el latch if_id lo
  // necesitan en IF, y se calcula recién en la sección EX.
  logic stall_load_use;
 
  // Halt (sección 2 del README). Por rango: el PC ya se fue mas allá de lo
  // que la Debug Unit cargó. Por ilegal: control_unit no reconoció la
  // instrucción actual de ID. Importante: no es un freeze de golpe --eso
  // cortaría instrucciones legítimas todavía en tránsito por EX/MEM/WB--
  // sino que a partir de que se dispara, if_id_reg se flushea (como ante
  // un branch mal predicho) para no aceptar más instrucciones nuevas, y
  // "halted" recién se levanta cuando los 4 latches ya drenaron a burbuja.
  logic halt_by_range, halt_by_illegal, halt_trigger;
  logic halt_latched, halt_cause_illegal_latched;
  logic run_enable;  // 1 = se puede avanzar este ciclo (por ahora, solo enable)
 
  assign run_enable  = enable;
  assign halt_trigger = halt_by_range || halt_by_illegal;
 
  always_ff @(posedge clk) begin
    if (rst) begin
      halt_latched               <= 1'b0;
      halt_cause_illegal_latched <= 1'b0;
    end else if (run_enable && !halt_latched && halt_trigger) begin
      halt_latched               <= 1'b1;
      halt_cause_illegal_latched <= halt_by_illegal;
    end
  end
 
  // Ya drenado: ninguno de los 4 latches tiene una instrucción real adentro
  assign halted = halt_latched && !if_id_q.valid && !id_ex_q.valid
                  && !ex_mem_q.valid && !mem_wb_q.valid;
 
  always_comb begin
    if (!halted)                          halt_code = HALT_NONE;
    else if (halt_cause_illegal_latched)  halt_code = HALT_ILLEGAL;
    else                                  halt_code = HALT_RANGE;
  end
 
  // ============================================================ IF
  logic [31:0] pc, pc_next, pc_plus4_if, instr_if;
 
  assign pc_plus4_if  = pc + 32'd4;
  assign pc_next      = redirect ? redirect_pc : pc_plus4_if;
  assign halt_by_range = (pc[IMEM_ADDR_W+1:2] >= program_len);
 
  pc_reg u_pc (.clk(clk), .rst(rst), .stall(stall_load_use || halt_latched || !run_enable), .pc_next(pc_next), .pc(pc));
  imem u_imem (
      .clk(clk), .we(imem_we), .waddr(imem_waddr), .wdata(imem_wdata),
      .addr(pc[IMEM_ADDR_W+1:0]), .instr(instr_if)
  );
 
  if_id_t if_id_d, if_id_q;
  assign if_id_d.valid    = 1'b1;  // IF siempre produce un fetch real este ciclo
  assign if_id_d.pc       = pc;
  assign if_id_d.pc_plus4 = pc_plus4_if;
  assign if_id_d.instr    = instr_if;
 
  // flush por halt: usa halt_trigger (combinacional) para cortar YA en el
  // mismo ciclo en que se detecta -- si usara solo halt_latched (que recién
  // vale 1 el ciclo siguiente) se colaría una instrucción de más antes de
  // que el flush hiciera efecto. halt_latched sostiene el flush después,
  // una vez que if_id_q ya dejó de mostrar la condición que lo disparó.
  pipe_reg #(.T(if_id_t)) u_if_id (
      .clk(clk), .rst(rst), .flush(redirect || halt_trigger || halt_latched), .stall(stall_load_use || !run_enable),
      .d(if_id_d), .q(if_id_q)
  );
 
  // ============================================================ ID
  instr_fields_t fields_id;
  assign fields_id = instr_fields_t'(if_id_q.instr);
 
  ctrl_t ctrl_id;
  logic  illegal_id;
  control_unit u_ctrl (
      .opcode(fields_id.opcode), .funct3(fields_id.funct3), .funct7(fields_id.funct7),
      .ctrl(ctrl_id), .illegal(illegal_id)
  );
 
  assign halt_by_illegal = illegal_id && if_id_q.valid;
 
  logic [31:0] imm_id;
  imm_gen u_imm (.instr(if_id_q.instr), .imm_src(ctrl_id.imm_src), .imm(imm_id));
 
  logic [31:0] rs1_data_id, rs2_data_id, wb_data;
  ctrl_t       ctrl_wb;
  assign ctrl_wb = mem_wb_q.ctrl;
 
  regfile #(.ENABLE_WB_BYPASS(1'b1)) u_regfile (
      .clk(clk), .rst(rst), .enable(run_enable), .we(ctrl_wb.reg_write),
      .rs1_addr(fields_id.rs1), .rs2_addr(fields_id.rs2), .rd_addr(mem_wb_q.rd),
      .rd_data(wb_data), .rs1_data(rs1_data_id), .rs2_data(rs2_data_id),
      .debug_addr(regfile_debug_addr), .debug_data(regfile_debug_data)
  );
 
  id_ex_t id_ex_d, id_ex_q;
  assign id_ex_d.valid    = if_id_q.valid;
  assign id_ex_d.pc       = if_id_q.pc;
  assign id_ex_d.pc_plus4 = if_id_q.pc_plus4;
  assign id_ex_d.rs1_data = rs1_data_id;
  assign id_ex_d.rs2_data = rs2_data_id;
  assign id_ex_d.imm      = imm_id;
  assign id_ex_d.rs1      = fields_id.rs1;
  assign id_ex_d.rs2      = fields_id.rs2;
  assign id_ex_d.rd       = fields_id.rd;
  assign id_ex_d.funct3   = fields_id.funct3;
  assign id_ex_d.ctrl     = ctrl_id;
 
  pipe_reg #(.T(id_ex_t)) u_id_ex (
      .clk(clk), .rst(rst), .flush(redirect || stall_load_use), .stall(!run_enable),
      .d(id_ex_d), .q(id_ex_q)
  );
 
  // ============================================================ EX
  ctrl_t ctrl_ex;
  assign ctrl_ex = id_ex_q.ctrl;
 
  // --- Detección de load-use (afecta IF/ID, se calcula acá porque necesita ctrl_ex) ---
  hazard_detect u_hazard (
      .id_ex_mem_read(ctrl_ex.mem_read), .id_ex_rd(id_ex_q.rd),
      .rs1_id(fields_id.rs1), .rs2_id(fields_id.rs2),
      .stall_load_use(stall_load_use)
  );
 
  // --- Forwarding ---
  fwd_src_e forward_a, forward_b;
  forward_unit u_fwd (
      .rs1_ex(id_ex_q.rs1), .rs2_ex(id_ex_q.rs2),
      .rd_ex_mem(ex_mem_q.rd), .reg_write_ex_mem(ctrl_mem.reg_write),
      .rd_mem_wb(mem_wb_q.rd), .reg_write_mem_wb(ctrl_wb.reg_write),
      .forward_a(forward_a), .forward_b(forward_b)
  );
 
  // Qué forwardear desde EX/MEM: para la mayoría de las instrucciones es
  // alu_result, pero jal/jalr escriben pc_plus4, no el resultado de la ALU.
  // Si la productora en EX/MEM es un load (wb_src==WB_MEM), esto todavía da
  // el valor incorrecto -- la dirección calculada, no el dato leído -- pero
  // ese caso específico (load-use) lo resuelve el stall del próximo paso,
  // no el forwarding.
  logic [31:0] ex_mem_fwd_val;
  assign ex_mem_fwd_val = (ctrl_mem.wb_src == WB_PC4) ? ex_mem_q.pc_plus4 : ex_mem_q.alu_result;
 
  logic [31:0] rs1_fwd, rs2_fwd;
  always_comb begin
    unique case (forward_a)
      FWD_EX_MEM: rs1_fwd = ex_mem_fwd_val;
      FWD_MEM_WB: rs1_fwd = wb_data;
      default:    rs1_fwd = id_ex_q.rs1_data;
    endcase
  end
  always_comb begin
    unique case (forward_b)
      FWD_EX_MEM: rs2_fwd = ex_mem_fwd_val;
      FWD_MEM_WB: rs2_fwd = wb_data;
      default:    rs2_fwd = id_ex_q.rs2_data;
    endcase
  end
 
  logic [31:0] alu_b_ex, alu_result_ex;
  logic        alu_zero_ex;
  assign alu_b_ex = ctrl_ex.alu_src ? id_ex_q.imm : rs2_fwd;
 
  alu u_alu (
      .a(rs1_fwd), .b(alu_b_ex), .op(ctrl_ex.alu_op),
      .result(alu_result_ex), .zero(alu_zero_ex)
  );
 
  // rs1_data acá también tiene que ser el forwardeado: si no, un jalr cuyo
  // rs1 se escribió una o dos instrucciones antes calcularía mal el target.
  branch_resolve u_branch (
      .pc(id_ex_q.pc), .imm(id_ex_q.imm), .rs1_data(rs1_fwd),
      .alu_zero(alu_zero_ex), .funct3(id_ex_q.funct3), .ctrl(id_ex_q.ctrl),
      .redirect(redirect), .redirect_pc(redirect_pc)
  );
 
  assign ex_mem_d.valid      = id_ex_q.valid;
  assign ex_mem_d.alu_result = alu_result_ex;
  assign ex_mem_d.rs2_data   = rs2_fwd;  // dato de store, ya forwardeado
  assign ex_mem_d.rd         = id_ex_q.rd;
  assign ex_mem_d.pc_plus4   = id_ex_q.pc_plus4;
  assign ex_mem_d.ctrl       = id_ex_q.ctrl;
 
  // Nunca se flushea: la instrucción que está en EX cuando se resuelve el
  // branch es la del branch mismo (legítima), no una de las especulativas.
  pipe_reg #(.T(ex_mem_t)) u_ex_mem (
      .clk(clk), .rst(rst), .flush(1'b0), .stall(!run_enable),
      .d(ex_mem_d), .q(ex_mem_q)
  );
 
  // ============================================================ MEM
  logic [31:0] dmem_rdata_mem;
 
  dmem u_dmem (
      .clk(clk), .enable(run_enable), .mem_read(ctrl_mem.mem_read), .mem_write(ctrl_mem.mem_write),
      .mem_size(ctrl_mem.mem_size), .mem_unsigned(ctrl_mem.mem_unsigned),
      .addr(ex_mem_q.alu_result[DMEM_ADDR_W-1:0]), .wdata(ex_mem_q.rs2_data),
      .rdata(dmem_rdata_mem),
      .debug_addr(dmem_debug_addr), .debug_data(dmem_debug_data)
  );
 
  mem_wb_t mem_wb_d;
  assign mem_wb_d.valid      = ex_mem_q.valid;
  assign mem_wb_d.mem_data   = dmem_rdata_mem;
  assign mem_wb_d.alu_result = ex_mem_q.alu_result;
  assign mem_wb_d.pc_plus4   = ex_mem_q.pc_plus4;
  assign mem_wb_d.rd         = ex_mem_q.rd;
  assign mem_wb_d.ctrl       = ex_mem_q.ctrl;
 
  pipe_reg #(.T(mem_wb_t)) u_mem_wb (
      .clk(clk), .rst(rst), .flush(1'b0), .stall(!run_enable),
      .d(mem_wb_d), .q(mem_wb_q)
  );
 
  // ============================================================ WB
  always_comb begin
    unique case (ctrl_wb.wb_src)
      WB_ALU:  wb_data = mem_wb_q.alu_result;
      WB_MEM:  wb_data = mem_wb_q.mem_data;
      WB_PC4:  wb_data = mem_wb_q.pc_plus4;
      default: wb_data = mem_wb_q.alu_result;
    endcase
  end
 
  // Latches crudos hacia la Debug Unit (DUMP_LATCHES)
  assign if_id_q_out  = if_id_q;
  assign id_ex_q_out  = id_ex_q;
  assign ex_mem_q_out = ex_mem_q;
  assign mem_wb_q_out = mem_wb_q;
 
endmodule