`timescale 1ps/1ps
module hazard_detect
  import riscv_pkg::*;
(
    input  logic                  id_ex_mem_read,  // ctrl.mem_read de la instrucción en EX
    input  logic [REG_ADDR_W-1:0] id_ex_rd,        // su rd
    input  logic [REG_ADDR_W-1:0] rs1_id,          // rs1/rs2 que necesita la instrucción en ID
    input  logic [REG_ADDR_W-1:0] rs2_id,
    output logic                  stall_load_use
);

assign stall_load_use = id_ex_mem_read && (id_ex_rd != '0) &&
                           ((id_ex_rd == rs1_id) || (id_ex_rd == rs2_id));

endmodule
