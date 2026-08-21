`timescale 1ps/1ps
module forward_unit
  import riscv_pkg::*;
(
    input  logic [REG_ADDR_W-1:0] rs1_ex,          // registro que necesita la instrucción en EX
    input  logic [REG_ADDR_W-1:0] rs2_ex,
    input  logic [REG_ADDR_W-1:0] rd_ex_mem,       // rd de la instrucción en EX/MEM (gap=1)
    input  logic                  reg_write_ex_mem,
    input  logic [REG_ADDR_W-1:0] rd_mem_wb,       // rd de la instrucción en MEM/WB (gap=2)
    input  logic                  reg_write_mem_wb,
    output fwd_src_e              forward_a,        // fuente para rs1
    output fwd_src_e              forward_b         // fuente para rs2
);

  always_comb begin
    // rs1 / forward_a — EX/MEM tiene prioridad por ser la escritura más reciente
    if (reg_write_ex_mem && (rd_ex_mem != '0) && (rd_ex_mem == rs1_ex)) begin
      forward_a = FWD_EX_MEM;
    end else if (reg_write_mem_wb && (rd_mem_wb != '0) && (rd_mem_wb == rs1_ex)) begin
      forward_a = FWD_MEM_WB;
    end else begin
      forward_a = FWD_NONE;
    end

    // rs2 / forward_b — misma lógica, independiente de rs1
    if (reg_write_ex_mem && (rd_ex_mem != '0) && (rd_ex_mem == rs2_ex)) begin
      forward_b = FWD_EX_MEM;
    end else if (reg_write_mem_wb && (rd_mem_wb != '0) && (rd_mem_wb == rs2_ex)) begin
      forward_b = FWD_MEM_WB;
    end else begin
      forward_b = FWD_NONE;
    end
  end

endmodule