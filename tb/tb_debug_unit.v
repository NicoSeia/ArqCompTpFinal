`include "riscv_defs.vh"
module tb_debug_unit;

  reg                     clk = 0;
  reg                     reset;
  wire                    rx_empty;
  wire [7:0]              rx_data;
  wire                    rx_rd;
  reg                     tx_done_tick;
  wire                    tx_start;
  wire [7:0]              tx_data;
  wire                    pipeline_rst;
  wire                    pipeline_enable;
  wire                    imem_we;
  wire [`IMEM_ADDR_W-1:0] imem_waddr;
  wire [31:0]             imem_wdata;
  wire [`IMEM_ADDR_W-1:0] program_len;
  reg                     halted;
  reg  [`HALT_CODE_W-1:0] halt_code;
  wire [`REG_ADDR_W-1:0]  regfile_debug_addr;
  wire [`XLEN-1:0]        regfile_debug_data;
  wire [`DMEM_ADDR_W-1:0] dmem_debug_addr;
  wire [7:0]              dmem_debug_data;
  reg  [`IF_ID_W-1:0]     if_id_q_in;
  reg  [`ID_EX_W-1:0]     id_ex_q_in;
  reg  [`EX_MEM_W-1:0]    ex_mem_q_in;
  reg  [`MEM_WB_W-1:0]    mem_wb_q_in;

  integer errors = 0;
  integer checks = 0;
  integer i, b;

  // Verilog no tiene .* : puertos explicitos (mismos nombres).
  debug_unit dut (
      .clk(clk), .reset(reset),
      .rx_empty(rx_empty), .rx_data(rx_data), .rx_rd(rx_rd),
      .tx_done_tick(tx_done_tick), .tx_start(tx_start), .tx_data(tx_data),
      .pipeline_rst(pipeline_rst), .pipeline_enable(pipeline_enable),
      .halted(halted), .halt_code(halt_code),
      .imem_we(imem_we), .imem_waddr(imem_waddr), .imem_wdata(imem_wdata),
      .program_len(program_len),
      .regfile_debug_addr(regfile_debug_addr), .regfile_debug_data(regfile_debug_data),
      .dmem_debug_addr(dmem_debug_addr), .dmem_debug_data(dmem_debug_data),
      .if_id_q_in(if_id_q_in), .id_ex_q_in(id_ex_q_in),
      .ex_mem_q_in(ex_mem_q_in), .mem_wb_q_in(mem_wb_q_in)
  );

  always #5 clk = ~clk;

  // Modelo mínimo de imem: solo para verificar que la Debug Unit escribe
  // donde y lo que corresponde, no es imem.v real.
  reg [31:0] imem_model [0:(1 << `IMEM_ADDR_W)-1];
  always @(posedge clk) begin
    if (imem_we) imem_model[imem_waddr] <= imem_wdata;
  end

  // Modelos mínimos de regfile/dmem, solo para probar DUMP_REGS/DUMP_MEM
  // en aislamiento -- no son regfile.v ni dmem.v reales.
  reg [31:0] regfile_model [0:31];
  assign regfile_debug_data = regfile_model[regfile_debug_addr];

  // El modelo es SINCRONO (1 ciclo de latencia), igual que el puerto de
  // debug de la dmem real (BRAM): la FSM tiene que esperar un ciclo.
  reg [7:0] dmem_model [0:(1 << `DMEM_ADDR_W)-1];
  reg [7:0] dmem_debug_data_q;
  always @(posedge clk) dmem_debug_data_q <= dmem_model[dmem_debug_addr];
  assign dmem_debug_data = dmem_debug_data_q;

  // Anchos calculados igual que en debug_unit.v, para no duplicar
  // constantes a mano -- si algun latch cambia de tamaño, esto se ajusta solo.
  localparam integer IF_ID_BYTES_TB  = (`IF_ID_W  + 7) / 8;
  localparam integer ID_EX_BYTES_TB  = (`ID_EX_W  + 7) / 8;
  localparam integer EX_MEM_BYTES_TB = (`EX_MEM_W + 7) / 8;
  localparam integer MEM_WB_BYTES_TB = (`MEM_WB_W + 7) / 8;

  // Latches zero-extendidos a un numero entero de bytes (asignar un vector
  // unsigned mas angosto a uno mas ancho completa con ceros).
  wire [IF_ID_BYTES_TB*8-1:0]  if_id_padded;
  wire [ID_EX_BYTES_TB*8-1:0]  id_ex_padded;
  wire [EX_MEM_BYTES_TB*8-1:0] ex_mem_padded;
  wire [MEM_WB_BYTES_TB*8-1:0] mem_wb_padded;
  assign if_id_padded  = if_id_q_in;
  assign id_ex_padded  = id_ex_q_in;
  assign ex_mem_padded = ex_mem_q_in;
  assign mem_wb_padded = mem_wb_q_in;

  // Modelo mínimo de rx_fifo: rx_data expone el frente de la cola de forma
  // ESTABLE hasta que rx_rd realmente hace el pop, en el flanco de clock
  // siguiente -- exactamente el mismo timing que rx_fifo.v real. Cambiar
  // rx_data apenas se ve rx_rd (sin esperar el flanco) fue el bug de la
  // primera versión de este testbench, no de debug_unit.
  reg [7:0] queue_mem [0:63];
  integer   queue_head = 0;
  integer   queue_tail = 0;

  // (en SV era una function queue_size() llamada desde always_comb; en
  // Verilog un always @* no ve las variables leidas DENTRO de una function,
  // asi que se escribe directo como asignacion continua)
  assign rx_empty = !((queue_tail - queue_head) > 0);
  assign rx_data  = ((queue_tail - queue_head) > 0) ? queue_mem[queue_head] : 8'h00;

  always @(posedge clk) begin
    if (rx_rd && ((queue_tail - queue_head) > 0)) queue_head <= queue_head + 1;
  end

  task automatic send_byte(input [7:0] byte_i);
    begin
      queue_mem[queue_tail] = byte_i;
      queue_tail = queue_tail + 1;
    end
  endtask

  task automatic wait_consumed;
    begin
      wait (queue_head == queue_tail);
      @(posedge clk); #1;  // dejar que el ultimo pop se termine de reflejar
    end
  endtask

  // Modelo mínimo de uart_tx: confirma la transmisión un ciclo después de
  // tx_start, sin simular bits seriales reales (mismo criterio que rx_fifo
  // arriba: a debug_unit no le importa cuánto tarda de verdad, solo el
  // protocolo tx_start/tx_data/tx_done_tick).
  always @(posedge clk) tx_done_tick <= tx_start;

  reg [7:0] captured_tx_data;
  task automatic wait_tx_response;
    begin
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
    end
  endtask

  // Variables que en SV eran locales a bloques begin/end sin nombre
  reg [7:0] expected;
  reg [7:0] expected_mem [0:2];

  // Campos de control "de prueba" para DUMP_LATCHES -- antes se armaban en
  // un unico ctrl_tb[`CTRL_W-1:0] campo por campo con `define de rango;
  // ahora cada campo es su propio reg, y se combinan con una concatenacion
  // explicita al armar cada *_q_in (misma idea que pipeline_top.v).
  reg        ctrl_tb_reg_write, ctrl_tb_mem_read, ctrl_tb_mem_write, ctrl_tb_alu_src;
  reg        ctrl_tb_branch, ctrl_tb_jump, ctrl_tb_jalr, ctrl_tb_mem_unsigned;
  reg [1:0]  ctrl_tb_wb_src, ctrl_tb_mem_size;
  reg [3:0]  ctrl_tb_alu_op;
  reg [2:0]  ctrl_tb_imm_src;
  reg [18:0] ctrl_tb_bus;  // los mismos 19 bits, ya combinados (para insertar en id_ex/ex_mem/mem_wb)

  initial begin
    reset = 1; tx_done_tick = 0; halted = 1'b0; halt_code = `HALT_NONE;
    @(posedge clk); #1;
    reset = 0;

    // ================= RESET =================
    send_byte(8'h00);  // OP_RESET

    // esperar a que efectivamente entre al barrido (ST_DECODE es un estado
    // intermedio antes de esto, pipeline_rst todavia no esta en 1 ahi)
    wait (dut.state_reg == dut.ST_RESET_CLEAR);
    #1;
    checks = checks + 1;
    if (!pipeline_rst) begin
      errors = errors + 1;
      $display("ERROR: [RESET] pipeline_rst no esta en 1 durante el barrido");
    end

    // esperar a que el barrido termine (vuelve a ST_IDLE)
    wait_consumed;
    wait (dut.state_reg == dut.ST_IDLE);
    #1;

    // las 1024 palabras de imem tienen que ser NOP
    checks = checks + 1;
    if (imem_model[0] !== 32'h00000013 || imem_model[1023] !== 32'h00000013) begin
      errors = errors + 1;
      $display("ERROR: [RESET] imem no quedo limpio (mem[0]=%08h mem[1023]=%08h)", imem_model[0], imem_model[1023]);
    end

    // pipeline_rst se tiene que haber bajado de nuevo
    checks = checks + 1;
    if (pipeline_rst) begin
      errors = errors + 1;
      $display("ERROR: [RESET] pipeline_rst se quedo en 1 despues del barrido");
    end

    // ================= LOAD_WORD =================
    // instrucción a cargar: 0xCAFEF00D, little-endian byte a byte
    send_byte(8'h01);  // OP_LOAD_WORD
    send_byte(8'h0D);  // byte 0 (LSB)
    send_byte(8'hF0);  // byte 1
    send_byte(8'hFE);  // byte 2
    send_byte(8'hCA);  // byte 3 (MSB)

    wait_consumed;
    wait (dut.state_reg == dut.ST_IDLE);
    #1;
    checks = checks + 1;
    if (imem_model[0] !== 32'hCAFEF00D) begin
      errors = errors + 1;
      $display("ERROR: [LOAD_WORD] imem[0]=%08h (esperado cafef00d)", imem_model[0]);
    end

    // segundo LOAD_WORD: tiene que ir a la direccion 1 (el contador incrementa solo)
    send_byte(8'h01);
    send_byte(8'hEF);
    send_byte(8'hBE);
    send_byte(8'hAD);
    send_byte(8'hDE);

    wait_consumed;
    wait (dut.state_reg == dut.ST_IDLE);
    #1;
    checks = checks + 1;
    if (imem_model[1] !== 32'hDEADBEEF) begin
      errors = errors + 1;
      $display("ERROR: [LOAD_WORD] imem[1]=%08h (esperado deadbeef)", imem_model[1]);
    end

    checks = checks + 1;
    if (program_len !== 10'd2) begin
      errors = errors + 1;
      $display("ERROR: [program_len] program_len=%0d (esperado 2, tras cargar 2 palabras)", program_len);
    end

    // ================= RESET reinicia el contador de carga =================
    send_byte(8'h00);
    wait (dut.state_reg != dut.ST_IDLE);
    wait_consumed;
    wait (dut.state_reg == dut.ST_IDLE);
    #1;

    send_byte(8'h01);
    send_byte(8'h11); send_byte(8'h11); send_byte(8'h11); send_byte(8'h11);
    wait_consumed;
    wait (dut.state_reg == dut.ST_IDLE);
    #1;
    checks = checks + 1;
    if (imem_model[0] !== 32'h11111111) begin
      errors = errors + 1;
      $display("ERROR: [RESET+LOAD_WORD] tras un reset, la carga vuelve a arrancar en addr 0 (imem[0]=%08h)", imem_model[0]);
    end

    // ================= STEP: todavia no haltea =================
    halted = 1'b0; halt_code = `HALT_NONE;
    send_byte(8'h03);  // OP_STEP

    // pipeline_enable tiene que pulsar exactamente un ciclo
    wait (pipeline_enable);
    checks = checks + 1;
    @(posedge clk); #1;
    if (pipeline_enable) begin
      errors = errors + 1;
      $display("ERROR: [STEP] pipeline_enable siguio en 1 mas de un ciclo");
    end

    wait_tx_response;
    checks = checks + 1;
    if (captured_tx_data !== 8'h00) begin
      errors = errors + 1;
      $display("ERROR: [STEP] respuesta=%02h (esperado 00, sigue corriendo)", captured_tx_data);
    end

    // ================= STEP: este paso haltea por rango =================
    send_byte(8'h03);
    wait (pipeline_enable);
    halted = 1'b1; halt_code = `HALT_RANGE;  // pipeline_top "avisa" que este paso halteo

    wait_tx_response;
    checks = checks + 1;
    if (captured_tx_data !== 8'h01) begin
      errors = errors + 1;
      $display("ERROR: [STEP] respuesta=%02h (esperado 01, halt por rango)", captured_tx_data);
    end

    // ================= RUN: pipeline_enable se mantiene hasta halted =================
    halted = 1'b0; halt_code = `HALT_NONE;
    send_byte(8'h02);  // OP_RUN

    wait (pipeline_enable);
    // se mantiene en 1 varios ciclos mientras no llega halted
    repeat (5) begin
      @(posedge clk); #1;
      checks = checks + 1;
      if (!pipeline_enable) begin
        errors = errors + 1;
        $display("ERROR: [RUN] pipeline_enable bajo antes de que llegara halted");
      end
    end

    halted = 1'b1; halt_code = `HALT_ILLEGAL;
    wait_tx_response;
    checks = checks + 1;
    if (captured_tx_data !== 8'h02) begin
      errors = errors + 1;
      $display("ERROR: [RUN] respuesta=%02h (esperado 02, halt por ilegal)", captured_tx_data);
    end
    checks = checks + 1;
    if (pipeline_enable) begin
      errors = errors + 1;
      $display("ERROR: [RUN] pipeline_enable se quedo en 1 despues de halted");
    end

    // ================= DUMP_REGS =================
    for (i = 0; i < 32; i = i + 1) regfile_model[i] = 32'h10000000 + i;

    send_byte(8'h04);  // OP_DUMP_REGS

    for (i = 0; i < 32; i = i + 1) begin
      for (b = 0; b < 4; b = b + 1) begin
        expected = regfile_model[i][8*b+:8];
        wait_tx_response;
        checks = checks + 1;
        if (captured_tx_data !== expected) begin
          errors = errors + 1;
          $display("ERROR: [DUMP_REGS] x%0d byte%0d = %02h (esperado %02h)", i, b, captured_tx_data, expected);
        end
      end
    end

    checks = checks + 1;
    wait (dut.state_reg == dut.ST_IDLE);
    #1;
    if (dut.state_reg !== dut.ST_IDLE) begin
      errors = errors + 1;
      $display("ERROR: [DUMP_REGS] no volvio a ST_IDLE al terminar");
    end

    // ================= DUMP_MEM =================
    dmem_model[100] = 8'hAA;
    dmem_model[101] = 8'hBB;
    dmem_model[102] = 8'hCC;

    send_byte(8'h06);         // OP_DUMP_MEM
    send_byte(8'd100); send_byte(8'd0);  // direccion=100, little-endian
    send_byte(8'd3);   send_byte(8'd0);  // cantidad=3

    expected_mem[0] = 8'hAA; expected_mem[1] = 8'hBB; expected_mem[2] = 8'hCC;
    for (i = 0; i < 3; i = i + 1) begin
      wait_tx_response;
      checks = checks + 1;
      if (captured_tx_data !== expected_mem[i]) begin
        errors = errors + 1;
        $display("ERROR: [DUMP_MEM] byte%0d = %02h (esperado %02h)", i, captured_tx_data, expected_mem[i]);
      end
    end

    checks = checks + 1;
    wait (dut.state_reg == dut.ST_IDLE);
    #1;
    if (dut.state_reg !== dut.ST_IDLE) begin
      errors = errors + 1;
      $display("ERROR: [DUMP_MEM] no volvio a ST_IDLE al terminar");
    end

    // --- DUMP_MEM con cantidad=0: no manda nada, vuelve derecho a IDLE ---
    send_byte(8'h06);
    send_byte(8'd0); send_byte(8'd0);
    send_byte(8'd0); send_byte(8'd0);  // cantidad=0
    wait_consumed;
    wait (dut.state_reg == dut.ST_IDLE);
    #1;
    checks = checks + 1;
    // si llego hasta aca sin colgarse esperando un tx_done_tick que nunca
    // se iba a pedir, el camino de cantidad=0 funciono
    if (tx_start) begin
      errors = errors + 1;
      $display("ERROR: [DUMP_MEM] cantidad=0 no deberia disparar ningun tx_start");
    end

    // ================= DUMP_LATCHES =================
    // Los *_q_in siguen siendo buses planos (puertos del DUT sin cambios),
    // pero ahora se arman con una concatenacion explicita en vez de
    // `define de rango de bits -- mismo orden de campos (MSB primero) que
    // usa pipeline_top.v en su propia concatenacion final, para que ambos
    // lados sigan de acuerdo en que es "el byte N" de cada latch.
    ctrl_tb_reg_write    = 1'b1;
    ctrl_tb_mem_read     = 1'b0;
    ctrl_tb_mem_write    = 1'b0;
    ctrl_tb_wb_src       = `WB_ALU;
    ctrl_tb_alu_src      = 1'b1;
    ctrl_tb_branch       = 1'b0;
    ctrl_tb_jump         = 1'b0;
    ctrl_tb_jalr         = 1'b0;
    ctrl_tb_mem_unsigned = 1'b0;
    ctrl_tb_alu_op       = `ALU_ADD;
    ctrl_tb_mem_size     = `MEM_WORD;
    ctrl_tb_imm_src      = `IMM_I;
    ctrl_tb_bus = {
        ctrl_tb_reg_write, ctrl_tb_mem_read, ctrl_tb_mem_write, ctrl_tb_wb_src, ctrl_tb_alu_src,
        ctrl_tb_branch, ctrl_tb_jump, ctrl_tb_jalr, ctrl_tb_mem_unsigned,
        ctrl_tb_alu_op, ctrl_tb_mem_size, ctrl_tb_imm_src
    };

    if_id_q_in = {1'b1, 32'hAAAA0000, 32'hAAAA0004, 32'h12345678};
    //             valid  pc           pc_plus4     instr

    id_ex_q_in = {
        1'b1,                    // valid
        32'hBBBB0000,            // pc
        32'hBBBB0004,            // pc_plus4
        32'h11111111,            // rs1_data
        32'h22222222,            // rs2_data
        32'h33333333,            // imm
        5'd5,                    // rs1
        5'd10,                   // rs2
        5'd15,                   // rd
        3'b101,                  // funct3
        ctrl_tb_bus              // ctrl (19 bits)
    };

    ex_mem_q_in = {
        1'b1,                    // valid
        32'hCCCC0000,            // alu_result
        32'hCCCC0004,            // rs2_data
        5'd20,                   // rd
        32'hCCCC0008,            // pc_plus4
        ctrl_tb_bus              // ctrl (19 bits)
    };

    mem_wb_q_in = {
        1'b1,                    // valid
        32'hDDDD0000,            // mem_data
        32'hDDDD0004,            // alu_result
        32'hDDDD0008,            // pc_plus4
        5'd25,                   // rd
        ctrl_tb_bus              // ctrl (19 bits)
    };

    send_byte(8'h05);  // OP_DUMP_LATCHES

    for (b = 0; b < IF_ID_BYTES_TB; b = b + 1) begin
      expected = if_id_padded[8*b+:8];
      wait_tx_response;
      checks = checks + 1;
      if (captured_tx_data !== expected) begin
        errors = errors + 1;
        $display("ERROR: [DUMP_LATCHES if_id] byte%0d = %02h (esperado %02h)", b, captured_tx_data, expected);
      end
    end

    for (b = 0; b < ID_EX_BYTES_TB; b = b + 1) begin
      expected = id_ex_padded[8*b+:8];
      wait_tx_response;
      checks = checks + 1;
      if (captured_tx_data !== expected) begin
        errors = errors + 1;
        $display("ERROR: [DUMP_LATCHES id_ex] byte%0d = %02h (esperado %02h)", b, captured_tx_data, expected);
      end
    end

    for (b = 0; b < EX_MEM_BYTES_TB; b = b + 1) begin
      expected = ex_mem_padded[8*b+:8];
      wait_tx_response;
      checks = checks + 1;
      if (captured_tx_data !== expected) begin
        errors = errors + 1;
        $display("ERROR: [DUMP_LATCHES ex_mem] byte%0d = %02h (esperado %02h)", b, captured_tx_data, expected);
      end
    end

    for (b = 0; b < MEM_WB_BYTES_TB; b = b + 1) begin
      expected = mem_wb_padded[8*b+:8];
      wait_tx_response;
      checks = checks + 1;
      if (captured_tx_data !== expected) begin
        errors = errors + 1;
        $display("ERROR: [DUMP_LATCHES mem_wb] byte%0d = %02h (esperado %02h)", b, captured_tx_data, expected);
      end
    end

    checks = checks + 1;
    wait (dut.state_reg == dut.ST_IDLE);
    #1;
    if (dut.state_reg !== dut.ST_IDLE) begin
      errors = errors + 1;
      $display("ERROR: [DUMP_LATCHES] no volvio a ST_IDLE al terminar");
    end

    if (errors == 0)
      $display("DEBUG_UNIT_TB: %0d/%0d checks OK", checks, checks);
    else
      $display("DEBUG_UNIT_TB: %0d errores en %0d checks", errors, checks);

    $finish;
  end

endmodule