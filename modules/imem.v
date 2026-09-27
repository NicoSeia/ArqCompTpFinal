`timescale 1ps/1ps
`include "riscv_defs.vh"
// Nota Verilog-2001: los puertos de escritura ya no tienen valor por
// defecto (en la version SV we=0, waddr=0, wdata=0). Hay que conectarlos.
module imem #(
    parameter DEPTH_WORDS = (1 << `IMEM_ADDR_W)
) (
    input  wire                     clk,
    input  wire                     we,       // antes default 1'b0
    input  wire [`IMEM_ADDR_W-1:0]  waddr,    // antes default '0
    input  wire [31:0]              wdata,    // antes default '0
    input  wire [`IMEM_ADDR_W+1:0]  addr,     // dirección de byte (viene del PC)
    output wire [31:0]              instr
);

  reg [31:0] mem [0:DEPTH_WORDS-1];

  assign instr = mem[addr[`IMEM_ADDR_W+1:2]];

  always @(posedge clk) begin
    if (we) begin
      mem[waddr] <= wdata;
    end
  end

  // contenido inicial para simulación: NOP (addi x0, x0, 0) en todo el rango
  integer i;
  initial begin
    for (i = 0; i < DEPTH_WORDS; i = i + 1) mem[i] = 32'h00000013;
  end

endmodule
