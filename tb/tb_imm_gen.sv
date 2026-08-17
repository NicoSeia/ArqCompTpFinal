module tb_imm_gen;

  import riscv_pkg::*;

  logic [31:0] instr;
  imm_src_e     imm_src;
  logic [31:0] imm;

  int errors = 0;
  int checks = 0;

  imm_gen dut (.instr(instr), .imm_src(imm_src), .imm(imm));

  task automatic check(input logic [31:0] instr_i, input imm_src_e src_i, input logic [31:0] expected, input string name);
    instr = instr_i; imm_src = src_i;
    #1;
    checks++;
    if (imm !== expected) begin
      errors++;
      $error("[%s] imm=%08h (esperado %08h)", name, imm, expected);
    end
  endtask

  initial begin
    // --- I-type: addi x1, x2, -5 ---
    check({12'hFFB, 5'd2, 3'b000, 5'd1, 7'b0010011}, IMM_I, 32'hFFFFFFFB, "I-type negativo (-5)");

    // --- S-type: sw x5, 8(x10) ---
    check({7'b0000000, 5'd5, 5'd10, 3'b010, 5'b01000, 7'b0100011}, IMM_S, 32'd8, "S-type positivo (8)");

    // --- S-type: sw x3, -4(x1) ---
    check({7'b1111111, 5'd3, 5'd1, 3'b010, 5'b11100, 7'b0100011}, IMM_S, 32'hFFFFFFFC, "S-type negativo (-4)");

    // --- B-type: beq x1, x2, 16 ---
    check({1'b0, 6'b000000, 5'd2, 5'd1, 3'b000, 4'b1000, 1'b0, 7'b1100011}, IMM_B, 32'd16, "B-type positivo (16)");

    // --- U-type: lui x5, 0x12345 ---
    check({20'h12345, 5'd5, 7'b0110111}, IMM_U, 32'h12345000, "U-type");

    // --- J-type: jal x1, 4 ---
    check({1'b0, 10'b0000000010, 1'b0, 8'b00000000, 5'd1, 7'b1101111}, IMM_J, 32'd4, "J-type positivo (4)");

    // --- R-type: no usa inmediato ---
    check(32'hFFFFFFFF, IMM_X, 32'd0, "IMM_X - R-type no usa inmediato");

    if (errors == 0)
      $display("IMM_GEN_TB: %0d/%0d checks OK", checks, checks);
    else
      $display("IMM_GEN_TB: %0d errores en %0d checks", errors, checks);

    $finish;
  end

endmodule