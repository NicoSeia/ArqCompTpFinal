module tb_pipeline_top;

  import riscv_pkg::*;

  logic clk = 0;
  logic rst;

  int errors = 0;
  int checks = 0;

  pipeline_top dut (.clk(clk), .rst(rst));

  always #5 clk = ~clk;

  function automatic logic [31:0] rtype(input logic [6:0] funct7, input logic [4:0] rs2, input logic [4:0] rs1, input logic [2:0] funct3, input logic [4:0] rd, input logic [6:0] opcode);
    return {funct7, rs2, rs1, funct3, rd, opcode};
  endfunction

  function automatic logic [31:0] itype(input logic [11:0] imm, input logic [4:0] rs1, input logic [2:0] funct3, input logic [4:0] rd, input logic [6:0] opcode);
    return {imm, rs1, funct3, rd, opcode};
  endfunction

  function automatic logic [31:0] stype(input logic [11:0] imm, input logic [4:0] rs2, input logic [4:0] rs1, input logic [2:0] funct3, input logic [6:0] opcode);
    return {imm[11:5], rs2, rs1, funct3, imm[4:0], opcode};
  endfunction

  function automatic logic [31:0] btype(input logic [12:0] imm, input logic [4:0] rs2, input logic [4:0] rs1, input logic [2:0] funct3, input logic [6:0] opcode);
    return {imm[12], imm[10:5], rs2, rs1, funct3, imm[4:1], imm[11], opcode};
  endfunction

  function automatic logic [31:0] utype(input logic [19:0] imm20, input logic [4:0] rd, input logic [6:0] opcode);
    return {imm20, rd, opcode};
  endfunction

  logic [31:0] prog[0:27];

  task automatic expect_reg(input int idx, input logic [31:0] exp, input string name);
    checks++;
    if (dut.u_regfile.regs[idx] !== exp) begin
      errors++;
      $error("[%s] x%0d=%08h (esperado %08h)", name, idx, dut.u_regfile.regs[idx], exp);
    end
  endtask

  initial begin
    // idx : instruccion                         : dependencias (gap a la escritura)
    prog[0]  = itype(12'd5,  5'd0, 3'b000, 5'd1,  OP_IMM);                 // addi x1,x0,5
    prog[1]  = itype(12'd10, 5'd0, 3'b000, 5'd2,  OP_IMM);                 // addi x2,x0,10
    prog[2]  = itype(12'd3,  5'd0, 3'b000, 5'd3,  OP_IMM);                 // addi x3,x0,3
    prog[3]  = itype(12'd7,  5'd0, 3'b000, 5'd4,  OP_IMM);                 // addi x4,x0,7 (relleno)
    prog[4]  = rtype(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd5, OP_R);          // add x5,x1,x2   (x1 gap4, x2 gap3)
    prog[5]  = rtype(7'b0100000, 5'd3, 5'd2, 3'b000, 5'd6, OP_R);          // sub x6,x2,x3   (x2 gap4, x3 gap3)
    prog[6]  = itype(12'd20, 5'd0, 3'b000, 5'd7,  OP_IMM);                 // addi x7,x0,20 (relleno)
    prog[7]  = itype(12'd30, 5'd0, 3'b000, 5'd8,  OP_IMM);                 // addi x8,x0,30 (relleno)
    prog[8]  = stype(12'd0, 5'd5, 5'd0, 3'b010, OP_STORE);                 // sw x5,0(x0)    (x5 gap4)
    prog[9]  = itype(12'd0, 5'd0, 3'b010, 5'd9,  OP_LOAD);                 // lw x9,0(x0)
    prog[10] = itype(12'd100, 5'd0, 3'b000, 5'd10, OP_IMM);                // addi x10,x0,100 (relleno)
    prog[11] = itype(12'd200, 5'd0, 3'b000, 5'd11, OP_IMM);                // addi x11,x0,200 (relleno)
    prog[12] = utype(20'd1, 5'd12, OP_LUI);                                // lui x12,1
    prog[13] = itype(-12'd7, 5'd0, 3'b000, 5'd13, OP_IMM);                 // addi x13,x0,-7
    prog[14] = btype(13'd8, 5'd1, 5'd1, 3'b000, OP_BRANCH);                // beq x1,x1,8 (toma el salto, x1 gap14)
    prog[15] = itype(12'd999, 5'd0, 3'b000, 5'd14, OP_IMM);                // addi x14,x0,999  <- VENENO
    prog[16] = itype(12'd42, 5'd0, 3'b000, 5'd15, OP_IMM);                 // addi x15,x0,42
    prog[17] = itype(12'd111, 5'd0, 3'b000, 5'd16, OP_IMM);                // addi x16,x0,111 (relleno)
    prog[18] = itype(12'd92, 5'd0, 3'b000, 5'd17, OP_IMM);                 // addi x17,x0,92  (direccion byte de idx23)
    prog[19] = itype(12'd55, 5'd0, 3'b000, 5'd18, OP_IMM);                 // addi x18,x0,55 (relleno)
    prog[20] = itype(12'd66, 5'd0, 3'b000, 5'd19, OP_IMM);                 // addi x19,x0,66 (relleno)
    prog[21] = itype(12'd0, 5'd17, 3'b000, 5'd20, OP_JALR);                // jalr x20,0(x17) (x17 gap3, salta a idx23)
    prog[22] = itype(12'd777, 5'd0, 3'b000, 5'd21, OP_IMM);                // addi x21,x0,777  <- VENENO
    prog[23] = itype(12'd13, 5'd0, 3'b000, 5'd22, OP_IMM);                 // addi x22,x0,13
    prog[24] = btype(13'd8, 5'd2, 5'd1, 3'b001, OP_BRANCH);                // bne x1,x2,8 (toma el salto)
    prog[25] = itype(12'd555, 5'd0, 3'b000, 5'd23, OP_IMM);                // addi x23,x0,555  <- VENENO
    prog[26] = itype(12'd15, 5'd2, 3'b111, 5'd24, OP_IMM);                 // andi x24,x2,15
    prog[27] = itype(12'd8, 5'd1, 3'b110, 5'd25, OP_IMM);                  // ori x25,x1,8

    for (int i = 0; i <= 27; i++) dut.u_imem.mem[i] = prog[i];

    rst = 1;
    @(posedge clk); #1;
    rst = 0;

    // Generoso a proposito: no hace falta el numero minimo exacto, solo
    // asegurarse de que el pipeline ya drenó todo por completo.
    repeat (70) @(posedge clk);
    #1;

    expect_reg(1,  32'd5,          "x1 = addi 5");
    expect_reg(2,  32'd10,         "x2 = addi 10");
    expect_reg(3,  32'd3,          "x3 = addi 3");
    expect_reg(4,  32'd7,          "x4 = addi 7");
    expect_reg(5,  32'd15,         "x5 = add x1+x2");
    expect_reg(6,  32'd7,          "x6 = sub x2-x3");
    expect_reg(7,  32'd20,         "x7 = addi 20");
    expect_reg(8,  32'd30,         "x8 = addi 30");
    expect_reg(9,  32'd15,         "x9 = lw (relee lo que escribio sw)");
    expect_reg(10, 32'd100,        "x10 = addi 100");
    expect_reg(11, 32'd200,        "x11 = addi 200");
    expect_reg(12, 32'h00001000,   "x12 = lui");
    expect_reg(13, -32'd7,         "x13 = addi -7");
    expect_reg(14, 32'd0,          "x14 = NO debe tener el veneno (beq lo salteo)");
    expect_reg(15, 32'd42,         "x15 = addi 42 tras el salto del beq");
    expect_reg(16, 32'd111,        "x16 = addi 111");
    expect_reg(17, 32'd92,         "x17 = addi 92");
    expect_reg(18, 32'd55,         "x18 = addi 55");
    expect_reg(19, 32'd66,         "x19 = addi 66");
    expect_reg(20, 32'd88,         "x20 = jalr guarda pc+4");
    expect_reg(21, 32'd0,          "x21 = NO debe tener el veneno (jalr lo salteo)");
    expect_reg(22, 32'd13,         "x22 = addi 13 tras el target del jalr");
    expect_reg(23, 32'd0,          "x23 = NO debe tener el veneno (bne lo salteo)");
    expect_reg(24, 32'd10,         "x24 = andi x2,15");
    expect_reg(25, 32'd13,         "x25 = ori x1,8");

    checks++;
    if ({dut.u_dmem.mem[3], dut.u_dmem.mem[2], dut.u_dmem.mem[1], dut.u_dmem.mem[0]} !== 32'd15) begin
      errors++;
      $error("mem[0] = %08h (esperado 15)",
             {dut.u_dmem.mem[3], dut.u_dmem.mem[2], dut.u_dmem.mem[1], dut.u_dmem.mem[0]});
    end

    if (errors == 0)
      $display("PIPELINE_TB: %0d/%0d checks OK", checks, checks);
    else
      $display("PIPELINE_TB: %0d errores en %0d checks", errors, checks);

    $finish;
  end

endmodule