module tb_hazard_detect;

  import riscv_pkg::*;

  logic                  id_ex_mem_read;
  logic [REG_ADDR_W-1:0] id_ex_rd, rs1_id, rs2_id;
  logic                  stall_load_use;

  int errors = 0;
  int checks = 0;

  hazard_detect dut (
      .id_ex_mem_read(id_ex_mem_read), .id_ex_rd(id_ex_rd),
      .rs1_id(rs1_id), .rs2_id(rs2_id), .stall_load_use(stall_load_use)
  );

  task automatic check(input logic exp, input string name);
    #1;
    checks++;
    if (stall_load_use !== exp) begin
      errors++;
      $error("[%s] stall_load_use=%0b (esperado %0b)", name, stall_load_use, exp);
    end
  endtask

  initial begin
    // --- no es load: nunca frena, aunque los registros coincidan ---
    id_ex_mem_read = 1'b0; id_ex_rd = 5'd3; rs1_id = 5'd3; rs2_id = 5'd7;
    check(1'b0, "no es load - no frena aunque coincida");

    // --- es load, pero ningun registro coincide ---
    id_ex_mem_read = 1'b1; id_ex_rd = 5'd3; rs1_id = 5'd1; rs2_id = 5'd2;
    check(1'b0, "load sin coincidencia - no frena");

    // --- hazard en rs1 ---
    rs1_id = 5'd3;
    check(1'b1, "hazard en rs1");

    // --- hazard en rs2 ---
    rs1_id = 5'd1; rs2_id = 5'd3;
    check(1'b1, "hazard en rs2");

    // --- hazard en ambos a la vez (ej: add x5,x1,x1 justo despues de lw x1,...) ---
    rs1_id = 5'd3; rs2_id = 5'd3;
    check(1'b1, "hazard en rs1 y rs2 simultaneo");

    // --- exclusion: rd=x0, aunque "coincida" nunca frena ---
    id_ex_rd = 5'd0; rs1_id = 5'd0; rs2_id = 5'd0;
    check(1'b0, "exclusion x0 - nunca frena aunque coincida");

    if (errors == 0)
      $display("HAZARD_DETECT_TB: %0d/%0d checks OK", checks, checks);
    else
      $display("HAZARD_DETECT_TB: %0d errores en %0d checks", errors, checks);

    $finish;
  end

endmodule