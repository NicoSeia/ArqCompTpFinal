`timescale 1ps/1ps
`include "riscv_defs.vh"
module alu (
    input  wire [`XLEN-1:0]     a,
    input  wire [`XLEN-1:0]     b,
    input  wire [`ALU_OP_W-1:0] op,
    output reg  [`XLEN-1:0]     result,
    output wire                 zero    // result == 0 -> lo va a usar next_pc_logic para beq/bne
);

  always @* begin
    case (op)
      `ALU_ADD:  result = a + b;
      `ALU_SUB:  result = a - b;
      `ALU_SLL:  result = a << b[4:0];
      `ALU_SLT:  result = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
      `ALU_SLTU: result = (a < b) ? 32'd1 : 32'd0;
      `ALU_XOR:  result = a ^ b;
      `ALU_SRL:  result = a >> b[4:0];
      `ALU_SRA:  result = $signed(a) >>> b[4:0];
      `ALU_OR:   result = a | b;
      `ALU_AND:  result = a & b;
      `ALU_PASS: result = b;
      default:   result = {`XLEN{1'b0}};
    endcase
  end

  assign zero = (result == {`XLEN{1'b0}});

endmodule
