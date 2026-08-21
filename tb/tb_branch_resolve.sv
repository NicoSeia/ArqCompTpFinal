module tb_branch_resolve;

  import riscv_pkg::*;

  logic [31:0] pc, imm, rs1_data, redirect_pc;
  logic        alu_zero, redirect;
  logic [2:0]  funct3;
  ctrl_t       ctrl;

  int errors = 0;
  int checks = 0;

  branch_resolve dut (
      .pc(pc), .imm(imm), .rs1_data(rs1_data), .alu_zero(alu_zero),
      .funct3(funct3), .ctrl(ctrl), .redirect(redirect), .redirect_pc(redirect_pc)
  );

  task automatic expect_redirect(input logic exp_redirect, input logic [31:0] exp_pc, input string name);
    #1;
    checks++;
    if (redirect !== exp_redirect) begin
      errors++;
      $error("[%s] redirect=%0b (esperado %0b)", name, redirect, exp_redirect);
    end
    if (exp_redirect) begin
      checks++;
      if (redirect_pc !== exp_pc) begin
        errors++;
        $error("[%s] redirect_pc=%0d (esperado %0d)", name, redirect_pc, exp_pc);
      end
    end
  endtask

  initial begin
    ctrl = '0;
    rs1_data = '0;

    // --- sin branch ni jump: no hay redirect ---
    pc = 32'd100; imm = 32'd16; funct3 = 3'b000; alu_zero = 1'b0;
    ctrl.branch = 0; ctrl.jump = 0; ctrl.jalr = 0;
    expect_redirect(1'b0, 32'd0, "sin branch/jump - no redirige");

    // --- beq tomado (alu_zero=1, funct3=000) ---
    ctrl.branch = 1; funct3 = 3'b000; alu_zero = 1'b1;
    expect_redirect(1'b1, 32'd116, "beq tomado - pc+imm");  // 100+16

    // --- beq no tomado (alu_zero=0, funct3=000) ---
    alu_zero = 1'b0;
    expect_redirect(1'b0, 32'd0, "beq no tomado - no redirige");

    // --- bne tomado (alu_zero=0, funct3=001) ---
    funct3 = 3'b001; alu_zero = 1'b0;
    expect_redirect(1'b1, 32'd116, "bne tomado - pc+imm");

    // --- bne no tomado (alu_zero=1, funct3=001) ---
    alu_zero = 1'b1;
    expect_redirect(1'b0, 32'd0, "bne no tomado - no redirige");

    ctrl.branch = 0;

    // --- jal: pc+imm, sin importar alu_zero ---
    ctrl.jump = 1; ctrl.jalr = 0; funct3 = 3'b000; alu_zero = 1'b0;
    expect_redirect(1'b1, 32'd116, "jal - pc+imm");

    // --- jalr: rs1+imm con bit0 forzado a 0 ---
    ctrl.jump = 1; ctrl.jalr = 1;
    rs1_data = 32'd41; imm = 32'd0;  // 41+0=41 (impar) -> debe limpiarse a 40
    expect_redirect(1'b1, 32'd40, "jalr - rs1+imm con bit0 limpio");

    rs1_data = 32'd40; imm = 32'd4;  // 40+4=44 (ya par) -> se mantiene
    expect_redirect(1'b1, 32'd44, "jalr - rs1+imm ya alineado");

    if (errors == 0)
      $display("BRANCH_RESOLVE_TB: %0d/%0d checks OK", checks, checks);
    else
      $display("BRANCH_RESOLVE_TB: %0d errores en %0d checks", errors, checks);

    $finish;
  end

endmodule