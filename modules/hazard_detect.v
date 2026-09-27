`timescale 1ps/1ps
`include "riscv_defs.vh"
module hazard_detect (
    input  wire                   id_ex_mem_read,  // ctrl.mem_read de la instrucción en EX
    input  wire [`REG_ADDR_W-1:0] id_ex_rd,        // su rd
    input  wire [`REG_ADDR_W-1:0] rs1_id,          // rs1/rs2 que necesita la instrucción en ID
    input  wire [`REG_ADDR_W-1:0] rs2_id,
    output wire                   stall_load_use
);

  assign stall_load_use = id_ex_mem_read && (id_ex_rd != {`REG_ADDR_W{1'b0}}) &&
                          ((id_ex_rd == rs1_id) || (id_ex_rd == rs2_id));

endmodule
