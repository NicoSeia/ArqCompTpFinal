module tb_datapath_singlecycle;

  import riscv_pkg::*;

  logic clk = 0;
  logic rst;

  int errors = 0;
  int checks = 0;

  datapath_singlecycle dut (.clk(clk), .rst(rst));

  always #5 clk = ~clk;

  // --- Helpers de encoding, uno por tipo de instrucción ---
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

  function automatic logic [31:0] jtype(input logic [20:0] imm, input logic [4:0] rd, input logic [6:0] opcode);
    return {imm[20], imm[10:1], imm[11], imm[19:12], rd, opcode};
  endfunction

  logic [31:0] prog[0:24];

  task automatic expect_reg(input int idx, input logic [31:0] exp, input string name);
    checks++;
    if (dut.u_regfile.regs[idx] !== exp) begin
      errors++;
      $error("[%s] x%0d=%08h (esperado %08h)", name, idx, dut.u_regfile.regs[idx], exp);
    end
  endtask

  initial begin
    // idx : instrucción                    : comentario
    prog[0]  = itype(12'd5, 5'd0, 3'b000, 5'd1, OP_IMM);                  // addi x1,x0,5
    prog[1]  = itype(12'd10, 5'd0, 3'b000, 5'd2, OP_IMM);                 // addi x2,x0,10
    prog[2]  = rtype(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3, OP_R);         // add x3,x1,x2
    prog[3]  = rtype(7'b0100000, 5'd1, 5'd2, 3'b000, 5'd4, OP_R);         // sub x4,x2,x1
    prog[4]  = stype(12'd0, 5'd3, 5'd0, 3'b010, OP_STORE);                // sw x3,0(x0)
    prog[5]  = itype(12'd0, 5'd0, 3'b010, 5'd5, OP_LOAD);                 // lw x5,0(x0)
    prog[6]  = btype(13'd8, 5'd1, 5'd1, 3'b000, OP_BRANCH);               // beq x1,x1,8 (toma el salto)
    prog[7]  = itype(12'd999, 5'd0, 3'b000, 5'd6, OP_IMM);                // addi x6,x0,999  <- VENENO
    prog[8]  = utype(20'd1, 5'd7, OP_LUI);                                // lui x7,1
    prog[9]  = itype(12'd56, 5'd0, 3'b000, 5'd11, OP_IMM);                // addi x11,x0,56
    prog[10] = jtype(21'd8, 5'd8, OP_JAL);                                // jal x8,8 (salta)
    prog[11] = itype(12'd888, 5'd0, 3'b000, 5'd9, OP_IMM);                // addi x9,x0,888  <- VENENO
    prog[12] = itype(12'd0, 5'd11, 3'b000, 5'd10, OP_JALR);               // jalr x10,0(x11)
    prog[13] = itype(12'd777, 5'd0, 3'b000, 5'd13, OP_IMM);               // addi x13,x0,777 <- VENENO
    prog[14] = itype(12'd42, 5'd0, 3'b000, 5'd14, OP_IMM);                // addi x14,x0,42
    prog[15] = itype(-12'd3, 5'd0, 3'b000, 5'd15, OP_IMM);                // addi x15,x0,-3
    prog[16] = stype(12'd4, 5'd15, 5'd0, 3'b000, OP_STORE);               // sb x15,4(x0)
    prog[17] = itype(12'd4, 5'd0, 3'b000, 5'd16, OP_LOAD);                // lb x16,4(x0)
    prog[18] = itype(12'd4, 5'd0, 3'b100, 5'd17, OP_LOAD);                // lbu x17,4(x0)
    prog[19] = itype(12'd1, 5'd0, 3'b000, 5'd18, OP_IMM);                 // addi x18,x0,1
    prog[20] = rtype(7'b0000000, 5'd2, 5'd18, 3'b001, 5'd19, OP_R);       // sll x19,x18,x2
    prog[21] = btype(13'd8, 5'd2, 5'd1, 3'b001, OP_BRANCH);               // bne x1,x2,8 (toma el salto)
    prog[22] = itype(12'd5555, 5'd0, 3'b000, 5'd20, OP_IMM);              // addi x20,x0,5555 <- VENENO
    prog[23] = itype(12'd15, 5'd2, 3'b111, 5'd21, OP_IMM);                // andi x21,x2,15
    prog[24] = itype(12'd8, 5'd1, 3'b110, 5'd22, OP_IMM);                 // ori x22,x1,8

    for (int i = 0; i <= 24; i++) dut.u_imem.mem[i] = prog[i];

    rst = 1;
    @(posedge clk); #1;
    rst = 0;

    // 25 instrucciones en memoria, pero 4 son veneno y se saltean -> 21 se
    // ejecutan de verdad. Cada flanco de clock completa una instrucción
    // (monociclo), así que 21 flancos alcanzan.
    repeat (21) @(posedge clk);
    #1;

    expect_reg(1,  32'd5,        "x1 = addi 5");
    expect_reg(2,  32'd10,       "x2 = addi 10");
    expect_reg(3,  32'd15,       "x3 = add");
    expect_reg(4,  32'd5,        "x4 = sub");
    expect_reg(5,  32'd15,       "x5 = lw (relee lo que escribio sw)");
    expect_reg(6,  32'd0,        "x6 = NO debe tener el veneno (beq lo salteo)");
    expect_reg(7,  32'h00001000, "x7 = lui");
    expect_reg(8,  32'd44,       "x8 = jal guarda pc+4");
    expect_reg(9,  32'd0,        "x9 = NO debe tener el veneno (jal lo salteo)");
    expect_reg(10, 32'd52,       "x10 = jalr guarda pc+4");
    expect_reg(11, 32'd56,       "x11 = addi 56");
    expect_reg(13, 32'd0,        "x13 = NO debe tener el veneno (jalr lo salteo)");
    expect_reg(14, 32'd42,       "x14 = addi tras el target de jalr");
    expect_reg(15, -32'd3,       "x15 = addi -3");
    expect_reg(16, -32'd3,       "x16 = lb con signo de 0xFD");
    expect_reg(17, 32'd253,      "x17 = lbu sin signo de 0xFD");
    expect_reg(18, 32'd1,        "x18 = addi 1");
    expect_reg(19, 32'd1024,     "x19 = sll 1<<10");
    expect_reg(20, 32'd0,        "x20 = NO debe tener el veneno (bne lo salteo)");
    expect_reg(21, 32'd10,       "x21 = andi");
    expect_reg(22, 32'd13,       "x22 = ori");

    // --- memoria: mem[0] tiene que ser el word que escribio sw x3 ---
    checks++;
    if ({dut.u_dmem.mem[3], dut.u_dmem.mem[2], dut.u_dmem.mem[1], dut.u_dmem.mem[0]} !== 32'd15) begin
      errors++;
      $error("mem[0] = %08h (esperado 15)",
             {dut.u_dmem.mem[3], dut.u_dmem.mem[2], dut.u_dmem.mem[1], dut.u_dmem.mem[0]});
    end

    // --- mem[4] tiene que ser el byte bajo de -3 (0xFD) que escribio sb ---
    checks++;
    if (dut.u_dmem.mem[4] !== 8'hFD) begin
      errors++;
      $error("mem[4] = %02h (esperado fd)", dut.u_dmem.mem[4]);
    end

    // --- PC final ---
    checks++;
    if (dut.pc !== 32'd100) begin
      errors++;
      $error("PC final = %0d (esperado 100)", dut.pc);
    end

    if (errors == 0)
      $display("DATAPATH_TB: %0d/%0d checks OK", checks, checks);
    else
      $display("DATAPATH_TB: %0d errores en %0d checks", errors, checks);

    $finish;
  end

endmodule