`timescale 1ps/1ps
module alu
  import riscv_pkg::*;
(
    input  logic [XLEN-1:0] a,
    input  logic [XLEN-1:0] b,
    input  alu_op_e         op,
    output logic [XLEN-1:0] result,
    output logic            zero    // result == 0 -> lo va a usar next_pc_logic para beq/bne
);

  always_comb begin
    unique case (op)
      ALU_ADD:  result = a + b;
      ALU_SUB:  result = a - b;
      ALU_SLL:  result = a << b[4:0];
      ALU_SLT:  result = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
      ALU_SLTU: result = (a < b) ? 32'd1 : 32'd0;
      ALU_XOR:  result = a ^ b;
      ALU_SRL:  result = a >> b[4:0];
      ALU_SRA:  result = $signed(a) >>> b[4:0];
      ALU_OR:   result = a | b;
      ALU_AND:  result = a & b;
      ALU_PASS: result = b;
      default:  result = '0;
    endcase
  end

  assign zero = (result == '0);

endmodule