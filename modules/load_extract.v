`timescale 1ps/1ps
`include "riscv_defs.vh"
// -----------------------------------------------------------------------------
// load_extract.v -- etapa WB: a partir de la palabra cruda que entrega la BRAM
// de dmem.v, elige el byte/halfword correcto y extiende signo (o ceros).
//
// SOLO ACCESOS ALINEADOS: un lh/lhu en direccion impar o un lw con
// addr[1:0] != 0 devuelve 0. mem_read = 0 (la instruccion en WB no es un
// load) tambien devuelve 0.
// -----------------------------------------------------------------------------
module load_extract (
    input  wire                   mem_read,
    input  wire [`MEM_SIZE_W-1:0] mem_size,
    input  wire                   mem_unsigned,
    input  wire [1:0]             addr_lo,        // addr[1:0] del load (viaja en alu_result)
    input  wire [31:0]            word,           // palabra cruda de la BRAM
    output reg  [31:0]            rdata
);

  reg [7:0]  b;
  reg [15:0] h;

  always @* begin
    case (addr_lo)
      2'd0:    b = word[7:0];
      2'd1:    b = word[15:8];
      2'd2:    b = word[23:16];
      default: b = word[31:24];
    endcase
    h = addr_lo[1] ? word[31:16] : word[15:0];

    rdata = 32'd0;
    if (mem_read) begin
      case (mem_size)
        `MEM_BYTE: rdata = mem_unsigned ? {24'b0, b} : {{24{b[7]}}, b};
        `MEM_HALF: begin
          if (!addr_lo[0]) rdata = mem_unsigned ? {16'b0, h} : {{16{h[15]}}, h};
        end
        `MEM_WORD: begin
          if (addr_lo == 2'd0) rdata = word;
        end
        default: rdata = 32'd0;
      endcase
    end
  end

endmodule