`timescale 1ps/1ps
module regfile
import riscv_pkg::*;
#(
  parameter bit ENABLE_WB_BYPASS = 1'b0
)(
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

  if (ENABLE_WB_BYPASS) begin : g_bypass
    assign rs1_data = (rs1_addr == '0) ? '0
                     : (we && (rd_addr == rs1_addr)) ? rd_data
                     : regs[rs1_addr];
    assign rs2_data = (rs2_addr == '0) ? '0
                     : (we && (rd_addr == rs2_addr)) ? rd_data
                     : regs[rs2_addr];
  end else begin : g_no_bypass
    assign rs1_data = (rs1_addr == '0) ? '0 : regs[rs1_addr];
    assign rs2_data = (rs2_addr == '0) ? '0 : regs[rs2_addr];
  end

endmodule