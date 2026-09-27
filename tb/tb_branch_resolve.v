module tb_branch_resolve;

  reg  [31:0] pc, imm, rs1_data;
  wire [31:0] redirect_pc;
  reg         alu_zero;
  wire        redirect;
  reg  [2:0]  funct3;
  reg         branch, jump, jalr;

  integer errors = 0;
  integer checks = 0;

  branch_resolve dut (
      .pc(pc), .imm(imm), .rs1_data(rs1_data), .alu_zero(alu_zero),
      .funct3(funct3), .branch(branch), .jump(jump), .jalr(jalr),
      .redirect(redirect), .redirect_pc(redirect_pc)
  );

  task automatic expect_redirect(input exp_redirect, input [31:0] exp_pc, input [8*64-1:0] name);
    begin
      #1;
      checks = checks + 1;
      if (redirect !== exp_redirect) begin
        errors = errors + 1;
        $display("ERROR: [%0s] redirect=%0b (esperado %0b)", name, redirect, exp_redirect);
      end
      if (exp_redirect) begin
        checks = checks + 1;
        if (redirect_pc !== exp_pc) begin
          errors = errors + 1;
          $display("ERROR: [%0s] redirect_pc=%0d (esperado %0d)", name, redirect_pc, exp_pc);
        end
      end
    end
  endtask

  initial begin
    branch = 0; jump = 0; jalr = 0;
    rs1_data = 32'd0;

    // --- sin branch ni jump: no hay redirect ---
    pc = 32'd100; imm = 32'd16; funct3 = 3'b000; alu_zero = 1'b0;
    branch = 0; jump = 0; jalr = 0;
    expect_redirect(1'b0, 32'd0, "sin branch/jump - no redirige");

    // --- beq tomado (alu_zero=1, funct3=000) ---
    branch = 1; funct3 = 3'b000; alu_zero = 1'b1;
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

    branch = 0;

    // --- jal: pc+imm, sin importar alu_zero ---
    jump = 1; jalr = 0; funct3 = 3'b000; alu_zero = 1'b0;
    expect_redirect(1'b1, 32'd116, "jal - pc+imm");

    // --- jalr: rs1+imm con bit0 forzado a 0 ---
    jump = 1; jalr = 1;
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
