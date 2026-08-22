`timescale 1ps/1ps
module dmem
  import riscv_pkg::*;
#(
    parameter int DEPTH_BYTES = (1 << DMEM_ADDR_W)
) (
    input  logic                   clk,
    input  logic                   enable = 1'b1,
    input  logic                   mem_read,
    input  logic                   mem_write,
    input  mem_size_e              mem_size,
    input  logic                   mem_unsigned,
    input  logic [DMEM_ADDR_W-1:0] addr,   // dirección de byte
    input  logic [XLEN-1:0]        wdata,
    input  logic [DMEM_ADDR_W-1:0] debug_addr = '0,
    output logic [XLEN-1:0]        rdata,
    output logic [7:0]             debug_data
);

  logic [7:0] mem[0:DEPTH_BYTES-1];

  // --- Lectura combinacional ---
  always_comb begin
    if (!mem_read) begin
      rdata = '0;
    end else begin
      unique case (mem_size)
        MEM_BYTE: rdata = mem_unsigned ? {24'b0, mem[addr]}
                                        : {{24{mem[addr][7]}}, mem[addr]};
        MEM_HALF: rdata = mem_unsigned ? {16'b0, mem[addr+1], mem[addr]}
                                        : {{16{mem[addr+1][7]}}, mem[addr+1], mem[addr]};
        MEM_WORD: rdata = {mem[addr+3], mem[addr+2], mem[addr+1], mem[addr]};
        default:  rdata = '0;
      endcase
    end
  end

  // --- Escritura síncrona ---
  always_ff @(posedge clk) begin
    if (mem_write && enable) begin
      unique case (mem_size)
        MEM_BYTE: mem[addr] <= wdata[7:0];
        MEM_HALF: begin
          mem[addr]   <= wdata[7:0];
          mem[addr+1] <= wdata[15:8];
        end
        MEM_WORD: begin
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