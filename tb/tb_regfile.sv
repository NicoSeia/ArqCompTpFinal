module tb_regfile;

  import riscv_pkg::*;

  logic                  clk = 0;
  logic                  rst;
  logic                  we;
  logic [REG_ADDR_W-1:0] rs1_addr, rs2_addr, rd_addr;
  logic [XLEN-1:0]       rd_data;
  logic [XLEN-1:0]       rs1_data, rs2_data;

  int errors = 0;
  int checks = 0;

  regfile dut (.*);

  always #5 clk = ~clk;  // periodo 10

  task automatic expect_val(input logic [XLEN-1:0] got, input logic [XLEN-1:0] exp, input string name);
    checks++;
    if (got !== exp) begin
      errors++;
      $error("[%s] valor=%0h (esperado %0h)", name, got, exp);
    end
  endtask

  initial begin
    // --- Reset: todos los registros en 0 ---
    rst = 1; we = 0; rd_addr = '0; rd_data = '0; rs1_addr = '0; rs2_addr = '0;
    @(posedge clk); #1;
    rst = 0;

    rs1_addr = 5'd1; rs2_addr = 5'd31; #1;
    expect_val(rs1_data, '0, "reset - x1 en 0");
    expect_val(rs2_data, '0, "reset - x31 en 0");

    // --- x0 hardwireado a 0, incluso intentando escribirlo ---
    rd_addr = 5'd0; rd_data = 32'hDEADBEEF; we = 1;
    @(posedge clk); #1;
    we = 0;
    rs1_addr = 5'd0; #1;
    expect_val(rs1_data, '0, "x0 - escritura ignorada, sigue en 0");

    // --- Escritura y lectura basica ---
    rd_addr = 5'd5; rd_data = 32'hCAFEBABE; we = 1;
    @(posedge clk); #1;
    we = 0;
    rs1_addr = 5'd5; #1;
    expect_val(rs1_data, 32'hCAFEBABE, "escritura basica - x5");

    // --- Lectura simultanea en los dos puertos, registros distintos ---
    rd_addr = 5'd10; rd_data = 32'h11111111; we = 1;
    @(posedge clk); #1;
    we = 0;
    rs1_addr = 5'd5; rs2_addr = 5'd10; #1;
    expect_val(rs1_data, 32'hCAFEBABE, "puerto 1 - x5 sigue correcto");
    expect_val(rs2_data, 32'h11111111, "puerto 2 - x10");

    // --- Orden write-before-read: en el mismo ciclo en que se escribe,
    //     la lectura combinacional todavia tiene que ver el valor VIEJO ---
    rd_addr = 5'd5; rd_data = 32'hA5A5A5A5; we = 1;
    rs1_addr = 5'd5; #1;
    expect_val(rs1_data, 32'hCAFEBABE, "durante la escritura - lectura ve el valor viejo");
    @(posedge clk); #1;
    we = 0;
    expect_val(rs1_data, 32'hA5A5A5A5, "despues del flanco - lectura ve el valor nuevo");

    if (errors == 0)
      $display("REGFILE_TB: %0d/%0d checks OK", checks, checks);
    else
      $display("REGFILE_TB: %0d errores en %0d checks", errors, checks);

    $finish;
  end

endmodule