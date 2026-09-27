`timescale 1ps/1ps
`include "riscv_defs.vh"
module datapath_singlecycle (
    input wire clk,
    input wire rst
);

  // ---- PC ----
  wire [31:0] pc, pc_next, pc_plus4;
  pc_reg u_pc (.clk(clk), .rst(rst), .stall(1'b0), .pc_next(pc_next), .pc(pc));

  // ---- IMEM ----
  // (puerto de escritura sin usar en el monociclo: se ata a 0, que era el default en SV)
  wire [31:0] instr;
  imem u_imem (
      .clk(clk), .we(1'b0), .waddr({`IMEM_ADDR_W{1'b0}}), .wdata(32'd0),
      .addr(pc[`IMEM_ADDR_W+1:0]), .instr(instr)
  );

  // ---- Extracción de campos (posiciones fijas del ISA) ----
  wire [31:0] fields;
  assign fields = instr;

  // ---- Control ----
  // Antes: un unico bus ctrl de `CTRL_W bits. Ahora: 12 wires individuales,
  // uno por campo (misma idea que en pipeline_top.v).
  wire        ctrl_reg_write, ctrl_mem_read, ctrl_mem_write, ctrl_alu_src;
  wire        ctrl_branch, ctrl_jump, ctrl_jalr, ctrl_mem_unsigned;
  wire [1:0]  ctrl_wb_src, ctrl_mem_size;
  wire [3:0]  ctrl_alu_op;
  wire [2:0]  ctrl_imm_src;
  wire        illegal;
  control_unit u_ctrl (
      .opcode(fields[`INSTR_OPCODE]), .funct3(fields[`INSTR_FUNCT3]), .funct7(fields[`INSTR_FUNCT7]),
      .reg_write(ctrl_reg_write), .mem_read(ctrl_mem_read), .mem_write(ctrl_mem_write),
      .wb_src(ctrl_wb_src), .alu_src(ctrl_alu_src),
      .branch(ctrl_branch), .jump(ctrl_jump), .jalr(ctrl_jalr), .mem_unsigned(ctrl_mem_unsigned),
      .alu_op(ctrl_alu_op), .mem_size(ctrl_mem_size), .imm_src(ctrl_imm_src),
      .illegal(illegal)
  );

  // ---- Inmediato ----
  wire [31:0] imm;
  imm_gen u_imm (.instr(instr), .imm_src(ctrl_imm_src), .imm(imm));

  // ---- Banco de registros ----
  wire [31:0] rs1_data, rs2_data;
  reg  [31:0] wb_data;
  wire [31:0] regfile_debug_data_unused;
  regfile u_regfile (
      .clk(clk), .rst(rst), .enable(1'b1), .we(ctrl_reg_write),
      .rs1_addr(fields[`INSTR_RS1]), .rs2_addr(fields[`INSTR_RS2]), .rd_addr(fields[`INSTR_RD]),
      .rd_data(wb_data), .rs1_data(rs1_data), .rs2_data(rs2_data),
      .debug_addr({`REG_ADDR_W{1'b0}}), .debug_data(regfile_debug_data_unused)
  );

  // ---- ALU ----
  wire [31:0] alu_b, alu_result;
  wire        alu_zero;
  assign alu_b = ctrl_alu_src ? imm : rs2_data;
  alu u_alu (.a(rs1_data), .b(alu_b), .op(ctrl_alu_op), .result(alu_result), .zero(alu_zero));

  // ---- Memoria de datos ----
  wire [31:0] dmem_rdata;
  wire [7:0]  dmem_debug_data_unused;
  dmem u_dmem (
      .clk(clk), .enable(1'b1), .mem_read(ctrl_mem_read), .mem_write(ctrl_mem_write),
      .mem_size(ctrl_mem_size), .mem_unsigned(ctrl_mem_unsigned),
      .addr(alu_result[`DMEM_ADDR_W-1:0]), .wdata(rs2_data), .rdata(dmem_rdata),
      .debug_addr({`DMEM_ADDR_W{1'b0}}), .debug_data(dmem_debug_data_unused)
  );

  // ---- Próximo PC ----
  next_pc_logic u_next_pc (
      .pc(pc), .imm(imm), .rs1_data(rs1_data), .alu_zero(alu_zero),
      .funct3(fields[`INSTR_FUNCT3]), .branch(ctrl_branch), .jump(ctrl_jump), .jalr(ctrl_jalr),
      .pc_next(pc_next), .pc_plus4(pc_plus4)
  );

  // ---- Mux de write-back ----
  always @* begin
    case (ctrl_wb_src)
      `WB_ALU: wb_data = alu_result;
      `WB_MEM: wb_data = dmem_rdata;
      `WB_PC4: wb_data = pc_plus4;
      default: wb_data = alu_result;
    endcase
  end

endmodule
