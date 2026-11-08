`include "riscv_defs.vh"
// -----------------------------------------------------------------------------
// tb_pipeline_hazards.v -- verifica el manejo de dependencias con loads tras
// la optimizacion de timing (el dato de un load NO se reenvia al EX: llega a
// la dependiente por el bypass del regfile en ID, y hazard_detect frena
// mientras el load esta en EX o en MEM).
//
//   PARTE 1: programa largo con loads seguidos de su uso a distancia 1, 2 y 3
//            (ALU), load -> beq tomado, load -> bne no tomado, load -> load
//            (puntero), load -> sw (dato y direccion), load -> jalr, y
//            forwarding de ALU hacia el comparador de branch (EX/MEM y MEM/WB).
//            Se corre libre (FASE A) y con enable aleatorio (FASE B).
//   PARTE 2: cuenta de ciclos de stall: dist.1 = 2, dist.2 = 1, dist.3 = 0.
// -----------------------------------------------------------------------------
module tb_pipeline_hazards;

  reg clk = 0;
  reg rst;
  reg enable;
  reg random_mode;

  integer errors = 0;
  integer checks = 0;
  integer i, cyc;
  integer stall_cnt;

  wire [`XLEN-1:0]        regfile_debug_data;
  wire [7:0]              dmem_debug_data;
  wire                    halted;
  wire [`HALT_CODE_W-1:0] halt_code;
  wire [`IF_ID_W-1:0]     if_id_q_out;
  wire [`ID_EX_W-1:0]     id_ex_q_out;
  wire [`EX_MEM_W-1:0]    ex_mem_q_out;
  wire [`MEM_WB_W-1:0]    mem_wb_q_out;

  reg [`IMEM_ADDR_W-1:0] prog_len;

  pipeline_top dut (
      .clk(clk), .rst(rst), .enable(enable),
      .program_len(prog_len),
      .imem_we(1'b0), .imem_waddr({`IMEM_ADDR_W{1'b0}}), .imem_wdata(32'd0),
      .regfile_debug_addr({`REG_ADDR_W{1'b0}}), .regfile_debug_data(regfile_debug_data),
      .dmem_debug_addr({`DMEM_ADDR_W{1'b0}}), .dmem_debug_data(dmem_debug_data),
      .halted(halted), .halt_code(halt_code),
      .if_id_q_out(if_id_q_out), .id_ex_q_out(id_ex_q_out),
      .ex_mem_q_out(ex_mem_q_out), .mem_wb_q_out(mem_wb_q_out)
  );

  always #5 clk = ~clk;

  // cuenta ciclos en los que el pipeline avanza Y hay stall por load-use
  always @(posedge clk) begin
    if (!rst && enable && dut.stall_load_use) stall_cnt = stall_cnt + 1;
  end

  always @(negedge clk) begin
    if (random_mode) enable = (($random & 7) < 5);
  end

  function [31:0] itype(input [11:0] imm, input [4:0] rs1, input [2:0] funct3, input [4:0] rd, input [6:0] opcode);
    itype = {imm, rs1, funct3, rd, opcode};
  endfunction
  function [31:0] rtype(input [6:0] funct7, input [4:0] rs2, input [4:0] rs1, input [2:0] funct3, input [4:0] rd, input [6:0] opcode);
    rtype = {funct7, rs2, rs1, funct3, rd, opcode};
  endfunction
  function [31:0] stype(input [11:0] imm, input [4:0] rs2, input [4:0] rs1, input [2:0] funct3, input [6:0] opcode);
    stype = {imm[11:5], rs2, rs1, funct3, imm[4:0], opcode};
  endfunction
  function [31:0] btype(input [12:0] imm, input [4:0] rs2, input [4:0] rs1, input [2:0] funct3);
    btype = {imm[12], imm[10:5], rs2, rs1, funct3, imm[4:1], imm[11], `OP_BRANCH};
  endfunction

  localparam NOP = 32'h00000013;  // addi x0,x0,0

  reg [31:0] prog [0:63];

  task automatic expect_reg(input integer idx, input [31:0] exp, input [8*40-1:0] name);
    begin
      checks = checks + 1;
      if (dut.u_regfile.regs[idx] !== exp) begin
        errors = errors + 1;
        $display("ERROR: [%0s] x%0d=%08h (esperado %08h)", name, idx, dut.u_regfile.regs[idx], exp);
      end
    end
  endtask

  task automatic expect_word(input integer widx, input [31:0] exp, input [8*40-1:0] name);
    begin
      checks = checks + 1;
      if (dut.u_dmem.mem[widx] !== exp) begin
        errors = errors + 1;
        $display("ERROR: [%0s] mem[%0d]=%08h (esperado %08h)", name, widx, dut.u_dmem.mem[widx], exp);
      end
    end
  endtask

  task automatic load_prog(input integer len);
    begin
      for (i = 0; i < len; i = i + 1) dut.u_imem.mem[i] = prog[i];
      prog_len = len;
    end
  endtask

  // reset + memoria en cero; pre_mem32 precarga mem[32] (byte 128) si es != 0
  task automatic reset_start(input [31:0] pre_mem32);
    begin
      for (i = 0; i < (1 << (`DMEM_ADDR_W-2)); i = i + 1) dut.u_dmem.mem[i] = 32'd0;
      dut.u_dmem.mem[32] = pre_mem32;
      rst = 1; enable = 1; random_mode = 0; stall_cnt = 0;
      @(posedge clk); #1;
      rst = 0; stall_cnt = 0;
    end
  endtask

  task automatic run_until_halt(input integer maxc, input rand_en);
    begin
      random_mode = rand_en;
      cyc = 0;
      while (!halted && cyc < maxc) begin @(posedge clk); cyc = cyc + 1; end
      random_mode = 0; enable = 1;
      @(posedge clk); #1;
      checks = checks + 1;
      if (!halted || halt_code !== `HALT_RANGE) begin
        errors = errors + 1;
        $display("ERROR: no llego a halt por rango (halted=%b code=%0d, ciclos=%0d)", halted, halt_code, cyc);
      end
    end
  endtask

  task automatic check_big(input [8*8-1:0] fase);
    begin
      $display("-- chequeo %0s --", fase);
      expect_reg(1,  32'd11, "x1 addi 11");
      expect_reg(2,  32'd128, "x2 base");
      expect_reg(3,  32'd11, "x3 addi 11 (reusa x3)");
      expect_reg(4,  32'd14, "x4 load-use dist1 (beq la saltea el 55)");
      expect_reg(5,  32'd66, "x5 tras beq tomado por forwarding ALU");
      expect_reg(6,  32'd7,  "x6 lw");
      expect_reg(7,  32'd14, "x7 load-use dist2");
      expect_reg(8,  32'd7,  "x8 lw");
      expect_reg(9,  32'd14, "x9 load-use dist3");
      expect_reg(10, 32'd7,  "x10 lw antes de beq");
      expect_reg(11, 32'd7,  "x11 addi 7");
      expect_reg(12, 32'd0,  "x12 salteado por beq tomado (load->beq)");
      expect_reg(13, 32'd1,  "x13 tras beq tomado");
      expect_reg(14, 32'd7,  "x14 lw antes de bne");
      expect_reg(15, 32'd2,  "x15 bne no tomado (load->bne)");
      expect_reg(16, 32'd3,  "x16 siguiente a bne");
      expect_reg(17, 32'd128, "x17 puntero cargado");
      expect_reg(18, 32'd7,  "x18 lw con direccion de un load");
      expect_reg(19, 32'd5,  "x19 lw");
      expect_reg(20, 32'd5,  "x20 lw de lo guardado (store dato=load)");
      expect_reg(21, 32'd144, "x21 destino jalr");
      expect_reg(22, 32'd144, "x22 lw del destino");
      expect_reg(23, 32'd136, "x23 link de jalr (pc+4)");
      expect_reg(24, 32'd0,  "x24 salteado por jalr (load->jalr)");
      expect_reg(25, 32'd9,  "x25 en el destino de jalr");
      expect_reg(26, 32'd7,  "x26 lw");
      expect_reg(27, 32'd14, "x27 add sobre load");
      expect_reg(28, 32'd21, "x28 add sobre ALU y load");
      expect_reg(29, 32'd3,  "x29 addi 3");
      expect_reg(30, 32'd4,  "x30 forward EX/MEM");
      expect_reg(31, 32'd7,  "x31 forward EX/MEM + MEM/WB");
      expect_word(32, 32'd7,   "mem[128]");
      expect_word(33, 32'd5,   "mem[132]");
      expect_word(34, 32'd128, "mem[136]");
      expect_word(35, 32'd5,   "mem[140] (store dato=load)");
      expect_word(36, 32'd144, "mem[144]");
    end
  endtask

  initial begin
    stall_cnt = 0; prog_len = 0; random_mode = 0;
    rst = 1; enable = 1;

    // ---------------- PARTE 1: programa largo ----------------
    prog[0]  = itype(12'd128, 5'd0, 3'b000, 5'd2, `OP_IMM);       // addi x2,x0,128
    prog[1]  = itype(12'd7,   5'd0, 3'b000, 5'd1, `OP_IMM);       // addi x1,x0,7
    prog[2]  = stype(12'd0,   5'd1, 5'd2, 3'b010, `OP_STORE);     // sw x1,0(x2)    mem[128]=7
    prog[3]  = itype(12'd5,   5'd0, 3'b000, 5'd5, `OP_IMM);       // addi x5,x0,5
    prog[4]  = stype(12'd4,   5'd5, 5'd2, 3'b010, `OP_STORE);     // sw x5,4(x2)    mem[132]=5
    prog[5]  = stype(12'd8,   5'd2, 5'd2, 3'b010, `OP_STORE);     // sw x2,8(x2)    mem[136]=128
    // dist 1
    prog[6]  = itype(12'd0,   5'd2, 3'b010, 5'd3, `OP_LOAD);      // lw x3,0(x2)
    prog[7]  = rtype(7'b0, 5'd3, 5'd3, 3'b000, 5'd4, `OP_R);      // add x4,x3,x3   -> 14
    // dist 2
    prog[8]  = itype(12'd0,   5'd2, 3'b010, 5'd6, `OP_LOAD);      // lw x6,0(x2)
    prog[9]  = NOP;
    prog[10] = rtype(7'b0, 5'd6, 5'd6, 3'b000, 5'd7, `OP_R);      // add x7,x6,x6   -> 14
    // dist 3
    prog[11] = itype(12'd0,   5'd2, 3'b010, 5'd8, `OP_LOAD);      // lw x8,0(x2)
    prog[12] = NOP;
    prog[13] = NOP;
    prog[14] = rtype(7'b0, 5'd8, 5'd8, 3'b000, 5'd9, `OP_R);      // add x9,x8,x8   -> 14
    // load -> beq tomado (comparador con dato de load)
    prog[15] = itype(12'd7,   5'd0, 3'b000, 5'd11, `OP_IMM);      // addi x11,x0,7
    prog[16] = itype(12'd0,   5'd2, 3'b010, 5'd10, `OP_LOAD);     // lw x10,0(x2)
    prog[17] = btype(13'd8,   5'd11, 5'd10, 3'b000);              // beq x10,x11,+8
    prog[18] = itype(12'd99,  5'd0, 3'b000, 5'd12, `OP_IMM);      // addi x12,x0,99 (salteado)
    prog[19] = itype(12'd1,   5'd0, 3'b000, 5'd13, `OP_IMM);      // addi x13,x0,1
    // load -> bne no tomado
    prog[20] = itype(12'd0,   5'd2, 3'b010, 5'd14, `OP_LOAD);     // lw x14,0(x2)
    prog[21] = btype(13'd8,   5'd11, 5'd14, 3'b001);              // bne x14,x11,+8 (iguales: no toma)
    prog[22] = itype(12'd2,   5'd0, 3'b000, 5'd15, `OP_IMM);      // addi x15,x0,2
    prog[23] = itype(12'd3,   5'd0, 3'b000, 5'd16, `OP_IMM);      // addi x16,x0,3
    // load -> load (puntero)
    prog[24] = itype(12'd8,   5'd2, 3'b010, 5'd17, `OP_LOAD);     // lw x17,8(x2)   = 128
    prog[25] = itype(12'd0,   5'd17, 3'b010, 5'd18, `OP_LOAD);    // lw x18,0(x17)  = 7
    // load -> sw (dato) -> lw
    prog[26] = itype(12'd4,   5'd2, 3'b010, 5'd19, `OP_LOAD);     // lw x19,4(x2)   = 5
    prog[27] = stype(12'd12,  5'd19, 5'd2, 3'b010, `OP_STORE);    // sw x19,12(x2)  mem[140]=5
    prog[28] = itype(12'd12,  5'd2, 3'b010, 5'd20, `OP_LOAD);     // lw x20,12(x2)  = 5
    // load -> jalr
    prog[29] = NOP;
    prog[30] = itype(12'd144, 5'd0, 3'b000, 5'd21, `OP_IMM);      // addi x21,x0,144
    prog[31] = stype(12'd16,  5'd21, 5'd2, 3'b010, `OP_STORE);    // sw x21,16(x2)  mem[144]=144
    prog[32] = itype(12'd16,  5'd2, 3'b010, 5'd22, `OP_LOAD);     // lw x22,16(x2)  = 144
    prog[33] = itype(12'd0,   5'd22, 3'b000, 5'd23, `OP_JALR);    // jalr x23,0(x22) -> pc=144, x23=136
    prog[34] = itype(12'd77,  5'd0, 3'b000, 5'd24, `OP_IMM);      // (salteado)
    prog[35] = itype(12'd78,  5'd0, 3'b000, 5'd24, `OP_IMM);      // (salteado)
    prog[36] = itype(12'd9,   5'd0, 3'b000, 5'd25, `OP_IMM);      // addi x25,x0,9  (destino)
    // load + ALU encadenado
    prog[37] = itype(12'd0,   5'd2, 3'b010, 5'd26, `OP_LOAD);     // lw x26,0(x2)
    prog[38] = rtype(7'b0, 5'd26, 5'd26, 3'b000, 5'd27, `OP_R);   // add x27,x26,x26 = 14
    prog[39] = rtype(7'b0, 5'd26, 5'd27, 3'b000, 5'd28, `OP_R);   // add x28,x27,x26 = 21
    // forwarding de ALU (no load) a ALU y a comparador
    prog[40] = itype(12'd3,   5'd0, 3'b000, 5'd29, `OP_IMM);      // addi x29,x0,3
    prog[41] = itype(12'd1,   5'd29, 3'b000, 5'd30, `OP_IMM);     // addi x30,x29,1 = 4
    prog[42] = rtype(7'b0, 5'd30, 5'd29, 3'b000, 5'd31, `OP_R);   // add x31,x29,x30 = 7
    prog[43] = itype(12'd11,  5'd0, 3'b000, 5'd1, `OP_IMM);       // addi x1,x0,11
    prog[44] = itype(12'd11,  5'd0, 3'b000, 5'd3, `OP_IMM);       // addi x3,x0,11
    prog[45] = btype(13'd8,   5'd3, 5'd1, 3'b000);                // beq x1,x3,+8  (x3 por EX/MEM, x1 por MEM/WB)
    prog[46] = itype(12'd55,  5'd0, 3'b000, 5'd4, `OP_IMM);       // addi x4,x0,55 (salteado)
    prog[47] = itype(12'd66,  5'd0, 3'b000, 5'd5, `OP_IMM);       // addi x5,x0,66
    load_prog(48);

    reset_start(32'd0);
    run_until_halt(3000, 1'b0);
    check_big("FASE A");

    reset_start(32'd0);
    run_until_halt(12000, 1'b1);
    check_big("FASE B");

    // ---------------- PARTE 2: ciclos de stall por distancia ----------------
    // dist 1: lw seguido de su uso
    prog[0] = itype(12'd128, 5'd0, 3'b000, 5'd2, `OP_IMM);        // addi x2,x0,128
    prog[1] = itype(12'd0,   5'd2, 3'b010, 5'd3, `OP_LOAD);       // lw x3,0(x2)  (mem[128]=7)
    prog[2] = rtype(7'b0, 5'd3, 5'd3, 3'b000, 5'd4, `OP_R);       // add x4,x3,x3
    load_prog(3);
    reset_start(32'd7);
    run_until_halt(200, 1'b0);
    expect_reg(4, 32'd14, "dist1 resultado");
    checks = checks + 1;
    if (stall_cnt !== 2) begin errors = errors + 1; $display("ERROR: dist1 stalls=%0d (esperado 2)", stall_cnt); end

    // dist 2
    prog[0] = itype(12'd128, 5'd0, 3'b000, 5'd2, `OP_IMM);
    prog[1] = itype(12'd0,   5'd2, 3'b010, 5'd3, `OP_LOAD);
    prog[2] = NOP;
    prog[3] = rtype(7'b0, 5'd3, 5'd3, 3'b000, 5'd4, `OP_R);
    load_prog(4);
    reset_start(32'd7);
    run_until_halt(200, 1'b0);
    expect_reg(4, 32'd14, "dist2 resultado");
    checks = checks + 1;
    if (stall_cnt !== 1) begin errors = errors + 1; $display("ERROR: dist2 stalls=%0d (esperado 1)", stall_cnt); end

    // dist 3
    prog[0] = itype(12'd128, 5'd0, 3'b000, 5'd2, `OP_IMM);
    prog[1] = itype(12'd0,   5'd2, 3'b010, 5'd3, `OP_LOAD);
    prog[2] = NOP;
    prog[3] = NOP;
    prog[4] = rtype(7'b0, 5'd3, 5'd3, 3'b000, 5'd4, `OP_R);
    load_prog(5);
    reset_start(32'd7);
    run_until_halt(200, 1'b0);
    expect_reg(4, 32'd14, "dist3 resultado");
    checks = checks + 1;
    if (stall_cnt !== 0) begin errors = errors + 1; $display("ERROR: dist3 stalls=%0d (esperado 0)", stall_cnt); end

    // sin dependencia con load: 0 stalls
    prog[0] = itype(12'd128, 5'd0, 3'b000, 5'd2, `OP_IMM);
    prog[1] = itype(12'd0,   5'd2, 3'b010, 5'd3, `OP_LOAD);
    prog[2] = rtype(7'b0, 5'd2, 5'd2, 3'b000, 5'd4, `OP_R);       // add x4,x2,x2 (no usa x3)
    load_prog(3);
    reset_start(32'd7);
    run_until_halt(200, 1'b0);
    expect_reg(4, 32'd256, "sin dependencia resultado");
    checks = checks + 1;
    if (stall_cnt !== 0) begin errors = errors + 1; $display("ERROR: sin dependencia stalls=%0d (esperado 0)", stall_cnt); end

    if (errors == 0)
      $display("PIPELINE_HAZARDS_TB: %0d/%0d checks OK", checks, checks);
    else
      $display("PIPELINE_HAZARDS_TB: %0d errores en %0d checks", errors, checks);
    $finish;
  end

endmodule