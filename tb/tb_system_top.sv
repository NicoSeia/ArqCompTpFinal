module tb_system_top;

  import riscv_pkg::*;

  localparam CLK_FREQ = 32;
  localparam BAUD     = 1;  // DIVISOR = 32/(1*16) = 2 -> rapido para simular

  logic clk = 0;
  logic reset;
  logic rx_serial;  // hacia el DUT (lo que la "PC" transmite)
  logic tx_serial;  // desde el DUT (lo que la "PC" recibe)

  always #5 clk = ~clk;

  system_top #(
      .NB_DATA(8), .CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD), .FIFO_W(8)
  ) dut (
      .clk(clk), .reset(reset), .rx_serial(rx_serial), .tx_serial(tx_serial)
  );

  // --- Lado "host": un uart_tx y un uart_rx propios, mismos módulos del TP2 ---
  logic host_s_tick;
  baud_rate_gen #(.CLK_FREQ(CLK_FREQ), .BAUD(BAUD)) u_host_baud (
      .clk(clk), .reset(reset), .tick(host_s_tick)
  );

  logic       host_tx_start;
  logic [7:0] host_tx_data;
  logic       host_tx_done_tick;
  uart_tx #(.NB_DATA(8), .S_TICK(16)) u_host_tx (
      .clk(clk), .reset(reset), .tx(host_tx_start), .s_tick(host_s_tick),
      .data_in(host_tx_data), .tx_done_tick(host_tx_done_tick), .tx_serial(rx_serial)
  );

  logic       host_rx_done_tick;
  logic [7:0] host_rx_data;
  uart_rx #(.NB_DATA(8), .S_TICK(16)) u_host_rx (
      .clk(clk), .reset(reset), .rx(tx_serial), .s_tick(host_s_tick),
      .rx_done_tick(host_rx_done_tick), .data_out(host_rx_data)
  );

  int errors = 0;
  int checks = 0;

  task automatic host_send_byte(input logic [7:0] b);
    host_tx_data  = b;
    host_tx_start = 1'b1;
    @(posedge clk); #1;
    host_tx_start = 1'b0;
    wait (host_tx_done_tick);
    @(posedge clk); #1;
  endtask

  logic [7:0] host_received;
  task automatic host_wait_byte();
    wait (host_rx_done_tick);
    host_received = host_rx_data;
    @(posedge clk); #1;
  endtask

  function automatic logic [31:0] itype(input logic [11:0] imm, input logic [4:0] rs1, input logic [2:0] funct3, input logic [4:0] rd, input logic [6:0] opcode);
    return {imm, rs1, funct3, rd, opcode};
  endfunction

  initial begin
    reset = 1; host_tx_start = 1'b0;
    repeat (5) @(posedge clk);
    reset = 0;

    // ================= RESET (byte serie real) =================
    host_send_byte(8'h00);
    wait (dut.u_debug_unit.state_reg == dut.u_debug_unit.ST_IDLE);
    #1;

    // ================= LOAD_WORD: addi x1,x0,42 (byte serie real) =================
    // instr = 0x02A00093, little-endian: 93 00 A0 02
    begin
      logic [31:0] instr;
      instr = itype(12'd42, 5'd0, 3'b000, 5'd1, OP_IMM);
      host_send_byte(8'h01);
      host_send_byte(instr[7:0]);
      host_send_byte(instr[15:8]);
      host_send_byte(instr[23:16]);
      host_send_byte(instr[31:24]);
    end
    wait (dut.u_debug_unit.state_reg == dut.u_debug_unit.ST_IDLE);
    #1;

    // ================= RUN: corre hasta halt por rango (program_len=1) =================
    host_send_byte(8'h02);
    host_wait_byte();
    checks++;
    if (host_received !== 8'h01) begin
      errors++;
      $error("[RUN] respuesta=%02h (esperado 01, halt por rango)", host_received);
    end

    // ================= DUMP_REGS: leer x0 y x1 por serie real =================
    host_send_byte(8'h04);

    // x0: 4 bytes, todos en 0
    for (int b = 0; b < 4; b++) begin
      host_wait_byte();
      checks++;
      if (host_received !== 8'h00) begin
        errors++;
        $error("[DUMP_REGS] x0 byte%0d = %02h (esperado 00)", b, host_received);
      end
    end

    // x1: 4 bytes, tiene que dar 42 (0x0000002A)
    begin
      logic [7:0] expected[0:3];
      expected[0] = 8'h2A; expected[1] = 8'h00; expected[2] = 8'h00; expected[3] = 8'h00;
      for (int b = 0; b < 4; b++) begin
        host_wait_byte();
        checks++;
        if (host_received !== expected[b]) begin
          errors++;
          $error("[DUMP_REGS] x1 byte%0d = %02h (esperado %02h)", b, host_received, expected[b]);
        end
      end
    end

    if (errors == 0)
      $display("SYSTEM_TOP_TB: %0d/%0d checks OK (punta a punta, bits seriales reales)", checks, checks);
    else
      $display("SYSTEM_TOP_TB: %0d errores en %0d checks", errors, checks);

    $finish;
  end

  // Guardarraíl: si algo se cuelga, cortar en vez de dejar correr para siempre
  initial begin
    #2_000_000;
    $display("TIMEOUT: la simulacion no termino a tiempo");
    $finish;
  end

endmodule
