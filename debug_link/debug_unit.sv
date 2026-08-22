`timescale 1ns / 1ps
module debug_unit
  import riscv_pkg::*;
(
    input  logic       clk,
    input  logic       reset,           // reset externo de la propia Debug Unit (power-on)
 
    // --- rx_fifo (mismos nombres que interface.v del TP2) ---
    input  logic       rx_empty,
    input  logic [7:0] rx_data,
    output logic       rx_rd,
 
    // --- uart_tx (mismos nombres que interface.v del TP2) ---
    input  logic       tx_done_tick,
    output logic       tx_start,
    output logic [7:0] tx_data,
 
    // --- Hacia pipeline_top.sv ---
    output logic pipeline_rst,
    output logic pipeline_enable,
 
    // --- Desde pipeline_top.sv: resultado de RUN/STEP ---
    input  logic       halted,
    input  halt_code_e halt_code,
 
    // --- Puerto de escritura de imem.sv ---
    output logic                    imem_we,
    output logic [IMEM_ADDR_W-1:0]  imem_waddr,
    output logic [31:0]             imem_wdata,
 
    // --- Hacia el halt por rango de pipeline_top.sv: cuantas palabras se
    //     cargaron hasta ahora. Es literalmente load_addr_reg expuesto tal
    //     cual, no hace falta un contador aparte. ---
    output logic [IMEM_ADDR_W-1:0]  program_len,
 
    // --- Puerto de debug de regfile.sv (DUMP_REGS) ---
    output logic [REG_ADDR_W-1:0] regfile_debug_addr,
    input  logic [XLEN-1:0]       regfile_debug_data,
 
    // --- Puerto de debug de dmem.sv (DUMP_MEM) ---
    output logic [DMEM_ADDR_W-1:0] dmem_debug_addr,
    input  logic [7:0]             dmem_debug_data,
 
    // --- Latches crudos de pipeline_top.sv (DUMP_LATCHES) ---
    input if_id_t  if_id_q_in,
    input id_ex_t  id_ex_q_in,
    input ex_mem_t ex_mem_q_in,
    input mem_wb_t mem_wb_q_in
);
 
  // Ancho de cada latch en bytes, calculado en vez de hardcodeado
  localparam int IF_ID_BYTES    = ($bits(if_id_t)  + 7) / 8;
  localparam int ID_EX_BYTES    = ($bits(id_ex_t)  + 7) / 8;
  localparam int EX_MEM_BYTES   = ($bits(ex_mem_t) + 7) / 8;
  localparam int MEM_WB_BYTES   = ($bits(mem_wb_t) + 7) / 8;
  localparam int MAX_LATCH_BITS = ID_EX_BYTES * 8;  // el más ancho de los 4, ya redondeado a bytes
 
  // Opcodes del protocolo (sección 4 del README)
  localparam logic [7:0] OP_RESET        = 8'h00;
  localparam logic [7:0] OP_LOAD_WORD    = 8'h01;
  localparam logic [7:0] OP_RUN          = 8'h02;
  localparam logic [7:0] OP_STEP         = 8'h03;
  localparam logic [7:0] OP_DUMP_REGS    = 8'h04;
  localparam logic [7:0] OP_DUMP_LATCHES = 8'h05;
  localparam logic [7:0] OP_DUMP_MEM     = 8'h06;
  localparam logic [7:0] OP_CLEAR_MEM    = 8'h07;
 
  typedef enum logic [4:0] {
    ST_IDLE,         // esperando el byte de opcode
    ST_DECODE,       // opcode ya en rx_data, decide a donde ir
    ST_RESET_CLEAR,  // barre imem escribiendo NOP, palabra por palabra
    ST_LOAD_B0,      // juntando los 4 bytes de LOAD_WORD, little-endian
    ST_LOAD_B1,
    ST_LOAD_B2,
    ST_LOAD_B3,
    ST_LOAD_COMMIT,  // ya están los 4 bytes, escribe la palabra en imem
    ST_RUN,          // pipeline_enable en 1 hasta que pipeline_top avise halted
    ST_STEP_PULSE,   // pipeline_enable en 1 exactamente un ciclo
    ST_TX_START,     // arma tx_data y pulsa tx_start un ciclo
    ST_TX_WAIT,      // espera tx_done_tick antes de volver a ST_IDLE
    ST_DUMPREGS_TX,  // arma el byte actual de DUMP_REGS y pulsa tx_start
    ST_DUMPREGS_WAIT,// espera tx_done_tick, decide si sigue con el proximo byte/registro
    ST_DUMPMEM_ADDR_B0,  // juntando los 2 bytes de direccion de DUMP_MEM
    ST_DUMPMEM_ADDR_B1,
    ST_DUMPMEM_LEN_B0,   // juntando los 2 bytes de cantidad de DUMP_MEM
    ST_DUMPMEM_LEN_B1,
    ST_DUMPMEM_TX,       // chequea si queda algo por mandar y arma el byte actual
    ST_DUMPMEM_WAIT,     // espera tx_done_tick, avanza direccion y decrementa cantidad
    ST_DUMPLATCHES_TX,   // arma el byte actual (byte bajo del shift register) y pulsa tx_start
    ST_DUMPLATCHES_WAIT  // espera tx_done_tick, desplaza el shift register o pasa al proximo latch
  } state_e;
 
  state_e state_reg, state_next;
 
  logic [31:0]            load_word_reg, load_word_next;    // arma la instrucción byte a byte
  logic [IMEM_ADDR_W-1:0] load_addr_reg, load_addr_next;    // contador de carga (LOAD_WORD)
  logic [IMEM_ADDR_W-1:0] clear_addr_reg, clear_addr_next;  // contador del barrido de RESET
 
  logic [REG_ADDR_W-1:0] dump_reg_idx_reg, dump_reg_idx_next;    // que registro (0..31)
  logic [1:0]            dump_byte_sel_reg, dump_byte_sel_next;  // que byte del word actual (0..3)
 
  logic [15:0] dump_mem_addr_reg, dump_mem_addr_next;  // direccion actual de DUMP_MEM
  logic [15:0] dump_mem_len_reg, dump_mem_len_next;    // cuantos bytes faltan mandar
 
  logic [MAX_LATCH_BITS-1:0] latch_shift_reg, latch_shift_next;  // bytes que faltan del latch actual, byte bajo primero
  logic [4:0]                latch_remaining_reg, latch_remaining_next;  // cuantos bytes faltan del latch actual
  logic [1:0]                latch_idx_reg, latch_idx_next;  // 0=if_id, 1=id_ex, 2=ex_mem, 3=mem_wb
 
  // Cada struct aplanado a su ancho exacto -- separado del shift register
  // (que siempre tiene el ancho maximo) para poder zero-extender cada uno
  // a su turno sin ambiguedad de conversion de tipos.
  logic [$bits(if_id_t)-1:0]  if_id_flat;
  logic [$bits(id_ex_t)-1:0]  id_ex_flat;
  logic [$bits(ex_mem_t)-1:0] ex_mem_flat;
  logic [$bits(mem_wb_t)-1:0] mem_wb_flat;
  assign if_id_flat  = if_id_q_in;
  assign id_ex_flat  = id_ex_q_in;
  assign ex_mem_flat = ex_mem_q_in;
  assign mem_wb_flat = mem_wb_q_in;
 
  always_ff @(posedge clk) begin
    if (reset) begin
      state_reg            <= ST_IDLE;
      load_word_reg        <= '0;
      load_addr_reg        <= '0;
      clear_addr_reg       <= '0;
      dump_reg_idx_reg     <= '0;
      dump_byte_sel_reg    <= '0;
      dump_mem_addr_reg    <= '0;
      dump_mem_len_reg     <= '0;
      latch_shift_reg      <= '0;
      latch_remaining_reg  <= '0;
      latch_idx_reg        <= '0;
    end else begin
      state_reg            <= state_next;
      load_word_reg        <= load_word_next;
      load_addr_reg        <= load_addr_next;
      clear_addr_reg       <= clear_addr_next;
      dump_reg_idx_reg     <= dump_reg_idx_next;
      dump_byte_sel_reg    <= dump_byte_sel_next;
      dump_mem_addr_reg    <= dump_mem_addr_next;
      dump_mem_len_reg     <= dump_mem_len_next;
      latch_shift_reg      <= latch_shift_next;
      latch_remaining_reg  <= latch_remaining_next;
      latch_idx_reg        <= latch_idx_next;
    end
  end
 
  always_comb begin
    // Valores por defecto: no hacer nada, mantener estado
    state_next         = state_reg;
    load_word_next      = load_word_reg;
    load_addr_next       = load_addr_reg;
    clear_addr_next      = clear_addr_reg;
    dump_reg_idx_next     = dump_reg_idx_reg;
    dump_byte_sel_next    = dump_byte_sel_reg;
    dump_mem_addr_next    = dump_mem_addr_reg;
    dump_mem_len_next     = dump_mem_len_reg;
    latch_shift_next      = latch_shift_reg;
    latch_remaining_next  = latch_remaining_reg;
    latch_idx_next        = latch_idx_reg;
 
    rx_rd              = 1'b0;
    tx_start            = 1'b0;
    tx_data             = 8'h00;
    pipeline_rst        = 1'b0;
    pipeline_enable     = 1'b0;
    imem_we             = 1'b0;
    imem_waddr          = '0;
    imem_wdata          = '0;
    regfile_debug_addr  = '0;
    dmem_debug_addr     = '0;
 
    unique case (state_reg)
 
      ST_IDLE: begin
        if (!rx_empty) state_next = ST_DECODE;
      end
 
      ST_DECODE: begin
        rx_rd = 1'b1;
        unique case (rx_data)
          OP_RESET:        state_next = ST_RESET_CLEAR;
          OP_LOAD_WORD:    state_next = ST_LOAD_B0;
          OP_RUN:          state_next = ST_RUN;
          OP_STEP:         state_next = ST_STEP_PULSE;
          OP_DUMP_REGS:    state_next = ST_DUMPREGS_TX;
          OP_DUMP_MEM:     state_next = ST_DUMPMEM_ADDR_B0;
          OP_DUMP_LATCHES: begin
            state_next           = ST_DUMPLATCHES_TX;
            latch_idx_next       = 2'd0;
            latch_shift_next     = {{(MAX_LATCH_BITS-$bits(if_id_t)){1'b0}}, if_id_flat};
            latch_remaining_next = IF_ID_BYTES[4:0];
          end
          default:         state_next = ST_IDLE;  // opcodes todavía no implementados: se ignoran
        endcase
      end
 
      ST_RESET_CLEAR: begin
        pipeline_rst = 1'b1;
        imem_we      = 1'b1;
        imem_waddr   = clear_addr_reg;
        imem_wdata   = 32'h00000013;  // NOP (addi x0,x0,0)
        if (clear_addr_reg == {IMEM_ADDR_W{1'b1}}) begin
          clear_addr_next = '0;
          load_addr_next  = '0;  // LOAD_WORD arranca de nuevo desde la dirección 0
          state_next      = ST_IDLE;
        end else begin
          clear_addr_next = clear_addr_reg + 1'b1;
        end
      end
 
      ST_LOAD_B0: if (!rx_empty) begin
        load_word_next[7:0] = rx_data;
        rx_rd      = 1'b1;
        state_next = ST_LOAD_B1;
      end
 
      ST_LOAD_B1: if (!rx_empty) begin
        load_word_next[15:8] = rx_data;
        rx_rd      = 1'b1;
        state_next = ST_LOAD_B2;
      end
 
      ST_LOAD_B2: if (!rx_empty) begin
        load_word_next[23:16] = rx_data;
        rx_rd      = 1'b1;
        state_next = ST_LOAD_B3;
      end
 
      ST_LOAD_B3: if (!rx_empty) begin
        load_word_next[31:24] = rx_data;
        rx_rd      = 1'b1;
        state_next = ST_LOAD_COMMIT;
      end
 
      ST_LOAD_COMMIT: begin
        imem_we        = 1'b1;
        imem_waddr     = load_addr_reg;
        imem_wdata     = load_word_reg;
        load_addr_next = load_addr_reg + 1'b1;
        state_next     = ST_IDLE;
      end
 
      // RUN: mantiene pipeline_enable en 1 tantos ciclos como haga falta,
      // hasta que pipeline_top avisa halted=1. No hay timeout -- si el
      // programa nunca llega a halt, esto se queda esperando para siempre
      // (ver "fuera de alcance" de la sección 4 del README).
      ST_RUN: begin
        pipeline_enable = 1'b1;
        if (halted) state_next = ST_TX_START;
      end
 
      // STEP: un solo ciclo de pipeline_enable, gracias a que este estado
      // dura exactamente un ciclo (state_next siempre avanza).
      ST_STEP_PULSE: begin
        pipeline_enable = 1'b1;
        state_next      = ST_TX_START;
      end
 
      // Arma la respuesta y pulsa tx_start un ciclo. halt_code ya tiene los
      // valores que pide el protocolo (0/1/2), no hace falta traducir nada.
      ST_TX_START: begin
        tx_start   = 1'b1;
        tx_data    = {6'b0, halt_code};
        state_next = ST_TX_WAIT;
      end
 
      ST_TX_WAIT: begin
        if (tx_done_tick) state_next = ST_IDLE;
      end
 
      // DUMP_REGS: recorre los 32 registros, 4 bytes little-endian cada uno.
      // regfile_debug_addr se mantiene fijo en dump_reg_idx_reg durante los
      // 4 bytes de ese registro -- no hace falta latchear el word aparte,
      // el puerto de debug es combinacional y no cambia mientras tanto.
      ST_DUMPREGS_TX: begin
        regfile_debug_addr = dump_reg_idx_reg;
        tx_start = 1'b1;
        unique case (dump_byte_sel_reg)
          2'd0: tx_data = regfile_debug_data[7:0];
          2'd1: tx_data = regfile_debug_data[15:8];
          2'd2: tx_data = regfile_debug_data[23:16];
          2'd3: tx_data = regfile_debug_data[31:24];
        endcase
        state_next = ST_DUMPREGS_WAIT;
      end
 
      ST_DUMPREGS_WAIT: begin
        regfile_debug_addr = dump_reg_idx_reg;
        if (tx_done_tick) begin
          if (dump_byte_sel_reg == 2'd3) begin
            dump_byte_sel_next = 2'd0;
            if (dump_reg_idx_reg == {REG_ADDR_W{1'b1}}) begin
              dump_reg_idx_next = '0;
              state_next        = ST_IDLE;  // x31 fue el ultimo, terminado
            end else begin
              dump_reg_idx_next = dump_reg_idx_reg + 1'b1;
              state_next        = ST_DUMPREGS_TX;
            end
          end else begin
            dump_byte_sel_next = dump_byte_sel_reg + 1'b1;
            state_next         = ST_DUMPREGS_TX;
          end
        end
      end
 
      // DUMP_MEM: direccion (2 bytes) + cantidad (2 bytes), despues manda
      // esa cantidad de bytes de dmem arrancando en esa direccion.
      ST_DUMPMEM_ADDR_B0: if (!rx_empty) begin
        dump_mem_addr_next[7:0] = rx_data;
        rx_rd      = 1'b1;
        state_next = ST_DUMPMEM_ADDR_B1;
      end
 
      ST_DUMPMEM_ADDR_B1: if (!rx_empty) begin
        dump_mem_addr_next[15:8] = rx_data;
        rx_rd      = 1'b1;
        state_next = ST_DUMPMEM_LEN_B0;
      end
 
      ST_DUMPMEM_LEN_B0: if (!rx_empty) begin
        dump_mem_len_next[7:0] = rx_data;
        rx_rd      = 1'b1;
        state_next = ST_DUMPMEM_LEN_B1;
      end
 
      ST_DUMPMEM_LEN_B1: if (!rx_empty) begin
        dump_mem_len_next[15:8] = rx_data;
        rx_rd      = 1'b1;
        state_next = ST_DUMPMEM_TX;
      end
 
      // Punto de chequeo: si ya no queda nada por mandar (cantidad=0, ya
      // sea porque el host pidio 0 bytes o porque ya se mandaron todos),
      // termina sin mandar nada mas.
      ST_DUMPMEM_TX: begin
        if (dump_mem_len_reg == 16'd0) begin
          state_next = ST_IDLE;
        end else begin
          dmem_debug_addr = dump_mem_addr_reg[DMEM_ADDR_W-1:0];
          tx_data         = dmem_debug_data;
          tx_start        = 1'b1;
          state_next      = ST_DUMPMEM_WAIT;
        end
      end
 
      ST_DUMPMEM_WAIT: begin
        dmem_debug_addr = dump_mem_addr_reg[DMEM_ADDR_W-1:0];
        if (tx_done_tick) begin
          dump_mem_addr_next = dump_mem_addr_reg + 16'd1;
          dump_mem_len_next  = dump_mem_len_reg - 16'd1;
          state_next         = ST_DUMPMEM_TX;
        end
      end
 
      // DUMP_LATCHES: manda el byte bajo del shift register compartido.
      // El mismo par de estados sirve para los 4 latches -- lo unico que
      // cambia es con que struct se recargo el shift register al empezar
      // cada uno.
      ST_DUMPLATCHES_TX: begin
        tx_data    = latch_shift_reg[7:0];
        tx_start   = 1'b1;
        state_next = ST_DUMPLATCHES_WAIT;
      end
 
      ST_DUMPLATCHES_WAIT: begin
        if (tx_done_tick) begin
          if (latch_remaining_reg == 5'd1) begin
            // se acaba de mandar el ultimo byte de este latch -- pasa al
            // siguiente, recargando el shift register con el struct que
            // corresponda (zero-extendido a MAX_LATCH_BITS)
            unique case (latch_idx_reg)
              2'd0: begin  // termino if_id_q, sigue id_ex_q
                latch_idx_next       = 2'd1;
                latch_shift_next     = {{(MAX_LATCH_BITS-$bits(id_ex_t)){1'b0}}, id_ex_flat};
                latch_remaining_next = ID_EX_BYTES[4:0];
                state_next           = ST_DUMPLATCHES_TX;
              end
              2'd1: begin  // termino id_ex_q, sigue ex_mem_q
                latch_idx_next       = 2'd2;
                latch_shift_next     = {{(MAX_LATCH_BITS-$bits(ex_mem_t)){1'b0}}, ex_mem_flat};
                latch_remaining_next = EX_MEM_BYTES[4:0];
                state_next           = ST_DUMPLATCHES_TX;
              end
              2'd2: begin  // termino ex_mem_q, sigue mem_wb_q
                latch_idx_next       = 2'd3;
                latch_shift_next     = {{(MAX_LATCH_BITS-$bits(mem_wb_t)){1'b0}}, mem_wb_flat};
                latch_remaining_next = MEM_WB_BYTES[4:0];
                state_next           = ST_DUMPLATCHES_TX;
              end
              2'd3: begin  // termino mem_wb_q, no queda nada mas
                state_next = ST_IDLE;
              end
            endcase
          end else begin
            latch_shift_next     = latch_shift_reg >> 8;
            latch_remaining_next = latch_remaining_reg - 5'd1;
            state_next           = ST_DUMPLATCHES_TX;
          end
        end
      end
 
      default: state_next = ST_IDLE;
 
    endcase
  end
 
  assign program_len = load_addr_reg;

endmodule
