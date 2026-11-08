`timescale 1ps/1ps
`include "riscv_defs.vh"
// -----------------------------------------------------------------------------
// hazard_detect.v
// Frena (stall) la instruccion que esta en ID cuando depende de un load que
// todavia no completo su WB.
//
// Antes (version con forwarding de loads desde WB): bastaba frenar 1 ciclo
// si el load estaba en EX; el dato del load se reenviaba desde MEM/WB (la
// salida de la BRAM) directo a la ALU / al comparador de branch.
//
// Ahora: el dato de un load NO se reenvia al EX. Llega a la instruccion
// dependiente por el bypass de escritura del banco de registros, cuando el
// load esta en WB y la dependiente en ID. Por eso hay que frenar mientras
// el load esta en EX (distancia 1) O en MEM (distancia 1 y 2):
//
//   load en EX  + dependiente en ID -> stall   (1er ciclo de espera)
//   load en MEM + dependiente en ID -> stall   (2do ciclo, o el unico si dist. 2)
//   load en WB  + dependiente en ID -> sin stall (bypass del regfile)
//
// Costo: load-use consecutivo = 2 ciclos de burbuja (antes 1); dependiente a
// distancia 2 = 1 ciclo (antes 0). Beneficio: la salida de la BRAM
// (clk-to-out ~2 ns) + load_extract dejan de estar en el camino hacia el
// PC (branch) y la ALU.
// -----------------------------------------------------------------------------
module hazard_detect (
    input  wire                   id_ex_mem_read,  // mem_read de la instruccion en EX
    input  wire [`REG_ADDR_W-1:0] id_ex_rd,        // su rd
    input  wire                   ex_mem_mem_read, // mem_read de la instruccion en MEM
    input  wire [`REG_ADDR_W-1:0] ex_mem_rd,       // su rd
    input  wire [`REG_ADDR_W-1:0] rs1_id,          // rs1/rs2 que necesita la instruccion en ID
    input  wire [`REG_ADDR_W-1:0] rs2_id,
    output wire                   stall_load_use
);

  wire hazard_ex, hazard_mem;

  assign hazard_ex  = id_ex_mem_read && (id_ex_rd != {`REG_ADDR_W{1'b0}}) &&
                      ((id_ex_rd == rs1_id) || (id_ex_rd == rs2_id));

  assign hazard_mem = ex_mem_mem_read && (ex_mem_rd != {`REG_ADDR_W{1'b0}}) &&
                      ((ex_mem_rd == rs1_id) || (ex_mem_rd == rs2_id));

  assign stall_load_use = hazard_ex || hazard_mem;

endmodule