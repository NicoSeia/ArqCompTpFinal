module tb_imem;

  import riscv_pkg::*;

  logic [IMEM_ADDR_W+1:0] addr;
  logic [31:0]            instr;

  int errors = 0;
  int checks = 0;

  imem dut (.addr(addr), .instr(instr));

  task automatic expect_instr(input logic [IMEM_ADDR_W+1:0] addr_i, input logic [31:0] expected, input string name);
    addr = addr_i;
    #1;
    checks++;
    if (instr !== expected) begin
      errors++;
      $error("[%s] addr=%0d -> instr=%08h (esperado %08h)", name, addr_i, instr, expected);
    end
  endtask

  initial begin
    // referencia jerárquica: todavía no hay ensamblador, cargamos a mano
    dut.mem[0] = 32'h002081B3;  // add x3, x1, x2
    dut.mem[1] = 32'h40208233;  // sub x4, x1, x2
    dut.mem[2] = 32'h0000006F;  // jal x0, 0

    // --- direccionamiento por byte, dividiendo por 4 ---
    expect_instr(12'd0,  32'h002081B3, "addr=0 -> mem[0]");
    expect_instr(12'd4,  32'h40208233, "addr=4 -> mem[1]");
    expect_instr(12'd8,  32'h0000006F, "addr=8 -> mem[2]");

    // --- una dirección no alineada tiene que caer en la misma palabra
    //     que la dirección alineada anterior (se ignoran los 2 bits bajos) ---
    expect_instr(12'd5, 32'h40208233, "addr=5 (no alineada) -> misma palabra que addr=4");

    // --- posición no inicializada -> NOP por defecto ---
    expect_instr(12'd12, 32'h00000013, "addr=12 -> NOP por defecto");

    if (errors == 0)
      $display("IMEM_TB: %0d/%0d checks OK", checks, checks);
    else
      $display("IMEM_TB: %0d errores en %0d checks", errors, checks);

    $finish;
  end

endmodule