module alu_tb;

  import riscv_pkg::*;

  logic [XLEN-1:0] a, b;
  alu_op_e         op;
  logic [XLEN-1:0] result;
  logic            zero;

  int errors = 0;
  int checks = 0;

  alu dut (.a(a), .b(b), .op(op), .result(result), .zero(zero));

  task automatic check(
      input logic [XLEN-1:0] a_i,
      input logic [XLEN-1:0] b_i,
      input alu_op_e         op_i,
      input logic [XLEN-1:0] expected_result,
      input string           name
  );
    a  = a_i;
    b  = b_i;
    op = op_i;
    #1; // deja asentar la lógica combinacional
    checks++;
    if (result !== expected_result) begin
      errors++;
      $error("[%s] a=%0d b=%0d -> result=%0d (esperado %0d)",
             name, $signed(a_i), $signed(b_i), $signed(result), $signed(expected_result));
    end
  endtask

  task automatic check_zero(input logic expected_zero, input string name);
    #1;
    checks++;
    if (zero !== expected_zero) begin
      errors++;
      $error("[%s] zero=%0b (esperado %0b)", name, zero, expected_zero);
    end
  endtask

  initial begin
    // --- Operaciones básicas ---
    check(32'd10, 32'd3, ALU_ADD, 32'd13, "add");
    check(32'd10, 32'd3, ALU_SUB, 32'd7,  "sub");
    check(32'hF0F0F0F0, 32'h0F0F0F0F, ALU_AND, 32'h00000000, "and");
    check(32'hF0F0F0F0, 32'h0F0F0F0F, ALU_OR,  32'hFFFFFFFF, "or");
    check(32'hFF00FF00, 32'h0F0F0F0F, ALU_XOR, 32'hF00FF00F, "xor");

    // --- Shifts (el hardware solo mira b[4:0], igual que el ISA real) ---
    check(32'h00000001, 32'd4,  ALU_SLL, 32'h00000010, "sll");
    check(32'h80000000, 32'd4,  ALU_SRL, 32'h08000000, "srl");
    check(32'h80000000, 32'd4,  ALU_SRA, 32'hF8000000, "sra - preserva el signo");
    check(32'h00000001, 32'd33, ALU_SLL, 32'h00000002, "sll - shift amount se trunca a 5 bits");

    // --- Comparaciones con signo vs sin signo ---
    check(-32'd1, 32'd1, ALU_SLT,  32'd1, "slt - -1 < 1 con signo");
    check(-32'd1, 32'd1, ALU_SLTU, 32'd0, "sltu - -1 es 0xFFFFFFFF, no es menor sin signo");
    check(32'd5,  32'd5, ALU_SLT,  32'd0, "slt - iguales no es menor");

    // --- Sub y flag zero (lo que va a resolver beq/bne en next_pc_logic) ---
    check(32'd8, 32'd8, ALU_SUB, 32'd0, "sub - a==b da 0");
    check_zero(1'b1, "zero flag - a==b levanta zero");

    check(32'd8, 32'd9, ALU_SUB, -32'd1, "sub - a!=b");
    check_zero(1'b0, "zero flag - a!=b no levanta zero");

    // --- pass (lui: el resultado es b, a se ignora) ---
    check(32'hFFFFFFFF, 32'h00001000, ALU_PASS, 32'h00001000, "pass - ignora a, devuelve b");

    // --- Resumen ---
    if (errors == 0)
      $display("ALU_TB: %0d/%0d checks OK", checks, checks);
    else
      $display("ALU_TB: %0d errores en %0d checks", errors, checks);

    $finish;
  end

endmodule