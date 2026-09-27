`timescale 1ns / 1ps
`include "riscv_defs.vh"
module system_top #(
    parameter NB_DATA   = 8,
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 9600,
    parameter FIFO_W    = 8
) (
    input  wire clk,
    input  wire reset,
    input  wire rx_serial,
    output wire tx_serial
);

  // ================================================================
  // Enlace UART (TP2, sin modificar) -- mismo cableado que top.v
  // ================================================================
  wire s_tick;

  baud_rate_gen #(
      .CLK_FREQ(CLK_FREQ),
      .BAUD(BAUD_RATE)
  ) u_baud_gen (
      .clk  (clk),
      .reset(reset),
      .tick (s_tick)
  );

  wire               rx_done_tick;
  wire [NB_DATA-1:0] rx_data_out;

  uart_rx #(
      .NB_DATA(NB_DATA),
      .S_TICK (16)
  ) u_uart_rx (
      .clk         (clk),
      .reset       (reset),
      .rx          (rx_serial),
      .s_tick      (s_tick),
      .rx_done_tick(rx_done_tick),
      .data_out    (rx_data_out)
  );

  wire               fifo_empty;
  wire               fifo_full;
  wire [NB_DATA-1:0] fifo_r_data;
  wire               fifo_rd;

  rx_fifo #(
      .B(NB_DATA),
      .W(FIFO_W)
  ) u_rx_fifo (
      .clk   (clk),
      .reset (reset),
      .rd    (fifo_rd),
      .wr    (rx_done_tick),
      .w_data(rx_data_out),
      .empty (fifo_empty),
      .full  (fifo_full),
      .r_data(fifo_r_data)
  );

  wire               tx_start;
  wire [NB_DATA-1:0] tx_data_in;
  wire               tx_done_tick;

  uart_tx #(
      .NB_DATA(NB_DATA),
      .S_TICK (16)
  ) u_uart_tx (
      .clk         (clk),
      .reset       (reset),
      .tx          (tx_start),
      .s_tick      (s_tick),
      .data_in     (tx_data_in),
      .tx_done_tick(tx_done_tick),
      .tx_serial   (tx_serial)
  );

  // ================================================================
  // Puente entre la Debug Unit y el pipeline
  // ================================================================
  wire pipeline_rst_cmd;
  wire pipeline_enable;

  wire                    imem_we;
  wire [`IMEM_ADDR_W-1:0] imem_waddr;
  wire [31:0]             imem_wdata;
  wire [`IMEM_ADDR_W-1:0] program_len;

  wire                    halted;
  wire [`HALT_CODE_W-1:0] halt_code;

  wire [`REG_ADDR_W-1:0]  regfile_debug_addr;
  wire [`XLEN-1:0]        regfile_debug_data;
  wire [`DMEM_ADDR_W-1:0] dmem_debug_addr;
  wire [7:0]              dmem_debug_data;

  wire [`IF_ID_W-1:0]  if_id_q;
  wire [`ID_EX_W-1:0]  id_ex_q;
  wire [`EX_MEM_W-1:0] ex_mem_q;
  wire [`MEM_WB_W-1:0] mem_wb_q;

  // El reset del pipeline es el reset global del sistema, O el que pide
  // la Debug Unit al procesar el comando RESET del protocolo.
  wire pipeline_rst;
  assign pipeline_rst = reset || pipeline_rst_cmd;

  debug_unit u_debug_unit (
      .clk  (clk),
      .reset(reset),

      .rx_empty(fifo_empty),
      .rx_data (fifo_r_data),
      .rx_rd   (fifo_rd),

      .tx_done_tick(tx_done_tick),
      .tx_start    (tx_start),
      .tx_data     (tx_data_in),

      .pipeline_rst   (pipeline_rst_cmd),
      .pipeline_enable(pipeline_enable),

      .halted   (halted),
      .halt_code(halt_code),

      .imem_we    (imem_we),
      .imem_waddr (imem_waddr),
      .imem_wdata (imem_wdata),
      .program_len(program_len),

      .regfile_debug_addr(regfile_debug_addr),
      .regfile_debug_data(regfile_debug_data),

      .dmem_debug_addr(dmem_debug_addr),
      .dmem_debug_data(dmem_debug_data),

      .if_id_q_in (if_id_q),
      .id_ex_q_in (id_ex_q),
      .ex_mem_q_in(ex_mem_q),
      .mem_wb_q_in(mem_wb_q)
  );

  // ================================================================
  // El pipeline en sí
  // ================================================================
  pipeline_top u_pipeline (
      .clk   (clk),
      .rst   (pipeline_rst),
      .enable(pipeline_enable),

      .program_len(program_len),
      .imem_we    (imem_we),
      .imem_waddr (imem_waddr),
      .imem_wdata (imem_wdata),

      .regfile_debug_addr(regfile_debug_addr),
      .regfile_debug_data(regfile_debug_data),

      .dmem_debug_addr(dmem_debug_addr),
      .dmem_debug_data(dmem_debug_data),

      .halted   (halted),
      .halt_code(halt_code),

      .if_id_q_out (if_id_q),
      .id_ex_q_out (id_ex_q),
      .ex_mem_q_out(ex_mem_q),
      .mem_wb_q_out(mem_wb_q)
  );

endmodule
