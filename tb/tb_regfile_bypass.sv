module tb_regfile_bypass;

  import riscv_pkg::*;

  logic                  clk = 0;
  logic                  rst;
  logic                  we;
  logic [REG_ADDR_W-1:0] rs1_addr, rs2_addr, rd_addr;
  logic [XLEN-1:0]       rd_data;
  logic [XLEN-1:0]       rs1_data, rs2_data;

  int errors = 0;
  int checks = 0;

  regfile #(.ENABLE_WB_BYPASS(1'b1)) dut (.*);

  always #5 clk = ~clk;

  task automatic expect_val(input logic [XLEN-1:0] got, input logic [XLEN-1:0] exp, input string name);
    checks++;
    if (got !== exp) begin
      errors++;
      $error("[%s] valor=%0h (esperado %0h)", name, got, exp);
    end
  endtask

  initial begin
    rst = 1; we = 0; rd_addr = '0; rd_data = '0; rs1_addr = '0; rs2_addr = '0;
    @(posedge clk); #1;
    rst = 0;

    // --- valor previo conocido en x5, para comparar contra el bypass despues ---
    rd_addr = 5'd5; rd_data = 32'hCAFEBABE; we = 1;
    @(posedge clk); #1;
    we = 0;

    // --- bypass: mismo ciclo en que se escribe x5, la lectura YA ve el nuevo valor ---
    rd_addr = 5'd5; rd_data = 32'hA5A5A5A5; we = 1;
    rs1_addr = 5'd5; rs2_addr = 5'd5;
    #1;
    expect_val(rs1_data, 32'hA5A5A5A5, "bypass puerto 1 - ve el valor nuevo en el mismo ciclo");
    expect_val(rs2_data, 32'hA5A5A5A5, "bypass puerto 2 - ve el valor nuevo en el mismo ciclo");

    // --- una direccion DISTINTA a la que se escribe sigue viendo su valor guardado ---
    rs1_addr = 5'd1; // x1 nunca se escribio, tiene que seguir en 0
    #1;
    expect_val(rs1_data, 32'd0, "direccion distinta a la escrita - no se contamina");

    @(posedge clk); #1;
    we = 0;
    rs1_addr = 5'd5;
    #1;
    expect_val(rs1_data, 32'hA5A5A5A5, "despues del flanco - se mantiene el valor nuevo");

    // --- x0: el bypass nunca lo pisa, ni siquiera si we apunta ahi ---
    rd_addr = 5'd0; rd_data = 32'hDEADBEEF; we = 1;
    rs1_addr = 5'd0;
    #1;
    expect_val(rs1_data, 32'd0, "x0 - el bypass no lo afecta");

    if (errors == 0)
      $display("REGFILE_BYPASS_TB: %0d/%0d checks OK", checks, checks);
    else
      $display("REGFILE_BYPASS_TB: %0d errores en %0d checks", errors, checks);

    $finish;
  end

endmodule