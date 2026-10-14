`timescale 1ps/1ps
`include "riscv_defs.vh"
// -----------------------------------------------------------------------------
// dmem.v -- memoria de datos pensada para BRAM (misma forma que la de los
// companeros: 1024 palabras de 32 bits, escritura por byte, lectura sincrona).
//
// PUERTO A (pipeline, etapa MEM):
//   - addr   : direccion de BYTE; solo se usa addr[DMEM_ADDR_W-1:2] (palabra).
//   - we[3:0]: habilitacion de escritura POR BYTE (we[0] = byte menos
//              significativo). 4'b0000 = no escribe. La alineacion del dato
//              y la mascara las arma store_align.v, no esta memoria.
//   - rdata  : palabra completa leida, REGISTRADA: la direccion se presenta
//              en el ciclo N y el dato sale en el ciclo N+1 (etapa WB). Esta
//              salida registrada hace de "latch MEM/WB" para el dato leido.
//              La extension de signo / seleccion de byte la hace
//              load_extract.v en WB.
//   - enable : cuando es 0 el puerto A se congela por completo (no escribe
//              y rdata mantiene su valor). Es el enable global del pipeline.
//
// PUERTO B (Debug Unit, DUMP_MEM) -- solo lectura, siempre habilitado:
//   - debug_addr: direccion de byte. debug_data sale 1 ciclo despues.
//   - Es un puerto independiente (la BRAM es dual-port nativa), asi que
//     leer la memoria desde la Debug Unit NO pisa rdata del puerto A.
//
// Politica de lectura/escritura simultanea en el puerto A: read-first (rdata
// devuelve el valor viejo). En el pipeline nunca coinciden un load y un store
// en la misma etapa MEM, asi que no se nota.
// -----------------------------------------------------------------------------
module dmem #(
    parameter DEPTH_WORDS = (1 << (`DMEM_ADDR_W - 2))   // 1024 palabras = 4 KiB
) (
    input  wire                    clk,
    input  wire                    enable,

    // --- Puerto A: pipeline ---
    input  wire [`DMEM_ADDR_W-1:0] addr,
    input  wire [31:0]             wdata,
    input  wire [3:0]              we,
    output reg  [31:0]             rdata,

    // --- Puerto B: Debug Unit (solo lectura, 1 byte) ---
    input  wire [`DMEM_ADDR_W-1:0] debug_addr,
    output wire [7:0]              debug_data
);

  (* ram_style = "block" *) reg [31:0] mem [0:DEPTH_WORDS-1];

  wire [`DMEM_ADDR_W-3:0] word_addr_a = addr[`DMEM_ADDR_W-1:2];
  wire [`DMEM_ADDR_W-3:0] word_addr_b = debug_addr[`DMEM_ADDR_W-1:2];

  reg [31:0] dbg_word;
  reg [1:0]  dbg_lane;

  // Contenido inicial en cero (simulacion y valor de INIT de la BRAM).
  integer i;
  initial begin
    for (i = 0; i < DEPTH_WORDS; i = i + 1) mem[i] = 32'd0;
    rdata    = 32'd0;
    dbg_word = 32'd0;
    dbg_lane = 2'd0;
  end

  // ---- Puerto A: escritura por byte + lectura sincrona (read-first) ----
  always @(posedge clk) begin
    if (enable) begin
      if (we[0]) mem[word_addr_a][7:0]   <= wdata[7:0];
      if (we[1]) mem[word_addr_a][15:8]  <= wdata[15:8];
      if (we[2]) mem[word_addr_a][23:16] <= wdata[23:16];
      if (we[3]) mem[word_addr_a][31:24] <= wdata[31:24];
      rdata <= mem[word_addr_a];
    end
  end

  // ---- Puerto B: lectura sincrona de la palabra, el byte se elige despues ----
  always @(posedge clk) begin
    dbg_word <= mem[word_addr_b];
    dbg_lane <= debug_addr[1:0];
  end

  assign debug_data = (dbg_lane == 2'd0) ? dbg_word[7:0]
                    : (dbg_lane == 2'd1) ? dbg_word[15:8]
                    : (dbg_lane == 2'd2) ? dbg_word[23:16]
                    :                      dbg_word[31:24];

endmodule