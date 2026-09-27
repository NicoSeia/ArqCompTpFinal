`include "riscv_defs.vh"
module tb_control_unit;

  reg  [6:0] opcode;
  reg  [2:0] funct3;
  reg  [6:0] funct7;

  wire        reg_write, mem_read, mem_write, alu_src;
  wire        branch, jump, jalr, mem_unsigned;
  wire [1:0]  wb_src, mem_size;
  wire [3:0]  alu_op;
  wire [2:0]  imm_src;
  wire        illegal;

  integer errors = 0;
  integer checks = 0;

  control_unit dut (
      .opcode(opcode), .funct3(funct3), .funct7(funct7),
      .reg_write(reg_write), .mem_read(mem_read), .mem_write(mem_write),
      .wb_src(wb_src), .alu_src(alu_src),
      .branch(branch), .jump(jump), .jalr(jalr), .mem_unsigned(mem_unsigned),
      .alu_op(alu_op), .mem_size(mem_size), .imm_src(imm_src),
      .illegal(illegal)
  );

  // El vector de control esperado se arma campo por campo, uno por señal
  // (antes era un unico vector [`CTRL_W-1:0] armado con `define de rango;
  // ahora cada campo es su propio puerto, asi que tambien es su propio reg).
  reg        e_reg_write, e_mem_read, e_mem_write, e_alu_src;
  reg        e_branch, e_jump, e_jalr, e_mem_unsigned;
  reg [1:0]  e_wb_src, e_mem_size;
  reg [3:0]  e_alu_op;
  reg [2:0]  e_imm_src;

  task automatic set_ctrl(
      input rw, input mr, input mw, input [`WB_SRC_W-1:0] wbs, input as,
      input br, input jp, input jr, input mu,
      input [`ALU_OP_W-1:0] aop, input [`MEM_SIZE_W-1:0] ms, input [`IMM_SRC_W-1:0] isrc
  );
    begin
      e_reg_write = rw; e_mem_read = mr; e_mem_write = mw;
      e_wb_src = wbs; e_alu_src = as;
      e_branch = br; e_jump = jp; e_jalr = jr; e_mem_unsigned = mu;
      e_alu_op = aop; e_mem_size = ms; e_imm_src = isrc;
    end
  endtask

  task automatic check(
      input [6:0] op_i, input [2:0] f3_i, input [6:0] f7_i, input [8*64-1:0] name
  );
    begin
      opcode = op_i; funct3 = f3_i; funct7 = f7_i;
      #1;
      checks = checks + 1;
      if (reg_write !== e_reg_write || mem_read !== e_mem_read || mem_write !== e_mem_write ||
          wb_src !== e_wb_src || alu_src !== e_alu_src || branch !== e_branch ||
          jump !== e_jump || jalr !== e_jalr || mem_unsigned !== e_mem_unsigned ||
          alu_op !== e_alu_op || mem_size !== e_mem_size || imm_src !== e_imm_src) begin
        errors = errors + 1;
        $display("ERROR: [%0s] ctrl no coincide (illegal=%0b) got={rw=%0b mr=%0b mw=%0b wbs=%0d as=%0b br=%0b jp=%0b jr=%0b mu=%0b aop=%0d ms=%0d isrc=%0d} esperado={rw=%0b mr=%0b mw=%0b wbs=%0d as=%0b br=%0b jp=%0b jr=%0b mu=%0b aop=%0d ms=%0d isrc=%0d}",
                 name, illegal,
                 reg_write, mem_read, mem_write, wb_src, alu_src, branch, jump, jalr, mem_unsigned, alu_op, mem_size, imm_src,
                 e_reg_write, e_mem_read, e_mem_write, e_wb_src, e_alu_src, e_branch, e_jump, e_jalr, e_mem_unsigned, e_alu_op, e_mem_size, e_imm_src);
      end
      checks = checks + 1;
      if (illegal !== 1'b0) begin
        errors = errors + 1;
        $display("ERROR: [%0s] illegal=1 pero deberia ser una instruccion valida", name);
      end
    end
  endtask

  task automatic check_illegal(input [6:0] op_i, input [2:0] f3_i, input [6:0] f7_i, input [8*64-1:0] name);
    begin
      opcode = op_i; funct3 = f3_i; funct7 = f7_i;
      #1;
      checks = checks + 1;
      if (illegal !== 1'b1) begin
        errors = errors + 1;
        $display("ERROR: [%0s] illegal=%0b (esperado 1)", name, illegal);
      end
    end
  endtask

  initial begin
    // ================= R-type =================
    set_ctrl(1,0,0,`WB_ALU,0, 0,0,0,0, `ALU_ADD, `MEM_WORD, `IMM_X);
    check(`OP_R, 3'b000, 7'b0000000, "add");

    e_alu_op = `ALU_SUB;
    check(`OP_R, 3'b000, 7'b0100000, "sub");

    e_alu_op = `ALU_SLL;
    check(`OP_R, 3'b001, 7'b0000000, "sll");

    e_alu_op = `ALU_SLT;
    check(`OP_R, 3'b010, 7'b0000000, "slt");

    e_alu_op = `ALU_SLTU;
    check(`OP_R, 3'b011, 7'b0000000, "sltu");

    e_alu_op = `ALU_XOR;
    check(`OP_R, 3'b100, 7'b0000000, "xor");

    e_alu_op = `ALU_SRL;
    check(`OP_R, 3'b101, 7'b0000000, "srl");

    e_alu_op = `ALU_SRA;
    check(`OP_R, 3'b101, 7'b0100000, "sra");

    e_alu_op = `ALU_OR;
    check(`OP_R, 3'b110, 7'b0000000, "or");

    e_alu_op = `ALU_AND;
    check(`OP_R, 3'b111, 7'b0000000, "and");

    // ================= I-type ALU inmediato =================
    set_ctrl(1,0,0,`WB_ALU,1, 0,0,0,0, `ALU_ADD, `MEM_WORD, `IMM_I);
    check(`OP_IMM, 3'b000, 7'b0, "addi");

    e_alu_op = `ALU_SLL;
    check(`OP_IMM, 3'b001, 7'b0, "slli");

    e_alu_op = `ALU_SLT;
    check(`OP_IMM, 3'b010, 7'b0, "slti");

    e_alu_op = `ALU_SLTU;
    check(`OP_IMM, 3'b011, 7'b0, "sltiu");

    e_alu_op = `ALU_XOR;
    check(`OP_IMM, 3'b100, 7'b0, "xori");

    e_alu_op = `ALU_SRL;
    check(`OP_IMM, 3'b101, 7'b0000000, "srli");

    e_alu_op = `ALU_SRA;
    check(`OP_IMM, 3'b101, 7'b0100000, "srai");

    e_alu_op = `ALU_OR;
    check(`OP_IMM, 3'b110, 7'b0, "ori");

    e_alu_op = `ALU_AND;
    check(`OP_IMM, 3'b111, 7'b0, "andi");

    // ================= Loads =================
    set_ctrl(1,1,0,`WB_MEM,1, 0,0,0,0, `ALU_ADD, `MEM_BYTE, `IMM_I);
    check(`OP_LOAD, 3'b000, 7'b0, "lb");

    e_mem_size = `MEM_HALF;
    check(`OP_LOAD, 3'b001, 7'b0, "lh");

    e_mem_size = `MEM_WORD;
    check(`OP_LOAD, 3'b010, 7'b0, "lw");

    e_mem_size = `MEM_BYTE; e_mem_unsigned = 1;
    check(`OP_LOAD, 3'b100, 7'b0, "lbu");

    e_mem_size = `MEM_HALF;
    check(`OP_LOAD, 3'b101, 7'b0, "lhu");

    // ================= Stores =================
    set_ctrl(0,0,1,`WB_ALU,1, 0,0,0,0, `ALU_ADD, `MEM_BYTE, `IMM_S);
    check(`OP_STORE, 3'b000, 7'b0, "sb");

    e_mem_size = `MEM_HALF;
    check(`OP_STORE, 3'b001, 7'b0, "sh");

    e_mem_size = `MEM_WORD;
    check(`OP_STORE, 3'b010, 7'b0, "sw");

    // ================= Branches =================
    set_ctrl(0,0,0,`WB_ALU,0, 1,0,0,0, `ALU_SUB, `MEM_WORD, `IMM_B);
    check(`OP_BRANCH, 3'b000, 7'b0, "beq");
    check(`OP_BRANCH, 3'b001, 7'b0, "bne");

    // ================= Lui =================
    set_ctrl(1,0,0,`WB_ALU,1, 0,0,0,0, `ALU_PASS, `MEM_WORD, `IMM_U);
    check(`OP_LUI, 3'b000, 7'b0, "lui");

    // ================= Jal =================
    set_ctrl(1,0,0,`WB_PC4,0, 0,1,0,0, `ALU_ADD, `MEM_WORD, `IMM_J);
    check(`OP_JAL, 3'b000, 7'b0, "jal");

    // ================= Jalr =================
    set_ctrl(1,0,0,`WB_PC4,0, 0,1,1,0, `ALU_ADD, `MEM_WORD, `IMM_I);
    check(`OP_JALR, 3'b000, 7'b0, "jalr");

    // ================= Encodings ilegales =================
    check_illegal(7'b1111111, 3'b000, 7'b0, "opcode inexistente");
    check_illegal(`OP_LOAD, 3'b011, 7'b0, "load con funct3 sin definir");
    check_illegal(`OP_BRANCH, 3'b010, 7'b0, "branch con funct3 sin definir (ni beq ni bne)");

    if (errors == 0)
      $display("CONTROL_UNIT_TB: %0d/%0d checks OK", checks, checks);
    else
      $display("CONTROL_UNIT_TB: %0d errores en %0d checks", errors, checks);

    $finish;
  end

endmodule
