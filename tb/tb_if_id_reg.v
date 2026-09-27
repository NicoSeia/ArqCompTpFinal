// -----------------------------------------------------------------------------
// tb_if_id_reg.v
// Testbench dirigido para if_id_reg (reemplaza al viejo tb_pipe_reg.v, que
// probaba el pipe_reg #(.WIDTH(...)) generico con offsets de bits a mano).
// Verifica: reset limpia a 0, flush limpia a 0, stall congela el valor
// anterior, y un avance normal propaga cada campo a su puerto de salida
// correspondiente -- con un valor DISTINTO por campo para detectar un
// campo conectado al puerto equivocado.
// -----------------------------------------------------------------------------
module tb_if_id_reg;

  reg clk = 0;
  always #5 clk = ~clk;

  integer errors = 0;
  integer checks = 0;

  task automatic check_bit(input val, input exp, input [255:0] name);
    begin
      checks = checks + 1;
      if (val !== exp) begin
        errors = errors + 1;
        $display("FAIL [%0s] got=%0b esperado=%0b", name, val, exp);
      end
    end
  endtask

  task automatic check_word(input [31:0] val, input [31:0] exp, input [255:0] name);
    begin
      checks = checks + 1;
      if (val !== exp) begin
        errors = errors + 1;
        $display("FAIL [%0s] got=%08h esperado=%08h", name, val, exp);
      end
    end
  endtask

  reg         rst, flush, stall;
  reg         d_valid;
  reg  [31:0] d_pc, d_pc_plus4, d_instr;
  wire        q_valid;
  wire [31:0] q_pc, q_pc_plus4, q_instr;

  if_id_reg dut (
      .clk(clk), .rst(rst), .flush(flush), .stall(stall),
      .d_valid(d_valid), .d_pc(d_pc), .d_pc_plus4(d_pc_plus4), .d_instr(d_instr),
      .q_valid(q_valid), .q_pc(q_pc), .q_pc_plus4(q_pc_plus4), .q_instr(q_instr)
  );

  initial begin
    rst = 1; flush = 0; stall = 0;
    d_valid = 1; d_pc = 32'hAAAA_0001; d_pc_plus4 = 32'hAAAA_0002; d_instr = 32'hAAAA_0003;
    @(posedge clk); #1;
    check_bit(q_valid, 1'b0, "reset limpia valid");
    check_word(q_pc, 32'd0, "reset limpia pc");
    check_word(q_pc_plus4, 32'd0, "reset limpia pc_plus4");
    check_word(q_instr, 32'd0, "reset limpia instr");

    rst = 0;
    @(posedge clk); #1;
    check_bit(q_valid, 1'b1, "avance normal - valid");
    check_word(q_pc, 32'hAAAA_0001, "avance normal - pc");
    check_word(q_pc_plus4, 32'hAAAA_0002, "avance normal - pc_plus4 (no cruzado con pc)");
    check_word(q_instr, 32'hAAAA_0003, "avance normal - instr (no cruzado con pc_plus4)");

    // stall: no debe cambiar aunque la entrada cambie
    stall = 1;
    d_pc = 32'hDEAD_BEEF; d_instr = 32'hDEAD_CAFE;
    @(posedge clk); #1;
    check_word(q_pc, 32'hAAAA_0001, "stall congela pc");
    check_word(q_instr, 32'hAAAA_0003, "stall congela instr");
    stall = 0;

    // flush: limpia todo el latch a 0, sin importar la entrada
    flush = 1;
    @(posedge clk); #1;
    check_bit(q_valid, 1'b0, "flush limpia valid");
    check_word(q_pc, 32'd0, "flush limpia pc");
    flush = 0;

    // vuelve a cargar normal despues del flush
    d_valid = 1; d_pc = 32'hBEEF_0001; d_pc_plus4 = 32'hBEEF_0002; d_instr = 32'hBEEF_0003;
    @(posedge clk); #1;
    check_bit(q_valid, 1'b1, "post-flush - vuelve a cargar normal");
    check_word(q_pc, 32'hBEEF_0001, "post-flush - pc");

    if (errors == 0)
      $display("IF_ID_REG_TB: %0d/%0d checks OK", checks, checks);
    else
      $display("IF_ID_REG_TB: %0d errores en %0d checks", errors, checks);

    $finish;
  end

endmodule
