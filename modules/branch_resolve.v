`timescale 1ps/1ps
// No necesita `include "riscv_defs.vh": ya no lee ningun campo de un bus
// de control empaquetado, solo 3 entradas individuales (branch/jump/jalr).
module branch_resolve (
    input  wire [31:0] pc,         // pc de la instrucción que está en EX
    input  wire [31:0] imm,
    input  wire [31:0] rs1_data,
    input  wire        alu_zero,
    input  wire [2:0]  funct3,
    input  wire        branch,
    input  wire        jump,
    input  wire        jalr,
    output wire         redirect,     // 1: hay que corregir el PC y flushear
    output reg  [31:0] redirect_pc
);

  wire branch_taken;

  // beq (funct3=000): toma el salto si son iguales (alu_zero=1)
  // bne (funct3=001): toma el salto si son distintos (alu_zero=0)
  assign branch_taken = branch && (alu_zero ^ funct3[0]);
  assign redirect     = jump || branch_taken;

  always @* begin
    if (jump && jalr) begin
      redirect_pc = (rs1_data + imm) & ~32'd1;  // jalr: rs1+imm, bit0 limpio
    end else begin
      redirect_pc = pc + imm;                    // jal, o branch tomado: pc+imm
    end
  end

endmodule
