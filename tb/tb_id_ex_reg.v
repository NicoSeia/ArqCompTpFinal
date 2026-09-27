// -----------------------------------------------------------------------------
// tb_id_ex_reg.v
// Testbench dirigido para id_ex_reg. Usa un valor DISTINTO por campo
// (incluidos los 12 campos de control, antes empaquetados en ctrl_t) para
// detectar un campo conectado al puerto equivocado.
// -----------------------------------------------------------------------------
module tb_id_ex_reg;

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

  task automatic check_field(input [31:0] val, input [31:0] exp, input [255:0] name);
    begin
      checks = checks + 1;
      if (val !== exp) begin
        errors = errors + 1;
        $display("FAIL [%0s] got=%0d esperado=%0d", name, val, exp);
      end
    end
  endtask

  reg         rst, flush, stall;
  reg         d_valid;
  reg  [31:0] d_pc, d_pc_plus4, d_rs1_data, d_rs2_data, d_imm;
  reg  [4:0]  d_rs1, d_rs2, d_rd;
  reg  [2:0]  d_funct3;
  reg         d_reg_write, d_mem_read, d_mem_write, d_alu_src;
  reg         d_branch, d_jump, d_jalr, d_mem_unsigned;
  reg  [1:0]  d_wb_src, d_mem_size;
  reg  [3:0]  d_alu_op;
  reg  [2:0]  d_imm_src;

  wire        q_valid;
  wire [31:0] q_pc, q_pc_plus4, q_rs1_data, q_rs2_data, q_imm;
  wire [4:0]  q_rs1, q_rs2, q_rd;
  wire [2:0]  q_funct3;
  wire        q_reg_write, q_mem_read, q_mem_write, q_alu_src;
  wire        q_branch, q_jump, q_jalr, q_mem_unsigned;
  wire [1:0]  q_wb_src, q_mem_size;
  wire [3:0]  q_alu_op;
  wire [2:0]  q_imm_src;

  id_ex_reg dut (
      .clk(clk), .rst(rst), .flush(flush), .stall(stall),
      .d_valid(d_valid), .d_pc(d_pc), .d_pc_plus4(d_pc_plus4),
      .d_rs1_data(d_rs1_data), .d_rs2_data(d_rs2_data), .d_imm(d_imm),
      .d_rs1(d_rs1), .d_rs2(d_rs2), .d_rd(d_rd), .d_funct3(d_funct3),
      .d_reg_write(d_reg_write), .d_mem_read(d_mem_read), .d_mem_write(d_mem_write),
      .d_wb_src(d_wb_src), .d_alu_src(d_alu_src), .d_branch(d_branch),
      .d_jump(d_jump), .d_jalr(d_jalr), .d_mem_unsigned(d_mem_unsigned),
      .d_alu_op(d_alu_op), .d_mem_size(d_mem_size), .d_imm_src(d_imm_src),
      .q_valid(q_valid), .q_pc(q_pc), .q_pc_plus4(q_pc_plus4),
      .q_rs1_data(q_rs1_data), .q_rs2_data(q_rs2_data), .q_imm(q_imm),
      .q_rs1(q_rs1), .q_rs2(q_rs2), .q_rd(q_rd), .q_funct3(q_funct3),
      .q_reg_write(q_reg_write), .q_mem_read(q_mem_read), .q_mem_write(q_mem_write),
      .q_wb_src(q_wb_src), .q_alu_src(q_alu_src), .q_branch(q_branch),
      .q_jump(q_jump), .q_jalr(q_jalr), .q_mem_unsigned(q_mem_unsigned),
      .q_alu_op(q_alu_op), .q_mem_size(q_mem_size), .q_imm_src(q_imm_src)
  );

  initial begin
    rst = 1; flush = 0; stall = 0;
    d_valid = 1;
    d_pc = 32'hB000_0001; d_pc_plus4 = 32'hB000_0002;
    d_rs1_data = 32'hB000_0003; d_rs2_data = 32'hB000_0004; d_imm = 32'hB000_0005;
    d_rs1 = 5'd11; d_rs2 = 5'd22; d_rd = 5'd9; d_funct3 = 3'b101;
    d_reg_write = 1; d_mem_read = 0; d_mem_write = 1;
    d_wb_src = 2'd2; d_alu_src = 1; d_branch = 0;
    d_jump = 1; d_jalr = 0; d_mem_unsigned = 1;
    d_alu_op = 4'd7; d_mem_size = 2'd1; d_imm_src = 3'd4;

    @(posedge clk); #1;
    check_bit(q_valid, 1'b0, "reset limpia valid");
    check_word(q_pc, 32'd0, "reset limpia pc");

    rst = 0;
    @(posedge clk); #1;
    check_bit(q_valid, 1'b1, "avance normal - valid");
    check_word(q_pc, 32'hB000_0001, "pc");
    check_word(q_pc_plus4, 32'hB000_0002, "pc_plus4 (no cruzado con pc)");
    check_word(q_rs1_data, 32'hB000_0003, "rs1_data");
    check_word(q_rs2_data, 32'hB000_0004, "rs2_data (no cruzado con rs1_data)");
    check_word(q_imm, 32'hB000_0005, "imm");
    check_field(q_rs1, 5'd11, "rs1");
    check_field(q_rs2, 5'd22, "rs2 (no cruzado con rs1)");
    check_field(q_rd,  5'd9,  "rd (no cruzado con rs1/rs2)");
    check_field(q_funct3, 3'b101, "funct3");
    check_bit(q_reg_write, 1'b1, "reg_write");
    check_bit(q_mem_read, 1'b0, "mem_read (no cruzado con mem_write)");
    check_bit(q_mem_write, 1'b1, "mem_write");
    check_field(q_wb_src, 2'd2, "wb_src");
    check_bit(q_alu_src, 1'b1, "alu_src");
    check_bit(q_branch, 1'b0, "branch (no cruzado con jump)");
    check_bit(q_jump, 1'b1, "jump");
    check_bit(q_jalr, 1'b0, "jalr (no cruzado con jump)");
    check_bit(q_mem_unsigned, 1'b1, "mem_unsigned");
    check_field(q_alu_op, 4'd7, "alu_op");
    check_field(q_mem_size, 2'd1, "mem_size");
    check_field(q_imm_src, 3'd4, "imm_src");

    // stall: no debe cambiar aunque la entrada cambie
    stall = 1;
    d_rd = 5'd31;
    @(posedge clk); #1;
    check_field(q_rd, 5'd9, "stall congela rd");
    stall = 0;

    // flush: limpia todo a 0
    flush = 1;
    @(posedge clk); #1;
    check_bit(q_valid, 1'b0, "flush limpia valid");
    check_bit(q_reg_write, 1'b0, "flush limpia reg_write");
    flush = 0;

    if (errors == 0)
      $display("ID_EX_REG_TB: %0d/%0d checks OK", checks, checks);
    else
      $display("ID_EX_REG_TB: %0d errores en %0d checks", errors, checks);

    $finish;
  end

endmodule
