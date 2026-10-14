`timescale 1ps/1ps
`include "riscv_defs.vh"
// -----------------------------------------------------------------------------
// store_align.v -- prepara un store para la BRAM de dmem.v (etapa MEM).
//
// A partir de mem_size y addr[1:0] genera la mascara de bytes (byte_en) y
// replica el dato en todos los carriles para que el byte/halfword quede en
// la posicion correcta de la palabra de 32 bits.
//
// SOLO ACCESOS ALINEADOS:
//   sb : cualquier direccion
//   sh : addr[0] == 0
//   sw : addr[1:0] == 0
// Un store desalineado NO escribe nada (byte_en = 0000). mem_write = 0
// tambien da byte_en = 0000.
// -----------------------------------------------------------------------------
module store_align (
    input  wire                   mem_write,
    input  wire [`MEM_SIZE_W-1:0] mem_size,
    input  wire [1:0]             addr_lo,        // addr[1:0] del store
    input  wire [31:0]            wdata,
    output reg  [3:0]             byte_en,
    output reg  [31:0]            wdata_aligned
);

  always @* begin
    byte_en       = 4'b0000;
    wdata_aligned = wdata;

    if (mem_write) begin
      case (mem_size)
        `MEM_BYTE: begin
          wdata_aligned = {4{wdata[7:0]}};
          case (addr_lo)
            2'd0: byte_en = 4'b0001;
            2'd1: byte_en = 4'b0010;
            2'd2: byte_en = 4'b0100;
            2'd3: byte_en = 4'b1000;
          endcase
        end
        `MEM_HALF: begin
          wdata_aligned = {2{wdata[15:0]}};
          case (addr_lo)
            2'd0:    byte_en = 4'b0011;
            2'd2:    byte_en = 4'b1100;
            default: byte_en = 4'b0000;   // halfword desalineado: se ignora
          endcase
        end
        `MEM_WORD: begin
          wdata_aligned = wdata;
          byte_en = (addr_lo == 2'd0) ? 4'b1111 : 4'b0000;  // desalineado: se ignora
        end
        default: byte_en = 4'b0000;
      endcase
    end
  end

endmodule