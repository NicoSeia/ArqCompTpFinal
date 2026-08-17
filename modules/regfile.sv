`timescale 1ps/1ps
module regfile
import riscv_pkg::*;
(
    input  logic                  clk,
    input  logic                  rst,
    input  logic                  we,
    input  logic [REG_ADDR_W-1:0] rs1_addr,
    input  logic [REG_ADDR_W-1:0] rs2_addr,
    input  logic [REG_ADDR_W-1:0] rd_addr,
    input  logic [XLEN-1:0]       rd_data,
    output logic [XLEN-1:0]       rs1_data,
    output logic [XLEN-1:0]       rs2_data
);

  logic [XLEN-1:0] regs [1:31];  // x0 no se almacena, se resuelve por MUX

  always_ff @(posedge clk) begin
    if (rst) begin
      for (int i = 1; i < 32; i++) regs[i] <= '0;
    end else if (we && (rd_addr != '0)) begin
      regs[rd_addr] <= rd_data;
    end
  end

  assign rs1_data = (rs1_addr == '0) ? '0 : regs[rs1_addr];
  assign rs2_data = (rs2_addr == '0) ? '0 : regs[rs2_addr];

endmodule