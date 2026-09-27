module tb_next_pc_logic;

  reg  [31:0] pc, imm, rs1_data;
  wire [31:0] pc_next, pc_plus4;
  reg         alu_zero;
  reg  [2:0]  funct3;
  reg         branch, jump, jalr;

  integer errors = 0;
  integer checks = 0;

  next_pc_logic dut (
      .pc(pc), .imm(imm), .rs1_data(rs1_data), .alu_zero(alu_zero),
      .funct3(funct3), .branch(branch), .jump(jump), .jalr(jalr),
      .pc_next(pc_next), .pc_plus4(pc_plus4)
  );

  task automatic expect_next(input [31:0] expected, input [8*64-1:0] name);
    begin
      #1;
      checks = checks + 1;
      if (pc_next !== expected) begin
        errors = errors + 1;
        $display("ERROR: [%0s] pc_next=%0d (esperado %0d)", name, pc_next, expected);
      end
    end
  endtask

  initial begin
    branch = 0; jump = 0; jalr = 0;
    rs1_data = 32'd0;

    // --- sin branch ni jump: PC+4 ---
    pc = 32'd100; imm = 32'd16; funct3 = 3'b000; alu_zero = 1'b0;
    branch = 0; jump = 0; jalr = 0;
    expect_next(32'd104, "sin branch/jump - PC+4");

    checks = checks + 1;
    if (pc_plus4 !== 32'd104) begin
      errors = errors + 1;
      $display("ERROR: pc_plus4=%0d (esperado 104)", pc_plus4);
    end

    // --- beq tomado (alu_zero=1, funct3=000) ---
    branch = 1; funct3 = 3'b000; alu_zero = 1'b1;
    expect_next(32'd116, "beq tomado - pc+imm");  // 100+16

    // --- beq no tomado (alu_zero=0, funct3=000) ---
    alu_zero = 1'b0;
    expect_next(32'd104, "beq no tomado - PC+4");

    // --- bne tomado (alu_zero=0, funct3=001) ---
    funct3 = 3'b001; alu_zero = 1'b0;
    expect_next(32'd116, "bne tomado - pc+imm");

    // --- bne no tomado (alu_zero=1, funct3=001) ---
    alu_zero = 1'b1;
    expect_next(32'd104, "bne no tomado - PC+4");

    branch = 0;

    // --- jal: pc+imm, sin importar alu_zero ---
    jump = 1; jalr = 0; funct3 = 3'b000; alu_zero = 1'b0;
    expect_next(32'd116, "jal - pc+imm");

    // --- jalr: rs1+imm con bit0 forzado a 0 ---
    jump = 1; jalr = 1;
    rs1_data = 32'd41; imm = 32'd0;  // 41+0=41 (impar) -> debe limpiarse a 40
    expect_next(32'd40, "jalr - rs1+imm con bit0 limpio");

    rs1_data = 32'd40; imm = 32'd4;  // 40+4=44 (ya par) -> se mantiene
    expect_next(32'd44, "jalr - rs1+imm ya alineado");

    if (errors == 0)
      $display("NEXT_PC_TB: %0d/%0d checks OK", checks, checks);
    else
      $display("NEXT_PC_TB: %0d errores en %0d checks", errors, checks);

    $finish;
  end

endmodule
