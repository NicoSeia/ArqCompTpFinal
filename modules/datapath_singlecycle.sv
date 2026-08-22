`timescale 1ps/1ps
module datapath_singlecycle
  import riscv_pkg::*;
(
    input logic clk,
    input logic rst
);

// ---- PC ----
  logic [31:0] pc, pc_next, pc_plus4;
  pc_reg u_pc (.clk(clk), .rst(rst), .pc_next(pc_next), .pc(pc));
 
  // ---- IMEM ----
  logic [31:0] instr;
  imem u_imem (.clk(clk), .addr(pc[IMEM_ADDR_W+1:0]), .instr(instr));
 
  // ---- Extracción de campos (posiciones fijas del ISA) ----
  instr_fields_t fields;
  assign fields = instr_fields_t'(instr);
 
  // ---- Control ----
  ctrl_t ctrl;
  logic  illegal;
  control_unit u_ctrl (
      .opcode(fields.opcode), .funct3(fields.funct3), .funct7(fields.funct7),
      .ctrl(ctrl), .illegal(illegal)
  );
 
  // ---- Inmediato ----
  logic [31:0] imm;
  imm_gen u_imm (.instr(instr), .imm_src(ctrl.imm_src), .imm(imm));
 
  // ---- Banco de registros ----
  logic [31:0] rs1_data, rs2_data, wb_data;
  regfile u_regfile (
      .clk(clk), .rst(rst), .we(ctrl.reg_write),
      .rs1_addr(fields.rs1), .rs2_addr(fields.rs2), .rd_addr(fields.rd),
      .rd_data(wb_data), .rs1_data(rs1_data), .rs2_data(rs2_data)
  );
 
  // ---- ALU ----
  logic [31:0] alu_b, alu_result;
  logic        alu_zero;
  assign alu_b = ctrl.alu_src ? imm : rs2_data;
  alu u_alu (.a(rs1_data), .b(alu_b), .op(ctrl.alu_op), .result(alu_result), .zero(alu_zero));
 
  // ---- Memoria de datos ----
  logic [31:0] dmem_rdata;
  dmem u_dmem (
      .clk(clk), .mem_read(ctrl.mem_read), .mem_write(ctrl.mem_write),
      .mem_size(ctrl.mem_size), .mem_unsigned(ctrl.mem_unsigned),
      .addr(alu_result[DMEM_ADDR_W-1:0]), .wdata(rs2_data), .rdata(dmem_rdata)
  );
 
  // ---- Próximo PC ----
  next_pc_logic u_next_pc (
      .pc(pc), .imm(imm), .rs1_data(rs1_data), .alu_zero(alu_zero),
      .funct3(fields.funct3), .ctrl(ctrl), .pc_next(pc_next), .pc_plus4(pc_plus4)
  );
 
  // ---- Mux de write-back ----
  always_comb begin
    unique case (ctrl.wb_src)
      WB_ALU:  wb_data = alu_result;
      WB_MEM:  wb_data = dmem_rdata;
      WB_PC4:  wb_data = pc_plus4;
      default: wb_data = alu_result;
    endcase
  end

endmodule