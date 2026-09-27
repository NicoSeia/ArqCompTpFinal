`timescale 1ps/1ps
`include "riscv_defs.vh"
// Nota Verilog-2001: los puertos ya no tienen valor por defecto (en la
// version SV enable=1 y debug_addr=0). Hay que conectarlos siempre.
module dmem #(
    parameter DEPTH_BYTES = (1 << `DMEM_ADDR_W)
) (
    input  wire                    clk,
    input  wire                    enable,        // antes default 1'b1
    input  wire                    mem_read,
    input  wire                    mem_write,
    input  wire [`MEM_SIZE_W-1:0]  mem_size,
    input  wire                    mem_unsigned,
    input  wire [`DMEM_ADDR_W-1:0] addr,          // dirección de byte
    input  wire [`XLEN-1:0]        wdata,
    input  wire [`DMEM_ADDR_W-1:0] debug_addr,    // antes default '0
    output reg  [`XLEN-1:0]        rdata,
    output wire [7:0]              debug_data
);

  reg [7:0] mem [0:DEPTH_BYTES-1];

  // --- Lectura combinacional ---
  always @* begin
    if (!mem_read) begin
      rdata = {`XLEN{1'b0}};
    end else begin
      case (mem_size)
        `MEM_BYTE: rdata = mem_unsigned ? {24'b0, mem[addr]}
                                         : {{24{mem[addr][7]}}, mem[addr]};
        `MEM_HALF: rdata = mem_unsigned ? {16'b0, mem[addr+1], mem[addr]}
                                         : {{16{mem[addr+1][7]}}, mem[addr+1], mem[addr]};
        `MEM_WORD: rdata = {mem[addr+3], mem[addr+2], mem[addr+1], mem[addr]};
        default:   rdata = {`XLEN{1'b0}};
      endcase
    end
  end

  // --- Escritura síncrona ---
  always @(posedge clk) begin
    if (mem_write && enable) begin
      case (mem_size)
        `MEM_BYTE: mem[addr] <= wdata[7:0];
        `MEM_HALF: begin
          mem[addr]   <= wdata[7:0];
          mem[addr+1] <= wdata[15:8];
        end
        `MEM_WORD: begin
          mem[addr]   <= wdata[7:0];
          mem[addr+1] <= wdata[15:8];
          mem[addr+2] <= wdata[23:16];
          mem[addr+3] <= wdata[31:24];
        end
        default: ; // no hace nada
      endcase
    end
  end

  assign debug_data = mem[debug_addr];

endmodule
