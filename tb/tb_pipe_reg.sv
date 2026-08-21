module tb_pipe_reg;

  import riscv_pkg::*;

  logic  clk = 0;
  logic  rst, flush, stall;
  id_ex_t din, dout;

  int errors = 0;
  int checks = 0;

  pipe_reg #(.T(id_ex_t)) dut (.clk(clk), .rst(rst), .flush(flush), .stall(stall), .d(din), .q(dout));

  always #5 clk = ~clk;

  task automatic expect_rd(input logic [REG_ADDR_W-1:0] exp, input string name);
    checks++;
    if (dout.rd !== exp) begin
      errors++;
      $error("[%s] rd=%0d (esperado %0d)", name, dout.rd, exp);
    end
  endtask

  initial begin
    rst = 1; flush = 0; stall = 0; din = '0;
    @(posedge clk); #1;
    rst = 0;
    expect_rd(5'd0, "reset - arranca en 0");

    // --- carga normal ---
    din.rd = 5'd7; din.pc = 32'd100;
    @(posedge clk); #1;
    expect_rd(5'd7, "carga normal - rd se actualiza");
    checks++;
    if (dout.pc !== 32'd100) begin
      errors++;
      $error("carga normal - pc=%0d (esperado 100)", dout.pc);
    end

    // --- stall: no debe cambiar aunque la entrada cambie ---
    stall = 1;
    din.rd = 5'd20;
    @(posedge clk); #1;
    expect_rd(5'd7, "stall - mantiene el valor viejo");
    stall = 0;

    // --- flush: limpia todo el struct a 0, sin importar la entrada ---
    flush = 1;
    din.rd = 5'd20;
    @(posedge clk); #1;
    expect_rd(5'd0, "flush - limpia a 0 (burbuja)");
    flush = 0;

    // --- vuelve a cargar normal despues del flush ---
    din.rd = 5'd3;
    @(posedge clk); #1;
    expect_rd(5'd3, "post-flush - vuelve a cargar normal");

    if (errors == 0)
      $display("PIPE_REG_TB: %0d/%0d checks OK", checks, checks);
    else
      $display("PIPE_REG_TB: %0d errores en %0d checks", errors, checks);

    $finish;
  end

endmodule