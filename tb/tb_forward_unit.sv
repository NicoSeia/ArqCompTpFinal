module tb_forward_unit;

  import riscv_pkg::*;

  logic [REG_ADDR_W-1:0] rs1_ex, rs2_ex, rd_ex_mem, rd_mem_wb;
  logic                  reg_write_ex_mem, reg_write_mem_wb;
  fwd_src_e              forward_a, forward_b;

  int errors = 0;
  int checks = 0;

  forward_unit dut (
      .rs1_ex(rs1_ex), .rs2_ex(rs2_ex),
      .rd_ex_mem(rd_ex_mem), .reg_write_ex_mem(reg_write_ex_mem),
      .rd_mem_wb(rd_mem_wb), .reg_write_mem_wb(reg_write_mem_wb),
      .forward_a(forward_a), .forward_b(forward_b)
  );

  task automatic check(input fwd_src_e exp_a, input fwd_src_e exp_b, input string name);
    #1;
    checks++;
    if (forward_a !== exp_a) begin
      errors++;
      $error("[%s] forward_a=%0d (esperado %0d)", name, forward_a, exp_a);
    end
    checks++;
    if (forward_b !== exp_b) begin
      errors++;
      $error("[%s] forward_b=%0d (esperado %0d)", name, forward_b, exp_b);
    end
  endtask

  initial begin
    // --- sin hazard: ningun rd coincide con rs1/rs2 ---
    rs1_ex = 5'd1; rs2_ex = 5'd2;
    rd_ex_mem = 5'd9;  reg_write_ex_mem = 1'b1;
    rd_mem_wb = 5'd10; reg_write_mem_wb = 1'b1;
    check(FWD_NONE, FWD_NONE, "sin hazard - nada coincide");

    // --- EX/MEM hazard en rs1 ---
    rd_ex_mem = 5'd1;  // coincide con rs1_ex
    check(FWD_EX_MEM, FWD_NONE, "EX/MEM hazard en rs1");

    // --- EX/MEM hazard en rs2 ---
    rd_ex_mem = 5'd2;  // coincide con rs2_ex
    check(FWD_NONE, FWD_EX_MEM, "EX/MEM hazard en rs2");

    // --- MEM/WB hazard en rs1 (sin coincidencia en EX/MEM) ---
    rd_ex_mem = 5'd9;  // no coincide con nada
    rd_mem_wb = 5'd1;  // coincide con rs1_ex
    check(FWD_MEM_WB, FWD_NONE, "MEM/WB hazard en rs1");

    // --- MEM/WB hazard en rs2 ---
    rd_mem_wb = 5'd2;  // coincide con rs2_ex
    check(FWD_NONE, FWD_MEM_WB, "MEM/WB hazard en rs2");

    // --- ambos operandos con hazard simultaneo, de fuentes distintas ---
    rd_ex_mem = 5'd1;  // rs1 <- EX/MEM
    rd_mem_wb = 5'd2;  // rs2 <- MEM/WB
    check(FWD_EX_MEM, FWD_MEM_WB, "rs1 y rs2 con hazard de fuentes distintas");

    // --- prioridad: EX/MEM y MEM/WB coinciden con el MISMO registro -> gana EX/MEM ---
    rd_ex_mem = 5'd1;
    rd_mem_wb = 5'd1;
    check(FWD_EX_MEM, FWD_NONE, "prioridad - EX/MEM gana por ser mas reciente");

    // --- exclusion: rd=x0, aunque "coincida" nunca se forwardea ---
    rs1_ex = 5'd0; rs2_ex = 5'd0;
    rd_ex_mem = 5'd0; reg_write_ex_mem = 1'b1;
    rd_mem_wb = 5'd0; reg_write_mem_wb = 1'b1;
    check(FWD_NONE, FWD_NONE, "exclusion x0 - nunca se forwardea aunque coincida");

    // --- exclusion: coincide el numero de registro pero reg_write=0 (ej. un store) ---
    rs1_ex = 5'd5; rs2_ex = 5'd6;
    rd_ex_mem = 5'd5; reg_write_ex_mem = 1'b0;  // coincide, pero no escribe
    rd_mem_wb = 5'd6; reg_write_mem_wb = 1'b0;  // coincide, pero no escribe
    check(FWD_NONE, FWD_NONE, "exclusion reg_write=0 - coincide el numero pero no escribe");

    if (errors == 0)
      $display("FORWARD_UNIT_TB: %0d/%0d checks OK", checks, checks);
    else
      $display("FORWARD_UNIT_TB: %0d errores en %0d checks", errors, checks);

    $finish;
  end

endmodule