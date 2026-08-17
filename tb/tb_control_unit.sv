module tb_control_unit;

  import riscv_pkg::*;

  logic [6:0] opcode;
  logic [2:0] funct3;
  logic [6:0] funct7;
  ctrl_t      ctrl;
  logic       illegal;

  int errors = 0;
  int checks = 0;

  control_unit dut (.opcode(opcode), .funct3(funct3), .funct7(funct7), .ctrl(ctrl), .illegal(illegal));

  // Nota: Icarus no soporta los assignment patterns con nombre de campo
  // ('{campo:valor}) para structs, asi que el struct esperado se arma
  // campo por campo con esta task.
  task automatic set_ctrl(
      output ctrl_t c,
      input logic rw, input logic mr, input logic mw, input wb_src_e wbs, input logic as,
      input logic br, input logic jp, input logic jr, input logic mu,
      input alu_op_e aop, input mem_size_e ms, input imm_src_e isrc
  );
    c.reg_write = rw; c.mem_read = mr; c.mem_write = mw; c.wb_src = wbs; c.alu_src = as;
    c.branch = br; c.jump = jp; c.jalr = jr; c.mem_unsigned = mu;
    c.alu_op = aop; c.mem_size = ms; c.imm_src = isrc;
  endtask

  task automatic check(
      input logic [6:0] op_i, input logic [2:0] f3_i, input logic [6:0] f7_i,
      input ctrl_t exp_ctrl, input string name
  );
    opcode = op_i; funct3 = f3_i; funct7 = f7_i;
    #1;
    checks++;
    if (ctrl !== exp_ctrl) begin
      errors++;
      $error("[%s] ctrl no coincide (illegal=%0b)", name, illegal);
    end
    checks++;
    if (illegal !== 1'b0) begin
      errors++;
      $error("[%s] illegal=1 pero deberia ser una instruccion valida", name);
    end
  endtask

  task automatic check_illegal(input logic [6:0] op_i, input logic [2:0] f3_i, input logic [6:0] f7_i, input string name);
    opcode = op_i; funct3 = f3_i; funct7 = f7_i;
    #1;
    checks++;
    if (illegal !== 1'b1) begin
      errors++;
      $error("[%s] illegal=%0b (esperado 1)", name, illegal);
    end
  endtask

  ctrl_t e;

  initial begin
    // ================= R-type =================
    set_ctrl(e, 1,0,0,WB_ALU,0, 0,0,0,0, ALU_ADD, MEM_WORD, IMM_X);
    check(OP_R, 3'b000, 7'b0000000, e, "add");

    e.alu_op = ALU_SUB;
    check(OP_R, 3'b000, 7'b0100000, e, "sub");

    e.alu_op = ALU_SLL;
    check(OP_R, 3'b001, 7'b0000000, e, "sll");

    e.alu_op = ALU_SLT;
    check(OP_R, 3'b010, 7'b0000000, e, "slt");

    e.alu_op = ALU_SLTU;
    check(OP_R, 3'b011, 7'b0000000, e, "sltu");

    e.alu_op = ALU_XOR;
    check(OP_R, 3'b100, 7'b0000000, e, "xor");

    e.alu_op = ALU_SRL;
    check(OP_R, 3'b101, 7'b0000000, e, "srl");

    e.alu_op = ALU_SRA;
    check(OP_R, 3'b101, 7'b0100000, e, "sra");

    e.alu_op = ALU_OR;
    check(OP_R, 3'b110, 7'b0000000, e, "or");

    e.alu_op = ALU_AND;
    check(OP_R, 3'b111, 7'b0000000, e, "and");

    // ================= I-type ALU inmediato =================
    set_ctrl(e, 1,0,0,WB_ALU,1, 0,0,0,0, ALU_ADD, MEM_WORD, IMM_I);
    check(OP_IMM, 3'b000, 7'b0, e, "addi");

    e.alu_op = ALU_SLL;
    check(OP_IMM, 3'b001, 7'b0, e, "slli");

    e.alu_op = ALU_SLT;
    check(OP_IMM, 3'b010, 7'b0, e, "slti");

    e.alu_op = ALU_SLTU;
    check(OP_IMM, 3'b011, 7'b0, e, "sltiu");

    e.alu_op = ALU_XOR;
    check(OP_IMM, 3'b100, 7'b0, e, "xori");

    e.alu_op = ALU_SRL;
    check(OP_IMM, 3'b101, 7'b0000000, e, "srli");

    e.alu_op = ALU_SRA;
    check(OP_IMM, 3'b101, 7'b0100000, e, "srai");

    e.alu_op = ALU_OR;
    check(OP_IMM, 3'b110, 7'b0, e, "ori");

    e.alu_op = ALU_AND;
    check(OP_IMM, 3'b111, 7'b0, e, "andi");

    // ================= Loads =================
    set_ctrl(e, 1,1,0,WB_MEM,1, 0,0,0,0, ALU_ADD, MEM_BYTE, IMM_I);
    check(OP_LOAD, 3'b000, 7'b0, e, "lb");

    e.mem_size = MEM_HALF;
    check(OP_LOAD, 3'b001, 7'b0, e, "lh");

    e.mem_size = MEM_WORD;
    check(OP_LOAD, 3'b010, 7'b0, e, "lw");

    e.mem_size = MEM_BYTE; e.mem_unsigned = 1;
    check(OP_LOAD, 3'b100, 7'b0, e, "lbu");

    e.mem_size = MEM_HALF;
    check(OP_LOAD, 3'b101, 7'b0, e, "lhu");

    // ================= Stores =================
    set_ctrl(e, 0,0,1,WB_ALU,1, 0,0,0,0, ALU_ADD, MEM_BYTE, IMM_S);
    check(OP_STORE, 3'b000, 7'b0, e, "sb");

    e.mem_size = MEM_HALF;
    check(OP_STORE, 3'b001, 7'b0, e, "sh");

    e.mem_size = MEM_WORD;
    check(OP_STORE, 3'b010, 7'b0, e, "sw");

    // ================= Branches =================
    set_ctrl(e, 0,0,0,WB_ALU,0, 1,0,0,0, ALU_SUB, MEM_WORD, IMM_B);
    check(OP_BRANCH, 3'b000, 7'b0, e, "beq");
    check(OP_BRANCH, 3'b001, 7'b0, e, "bne");

    // ================= Lui =================
    set_ctrl(e, 1,0,0,WB_ALU,1, 0,0,0,0, ALU_PASS, MEM_WORD, IMM_U);
    check(OP_LUI, 3'b000, 7'b0, e, "lui");

    // ================= Jal =================
    set_ctrl(e, 1,0,0,WB_PC4,0, 0,1,0,0, ALU_ADD, MEM_WORD, IMM_J);
    check(OP_JAL, 3'b000, 7'b0, e, "jal");

    // ================= Jalr =================
    set_ctrl(e, 1,0,0,WB_PC4,0, 0,1,1,0, ALU_ADD, MEM_WORD, IMM_I);
    check(OP_JALR, 3'b000, 7'b0, e, "jalr");

    // ================= Encodings ilegales =================
    check_illegal(7'b1111111, 3'b000, 7'b0, "opcode inexistente");
    check_illegal(OP_LOAD, 3'b011, 7'b0, "load con funct3 sin definir");
    check_illegal(OP_BRANCH, 3'b010, 7'b0, "branch con funct3 sin definir (ni beq ni bne)");

    if (errors == 0)
      $display("CONTROL_UNIT_TB: %0d/%0d checks OK", checks, checks);
    else
      $display("CONTROL_UNIT_TB: %0d errores en %0d checks", errors, checks);

    $finish;
  end

endmodule