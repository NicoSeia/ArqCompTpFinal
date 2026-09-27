`timescale 1ps/1ps
// No necesita `include "riscv_defs.vh": ya no lee ningun campo de un bus
// de control empaquetado, solo 3 entradas individuales (branch/jump/jalr).
module next_pc_logic (
    input  wire [31:0] pc,
    input  wire [31:0] imm,
    input  wire [31:0] rs1_data,
    input  wire        alu_zero,
    input  wire [2:0]  funct3,
    input  wire        branch,
    input  wire        jump,
    input  wire        jalr,
    output reg  [31:0] pc_next,
    output wire [31:0] pc_plus4
);

  wire [31:0] pc_target;
  wire        branch_taken;

  assign pc_plus4     = pc + 32'd4;
  assign pc_target    = pc + imm;
  assign branch_taken = branch && (alu_zero ^ funct3[0]);

  always @* begin
    if (jump) begin
      if (jalr) begin
        pc_next = (rs1_data + imm) & ~32'd1;  // jalr: target = rs1+imm, bit0 limpio
      end else begin
        pc_next = pc_target;                   // jal: target = pc+imm
      end
    end else if (branch_taken) begin
      pc_next = pc_target;
    end else begin
      pc_next = pc_plus4;
    end
  end

endmodule
