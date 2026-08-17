`timescale 1ps/1ps
module next_pc_logic
  import riscv_pkg::*;
(
    input  logic [31:0] pc,
    input  logic [31:0] imm,
    input  logic [31:0] rs1_data,
    input  logic        alu_zero,
    input  logic [2:0]  funct3,
    input  ctrl_t        ctrl,
    output logic [31:0] pc_next,
    output logic [31:0] pc_plus4
);

  logic [31:0] pc_target;
  logic        branch_taken;

  assign pc_plus4    = pc + 32'd4;
  assign pc_target   = pc + imm;
  assign branch_taken = ctrl.branch && (alu_zero ^ funct3[0]);

  always_comb begin
    if (ctrl.jump) begin
      if (ctrl.jalr)
        pc_next = (rs1_data + imm) & ~32'd1;  // jalr: target = rs1+imm, bit0 limpio
      else
        pc_next = pc_target;                   // jal: target = pc+imm
    end else if (branch_taken) begin
      pc_next = pc_target;
    end else begin
      pc_next = pc_plus4;
    end
  end

endmodule