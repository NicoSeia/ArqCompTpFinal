`timescale 1ps/1ps
`include "riscv_defs.vh"
module imm_gen (
    input  wire [31:0]            instr,
    input  wire [`IMM_SRC_W-1:0]  imm_src,
    output reg  [31:0]            imm
);

  always @* begin
    case (imm_src)
      `IMM_I:  imm = {{20{instr[31]}}, instr[31:20]};
      `IMM_S:  imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
      `IMM_B:  imm = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
      `IMM_U:  imm = {instr[31:12], 12'b0};
      `IMM_J:  imm = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
      default: imm = 32'd0;  // IMM_X: R-type no usa inmediato
    endcase
  end

endmodule
