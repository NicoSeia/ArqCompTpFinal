`timescale 1ps/1ps
module branch_resolve
  import riscv_pkg::*;
(
    input  logic [31:0] pc,         // pc de la instrucción que está en EX
    input  logic [31:0] imm,
    input  logic [31:0] rs1_data,
    input  logic        alu_zero,
    input  logic [2:0]  funct3,
    input  ctrl_t        ctrl,
    output logic         redirect,     // 1: hay que corregir el PC y flushear
    output logic [31:0] redirect_pc
);

  logic branch_taken;

  // beq (funct3=000): toma el salto si son iguales (alu_zero=1)
  // bne (funct3=001): toma el salto si son distintos (alu_zero=0)
  assign branch_taken = ctrl.branch && (alu_zero ^ funct3[0]);
  assign redirect      = ctrl.jump || branch_taken;

  always_comb begin
    if (ctrl.jump && ctrl.jalr) begin
      redirect_pc = (rs1_data + imm) & ~32'd1;  // jalr: rs1+imm, bit0 limpio
    end else begin
      redirect_pc = pc + imm;                    // jal, o branch tomado: pc+imm
    end
  end

endmodule