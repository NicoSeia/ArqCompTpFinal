`include "riscv_defs.vh"
// -----------------------------------------------------------------------------
// tb_pipeline_mem.v -- prueba el camino de memoria del pipeline con la dmem
// BRAM (lectura sincrona + store_align + load_extract):
//   - sb/sh/sw y lb/lbu/lh/lhu/lw alineados, con signo y sin signo
//   - stores/loads desalineados (se ignoran / devuelven 0)
//   - load-use (load seguido de instruccion que lo usa, incluido un store
//     cuyo dato viene de un load) y store seguido de load de la misma direccion
//   - FASE B: el mismo programa con `enable` aleatorio (pipeline pausado a
//     cada rato, como STEP) y el puerto de debug de dmem leyendo direcciones
//     al azar en cada ciclo. Tiene que dar EXACTAMENTE los mismos resultados:
//     prueba que la lectura de debug no pisa el dato de un load que esta en WB.
// -----------------------------------------------------------------------------
module tb_pipeline_mem;

  reg clk = 0;
  reg rst;
  reg enable;
  reg [`DMEM_ADDR_W-1:0] dmem_debug_addr;

  integer errors = 0;
  integer checks = 0;
  integer i, cyc;
  reg random_mode;

  wire [`XLEN-1:0]        regfile_debug_data;
  wire [7:0]              dmem_debug_data;
  wire                    halted;
  wire [`HALT_CODE_W-1:0] halt_code;
  wire [`IF_ID_W-1:0]     if_id_q_out;
  wire [`ID_EX_W-1:0]     id_ex_q_out;
  wire [`EX_MEM_W-1:0]    ex_mem_q_out;
  wire [`MEM_WB_W-1:0]    mem_wb_q_out;

  localparam PROG_LEN = 34;

  pipeline_top dut (
      .clk(clk), .rst(rst), .enable(enable),
      .program_len(PROG_LEN[`IMEM_ADDR_W-1:0]),
      .imem_we(1'b0), .imem_waddr({`IMEM_ADDR_W{1'b0}}), .imem_wdata(32'd0),
      .regfile_debug_addr({`REG_ADDR_W{1'b0}}), .regfile_debug_data(regfile_debug_data),
      .dmem_debug_addr(dmem_debug_addr), .dmem_debug_data(dmem_debug_data),
      .halted(halted), .halt_code(halt_code),
      .if_id_q_out(if_id_q_out), .id_ex_q_out(id_ex_q_out),
      .ex_mem_q_out(ex_mem_q_out), .mem_wb_q_out(mem_wb_q_out)
  );

  always #5 clk = ~clk;

  function [31:0] itype(input [11:0] imm, input [4:0] rs1, input [2:0] funct3, input [4:0] rd, input [6:0] opcode);
    itype = {imm, rs1, funct3, rd, opcode};
  endfunction
  function [31:0] rtype(input [6:0] funct7, input [4:0] rs2, input [4:0] rs1, input [2:0] funct3, input [4:0] rd, input [6:0] opcode);
    rtype = {funct7, rs2, rs1, funct3, rd, opcode};
  endfunction
  function [31:0] stype(input [11:0] imm, input [4:0] rs2, input [4:0] rs1, input [2:0] funct3, input [6:0] opcode);
    stype = {imm[11:5], rs2, rs1, funct3, imm[4:0], opcode};
  endfunction
  function [31:0] utype(input [19:0] imm20, input [4:0] rd, input [6:0] opcode);
    utype = {imm20, rd, opcode};
  endfunction

  reg [31:0] prog [0:PROG_LEN-1];

  task automatic expect_reg(input integer idx, input [31:0] exp, input [8*48-1:0] name);
    begin
      checks = checks + 1;
      if (dut.u_regfile.regs[idx] !== exp) begin
        errors = errors + 1;
        $display("ERROR: [%0s] x%0d=%08h (esperado %08h)", name, idx, dut.u_regfile.regs[idx], exp);
      end
    end
  endtask

  task automatic expect_word(input integer widx, input [31:0] exp, input [8*48-1:0] name);
    begin
      checks = checks + 1;
      if (dut.u_dmem.mem[widx] !== exp) begin
        errors = errors + 1;
        $display("ERROR: [%0s] mem[%0d]=%08h (esperado %08h)", name, widx, dut.u_dmem.mem[widx], exp);
      end
    end
  endtask

  task automatic check_all(input [8*8-1:0] fase);
    begin
      $display("-- chequeo %0s --", fase);
      expect_reg(1,  32'h12345678, "x1 lui+addi");
      expect_reg(2,  32'd64,       "x2 base");
      expect_reg(3,  32'h12345678, "x3 lw tras sw (dato propio)");
      expect_reg(4,  32'h12345678, "x4 load-use sobre lw");
      expect_reg(5,  32'h00000078, "x5 lb byte0 (positivo)");
      expect_reg(6,  32'h00000012, "x6 lb byte3 (positivo)");
      expect_reg(7,  32'hFFFFFFFF, "x7 addi -1");
      expect_reg(8,  32'h1234FF78, "x8 lw tras sb en byte1");
      expect_reg(9,  32'hFFFFFFFF, "x9 lb con signo (0xFF)");
      expect_reg(10, 32'h000000FF, "x10 lbu sin signo (0xFF)");
      expect_reg(11, 32'hFFFFFDEF, "x11 addi -529");
      expect_reg(12, 32'hFFFFFDEF, "x12 lh con signo");
      expect_reg(13, 32'h0000FDEF, "x13 lhu sin signo");
      expect_reg(14, 32'hFDEFFF78, "x14 lw tras sh en half alto");
      expect_reg(15, 32'hFFFFFF78, "x15 lh half bajo con signo");
      expect_reg(16, 32'h0000FF78, "x16 lhu half bajo");
      expect_reg(17, 32'hFDEFFF78, "x17 lw tras sw desalineado (ignorado)");
      expect_reg(18, 32'h00000000, "x18 lw desalineado -> 0");
      expect_reg(19, 32'h00000000, "x19 lh desalineado -> 0");
      expect_reg(20, 32'hFDEFFF78, "x20 lw tras sh desalineado (ignorado)");
      expect_reg(21, 32'hFDEFFF78, "x21 lw");
      expect_reg(22, 32'hFDEFFF78, "x22 lw de lo guardado (store con dato de load)");
      expect_reg(23, 32'h00000055, "x23 addi 85");
      expect_reg(24, 32'h00000055, "x24 lw justo tras sw (misma direccion)");
      expect_reg(25, 32'h00000055, "x25 lw");
      expect_reg(26, 32'h000000AA, "x26 add sobre load");
      expect_word(16, 32'hFDEFFF78, "mem[64..67]");
      expect_word(17, 32'hFDEFFF78, "mem[68..71]");
      expect_word(18, 32'h00000055, "mem[72..75]");
    end
  endtask

  task automatic reset_and_run;
    begin
      for (i = 0; i < (1 << (`DMEM_ADDR_W-2)); i = i + 1) dut.u_dmem.mem[i] = 32'd0;
      rst = 1; enable = 1; random_mode = 0;
      @(posedge clk); #1;
      rst = 0;
    end
  endtask

  // lectura de un byte por el puerto de debug (sincrono: 1 flanco de latencia)
  task automatic expect_debug_byte(input [`DMEM_ADDR_W-1:0] a, input [7:0] exp, input [8*32-1:0] name);
    begin
      dmem_debug_addr = a;
      @(posedge clk); #1;
      checks = checks + 1;
      if (dmem_debug_data !== exp) begin
        errors = errors + 1;
        $display("ERROR: [%0s] debug[%0d]=%02h (esperado %02h)", name, a, dmem_debug_data, exp);
      end
    end
  endtask

  // En FASE B: enable aleatorio (~65% de los ciclos) y direccion de debug aleatoria
  always @(negedge clk) begin
    if (random_mode) begin
      enable          = (($random & 7) < 5);
      dmem_debug_addr = $random;
    end
  end

  initial begin
    dmem_debug_addr = 0;
    rst = 1; enable = 1; random_mode = 0;

    prog[0]  = utype(20'h12345, 5'd1, `OP_LUI);                      // lui  x1,0x12345
    prog[1]  = itype(12'h678, 5'd1, 3'b000, 5'd1, `OP_IMM);          // addi x1,x1,0x678
    prog[2]  = itype(12'd64,  5'd0, 3'b000, 5'd2, `OP_IMM);          // addi x2,x0,64
    prog[3]  = stype(12'd0,   5'd1, 5'd2, 3'b010, `OP_STORE);        // sw   x1,0(x2)
    prog[4]  = itype(12'd0,   5'd2, 3'b010, 5'd3, `OP_LOAD);         // lw   x3,0(x2)
    prog[5]  = rtype(7'b0, 5'd0, 5'd3, 3'b000, 5'd4, `OP_R);         // add  x4,x3,x0   (load-use)
    prog[6]  = itype(12'd0,   5'd2, 3'b000, 5'd5, `OP_LOAD);         // lb   x5,0(x2)
    prog[7]  = itype(12'd3,   5'd2, 3'b000, 5'd6, `OP_LOAD);         // lb   x6,3(x2)
    prog[8]  = itype(12'hFFF, 5'd0, 3'b000, 5'd7, `OP_IMM);          // addi x7,x0,-1
    prog[9]  = stype(12'd1,   5'd7, 5'd2, 3'b000, `OP_STORE);        // sb   x7,1(x2)
    prog[10] = itype(12'd0,   5'd2, 3'b010, 5'd8, `OP_LOAD);         // lw   x8,0(x2)
    prog[11] = itype(12'd1,   5'd2, 3'b000, 5'd9, `OP_LOAD);         // lb   x9,1(x2)
    prog[12] = itype(12'd1,   5'd2, 3'b100, 5'd10, `OP_LOAD);        // lbu  x10,1(x2)
    prog[13] = itype(12'hDEF, 5'd0, 3'b000, 5'd11, `OP_IMM);         // addi x11,x0,-529
    prog[14] = stype(12'd2,   5'd11, 5'd2, 3'b001, `OP_STORE);       // sh   x11,2(x2)
    prog[15] = itype(12'd2,   5'd2, 3'b001, 5'd12, `OP_LOAD);        // lh   x12,2(x2)
    prog[16] = itype(12'd2,   5'd2, 3'b101, 5'd13, `OP_LOAD);        // lhu  x13,2(x2)
    prog[17] = itype(12'd0,   5'd2, 3'b010, 5'd14, `OP_LOAD);        // lw   x14,0(x2)
    prog[18] = itype(12'd0,   5'd2, 3'b001, 5'd15, `OP_LOAD);        // lh   x15,0(x2)
    prog[19] = itype(12'd0,   5'd2, 3'b101, 5'd16, `OP_LOAD);        // lhu  x16,0(x2)
    prog[20] = stype(12'd1,   5'd1, 5'd2, 3'b010, `OP_STORE);        // sw   x1,1(x2)   desalineado
    prog[21] = itype(12'd0,   5'd2, 3'b010, 5'd17, `OP_LOAD);        // lw   x17,0(x2)
    prog[22] = itype(12'd1,   5'd2, 3'b010, 5'd18, `OP_LOAD);        // lw   x18,1(x2)  desalineado
    prog[23] = stype(12'd1,   5'd1, 5'd2, 3'b001, `OP_STORE);        // sh   x1,1(x2)   desalineado
    prog[24] = itype(12'd1,   5'd2, 3'b001, 5'd19, `OP_LOAD);        // lh   x19,1(x2)  desalineado
    prog[25] = itype(12'd0,   5'd2, 3'b010, 5'd20, `OP_LOAD);        // lw   x20,0(x2)
    prog[26] = itype(12'd0,   5'd2, 3'b010, 5'd21, `OP_LOAD);        // lw   x21,0(x2)
    prog[27] = stype(12'd4,   5'd21, 5'd2, 3'b010, `OP_STORE);       // sw   x21,4(x2)  (dato viene de un load)
    prog[28] = itype(12'd4,   5'd2, 3'b010, 5'd22, `OP_LOAD);        // lw   x22,4(x2)
    prog[29] = itype(12'd85,  5'd0, 3'b000, 5'd23, `OP_IMM);         // addi x23,x0,85
    prog[30] = stype(12'd8,   5'd23, 5'd2, 3'b010, `OP_STORE);       // sw   x23,8(x2)
    prog[31] = itype(12'd8,   5'd2, 3'b010, 5'd24, `OP_LOAD);        // lw   x24,8(x2)  (justo tras el sw)
    prog[32] = itype(12'd8,   5'd2, 3'b010, 5'd25, `OP_LOAD);        // lw   x25,8(x2)
    prog[33] = rtype(7'b0, 5'd25, 5'd25, 3'b000, 5'd26, `OP_R);      // add  x26,x25,x25 (load-use)

    for (i = 0; i < PROG_LEN; i = i + 1) dut.u_imem.mem[i] = prog[i];

    // ============ FASE A: corrida libre (enable=1 todo el tiempo) ============
    reset_and_run;
    cyc = 0;
    while (!halted && cyc < 2000) begin @(posedge clk); cyc = cyc + 1; end
    #1;
    checks = checks + 1;
    if (!halted || halt_code !== `HALT_RANGE) begin
      errors = errors + 1;
      $display("ERROR: [fase A] no llego a halt por rango (halted=%b code=%0d)", halted, halt_code);
    end
    check_all("FASE A");

    // lectura de memoria por el puerto de debug (como DUMP_MEM)
    expect_debug_byte(12'd64, 8'h78, "debug mem[64]");
    expect_debug_byte(12'd65, 8'hFF, "debug mem[65]");
    expect_debug_byte(12'd66, 8'hEF, "debug mem[66]");
    expect_debug_byte(12'd67, 8'hFD, "debug mem[67]");
    expect_debug_byte(12'd72, 8'h55, "debug mem[72]");

    // ============ FASE B: enable aleatorio + debug aleatorio ============
    reset_and_run;
    random_mode = 1;
    cyc = 0;
    while (!halted && cyc < 6000) begin @(posedge clk); cyc = cyc + 1; end
    random_mode = 0; enable = 1;
    @(posedge clk); #1;
    checks = checks + 1;
    if (!halted || halt_code !== `HALT_RANGE) begin
      errors = errors + 1;
      $display("ERROR: [fase B] no llego a halt por rango (halted=%b code=%0d)", halted, halt_code);
    end
    check_all("FASE B");

    if (errors == 0)
      $display("PIPELINE_MEM_TB: %0d/%0d checks OK", checks, checks);
    else
      $display("PIPELINE_MEM_TB: %0d errores en %0d checks", errors, checks);
    $finish;
  end

endmodule