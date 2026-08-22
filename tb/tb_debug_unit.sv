module tb_debug_unit;

  import riscv_pkg::*;

  logic       clk = 0;
  logic       reset;
  logic       rx_empty;
  logic [7:0] rx_data;
  logic       rx_rd;
  logic       tx_done_tick;
  logic       tx_start;
  logic [7:0] tx_data;
  logic       pipeline_rst;
  logic       pipeline_enable;
  logic                   imem_we;
  logic [IMEM_ADDR_W-1:0] imem_waddr;
  logic [31:0]            imem_wdata;
  logic [IMEM_ADDR_W-1:0] program_len;
  logic                   halted;
  halt_code_e             halt_code;
  logic [REG_ADDR_W-1:0]  regfile_debug_addr;
  logic [XLEN-1:0]        regfile_debug_data;
  logic [DMEM_ADDR_W-1:0] dmem_debug_addr;
  logic [7:0]             dmem_debug_data;
  if_id_t  if_id_q_in;
  id_ex_t  id_ex_q_in;
  ex_mem_t ex_mem_q_in;
  mem_wb_t mem_wb_q_in;

  int errors = 0;
  int checks = 0;

  debug_unit dut (.*);

  always #5 clk = ~clk;

  // Modelo mínimo de imem: solo para verificar que la Debug Unit escribe
  // donde y lo que corresponde, no es imem.sv real.
  logic [31:0] imem_model[0:(1 << IMEM_ADDR_W)-1];
  always_ff @(posedge clk) begin
    if (imem_we) imem_model[imem_waddr] <= imem_wdata;
  end

  // Modelos mínimos de regfile/dmem, solo para probar DUMP_REGS/DUMP_MEM
  // en aislamiento -- no son regfile.sv ni dmem.sv reales.
  logic [31:0] regfile_model[0:31];
  assign regfile_debug_data = regfile_model[regfile_debug_addr];

  logic [7:0] dmem_model[0:(1 << DMEM_ADDR_W)-1];
  assign dmem_debug_data = dmem_model[dmem_debug_addr];

  // Anchos calculados igual que en debug_unit.sv, para no duplicar
  // constantes a mano -- si algun struct cambia de tamaño, esto se ajusta solo.
  localparam int IF_ID_BYTES_TB  = ($bits(if_id_t)  + 7) / 8;
  localparam int ID_EX_BYTES_TB  = ($bits(id_ex_t)  + 7) / 8;
  localparam int EX_MEM_BYTES_TB = ($bits(ex_mem_t) + 7) / 8;
  localparam int MEM_WB_BYTES_TB = ($bits(mem_wb_t) + 7) / 8;

  logic [$bits(if_id_t)-1:0]  if_id_flat_exp;
  logic [$bits(id_ex_t)-1:0]  id_ex_flat_exp;
  logic [$bits(ex_mem_t)-1:0] ex_mem_flat_exp;
  logic [$bits(mem_wb_t)-1:0] mem_wb_flat_exp;
  assign if_id_flat_exp  = if_id_q_in;
  assign id_ex_flat_exp  = id_ex_q_in;
  assign ex_mem_flat_exp = ex_mem_q_in;
  assign mem_wb_flat_exp = mem_wb_q_in;

  logic [IF_ID_BYTES_TB*8-1:0]  if_id_padded;
  logic [ID_EX_BYTES_TB*8-1:0]  id_ex_padded;
  logic [EX_MEM_BYTES_TB*8-1:0] ex_mem_padded;
  logic [MEM_WB_BYTES_TB*8-1:0] mem_wb_padded;
  assign if_id_padded  = {{(IF_ID_BYTES_TB*8-$bits(if_id_t)){1'b0}}, if_id_flat_exp};
  assign id_ex_padded  = {{(ID_EX_BYTES_TB*8-$bits(id_ex_t)){1'b0}}, id_ex_flat_exp};
  assign ex_mem_padded = {{(EX_MEM_BYTES_TB*8-$bits(ex_mem_t)){1'b0}}, ex_mem_flat_exp};
  assign mem_wb_padded = {{(MEM_WB_BYTES_TB*8-$bits(mem_wb_t)){1'b0}}, mem_wb_flat_exp};

  // Modelo mínimo de rx_fifo: rx_data expone el frente de la cola de forma
  // ESTABLE hasta que rx_rd realmente hace el pop, en el flanco de clock
  // siguiente -- exactamente el mismo timing que rx_fifo.v real. Cambiar
  // rx_data apenas se ve rx_rd (sin esperar el flanco) fue el bug de la
  // primera versión de este testbench, no de debug_unit.sv.
  logic [7:0] queue_mem[0:63];
  int         queue_head = 0;
  int         queue_tail = 0;

  function automatic int queue_size();
    return queue_tail - queue_head;
  endfunction

  always_comb begin
    if (queue_size() > 0) begin
      rx_empty = 1'b0;
      rx_data  = queue_mem[queue_head];
    end else begin
      rx_empty = 1'b1;
      rx_data  = 8'h00;
    end
  end

  always_ff @(posedge clk) begin
    if (rx_rd && queue_size() > 0) queue_head <= queue_head + 1;
  end

  task automatic send_byte(input logic [7:0] b);
    queue_mem[queue_tail] = b;
    queue_tail = queue_tail + 1;
  endtask

  task automatic wait_consumed();
    wait (queue_head == queue_tail);
    @(posedge clk); #1;  // dejar que el ultimo pop se termine de reflejar
  endtask

  // Modelo mínimo de uart_tx: confirma la transmisión un ciclo después de
  // tx_start, sin simular bits seriales reales (mismo criterio que rx_fifo
  // arriba: a debug_unit.sv no le importa cuánto tarda de verdad, solo el
  // protocolo tx_start/tx_data/tx_done_tick).
  always_ff @(posedge clk) tx_done_tick <= tx_start;

  logic [7:0] captured_tx_data;
  task automatic wait_tx_response();
    // si tx_start ya esta en 1 en el momento en que se llama esta tarea
    // (pasa en STEP, donde el llamador ya avanzo hasta ese mismo ciclo),
    // lo toma directo -- esperar un flanco de mas antes de chequear se lo
    // salteaba por completo, quedandose esperando para siempre.
    while (!tx_start) begin
      @(posedge clk);
      #1;
    end
    captured_tx_data = tx_data;
    // esperar a que tx_start baje de nuevo antes de salir, para que una
    // proxima llamada inmediata (como en el loop de DUMP_REGS) no vuelva
    // a capturar este mismo pulso en vez del siguiente.
    while (tx_start) begin
      @(posedge clk);
      #1;
    end
  endtask

  initial begin
    reset = 1; tx_done_tick = 0; halted = 1'b0; halt_code = HALT_NONE;
    @(posedge clk); #1;
    reset = 0;

    // ================= RESET =================
    send_byte(8'h00);  // OP_RESET

    // esperar a que efectivamente entre al barrido (ST_DECODE es un estado
    // intermedio antes de esto, pipeline_rst todavia no esta en 1 ahi)
    wait (dut.state_reg == dut.ST_RESET_CLEAR);
    #1;
    checks++;
    if (!pipeline_rst) begin
      errors++;
      $error("[RESET] pipeline_rst no esta en 1 durante el barrido");
    end

    // esperar a que el barrido termine (vuelve a ST_IDLE)
    wait_consumed();
    wait (dut.state_reg == dut.ST_IDLE);
    #1;

    // las 1024 palabras de imem tienen que ser NOP
    checks++;
    if (imem_model[0] !== 32'h00000013 || imem_model[1023] !== 32'h00000013) begin
      errors++;
      $error("[RESET] imem no quedo limpio (mem[0]=%08h mem[1023]=%08h)", imem_model[0], imem_model[1023]);
    end

    // pipeline_rst se tiene que haber bajado de nuevo
    checks++;
    if (pipeline_rst) begin
      errors++;
      $error("[RESET] pipeline_rst se quedo en 1 despues del barrido");
    end

    // ================= LOAD_WORD =================
    // instrucción a cargar: 0xCAFEF00D, little-endian byte a byte
    send_byte(8'h01);  // OP_LOAD_WORD
    send_byte(8'h0D);  // byte 0 (LSB)
    send_byte(8'hF0);  // byte 1
    send_byte(8'hFE);  // byte 2
    send_byte(8'hCA);  // byte 3 (MSB)

    wait_consumed();
    wait (dut.state_reg == dut.ST_IDLE);
    #1;
    checks++;
    if (imem_model[0] !== 32'hCAFEF00D) begin
      errors++;
      $error("[LOAD_WORD] imem[0]=%08h (esperado cafef00d)", imem_model[0]);
    end

    // segundo LOAD_WORD: tiene que ir a la direccion 1 (el contador incrementa solo)
    send_byte(8'h01);
    send_byte(8'hEF);
    send_byte(8'hBE);
    send_byte(8'hAD);
    send_byte(8'hDE);

    wait_consumed();
    wait (dut.state_reg == dut.ST_IDLE);
    #1;
    checks++;
    if (imem_model[1] !== 32'hDEADBEEF) begin
      errors++;
      $error("[LOAD_WORD] imem[1]=%08h (esperado deadbeef)", imem_model[1]);
    end

    checks++;
    if (program_len !== 10'd2) begin
      errors++;
      $error("[program_len] program_len=%0d (esperado 2, tras cargar 2 palabras)", program_len);
    end

    // ================= RESET reinicia el contador de carga =================
    send_byte(8'h00);
    wait (dut.state_reg != dut.ST_IDLE);
    wait_consumed();
    wait (dut.state_reg == dut.ST_IDLE);
    #1;

    send_byte(8'h01);
    send_byte(8'h11); send_byte(8'h11); send_byte(8'h11); send_byte(8'h11);
    wait_consumed();
    wait (dut.state_reg == dut.ST_IDLE);
    #1;
    checks++;
    if (imem_model[0] !== 32'h11111111) begin
      errors++;
      $error("[RESET+LOAD_WORD] tras un reset, la carga vuelve a arrancar en addr 0 (imem[0]=%08h)", imem_model[0]);
    end

    // ================= STEP: todavia no haltea =================
    halted = 1'b0; halt_code = HALT_NONE;
    send_byte(8'h03);  // OP_STEP

    // pipeline_enable tiene que pulsar exactamente un ciclo
    wait (pipeline_enable);
    checks++;
    @(posedge clk); #1;
    if (pipeline_enable) begin
      errors++;
      $error("[STEP] pipeline_enable siguio en 1 mas de un ciclo");
    end

    wait_tx_response();
    checks++;
    if (captured_tx_data !== 8'h00) begin
      errors++;
      $error("[STEP] respuesta=%02h (esperado 00, sigue corriendo)", captured_tx_data);
    end

    // ================= STEP: este paso haltea por rango =================
    send_byte(8'h03);
    wait (pipeline_enable);
    halted = 1'b1; halt_code = HALT_RANGE;  // pipeline_top "avisa" que este paso halteo

    wait_tx_response();
    checks++;
    if (captured_tx_data !== 8'h01) begin
      errors++;
      $error("[STEP] respuesta=%02h (esperado 01, halt por rango)", captured_tx_data);
    end

    // ================= RUN: pipeline_enable se mantiene hasta halted =================
    halted = 1'b0; halt_code = HALT_NONE;
    send_byte(8'h02);  // OP_RUN

    wait (pipeline_enable);
    // se mantiene en 1 varios ciclos mientras no llega halted
    repeat (5) begin
      @(posedge clk); #1;
      checks++;
      if (!pipeline_enable) begin
        errors++;
        $error("[RUN] pipeline_enable bajo antes de que llegara halted");
      end
    end

    halted = 1'b1; halt_code = HALT_ILLEGAL;
    wait_tx_response();
    checks++;
    if (captured_tx_data !== 8'h02) begin
      errors++;
      $error("[RUN] respuesta=%02h (esperado 02, halt por ilegal)", captured_tx_data);
    end
    checks++;
    if (pipeline_enable) begin
      errors++;
      $error("[RUN] pipeline_enable se quedo en 1 despues de halted");
    end

    // ================= DUMP_REGS =================
    for (int i = 0; i < 32; i++) regfile_model[i] = 32'h10000000 + i;

    send_byte(8'h04);  // OP_DUMP_REGS

    for (int i = 0; i < 32; i++) begin
      for (int b = 0; b < 4; b++) begin
        logic [7:0] expected;
        expected = regfile_model[i][8*b+:8];
        wait_tx_response();
        checks++;
        if (captured_tx_data !== expected) begin
          errors++;
          $error("[DUMP_REGS] x%0d byte%0d = %02h (esperado %02h)", i, b, captured_tx_data, expected);
        end
      end
    end

    checks++;
    wait (dut.state_reg == dut.ST_IDLE);
    #1;
    if (dut.state_reg !== dut.ST_IDLE) begin
      errors++;
      $error("[DUMP_REGS] no volvio a ST_IDLE al terminar");
    end

    // ================= DUMP_MEM =================
    dmem_model[100] = 8'hAA;
    dmem_model[101] = 8'hBB;
    dmem_model[102] = 8'hCC;

    send_byte(8'h06);         // OP_DUMP_MEM
    send_byte(8'd100); send_byte(8'd0);  // direccion=100, little-endian
    send_byte(8'd3);   send_byte(8'd0);  // cantidad=3

    begin
      logic [7:0] expected_mem[0:2];
      expected_mem[0] = 8'hAA; expected_mem[1] = 8'hBB; expected_mem[2] = 8'hCC;
      for (int i = 0; i < 3; i++) begin
        wait_tx_response();
        checks++;
        if (captured_tx_data !== expected_mem[i]) begin
          errors++;
          $error("[DUMP_MEM] byte%0d = %02h (esperado %02h)", i, captured_tx_data, expected_mem[i]);
        end
      end
    end

    checks++;
    wait (dut.state_reg == dut.ST_IDLE);
    #1;
    if (dut.state_reg !== dut.ST_IDLE) begin
      errors++;
      $error("[DUMP_MEM] no volvio a ST_IDLE al terminar");
    end

    // --- DUMP_MEM con cantidad=0: no manda nada, vuelve derecho a IDLE ---
    send_byte(8'h06);
    send_byte(8'd0); send_byte(8'd0);
    send_byte(8'd0); send_byte(8'd0);  // cantidad=0
    wait_consumed();
    wait (dut.state_reg == dut.ST_IDLE);
    #1;
    checks++;
    // si llego hasta aca sin colgarse esperando un tx_done_tick que nunca
    // se iba a pedir, el camino de cantidad=0 funciono
    if (tx_start) begin
      errors++;
      $error("[DUMP_MEM] cantidad=0 no deberia disparar ningun tx_start");
    end

    // ================= DUMP_LATCHES =================
    if_id_q_in.valid    = 1'b1;
    if_id_q_in.pc       = 32'hAAAA0000;
    if_id_q_in.pc_plus4 = 32'hAAAA0004;
    if_id_q_in.instr    = 32'h12345678;

    id_ex_q_in.valid    = 1'b1;
    id_ex_q_in.pc       = 32'hBBBB0000;
    id_ex_q_in.pc_plus4 = 32'hBBBB0004;
    id_ex_q_in.rs1_data = 32'h11111111;
    id_ex_q_in.rs2_data = 32'h22222222;
    id_ex_q_in.imm      = 32'h33333333;
    id_ex_q_in.rs1      = 5'd5;
    id_ex_q_in.rs2      = 5'd10;
    id_ex_q_in.rd       = 5'd15;
    id_ex_q_in.funct3   = 3'b101;
    id_ex_q_in.ctrl.reg_write    = 1'b1;
    id_ex_q_in.ctrl.mem_read     = 1'b0;
    id_ex_q_in.ctrl.mem_write    = 1'b0;
    id_ex_q_in.ctrl.wb_src       = WB_ALU;
    id_ex_q_in.ctrl.alu_src      = 1'b1;
    id_ex_q_in.ctrl.branch       = 1'b0;
    id_ex_q_in.ctrl.jump         = 1'b0;
    id_ex_q_in.ctrl.jalr         = 1'b0;
    id_ex_q_in.ctrl.mem_unsigned = 1'b0;
    id_ex_q_in.ctrl.alu_op       = ALU_ADD;
    id_ex_q_in.ctrl.mem_size     = MEM_WORD;
    id_ex_q_in.ctrl.imm_src      = IMM_I;

    ex_mem_q_in.valid      = 1'b1;
    ex_mem_q_in.alu_result = 32'hCCCC0000;
    ex_mem_q_in.rs2_data   = 32'hCCCC0004;
    ex_mem_q_in.rd         = 5'd20;
    ex_mem_q_in.pc_plus4   = 32'hCCCC0008;
    ex_mem_q_in.ctrl       = id_ex_q_in.ctrl;

    mem_wb_q_in.valid      = 1'b1;
    mem_wb_q_in.mem_data   = 32'hDDDD0000;
    mem_wb_q_in.alu_result = 32'hDDDD0004;
    mem_wb_q_in.pc_plus4   = 32'hDDDD0008;
    mem_wb_q_in.rd         = 5'd25;
    mem_wb_q_in.ctrl       = id_ex_q_in.ctrl;

    send_byte(8'h05);  // OP_DUMP_LATCHES

    for (int b = 0; b < IF_ID_BYTES_TB; b++) begin
      logic [7:0] expected;
      expected = if_id_padded[8*b+:8];
      wait_tx_response();
      checks++;
      if (captured_tx_data !== expected) begin
        errors++;
        $error("[DUMP_LATCHES if_id] byte%0d = %02h (esperado %02h)", b, captured_tx_data, expected);
      end
    end

    for (int b = 0; b < ID_EX_BYTES_TB; b++) begin
      logic [7:0] expected;
      expected = id_ex_padded[8*b+:8];
      wait_tx_response();
      checks++;
      if (captured_tx_data !== expected) begin
        errors++;
        $error("[DUMP_LATCHES id_ex] byte%0d = %02h (esperado %02h)", b, captured_tx_data, expected);
      end
    end

    for (int b = 0; b < EX_MEM_BYTES_TB; b++) begin
      logic [7:0] expected;
      expected = ex_mem_padded[8*b+:8];
      wait_tx_response();
      checks++;
      if (captured_tx_data !== expected) begin
        errors++;
        $error("[DUMP_LATCHES ex_mem] byte%0d = %02h (esperado %02h)", b, captured_tx_data, expected);
      end
    end

    for (int b = 0; b < MEM_WB_BYTES_TB; b++) begin
      logic [7:0] expected;
      expected = mem_wb_padded[8*b+:8];
      wait_tx_response();
      checks++;
      if (captured_tx_data !== expected) begin
        errors++;
        $error("[DUMP_LATCHES mem_wb] byte%0d = %02h (esperado %02h)", b, captured_tx_data, expected);
      end
    end

    checks++;
    wait (dut.state_reg == dut.ST_IDLE);
    #1;
    if (dut.state_reg !== dut.ST_IDLE) begin
      errors++;
      $error("[DUMP_LATCHES] no volvio a ST_IDLE al terminar");
    end

    if (errors == 0)
      $display("DEBUG_UNIT_TB: %0d/%0d checks OK", checks, checks);
    else
      $display("DEBUG_UNIT_TB: %0d errores en %0d checks", errors, checks);

    $finish;
  end

endmodule
