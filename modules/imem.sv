`timescale 1ps/1ps
module imem
  import riscv_pkg::*;
#(
    parameter int DEPTH_WORDS = (1 << IMEM_ADDR_W)
) (
    input  logic [IMEM_ADDR_W+1:0] addr,   // dirección de byte (viene del PC)
    output logic [31:0]            instr
);

  logic [31:0] mem[0:DEPTH_WORDS-1];

  assign instr = mem[addr[IMEM_ADDR_W+1:2]];

  // contenido inicial para simulación: NOP (addi x0, x0, 0) en todo el rango
  initial begin
    for (int i = 0; i < DEPTH_WORDS; i++) mem[i] = 32'h00000013;
  end

endmodule