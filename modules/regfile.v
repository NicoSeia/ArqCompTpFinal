`timescale 1ps/1ps
`include "riscv_defs.vh"
// Nota Verilog-2001: enable y debug_addr ya no tienen valor por defecto
// (antes 1'b1 y '0). Hay que conectarlos siempre.
module regfile #(
  parameter ENABLE_WB_BYPASS = 1'b0
)(
    input  wire                   clk,
    input  wire                   rst,
    input  wire                   enable,      // antes default 1'b1
    input  wire                   we,
    input  wire [`REG_ADDR_W-1:0] rs1_addr,
    input  wire [`REG_ADDR_W-1:0] rs2_addr,
    input  wire [`REG_ADDR_W-1:0] rd_addr,
    input  wire [`XLEN-1:0]       rd_data,
    input  wire [`REG_ADDR_W-1:0] debug_addr,  // antes default '0
    output wire [`XLEN-1:0]       rs1_data,
    output wire [`XLEN-1:0]       rs2_data,
    output wire [`XLEN-1:0]       debug_data
);

  reg [`XLEN-1:0] regs [1:31];  // x0 no se almacena, se resuelve por MUX

  // Escritura efectiva: solo cuenta si realmente hay we Y el sistema esta
  // habilitado. Tanto el flip-flop como el bypass usan esta misma señal,
  // para que los dos vean exactamente la misma realidad.
  wire we_eff;
  assign we_eff = we && enable;

  integer i;
  always @(posedge clk) begin
    if (rst) begin
      for (i = 1; i < 32; i = i + 1) regs[i] <= {`XLEN{1'b0}};
    end else if (we && (rd_addr != {`REG_ADDR_W{1'b0}})) begin
      regs[rd_addr] <= rd_data;
    end
  end

  generate
    if (ENABLE_WB_BYPASS) begin : g_bypass
      assign rs1_data = (rs1_addr == {`REG_ADDR_W{1'b0}}) ? {`XLEN{1'b0}}
                       : (we && (rd_addr == rs1_addr)) ? rd_data
                       : regs[rs1_addr];
      assign rs2_data = (rs2_addr == {`REG_ADDR_W{1'b0}}) ? {`XLEN{1'b0}}
                       : (we && (rd_addr == rs2_addr)) ? rd_data
                       : regs[rs2_addr];
    end else begin : g_no_bypass
      assign rs1_data = (rs1_addr == {`REG_ADDR_W{1'b0}}) ? {`XLEN{1'b0}} : regs[rs1_addr];
      assign rs2_data = (rs2_addr == {`REG_ADDR_W{1'b0}}) ? {`XLEN{1'b0}} : regs[rs2_addr];
    end
  endgenerate

  assign debug_data = (debug_addr == {`REG_ADDR_W{1'b0}}) ? {`XLEN{1'b0}} : regs[debug_addr];

endmodule
